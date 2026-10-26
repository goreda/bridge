//! Read-only class audit observer for the self-anchored spacing classifier.
//!
//! The spacing solver (`self_anchored_spacing`) classifies every glyph side
//! into a `SideClass` and resolves each facing class pair's target through a
//! fixed cascade: measured source class-pair median (FontContext) -> K2
//! per-class channel table (policy `class_channel_targets`) -> Lane B cadence
//! table (policy `cadence_class_pass`) -> the frozen anchor W_target
//! fallback. This module carries an exact copy of that already-computed
//! state out of the solve for inspection. It adds no computation beyond
//! copying values the solver already derived, and the per-class-pair target
//! rows resolve through the solver's own single lookup path
//! (`resolve_class_target`), so the report cannot drift from the solver.
//! Nothing here feeds back: solver decisions, emitted spacing, and OTF bytes
//! are untouched (byte-inert by construction; guarded by the golden solver
//! tests plus `class_audit_capture_is_byte_inert_against_golden_values`).
//!
//! Data provenance (how the factory feeds the classifier):
//! - Glyph outlines arrive as `OutlineProfile` scan rows; the solver builds
//!   per-glyph band walls (`build_walls`), derives the scale `s` and the
//!   band from baseline/x_height/cap_height, and classifies each side with
//!   `classify_side` over the clamped side series. Geometry only.
//! - Measured source spacing arrives ONLY through `FontContext`
//!   (`measured_pairs` / `measured_sidebearings` / `measured_space_advance`),
//!   supplied by the caller. The reference pipeline driver
//!   (pipeline/src/main.rs, `solve_spacing_excluding_culprits`) passes a
//!   FontContext carrying `glyph_codepoints` only - no measured pairs or
//!   sidebearings - so in that wiring no class pair has a measured target
//!   and `measured_pair_count` here reports 0.
//! - The TSV provenance header records exactly which of these inputs were
//!   present for the solve the snapshot was captured from.

use crate::self_anchored_spacing::SideClass;

/// Which cascade level produced a class pair's target. Resolution order is
/// the cascade order: a measured source target always wins; the anchor
/// fallback is last.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClassTargetSource {
    /// Measured source spacing: the median of the FontContext measured
    /// pairs grouped by this facing class pair.
    MeasuredSource,
    /// K2: derived per-class channel target (policy `class_channel_targets`).
    ChannelK2,
    /// Lane B: derived cadence/area target (policy `cadence_class_pass`).
    CadenceLaneB,
    /// Frozen fallback: the anchor W_target (self-derived equal-area target).
    AnchorWTarget,
}

impl ClassTargetSource {
    /// Stable TSV token for the source.
    pub fn code(&self) -> &'static str {
        match self {
            ClassTargetSource::MeasuredSource => "measured",
            ClassTargetSource::ChannelK2 => "channel_k2",
            ClassTargetSource::CadenceLaneB => "cadence_lane_b",
            ClassTargetSource::AnchorWTarget => "anchor_w_target",
        }
    }
}

/// One glyph's facing classes exactly as the classifier assigned them.
#[derive(Debug, Clone)]
pub struct ClassAuditGlyph {
    pub glyph_id: String,
    /// The classifier's class for the glyph's left side.
    pub left_class: SideClass,
    /// The classifier's class for the glyph's right side.
    pub right_class: SideClass,
    /// h_eff > 0: only inked glyphs feed class membership and target pools.
    pub inked: bool,
}

/// One present side class with its inked-glyph membership: `glyph:L` /
/// `glyph:R` side entries in solver input order (the same population and
/// pooling order the target derivations use), plus the side count.
#[derive(Debug, Clone)]
pub struct ClassMembership {
    pub class: SideClass,
    pub member_count: usize,
    pub members: Vec<String>,
}

/// The resolved target for one ordered facing class pair (left glyph's
/// right class -> right glyph's left class) and the cascade level that
/// produced it. Every ordered pair of present classes appears exactly once.
#[derive(Debug, Clone)]
pub struct ClassPairTargetRow {
    pub left_class: SideClass,
    pub right_class: SideClass,
    pub target: f64,
    pub source: ClassTargetSource,
}

/// A read-only snapshot of the classifier state of one solve.
#[derive(Debug, Clone)]
pub struct ClassAudit {
    /// Anchor mode label of the solve (AnchorMode display string).
    pub anchor_mode: String,
    /// Anchor pair-white target W; the frozen fallback for every class pair
    /// without a measured or derived target.
    pub w_target: f64,
    /// Classifier scale unit s (median stem width; the only length unit in
    /// side classification).
    pub scale_s: f64,
    pub upm: u16,
    pub baseline: f64,
    pub x_height: f64,
    pub cap_height: f64,
    /// The J(d) cap depth actually used; `dcap_from_policy` distinguishes
    /// the policy override from the measured plateau default.
    pub dcap: f64,
    pub dcap_from_policy: bool,
    /// Effective distribution weight (policy None resolves to 0.0).
    pub lambda: f64,
    pub cadence_class_pass: bool,
    pub class_channel_targets: bool,
    /// Counts of the measured inputs the factory (FontContext) carried into
    /// this solve; 0/0 + `has_glyph_codepoints` is the current reference
    /// pipeline wiring (see module header).
    pub measured_pair_count: usize,
    pub measured_sidebearing_count: usize,
    pub has_glyph_codepoints: bool,
    pub has_measured_space_advance: bool,
    /// Every glyph in solver input order with its facing classes.
    pub glyphs: Vec<ClassAuditGlyph>,
    /// Present classes over the inked population, enum order.
    pub classes: Vec<ClassMembership>,
    /// The resolved target for every ordered pair of present classes.
    pub pair_targets: Vec<ClassPairTargetRow>,
}

impl ClassAudit {
    /// The resolved target row for a glyph pair faced exactly as the solver
    /// faces it (left glyph's right class -> right glyph's left class). Use
    /// this for selected pairs (e.g. v-c / y-o / v-o / f-v in a Marq class
    /// audit). None only when a glyph id is absent from the solve.
    pub fn pair_target_for(&self, left_glyph: &str, right_glyph: &str) -> Option<&ClassPairTargetRow> {
        let l = self.glyphs.iter().find(|g| g.glyph_id == left_glyph)?;
        let r = self.glyphs.iter().find(|g| g.glyph_id == right_glyph)?;
        self.pair_targets.iter()
            .find(|p| p.left_class == l.right_class && p.right_class == r.left_class)
    }

    /// Deterministic TSV rendering: a provenance header line, then the
    /// [glyphs], [classes] and [class_pair_targets] sections. Same solve
    /// in, same bytes out.
    pub fn to_tsv(&self) -> String {
        fn onoff(b: bool) -> &'static str { if b { "on" } else { "off" } }
        fn yesno(b: bool) -> &'static str { if b { "yes" } else { "no" } }
        let mut out = String::new();
        out.push_str("# kni-class-audit v1 (read-only observer; solver decisions and OTF bytes untouched)\n");
        out.push_str(&format!(
            "# provenance anchor_mode={} w_target={:.6} scale_s={:.6} upm={} baseline={:.6} x_height={:.6} cap_height={:.6} dcap={:.6} dcap_source={} lambda={:.6} cadence_class_pass={} class_channel_targets={} measured_pairs={} measured_sidebearings={} glyph_codepoints={} measured_space_advance={}\n",
            self.anchor_mode, self.w_target, self.scale_s, self.upm,
            self.baseline, self.x_height, self.cap_height, self.dcap,
            if self.dcap_from_policy { "policy" } else { "measured_plateau_default" },
            self.lambda,
            onoff(self.cadence_class_pass), onoff(self.class_channel_targets),
            self.measured_pair_count, self.measured_sidebearing_count,
            yesno(self.has_glyph_codepoints), yesno(self.has_measured_space_advance)));
        out.push_str("[glyphs]\nglyph_id\tleft_class\tright_class\tinked\n");
        for g in &self.glyphs {
            out.push_str(&format!("{}\t{}\t{}\t{}\n",
                g.glyph_id, g.left_class, g.right_class, g.inked));
        }
        out.push_str("[classes]\nclass\tmember_count\tmembers\n");
        for c in &self.classes {
            out.push_str(&format!("{}\t{}\t{}\n",
                c.class, c.member_count, c.members.join(",")));
        }
        out.push_str("[class_pair_targets]\nleft_class\tright_class\ttarget\tsource\n");
        for p in &self.pair_targets {
            out.push_str(&format!("{}\t{}\t{:.6}\t{}\n",
                p.left_class, p.right_class, p.target, p.source.code()));
        }
        out
    }
}
