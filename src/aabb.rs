use crate::interval::Interval;
use crate::vec3::Vec3;
use crate::vec3::Point3;
use crate::ray::Ray;

#[derive(Debug, Clone, Default)]
pub struct AABB {
    pub x: Interval,
    pub y: Interval,
    pub z: Interval
}

impl AABB {
    pub fn new(x: Interval, y: Interval, z: Interval) -> Self {
        Self {
            x,
            y,
            z
        }
    }

    pub fn from_points(a: Point3, b: Point3) -> Self {
        Self {
            x: if a.x() <= b.x() { Interval::new(a.x(), b.x()) } else { Interval::new(b.x(), a.x()) },
            y: if a.y() <= b.y() { Interval::new(a.y(), b.y()) } else { Interval::new(b.y(), a.y()) },
            z: if a.z() <= b.z() { Interval::new(a.z(), b.z()) } else { Interval::new(b.z(), a.z()) }
        }
    }

    pub fn from_aabbs(a: &AABB, b: &AABB) -> Self {
        Self {
            x: Interval::from_intervals(&a.x, &b.x),
            y: Interval::from_intervals(&a.y, &b.y),
            z: Interval::from_intervals(&a.z, &b.z)
        }
    }

    pub fn from_triangle(a: Point3, b: Point3, c: Point3) -> Self {
        let xmin = a.x().min(b.x()).min(c.x());
        let xmax = a.x().max(b.x()).max(c.x());
        let ymin = a.y().min(b.y()).min(c.y());
        let ymax = a.y().max(b.y()).max(c.y());
        let zmin = a.z().min(b.z()).min(c.z());
        let zmax = a.z().max(b.z()).max(c.z());

        let mut x = Interval::new(xmin, xmax);
        let mut y = Interval::new(ymin, ymax);
        let mut z = Interval::new(zmin, zmax);

        let min_axis_size = 1e-8;
        if x.size() < min_axis_size { x = x.expand(min_axis_size); }
        if y.size() < min_axis_size { y = y.expand(min_axis_size); }
        if z.size() < min_axis_size { z = z.expand(min_axis_size); }

        Self {
            x,
            y,
            z
        }
    }

    pub fn axis_interval(&self, n: i32) -> &Interval {
        if n == 1 { return &self.y; }
        else if n == 2 { return &self.z; }
        else { return &self.x; }
    }

    pub fn hit(&self, r: &Ray, ray_t: Interval) -> bool {
        let ray_orig: &Point3 = r.origin();
        let ray_dir: &Vec3 = r.direction();
        let mut result_interval: Interval = ray_t;

        for axis in 0..3 {
            let ax: &Interval = self.axis_interval(axis);
            let adinv: f64 = 1.0 / ray_dir[axis as usize];

            let t0 = (ax.min - ray_orig[axis as usize]) * adinv;
            let t1 = (ax.max - ray_orig[axis as usize]) * adinv;

            if t0 < t1 {
                if t0 > result_interval.min { result_interval.min = t0; }
                if t1 < result_interval.max { result_interval.max = t1; }
            }
            else {
                if t1 > result_interval.min { result_interval.min = t1; }
                if t0 < result_interval.max { result_interval.max = t0; }
            }

            if result_interval.min >= result_interval.max {
                return false;
            }
        }

        true
    }

    pub fn longest_axis(&self) -> i32 {
        if self.x.size() > self.y.size() {
            if self.x.size() > self.z.size() {
                return 0;
            }
            else {
                return 2;
            }
        }
        else {
            if self.y.size() > self.z.size() {
                return 1;
            }
            else {
                return 2;
            }
        }
    }

    pub const EMPTY: AABB = AABB {
        x: Interval::EMPTY,
        y: Interval::EMPTY,
        z: Interval::EMPTY
    };

    pub const UNIVERSE: AABB = AABB {
        x: Interval::UNIVERSE,
        y: Interval::UNIVERSE,
        z: Interval::UNIVERSE
    };
}