use crate::image_parser::parse_image;
pub use crate::vec3::Point3;
pub use crate::color::Color;
pub use crate::interval::Interval;
pub use crate::image_parser;

pub use std::sync::Arc;
pub use std::vec::Vec;

pub trait Texture: Send + Sync {
    fn color_at(&self, u: f64, v: f64, p: &Point3) -> Color;
}

pub struct SolidColor {
    albedo: Color
}

pub struct CheckerTexture {
    inv_scale: f64,
    odd: Arc<dyn Texture>,
    even: Arc<dyn Texture>
}

pub struct ImageTexture {
    image: (u32, u32, Vec<Color>)
}

impl SolidColor {
    pub fn new(albedo: Color) -> Self {
        Self {albedo}
    }
}

impl Texture for SolidColor {
    fn color_at(&self, _u: f64, _v: f64, _p: &Point3) -> Color {
        self.albedo
    }
}

impl CheckerTexture {
    pub fn new(scale: f64, odd: Arc<dyn Texture>, even: Arc<dyn Texture>) -> Self {
        Self {
            inv_scale: 1.0 / scale,
            odd: odd.clone(),
            even: even.clone()
        }
    }

    pub fn from_colors(scale: f64, odd_color: Color, even_color: Color) -> Self {
        Self {
            inv_scale: 1.0 / scale,
            odd: Arc::new(SolidColor::new(odd_color)),
            even: Arc::new(SolidColor::new(even_color))
        }
    }
}

impl Texture for CheckerTexture {
    fn color_at(&self, u: f64, v: f64, p: &Point3) -> Color {
        let ix = (self.inv_scale * p.x()).floor() as i32;
        let iy = (self.inv_scale * p.y()).floor() as i32;
        let iz = (self.inv_scale * p.z()).floor() as i32;

        if (ix + iy + iz) % 2 == 0 {
            return self.even.color_at(u, v, p);
        }
        else {
            return self.odd.color_at(u, v, p);
        }
    }
}

impl ImageTexture {
    pub fn new(path: &str) -> Self {
        Self {
            image: parse_image(path)
        }
    }

    pub fn width(&self) -> u32 {
        self.image.0
    }

    pub fn height(&self) -> u32 {
        self.image.1
    }

    pub fn pixel(&self, i: usize, j: usize) -> Color {
        let index = j * self.image.0 as usize + i;
        if index >= self.image.2.len() {
            eprintln!("err at idx {}, i = {}, j = {}", index, i, j);
            return Color::new(0.0, 1.0, 1.0);
        }

        self.image.2[index]
    }
}

impl Texture for ImageTexture {
    fn color_at(&self, u: f64, v: f64, _p: &Point3) -> Color {
        if self.width() == 0 || self.height() == 0 {
            return Color::new(0.0, 1.0, 1.0);
        }

        let u = Interval::new(0.0, 1.0).clamp(u);
        let v = 1.0 - Interval::new(0.0, 1.0).clamp(v);

        let i = (u * self.width() as f64) as usize;
        let j = (v * self.height() as f64) as usize;
        let i = i.min((self.width() - 1) as usize);
        let j = j.min((self.height() - 1) as usize);
        let pixel = self.pixel(i, j);

        // parse_image uses rgb32f; values are already in [0, 1].
        pixel
    }
}