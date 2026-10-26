// Regression: zero-area emission guard (always-output contract).
// A thin sub-tolerance streak (marker-drawn dash row: one source pixel
// tall) traces to a sliver whose corners the stub band suppresses; the
// fit then collapsed the ring to a zero-area out-and-back line and the
// profiler saw no ink (Marq Standard hyphen/endash/emdash class). The
// guard re-emits the captured polygon as Line spans with a typed
// FallbackReason::AreaCollapseRestored ledger event. Rings the fit
// represents with real area are untouched (bit-identical path).

use kni_core::capture::capture_gray;
use kni_core::capture_fit::{fit_captured_with_typed_ledgers, round_and_clean_ring, FallbackReason};
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::{ReferenceRing, Span};

const SCALE: f64 = 1.9651741293532339; // Marq run scale (style-scales binding)
const POL: FitPolicy = FitPolicy { squared_error: 0.25, max_refits: 8 }; // Marq run policy

fn ring_chord_area(r: &ReferenceRing) -> f64 {
    let mut a2 = 0.0f64;
    let mut cur = r.start;
    for sp in &r.spans {
        let end = match sp { Span::Line { end } => *end, Span::Cubic { end, .. } => *end };
        a2 += cur.x * end.y - end.x * cur.y;
        cur = end;
    }
    a2 += cur.x * r.start.y - r.start.x * cur.y;
    a2.abs() / 2.0
}

fn streak_tile(streak_rows: usize, ink: u8) -> (usize, usize, Vec<u8>) {
    let (w, h) = (600usize, 400usize);
    let mut gray = vec![255u8; w * h];
    for k in 0..18 {
        let y0 = 50 + k * 6;
        let x0 = 60 + (k * 7) % 90;
        let x1 = 500 - (k * 3) % 60;
        for r in 0..streak_rows {
            for x in x0..x1.min(w) {
                gray[(y0 + r) * w + x] = ink;
            }
        }
    }
    (w, h, gray)
}

#[test]
fn one_px_streak_rings_ship_with_their_captured_area() {
    let (w, h, gray) = streak_tile(1, 100);
    let mc = capture_gray(w, h, &gray, 0.25).expect("streak tile captures");
    assert_eq!(mc.rings.len(), 18, "18 streak rows trace as 18 slivers");
    let (rings, _spans, _fb, dropped, fevents, _astubs, _declined) =
        fit_captured_with_typed_ledgers(&mc.rings, SCALE, &POL);
    assert_eq!(dropped, 0, "every sliver carried >= the half-pixel-square capture area");
    assert_eq!(rings.len(), 18, "no sliver lost");
    let restored = fevents.iter().filter(|e| e.reason == FallbackReason::AreaCollapseRestored).count();
    assert_eq!(restored, 18, "every collapsed sliver restored with a typed ledger event");
    for r in &rings {
        assert!(ring_chord_area(r) > 0.5 * SCALE * SCALE,
            "shipped ring keeps measurable ink area, not an out-and-back line");
        assert!(r.spans.len() >= 3, "restored ring is a closed polygon, not 2 spans");
    }
}

#[test]
fn healthy_ring_path_is_bit_identical_no_guard_event() {
    // A solid block with real area: the guard must not fire and the emitted
    // rings must be exactly what the unguarded pipeline produces.
    let (w, h) = (200usize, 200usize);
    let mut gray = vec![255u8; w * h];
    for y in 50..150 {
        for x in 50..150 {
            gray[y * w + x] = 0;
        }
    }
    let mc = capture_gray(w, h, &gray, 0.25).expect("block captures");
    let (rings, _spans, _fb, _dropped, fevents, _astubs, _declined) =
        fit_captured_with_typed_ledgers(&mc.rings, SCALE, &POL);
    assert!(fevents.iter().all(|e| e.reason != FallbackReason::AreaCollapseRestored),
        "no restore event on the healthy path");
    assert_eq!(rings.len(), 1);
    let area = ring_chord_area(&rings[0]);
    assert!(area > 90.0 * SCALE * SCALE, "block area preserved ({area})");
    // Every emitted span of a healthy rectangle stays a plain 4-side fit
    // (Line sides); the guard adds nothing.
    assert_eq!(rings[0].spans.len(), 4, "rectangle ships as 4 sides, unchanged");
}

/// Marq A r2558 class: a horizontal stroke row of marker fragments
/// (5x1 px slivers on a ~7 px ladder, the cached y=-1029 pattern).
/// Chain: capture -> fit -> 1.0-unit integer round. Old chain collapsed
/// each fragment to a zero-area out-and-back and then to single-point
/// rings (profiler DegenerateRing -> glyph dropped). Post-fix: every
/// fragment is restored by the zero-area guard and SURVIVES the integer
/// lattice as real geometry; no 1-point ring can be emitted.
#[test]
fn stroke_fragment_ladder_survives_fit_and_integer_rounding() {
    let (w, h) = (600usize, 400usize);
    let mut gray = vec![255u8; w * h];
    // letter body so the glyph has ordinary rings too
    for y in 60..340 {
        for x in 60..120 {
            gray[y * w + x] = 0;
        }
    }
    // fragment ladder: 8 fragments, 5x1 px, 7 px pitch (cached A pattern)
    for k in 0..8 {
        let x0 = 200 + k * 7;
        for x in x0..x0 + 5 {
            gray[200 * w + x] = 100;
        }
    }
    let mc = capture_gray(w, h, &gray, 0.25).expect("capture");
    let (float, _n, _fb, dropped, fevents, _a, _d) =
        fit_captured_with_typed_ledgers(&mc.rings, SCALE, &POL);
    assert_eq!(dropped, 0);
    let restored = fevents.iter().filter(|e| e.reason == FallbackReason::AreaCollapseRestored).count();
    assert_eq!(restored, 8, "every fragment's fit collapse caught by the guard");
    for r in &float {
        let rr = round_and_clean_ring(r, 1.0);
        let mut pts = vec![rr.start];
        for sp in &rr.spans {
            match sp { Span::Line { end } => pts.push(*end), Span::Cubic { end, .. } => pts.push(*end) }
        }
        let mut u = pts.clone();
        u.sort_by(|a, b| a.x.partial_cmp(&b.x).unwrap().then(a.y.partial_cmp(&b.y).unwrap()));
        u.dedup();
        assert!(u.len() >= 2, "no single-point ring after the integer lattice (the A r2558 terminal)");
    }
}
