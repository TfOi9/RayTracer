use crate::vec3::Vec3;
use crate::vec3::Point3;
use crate::hittable::HitRecord;
use crate::hittable::Hittable;
use crate::ray::Ray;
use crate::interval::Interval;
use crate::material::Material;

use std::rc::Rc;

pub struct Sphere {
    center: Ray,
    radius: f64,
    mat: Rc<dyn Material>
}

impl Sphere {
    pub fn new(static_center: Point3, radius: f64, mat: Rc<dyn Material>) -> Self {
        Sphere {
            center: Ray::new(static_center, Vec3::new(0.0, 0.0, 0.0), 0.0),
            radius: radius.max(0.0),
            mat
        }
    }

    pub fn new_moving(center0: Point3, center1: Point3, radius: f64, mat: Rc<dyn Material>) -> Self {
        Sphere {
            center: Ray::new(center0, center1 - center0, 0.0),
            radius: radius.max(0.0),
            mat
        }
    }

    pub fn center_at(&self, tm: f64) -> Point3 {
        self.center.at(tm)
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
            front_face: true
        };

        let outward_normal = (record.p.clone() - current_center) / self.radius;
        record.set_face_normal(r, &outward_normal);

        Some(record)
    }
}