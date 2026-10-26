//! Candidate fitter readiness records only, no solve or numeric default.
use crate::decision_evidence_envelope::PinClaim;
use crate::reference_slice::Point;
#[derive(Clone,Debug)]
pub struct FitterRequirements {
 pub mechanism_source:PinClaim,
 pub normal_equations:Option<PinClaim>,
 pub sample_weight_definition:Option<PinClaim>,
 pub tangent_convention:Option<PinClaim>,
 pub error_measure:Option<PinClaim>,
 pub tolerance_calibration:Option<PinClaim>,
 pub determinant_policy:Option<PinClaim>,
 pub reparameterization_rule:Option<PinClaim>,
 pub termination_policy:Option<PinClaim>,
 pub split_seam_policy:Option<PinClaim>,
}
#[derive(Clone,Debug,PartialEq)]
pub enum UnboundRequirement {NormalEquations,SampleWeights,TangentConvention,ErrorMeasure,ToleranceCalibration,DeterminantPolicy,Reparameterization,Termination,SplitSeam}
/// Presence is storage readiness only, never authentication/qualification/adoption.
pub fn missing(r:&FitterRequirements)->Vec<UnboundRequirement>{
 let fields=[(&r.normal_equations,UnboundRequirement::NormalEquations),(&r.sample_weight_definition,UnboundRequirement::SampleWeights),(&r.tangent_convention,UnboundRequirement::TangentConvention),(&r.error_measure,UnboundRequirement::ErrorMeasure),(&r.tolerance_calibration,UnboundRequirement::ToleranceCalibration),(&r.determinant_policy,UnboundRequirement::DeterminantPolicy),(&r.reparameterization_rule,UnboundRequirement::Reparameterization),(&r.termination_policy,UnboundRequirement::Termination),(&r.split_seam_policy,UnboundRequirement::SplitSeam)];
 fields.into_iter().filter_map(|(pin,kind)|if pin.is_none(){Some(kind)}else{None}).collect()
}
#[derive(Clone,Debug)]
pub struct SourceFitRun {pub source_pin:PinClaim,pub frame_pin:PinClaim,pub ring_index:usize,pub span_indices:Vec<usize>,pub points:Vec<Point>,pub start_tangent:Point,pub end_tangent:Point,pub tangent_binding:PinClaim,pub seam_binding:PinClaim}
#[derive(Clone,Debug,PartialEq)]
pub enum RunInputBoundary {NoSamples,NonFinitePoint,NonFiniteTangent,ZeroTangent,MissingSourceSpanIndices}
/// Finiteness/explicit input checks only. No normalization or geometric guess.
pub fn inspect_run(run:&SourceFitRun)->Vec<RunInputBoundary>{let mut out=Vec::new();if run.points.is_empty(){out.push(RunInputBoundary::NoSamples);}if run.span_indices.is_empty(){out.push(RunInputBoundary::MissingSourceSpanIndices);}if run.points.iter().any(|p|!p.x.is_finite()||!p.y.is_finite()){out.push(RunInputBoundary::NonFinitePoint);}if [run.start_tangent,run.end_tangent].iter().any(|p|!p.x.is_finite()||!p.y.is_finite()){out.push(RunInputBoundary::NonFiniteTangent);}if [run.start_tangent,run.end_tangent].iter().any(|p|p.x==0.&&p.y==0.){out.push(RunInputBoundary::ZeroTangent);}out}
#[derive(Clone,Debug)]
pub struct RunIntake {pub retained_source:SourceFitRun,pub boundaries:Vec<RunInputBoundary>}
/// Every sibling run inspected independently; no aggregate rejection/hidden drop.
pub fn inspect_runs(runs:Vec<SourceFitRun>)->Vec<RunIntake>{runs.into_iter().map(|run|{let boundaries=inspect_run(&run);RunIntake{retained_source:run,boundaries}}).collect()}
/// NE-2 economy-search readiness records. Presence is storage readiness
/// only, never authentication/qualification/adoption of the mechanic.
#[derive(Clone,Debug)]
pub struct EconomyRequirements {
 /// Corner screen: kink-visibility threshold derivation (band/local-step).
 pub corner_visibility_derivation:Option<PinClaim>,
 /// Collinear merge: theta derivation (caller budget, chord lengths) and
 /// merged-line budget check rule.
 pub merge_tolerance_derivation:Option<PinClaim>,
 /// C->L degrade: degrade_eps derivation (min of acquisition band and
 /// caller accept-gate distance).
 pub degrade_epsilon_derivation:Option<PinClaim>,
 /// Post-fit zero-length tidy: the drop rule and its typed ledger record.
 pub zero_length_tidy_rule:Option<PinClaim>,
 /// Objective currency binding: the source_step measurement the NE-1
 /// band-squared currency is derived from.
 pub objective_currency_binding:Option<PinClaim>,
}
#[derive(Clone,Debug,PartialEq)]
pub enum UnboundEconomyRequirement {CornerVisibility,MergeTolerance,DegradeEpsilon,ZeroLengthTidy,ObjectiveCurrency}
/// Presence is storage readiness only, never adoption.
pub fn missing_economy(r:&EconomyRequirements)->Vec<UnboundEconomyRequirement>{
 let fields=[(&r.corner_visibility_derivation,UnboundEconomyRequirement::CornerVisibility),(&r.merge_tolerance_derivation,UnboundEconomyRequirement::MergeTolerance),(&r.degrade_epsilon_derivation,UnboundEconomyRequirement::DegradeEpsilon),(&r.zero_length_tidy_rule,UnboundEconomyRequirement::ZeroLengthTidy),(&r.objective_currency_binding,UnboundEconomyRequirement::ObjectiveCurrency)];
 fields.into_iter().filter_map(|(pin,kind)|if pin.is_none(){Some(kind)}else{None}).collect()
}
#[cfg(test)]
mod economy_requirements_tests {
 use super::*;
 fn pin()->PinClaim{PinClaim{algorithm:"fixture".into(),claimed_digest:"unverified".into(),subject_ref:"source".into()}}
 fn empty()->EconomyRequirements{EconomyRequirements{corner_visibility_derivation:None,merge_tolerance_derivation:None,degrade_epsilon_derivation:None,zero_length_tidy_rule:None,objective_currency_binding:None}}
 #[test]fn all_five_requirements_start_unbound(){
  assert_eq!(missing_economy(&empty()).len(),5);
 }
 #[test]fn pins_fill_only_their_own_slot(){
  let mut r=empty();r.degrade_epsilon_derivation=Some(pin());
  let m=missing_economy(&r);
  assert_eq!(m.len(),4);
  assert!(!m.contains(&UnboundEconomyRequirement::DegradeEpsilon));
  assert!(m.contains(&UnboundEconomyRequirement::CornerVisibility));
 }
}
