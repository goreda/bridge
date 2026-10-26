//! ENGINE CANONICAL SCALE v4: RESEARCH CANDIDATE (new file: engine/core/src/canonical_scale.rs). UNRUN SOURCE.
//! Pure arithmetic over measured pixel extents; std only; no I/O, no solver, no image access.
//! PRODUCTION ADOPTION IS NOT APPROVED: the vertical-envelope convention below is a NEW normalization proposed for
//! review, so every success status is `CanonicalConventionCandidate`, never "usable".
//!
//! WHAT THIS IS NOT: it does not recover the source font's original em. A tile carries pixels only; its px/em is not
//! fixed by font_size plus bitmap shape (cap height, x-height, stem width all scale with the same unknown factor, so
//! agreeing measurements are one anchor, not two). Unless a renderer normalization reference is supplied, the
//! status is `Identifiability::SourceOriginalEmUnidentifiable`. A renderer that normalizes some glyph height (e.g. the
//! same H px for several styles) makes THAT height a renderer constant, not a scale anchor. The coded envelope uses
//! Ascender-top / Descender-bottom / Baseline-bottom role SETS; whether H is in the Ascender set (then it enters the
//! upper anchor) is a role-policy question NOT decided here. `cross_group_role_report` exposes identical-median suspects.
//! A reference height (e.g. one font's H in units) would be a normalization convention record, not a verified original
//! size; its measurement depends on threshold/frame binding, and an integer bbox is not interchangeable with a fractional median.
//! Nothing here encodes a glyph height, an old K, a target near 1.7 or a cap-height ratio; roles/conventions must not
//! be chosen to land on an expected scale.
//!
//! Coordinates: canvas pixels, y DOWN, continuous pixel EDGES (top = upper ink edge, bottom = lower ink edge).

use std::collections::HashSet;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Role { Baseline, Ascender, Descender, Cap, XHeight }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Extent { Top, Bottom }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stat { Median }
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Anchor { pub role: Role, pub extent: Extent }

/// The published definition of the canonical em: `em_px = lower - upper` (each aggregated by `stat`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Convention { pub baseline: Anchor, pub upper: Anchor, pub lower: Anchor, pub stat: Stat }
impl Convention {
    /// CANDIDATE convention (not a recovered fact): 1 em := ascender-top .. descender-bottom envelope; baseline := flat-bottom bottoms.
    pub fn vertical_envelope() -> Self {
        Convention {
            baseline: Anchor { role: Role::Baseline, extent: Extent::Bottom },
            upper: Anchor { role: Role::Ascender, extent: Extent::Top },
            lower: Anchor { role: Role::Descender, extent: Extent::Bottom },
            stat: Stat::Median,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PixelFrame { pub width: u32, pub height: u32 }

/// Source group identity: one style / one capture frame. Width x height alone is NOT identity (same canvas size can carry a
/// different origin rule or style), so the group id and an explicit frame binding string (e.g. frame_id or a hash of the
/// origin/threshold rule) are required and every observation must carry the same triple.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourceGroup { id: String, frame: PixelFrame, frame_binding: String }
impl SourceGroup {
    pub fn new(id: &str, frame: PixelFrame, frame_binding: &str) -> Result<Self, ScaleError> {
        if id.is_empty() || frame_binding.is_empty() { return Err(ScaleError::InvalidGroup); }
        if frame.width == 0 || frame.height == 0 { return Err(ScaleError::InvalidGroup); }
        Ok(SourceGroup { id: id.to_string(), frame, frame_binding: frame_binding.to_string() })
    }
    pub fn id(&self) -> &str { &self.id }
    pub fn frame(&self) -> PixelFrame { self.frame }
    pub fn frame_binding(&self) -> &str { &self.frame_binding }
}

/// One glyph's measured source extent. Constructed only through `new` (validated); derive/derived_bounds revalidate anyway.
/// `roles` is a SET: Baseline/Cap/Ascender membership overlaps naturally (H is flat-bottom and cap). Empty set = no role.
#[derive(Clone, Debug, PartialEq)]
pub struct GlyphObservation { id: String, group_id: String, frame_binding: String, frame: PixelFrame, source_pin: String, roles: Vec<Role>, top_px: f64, bottom_px: f64 }
impl GlyphObservation {
    pub fn new(group: &SourceGroup, id: &str, source_pin: &str, roles: &[Role], top_px: f64, bottom_px: f64) -> Result<Self, ScaleError> {
        let mut r = roles.to_vec(); r.sort(); r.dedup();
        let o = GlyphObservation { id: id.to_string(), group_id: group.id.clone(), frame_binding: group.frame_binding.clone(), frame: group.frame, source_pin: source_pin.to_string(), roles: r, top_px, bottom_px };
        o.validate(group)?;
        Ok(o)
    }
    pub fn id(&self) -> &str { &self.id }
    pub fn roles(&self) -> &[Role] { &self.roles }
    pub fn source_pin(&self) -> &str { &self.source_pin }
    pub fn top_px(&self) -> f64 { self.top_px }
    pub fn bottom_px(&self) -> f64 { self.bottom_px }
    /// Full revalidation against the group (id/pin present, group triple equal, finite ordered extents inside the frame).
    /// Applies to EVERY observation, role-less ones included.
    fn validate(&self, group: &SourceGroup) -> Result<(), ScaleError> {
        let bad = |why: &'static str| ScaleError::InvalidMeasurement { glyph: self.id.clone(), why };
        if self.id.is_empty() { return Err(ScaleError::EmptyGlyphId); }
        if self.source_pin.is_empty() { return Err(ScaleError::EmptySourcePin { glyph: self.id.clone() }); }
        if self.group_id != group.id || self.frame_binding != group.frame_binding || self.frame != group.frame {
            return Err(ScaleError::GroupMismatch { glyph: self.id.clone() });
        }
        if !(self.top_px.is_finite() && self.bottom_px.is_finite()) { return Err(bad("non-finite extent")); }
        if !(self.top_px < self.bottom_px) { return Err(bad("top must be above bottom (y down)")); }
        if self.top_px < 0.0 || self.bottom_px > f64::from(self.frame.height) { return Err(bad("extent outside the native frame")); }
        Ok(())
    }
}

/// Renderer normalization reference, ONLY if the corpus metadata/markup carries it. Recorded, never silently preferred.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct RendererNormalization { pub em_px: f64 }

#[derive(Clone, Debug, PartialEq)]
pub enum Identifiability {
    SourceOriginalEmUnidentifiable { missing: Vec<&'static str> },
    RendererMetadataPresent { renderer_em_px: f64 },
}
/// Success status. Production adoption is not approved: the convention is a candidate normalization.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ScaleStatus { CanonicalConventionCandidate }

#[derive(Clone, Debug, PartialEq)]
pub enum ExclusionReason { NoRole }
#[derive(Clone, Debug, PartialEq)]
pub struct Exclusion { pub id: String, pub reason: ExclusionReason }

#[derive(Clone, Debug, PartialEq)]
pub struct RoleStat { pub role: Role, pub extent: Extent, pub count: usize, pub median_px: f64, pub mad_px: f64, pub min_px: f64, pub max_px: f64 }

#[derive(Clone, Debug, PartialEq)]
pub enum ScaleError {
    EmptyPopulation,
    InvalidGroup,
    EmptyGlyphId,
    EmptySourcePin { glyph: String },
    DuplicateGlyphId { glyph: String },
    /// Observation's group id / frame binding / frame differs from the group record.
    GroupMismatch { glyph: String },
    /// derived_bounds was handed an observation that was not part of the population this scale was derived from.
    ForeignObservation { glyph: String },
    InvalidMeasurement { glyph: String, why: &'static str },
    InvalidUpm,
    InvalidRendererEm,
    MissingRole { role: Role, extent: Extent },
    AnchorOrder { upper_px: f64, baseline_px: f64, lower_px: f64 },
    DegenerateEm { em_px: f64 },
}

#[derive(Clone, Debug, PartialEq)]
pub struct CanonicalScale {
    group: SourceGroup, convention: Convention, upm: f64,
    baseline_px: f64, upper_px: f64, lower_px: f64, em_px: f64, scale: f64,
    identifiability: Identifiability,
    role_stats: Vec<RoleStat>, role_counts: Vec<(Role, usize)>, excluded: Vec<Exclusion>,
    /// (id, source_pin, roles, top, bottom) for EVERY population member, sorted by id: the full population record.
    population: Vec<(String, String, Vec<Role>, f64, f64)>,
}
impl CanonicalScale {
    pub fn status(&self) -> ScaleStatus { ScaleStatus::CanonicalConventionCandidate }
    pub fn group(&self) -> &SourceGroup { &self.group }
    pub fn convention(&self) -> Convention { self.convention }
    pub fn upm(&self) -> f64 { self.upm }
    pub fn baseline_px(&self) -> f64 { self.baseline_px }
    pub fn upper_px(&self) -> f64 { self.upper_px }
    pub fn lower_px(&self) -> f64 { self.lower_px }
    pub fn em_px(&self) -> f64 { self.em_px }
    /// Font units per source pixel.
    pub fn scale(&self) -> f64 { self.scale }
    pub fn identifiability(&self) -> &Identifiability { &self.identifiability }
    pub fn role_stats(&self) -> &[RoleStat] { &self.role_stats }
    pub fn role_counts(&self) -> &[(Role, usize)] { &self.role_counts }
    pub fn excluded(&self) -> &[Exclusion] { &self.excluded }
}

fn median(v: &mut Vec<f64>) -> f64 {
    v.sort_by(|a, b| a.total_cmp(b));
    let n = v.len();
    if n % 2 == 1 { v[n / 2] } else { v[n / 2 - 1] + (v[n / 2] - v[n / 2 - 1]) / 2.0 }
}
fn stat_of(role: Role, extent: Extent, vals: &[f64]) -> RoleStat {
    let mut a = vals.to_vec();
    let m = median(&mut a);
    let mut dev: Vec<f64> = vals.iter().map(|x| (x - m).abs()).collect();
    let mad = median(&mut dev);
    RoleStat { role, extent, count: vals.len(), median_px: m, mad_px: mad,
        min_px: vals.iter().cloned().fold(f64::INFINITY, f64::min), max_px: vals.iter().cloned().fold(f64::NEG_INFINITY, f64::max) }
}
fn values(obs: &[GlyphObservation], a: Anchor) -> Vec<f64> {
    obs.iter().filter(|o| o.roles.contains(&a.role)).map(|o| match a.extent { Extent::Top => o.top_px, Extent::Bottom => o.bottom_px }).collect()
}

/// Derive for ONE source group. Every observation is revalidated (group triple, ids, pins, finite extents inside the frame),
/// role-less ones included; NoRole only keeps a glyph out of the anchor populations, never out of validation or the record.
pub fn derive_canonical_scale(
    group: &SourceGroup, obs: &[GlyphObservation], conv: Convention, upm: f64,
    renderer: Option<RendererNormalization>, renderer_metadata_looked_for: &[&'static str],
) -> Result<CanonicalScale, ScaleError> {
    if !(upm.is_finite() && upm > 0.0) { return Err(ScaleError::InvalidUpm); }
    if obs.is_empty() { return Err(ScaleError::EmptyPopulation); }
    let mut ids: HashSet<&str> = HashSet::new();
    for o in obs {
        o.validate(group)?;
        if !ids.insert(o.id.as_str()) { return Err(ScaleError::DuplicateGlyphId { glyph: o.id.clone() }); }
    }
    let need = |a: Anchor| -> Result<Vec<f64>, ScaleError> {
        let v = values(obs, a);
        if v.is_empty() { Err(ScaleError::MissingRole { role: a.role, extent: a.extent }) } else { Ok(v) }
    };
    let (bv, uv, lv) = (need(conv.baseline)?, need(conv.upper)?, need(conv.lower)?);
    let (baseline_px, upper_px, lower_px) = (
        stat_of(conv.baseline.role, conv.baseline.extent, &bv).median_px,
        stat_of(conv.upper.role, conv.upper.extent, &uv).median_px,
        stat_of(conv.lower.role, conv.lower.extent, &lv).median_px);
    if !(upper_px < baseline_px && baseline_px < lower_px) { return Err(ScaleError::AnchorOrder { upper_px, baseline_px, lower_px }); }
    let em_px = lower_px - upper_px;
    if !(em_px.is_finite() && em_px > 0.0) { return Err(ScaleError::DegenerateEm { em_px }); }
    let scale = upm / em_px;
    if !(scale.is_finite() && scale > 0.0) { return Err(ScaleError::DegenerateEm { em_px }); }
    let identifiability = match renderer {
        Some(r) if r.em_px.is_finite() && r.em_px > 0.0 => Identifiability::RendererMetadataPresent { renderer_em_px: r.em_px },
        Some(_) => return Err(ScaleError::InvalidRendererEm),
        None => Identifiability::SourceOriginalEmUnidentifiable { missing: renderer_metadata_looked_for.to_vec() },
    };
    let mut roles: Vec<Role> = obs.iter().flat_map(|o| o.roles.iter().cloned()).collect();
    roles.sort(); roles.dedup();
    let (mut role_stats, mut role_counts) = (vec![], vec![]);
    for r in roles {
        role_counts.push((r, obs.iter().filter(|o| o.roles.contains(&r)).count()));
        for e in [Extent::Top, Extent::Bottom] { role_stats.push(stat_of(r, e, &values(obs, Anchor { role: r, extent: e }))); }
    }
    let excluded = obs.iter().filter(|o| o.roles.is_empty()).map(|o| Exclusion { id: o.id.clone(), reason: ExclusionReason::NoRole }).collect();
    let mut population: Vec<_> = obs.iter().map(|o| (o.id.clone(), o.source_pin.clone(), o.roles.clone(), o.top_px, o.bottom_px)).collect();
    population.sort_by(|a, b| a.0.cmp(&b.0));
    Ok(CanonicalScale { group: group.clone(), convention: conv, upm, baseline_px, upper_px, lower_px, em_px, scale, identifiability, role_stats, role_counts, excluded, population })
}

pub fn y_units(cs: &CanonicalScale, y_px: f64) -> Option<f64> { let v = (cs.baseline_px - y_px) * cs.scale; v.is_finite().then_some(v) }
pub fn x_units(cs: &CanonicalScale, x_px: f64, origin_px: f64) -> Option<f64> { let v = (x_px - origin_px) * cs.scale; v.is_finite().then_some(v) }

#[derive(Clone, Debug, PartialEq)]
pub struct DerivedBounds { pub id: String, pub y_top_units: f64, pub y_bottom_units: f64 }

/// Derived vertical bounds for the supplied glyphs. Each observation is REVALIDATED against the scale's own group, must belong to
/// the population the scale was derived from (id, pin and extents equal to the recorded member), else typed error; a forged or
/// foreign observation is never converted.
pub fn derived_bounds(cs: &CanonicalScale, obs: &[GlyphObservation]) -> Result<Vec<DerivedBounds>, ScaleError> {
    obs.iter().map(|o| {
        o.validate(&cs.group)?;
        let member = cs.population.iter().find(|m| m.0 == o.id);
        match member {
            Some(m) if m.1 == o.source_pin && m.3 == o.top_px && m.4 == o.bottom_px && m.2 == o.roles => {}
            _ => return Err(ScaleError::ForeignObservation { glyph: o.id.clone() }),
        }
        match (y_units(cs, o.top_px), y_units(cs, o.bottom_px)) {
            (Some(t), Some(b)) => Ok(DerivedBounds { id: o.id.clone(), y_top_units: t, y_bottom_units: b }),
            _ => Err(ScaleError::InvalidMeasurement { glyph: o.id.clone(), why: "derived bound not finite" }),
        }
    }).collect()
}

/// TSV-safe text: tab, newline, CR and backslash escaped.
fn esc(s: &str) -> String { s.replace('\\', "\\\\").replace('\t', "\\t").replace('\n', "\\n").replace('\r', "\\r") }

/// Audit cohort: one TSV row per (shared pin, member glyph): "canonical_scale_shared_pin\tgroup\tpin\tid\n", all strings
/// esc()-escaped so no delimiter ambiguity; sorted by pin then id. Pins held by >1 glyph only. Reported only; nothing is
/// refused or dropped. Weighting by glyph vs by unique image is a separate open convention; the current contract
/// counts every distinct glyph.
pub fn shared_content_audit(cs: &CanonicalScale) -> Vec<String> {
    let mut m: std::collections::BTreeMap<&str, Vec<&str>> = std::collections::BTreeMap::new();
    for (id, pin, _, _, _) in &cs.population { m.entry(pin.as_str()).or_default().push(id.as_str()); }
    let mut out = vec![];
    for (p, mut v) in m { if v.len() > 1 { v.sort(); for id in v { out.push(format!("canonical_scale_shared_pin\t{}\t{}\t{}\n", esc(cs.group.id()), esc(p), esc(id))); } } }
    out
}
/// Full population record, one line per member (every glyph, role-less included), sorted by id.
pub fn population_record(cs: &CanonicalScale) -> Vec<String> {
    cs.population.iter().map(|(id, pin, roles, t, b)| {
        let r: Vec<String> = roles.iter().map(|x| format!("{x:?}")).collect();
        format!("canonical_scale_member\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n", esc(cs.group.id()), esc(id), esc(pin), if r.is_empty() { "-".to_string() } else { r.join("+") }, t, b, if roles.is_empty() { "excluded_no_role" } else { "anchor_pool" })
    }).collect()
}
/// FNV-1a 64 over the population record. NON-cryptographic: an integrity tag for the row, not a pin; the caller may add sha256.
pub fn population_tag(cs: &CanonicalScale) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for line in population_record(cs) { for b in line.bytes() { h ^= u64::from(b); h = h.wrapping_mul(0x100000001b3); } }
    h
}

pub fn receipt_row(cs: &CanonicalScale) -> String {
    let ident = match &cs.identifiability {
        Identifiability::SourceOriginalEmUnidentifiable { missing } => format!("SourceOriginalEmUnidentifiable[{}]", missing.join(",")),
        Identifiability::RendererMetadataPresent { renderer_em_px } => format!("RendererMetadataPresent[{renderer_em_px}]"),
    };
    let a = |x: Anchor| format!("{:?}.{:?}", x.role, x.extent);
    let roles: Vec<String> = cs.role_counts.iter().map(|(r, n)| format!("{r:?}:{n}")).collect();
    format!(
        "canonical_scale\t{}\tstatus\t{:?}\tidentifiability\t{}\tconvention\tbaseline={};upper={};lower={};em=lower-upper;stat={:?}\tupm\t{}\tframe_px\t{}x{}\tframe_binding\t{}\tbaseline_px\t{}\tupper_px\t{}\tlower_px\t{}\tem_px\t{}\tscale\t{}\troles\t{}\tmembers\t{}\texcluded_no_role\t{}\tpopulation_fnv1a64\t{:016x}\n",
        esc(cs.group.id()), cs.status(), esc(&ident), a(cs.convention.baseline), a(cs.convention.upper), a(cs.convention.lower), cs.convention.stat,
        cs.upm, cs.group.frame.width, cs.group.frame.height, esc(cs.group.frame_binding()), cs.baseline_px, cs.upper_px, cs.lower_px, cs.em_px, cs.scale,
        roles.join(","), cs.population.len(), cs.excluded.len(), population_tag(cs)
    )
}

/// Per-group view of one role/extent across groups. If several styles show the SAME median to within their own dispersion,
/// the renderer may have normalized that height (then it is a renderer constant, not evidence of the scale). Reported, not judged.
pub fn cross_group_role_report(scales: &[CanonicalScale], role: Role, extent: Extent) -> Vec<(String, usize, f64, f64)> {
    scales.iter().filter_map(|s| s.role_stats.iter().find(|r| r.role == role && r.extent == extent).map(|r| (s.group.id.clone(), r.count, r.median_px, r.mad_px))).collect()
}

#[cfg(test)]
mod tests {
    //! Unit arithmetic only: synthetic observations (arbitrary non-font numbers), no tile, no pipeline, no fit. Invariance tests are
    //! properties of the arithmetic, NOT independent anchors on the true em (there is none).
    use super::*;
    use Role::*;
    const FRAME: PixelFrame = PixelFrame { width: 1000, height: 900 };
    fn grp() -> SourceGroup { SourceGroup::new("styleA", FRAME, "frame-binding-A").unwrap() }
    fn ob(g: &SourceGroup, id: &str, roles: &[Role], top: f64, bottom: f64) -> GlyphObservation { GlyphObservation::new(g, id, &format!("pin-{id}"), roles, top, bottom).unwrap() }
    fn pop(g: &SourceGroup) -> Vec<GlyphObservation> {
        vec![
            ob(g, "b1", &[Baseline], 300.0, 600.0), ob(g, "b2", &[Baseline], 280.0, 600.5), ob(g, "b3", &[Baseline], 310.0, 599.5),
            ob(g, "a1", &[Ascender], 120.0, 600.0), ob(g, "a2", &[Ascender], 100.0, 600.0), ob(g, "a3", &[Ascender], 110.0, 600.0),
            ob(g, "d1", &[Descender], 330.0, 760.0), ob(g, "d2", &[Descender], 340.0, 780.0), ob(g, "d3", &[Descender], 335.0, 770.0),
            ob(g, "x1", &[XHeight], 360.0, 601.0), ob(g, "mark", &[], 50.0, 70.0),
        ]
    }
    fn derive(g: &SourceGroup, p: &[GlyphObservation]) -> Result<CanonicalScale, ScaleError> {
        derive_canonical_scale(g, p, Convention::vertical_envelope(), 1000.0, None, &["font_size", "em_box", "grid_unit", "frame_id"])
    }
    fn close(a: f64, b: f64) -> bool { (a - b).abs() <= 64.0 * f64::EPSILON * a.abs().max(b.abs()).max(1.0) }

    #[test]
    fn status_is_candidate_and_source_em_is_unidentifiable() {
        let g = grp();
        let cs = derive(&g, &pop(&g)).unwrap();
        assert_eq!(cs.status(), ScaleStatus::CanonicalConventionCandidate);
        assert!(matches!(cs.identifiability(), Identifiability::SourceOriginalEmUnidentifiable { missing } if missing.len() == 4));
        assert!(close(cs.scale() * cs.em_px(), cs.upm()));
        let row = receipt_row(&cs);
        assert!(row.contains("\tstatus\tCanonicalConventionCandidate\t") && !row.contains("Usable"));
        assert!(row.contains("SourceOriginalEmUnidentifiable[font_size,em_box,grid_unit,frame_id]"));
    }
    #[test]
    fn medians_not_extremes_define_the_anchors() {
        let g = grp();
        let cs = derive(&g, &pop(&g)).unwrap();
        assert_eq!((cs.baseline_px(), cs.upper_px(), cs.lower_px(), cs.em_px()), (600.0, 110.0, 770.0, 660.0));
    }
    #[test]
    fn every_population_is_visible_and_every_glyph_has_a_bound() {
        let g = grp(); let p = pop(&g);
        let cs = derive(&g, &p).unwrap();
        assert_eq!(cs.excluded(), &[Exclusion { id: "mark".into(), reason: ExclusionReason::NoRole }]);
        assert!(cs.role_counts().contains(&(XHeight, 1)) && cs.role_counts().contains(&(Ascender, 3)));
        assert_eq!(derived_bounds(&cs, &p).unwrap().len(), p.len());
        let rec = population_record(&cs);
        assert_eq!(rec.len(), p.len());
        assert!(rec.iter().any(|l| l.contains("\tmark\t") && l.ends_with("excluded_no_role\n")));
    }
    #[test]
    fn multi_role_glyph_counts_in_each_population() {
        let g = grp();
        let mut p = pop(&g);
        p.push(ob(&g, "H", &[Baseline, Cap, Ascender], 150.0, 600.0)); // flat-bottom cap that also reaches an ascender-like top
        let cs = derive(&g, &p).unwrap();
        assert!(cs.role_counts().contains(&(Baseline, 4)) && cs.role_counts().contains(&(Cap, 1)) && cs.role_counts().contains(&(Ascender, 4)));
        // overlap is data, not a bias fix: Ascender tops 100,110,120,150 -> median 115
        assert_eq!(cs.upper_px(), 115.0);
    }
    #[test]
    fn outlier_member_is_reported_not_dropped() {
        let g = grp(); let mut p = pop(&g);
        p.push(ob(&g, "a_out", &[Ascender], 20.0, 600.0));
        let cs = derive(&g, &p).unwrap();
        assert_eq!(cs.upper_px(), 105.0);
        let st = cs.role_stats().iter().find(|s| s.role == Ascender && s.extent == Extent::Top).unwrap();
        assert_eq!((st.min_px, st.count), (20.0, 4));
        assert!(st.mad_px > 0.0);
    }
    #[test]
    fn translation_invariance() {
        let g = grp(); let base = derive(&g, &pop(&g)).unwrap();
        let moved: Vec<_> = pop(&g).iter().map(|o| ob(&g, o.id(), o.roles(), o.top_px() + 37.25, o.bottom_px() + 37.25)).collect();
        let m = derive(&g, &moved).unwrap();
        assert!(close(m.em_px(), base.em_px()) && close(m.scale(), base.scale()) && close(m.baseline_px(), base.baseline_px() + 37.25));
    }
    #[test]
    fn reflection_invariance_with_swapped_roles() {
        let g = grp(); let h = f64::from(FRAME.height);
        let flipped: Vec<_> = pop(&g).iter().map(|o| {
            let roles: Vec<Role> = o.roles().iter().map(|r| match r { Ascender => Descender, Descender => Ascender, x => *x }).collect();
            ob(&g, o.id(), &roles, h - o.bottom_px(), h - o.top_px())
        }).collect();
        // relabelled flipped members: old descenders (now Ascender) have Top at the new upper side, old ascenders (now Descender) Bottom at the new lower side;
        // only the baseline anchor changes edge (the old Bottom edge is now the Top edge).
        let conv = Convention { baseline: Anchor { role: Baseline, extent: Extent::Top }, ..Convention::vertical_envelope() };
        let r = derive_canonical_scale(&g, &flipped, conv, 1000.0, None, &[]).unwrap();
        let b = derive(&g, &pop(&g)).unwrap();
        assert!(close(r.em_px(), b.em_px()) && close(r.scale(), b.scale()));
    }
    #[test]
    fn size_ratio_invariance_scale_inversely_unit_bounds_identical() {
        let g = grp(); let b = derive(&g, &pop(&g)).unwrap();
        let k = 2.5;
        let g2 = SourceGroup::new("styleA", PixelFrame { width: 2500, height: 2250 }, "frame-binding-A").unwrap();
        let big: Vec<_> = pop(&g).iter().map(|o| ob(&g2, o.id(), o.roles(), o.top_px() * k, o.bottom_px() * k)).collect();
        let c = derive(&g2, &big).unwrap();
        assert!(close(c.em_px(), b.em_px() * k) && close(c.scale(), b.scale() / k) && close(c.baseline_px(), b.baseline_px() * k));
        let (ub, uc) = (derived_bounds(&b, &pop(&g)).unwrap(), derived_bounds(&c, &big).unwrap());
        for (x, y) in ub.iter().zip(uc.iter()) { assert!(close(x.y_top_units, y.y_top_units) && close(x.y_bottom_units, y.y_bottom_units)); }
    }
    #[test]
    fn envelope_in_units_equals_upm_by_construction_not_independent_evidence() {
        let g = grp(); let cs = derive(&g, &pop(&g)).unwrap();
        assert!(close(y_units(&cs, cs.upper_px()).unwrap() - y_units(&cs, cs.lower_px()).unwrap(), cs.upm()));
    }
    #[test]
    fn construction_validates_every_observation_including_role_less() {
        let g = grp();
        let mk = |roles: &[Role], t: f64, b: f64| GlyphObservation::new(&g, "z", "pin-z", roles, t, b);
        assert!(matches!(mk(&[], f64::NAN, 70.0), Err(ScaleError::InvalidMeasurement { why: "non-finite extent", .. })));
        assert!(matches!(mk(&[], 10.0, 10_000.0), Err(ScaleError::InvalidMeasurement { why: "extent outside the native frame", .. })));
        assert!(matches!(mk(&[Baseline], 70.0, 50.0), Err(ScaleError::InvalidMeasurement { .. })));
        assert_eq!(GlyphObservation::new(&g, "", "p", &[], 1.0, 2.0), Err(ScaleError::EmptyGlyphId));
        assert_eq!(GlyphObservation::new(&g, "z", "", &[], 1.0, 2.0), Err(ScaleError::EmptySourcePin { glyph: "z".into() }));
        assert_eq!(SourceGroup::new("", FRAME, "b"), Err(ScaleError::InvalidGroup));
        assert_eq!(SourceGroup::new("s", PixelFrame { width: 0, height: 5 }, "b"), Err(ScaleError::InvalidGroup));
        // a forged role-less observation (same-module field access) is caught by derive's own revalidation, not skipped
        let mut p = pop(&g);
        let i = p.iter().position(|o| o.id() == "mark").unwrap();
        p[i].top_px = f64::NAN;
        assert!(matches!(derive(&g, &p), Err(ScaleError::InvalidMeasurement { ref glyph, .. }) if glyph == "mark"));
    }
    #[test]
    fn group_identity_is_more_than_pixel_size() {
        let g = grp();
        let other_binding = SourceGroup::new("styleA", FRAME, "frame-binding-B").unwrap(); // same canvas, different origin rule
        let other_style = SourceGroup::new("styleB", FRAME, "frame-binding-A").unwrap();
        let mut p = pop(&g);
        p[3] = ob(&other_binding, "a1", &[Ascender], 120.0, 600.0);
        assert_eq!(derive(&g, &p), Err(ScaleError::GroupMismatch { glyph: "a1".into() }));
        let mut q = pop(&g);
        q[3] = ob(&other_style, "a1", &[Ascender], 120.0, 600.0);
        assert_eq!(derive(&g, &q), Err(ScaleError::GroupMismatch { glyph: "a1".into() }));
        let mut r = pop(&g);
        r[3] = GlyphObservation::new(&SourceGroup::new("styleA", PixelFrame { width: 786, height: 1122 }, "frame-binding-A").unwrap(), "a1", "pin-a1", &[Ascender], 120.0, 600.0).unwrap();
        assert_eq!(derive(&g, &r), Err(ScaleError::GroupMismatch { glyph: "a1".into() }));
    }
    #[test]
    fn duplicate_ids_are_typed_shared_pins_are_audited() {
        let g = grp();
        let mut p = pop(&g); p.push(ob(&g, "a1", &[Ascender], 90.0, 600.0));
        assert_eq!(derive(&g, &p), Err(ScaleError::DuplicateGlyphId { glyph: "a1".into() }));
        // Shared tile content is NOT a refusal: distinct glyphs may have identical PNG bytes. Each glyph still counts.
        let mut q = pop(&g);
        q.push(GlyphObservation::new(&g, "a1_again", "pin-a1", &[Ascender], 90.0, 600.0).unwrap());
        let n = q.len();
        let cs = derive(&g, &q).unwrap();
        assert_eq!(cs.population.len(), n);
        let audit = shared_content_audit(&cs);
        assert_eq!(audit, vec![
            "canonical_scale_shared_pin\tstyleA\tpin-a1\ta1\n".to_string(),
            "canonical_scale_shared_pin\tstyleA\tpin-a1\ta1_again\n".to_string()]);
        // hostile ids/pins (tab, newline, comma, backslash) stay unambiguous: one row per member, escaped.
        let mut h = pop(&g);
        h.push(GlyphObservation::new(&g, "x,\ty", "p\tq\n", &[Ascender], 90.0, 600.0).unwrap());
        h.push(GlyphObservation::new(&g, "z\\", "p\tq\n", &[Ascender], 90.0, 600.0).unwrap());
        let rows = shared_content_audit(&derive(&g, &h).unwrap());
        assert_eq!(rows, vec![
            "canonical_scale_shared_pin\tstyleA\tp\\tq\\n\tx,\\ty\n".to_string(),
            "canonical_scale_shared_pin\tstyleA\tp\\tq\\n\tz\\\\\n".to_string()]);
        assert!(rows.iter().all(|r| r.matches('\t').count() == 3 && r.matches('\n').count() == 1 && r.ends_with('\n')));
    }
    #[test]
    fn typed_failures() {
        let g = grp();
        let mut no_desc = pop(&g); no_desc.retain(|o| !o.roles().contains(&Descender));
        assert_eq!(derive(&g, &no_desc), Err(ScaleError::MissingRole { role: Descender, extent: Extent::Bottom }));
        let mut no_base = pop(&g); no_base.retain(|o| !o.roles().contains(&Baseline));
        assert_eq!(derive(&g, &no_base), Err(ScaleError::MissingRole { role: Baseline, extent: Extent::Bottom }));
        assert_eq!(derive(&g, &[]), Err(ScaleError::EmptyPopulation));
        let mut ord = pop(&g);
        for o in ord.iter_mut().filter(|o| o.roles().contains(&Ascender)) { o.top_px = 650.0; o.bottom_px = 700.0; }
        assert!(matches!(derive(&g, &ord), Err(ScaleError::AnchorOrder { .. })));
        assert_eq!(derive_canonical_scale(&g, &pop(&g), Convention::vertical_envelope(), 0.0, None, &[]), Err(ScaleError::InvalidUpm));
        assert_eq!(derive_canonical_scale(&g, &pop(&g), Convention::vertical_envelope(), 1000.0, Some(RendererNormalization { em_px: -1.0 }), &[]), Err(ScaleError::InvalidRendererEm));
    }
    #[test]
    fn renderer_metadata_is_recorded_and_never_replaces_the_derived_scale() {
        let g = grp();
        let cs = derive_canonical_scale(&g, &pop(&g), Convention::vertical_envelope(), 1000.0, Some(RendererNormalization { em_px: 777.0 }), &[]).unwrap();
        assert_eq!(cs.identifiability(), &Identifiability::RendererMetadataPresent { renderer_em_px: 777.0 });
        assert_eq!(cs.em_px(), 660.0);
    }
    #[test]
    fn derived_bounds_rejects_foreign_and_forged_observations() {
        let g = grp(); let p = pop(&g); let cs = derive(&g, &p).unwrap();
        let foreign = ob(&g, "not_in_population", &[Baseline], 100.0, 200.0);
        assert_eq!(derived_bounds(&cs, &[foreign]), Err(ScaleError::ForeignObservation { glyph: "not_in_population".into() }));
        let mut forged = p[0].clone(); forged.bottom_px += 1.0; // same id, different extent than the derivation saw
        assert_eq!(derived_bounds(&cs, &[forged]), Err(ScaleError::ForeignObservation { glyph: "b1".into() }));
        let other = SourceGroup::new("styleB", FRAME, "frame-binding-A").unwrap();
        assert_eq!(derived_bounds(&cs, &[ob(&other, "b1", &[Baseline], 300.0, 600.0)]), Err(ScaleError::GroupMismatch { glyph: "b1".into() }));
    }
    #[test]
    fn receipt_row_is_tsv_safe_and_carries_the_population_tag() {
        let g = SourceGroup::new("sty\tle\nA", FRAME, "bind\\ing").unwrap();
        let cs = derive(&g, &pop(&g)).unwrap();
        let row = receipt_row(&cs);
        assert_eq!(row.matches('\n').count(), 1, "one physical line");
        assert!(row.contains("canonical_scale\tsty\\tle\\nA\t") && row.contains("frame_binding\tbind\\\\ing\t"));
        assert!(row.contains("\tmembers\t11\texcluded_no_role\t1\tpopulation_fnv1a64\t"));
        let mut p2 = pop(&g); p2[0] = GlyphObservation::new(&g, "b1", "pin-OTHER", &[Baseline], 300.0, 600.0).unwrap();
        assert_ne!(population_tag(&cs), population_tag(&derive(&g, &p2).unwrap()));
        assert!(row.contains("\tem_px\t660\t"));
    }
    #[test]
    fn cross_group_report_lists_each_group_without_judging() {
        let (ga, gb) = (grp(), SourceGroup::new("styleB", FRAME, "frame-binding-A").unwrap());
        let (a, b) = (derive(&ga, &pop(&ga)).unwrap(), derive(&gb, &pop(&gb)).unwrap());
        let rep = cross_group_role_report(&[a, b], Ascender, Extent::Top);
        assert_eq!(rep, vec![("styleA".to_string(), 3, 110.0, 10.0), ("styleB".to_string(), 3, 110.0, 10.0)]);
    }
}
