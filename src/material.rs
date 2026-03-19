use crate::Ray;
use crate::HitRecord;
use crate::Color;
use crate::Vec3;

use rand::RngCore;

pub trait Material {
    fn scatter(&self, r_in: &Ray, rec: &HitRecord, rng: &mut dyn RngCore) -> Option<(Color, Ray)>;
}

pub struct Lambertian {
    albedo: Color
}

pub struct Metal {
    albedo: Color
}

impl Lambertian {
    pub fn new(albedo_r: f64, albedo_g: f64, albedo_b: f64) -> Self {
        Self {
            albedo: Color::new(albedo_r, albedo_g, albedo_b)
        }
    }

    pub fn from_color(albedo: Color) -> Self {
        Self {
            albedo
        }
    }
}

impl Material for Lambertian {
    fn scatter(&self, _r_in: &Ray, rec: &HitRecord, rng: &mut dyn RngCore) -> Option<(Color, Ray)> {
        let scatter_direction = rec.normal + Vec3::random_unit(rng);

        if scatter_direction.near_zero() {
            return Some((self.albedo, Ray::new(rec.p, rec.p)));
        }

        Some((self.albedo, Ray::new(rec.p, scatter_direction)))
    }
}

impl Metal {
    pub fn new(albedo_r: f64, albedo_g: f64, albedo_b: f64) -> Self {
        Self {
            albedo: Color::new(albedo_r, albedo_g, albedo_b)
        }
    }

    pub fn from_color(albedo: Color) -> Self {
        Self {
            albedo
        }
    }
}

impl Material for Metal {
    fn scatter(&self, r_in: &Ray, rec: &HitRecord, _rng: &mut dyn RngCore) -> Option<(Color, Ray)> {
        let reflected = Vec3::reflect((*r_in.direction()).clone(), rec.normal.clone()); 
        Some((self.albedo, Ray::new(rec.p, reflected)))
    }
}
