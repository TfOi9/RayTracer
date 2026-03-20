use raytracer::Vec3;
use raytracer::Color;
use raytracer::Dielectric;
use raytracer::Point3;
use raytracer::Sphere;
use raytracer::HittableList;
use raytracer::Camera;
use raytracer::Lambertian;
use raytracer::Metal;
use raytracer::utils::random_real;
use raytracer::utils::random_real_interval;

use std::sync::Arc;

fn main() {
    let mut world: HittableList = Vec::new();

    let material_ground = Arc::new(Lambertian::new(0.5, 0.5, 0.5));
    world.push(Box::new(Sphere::new(Point3::new(0.0, -1000.0, -1.0), 1000.0, material_ground)));

    let mut rng = rand::thread_rng();

    for a in -11..11 {
        for b in -11..11 {
            let choose_mat = random_real(&mut rng);
            let center = Point3::new(
                (a as f64) + 0.9 * random_real(&mut rng),
                0.2,
                (b as f64) + 0.9 * random_real(&mut rng)
            );

            if (center - Point3::new(4.0, 0.2, 0.0)).length() > 0.9 {
                if choose_mat < 0.8 {
                    let color = Color::new(random_real(&mut rng), random_real(&mut rng), random_real(&mut rng));
                    let albedo = color.hadamard_product(color);
                    let material_sphere = Arc::new(Lambertian::from_color(albedo));
                    let center1 = center + Vec3::new(0.0, random_real_interval(&mut rng, 0.0, 0.5), 0.0);
                    world.push(Box::new(Sphere::new_moving(center, center1, 0.2, material_sphere)));
                }
                else if choose_mat < 0.95 {
                    let color = Color::new(
                        random_real_interval(&mut rng, 0.5, 1.0),
                        random_real_interval(&mut rng, 0.5, 1.0),
                        random_real_interval(&mut rng, 0.5, 1.0)
                    );
                    let fuzz = random_real_interval(&mut rng, 0.0, 0.5);
                    let material_sphere = Arc::new(Metal::from_color(color, fuzz));
                    world.push(Box::new(Sphere::new(center, 0.2, material_sphere)));
                }
                else {
                    let material_sphere = Arc::new(Dielectric::new(1.5));
                    world.push(Box::new(Sphere::new(center, 0.2, material_sphere)));
                }
            }
        }
    }

    let material1 = Arc::new(Dielectric::new(1.5));
    world.push(Box::new(Sphere::new(Point3::new(0.0,1.0, 0.0), 1.0, material1)));

    let material2 = Arc::new(Lambertian::new(0.4, 0.2, 0.1));
    world.push(Box::new(Sphere::new(Point3::new(-4.0,1.0, 0.0), 1.0, material2)));

    let material3 = Arc::new(Metal::new(0.7, 0.6, 0.5, 0.0));
    world.push(Box::new(Sphere::new(Point3::new(4.0,1.0, 0.0), 1.0, material3)));

    let cam = Camera::new(16.0 / 9.0, 1200,
            500, 50, 20.0,
            Point3::new(-13.0, 2.0, 3.0),
            Point3::new(0.0, 0.0, 0.0),
            Vec3::new(0.0, 1.0, 0.0),
            0.6, 10.0);

    cam.render(&world);
}