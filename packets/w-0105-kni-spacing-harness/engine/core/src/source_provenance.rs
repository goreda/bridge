//! Measurement-only source mapping. No geometry edits, tolerances or intent.
use crate::reference_slice::{Point,ReferenceRing,Span};

#[derive(Clone,Debug)]
pub struct SourceInterval {
    pub arc:usize,
    pub first_sample:usize,
    pub last_sample:usize,
    /// Retained fitted-source arc samples in font coordinates, NOT raw raster.
    pub samples:Vec<Point>,
}
#[derive(Clone,Debug)]
pub struct PreEmissionSpan {
    pub parent_index:usize,
    pub start:Point,
    pub span:Span,
    pub source:Option<SourceInterval>,
}
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum UnresolvedReason {
    GeometryChangedAfterFit,
    AmbiguousParent,
    InvalidSourceInterval,
}
#[derive(Clone,Debug)]
pub enum ParentBinding {
    ExactRoundedParent{parent_index:usize,source:SourceInterval},
    SyntheticClosure{parent_index:usize},
    Unresolved{reason:UnresolvedReason},
}
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum SpanRole { Corner,Extremum,Seam,Free,Unknown }
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum BindingStatus { RawIntervalBound, Synthetic, UnresolvedRawInterval, UnresolvedGeometry }
#[derive(Clone,Debug)]
pub struct EmittedSpanRecord {
    pub emitted_index:usize,
    pub span_id:String,
    /// No source role is inferred from geometry by this observer.
    pub role:SpanRole,
    pub status:BindingStatus,
    pub start:Point,
    pub span:Span,
    pub binding:ParentBinding,
}
#[derive(Clone,Debug)]
pub struct RingProvenance {
    pub captured_ring_index:usize,
    pub source_tile_pin:Option<String>,
    pub pre_emission:Vec<PreEmissionSpan>,
    pub emitted:Vec<EmittedSpanRecord>,
    pub unmatched_parent_indices:Vec<usize>,
    /// This mapping is not construction-role evidence.
    pub construction_status:&'static str,
}
fn end(s:&Span)->Point{match s{Span::Line{end}|Span::Cubic{end,..}=>*end}}
fn round_point(p:Point)->Point{Point{x:p.x.round(),y:p.y.round()}}
fn rounded(s:&Span)->Span{match s{Span::Line{end}=>Span::Line{end:round_point(*end)},Span::Cubic{control_one,control_two,end}=>Span::Cubic{control_one:round_point(*control_one),control_two:round_point(*control_two),end:round_point(*end)}}}
fn equal(a:&Span,b:&Span)->bool{match(a,b){(Span::Line{end:a},Span::Line{end:b})=>a==b,(Span::Cubic{control_one:a1,control_two:a2,end:a3},Span::Cubic{control_one:b1,control_two:b2,end:b3})=>a1==b1&&a2==b2&&a3==b3,_=>false}}
/// Match exact integer geometry only. Subdivision, merging or pinned controls
/// not already represented by a parent are explicitly unresolved. Never use
/// nearest-neighbour/endpoints alone to fabricate a source interval.
pub fn bind_emission(captured_ring_index:usize,parents:Vec<PreEmissionSpan>,ring:&ReferenceRing)->RingProvenance{
    let mut current=ring.start;let mut used=Vec::new();let mut emitted=Vec::new();
    for (emitted_index,span) in ring.spans.iter().enumerate(){
        let matches:Vec<_>=parents.iter().filter(|p|round_point(p.start)==current&&equal(&rounded(&p.span),span)).collect();
        let binding=if matches.len()!=1{ParentBinding::Unresolved{reason:if matches.is_empty(){UnresolvedReason::GeometryChangedAfterFit}else{UnresolvedReason::AmbiguousParent}}}
        else{let p=matches[0];used.push(p.parent_index);match &p.source{
            None=>ParentBinding::SyntheticClosure{parent_index:p.parent_index},
            Some(s) if s.first_sample<=s.last_sample&&s.last_sample<s.samples.len()=>ParentBinding::ExactRoundedParent{parent_index:p.parent_index,source:s.clone()},
            Some(_)=>ParentBinding::Unresolved{reason:UnresolvedReason::InvalidSourceInterval},
        }};
        let status=match binding {
            ParentBinding::ExactRoundedParent{..}=>BindingStatus::UnresolvedRawInterval,
            ParentBinding::SyntheticClosure{..}=>BindingStatus::Synthetic,
            ParentBinding::Unresolved{..}=>BindingStatus::UnresolvedGeometry,
        };
        emitted.push(EmittedSpanRecord{emitted_index,
            span_id:format!("ring:{captured_ring_index}/span:{emitted_index}"),
            role:SpanRole::Unknown,status,start:current,span:span.clone(),binding});current=end(span);
    }
    let unmatched_parent_indices=parents.iter().filter(|p|!used.contains(&p.parent_index)).map(|p|p.parent_index).collect();
    RingProvenance{captured_ring_index,source_tile_pin:None,pre_emission:parents,emitted,unmatched_parent_indices,construction_status:"NOT_DERIVABLE: source roles/intent not supplied"}
}

/// Chief schema gate: fitted arc samples are not RAW raster intervals.
/// Until explicit raw-index binding and event roles exist, regions abstain.
pub fn region_ready(record:&RingProvenance)->bool {
    !record.emitted.is_empty() && record.emitted.iter().all(|s|
        s.status==BindingStatus::RawIntervalBound && s.role!=SpanRole::Unknown)
}

#[derive(Clone,Debug,PartialEq,Eq)]
pub struct RawArcInterval {
    pub captured_ring_index:usize,
    pub raw_point_count:usize,
    pub raw_start_choice:usize,
    pub first_raw_index:usize,
    pub last_raw_index:usize,
    pub reversed:bool,
    pub wraps:bool,
}
impl RawArcInterval {
    /// No match tolerance: recorded indices and traversal metadata must agree.
    pub fn valid(&self)->bool {
        self.raw_point_count>0 && self.raw_start_choice<self.raw_point_count
            && self.first_raw_index<self.raw_point_count && self.last_raw_index<self.raw_point_count
            && self.wraps==if self.reversed {self.last_raw_index>self.first_raw_index}
                else {self.last_raw_index<self.first_raw_index}
    }
}
/// Retained raw identities are recorded by capture, never searched by geometry.
/// Equal start/end needs an explicit full-ring description, so this function
/// abstains rather than guessing whether it means a point or a wrapped ring.
pub fn recorded_raw_interval(lineage:&crate::capture::CaptureLineage,first:usize,last:usize)
    ->Option<RawArcInterval> {
    let (&a,&b)=(lineage.retained_raw_indices.get(first)?,lineage.retained_raw_indices.get(last)?);
    if a==b {return None;}
    let interval=RawArcInterval{captured_ring_index:lineage.captured_ring_index,
        raw_point_count:lineage.raw_point_count,raw_start_choice:lineage.raw_start_index,
        first_raw_index:a,last_raw_index:b,reversed:lineage.reversed,
        wraps:if lineage.reversed{b>a}else{b<a}};
    interval.valid().then_some(interval)
}
