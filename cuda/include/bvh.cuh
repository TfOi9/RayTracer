#ifndef CUDA_BVH_CUH
#define CUDA_BVH_CUH

#include "aabb.cuh"
#include "hittable.cuh"

// flat SoA BVH representation for GPU ray tracing
struct BVH {
    int count;
    int *left;
    int *right;
    AABB *bbox;
    int *hittableIndex; // Only valid for leaf nodes, -1 for internal
    bool *isLeaf;
    HittableList *hittables;

    __device__
    bool hit(const Ray& ray, const Interval& ray_t, HitRecord& out_record, curandState* rand_state, int node_index = 0) const {
        if (count <= 0 || node_index < 0 || node_index >= count ||
            left == nullptr || right == nullptr || bbox == nullptr ||
            hittableIndex == nullptr || hittables == nullptr) {
            return false;
        }

        constexpr int STACK_CAPACITY = 2048;
        int stack[STACK_CAPACITY];
        int top = 0;
        stack[top++] = node_index;

        bool any_hit = false;
        float closest_t = ray_t.max;
        HitRecord temp_record;

        while (top > 0) {
            int current = stack[--top];
            if (current < 0 || current >= count) {
                continue;
            }

            if (!bbox[current].hit(ray, Interval(ray_t.min, closest_t))) {
                continue;
            }

            int obj_index = hittableIndex[current];
            bool leaf = isLeaf != nullptr ? isLeaf[current] : (obj_index >= 0);
            if (leaf) {
                if (obj_index < 0 || obj_index >= hittables->count) {
                    continue;
                }
                if (hittables->hit(obj_index, ray, Interval(ray_t.min, closest_t), temp_record, rand_state)) {
                    any_hit = true;
                    closest_t = temp_record.t;
                    out_record = temp_record;
                }
                continue;
            }

            if (top + 2 >= STACK_CAPACITY) {
                return any_hit;
            }

            const int left_idx = left[current];
            const int right_idx = right[current];
            if (left_idx >= 0 && left_idx < count) {
                stack[top++] = left_idx;
            }
            if (right_idx >= 0 && right_idx < count) {
                stack[top++] = right_idx;
            }
        }

        return any_hit;
    }
};

#endif // CUDA_BVH_CUH