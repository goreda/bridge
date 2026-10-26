//! Order-preserving reduce for the stage-1 fit ledgers (pieces 13-15).
//!
//! Parallel fit workers return one `LedgerEntry` per glyph tagged with its manifest
//! index. `reduce_in_manifest_order` sorts by that index (not by completion order) and
//! folds the entries into a `Stage1Ledger` sequentially, so the exclusion list, the
//! typed fallback totals, `fallback-glyphs.tsv`, the stage1 pin emission order are identical for any job count. The serial loop uses the same
//! `absorb`, which keeps jobs=1 byte-identical to the old inline accumulation.

// Helpers only: the stage-1 driver (par-fit patch A, stage1_reduce) owns calling the reduce.
// Until it lands the only non-test caller is exclusion_counter_lines.
#![allow(dead_code)]

use std::collections::HashMap;

/// What one glyph's fit contributed to the run ledgers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LedgerEntry {
    Drawn { name: String, pin: String, fallback_spans: usize, sub_grid: usize },
    Excluded { name: String, codepoint: u32, reason: String },
}

#[derive(Default, Debug, Clone, PartialEq, Eq)]
pub struct Stage1Ledger {
    /// (glyph, codepoint, reason) in manifest order.
    pub exclusions: Vec<(String, Option<u32>, String)>,
    pub fallback_span_total: usize,
    /// (glyph, typed fallback spans) in manifest order, zero rows included (the tsv filters).
    pub fallback_glyph_spans: Vec<(String, usize)>,
    pub sub_grid_floor_total: usize,
    /// (glyph, png sha256) in manifest order; a repeated glyph keeps its last pin, like the map.
    pins_ordered: Vec<(String, String)>,
    pin_slot: HashMap<String, usize>,
}

impl Stage1Ledger {
    pub fn new() -> Self { Self::default() }

    /// Fold one glyph. Overflow of the checked fallback total is an error naming the glyph.
    pub fn absorb(&mut self, e: LedgerEntry) -> Result<(), String> {
        match e {
            LedgerEntry::Drawn { name, pin, fallback_spans, sub_grid } => {
                self.fallback_span_total = self.fallback_span_total.checked_add(fallback_spans)
                    .ok_or_else(|| format!("fallback ledger total overflow at glyph {name}"))?;
                self.sub_grid_floor_total = self.sub_grid_floor_total.checked_add(sub_grid)
                    .ok_or_else(|| format!("sub-grid floor total overflow at glyph {name}"))?;
                self.fallback_glyph_spans.push((name.clone(), fallback_spans));
                self.set_pin(name, pin);
            }
            LedgerEntry::Excluded { name, codepoint, reason } => {
                self.exclusions.push((name, Some(codepoint), reason));
            }
        }
        Ok(())
    }

    pub fn set_pin(&mut self, name: String, pin: String) {
        if let Some(&i) = self.pin_slot.get(&name) {
            self.pins_ordered[i].1 = pin;
        } else {
            self.pin_slot.insert(name.clone(), self.pins_ordered.len());
            self.pins_ordered.push((name, pin));
        }
    }

    /// Pins in emission (manifest) order.
    pub fn pins_in_order(&self) -> &[(String, String)] { &self.pins_ordered }

    /// Lookup map for consumers that only `get`.
    pub fn pins_map(&self) -> HashMap<String, String> { self.pins_ordered.iter().cloned().collect() }

    /// `glyph_exclusions_*` and `glyph_skip_total` receipt rows; empty when nothing was excluded.
    pub fn exclusion_counter_lines(&self) -> String { exclusion_counter_lines(&self.exclusions) }
}

/// Counter rows for the exclusion ledger. Counts are derived from the ordered list only.
pub fn exclusion_counter_lines(exclusions: &[(String, Option<u32>, String)]) -> String {
    if exclusions.is_empty() { return String::new(); }
    let intentional_empty = exclusions.iter().filter(|(_, _, w)| w.contains("no contours")).count();
    let failures = exclusions.len() - intentional_empty;
    format!(
        "glyph_exclusions_total\t{}\t(run partial - not all manifest glyphs processed)\nglyph_exclusions_intentional_empty\t{}\nglyph_exclusions_failures\t{}\n{}",
        exclusions.len(), intentional_empty, failures, crate::glyph_skip_total_line(exclusions.len()))
}

/// Sort worker results by manifest index and fold them sequentially. `n` is the number of
/// jobs launched: the indices must be exactly 0..n, each once. Anything else is refused.
pub fn reduce_in_manifest_order(n: usize, mut outcomes: Vec<(usize, LedgerEntry)>) -> Result<Stage1Ledger, String> {
    if outcomes.len() != n {
        return Err(format!("fit outcomes: expected {n}, got {}", outcomes.len()));
    }
    outcomes.sort_by_key(|(i, _)| *i);
    for (want, (got, _)) in outcomes.iter().enumerate() {
        if *got != want {
            return Err(if *got < want {
                format!("duplicate fit outcome for manifest index {got}")
            } else {
                format!("missing fit outcome for manifest index {want} (next seen {got})")
            });
        }
    }
    let mut l = Stage1Ledger::new();
    for (_, e) in outcomes { l.absorb(e)?; }
    Ok(l)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn drawn(n: &str, f: usize) -> LedgerEntry {
        LedgerEntry::Drawn { name: n.into(), pin: format!("pin-{n}"), fallback_spans: f, sub_grid: 1 }
    }
    fn excl(n: &str, cp: u32, r: &str) -> LedgerEntry {
        LedgerEntry::Excluded { name: n.into(), codepoint: cp, reason: r.into() }
    }
    fn sample() -> Vec<(usize, LedgerEntry)> {
        vec![(0, drawn("A", 0)), (1, excl("space", 0x20, "no contours")), (2, drawn("g", 4)),
             (3, excl("x", 0x78, "unreadable")), (4, drawn("B", 2))]
    }
    fn serial(v: &[(usize, LedgerEntry)]) -> Stage1Ledger {
        let mut l = Stage1Ledger::new();
        for (_, e) in v { l.absorb(e.clone()).unwrap(); }
        l
    }

    #[test]
    fn exclusions_ordered_and_counters_exact() {
        let l = reduce_in_manifest_order(5, sample()).unwrap();
        assert_eq!(l.exclusions.iter().map(|e| e.0.as_str()).collect::<Vec<_>>(), ["space", "x"]);
        assert_eq!(l.exclusion_counter_lines(),
            "glyph_exclusions_total\t2\t(run partial - not all manifest glyphs processed)\nglyph_exclusions_intentional_empty\t1\nglyph_exclusions_failures\t1\nglyph_skip_total\t2\n");
        assert_eq!(exclusion_counter_lines(&[]), "");
    }

    #[test]
    fn any_arrival_order_equals_serial() {
        let base = sample();
        let want = serial(&base);
        // every rotation and the reverse
        for k in 0..base.len() {
            let mut v = base.clone();
            v.rotate_left(k);
            assert_eq!(reduce_in_manifest_order(5, v).unwrap(), want);
        }
        let mut r = base.clone();
        r.reverse();
        assert_eq!(reduce_in_manifest_order(5, r).unwrap(), want);
    }

    #[test]
    fn fallback_ledger_total_and_tsv_bytes_equal_serial() {
        let mut r = sample();
        r.reverse();
        let l = reduce_in_manifest_order(5, r).unwrap();
        assert_eq!(l.fallback_span_total, 6);
        assert_eq!(l.sub_grid_floor_total, 3);
        assert_eq!(l.fallback_glyph_spans, vec![("A".to_string(), 0), ("g".to_string(), 4), ("B".to_string(), 2)]);
        let tsv = |rows: &[(String, usize)]| {
            let mut t = String::from("glyph\tspans\n");
            for (n, c) in rows { if *c > 0 { t.push_str(&format!("{n}\t{c}\n")); } }
            t
        };
        assert_eq!(tsv(&l.fallback_glyph_spans), "glyph\tspans\ng\t4\nB\t2\n");
    }

    #[test]
    fn fallback_total_overflow_is_typed_error_reversed_arrival() {
        let v = vec![(1, drawn("b", 1)), (0, drawn("a", usize::MAX))];
        assert!(reduce_in_manifest_order(2, v).unwrap_err().contains("fallback ledger total overflow at glyph b"));
    }

    #[test]
    fn sub_grid_total_overflow_is_typed_error_reversed_arrival() {
        let big = |n: &str, k: usize| LedgerEntry::Drawn { name: n.into(), pin: "p".into(), fallback_spans: 0, sub_grid: k };
        let v = vec![(1, big("b", 1)), (0, big("a", usize::MAX))];
        assert!(reduce_in_manifest_order(2, v).unwrap_err().contains("sub-grid floor total overflow at glyph b"));
    }

    #[test]
    fn indices_must_be_exactly_zero_to_n() {
        let e = |n: &str| drawn(n, 0);
        assert!(reduce_in_manifest_order(2, vec![(0, e("a"))]).unwrap_err().contains("expected 2, got 1"));
        assert!(reduce_in_manifest_order(1, vec![(0, e("a")), (1, e("b"))]).is_err());
        assert!(reduce_in_manifest_order(2, vec![(0, e("a")), (2, e("b"))]).unwrap_err().contains("missing fit outcome for manifest index 1"));
        assert!(reduce_in_manifest_order(2, vec![(1, e("a")), (1, e("b"))]).unwrap_err().contains("missing fit outcome for manifest index 0"));
        assert!(reduce_in_manifest_order(2, vec![(0, e("a")), (0, e("b"))]).unwrap_err().contains("duplicate fit outcome for manifest index 0"));
        assert!(reduce_in_manifest_order(0, vec![]).unwrap().exclusions.is_empty());
    }

    #[test]
    fn repeated_glyph_name_matches_old_serial_inline_behavior() {
        // Old inline code: exclusions Vec::push (no dedupe), fallback_glyph_spans push (no dedupe),
        // stage1_pins HashMap::insert (last value wins), totals summed per occurrence.
        let v = vec![(0, drawn("a", 1)), (1, excl("a", 0x61, "unreadable")), (2, LedgerEntry::Drawn { name: "a".into(), pin: "late".into(), fallback_spans: 2, sub_grid: 0 })];
        let l = reduce_in_manifest_order(3, v).unwrap();
        assert_eq!(l.exclusions.len(), 1);
        assert_eq!(l.fallback_glyph_spans, vec![("a".to_string(), 1), ("a".to_string(), 2)]);
        assert_eq!(l.fallback_span_total, 3);
        assert_eq!(l.pins_in_order(), &[("a".to_string(), "late".to_string())]);
        assert_eq!(l.pins_map().get("a").map(String::as_str), Some("late"));
    }

    #[test]
    fn skip_total_line_bytes_locked() {
        assert_eq!(crate::glyph_skip_total_line(2), "glyph_skip_total\t2\n");
        assert!(exclusion_counter_lines(&[("x".into(), Some(1), "r".into())]).ends_with("glyph_skip_total\t1\n"));
    }

    #[test]
    fn pins_emit_in_manifest_order_not_completion_order() {
        let mut r = sample();
        r.reverse();
        let l = reduce_in_manifest_order(5, r).unwrap();
        assert_eq!(l.pins_in_order().iter().map(|p| p.0.as_str()).collect::<Vec<_>>(), ["A", "g", "B"]);
        let m = l.pins_map();
        assert_eq!(m.get("g").map(String::as_str), Some("pin-g"));
        assert!(m.get("x").is_none());
    }

    #[test]
    fn repeated_pin_keeps_slot_and_last_value() {
        let mut l = Stage1Ledger::new();
        l.set_pin("a".into(), "1".into());
        l.set_pin("b".into(), "2".into());
        l.set_pin("a".into(), "3".into());
        assert_eq!(l.pins_in_order(), &[("a".to_string(), "3".to_string()), ("b".to_string(), "2".to_string())]);
    }
}
