use crate::color::Color;
use crate::hittable::Hittable;
use crate::utils::degrees_to_radians;
use crate::utils::random_real;
use crate::vec3::Vec3;
use crate::vec3::Point3;
use crate::interval::Interval;
use crate::ray::Ray;

use::rand::RngCore;

use::rayon::prelude::*;
use indicatif::{ProgressBar, ProgressStyle};

pub struct Camera {
    pub aspect_ratio: f64,
    pub image_width: i32,
    pub samples_per_pixel: i32,
    pub max_depth: i32,
    pub vfov: f64,
    pub lookfrom: Point3,
    pub lookat: Point3,
    pub vup: Vec3,
    pub defocus_angle: f64,
    pub focus_dist: f64,
    image_height: i32,
    pixel_sample_scale: f64,
    center: Point3,
    pixel00_loc: Point3,
    pixel_delta_u: Vec3,
    pixel_delta_v: Vec3,
    // u: Vec3,
    // v: Vec3,
    // w: Vec3,
    defocus_disk_u: Vec3,
    defocus_disk_v: Vec3,
}

impl Camera {
    pub fn new(aspect_ratio: f64, image_width: i32, samples_per_pixel: i32, max_depth: i32,
            vfov: f64, lookfrom: Point3, lookat: Point3, vup: Vec3,
            defocus_angle: f64, focus_dist: f64) -> Self {
        let image_height: i32 = ((image_width as f64) / aspect_ratio).max(1.0) as i32;

        let pixel_sample_scale = 1.0 / (samples_per_pixel as f64);

        let theta = degrees_to_radians(vfov);
        let h = (theta / 2.0).tan();
        let viewport_height: f64 = h * 2.0 * focus_dist;
        let viewport_width: f64 = viewport_height * (image_width as f64) / (image_height as f64);
        let center = lookfrom;

        let w = (lookfrom - lookat).unit();
        let u = Vec3::cross(&w, &vup).unit();
        let v = Vec3::cross(&u, &w);

        let viewport_u = viewport_width * u;
        let viewport_v = viewport_height * -v;

        let pixel_delta_u = viewport_u / (image_width as f64);
        let pixel_delta_v = viewport_v / (image_height as f64);

        let viewport_upper_left = center - focus_dist * w
            - viewport_u / 2.0 - viewport_v / 2.0;

        let pixel00_loc = viewport_upper_left + (pixel_delta_u + pixel_delta_v) / 2.0;

        let focus_radius = focus_dist * (degrees_to_radians(defocus_angle / 2.0)).tan();
        let defocus_disk_u = focus_radius * u;
        let defocus_disk_v = focus_radius * v;

        Camera {
            aspect_ratio,
            image_width,
            samples_per_pixel,
            max_depth,
            vfov,
            lookfrom,
            lookat,
            vup,
            defocus_angle,
            focus_dist,
            image_height,
            pixel_sample_scale,
            center,
            pixel00_loc,
            pixel_delta_u,
            pixel_delta_v,
            // u,
            // v,
            // w,
            defocus_disk_u,
            defocus_disk_v,
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

            return Color::new(0.0, 0.0, 0.0);
        }

        let unit_ray = r.direction().unit();
        let a = 0.5 * (unit_ray.y() + 1.0);

        Color::new(1.0, 1.0, 1.0) * (1.0 - a) + Color::new(0.5, 0.7, 1.0) * a
    }

    fn sample_square(rng: &mut dyn RngCore) -> Vec3 {
        Vec3::new(random_real(rng) + 0.5, random_real(rng) + 0.5, 0.0)
    }

    fn sample_defocus_disk(&self, rng: &mut dyn RngCore) -> Vec3 {
        let p = Vec3::random_in_unit_disk(rng);
        self.center + (p.x() * self.defocus_disk_u) + (p.y() * self.defocus_disk_v)
    }

    fn get_ray(&self, i: i32, j: i32, tm: f64, rng: &mut dyn RngCore) -> Ray {
        let offset = Self::sample_square(rng);
        let pixel_sample = self.pixel00_loc
            + self.pixel_delta_u * (i as f64 + offset.x())
            + self.pixel_delta_v * (j as f64 + offset.y());

        let ray_origin = if self.defocus_angle <= 0.0 { self.center } else { self.sample_defocus_disk(rng) };
        let ray_direction = pixel_sample - ray_origin;

        Ray::new(ray_origin, ray_direction, tm)
    }

    pub fn render(&self, world: &dyn Hittable) {
        println!("P3\n{} {}\n255", self.image_width, self.image_height);

        let total_pixels = self.image_width * self.image_height;
        let pixels: Vec<(i32, i32)> = (0..self.image_height)
            .flat_map(|j| (0..self.image_width).map(move |i| (i, j)))
            .collect();

        let pb = ProgressBar::new(total_pixels as u64);
        pb.set_style(ProgressStyle::default_bar()
            .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} ({eta})")
            .unwrap()
            .progress_chars("#>-"));

        let colors: Vec<Color> = pixels
            .par_iter()
            .map(|&(i, j)| {
                let mut rng = rand::thread_rng();
                let mut pixel_color = Color::new(0.0, 0.0, 0.0);
                for _ in 0..self.samples_per_pixel {
                    let ray = self.get_ray(i, j, 0.0, &mut rng);
                    pixel_color += self.ray_color(&ray, world, &mut rng, 0);
                }
                pixel_color *= self.pixel_sample_scale;
                pb.inc(1);

                pixel_color
        }).collect();

        for color in colors {
            color.print_color();
        }

        // for j in 0..self.image_height {
        //     if (self.image_height - j) % 10 == 0 {
        //         eprintln!("{} scanlines remaining...", self.image_height - j);
        //     }
        //     for i in 0..self.image_width {
        //         let mut rng = rand::thread_rng();
        //         let mut pixel_color = Color::new(0.0, 0.0, 0.0);
        //         for _ in 0..self.samples_per_pixel {
        //             let ray = self.get_ray(i, j, random_real(&mut rng), &mut rng);
        //             pixel_color += self.ray_color(&ray, world, &mut rng, 0);
        //         }
        //         pixel_color *= self.pixel_sample_scale;
        //         pixel_color.print_color();
        //     }
        // }

        eprintln!("done.");
    }
}