//! Source-class-bound guide measurements. No geometry mutation or auto classification.
use std::collections::{BTreeMap, BTreeSet};
pub const MODE: &str = "no snap, measurement/annotation only";
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Scope { pub font: String, pub master: String, pub style: String, pub frame: String }
#[derive(Clone, Debug)]
pub enum SpreadLimit {
    Image { font_units_per_source_pixel: f64 },
    VectorMeasured { font_units: f64, derivation: String },
    VectorDeclared { font_units: f64, derivation: String },
}
impl SpreadLimit {
    pub fn value(&self) -> f64 { match self {
        Self::Image { font_units_per_source_pixel } => *font_units_per_source_pixel,
        Self::VectorMeasured { font_units, .. } | Self::VectorDeclared { font_units, .. } => *font_units,
    }}
    pub fn label(&self) -> &'static str { match self {
        Self::Image { .. } => "image: one source pixel from frame scale",
        Self::VectorMeasured { .. } => "vector: source-derived limit",
        Self::VectorDeclared { .. } => "vector: declared, not measured",
    }}
}
#[derive(Clone, Debug)]
pub struct EdgeObservation {
    pub edge_id: String, pub glyph: String, pub class: String,
    pub source_pin: String, pub membership_evidence: String,
    /// All samples already in the same y-up font-unit frame. Never fitted nodes.
    pub source_y: Vec<f64>,
}
#[derive(Clone, Debug)]
pub struct Guide {
    pub class: String, pub y: Option<f64>, pub source_spread: Option<f64>,
    pub reason: Option<&'static str>, pub reference_glyphs: usize,
}
#[derive(Clone, Debug)]
pub struct Inventory {
    pub scope: Scope, pub source_pin: String, pub limit: SpreadLimit,
    pub guides: BTreeMap<String, Guide>, edges: BTreeMap<String, EdgeObservation>,
}
#[derive(Clone, Debug, PartialEq)]
pub enum Error { InvalidScope, InvalidPin, InvalidLimit, InvalidClass, InvalidEdge, DuplicateEdge, NonFinite, UnrequestedClass }
fn token(s: &str) -> bool { !s.is_empty() && !s.chars().any(char::is_control) }
fn pin(s: &str) -> bool { s.len() == 64 && s.bytes().all(|c| c.is_ascii_hexdigit()) }
fn median(v: &[f64]) -> f64 {
    let mut a = v.to_vec(); a.sort_by(f64::total_cmp);
    let n = a.len(); if n % 2 == 0 { a[n/2-1]/2.0 + a[n/2]/2.0 } else { a[n/2] }
}
fn spread(v: &[f64]) -> f64 { let lo=v.iter().copied().reduce(f64::min).unwrap(); let hi=v.iter().copied().reduce(f64::max).unwrap(); hi-lo }
/// Derive positions, never semantic membership. At least two distinct glyphs are
/// needed to observe between-glyph spread (CONVENTION: independent support).
/// Range of edge medians and every edge's own sample range must be <= limit.
/// Duplicate observations are rejected rather than counted as extra support.
pub fn derive(scope: Scope, source_pin: String, classes: &[String], edges: &[EdgeObservation], limit: SpreadLimit) -> Result<Inventory, Error> {
    if [&scope.font,&scope.master,&scope.style,&scope.frame].iter().any(|s| !token(s)) { return Err(Error::InvalidScope); }
    if !pin(&source_pin) { return Err(Error::InvalidPin); }
    if !limit.value().is_finite() || limit.value()<0.0 { return Err(Error::InvalidLimit); }
    match &limit {
        SpreadLimit::Image { font_units_per_source_pixel } if *font_units_per_source_pixel==0.0 => return Err(Error::InvalidLimit),
        SpreadLimit::VectorMeasured { derivation, .. } | SpreadLimit::VectorDeclared { derivation, .. } if !token(derivation) => return Err(Error::InvalidLimit),
        _ => (),
    }
    let mut groups: BTreeMap<String,Vec<&EdgeObservation>> = BTreeMap::new();
    for c in classes { if !token(c) || groups.insert(c.clone(),Vec::new()).is_some() { return Err(Error::InvalidClass); } }
    let mut map = BTreeMap::new();
    for e in edges {
        if !pin(&e.source_pin) || e.source_pin!=source_pin { return Err(Error::InvalidPin); }
        if [&e.edge_id,&e.glyph,&e.membership_evidence].iter().any(|s| !token(s)) || e.source_y.is_empty() { return Err(Error::InvalidEdge); }
        if e.source_y.iter().any(|y| !y.is_finite()) || !spread(&e.source_y).is_finite() { return Err(Error::NonFinite); }
        if map.insert(e.edge_id.clone(),e.clone()).is_some() { return Err(Error::DuplicateEdge); }
        groups.get_mut(&e.class).ok_or(Error::UnrequestedClass)?.push(e);
    }
    let mut guides=BTreeMap::new();
    for (class, es) in groups {
        let support=es.iter().map(|e| &e.glyph).collect::<BTreeSet<_>>().len();
        let medians: Vec<f64> = es.iter().map(|e| median(&e.source_y)).collect();
        let range=if medians.is_empty() { None } else { Some(spread(&medians)) };
        if range.is_some_and(|v| !v.is_finite()) { return Err(Error::NonFinite); }
        let reason=if support<2 { Some("insufficient independent source glyphs") }
            else if es.iter().any(|e| spread(&e.source_y)>limit.value()) { Some("source edge spread exceeds limit") }
            else if range.unwrap()>limit.value() { Some("source class spread exceeds limit") } else { None };
        let y=if reason.is_none() { Some(median(&medians)) } else { None };
        guides.insert(class.clone(),Guide { class,y,source_spread:range,reason,reference_glyphs:support });
    }
    Ok(Inventory { scope,source_pin,limit,guides,edges:map })
}
#[derive(Clone, Debug)]
pub struct NodeObservation { pub node_id: String, pub scope: Scope, pub glyph: String, pub y: f64, pub source_edge_id: Option<String> }
#[derive(Clone, Debug)]
pub struct Row {
    pub node_id: String, pub class: Option<String>, pub node_y: f64,
    pub guide_y: Option<f64>, pub signed_offset: Option<f64>,
    pub reason: Option<&'static str>, pub mode: &'static str,
}
#[derive(Clone, Copy, Debug, Default)]
pub enum BindingMode { #[default] Disabled, Measure }
/// Only immutable inputs are accepted. Unbound nodes abstain; no nearest-height rule.
pub fn annotate(inventory: &Inventory, nodes: &[NodeObservation], mode: BindingMode) -> Vec<Row> {
    let mut seen=BTreeSet::new();
    let duplicates=nodes.iter().filter_map(|n| if seen.insert(n.node_id.clone()) { None } else { Some(n.node_id.clone()) }).collect::<BTreeSet<_>>();
    nodes.iter().map(|n| {
        let mut r=Row { node_id:n.node_id.clone(),class:None,node_y:n.y,guide_y:None,signed_offset:None,reason:None,mode:MODE };
        r.reason=if matches!(mode,BindingMode::Disabled) { Some("binding disabled") }
            else if !token(&n.node_id) || !token(&n.glyph) { Some("invalid node identity") }
            else if duplicates.contains(&n.node_id) { Some("duplicate node identity") }
            else if !n.y.is_finite() { Some("nonfinite node") }
            else if n.scope!=inventory.scope { Some("scope or frame mismatch") }
            else { match n.source_edge_id.as_ref().and_then(|id| inventory.edges.get(id)) {
                None => Some("missing source edge membership"),
                Some(e) if e.glyph!=n.glyph => Some("source edge glyph mismatch"),
                Some(e) => {
                    r.class=Some(e.class.clone()); let g=&inventory.guides[&e.class]; r.guide_y=g.y;
                    if let Some(y)=g.y { let off=n.y-y; if off.is_finite() {r.signed_offset=Some(off);None} else {Some("nonfinite offset")} } else {g.reason}
                }
            }};
        r
    }).collect()
}
#[derive(Clone, Debug)]
pub struct ClassSummary {
    pub class: String, pub measured: usize, pub abstained: usize,
    pub signed_median: Option<f64>, pub signed_p90: Option<f64>, pub signed_max: Option<f64>,
    pub absolute_max: Option<f64>, pub mode: &'static str,
}
/// p90 uses nearest rank (CONVENTION: ceil(0.9*n)); signed distribution,
/// absolute maximum separately. Missing offsets are never filled with zero.
pub fn summarize(inventory: &Inventory, rows: &[Row]) -> Vec<ClassSummary> {
    inventory.guides.keys().map(|class| {
        let rs:Vec<_>=rows.iter().filter(|r|r.class.as_ref()==Some(class)).collect();
        let mut v:Vec<_>=rs.iter().filter_map(|r|r.signed_offset).collect();v.sort_by(f64::total_cmp);
        let (m,p,x,a)=if v.is_empty(){(None,None,None,None)}else{
            (Some(median(&v)),Some(v[(v.len()*9).div_ceil(10)-1]),v.last().copied(),Some(v.iter().map(|x|x.abs()).reduce(f64::max).unwrap()))
        };
        ClassSummary{class:class.clone(),measured:v.len(),abstained:rs.len()-v.len(),signed_median:m,signed_p90:p,signed_max:x,absolute_max:a,mode:MODE}
    }).collect()
}
