#ifndef CUDA_HITTABLE_CUH
#define CUDA_HITTABLE_CUH

#include "vec3.cuh"
#include "ray.cuh"
#include "interval.cuh"
#include "pi.cuh"
#include "random.cuh"

enum HittableType {
    UnknownHittable = 0,
    Sphere,
    Triangle,
    Quad,
    ConstantMediumSphere
};

struct HitRecord {
    Point3 p;
    Vec3 normal;
    int materialId;
    float t;
    float u;
    float v;
    bool front_face;

    __host__ __device__
    void set_face_normal(const Ray& ray, const Vec3& outward_normal) {
        front_face = ray.direction.dot(outward_normal) < 0;
        normal = front_face ? outward_normal : outward_normal * -1.0f;
    }
};

__host__ __device__
bool hit_sphere(const Vec3 &center0, const Vec3& moving, float radius, const Ray &ray, const Interval& ray_t, HitRecord& out_record);

__host__ __device__
bool hit_triangle(const Vec3& a, const Vec3& edge1, const Vec3& edge2, const Ray& ray, const Interval& ray_t, HitRecord& out_record);

__host__ __device__
bool hit_quad(const Vec3& q, const Vec3& u, const Vec3& v, const Vec3& w, const Ray& ray, const Interval& ray_t, HitRecord& out_record);

__device__
bool hit_constant_medium_sphere(const Vec3& center0, const Vec3& moving, float radius, float neg_inv_density,
                                const Ray& ray, const Interval& ray_t, curandState* rand_state, HitRecord& out_record);

__host__ __device__
inline void sphere_uv(const Vec3& p, float& u, float& v) {
    float theta = acosf(-p.y);
    float phi = atan2f(-p.z, p.x) + M_PI;
    u = phi / (2.0f * M_PI);
    v = theta / M_PI;
}

// SoA style hittable list for GPU ray tracing
struct HittableList {
    int count;
    Vec3 *point;
    Vec3 *u;
    Vec3 *v;
    Vec3 *moving;
    Vec3 *aux1;
    Vec3 *aux2;
    float *radius;
    int *materialId;
    int *textureId;
    HittableType *type;

    __device__
    bool hit(int index, const Ray& ray, const Interval& ray_t, HitRecord& out_record, curandState* rand_state) const {
        if (count <= 0 || index < 0 || index >= count ||
            point == nullptr || u == nullptr || v == nullptr || moving == nullptr ||
            aux1 == nullptr || aux2 == nullptr || radius == nullptr || materialId == nullptr ||
            textureId == nullptr || type == nullptr) {
            return false;
        }

        HittableType t = type[index];
        bool hit_ok = false;
        switch (t) {
            case Sphere:
                if (radius[index] <= 0.0f) {
                    return false;
                }
                hit_ok = hit_sphere(point[index], moving[index], radius[index], ray, ray_t, out_record);
                break;
            case Triangle:
                hit_ok = hit_triangle(point[index], u[index], v[index], ray, ray_t, out_record);
                break;
            case Quad:
                hit_ok = hit_quad(point[index], u[index], v[index], aux1[index], ray, ray_t, out_record);
                break;
            case ConstantMediumSphere:
                if (radius[index] <= 0.0f || rand_state == nullptr) {
                    return false;
                }
                hit_ok = hit_constant_medium_sphere(point[index], moving[index], radius[index], aux1[index].x,
                                                    ray, ray_t, rand_state, out_record);
                break;
            default:
                return false;
        }
        if (!hit_ok) {
            return false;
        }

        out_record.materialId = materialId[index];
        if (t == Sphere) {
            Vec3 center_at_t = point[index] + moving[index] * ray.time;
            Vec3 outward = (out_record.p - center_at_t) / radius[index];
            sphere_uv(outward, out_record.u, out_record.v);
        } else if (t == ConstantMediumSphere) {
            out_record.u = 0.0f;
            out_record.v = 0.0f;
        }

        return true;
    }
};

/*
    SoA style hittable list for GPU ray tracing

    - point: For spheres, this is the center. For triangles and quads, this is the first vertex.
    - u: For triangles and quads, this is the edge vector from the first vertex to the second vertex. For spheres, this is unused.
    - v: For triangles and quads, this is the edge vector from the first vertex to the third vertex. For spheres, this is unused.
    - moving: For moving spheres, this is the velocity vector. For static objects, this is unused.
    - aux1: For triangles, this is unused. For quads, this is (w = ) n / (n * n). For spheres, this is unused.
    - aux2: Currently unused, reserved for future use.
    - radius: For spheres, this is the radius. For triangles and quads, this is unused.
    - materialId: The ID of the material associated with this hittable object.
    - textureId: The ID of the texture associated with this hittable object (if any).

*/

__host__ __device__
bool hit_sphere(const Vec3 &center0, const Vec3& moving, float radius, const Ray &ray, const Interval& ray_t, HitRecord& out_record) {
    Vec3 center = center0 + moving * ray.time;
    Vec3 oc = center - ray.origin;
    float a = ray.direction.length_squared();
    float h = ray.direction.dot(oc);
    float c = oc.length_squared() - radius * radius;
    float discriminant = h * h - a * c;

    if (discriminant < 0.0f) {
        return false;
    }

    float sqrt_disc = sqrtf(discriminant);
    float t1 = (h - sqrt_disc) / a;
    if (t1 < ray_t.max && t1 > ray_t.min) {
        out_record.t = t1;
        out_record.p = ray.at(t1);
        Vec3 outward = (out_record.p - center) / radius;
        out_record.set_face_normal(ray, outward);
        return true;
    }

    float t2 = (h + sqrt_disc) / a;
    if (t2 < ray_t.max && t2 > ray_t.min) {
        out_record.t = t2;
        out_record.p = ray.at(t2);
        Vec3 outward = (out_record.p - center) / radius;
        out_record.set_face_normal(ray, outward);
        return true;
    }

    return false;
}

__host__ __device__
bool hit_triangle(const Vec3& a, const Vec3& edge1, const Vec3& edge2, const Ray& ray, const Interval& ray_t, HitRecord& out_record) {
    Vec3 h = ray.direction.cross(edge2);
    float det = edge1.dot(h);
    if (fabsf(det) < 1e-8f) {
        return false;
    }
    float f = 1.0f / det;
    Vec3 s = ray.origin - a;
    float u = f * s.dot(h);
    if (u < 0.0f || u > 1.0f) {
        return false;
    }
    Vec3 q = s.cross(edge1);
    float v = f * ray.direction.dot(q);
    if (v < 0.0f || u + v > 1.0f) {
        return false;
    }
    float t = f * edge2.dot(q);
    if (t < ray_t.min || t > ray_t.max) {
        return false;
    }
    out_record.t = t;
    out_record.p = ray.at(t);
    out_record.normal = edge1.cross(edge2).normalize();
    out_record.set_face_normal(ray, out_record.normal);
    out_record.u = u;
    out_record.v = v;
    return true;
}

__host__ __device__
bool hit_quad(const Vec3& q, const Vec3& u, const Vec3& v, const Vec3& w, const Ray& ray, const Interval& ray_t, HitRecord& out_record) {
    (void)w;

    Vec3 n = u.cross(v);
    float denom = n.dot(ray.direction);
    if (fabsf(denom) < 1e-6f) {
        return false;
    }

    float d = n.dot(q);
    float t = (d - n.dot(ray.origin)) / denom;
    if (t < ray_t.min || t > ray_t.max) {
        return false;
    }

    Vec3 intersection = ray.at(t);
    Vec3 planar_hitpoint = intersection - q;

    // Solve planar_hitpoint = alpha*u + beta*v via 2x2 normal equations.
    float uu = u.dot(u);
    float uv = u.dot(v);
    float vv = v.dot(v);
    float up = planar_hitpoint.dot(u);
    float vp = planar_hitpoint.dot(v);
    float det = uu * vv - uv * uv;
    if (fabsf(det) < 1e-10f) {
        return false;
    }

    float alpha = (up * vv - vp * uv) / det;
    float beta = (vp * uu - up * uv) / det;
    if (alpha < 0.0f || alpha > 1.0f || beta < 0.0f || beta > 1.0f) {
        return false;
    }

    out_record.t = t;
    out_record.p = intersection;
    Vec3 outward = n.normalize();
    out_record.set_face_normal(ray, outward);
    out_record.u = alpha;
    out_record.v = beta;
    return true;
}

__device__
bool hit_constant_medium_sphere(const Vec3& center0, const Vec3& moving, float radius, float neg_inv_density,
                                const Ray& ray, const Interval& ray_t, curandState* rand_state, HitRecord& out_record) {
    Vec3 center = center0 + moving * ray.time;
    Vec3 oc = center - ray.origin;
    float a = ray.direction.length_squared();
    float h = ray.direction.dot(oc);
    float c = oc.length_squared() - radius * radius;
    float discriminant = h * h - a * c;
    if (discriminant < 0.0f) {
        return false;
    }

    float sqrt_disc = sqrtf(discriminant);
    float t1 = (h - sqrt_disc) / a;
    float t2 = (h + sqrt_disc) / a;
    if (t1 > t2) {
        float tmp = t1;
        t1 = t2;
        t2 = tmp;
    }

    float rec1_t = t1;
    float rec2_t = t2;
    if (rec1_t < ray_t.min) {
        rec1_t = ray_t.min;
    }
    if (rec2_t > ray_t.max) {
        rec2_t = ray_t.max;
    }
    if (rec1_t >= rec2_t) {
        return false;
    }
    if (rec1_t < 0.0f) {
        rec1_t = 0.0f;
    }

    float ray_length = ray.direction.length();
    float distance_inside_boundary = (rec2_t - rec1_t) * ray_length;

    float xi = random_float(rand_state);
    if (xi < 1e-6f) {
        xi = 1e-6f;
    }
    float hit_distance = neg_inv_density * logf(xi);
    if (hit_distance > distance_inside_boundary) {
        return false;
    }

    float t = rec1_t + hit_distance / ray_length;
    out_record.t = t;
    out_record.p = ray.at(t);
    out_record.normal = Vec3(1.0f, 0.0f, 0.0f);
    out_record.front_face = true;
    out_record.u = 0.0f;
    out_record.v = 0.0f;
    return true;
}

#endif // CUDA_HITTABLE_CUH