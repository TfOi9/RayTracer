use std::ops::{Add, AddAssign, Sub, SubAssign, Mul, MulAssign, Div, DivAssign};
use rand::RngCore;

use crate::utils::{self, random_real, random_real_interval};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Vec3 {
    e: [f64; 3]
}

pub type Point3 = Vec3;

impl Vec3 {
    pub fn new(x: f64, y: f64, z: f64) -> Self {
        Self { e:[x, y, z] }
    }

    pub fn x(&self) -> f64 {
        self.e[0]
    }

    pub fn y(&self) -> f64 {
        self.e[1]
    }

    pub fn z(&self) -> f64 {
        self.e[2]
    }

    pub fn components(&self) -> (f64, f64, f64) {
        (self.e[0], self.e[1], self.e[2])
    }

    pub fn length(&self) -> f64 {
        (self.e[0] * self.e[0] + self.e[1] * self.e[1] + self.e[2] * self.e[2]).sqrt()
    }

    pub fn length_squared(&self) -> f64 {
        self.e[0] * self.e[0] + self.e[1] * self.e[1] + self.e[2] * self.e[2]
    }
}

impl Default for Vec3 {
    fn default() -> Self {
        Self { e: [0.0, 0.0, 0.0] }
    }
}

impl Add for Vec3 {
    type Output = Self;
    fn add(self, other: Self) -> Self {
        Self {
            e: [
                self.e[0] + other.e[0],
                self.e[1] + other.e[1],
                self.e[2] + other.e[2]
            ]
        }
    }
}

impl Sub for Vec3 {
    type Output = Self;
    fn sub(self, other: Self) -> Self {
        Self {
            e: [
                self.e[0] - other.e[0],
                self.e[1] - other.e[1],
                self.e[2] - other.e[2]
            ]
        }
    }
}

impl Mul<f64> for Vec3 {
    type Output = Self;
    fn mul(self, other: f64) -> Self {
        Self {
            e: [
                self.e[0] * other,
                self.e[1] * other,
                self.e[2] * other
            ]
        }
    }
}

impl Mul<Vec3> for f64 {
    type Output = Vec3;
    fn mul(self, other: Vec3) -> Vec3 {
        Vec3 {
            e: [
                other.e[0] * self,
                other.e[1] * self,
                other.e[2] * self
            ]
        }
    }
}

impl Mul<Self> for Vec3 {
    type Output = f64;
    fn mul(self, other: Self) -> f64 {
        self.e[0] * other.e[0] + self.e[1] * other.e[1] + self.e[2] * other.e[2]
    }
}

impl Div<f64> for Vec3 {
    type Output = Self;
    fn div(self, other: f64) -> Self {
        Self {
            e: [
                self.e[0] / other,
                self.e[1] / other,
                self.e[2] / other
            ]
        }
    }
}

impl AddAssign for Vec3 {
    fn add_assign(&mut self, other: Self) {
        self.e[0] += other.e[0];
        self.e[1] += other.e[1];
        self.e[2] += other.e[2];
    }
}

impl SubAssign for Vec3 {
    fn sub_assign(&mut self, other: Self) {
        self.e[0] -= other.e[0];
        self.e[1] -= other.e[1];
        self.e[2] -= other.e[2];
    }
}

impl MulAssign<f64> for Vec3 {
    fn mul_assign(&mut self, other: f64) {
        self.e[0] *= other;
        self.e[1] *= other;
        self.e[2] *= other;
    }
}

impl DivAssign<f64> for Vec3 {
    fn div_assign(&mut self, other: f64) {
        self.e[0] /= other;
        self.e[1] /= other;
        self.e[2] /= other;
    }
}

use::std::ops::{Index, IndexMut};

impl Index<usize> for Vec3 {
    type Output = f64;
    fn index(&self, index : usize) -> &Self::Output {
        &self.e[index]
    }
}

impl IndexMut<usize> for Vec3 {
    fn index_mut(&mut self, index: usize) -> &mut Self::Output {
        &mut self.e[index]
    }
}

impl Vec3 {
    pub fn cross(a: &Vec3, b: &Vec3) -> Vec3 {
        Vec3 {
            e: [
                a.e[1] * b.e[2] - a.e[2] * b.e[1],
                a.e[2] * b.e[0] - a.e[0] * b.e[2],
                a.e[0] * b.e[1] - a.e[1] * b.e[0]
            ]
        }
    }
}

use::std::ops::Neg;

impl Neg for Vec3 {
    type Output = Self;
    fn neg(self) -> Self::Output {
        Vec3 {
            e: [
                -self.e[0],
                -self.e[1],
                -self.e[2]
            ]
        }
    }
}

impl Vec3 {
    pub fn unit(self) -> Self {
        let len = self.length();
        self / len
    }

    pub fn random_unit(rng: &mut dyn RngCore) -> Self {
        let theta: f64 = random_real_interval(rng, 0.0, 2.0 * utils::PI);
        let z: f64 = random_real(rng);
        let phi: f64 = z.acos();
        
        Vec3::new(
            phi.sin() * theta.cos(),
            phi.sin() * theta.sin(),
            z
        )
    }

    pub fn random_unit_on_hemishpere(normal: &Vec3, rng: &mut dyn RngCore) -> Self {
        let unit = Self::random_unit(rng);
        if unit * *normal > 0.0 {
            return unit;
        }
        else {
            return -unit;
        }
    }
}

impl Vec3 {
    pub fn near_zero(&self) -> bool {
        self.e[0].abs() < 1e-8 && self.e[1].abs() < 1e-8 && self.e[2].abs() < 1e-8
    }

    pub fn reflect(v: Vec3, n: Vec3) -> Vec3 {
        v - 2.0 * v * n * n
    }
}