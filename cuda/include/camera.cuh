#ifndef CUDA_CAMERA_CUH
#define CUDA_CAMERA_CUH

#include "material.cuh"
#include "vec3.cuh"
#include "bvh.cuh"
#include "hittable.cuh"
#include "random.cuh"
#include "ray.cuh"
#include "pi.cuh"

#include <cuda_runtime.h>
#include <curand_kernel.h>

#include <chrono>
#include <cstdio>
#include <thread>
#include <vector>
#include <iostream>

static __host__ inline float clamp01(float x) {
    if (!isfinite(x)) return 0.0f;
    if (x < 0.0f) return 0.0f;
    if (x > 0.999f) return 0.999f;
    return x;
}

static __host__ inline void write_color_ppm(FILE* output, const Color& c) {
    float r = sqrtf(fmaxf(0.0f, c.x));
    float g = sqrtf(fmaxf(0.0f, c.y));
    float b = sqrtf(fmaxf(0.0f, c.z));

    int ir = static_cast<int>(256.0f * clamp01(r));
    int ig = static_cast<int>(256.0f * clamp01(g));
    int ib = static_cast<int>(256.0f * clamp01(b));
    fprintf(output, "%d %d %d\n", ir, ig, ib);
}

struct Camera;

__global__ void init_rand_kernel(curandState *rand_states, int tile_width, int tile_height,
                                 unsigned long long seed, int tile_origin_x, int tile_origin_y,
                                 int full_image_width);

__global__ void render_kernel(const Camera *camera, BVH *bvh, MaterialList *materials,
                              Color *framebuffer, curandState *rand_states,
                              int tile_width, int tile_height,
                              int tile_origin_x, int tile_origin_y,
                              int full_image_width,
                              unsigned long long *progress_counter);

struct Camera {
    float aspect_ratio;
    int image_width;
    int image_height;
    int samples_per_pixel;
    int max_depth;
    float vfov;
    Point3 lookfrom;
    Point3 lookat;
    Vec3 vup;
    float defocus_angle;
    float focus_dist;
    float pixel_sample_scale;
    Point3 center;
    Point3 pixel00_loc;
    Vec3 pixel_delta_u;
    Vec3 pixel_delta_v;
    Vec3 defocus_disk_u;
    Vec3 defocus_disk_v;
    Color background;
    bool use_bvh;
    unsigned long long rng_seed;

    __host__
            Camera(float aspect_ratio, int image_width, int image_height, int samples_per_pixel, int max_depth,
           float vfov, Point3 lookfrom, Point3 lookat, Vec3 vup, float defocus_angle, float focus_dist,
                Color background, bool use_bvh = true, unsigned long long rng_seed = 1337ULL)
        : aspect_ratio(aspect_ratio), image_width(image_width), image_height(image_height),
          samples_per_pixel(samples_per_pixel), max_depth(max_depth), vfov(vfov), lookfrom(lookfrom),
          lookat(lookat), vup(vup), defocus_angle(defocus_angle), focus_dist(focus_dist),
               background(background), use_bvh(use_bvh), rng_seed(rng_seed) {
                this->center = lookfrom;
                this->pixel_sample_scale = 1.0f / samples_per_pixel;

        float theta = vfov * M_PI / 180.0f;
        float h = tan(theta / 2);
                float viewport_height = 2.0f * h * focus_dist;
        float viewport_width = aspect_ratio * viewport_height;

        Vec3 w = (lookfrom - lookat).normalize();
        Vec3 u = vup.cross(w).normalize();
        Vec3 v = w.cross(u);

        Vec3 viewport_u = u * viewport_width;
        Vec3 viewport_v = v * (-viewport_height);

        Vec3 pixel_delta_u = viewport_u / image_width;
        Vec3 pixel_delta_v = viewport_v / image_height;

        Vec3 viewport_upper_left = this->center - w * focus_dist - viewport_u / 2 - viewport_v / 2;

        Vec3 pixel00_loc = viewport_upper_left + pixel_delta_u / 2 + pixel_delta_v / 2;

        float focus_radius = tanf((defocus_angle * M_PI / 180.0f) * 0.5f) * focus_dist;
        Vec3 defocus_disk_u = u * focus_radius;
        Vec3 defocus_disk_v = v * focus_radius;

        this->pixel00_loc = pixel00_loc;
        this->pixel_delta_u = pixel_delta_u;
        this->pixel_delta_v = pixel_delta_v;
        this->defocus_disk_u = defocus_disk_u;
        this->defocus_disk_v = defocus_disk_v;
    }

    __device__
    Vec3 sample_square(curandState *rand_state) const {
        return Vec3(random_float(rand_state) - 0.5f, random_float(rand_state) - 0.5f, 0);
    }

    __device__
    Vec3 sample_defocus_disk(curandState *rand_state) const {
        Vec3 p = random_in_unit_disk(rand_state);
        return center + defocus_disk_u * p.x + defocus_disk_v * p.y;
    }

    __device__
    Ray get_ray(int i, int j, curandState *rand_state) const {
        Vec3 offset = sample_square(rand_state);
        Vec3 pixel_sample = pixel00_loc + pixel_delta_u * (i + offset.x) + pixel_delta_v * (j + offset.y);
        Vec3 ray_origin = defocus_angle <= 0.0 ? center : sample_defocus_disk(rand_state);
        return Ray(ray_origin, pixel_sample - ray_origin, random_float(rand_state));
    }

    __device__
    bool hit_world_linear(const Ray& ray, HittableList *hittables, HitRecord& out_record, curandState* rand_state) const {
        bool any_hit = false;
        float closest = FLT_MAX;
        HitRecord temp;

        for (int i = 0; i < hittables->count; ++i) {
            if (hittables->hit(i, ray, Interval(0.001f, closest), temp, rand_state)) {
                any_hit = true;
                closest = temp.t;
                out_record = temp;
            }
        }

        return any_hit;
    }

    __device__
    Color ray_color(Ray& ray, BVH *bvh, MaterialList *materials, curandState *rand_state, int depth) const {
        Ray current_ray = ray;
        Color throughput(1.0f, 1.0f, 1.0f);
        Color radiance(0.0f, 0.0f, 0.0f);

        for (int bounce = depth; bounce < max_depth; ++bounce) {
            HitRecord rec;
            bool hit_any = use_bvh
                ? bvh->hit(current_ray, Interval(0.001f, FLT_MAX), rec, rand_state)
                : hit_world_linear(current_ray, bvh->hittables, rec, rand_state);

            if (!hit_any) {
                radiance += throughput.hadamard_product(background);
                return radiance;
            }

            Color emitted = materials->emitted(rec.materialId, rec.u, rec.v, rec.p);
            radiance += throughput.hadamard_product(emitted);

            Vec3 attenuation;
            Ray scattered;
            if (!materials->scatter(rec.materialId, current_ray, rec, rand_state, attenuation, scattered)) {
                return radiance;
            }

            throughput = throughput.hadamard_product(attenuation);
            if (!isfinite(throughput.x) || !isfinite(throughput.y) || !isfinite(throughput.z)) {
                return radiance;
            }

            current_ray = scattered;
        }

        return radiance;
    }

    __host__
    void render(FILE* output_path, BVH *bvh, MaterialList *materials) const {
        std::cerr << "use_bvh: " << (use_bvh ? "true" : "false") << std::endl;

        if (output_path == nullptr || bvh == nullptr || materials == nullptr) {
            std::cerr << "render precondition failed: null output/bvh/materials pointer" << std::endl;
            return;
        }

        fprintf(output_path, "P3\n%d %d\n255\n", image_width, image_height);

        constexpr int kMaxTileSize = 256;
        constexpr float kMinFreeRatio = 0.20f;
        constexpr int kProgressPollMs = 80;

        int total_pixels = image_width * image_height;
        if (total_pixels <= 0) {
            return;
        }

        Color *d_framebuffer = nullptr;
        curandState *d_rand_states = nullptr;
        unsigned long long *d_progress_counter = nullptr;
        Camera *d_camera = nullptr;
        cudaEvent_t render_done_event = nullptr;
        cudaStream_t render_stream = nullptr;
        cudaStream_t progress_stream = nullptr;
        size_t tile_capacity_pixels = 0;

        bool failed = false;
        auto check_cuda = [&](cudaError_t err, const char* op) -> bool {
            if (err == cudaSuccess) {
                return true;
            }
            std::cerr << "CUDA error in " << op << ": " << cudaGetErrorString(err) << std::endl;
            failed = true;
            return false;
        };

        auto pixel_device_bytes = [&]() -> size_t {
            return sizeof(Color) + sizeof(curandState);
        };

        auto required_free_after_alloc = [&](size_t free_mem, size_t total_mem) -> size_t {
            const size_t target_free_total = static_cast<size_t>(static_cast<double>(total_mem) * static_cast<double>(kMinFreeRatio));
            if (free_mem > target_free_total) {
                return target_free_total;
            }

            // If scene/static allocations already consumed >80% VRAM, keep 20% of current free memory.
            return static_cast<size_t>(static_cast<double>(free_mem) * static_cast<double>(kMinFreeRatio));
        };

        auto choose_tile_side_from_memory = [&](size_t free_mem, size_t required_free_bytes) -> int {
            const size_t reserve_bytes = required_free_bytes;
            size_t usable_bytes = 0;
            if (free_mem > reserve_bytes) {
                usable_bytes = free_mem - reserve_bytes;
            }

            size_t max_pixels = usable_bytes / pixel_device_bytes();
            if (max_pixels == 0) {
                return 1;
            }

            int side = static_cast<int>(sqrt(static_cast<double>(max_pixels)));
            if (side < 1) {
                side = 1;
            }
            if (side > kMaxTileSize) {
                side = kMaxTileSize;
            }
            if (side >= 16) {
                side = (side / 16) * 16;
            }
            return side > 0 ? side : 1;
        };

        auto release_tile_buffers = [&]() {
            if (d_rand_states != nullptr) {
                cudaFree(d_rand_states);
                d_rand_states = nullptr;
            }
            if (d_framebuffer != nullptr) {
                cudaFree(d_framebuffer);
                d_framebuffer = nullptr;
            }
            tile_capacity_pixels = 0;
        };

        auto ensure_tile_capacity = [&](int tile_side) {
            const size_t requested_pixels = static_cast<size_t>(tile_side) * static_cast<size_t>(tile_side);
            if (requested_pixels == tile_capacity_pixels) {
                return;
            }

            release_tile_buffers();

            check_cuda(cudaMalloc(&d_framebuffer, sizeof(Color) * requested_pixels), "cudaMalloc(d_framebuffer)");
            if (!failed) {
                check_cuda(cudaMalloc(&d_rand_states, sizeof(curandState) * requested_pixels), "cudaMalloc(d_rand_states)");
            }
            if (!failed) {
                tile_capacity_pixels = requested_pixels;
            }
        };

        if (!failed) {
            check_cuda(cudaMalloc(&d_progress_counter, sizeof(unsigned long long)), "cudaMalloc(d_progress_counter)");
        }
        if (!failed) {
            check_cuda(cudaMalloc(&d_camera, sizeof(Camera)), "cudaMalloc(d_camera)");
        }
        if (!failed) {
            check_cuda(cudaMemcpy(d_camera, this, sizeof(Camera), cudaMemcpyHostToDevice), "cudaMemcpy(d_camera)");
        }
        if (!failed) {
            check_cuda(cudaEventCreate(&render_done_event), "cudaEventCreate(render_done_event)");
        }
        if (!failed) {
            check_cuda(cudaStreamCreateWithFlags(&render_stream, cudaStreamNonBlocking), "cudaStreamCreateWithFlags(render_stream)");
        }
        if (!failed) {
            check_cuda(cudaStreamCreateWithFlags(&progress_stream, cudaStreamNonBlocking), "cudaStreamCreateWithFlags(progress_stream)");
        }

        unsigned long long seed = rng_seed == 0ULL
            ? static_cast<unsigned long long>(std::chrono::high_resolution_clock::now().time_since_epoch().count())
            : rng_seed;

        const int bar_width = 40;
        const auto render_start_time = std::chrono::steady_clock::now();

        if (!failed) {
            std::vector<Color> host_framebuffer(total_pixels);
            std::vector<Color> host_tile;

            int rendered_pixels = 0;
            dim3 block_dim(16, 16);
            int tile_origin_y = 0;
            bool low_mem_warning_printed = false;
            bool vram_telemetry_unreliable = false;
            int suspicious_mem_samples = 0;

            auto query_mem_info = [&](size_t &free_mem, size_t &total_mem, const char* op) -> bool {
                check_cuda(cudaMemGetInfo(&free_mem, &total_mem), op);
                if (failed) {
                    return false;
                }

                bool suspicious = (total_mem > 0 && free_mem == 0) || (free_mem > total_mem);
                if (suspicious) {
                    ++suspicious_mem_samples;
                } else {
                    suspicious_mem_samples = 0;
                }

                if (!vram_telemetry_unreliable && suspicious_mem_samples >= 2) {
                    vram_telemetry_unreliable = true;
                    std::cerr << "warning: cudaMemGetInfo telemetry looks unreliable;"
                              << " switching tile sizing to fixed fallback" << std::endl;
                }
                return true;
            };

            while (tile_origin_y < image_height && !failed) {
                int row_tile_step = 1;
                int tile_origin_x = 0;
                while (tile_origin_x < image_width && !failed) {
                    size_t free_mem = 0;
                    size_t total_mem = 0;
                    if (!query_mem_info(free_mem, total_mem, "cudaMemGetInfo(pre-tile)")) {
                        break;
                    }

                    size_t min_free_after_alloc = vram_telemetry_unreliable ? 0 : required_free_after_alloc(free_mem, total_mem);
                    int dynamic_tile_side = vram_telemetry_unreliable
                        ? kMaxTileSize
                        : choose_tile_side_from_memory(free_mem, min_free_after_alloc);
                    int remain_width = image_width - tile_origin_x;
                    int remain_height = image_height - tile_origin_y;
                    int tile_width = dynamic_tile_side < remain_width ? dynamic_tile_side : remain_width;
                    int tile_height = dynamic_tile_side < remain_height ? dynamic_tile_side : remain_height;

                    if (tile_width < 1) {
                        tile_width = 1;
                    }
                    if (tile_height < 1) {
                        tile_height = 1;
                    }

                    if (tile_height > row_tile_step) {
                        row_tile_step = tile_height;
                    }

                    int committed_side = tile_width > tile_height ? tile_width : tile_height;
                    while (!failed) {
                        ensure_tile_capacity(committed_side);
                        if (failed) {
                            break;
                        }

                        size_t post_alloc_free = 0;
                        size_t post_alloc_total = 0;
                        if (!query_mem_info(post_alloc_free, post_alloc_total, "cudaMemGetInfo(post-alloc)")) {
                            break;
                        }

                        if (vram_telemetry_unreliable) {
                            break;
                        }

                        float post_alloc_free_ratio = post_alloc_total == 0
                            ? 0.0f
                            : static_cast<float>(post_alloc_free) / static_cast<float>(post_alloc_total);
                        size_t post_alloc_required_free = min_free_after_alloc;

                        if (post_alloc_free >= post_alloc_required_free) {
                            break;
                        }

                        if (!low_mem_warning_printed) {
                            std::cerr << "warning: reducing tile size to keep VRAM headroom target"
                                      << " (required_free=" << (post_alloc_required_free / (1024.0 * 1024.0)) << " MiB"
                                      << ", current_free_ratio=" << (post_alloc_free_ratio * 100.0f) << "%)"
                                      << std::endl;
                            low_mem_warning_printed = true;
                        }

                        if (committed_side <= 1) {
                            failed = true;
                            std::cerr << "CUDA error in tile sizing: unable to maintain VRAM headroom target" << std::endl;
                            break;
                        }

                        committed_side /= 2;
                        if (committed_side < 1) {
                            committed_side = 1;
                        }

                        if (tile_width > committed_side) {
                            tile_width = committed_side;
                        }
                        if (tile_height > committed_side) {
                            tile_height = committed_side;
                        }
                    }

                    if (failed) {
                        break;
                    }

                    int tile_pixels = tile_width * tile_height;
                    if (host_tile.size() < static_cast<size_t>(tile_pixels)) {
                        host_tile.resize(static_cast<size_t>(tile_pixels));
                    }

                    size_t launch_free_mem = 0;
                    size_t launch_total_mem = 0;
                    if (!query_mem_info(launch_free_mem, launch_total_mem, "cudaMemGetInfo(tile-start)")) {
                        break;
                    }
                    (void)launch_free_mem;
                    (void)launch_total_mem;

                    dim3 grid_dim((tile_width + block_dim.x - 1) / block_dim.x,
                                  (tile_height + block_dim.y - 1) / block_dim.y);

                    check_cuda(cudaMemsetAsync(d_progress_counter, 0, sizeof(unsigned long long), render_stream),
                               "cudaMemsetAsync(d_progress_counter)");
                    if (failed) {
                        break;
                    }

                    init_rand_kernel<<<grid_dim, block_dim, 0, render_stream>>>(
                        d_rand_states,
                        tile_width,
                        tile_height,
                        seed,
                        tile_origin_x,
                        tile_origin_y,
                        image_width
                    );
                    check_cuda(cudaGetLastError(), "init_rand_kernel launch");
                    if (failed) {
                        break;
                    }

                    render_kernel<<<grid_dim, block_dim, 0, render_stream>>>(
                        d_camera,
                        bvh,
                        materials,
                        d_framebuffer,
                        d_rand_states,
                        tile_width,
                        tile_height,
                        tile_origin_x,
                        tile_origin_y,
                        image_width,
                        d_progress_counter
                    );
                    check_cuda(cudaGetLastError(), "render_kernel launch");
                    if (failed) {
                        break;
                    }

                    check_cuda(cudaEventRecord(render_done_event, render_stream), "cudaEventRecord(render_done_event)");
                    if (failed) {
                        break;
                    }

                    unsigned long long tile_progress = 0;
                    while (!failed) {
                        cudaError_t query_status = cudaEventQuery(render_done_event);
                        if (query_status == cudaSuccess) {
                            break;
                        }
                        if (query_status != cudaErrorNotReady) {
                            check_cuda(query_status, "cudaEventQuery(render_done_event)");
                            break;
                        }

                        check_cuda(cudaMemcpyAsync(&tile_progress, d_progress_counter, sizeof(unsigned long long),
                                                   cudaMemcpyDeviceToHost, progress_stream),
                                   "cudaMemcpyAsync(tile progress)");
                        if (!failed) {
                            check_cuda(cudaStreamSynchronize(progress_stream), "cudaStreamSynchronize(progress_stream)");
                        }
                        if (failed) {
                            break;
                        }

                        if (tile_progress > static_cast<unsigned long long>(tile_pixels)) {
                            tile_progress = static_cast<unsigned long long>(tile_pixels);
                        }

                        size_t monitor_free_mem = 0;
                        size_t monitor_total_mem = 0;
                        if (!query_mem_info(monitor_free_mem, monitor_total_mem, "cudaMemGetInfo(progress)")) {
                            break;
                        }

                        int live_pixels = rendered_pixels + static_cast<int>(tile_progress);
                        float ratio = static_cast<float>(live_pixels) / static_cast<float>(total_pixels);
                        int filled = static_cast<int>(ratio * bar_width);
                        float free_ratio = monitor_total_mem == 0
                            ? 0.0f
                            : static_cast<float>(monitor_free_mem) / static_cast<float>(monitor_total_mem);
                        float used_ratio = 1.0f - free_ratio;
                        const auto now = std::chrono::steady_clock::now();
                        double elapsed_sec = std::chrono::duration<double>(now - render_start_time).count();

                        if (vram_telemetry_unreliable) {
                            fprintf(stderr, "\r[t=%7.2fs vram= n/a ] [", elapsed_sec);
                        } else {
                            fprintf(stderr, "\r[t=%7.2fs vram=%5.1f%%] [", elapsed_sec, used_ratio * 100.0f);
                        }
                        for (int k = 0; k < bar_width; ++k) {
                            fputc(k < filled ? '=' : ' ', stderr);
                        }
                        fprintf(stderr, "] %6.2f%% (%d/%d) tile=%dx%d free=%5.1f%%",
                                ratio * 100.0f, live_pixels, total_pixels, tile_width, tile_height, free_ratio * 100.0f);
                        fflush(stderr);

                        std::this_thread::sleep_for(std::chrono::milliseconds(kProgressPollMs));
                    }

                    if (!failed) {
                        check_cuda(cudaEventSynchronize(render_done_event), "cudaEventSynchronize(render_done_event)");
                    }
                    if (failed) {
                        break;
                    }

                    check_cuda(cudaMemcpy(host_tile.data(), d_framebuffer, sizeof(Color) * tile_pixels, cudaMemcpyDeviceToHost),
                               "cudaMemcpy(tile framebuffer D2H)");
                    if (failed) {
                        break;
                    }

                    for (int local_y = 0; local_y < tile_height; ++local_y) {
                        int global_y = tile_origin_y + local_y;
                        int global_row_offset = global_y * image_width;
                        int local_row_offset = local_y * tile_width;
                        for (int local_x = 0; local_x < tile_width; ++local_x) {
                            int global_x = tile_origin_x + local_x;
                            host_framebuffer[global_row_offset + global_x] = host_tile[local_row_offset + local_x];
                        }
                    }

                    rendered_pixels += tile_pixels;
                    float ratio = static_cast<float>(rendered_pixels) / static_cast<float>(total_pixels);
                    int filled = static_cast<int>(ratio * bar_width);
                    size_t final_free_mem = 0;
                    size_t final_total_mem = 0;
                    if (!query_mem_info(final_free_mem, final_total_mem, "cudaMemGetInfo(progress-finalize)")) {
                        break;
                    }
                    float final_free_ratio = final_total_mem == 0
                        ? 0.0f
                        : static_cast<float>(final_free_mem) / static_cast<float>(final_total_mem);
                    float final_used_ratio = 1.0f - final_free_ratio;
                    const auto now = std::chrono::steady_clock::now();
                    double elapsed_sec = std::chrono::duration<double>(now - render_start_time).count();

                    if (vram_telemetry_unreliable) {
                        fprintf(stderr, "\r[t=%7.2fs vram= n/a ] [", elapsed_sec);
                    } else {
                        fprintf(stderr, "\r[t=%7.2fs vram=%5.1f%%] [", elapsed_sec, final_used_ratio * 100.0f);
                    }
                    for (int k = 0; k < bar_width; ++k) {
                        fputc(k < filled ? '=' : ' ', stderr);
                    }
                    fprintf(stderr, "] %6.2f%% (%d/%d)", ratio * 100.0f, rendered_pixels, total_pixels);
                    fflush(stderr);

                    tile_origin_x += tile_width;
                }

                tile_origin_y += row_tile_step;
            }

            if (!failed) {
                fprintf(stderr, "\n");
                for (int j = 0; j < image_height; ++j) {
                    for (int i = 0; i < image_width; ++i) {
                        int idx = j * image_width + i;
                        write_color_ppm(output_path, host_framebuffer[idx]);
                    }
                }
            }
        }

        if (progress_stream != nullptr) {
            cudaStreamDestroy(progress_stream);
        }
        if (render_stream != nullptr) {
            cudaStreamDestroy(render_stream);
        }
        if (render_done_event != nullptr) {
            cudaEventDestroy(render_done_event);
        }
        if (d_progress_counter != nullptr) {
            cudaFree(d_progress_counter);
        }

        if (d_camera != nullptr) {
            cudaFree(d_camera);
        }
        if (d_rand_states != nullptr) {
            cudaFree(d_rand_states);
        }
        if (d_framebuffer != nullptr) {
            cudaFree(d_framebuffer);
        }

        if (failed) {
            std::cerr << "render aborted due to CUDA failure" << std::endl;
        }
    }
};

__global__ void init_rand_kernel(curandState *rand_states, int tile_width, int tile_height,
                                 unsigned long long seed, int tile_origin_x, int tile_origin_y,
                                 int full_image_width) {
    int local_x = blockIdx.x * blockDim.x + threadIdx.x;
    int local_y = blockIdx.y * blockDim.y + threadIdx.y;
    if (local_x >= tile_width || local_y >= tile_height) {
        return;
    }

    int local_idx = local_y * tile_width + local_x;
    int global_x = tile_origin_x + local_x;
    int global_y = tile_origin_y + local_y;
    unsigned long long global_idx = static_cast<unsigned long long>(global_y) *
                                    static_cast<unsigned long long>(full_image_width) +
                                    static_cast<unsigned long long>(global_x);
    curand_init(seed, global_idx, 0, &rand_states[local_idx]);
}

__global__ void render_kernel(const Camera *camera, BVH *bvh, MaterialList *materials,
                              Color *framebuffer, curandState *rand_states,
                              int tile_width, int tile_height,
                              int tile_origin_x, int tile_origin_y,
                              int full_image_width,
                              unsigned long long *progress_counter) {
    int local_x = blockIdx.x * blockDim.x + threadIdx.x;
    int local_y = blockIdx.y * blockDim.y + threadIdx.y;
    if (local_x >= tile_width || local_y >= tile_height) {
        return;
    }

    int local_idx = local_y * tile_width + local_x;
    int global_x = tile_origin_x + local_x;
    int global_y = tile_origin_y + local_y;
    curandState local_state = rand_states[local_idx];

    Color pixel_color(0, 0, 0);
    for (int s = 0; s < camera->samples_per_pixel; ++s) {
        Ray ray = camera->get_ray(global_x, global_y, &local_state);
        pixel_color += camera->ray_color(ray, bvh, materials, &local_state, 0);
    }
    pixel_color *= camera->pixel_sample_scale;

    framebuffer[local_idx] = pixel_color;
    rand_states[local_idx] = local_state;
    (void)full_image_width;
    atomicAdd(progress_counter, 1ULL);
}

#endif // CUDA_CAMERA_CUH
