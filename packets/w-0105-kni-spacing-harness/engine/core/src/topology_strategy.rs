//! Required interface for exact-predicate/curved-ring topology work, unimplemented.
//! No strategy result is silently converted to admission, output or a junction choice.
use crate::decision_evidence_envelope::PinClaim;
use crate::reference_slice::{Point,ReferenceRing};

#[derive(Clone, Debug)]
pub struct TopologySubject {
    pub source_pin: PinClaim,
    pub frame_revision: PinClaim,
    pub ring_index: usize,
    pub ring: ReferenceRing,
}

#[derive(Clone, Debug)]
pub enum OrientationClaim { Clockwise,CounterClockwise,Collinear,Unresolved }

#[derive(Clone, Debug)]
pub enum IntersectionClaim {
    Disjoint,
    ProperCrossing,
    Touching,
    CoincidentOverlap,
    Unresolved,
}

#[derive(Clone, Debug)]
pub enum ContainmentClaim { StrictlyContained,Outside,BoundaryContact,Unresolved }

#[derive(Clone, Debug)]
pub struct PredicateObservation<T> {
    pub result_claim: T,
    pub strategy_revision: PinClaim,
    pub source_refs: Vec<PinClaim>,
    pub evidence_refs: Vec<PinClaim>,
    pub unmet_requirements: Vec<String>,
}

/// Implementation must declare numeric/degenerate/curve coverage explicitly.
#[derive(Clone, Debug)]
pub struct StrategyRequirements {
    pub exact_binary64_input_interpretation: String,
    pub orientation_predicate_method: String,
    pub intersection_root_isolation_method: Option<String>,
    pub boundary_and_coincident_curve_rules: String,
    pub source_parameter_interval_binding: String,
    pub evidence_verification_rule: String,
    pub unimplemented_cases: Vec<String>,
}

pub trait TopologyPredicateStrategy {
    fn revision(&self) -> &PinClaim;
    fn requirements(&self) -> &StrategyRequirements;
    fn orientation(&self,a:Point,b:Point,c:Point) -> PredicateObservation<OrientationClaim>;
    fn ring_intersections(&self,first:&TopologySubject,second:&TopologySubject) -> PredicateObservation<IntersectionClaim>;
    fn ring_containment(&self,inner:&TopologySubject,outer:&TopologySubject) -> PredicateObservation<ContainmentClaim>;
}

// No implementation or default strategy is supplied. Binary64 observations stay
// explicitly limited; downstream must not infer exactness from this trait name.
