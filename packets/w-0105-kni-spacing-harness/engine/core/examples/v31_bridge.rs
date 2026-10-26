// v3.1 fixture consumer bridge (option C, ring-only): one ring per run.
// stdin:  n\n (x y)*n\n k\n (c0 .. ck on one line; k=-1: engine detects)
// stdout: FALLBACK <0|1>\nNSPANS <m>\n then per span "L x y" | "C x1 y1 x2 y2 x y"
// Coordinates are source units as given; policy squared_error = 1.0
// (fixture retained_residual_budget 1.0 source-px), t_line = derived 1.0.
use kni_core::capture::corners;
use kni_core::capture_fit::fit_ring;
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::{Point, Span};
use std::io::Read;

fn main() {
    let mut buf = String::new();
    std::io::stdin().read_to_string(&mut buf).unwrap();
    let mut it = buf.split_whitespace();
    let n: usize = it.next().unwrap().parse().unwrap();
    let pts: Vec<Point> = (0..n)
        .map(|_| Point {
            x: it.next().unwrap().parse().unwrap(),
            y: it.next().unwrap().parse().unwrap(),
        })
        .collect();
    let k: i64 = it.next().unwrap().parse().unwrap();
    let cr: Vec<usize> = if k < 0 {
        corners(&pts)
    } else {
        (0..k).map(|_| it.next().unwrap().parse().unwrap()).collect()
    };
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let (ring, _ns, fb) = fit_ring(pts, cr, &policy);
    println!("START {:.6} {:.6}", ring.start.x, ring.start.y);
    println!("FALLBACK {}", if fb { 1 } else { 0 });
    println!("NSPANS {}", ring.spans.len());
    for s in &ring.spans {
        match s {
            Span::Line { end } => println!("L {:.6} {:.6}", end.x, end.y),
            Span::Cubic { control_one, control_two, end } => println!(
                "C {:.6} {:.6} {:.6} {:.6} {:.6} {:.6}",
                control_one.x, control_one.y, control_two.x, control_two.y, end.x, end.y
            ),
        }
    }
}
