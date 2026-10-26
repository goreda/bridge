//! K5 (export gate fallback), second half: a pure closure check that every
//! unresolved spacing pair is accounted for by a per-pair diagnostic, plus the
//! receipt rows that say so. Never refuses in Default mode (partial export
//! stays the rule); Strict mode returns Err so a kit-acceptance caller can
//! refuse. No I/O, no solver math. Add-only: it reads counters and ledger
//! reason codes that already exist.

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ClosureMode { Default, Strict }

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SpacingClosureInput<'a> {
    pub numeric_failed: usize,
    pub geometric_hold: usize,
    pub no_accepted: usize,
    /// `PairLedgerReason::code()` of every pair_ledger row, in order.
    pub ledger_codes: &'a [&'a str],
    /// solved.hold_reasons.len(): one line per held pair of the three classes above.
    pub hold_reason_lines: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ClosureReport {
    pub unresolved: usize,
    pub closed: bool,
    pub problems: Vec<String>,
    pub rows: String,
}

fn count(codes: &[&str], c: &str) -> usize { codes.iter().filter(|x| **x == c).count() }

/// W4 candidate (item 8): ledger codes of the numeric_failed class, derived from
/// metrics/src/self_anchored_spacing.rs tier-1/tier-2 paths (lines ~2616-2778):
/// every pair counted into numeric_failed_pairs and NOT later resolved (decremented
/// with a fallback_derived row) is ledgered under exactly one of these four codes:
/// nonfinite_failure (NonFiniteFailure), not_converged (NotConverged: malformed tier-1
/// hold, widened-solve re-guard failure, widened-solve failure), natural_unverifiable
/// (NaturalUnverifiable), natural_frame_conflict (NaturalFrameConflict).
pub const NUMERIC_FAILED_CODES: [&str; 4] =
    ["nonfinite_failure", "not_converged", "natural_unverifiable", "natural_frame_conflict"];

pub fn spacing_closure(i: &SpacingClosureInput, mode: ClosureMode) -> Result<ClosureReport, String> {
    let unresolved = i.numeric_failed.checked_add(i.geometric_hold)
        .and_then(|a| a.checked_add(i.no_accepted))
        .ok_or_else(|| "spacing closure: unresolved counter overflow".to_string())?;
    let mut problems = Vec::new();
    let nf = count(i.ledger_codes, "no_feasible");
    if nf != i.geometric_hold {
        problems.push(format!("geometric_hold={} but no_feasible ledger rows={}", i.geometric_hold, nf));
    }
    let na = count(i.ledger_codes, "no_accepted_candidate");
    if na != i.no_accepted {
        problems.push(format!("no_accepted={} but no_accepted_candidate ledger rows={}", i.no_accepted, na));
    }
    // W4 candidate (item 8, F7): the same cross-check for the numeric_failed class.
    // Baseline gap: numeric_failed was covered only by the hold_reason_lines total,
    // so a numeric counter/ledger divergence passed silently (W4 probe q8).
    let nfc: usize = NUMERIC_FAILED_CODES.iter().map(|c| count(i.ledger_codes, c)).sum();
    if nfc != i.numeric_failed {
        problems.push(format!("numeric_failed={} but numeric-class ledger rows={} (nonfinite_failure+not_converged+natural_unverifiable+natural_frame_conflict)", i.numeric_failed, nfc));
    }
    if i.hold_reason_lines != unresolved {
        problems.push(format!("unresolved={} but hold_reason lines={}", unresolved, i.hold_reason_lines));
    }
    let closed = problems.is_empty();
    let mut rows = format!(
        "spacing_gate_closure\tunresolved\t{}\tnumeric_failed\t{}\tgeometric_hold\t{}\tno_accepted\t{}\tdiagnosed\t{}\tclosed\t{}\n",
        unresolved, i.numeric_failed, i.geometric_hold, i.no_accepted, i.hold_reason_lines, closed);
    for p in &problems { rows.push_str(&format!("warning\tspacing_gate_closure_gap\t{}\n", p.replace('\t', " ").replace('\n', " "))); }
    if mode == ClosureMode::Strict && (unresolved > 0 || !closed) {
        return Err(format!("spacing closure strict: unresolved={} closed={} problems={:?}", unresolved, closed, problems));
    }
    Ok(ClosureReport { unresolved, closed, problems, rows })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn inp<'a>(n: usize, g: usize, a: usize, codes: &'a [&'a str], h: usize) -> SpacingClosureInput<'a> {
        SpacingClosureInput { numeric_failed: n, geometric_hold: g, no_accepted: a, ledger_codes: codes, hold_reason_lines: h }
    }
    #[test]
    fn clean_run_is_closed_in_both_modes() {
        for m in [ClosureMode::Default, ClosureMode::Strict] {
            let r = spacing_closure(&inp(0, 0, 0, &["fallback_derived"], 0), m).unwrap();
            assert!(r.closed && r.unresolved == 0 && r.problems.is_empty());
            assert!(r.rows.contains("closed\ttrue"));
        }
    }
    #[test]
    fn eleven_unresolved_pairs_never_refuse_in_default() {
        let codes = ["no_feasible"; 7].iter().chain(["no_accepted_candidate"; 4].iter()).copied().collect::<Vec<_>>();
        let r = spacing_closure(&inp(0, 7, 4, &codes, 11), ClosureMode::Default).unwrap();
        assert_eq!(r.unresolved, 11);
        assert!(r.closed);
        assert!(r.rows.contains("unresolved\t11"));
    }
    #[test]
    fn strict_refuses_when_unresolved() {
        let codes = ["no_feasible"];
        let e = spacing_closure(&inp(0, 1, 0, &codes, 1), ClosureMode::Strict).unwrap_err();
        assert!(e.contains("unresolved=1"));
    }
    #[test]
    fn counter_only_rejection_is_flagged_not_hidden() {
        // counter says 3 geometric holds but ledger lists 1: the old "counter-only" defect.
        let r = spacing_closure(&inp(0, 3, 0, &["no_feasible"], 3), ClosureMode::Default).unwrap();
        assert!(!r.closed);
        assert!(r.rows.contains("spacing_gate_closure_gap\tgeometric_hold=3 but no_feasible ledger rows=1"));
        assert!(spacing_closure(&inp(0, 3, 0, &["no_feasible"], 3), ClosureMode::Strict).is_err());
    }
    #[test]
    fn missing_hold_reason_lines_flagged() {
        // W4 candidate amendment: this fixture (numeric_failed=2, zero ledger rows) now
        // yields TWO problems - the new numeric-class cross-check AND the hold_reason
        // total. Baseline asserted exactly 1. Both are intended.
        let r = spacing_closure(&inp(2, 0, 0, &[], 1), ClosureMode::Default).unwrap();
        assert!(!r.closed && r.problems.len() == 2, "got {:?}", r.problems);
        assert!(r.problems.iter().any(|p| p.contains("numeric_failed=2 but numeric-class ledger rows=0")));
        assert!(r.problems.iter().any(|p| p.contains("unresolved=2 but hold_reason lines=1")));
    }
    #[test]
    fn extra_ledger_rows_flagged() {
        let r = spacing_closure(&inp(0, 0, 1, &["no_accepted_candidate", "no_accepted_candidate"], 1), ClosureMode::Default).unwrap();
        assert!(!r.closed);
    }
    #[test]
    fn overflow_is_typed_error_in_both_modes() {
        for m in [ClosureMode::Default, ClosureMode::Strict] {
            assert!(spacing_closure(&inp(usize::MAX, 1, 0, &[], 0), m).unwrap_err().contains("overflow"));
        }
    }
    // ---- W4 candidate tests (item 8): numeric_failed ledger cross-check ----
    #[test]
    fn w4_numeric_class_rows_close() {
        // 3 numeric failures, all four numeric-class codes represented across the ledger
        let codes = ["nonfinite_failure", "not_converged", "natural_unverifiable"];
        let r = spacing_closure(&inp(3, 0, 0, &codes, 3), ClosureMode::Default).unwrap();
        assert!(r.closed && r.problems.is_empty(), "got {:?}", r.problems);
    }
    #[test]
    fn w4_numeric_gap_flagged_not_hidden() {
        // F7: counter says 2 numeric failures, ledger shows none. Baseline: closed.
        let r = spacing_closure(&inp(2, 0, 0, &[], 2), ClosureMode::Default).unwrap();
        assert!(!r.closed);
        assert!(r.rows.contains("numeric_failed=2 but numeric-class ledger rows=0"));
        assert!(spacing_closure(&inp(2, 0, 0, &[], 2), ClosureMode::Strict).is_err());
    }
    #[test]
    fn w4_numeric_partial_coverage_flagged() {
        let codes = ["nonfinite_failure"];
        let r = spacing_closure(&inp(3, 0, 0, &codes, 3), ClosureMode::Default).unwrap();
        assert!(!r.closed);
        assert!(r.problems.iter().any(|p| p.contains("numeric_failed=3 but numeric-class ledger rows=1")));
    }
    #[test]
    fn w4_fallback_derived_rows_do_not_count_as_numeric() {
        // resolved tier-2 pairs carry fallback_derived; they must not satisfy the check
        let r = spacing_closure(&inp(1, 0, 0, &["fallback_derived"], 1), ClosureMode::Default).unwrap();
        assert!(!r.closed);
        assert!(r.problems.iter().any(|p| p.contains("numeric_failed=1 but numeric-class ledger rows=0")));
    }
    #[test]
    fn w4_non_numeric_codes_do_not_inflate_the_count() {
        // a no_feasible row while numeric_failed=0 must not satisfy a numeric expectation
        let r = spacing_closure(&inp(0, 1, 0, &["no_feasible"], 1), ClosureMode::Default).unwrap();
        assert!(r.closed, "got {:?}", r.problems);
    }
    #[test]
    fn w4_stray_numeric_row_with_zero_counter_flagged() {
        // ledger carries a numeric-class row the counter does not know (reverse direction)
        let r = spacing_closure(&inp(0, 0, 0, &["natural_frame_conflict"], 0), ClosureMode::Default).unwrap();
        assert!(!r.closed);
        assert!(r.problems.iter().any(|p| p.contains("numeric_failed=0 but numeric-class ledger rows=1")));
    }
    #[test]
    fn rows_have_no_tabs_or_newlines_in_gap_text() {
        let r = spacing_closure(&inp(0, 1, 0, &[], 0), ClosureMode::Default).unwrap();
        for l in r.rows.lines().filter(|l| l.starts_with("warning\tspacing_gate_closure_gap")) { assert_eq!(l.matches('\t').count(), 2); }
    }
}
