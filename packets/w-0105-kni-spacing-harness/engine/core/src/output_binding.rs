//! Explicit cross-output frame/fill declaration, no hidden transformation.
use crate::decision_evidence_envelope::PinClaim;
#[derive(Clone,Copy,Debug,PartialEq)]
pub enum AxisDirection { Up,Down }
#[derive(Clone,Debug)]
pub struct FrameFillBinding {pub source_frame:PinClaim,pub target_frame:PinClaim,pub correspondence:PinClaim,pub source_units_per_em:u16,pub target_units_per_em:u16,pub source_y:AxisDirection,pub target_y:AxisDirection,pub source_fill:crate::cff_fill::SourceFill}
#[derive(Clone,Debug,PartialEq)]
pub enum BindingObservation {DirectCoordinateFrameDeclared,ExplicitTransformRequired,FillEquivalenceUnresolved}
pub fn inspect(binding:&FrameFillBinding)->Vec<BindingObservation>{
 let mut out=vec![if binding.source_units_per_em==binding.target_units_per_em&&binding.source_y==binding.target_y{BindingObservation::DirectCoordinateFrameDeclared}else{BindingObservation::ExplicitTransformRequired}];
 if binding.source_fill!=crate::cff_fill::SourceFill::EvenOdd{out.push(BindingObservation::FillEquivalenceUnresolved);}out
}
// Correspondence pins are unverified declarations, never identity proof.
// EvenOdd intent does not prove overlap/topology or rendering compatibility.
