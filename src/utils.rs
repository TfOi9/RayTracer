use rand::Rng;
use rand::RngCore;

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