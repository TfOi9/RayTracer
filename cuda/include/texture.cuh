#ifndef CUDA_TEXTURE_CUH
#define CUDA_TEXTURE_CUH

#include "vec3.cuh"

#include <cmath>
#include <cstdint>

enum TextureType {
    UnknownTexture = 0,
    SolidColor,
    Checker,
    Image,
    Perlin
};

struct TextureList {
    int count;
    Vec3 *color1;
    Vec3 *color2;
    Vec3 *color3;
    float *checkerInvScale;
    int *resourceId;
    int resourceCount;
    int *resourceWidth;
    int *resourceHeight;
    int *resourceOffset;
    Vec3 *resourcePixels;
    TextureType *type;

    __device__
    static float clamp01(float x) {
        if (x < 0.0f) {
            return 0.0f;
        }
        if (x > 1.0f) {
            return 1.0f;
        }
        return x;
    }

    __device__
    static float fade(float t) {
        return t * t * (3.0f - 2.0f * t);
    }

    __device__
    static uint32_t hash_u32(uint32_t x) {
        x ^= x >> 16;
        x *= 0x7feb352du;
        x ^= x >> 15;
        x *= 0x846ca68bu;
        x ^= x >> 16;
        return x;
    }

    __device__
    static Vec3 gradient_from_lattice(int x, int y, int z) {
        uint32_t h = hash_u32(static_cast<uint32_t>(x) * 73856093u
            ^ static_cast<uint32_t>(y) * 19349663u
            ^ static_cast<uint32_t>(z) * 83492791u);

        float gx = static_cast<float>((h & 1023u)) / 511.5f - 1.0f;
        float gy = static_cast<float>(((h >> 10) & 1023u)) / 511.5f - 1.0f;
        float gz = static_cast<float>(((h >> 20) & 1023u)) / 511.5f - 1.0f;
        Vec3 g(gx, gy, gz);
        float len = g.length();
        if (len <= 1e-8f) {
            return Vec3(1.0f, 0.0f, 0.0f);
        }
        return g / len;
    }

    __device__
    static float perlin_noise(const Point3& p) {
        const int i0 = static_cast<int>(floorf(p.x));
        const int j0 = static_cast<int>(floorf(p.y));
        const int k0 = static_cast<int>(floorf(p.z));

        const float u = p.x - floorf(p.x);
        const float v = p.y - floorf(p.y);
        const float w = p.z - floorf(p.z);

        const float uu = fade(u);
        const float vv = fade(v);
        const float ww = fade(w);

        float accum = 0.0f;
        for (int di = 0; di < 2; ++di) {
            for (int dj = 0; dj < 2; ++dj) {
                for (int dk = 0; dk < 2; ++dk) {
                    Vec3 grad = gradient_from_lattice(i0 + di, j0 + dj, k0 + dk);
                    Vec3 weight_v(u - static_cast<float>(di), v - static_cast<float>(dj), w - static_cast<float>(dk));

                    const float wi = di ? uu : (1.0f - uu);
                    const float wj = dj ? vv : (1.0f - vv);
                    const float wk = dk ? ww : (1.0f - ww);
                    accum += wi * wj * wk * grad.dot(weight_v);
                }
            }
        }
        return accum;
    }

    __device__
    static float perlin_turbulence(const Point3& p, int depth) {
        float accum = 0.0f;
        float weight = 1.0f;
        Point3 temp_p = p;
        for (int i = 0; i < depth; ++i) {
            accum += weight * perlin_noise(temp_p);
            weight *= 0.5f;
            temp_p *= 2.0f;
        }
        return fabsf(accum);
    }

    __device__
    Vec3 sample_image(int texture_index, float u, float v) const {
        if (resourceId == nullptr || resourceWidth == nullptr || resourceHeight == nullptr ||
            resourceOffset == nullptr || resourcePixels == nullptr) {
            return Vec3(0.0f, 1.0f, 1.0f);
        }

        const int rid = resourceId[texture_index];
        if (rid < 0 || rid >= resourceCount) {
            return Vec3(0.0f, 1.0f, 1.0f);
        }

        const int width = resourceWidth[rid];
        const int height = resourceHeight[rid];
        const int offset = resourceOffset[rid];
        if (width <= 0 || height <= 0 || offset < 0) {
            return Vec3(0.0f, 1.0f, 1.0f);
        }

        const float uu = clamp01(u);
        const float vv = 1.0f - clamp01(v);

        int i = static_cast<int>(uu * static_cast<float>(width));
        int j = static_cast<int>(vv * static_cast<float>(height));
        if (i >= width) {
            i = width - 1;
        }
        if (j >= height) {
            j = height - 1;
        }

        const int idx = offset + j * width + i;
        return resourcePixels[idx];
    }

    __device__
    Vec3 sample(int index, float u, float v, const Point3& p) const {
        if (count <= 0 || index < 0 || index >= count ||
            color1 == nullptr || color2 == nullptr || color3 == nullptr ||
            checkerInvScale == nullptr || resourceId == nullptr || type == nullptr) {
            return Vec3(1.0f, 0.0f, 1.0f);
        }

        TextureType t = type[index];
        switch (t) {
            case SolidColor:
                return color1[index];
            case Checker: {
                float inv_scale = checkerInvScale[index];
                int ix = static_cast<int>(floorf(inv_scale * p.x));
                int iy = static_cast<int>(floorf(inv_scale * p.y));
                int iz = static_cast<int>(floorf(inv_scale * p.z));
                if ((ix + iy + iz) % 2 == 0) {
                    return color2[index];
                } else {
                    return color1[index];
                }
            }
            case Image:
                return sample_image(index, u, v);
            case Perlin: {
                const float scale = color3[index].x;
                const float turb = perlin_turbulence(p, 7);
                const float val = 1.0f + sinf(scale * p.z + 10.0f * turb);
                return Vec3(0.5f, 0.5f, 0.5f) * val;
            }
            default:
                return Vec3(1.0f, 1.0f, 1.0f); // Default to white for unknown types
        }
    }
};

#endif // CUDA_TEXTURE_CUH