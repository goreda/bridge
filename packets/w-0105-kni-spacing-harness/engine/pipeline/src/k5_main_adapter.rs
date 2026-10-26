//! k5_main_adapter.rs - K5 bind: main.rs spacing pair ledger -> export gate.
//!
//! Add-only, std-only, pure (no I/O). Connects the typed pair ledger the
//! solver already produces to `k5_export_gate::export_gate` (items fail,
//! batches do not) and to `export_gate_closure::spacing_closure`, and renders
//! the per-pair report plus receipt rows.
//!
//! Policy kept (scoped partial fallback): in `ClosureMode::Default` this
//! module NEVER returns Err and never decides whether bytes are published;
//! unresolved pairs become diagnostics and `partial=true`. Publication of an
//! illegal font stays blocked by the existing atomic publish path in main.rs.
//! `ClosureMode::Strict` (kit acceptance) returns Err on any unresolved pair,
//! on a gate refusal, or on a closure gap.

use crate::export_gate_closure::{spacing_closure, ClosureMode, ClosureReport, SpacingClosureInput};
use crate::k5_export_gate::{export_gate, Diagnostic, ExportItem, GateOutcome, ItemStatus};

/// Ledger reason codes that mean "this pair was not solved".
/// (`PairLedgerReason::code()` strings; excluded_unmeasurable is unresolved:
/// the pair was never measured and carries no kern row. The other excluded_*
/// codes and fallback_derived are accounted-for outcomes, not failures.)
pub const UNRESOLVED_CODES: [&str; 7] = [
    "no_feasible",
    "no_accepted_candidate",
    "not_converged",
    "nonfinite_failure",
    "natural_unverifiable",
    "natural_frame_conflict",
    "excluded_unmeasurable",
];

pub fn is_unresolved(code: &str) -> bool {
    UNRESOLVED_CODES.contains(&code)
}

#[derive(Clone, Debug)]
pub struct LedgerPair<'a> {
    pub left: &'a str,
    pub right: &'a str,
    pub class: &'a str,
    pub reason_code: &'a str,
}

/// Counters taken from the solution (same fields main.rs already receipts).
#[derive(Clone, Copy, Debug, Default)]
pub struct Counters {
    pub numeric_failed: usize,
    pub geometric_hold: usize,
    pub no_accepted: usize,
    pub hold_reason_lines: usize,
}

/// Fields beyond the ones main.rs reads are exercised by the tests and kept for callers.
#[allow(dead_code)]
#[derive(Clone, Debug)]
pub struct AdapterReport {
    pub submitted: usize,
    pub failed: usize,
    pub complete: bool,
    pub gate_refused: bool,
    /// Counter says failed, ledger has no unresolved row for it
    /// (counter-only failures, e.g. numeric_failed_malformed has no ledger code).
    pub unledgered_numeric: usize,
    pub closure: ClosureReport,
    pub pair_tsv: String,
    pub receipt_rows: String,
}

fn clean(s: &str) -> String {
    s.replace('\t', " ").replace('\n', " ").replace('\r', " ")
}

pub fn build_items(rows: &[LedgerPair]) -> Vec<ExportItem> {
    rows.iter()
        .map(|r| ExportItem {
            pair: format!("{}|{}|{}", r.left, r.right, r.class),
            status: if is_unresolved(r.reason_code) {
                ItemStatus::Failed { reason: r.reason_code.to_string() }
            } else {
                ItemStatus::Solved
            },
        })
        .collect()
}

pub fn evaluate(rows: &[LedgerPair], c: Counters, mode: ClosureMode) -> Result<AdapterReport, String> {
    let items = build_items(rows);
    let outcome = export_gate(&items);
    let (shipped, diags, complete, refused, refuse_reason): (usize, Vec<Diagnostic>, bool, bool, String) = match &outcome {
        GateOutcome::Exported { shipped, diagnostics, complete } => {
            (shipped.len(), diagnostics.clone(), *complete, false, String::new())
        }
        GateOutcome::Refused { diagnostics, reason } => (0, diagnostics.clone(), false, true, reason.clone()),
    };
    let codes: Vec<&str> = rows.iter().map(|r| r.reason_code).collect();
    let closure = spacing_closure(
        &SpacingClosureInput {
            numeric_failed: c.numeric_failed,
            geometric_hold: c.geometric_hold,
            no_accepted: c.no_accepted,
            ledger_codes: &codes,
            hold_reason_lines: c.hold_reason_lines,
        },
        ClosureMode::Default,
    )?;
    // Counter-only numeric failures: numeric_failed minus ledger rows that carry a numeric-failure code.
    let ledger_numeric = codes
        .iter()
        .filter(|x| matches!(**x, "not_converged" | "nonfinite_failure" | "natural_unverifiable" | "natural_frame_conflict"))
        .count();
    let unledgered_numeric = c.numeric_failed.saturating_sub(ledger_numeric);

    let mut tsv = String::from("pair\tstatus\treason\n");
    for it in &items {
        if let ItemStatus::Solved = it.status {
            tsv.push_str(&format!("{}\tsolved\t\n", clean(it.pair.trim())));
        }
    }
    for d in &diags {
        tsv.push_str(&format!("{}\tfailed\t{}\n", clean(&d.pair), clean(&d.reason)));
    }
    if unledgered_numeric > 0 {
        tsv.push_str(&format!("(counter-only)\tfailed\tunledgered_numeric_failure_x{}\n", unledgered_numeric));
    }
    let failed = diags.len();
    let mut rb = format!(
        "export_gate_pairs\tsubmitted\t{}\tshipped\t{}\tfailed\t{}\tcomplete\t{}\tgate_refused\t{}\tunledgered_numeric\t{}\treport\texport-gate-pairs.tsv\n",
        items.len(), shipped, failed, complete && unledgered_numeric == 0, refused, unledgered_numeric);
    if refused {
        rb.push_str(&format!("warning\texport_gate_pairs_refused\t{}\tdegrade\tpair_outcomes_only_glyphs_still_ship\n", clean(&refuse_reason)));
    }
    if unledgered_numeric > 0 {
        rb.push_str(&format!("warning\texport_gate_pairs_counter_only\tnumeric_failed_without_ledger_row\t{}\n", unledgered_numeric));
    }
    rb.push_str(&closure.rows);

    if mode == ClosureMode::Strict && (failed > 0 || refused || unledgered_numeric > 0 || !closure.closed) {
        return Err(format!(
            "export gate strict: failed={} refused={} unledgered_numeric={} closure_closed={}",
            failed, refused, unledgered_numeric, closure.closed));
    }
    Ok(AdapterReport {
        submitted: items.len(), failed, complete: complete && unledgered_numeric == 0,
        gate_refused: refused, unledgered_numeric, closure, pair_tsv: tsv, receipt_rows: rb,
    })
}

/// Typed, pinned process exit code for a run whose receipt carries a `not_approved` export_gate row.
pub const EXIT_NOT_APPROVED: u8 = 3;

/// Distinct unresolved ledger codes, deterministic (sorted, deduplicated).
pub fn unresolved_codes_present(rows: &[LedgerPair]) -> Vec<&'static str> {
    let mut v: Vec<&'static str> = UNRESOLVED_CODES.iter().copied()
        .filter(|c| rows.iter().any(|r| r.reason_code == *c)).collect();
    v.sort_unstable();
    v
}

/// Receipt rows `export_gate<TAB>diagnostic<TAB>not_approved<TAB>reason<TAB><code>`, one per unresolved code,
/// emitted only when an .otf was produced (no .otf: no row).
pub fn not_approved_rows(codes: &[&str], otf_produced: bool) -> String {
    if !otf_produced { return String::new(); }
    let mut sorted: Vec<&str> = codes.to_vec();
    sorted.sort_unstable();
    sorted.dedup();
    sorted.iter().filter(|c| !c.is_empty())
        .map(|c| format!("export_gate\tdiagnostic\tnot_approved\treason\t{c}\n")).collect()
}

/// True when the receipt text carries at least one full not_approved row (5 tab fields, non-empty code).
pub fn receipt_has_not_approved(receipt: &str) -> bool {
    receipt.lines().any(|l| {
        let f: Vec<&str> = l.split('\t').collect();
        f.len() == 5 && f[0] == "export_gate" && f[1] == "diagnostic" && f[2] == "not_approved" && f[3] == "reason" && !f[4].is_empty()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rows11<'a>(codes: &'a [&'a str], names: &'a [(String, String)]) -> Vec<LedgerPair<'a>> {
        names.iter().zip(codes.iter()).map(|((l, r), c)| LedgerPair { left: l, right: r, class: "c", reason_code: c }).collect()
    }
    fn names(n: usize) -> Vec<(String, String)> {
        (0..n).map(|i| (format!("L{i}"), format!("R{i}"))).collect()
    }

    /// 11 failed pairs among 253 (the B34-03/H7 shape): every pair/reason reported, run not refused.
    #[test]
    fn eleven_failed_pairs_of_253_all_reported_and_not_refused() {
        let nm = names(253);
        let mut codes: Vec<&str> = vec!["fallback_derived"; 242];
        codes.extend(["no_feasible"; 7]);
        codes.extend(["no_accepted_candidate"; 4]);
        let rows = rows11(&codes, &nm);
        let c = Counters { numeric_failed: 0, geometric_hold: 7, no_accepted: 4, hold_reason_lines: 11 };
        let r = evaluate(&rows, c, ClosureMode::Default).unwrap();
        assert_eq!(r.submitted, 253);
        assert_eq!(r.failed, 11);
        assert!(!r.complete && !r.gate_refused);
        assert!(r.closure.closed && r.closure.unresolved == 11);
        let failed_rows = r.pair_tsv.lines().filter(|l| l.contains("\tfailed\t")).count();
        assert_eq!(failed_rows, 11);
        assert_eq!(r.pair_tsv.lines().filter(|l| l.contains("\tfailed\tno_feasible")).count(), 7);
        assert_eq!(r.pair_tsv.lines().filter(|l| l.contains("\tfailed\tno_accepted_candidate")).count(), 4);
        assert!(r.receipt_rows.contains("shipped\t242\tfailed\t11\tcomplete\tfalse"));
    }

    #[test]
    fn all_failed_is_gate_refusal_row_not_err_in_default() {
        let nm = names(3);
        let codes = ["no_feasible"; 3];
        let rows = rows11(&codes, &nm);
        let c = Counters { numeric_failed: 0, geometric_hold: 3, no_accepted: 0, hold_reason_lines: 3 };
        let r = evaluate(&rows, c, ClosureMode::Default).unwrap();
        assert!(r.gate_refused && r.failed == 3);
        assert!(r.receipt_rows.contains("warning\texport_gate_pairs_refused"));
        assert!(evaluate(&rows, c, ClosureMode::Strict).is_err());
    }

    #[test]
    fn clean_run_complete_in_both_modes() {
        let nm = names(5);
        let codes = ["fallback_derived", "excluded_self_pair", "excluded_below_epsilon", "fallback_derived", "fallback_derived"];
        let rows = rows11(&codes, &nm);
        for m in [ClosureMode::Default, ClosureMode::Strict] {
            let r = evaluate(&rows, Counters::default(), m).unwrap();
            assert!(r.complete && r.failed == 0 && !r.gate_refused);
        }
    }

    /// Negative: a numeric failure the ledger cannot account for is flagged, not hidden.
    #[test]
    fn counter_only_numeric_failure_is_flagged() {
        let nm = names(2);
        let codes = ["fallback_derived", "natural_unverifiable"];
        let rows = rows11(&codes, &nm);
        let c = Counters { numeric_failed: 3, geometric_hold: 0, no_accepted: 0, hold_reason_lines: 3 };
        let r = evaluate(&rows, c, ClosureMode::Default).unwrap();
        assert_eq!(r.unledgered_numeric, 2);
        assert!(!r.complete);
        assert!(r.pair_tsv.contains("(counter-only)\tfailed\tunledgered_numeric_failure_x2"));
        assert!(evaluate(&rows, c, ClosureMode::Strict).is_err());
    }

    #[test]
    fn duplicate_and_blank_names_are_loud_not_shipped() {
        let nm = vec![("A".to_string(), "B".to_string()), ("A".to_string(), "B".to_string()), (String::new(), String::new())];
        let codes = ["fallback_derived", "fallback_derived", "fallback_derived"];
        let rows: Vec<LedgerPair> = nm.iter().zip(codes.iter()).map(|((l, r), c)| LedgerPair { left: l, right: r, class: "", reason_code: c }).collect();
        let r = evaluate(&rows, Counters::default(), ClosureMode::Default).unwrap();
        assert_eq!(r.failed, 1);
        assert!(r.pair_tsv.contains("duplicate_pair_name"));
    }

    /// Negative: a failed duplicate pair keeps its real reason in the same report row.
    #[test]
    fn failed_duplicate_pair_keeps_original_reason_in_report() {
        let rows = vec![
            LedgerPair { left: "A", right: "B", class: "c", reason_code: "no_feasible" },
            LedgerPair { left: "A", right: "B", class: "c", reason_code: "natural_unverifiable" },
        ];
        let c = Counters { numeric_failed: 1, geometric_hold: 1, no_accepted: 0, hold_reason_lines: 2 };
        let r = evaluate(&rows, c, ClosureMode::Default).unwrap();
        assert_eq!(r.failed, 2);
        assert!(r.pair_tsv.contains("A|B|c\tfailed\tno_feasible\n"));
        assert!(r.pair_tsv.contains("A|B|c\tfailed\tduplicate_pair_name;original_reason=natural_unverifiable\n"));
    }

    #[test]
    fn tabs_and_newlines_cannot_break_the_report() {
        let (l, r_) = ("a\tb".to_string(), "c\nd".to_string());
        let rows = vec![LedgerPair { left: &l, right: &r_, class: "x", reason_code: "no_feasible" }];
        let c = Counters { numeric_failed: 0, geometric_hold: 1, no_accepted: 0, hold_reason_lines: 1 };
        let r = evaluate(&rows, c, ClosureMode::Default).unwrap();
        for line in r.pair_tsv.lines().skip(1) { assert_eq!(line.matches('\t').count(), 2, "{line:?}"); }
    }

    #[test]
    fn empty_ledger_is_not_a_failure_in_default() {
        let r = evaluate(&[], Counters::default(), ClosureMode::Default).unwrap();
        assert_eq!(r.submitted, 0);
        assert!(r.gate_refused, "gate reports empty batch; run is NOT blocked in default mode");
        assert!(r.receipt_rows.contains("submitted\t0"));
    }

    #[test]
    fn not_approved_none_when_no_unresolved_code() {
        let nm = names(2);
        let rows = rows11(&["fallback_derived", "excluded_overlap"], &nm);
        assert!(unresolved_codes_present(&rows).is_empty());
        assert_eq!(not_approved_rows(&unresolved_codes_present(&rows), true), "");
    }
    #[test]
    fn not_approved_single_code_one_full_row() {
        let nm = names(3);
        let rows = rows11(&["no_feasible", "no_feasible", "fallback_derived"], &nm);
        let r = not_approved_rows(&unresolved_codes_present(&rows), true);
        assert_eq!(r, "export_gate\tdiagnostic\tnot_approved\treason\tno_feasible\n");
        assert!(receipt_has_not_approved(&r));
    }
    #[test]
    fn not_approved_multi_code_sorted_one_row_each() {
        let nm = names(4);
        let rows = rows11(&["not_converged", "excluded_unmeasurable", "no_feasible", "not_converged"], &nm);
        let r = not_approved_rows(&unresolved_codes_present(&rows), true);
        let got: Vec<&str> = r.lines().map(|l| l.rsplit('\t').next().unwrap()).collect();
        assert_eq!(got, vec!["excluded_unmeasurable", "no_feasible", "not_converged"]);
    }
    #[test]
    fn not_approved_no_row_without_otf() {
        let nm = names(1);
        let rows = rows11(&["no_feasible"], &nm);
        assert_eq!(not_approved_rows(&unresolved_codes_present(&rows), false), "");
        assert!(!receipt_has_not_approved("export_gate\tdiagnostic\tnot_approved\treason\n"));
        assert!(!receipt_has_not_approved("export_gate_pairs\tsubmitted\t1\n"));
    }
}
