use crate::color::Color;
use crate::hittable::Hittable;
use crate::vec3::Vec3;
use crate::vec3::Point3;
use crate::interval::Interval;
use crate::ray::Ray;

pub struct Camera {
    pub aspect_ratio: f64,
    pub image_width: i32,
    image_height: i32,
    center: Point3,
    pixel00_loc: Point3,
    pixel_delta_u: Vec3,
    pixel_delta_v: Vec3
}

impl Camera {
    pub fn new(aspect_ratio: f64, image_width: i32) -> Self {
        let image_height: i32 = ((image_width as f64) / aspect_ratio).max(1.0) as i32;

        let focal_length: f64 = 1.0;
        let viewport_height: f64 = 2.0;
        let viewport_width: f64 = viewport_height * (image_width as f64) / (image_height as f64);
        let center = Point3::new(0.0, 0.0, 0.0);

        let viewport_u = Vec3::new(viewport_width, 0.0, 0.0);
        let viewport_v = Vec3::new(0.0, -viewport_height, 0.0);

        let pixel_delta_u = viewport_u / (image_width as f64);
        let pixel_delta_v = viewport_v / (image_height as f64);

        let viewport_upper_left = center - Vec3::new(0.0, 0.0, focal_length)
            - viewport_u / 2.0 - viewport_v / 2.0;

        let pixel00_loc = viewport_upper_left + (pixel_delta_u + pixel_delta_v) / 2.0;

        Camera {
            aspect_ratio,
            image_width,
            image_height,
            center,
            pixel00_loc,
            pixel_delta_u,
            pixel_delta_v
        }
    }

    fn ray_color(&self, r: &Ray, world: &dyn Hittable) -> Color {
        if let Some(rec) = world.hit(r, Interval::POSITIVE) {
            return (rec.normal + Color::new(1.0, 1.0, 1.0)) * 0.5;
        }

        let unit_ray = r.direction().unit();
        let a = 0.5 * (unit_ray.y() + 1.0);

        Color::new(1.0, 1.0, 1.0) * (1.0 - a) + Color::new(0.5, 0.7, 1.0) * a
    }

    pub fn render(&self, world: &dyn Hittable) {
        println!("P3\n{} {}\n255", self.image_width, self.image_height);

        for j in 0..self.image_height {
            for i in 0..self.image_width {
                let pixel_center = self.pixel00_loc
                    + self.pixel_delta_u * (i as f64) + self.pixel_delta_v * (j as f64);
                let ray_direction = pixel_center - self.center;

                let ray = Ray::new(self.center.clone(), ray_direction);
                let pixel_color = self.ray_color( &ray, world);

                pixel_color.print_color();
            }
        }
    }
}