use raytracer::Color;

fn main() {
    let width : u32 = 256;
    let height : u32 = 256;

    println!("P3\n{} {}\n255", width, height);

    for i in 0..width {
        for j in 0..height {
            let col = Color::new(
                (i as f64) / ((width - 1) as f64),
                (j as f64) / ((height - 1) as f64),
                0.0);
            println!("{}", col);
        }
    }

    eprintln!("done.");
}
