//! Wall-time evidence for the node_objective deviation bracket work budget
//! (item 1/12, kni-core 0.1.1). Prints measured timings; asserts nothing.
//! Run: cargo run -p kni-core --release --example dev_bracket_bench
use kni_core::lever_api::{NodeBudget, SourceMask};
use kni_core::node_objective::{self, Policy};
use kni_core::reference_slice::{Point, ReferenceRing, Span};
use std::time::Instant;

fn p(x: f64, y: f64) -> Point { Point { x, y } }

fn circle_polygon(n: usize) -> (Vec<ReferenceRing>, SourceMask) {
    let mut ink = vec![255u8; 24 * 24];
    for j in 0..24 { for i in 0..24 {
        let (dx, dy) = (i as f64 - 11.5, j as f64 - 11.5);
        if dx * dx + dy * dy <= 81.0 { ink[j * 24 + i] = 0; }
    } }
    let m = SourceMask { w: 24, h: 24, ink, scale: 1.0, origin: (0.0, 24.0) };
    let pts: Vec<(f64, f64)> = (0..n).map(|i| {
        let t = i as f64 * std::f64::consts::TAU / n as f64;
        ((12.0 + 9.0 * t.cos()).round(), (12.0 + 9.0 * t.sin()).round())
    }).collect();
    let r = ReferenceRing { start: p(pts[0].0, pts[0].1),
        spans: pts[1..].iter().chain(std::iter::once(&pts[0])).map(|&(x, y)| Span::Line { end: p(x, y) }).collect() };
    (vec![r], m)
}

fn main() {
    // Lever-level: candidate-heavy fixture through the full node pass.
    for n in [16usize, 24, 48] {
        let (rings, mask) = circle_polygon(n);
        let budget = NodeBudget { max_nodes: n, max_nodes_per_ring: vec![n] };
        for (pname, policy) in [("strict", Policy::STRICT), ("noise", Policy::NOISE)] {
            let t = Instant::now();
            let r = node_objective::try_apply(&rings, &mask, &budget, policy);
            let dt = t.elapsed();
            match r {
                Ok((out, _)) => println!("lever\tcircle{n}\t{pname}\t{:?}\tnodes {}->{}", dt, n, out[0].spans.len()),
                Err(e) => println!("lever\tcircle{n}\t{pname}\t{:?}\tERR {e:?}", dt),
            }
        }
    }
}
