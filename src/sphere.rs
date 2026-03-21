use crate::vec3::Vec3;
use crate::vec3::Point3;
use crate::hittable::HitRecord;
use crate::hittable::Hittable;
use crate::ray::Ray;
use crate::interval::Interval;
use crate::material::Material;
use crate::aabb::AABB;
use crate::utils::PI;

use std::sync::Arc;

pub struct Sphere {
    center: Ray,
    radius: f64,
    mat: Arc<dyn Material>,
    bbox: AABB
}

impl Sphere {
    pub fn new(static_center: Point3, radius: f64, mat: Arc<dyn Material>) -> Self {
        let rvec = Vec3::new(radius, radius, radius);

        Sphere {
            center: Ray::new(static_center, Vec3::new(0.0, 0.0, 0.0), 0.0),
            radius: radius.max(0.0),
            mat,
            bbox: AABB::from_points(static_center - rvec, static_center + rvec)
        }
    }

    pub fn new_moving(center0: Point3, center1: Point3, radius: f64, mat: Arc<dyn Material>) -> Self {
        let rvec = Vec3::new(radius, radius, radius);
        let aabb1 = AABB::from_points(center0 - rvec, center0 + rvec);
        let aabb2 = AABB::from_points(center1 - rvec, center1 + rvec);

        Sphere {
            center: Ray::new(center0, center1 - center0, 0.0),
            radius: radius.max(0.0),
            mat,
            bbox: AABB::from_aabbs(&aabb1, &aabb2)
        }
    }

    pub fn center_at(&self, tm: f64) -> Point3 {
        self.center.at(tm)
    }

    fn get_sphere_uv(p: &Point3) -> (f64, f64) {
        let theta = (-p.y()).acos();
        let phi = (-p.z()).atan2(p.x()) + PI;

        (phi / (2.0 * PI), theta / PI)
    }
}

impl Hittable for Sphere {
    fn hit(&self, r: &Ray, ray_t: Interval) -> Option<HitRecord> {
        let current_center = self.center_at(r.time());

        let oc = current_center - *r.origin();
        let a = (*r.direction()).length_squared();
        let h = *r.direction() * oc;
        let c = oc.length_squared() - self.radius * self.radius;

        let discriminant = h * h - a * c;
        if discriminant < 0.0 {
            return None;
        }
        let sqrtd = discriminant.sqrt();

        let mut root = (h - sqrtd) / a;
        if !ray_t.surrounds(root) {
            root = (h + sqrtd) / a;
            if !ray_t.surrounds(root) {
                return None;
            }
        }

        let recordp = r.at(root);
        let mut record = HitRecord {
            t: root,
            normal: (recordp - current_center) / self.radius,
            mat: self.mat.clone(),
            p: recordp,
            front_face: true,
            u: 0.0,
            v: 0.0
        };

        let outward_normal = (record.p.clone() - current_center) / self.radius;
        record.set_face_normal(r, &outward_normal);

        let uv = Sphere::get_sphere_uv(&outward_normal);
        record.u = uv.0;
        record.v = uv.1;

        Some(record)
    }

    fn bounding_box(&self) -> AABB {
        self.bbox.clone()
    }
}