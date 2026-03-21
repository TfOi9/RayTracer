pub use rand::Rng;

use crate::utils::random_real_interval;
pub use crate::vec3::Vec3;
pub use crate::vec3::Point3;
pub use crate::utils;

pub struct Perlin {
    randfloat: [f64; 256],
    randvec: [Vec3; 256],
    perm_x: [i32; 256],
    perm_y: [i32; 256],
    perm_z: [i32; 256]
}

impl Perlin {
    fn permute(p: &mut [i32], n: usize) {
        let mut rng = rand::thread_rng();
        for i in (0..n).rev() {
            let target: usize = rng.gen_range(0..=i);
            let temp = p[i];
            p[i] = p[target];
            p[target] = temp;
        }
    }

    fn perlin_generate_perm(p: &mut [i32]) {
        for i in 0..256 {
            p[i as usize] = i;
        }

        Self::permute(p, 256);
    }

    pub fn new() -> Self {
        let mut rng = rand::thread_rng();

        let mut randfloat = [0.0; 256];
        for i in 0..256 {
            randfloat[i] = rng.r#gen();
        }

        let mut randvec = [Vec3::default(); 256];
        for i in 0..256 {
            randvec[i] = Vec3::new(
                random_real_interval(&mut rng, -1.0, 1.0),
                random_real_interval(&mut rng, -1.0, 1.0),
                random_real_interval(&mut rng, -1.0, 1.0)
            ).unit();
        }

        let mut perm_x = [0; 256];
        let mut perm_y = [0; 256];
        let mut perm_z = [0; 256];

        Self::perlin_generate_perm(&mut perm_x);
        Self::perlin_generate_perm(&mut perm_y);
        Self::perlin_generate_perm(&mut perm_z);

        Self {
            randfloat,
            randvec,
            perm_x,
            perm_y,
            perm_z
        }
    }

    pub fn noise(&self, p: &Point3) -> f64 {
        let u = p.x() - p.x().floor();
        let v = p.y() - p.y().floor();
        let w = p.z() - p.z().floor();

        let i = (p.x().floor()) as i32;
        let j = (p.y().floor()) as i32;
        let k = (p.z().floor()) as i32;

        let mut c = [[[Vec3::default(); 2]; 2]; 2];
        for di in 0..2 {
            for dj in 0..2 {
                for dk in 0..2 {
                    c[di][dj][dk] = self.randvec[
                       (self.perm_x[((i + di as i32) & 255) as usize] ^
                        self.perm_y[((j + dj as i32) & 255) as usize] ^
                        self.perm_z[((k + dk as i32) & 255) as usize]) as usize
                    ];
                }
            }
        }

        Self::perlin_interp(&c, u, v, w)
    }

    fn perlin_interp(c: &[[[Vec3; 2]; 2]; 2], u: f64, v: f64, w: f64) -> f64 {
        let uu = u * u * (3.0 - 2.0 * u);
        let vv = v * v * (3.0 - 2.0 * v);
        let ww = w * w * (3.0 - 2.0 * w);

        let mut accum: f64 = 0.0;
        for i in 0..2 {
            for j in 0..2 {
                for k in 0..2 {
                    let weight_v = Vec3::new(u - i as f64, v - j as f64, w - k as f64);
                    accum += ((i as f64) * uu + ((1 - i) as f64) * (1.0 - uu))
                           * ((j as f64) * vv + ((1 - j) as f64) * (1.0 - vv))
                           * ((k as f64) * ww + ((1 - k) as f64) * (1.0 - ww))
                           * c[i][j][k] * weight_v;
                }
            }
        }
        accum
    }
}