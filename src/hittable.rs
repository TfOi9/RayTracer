use crate::vec3::Vec3;
use crate::vec3::Point3;
use crate::ray::Ray;
use crate::interval::Interval;
use crate::material::Material;

use::std::rc::Rc;

pub struct HitRecord {
    pub p: Point3,
    pub normal: Vec3,
    pub mat: Rc<dyn Material>,
    pub t: f64,
    pub front_face: bool
}

impl HitRecord {
    pub fn set_face_normal(&mut self, r: &Ray, outward_normal: &Vec3) {
        // NOTE: outward_normal is supposed to have unit length.

        self.front_face = *r.direction() * *outward_normal < 0.0;
        self.normal = if self.front_face { *outward_normal } else { -*outward_normal };
    }
}

pub trait Hittable {
    fn hit(&self, r: &Ray, ray_t: Interval) -> Option<HitRecord>;
}