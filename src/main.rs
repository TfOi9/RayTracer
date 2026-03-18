use raytracer::Point3;
use raytracer::Sphere;
use raytracer::HittableList;
use raytracer::Camera;

fn main() {
    let mut world: HittableList = Vec::new();
    world.push(Box::new(Sphere::new(Point3::new(0.0, 0.0, -1.0), 0.5)));
    world.push(Box::new(Sphere::new(Point3::new(0.0, -100.5, -1.0), 100.0)));

    let cam = Camera::new(16.0 / 9.0, 400);

    cam.render(&world);
}