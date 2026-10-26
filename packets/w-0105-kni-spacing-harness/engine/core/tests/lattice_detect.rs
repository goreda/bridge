// LATTICE-1 prototype tests (harness-only): synthetic lattice fixtures for
// the detector and classifier, plus the stage-2 -> stage-3 link guard (a
// classified lattice_dot must pass the existing circle recognition so the
// later routing stage has a live target). No production code involved.

#[path = "../src/lattice.rs"]
mod lattice;

use kni_core::capture::CapturedRing;
use kni_core::form::recognize_circle_ring;
use kni_core::reference_slice::Point;
use lattice::{classify_contour, detect_lattice, ring_features, ContourClass, LatticeStatus};

fn regular_ngon(cx: f64, cy: f64, r: f64, n: usize) -> Vec<Point> {
    (0..n)
        .map(|i| {
            let a = i as f64 / n as f64 * std::f64::consts::TAU;
            Point { x: cx + r * a.cos(), y: cy + r * a.sin() }
        })
        .collect()
}

fn ring(points: Vec<Point>, corners: Vec<usize>, hole: bool) -> CapturedRing {
    CapturedRing { raw: points.clone(), points, corners, hole }
}

fn grid_glyph(_name: &str, ox: f64, oy: f64, nx: usize, ny: usize, spacing: f64, r: f64) -> Vec<CapturedRing> {
    let mut out = Vec::new();
    for iy in 0..ny {
        for ix in 0..nx {
            out.push(ring(
                regular_ngon(ox + ix as f64 * spacing, oy + iy as f64 * spacing, r, 16),
                vec![],
                false,
            ));
        }
    }
    out
}

fn bar(cx: f64, cy: f64, w: f64, h: f64) -> CapturedRing {
    ring(
        vec![
            Point { x: cx - w / 2.0, y: cy - h / 2.0 },
            Point { x: cx + w / 2.0, y: cy - h / 2.0 },
            Point { x: cx + w / 2.0, y: cy + h / 2.0 },
            Point { x: cx - w / 2.0, y: cy + h / 2.0 },
        ],
        vec![0, 1, 2, 3],
        false,
    )
}

fn features_of(glyphs: &[(String, Vec<CapturedRing>)]) -> Vec<lattice::RingFeatures> {
    let mut v = Vec::new();
    for (g, rings) in glyphs {
        for (i, r) in rings.iter().enumerate() {
            v.push(ring_features(g, i, r));
        }
    }
    v
}

#[test]
fn detects_square_grid_and_classifies_dots() {
    // 6 glyphs of a 4x5 dot grid each (spacing 40px, radius 9px) -> 120 dots.
    let glyphs: Vec<(String, Vec<CapturedRing>)> = (0..6)
        .map(|g| (format!("g{g}"), grid_glyph("x", 20.0, 20.0, 4, 5, 40.0, 9.0)))
        .collect();
    let feats = features_of(&glyphs);
    let status = detect_lattice(&feats);
    let p = match status {
        LatticeStatus::Detected(p) => p,
        LatticeStatus::NoLattice { failed_check } => panic!("expected detected, got no_lattice {failed_check}"),
    };
    assert!((p.spacing - 40.0).abs() < 4.0, "spacing {}", p.spacing);
    assert!((p.dot_radius - 9.0).abs() < 2.0, "radius {}", p.dot_radius);
    assert!(p.coverage >= 0.99, "coverage {}", p.coverage);
    // exercise the full typed surface so the harness stays warning-free
    assert_eq!(p.glyph_count, 6);
    assert!(p.candidate_count >= p.dot_count);
    assert!(p.dot_radius_tol > 0.0);
    assert!(p.per_glyph_phase_agreement >= 0.99);
    assert_eq!(ContourClass::LatticeDot.as_str(), "lattice_dot");
    assert_eq!(ContourClass::Ambiguous.as_str(), "ambiguous");
    for f in &feats {
        assert!(f.area > 0.0 && f.perimeter > 0.0);
        assert!(f.ring_index < 20);
        assert!(f.n_points >= 16 && f.n_corners == 0);
    }
    let dots = feats
        .iter()
        .filter(|f| classify_contour(f, &p) == ContourClass::LatticeDot)
        .count();
    assert_eq!(dots, feats.len());
}

#[test]
fn strokes_only_style_is_no_lattice() {
    let glyphs: Vec<(String, Vec<CapturedRing>)> = (0..4)
        .map(|g| {
            (
                format!("g{g}"),
                vec![bar(50.0, 200.0, 30.0, 320.0), bar(150.0, 200.0, 30.0, 300.0)],
            )
        })
        .collect();
    let feats = features_of(&glyphs);
    match detect_lattice(&feats) {
        LatticeStatus::NoLattice { failed_check } => assert_eq!(failed_check, "dot_cluster_size"),
        LatticeStatus::Detected(_) => panic!("bars must not detect a lattice"),
    }
}

#[test]
fn tiny_speck_population_below_floor_is_no_lattice() {
    // 8 dots only: below MIN_DOT_COUNT even though perfectly circular.
    let glyphs = vec![("g0".to_string(), grid_glyph("x", 10.0, 10.0, 4, 2, 30.0, 6.0))];
    let feats = features_of(&glyphs);
    match detect_lattice(&feats) {
        LatticeStatus::NoLattice { .. } => {}
        LatticeStatus::Detected(_) => panic!("8 dots must not detect a lattice"),
    }
}

#[test]
fn off_lattice_dot_is_not_reclassified() {
    let mut glyphs: Vec<(String, Vec<CapturedRing>)> = (0..5)
        .map(|g| (format!("g{g}"), grid_glyph("x", 20.0, 20.0, 4, 5, 40.0, 9.0)))
        .collect();
    // one dot shifted half a cell off the grid in glyph 0
    glyphs[0].1.push(ring(regular_ngon(20.0 + 20.0, 20.0 + 20.0, 9.0, 16), vec![], false));
    let feats = features_of(&glyphs);
    let p = match detect_lattice(&feats) {
        LatticeStatus::Detected(p) => p,
        LatticeStatus::NoLattice { failed_check } => panic!("no_lattice {failed_check}"),
    };
    // glyph 0 holds 4x5 = 20 grid dots; the stray is ring index 20
    let stray = &feats[20];
    assert_ne!(
        classify_contour(stray, &p),
        ContourClass::LatticeDot,
        "off-lattice dot must stay out of the dot path"
    );
}

#[test]
fn stroke_glyph_inside_dot_style_stays_stroke() {
    let mut glyphs: Vec<(String, Vec<CapturedRing>)> = (0..5)
        .map(|g| (format!("g{g}"), grid_glyph("x", 20.0, 20.0, 4, 5, 40.0, 9.0)))
        .collect();
    glyphs[0].1.push(bar(80.0, 60.0, 24.0, 200.0)); // a stem among the dots
    let feats = features_of(&glyphs);
    let p = match detect_lattice(&feats) {
        LatticeStatus::Detected(p) => p,
        LatticeStatus::NoLattice { failed_check } => panic!("no_lattice {failed_check}"),
    };
    // glyph 0 holds 4x5 = 20 grid dots; the stem is ring index 20
    let stem = &feats[20];
    assert_eq!(classify_contour(stem, &p), ContourClass::Stroke);
}

#[test]
fn lattice_dot_passes_existing_circle_recognition() {
    // The stage-2 -> stage-3 link the owner asked about: a dot the classifier
    // accepts must be accepted by the existing Unit-font circle path at Mona
    // Alt parameters (scale 1.8217, t_circle = 1.0*scale, rdp_eps = 0.5*scale).
    let scale = 1.821705426356589f64;
    let dot_px = regular_ngon(60.0, 60.0, 16.0, 48);
    let pts: Vec<Point> = dot_px.iter().map(|p| Point { x: p.x * scale, y: p.y * scale }).collect();
    let out = recognize_circle_ring(&pts, &[], false, 1.0 * scale, 0.5 * scale);
    assert!(out.is_some(), "radius-16px dot must pass circle recognition at Mona Alt scale");
    assert_eq!(out.unwrap().spans.len(), 4, "circle emits 4 nodes");
}

#[test]
fn small_dot_below_proof_limit_abstains_by_design() {
    // documents the current abstention the probe measures on Mona Alt: radius
    // under ~14.6px makes the angular-coverage proof limit exceed 45 deg
    // (limit = 3*sqrt(2*rdp_eps/r) with rdp_eps = 0.5px, scale-invariant).
    let scale = 1.821705426356589f64;
    let dot_px = regular_ngon(60.0, 60.0, 9.0, 48);
    let pts: Vec<Point> = dot_px.iter().map(|p| Point { x: p.x * scale, y: p.y * scale }).collect();
    assert!(recognize_circle_ring(&pts, &[], false, 1.0 * scale, 0.5 * scale).is_none());
}

#[test]
fn dot_with_declared_corners_is_refused_by_circle_gate() {
    let scale = 1.821705426356589f64;
    let dot_px = regular_ngon(60.0, 60.0, 16.0, 48);
    let pts: Vec<Point> = dot_px.iter().map(|p| Point { x: p.x * scale, y: p.y * scale }).collect();
    assert!(recognize_circle_ring(&pts, &[7], false, 1.0 * scale, 0.5 * scale).is_none());
}
