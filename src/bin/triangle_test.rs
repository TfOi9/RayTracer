use raytracer::Interval;
use raytracer::Lambertian;
use raytracer::Point3;
use raytracer::Ray;
use raytracer::Triangle;
use raytracer::Vec3;
use raytracer::hittable::Hittable;

use std::sync::Arc;

fn main() {}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_triangle() -> Triangle {
        let mat = Arc::new(Lambertian::new(0.8, 0.2, 0.1));
        Triangle::new(
            Point3::new(0.0, 0.0, 0.0),
            Point3::new(1.0, 0.0, 0.0),
            Point3::new(0.0, 1.0, 0.0),
            mat,
        )
    }

    #[test]
    fn hit_from_front_sets_front_face_and_flips_normal_toward_ray() {
        let tri = make_triangle();
        let ray = Ray::new(Point3::new(0.2, 0.2, 1.0), Vec3::new(0.0, 0.0, -1.0), 0.0);

        let rec = tri
            .hit(&ray, Interval::new(0.001, f64::INFINITY))
            .expect("expected a hit from front side");

        assert!(rec.front_face);
        assert!((*ray.direction() * rec.normal) < 0.0);
        assert!((rec.normal.length() - 1.0).abs() < 1e-10);
    }

    #[test]
    fn hit_from_back_marks_back_face_and_keeps_normal_against_ray() {
        let tri = make_triangle();
        let ray = Ray::new(Point3::new(0.2, 0.2, -1.0), Vec3::new(0.0, 0.0, 1.0), 0.0);

        let rec = tri
            .hit(&ray, Interval::new(0.001, f64::INFINITY))
            .expect("expected a hit from back side");

        assert!(!rec.front_face);
        assert!((*ray.direction() * rec.normal) < 0.0);
        assert!((rec.normal.length() - 1.0).abs() < 1e-10);
    }

    #[test]
    fn flat_triangle_bbox_has_non_zero_thickness() {
        let tri = make_triangle();
        let bbox = tri.bounding_box();

        assert!(bbox.z.size() > 0.0);
    }
}
