use crate::color::Color;

use std::vec::Vec;

pub fn parse_image(path: &str) -> (u32, u32, Vec<Color>) {
    let img = image::open(path)
        .expect(&format!("Failed to open image {}!", path))
        .to_rgb32f();
    let (width, height) = img.dimensions();
    eprintln!("loaded image {}: {}x{}", path, width, height);
    let rgb_vec: Vec<Color> = img.pixels()
        .map(|p| Color::new(p[0] as f64, p[1] as f64, p[2] as f64))
        .collect();
    eprintln!("loaded pixels: {}", rgb_vec.len());
    (width, height, rgb_vec)
}