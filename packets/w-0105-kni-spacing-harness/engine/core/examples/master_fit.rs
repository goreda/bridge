//! Synthetic demo: two ellipse masters, four extremum landmarks. Prints the receipt and node counts.
use kni_core::capture::{CapturedRing, MeasuredContour};
use kni_core::cubic_fit::FitPolicy;
use kni_core::master_fit_context::*;
use kni_core::reference_slice::Point;
fn ell(rx: f64, ry: f64) -> MeasuredContour {
    let raw: Vec<Point> = (0..360).map(|i| { let a = i as f64 * std::f64::consts::TAU / 360.0; Point { x: 100.0 + rx * a.cos(), y: 100.0 + ry * a.sin() } }).collect();
    MeasuredContour { width: 300, height: 300, origin_x: 0.0, origin_y: 0.0, rings: vec![CapturedRing { points: raw.clone(), corners: vec![], hole: false, raw }] }
}
fn main() {
    let mk = |id: &str, w: f64, rx: f64| MasterInput { master_id: id.into(), axes: vec![AxisCoordinate { tag: *b"wght", value: w }],
        glyph_id: "o".into(), captured: ell(rx, 60.0), scale: 1.0, source_pin: "0".repeat(64) };
    let roles = [(0, LandmarkRole::XMax), (90, LandmarkRole::YMax), (180, LandmarkRole::XMin), (270, LandmarkRole::YMin)];
    let c = ContourCorrespondence { correspondence_id: "outer".into(), hole: false, orientation: Orientation::Ccw,
        landmarks: roles.iter().map(|&(i, r)| ["a", "b"].iter().map(|id| LandmarkRef { master_id: id.to_string(), ring_index: 0, raw_point_index: i, role: r }).collect()).collect() };
    let set = MasterSet { inputs: vec![mk("a", 300.0, 40.0), mk("b", 700.0, 55.0)], correspondence: vec![c] };
    match fit_master_set(&set, &FitPolicy { squared_error: 0.25, max_refits: 8 }) {
        Ok(r) => println!("{}", r.receipt), Err(e) => println!("refused: {:?}", e),
    }
}
