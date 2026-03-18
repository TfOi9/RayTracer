use raytracer::Vec3;
use raytracer::Point3;
use raytracer::Color;
use raytracer::Ray;

fn ray_color(r: &Ray) -> Color {
    let unit_ray = r.direction().unit();
    let a = 0.5 * (unit_ray.y() + 1.0);
    Color::new(1.0, 1.0, 1.0) * (1.0 - a) + Color::new(0.5, 0.7, 1.0) * a
}

fn main() {
    let aspect_ratio: f64 = 16.0 / 9.0;
    let image_width: i32 = 400;
    let image_height: i32 = ((image_width as f64) / aspect_ratio).max(1.0) as i32;

    let focal_length: f64 = 1.0;
    let viewport_height: f64 = 2.0;
    let viewport_width: f64 = viewport_height * (image_width as f64) / (image_height as f64);
    let camera_center = Point3::new(0.0, 0.0, 0.0);

    let viewport_u = Vec3::new(viewport_width, 0.0, 0.0);
    let viewport_v = Vec3::new(0.0, -viewport_height, 0.0);

    let pixel_delta_u = viewport_u / (image_width as f64);
    let pixel_delta_v = viewport_v / (image_height as f64);

    let viewport_upper_left = camera_center - Vec3::new(0.0, 0.0, focal_length)
        - viewport_u / 2.0 - viewport_v / 2.0;

    let pixel00_loc = viewport_upper_left + (pixel_delta_u + pixel_delta_v) / 2.0;

    println!("P3\n{} {}\n255", image_width, image_height);

    for j in 0..image_height {
        for i in 0..image_width {
            let pixel_center = pixel00_loc + pixel_delta_u * (i as f64) + pixel_delta_v * (j as f64);
            let ray_direction = pixel_center - camera_center;

            let ray = Ray::new(camera_center.clone(), ray_direction);
            let pixel_color = ray_color(&ray);

            pixel_color.print_color();
        }
    }

}
