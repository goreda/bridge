//! End-to-end: owner R scan -> engine-internal capture -> corner-split gated
//! fit -> CFF container encode. No external rasterizer or contour tool runs
//! in this pipeline; the fixture is the owner-supplied scan PNG.

use kni_core::capture::capture_png;
use kni_core::capture_fit::{fit_captured, fit_captured_with_fallback_events};
use kni_core::cff_container::CffGlyph;
use kni_core::cubic_fit::FitPolicy;
use kni_core::native_font::{encode, NativeFontInput};
use kni_core::reference_slice::{DrawnGlyph, Point, Span};
use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, NameRecord, Os2Metadata, PostMetadata};

#[test]
fn capture_fit_encode_r_scan() {
    let png = include_bytes!("fixtures/r_scan.png");
    let mc = capture_png(png, 0.29).expect("capture"); // 02 contract: eps <= 0.29px
    assert_eq!(mc.rings.len(), 2, "R scan: outer ring + counter");
    assert!(!mc.rings[0].hole);
    assert!(mc.rings[1].hole);
    let mut mxy = 0f64;
    for r in &mc.rings {
        for p in &r.points {
            mxy = mxy.max(p.y);
        }
    }
    let scale = 700.0 / mxy;
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let (rings, total_spans, status, dropped, fevents) = fit_captured_with_fallback_events(&mc.rings, scale, &policy);
    // Capture status derives from the finalized typed fallback ledger
    // (has_unresolved == !events.is_empty()). This asserts the status/ledger
    // contract, NOT a fit-quality claim.
    assert_eq!(status, !fevents.is_empty(), "status must derive from the finalized typed fallback ledger");
    // PN-3 fallback rescue (capture_fit) + architect rule (a): the
    // damped-Newton rescue + corner resplit + strict-reduction partial
    // adoption, plus event-free acceptance of in-bound ambiguous-lineage
    // Lines with a real (>=3-sample) measurement, resolve all 22 historical
    // SplitUnresolved events on this fixture at its own policy; the typed
    // DeclinedAmbiguity receipts remain in the ledger (honesty preserved),
    // the hard-fail gate input reads empty (status false).
    assert_eq!(fevents.len(), 0, "typed fallback ledger count changed");
    assert!(!status, "fixture resolves fully under its policy; honest status is false");
    // Wrapper parity: the plain and ledger-returning wrappers agree on
    // geometry, span count, status, and dropped for the same input.
    let (rings_p, total_spans_p, status_p, dropped_p) = fit_captured(&mc.rings, scale, &policy);
    assert_eq!(total_spans_p, total_spans);
    assert_eq!(status_p, status);
    assert_eq!(dropped_p, dropped);
    assert_eq!(format!("{:?}", rings_p), format!("{:?}", rings), "wrapper parity: rings must be identical");
    assert!(total_spans >= 8, "expected fitted spans, got {}", total_spans);
    // closure: every ring's last span end equals its start
    for r in &rings {
        let last_end = match r.spans.last().unwrap() {
            Span::Line { end } => *end,
            Span::Cubic { end, .. } => *end,
        };
        assert_eq!(last_end, r.start, "ring must close exactly");
    }
    let mut mn = [i32::MAX; 2];
    let mut mx = [i32::MIN; 2];
    for r in &rings {
        let mut pts = vec![r.start];
        for s in &r.spans {
            match s {
                Span::Line { end } => pts.push(*end),
                Span::Cubic { control_one, control_two, end } => {
                    pts.push(*control_one);
                    pts.push(*control_two);
                    pts.push(*end);
                }
            }
        }
        for p in pts {
            mn[0] = mn[0].min(p.x as i32);
            mn[1] = mn[1].min(p.y as i32);
            mx[0] = mx[0].max(p.x as i32);
            mx[1] = mx[1].max(p.y as i32);
        }
    }
    // plausible gate: font bbox stays sane relative to cap height 700
    assert!(mx[0] - mn[0] < 1400, "bbox width sanity");
    assert!(mx[1] - mn[1] < 1400, "bbox height sanity");
    let adv = (mx[0] - mn[0] + 120) as u16;
    let lsb = 60i16;
    let extent = (lsb as i32 + (mx[0] - mn[0])) as i16;
    let rsb = (adv as i32 - extent as i32) as i16;
    let empty = CffGlyph {
        name: ".notdef".into(),
        advance: 500,
        outline: DrawnGlyph { glyph_id: "notdef".into(), rings: vec![] },
    };
    let g = CffGlyph { name: "R".into(), advance: adv, outline: DrawnGlyph { glyph_id: "R".into(), rings } };
    let input = NativeFontInput {
        postscript_name: "KNIRScanEngine-Regular".into(),
        glyphs: vec![empty, g],
        left_side_bearings: vec![0, lsb],
        mapping: vec![(82, 1)],
        head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [mn[0] as i16, mn[1] as i16, mx[0] as i16, mx[1] as i16], mac_style: 0, lowest_ppem: 1 },
        hhea: HheaMetadata { ascender: 800, descender: -200, line_gap: 0, advance_max: adv.max(500), min_lsb: 60, min_rsb: rsb, max_extent: extent, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 2 },
        post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 1, memory: [0; 4] },
        os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 2, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0, panose: [0; 10], unicode_ranges: [1, 0, 0, 0], vendor: *b"KNI0", selection: 64, first_char: 82, last_char: 82, typo: [800, -200, 0], win_ascent: 800, win_descent: 200, version: 0, cap_height: 0, x_height: 0 },
        names: [(1u16, "KNI R Scan Engine"), (2, "Regular"), (3, "KNI R Scan Engine:1"), (4, "KNI R Scan Engine Regular"), (5, "Version 1.0"), (6, "KNIRScanEngine-Regular")]
            .iter()
            .map(|(id, t)| NameRecord { language: 0x409, name_id: *id, value: t.to_string() })
            .collect(),
    };
    let data = encode(&input).expect("encode");
    assert_eq!(&data[..4], b"OTTO", "CFF sfnt magic");
    assert!(data.len() < 4096, "single-glyph font stays small");
    let _ = Point { x: 0.0, y: 0.0 };
}

#[test]
fn fallback_flag_set_on_degenerate_ring() {
    // duplicate leading point -> zero-length first chord -> adjacent_chord_tangents
    // returns None -> polyline fallback must set the flag.
    use kni_core::capture_fit::fit_ring;
    let pts = vec![
        Point { x: 0.0, y: 0.0 },
        Point { x: 0.0, y: 0.0 },
        Point { x: 100.0, y: 0.0 },
        Point { x: 100.0, y: 100.0 },
    ];
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let (_ring, _ns, fb) = fit_ring(pts, vec![], &policy);
    assert!(fb, "degenerate input must report fallback=true");
}

#[test]
fn wrap_dedup_keeps_sharper() {
    // Rectangle with sharp 90+ deg corners at indices 1, 20, 40 and a
    // blunter corner at index 58 (wrap-adjacent to index 1: distance
    // n-(58-1)=3 < k=4). Suppression must keep index 1 and drop 58.
    let mut pts: Vec<Point> = Vec::new();
    pts.push(Point { x: 50.0, y: 0.0 }); // 0: bottom edge
    pts.push(Point { x: 100.0, y: 0.0 }); // 1: sharp corner B
    for i in 1..=18 { pts.push(Point { x: 100.0, y: 10.0 * i as f64 }); } // 2..=19 right edge
    pts.push(Point { x: 100.0, y: 200.0 }); // 20: corner C
    for i in 1..=19 { pts.push(Point { x: 100.0 - 10.0 * i as f64, y: 200.0 }); } // 21..=39 top edge
    pts.push(Point { x: -80.0, y: 200.0 }); // 40: corner D
    for i in 1..=17 { pts.push(Point { x: -80.0, y: 200.0 - 10.0 * i as f64 }); } // 41..=57 left edge
    pts.push(Point { x: -80.0, y: 20.0 }); // 58: blunt corner (window turn ~90 deg, blunter than B's ~99 deg)
    pts.push(Point { x: -20.0, y: 0.0 }); // 59: bottom edge
    let cs = kni_core::capture::corners(&pts);
    assert!(cs.contains(&1), "sharper wrap candidate at 1 must survive, got {:?}", cs);
    assert!(!cs.contains(&58), "blunter wrap neighbor 58 must lose, got {:?}", cs);
    assert_eq!(cs.len(), 3, "exactly the three true corners, got {:?}", cs);
}
