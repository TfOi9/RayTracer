use raytracer::Vec3;

fn main() {
    let v1 = Vec3::new(2.0, 5.0, -1.0);
    let v2 = Vec3::new(1.0, 2.0, 3.0);

    println!("x = {}, y = {}, z = {}", v1.x(), v1.y(), v1.z());

    println!("{:?}", v1 + v2);

    let v3 = Vec3::new(3.0, 4.0, 0.0);
    println!("length is {}", v3.length());

    println!("{:?}", v3.components());

    let v4 = v3 * 3.0;
    println!("{:?}", v4);

    let v5 = v1 * v4;
    println!("{:?}", v5);

    let mut m1 = Vec3::new(1.0, 2.0, -1.0);
    m1 += Vec3::new(1.0, 1.0, 1.0);
    println!("{:?}", m1);

    m1 -= Vec3::new(1.0, 1.0, 1.0);
    println!("{:?}", m1);

    println!("v1[1] = {}", v1[1]);

    m1[0] = 0.0;
    println!("m1[0] = {}", m1[0]);

    m1 = Vec3::cross(&v1, &v2);
    println!("{:?}", m1);

    m1 = -m1;
    println!("{:?}", m1);

    let v6 = -v4;
    println!("{:?}", v6);

}
