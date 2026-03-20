use raytracer::Vec3;
use raytracer::Point3;
use raytracer::Ray;

fn main() {
    let orig = Point3::new(0.0, 0.0, 0.0);
    let dir = Vec3::new(1.0, 1.0, 2.0);

    let ray1 = Ray::new(orig, dir, 0.0);
    println!("{:?}", ray1);

    let ray2 = Ray::from_coordinates(1.0, -1.0, 0.0, 2.0, 3.0, -4.0, 0.0);
    println!("{:?}", ray2);

    println!("{:?}", ray2.origin());
    println!("{:?}", ray2.direction());

    println!("{:?}", ray1.at(1.0));
    println!("{:?}", ray2.at(-2.0));
}
