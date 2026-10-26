use kni_core::capture::{CapturedRing, MeasuredContour};
use kni_core::cubic_fit::FitPolicy;
use kni_core::master_fit_context::*;
use kni_core::reference_slice::{Point, Span};

fn ellipse(rx: f64, ry: f64, n: usize) -> MeasuredContour {
    let raw: Vec<Point> = (0..n).map(|i| { let a = i as f64 * std::f64::consts::TAU / n as f64;
        Point { x: 100.0 + rx * a.cos(), y: 100.0 + ry * a.sin() } }).collect();
    MeasuredContour { width: 300, height: 300, origin_x: 0.0, origin_y: 0.0,
        rings: vec![CapturedRing { points: raw.clone(), corners: vec![], hole: false, raw }] }
}
fn input(id: &str, w: f64, rx: f64, ry: f64) -> MasterInput {
    MasterInput { master_id: id.into(), axes: vec![AxisCoordinate { tag: *b"wght", value: w }], glyph_id: "o".into(),
        captured: ellipse(rx, ry, 360), scale: 1.0, source_pin: "a".repeat(64) }
}
fn lm(id: &str, i: usize, role: LandmarkRole) -> LandmarkRef { LandmarkRef { master_id: id.into(), ring_index: 0, raw_point_index: i, role } }
fn corr(ids: &[&str]) -> ContourCorrespondence {
    let cols = [(0, LandmarkRole::XMax), (90, LandmarkRole::YMax), (180, LandmarkRole::XMin), (270, LandmarkRole::YMin)];
    ContourCorrespondence { correspondence_id: "outer".into(), hole: false, orientation: Orientation::Ccw,
        landmarks: cols.iter().map(|&(i, r)| ids.iter().map(|id| lm(id, i, r)).collect()).collect() }
}
fn pol() -> FitPolicy { FitPolicy { squared_error: 0.25, max_refits: 8 } }
fn set() -> MasterSet {
    MasterSet { inputs: vec![input("light", 300.0, 40.0, 60.0), input("bold", 700.0, 55.0, 62.0)], correspondence: vec![corr(&["light", "bold"])] }
}
fn kinds(r: &MasterFitResult, m: usize) -> Vec<bool> { r.masters[m].outline.rings[0].spans.iter().map(|s| matches!(s, Span::Cubic{..})).collect() }

#[test]
fn compatible_masters_share_topology() {
    let r = fit_master_set(&set(), &pol()).unwrap();
    assert!(r.compatible_topology);
    assert_eq!(kinds(&r, 0), kinds(&r, 1));
    assert!(r.masters[0].outline.rings[0].spans.len() >= 4);
    println!("{}", r.receipt);
    assert_eq!(r.receipt, fit_master_set(&set(), &pol()).unwrap().receipt);
}
#[test]
fn typed_refusals() {
    let mut s = set(); s.correspondence.clear();
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::MissingCorrespondence(_))));
    let mut s = set(); s.inputs[1].master_id = "light".into();
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::DuplicateMaster(_))));
    let mut s = set(); s.inputs[1].axes[0].tag = *b"wdth";
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::BadAxes(_))));
    let mut s = set(); s.correspondence[0].landmarks[1][0].raw_point_index = 45; // not the y max
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::InvalidLandmark(_))));
    let mut s = set(); s.correspondence[0].landmarks[1][1].role = LandmarkRole::Corner;
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::InvalidLandmark(_))));
    let mut s = set(); s.correspondence[0].orientation = Orientation::Cw;
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::IncompatibleTopology(_))));
    let mut s = set(); let extra = s.inputs[1].captured.rings[0].clone(); s.inputs[1].captured.rings.push(extra);
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::IncompatibleTopology(_))));
    let mut s = set(); s.inputs[0].scale = f64::NAN;
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::NonFinite(_))));
    let mut s = set(); s.correspondence[0].landmarks[2].pop();
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::InvalidLandmark(_))));
}
#[test]
fn identity_validation() {
    let mut s = set(); s.inputs[0].source_pin = "abc".into();
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::UnsupportedConstraint(_))));
    let mut s = set(); s.inputs[0].master_id = " ".into();
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::UnsupportedConstraint(_))));
    let mut s = set(); s.inputs[0].glyph_id = "".into(); s.inputs[1].glyph_id = "".into();
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::UnsupportedConstraint(_))));
    let mut s = set(); s.inputs[0].axes[0].tag = [0, 0, 0, 0];
    assert!(matches!(fit_master_set(&s, &pol()), Err(MasterFitError::BadAxes(_))));
    // extremum role on a line whose direction is not along the constrained axis must not become a line
    let r = fit_master_set(&set(), &pol()).unwrap();
    assert!(r.receipt.contains("tangent_lookahead_fraction=") && r.receipt.contains("max_split_depth="));
}

// ----- additive trace tests (VF0 fit-trace) -----

fn input_notch(id: &str, w: f64, rx: f64, ry: f64, notch_r: f64) -> MasterInput {
    let n = 360; let notch_i = 225;
    let raw: Vec<Point> = (0..n).map(|i| { let a = i as f64 * std::f64::consts::TAU / n as f64;
        let (rrx, rry) = if i == notch_i { (notch_r, notch_r) } else { (rx, ry) };
        Point { x: 100.0 + rrx * a.cos(), y: 100.0 + rry * a.sin() } }).collect();
    MasterInput { master_id: id.into(), axes: vec![AxisCoordinate { tag: *b"wght", value: w }], glyph_id: "o".into(),
        captured: MeasuredContour { width: 300, height: 300, origin_x: 0.0, origin_y: 0.0,
            rings: vec![CapturedRing { points: raw.clone(), corners: vec![], hole: false, raw }] },
        scale: 1.0, source_pin: "a".repeat(64) }
}
fn notch_set() -> MasterSet {
    MasterSet { inputs: vec![input_notch("light", 300.0, 40.0, 60.0, 20.0), input_notch("bold", 700.0, 55.0, 62.0, 20.0)], correspondence: vec![corr(&["light", "bold"])] }
}
fn collect_splits<'a>(node: &'a DecisionNode, path: &str, out: &mut Vec<(String, usize, &'a [SplitRecord])>) {
    match node {
        DecisionNode::Split { depth, path: stored, splits, left, right } => {
            assert_eq!(stored, &path.to_string(), "stored path must equal the structural walk position");
            out.push((path.to_string(), *depth, splits.as_slice()));
            collect_splits(left, &format!("{}L", path), out);
            collect_splits(right, &format!("{}R", path), out);
        }
        _ => {}
    }
}
fn leaf_paths(node: &DecisionNode, path: &str, out: &mut Vec<String>) {
    match node {
        DecisionNode::AllStraight | DecisionNode::AllCubic => out.push(path.to_string()),
        DecisionNode::Split { left, right, .. } => {
            leaf_paths(left, &format!("{}L", path), out);
            leaf_paths(right, &format!("{}R", path), out);
        }
    }
}

#[test]
fn traced_and_delegating_entrypoints_agree_api_consistency() {
    // API consistency ONLY: the delegating wrapper and the traced entrypoint
    // return equal results on the same input. This is NOT
    // historical-preservation proof; that requires comparing the pre-trace source
    // against this candidate on the same fixtures (geometry hashes, receipt, refusals).
    let (r1, _t) = fit_master_set_traced(&set(), &pol()).unwrap();
    let r2 = fit_master_set(&set(), &pol()).unwrap();
    assert_eq!(r1.receipt, r2.receipt);
    assert_eq!(r1.compatible_topology, r2.compatible_topology);
    assert_eq!(kinds(&r1, 0), kinds(&r2, 0));
    assert_eq!(kinds(&r1, 1), kinds(&r2, 1));
}
#[test]
fn trace_records_supplied_correspondence_ring_and_start_maps() {
    let (_r, t) = fit_master_set_traced(&set(), &pol()).unwrap();
    assert_eq!(t.glyph_id, "o");
    assert_eq!(t.master_ids, vec!["light".to_string(), "bold".to_string()]);
    assert_eq!(t.rings.len(), 1);
    let ring = &t.rings[0];
    assert_eq!(ring.correspondence_id, "outer");
    assert_eq!(ring.ring_map, vec![(0, 0), (1, 0)]);
    assert_eq!(ring.start_map, vec![(0, 0), (1, 0)]);
    assert_eq!(ring.columns.len(), 4);
    let want = [(0usize, 90usize), (90, 180), (180, 270), (270, 0)];
    let roles = [LandmarkRole::XMax, LandmarkRole::YMax, LandmarkRole::XMin, LandmarkRole::YMin];
    for (col, ct) in ring.columns.iter().enumerate() {
        assert_eq!(ct.column, col);
        assert_eq!(ct.raw_interval, vec![(0, want[col].0, want[col].1), (1, want[col].0, want[col].1)]);
        assert_eq!(ct.role_start, roles[col]);
        assert_eq!(ct.role_end, roles[(col + 1) % 4]);
    }
}
#[test]
fn trace_emissions_match_result_spans_and_leaf_paths() {
    let (r, t) = fit_master_set_traced(&set(), &pol()).unwrap();
    for (ri, ring) in t.rings.iter().enumerate() {
        for ct in &ring.columns {
            let mut leaves = Vec::new(); leaf_paths(&ct.decision, "", &mut leaves);
            for em in &ct.emitted {
                assert!(leaves.contains(&em.source_path), "emission path not a decision leaf");
                assert_eq!(em.source_column, ct.column);
                let sp = &r.masters[em.master_index].outline.rings[ri].spans[em.span_index_in_ring];
                let k = match sp { Span::Line { .. } => SpanKind::Line, Span::Cubic { .. } => SpanKind::Cubic };
                assert_eq!(em.kind, k);
            }
        }
        for mi in 0..2 {
            let total: usize = ring.columns.iter().map(|ct| ct.emitted.iter().filter(|e| e.master_index == mi).count()).sum();
            assert_eq!(total, r.masters[mi].outline.rings[ri].spans.len());
        }
    }
}
#[test]
fn trace_records_actual_split_choices_on_shared_split() {
    let s = notch_set();
    let (_r, t) = fit_master_set_traced(&s, &pol()).unwrap();
    let mut n_split_nodes = 0usize;
    for ring in &t.rings {
        for ct in &ring.columns {
            let mut splits = Vec::new();
            collect_splits(&ct.decision, "", &mut splits);
            n_split_nodes += splits.len();
            for (path, depth, recs) in &splits {
                assert!(path.chars().all(|c| c == 'L' || c == 'R'));
                assert_eq!(path.len(), *depth);
                assert_eq!(recs.len(), 2);
                for (mi, rec) in recs.iter().enumerate() {
                    assert_eq!(rec.master_index, mi);
                    assert!(rec.selected_sample_offset >= 1);
                    assert!(rec.total_arc > 0.0);
                    assert!(rec.actual_fraction > 0.0 && rec.actual_fraction < 1.0);
                    assert_eq!(rec.actual_fraction, rec.cum_at_split / rec.total_arc);
                    // split_point_scaled must BE the actual selected raw sample
                    // (scaled); integer offset walk via selected_raw_index,
                    // no fraction math
                    let m = &s.inputs[rec.master_index];
                    let ri = ring.ring_map[rec.master_index].1;
                    let p = m.captured.rings[ri].raw[rec.selected_raw_index];
                    assert_eq!(rec.split_point_scaled, (p.x * m.scale, p.y * m.scale));
                }
            }
        }
    }
    assert!(n_split_nodes > 0, "notch fixture must force at least one shared split");
}

// ----- MFC-S01: trace-bound shared-split reconstruction -----
// For every shared split recorded in the trace, reconstruct the recursive segment from the
// column root raw interval plus the L/R path and check the recorded values against that
// reconstruction: split_point_scaled must be the actual selected sample, and
// selected_raw_index must equal a pure integer offset walk (no fraction math, no
// nearest-geometry lookup, no assertion that the measured fraction equals 0.5). Fixture:
// notch_set(), which forces at least one shared split (non-vacuity is asserted below).

fn mfc_segment_points(m: &MasterInput, ring: usize, a: usize, b: usize) -> Vec<Point> {
    // mirrors segment() in the source (cyclic inclusive walk a..=b, scaled); reconstruction only
    let raw = &m.captured.rings[ring].raw; let n = raw.len();
    let mut v = Vec::new(); let mut i = a;
    loop { v.push(Point { x: raw[i].x * m.scale, y: raw[i].y * m.scale }); if i == b { break; } i = (i + 1) % n; }
    v
}

fn mfc_verify_split_node(m: &MasterInput, mi: usize, ring_raw_len: usize, abs_base: usize, pts: &[Point], node: &DecisionNode, col: usize) {
    // abs_base = raw ring index (mod ring_raw_len) of pts[0]; the integer offset walk, independent of the trace.
    if let DecisionNode::Split { path, splits, left, right, .. } = node {
        let rec = splits.iter().find(|r| r.master_index == mi)
            .unwrap_or_else(|| panic!("col {col} path {path}: no SplitRecord for master {mi}"));
        let n = ring_raw_len;
        let mut cum = vec![0.0f64];
        for i in 1..pts.len() { cum.push(cum[i - 1] + (pts[i].x - pts[i - 1].x).hypot(pts[i].y - pts[i - 1].y)); }
        let i = rec.selected_sample_offset;
        assert!(i >= 1 && i + 1 < pts.len(), "col {col} path {path}: selected offset {i} not interior to {} points", pts.len());
        assert_eq!(rec.total_arc, *cum.last().unwrap(), "col {col} path {path}: total_arc");
        assert_eq!(rec.cum_at_split, cum[i], "col {col} path {path}: cum_at_split");
        assert_eq!(rec.actual_fraction, rec.cum_at_split / rec.total_arc, "col {col} path {path}: actual_fraction");
        assert!(rec.actual_fraction > 0.0 && rec.actual_fraction < 1.0, "col {col} path {path}: fraction in (0,1)");
        assert_eq!(rec.split_point_scaled, (pts[i].x, pts[i].y),
            "col {col} path {path}: split_point_scaled must equal the ACTUAL selected sample, reconstructed from root interval + path");
        assert_eq!(rec.selected_raw_index, (abs_base + i) % n.max(1),
            "col {col} path {path}: selected_raw_index must equal the integer offset walk (root interval + path), no fraction math");
        mfc_verify_split_node(m, mi, n, abs_base, &pts[..=i], left, col);
        mfc_verify_split_node(m, mi, n, (abs_base + i) % n.max(1), &pts[i..], right, col);
    }
}

#[test]
fn mfc_s01_shared_split_trace_reconstruction() {
    let s = notch_set();
    let (r, t) = fit_master_set_traced(&s, &pol()).unwrap();
    let mut n_split_nodes = 0usize;
    for ring in &t.rings {
        for ct in &ring.columns {
            for &(mi, ia, ib) in &ct.raw_interval {
                let m = &s.inputs[mi];
                let ridx = ring.ring_map[mi].1;
                let pts = mfc_segment_points(m, ridx, ia, ib);
                // wrapped root interval: raw indices bound the extracted segment endpoints exactly
                let raw = &m.captured.rings[ridx].raw;
                assert_eq!(pts[0], Point { x: raw[ia].x * m.scale, y: raw[ia].y * m.scale }, "col {} root start", ct.column);
                assert_eq!(*pts.last().unwrap(), Point { x: raw[ib].x * m.scale, y: raw[ib].y * m.scale }, "col {} root end", ct.column);
                mfc_verify_split_node(m, mi, raw.len(), ia, &pts, &ct.decision, ct.column);
            }
            let mut splits = Vec::new(); collect_splits(&ct.decision, "", &mut splits); n_split_nodes += splits.len();
        }
    }
    assert!(n_split_nodes > 0, "notch fixture must force at least one shared split (else this case is vacuous)");
    // compatibility on the traced run: identical kind sequences and span counts per ring across masters
    assert_eq!(kinds(&r, 0), kinds(&r, 1));
    assert_eq!(r.masters[0].outline.rings.len(), r.masters[1].outline.rings.len());
    for ri in 0..r.masters[0].outline.rings.len() {
        assert_eq!(r.masters[0].outline.rings[ri].spans.len(), r.masters[1].outline.rings[ri].spans.len());
    }
    // deterministic receipt across two identical traced calls
    let (r2, _t2) = fit_master_set_traced(&notch_set(), &pol()).unwrap();
    assert_eq!(r.receipt, r2.receipt);
}

#[test]
fn mfc_notch_leaf_ids_and_span_bijection() {
    // The plain ellipse fixture never splits, so L/R recursive leaf identity is not exercised there.
    // The same identity and bijection assertions run here on the forced-split notch fixture.
    let (r, t) = fit_master_set_traced(&notch_set(), &pol()).unwrap();
    let nm = t.master_ids.len();
    let mut any_recursive_leaf = false;
    for (ri, ring) in t.rings.iter().enumerate() {
        let ids: Vec<Vec<(usize, String, SpanKind)>> = (0..nm).map(|mi| {
            ring.columns.iter().flat_map(|ct| ct.emitted.iter().filter(move |e| e.master_index == mi)
                .map(|e| (e.source_column, e.source_path.clone(), e.kind))).collect()
        }).collect();
        for mi in 1..nm { assert_eq!(ids[0], ids[mi], "notch ring {ri}: shared leaf identity differs for master {mi}"); }
        for mi in 0..nm {
            let mut idx: Vec<usize> = ring.columns.iter().flat_map(|ct| ct.emitted.iter().filter(move |e| e.master_index == mi).map(|e| e.span_index_in_ring)).collect();
            idx.sort_unstable();
            let want: Vec<usize> = (0..r.masters[mi].outline.rings[ri].spans.len()).collect();
            assert_eq!(idx, want, "notch ring {ri} master {mi}: emitted span indices not a bijection");
        }
        for ct in &ring.columns { if ct.emitted.iter().any(|e| !e.source_path.is_empty()) { any_recursive_leaf = true; } }
    }
    assert!(any_recursive_leaf, "notch fixture must produce at least one recursive (non-root) leaf path, else this test is vacuous");
}
