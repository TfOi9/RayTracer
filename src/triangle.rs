use crate::vec3::Vec3;
use crate::vec3::Point3;
use crate::hittable::HitRecord;
use crate::hittable::Hittable;
use crate::ray::Ray;
use crate::interval::Interval;
use crate::material::Material;
use crate::aabb::AABB;

use std::sync::Arc;

pub struct Triangle {
    a: Point3,
    e1: Vec3,
    e2: Vec3,
    normal: Vec3,
    mat: Arc<dyn Material>,
    bbox: AABB
}

impl Triangle {
    pub fn new(a: Point3, b: Point3, c: Point3, mat: Arc<dyn Material>) -> Self {
        Self {
            a,
            e1: b - a,
            e2: c - a,
            normal: Vec3::cross(&(b - a), &(c - a)),
            mat,
            bbox: AABB::from_triangle(a, b, c)
        }
    }
}

impl Hittable for Triangle {
    fn hit(&self, r: &Ray, ray_t: Interval) -> Option<HitRecord> {
        let p: Vec3 = Vec3::cross(r.direction(), &self.e2);
        let det: f64 = self.e1 * p;
        
        if det.abs() < 1e-8 {
            return None;
        }

        let t: Vec3 = *r.origin() - self.a;
        let u: f64 = t * p / det;
        if u < 0.0 || u > 1.0 {
            return None;
        }

        let q = Vec3::cross(&t, &self.e1);
        let v: f64 = *r.direction() * q / det;
        if v < 0.0 || u + v > 1.0 {
            return None;
        }

        let hit_t: f64 = self.e2 * q / det;
        if !ray_t.surrounds(hit_t) {
            return None;
        }

        let normal_len_sq = self.normal.length_squared();
        if normal_len_sq < 1e-16 {
            return None;
        }
        let outward_normal = self.normal / normal_len_sq.sqrt();

        let recordp = r.at(hit_t);
        let mut record = HitRecord {
            t: hit_t,
            normal: outward_normal,
            mat: self.mat.clone(),
            p: recordp,
            front_face: true
        };

        record.set_face_normal(r, &outward_normal);

        Some(record)
    }

    fn bounding_box(&self) -> AABB {
        self.bbox.clone()
    }
}