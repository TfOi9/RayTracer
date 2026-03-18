use crate::vec3::Vec3;
use crate::vec3::Point3;

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Ray {
    orig: Point3,
    dir: Vec3
}

impl Ray {
    pub fn new(orig: Point3, dir: Vec3) -> Self {
        Self {
            orig: orig,
            dir: dir
        }
    }

    pub fn from_coordinates(origx: f64, origy: f64, origz: f64, dirx: f64, diry: f64, dirz: f64) -> Self {
        Self {
            orig: Point3::new(origx, origy, origz),
            dir: Vec3::new(dirx, diry, dirz)
        }
    }

    pub fn origin(&self) -> &Point3 {
        &self.orig
    }

    pub fn direction(&self) -> &Vec3 {
        &self.dir
    }

    pub fn at(&self, t: f64) -> Point3 {
        self.orig + self.dir * t
    }
}