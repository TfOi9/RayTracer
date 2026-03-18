use crate::vec3::Vec3;

pub type Color = Vec3;

impl Color {
    pub fn print_color(&self) {
        let ir = (255.999 * self.x()) as u8;
        let ig = (255.999 * self.y()) as u8;
        let ib = (255.999 * self.z()) as u8;

        println!("{} {} {}", ir, ig, ib);
    }
}