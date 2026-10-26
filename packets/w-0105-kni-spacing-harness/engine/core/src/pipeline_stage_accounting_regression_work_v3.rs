#![cfg(test)]
//! Pipeline stage-accounting regression (v3; successor of v2). SYNTHETIC SCAFFOLD ONLY, SOURCE-TEST ONLY.
//! Scope: v2 semantics kept; refusal and round-cleanup cases extended; marker boundaries tightened (exact prefixes WITH ": ", exact full E0-tail-drop string, lookalike and duplicate negatives). fit_from_source_frame / capture are NEVER called here. No edit to any existing N3/PRE test, no extra wrapper, no 25/26 pins, no prefit==E0, no geometry/limits change, no FAILED pipeline status is invented: the only refusal shapes are the `LeverError` variants returned by public node_objective::try_apply / try_apply_protected and the `refused` strings pushed by the supplied pipeline source. Pristine pipeline source strings were read; the instrumented dump was not compared.
use crate::capture_fit::round_and_clean_ring;
use crate::generated_draw_frame::GeneratedDrawing;
use crate::lever_api::{count_nodes, hash_rings, LeverError, LeverReport, NodeBudget, SourceMask};
use crate::reference_slice::{Point, ReferenceRing, Span};

fn p(x: f64, y: f64) -> Point { Point { x, y } }
fn ln(x: f64, y: f64) -> Span { Span::Line { end: p(x, y) } }
fn ring(start: (f64, f64), spans: Vec<Span>) -> ReferenceRing { ReferenceRing { start: p(start.0, start.1), spans } }
/// Closed INTEGER-grid square (side 8) with `extra` (0..=7) additional collinear nodes at x = 1..=extra on its bottom edge (spans = 4 + extra; last end == start). All coordinates are integers.
fn square_with_extra(extra: usize) -> ReferenceRing {
    assert!(extra <= 7);
    let mut s = Vec::new();
    for i in 1..=extra { s.push(ln(i as f64, 0.0)); }
    s.push(ln(8.0, 0.0)); s.push(ln(8.0, 8.0)); s.push(ln(0.0, 8.0)); s.push(ln(0.0, 0.0));
    ring((0.0, 0.0), s)
}
fn rep(lever: &'static str, input: u64, output: u64, before: usize, after: usize, notes: &str) -> LeverReport {
    let id = IDENT.iter().find(|x| x.0 == lever).copied().unwrap_or((lever, "unknown", "unknown", &[]));
    LeverReport { lever, lever_id: id.1, api_version: crate::lever_api::LEVER_API_VERSION, stage_tag: id.2, input_hash: input, output_hash: output, seed: 0,
        nodes_before: before, nodes_after: after, area_before: 1.0, area_after: 1.0, c2_missing: 0, max_node_displacement: 0.0, notes: notes.to_string() }
}
fn drawing(baseline: Vec<ReferenceRing>, rings: Vec<ReferenceRing>, reports: Vec<LeverReport>, refused: Vec<String>) -> GeneratedDrawing {
    GeneratedDrawing { rings, baseline, reports, refused, baseline_area: 1.0, final_area: 1.0, baseline_missing_extrema: 0, final_missing_extrema: 0,
        source_fit_spans: 7, fallback: false, dropped: 1, fallback_line_spans: 0, sub_grid_floor: 0, ambiguous_stubs: 0, ambig_declined: 0, fallback_provenance: Vec::new() }
}
/// node_objective notes begin "slack={} removed={} flatten_chords_out=...": exactly ONE `removed=` token, canonical usize (digits only, no leading zero except "0"), else Err.
fn removed_from_notes(notes: &str) -> Result<usize, String> {
    let toks: Vec<&str> = notes.split_whitespace().filter(|t| t.starts_with("removed=")).collect();
    if toks.len() != 1 { return Err(format!("expected exactly one removed= token, found {}", toks.len())); }
    let v = &toks[0]["removed=".len()..];
    if v.is_empty() || !v.bytes().all(|c| c.is_ascii_digit()) || (v.len() > 1 && v.starts_with('0')) { return Err(format!("malformed removed value {v:?}")); }
    v.parse::<usize>().map_err(|e| format!("removed value: {e}"))
}
/// Marker entries ending in ": " are PREFIXES (the pipeline pushes format!("<prefix>{e:?}")); any other entry (the E0 tail drop) must match the whole string exactly.
/// EXACT identities from the supplied sources: (lever, lever_id, stage_tag, refusal/drop marker prefixes the v6 pipeline pushes into `refused` when that stage emits no report). api_version must equal lever_api::LEVER_API_VERSION (3 in the supplied lever_api).
const IDENT: [(&str, &str, &str, &[&str]); 3] = [
    ("emitted_geometry_refine", "D2.emitted_geometry_refine", "post-fit/default", &["emission refinement refused: "]),
    ("tail_refine", "D4.tail_refine", "post-fit/default", &["handle refinement refused: ", "handle refinement candidate dropped: E0 protected predicate violated or identity unstable (exact-input fallback)"]),
    ("node_objective", "N1.node_objective", "post-fit/opt-in", &["strict node reduction refused: "]),
];
/// Stage-boundary accounting over PUBLIC fields only. Units: nodes = sum of ring.spans.len() (count_nodes); the closing start is not an extra node.
/// Chain rule (holds in every branch of the v6 pipeline source: a refused or E0-dropped stage pushes no report and leaves `rings` unchanged):
/// report[i].input_hash == (report[i-1].output_hash, or hash_rings(baseline) for i == 0); same for nodes_before/nodes_after; the last output == hash_rings(rings).
/// `strict_stages`=true: each of the 3 stages must be present exactly once OR have an attributable exact refusal/drop marker in `refused`; a silently omitted stage is an Err.
/// `strict_stages`=false is the WEAKER observational-chain mode: only the chain of whatever reports exist is checked; an arbitrary omitted stage is NOT accounted.
fn check_drawing_accounting(d: &GeneratedDrawing, strict_stages: bool) -> Result<(), String> {
    let manual: usize = d.baseline.iter().map(|r| r.spans.len()).sum();
    if count_nodes(&d.baseline) != manual { return Err("baseline count_nodes != sum of spans".into()); }
    if count_nodes(&d.rings) > count_nodes(&d.baseline) { return Err("final nodes exceed baseline nodes".into()); }
    let mut last_pos: isize = -1;
    let (mut in_hash, mut in_nodes) = (hash_rings(&d.baseline), count_nodes(&d.baseline));
    for (i, r) in d.reports.iter().enumerate() {
        let pos = IDENT.iter().position(|x| x.0 == r.lever).ok_or_else(|| format!("report {i}: unknown lever {}", r.lever))?;
        let (_, lid, tag, _) = IDENT[pos];
        if r.lever_id != lid || r.stage_tag != tag || r.api_version != crate::lever_api::LEVER_API_VERSION { return Err(format!("report {i}: identity mismatch (lever_id/stage_tag/api_version) for {}", r.lever)); }
        let pos = pos as isize;
        if pos <= last_pos { return Err(format!("report {i}: stage order/duplicate violated ({})", r.lever)); }
        last_pos = pos;
        if r.input_hash != in_hash { return Err(format!("report {i}: input_hash does not chain")); }
        if r.nodes_before != in_nodes { return Err(format!("report {i}: nodes_before does not chain")); }
        if r.lever != "node_objective" && r.nodes_after != r.nodes_before { return Err(format!("report {i}: {} must not change node count", r.lever)); }
        if r.nodes_after > r.nodes_before { return Err(format!("report {i}: nodes increased")); }
        if r.lever == "node_objective" {
            // verified in node_objective::run: each accepted removal splices 2 spans into 1 and pushes exactly one ledger entry
            let removed = removed_from_notes(&r.notes).map_err(|e| format!("report {i}: {e}"))?;
            if r.nodes_before < r.nodes_after { return Err(format!("report {i}: nodes_after > nodes_before")); }
            if r.nodes_before - r.nodes_after != removed { return Err(format!("report {i}: removed={removed} != before-after")); }
        }
        in_hash = r.output_hash; in_nodes = r.nodes_after;
    }
    if strict_stages {
        for (lever, _, _, marks) in IDENT.iter() {
            let n = d.reports.iter().filter(|r| r.lever == *lever).count();
            let marked = d.refused.iter().filter(|m| marks.iter().any(|p| **m == *p || (p.ends_with(": ") && m.starts_with(p)))).count();
            if n > 1 || marked > 1 || (n == 0 && marked == 0) || (n == 1 && marked > 0) { return Err(format!("stage {lever}: reports={n}, attributable exact refusal markers={marked} (need exactly one report XOR exactly one marker)")); }
        }
    }
    if in_hash != hash_rings(&d.rings) { return Err("last output_hash (or baseline hash when no report) != hash_rings(rings)".into()); }
    if in_nodes != count_nodes(&d.rings) { return Err("last nodes_after (or baseline count when no report) != count_nodes(rings)".into()); }
    Ok(())
}

#[test]
fn count_nodes_is_sum_of_spans_and_start_is_not_a_node() {
    let r = square_with_extra(1); // start (0,0) + 5 spans, last end == start
    assert_eq!(r.spans.len(), 5);
    assert_eq!(count_nodes(&[r.clone(), square_with_extra(0)]), 5 + 4);
    assert_eq!(count_nodes(&[]), 0);
}
#[test]
fn round_and_clean_removes_exact_zero_length_spans_so_float_count_differs_from_rounded() {
    // first span ends within 0.3 of the start: after rounding it equals the current point exactly -> removed (tol 0)
    let float = ring((-0.2, 0.0), vec![ln(0.2, 0.1), ln(5.0, 0.0), ln(5.0, 5.0), ln(0.0, 5.0), ln(0.0, 0.0)]);
    let out = round_and_clean_ring(&float, 1.0);
    assert_eq!(float.spans.len(), 5);
    assert_eq!(out.spans.len(), 4, "the exact-zero-length span is removed");
    assert!(out.start.x.is_sign_positive() && out.start.x == 0.0, "-0.0 normalized");
    let end = match out.spans.last().unwrap() { Span::Line { end } | Span::Cubic { end, .. } => *end };
    assert_eq!(end, out.start, "ring stays closed");
    // so fit count == rounded count is NOT a general property; rounded count <= fit count is
    assert!(count_nodes(&[out]) <= count_nodes(&[float]));
}
#[test]
fn round_and_clean_never_empties_a_ring() {
    let all_zero = ring((0.1, 0.1), vec![ln(0.2, 0.2), ln(0.3, 0.1), ln(0.1, 0.2)]);
    let out = round_and_clean_ring(&all_zero, 1.0);
    assert!(!out.spans.is_empty(), "guard: a ring that would lose all spans is returned unchanged (rounded), not emptied");
    assert_eq!(out.spans.len(), all_zero.spans.len());
}
#[test]
fn round_and_clean_on_integer_grid_ring_keeps_count() {
    let r = square_with_extra(2);
    assert_eq!(round_and_clean_ring(&r, 1.0).spans.len(), r.spans.len());
}
#[test]
fn accounting_accepts_synthetic_full_chain() {
    let base = vec![square_with_extra(2)]; // 6 nodes
    let after_nodes = vec![square_with_extra(1)]; // 5 nodes
    let (h0, h1, h2) = (hash_rings(&base), hash_rings(&base), hash_rings(&after_nodes));
    let d = drawing(base.clone(), after_nodes, vec![rep("emitted_geometry_refine", h0, h1, 6, 6, ""), rep("tail_refine", h1, h1, 6, 6, ""), rep("node_objective", h1, h2, 6, 5, "slack=0 removed=1 flatten_chords_out=0")], vec![]);
    assert_eq!(check_drawing_accounting(&d, true), Ok(()));
}
#[test]
fn accounting_accepts_refusal_and_dropped_stage_with_no_report() {
    let base = vec![square_with_extra(1)];
    let d = drawing(base.clone(), base.clone(), vec![], vec!["emission refinement refused: x".into(), "handle refinement candidate dropped: E0 protected predicate violated or identity unstable (exact-input fallback)".into(), "strict node reduction refused: x".into()]);
    assert_eq!(check_drawing_accounting(&d, true), Ok(()));
    // a middle stage dropped: tail report absent, node_objective chains from the emitted output
    let h = hash_rings(&base);
    let d2 = drawing(base.clone(), base.clone(), vec![rep("emitted_geometry_refine", h, h, 5, 5, ""), rep("node_objective", h, h, 5, 5, "slack=0 removed=0")], vec!["handle refinement refused: x".into()]);
    assert_eq!(check_drawing_accounting(&d2, true), Ok(()));
}
#[test]
fn accounting_rejects_each_broken_boundary() {
    let base = vec![square_with_extra(2)]; let less = vec![square_with_extra(1)];
    let (hb, hl) = (hash_rings(&base), hash_rings(&less));
    // no report but rings differ from baseline
    assert!(check_drawing_accounting(&drawing(base.clone(), less.clone(), vec![], vec![]), false).is_err());
    // input hash chain broken
    assert!(check_drawing_accounting(&drawing(base.clone(), less.clone(), vec![rep("node_objective", hb ^ 1, hl, 6, 5, "removed=1")], vec![]), false).is_err());
    // nodes_before chain broken
    assert!(check_drawing_accounting(&drawing(base.clone(), less.clone(), vec![rep("node_objective", hb, hl, 7, 5, "removed=2")], vec![]), false).is_err());
    // removed count inconsistent with before-after
    assert!(check_drawing_accounting(&drawing(base.clone(), less.clone(), vec![rep("node_objective", hb, hl, 6, 5, "removed=2")], vec![]), false).is_err());
    // missing removed= in notes
    assert!(check_drawing_accounting(&drawing(base.clone(), less.clone(), vec![rep("node_objective", hb, hl, 6, 5, "slack=0")], vec![]), false).is_err());
    // last output hash does not match rings
    assert!(check_drawing_accounting(&drawing(base.clone(), less.clone(), vec![rep("node_objective", hb, hb, 6, 5, "removed=1")], vec![]), false).is_err());
    // non-removal stage changed the node count
    assert!(check_drawing_accounting(&drawing(base.clone(), less.clone(), vec![rep("tail_refine", hb, hl, 6, 5, "")], vec![]), false).is_err());
    // stage order violated / duplicated / unknown
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![rep("node_objective", hb, hb, 6, 6, "removed=0"), rep("tail_refine", hb, hb, 6, 6, "")], vec![]), false).is_err());
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![rep("mystery", hb, hb, 6, 6, "")], vec![]), false).is_err());
    // final nodes exceed baseline
    assert!(check_drawing_accounting(&drawing(less.clone(), base.clone(), vec![], vec![]), false).is_err());
}
#[test]
fn prefit_context_fields_are_independent_of_later_stage_counts() {
    // synthetic only: the pre-fit counters are carried unchanged next to a stage chain that changes node counts; they must not be compared to final nodes
    let base = vec![square_with_extra(2)]; let less = vec![square_with_extra(1)];
    let (hb, hl) = (hash_rings(&base), hash_rings(&less));
    let d = drawing(base, less, vec![rep("node_objective", hb, hl, 6, 5, "slack=0 removed=1")], vec![]);
    let snap = (d.source_fit_spans, d.fallback, d.dropped, d.fallback_line_spans);
    assert_eq!(check_drawing_accounting(&d, false), Ok(()));
    assert_eq!(snap, (d.source_fit_spans, d.fallback, d.dropped, d.fallback_line_spans), "accounting check does not alter the context");
    assert_ne!(d.source_fit_spans, count_nodes(&d.rings), "synthetic: source_fit_spans is NOT required to equal final nodes (no such assertion exists)");
}
#[test]
fn strict_policy_and_tail_defaults_by_value() {
    assert_eq!(crate::node_objective::Policy::STRICT.slack, 0.0);
    let c = crate::tail_refine::TailConfig::default();
    assert_eq!(c.max_sweeps, 4);
    assert!(c.validate().is_ok());
    let zero = crate::tail_refine::TailConfig { max_sweeps: 0, ..Default::default() };
    assert!(zero.validate().is_err());
}
#[test]
fn synthetic_tolerant_node_objective_strict_report_consistent_or_flatten_budget_refusal() {
    // SYNTHETIC/TOLERANT by design: not run by the author; the success branch MAY BE UNEXERCISED. Accepted refusal = Violation containing 'flatten budget refused' only (per node_objective tests/source); every other Err panics.
    let rings = vec![square_with_extra(1)];
    let mask = SourceMask { w: 8, h: 8, ink: vec![0u8; 64], scale: 1.0, origin: (0.0, 8.0) };
    let budget = NodeBudget { max_nodes: count_nodes(&rings), max_nodes_per_ring: rings.iter().map(|r| r.spans.len()).collect() };
    match crate::node_objective::try_apply(&rings, &mask, &budget, crate::node_objective::Policy::STRICT) {
        Ok((out, report)) => {
            assert_eq!(report.nodes_before, count_nodes(&rings));
            assert_eq!(report.nodes_after, count_nodes(&out));
            assert_eq!(report.input_hash, hash_rings(&rings));
            assert_eq!(report.output_hash, hash_rings(&out));
            let removed = removed_from_notes(&report.notes).expect("removed= present");
            assert_eq!(report.nodes_before - report.nodes_after, removed, "single-removal semantics: one span less per ledger entry");
            let d = drawing(rings.clone(), out, vec![report], vec![]);
            assert_eq!(check_drawing_accounting(&d, false), Ok(()), "observational chain only: the other stages were not run here");
        }
        Err(e) => {
            // refusal crossing: no report exists, rings stay the input; the accounting checker accepts exactly this shape
            // only the refusal the supplied source can raise for a valid closed integer ring + valid mask: the flatten-budget guard; anything else is a real failure
            match &e { LeverError::Violation(m) if m.contains("flatten budget refused") => {} other => panic!("unexpected LeverError (not an accepted refusal): {other:?}") }
            let d = drawing(rings.clone(), rings.clone(), vec![], vec!["strict node reduction refused: x".into()]);
            assert_eq!(check_drawing_accounting(&d, false), Ok(()));
        }
    }
}

#[test]
fn identity_mismatches_are_rejected() {
    let base = vec![square_with_extra(1)]; let h = hash_rings(&base);
    let ok = || rep("tail_refine", h, h, 5, 5, "");
    assert_eq!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![ok()], vec![]), false), Ok(()));
    let mut r = ok(); r.lever_id = "D4.other"; assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![r], vec![]), false).is_err());
    let mut r = ok(); r.stage_tag = "post-fit/opt-in"; assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![r], vec![]), false).is_err());
    let mut r = ok(); r.api_version = crate::lever_api::LEVER_API_VERSION + 1; assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![r], vec![]), false).is_err());
    let mut r = ok(); r.lever_id = "N1.node_objective"; assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![r], vec![]), false).is_err());
}
#[test]
fn stage_presence_strict_vs_observational() {
    let base = vec![square_with_extra(1)]; let h = hash_rings(&base);
    let only_emitted = vec![rep("emitted_geometry_refine", h, h, 5, 5, "")];
    // tail and node_objective silently absent: strict rejects, observational mode accepts (weaker coverage: omitted stages are NOT accounted)
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), only_emitted.clone(), vec![]), true).is_err());
    assert_eq!(check_drawing_accounting(&drawing(base.clone(), base.clone(), only_emitted.clone(), vec![]), false), Ok(()));
    // attributable exact markers for the two absent stages -> strict accepts
    let marks = vec!["handle refinement candidate dropped: E0 protected predicate violated or identity unstable (exact-input fallback)".to_string(), "strict node reduction refused: x".to_string()];
    assert_eq!(check_drawing_accounting(&drawing(base.clone(), base.clone(), only_emitted.clone(), marks), true), Ok(()));
    // a stage both reported and marked refused, or reported twice, is rejected
    let both = vec![rep("emitted_geometry_refine", h, h, 5, 5, "")];
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), both, vec!["emission refinement refused: x".into(), "handle refinement refused: x".into(), "strict node reduction refused: x".into()]), true).is_err());
    let twice = vec![rep("tail_refine", h, h, 5, 5, ""), rep("tail_refine", h, h, 5, 5, "")];
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), twice, vec![]), false).is_err());
    // unrelated refused text is not an attributable marker
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![], vec!["something else".into()]), true).is_err());
}
#[test]
fn removed_token_parsing_is_strict() {
    assert_eq!(removed_from_notes("slack=0 removed=3 flatten_chords_out=1"), Ok(3));
    assert_eq!(removed_from_notes("slack=0 removed=0"), Ok(0));
    for bad in ["slack=0", "removed=1 removed=1", "removed=1 removed=2", "removed=", "removed=x", "removed=01", "removed=-1", "removed=1.0", "removed=99999999999999999999999999"] {
        assert!(removed_from_notes(bad).is_err(), "{bad}");
    }
    // nodes_after > nodes_before for node_objective is rejected before any subtraction
    let base = vec![square_with_extra(1)]; let more = vec![square_with_extra(2)];
    let (hb, hm) = (hash_rings(&base), hash_rings(&more));
    assert!(check_drawing_accounting(&drawing(base, more, vec![rep("node_objective", hb, hm, 5, 6, "removed=0")], vec![]), false).is_err());
}

#[test]
fn marker_lookalikes_and_duplicates_are_rejected() {
    let base = vec![square_with_extra(1)]; let h = hash_rings(&base);
    let e = || rep("emitted_geometry_refine", h, h, 5, 5, "");
    let t = || rep("tail_refine", h, h, 5, 5, "");
    let n = || rep("node_objective", h, h, 5, 5, "slack=0 removed=0");
    let good_drop = "handle refinement candidate dropped: E0 protected predicate violated or identity unstable (exact-input fallback)".to_string();
    // exact tail drop string accepted (emitted + node reported)
    assert_eq!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![e(), n()], vec![good_drop.clone()]), true), Ok(()));
    // lookalikes for the absent tail stage: all rejected under strict
    for bad in ["handle refinement refusedXYZ", "handle refinement refused", "handle refinement refused:x", "Handle refinement refused: x", " handle refinement refused: x",
                "handle refinement candidate dropped: E0 protected predicate violated or identity unstable (exact-input fallback) ", "handle refinement candidate dropped: E0 protected predicate violated or identity unstable (exact-input fallback)XYZ", "handle refinement candidate dropped"] {
        assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![e(), n()], vec![bad.to_string()]), true).is_err(), "{bad:?}");
    }
    // lookalikes for emitted / node_objective
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![t(), n()], vec!["emission refinement refusedXYZ".into()]), true).is_err());
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![e(), t()], vec!["strict node reduction refused".into()]), true).is_err());
    // duplicate markers for one stage (same or two different tail markers) are rejected
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![e(), n()], vec!["handle refinement refused: a".into(), "handle refinement refused: b".into()]), true).is_err());
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![e(), n()], vec!["handle refinement refused: a".into(), good_drop]), true).is_err());
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![e(), t()], vec!["strict node reduction refused: a".into(), "strict node reduction refused: b".into()]), true).is_err());
    // a forged marker cannot replace a missing stage next to a real report for the SAME stage
    assert!(check_drawing_accounting(&drawing(base.clone(), base.clone(), vec![e(), t(), n()], vec!["strict node reduction refused: x".into()]), true).is_err());
}

// ---------------- refusal cases: each names the public typed API/error it tests (node_objective::try_apply / try_apply_protected -> LeverError) ----------------
fn valid_mask() -> SourceMask { SourceMask { w: 8, h: 8, ink: vec![0u8; 64], scale: 1.0, origin: (0.0, 8.0) } }
fn budget_for(rings: &[ReferenceRing]) -> NodeBudget { NodeBudget { max_nodes: count_nodes(rings), max_nodes_per_ring: rings.iter().map(|r| r.spans.len()).collect() } }
/// The pipeline wraps any try_apply Err as format!("strict node reduction refused: {e:?}") (generated_draw_frame source); the checker must accept exactly that shape as the node_objective stage's attributable refusal.
fn assert_node_refusal_marker_is_attributable(e: &LeverError) {
    let base = vec![square_with_extra(1)]; let h = hash_rings(&base);
    let marker = format!("strict node reduction refused: {e:?}");
    let d = drawing(base.clone(), base.clone(), vec![rep("emitted_geometry_refine", h, h, 5, 5, ""), rep("tail_refine", h, h, 5, 5, "")], vec![marker]);
    assert_eq!(check_drawing_accounting(&d, true), Ok(()));
}
#[test]
fn lever_error_bad_mask_from_try_apply() {   // LeverError::BadMask
    let rings = vec![square_with_extra(1)];
    let bad = SourceMask { w: 0, h: 0, ink: vec![], scale: 1.0, origin: (0.0, 0.0) };
    let e = crate::node_objective::try_apply(&rings, &bad, &budget_for(&rings), crate::node_objective::Policy::STRICT).unwrap_err();
    assert_eq!(e, LeverError::BadMask); assert_node_refusal_marker_is_attributable(&e);
}
#[test]
fn lever_error_non_closed_ring_from_try_apply() {   // LeverError::NonClosedRing { ring: 0 }
    let rings = vec![ring((0.0, 0.0), vec![ln(8.0, 0.0), ln(8.0, 8.0), ln(0.0, 8.0)])];
    let e = crate::node_objective::try_apply(&rings, &valid_mask(), &budget_for(&rings), crate::node_objective::Policy::STRICT).unwrap_err();
    assert_eq!(e, LeverError::NonClosedRing { ring: 0 }); assert_node_refusal_marker_is_attributable(&e);
}
#[test]
fn lever_error_non_integer_input_from_try_apply() {   // LeverError::NonIntegerInput { ring: 0 } (closed ring, non-integer start)
    let rings = vec![ring((0.5, 0.0), vec![ln(8.0, 0.0), ln(8.0, 8.0), ln(0.0, 8.0), ln(0.5, 0.0)])];
    let e = crate::node_objective::try_apply(&rings, &valid_mask(), &budget_for(&rings), crate::node_objective::Policy::STRICT).unwrap_err();
    assert_eq!(e, LeverError::NonIntegerInput { ring: 0 }); assert_node_refusal_marker_is_attributable(&e);
}
#[test]
fn lever_error_node_ceiling_per_ring_and_total_from_try_apply() {   // LeverError::NodeCeiling (per ring first, then total with ring usize::MAX)
    let rings = vec![square_with_extra(1)]; // 5 spans
    let per_ring = NodeBudget { max_nodes: 5, max_nodes_per_ring: vec![3] };
    let e = crate::node_objective::try_apply(&rings, &valid_mask(), &per_ring, crate::node_objective::Policy::STRICT).unwrap_err();
    assert_eq!(e, LeverError::NodeCeiling { ring: 0, got: 5, max: 3 }); assert_node_refusal_marker_is_attributable(&e);
    let total = NodeBudget { max_nodes: 4, max_nodes_per_ring: vec![5] };
    let e = crate::node_objective::try_apply(&rings, &valid_mask(), &total, crate::node_objective::Policy::STRICT).unwrap_err();
    assert_eq!(e, LeverError::NodeCeiling { ring: usize::MAX, got: 5, max: 4 }); assert_node_refusal_marker_is_attributable(&e);
}
#[test]
fn lever_error_violation_for_missing_protected_node_and_bad_slack() {   // LeverError::Violation via try_apply_protected / bad Policy
    let rings = vec![square_with_extra(1)];
    let mut prot = crate::node_objective::Protected::new(); prot.insert((0, 99));
    match crate::node_objective::try_apply_protected(&rings, &valid_mask(), &budget_for(&rings), crate::node_objective::Policy::STRICT, &prot) {
        Err(LeverError::Violation(m)) => assert!(m.contains("does not exist in the input"), "{m}"),
        other => panic!("expected Violation for a protected node that does not exist, got {other:?}"),
    }
    let bad = crate::node_objective::Policy { slack: -1.0 };
    match crate::node_objective::try_apply(&rings, &valid_mask(), &budget_for(&rings), bad) {
        Err(LeverError::Violation(m)) => assert!(m.contains("bad slack"), "{m}"),
        other => panic!("expected Violation(bad slack), got {other:?}"),
    }
}
// ---------------- round-cleanup cases (public capture_fit::round_and_clean_ring) ----------------
fn cubic(c1: (f64, f64), c2: (f64, f64), e: (f64, f64)) -> Span { Span::Cubic { control_one: p(c1.0, c1.1), control_two: p(c2.0, c2.1), end: p(e.0, e.1) } }
#[test]
fn round_clean_collapsed_cubic_removed_but_cubic_with_distinct_controls_kept() {
    // span 0: end and both controls round onto the current point -> removed; span 2: end equals the current point (4,0) but its controls differ -> kept
    let r = ring((0.0, 0.0), vec![cubic((0.2, 0.2), (0.3, 0.1), (0.1, 0.1)), ln(4.0, 0.0), cubic((5.0, 2.0), (3.0, 2.0), (4.0, 0.0)), ln(4.0, 4.0), ln(0.0, 4.0), ln(0.0, 0.0)]);
    let out = round_and_clean_ring(&r, 1.0);
    assert_eq!(r.spans.len(), 6); assert_eq!(out.spans.len(), 5);
    assert!(matches!(out.spans[0], Span::Line { .. }), "the collapsed cubic (span 0) is gone; the first remaining span is the line to (4,0)");
    assert!(out.spans.iter().any(|s| matches!(s, Span::Cubic { .. })), "the zero-extent-end cubic with distinct controls is retained");
}
#[test]
fn round_clean_is_idempotent_and_never_adds_spans() {
    let inputs = vec![
        ring((-0.2, 0.0), vec![ln(0.2, 0.1), ln(5.0, 0.0), ln(5.0, 5.0), ln(0.0, 5.0), ln(0.0, 0.0)]),
        square_with_extra(3),
        ring((0.1, 0.1), vec![ln(0.2, 0.2), ln(0.3, 0.1), ln(0.1, 0.2)]),
    ];
    for r in &inputs {
        let once = round_and_clean_ring(r, 1.0);
        assert!(once.spans.len() <= r.spans.len());
        let twice = round_and_clean_ring(&once, 1.0);
        assert_eq!(twice.spans.len(), once.spans.len());
        assert_eq!(hash_rings(&[twice]), hash_rings(&[once]));
    }
}
