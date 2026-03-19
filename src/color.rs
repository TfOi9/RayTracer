use crate::vec3::Vec3;
use crate::interval::Interval;

pub type Color = Vec3;

impl Color {
    pub fn linear_to_gamma(linear_component: f64) -> f64 {
        linear_component.sqrt()
    }
}

impl Color {
    pub fn print_color(&self) {
        let r = Self::linear_to_gamma(self.x());
        let g = Self::linear_to_gamma(self.y());
        let b = Self::linear_to_gamma(self.z());

        let ir = (256.0 * Interval::PSEUDO_UNIT.clamp(r)) as u8;
        let ig = (256.0 * Interval::PSEUDO_UNIT.clamp(g)) as u8;
        let ib = (256.0 * Interval::PSEUDO_UNIT.clamp(b)) as u8;

        println!("{} {} {}", ir, ig, ib);
    }
}

impl Color {
    pub fn hadamard_product(&self, other: Color) -> Color {
        Color::new(self.x() * other.x(), self.y() * other.y(), self.z() * other.z())
    }
}