//! Opt-in ambiguity decision over adapter-qualified u32 binding identities.
//! No geometry, score margin, threshold or environment policy is inferred here.
//! OFF returns Proceed immediately. Duplicate IDs are not independent choices.
//! CONTEXT CONTRACT: subject and stage are supplied by the integrator; an empty
//! subject is allowed ONLY for run-level evidence; glyph-level adapters must
//! supply the actual glyph. It is never synthesized from style.
//! APPROVED missing policy: missing evidence takes
//! precedence over ambiguity; empty candidates add BoundCandidate if absent.
//! Each distinct missing kind is retained; one row per kind is approved.
//! APPROVED scalar ledger_code rule: it names the first kind in
//! adapter order; ledger_rows emits one row PER missing kind with its own code.
//! All missing precedence, default, per-kind rows and scalar-code rules approved.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stage { Capture, Solve, Manifest }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvidenceKind { SpaceAdvance, NotdefBound, BoundCandidate }
impl EvidenceKind {
    pub fn ledger_code(self) -> &'static str {
        match self { Self::SpaceAdvance => "MissingSpaceEvidence", Self::NotdefBound => "NoNotdefCandidate", Self::BoundCandidate => "MISSING-BOUND-CANDIDATE" }
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AmbiguityContext {
    pub qualified_candidate_ids: Vec<u32>,
    pub missing_evidence: Vec<EvidenceKind>,
    pub style_id: String,
    pub guard_enabled: bool,
    pub subject_glyph: String,
    pub stage: Stage,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExclusionReason { AmbiguousCandidates }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TypedExclusion {
    pub subject_glyph: String,
    pub candidate_ids: Vec<u32>,
    pub reason: ExclusionReason,
    pub stage: Stage,
    pub ledger_code: &'static str,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TypedMissing {
    pub subject_glyph: String,
    pub missing: Vec<EvidenceKind>,
    pub stage: Stage,
    pub ledger_code: &'static str,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AmbiguityVerdict { Proceed, Degrade(TypedExclusion), Missing(TypedMissing) }

pub fn evaluate(ctx: &AmbiguityContext) -> AmbiguityVerdict {
    if !ctx.guard_enabled { return AmbiguityVerdict::Proceed; }
    let mut ids = Vec::new();
    for &id in &ctx.qualified_candidate_ids { if !ids.contains(&id) { ids.push(id); } }
    let mut missing = Vec::new();
    for &kind in &ctx.missing_evidence { if !missing.contains(&kind) { missing.push(kind); } }
    if ids.is_empty() && !missing.contains(&EvidenceKind::BoundCandidate) { missing.push(EvidenceKind::BoundCandidate); }
    if let Some(&first) = missing.first() {
        return AmbiguityVerdict::Missing(TypedMissing { subject_glyph: ctx.subject_glyph.clone(),
            ledger_code: first.ledger_code(), missing, stage: ctx.stage });
    }
    if ids.len() > 1 {
        return AmbiguityVerdict::Degrade(TypedExclusion { subject_glyph: ctx.subject_glyph.clone(),
            candidate_ids: ids, reason: ExclusionReason::AmbiguousCandidates, stage: ctx.stage,
            ledger_code: "AMBIGUOUS-CANDIDATES-EXCLUDED" });
    }
    AmbiguityVerdict::Proceed
}
fn cell(s: &str) -> String {
    let mut out = String::new();
    for c in s.chars() {
        match c { '\\' => out.push_str("\\\\"), '\t' => out.push_str("\\t"), '\n' => out.push_str("\\n"), '\r' => out.push_str("\\r"), _ => out.push(c) }
    }
    out
}
impl TypedExclusion {
    pub fn ledger_row(&self) -> String {
        format!("{:?}\t{}\t{}\t{:?}\n", self.stage, cell(self.ledger_code), cell(&self.subject_glyph), self.reason)
    }
}
impl TypedMissing {
    /// Approved mixed-kind rule: one row per distinct missing kind, each with
    /// its exact code. Never label missing evidence as ambiguity.
    pub fn ledger_rows(&self) -> String {
        self.missing.iter().map(|kind| format!("{:?}\t{}\t{}\t{:?}\n",
            self.stage, kind.ledger_code(), cell(&self.subject_glyph), kind)).collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};
    use kni_core::generated_native::encode_generated;
    use kni_core::native_font::NativeFontInput;
    use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, Os2Metadata, PostMetadata};
    fn ctx(text: &str) -> AmbiguityContext {
        let ids = text.lines().filter(|l| !l.is_empty() && !l.starts_with('#')).map(|s| s.parse().unwrap()).collect();
        AmbiguityContext { qualified_candidate_ids: ids, missing_evidence: vec![], style_id: "synthetic-style".into(),
            guard_enabled: true, subject_glyph: "synthetic_bound".into(), stage: Stage::Capture }
    }
    fn metadata() -> NativeFontInput {
        // Synthetic font metadata copied in shape from the package floor tests;
        // these are declared fixture values, not production policy thresholds.
        NativeFontInput {
            postscript_name: "GuardFixture-Regular".into(), glyphs: vec![], left_side_bearings: vec![], mapping: vec![],
            head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [0; 4], mac_style: 0, lowest_ppem: 1 },
            hhea: HheaMetadata { ascender: 0, descender: 0, line_gap: 0, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 },
            post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 0, memory: [0; 4] },
            os2: Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0,
                panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"TEST", selection: 64, first_char: 0, last_char: 0, typo: [0; 3], win_ascent: 0, win_descent: 0, version: 0, cap_height: 0, x_height: 0 },
            names: crate::names("GuardFixture", "Regular", "GuardFixture-Regular"),
        }
    }
    fn glyphs() -> Vec<DrawnGlyph> {
        let p = |x, y| Point { x, y };
        vec![DrawnGlyph { glyph_id: ".notdef".into(), rings: vec![] }, DrawnGlyph { glyph_id: "synthetic_bound".into(), rings: vec![ReferenceRing {
            start: p(0.0, 0.0), spans: vec![Span::Line { end: p(100.0, 0.0) }, Span::Line { end: p(100.0, 200.0) },
                Span::Line { end: p(0.0, 200.0) }, Span::Line { end: p(0.0, 0.0) }],
        }] }]
    }
    fn export(gs: &[DrawnGlyph]) -> Vec<u8> {
        let metrics: Vec<_> = gs.iter().map(|g| (g.glyph_id.clone(), 0.0, if g.rings.is_empty() { 500.0 } else { 400.0 }, 500.0)).collect();
        let mapping = if gs.len() > 1 { vec![(0x41, 1)] } else { vec![] };
        encode_generated(gs, &mapping, &metrics, &metadata()).unwrap()
    }
    fn adapted(c: &AmbiguityContext) -> (Vec<u8>, Vec<TypedExclusion>, String) {
        let mut gs = glyphs(); let mut records = Vec::new(); let mut ledger = String::new();
        match evaluate(c) {
            AmbiguityVerdict::Proceed => {},
            AmbiguityVerdict::Degrade(e) => {
                gs.retain(|g| g.glyph_id != e.subject_glyph);
                ledger.push_str(&e.ledger_row()); records.push(e);
            }
            AmbiguityVerdict::Missing(m) => { ledger.push_str(&m.ledger_rows()); }
        }
        (export(&gs), records, ledger)
    }
    #[test]
    fn two_candidate_fixture_excludes_once_and_still_encodes_an_otf() {
        let c = ctx(include_str!("../tests/fixtures/guard_degrade/two-candidate.txt"));
        let snapshot = c.clone(); let (otf, records, ledger) = adapted(&c);
        assert_eq!(c, snapshot); assert_eq!(records.len(), 1); assert_eq!(ledger.lines().count(), 1);
        assert_eq!(records[0].reason, ExclusionReason::AmbiguousCandidates);
        assert_eq!(records[0].candidate_ids, c.qualified_candidate_ids);
        assert_eq!(ledger, "Capture\tAMBIGUOUS-CANDIDATES-EXCLUDED\tsynthetic_bound\tAmbiguousCandidates\n");
        assert_eq!(otf, export(&glyphs()[..1])); assert!(otf.starts_with(b"OTTO"));
    }
    #[test]
    fn clean_single_candidate_is_byte_identical_to_ungated_encoder() {
        let c = ctx(include_str!("../tests/fixtures/guard_degrade/single-candidate.txt"));
        let (bytes, records, ledger) = adapted(&c);
        assert_eq!(evaluate(&c), AmbiguityVerdict::Proceed);
        assert_eq!(bytes, export(&glyphs())); assert!(records.is_empty() && ledger.is_empty());
    }
    #[test]
    fn off_is_byte_identical_even_for_missing_or_ambiguous_context() {
        for mut c in [ctx("1\n2\n"), ctx("")] {
            c.guard_enabled = false; c.subject_glyph.clear(); c.missing_evidence.push(EvidenceKind::SpaceAdvance);
            let snap = c.clone(); let (bytes, records, ledger) = adapted(&c);
            assert_eq!(bytes, export(&glyphs())); assert!(records.is_empty() && ledger.is_empty()); assert_eq!(c, snap);
        }
    }
    #[test]
    fn repeated_id_is_not_second_candidate_and_order_is_not_sorted() {
        assert_eq!(evaluate(&ctx("7\n7\n")), AmbiguityVerdict::Proceed);
        let AmbiguityVerdict::Degrade(e) = evaluate(&ctx("9\n2\n9\n")) else { panic!("expected ambiguity") };
        assert_eq!(e.candidate_ids, vec![9, 2]);
    }
    #[test]
    fn missing_precedes_ambiguity_and_zero_ids_mean_missing() {
        let AmbiguityVerdict::Missing(m) = evaluate(&ctx("")) else { panic!("expected missing") };
        assert_eq!(m.missing, vec![EvidenceKind::BoundCandidate]); assert_eq!(m.ledger_code, "MISSING-BOUND-CANDIDATE");
        let mut c = ctx("1\n2\n"); c.stage = Stage::Solve; c.subject_glyph.clear();
        c.missing_evidence = vec![EvidenceKind::SpaceAdvance, EvidenceKind::NotdefBound, EvidenceKind::SpaceAdvance];
        let AmbiguityVerdict::Missing(m) = evaluate(&c) else { panic!("expected missing precedence") };
        assert_eq!(m.missing, vec![EvidenceKind::SpaceAdvance, EvidenceKind::NotdefBound]);
        assert_eq!(m.ledger_code, "MissingSpaceEvidence");
        assert_eq!(m.ledger_rows(), "Solve\tMissingSpaceEvidence\t\tSpaceAdvance\nSolve\tNoNotdefCandidate\t\tNotdefBound\n");
    }
    #[test]
    fn ledger_cells_escape_and_explicit_subject_stage_are_copied() {
        let mut c = ctx("1\n2\n"); c.subject_glyph = "a\tb\nc\r\\".into(); c.stage = Stage::Manifest;
        let AmbiguityVerdict::Degrade(e) = evaluate(&c) else { panic!("expected ambiguity") };
        assert_eq!(e.subject_glyph, c.subject_glyph); assert_eq!(e.stage, Stage::Manifest);
        let row = e.ledger_row(); assert_eq!(row.lines().count(), 1); assert_eq!(row.trim_end().split('\t').count(), 4);
        assert!(row.contains("a\\tb\\nc\\r\\\\"));
    }
}
