use raytracer::Vec3;
use raytracer::Dielectric;
use raytracer::Point3;
use raytracer::Sphere;
use raytracer::HittableList;
use raytracer::Camera;
use raytracer::Lambertian;
use raytracer::Metal;

use std::rc::Rc;

fn main() {
    let mut world: HittableList = Vec::new();

    let material_ground = Rc::new(Lambertian::new(0.8, 0.8, 0.0));
    let material_center = Rc::new(Lambertian::new(0.1, 0.2, 0.5));
    let material_left = Rc::new(Dielectric::new(1.5));
    let material_bubble = Rc::new(Dielectric::new(1.0 / 1.5));
    let material_right = Rc::new(Metal::new(0.8, 0.6, 0.2, 1.0));

    world.push(Box::new(Sphere::new(Point3::new(0.0, -100.5, -1.0), 100.0, material_ground)));
    world.push(Box::new(Sphere::new(Point3::new(0.0, 0.0, -1.2), 0.5, material_center)));
    world.push(Box::new(Sphere::new(Point3::new(-1.0, 0.0, -1.0), 0.5, material_left)));
    world.push(Box::new(Sphere::new(Point3::new(-1.0, 0.0, -1.0), 0.4, material_bubble)));
    world.push(Box::new(Sphere::new(Point3::new(1.0, 0.0, -1.0), 0.5, material_right)));

    let cam = Camera::new(16.0 / 9.0, 800,
            100, 50, 20.0,
            Point3::new(-2.0, 2.0, 1.0),
            Point3::new(0.0, 0.0, -1.0),
            Vec3::new(0.0, 1.0, 0.0));

    cam.render(&world);
}