//! Node-economy probe (item 1/12 measurement harness): deterministic
//! synthetic fixtures through node_objective::try_apply, printing raw
//! counts per fixture and policy. No font, style or glyph-class knowledge;
//! every number below is a measurement, not a threshold.
//! Run: cargo run -p kni-core --example node_objective_probe
use kni_core::lever_api::{NodeBudget, SourceMask};
use kni_core::node_objective::{self, Policy};
use kni_core::reference_slice::{Point, ReferenceRing, Span};

fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn nodes(r: &ReferenceRing) -> usize { r.spans.len() }

fn square_collinear() -> (Vec<ReferenceRing>, SourceMask) {
    let ring = ReferenceRing { start: p(0., 0.), spans: vec![
        Span::Line { end: p(3., 0.) }, Span::Line { end: p(6., 0.) }, Span::Line { end: p(10., 0.) },
        Span::Line { end: p(10., 5.) }, Span::Line { end: p(10., 10.) },
        Span::Line { end: p(0., 10.) }, Span::Line { end: p(0., 0.) } ] };
    let mut ink = vec![255u8; 144];
    for j in 1..11 { for i in 1..11 { ink[j * 12 + i] = 0; } }
    (vec![ring], SourceMask { w: 12, h: 12, ink, scale: 1.0, origin: (-1.0, 11.0) })
}

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

/// Rounded-corner rectangle: 4 straight edges with collinear extra nodes
/// and 4 quarter-arc cubics, all integer, 100x60 font units.
fn rounded_rect() -> (Vec<ReferenceRing>, SourceMask) {
    let spans = vec![
        Span::Line { end: p(50., 0.) }, Span::Line { end: p(90., 0.) },
        Span::Cubic { control_one: p(96., 0.), control_two: p(100., 4.), end: p(100., 10.) },
        Span::Line { end: p(100., 30.) }, Span::Line { end: p(100., 50.) },
        Span::Cubic { control_one: p(100., 56.), control_two: p(96., 60.), end: p(90., 60.) },
        Span::Line { end: p(50., 60.) }, Span::Line { end: p(10., 60.) },
        Span::Cubic { control_one: p(4., 60.), control_two: p(0., 56.), end: p(0., 50.) },
        Span::Line { end: p(0., 30.) }, Span::Line { end: p(0., 10.) },
        Span::Cubic { control_one: p(0., 4.), control_two: p(4., 0.), end: p(10., 0.) },
    ];
    let ring = ReferenceRing { start: p(10., 0.), spans };
    let mut ink = vec![255u8; 120 * 80];
    for j in 5..75 { for i in 5..115 {
        let x = i as f64; let y = 80.0 - j as f64;
        let inside = (x >= 10.0 && x <= 90.0 && y >= 0.0 && y <= 60.0)
            || (x > 90.0 && x <= 100.0 && y >= 10.0 && y <= 50.0)
            || (x >= 0.0 && x < 10.0 && y >= 10.0 && y <= 50.0)
            || ((x - 90.0).powi(2) + (y - 50.0).powi(2) <= 100.0 && x > 90.0 && y > 50.0)
            || ((x - 10.0).powi(2) + (y - 50.0).powi(2) <= 100.0 && x < 10.0 && y > 50.0)
            || ((x - 90.0).powi(2) + (y - 10.0).powi(2) <= 100.0 && x > 90.0 && y < 10.0)
            || ((x - 10.0).powi(2) + (y - 10.0).powi(2) <= 100.0 && x < 10.0 && y < 10.0);
        if inside { ink[j * 120 + i] = 0; }
    } }
    (vec![ring], SourceMask { w: 120, h: 80, ink, scale: 1.0, origin: (0.0, 80.0) })
}

fn main() {
    println!("fixture\tpolicy\tnodes_before\tnodes_after\tremovals\tarea_before\tarea_after\tc2_missing");
    for (name, (rings, mask)) in [
        ("square_collinear", square_collinear()),
        ("circle_polygon_16", circle_polygon(16)),
        ("circle_polygon_24", circle_polygon(24)),
        ("rounded_rect", rounded_rect()),
    ] {
        let before: usize = rings.iter().map(nodes).sum();
        let budget = NodeBudget { max_nodes: before, max_nodes_per_ring: rings.iter().map(nodes).collect() };
        for (pname, policy) in [("strict", Policy::STRICT), ("half-noise", Policy::HALF_NOISE), ("noise", Policy::NOISE)] {
            match node_objective::try_apply(&rings, &mask, &budget, policy) {
                Ok((out, report)) => {
                    let after: usize = out.iter().map(nodes).sum();
                    println!("{name}\t{pname}\t{before}\t{after}\t{}\t{:.6}\t{:.6}\t{}",
                        before - after, report.area_before, report.area_after, report.c2_missing);
                }
                Err(e) => println!("{name}\t{pname}\t{before}\tERR\tERR\tERR\tERR\t{e:?}"),
            }
        }
    }
}
