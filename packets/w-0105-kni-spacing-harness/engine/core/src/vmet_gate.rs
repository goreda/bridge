//! vmet_gate: OS/2 + hhea vertical-metric consistency gate (VMET-GATE).
//!
//! General machinery only: the module carries no style name and no metric
//! number. The style's declared vertical record (ascender, descender, line
//! gap) arrives as caller input from the style record (the engine's
//! declared/measured per-style data); Paul New's declared record is the
//! caller's (900/-100) style-spec input exactly like any other style's own
//! measured record - nothing here knows it.
//!
//! What the gate checks, per style, against the actual table values the
//! export is about to ship:
//!
//! 1. Clipping prevention (usWinAscent/usWinDescent): Windows clips glyph
//!    ink outside [ -win_descent, win_ascent ]. The check mirrors the
//!    engine's existing os2_consistency semantic exactly:
//!      win_ascent  >= max(0, ink_y_max)
//!      win_descent >= max(0, -ink_y_min)
//!    with ink_y the true-ink y extents over all glyphs (head.bounds y
//!    range, the engine's single outward-rounded ink convention).
//! 2. Typo metrics vs the style record: sTypoAscender/sTypoDescender/
//!    sTypoLineGap must equal the declared record; a style's line layout is
//!    its declared data, not a value re-derived per run.
//! 3. hhea/typo agreement (the engine's one-line-layout convention, as
//!    shipped by the export tail: typo == [hhea.ascender, hhea.descender,
//!    hhea.line_gap]): consumers that read hhea and consumers that read
//!    typo must never see two different line layouts for the same font.
//! 4. Sign and span sanity under the engine's coordinate convention
//!    (baseline 0, ink below it negative): ascender >= 0, descender <= 0,
//!    and ascender - descender > 0 (a non-positive span cannot hold ink).
//!
//! Every check is a typed failure carrying both the declared and the actual
//! value; the gate never edits a metric and never picks a "close enough"
//! tolerance - equality is integer equality, coverage is the ink's own
//! extent. Additive module: no production path calls it, so every existing
//! style and pair remains bit-identical while it is unwired. The per-style
//! report (`render_report`) is deterministic and labels each row with its
//! style id.

use crate::sfnt_metadata::{HheaMetadata, Os2Metadata};

/// The style's declared vertical record, supplied by the caller from the
/// style record (declared spec or the style's own measurements).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct StyleVerticalRecord {
    pub style_id: String,
    pub ascender: i16,
    pub descender: i16,
    pub line_gap: i16,
}

/// One typed gate failure, declared-vs-actual values included.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum VmetFailure {
    /// usWinAscent does not cover the ink: glyphs clip at the top on Windows.
    WinAscentClipsInk { win_ascent: u16, ink_y_max: i16 },
    /// usWinDescent does not cover the ink: glyphs clip at the bottom.
    WinDescentClipsInk { win_descent: u16, ink_y_min: i16 },
    TypoAscenderMismatch { declared: i16, actual: i16 },
    TypoDescenderMismatch { declared: i16, actual: i16 },
    TypoLineGapMismatch { declared: i16, actual: i16 },
    HheaTypoAscenderDiverge { hhea: i16, typo: i16 },
    HheaTypoDescenderDiverge { hhea: i16, typo: i16 },
    HheaTypoLineGapDiverge { hhea: i16, typo: i16 },
    /// ascender < 0 contradicts baseline-0 engine coordinates.
    AscenderNegative { ascender: i16 },
    /// descender > 0 contradicts baseline-0 engine coordinates.
    DescenderPositive { descender: i16 },
    /// ascender - descender <= 0: no room for ink.
    NonPositiveSpan { ascender: i16, descender: i16 },
}

impl VmetFailure {
    /// Stable machine-readable code for reports and ledgers.
    pub fn code(&self) -> &'static str {
        match self {
            Self::WinAscentClipsInk { .. } => "WIN-ASCENT-CLIPS-INK",
            Self::WinDescentClipsInk { .. } => "WIN-DESCENT-CLIPS-INK",
            Self::TypoAscenderMismatch { .. } => "TYPO-ASCENDER-MISMATCH",
            Self::TypoDescenderMismatch { .. } => "TYPO-DESCENDER-MISMATCH",
            Self::TypoLineGapMismatch { .. } => "TYPO-LINEGAP-MISMATCH",
            Self::HheaTypoAscenderDiverge { .. } => "HHEA-TYPO-ASCENDER-DIVERGE",
            Self::HheaTypoDescenderDiverge { .. } => "HHEA-TYPO-DESCENDER-DIVERGE",
            Self::HheaTypoLineGapDiverge { .. } => "HHEA-TYPO-LINEGAP-DIVERGE",
            Self::AscenderNegative { .. } => "ASCENDER-NEGATIVE",
            Self::DescenderPositive { .. } => "DESCENDER-POSITIVE",
            Self::NonPositiveSpan { .. } => "NON-POSITIVE-SPAN",
        }
    }
}

/// Gate outcome for one style: every detected failure, in check order.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GateOutcome {
    pub style_id: String,
    pub ink_y: [i16; 2],
    pub win: [u16; 2],
    pub typo: [i16; 3],
    pub hhea: [i16; 3],
    pub failures: Vec<VmetFailure>,
}

impl GateOutcome {
    pub fn passed(&self) -> bool { self.failures.is_empty() }
}

/// Run the gate for one style. `ink_y` is [ink_y_min, ink_y_max], the
/// true-ink y extents over all glyphs (head.bounds[1], head.bounds[3]).
pub fn gate(record: &StyleVerticalRecord, hhea: &HheaMetadata, os2: &Os2Metadata, ink_y: [i16; 2]) -> GateOutcome {
    let mut failures = Vec::new();

    // 1. Clipping prevention, os2_consistency semantic: the required window
    // is the ink's own extent clipped at the baseline, nothing more.
    let need_ascent = (ink_y[1] as i32).max(0);
    let need_descent = (-(ink_y[0] as i32)).max(0);
    if (os2.win_ascent as i32) < need_ascent {
        failures.push(VmetFailure::WinAscentClipsInk { win_ascent: os2.win_ascent, ink_y_max: ink_y[1] });
    }
    if (os2.win_descent as i32) < need_descent {
        failures.push(VmetFailure::WinDescentClipsInk { win_descent: os2.win_descent, ink_y_min: ink_y[0] });
    }

    // 2. Typo metrics vs the declared style record.
    if os2.typo[0] != record.ascender {
        failures.push(VmetFailure::TypoAscenderMismatch { declared: record.ascender, actual: os2.typo[0] });
    }
    if os2.typo[1] != record.descender {
        failures.push(VmetFailure::TypoDescenderMismatch { declared: record.descender, actual: os2.typo[1] });
    }
    if os2.typo[2] != record.line_gap {
        failures.push(VmetFailure::TypoLineGapMismatch { declared: record.line_gap, actual: os2.typo[2] });
    }

    // 3. hhea/typo agreement (engine's one-line-layout convention).
    if hhea.ascender != os2.typo[0] {
        failures.push(VmetFailure::HheaTypoAscenderDiverge { hhea: hhea.ascender, typo: os2.typo[0] });
    }
    if hhea.descender != os2.typo[1] {
        failures.push(VmetFailure::HheaTypoDescenderDiverge { hhea: hhea.descender, typo: os2.typo[1] });
    }
    if hhea.line_gap != os2.typo[2] {
        failures.push(VmetFailure::HheaTypoLineGapDiverge { hhea: hhea.line_gap, typo: os2.typo[2] });
    }

    // 4. Sign and span sanity (baseline-0 coordinate convention).
    if record.ascender < 0 {
        failures.push(VmetFailure::AscenderNegative { ascender: record.ascender });
    }
    if record.descender > 0 {
        failures.push(VmetFailure::DescenderPositive { descender: record.descender });
    }
    if record.ascender as i32 - record.descender as i32 <= 0 {
        failures.push(VmetFailure::NonPositiveSpan { ascender: record.ascender, descender: record.descender });
    }

    GateOutcome {
        style_id: record.style_id.clone(),
        ink_y,
        win: [os2.win_ascent, os2.win_descent],
        typo: os2.typo,
        hhea: [hhea.ascender, hhea.descender, hhea.line_gap],
        failures,
    }
}

/// Per-style report (format `vmet_gate_report_v1`). One row per style in
/// the order given; failing rows list their typed failure codes; totals are
/// sums over the rendered rows only. TSV cells are sanitized against stray
/// tabs/newlines in style ids.
pub fn render_report(outcomes: &[GateOutcome]) -> String {
    let mut s = String::from("vmet_gate_report_v1\n");
    s.push_str(&format!("styles\t{}\n", outcomes.len()));
    let mut pass = 0usize;
    let mut fail = 0usize;
    for o in outcomes {
        let id = o.style_id.replace(['\t', '\n', '\r'], " ");
        if o.passed() {
            pass += 1;
            s.push_str(&format!(
                "style\t{}\tpass\tink={},{}\twin={},{}\ttypo={},{},{}\thhea={},{},{}\n",
                id, o.ink_y[0], o.ink_y[1], o.win[0], o.win[1],
                o.typo[0], o.typo[1], o.typo[2], o.hhea[0], o.hhea[1], o.hhea[2],
            ));
        } else {
            fail += 1;
            let codes: Vec<&str> = o.failures.iter().map(|f| f.code()).collect();
            s.push_str(&format!(
                "style\t{}\tfail\tink={},{}\twin={},{}\ttypo={},{},{}\thhea={},{},{}\tfailures={}\n",
                id, o.ink_y[0], o.ink_y[1], o.win[0], o.win[1],
                o.typo[0], o.typo[1], o.typo[2], o.hhea[0], o.hhea[1], o.hhea[2],
                codes.join(","),
            ));
        }
    }
    s.push_str(&format!("pass\t{pass}\n"));
    s.push_str(&format!("fail\t{fail}\n"));
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hhea(a: i16, d: i16, g: i16) -> HheaMetadata {
        HheaMetadata { ascender: a, descender: d, line_gap: g, advance_max: 0, min_lsb: 0, min_rsb: 0, max_extent: 0, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: 0 }
    }
    fn os2(typo: [i16; 3], wa: u16, wd: u16) -> Os2Metadata {
        Os2Metadata { average_width: 0, weight: 400, width: 5, embedding: 0, subscript: [0; 4], superscript: [0; 4], strikeout: [0; 2], family_class: 0,
            panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"TEST", selection: 64, first_char: 0, last_char: 0, typo, win_ascent: wa, win_descent: wd, version: 0, cap_height: 0, x_height: 0 }
    }
    fn rec(id: &str, a: i16, d: i16, g: i16) -> StyleVerticalRecord {
        StyleVerticalRecord { style_id: id.to_string(), ascender: a, descender: d, line_gap: g }
    }

    #[test]
    fn consistent_style_passes() {
        // Record 800/-200/0, ink inside [-200, 800], all tables in agreement.
        let o = gate(&rec("Test/Regular", 800, -200, 0), &hhea(800, -200, 0), &os2([800, -200, 0], 800, 200), [-200, 800]);
        assert!(o.passed(), "{:?}", o.failures);
    }

    #[test]
    fn ink_outside_record_still_passes_when_win_covers_it() {
        // The gate checks clipping against the ink, not against the record:
        // ink reaching 850 with win_ascent 850 is clipping-safe even though
        // the declared ascender is 800 (that divergence is the typo check's
        // business only when the typo values leave the record).
        let o = gate(&rec("Test/Regular", 800, -200, 0), &hhea(800, -200, 0), &os2([800, -200, 0], 850, 200), [-200, 850]);
        assert!(o.passed(), "{:?}", o.failures);
    }

    #[test]
    fn win_ascent_below_ink_clips() {
        let o = gate(&rec("Test/Regular", 800, -200, 0), &hhea(800, -200, 0), &os2([800, -200, 0], 799, 200), [-200, 800]);
        assert_eq!(o.failures, vec![VmetFailure::WinAscentClipsInk { win_ascent: 799, ink_y_max: 800 }]);
    }

    #[test]
    fn win_descent_below_ink_clips() {
        let o = gate(&rec("Test/Regular", 800, -200, 0), &hhea(800, -200, 0), &os2([800, -200, 0], 800, 100), [-200, 800]);
        assert_eq!(o.failures, vec![VmetFailure::WinDescentClipsInk { win_descent: 100, ink_y_min: -200 }]);
    }

    #[test]
    fn ink_one_side_of_baseline_needs_no_window_on_the_other() {
        // All ink above baseline: required descent is 0; all below: required
        // ascent is 0 (os2_consistency's max(0, ...) semantic).
        let above = gate(&rec("T", 800, -200, 0), &hhea(800, -200, 0), &os2([800, -200, 0], 500, 0), [50, 500]);
        assert!(above.passed(), "{:?}", above.failures);
        let below = gate(&rec("T", 800, -200, 0), &hhea(800, -200, 0), &os2([800, -200, 0], 0, 300), [-300, -10]);
        assert!(below.passed(), "{:?}", below.failures);
    }

    #[test]
    fn typo_mismatches_are_typed_per_field() {
        let o = gate(&rec("T", 800, -200, 20), &hhea(810, -190, 0), &os2([810, -190, 0], 850, 250), [-200, 800]);
        assert_eq!(o.failures, vec![
            VmetFailure::TypoAscenderMismatch { declared: 800, actual: 810 },
            VmetFailure::TypoDescenderMismatch { declared: -200, actual: -190 },
            VmetFailure::TypoLineGapMismatch { declared: 20, actual: 0 },
        ]);
    }

    #[test]
    fn hhea_typo_divergence_is_typed_per_field() {
        let o = gate(&rec("T", 800, -200, 0), &hhea(900, -100, 5), &os2([800, -200, 0], 900, 200), [-200, 800]);
        assert_eq!(o.failures, vec![
            VmetFailure::HheaTypoAscenderDiverge { hhea: 900, typo: 800 },
            VmetFailure::HheaTypoDescenderDiverge { hhea: -100, typo: -200 },
            VmetFailure::HheaTypoLineGapDiverge { hhea: 5, typo: 0 },
        ]);
    }

    #[test]
    fn shipped_paul_new_values_fail_against_the_declared_record() {
        // Caller-side style record (the declared style spec: ascender 900,
        // descender -100) against the values the shipped OTF actually
        // carried (770/-230 everywhere) with ink to y=900: the gate catches
        // the typo mismatch on both fields and the top clipping.
        let o = gate(&rec("Paul New/Regular", 900, -100, 0), &hhea(770, -230, 0), &os2([770, -230, 0], 770, 230), [-230, 900]);
        assert_eq!(o.failures, vec![
            VmetFailure::WinAscentClipsInk { win_ascent: 770, ink_y_max: 900 },
            VmetFailure::TypoAscenderMismatch { declared: 900, actual: 770 },
            VmetFailure::TypoDescenderMismatch { declared: -100, actual: -230 },
        ]);
        // The declared record itself, consistently shipped, passes.
        let ok = gate(&rec("Paul New/Regular", 900, -100, 0), &hhea(900, -100, 0), &os2([900, -100, 0], 900, 100), [-100, 900]);
        assert!(ok.passed(), "{:?}", ok.failures);
    }

    #[test]
    fn sign_and_span_sanity() {
        let neg = gate(&rec("T", -5, -200, 0), &hhea(-5, -200, 0), &os2([-5, -200, 0], 800, 200), [-200, 800]);
        assert!(neg.failures.contains(&VmetFailure::AscenderNegative { ascender: -5 }));
        let pos = gate(&rec("T", 800, 10, 0), &hhea(800, 10, 0), &os2([800, 10, 0], 800, 200), [-200, 800]);
        assert!(pos.failures.contains(&VmetFailure::DescenderPositive { descender: 10 }));
        let flat = gate(&rec("T", 100, 100, 0), &hhea(100, 100, 0), &os2([100, 100, 0], 800, 200), [-200, 800]);
        assert!(flat.failures.contains(&VmetFailure::NonPositiveSpan { ascender: 100, descender: 100 }));
    }

    #[test]
    fn failure_codes_are_stable_and_unique() {
        let all = [
            VmetFailure::WinAscentClipsInk { win_ascent: 0, ink_y_max: 1 },
            VmetFailure::WinDescentClipsInk { win_descent: 0, ink_y_min: -1 },
            VmetFailure::TypoAscenderMismatch { declared: 0, actual: 1 },
            VmetFailure::TypoDescenderMismatch { declared: 0, actual: 1 },
            VmetFailure::TypoLineGapMismatch { declared: 0, actual: 1 },
            VmetFailure::HheaTypoAscenderDiverge { hhea: 0, typo: 1 },
            VmetFailure::HheaTypoDescenderDiverge { hhea: 0, typo: 1 },
            VmetFailure::HheaTypoLineGapDiverge { hhea: 0, typo: 1 },
            VmetFailure::AscenderNegative { ascender: -1 },
            VmetFailure::DescenderPositive { descender: 1 },
            VmetFailure::NonPositiveSpan { ascender: 0, descender: 0 },
        ];
        let codes: Vec<&str> = all.iter().map(|f| f.code()).collect();
        let mut dedup = codes.clone();
        dedup.sort();
        dedup.dedup();
        assert_eq!(codes.len(), dedup.len());
        for c in &codes {
            assert!(c.bytes().all(|b| b.is_ascii_uppercase() || b == b'-'), "{c}");
        }
    }

    #[test]
    fn report_is_golden_and_per_style() {
        let ok = gate(&rec("Marq/Alternate", 800, -200, 0), &hhea(800, -200, 0), &os2([800, -200, 0], 800, 200), [-200, 800]);
        let bad = gate(&rec("Paul New/Regular", 900, -100, 0), &hhea(770, -230, 0), &os2([770, -230, 0], 770, 230), [-230, 900]);
        let got = render_report(&[ok, bad]);
        let want = "vmet_gate_report_v1\n\
            styles\t2\n\
            style\tMarq/Alternate\tpass\tink=-200,800\twin=800,200\ttypo=800,-200,0\thhea=800,-200,0\n\
            style\tPaul New/Regular\tfail\tink=-230,900\twin=770,230\ttypo=770,-230,0\thhea=770,-230,0\tfailures=WIN-ASCENT-CLIPS-INK,TYPO-ASCENDER-MISMATCH,TYPO-DESCENDER-MISMATCH\n\
            pass\t1\n\
            fail\t1\n";
        assert_eq!(got, want);
        assert!(render_report(&[]).contains("styles\t0\n"));
    }

    #[test]
    fn gate_is_deterministic() {
        let a = gate(&rec("T", 800, -200, 0), &hhea(800, -200, 0), &os2([800, -200, 0], 799, 200), [-200, 800]);
        let b = gate(&rec("T", 800, -200, 0), &hhea(800, -200, 0), &os2([800, -200, 0], 799, 200), [-200, 800]);
        assert_eq!(a, b);
    }
}
