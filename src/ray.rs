use crate::vec3::Vec3;
use crate::vec3::Point3;

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Ray {
    orig: Point3,
    dir: Vec3,
    tm: f64
}

impl Ray {
    pub fn new(orig: Point3, dir: Vec3, tm: f64) -> Self {
        Self {
            orig,
            dir,
            tm
        }
    }

    pub fn from_coordinates(origx: f64, origy: f64, origz: f64, dirx: f64, diry: f64, dirz: f64, tm: f64) -> Self {
        Self {
            orig: Point3::new(origx, origy, origz),
            dir: Vec3::new(dirx, diry, dirz),
            tm
        }
    }

    pub fn origin(&self) -> &Point3 {
        &self.orig
    }

    pub fn direction(&self) -> &Vec3 {
        &self.dir
    }

    pub fn time(&self) -> f64 {
        self.tm
    }

    pub fn at(&self, t: f64) -> Point3 {
        self.orig + self.dir * t
    }
}