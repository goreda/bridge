//! Slice A decomposition tests: h-like (with 37-degree rotation), k-like,
//! ring, bar, ring + detached mark, and the reference R export outline.
//! Assertions are on part classes, provenance presence and silhouette
//! reconstruction, never on node counts.

use kni_master::decompose::{decompose, Decomposition, PartClass};
use kni_master::fixture::parse;
use kni_master::model::{MasterGlyph, Op, Pt, StrokeContour};
use kni_master::raster::{bounds_of, paired_iou, rasterize};

const KAPPA: f64 = 0.5522847498;

fn contour(ops: Vec<Op>) -> StrokeContour {
    StrokeContour { stroke: String::new(), ops }
}

fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> StrokeContour {
    contour(vec![
        Op::Move((x0, y0)),
        Op::Line((x1, y0)),
        Op::Line((x1, y1)),
        Op::Line((x0, y1)),
        Op::Close,
    ])
}

/// Cubic arc from angle a0 to a1 (degrees), at most 90 deg per piece.
fn arc_ops(cx: f64, cy: f64, r: f64, a0: f64, a1: f64) -> Vec<Op> {
    let mut ops = Vec::new();
    let dir = (a1 - a0).signum();
    let mut a = a0;
    while (a1 - a).abs() > 1e-9 {
        let b = a + dir * (a1 - a).abs().min(90.0);
        let k = 4.0 / 3.0 * (((b - a) / 4.0).to_radians()).tan();
        let (sa, ca) = a.to_radians().sin_cos();
        let (sb, cb) = b.to_radians().sin_cos();
        let p0 = (cx + r * ca, cy + r * sa);
        let p1 = (cx + r * cb, cy + r * sb);
        // Tangent for increasing angle is (-sin, cos); k carries the sign.
        ops.push(Op::Curve(
            (p0.0 + k * r * -sa, p0.1 + k * r * ca),
            (p1.0 - k * r * -sb, p1.1 - k * r * cb),
            p1,
        ));
        a = b;
    }
    let _ = KAPPA;
    ops
}

fn circle(cx: f64, cy: f64, r: f64, ccw: bool) -> StrokeContour {
    let mut ops = vec![Op::Move((cx + r, cy))];
    let (a0, a1) = if ccw { (0.0, 360.0) } else { (360.0, 0.0) };
    ops.extend(arc_ops(cx, cy, r, a0, a1));
    ops.push(Op::Close);
    contour(ops)
}

/// Rotated rectangle around the a->b axis with width wd.
fn bar(a: Pt, b: Pt, wd: f64) -> StrokeContour {
    let dx = b.0 - a.0;
    let dy = b.1 - a.1;
    let l = dx.hypot(dy);
    let (px, py) = (-dy / l * wd / 2.0, dx / l * wd / 2.0);
    contour(vec![
        Op::Move((a.0 + px, a.1 + py)),
        Op::Line((a.0 - px, a.1 - py)),
        Op::Line((b.0 - px, b.1 - py)),
        Op::Line((b.0 + px, b.1 + py)),
        Op::Close,
    ])
}

fn rotate_pt(p: Pt, deg: f64) -> Pt {
    let (s, c) = deg.to_radians().sin_cos();
    (p.0 * c - p.1 * s, p.0 * s + p.1 * c)
}

fn rotate_glyph(g: &MasterGlyph, deg: f64) -> MasterGlyph {
    let map = |o: &Op| match o {
        Op::Move(p) => Op::Move(rotate_pt(*p, deg)),
        Op::Line(p) => Op::Line(rotate_pt(*p, deg)),
        Op::Curve(a, b, p) => Op::Curve(rotate_pt(*a, deg), rotate_pt(*b, deg), rotate_pt(*p, deg)),
        Op::Close => Op::Close,
    };
    MasterGlyph {
        name: g.name.clone(),
        advance: g.advance,
        upm: g.upm,
        contours: g
            .contours
            .iter()
            .map(|c| contour(c.ops.iter().map(&map).collect()))
            .collect(),
    }
}

fn glyph(name: &str, contours: Vec<StrokeContour>) -> MasterGlyph {
    MasterGlyph { name: name.to_string(), advance: 0.0, upm: 1000.0, contours }
}

/// h-like: stem + arch (half-annulus) + right bar, one open outer contour.
fn h_like() -> MasterGlyph {
    let mut ops = vec![
        Op::Move((60.0, 0.0)),
        Op::Line((60.0, 260.0)),
        Op::Line((100.0, 260.0)),
        Op::Line((100.0, 160.0 + (90.0_f64 * 90.0 - 50.0 * 50.0).sqrt())),
    ];
    ops.extend(arc_ops(150.0, 160.0, 90.0, 123.69006752597977, 0.0));
    ops.extend([
        Op::Line((240.0, 0.0)),
        Op::Line((200.0, 0.0)),
        Op::Line((200.0, 160.0)),
    ]);
    ops.extend(arc_ops(150.0, 160.0, 50.0, 0.0, 180.0));
    ops.extend([Op::Line((100.0, 0.0)), Op::Close]);
    glyph("h_like", vec![contour(ops)])
}

/// k-like: stem + two diagonal bars (overlapping source contours).
fn k_like() -> MasterGlyph {
    glyph(
        "k_like",
        vec![
            rect(60.0, 0.0, 100.0, 260.0),
            bar((100.0, 150.0), (230.0, 255.0), 40.0),
            bar((100.0, 140.0), (230.0, 5.0), 40.0),
        ],
    )
}

fn ring() -> MasterGlyph {
    glyph("ring", vec![circle(150.0, 150.0, 110.0, true), circle(150.0, 150.0, 50.0, false)])
}

fn bar_only() -> MasterGlyph {
    glyph("bar_only", vec![rect(60.0, 0.0, 100.0, 260.0)])
}

fn ring_with_mark() -> MasterGlyph {
    glyph(
        "ring_with_mark",
        vec![
            circle(150.0, 150.0, 110.0, true),
            circle(150.0, 150.0, 50.0, false),
            rect(140.0, 300.0, 170.0, 330.0),
        ],
    )
}

fn reference_r() -> MasterGlyph {
    parse(include_str!("fixtures/reference_r_export.glyph")).expect("fixture parses")
}

/// Split a StrokeContour into single-subpath op lists.
fn subpaths(c: &StrokeContour) -> Vec<Vec<Op>> {
    let mut out: Vec<Vec<Op>> = Vec::new();
    for op in &c.ops {
        if matches!(op, Op::Move(_)) || out.is_empty() {
            out.push(Vec::new());
        }
        out.last_mut().unwrap().push(op.clone());
    }
    out
}

/// IoU of the decomposition's union silhouette against the source outline.
fn reconstruction_iou(src: &MasterGlyph, d: &Decomposition) -> f64 {
    let src_polys: Vec<Vec<Pt>> = src.contours.iter().map(kni_master::check::stroke_polygon).collect();
    let mut part_polys: Vec<Vec<Pt>> = Vec::new();
    for c in &d.glyph.contours {
        for sp in subpaths(c) {
            part_polys.push(kni_master::check::stroke_polygon(&StrokeContour {
                stroke: String::new(),
                ops: sp,
            }));
        }
    }
    let b = bounds_of(&[&src_polys, &part_polys], 2.0);
    let span = (b.2 - b.0).max(b.3 - b.1);
    let px = span / 640.0;
    let (_, _, m_src) = rasterize(&src_polys, true, b, px, (0.5, 0.5));
    let (_, _, m_part) = rasterize(&part_polys, true, b, px, (0.5, 0.5));
    paired_iou(&m_part, &m_src).0
}

fn classes(d: &Decomposition) -> Vec<PartClass> {
    let mut v: Vec<PartClass> = d.parts.iter().map(|p| p.class).collect();
    v.sort_by_key(|c| c.as_str().to_string());
    v
}

fn check_common(src: &MasterGlyph, d: &Decomposition) {
    // A -> B/C structural contract: one closed ring per structural stroke,
    // counters as separate rings.
    kni_master::decompose::check_structure(d).expect("structural contract");
    for p in &d.parts {
        assert!(!p.provenance.rule.is_empty(), "part {} has no decision record", p.name);
        assert!(!p.provenance.branches.is_empty(), "part {} has no skeleton provenance", p.name);
        assert!(!p.provenance.runs.is_empty() || p.class == PartClass::Mark, "part {} has no boundary provenance", p.name);
        assert_eq!(p.contour.stroke, p.name, "stroke name is the part identity");
    }
    // Regression floor for the assembly, not an acceptance proof: the
    // current reconstruction IoU is measured at 0.9836 on this fixture.
    let iou = reconstruction_iou(src, d);
    assert!(iou >= 0.95, "reconstruction IoU {iou} < 0.95");
}

#[test]
fn h_like_splits_into_stem_and_arm() {
    let g = h_like();
    let d = decompose(&g).expect("decompose");
    assert_eq!(classes(&d), vec![PartClass::Arm, PartClass::Stem], "parts: {:#?}", d.parts.iter().map(|p| (&p.name, &p.provenance.rule)).collect::<Vec<_>>());
    check_common(&g, &d);
}

#[test]
fn rotated_h_like_gives_the_same_parts() {
    let g = rotate_glyph(&h_like(), 37.0);
    let d = decompose(&g).expect("decompose");
    assert_eq!(classes(&d), vec![PartClass::Arm, PartClass::Stem], "parts: {:#?}", d.parts.iter().map(|p| (&p.name, &p.provenance.rule)).collect::<Vec<_>>());
    check_common(&g, &d);
}

#[test]
fn k_like_splits_into_stem_arm_leg() {
    let g = k_like();
    let d = decompose(&g).expect("decompose");
    assert_eq!(classes(&d), vec![PartClass::Arm, PartClass::Leg, PartClass::Stem], "parts: {:#?}", d.parts.iter().map(|p| (&p.name, &p.provenance.rule)).collect::<Vec<_>>());
    check_common(&g, &d);
}

#[test]
fn ring_is_one_bowl() {
    let g = ring();
    let d = decompose(&g).expect("decompose");
    assert_eq!(classes(&d), vec![PartClass::Bowl]);
    assert_eq!(d.parts[0].provenance.counters.len(), 1, "the bowl owns the counter");
    check_common(&g, &d);
}

#[test]
fn lone_bar_is_one_stem() {
    let g = bar_only();
    let d = decompose(&g).expect("decompose");
    assert_eq!(classes(&d), vec![PartClass::Stem]);
    check_common(&g, &d);
}

fn scale_glyph(g: &MasterGlyph, k: f64, t: Pt) -> MasterGlyph {
    let f = |p: Pt| (p.0 * k + t.0, p.1 * k + t.1);
    let map = |o: &Op| match o {
        Op::Move(p) => Op::Move(f(*p)),
        Op::Line(p) => Op::Line(f(*p)),
        Op::Curve(a, b, p) => Op::Curve(f(*a), f(*b), f(*p)),
        Op::Close => Op::Close,
    };
    MasterGlyph {
        name: g.name.clone(),
        advance: g.advance,
        upm: g.upm,
        contours: g.contours.iter().map(|c| contour(c.ops.iter().map(&map).collect())).collect(),
    }
}

#[test]
fn translated_scaled_ring_with_mark_groups_the_same() {
    // Counter enclosure probes must survive translation and scale of the
    // source outline (regression: counter probes entered grouping in font
    // units while the skeleton path lives in raster cells).
    let g = scale_glyph(&ring_with_mark(), 2.7, (513.0, -271.0));
    let d = decompose(&g).expect("decompose");
    assert_eq!(classes(&d), vec![PartClass::Bowl, PartClass::Mark], "parts: {:#?}", d.parts.iter().map(|p| (&p.name, &p.provenance.rule)).collect::<Vec<_>>());
    check_common(&g, &d);
}

#[test]
fn detached_mark_is_its_own_part() {
    let g = ring_with_mark();
    let d = decompose(&g).expect("decompose");
    assert_eq!(classes(&d), vec![PartClass::Bowl, PartClass::Mark], "parts: {:#?}", d.parts.iter().map(|p| (&p.name, &p.provenance.rule)).collect::<Vec<_>>());
    check_common(&g, &d);
}

#[test]
fn reference_r_splits_into_stem_bowl_leg() {
    let g = reference_r();
    let d = decompose(&g).expect("decompose");
    assert_eq!(classes(&d), vec![PartClass::Bowl, PartClass::Leg, PartClass::Stem], "parts: {:#?}", d.parts.iter().map(|p| (&p.name, &p.provenance.rule)).collect::<Vec<_>>());
    let bowl = d.parts.iter().find(|p| p.class == PartClass::Bowl).unwrap();
    assert_eq!(bowl.provenance.counters.len(), 1, "R counter travels inside the bowl");
    check_common(&g, &d);
}

/// The exported glyph keeps its ink under nonzero (sum-of-windings) fill:
/// the ring's counter center stays EMPTY and the stroke band stays INK.
#[test]
fn exported_glyph_preserves_ink_under_winding_fill() {
    use kni_master::check::stroke_polygon;
    use kni_master::raster::inside_merged;
    let g = ring();
    let d = decompose(&g).expect("decompose");
    let polys: Vec<Vec<(f64, f64)>> = d.glyph.contours.iter().map(stroke_polygon).collect();
    assert!(!inside_merged((150.0, 150.0), &polys), "counter center filled back in");
    assert!(inside_merged((150.0 + 80.0, 150.0), &polys), "stroke band lost ink");
    // and the source fills the same way at those probe points
    let src: Vec<Vec<(f64, f64)>> = g.contours.iter().map(stroke_polygon).collect();
    assert!(!inside_merged((150.0, 150.0), &src));
    assert!(inside_merged((230.0, 150.0), &src));
}

fn rect_cw(x0: f64, y0: f64, x1: f64, y1: f64) -> StrokeContour {
    contour(vec![
        Op::Move((x0, y0)),
        Op::Line((x0, y1)),
        Op::Line((x1, y1)),
        Op::Line((x1, y0)),
        Op::Close,
    ])
}

/// Mixed-winding source semantics: a reversed rect fully inside solid ink
/// is an enclosed background region of the nonzero fill and MUST carve.
#[test]
fn buried_counter_ring_carves_like_the_source_fill() {
    use kni_master::check::stroke_polygon;
    use kni_master::raster::inside_merged;
    let g = glyph("buried", vec![rect(0.0, 0.0, 200.0, 300.0), rect_cw(60.0, 100.0, 140.0, 200.0)]);
    let d = decompose(&g).expect("decompose");
    let polys: Vec<Vec<(f64, f64)>> = d.glyph.contours.iter().map(stroke_polygon).collect();
    assert!(!inside_merged((100.0, 150.0), &polys), "buried counter filled back in");
    assert!(inside_merged((30.0, 150.0), &polys), "frame lost ink");
    check_common(&g, &d);
}

/// A source counter PARTIALLY covered by another stroke is not bounded by
/// its source ring: only the open wedge is background. The reconstruction
/// must carve exactly the wedge and keep the covered half as ink.
#[test]
fn partially_covered_counter_carves_only_the_open_wedge() {
    use kni_master::check::stroke_polygon;
    use kni_master::raster::inside_merged;
    let g = glyph(
        "covered",
        vec![
            rect(0.0, 0.0, 200.0, 300.0),        // outer frame
            rect_cw(50.0, 100.0, 150.0, 200.0),  // counter, right half covered
            rect(100.0, 50.0, 240.0, 250.0),     // covering bar
        ],
    );
    // source fill at the probe points: wedge background, covered half ink
    let src: Vec<Vec<(f64, f64)>> = g.contours.iter().map(stroke_polygon).collect();
    assert!(!inside_merged((75.0, 150.0), &src), "wedge is background in the source");
    assert!(inside_merged((125.0, 150.0), &src), "covered half is ink in the source");
    let d = decompose(&g).expect("decompose");
    let polys: Vec<Vec<(f64, f64)>> = d.glyph.contours.iter().map(stroke_polygon).collect();
    assert!(!inside_merged((75.0, 150.0), &polys), "open wedge filled back in");
    assert!(inside_merged((125.0, 150.0), &polys), "covered half of the counter lost ink");
    assert!(inside_merged((30.0, 150.0), &polys), "frame lost ink");
    check_common(&g, &d);
}

// ------------------------------------------------- SliceC plug contract (parts_plug)

use kni_core::reference_slice::{Point as RPoint, ReferenceRing, Span as RSpan};
use kni_master::parts_plug::{
    decompose_rings_into_parts, decide, reference_ring_to_contour, wire_summary_line,
    ExactCarryReason, PartRegistry, PartShape, PartsOut, WireLedgerRow, LOW_IOU_CARRY_THRESHOLD,
};
use kni_master::decompose::DecomposeParams;

fn rpoint(x: f64, y: f64) -> RPoint { RPoint { x, y } }

/// Ring conversion is 1:1 at the plug: Move, one op per span, Close; no
/// tolerance, no normalization.
#[test] fn plug_ring_conversion_is_one_to_one() {
    let r = ReferenceRing {
        start: rpoint(0.0, 0.0),
        spans: vec![
            RSpan::Line { end: rpoint(10.0, 0.0) },
            RSpan::Cubic { control_one: rpoint(10.0, 5.0), control_two: rpoint(5.0, 10.0), end: rpoint(0.0, 10.0) },
            RSpan::Line { end: rpoint(0.0, 0.0) },
        ],
    };
    let c = reference_ring_to_contour(&r);
    assert_eq!(c.ops.len(), 5);
    assert!(matches!(c.ops[0], Op::Move(_)));
    assert!(matches!(c.ops[1], Op::Line(_)));
    assert!(matches!(c.ops[2], Op::Curve(_, _, _)));
    assert!(matches!(c.ops[3], Op::Line(_)));
    assert!(matches!(c.ops[4], Op::Close));
}

/// The lane decision: exactly the threshold stays PARTS, below carries.
#[test] fn plug_decide_threshold_boundary() {
    assert!(matches!(decide(2, LOW_IOU_CARRY_THRESHOLD), PartsOut::Parts(_)));
    assert!(matches!(decide(2, 1.0), PartsOut::Parts(_)));
    assert!(matches!(
        decide(2, LOW_IOU_CARRY_THRESHOLD - 1e-9),
        PartsOut::ExactCarry { reason: ExactCarryReason::LowIoU }
    ));
}

/// Empty rings carry exactly with the EmptyOutline reason.
#[test] fn plug_empty_rings_exact_carry() {
    let mut reg = PartRegistry::default();
    let (out, row) = decompose_rings_into_parts("space", &[], 250.0, &mut reg, &DecomposeParams::default());
    assert!(matches!(out, PartsOut::ExactCarry { reason: ExactCarryReason::EmptyOutline }));
    assert_eq!(row.reason, Some(ExactCarryReason::EmptyOutline));
    assert_eq!(row.parts, 0);
    assert_eq!(row.note, Some("no-usable-contours"));
    assert!(reg.minted.is_empty());
}

/// The canonical row grammar is pinned byte-for-byte (SliceC row pin
/// target): space separators, iou fixed six decimals, note token last.
#[test] fn plug_ledger_row_format_is_pinned() {
    let parts = WireLedgerRow { glyph: "h".into(), parts: 2, iou: 0.999_96, reason: None, note: None };
    assert_eq!(
        parts.to_line(&["h._part.arm".into(), "h._part.stem".into()]),
        "glyph h PARTS n=2 iou 0.999960 parts [h._part.arm, h._part.stem]"
    );
    let carry = WireLedgerRow { glyph: "period".into(), parts: 1, iou: 0.618_951, reason: Some(ExactCarryReason::LowIoU), note: None };
    assert_eq!(carry.to_line(&[]), "glyph period EXACTCARRY reason=LowIoU iou 0.618951");
    let noted = WireLedgerRow { glyph: "space".into(), parts: 0, iou: 1.0, reason: Some(ExactCarryReason::EmptyOutline), note: Some("no-usable-contours") };
    assert_eq!(noted.to_line(&[]), "glyph space EXACTCARRY reason=EmptyOutline iou 1.000000 note=no-usable-contours");
    // header: minted count present (publish gate parts>0), reasons sorted
    let mut reasons = std::collections::BTreeMap::new();
    reasons.insert("LowIoU".to_string(), 21u32);
    reasons.insert("EmptyOutline".to_string(), 1u32);
    assert_eq!(
        wire_summary_line(137, 115, 22, 0, 972, &reasons),
        "wire-summary glyphs 137 parts 115 exactcarry 22 panics 0 minted 972 reasons {\"EmptyOutline\": 1, \"LowIoU\": 21}"
    );
    assert_eq!(
        wire_summary_line(1, 1, 0, 0, 2, &std::collections::BTreeMap::new()),
        "wire-summary glyphs 1 parts 1 exactcarry 0 panics 0 minted 2 reasons {}"
    );
}

/// h-like through the plug: Parts with one Component shape per part,
/// minted names <glyph>._part.<class>, advance 0, no-export, holes riding
/// the minted glyph, identity placement, ledger row clean.
/// Block-arch h variant for the plug lane (owner rule 2026-10-18 21:36
/// gate amendment, named reason): the smooth-cubic h_like arch
/// measurably rasterizes 8 px outside the source silhouette at the arch
/// crest (arm ring flattening divergence, x [105.6, 216.6] y [220.5,
/// 249.8] at px 0.4125), so the PartProtrusion gate correctly carries
/// it; the owner Marq h source (LINE-staircase arch) measures
/// outside_px [0, 0] and stays PARTS. This all-LINE block arch measures
/// outside_px [0, 0, 0] and keeps this test on the PARTS contract path.
/// It also exercises the duplicate-name .2 suffix (two Stem parts).
fn h_like_block() -> MasterGlyph {
    glyph("h_like", vec![contour(vec![
        Op::Move((60.0, 0.0)), Op::Line((60.0, 260.0)), Op::Line((100.0, 260.0)), Op::Line((100.0, 200.0)),
        Op::Line((200.0, 200.0)), Op::Line((200.0, 260.0)), Op::Line((240.0, 260.0)), Op::Line((240.0, 0.0)),
        Op::Line((200.0, 0.0)), Op::Line((200.0, 160.0)), Op::Line((100.0, 160.0)), Op::Line((100.0, 0.0)), Op::Close,
    ])])
}

#[test] fn plug_h_like_parts_and_registry() {
    let g = h_like_block();
    let rings: Vec<ReferenceRing> = vec![ReferenceRing {
        start: rpoint(0.0, 0.0),
        spans: {
            // rebuild the fixture contour as spans through the plug's own
            // conversion to keep this test about plug behavior, not geometry
            let mut spans = Vec::new();
            let ops = &g.contours[0].ops;
            let mut i = 1;
            while i < ops.len() {
                match ops[i] {
                    Op::Line(p) => spans.push(RSpan::Line { end: rpoint(p.0, p.1) }),
                    Op::Curve(a, b, p) => spans.push(RSpan::Cubic { control_one: rpoint(a.0, a.1), control_two: rpoint(b.0, b.1), end: rpoint(p.0, p.1) }),
                    _ => {}
                }
                i += 1;
            }
            // start must be the fixture's Move, not (0,0)
            spans
        },
    }];
    let rings = vec![ReferenceRing {
        start: match g.contours[0].ops[0] { Op::Move(p) => rpoint(p.0, p.1), _ => unreachable!() },
        spans: rings.into_iter().next().unwrap().spans,
    }];
    let mut reg = PartRegistry::default();
    let (out, row) = decompose_rings_into_parts("h", &rings, 533.0, &mut reg, &DecomposeParams::default());
    let PartsOut::Parts(parts) = out else { panic!("h-like must stay PARTS, row: {row:?}") };
    assert_eq!(parts.shapes.len(), row.parts);
    assert_eq!(row.reason, None);
    assert!(row.iou >= LOW_IOU_CARRY_THRESHOLD, "iou {}", row.iou);
    // names: <glyph>._part.<class>, one per shape, classes from geometry
    let mut names: Vec<String> = parts.shapes.iter().map(|s| match s {
        PartShape::Component { part_glyph, pos, scale, angle, alignment, anchor } => {
            assert_eq!(*pos, (0.0, 0.0));
            assert_eq!(*scale, 1.0);
            assert_eq!(*angle, 0.0);
            assert!(alignment.is_none() && anchor.is_none());
            part_glyph.clone()
        }
        PartShape::Path(_) => panic!("holed parts must use the minted Component form"),
    }).collect();
    names.sort();
    assert_eq!(names, vec!["h._part.arm".to_string(), "h._part.stem".to_string(), "h._part.stem.2".to_string()]);
    // registry: one mint per part, advance 0, no-export
    assert_eq!(reg.minted.len(), 3);
    for m in &reg.minted {
        assert_eq!(m.advance, 0.0);
        assert!(!m.export);
        assert!(names.contains(&m.name));
    }
}

/// Owner rule 2026-10-18 21:36 gate: any part with outside_px > 0 flips
/// the glyph to ExactCarry PartProtrusion and preempts LowIoU; all-zero
/// outside_px keeps decide()'s threshold semantics unchanged.
#[test]
fn plug_part_protrusion_gate() {
    use kni_master::parts_plug::{decide_gated, ExactCarryReason, PartsOut};
    match decide_gated(2, 0.5, &[0, 3]) {
        PartsOut::ExactCarry { reason } => assert_eq!(reason, ExactCarryReason::PartProtrusion),
        _ => panic!("protruding part must flip to carry"),
    }
    match decide_gated(1, 0.1, &[7]) {
        PartsOut::ExactCarry { reason } => assert_eq!(reason, ExactCarryReason::PartProtrusion),
        _ => panic!("gate must preempt LowIoU"),
    }
    match decide_gated(1, 0.1, &[0]) {
        PartsOut::ExactCarry { reason } => assert_eq!(reason, ExactCarryReason::LowIoU),
        _ => panic!("low IoU without protrusion stays LowIoU"),
    }
    match decide_gated(2, 0.999, &[0, 0]) {
        PartsOut::Parts(_) => {}
        _ => panic!("clean glyph stays Parts"),
    }
}

/// outside_px counts exactly the part ink beyond the silhouette on the
/// pinned grid: the unshifted part measures 0, a part shifted halfway
/// out of a square source measures > 0.
#[test]
fn plug_part_outside_px_counts_only_protrusion() {
    use kni_master::decompose::{Decomposition, Part, PartClass, Provenance};
    use kni_master::model::{MasterGlyph, Op, StrokeContour};
    use kni_master::parts_plug::part_outside_px;
    let square = |dx: f64| StrokeContour {
        stroke: String::new(),
        ops: vec![
            Op::Move((dx, 0.0)),
            Op::Line((dx + 100.0, 0.0)),
            Op::Line((dx + 100.0, 100.0)),
            Op::Line((dx, 100.0)),
            Op::Close,
        ],
    };
    let prov = || Provenance {
        branches: vec![],
        runs: vec![],
        counters: vec![],
        axis_deg: 90.0,
        rel_axis_deg: Some(0.0),
        aspect: 1.0,
        curvature: 0.0,
        free_ends: 0,
        axis_pos: Some(0.5),
        rule: "test".into(),
    };
    let mk = |dx: f64| Decomposition {
        glyph: MasterGlyph { name: "t".into(), advance: 0.0, upm: 1000.0, contours: vec![square(0.0)] },
        parts: vec![Part { name: "p".into(), class: PartClass::Stem, contour: square(dx), holes: vec![], provenance: prov() }],
        glyph_axis_deg: Some(90.0),
        cell: 1.0,
    };
    assert_eq!(part_outside_px(&[square(0.0)], &mk(0.0)), vec![0]);
    let out = part_outside_px(&[square(0.0)], &mk(50.0))[0];
    assert!(out > 0, "shifted part must measure protrusion, got {out}");
}
