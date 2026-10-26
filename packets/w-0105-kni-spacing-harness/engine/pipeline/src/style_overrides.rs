//! DECLARED STYLE OVERRIDES (engine/pipeline/src/style_overrides.rs).
//!
//! Style-scoped declared conventions, single source: the kit's
//! `style-overrides.tsv` (chief interface decision 2026-10-17; format frozen).
//! One row per style: `family TAB style TAB lsb TAB rsb TAB note`, mandatory
//! header. The values are owner-declared convention data with provenance
//! (like PAUL_NEW_DESCENDER_UNITS): declared, never derived, never guessed.
//! Convention doc: docs/kni/2026-10-17-mona-alt-monospace-convention.md.
//!
//! Semantics (chief ruling 2026-10-17): SET, never ADD. When the run's style
//! matches a row, the manifest's lsb_add/rsb_add (and the kit menu /
//! --lsb-add/--rsb-add flags behind them) are IGNORED; the post-step values
//! are SET from the row. One injection point (manifest -> run_config ->
//! post_metrics), so the value is applied exactly once and 40/45 can never
//! become 80/90.
use kni_core::cff_reader::sha256_hex;
use std::collections::BTreeMap;
use std::path::Path;

/// Mandatory first line of the table (format frozen).
pub const HEADER: &str = "family\tstyle\tlsb\trsb\tnote";

/// A table row is a DECLARED convention only when its note starts with this
/// prefix. Other rows (kit presets the launcher applies as plain flag values,
/// e.g. Marq/Alternate 25/25) stay inert for the engine: they neither SET the
/// post-step nor stop spacing/kern.
pub const DECLARED_NOTE_PREFIX: &str = "engine declared convention";

/// One declared override row.
#[derive(Clone, Debug, PartialEq)]
pub struct StyleOverride {
    pub lsb_add: f64,
    pub rsb_add: f64,
    pub note: String,
}

#[derive(Clone, Debug, PartialEq)]
pub enum OverrideError {
    Io { path: String, reason: String },
    /// Pinned evidence mismatch: the file read is not the pinned table.
    ShaMismatch { path: String, expected: String, actual: String },
    EmptyTable,
    BadHeader { found: String },
    BadRow { line: usize, reason: &'static str },
    BadValue { line: usize, field: &'static str, found: String },
    DuplicateStyle { line: usize, family: String, style: String },
}

fn parse_value(line: usize, field: &'static str, text: &str) -> Result<f64, OverrideError> {
    // Declared integral font units only (the post-step domain is integral
    // DeclaredOutputUnits); no fractions, no signs, no exponents.
    if text.is_empty() || !text.bytes().all(|b| b.is_ascii_digit()) {
        return Err(OverrideError::BadValue { line, field, found: text.to_string() });
    }
    let v: u32 = text.parse().map_err(|_| OverrideError::BadValue { line, field, found: text.to_string() })?;
    if v as f64 > crate::post_metrics::MAX_OFFSET {
        return Err(OverrideError::BadValue { line, field, found: text.to_string() });
    }
    Ok(v as f64)
}

/// Parse and validate the table text. Every row must be exactly five
/// tab-separated fields; family/style non-empty, lsb/rsb declared integral
/// units in representable range, one row per (family, style).
pub fn parse_table(text: &str) -> Result<BTreeMap<(String, String), StyleOverride>, OverrideError> {
    let mut lines = text.lines();
    let header = lines.next().ok_or(OverrideError::EmptyTable)?;
    if header != HEADER {
        return Err(OverrideError::BadHeader { found: header.to_string() });
    }
    let mut table: BTreeMap<(String, String), StyleOverride> = BTreeMap::new();
    for (i, raw) in lines.enumerate() {
        let line = i + 2;
        let t = raw.trim();
        if t.is_empty() || t.starts_with('#') { continue; }
        let f: Vec<&str> = raw.split('\t').collect();
        if f.len() != 5 {
            return Err(OverrideError::BadRow { line, reason: "expected 5 tab-separated fields (family, style, lsb, rsb, note)" });
        }
        let (family, style) = (f[0].trim(), f[1].trim());
        if family.is_empty() || style.is_empty() {
            return Err(OverrideError::BadRow { line, reason: "family and style must be non-empty" });
        }
        let row = StyleOverride {
            lsb_add: parse_value(line, "lsb", f[2].trim())?,
            rsb_add: parse_value(line, "rsb", f[3].trim())?,
            note: f[4].trim().to_string(),
        };
        if table.insert((family.to_string(), style.to_string()), row).is_some() {
            return Err(OverrideError::DuplicateStyle { line, family: family.to_string(), style: style.to_string() });
        }
    }
    Ok(table)
}

/// Load the pinned table: the file's sha256 must equal the manifest pin, so
/// the values the engine SETS are exactly the pinned declared data.
pub fn load_pinned(path: &Path, expected_sha256: &str) -> Result<BTreeMap<(String, String), StyleOverride>, OverrideError> {
    let bytes = std::fs::read(path).map_err(|e| OverrideError::Io { path: path.display().to_string(), reason: e.to_string() })?;
    let actual = sha256_hex(&bytes);
    if actual != expected_sha256 {
        return Err(OverrideError::ShaMismatch { path: path.display().to_string(), expected: expected_sha256.to_string(), actual });
    }
    let text = String::from_utf8(bytes).map_err(|e| OverrideError::Io { path: path.display().to_string(), reason: format!("utf8: {e}") })?;
    parse_table(&text)
}

/// Row lookup by manifest family/subfamily.
pub fn lookup<'a>(table: &'a BTreeMap<(String, String), StyleOverride>, family: &str, subfamily: &str) -> Option<&'a StyleOverride> {
    table.get(&(family.to_string(), subfamily.to_string()))
        .filter(|r| r.note.starts_with(DECLARED_NOTE_PREFIX))
}

/// The declared post-step scope under a style override: EVERY glyph class
/// carries the declared bearings (owner: "tüm karakterler için"; convention
/// doc: "every glyph ships with fixed lsb/rsb"). kerning_letters stays false:
/// no kern ran, there is nothing to select.
pub const DECLARED_POST_SCOPE: kni_core::offset_scope::ScopePolicy = kni_core::offset_scope::ScopePolicy {
    base: true, space: true, notdef: true, mark: true, kerning_letters: false,
};

/// The manifest post_scope_label a declared override sets (one token, matches
/// the kit's [A-Za-z0-9._+-] label rule).
pub const DECLARED_POST_SCOPE_LABEL: &str = "style-override-declared";

fn fmt_units(v: f64) -> String {
    if v.fract() == 0.0 && v.is_finite() { format!("{}", v as i64) } else { format!("{v:?}") }
}

/// Typed receipt row (chief-required name): the declared convention SET the
/// post-step values and IGNORED the flag/manifest values. Emitted whenever a
/// style override matched, with the values it replaced.
pub fn overrides_flags_row(manifest_lsb_add: f64, manifest_rsb_add: f64, row: &StyleOverride) -> String {
    format!(
        "declared_convention_overrides_flags\tflag_lsb_add\t{}\tflag_rsb_add\t{}\tset_lsb\t{}\tset_rsb\t{}\tnote\t{}\n",
        fmt_units(manifest_lsb_add), fmt_units(manifest_rsb_add),
        fmt_units(row.lsb_add), fmt_units(row.rsb_add),
        crate::post_metrics::tsv_escape(&row.note),
    )
}

/// Typed receipt rows: the style's kerning/ and sidebearing/ input
/// directories are ignored under the declared convention (no pair solving,
/// no per-character sidebearing solving consumed them).
pub fn ignored_input_rows() -> String {
    let mut s = String::new();
    s.push_str("style_override_inputs\tkerning_dir\tignored\treason\tdeclared_convention\n");
    s.push_str("style_override_inputs\tsidebearing_dir\tignored\treason\tdeclared_convention\n");
    s
}

/// Typed spacing receipt row for an override style: the per-character
/// sidebearing solve did NOT run; the natural zero-bearing population ships
/// and the declared post-step SET yields the row's lsb/rsb.
pub fn spacing_not_run_row() -> String {
    "spacing\tnot_run\treason\tdeclared_convention\tdetail\tper-character sidebearing solving disabled for this style; natural zero-bearing population ships; declared post-step SET applies\n".to_string()
}

/// Typed kern receipt rows for an override style (always-output: marked
/// not_run, never dropped): no pair solving ran, no kern is generated, the
/// drop ledger closes at zero.
pub fn kern_not_run_rows() -> String {
    let mut s = String::new();
    s.push_str("kern\tnot_run\treason\tdeclared_convention\tdetail\tkerning not generated for this style (owner-declared monospace convention); no pair solving ran\n");
    s.push_str("kern_drop_total\tnot_run\treason\tdeclared_convention\toverlap_hold\t0\tclamp_refused\t0\trejected_unbound\t0\tdropped_zero\t0\tclosed\ttrue\n");
    s
}

#[cfg(test)]
mod tests {
    #[test]
    fn real_kit_table_with_comments_parses() {
        let tsv = "family\tstyle\tlsb\trsb\tnote\n# style-scoped sidebearing overrides (v11.4.1)\n# note prefix \"engine declared convention\" = the engine applies the values itself\nMarq\tAlternate\t25\t25\tkit preset (post-lsb-rsb-pass static add, owner 2026-10-14/16)\nMona Alt\tRegular\t40\t45\tengine declared convention, display only (owner directive 2026-10-17)\n";
        let table = parse_table(tsv).unwrap();
        assert_eq!(table.len(), 2);
        assert!(lookup(&table, "Marq", "Alternate").is_none());
        assert!(lookup(&table, "Mona Alt", "Regular").is_some());
    }

    #[test]
    fn marq_preset_row_is_inert() {
        let tsv = "family\tstyle\tlsb\trsb\tnote\nMarq\tAlternate\t25\t25\tkit preset\nMona Alt\tRegular\t40\t45\tengine declared convention: monospace uniform sidebearings\n";
        let table = parse_table(tsv).unwrap();
        assert_eq!(table.len(), 2);
        assert!(lookup(&table, "Marq", "Alternate").is_none(), "kit preset rows must stay inert for the engine");
        let r = lookup(&table, "Mona Alt", "Regular").unwrap();
        assert_eq!((r.lsb_add, r.rsb_add), (40.0, 45.0));
    }

    use super::*;

    const GOOD: &str = "family\tstyle\tlsb\trsb\tnote\nMona Alt\tRegular\t40\t45\tengine declared convention: monospace uniform sidebearings\n";

    #[test]
    fn parses_frozen_format() {
        let t = parse_table(GOOD).unwrap();
        let r = lookup(&t, "Mona Alt", "Regular").unwrap();
        assert_eq!((r.lsb_add, r.rsb_add), (40.0, 45.0));
        assert!(r.note.starts_with(DECLARED_NOTE_PREFIX));
        // Style scoping: "Mona" is NOT "Mona Alt" ("mona ile karistirmayin").
        assert!(lookup(&t, "Mona", "Regular").is_none());
        assert!(lookup(&t, "Mona Alt", "Bold").is_none());
        assert!(lookup(&t, "Marq", "Alternate").is_none());
    }

    #[test]
    fn header_is_mandatory() {
        assert!(matches!(parse_table(""), Err(OverrideError::EmptyTable)));
        assert!(matches!(parse_table("family\tstyle\tlsb\trsb\n"), Err(OverrideError::BadHeader { .. })));
        assert!(matches!(parse_table("Mona Alt\tRegular\t40\t45\tx\n"), Err(OverrideError::BadHeader { .. })));
    }

    #[test]
    fn bad_rows_are_typed_refusals() {
        assert!(matches!(parse_table("family\tstyle\tlsb\trsb\tnote\nMona Alt\tRegular\t40\n"), Err(OverrideError::BadRow { line: 2, .. })));
        assert!(matches!(parse_table("family\tstyle\tlsb\trsb\tnote\n\tRegular\t40\t45\tx\n"), Err(OverrideError::BadRow { line: 2, .. })));
        assert!(matches!(parse_table("family\tstyle\tlsb\trsb\tnote\nMona Alt\tRegular\t-1\t45\tx\n"), Err(OverrideError::BadValue { field: "lsb", .. })));
        assert!(matches!(parse_table("family\tstyle\tlsb\trsb\tnote\nMona Alt\tRegular\t40.5\t45\tx\n"), Err(OverrideError::BadValue { field: "lsb", .. })));
        assert!(matches!(parse_table("family\tstyle\tlsb\trsb\tnote\nMona Alt\tRegular\t40000\t45\tx\n"), Err(OverrideError::BadValue { field: "lsb", .. })));
        assert!(matches!(parse_table("family\tstyle\tlsb\trsb\tnote\nMona Alt\tRegular\t40\t45\tx\nMona Alt\tRegular\t1\t2\ty\n"), Err(OverrideError::DuplicateStyle { line: 3, .. })));
    }

    #[test]
    fn pinned_load_refuses_drift() {
        let dir = std::env::temp_dir().join(format!("kni-so-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("style-overrides.tsv");
        std::fs::write(&p, GOOD).unwrap();
        let sha = sha256_hex(GOOD.as_bytes());
        let t = load_pinned(&p, &sha).unwrap();
        assert!(lookup(&t, "Mona Alt", "Regular").is_some());
        assert!(matches!(load_pinned(&p, "0".repeat(64).as_str()), Err(OverrideError::ShaMismatch { .. })));
        assert!(matches!(load_pinned(&p.join("missing"), &sha), Err(OverrideError::Io { .. })));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn receipt_rows_are_typed() {
        let r = StyleOverride { lsb_add: 40.0, rsb_add: 45.0, note: "n".into() };
        let row = overrides_flags_row(25.0, 25.0, &r);
        assert!(row.starts_with("declared_convention_overrides_flags\t"));
        assert!(row.contains("flag_lsb_add\t25") && row.contains("set_lsb\t40") && row.contains("set_rsb\t45"));
        assert!(spacing_not_run_row().starts_with("spacing\tnot_run\treason\tdeclared_convention\t"));
        let k = kern_not_run_rows();
        assert!(k.contains("kern\tnot_run\treason\tdeclared_convention\t"));
        assert!(k.contains("kern_drop_total\tnot_run\treason\tdeclared_convention\t") && k.contains("closed\ttrue"));
        let i = ignored_input_rows();
        assert!(i.contains("kerning_dir\tignored") && i.contains("sidebearing_dir\tignored"));
        // Declared scope covers every glyph class; kerning_letters stays out.
        assert!(DECLARED_POST_SCOPE.base && DECLARED_POST_SCOPE.space && DECLARED_POST_SCOPE.notdef && DECLARED_POST_SCOPE.mark && !DECLARED_POST_SCOPE.kerning_letters);
    }
}
