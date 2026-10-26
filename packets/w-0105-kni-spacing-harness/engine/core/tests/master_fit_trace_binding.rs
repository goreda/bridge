//! Structural trace-binding contract tests for master_fit_trace_binding.
//! Synthetic fixtures only; no real axis vectors. Every negative case mutates
//! an otherwise-valid (result, trace) pair from fit_master_set_traced, one
//! invariant each, and asserts the exact typed error. Nothing here asserts
//! authenticated provenance or geometry validity: the binding is
//! STRUCTURAL_BINDING_ONLY and raw-index bounds are UNVERIFIED by design.
//! Validation-order contract: the canonical per-column (path, kind) sequence
//! guard runs before per-emission tree walks, so MalformedPath, PathIntoLeaf,
//! NonTerminalPath and LeafKindMismatch are DEFENSIVE variants no emission
//! mutation can reach; they are intentionally not covered here.
//! ResultKindMismatch is reachable (N36), and SpanIndexHole is reachable via
//! a result-side extra span (N44).
use kni_core::capture::{CapturedRing, MeasuredContour};
use kni_core::cubic_fit::FitPolicy;
use kni_core::master_fit_context::*;
use kni_core::master_fit_trace_binding::*;
use kni_core::reference_slice::{Point, Span};

// ---------- fixtures (same construction style as tests/master_fit_context.rs) ----------

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
fn lm(id: &str, ring: usize, i: usize, role: LandmarkRole) -> LandmarkRef {
    LandmarkRef { master_id: id.into(), ring_index: ring, raw_point_index: i, role }
}
fn corr(ids: &[&str], ring: usize) -> ContourCorrespondence {
    let cols = [(0, LandmarkRole::XMax), (90, LandmarkRole::YMax), (180, LandmarkRole::XMin), (270, LandmarkRole::YMin)];
    ContourCorrespondence { correspondence_id: "outer".into(), hole: false, orientation: Orientation::Ccw,
        landmarks: cols.iter().map(|&(i, r)| ids.iter().map(|id| lm(id, ring, i, r)).collect()).collect() }
}
fn pol() -> FitPolicy { FitPolicy { squared_error: 0.25, max_refits: 8 } }
fn set() -> MasterSet {
    MasterSet { inputs: vec![input("light", 300.0, 40.0, 60.0), input("bold", 700.0, 55.0, 62.0)], correspondence: vec![corr(&["light", "bold"], 0)] }
}
fn notch_set() -> MasterSet {
    MasterSet { inputs: vec![input_notch("light", 300.0, 40.0, 60.0, 20.0), input_notch("bold", 700.0, 55.0, 62.0, 20.0)], correspondence: vec![corr(&["light", "bold"], 0)] }
}
/// Two-ring fixture: outer ellipse (hole=false, Ccw) + inner reversed ellipse
/// (hole=true, Cw); master B captures the two rings in swapped vector order,
/// so the correspondence ring maps differ per master (explicit ring map).
/// Each ring's raw vector is deterministically rotated so the supplied start
/// index s lands on the angle-0 point, a true extremum: the Ccw outer ring
/// uses rotate_left(n - s); the reversed Cw inner ring uses
/// rotate_left(n - 1 - s) (after reverse, angle 0 sits at index n - 1).
/// Landmark indices below are derived from those rotations.
fn tworing_set() -> MasterSet {
    let mk = |id: &str, w: f64, rxo: f64, ryo: f64, rxi: f64, ryi: f64, swap: bool, so: usize, si: usize| {
        let n = 360;
        let mut rawo: Vec<Point> = (0..n).map(|i| { let a = i as f64 * std::f64::consts::TAU / n as f64;
            Point { x: 100.0 + rxo * a.cos(), y: 100.0 + ryo * a.sin() } }).collect();
        rawo.rotate_left((n - so) % n);
        let mut rawi: Vec<Point> = (0..n).map(|i| { let a = i as f64 * std::f64::consts::TAU / n as f64;
            Point { x: 100.0 + rxi * a.cos(), y: 100.0 + ryi * a.sin() } }).collect();
        rawi.reverse();
        rawi.rotate_left((n - 1 - si) % n);
        let outer = CapturedRing { points: rawo.clone(), corners: vec![], hole: false, raw: rawo };
        let inner = CapturedRing { points: rawi.clone(), corners: vec![], hole: true, raw: rawi };
        let rings = if swap { vec![inner, outer] } else { vec![outer, inner] };
        MasterInput { master_id: id.into(), axes: vec![AxisCoordinate { tag: *b"wght", value: w }], glyph_id: "o".into(),
            captured: MeasuredContour { width: 300, height: 300, origin_x: 0.0, origin_y: 0.0, rings },
            scale: 1.0, source_pin: "a".repeat(64) }
    };
    // (light index, bold index, role): genuinely distinct supplied starts per
    // ring/master (outer 0/5, inner 10/20). Ccw ring: role at (s + angle).
    let outer_cols = [(0, 5, LandmarkRole::XMax), (90, 95, LandmarkRole::YMax), (180, 185, LandmarkRole::XMin), (270, 275, LandmarkRole::YMin)];
    // Cw (reversed) ring: role at (s - angle) mod n
    let inner_cols = [(10, 20, LandmarkRole::XMax), (100, 110, LandmarkRole::YMin), (190, 200, LandmarkRole::XMin), (280, 290, LandmarkRole::YMax)];
    let oc = ContourCorrespondence { correspondence_id: "outer".into(), hole: false, orientation: Orientation::Ccw,
        landmarks: outer_cols.iter().map(|&(li, bi, r)| vec![lm("light", 0, li, r), lm("bold", 1, bi, r)]).collect() };
    let ic = ContourCorrespondence { correspondence_id: "hole".into(), hole: true, orientation: Orientation::Cw,
        landmarks: inner_cols.iter().map(|&(li, bi, r)| vec![lm("light", 1, li, r), lm("bold", 0, bi, r)]).collect() };
    MasterSet { inputs: vec![mk("light", 300.0, 60.0, 70.0, 25.0, 30.0, false, 0, 10), mk("bold", 700.0, 66.0, 72.0, 28.0, 31.0, true, 5, 20)],
        correspondence: vec![oc, ic] }
}

fn pair() -> (MasterFitResult, MasterFitTrace) { fit_master_set_traced(&set(), &pol()).unwrap() }
fn notch_pair() -> (MasterFitResult, MasterFitTrace) { fit_master_set_traced(&notch_set(), &pol()).unwrap() }
fn tworing_pair() -> (MasterFitResult, MasterFitTrace) { fit_master_set_traced(&tworing_set(), &pol()).unwrap() }

/// Mutable handle to a Split decision node, if the node is one.
fn first_split_mut(node: &mut DecisionNode) -> Option<&mut DecisionNode> {
    match node {
        DecisionNode::Split { .. } => Some(node),
        _ => None,
    }
}
fn split_fields_mut(node: &mut DecisionNode) -> (&mut String, &mut usize, &mut Vec<SplitRecord>, &mut DecisionNode, &mut DecisionNode) {
    match node {
        DecisionNode::Split { depth, path, splits, left, right } => (path, depth, splits, left, right),
        _ => panic!("not a split"),
    }
}

// ---------- positive cases ----------

#[test]
fn tb_p01_ellipse_binds_with_verbatim_identity() {
    let (r, t) = pair();
    let b = bind_master_fit_trace(&r, &t).unwrap();
    assert_eq!(b.scope, BINDING_SCOPE);
    assert_eq!(b.scope, "STRUCTURAL_BINDING_ONLY");
    assert_eq!(b.glyph_id, "o");
    assert_eq!(b.receipt, r.receipt);
    assert_eq!(b.masters.len(), 2);
    for (mi, mb) in b.masters.iter().enumerate() {
        assert_eq!(mb.master_index, mi);
        assert_eq!(mb.master_id, r.masters[mi].master_id);
        assert_eq!(mb.axes, r.masters[mi].axes);
        assert_eq!(mb.source_pin, r.masters[mi].source_pin);
    }
    assert_eq!(b.masters[0].rings.len(), 1);
    let rb = &b.masters[0].rings[0];
    assert_eq!(rb.correspondence_id, "outer");
    assert_eq!(rb.captured_ring_index, 0);
    assert_eq!(rb.start_raw_index, 0);
    assert_eq!(rb.spans.len(), r.masters[0].outline.rings[0].spans.len());
    for (si, sb) in rb.spans.iter().enumerate() {
        assert_eq!(sb.span_index_in_ring, si);
        let k = match r.masters[0].outline.rings[0].spans[si] { Span::Line { .. } => SpanKind::Line, Span::Cubic { .. } => SpanKind::Cubic };
        assert_eq!(sb.kind, k);
        assert!(sb.split_chain.is_empty(), "ellipse has no splits");
    }
    assert_eq!(rb.spans[0].column_raw_interval, (0, 90));
}

#[test]
fn tb_p02_notch_binds_split_chain_in_traversal_order() {
    let (r, t) = notch_pair();
    let b = bind_master_fit_trace(&r, &t).unwrap();
    let mut saw_chain = false;
    for ct in &t.rings[0].columns {
        for em in ct.emitted.iter().filter(|e| e.master_index == 0) {
            let sb = &b.masters[0].rings[0].spans[em.span_index_in_ring];
            let exp = chain_for_path(&ct.decision, 0, &em.source_path);
            assert_eq!(sb.split_chain, exp, "split_chain must equal the selected_raw_index chain down the source path, in traversal order");
            if !exp.is_empty() { saw_chain = true; }
        }
    }
    assert!(saw_chain, "notch fixture must yield at least one nonempty split chain");
}
/// Reconstruct the expected split chain for one master down one L/R path.
fn chain_for_path(node: &DecisionNode, mi: usize, path: &str) -> Vec<usize> {
    let mut out = Vec::new();
    let mut cur = node;
    for c in path.chars() {
        match cur {
            DecisionNode::Split { splits, left, right, .. } => {
                out.push(splits.iter().find(|s| s.master_index == mi).unwrap().selected_raw_index);
                cur = if c == 'L' { left } else { right };
            }
            _ => panic!("path continues past a leaf"),
        }
    }
    out
}

#[test]
fn tb_p03_tworing_explicit_ring_and_start_maps() {
    let (r, t) = tworing_pair();
    let b = bind_master_fit_trace(&r, &t).unwrap();
    assert_eq!(b.masters[0].rings.len(), 2);
    // output ring order follows correspondence order in both masters
    assert_eq!(b.masters[0].rings[0].correspondence_id, "outer");
    assert_eq!(b.masters[0].rings[1].correspondence_id, "hole");
    // explicit supplied ring map: light captured rings [0,1], bold [1,0]
    assert_eq!(b.masters[0].rings[0].captured_ring_index, 0);
    assert_eq!(b.masters[0].rings[1].captured_ring_index, 1);
    assert_eq!(b.masters[1].rings[0].captured_ring_index, 1);
    assert_eq!(b.masters[1].rings[1].captured_ring_index, 0);
    // start map transport: distinct supplied starts echoed per ring/master
    assert_eq!(b.masters[0].rings[0].start_raw_index, 0);
    assert_eq!(b.masters[1].rings[0].start_raw_index, 5);
    assert_eq!(b.masters[0].rings[1].start_raw_index, 10);
    assert_eq!(b.masters[1].rings[1].start_raw_index, 20);
}

// ---------- negative cases: one invariant each, exact typed error ----------

#[test]
fn tb_n01_rejects_compatible_topology_false() {
    let (mut r, t) = pair();
    r.compatible_topology = false;
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::CompatibleTopologyFalse));
}
#[test]
fn tb_n02_rejects_empty_masters() {
    let (mut r, t) = pair();
    r.masters.clear();
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::EmptyMasters));
}
#[test]
fn tb_n03_rejects_trace_glyph_mismatch() {
    let (r, mut t) = pair();
    t.glyph_id = "x".into();
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::GlyphIdMismatch { location: GlyphIdLocation::Trace, expected: "o".into(), found: "x".into() }));
}
#[test]
fn tb_n04_rejects_outline_glyph_mismatch() {
    let (mut r, t) = pair();
    r.masters[1].outline.glyph_id = "x".into();
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::GlyphIdMismatch { location: GlyphIdLocation::Outline { master_index: 1 }, expected: "o".into(), found: "x".into() }));
}
#[test]
fn tb_n05_rejects_master_count_mismatch() {
    let (r, mut t) = pair();
    t.master_ids.push("extra".into());
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::MasterCountMismatch { result: 2, trace: 3 }));
}
#[test]
fn tb_n06_rejects_master_id_order_swap() {
    let (r, mut t) = pair();
    t.master_ids.swap(0, 1);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterIdMismatch { index: 0, result_id: "light".into(), trace_id: "bold".into() }));
}
#[test]
fn tb_n07_rejects_duplicate_master_id() {
    let (mut r, mut t) = pair();
    // duplicate on BOTH sides so the per-index MasterIdMismatch guard passes
    // and the duplicate invariant is the one under test
    r.masters[1].master_id = r.masters[0].master_id.clone();
    t.master_ids[1] = t.master_ids[0].clone();
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::DuplicateMasterId { master_id: "light".into() }));
}
#[test]
fn tb_n08_rejects_ring_count_mismatch() {
    let (mut r, t) = pair();
    r.masters[0].outline.rings.pop();
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::RingCountMismatch { master_index: 0, result: 0, trace: 1 }));
}
#[test]
fn tb_n09_rejects_empty_correspondence_id() {
    let (r, mut t) = pair();
    t.rings[0].correspondence_id = String::new();
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::EmptyCorrespondenceId { ring: 0 }));
}
#[test]
fn tb_n10_rejects_duplicate_correspondence_id() {
    let (r, mut t) = tworing_pair();
    t.rings[1].correspondence_id = t.rings[0].correspondence_id.clone();
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::DuplicateCorrespondenceId { correspondence_id: "outer".into() }));
}
#[test]
fn tb_n11_rejects_captured_ring_reused() {
    let (r, mut t) = tworing_pair();
    // both correspondences claim captured ring 0 for master 0
    t.rings[1].ring_map[0] = (0, 0);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::CapturedRingReused { master_index: 0, captured_ring_index: 0, first_ring: 0, second_ring: 1 }));
}
#[test]
fn tb_n12_rejects_ring_map_master_out_of_range() {
    let (r, mut t) = pair();
    t.rings[0].ring_map[1] = (9, 0);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterMapOutOfRange { ring: 0, column: None, map: MapKind::RingMap, master_index: 9 }));
}
#[test]
fn tb_n13_rejects_ring_map_master_duplicate() {
    let (r, mut t) = pair();
    t.rings[0].ring_map.push((0, 0));
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterMapDuplicate { ring: 0, column: None, map: MapKind::RingMap, master_index: 0 }));
}
#[test]
fn tb_n14_rejects_ring_map_master_missing() {
    let (r, mut t) = pair();
    t.rings[0].ring_map.pop();
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterMapMissing { ring: 0, column: None, map: MapKind::RingMap, master_index: 1 }));
}
#[test]
fn tb_n15_rejects_start_map_entry_out_of_range() {
    let (r, mut t) = pair();
    t.rings[0].start_map[1] = (9, 0);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterMapOutOfRange { ring: 0, column: None, map: MapKind::StartMap, master_index: 9 }));
}
#[test]
fn tb_n16_rejects_column_id_duplicate() {
    let (r, mut t) = pair();
    t.rings[0].columns[1].column = 0;
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::ColumnIdDuplicate { ring: 0, column: 0 }));
}
#[test]
fn tb_n17_rejects_column_id_gap() {
    let (r, mut t) = pair();
    t.rings[0].columns[3].column = 4;
    // ids become 0,1,2,4 with 4 columns: the out-of-range id is rejected first
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::ColumnIdOutOfRange { ring: 0, column: 4 }));
}
#[test]
fn tb_n18_rejects_start_map_mismatch() {
    let (r, mut t) = pair();
    t.rings[0].start_map[0] = (0, 7);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::StartMapMismatch { ring: 0, master_index: 0, start_map: 7, first_column_start: 0 }));
}
#[test]
fn tb_n19_rejects_column_join_mismatch() {
    let (r, mut t) = pair();
    let e = t.rings[0].columns[0].raw_interval[0].2;
    t.rings[0].columns[0].raw_interval[0] = (0, 0, e + 1);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnJoinMismatch { ring: 0, master_index: 0, column: 0, end: e + 1, next_start: 90 }));
}
#[test]
fn tb_n20_rejects_column_wrap_mismatch() {
    let (r, mut t) = pair();
    let e = t.rings[0].columns[3].raw_interval[0].2;
    t.rings[0].columns[3].raw_interval[0] = (0, 270, e + 1);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnWrapMismatch { ring: 0, master_index: 0, last_end: e + 1, first_start: 0 }));
}
#[test]
fn tb_n21_rejects_split_path_mismatch() {
    let (r, mut t) = notch_pair();
    for ct in t.rings[0].columns.iter_mut() {
        if let Some(n) = first_split_mut(&mut ct.decision) {
            let (path, _, _, _, _) = split_fields_mut(n);
            *path = if path == "L" { "R".into() } else { "L".into() };
        }
    }
    assert!(matches!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::SplitPathMismatch { .. })));
}
#[test]
fn tb_n22_rejects_split_depth_mismatch() {
    let (r, mut t) = notch_pair();
    for ct in t.rings[0].columns.iter_mut() {
        if let Some(n) = first_split_mut(&mut ct.decision) {
            let (_, depth, _, _, _) = split_fields_mut(n);
            *depth += 1;
        }
    }
    assert!(matches!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::SplitDepthMismatch { .. })));
}
#[test]
fn tb_n23_rejects_emission_master_index_out_of_range() {
    let (r, mut t) = pair();
    t.rings[0].columns[0].emitted[0].master_index = 9;
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::EmissionMasterIndexOutOfRange { ring: 0, column: 0, master_index: 9 }));
}
#[test]
fn tb_n24_rejects_source_column_mismatch() {
    let (r, mut t) = pair();
    t.rings[0].columns[0].emitted[0].source_column = 3;
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::SourceColumnMismatch { ring: 0, containing_column: 0, named_column: 3 }));
}
#[test]
fn tb_n25_rejects_duplicated_leaf_emission_shared_by_both_masters() {
    // cross-master equality alone would accept this; the DFS terminal list must not
    let (r, mut t) = pair();
    for ct in t.rings[0].columns.iter_mut() {
        let e0 = ct.emitted[0].clone();
        let e1 = ct.emitted.iter().find(|e| e.master_index == 1 && e.source_path == e0.source_path).unwrap().clone();
        ct.emitted.push(e0); ct.emitted.push(e1);
    }
    assert!(matches!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::ColumnLeafCountMismatch { .. })));
}
#[test]
fn tb_n26_rejects_span_index_out_of_range() {
    let (r, mut t) = pair();
    t.rings[0].columns[0].emitted[0].span_index_in_ring = 99;
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::SpanIndexOutOfRange { ring: 0, master_index: 0, span_index: 99, ring_len: r.masters[0].outline.rings[0].spans.len() }));
}
#[test]
fn tb_n27_rejects_span_index_duplicate() {
    let (r, mut t) = pair();
    let v = t.rings[0].columns[0].emitted[0].span_index_in_ring;
    t.rings[0].columns[1].emitted[0].span_index_in_ring = v;
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::SpanIndexDuplicate { ring: 0, master_index: 0, span_index: v }));
}
#[test]
fn tb_n28_rejects_span_index_hole() {
    let (r, mut t) = pair();
    // remove master 0's last emission of the ring: unique, in range, one hole
    let last_col = t.rings[0].columns.len() - 1;
    let pos = t.rings[0].columns[last_col].emitted.iter().rposition(|e| e.master_index == 0).unwrap();
    t.rings[0].columns[last_col].emitted.remove(pos);
    assert_eq!(last_col, 3, "ellipse fixture has four landmark-split columns");
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnLeafCountMismatch { ring: 0, column: 3, master_index: 0, emissions: 0, terminals: 1 }));
}
#[test]
fn tb_n29_rejects_malformed_path() {
    let (r, mut t) = pair();
    t.rings[0].columns[0].emitted[0].source_path = "LX".into();
    // the canonical per-column (path, kind) sequence comparison rejects this
    // before any tree walk (position 0: expected leaf path "")
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnLeafSequenceMismatch { ring: 0, column: 0, master_index: 0, position: 0 }));
}
#[test]
fn tb_n30_rejects_path_into_leaf() {
    let (r, mut t) = pair();
    // ellipse columns are root leaves; any non-empty path walks into a leaf
    t.rings[0].columns[0].emitted[0].source_path = "L".into();
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnLeafSequenceMismatch { ring: 0, column: 0, master_index: 0, position: 0 }));
}
#[test]
fn tb_n31_rejects_non_terminal_path() {
    let (r, mut t) = notch_pair();
    // find the split column; set one emission to the (non-terminal) root path
    let col = t.rings[0].columns.iter().position(|ct| matches!(ct.decision, DecisionNode::Split { .. })).unwrap();
    t.rings[0].columns[col].emitted.iter_mut().find(|e| e.master_index == 0).unwrap().source_path = String::new();
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnLeafSequenceMismatch { ring: 0, column: col, master_index: 0, position: 0 }));
}
#[test]
fn tb_n32_rejects_split_master_index_out_of_range() {
    let (r, mut t) = notch_pair();
    for ct in t.rings[0].columns.iter_mut() {
        if let Some(n) = first_split_mut(&mut ct.decision) {
            let (_, _, splits, _, _) = split_fields_mut(n);
            splits[0].master_index = 9;
            break;
        }
    }
    assert!(matches!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::SplitMasterIndexOutOfRange { .. })));
}
#[test]
fn tb_n33_rejects_split_record_missing() {
    let (r, mut t) = notch_pair();
    for ct in t.rings[0].columns.iter_mut() {
        if let Some(n) = first_split_mut(&mut ct.decision) {
            let (_, _, splits, _, _) = split_fields_mut(n);
            splits.remove(0);
            break;
        }
    }
    assert!(matches!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::SplitRecordMissing { .. })));
}
#[test]
fn tb_n34_rejects_split_record_duplicate() {
    let (r, mut t) = notch_pair();
    for ct in t.rings[0].columns.iter_mut() {
        if let Some(n) = first_split_mut(&mut ct.decision) {
            let (_, _, splits, _, _) = split_fields_mut(n);
            let c = splits[0].clone(); splits.push(c);
            break;
        }
    }
    assert!(matches!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::SplitRecordDuplicate { .. })));
}
#[test]
fn tb_n35_rejects_leaf_kind_mismatch() {
    let (r, mut t) = pair();
    let flip = |k: SpanKind| match k { SpanKind::Line => SpanKind::Cubic, SpanKind::Cubic => SpanKind::Line };
    let e = &mut t.rings[0].columns[0].emitted[0];
    e.kind = flip(e.kind);
    // the sequence comparison checks (path, kind) pairs, so a kind flip is
    // rejected here, before the walk and the result-span kind checks
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnLeafSequenceMismatch { ring: 0, column: 0, master_index: 0, position: 0 }));
}
#[test]
fn tb_n36_rejects_result_kind_mismatch() {
    let (mut r, t) = pair();
    // rewrite result span 0 of ring 0 master 0 as the OTHER kind with the same end point
    let end = match r.masters[0].outline.rings[0].spans[0] { Span::Line { end } | Span::Cubic { end, .. } => end };
    let was_line = matches!(r.masters[0].outline.rings[0].spans[0], Span::Line { .. });
    r.masters[0].outline.rings[0].spans[0] = if was_line {
        Span::Cubic { control_one: end, control_two: end, end }
    } else {
        Span::Line { end }
    };
    assert!(matches!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::ResultKindMismatch { .. })));
}
#[test]
fn tb_n37_rejects_ordered_leaf_mismatch_one_master() {
    let (r, mut t) = notch_pair();
    // relabel one master-1 emission's path to another valid terminal leaf
    let col = t.rings[0].columns.iter().position(|ct| { let mut v = Vec::new(); leaf_paths(&ct.decision, "", &mut v); v.len() >= 2 }).unwrap();
    let mut leaves = Vec::new(); leaf_paths(&t.rings[0].columns[col].decision, "", &mut leaves);
    let e = t.rings[0].columns[col].emitted.iter_mut().find(|e| e.master_index == 1 && e.source_path == leaves[0]).unwrap();
    e.source_path = leaves[1].clone();
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnLeafSequenceMismatch { ring: 0, column: col, master_index: 1, position: 0 }));
}
fn leaf_paths(node: &DecisionNode, path: &str, out: &mut Vec<String>) {
    match node {
        DecisionNode::AllStraight | DecisionNode::AllCubic => out.push(path.to_string()),
        DecisionNode::Split { left, right, .. } => { leaf_paths(left, &format!("{}L", path), out); leaf_paths(right, &format!("{}R", path), out); }
    }
}

#[test]
fn tb_n38_rejects_empty_rings() {
    let (r, mut t) = pair();
    t.rings.clear();
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::EmptyRings));
}
#[test]
fn tb_n39_rejects_empty_column_set() {
    let (r, mut t) = pair();
    t.rings[0].columns.clear();
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::EmptyColumnSet { ring: 0 }));
}
#[test]
fn tb_n40_rejects_empty_result_ring() {
    let (mut r, t) = pair();
    r.masters[0].outline.rings[0].spans.clear();
    assert_eq!(bind_master_fit_trace(&r, &t), Err(TraceBindingError::EmptyResultRing { ring: 0, master_index: 0 }));
}
#[test]
fn tb_n41_rejects_raw_interval_master_out_of_range() {
    let (r, mut t) = pair();
    t.rings[0].columns[0].raw_interval[1].0 = 9;
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterMapOutOfRange { ring: 0, column: Some(0), map: MapKind::RawInterval, master_index: 9 }));
}

#[test]
fn tb_p05_policy_echoes_carried_as_supplied() {
    let (r, t) = pair();
    let b = bind_master_fit_trace(&r, &t).unwrap();
    assert_eq!(b.squared_error, t.squared_error);
    assert_eq!(b.max_refits, t.max_refits);
    assert_eq!(b.tangent_lookahead_fraction, t.tangent_lookahead_fraction);
    assert_eq!(b.max_split_depth, t.max_split_depth);
    assert_eq!(b.split_fraction, t.split_fraction);
    assert_eq!(b.squared_error, 0.25);
    assert_eq!(b.max_refits, 8);
    assert_eq!(b.tangent_lookahead_fraction, TANGENT_LOOKAHEAD_FRACTION);
    assert_eq!(b.max_split_depth, MAX_SPLIT_DEPTH);
    // carried, not recomputed: a mutated trace echo passes through verbatim
    let mut t2 = t.clone();
    t2.squared_error = 0.5;
    let b2 = bind_master_fit_trace(&r, &t2).unwrap();
    assert_eq!(b2.squared_error, 0.5);
    assert_eq!(b2.split_fraction, t2.split_fraction, "declared target echo, never a measured fraction");
}

#[test]
fn tb_n42_rejects_shared_span_index_permutation() {
    let (r, mut t) = notch_pair();
    // swap the span_index_in_ring values of the first two Line emissions
    // within EACH master of the split column: the bijection, the kinds and
    // the shared leaf sequence all still hold; only the canonical span-order
    // guard (columns 0..ncols, DFS leaves, exactly 0,1,2,...) rejects it
    let col = t.rings[0].columns.iter().position(|ct|
        ct.emitted.iter().filter(|e| e.master_index == 0 && e.kind == SpanKind::Line).count() >= 2).unwrap();
    let line0: Vec<usize> = t.rings[0].columns[col].emitted.iter().enumerate()
        .filter(|(_, e)| e.master_index == 0 && e.kind == SpanKind::Line).map(|(i, _)| i).collect();
    let expected = t.rings[0].columns[col].emitted[line0[0]].span_index_in_ring;
    let found = t.rings[0].columns[col].emitted[line0[1]].span_index_in_ring;
    {
        let ct = &mut t.rings[0].columns[col];
        for mi in 0..2usize {
            let idxs: Vec<usize> = ct.emitted.iter().enumerate()
                .filter(|(_, e)| e.master_index == mi && e.kind == SpanKind::Line).map(|(i, _)| i).collect();
            let (a, b) = (idxs[0], idxs[1]);
            let tmp = ct.emitted[a].span_index_in_ring;
            ct.emitted[a].span_index_in_ring = ct.emitted[b].span_index_in_ring;
            ct.emitted[b].span_index_in_ring = tmp;
        }
    }
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::SpanIndexOutOfOrder { ring: 0, master_index: 0, column: col, expected, found }));
}
#[test]
fn tb_n43_rejects_shuffled_column_positions() {
    let (r, mut t) = pair();
    // same id set, wrong entry positions: producer contract position == column id
    t.rings[0].columns.swap(0, 1);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnIdOutOfOrder { ring: 0, position: 0, column: 1 }));
}
#[test]
fn tb_n44_rejects_result_only_span_index_hole() {
    let (mut r, t) = notch_pair();
    // master 0's result ring gains a span the trace never emitted: every
    // emission stays canonical, so the hole guard reports the unbound slot
    let n = t.rings[0].columns.iter().map(|ct| ct.emitted.iter().filter(|e| e.master_index == 0).count()).sum::<usize>();
    let extra = r.masters[0].outline.rings[0].spans.last().unwrap().clone();
    r.masters[0].outline.rings[0].spans.push(extra);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::SpanIndexHole { ring: 0, master_index: 0, span_index: n }));
}

// ---------- bind must not mutate its inputs ----------

#[test]
fn tb_p04_bind_leaves_inputs_debug_and_receipt_unchanged() {
    let (r, t) = notch_pair();
    let (rd, td) = (format!("{:?}", r), format!("{:?}", t));
    let receipt = r.receipt.clone();
    bind_master_fit_trace(&r, &t).unwrap();
    assert_eq!(rd, format!("{:?}", r));
    assert_eq!(td, format!("{:?}", t));
    assert_eq!(receipt, r.receipt);
}

// ---------- producer composition: BoundMasterFit wrapper ----------

#[test]
fn tb_p06_bound_wrapper_ellipse_success() {
    let b = fit_master_set_bound(&set(), &pol()).unwrap();
    assert_eq!(b.result().masters.len(), 2);
    assert_eq!(b.binding().masters.len(), 2);
    assert!(b.binding().masters.iter().all(|m| m.rings.iter().all(|r| !r.spans.is_empty())));
}
#[test]
fn tb_p07_bound_wrapper_notch_success() {
    let b = fit_master_set_bound(&notch_set(), &pol()).unwrap();
    assert_eq!(b.result().masters.len(), 2);
    assert!(b.binding().masters.iter().all(|m| m.rings.iter().all(|r| !r.spans.is_empty())));
}
#[test]
fn tb_p08_bound_wrapper_tworing_success() {
    let b = fit_master_set_bound(&tworing_set(), &pol()).unwrap();
    assert_eq!(b.binding().masters[0].rings.len(), 2);
    assert_eq!(b.binding().masters[1].rings.len(), 2);
}
#[test]
fn tb_p09_bound_wrapper_getter_identity_and_receipt() {
    let b = fit_master_set_bound(&notch_set(), &pol()).unwrap();
    let (r, t) = notch_pair();
    // within the atomic triple: receipt and master identity agree across
    // the getter-exposed parts
    assert_eq!(b.binding().receipt, b.result().receipt);
    for (i, m) in b.result().masters.iter().enumerate() {
        assert_eq!(b.binding().masters[i].master_id, m.master_id);
    }
    // measured identity across separate fit runs of the same fixture: the
    // binding (its structural identity fields and carried receipt) only;
    // result geometry is not compared
    let expect = bind_master_fit_trace(&r, &t).unwrap();
    assert_eq!(b.binding().receipt, r.receipt);
    assert_eq!(b.binding(), &expect);
}
#[test]
fn tb_n45_bound_wrapper_fit_error_propagates_typed() {
    let mut s = set();
    s.inputs[1].master_id = "light".into();
    // BoundMasterFit is intentionally not PartialEq: extract the error
    let err = match fit_master_set_bound(&s, &pol()) {
        Err(e) => e,
        Ok(_) => panic!("duplicate master id must fail the composed fit"),
    };
    assert_eq!(err, FitBindError::Fit(MasterFitError::DuplicateMaster("light".into())));
}

// ---------- gap negatives: map entries and tree depth bound ----------

#[test]
fn tb_n46_rejects_start_map_master_duplicate() {
    let (r, mut t) = pair();
    t.rings[0].start_map[1].0 = 0;
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterMapDuplicate { ring: 0, column: None, map: MapKind::StartMap, master_index: 0 }));
}
#[test]
fn tb_n47_rejects_start_map_master_missing() {
    let (r, mut t) = pair();
    t.rings[0].start_map.pop();
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterMapMissing { ring: 0, column: None, map: MapKind::StartMap, master_index: 1 }));
}
#[test]
fn tb_n48_rejects_raw_interval_master_duplicate() {
    let (r, mut t) = pair();
    t.rings[0].columns[0].raw_interval[1].0 = 0;
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterMapDuplicate { ring: 0, column: Some(0), map: MapKind::RawInterval, master_index: 0 }));
}
#[test]
fn tb_n49_rejects_raw_interval_master_missing() {
    let (r, mut t) = pair();
    t.rings[0].columns[0].raw_interval.pop();
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::MasterMapMissing { ring: 0, column: Some(0), map: MapKind::RawInterval, master_index: 1 }));
}
/// Left-chain of `n` nested splits; every stored path/depth consistent with
/// the DFS traversal, AllStraight leaves, no split records (the guards under
/// test run before any record walk).
fn tb_deep_chain(n: usize) -> DecisionNode {
    fn go(d: usize, n: usize, path: String) -> DecisionNode {
        if d == n { return DecisionNode::AllStraight; }
        DecisionNode::Split {
            depth: d,
            path: path.clone(),
            splits: vec![],
            left: Box::new(go(d + 1, n, format!("{}L", path))),
            right: Box::new(DecisionNode::AllStraight),
        }
    }
    go(0, n, String::new())
}
#[test]
fn tb_n50_rejects_tree_depth_exceeded() {
    let (r, mut t) = pair();
    t.rings[0].columns[0].decision = tb_deep_chain(MAX_SPLIT_DEPTH + 1);
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::TreeDepthExceeded {
            ring: 0, column: 0,
            path: "L".repeat(MAX_SPLIT_DEPTH + 1),
            depth: MAX_SPLIT_DEPTH + 1, bound: MAX_SPLIT_DEPTH,
        }));
}
#[test]
fn tb_n51_depth_bound_boundary_reaches_sequence_error() {
    // NEGATIVE PROBE, not a successful binding: a chain of exactly
    // MAX_SPLIT_DEPTH splits clears the depth guard, and the broken first
    // emission is then rejected by the canonical leaf-sequence comparison
    let (r, mut t) = pair();
    let decision = tb_deep_chain(MAX_SPLIT_DEPTH);
    let mut leaves = Vec::new(); leaf_paths(&decision, "", &mut leaves);
    let mut emitted = Vec::new();
    for mi in 0..2usize {
        for (i, path) in leaves.iter().enumerate() {
            emitted.push(SpanEmission { master_index: mi, span_index_in_ring: i, kind: SpanKind::Line, source_column: 0, source_path: path.clone() });
        }
    }
    emitted[0].source_path = "X".into();
    let ct = &mut t.rings[0].columns[0];
    ct.decision = decision;
    ct.emitted = emitted;
    assert_eq!(bind_master_fit_trace(&r, &t),
        Err(TraceBindingError::ColumnLeafSequenceMismatch { ring: 0, column: 0, master_index: 0, position: 0 }));
}

// ---------- VF4 span ledger: exact success / escaping / ordering (W3) ----------
// Subject: master_fit_span_ledger::format_span_ledger, W2 candidate v5 (module
// sha256 13f49d26afdda5c94cf7275373eddc74db8fdce8724de50b9805154436b59a4d) on
// canonical base a366479f640bc50a1cad92650320d0889fb9668b. The pinned v1 record
// grammar (one record per line, TAB-separated fields, STORED order):
//   kni.span-ledger.v1
//   scope\tSTRUCTURAL_BINDING_ONLY\tidentity only; raw bounds UNVERIFIED; carried claims NOT verified
//   glyph\t<esc glyph_id>
//   master\t<master_index>\tmaster_id=<esc>
//   ring\t<ring position 0..>\tcorrespondence_id=<esc>\tcaptured_ring_index=<n>\tstart_raw_index=<n>
//   span\t<span_index_in_ring>\tkind=<line|cubic>\tcolumn=<n>\tpath=<esc>\traw=(<start>,<end>)\tsplits=[<i0>,...]
// Escaping pinned: crate::iou_report::escape_id (empty -> "%EMPTY"; ASCII
// alphanumerics and '.' '_' '-' '+' verbatim; every other UTF-8 byte -> %XX
// uppercase hex). Minimum format EXCLUDES receipt, policy echoes, axes and
// source_pin although all are available on the binding. The oracle helpers
// below re-implement the pinned layout and the documented escape INDEPENDENTLY
// (no call into the formatter or escape_id), so the goldens fail on any
// layout, field, order, escape or content drift; nothing here is a snapshot
// blessed from formatter output.
use kni_core::master_fit_span_ledger::format_span_ledger;

/// Independent oracle for the documented escape (iou_report::escape_id).
fn sl_esc(s: &str) -> String {
    if s.is_empty() { return "%EMPTY".into(); }
    let mut o = String::new();
    for &b in s.as_bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-' | b'+') { o.push(b as char); }
        else { o.push_str(&format!("%{:02X}", b)) }
    }
    o
}

/// Independent oracle for the pinned v1 grammar over the binding's own values.
fn sl_expected_ledger(b: &MasterFitTraceBinding) -> String {
    let mut o = String::new();
    o.push_str("kni.span-ledger.v1\n");
    o.push_str("scope\tSTRUCTURAL_BINDING_ONLY\tidentity only; raw bounds UNVERIFIED; carried claims NOT verified\n");
    o.push_str(&format!("glyph\t{}\n", sl_esc(&b.glyph_id)));
    for m in &b.masters {
        o.push_str(&format!("master\t{}\tmaster_id={}\n", m.master_index, sl_esc(&m.master_id)));
        for (ri, r) in m.rings.iter().enumerate() {
            o.push_str(&format!("ring\t{}\tcorrespondence_id={}\tcaptured_ring_index={}\tstart_raw_index={}\n",
                ri, sl_esc(&r.correspondence_id), r.captured_ring_index, r.start_raw_index));
            for s in &r.spans {
                let chain = s.split_chain.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(",");
                let kind = match s.kind { SpanKind::Line => "line", SpanKind::Cubic => "cubic" };
                o.push_str(&format!("span\t{}\tkind={}\tcolumn={}\tpath={}\traw=({},{})\tsplits=[{}]\n",
                    s.span_index_in_ring, kind, s.source_column, sl_esc(&s.source_path),
                    s.column_raw_interval.0, s.column_raw_interval.1, chain));
            }
        }
    }
    o
}

/// Per-record TAB field counts from the pinned grammar (header 1, scope 3,
/// glyph 2, master 3, ring 5, span 7); asserts one record per line, a trailing
/// newline, and no unknown record type. Any extra field (coordinate, metric,
/// receipt, pin) breaks the counts even before the golden compare.
fn sl_assert_field_counts(out: &str) {
    let lines: Vec<&str> = out.split('\n').collect();
    assert_eq!(lines.last(), Some(&""), "ledger must end with a newline");
    for ln in &lines[..lines.len() - 1] {
        let want = match ln.split('\t').next().unwrap() {
            "kni.span-ledger.v1" => 1,
            "scope" => 3,
            "glyph" => 2,
            "master" => 3,
            "ring" => 5,
            "span" => 7,
            other => panic!("unknown record type: {other}"),
        };
        let got = ln.split('\t').count();
        assert_eq!(got, want, "record {ln:?} must have {want} TAB-separated fields");
    }
}

/// Hostile-ID fixture: carried IDs with TAB, LF, CRLF, backslash, percent and
/// a non-ASCII (Unicode) character - all VALID producer inputs (non-empty;
/// EmptyCorrespondenceId guards only the empty string; no charset rule exists
/// in the binding module). Every rename is consistent at construction:
/// MasterInput.master_id AND every LandmarkRef.master_id via lm(), plus the
/// ContourCorrespondence.correspondence_id and glyph_id on all inputs. No
/// post-hoc partial mutation.
fn hostile_set() -> MasterSet {
    let mk = |id: &str, w: f64, rx: f64, ry: f64| MasterInput { master_id: id.into(),
        axes: vec![AxisCoordinate { tag: *b"wght", value: w }], glyph_id: "oé".into(),
        captured: ellipse(rx, ry, 360), scale: 1.0, source_pin: "a".repeat(64) };
    let cols = [(0, LandmarkRole::XMax), (90, LandmarkRole::YMax), (180, LandmarkRole::XMin), (270, LandmarkRole::YMin)];
    let c = ContourCorrespondence { correspondence_id: "ou\nter\\x\r\ny".into(), hole: false, orientation: Orientation::Ccw,
        landmarks: cols.iter().map(|&(i, r)| vec![lm("li\tght", 0, i, r), lm("bo%ld", 0, i, r)]).collect() };
    MasterSet { inputs: vec![mk("li\tght", 300.0, 40.0, 60.0), mk("bo%ld", 700.0, 55.0, 62.0)], correspondence: vec![c] }
}

/// Injectivity spot-check fixture: master ids "aA" vs "a%41" (escaped forms
/// must stay distinct) plus a passthrough correspondence id using only the
/// verbatim byte set.
fn inject_set() -> MasterSet {
    let mk = |id: &str, w: f64, rx: f64, ry: f64| MasterInput { master_id: id.into(),
        axes: vec![AxisCoordinate { tag: *b"wght", value: w }], glyph_id: "o".into(),
        captured: ellipse(rx, ry, 360), scale: 1.0, source_pin: "a".repeat(64) };
    let cols = [(0, LandmarkRole::XMax), (90, LandmarkRole::YMax), (180, LandmarkRole::XMin), (270, LandmarkRole::YMin)];
    let c = ContourCorrespondence { correspondence_id: "c.1_x-2+3".into(), hole: false, orientation: Orientation::Ccw,
        landmarks: cols.iter().map(|&(i, r)| vec![lm("aA", 0, i, r), lm("a%41", 0, i, r)]).collect() };
    MasterSet { inputs: vec![mk("aA", 300.0, 40.0, 60.0), mk("a%41", 700.0, 55.0, 62.0)], correspondence: vec![c] }
}

#[test]
fn sl_p01_ellipse_exact_golden_and_layout() {
    let f = fit_master_set_bound(&set(), &pol()).unwrap();
    let b = f.binding();
    let out = format_span_ledger(&f);
    // golden: byte-exact against the independently-built expected ledger
    assert_eq!(out, sl_expected_ledger(b));
    sl_assert_field_counts(&out);
    // record count derived from the binding: 3 header lines + one master record
    // per master + one ring record per ring + one span record per span
    let mut want = 3;
    for m in &b.masters { want += 1; for r in &m.rings { want += 1 + r.spans.len(); } }
    assert_eq!(out.lines().count(), want, "one record per line, stored order");
    // fixture-stable content pins (landed p01/n20 evidence)
    assert!(out.contains("master\t0\tmaster_id=light\n"));
    assert!(out.contains("master\t1\tmaster_id=bold\n"));
    assert!(out.contains("ring\t0\tcorrespondence_id=outer\tcaptured_ring_index=0\tstart_raw_index=0\n"));
    let spans = &b.masters[0].rings[0].spans;
    assert_eq!(spans.len(), 4, "ellipse fixture: four single-leaf columns (landed n20 uses columns[3])");
    let k0 = match spans[0].kind { SpanKind::Line => "line", SpanKind::Cubic => "cubic" };
    assert!(out.contains(&format!("span\t0\tkind={k0}\tcolumn=0\tpath=%EMPTY\traw=(0,90)\tsplits=[]\n")),
        "span 0: interval (0,90) per landed p01; empty root path prints as the explicit %EMPTY marker, never blank");
    // the wrap column carries a WRAPPED interval as supplied, UNSORTED: landed
    // n20 proves column 3's interval is (270, 0) (start 270; the wrap guard
    // requires last_end == first_start == 0)
    assert_eq!(spans[3].column_raw_interval, (270, 0), "wrapped interval as supplied (landed n20 guard semantics)");
    assert!(out.contains("raw=(270,0)\tsplits=[]\n"), "wrapped pair prints UNSORTED, exactly as supplied");
    assert!(out.contains("\tsplits=[]\n"), "empty split chain renders as the explicit empty list");
    // every span's raw pair renders exactly as carried by the binding
    for m in &b.masters { for r in &m.rings { for s in &r.spans {
        assert!(out.contains(&format!("raw=({},{})", s.column_raw_interval.0, s.column_raw_interval.1)));
    } } }
}

#[test]
fn sl_p02_ellipse_excludes_receipt_policy_axes_and_pin() {
    let f = fit_master_set_bound(&set(), &pol()).unwrap();
    let b = f.binding();
    let out = format_span_ledger(&f);
    // minimum format: receipt, policy echoes, axes and source_pin are EXCLUDED
    // although all are available on the binding (chief ruling)
    assert!(!out.contains("receipt"));
    assert!(!out.contains("source_pin"));
    assert!(!out.contains(&"a".repeat(64)), "the fixture's source_pin value must never be printed");
    assert!(!out.contains("wght"), "axis tag must never be printed");
    assert!(!out.contains("axes"));
    assert!(!out.contains("squared_error"));
    assert!(!out.contains("max_refits"));
    assert!(!out.contains("tangent_lookahead_fraction"));
    assert!(!out.contains("max_split_depth"));
    assert!(!out.contains("split_fraction"));
    if b.receipt.len() >= 8 {
        assert!(!out.contains(&b.receipt), "the receipt value must never be printed");
    }
    // the exact header carries claims only, plus the glyph structural ID
    let mut it = out.lines();
    assert_eq!(it.next(), Some("kni.span-ledger.v1"));
    assert_eq!(it.next(), Some("scope\tSTRUCTURAL_BINDING_ONLY\tidentity only; raw bounds UNVERIFIED; carried claims NOT verified"));
    assert_eq!(it.next(), Some("glyph\to"));
}

#[test]
fn sl_p03_notch_chains_and_wrapped_interval_as_supplied() {
    let f = fit_master_set_bound(&notch_set(), &pol()).unwrap();
    let b = f.binding();
    let out = format_span_ledger(&f);
    assert_eq!(out, sl_expected_ledger(b));
    sl_assert_field_counts(&out);
    // span record count derived from the binding (not hardcoded); canonical
    // span_index order 0..N-1 within the ring
    let spans = &b.masters[0].rings[0].spans;
    let span_lines: Vec<&str> = out.lines().filter(|l| l.starts_with("span\t")).collect();
    assert_eq!(span_lines.len(), b.masters.iter().map(|m| m.rings.iter().map(|r| r.spans.len()).sum::<usize>()).sum::<usize>());
    for (i, l) in span_lines.iter().take(spans.len()).enumerate() {
        assert!(l.starts_with(&format!("span\t{i}\t")), "canonical span order within the ring");
    }
    // at least one nonempty split chain (landed p02 saw_chain evidence), each
    // rendered in binding traversal order via the golden; explicit token check:
    let mut saw_chain = false;
    for m in &b.masters { for r in &m.rings { for s in &r.spans {
        let chain = s.split_chain.iter().map(|i| i.to_string()).collect::<Vec<_>>().join(",");
        assert!(out.contains(&format!("splits=[{chain}]\n")));
        if !s.split_chain.is_empty() { saw_chain = true; }
    } } }
    assert!(saw_chain, "notch fixture must yield at least one nonempty split chain (landed p02)");
    // every interval prints exactly as supplied (the golden includes any
    // wrapped pair UNSORTED; the (270,0) wrap is pinned explicitly in sl_p01)
    for m in &b.masters { for r in &m.rings { for s in &r.spans {
        assert!(out.contains(&format!("raw=({},{})", s.column_raw_interval.0, s.column_raw_interval.1)));
    } } }
}

#[test]
fn sl_p04_tworing_order_and_record_sequence() {
    let f = fit_master_set_bound(&tworing_set(), &pol()).unwrap();
    let b = f.binding();
    let out = format_span_ledger(&f);
    assert_eq!(out, sl_expected_ledger(b));
    sl_assert_field_counts(&out);
    // fixture-stable ring identity (landed p03): correspondence order in both
    // masters; per-master captured ring and start maps differ
    assert!(out.contains("master\t0\tmaster_id=light\nring\t0\tcorrespondence_id=outer\tcaptured_ring_index=0\tstart_raw_index=0\n"));
    assert!(out.contains("ring\t1\tcorrespondence_id=hole\tcaptured_ring_index=1\tstart_raw_index=10\n"));
    assert!(out.contains("master\t1\tmaster_id=bold\nring\t0\tcorrespondence_id=outer\tcaptured_ring_index=1\tstart_raw_index=5\n"));
    assert!(out.contains("ring\t1\tcorrespondence_id=hole\tcaptured_ring_index=0\tstart_raw_index=20\n"));
    // ordering contract: the record-ID token sequence equals the binding's own
    // traversal order exactly - fails on any reordering, grouping or sorting
    let mut want: Vec<String> = vec!["header".into(), "scope".into(), format!("glyph:{}", sl_esc(&b.glyph_id))];
    for m in &b.masters {
        want.push(format!("master:{}", m.master_index));
        for r in &m.rings {
            want.push(format!("ring:{}", sl_esc(&r.correspondence_id)));
            for s in &r.spans { want.push(format!("span:{}", s.span_index_in_ring)); }
        }
    }
    let got: Vec<String> = out.lines().map(|l| {
        let f0: Vec<&str> = l.split('\t').collect();
        match f0[0] {
            "kni.span-ledger.v1" => "header".to_string(),
            "scope" => "scope".to_string(),
            "glyph" => format!("glyph:{}", f0[1]),
            "master" => format!("master:{}", f0[1]),
            "ring" => format!("ring:{}", f0[2].strip_prefix("correspondence_id=").unwrap()),
            "span" => format!("span:{}", f0[1]),
            other => panic!("unknown record type: {other}"),
        }
    }).collect();
    assert_eq!(got, want, "record order must equal binding traversal order exactly (no sort, no group, no reorder)");
}

#[test]
fn sl_p05_hostile_ids_escape_exactly() {
    let f = fit_master_set_bound(&hostile_set(), &pol()).unwrap();
    let out = format_span_ledger(&f);
    // exact escaped renderings, character for character, under the pinned
    // escape_id scheme: TAB %09, LF %0A, CR %0D, backslash %5C, '%' %25,
    // U+00E9 (UTF-8 bytes C3 A9) %C3%A9
    assert!(out.contains("glyph\to%C3%A9\n"));
    assert!(out.contains("master\t0\tmaster_id=li%09ght\n"));
    assert!(out.contains("master\t1\tmaster_id=bo%25ld\n"));
    assert!(out.contains("correspondence_id=ou%0Ater%5Cx%0D%0Ay\t"));
    // no raw TAB / LF / CR / backslash from any ID reaches the output; the
    // record-per-line and TAB-field structure stays unambiguous
    assert!(!out.contains("li\tght"));
    assert!(!out.contains("bo%ld"));
    assert!(!out.contains("ou\nter"));
    assert!(!out.contains("ter\\x"));
    assert!(!out.contains('\r'));
    sl_assert_field_counts(&out);
    // the golden still holds over the hostile binding
    assert_eq!(out, sl_expected_ledger(f.binding()));
}

#[test]
fn sl_p06_escape_injective_and_literal_passthrough() {
    let f = fit_master_set_bound(&inject_set(), &pol()).unwrap();
    let out = format_span_ledger(&f);
    // "aA" passes verbatim; "a%41" becomes "a%2541" - distinct renderings of
    // distinct raw ids (injectivity spot-check)
    assert!(out.contains("master_id=aA\n"));
    assert!(out.contains("master_id=a%2541\n"));
    assert!(!out.contains("master_id=a%41\n"));
    // the verbatim byte set [A-Za-z0-9._-+] renders unchanged
    assert!(out.contains("correspondence_id=c.1_x-2+3\t"));
    assert_eq!(out, sl_expected_ledger(f.binding()));
}

#[test]
fn sl_p07_determinism() {
    let f = fit_master_set_bound(&tworing_set(), &pol()).unwrap();
    let out1 = format_span_ledger(&f);
    let out2 = format_span_ledger(&f);
    assert_eq!(out1, out2, "same input, byte-identical output");
    let g = fit_master_set_bound(&tworing_set(), &pol()).unwrap();
    assert_eq!(out1, format_span_ledger(&g),
        "two independently produced bindings of the same fixture render byte-identical");
}

#[test]
fn sl_p08_actual_output_claim_labels() {
    let f = fit_master_set_bound(&set(), &pol()).unwrap();
    let out = format_span_ledger(&f);
    // asserted against the ACTUAL formatter output, never a doc comment
    let mut it = out.lines();
    assert_eq!(it.next(), Some("kni.span-ledger.v1"));
    let scope = it.next().unwrap();
    assert!(scope.contains("STRUCTURAL_BINDING_ONLY"));
    assert!(scope.contains("raw bounds UNVERIFIED"));
    assert!(scope.contains("carried claims NOT verified"));
    assert_eq!(scope, "scope\tSTRUCTURAL_BINDING_ONLY\tidentity only; raw bounds UNVERIFIED; carried claims NOT verified");
}
