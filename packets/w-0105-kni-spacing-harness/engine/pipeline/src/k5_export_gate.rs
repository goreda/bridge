//! k5_export_gate.rs — K5: export gate with fallback and per-pair diagnostics.
//!
//! Second-half deliverable, add-only, fix-forward v2.
//! Base: snapshots/261018-2214-integrated-tip. English-only (item 14).
//!
//! Finding B34-03/H7: 11 unsolved pairs killed a whole 253-glyph export and
//! the gate kept a counter with no per-pair diagnostic. This gate inverts
//! that: items fail, batches don't. The batch dies only when NOTHING is
//! exportable — and then it dies loud, with a batch-level reason AND the
//! per-item diagnostics (review F8). Exported outcomes carry an explicit
//! complete flag so "partial" is a fact, not an inference (review G-d).
//!
//! Bridge (item 13): consumes the k1-export-items/1 JSON emitted by the
//! kit side (k1_wire.plan_to_export_items), connecting the Python plan to
//! this Rust gate.

use std::collections::HashSet;

pub const EXPORT_ITEMS_SCHEMA: &str = "k1-export-items/1";

#[derive(Debug, Clone, PartialEq)]
pub enum ItemStatus {
    Solved,
    Failed { reason: String },
}

#[derive(Debug, Clone, PartialEq)]
pub struct ExportItem {
    pub pair: String,
    pub status: ItemStatus,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Diagnostic {
    pub pair: String,
    pub reason: String,
}

#[derive(Debug, Clone, PartialEq)]
pub enum GateOutcome {
    /// Batch ships. `complete` is false the moment any diagnostic exists,
    /// so partial shipment is an explicit fact (G-d).
    Exported { shipped: Vec<String>, diagnostics: Vec<Diagnostic>, complete: bool },
    /// The only fatal case: zero exportable items. Loud at batch level
    /// (reason) AND item level (diagnostics) — F8.
    Refused { diagnostics: Vec<Diagnostic>, reason: String },
}

pub fn export_gate(items: &[ExportItem]) -> GateOutcome {
    let mut shipped = Vec::new();
    let mut diagnostics = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    for item in items {
        let name = item.pair.trim();
        if name.is_empty() {
            // F7: an empty pair name is invalid input, never a shipment.
            diagnostics.push(Diagnostic {
                pair: item.pair.clone(),
                reason: "empty_pair_name".into(),
            });
            continue;
        }
        if !seen.insert(name.to_string()) {
            // Diagnostic integrity: a later duplicate must not shadow its own
            // real failure reason. Keep the duplicate marker AND the original
            // reason in the same row (solved duplicates keep the bare marker).
            let reason = match &item.status {
                ItemStatus::Failed { reason } => {
                    let r = reason.trim();
                    let r = if r.is_empty() { "unspecified_failure" } else { r };
                    format!("duplicate_pair_name;original_reason={}", r)
                }
                ItemStatus::Solved => "duplicate_pair_name".to_string(),
            };
            diagnostics.push(Diagnostic { pair: item.pair.clone(), reason });
            continue;
        }
        match &item.status {
            // F25: ship the normalized (trimmed) name — the same form the
            // dedup key uses. Padded input must not leak into the output.
            ItemStatus::Solved => shipped.push(name.to_string()),
            ItemStatus::Failed { reason } => {
                // Item 11: a failure without a reason is a data bug; the
                // diagnostic must still say something true.
                let reason = if reason.trim().is_empty() {
                    "unspecified_failure".to_string()
                } else {
                    reason.clone()
                };
                diagnostics.push(Diagnostic { pair: item.pair.clone(), reason });
            }
        }
    }
    if shipped.is_empty() {
        let reason = if items.is_empty() {
            "empty batch: no export items at all".to_string()
        } else {
            format!(
                "zero exportable items out of {} submitted ({} diagnostics)",
                items.len(),
                diagnostics.len()
            )
        };
        GateOutcome::Refused { diagnostics, reason }
    } else {
        let complete = diagnostics.is_empty();
        GateOutcome::Exported { shipped, diagnostics, complete }
    }
}

// --- Bridge: k1-export-items/1 JSON -> Vec<ExportItem> (item 13) ---
// Fixed-schema, std-only parser. Strict: unknown keys and malformed input
// are errors, never guesses.

struct Cursor<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Cursor<'a> {
    fn ws(&mut self) {
        while let Some(c) = self.b.get(self.i) {
            if c.is_ascii_whitespace() { self.i += 1; } else { break; }
        }
    }
    fn expect(&mut self, c: u8) -> Result<(), String> {
        self.ws();
        if self.b.get(self.i) == Some(&c) {
            self.i += 1;
            Ok(())
        } else {
            Err(format!("expected '{}' at byte {}", c as char, self.i))
        }
    }
    fn string(&mut self) -> Result<String, String> {
        self.ws();
        if self.b.get(self.i) != Some(&b'"') {
            return Err(format!("expected string at byte {}", self.i));
        }
        self.i += 1;
        let mut s = String::new();
        loop {
            match self.b.get(self.i) {
                None => return Err("unterminated string".into()),
                Some(b'"') => {
                    self.i += 1;
                    return Ok(s);
                }
                Some(b'\\') => {
                    self.i += 1;
                    match self.b.get(self.i) {
                        Some(b'"') => { s.push('"'); self.i += 1; }
                        Some(b'\\') => { s.push('\\'); self.i += 1; }
                        Some(b'/') => { s.push('/'); self.i += 1; }
                        Some(b'n') => { s.push('\n'); self.i += 1; }
                        Some(b'r') => { s.push('\r'); self.i += 1; }
                        Some(b't') => { s.push('\t'); self.i += 1; }
                        Some(b'u') => {
                            self.i += 1;
                            let hex = self.b.get(self.i..self.i + 4)
                                .ok_or("bad \\u escape")?;
                            let hex = std::str::from_utf8(hex).map_err(|_| "bad \\u escape")?;
                            let code = u32::from_str_radix(hex, 16).map_err(|_| "bad \\u escape")?;
                            s.push(char::from_u32(code).ok_or("bad \\u escape")?);
                            self.i += 4;
                        }
                        _ => return Err("bad escape".into()),
                    }
                }
                Some(_) => {
                    let ch = std::str::from_utf8(&self.b[self.i..])
                        .map_err(|_| "bad utf8")?
                        .chars().next().ok_or("bad utf8")?;
                    s.push(ch);
                    self.i += ch.len_utf8();
                }
            }
        }
    }
    fn comma_or_close(&mut self, close: u8, what: &str) -> Result<bool, String> {
        self.ws();
        match self.b.get(self.i) {
            Some(b',') => { self.i += 1; Ok(true) }
            Some(c) if *c == close => { self.i += 1; Ok(false) }
            _ => Err(format!("expected ',' or '{}' in {}", close as char, what)),
        }
    }
}

fn parse_item(c: &mut Cursor) -> Result<ExportItem, String> {
    c.expect(b'{')?;
    let (mut pair, mut status, mut reason) = (None, None, None);
    loop {
        let key = c.string()?;
        c.expect(b':')?;
        match key.as_str() {
            "pair" => pair = Some(c.string()?),
            "status" => status = Some(c.string()?),
            "reason" => reason = Some(c.string()?),
            "note" => { c.string()?; }
            other => return Err(format!("unknown item key {:?}", other)),
        }
        if !c.comma_or_close(b'}', "item")? { break; }
    }
    let pair = pair.ok_or("item missing pair")?;
    match status.as_deref() {
        Some("solved") => Ok(ExportItem { pair, status: ItemStatus::Solved }),
        Some("failed") => Ok(ExportItem {
            pair,
            status: ItemStatus::Failed { reason: reason.unwrap_or_default() },
        }),
        other => Err(format!("item status must be solved|failed, got {:?}", other)),
    }
}

/// Parse the k1-export-items/1 JSON emitted by k1_wire.plan_to_export_items.
pub fn items_from_json(text: &str) -> Result<Vec<ExportItem>, String> {
    let mut c = Cursor { b: text.as_bytes(), i: 0 };
    c.expect(b'{')?;
    let (mut items, mut schema_ok) = (None, false);
    loop {
        let key = c.string()?;
        c.expect(b':')?;
        match key.as_str() {
            "schema" => {
                if c.string()? != EXPORT_ITEMS_SCHEMA {
                    return Err("schema mismatch".into());
                }
                schema_ok = true;
            }
            "items" => {
                c.expect(b'[')?;
                let mut v = Vec::new();
                c.ws();
                if c.b.get(c.i) == Some(&b']') {
                    c.i += 1;
                } else {
                    loop {
                        v.push(parse_item(&mut c)?);
                        if !c.comma_or_close(b']', "items")? { break; }
                    }
                }
                items = Some(v);
            }
            "plan_sha256" => { c.string()?; }
            other => return Err(format!("unknown key {:?}", other)),
        }
        if !c.comma_or_close(b'}', "root")? { break; }
    }
    if !schema_ok {
        return Err("missing schema".into());
    }
    items.ok_or_else(|| "missing items".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solved(pair: &str) -> ExportItem {
        ExportItem { pair: pair.into(), status: ItemStatus::Solved }
    }
    fn failed(pair: &str, why: &str) -> ExportItem {
        ExportItem { pair: pair.into(), status: ItemStatus::Failed { reason: why.into() } }
    }

    /// Realistic kern-pair names from two 16-glyph sets (16x16=256 combos).
    fn realistic_items(solved_n: usize, failed_n: usize) -> Vec<ExportItem> {
        let glyphs = ["a", "e", "o", "n", "r", "t", "v", "w",
                      "y", "f", "g", "i", "l", "s", "u", "c"];
        let mut items = Vec::new();
        'outer: for l in &glyphs {
            for r in &glyphs {
                if items.len() >= solved_n + failed_n { break 'outer; }
                let name = format!("{} {}", l, r);
                if items.len() < solved_n {
                    items.push(solved(&name));
                } else {
                    items.push(failed(&name, "spacing unsolved"));
                }
            }
        }
        items
    }

    // P1: THE regression case from findings-part-34 H7: 253 glyphs, 11
    // unsolved pairs. The old gate killed the export; this gate ships 242
    // and names all 11. complete=false makes the partiality explicit (G-d).
    #[test]
    fn p1_eleven_failures_do_not_kill_the_batch() {
        let items = realistic_items(242, 11);
        assert_eq!(items.len(), 253);
        match export_gate(&items) {
            GateOutcome::Exported { shipped, diagnostics, complete } => {
                assert_eq!(shipped.len(), 242);
                assert_eq!(diagnostics.len(), 11);
                assert!(!complete);
                assert!(diagnostics.iter().all(|d| d.reason == "spacing unsolved"));
            }
            GateOutcome::Refused { .. } => panic!("K5 regression: batch died on 11/253"),
        }
    }

    // P2: a clean batch exports complete.
    #[test]
    fn p2_clean_batch_exports_complete() {
        match export_gate(&[solved("a v"), solved("t o")]) {
            GateOutcome::Exported { shipped, diagnostics, complete } => {
                assert_eq!(shipped, vec!["a v", "t o"]);
                assert!(diagnostics.is_empty());
                assert!(complete);
            }
            _ => panic!(),
        }
    }

    // P3: G-d — a single solved pair still exports (partial, explicit).
    #[test]
    fn p3_one_solved_of_253_exports_partial() {
        let mut items = realistic_items(0, 252);
        items.push(solved("q q")); // outside the generated 16-glyph grid
        match export_gate(&items) {
            GateOutcome::Exported { shipped, diagnostics, complete } => {
                assert_eq!(shipped, vec!["q q"]);
                assert_eq!(diagnostics.len(), 252);
                assert!(!complete);
            }
            GateOutcome::Refused { .. } => panic!("1/253 must export partial, not die"),
        }
    }

    // P4: bridge — the exact JSON emitted by k1_wire.plan_to_export_items
    // (generated by the Python side, byte-identical) parses and gates.
    #[test]
    fn p4_bridge_consumes_kit_json() {
        let json = r#"{"items":[{"pair":"a v","status":"solved"},{"pair":"t o","status":"solved"},{"pair":"y g","reason":"measurement_missing","status":"failed"}],"plan_sha256":"efb688eda0d7e949622a362c7fb921bee0edd19ff8aea0265636d43b9ce9464d","schema":"k1-export-items/1"}"#;
        let items = items_from_json(json).unwrap();
        assert_eq!(items.len(), 3);
        match export_gate(&items) {
            GateOutcome::Exported { shipped, diagnostics, complete } => {
                assert_eq!(shipped, vec!["a v", "t o"]);
                assert_eq!(diagnostics.len(), 1);
                assert_eq!(diagnostics[0].pair, "y g");
                assert_eq!(diagnostics[0].reason, "measurement_missing");
                assert!(!complete);
            }
            _ => panic!(),
        }
    }

    // N1: zero exportable items — refused LOUD at batch level (F8) with
    // every per-item reason preserved.
    #[test]
    fn n1_zero_solvable_refused_loudly() {
        let items = vec![failed("a v", "ring open"), failed("t o", "scale missing")];
        match export_gate(&items) {
            GateOutcome::Refused { diagnostics, reason } => {
                assert!(reason.contains("zero exportable items out of 2"), "got: {reason}");
                assert_eq!(diagnostics.len(), 2);
                assert_eq!(diagnostics[1].reason, "scale missing");
            }
            GateOutcome::Exported { .. } => panic!("empty export must not ship"),
        }
    }

    // N2: an empty batch is refused with a batch-level reason (F8).
    #[test]
    fn n2_empty_batch_refused_with_reason() {
        match export_gate(&[]) {
            GateOutcome::Refused { diagnostics, reason } => {
                assert!(diagnostics.is_empty());
                assert!(reason.contains("empty batch"), "got: {reason}");
            }
            GateOutcome::Exported { .. } => panic!("nothing to ship is not a shipment"),
        }
    }

    // N3: duplicate pair names — first ships, rest are diagnostics.
    #[test]
    fn n3_duplicate_pair_name_diagnosed() {
        let items = vec![solved("a v"), solved("a v"), solved("t o")];
        match export_gate(&items) {
            GateOutcome::Exported { shipped, diagnostics, complete } => {
                assert_eq!(shipped, vec!["a v", "t o"]);
                assert_eq!(diagnostics.len(), 1);
                assert_eq!(diagnostics[0].reason, "duplicate_pair_name");
                assert!(!complete);
            }
            _ => panic!(),
        }
    }

    // N8: a later failed duplicate keeps its real reason next to the duplicate marker.
    #[test]
    fn n8_failed_duplicate_keeps_original_reason() {
        let items = vec![failed("a v", "no_feasible"), failed("a v", "not_converged"), failed("a v ", "  "), solved("t o")];
        match export_gate(&items) {
            GateOutcome::Exported { shipped, diagnostics, complete } => {
                assert_eq!(shipped, vec!["t o"]);
                assert_eq!(diagnostics.len(), 3);
                assert_eq!(diagnostics[0].reason, "no_feasible");
                assert_eq!(diagnostics[1].reason, "duplicate_pair_name;original_reason=not_converged");
                assert_eq!(diagnostics[2].reason, "duplicate_pair_name;original_reason=unspecified_failure");
                assert!(!complete);
            }
            _ => panic!(),
        }
    }

    // N9: a solved duplicate keeps the bare marker (unchanged contract).
    #[test]
    fn n9_solved_duplicate_bare_marker() {
        let items = vec![failed("a v", "no_feasible"), solved("a v"), solved("t o")];
        match export_gate(&items) {
            GateOutcome::Exported { diagnostics, .. } => {
                assert_eq!(diagnostics[1].reason, "duplicate_pair_name");
            }
            _ => panic!(),
        }
    }

    // N4: a failure with an empty reason is normalized, never blank.
    #[test]
    fn n4_empty_reason_normalized() {
        let items = vec![solved("a v"), failed("t o", "  ")];
        match export_gate(&items) {
            GateOutcome::Exported { diagnostics, .. } => {
                assert_eq!(diagnostics[0].reason, "unspecified_failure");
            }
            _ => panic!(),
        }
    }

    // N5: empty pair names never ship (F7).
    #[test]
    fn n5_empty_pair_name_never_ships() {
        let items = vec![solved(""), solved("a v")];
        match export_gate(&items) {
            GateOutcome::Exported { shipped, diagnostics, .. } => {
                assert_eq!(shipped, vec!["a v"]);
                assert_eq!(diagnostics[0].reason, "empty_pair_name");
            }
            _ => panic!(),
        }
    }

    // N7: F25 — padded pair names ship normalized, not padded.
    #[test]
    fn n7_padded_pair_name_ships_trimmed() {
        let items = vec![solved(" a v "), solved("a v"), solved("t o")];
        match export_gate(&items) {
            GateOutcome::Exported { shipped, diagnostics, .. } => {
                assert_eq!(shipped, vec!["a v", "t o"]); // trimmed, deduped
                assert_eq!(diagnostics.len(), 1);
                assert_eq!(diagnostics[0].reason, "duplicate_pair_name");
            }
            _ => panic!(),
        }
    }

    // N6: bridge strictness — wrong schema and malformed JSON are errors.
    #[test]
    fn n6_bridge_rejects_wrong_schema_and_malformed() {
        assert!(items_from_json(r#"{"schema":"other/9","items":[]}"#).is_err());
        assert!(items_from_json(r#"{"schema":"k1-export-items/1"}"#).is_err());
        assert!(items_from_json(r#"{"schema":"k1-export-items/1","items":[{"pair":"a"}"#).is_err());
        assert!(items_from_json(r#"{"schema":"k1-export-items/1","items":[{"pair":"a v","status":"maybe"}]}"#).is_err());
    }
}
