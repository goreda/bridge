//! Two proposal-derived domain adapters, not fitters or ranking policies.
use crate::decision_evidence_envelope::PinClaim;
use crate::reference_slice::ReferenceGlyph;

#[derive(Clone, Debug)]
pub enum DomainMethod { LandmarkRegions, WholeContour }

#[derive(Clone, Debug)]
pub enum RankingPolicyClaim { R1, R2, GpTwo, ExplicitNew { name: String } }

#[derive(Clone, Debug)]
pub struct PolicySlot {
    pub domain_method: DomainMethod,
    pub domain_method_source: PinClaim,
    pub ranking: Option<RankingPolicyClaim>,
    pub ranking_binding: Option<PinClaim>,
    pub calibration_revision: Option<PinClaim>,
    pub holdout_evidence: Vec<PinClaim>,
}

#[derive(Clone, Debug)]
pub struct SourceLandmarks {
    pub ring_index: usize,
    /// Source endpoint indices, no algorithm-generated junction/corner guesses.
    pub endpoint_indices: Vec<usize>,
    pub source_evidence: PinClaim,
}

#[derive(Clone, Debug)]
pub enum CandidateRepresentation { Polygonal, Bezier, Hybrid }

#[derive(Clone, Debug)]
pub struct CandidateDomain {
    pub ring_index: usize,
    pub start_endpoint: usize,
    pub end_endpoint: usize,
    pub wraps_source_seam: bool,
    pub representations: Vec<CandidateRepresentation>,
}

#[derive(Clone, Debug)]
pub enum DomainBoundary {
    MissingLandmarks { ring_index: usize },
    InvalidLandmarkIndex { ring_index: usize },
    EmptySourceRing { ring_index: usize },
    AmbiguousLandmarkSources { ring_index: usize },
    DuplicateLandmarkAliases { ring_index: usize },
    JunctionConnectionUnresolved,
    RankingPolicyUnbound,
    QualifiedCalibrationUnverified,
}

#[derive(Clone, Debug)]
pub struct DomainPreparation {
    pub landmark_orders: Vec<LandmarkOrder>,
    pub domains: Vec<CandidateDomain>,
    pub unresolved: Vec<DomainBoundary>,
}

fn all_representations() -> Vec<CandidateRepresentation> {
    vec![CandidateRepresentation::Polygonal, CandidateRepresentation::Bezier, CandidateRepresentation::Hybrid]
}

/// Emits only requested comparison domains; qualification/geometry remain absent.
pub fn prepare_domains(glyph: &ReferenceGlyph, landmarks: &[SourceLandmarks], policy: &PolicySlot) -> DomainPreparation {
    let mut domains = Vec::new();
    let mut landmark_orders=Vec::new();
    let mut unresolved = vec![DomainBoundary::QualifiedCalibrationUnverified];
    if policy.ranking.is_none() || policy.ranking_binding.is_none() {
        unresolved.push(DomainBoundary::RankingPolicyUnbound);
    }
    if glyph.declared_junction_decision_required { unresolved.push(DomainBoundary::JunctionConnectionUnresolved); }
    for (ring_index, ring) in glyph.rings.iter().enumerate() {
        if ring.spans.is_empty(){unresolved.push(DomainBoundary::EmptySourceRing{ring_index});continue;}
        match policy.domain_method {
            DomainMethod::WholeContour => domains.push(CandidateDomain {
                ring_index, start_endpoint: 0, end_endpoint: ring.spans.len(),
                wraps_source_seam: true, representations: all_representations(),
            }),
            DomainMethod::LandmarkRegions => {
                let Some(source) = landmarks.iter().find(|l| l.ring_index == ring_index) else {
                    unresolved.push(DomainBoundary::MissingLandmarks { ring_index }); continue;
                };
                let same_pin=|a:&PinClaim,b:&PinClaim|a.algorithm==b.algorithm&&a.claimed_digest==b.claimed_digest&&a.subject_ref==b.subject_ref;
                let canonical=|l:&SourceLandmarks|{let mut v=l.endpoint_indices.clone();v.sort_unstable();v.dedup();v};
                if landmarks.iter().filter(|l|l.ring_index==ring_index).any(|l|!same_pin(&l.source_evidence,&source.source_evidence)||canonical(l)!=canonical(source)){unresolved.push(DomainBoundary::AmbiguousLandmarkSources{ring_index});continue;}
                let mut indices = source.endpoint_indices.clone();
                indices.sort_unstable(); indices.dedup();
                if indices.len()!=source.endpoint_indices.len(){unresolved.push(DomainBoundary::DuplicateLandmarkAliases{ring_index});}
                landmark_orders.push(LandmarkOrder{ring_index,raw_source_indices:source.endpoint_indices.clone(),derived_cyclic_indices:indices.clone()});
                if indices.iter().any(|i| *i >= ring.spans.len()) {
                    unresolved.push(DomainBoundary::InvalidLandmarkIndex { ring_index }); continue;
                }
                if indices.len() < 2 { unresolved.push(DomainBoundary::MissingLandmarks { ring_index }); continue; }
                for index in 0..indices.len() {
                    domains.push(CandidateDomain {
                        ring_index, start_endpoint: indices[index], end_endpoint: indices[(index+1)%indices.len()],
                        wraps_source_seam: index+1 == indices.len(), representations: all_representations(),
                    });
                }
            },
        }
    }
    DomainPreparation { landmark_orders,domains, unresolved }
}

#[derive(Clone,Debug)]
pub struct LandmarkOrder {pub ring_index:usize,pub raw_source_indices:Vec<usize>,pub derived_cyclic_indices:Vec<usize>}
#[derive(Clone,Debug)]
pub struct ClosureAliasBinding {pub ring_index:usize,pub source_evidence:PinClaim,pub alias_endpoint:usize,pub canonical_endpoint:usize}
/// Alias only under explicit caller source-correspondence binding, pins not authenticated.
pub fn prepare_domains_bound(glyph:&ReferenceGlyph,landmarks:&[SourceLandmarks],policy:&PolicySlot,bindings:&[ClosureAliasBinding])->DomainPreparation{
 let mut mapped=landmarks.to_vec();
 for l in &mut mapped{if let Some(ring)=glyph.rings.get(l.ring_index){let matches:Vec<_>=bindings.iter().filter(|b|b.ring_index==l.ring_index&&b.alias_endpoint==ring.spans.len()&&b.canonical_endpoint==0&&b.source_evidence.algorithm==l.source_evidence.algorithm&&b.source_evidence.claimed_digest==l.source_evidence.claimed_digest&&b.source_evidence.subject_ref==l.source_evidence.subject_ref).collect();if matches.len()==1{for i in &mut l.endpoint_indices{if *i==ring.spans.len(){*i=0;}}}}}
 let mut result=prepare_domains(glyph,&mapped,policy);
 for order in &mut result.landmark_orders{if let Some(l)=landmarks.iter().find(|l|l.ring_index==order.ring_index){order.raw_source_indices=l.endpoint_indices.clone();}}
 result
}
