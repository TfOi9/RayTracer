pub use crate::color::Color;
pub use crate::material::Material;
use crate::utils::{self, cos_theta, tan_theta};
pub use crate::vec3::Vec3;
pub use crate::utils::PI;

pub struct DisneyBSDF {
    pub base_color: Color,
    pub subsurface: f64,
    pub metallic: f64,
    pub specular: f64,
    pub specular_tint: f64,
    pub roughness: f64,
    pub anisotropic: f64,
    pub sheen: f64,
    pub sheen_tint: f64,
    pub clearcoat: f64,
    pub clearcoat_gloss: f64,
    pub transmission: f64,
    pub ior: f64
}

impl DisneyBSDF {
    pub fn new(base_color: Color, subsurface: f64, metallic: f64, specular: f64, specular_tint: f64,
            roughness: f64, anisotropic: f64, sheen: f64, sheen_tint: f64, clearcoat: f64, clearcoat_gloss: f64,
            transmission: f64, ior: f64) -> Self {
        Self {
            base_color,
            subsurface,
            metallic,
            specular,
            specular_tint,
            roughness,
            anisotropic,
            sheen,
            sheen_tint,
            clearcoat,
            clearcoat_gloss,
            transmission,
            ior
        }
    }

    pub fn calculate_tint(basecolor: &Color) -> Vec3 {
        let luminance: f64 = Vec3::new(0.3, 0.6, 1.0) * *basecolor;
        if luminance > 0.0 {
            return *basecolor * (1.0 / luminance);
        }
        else {
            return Vec3::new(0.0, 0.0, 0.0);
        }
    }

    pub fn evaluate_sheen(&self, _wo: &Vec3, wm: &Vec3, wi: &Vec3) -> Vec3 {
        if self.sheen <= 0.0 {
            return Vec3::new(0.0, 0.0, 0.0);
        }

        let dothl = *wm * *wi;
        let tint = DisneyBSDF::calculate_tint(&self.base_color);
        self.sheen * utils::lerp(Vec3::new(1.0, 1.0, 1.0), tint, self.sheen_tint) * utils::schlick_weight(dothl)
    }

    pub fn gtr1(absdothl: f64, a: f64) -> f64 {
        if a >= 1.0 {
            return 1.0 / PI;
        }

        let a2 = a * a;
        (a2 - 1.0) / (PI * a2.log2() * (1.0 + (a2 - 1.0) * absdothl * absdothl))
    }

    pub fn separable_smith_ggxg1(w: &Vec3, a: f64) -> f64 {
        let a2 = a * a;
        let absdotnv = w.z().abs();

        2.0 / (1.0 + (a2 + (1.0 - a2) * absdotnv * absdotnv).sqrt())
    }

    pub fn evaluate_clearcoat(clearcoat: f64, alpha: f64, wo: &Vec3, wm: &Vec3, wi: &Vec3,
            fpdfw: &mut f64, rpdfw: &mut f64) -> f64 {
        if clearcoat <= 0.0 {
            return 0.0;
        }

        let absdotnh = wm.z().abs();
        let absdotnl = wi.z().abs();
        let absdotnv = wo.z().abs();
        let dothl = *wm * *wi;

        let d = DisneyBSDF::gtr1(absdotnh, 0.1 - 0.099 * alpha);
        let f = utils::schlick(0.04, dothl);
        let gl = DisneyBSDF::separable_smith_ggxg1(wi, 0.25);
        let gv = DisneyBSDF::separable_smith_ggxg1(wo, 0.25);

        *fpdfw = d / (4.0 * absdotnl);
        *rpdfw = d / (4.0 * absdotnv);

        0.25 * clearcoat * d * f * gl * gv
    }

    pub fn ggx_anisotropic_d(wm: &Vec3, ax: f64, ay: f64) -> f64 {
        let dothx2 = wm.x() * wm.x();
        let dothy2 = wm.z() * wm.z();
        let cos_2theta = utils::cos_2theta(wm);
        let ax2 = ax * ax;
        let ay2 = ay * ay;

        let temp = dothx2 / ax2 + dothy2 / ay2 + cos_2theta;
        1.0 / (PI * ax * ay * temp * temp)
    }

    pub fn separable_smith_ggxg1_2(w: &Vec3, wm: &Vec3, ax: f64, ay: f64) -> f64 {
        let dothw = *w * *wm;
        if dothw <= 0.0 {
            return 0.0;
        }

        let abstantheta = tan_theta(w).abs();
        if abstantheta > 1e10 {
            return 0.0;
        }

        let a = (utils::cos_2phi(w) * ax * ax + utils::sin_2phi(w) * ay * ay).sqrt();
        let a_tan_2theta = a * abstantheta;
        let a2tan_2theta = a_tan_2theta * a_tan_2theta;

        let lambda = 0.5 * (-1.0 + (1.0 + a2tan_2theta).sqrt());
        1.0 / (1.0 + lambda)
    }
}