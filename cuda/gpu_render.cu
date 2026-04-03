#include "include/parser.cuh"
#include "include/camera.cuh"
#include "include/texture.cuh"
#include "include/material.cuh"
#include "include/hittable.cuh"
#include "include/bvh.cuh"

#include <cuda_runtime.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#define CUDA_CHECK(call) \
    do { \
        cudaError_t err__ = (call); \
        if (err__ != cudaSuccess) { \
            std::cerr << "CUDA error at " << __FILE__ << ":" << __LINE__ \
                      << " -> " << cudaGetErrorString(err__) << std::endl; \
            std::exit(1); \
        } \
    } while (0)

struct CameraConfig {
    float aspect_ratio = 16.0f / 9.0f;
    int image_width = 400;
    int samples_per_pixel = 50;
    int max_depth = 20;
    float vfov = 20.0f;
    Point3 lookfrom = Point3(13.0f, 2.0f, 3.0f);
    Point3 lookat = Point3(0.0f, 0.0f, 0.0f);
    Vec3 vup = Vec3(0.0f, 1.0f, 0.0f);
    float defocus_angle = 0.6f;
    float focus_dist = 10.0f;
    Color background = Color(0.70f, 0.80f, 1.00f);
    bool use_bvh = true;
    unsigned long long rng_seed = 1337ULL;
};

static inline bool parse_bool_value(const std::string& value, const std::string& key) {
    if (value == "1" || value == "true" || value == "TRUE" || value == "yes" || value == "on") {
        return true;
    }
    if (value == "0" || value == "false" || value == "FALSE" || value == "no" || value == "off") {
        return false;
    }
    throw std::runtime_error("invalid bool value for key: " + key + ", got: " + value);
}

static inline std::string trim_copy_local(const std::string& in) {
    size_t begin = 0;
    while (begin < in.size() && std::isspace(static_cast<unsigned char>(in[begin]))) {
        ++begin;
    }
    size_t end = in.size();
    while (end > begin && std::isspace(static_cast<unsigned char>(in[end - 1]))) {
        --end;
    }
    return in.substr(begin, end - begin);
}

static inline Vec3 parse_vec3(const std::string& text, const std::string& key) {
    std::istringstream iss(text);
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    if (!(iss >> x >> y >> z)) {
        throw std::runtime_error("invalid vec3 value for key: " + key);
    }
    return Vec3(x, y, z);
}

static CameraConfig load_camera_config(const std::string& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
        throw std::runtime_error("failed to open camera config: " + path);
    }

    CameraConfig cfg;
    std::string line;
    while (std::getline(file, line)) {
        line = trim_copy_local(line);
        if (line.empty() || line[0] == '#') {
            continue;
        }

        const size_t eq = line.find('=');
        if (eq == std::string::npos) {
            throw std::runtime_error("invalid config line (missing '='): " + line);
        }

        const std::string key = trim_copy_local(line.substr(0, eq));
        const std::string value = trim_copy_local(line.substr(eq + 1));

        if (key == "aspect_ratio") {
            cfg.aspect_ratio = std::stof(value);
        } else if (key == "image_width") {
            cfg.image_width = std::stoi(value);
        } else if (key == "samples_per_pixel") {
            cfg.samples_per_pixel = std::stoi(value);
        } else if (key == "max_depth") {
            cfg.max_depth = std::stoi(value);
        } else if (key == "vfov") {
            cfg.vfov = std::stof(value);
        } else if (key == "lookfrom") {
            cfg.lookfrom = parse_vec3(value, key);
        } else if (key == "lookat") {
            cfg.lookat = parse_vec3(value, key);
        } else if (key == "vup") {
            cfg.vup = parse_vec3(value, key);
        } else if (key == "defocus_angle") {
            cfg.defocus_angle = std::stof(value);
        } else if (key == "focus_dist") {
            cfg.focus_dist = std::stof(value);
        } else if (key == "background") {
            cfg.background = parse_vec3(value, key);
        } else if (key == "use_bvh") {
            cfg.use_bvh = parse_bool_value(value, key);
        } else if (key == "rng_seed") {
            cfg.rng_seed = static_cast<unsigned long long>(std::stoull(value));
        } else {
            throw std::runtime_error("unknown config key: " + key);
        }
    }

    if (cfg.aspect_ratio <= 0.0f || cfg.image_width <= 0 || cfg.samples_per_pixel <= 0 || cfg.max_depth <= 0) {
        throw std::runtime_error("invalid camera config values");
    }

    return cfg;
}

static inline bool finite_vec3(const Vec3& v) {
    return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z);
}

static void validate_ir_for_cuda(const ParsedIR& ir) {
    const int tex_count = static_cast<int>(ir.textures.size());
    const int mat_count = static_cast<int>(ir.materials.size());
    const int hit_count = static_cast<int>(ir.hittables.size());
    const int bvh_count = static_cast<int>(ir.bvh.size());
    const int res_count = static_cast<int>(ir.resources.size());

    auto fail = [](const std::string& msg) -> void {
        throw std::runtime_error("invalid IR: " + msg);
    };

    if (tex_count <= 0 || mat_count <= 0 || hit_count <= 0 || bvh_count <= 0) {
        fail("critical sections must be non-empty");
    }

    for (int i = 0; i < tex_count; ++i) {
        const ParsedTextureRow& row = ir.textures[i];
        if (row.type < SolidColor || row.type > Perlin) {
            fail("texture[" + std::to_string(i) + "] has unknown type " + std::to_string(row.type));
        }
        if (!finite_vec3(row.c1) || !finite_vec3(row.c2) || !finite_vec3(row.c3)) {
            fail("texture[" + std::to_string(i) + "] contains non-finite color data");
        }
        if (row.type == Image) {
            if (row.resourceId < 0 || row.resourceId >= res_count) {
                fail("texture[" + std::to_string(i) + "] image resource id out of range");
            }
        } else if (row.resourceId != 0) {
            fail("texture[" + std::to_string(i) + "] non-image texture has non-zero resource id");
        }
    }

    for (int i = 0; i < res_count; ++i) {
        const ParsedResourceRow& row = ir.resources[i];
        if (row.type != 1) {
            fail("resource[" + std::to_string(i) + "] has unsupported type " + std::to_string(row.type));
        }
        if (row.width < 0 || row.height < 0) {
            fail("resource[" + std::to_string(i) + "] has negative width/height");
        }
        const size_t expected = static_cast<size_t>(row.width) * static_cast<size_t>(row.height);
        if (row.pixels.size() != expected) {
            fail("resource[" + std::to_string(i) + "] pixel count mismatch");
        }
        for (size_t p = 0; p < row.pixels.size(); ++p) {
            if (!finite_vec3(row.pixels[p])) {
                fail("resource[" + std::to_string(i) + "] contains non-finite pixel data");
            }
        }
    }

    for (int i = 0; i < mat_count; ++i) {
        const ParsedMaterialRow& row = ir.materials[i];
        if (row.type < Lambertian || row.type > Isotropic) {
            fail("material[" + std::to_string(i) + "] has unknown type " + std::to_string(row.type));
        }
        if (row.textureId < 0 || row.textureId >= tex_count) {
            fail("material[" + std::to_string(i) + "] texture id out of range");
        }
        if (!finite_vec3(row.color) || !std::isfinite(row.p1) || !std::isfinite(row.p2)) {
            fail("material[" + std::to_string(i) + "] contains non-finite parameters");
        }
    }

    for (int i = 0; i < hit_count; ++i) {
        const ParsedHittableRow& row = ir.hittables[i];
        if (row.type < Sphere || row.type > ConstantMediumSphere) {
            fail("hittable[" + std::to_string(i) + "] has unknown type " + std::to_string(row.type));
        }
        if (row.materialId < 0 || row.materialId >= mat_count) {
            fail("hittable[" + std::to_string(i) + "] material id out of range");
        }
        if (row.textureId < 0 || row.textureId >= tex_count) {
            fail("hittable[" + std::to_string(i) + "] texture id out of range");
        }
        if (!finite_vec3(row.p) || !finite_vec3(row.u) || !finite_vec3(row.v) ||
            !finite_vec3(row.moving) || !finite_vec3(row.aux1) || !finite_vec3(row.aux2) ||
            !std::isfinite(row.radius)) {
            fail("hittable[" + std::to_string(i) + "] contains non-finite geometry");
        }
        if ((row.type == Sphere || row.type == ConstantMediumSphere) && row.radius <= 0.0f) {
            fail("hittable[" + std::to_string(i) + "] sphere/medium radius must be > 0");
        }
    }

    std::vector<int> parent_count(bvh_count, 0);
    int leaf_count = 0;
    for (int i = 0; i < bvh_count; ++i) {
        const ParsedBvhRow& row = ir.bvh[i];
        if (!std::isfinite(row.bbox.x.min) || !std::isfinite(row.bbox.x.max) ||
            !std::isfinite(row.bbox.y.min) || !std::isfinite(row.bbox.y.max) ||
            !std::isfinite(row.bbox.z.min) || !std::isfinite(row.bbox.z.max)) {
            fail("bvh[" + std::to_string(i) + "] has non-finite bbox");
        }
        if (row.bbox.x.min > row.bbox.x.max || row.bbox.y.min > row.bbox.y.max || row.bbox.z.min > row.bbox.z.max) {
            fail("bvh[" + std::to_string(i) + "] has invalid bbox interval");
        }

        if (row.hittableIndex >= 0) {
            ++leaf_count;
            if (row.hittableIndex >= hit_count) {
                fail("bvh[" + std::to_string(i) + "] hittable index out of range");
            }
            if (row.left != -1 || row.right != -1) {
                fail("bvh[" + std::to_string(i) + "] leaf must not have children");
            }
            continue;
        }

        if (row.left < 0 || row.left >= bvh_count || row.right < 0 || row.right >= bvh_count) {
            fail("bvh[" + std::to_string(i) + "] internal node has invalid children");
        }
        if (row.left == i || row.right == i || row.left == row.right) {
            fail("bvh[" + std::to_string(i) + "] internal node has self/duplicate child");
        }

        ++parent_count[row.left];
        ++parent_count[row.right];
    }

    if (leaf_count != hit_count) {
        fail("leaf count does not match hittable count");
    }

    if (parent_count[0] != 0) {
        fail("bvh root node index 0 must have no parent");
    }
    for (int i = 1; i < bvh_count; ++i) {
        if (parent_count[i] != 1) {
            fail("bvh node[" + std::to_string(i) + "] must have exactly one parent");
        }
    }

    std::vector<uint8_t> visited(static_cast<size_t>(bvh_count), 0);
    std::vector<int> stack;
    stack.reserve(static_cast<size_t>(bvh_count));
    stack.push_back(0);

    while (!stack.empty()) {
        const int idx = stack.back();
        stack.pop_back();
        if (idx < 0 || idx >= bvh_count) {
            fail("bvh traversal found out-of-range node index");
        }
        if (visited[static_cast<size_t>(idx)] != 0) {
            continue;
        }
        visited[static_cast<size_t>(idx)] = 1;

        const ParsedBvhRow& row = ir.bvh[idx];
        if (row.hittableIndex < 0) {
            stack.push_back(row.left);
            stack.push_back(row.right);
        }
    }

    for (int i = 0; i < bvh_count; ++i) {
        if (visited[static_cast<size_t>(i)] == 0) {
            fail("bvh node[" + std::to_string(i) + "] is unreachable from root");
        }
    }
}

struct DeviceScene {
    TextureList* d_textures = nullptr;
    MaterialList* d_materials = nullptr;
    HittableList* d_hittables = nullptr;
    BVH* d_bvh = nullptr;

    Vec3* d_tex_color1 = nullptr;
    Vec3* d_tex_color2 = nullptr;
    Vec3* d_tex_color3 = nullptr;
    float* d_tex_checker_inv_scale = nullptr;
    int* d_tex_resource_id = nullptr;
    int* d_res_width = nullptr;
    int* d_res_height = nullptr;
    int* d_res_offset = nullptr;
    Vec3* d_res_pixels = nullptr;
    TextureType* d_tex_type = nullptr;

    int* d_mat_texture_id = nullptr;
    Vec3* d_mat_albedo = nullptr;
    float* d_mat_c1 = nullptr;
    float* d_mat_c2 = nullptr;
    MaterialType* d_mat_type = nullptr;

    Vec3* d_hit_point = nullptr;
    Vec3* d_hit_u = nullptr;
    Vec3* d_hit_v = nullptr;
    Vec3* d_hit_moving = nullptr;
    Vec3* d_hit_aux1 = nullptr;
    Vec3* d_hit_aux2 = nullptr;
    float* d_hit_radius = nullptr;
    int* d_hit_material_id = nullptr;
    int* d_hit_texture_id = nullptr;
    HittableType* d_hit_type = nullptr;

    int* d_bvh_left = nullptr;
    int* d_bvh_right = nullptr;
    AABB* d_bvh_bbox = nullptr;
    int* d_bvh_hittable_index = nullptr;
    bool* d_bvh_is_leaf = nullptr;
};

static void free_device_scene(DeviceScene& ds) {
    cudaFree(ds.d_bvh);
    cudaFree(ds.d_bvh_left);
    cudaFree(ds.d_bvh_right);
    cudaFree(ds.d_bvh_bbox);
    cudaFree(ds.d_bvh_hittable_index);
    cudaFree(ds.d_bvh_is_leaf);

    cudaFree(ds.d_hittables);
    cudaFree(ds.d_hit_point);
    cudaFree(ds.d_hit_u);
    cudaFree(ds.d_hit_v);
    cudaFree(ds.d_hit_moving);
    cudaFree(ds.d_hit_aux1);
    cudaFree(ds.d_hit_aux2);
    cudaFree(ds.d_hit_radius);
    cudaFree(ds.d_hit_material_id);
    cudaFree(ds.d_hit_texture_id);
    cudaFree(ds.d_hit_type);

    cudaFree(ds.d_materials);
    cudaFree(ds.d_mat_texture_id);
    cudaFree(ds.d_mat_albedo);
    cudaFree(ds.d_mat_c1);
    cudaFree(ds.d_mat_c2);
    cudaFree(ds.d_mat_type);

    cudaFree(ds.d_textures);
    cudaFree(ds.d_tex_color1);
    cudaFree(ds.d_tex_color2);
    cudaFree(ds.d_tex_color3);
    cudaFree(ds.d_tex_checker_inv_scale);
    cudaFree(ds.d_tex_resource_id);
    cudaFree(ds.d_tex_type);
    cudaFree(ds.d_res_width);
    cudaFree(ds.d_res_height);
    cudaFree(ds.d_res_offset);
    cudaFree(ds.d_res_pixels);
}

static DeviceScene build_device_scene(const ParsedIR& ir) {
    DeviceScene ds;

    validate_ir_for_cuda(ir);

    const int tex_count = static_cast<int>(ir.textures.size());
    const int mat_count = static_cast<int>(ir.materials.size());
    const int hit_count = static_cast<int>(ir.hittables.size());
    const int bvh_count = static_cast<int>(ir.bvh.size());
    const int res_count = static_cast<int>(ir.resources.size());

    std::vector<Vec3> h_tex_color1(tex_count), h_tex_color2(tex_count), h_tex_color3(tex_count);
    std::vector<float> h_tex_checker_inv_scale(tex_count, 0.0f);
    std::vector<int> h_tex_resource_id(tex_count);
    std::vector<TextureType> h_tex_type(tex_count);
    std::vector<int> h_res_width(res_count, 0), h_res_height(res_count, 0), h_res_offset(res_count, 0);
    size_t total_res_pixels = 0;
    for (int i = 0; i < res_count; ++i) {
        h_res_width[i] = ir.resources[i].width;
        h_res_height[i] = ir.resources[i].height;
        h_res_offset[i] = static_cast<int>(total_res_pixels);
        total_res_pixels += ir.resources[i].pixels.size();
    }
    std::vector<Vec3> h_res_pixels(total_res_pixels);
    for (int i = 0; i < res_count; ++i) {
        const int offset = h_res_offset[i];
        const auto& src = ir.resources[i].pixels;
        for (size_t j = 0; j < src.size(); ++j) {
            h_res_pixels[static_cast<size_t>(offset) + j] = src[j];
        }
    }

    for (int i = 0; i < tex_count; ++i) {
        h_tex_color1[i] = ir.textures[i].c1;
        h_tex_color2[i] = ir.textures[i].c2;
        h_tex_color3[i] = ir.textures[i].c3;
        h_tex_resource_id[i] = ir.textures[i].resourceId;
        h_tex_type[i] = static_cast<TextureType>(ir.textures[i].type);

        if (h_tex_type[i] == Checker) {
            // New IR stores checker inv_scale in c3.x; old IR keeps c3.x=0.
            h_tex_checker_inv_scale[i] = ir.textures[i].c3.x > 0.0f ? ir.textures[i].c3.x : 3.125f;
        }
    }

    CUDA_CHECK(cudaMalloc(&ds.d_tex_color1, sizeof(Vec3) * tex_count));
    CUDA_CHECK(cudaMalloc(&ds.d_tex_color2, sizeof(Vec3) * tex_count));
    CUDA_CHECK(cudaMalloc(&ds.d_tex_color3, sizeof(Vec3) * tex_count));
    CUDA_CHECK(cudaMalloc(&ds.d_tex_checker_inv_scale, sizeof(float) * tex_count));
    CUDA_CHECK(cudaMalloc(&ds.d_tex_resource_id, sizeof(int) * tex_count));
    CUDA_CHECK(cudaMalloc(&ds.d_tex_type, sizeof(TextureType) * tex_count));
    if (res_count > 0) {
        CUDA_CHECK(cudaMalloc(&ds.d_res_width, sizeof(int) * res_count));
        CUDA_CHECK(cudaMalloc(&ds.d_res_height, sizeof(int) * res_count));
        CUDA_CHECK(cudaMalloc(&ds.d_res_offset, sizeof(int) * res_count));
    }
    if (total_res_pixels > 0) {
        CUDA_CHECK(cudaMalloc(&ds.d_res_pixels, sizeof(Vec3) * total_res_pixels));
    }

    CUDA_CHECK(cudaMemcpy(ds.d_tex_color1, h_tex_color1.data(), sizeof(Vec3) * tex_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_tex_color2, h_tex_color2.data(), sizeof(Vec3) * tex_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_tex_color3, h_tex_color3.data(), sizeof(Vec3) * tex_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_tex_checker_inv_scale, h_tex_checker_inv_scale.data(), sizeof(float) * tex_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_tex_resource_id, h_tex_resource_id.data(), sizeof(int) * tex_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_tex_type, h_tex_type.data(), sizeof(TextureType) * tex_count, cudaMemcpyHostToDevice));
    if (res_count > 0) {
        CUDA_CHECK(cudaMemcpy(ds.d_res_width, h_res_width.data(), sizeof(int) * res_count, cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(ds.d_res_height, h_res_height.data(), sizeof(int) * res_count, cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(ds.d_res_offset, h_res_offset.data(), sizeof(int) * res_count, cudaMemcpyHostToDevice));
    }
    if (total_res_pixels > 0) {
        CUDA_CHECK(cudaMemcpy(ds.d_res_pixels, h_res_pixels.data(), sizeof(Vec3) * total_res_pixels, cudaMemcpyHostToDevice));
    }

    TextureList h_textures{};
    h_textures.count = tex_count;
    h_textures.color1 = ds.d_tex_color1;
    h_textures.color2 = ds.d_tex_color2;
    h_textures.color3 = ds.d_tex_color3;
    h_textures.checkerInvScale = ds.d_tex_checker_inv_scale;
    h_textures.resourceId = ds.d_tex_resource_id;
    h_textures.resourceCount = res_count;
    h_textures.resourceWidth = ds.d_res_width;
    h_textures.resourceHeight = ds.d_res_height;
    h_textures.resourceOffset = ds.d_res_offset;
    h_textures.resourcePixels = ds.d_res_pixels;
    h_textures.type = ds.d_tex_type;

    CUDA_CHECK(cudaMalloc(&ds.d_textures, sizeof(TextureList)));
    CUDA_CHECK(cudaMemcpy(ds.d_textures, &h_textures, sizeof(TextureList), cudaMemcpyHostToDevice));

    std::cerr << "Textures uploaded to device." << std::endl;

    std::vector<int> h_mat_texture_id(mat_count);
    std::vector<Vec3> h_mat_albedo(mat_count);
    std::vector<float> h_mat_c1(mat_count), h_mat_c2(mat_count);
    std::vector<MaterialType> h_mat_type(mat_count);
    for (int i = 0; i < mat_count; ++i) {
        h_mat_texture_id[i] = ir.materials[i].textureId;
        h_mat_albedo[i] = ir.materials[i].color;
        h_mat_c1[i] = ir.materials[i].p1;
        h_mat_c2[i] = ir.materials[i].p2;
        h_mat_type[i] = static_cast<MaterialType>(ir.materials[i].type);
    }

    CUDA_CHECK(cudaMalloc(&ds.d_mat_texture_id, sizeof(int) * mat_count));
    CUDA_CHECK(cudaMalloc(&ds.d_mat_albedo, sizeof(Vec3) * mat_count));
    CUDA_CHECK(cudaMalloc(&ds.d_mat_c1, sizeof(float) * mat_count));
    CUDA_CHECK(cudaMalloc(&ds.d_mat_c2, sizeof(float) * mat_count));
    CUDA_CHECK(cudaMalloc(&ds.d_mat_type, sizeof(MaterialType) * mat_count));

    CUDA_CHECK(cudaMemcpy(ds.d_mat_texture_id, h_mat_texture_id.data(), sizeof(int) * mat_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_mat_albedo, h_mat_albedo.data(), sizeof(Vec3) * mat_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_mat_c1, h_mat_c1.data(), sizeof(float) * mat_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_mat_c2, h_mat_c2.data(), sizeof(float) * mat_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_mat_type, h_mat_type.data(), sizeof(MaterialType) * mat_count, cudaMemcpyHostToDevice));

    MaterialList h_materials{};
    h_materials.count = mat_count;
    h_materials.textureId = ds.d_mat_texture_id;
    h_materials.albedo = ds.d_mat_albedo;
    h_materials.constraint1 = ds.d_mat_c1;
    h_materials.constraint2 = ds.d_mat_c2;
    h_materials.type = ds.d_mat_type;
    h_materials.textures = ds.d_textures;

    CUDA_CHECK(cudaMalloc(&ds.d_materials, sizeof(MaterialList)));
    CUDA_CHECK(cudaMemcpy(ds.d_materials, &h_materials, sizeof(MaterialList), cudaMemcpyHostToDevice));

    std::cerr << "Materials uploaded to device." << std::endl;

    std::vector<Vec3> h_hit_point(hit_count), h_hit_u(hit_count), h_hit_v(hit_count), h_hit_moving(hit_count), h_hit_aux1(hit_count), h_hit_aux2(hit_count);
    std::vector<float> h_hit_radius(hit_count);
    std::vector<int> h_hit_material_id(hit_count), h_hit_texture_id(hit_count);
    std::vector<HittableType> h_hit_type(hit_count);

    for (int i = 0; i < hit_count; ++i) {
        h_hit_point[i] = ir.hittables[i].p;
        h_hit_u[i] = ir.hittables[i].u;
        h_hit_v[i] = ir.hittables[i].v;
        h_hit_moving[i] = ir.hittables[i].moving;
        h_hit_aux1[i] = ir.hittables[i].aux1;
        h_hit_aux2[i] = ir.hittables[i].aux2;
        h_hit_radius[i] = ir.hittables[i].radius;
        h_hit_texture_id[i] = ir.hittables[i].textureId;
        h_hit_material_id[i] = ir.hittables[i].materialId;
        h_hit_type[i] = static_cast<HittableType>(ir.hittables[i].type);
    }

    CUDA_CHECK(cudaMalloc(&ds.d_hit_point, sizeof(Vec3) * hit_count));
    CUDA_CHECK(cudaMalloc(&ds.d_hit_u, sizeof(Vec3) * hit_count));
    CUDA_CHECK(cudaMalloc(&ds.d_hit_v, sizeof(Vec3) * hit_count));
    CUDA_CHECK(cudaMalloc(&ds.d_hit_moving, sizeof(Vec3) * hit_count));
    CUDA_CHECK(cudaMalloc(&ds.d_hit_aux1, sizeof(Vec3) * hit_count));
    CUDA_CHECK(cudaMalloc(&ds.d_hit_aux2, sizeof(Vec3) * hit_count));
    CUDA_CHECK(cudaMalloc(&ds.d_hit_radius, sizeof(float) * hit_count));
    CUDA_CHECK(cudaMalloc(&ds.d_hit_material_id, sizeof(int) * hit_count));
    CUDA_CHECK(cudaMalloc(&ds.d_hit_texture_id, sizeof(int) * hit_count));
    CUDA_CHECK(cudaMalloc(&ds.d_hit_type, sizeof(HittableType) * hit_count));

    CUDA_CHECK(cudaMemcpy(ds.d_hit_point, h_hit_point.data(), sizeof(Vec3) * hit_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_hit_u, h_hit_u.data(), sizeof(Vec3) * hit_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_hit_v, h_hit_v.data(), sizeof(Vec3) * hit_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_hit_moving, h_hit_moving.data(), sizeof(Vec3) * hit_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_hit_aux1, h_hit_aux1.data(), sizeof(Vec3) * hit_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_hit_aux2, h_hit_aux2.data(), sizeof(Vec3) * hit_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_hit_radius, h_hit_radius.data(), sizeof(float) * hit_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_hit_material_id, h_hit_material_id.data(), sizeof(int) * hit_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_hit_texture_id, h_hit_texture_id.data(), sizeof(int) * hit_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_hit_type, h_hit_type.data(), sizeof(HittableType) * hit_count, cudaMemcpyHostToDevice));

    HittableList h_hittables{};
    h_hittables.count = hit_count;
    h_hittables.point = ds.d_hit_point;
    h_hittables.u = ds.d_hit_u;
    h_hittables.v = ds.d_hit_v;
    h_hittables.moving = ds.d_hit_moving;
    h_hittables.aux1 = ds.d_hit_aux1;
    h_hittables.aux2 = ds.d_hit_aux2;
    h_hittables.radius = ds.d_hit_radius;
    h_hittables.materialId = ds.d_hit_material_id;
    h_hittables.textureId = ds.d_hit_texture_id;
    h_hittables.type = ds.d_hit_type;

    CUDA_CHECK(cudaMalloc(&ds.d_hittables, sizeof(HittableList)));
    CUDA_CHECK(cudaMemcpy(ds.d_hittables, &h_hittables, sizeof(HittableList), cudaMemcpyHostToDevice));

    std::cerr << "Hittables uploaded to device." << std::endl;

    std::vector<int> h_bvh_left(bvh_count), h_bvh_right(bvh_count), h_bvh_hittable_index(bvh_count);
    std::vector<AABB> h_bvh_bbox(bvh_count);
    std::vector<bool> h_bvh_is_leaf(bvh_count);

    for (int i = 0; i < bvh_count; ++i) {
        h_bvh_left[i] = ir.bvh[i].left;
        h_bvh_right[i] = ir.bvh[i].right;
        h_bvh_bbox[i] = ir.bvh[i].bbox;
        h_bvh_hittable_index[i] = ir.bvh[i].hittableIndex;
        h_bvh_is_leaf[i] = ir.bvh[i].hittableIndex >= 0;
    }

    CUDA_CHECK(cudaMalloc(&ds.d_bvh_left, sizeof(int) * bvh_count));
    CUDA_CHECK(cudaMalloc(&ds.d_bvh_right, sizeof(int) * bvh_count));
    CUDA_CHECK(cudaMalloc(&ds.d_bvh_bbox, sizeof(AABB) * bvh_count));
    CUDA_CHECK(cudaMalloc(&ds.d_bvh_hittable_index, sizeof(int) * bvh_count));
    CUDA_CHECK(cudaMalloc(&ds.d_bvh_is_leaf, sizeof(bool) * bvh_count));

    CUDA_CHECK(cudaMemcpy(ds.d_bvh_left, h_bvh_left.data(), sizeof(int) * bvh_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_bvh_right, h_bvh_right.data(), sizeof(int) * bvh_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_bvh_bbox, h_bvh_bbox.data(), sizeof(AABB) * bvh_count, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(ds.d_bvh_hittable_index, h_bvh_hittable_index.data(), sizeof(int) * bvh_count, cudaMemcpyHostToDevice));

    std::vector<uint8_t> h_bvh_is_leaf_u8(bvh_count);
    for (int i = 0; i < bvh_count; ++i) {
        h_bvh_is_leaf_u8[i] = h_bvh_is_leaf[i] ? 1 : 0;
    }
    CUDA_CHECK(cudaMemcpy(ds.d_bvh_is_leaf, h_bvh_is_leaf_u8.data(), sizeof(bool) * bvh_count, cudaMemcpyHostToDevice));

    BVH h_bvh{};
    h_bvh.count = bvh_count;
    h_bvh.left = ds.d_bvh_left;
    h_bvh.right = ds.d_bvh_right;
    h_bvh.bbox = ds.d_bvh_bbox;
    h_bvh.hittableIndex = ds.d_bvh_hittable_index;
    h_bvh.isLeaf = ds.d_bvh_is_leaf;
    h_bvh.hittables = ds.d_hittables;

    CUDA_CHECK(cudaMalloc(&ds.d_bvh, sizeof(BVH)));
    CUDA_CHECK(cudaMemcpy(ds.d_bvh, &h_bvh, sizeof(BVH), cudaMemcpyHostToDevice));

    std::cerr << "BVH uploaded to device." << std::endl;

    return ds;
}

static size_t estimate_scene_device_bytes(const ParsedIR& ir) {
    const size_t tex_count = ir.textures.size();
    const size_t mat_count = ir.materials.size();
    const size_t hit_count = ir.hittables.size();
    const size_t bvh_count = ir.bvh.size();
    const size_t res_count = ir.resources.size();

    size_t bytes = 0;

    bytes += sizeof(Vec3) * tex_count * 3;
    bytes += sizeof(float) * tex_count;
    bytes += sizeof(int) * tex_count;
    bytes += sizeof(TextureType) * tex_count;
    bytes += sizeof(TextureList);

    bytes += sizeof(int) * mat_count;
    bytes += sizeof(Vec3) * mat_count;
    bytes += sizeof(float) * mat_count * 2;
    bytes += sizeof(MaterialType) * mat_count;
    bytes += sizeof(MaterialList);

    bytes += sizeof(Vec3) * hit_count * 6;
    bytes += sizeof(float) * hit_count;
    bytes += sizeof(int) * hit_count * 2;
    bytes += sizeof(HittableType) * hit_count;
    bytes += sizeof(HittableList);

    bytes += sizeof(int) * bvh_count * 3;
    bytes += sizeof(AABB) * bvh_count;
    bytes += sizeof(bool) * bvh_count;
    bytes += sizeof(BVH);
    bytes += sizeof(int) * res_count * 3; // For resource width, height, and offset
    size_t total_res_pixels = 0;
    for (const auto& r : ir.resources) {
        total_res_pixels += r.pixels.size();
    }
    bytes += sizeof(Vec3) * total_res_pixels; // For resource pixels

    return bytes;
}

static void print_device_memory_usage(const char* tag) {
    size_t free_mem = 0;
    size_t total_mem = 0;
    CUDA_CHECK(cudaMemGetInfo(&free_mem, &total_mem));

    const size_t used_mem = total_mem - free_mem;
    const double used_ratio = total_mem == 0 ? 0.0 : static_cast<double>(used_mem) / static_cast<double>(total_mem);
    const double free_ratio = 1.0 - used_ratio;

    std::cerr << std::fixed << std::setprecision(2)
              << "[" << tag << "] VRAM used=" << (used_mem / (1024.0 * 1024.0)) << " MiB"
              << " (" << (used_ratio * 100.0) << "%), free=" << (free_mem / (1024.0 * 1024.0)) << " MiB"
              << " (" << (free_ratio * 100.0) << "%), total=" << (total_mem / (1024.0 * 1024.0)) << " MiB"
              << std::endl;
}

int main(int argc, char** argv) {
    const bool build_only = (argc == 5 && std::string(argv[4]) == "--build-only");
    if (!(argc == 4 || build_only)) {
        std::cerr << "usage: gpu_render <ir_path> <output_ppm_path> <camera_cfg_path> [--build-only]" << std::endl;
        return 2;
    }

    const std::string ir_path = argv[1];
    const std::string output_path = argv[2];
    const std::string camera_cfg_path = argv[3];

    CUDA_CHECK(cudaDeviceSetLimit(cudaLimitStackSize, 32 * 1024));
    CUDA_CHECK(cudaDeviceSetLimit(cudaLimitMallocHeapSize, 64 * 1024 * 1024));
    size_t configured_stack_size = 0;
    size_t configured_heap_size = 0;
    CUDA_CHECK(cudaDeviceGetLimit(&configured_stack_size, cudaLimitStackSize));
    CUDA_CHECK(cudaDeviceGetLimit(&configured_heap_size, cudaLimitMallocHeapSize));
    std::cerr << "CUDA limits: stack=" << configured_stack_size
              << " bytes, malloc_heap=" << configured_heap_size << " bytes" << std::endl;
    print_device_memory_usage("startup");

    std::cerr << "Loading IR from: " << ir_path << std::endl;

    ParsedIR ir;
    std::string err;
    if (!parse_ir_file(ir_path, ir, &err)) {
        std::cerr << "parse_ir_file failed: " << err << std::endl;
        return 1;
    }

    std::cerr << "IR loaded successfully. Textures: " << ir.textures.size() << ", Materials: " << ir.materials.size()
              << ", Hittables: " << ir.hittables.size() << ", BVH Nodes: " << ir.bvh.size() << std::endl;

    CameraConfig cfg;
    try {
        cfg = load_camera_config(camera_cfg_path);
    } catch (const std::exception& ex) {
        std::cerr << "load_camera_config failed: " << ex.what() << std::endl;
        return 1;
    }

    std::cerr << "Camera config loaded successfully." << std::endl;

    std::cerr << "Building device scene..." << std::endl;
    print_device_memory_usage("before-scene-build");

    DeviceScene ds;
    try {
        ds = build_device_scene(ir);
    } catch (const std::exception& ex) {
        std::cerr << "build_device_scene failed: " << ex.what() << std::endl;
        return 1;
    }

    std::cerr << "Device scene built successfully." << std::endl;
    const size_t estimated_scene_bytes = estimate_scene_device_bytes(ir);
    std::cerr << std::fixed << std::setprecision(2)
              << "[scene-estimate] Device allocations ~= "
              << (estimated_scene_bytes / (1024.0 * 1024.0)) << " MiB" << std::endl;
    print_device_memory_usage("after-scene-build");

    if (build_only) {
        std::cerr << "Build-only mode enabled: skipping render." << std::endl;
        free_device_scene(ds);
        CUDA_CHECK(cudaDeviceSynchronize());
        print_device_memory_usage("after-scene-free");
        return 0;
    }

    FILE* output = std::fopen(output_path.c_str(), "w");
    if (!output) {
        std::cerr << "failed to open output file: " << output_path << std::endl;
        free_device_scene(ds);
        return 1;
    }

    const int image_height = std::max(1, static_cast<int>(cfg.image_width / cfg.aspect_ratio));

    Camera cam(
        cfg.aspect_ratio,
        cfg.image_width,
        image_height,
        cfg.samples_per_pixel,
        cfg.max_depth,
        cfg.vfov,
        cfg.lookfrom,
        cfg.lookat,
        cfg.vup,
        cfg.defocus_angle,
        cfg.focus_dist,
        cfg.background,
        cfg.use_bvh,
        cfg.rng_seed
    );

    std::cerr << "Starting render..." << std::endl;

    cam.render(output, ds.d_bvh, ds.d_materials);
    CUDA_CHECK(cudaDeviceSynchronize());

    free_device_scene(ds);
    print_device_memory_usage("after-scene-free");
    std::fclose(output);

    return 0;
}
