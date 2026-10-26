//! Caller-bound construction regions. No inferred roles, geometry edits or acceptance decisions.
use crate::reference_slice::{DrawnGlyph, Point, Span};
use crate::economy::{ConstructionComparison, FontAssessment, FontEconomyEvaluator};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RegionKind { Ink, Counter, Unknown }
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RingRole { Outer, Hole, Unknown }
#[derive(Clone, Debug)]
pub struct SpanRange {
    pub ring: usize,
    /// Half-open original outline span indices. No implicit wrap or reindexing.
    pub first: usize,
    pub end: usize,
    pub role: RingRole,
}
#[derive(Clone, Debug)]
pub struct ConstructionRegion {
    pub id: String,
    pub kind: RegionKind,
    /// Caller record identifying the candidate structural hypothesis, not accepted intent.
    pub hypothesis_ref: String,
    pub baseline: Vec<SpanRange>,
    pub candidate: Vec<SpanRange>,
    /// Explicit source-boundary chains in the same font-coordinate frame as both outlines.
    /// Consecutive points are connected; no closing segment is invented.
    pub source_chains: Vec<Vec<Point>>,
}
#[derive(Clone, Debug)]
pub struct RegionConfig {
    pub source_pin: String,
    pub frame_pin: String,
    pub glyph_id: String,
    /// Caller-selected sampling convention, not a shape tolerance.
    pub flatten_steps: usize,
}
#[derive(Clone, Debug, PartialEq)]
pub struct BoundaryMetrics { pub squared_error: f64, pub maximum_deviation: f64 }
#[derive(Clone, Debug)]
pub struct RegionMeasurement {
    /// Retained output identity so callers can join metrics to their declared region.
    pub id: String,
    pub kind: RegionKind,
    /// Retained provenance link to the caller hypothesis; metrics do not accept it.
    pub hypothesis_ref: String,
    pub hypothesis_status: &'static str,
    pub metric_label: &'static str,
    pub baseline: BoundaryMetrics,
    pub candidate: BoundaryMetrics,
    pub construction: ConstructionComparison,
}
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RegionError {
    MissingPin, GlyphMismatch, EmptyRegions, DuplicateId, UnknownStructure,
    EmptyMembership, InvalidRange, Overlap, InvalidSource, InvalidGeometry,
    InvalidResolution, UnverifiedFont, PinMismatch,
}
fn end(s: &Span) -> Point { match s { Span::Line { end } | Span::Cubic { end, .. } => *end } }
fn finite(p: Point) -> bool { p.x.is_finite() && p.y.is_finite() }
fn valid_chain(c: &[Point]) -> bool {
    c.len() > 1 && c.iter().all(|p| finite(*p)) && c.windows(2).all(|w| w[0] != w[1])
}
fn chains(g: &DrawnGlyph, ranges: &[SpanRange], kind: &RegionKind, steps: usize,
          occupied: &mut Vec<(usize, usize)>) -> Result<Vec<Vec<Point>>, RegionError> {
    if ranges.is_empty() { return Err(RegionError::EmptyMembership); }
    let mut out = Vec::new();
    for r in ranges {
        if r.role == RingRole::Unknown || *kind == RegionKind::Unknown {
            return Err(RegionError::UnknownStructure);
        }
        let ring = g.rings.get(r.ring).ok_or(RegionError::InvalidRange)?;
        if r.first >= r.end || r.end > ring.spans.len() { return Err(RegionError::InvalidRange); }
        let mut current = if r.first == 0 { ring.start } else { end(&ring.spans[r.first - 1]) };
        let mut pts = vec![current];
        for i in r.first..r.end {
            if occupied.contains(&(r.ring, i)) { return Err(RegionError::Overlap); }
            occupied.push((r.ring, i));
            match &ring.spans[i] {
                Span::Line { end } => pts.push(*end),
                Span::Cubic { control_one: a, control_two: b, end: e } => {
                    if ![current,*a,*b,*e].iter().all(|p| finite(*p)) { return Err(RegionError::InvalidGeometry); }
                    for j in 1..=steps {
                        if j == steps { pts.push(*e); continue; }
                        let t = j as f64 / steps as f64; let u = 1.0 - t;
                        pts.push(Point { x: u*u*u*current.x + 3.0*u*u*t*a.x + 3.0*u*t*t*b.x + t*t*t*e.x,
                            y: u*u*u*current.y + 3.0*u*u*t*a.y + 3.0*u*t*t*b.y + t*t*t*e.y });
                    }
                }
            }
            current = end(&ring.spans[i]);
        }
        if !valid_chain(&pts) { return Err(RegionError::InvalidGeometry); }
        out.push(pts);
    }
    Ok(out)
}
fn distance(p: Point, a: Point, b: Point) -> Option<f64> {
    let (dx,dy) = (b.x-a.x,b.y-a.y); let len2=dx*dx+dy*dy;
    if !len2.is_finite() || len2 <= 0.0 { return None; }
    let t=(((p.x-a.x)*dx+(p.y-a.y)*dy)/len2).clamp(0.0,1.0);
    let d=(p.x-a.x-t*dx).hypot(p.y-a.y-t*dy);
    d.is_finite().then_some(d)
}
fn metrics(a: &[Vec<Point>], b: &[Vec<Point>]) -> Result<BoundaryMetrics, RegionError> {
    fn directed(a: &[Vec<Point>], b: &[Vec<Point>]) -> Option<(f64,f64)> {
        let mut sum=0.0; let mut max=0.0f64; let mut count=0usize;
        for p in a.iter().flatten() {
            let mut best=f64::INFINITY;
            for chain in b { for w in chain.windows(2) { best=best.min(distance(*p,w[0],w[1])?); } }
            sum+=best*best; max=max.max(best); count+=1;
        }
        let mean=sum/count as f64;
        (count>0 && mean.is_finite() && max.is_finite()).then_some((mean,max))
    }
    let (ab,ma)=directed(a,b).ok_or(RegionError::InvalidGeometry)?;
    let (ba,mb)=directed(b,a).ok_or(RegionError::InvalidGeometry)?;
    let squared_error=ab/2.0+ba/2.0;
    if !squared_error.is_finite() { return Err(RegionError::InvalidGeometry); }
    Ok(BoundaryMetrics { squared_error, maximum_deviation: ma.max(mb) })
}
/// Descriptive sampled boundary metrics only. Unassigned spans are allowed; coverage is not claimed.
/// Every caller role and hypothesis remains unverified. Overlap anywhere in either membership side abstains.
pub fn measure_regions(cfg: &RegionConfig, base: &DrawnGlyph, cand: &DrawnGlyph,
                       regions: &[ConstructionRegion]) -> Result<Vec<RegionMeasurement>,RegionError> {
    if cfg.source_pin.trim().is_empty() || cfg.frame_pin.trim().is_empty() { return Err(RegionError::MissingPin); }
    if cfg.glyph_id.trim().is_empty() || base.glyph_id!=cfg.glyph_id || cand.glyph_id!=cfg.glyph_id { return Err(RegionError::GlyphMismatch); }
    if cfg.flatten_steps==0 { return Err(RegionError::InvalidResolution); }
    if regions.is_empty() { return Err(RegionError::EmptyRegions); }
    let mut ordered: Vec<_> = regions.iter().collect(); ordered.sort_by(|a,b| a.id.cmp(&b.id));
    let mut bo=Vec::new(); let mut co=Vec::new(); let mut result=Vec::new(); let mut previous=None;
    for r in ordered {
        if r.id.trim().is_empty() || previous==Some(&r.id) { return Err(RegionError::DuplicateId); }
        previous=Some(&r.id);
        if r.kind==RegionKind::Unknown || r.hypothesis_ref.trim().is_empty() { return Err(RegionError::UnknownStructure); }
        if r.source_chains.is_empty() || !r.source_chains.iter().all(|c|valid_chain(c)) { return Err(RegionError::InvalidSource); }
        let b=chains(base,&r.baseline,&r.kind,cfg.flatten_steps,&mut bo)?;
        let c=chains(cand,&r.candidate,&r.kind,cfg.flatten_steps,&mut co)?;
        result.push(RegionMeasurement { id:r.id.clone(), kind:r.kind.clone(), hypothesis_ref:r.hypothesis_ref.clone(),
            hypothesis_status:"candidate, not accepted hypothesis", metric_label:"sampled boundary metrics",
            baseline:metrics(&r.source_chains,&b)?, candidate:metrics(&r.source_chains,&c)?,
            construction:ConstructionComparison::Unknown });
    }
    Ok(result)
}
/// Additive wrapper: retain the existing evaluator assessment unchanged, return local metrics separately.
/// Region metrics never replace ring assessments or turn Unknown into acceptance evidence.
pub fn assess_with_regions<E: FontEconomyEvaluator>(ev: &mut E, cfg: &RegionConfig, base: &DrawnGlyph,
    cand: &DrawnGlyph, regions: &[ConstructionRegion]) -> Result<(FontAssessment,Vec<RegionMeasurement>),RegionError> {
    let local=measure_regions(cfg,base,cand,regions)?;
    let global=ev.assess(base,cand).ok_or(RegionError::UnverifiedFont)?;
    if global.source_pin!=cfg.source_pin || global.render_frame_pin!=cfg.frame_pin { return Err(RegionError::PinMismatch); }
    Ok((global,local))
}
