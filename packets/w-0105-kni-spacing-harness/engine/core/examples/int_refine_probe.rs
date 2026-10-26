//! Probe: runs int_refine on text-dumped canonical rings (see ~/w/probe) against the tile PNG.
use kni_core::{capture::decode_png_gray, int_refine::try_apply, lever_api::*,
    reference_slice::{Point, ReferenceRing, Span}};
fn rd(path: &str, ysign: f64) -> (ReferenceRing, Vec<ReferenceRing>, SourceMask) {
    let t = std::fs::read_to_string(path).unwrap();
    let mut rings: Vec<ReferenceRing> = vec![];
    let mut m = None;
    for l in t.lines() {
        let v: Vec<&str> = l.split_whitespace().collect();
        let f = |i: usize| v[i].parse::<f64>().unwrap();
        match v[0] {
            "H" => {
                let (k, ox, oy, tx, ty) = (f(1), f(2), f(3), f(4), f(5));
                let png = std::fs::read(v[6]).unwrap();
                let (w, h, mut g) = decode_png_gray(&png).unwrap();
                if let Ok(t) = std::env::var("PROBE_THR") { let t: u8 = t.parse().unwrap(); for b in g.iter_mut() { *b = if *b < t { 0 } else { 255 }; } }
                m = Some(SourceMask { w, h, ink: g, scale: k, origin: (tx - ox * k, ty - ysign * oy * k) });
            }
            "R" => rings.push(ReferenceRing { start: Point { x: f(1), y: f(2) }, spans: vec![] }),
            "L" => rings.last_mut().unwrap().spans.push(Span::Line { end: Point { x: f(1), y: f(2) } }),
            "C" => rings.last_mut().unwrap().spans.push(Span::Cubic {
                control_one: Point { x: f(1), y: f(2) }, control_two: Point { x: f(3), y: f(4) }, end: Point { x: f(5), y: f(6) } }),
            _ => {}
        }
    }
    (rings[0].clone(), rings, m.unwrap())
}
fn hex(rings: &[ReferenceRing]) -> String {
    use kni_core::{cff_container::{charstring, CffGlyph}, reference_slice::DrawnGlyph};
    let g = CffGlyph { name: "p".into(), advance: 0, outline: DrawnGlyph { glyph_id: "p".into(), rings: rings.to_vec() } };
    charstring(&g).unwrap().iter().map(|b| format!("{:02x}", b)).collect()
}
fn dump(rings: &[ReferenceRing]) -> String {
    let mut s = String::new();
    for r in rings { s += &format!("R {} {}\n", r.start.x, r.start.y);
        for sp in &r.spans { match sp {
            Span::Line { end } => s += &format!("L {} {}\n", end.x, end.y),
            Span::Cubic { control_one: a, control_two: b, end } => s += &format!("C {} {} {} {} {} {}\n", a.x, a.y, b.x, b.y, end.x, end.y) } } }
    s
}
fn main() {
    if std::env::args().nth(1).as_deref() == Some("c2") {
        // c2 FILE... : prints missing_extrema per ring file (rd() needs H line; reads rings only)
        for f in std::env::args().skip(2) {
            let t = std::fs::read_to_string(&f).unwrap();
            let mut rings: Vec<ReferenceRing> = vec![];
            for l in t.lines() { let v: Vec<&str> = l.split_whitespace().collect(); if v.is_empty() { continue; }
                let g = |i: usize| v[i].parse::<f64>().unwrap();
                match v[0] { "R" => rings.push(ReferenceRing { start: Point { x: g(1), y: g(2) }, spans: vec![] }),
                  "L" => rings.last_mut().unwrap().spans.push(Span::Line { end: Point { x: g(1), y: g(2) } }),
                  "C" => rings.last_mut().unwrap().spans.push(Span::Cubic { control_one: Point { x: g(1), y: g(2) }, control_two: Point { x: g(3), y: g(4) }, end: Point { x: g(5), y: g(6) } }),
                  _ => {} } }
            println!("{} {}", f, missing_extrema(&rings));
        }
        return;
    }
    if std::env::args().nth(1).as_deref() == Some("measure") {
        // measure DEC.txt(rings, with H line from original probe file) : args: probe_file dec_file
        let a: Vec<String> = std::env::args().collect();
        let (_, _, m) = rd(&a[2], 1.0);
        let (_, rings, _) = rd(&a[3], 1.0);
        println!("{:.3}", area_error(&rings, &m));
        return;
    }
    if std::env::args().nth(1).as_deref() == Some("emit") {
        let a: Vec<String> = std::env::args().collect();
        let (_, rings, m) = rd(&a[2], 1.0);
        let b = NodeBudget { max_nodes: count_nodes(&rings), max_nodes_per_ring: vec![] };
        let (out, r) = try_apply(&rings, &m, &b).unwrap();
        println!("{} {} {} {}", hex(&rings), hex(&out), r.input_hash, r.output_hash);
        std::fs::write(format!("{}.after", a[2]), dump(&out)).unwrap();
        return;
    }
    let a: Vec<String> = std::env::args().collect();
    let ysign: f64 = a[1].parse().unwrap();
    for p in &a[2..] {
        let (_, rings, m) = rd(p, ysign);
        let b = NodeBudget { max_nodes: count_nodes(&rings), max_nodes_per_ring: vec![] };
        match try_apply(&rings, &m, &b) {
            Ok((_, r)) => println!("{} nodes {}->{} area {:.1}->{:.1} c2 {} disp {} {}", p, r.nodes_before, r.nodes_after, r.area_before, r.area_after, r.c2_missing, r.max_node_displacement, r.notes),
            Err(e) => println!("{} ERR {:?} area_in {:.1}", p, e, area_error(&rings, &m)),
        }
    }
}
