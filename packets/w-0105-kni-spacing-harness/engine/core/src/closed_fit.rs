//! Engineering child-local recursion and exact seam assembly, all NOT_RUN.
//! Not FL seam reconstruction or unchanged Schneider recursion.
use crate::cubic_fit::{adjacent_chord_tangents,fit_run,FitOutcome,FitPolicy};
use crate::decision_evidence_envelope::PinClaim;
use crate::fitter_requirements::{inspect_run,SourceFitRun};
use crate::reference_slice::{Point,ReferenceRing,Span};
#[derive(Clone,Debug)]
pub struct ClosureAlias {pub final_source_index:usize,pub first_source_index:usize,pub binding:PinClaim}
#[derive(Clone,Debug)]
pub struct RingFitInput {pub runs:Vec<SourceFitRun>,pub closure_alias:ClosureAlias}
#[derive(Clone,Debug)]
pub struct FittedPiece {pub run_index:usize,pub local_start:usize,pub local_end:usize,pub controls:[Point;4]}
#[derive(Clone,Debug,PartialEq)]
pub enum AssemblyBoundary {InvalidPolicy,NoRuns,InvalidRun{run:usize},BindingMismatch{run:usize},JoinMismatch{run:usize},SourceJoinMismatch{run:usize},ClosureMismatch,ClosureAliasMismatch,UnresolvedChild{run:usize,start:usize,end:usize}}
#[derive(Clone,Debug)]
pub struct RingFitPreparation {pub retained_source:RingFitInput,pub pieces:Vec<FittedPiece>,pub boundaries:Vec<AssemblyBoundary>,pub closed_candidate:Option<ReferenceRing>}
fn pin_eq(a:&PinClaim,b:&PinClaim)->bool{a.algorithm==b.algorithm&&a.claimed_digest==b.claimed_digest&&a.subject_ref==b.subject_ref}
fn finite(p:Point)->bool{p.x.is_finite()&&p.y.is_finite()}
/// No inherited or sibling tangents. Stack order is left child then right.
fn fit_children(run:usize,points:&[Point],policy:&FitPolicy,pieces:&mut Vec<FittedPiece>,boundaries:&mut Vec<AssemblyBoundary>){
 if points.len()<3{boundaries.push(AssemblyBoundary::UnresolvedChild{run,start:0,end:points.len().saturating_sub(1)});return;}
 let mut stack=vec![(0,points.len()-1)];
 while let Some((start,end))=stack.pop(){let subset=&points[start..=end];
  let Some((left,right))=adjacent_chord_tangents(subset)else{boundaries.push(AssemblyBoundary::UnresolvedChild{run,start,end});continue;};
  if subset.len()==2{let chord=(subset[1].x-subset[0].x).hypot(subset[1].y-subset[0].y);let distance=chord/3.;let q=[subset[0],Point{x:subset[0].x+left.x*distance,y:subset[0].y+left.y*distance},Point{x:subset[1].x+right.x*distance,y:subset[1].y+right.y*distance},subset[1]];if q.iter().all(|p|finite(*p)){pieces.push(FittedPiece{run_index:run,local_start:start,local_end:end,controls:q});}else{boundaries.push(AssemblyBoundary::UnresolvedChild{run,start,end});}continue;}
  match fit_run(subset,left,right,policy){
   FitOutcome::Fitted{controls,..}=>pieces.push(FittedPiece{run_index:run,local_start:start,local_end:end,controls}),
   FitOutcome::SplitUnresolved{sample_index:Some(i),..} if i>0&&i<subset.len()-1=>{let mid=start+i;stack.push((mid,end));stack.push((start,mid));},
   _=>boundaries.push(AssemblyBoundary::UnresolvedChild{run,start,end}),
  }
 }
}
/// Ordered runs and explicit aliases supplied by caller, never rotated/closed implicitly.
/// Pin comparisons compare stored identities only, not authentication or custody.
pub fn prepare_closed(input:RingFitInput,policy:&FitPolicy)->RingFitPreparation{
 let mut pieces=Vec::new();let mut boundaries=Vec::new();
 if !policy.squared_error.is_finite()||policy.squared_error<0.{boundaries.push(AssemblyBoundary::InvalidPolicy);return RingFitPreparation{retained_source:input,pieces,boundaries,closed_candidate:None};}
 if input.runs.is_empty(){boundaries.push(AssemblyBoundary::NoRuns);}else{
  let first=&input.runs[0];
  for(i,run)in input.runs.iter().enumerate(){
   if !inspect_run(run).is_empty()||run.span_indices.len()!=run.points.len(){boundaries.push(AssemblyBoundary::InvalidRun{run:i});continue;}
   if run.ring_index!=first.ring_index||!pin_eq(&run.source_pin,&first.source_pin)||!pin_eq(&run.frame_pin,&first.frame_pin){boundaries.push(AssemblyBoundary::BindingMismatch{run:i});}
   if i>0{let prev=&input.runs[i-1];if prev.points.last()!=run.points.first(){boundaries.push(AssemblyBoundary::JoinMismatch{run:i});}if prev.span_indices.last()!=run.span_indices.first(){boundaries.push(AssemblyBoundary::SourceJoinMismatch{run:i});}}
   fit_children(i,&run.points,policy,&mut pieces,&mut boundaries);
  }
  let last=input.runs.last().unwrap();
  if last.points.last()!=first.points.first()||first.points.is_empty(){boundaries.push(AssemblyBoundary::ClosureMismatch);}
  if last.span_indices.last()!=Some(&input.closure_alias.final_source_index)||first.span_indices.first()!=Some(&input.closure_alias.first_source_index){boundaries.push(AssemblyBoundary::ClosureAliasMismatch);}
 }
 // Initial runs need three samples; only split children use the two-point base case.
 let closed_candidate=if boundaries.is_empty()&&!pieces.is_empty(){let start=pieces[0].controls[0];let mut spans=Vec::new();let mut prior=start;let mut valid=true;for piece in &pieces{if piece.controls[0]!=prior{valid=false;}prior=piece.controls[3];spans.push(Span::Cubic{control_one:piece.controls[1],control_two:piece.controls[2],end:prior});}if prior!=start{valid=false;}if valid{Some(ReferenceRing{start,spans})}else{boundaries.push(AssemblyBoundary::ClosureMismatch);None}}else{None};
 RingFitPreparation{retained_source:input,pieces,boundaries,closed_candidate}
}
