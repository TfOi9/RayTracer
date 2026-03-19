use crate::vec3::Point3;
use crate::hittable::HitRecord;
use crate::hittable::Hittable;
use crate::ray::Ray;
use crate::interval::Interval;
use crate::material::Material;

use std::rc::Rc;

pub struct Sphere {
    center: Point3,
    radius: f64,
    mat: Rc<dyn Material>
}

impl Sphere {
    pub fn new(center: Point3, radius: f64, mat: Rc<dyn Material>) -> Self {
        Sphere {
            center,
            radius: radius.max(0.0),
            mat
        }
    }
}

impl Hittable for Sphere {
    fn hit(&self, r: &Ray, ray_t: Interval) -> Option<HitRecord> {
        let oc = self.center - *r.origin();
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
            normal: (recordp - self.center) / self.radius,
            mat: self.mat.clone(),
            p: recordp,
            front_face: true
        };

        let outward_normal = (record.p.clone() - self.center) / self.radius;
        record.set_face_normal(r, &outward_normal);

        Some(record)
    }
}