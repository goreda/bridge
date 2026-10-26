//! C3 before/after probe: runs the 5 pinned real-scan fixtures through the
//! production capture+fit path, then measures the corner-explicit
//! representation per fixture. Prints the report table plus the measured
//! turn distribution on the explicit corner links (the data an architect
//! needs to read intent off the links). Measurement only.
use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured;
use kni_core::corner_nodes::*;
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::{DrawnGlyph, Point, Span};

const K: f64 = 690.0 / 403.5087719298246;
const FX: [&str; 5] = ["r_scan.png", "s_scan.png", "u_scan.png", "dot_00b7.png", "quote_2018.png"];

fn main() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");
    let pol = FitPolicy { squared_error: 0.1, max_refits: 6 };
    let mut rows = Vec::new();
    for name in FX {
        let png = std::fs::read(format!("{}/{}", dir, name)).unwrap();
        let mc = capture_png(&png, 0.5).unwrap();
        let (rings, ..) = fit_captured(&mc.rings, K, &pol);
        let g = DrawnGlyph { glyph_id: name.to_string(), rings };
        let xg = split_glyph(&g, 1.0).unwrap();
        let back = collapse_glyph(&xg).unwrap();
        let identical = g.rings.iter().zip(back.rings.iter()).all(|(a, b)| format!("{:?}", a) == format!("{:?}", b));
        let s = glyph_stats(&g, &xg, 1.0);
        let mut turns: Vec<f64> = xg.rings.iter().flat_map(|r| r.connectors.iter()).filter_map(|c| match c {
            Connector::CornerLink(l) => Some(l.turn_deg),
            _ => None,
        }).collect();
        turns.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let median = if turns.is_empty() { 0.0 } else { turns[turns.len() / 2] };
        let max = turns.last().copied().unwrap_or(0.0);
        let min = turns.first().copied().unwrap_or(0.0);
        println!("{} | collapse_identical={} | link_turn_deg min={:.3} median={:.3} max={:.3}", name, identical, min, median, max);
        rows.push((name.to_string(), s));
    }
    println!("{}", render_report(&rows));
    // Silence unused-import style drift if Span/Point go unused in future edits.
    let _ = (Point { x: 0.0, y: 0.0 }, std::mem::size_of::<Option<Span>>());
}
