//! Synthetic accounting tests only. No capture/fit or collection execution.
#[path = "../../pipeline/src/iou_population.rs"]
mod population;
use kni_core::iou_report::*;
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};

#[test]
fn report_accounts_for_full_manifest_and_assembly_population_once() {
    let manifest: Vec<String> = ["ok", "empty", "refused", "missing-gid"].iter().map(|s| s.to_string()).collect();
    let expected = population::expected_population(&manifest, true).unwrap();
    let keys: Vec<_> = expected.iter().map(|g| ("style".into(), g.clone())).collect();
    let evidence = FrameEvidence {
        scale_k: Some(1.0), origin: Some((0.0, 0.0)), ink_threshold: Some(128),
        flatten_steps: Some(1), canvas: Some((2, 2)), translation: Some((0.0, 0.0)),
        limits: Some(ResourceLimits { max_pixels: 4, max_flatten_steps: 1, max_edges: 8, max_png_bytes: 32 , max_png_working_bytes: 1 << 26}),
        ..Default::default()
    };
    let p = |x, y| Point { x, y };
    let outline = DrawnGlyph { glyph_id: "ok".into(), rings: vec![ReferenceRing {
        start: p(0.0, 0.0), spans: vec![Span::Line { end: p(2.0, 0.0) },
        Span::Line { end: p(2.0, -2.0) }, Span::Line { end: p(0.0, -2.0) },
        Span::Line { end: p(0.0, 0.0) }]
    }] };
    let job = |name: &str, outline| IouJob {
        style: "style".into(), glyph_id: name.into(),
        source: SourceInput::Gray { w: 2, h: 2, gray: vec![0; 4] },
        outline, evidence: evidence.clone(), stage: OutlineStage::OtfReadback,
    };
    let jobs = vec![job("ok", Ok(outline)),
        job("refused", Err(IouError::SourceDecode { glyph: "refused".into(), detail: "Stage1Refused".into() })),
        job("missing-gid", Err(IouError::SourceDecode { glyph: "missing-gid".into(), detail: "missing emitted GID".into() }))];
    let ex: Vec<_> = ["empty", ".notdef", "space"].iter().map(|name| Exclusion {
        style: "style".into(), glyph_id: name.to_string(), reason: "explicit synthetic exclusion".into()
    }).collect();
    let out = run_jobs(&jobs, Some(1));
    let report = build_report(&keys, out.rows.clone(), ex.clone(), out.duplicates, None).unwrap();
    let summary = report.overall();
    assert_eq!((summary.total, summary.measured, summary.failed, summary.excluded), (6, 1, 2, 3));
    for index in 0..ex.len() {
        let mut dropped = ex.clone(); dropped.remove(index);
        assert!(build_report(&keys, out.rows.clone(), dropped, vec![], None).is_err());
    }
    for index in 0..out.rows.len() {
        let mut dropped = out.rows.clone(); dropped.remove(index);
        assert!(build_report(&keys, dropped, ex.clone(), vec![], None).is_err());
        let mut doubled = out.rows.clone(); doubled.push(out.rows[index].clone());
        assert!(build_report(&keys, doubled, ex.clone(), vec![], None).is_err());
    }
    let mut doubled = ex.clone(); doubled.push(ex[0].clone());
    assert!(build_report(&keys, out.rows, doubled, vec![], None).is_err());
}
