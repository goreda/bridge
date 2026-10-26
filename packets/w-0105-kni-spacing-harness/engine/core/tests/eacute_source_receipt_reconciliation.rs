//! Eacute SOURCE-RECEIPT RECONCILIATION regression (chief 2026-10-15 routing, N3 lane).
//! Replaces the retired generic `source_fit_spans == emitted spans` invariant with explicit
//! per-stage accounting on the CURRENT tree. Units are distinct and asserted separately:
//!   source_fit_spans  = pre-refine float-fit span count (capture-fit output, pre-E0)
//!   baseline (E0)     = round_and_clean_ring(float) span count
//!   lever reports     = nodes_before/nodes_after chain across every lever stage
//!   final emitted     = rings span sum after the last lever (legal node reduction included)
//!   dropped           = capture-fit conversion drops ONLY (lever reductions are NOT drops)
//!   fallback_line_spans = fallback ledger count (independent unit)
//! Route: capture_source(bytes, rdp_eps, limits) -> fit_captured_source_frame(&src, scale, &policy).
//! Fixture inputs: eps 0.25, FitPolicy{squared_error 0.25, max_refits 8}, SCALE 1.7100183991006373.
//! CURRENT-TREE HISTORICAL CHARACTERIZATION (not a quality claim): E0 26 spans -> final 25,
//! the single removal reported by lever N1.node_objective ("removed=1", nodes 26->25,
//! area 1832.8972849021145 -> 1832.5386321401234, measured 2026-10-15 via boundary dump).
use kni_core::capture_dispatch::capture_source;
use kni_core::cubic_fit::FitPolicy;
use kni_core::generated_draw_frame::fit_captured_source_frame;
use kni_core::jpeg_source::Limits;

const PNG: &[u8] = include_bytes!("fixtures/00C9_scan.png");
const SCALE: f64 = 1.7100183991006373;
const EPS: f64 = 0.25;
fn policy() -> FitPolicy { FitPolicy { squared_error: 0.25, max_refits: 8 } }
fn limits() -> Limits { Limits { max_input_bytes: 1 << 26, max_pixels: 1 << 26, max_working_bytes: 1 << 28 } }
fn png_limits() -> kni_core::capture::DecodeLimits { kni_core::capture::DecodeLimits { max_input_bytes: 1 << 26, max_pixels: 1 << 26, max_working_bytes: 1 << 28 } }

fn span_count(rings: &[kni_core::reference_slice::ReferenceRing]) -> usize {
    rings.iter().map(|r| r.spans.len()).sum()
}

#[test]
fn every_node_transition_is_explicit_in_a_lever_report() {
    let src = capture_source(PNG, EPS, &png_limits(), limits()).expect("capture_source");
    let r = fit_captured_source_frame(&src, SCALE, &policy()).expect("route");
    let d = &r.drawing;

    // Unit 1: pre-refine fit count equals the E0 baseline count on this fixture
    // (round_and_clean_ring does not add/remove spans; verified relationship, not assumed).
    let e0 = span_count(&d.baseline);
    assert_eq!(d.source_fit_spans, e0, "pre-refine fit count must equal E0 baseline spans");

    // Unit 2: full lever chain. Every stage is explicit: the chain starts at the E0
    // node count and every nodes_before equals the previous nodes_after. A silent
    // node loss would break the chain or leave the final count unexplained.
    let mut cursor = e0;
    assert!(!d.reports.is_empty(), "at least one lever report expected on this fixture");
    for rep in &d.reports {
        assert_eq!(rep.nodes_before, cursor,
            "lever {} starts at {} but chain is at {}", rep.lever_id, rep.nodes_before, cursor);
        cursor = rep.nodes_after;
    }

    // Unit 3: final emitted equals the end of the explicit chain.
    let final_spans = span_count(&d.rings);
    assert_eq!(final_spans, cursor,
        "final emitted {} must equal last lever nodes_after {}", final_spans, cursor);

    // Unit 4: capture-fit drop unit is separate: no capture-fit drop on this fixture.
    assert_eq!(d.dropped, 0, "capture-fit drops must be 0 (lever reductions are not drops)");
    assert!(d.refused.is_empty(), "diagnostic refusals: {:?}", d.refused);

    // Unit 5: fallback ledger is its own unit and agrees with the flag.
    assert_eq!(d.fallback, d.fallback_line_spans > 0);
    // NOTE (chief 23:15): fallback_line_spans is a ledger unit, not a span count;
    // no cross-unit <= comparison. Exact fixture value 25 is pinned in the
    // historical test below.
}

/// Current-tree historical characterization: the exact stage counts measured by the
/// 2026-10-15 boundary dump. If any stage changes behavior, this test fails loudly and
/// the numbers must be re-pinned with a NEW boundary-dump receipt, never silently.
#[test]
fn current_tree_stage_counts_pinned() {
    let src = capture_source(PNG, EPS, &png_limits(), limits()).expect("capture_source");
    let r = fit_captured_source_frame(&src, SCALE, &policy()).expect("route");
    let d = &r.drawing;
    // Re-pinned 27 -> 23 with the PN-3 fallback rescue (boundary-dump
    // receipt, 2026-10-17 probe on this tree): the damped-Newton rescue +
    // corner resplit resolve the unresolved split chains this fixture
    // carried; N1 now removes 0 nodes and the raw-frame fallback ledger
    // reads 0 (was 25). Stage counts measured, not derived.
    assert_eq!(span_count(&d.baseline), 23, "E0 baseline spans");
    let chain: Vec<(String, usize, usize)> =
        d.reports.iter().map(|rep| (rep.lever_id.to_string(), rep.nodes_before, rep.nodes_after)).collect();
    assert_eq!(
        chain,
        vec![
            ("D2.emitted_geometry_refine".to_string(), 23, 23),
            ("D4.tail_refine".to_string(), 23, 23),
            ("N1.node_objective".to_string(), 23, 23),
        ],
        "lever stage chain"
    );
    assert_eq!(span_count(&d.rings), 23, "final emitted spans after legal reduction");
    assert_eq!(d.source_fit_spans, 23, "pre-refine fit count unit");
    assert_eq!(d.fallback_line_spans, 0, "fallback ledger unit (raw-frame fit route; diverges from captured-fit count); 25 -> 0 with the PN-3 fallback rescue");
    // The reduction is area-improving and reported, not silent:
    let n1 = d.reports.iter().find(|rep| rep.lever_id.to_string() == "N1.node_objective").expect("N1 report");
    let removed: usize = n1.notes.split_whitespace()
        .find_map(|tok| tok.strip_prefix("removed=").and_then(|v| v.parse().ok()))
        .expect("N1 notes must carry an exact removed=N token");
    assert_eq!(removed, 0, "N1 removed token");
    assert_eq!(n1.nodes_before - n1.nodes_after, removed,
        "N1 nodes_before - nodes_after must equal the parsed removed token");
    // fix 3: measure the N1 stage itself, not the whole-route delta (D2 improvement
    // would mask an N1 regression in final_area < baseline_area).
    // With the PN-3 rescue the baseline no longer carries the unresolved
    // chain N1 used to remove, so N1 removes nothing and its area is flat;
    // the stage contract relaxes to "never worsens" (D2 still improves the
    // route: baseline 2116.23 -> final 1836.16 on the re-pin receipt).
    assert!(n1.area_after <= n1.area_before, "N1 stage must not worsen area: {} -> {}", n1.area_before, n1.area_after);
    assert!(d.final_area < d.baseline_area, "route must not worsen area");
}
