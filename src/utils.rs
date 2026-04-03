use rand::Rng;
use rand::RngCore;
use crate::vec3::Vec3;
use std::ops::{Add, Sub, Mul};

pub const PI: f64 = 3.1415926;

pub fn degrees_to_radians(degrees: f64) -> f64 {
    degrees * PI / 180.0
}

pub fn random_real(rng: &mut dyn RngCore) -> f64 {
    rng.r#gen()
}

pub fn random_real_interval(rng: &mut dyn RngCore, min: f64, max: f64) -> f64 {
    min + rng.r#gen::<f64>() * (max - min)
}

pub fn random_integer_interval(rng: &mut dyn RngCore, min: i32, max: i32) -> i32 {
    rng.gen_range(min..=max)
}

pub fn lerp<T>(a: T, b: T, t: f64) -> T
        where T: Add<Output = T> + Sub<Output = T> + Mul<f64, Output = T> + Clone {
    a.clone() + (b - a) * t
}

pub fn schlick(f: f64, d: f64) -> f64 {
    f + (1.0 - f) * (1.0 - d).powi(5)
}

pub fn schlick_weight(f: f64) -> f64 {
    (1.0 - f).powi(5)
}

pub fn cos_theta(v: &Vec3) -> f64 {
    v.z()
}

pub fn tan_theta(v: &Vec3) -> f64 {
    (v.x() * v.x() + v.y() * v.y()).sqrt() / v.z().abs()
}

pub fn cos_2theta(v: &Vec3) -> f64 {
    2.0 * v.z() * v.z() - 1.0
}

pub fn cos_2phi(v: &Vec3) -> f64 {
    (v.x() * v.x() - v.y() * v.y()) / (v.x() * v.x() + v.y() * v.y())
}

pub fn sin_2phi(v: &Vec3) -> f64 {
    (2.0 * v.x() * v.y()) / (v.x() * v.x() + v.y() * v.y())
}