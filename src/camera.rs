use crate::color::Color;
use crate::hittable::Hittable;
use crate::utils::random_real;
use crate::vec3::Vec3;
use crate::vec3::Point3;
use crate::interval::Interval;
use crate::ray::Ray;

use::rand::RngCore;

pub struct Camera {
    pub aspect_ratio: f64,
    pub image_width: i32,
    pub samples_per_pixel: i32,
    pub max_depth: i32,
    image_height: i32,
    pixel_sample_scale: f64,
    center: Point3,
    pixel00_loc: Point3,
    pixel_delta_u: Vec3,
    pixel_delta_v: Vec3
}

impl Camera {
    pub fn new(aspect_ratio: f64, image_width: i32, samples_per_pixel: i32, max_depth: i32) -> Self {
        let image_height: i32 = ((image_width as f64) / aspect_ratio).max(1.0) as i32;

        let pixel_sample_scale = 1.0 / (samples_per_pixel as f64);

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
            samples_per_pixel,
            max_depth,
            image_height,
            pixel_sample_scale,
            center,
            pixel00_loc,
            pixel_delta_u,
            pixel_delta_v
        }
    }

    fn ray_color(&self, r: &Ray, world: &dyn Hittable, rng: &mut dyn RngCore, dep: i32) -> Color {
        if dep >= self.max_depth {
            return Color::new(0.0, 0.0, 0.0);
        }

        if let Some(rec) = world.hit(r, Interval::PSEUDO_POSITIVE) {
            if let Some((attenuation, scattered)) = rec.mat.scatter(r, &rec, rng) {
                return attenuation.hadamard_product(self.ray_color(&scattered, world, rng, dep + 1));
            }

            Color::new(0.0, 0.0, 0.0);
            // let direction = Vec3::random_unit_on_hemishpere(&rec.normal, rng) + rec.normal;
            // return self.ray_color(&Ray::new(rec.p, direction), world, rng, dep + 1) * 0.5;
        }

        let unit_ray = r.direction().unit();
        let a = 0.5 * (unit_ray.y() + 1.0);

        Color::new(1.0, 1.0, 1.0) * (1.0 - a) + Color::new(0.5, 0.7, 1.0) * a
    }

    fn sample_square(rng: &mut dyn RngCore) -> Vec3 {
        Vec3::new(random_real(rng) + 0.5, random_real(rng) + 0.5, 0.0)
    }

    fn get_ray(&self, i: i32, j: i32, rng: &mut dyn RngCore) -> Ray {
        let offset = Self::sample_square(rng);
        let pixel_sample = self.pixel00_loc
            + self.pixel_delta_u * (i as f64 + offset.x())
            + self.pixel_delta_v * (j as f64 + offset.y());

        let ray_origin = self.center;
        let ray_direction = pixel_sample - ray_origin;

        Ray::new(ray_origin, ray_direction)
    }

    pub fn render(&self, world: &dyn Hittable) {
        println!("P3\n{} {}\n255", self.image_width, self.image_height);

        for j in 0..self.image_height {
            if (self.image_height - j) % 10 == 0 {
                eprintln!("{} scanlines remaining...", self.image_height - j);
            }
            for i in 0..self.image_width {
                let mut rng = rand::thread_rng();
                let mut pixel_color = Color::new(0.0, 0.0, 0.0);
                for _ in 0..self.samples_per_pixel {
                    let ray = self.get_ray(i, j, &mut rng);
                    pixel_color += self.ray_color(&ray, world, &mut rng, 0);
                }
                pixel_color *= self.pixel_sample_scale;
                pixel_color.print_color();
            }
        }

        eprintln!("done.");
    }
}