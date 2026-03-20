use crate::Ray;
use crate::HitRecord;
use crate::Color;
use crate::Vec3;
use crate::utils::random_real;

use rand::RngCore;

pub trait Material {
    fn scatter(&self, r_in: &Ray, rec: &HitRecord, rng: &mut dyn RngCore) -> Option<(Color, Ray)>;
}

pub struct Lambertian {
    albedo: Color
}

pub struct Metal {
    albedo: Color,
    fuzz: f64
}

pub struct Dielectric {
    refractive_index: f64
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
    fn scatter(&self, r_in: &Ray, rec: &HitRecord, rng: &mut dyn RngCore) -> Option<(Color, Ray)> {
        let scatter_direction = rec.normal + Vec3::random_unit(rng);

        if scatter_direction.near_zero() {
            return Some((self.albedo, Ray::new(rec.p, rec.normal, r_in.time())));
        }

        Some((self.albedo, Ray::new(rec.p, scatter_direction, r_in.time())))
    }
}

impl Metal {
    pub fn new(albedo_r: f64, albedo_g: f64, albedo_b: f64, fuzz: f64) -> Self {
        Self {
            albedo: Color::new(albedo_r, albedo_g, albedo_b),
            fuzz: fuzz.clamp(0.0, 1.0)
        }
    }

    pub fn from_color(albedo: Color, fuzz: f64) -> Self {
        Self {
            albedo,
            fuzz: fuzz.clamp(0.0, 1.0)
        }
    }
}

impl Material for Metal {
    fn scatter(&self, r_in: &Ray, rec: &HitRecord, rng: &mut dyn RngCore) -> Option<(Color, Ray)> {
        let reflected = Vec3::reflect((*r_in.direction()).clone(), rec.normal.clone()).unit()
            + self.fuzz * Vec3::random_unit(rng);

        let scattered = Ray::new(rec.p, reflected, r_in.time());
        if *(scattered.direction()) * rec.normal <= 0.0 {
            return None;
        }

        Some((self.albedo, scattered))
    }
}

impl Dielectric {
    pub fn new(refractive_index: f64) -> Self {
        Self {
            refractive_index
        }
    }

    fn reflectance(cosine: f64, refractive_index: f64) -> f64 {
        let r0_base: f64 = (1.0 - refractive_index) / (1.0 + refractive_index);
        let r0: f64 = r0_base * r0_base;
        r0 + (1.0 - r0) * (1.0 - cosine).powf(5.0)
    }
}

impl Material for Dielectric {
    fn scatter(&self, r_in: &Ray, rec: &HitRecord, rng: &mut dyn RngCore) -> Option<(Color, Ray)> {
        let ri: f64 = if rec.front_face { 1.0 / self.refractive_index } else { self.refractive_index };

        let unit_direction = (*r_in.direction()).unit();
        let cos_theta = (-unit_direction * rec.normal).min(1.0);
        let sin_theta = (1.0 - cos_theta * cos_theta).sqrt();
        let direction = if ri * sin_theta > 1.0
                || Dielectric::reflectance(cos_theta, ri) > random_real(rng) {
            Vec3::reflect(unit_direction, rec.normal)
        }
        else {
            Vec3::refract(unit_direction, rec.normal, ri)
        };

        Some((Color::new(1.0, 1.0, 1.0), Ray::new(rec.p, direction, r_in.time())))
    }
}
