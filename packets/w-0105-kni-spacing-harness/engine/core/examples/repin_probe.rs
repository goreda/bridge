//! Re-pin probe: for each pinned fixture, report the typed fallback ledger
//! breakdown and the quality metrics the tests assert.
use kni_core::capture::capture_png;
use kni_core::capture_fit::{fit_captured_with_fallback_events, FallbackReason};
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::{Point, Span};

fn report(name: &str, png: &[u8], eps: f64, scale: f64, se: f64, mr: usize) {
    let mc = capture_png(png, eps).expect("capture");
    let scale = if scale < 0.0 { let mut mxy = 0f64; for r in &mc.rings { for p in &r.points { mxy = mxy.max(p.y); } } 700.0 / mxy } else { scale };
    let policy = FitPolicy { squared_error: se, max_refits: mr };
    let (rings, n, status, d, fevents) = fit_captured_with_fallback_events(&mc.rings, scale, &policy);
    let (mut su, mut dl, mut dg, mut sg, mut ar) = (0, 0, 0, 0, 0);
    for e in &fevents { match e.reason { FallbackReason::SplitUnresolved => su += 1, FallbackReason::DepthLimit => dl += 1, FallbackReason::DegenerateTangents => dg += 1, FallbackReason::SubGridSpan => sg += 1, FallbackReason::AreaCollapseRestored => ar += 1 } }
    println!("{}\tspans={}\tstatus={}\tdropped={}\tevents={}\tSplitUnresolved={}\tDepthLimit={}\tDegenerateTangents={}\tSubGridSpan={}\tAreaCollapseRestored={}", name, n, status, d, fevents.len(), su, dl, dg, sg, ar);
    // bulge metric (small_ring_bias): fitted area vs captured area
    fn cubic_pt(p0: Point, c1: Point, c2: Point, p3: Point, t: f64) -> Point {
        let v = 1.0 - t;
        Point { x: v*v*v*p0.x + 3.0*v*v*t*c1.x + 3.0*v*t*t*c2.x + t*t*t*p3.x, y: v*v*v*p0.y + 3.0*v*v*t*c1.y + 3.0*v*t*t*c2.y + t*t*t*p3.y }
    }
    fn area(poly: &[Point]) -> f64 { let mut a = 0.0; for i in 0..poly.len() { let (u, v) = (poly[i], poly[(i + 1) % poly.len()]); a += u.x * v.y - v.x * u.y; } a / 2.0 }
    let mut fit_area = 0.0;
    for r in &rings {
        let mut poly = vec![r.start];
        let mut cur = r.start;
        for sp in &r.spans {
            match sp { Span::Line { end } => { poly.push(*end); cur = *end; }, Span::Cubic { control_one, control_two, end } => { for i in 1..=16 { poly.push(cubic_pt(cur, *control_one, *control_two, *end, i as f64 / 16.0)); } cur = *end; } }
        }
        fit_area += area(&poly).abs();
    }
    let mut src_area = 0.0;
    for r in &mc.rings { src_area += area(&r.points).abs(); }
    println!("{}\tarea_rel={:+.4}", name, (fit_area - src_area) / src_area);
    // bowed-straight metric (straight_edge_fit): max sag ratio on long cubics
    let mut worst = 0.0f64;
    for r in &rings {
        let mut cur = r.start;
        for sp in &r.spans {
            if let Span::Cubic { control_one, control_two, end } = sp {
                let (dx, dy) = (end.x - cur.x, end.y - cur.y);
                let l = dx.hypot(dy);
                if l > 60.0 {
                    let sag = |c: &Point| (dx * (c.y - cur.y) - dy * (c.x - cur.x)).abs() / l;
                    let ratio = sag(control_one).max(sag(control_two)) / l;
                    if ratio < 0.02 { println!("{}\tBOWED long cubic len {:.1} sag {:.4}", name, l, ratio); }
                    worst = worst.max(ratio);
                }
                cur = *end;
            } else { cur = match sp { Span::Line { end } => *end, _ => cur }; }
        }
    }
    println!("{}\tlong_cubic_max_sag_ratio={:.4}", name, worst);
}

fn main() {
    report("r_scan", include_bytes!("../tests/fixtures/r_scan.png"), 0.29, -1.0, 1.0, 6);
    report("u_scan", include_bytes!("../tests/fixtures/u_scan.png"), 0.5, 1000.0 / 1050.0, 1.0, 6);
    report("dot", include_bytes!("../tests/fixtures/dot_00b7.png"), 0.5, 1.0, 1.0, 6);
    report("quote", include_bytes!("../tests/fixtures/quote_2018.png"), 0.5, 1.0, 1.0, 6);
    report("eacute00C9", include_bytes!("../tests/fixtures/00C9_scan.png"), 0.5, 1.71, 0.1, 6);
}
