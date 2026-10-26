//! Schneider-derived engineering method, NOT FL equivalence.
//! Synthetic execution status: docs/engine/execution; not production acceptance.
use crate::reference_slice::Point;
#[derive(Clone,Debug)]
pub struct FitPolicy {pub squared_error:f64,pub max_refits:usize}
/// Why a fit ended unresolved after entering the refit loop: the derived
/// budget ran out, refit candidate generation failed, or a non-improving
/// candidate certified the best explainable state for these end tangents
/// (the improvement certificate). None: the loop was never entered.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum RefitStop {BudgetExhausted,CandidateFailed,CertifiedNoImprovement}
#[derive(Clone,Debug)]
pub enum FitOutcome {Fitted{controls:[Point;4],parameters:Vec<f64>,max_squared_error:f64},SplitUnresolved{sample_index:Option<usize>,stop:Option<RefitStop>},InvalidInput}
fn add(a:Point,b:Point)->Point{Point{x:a.x+b.x,y:a.y+b.y}}
fn sub(a:Point,b:Point)->Point{Point{x:a.x-b.x,y:a.y-b.y}}
fn scale(a:Point,k:f64)->Point{Point{x:a.x*k,y:a.y*k}}
fn dot(a:Point,b:Point)->f64{a.x*b.x+a.y*b.y}
fn finite(a:Point)->bool{a.x.is_finite()&&a.y.is_finite()}
fn unit(a:Point)->Option<Point>{let n=a.x.hypot(a.y);if !n.is_finite()||n==0.{None}else{let p=Point{x:a.x/n,y:a.y/n};if finite(p){Some(p)}else{None}}}
/// Named estimator only when explicitly selected by caller, inward at both ends.
pub fn adjacent_chord_tangents(points:&[Point])->Option<(Point,Point)>{if points.len()<2{return None;}Some((unit(sub(points[1],points[0]))?,unit(sub(points[points.len()-2],points[points.len()-1]))?))}
fn basis(t:f64)->[f64;4]{let v=1.-t;[v*v*v,3.*t*v*v,3.*t*t*v,t*t*t]}
fn evaluate(q:&[Point;4],t:f64)->Point{let b=basis(t);(0..4).fold(Point{x:0.,y:0.},|p,i|add(p,scale(q[i],b[i])))}
fn derivatives(q:&[Point;4],t:f64)->(Point,Point){let v=1.-t;let a=scale(sub(q[1],q[0]),3.);let b=scale(sub(q[2],q[1]),3.);let c=scale(sub(q[3],q[2]),3.);(add(add(scale(a,v*v),scale(b,2.*v*t)),scale(c,t*t)),add(scale(sub(b,a),2.*v),scale(sub(c,b),2.*t)))}
fn solve(points:&[Point],u:&[f64],left:Point,right:Point)->Option<[Point;4]>{
 let p0=points[0];let p3=*points.last()?;let(mut c00,mut c01,mut c11,mut x0,mut x1)=(0.,0.,0.,0.,0.);
 for(p,t)in points.iter().zip(u){let b=basis(*t);let a0=scale(left,b[1]);let a1=scale(right,b[2]);let r=sub(*p,add(scale(p0,b[0]+b[1]),scale(p3,b[2]+b[3])));c00+=dot(a0,a0);c01+=dot(a0,a1);c11+=dot(a1,a1);x0+=dot(a0,r);x1+=dot(a1,r);}
 let det=c00*c11-c01*c01;if !det.is_finite()||det<=0.{return None;}let a=(x0*c11-x1*c01)/det;let b=(c00*x1-c01*x0)/det;if !a.is_finite()||!b.is_finite()||a<=0.||b<=0.{return None;}
 let q=[p0,add(p0,scale(left,a)),add(p3,scale(right,b)),p3];if q.iter().all(|p|finite(*p)){Some(q)}else{None}
}
fn error(points:&[Point],u:&[f64],q:&[Point;4])->Option<(f64,usize)>{let mut max= -1.;let mut index=1;for i in 1..points.len()-1{let d=sub(evaluate(q,u[i]),points[i]);let e=dot(d,d);if !e.is_finite(){return None;}if e>max{max=e;index=i;}}Some((max.max(0.),index))}
// Pure full-Newton proposal. None never changes the caller's prior state.
fn newton_step(q:&[Point;4],point:Point,t:f64)->Option<f64>{
 let next=newton_step_raw(q,point,t)?;
 if !(0.0..=1.0).contains(&next){None}else{Some(next)}
}
fn proposed_parameters(points:&[Point],u:&[f64],q:&[Point;4])->Option<Vec<f64>>{
 let mut proposed=u.to_vec();
 for i in 1..points.len()-1{proposed[i]=newton_step(q,points[i],u[i])?;}
 if proposed.windows(2).any(|p|p[0]>p[1]){None}else{Some(proposed)}
}
// Compute a whole replacement before committing any prior-state field.
fn refitted_candidate(points:&[Point],u:&[f64],q:&[Point;4],left:Point,right:Point)->Option<(Vec<f64>,[Point;4],f64,usize)>{
 let proposed=proposed_parameters(points,u,q)?;
 let next=solve(points,&proposed,left,right)?;
 let(max,split)=error(points,&proposed,&next)?;
 Some((proposed,next,max,split))
}
/// Damped per-point Newton proposal (Schneider's graphics-gems fall-back):
/// the full-vector proposal is all-or-nothing - ONE footpoint whose Newton
/// step is non-finite, zero-denominator, or lands outside [0,1] discards the
/// whole refit (RefitStop::CandidateFailed). On short arcs sampled from a
/// noisy acquisition chain (photo/JPEG sources) that single bad step is the
/// common case, not the exception, and the arc is declared unresolvable
/// without ever trying the steps that DO converge. The damped proposal keeps
/// each converging step and clamps it into the open interval of its ORIGINAL
/// neighbours, so the result stays monotone by construction (u is sorted;
/// clamping u[i] into [u[i-1], u[i+1]] for every i keeps proposed[i] <=
/// proposed[i+1] since the bounds themselves are monotone in i). A point
/// whose step cannot be computed keeps its current parameter; a point with
/// no room to move (equal neighbours) keeps its current parameter. When no
/// point moves the proposal equals the input and the caller's improvement
/// certificate stops the loop honestly (CertifiedNoImprovement).
/// No thresholds: the clamp interval is the parameter's own neighbourhood.
fn proposed_parameters_damped(points:&[Point],u:&[f64],q:&[Point;4])->Option<Vec<f64>>{
 let mut proposed=u.to_vec();
 for i in 1..points.len()-1{
  let t=newton_step_raw(q,points[i],u[i])?;
  let lo=u[i-1];let hi=u[i+1];
  if hi<=lo{continue;}
  proposed[i]=t.clamp(lo,hi);
 }
 if proposed.windows(2).any(|p|p[0]>p[1]){None}else{Some(proposed)}
}
/// Raw Newton step without the [0,1] membership rejection: None only when the
/// step itself is not computable (non-finite or zero denominator). Range
/// handling belongs to the caller (strict reject for the full-vector path,
/// clamp for the damped path).
fn newton_step_raw(q:&[Point;4],point:Point,t:f64)->Option<f64>{
 let at=evaluate(q,t);let(d1,d2)=derivatives(q,t);let r=sub(at,point);
 let denominator=dot(d1,d1)+dot(r,d2);
 if !denominator.is_finite()||denominator==0.{return None;}
 let next=t-dot(r,d1)/denominator;
 if !next.is_finite(){None}else{Some(next)}
}
fn refitted_candidate_damped(points:&[Point],u:&[f64],q:&[Point;4],left:Point,right:Point)->Option<(Vec<f64>,[Point;4],f64,usize)>{
 let proposed=proposed_parameters_damped(points,u,q)?;
 let next=solve(points,&proposed,left,right)?;
 let(max,split)=error(points,&proposed,&next)?;
 Some((proposed,next,max,split))
}
fn ceil_log2(x: usize) -> usize { if x <= 1 { 0 } else { usize::BITS as usize - (x - 1).leading_zeros() as usize } }
/// Refit budget derived from the arc's own sample count, not a global
/// literal. The refit loop is full-vector Newton on the sample footpoints;
/// Newton converges quadratically (correct digits double per step). The
/// initial parameter misplacement is order-unity in normalized u, and the
/// finest target that is measurable on this data is one sample spacing,
/// 1/(n-1): resolving parameters below the spacing of the samples they
/// belong to changes nothing the residual can observe. The digits required
/// are therefore log2(n-1); the steps to double into them are
/// ceil(log2(ceil(log2(n-1)))), plus one final step whose only job is to be
/// observed NOT improving (the improvement certificate in the loop), so the
/// stop is certified rather than truncated mid-descent.
fn derived_reparam_budget(n_samples: usize) -> usize {
    let digits = ceil_log2(n_samples.saturating_sub(1)).max(1);
    ceil_log2(digits) + 1
}

/// Source-bound open run. Splitting is requested, never silently fabricated here.
pub fn fit_run(points:&[Point],left:Point,right:Point,policy:&FitPolicy)->FitOutcome{
 fit_run_observed(points,left,right,policy,|_,_|{})
}
/// Damped-fit variant of `fit_run`: identical dual-init, solve, plausibility
/// ranking, budget and improvement certificate; the ONLY difference is the
/// reparameterization proposal (damped per-point clamped Newton instead of
/// the all-or-nothing full vector, see proposed_parameters_damped). Intended
/// for callers that re-fit an arc the primary fitter already declared
/// unresolved: the policy (incl. its accept threshold) is the caller's own,
/// and every emitted result still passes the caller's downstream gates.
pub fn fit_run_damped(points:&[Point],left:Point,right:Point,policy:&FitPolicy)->FitOutcome{
 fit_run_inner(points,left,right,policy,|_,_|{},true)
}
// Private observer records attempts against immutable prior parameters for unit tests.
fn fit_run_observed<F:FnMut(usize,&[f64])>(points:&[Point],left:Point,right:Point,policy:&FitPolicy,observe:F)->FitOutcome{
 fit_run_inner(points,left,right,policy,observe,false)
}
fn fit_run_inner<F:FnMut(usize,&[f64])>(points:&[Point],left:Point,right:Point,policy:&FitPolicy,mut observe:F,damped:bool)->FitOutcome{
 if points.len()<3{return FitOutcome::SplitUnresolved{sample_index:None,stop:None};}
 if !points.iter().all(|p|finite(*p))||!policy.squared_error.is_finite()||policy.squared_error<0.{return FitOutcome::InvalidInput;}
 let(Some(left),Some(right))=(unit(left),unit(right))else{return FitOutcome::InvalidInput;};
 // Initial parameter map: dual-init argmin over the two derived maps.
 // Derivation: the acquisition chain samples the contour at arc-length-uniform
 // steps (iso-chain edges are pixel cells), so the ideal initial map is
 // normalized arc length. A chord-length increment underestimates arc length
 // where curvature is high: for local curvature k and step ds the chord is
 // ds*(1 - (k*ds)^2/24 + O((k*ds)^4)), a distortion ORDER-(k*ds)^2 biased
 // against exactly the regions the fit must resolve. The square-root chord
 // deviates from sqrt(ds) by (k*ds)^2/48: half the distortion and in the
 // opposite sign, so high-curvature stretches receive MORE parameter
 // resolution, not less (Lee 1989, "Choosing nodes in parametric curve
 // interpolation": the centripetal model is the derived choice for data with
 // strong curvature variation; uniform sampling is the degenerate case of
 // both).
 // Addendum (the k->0 corner): as local curvature vanishes the chord
 // increment IS the exact arc-length map (chord -> ds), while the
 // square-root chord keeps a systematic sqrt distortion of the same order.
 // On short, low-curvature arcs the chord map is therefore the exact model
 // and the centripetal map the approximation; on strong curvature variation
 // the ordering flips (above). Neither map dominates across the curvature
 // range, and a curvature threshold would be an untuned constant, so the
 // initial solve runs under BOTH maps and the candidate with the smaller
 // policy metric (max squared error) enters the refit loop; an exact tie
 // keeps the centripetal candidate (the incumbent, and the derived choice
 // under curvature variation). Monotonicity of both maps is preserved
 // (identity and sqrt are monotone), so each is a legal parameterization.
 // The Newton refits below own exact footpoints; the maps only have to
 // start them inside the convergence basin - running both and keeping the
 // argmin removes the basin-choice failure mode without a threshold.
 let mut u_chord=vec![0.];let mut u_cent=vec![0.];
 for i in 1..points.len(){let chord=sub(points[i],points[i-1]);let d=chord.x.hypot(chord.y);let a=u_chord[i-1]+d;let b=u_cent[i-1]+d.sqrt();if !a.is_finite()||!b.is_finite(){return FitOutcome::InvalidInput;}u_chord.push(a);u_cent.push(b);}
 let mut solved=0usize;
 let mut cands:Vec<(Vec<f64>,[Point;4],f64,usize,bool,f64)>=Vec::new();
 // Centripetal first: the incumbent keeps exact ties (strict < below).
 for u in [&mut u_cent,&mut u_chord]{
  let total=*u.last().unwrap();if total==0.{return FitOutcome::InvalidInput;}for t in u.iter_mut(){*t/=total;}u[0]=0.;let last=u.len()-1;u[last]=1.;
  let Some(q)=solve(points,u,left,right)else{continue};solved+=1;
  let Some((max,split))=error(points,u,&q)else{continue};
  // Plausibility gate (same capture_fit::plausible rule the pipeline
  // applies post-fit; no new constants): an implausible solve is an
  // overshooting curve whose low error measures geometry the caller will
  // reject, so it must not win the argmin against a plausible candidate.
  let plaus=crate::capture_fit::plausible(points,&q);
  // Ranking metric: the caller's own accept gate (capture_fit::dense_gate,
  // single source of the two-sided dense excursion). The sampled max error
  // is blind between sample points, where a wrong-basin start already bows;
  // the dense excursion is what the fitted curve will actually be judged by.
  let(dense,_)=crate::capture_fit::dense_gate(&q,points);
  // The dense value ranks the candidates only; the stored error stays the
  // sampled max squared error so the refit loop below keeps its units and
  // its improvement certificate.
  cands.push((u.clone(),q,max,split,plaus,dense));
 }
 let pick=match cands.iter().filter(|c|c.4).min_by(|a,b|a.5.partial_cmp(&b.5).unwrap()){
  Some(c)=>Some(c.clone()),
  // Neither solve is plausible: the error metric would rank curves the
  // caller rejects either way, so the incumbent order decides
  // (centripetal, which ran first) - same rule as an exact tie.
  None=>cands.first().cloned(),
 };
 let(mut u,mut q,mut max,mut split)=match pick{
  Some(c)=>(c.0,c.1,c.2,c.3),
  None=>return FitOutcome::SplitUnresolved{sample_index:if solved==0{initial_split(points)}else{None},stop:None},
 };
 // Effective refit budget: the caller's declared cap, bounded further by the
 // arc's own geometry (derived_reparam_budget). The derived budget is what
 // quadratic Newton convergence can spend usefully; past it, further refits
 // move parameters by less than one sample spacing - unmeasurable on this
 // data, so the loop must not burn the caller's cap chasing it.
 let budget=policy.max_refits.min(derived_reparam_budget(points.len()));
 let mut stop=RefitStop::BudgetExhausted;
 for attempt in 0..=budget{
  if max<=policy.squared_error{return FitOutcome::Fitted{controls:q,parameters:u,max_squared_error:max};}if attempt==budget{break;}
  observe(attempt,&u);
  let candidate=if damped{refitted_candidate_damped(points,&u,&q,left,right)}else{refitted_candidate(points,&u,&q,left,right)};
  let Some((proposed,next,next_max,next_split))=candidate else{stop=RefitStop::CandidateFailed;break;};
  // Improvement certificate: a refit is committed only while it strictly
  // reduces the objective it is asked to minimize. Committing a worsening
  // candidate (the prior unconditional accept) ratchets the residual upward
  // and burns budget; a non-improving step certifies that this cubic, with
  // these end tangents, has reached its best explainable state - the honest
  // answer is to stop and let the caller split, not to keep iterating.
  if next_max>=max{stop=RefitStop::CertifiedNoImprovement;break;};u=proposed;q=next;max=next_max;split=next_split;
 }
 FitOutcome::SplitUnresolved{sample_index:Some(split),stop:Some(stop)}
}

/// Parent engineering choice: largest chord gap, earlier ties, internal index.
pub fn initial_split(points:&[Point])->Option<usize>{
 if points.len()<3{return None;}let mut largest= -1.;let mut gap=0;
 for i in 0..points.len()-1{let d=sub(points[i+1],points[i]);let length=d.x.hypot(d.y);if !length.is_finite(){return None;}if length>largest{largest=length;gap=i;}}
 Some(if gap+1==points.len()-1{gap}else{gap+1})
}
#[derive(Clone,Debug)]
pub struct BoundFitCandidate {pub retained_source:crate::fitter_requirements::SourceFitRun,pub boundaries:Vec<crate::fitter_requirements::RunInputBoundary>,pub outcome:FitOutcome}
/// Preserve source/frame/span/tangent/seam claims and process siblings independently.
pub fn fit_bound_runs(runs:Vec<crate::fitter_requirements::SourceFitRun>,policy:&FitPolicy)->Vec<BoundFitCandidate>{runs.into_iter().map(|run|{let boundaries=crate::fitter_requirements::inspect_run(&run);let outcome=if boundaries.is_empty(){fit_run(&run.points,run.start_tangent,run.end_tangent,policy)}else{FitOutcome::InvalidInput};BoundFitCandidate{retained_source:run,boundaries,outcome}}).collect()}

#[cfg(test)]
mod guard_tests {
 use super::*;
 fn p(x:f64,y:f64)->Point{Point{x,y}}
 fn linear()->[Point;4]{[p(0.,0.),p(1./3.,0.),p(2./3.,0.),p(1.,0.)]}
 #[test]fn full_newton_includes_residual_second_derivative(){let q=[p(0.,0.),p(1./3.,0.),p(2./3.,1./3.),p(1.,1.)];let t=newton_step(&q,p(0.5,0.),0.5).unwrap();assert!((t-0.4).abs()<1e-14);assert!((t-0.375).abs()>0.01);}
 #[test]fn zero_denominator_rejects_without_prior_mutation(){let q=[p(0.,0.);4];let u=vec![0.,0.5,1.];let saved=u.clone();assert!(proposed_parameters(&[p(0.,0.),p(1.,1.),p(0.,0.)],&u,&q).is_none());assert_eq!(u,saved);}
 #[test]fn nonfinite_denominator_rejects(){let q=[p(f64::MAX,f64::MAX);4];assert!(newton_step(&q,p(-f64::MAX,0.),0.5).is_none());}
 #[test]fn outside_parameter_rejects_no_clamp(){assert!(newton_step(&linear(),p(2.,0.),0.5).is_none());}
 #[test]fn nonmonotone_parameters_reject_without_reorder(){let u=vec![0.,0.25,0.75,1.];let points=[p(0.,0.),p(0.8,0.),p(0.2,0.),p(1.,0.)];assert!(proposed_parameters(&points,&u,&linear()).is_none());assert_eq!(u,vec![0.,0.25,0.75,1.]);}
 #[test]fn sampled_max_error_tie_keeps_earlier_index(){let q=[p(0.,0.);4];assert_eq!(error(&[p(0.,0.),p(1.,0.),p(-1.,0.),p(0.,0.)],&[0.,0.25,0.75,1.],&q),Some((1.,1)));}
 #[test]fn tiny_vector_normalization_is_finite(){let smallest=f64::from_bits(1);assert_eq!(unit(p(smallest,0.)),Some(p(1.,0.)));assert_eq!(unit(p(0.,-smallest)),Some(p(0.,-1.)));}
 #[test]fn caller_refit_budget_is_exact_for_valid_proposals(){let points=[p(0.,0.),p(1.,1.),p(2.,0.3),p(3.,1.),p(4.,0.)];for budget in 0..=2{let mut attempts=Vec::new();let _=fit_run_observed(&points,p(1.,1.),p(-1.,1.),&FitPolicy{squared_error:0.,max_refits:budget},|i,u|attempts.push((i,u.to_vec())));assert_eq!(attempts.len(),budget);assert_eq!(attempts.iter().map(|x|x.0).collect::<Vec<_>>(),(0..budget).collect::<Vec<_>>());if budget==2{assert_ne!(attempts[0].1,attempts[1].1);}}}
 #[test]fn rejected_refit_retains_complete_candidate_state(){let q=[p(0.,0.);4];let u=vec![0.,0.5,1.];let points=[p(0.,0.),p(1.,1.),p(0.,0.)];let prior=(u.clone(),q,error(&points,&u,&q).unwrap());assert!(refitted_candidate(&points,&u,&q,p(1.,0.),p(-1.,0.)).is_none());assert_eq!((u,q,error(&points,&prior.0,&q).unwrap()),prior);}
 #[test]fn refit_solve_failure_retains_prior_parameters_and_controls(){let q=linear();let u=vec![0.,0.5,1.];let points=[p(0.,0.),p(0.5,0.),p(1.,0.)];assert!(proposed_parameters(&points,&u,&q).is_some());assert!(refitted_candidate(&points,&u,&q,p(1.,0.),p(-1.,0.)).is_none());assert_eq!(u,vec![0.,0.5,1.]);assert_eq!(q,linear());}
 #[test]fn derived_reparam_budget_digit_doubling(){
  // ceil(log2(ceil(log2(n-1)))) + 1: n=3 -> 1, n=17 -> 3, n=25 -> 4, n=1000 -> 5.
  assert_eq!(derived_reparam_budget(3),1);
  assert_eq!(derived_reparam_budget(17),3);
  assert_eq!(derived_reparam_budget(25),4);
  assert_eq!(derived_reparam_budget(1000),5);
 }
 #[test]fn worsening_refit_is_rejected_and_certifies_stop(){
  // A candidate that does not strictly reduce max squared error must not be
  // committed: the loop stops at the prior (better) state. Guard property:
  // for these fixtures the committed solve's error never exceeds the initial
  // solve's error.
  let fixtures:Vec<Vec<Point>>=vec![
   vec![p(0.,0.),p(1.,1.),p(2.,0.3),p(3.,1.),p(4.,0.)],
   vec![p(0.,0.),p(0.4,3.),p(0.8,0.)],
   vec![p(0.,0.),p(1.,0.1),p(2.,-0.1),p(3.,0.)],
  ];
  for points in fixtures{
   let left=unit(sub(points[1],points[0])).unwrap();
   let last=points.len()-1;
   let right=unit(sub(points[last-1],points[last])).unwrap();
   let mut u=vec![0.];for i in 1..points.len(){u.push(u[i-1]+(points[i].x-points[i-1].x).hypot(points[i].y-points[i-1].y).sqrt());}
   let total=*u.last().unwrap();for t in &mut u{*t/=total;}
   let q0=solve(&points,&u,left,right).unwrap();
   let(max0,_)=error(&points,&u,&q0).unwrap();
   if let FitOutcome::Fitted{max_squared_error,..}=fit_run(&points,left,right,&FitPolicy{squared_error:0.,max_refits:8}){
    assert!(max_squared_error<=max0,"committed refit worsened the objective: {max_squared_error} > {max0}");
   }
  }
 }
 #[test]fn threshold_equality_accepts_without_refit(){let points=[p(0.,0.),p(1.,1.),p(2.,0.3),p(3.,1.),p(4.,0.)];let left=unit(p(1.,1.)).unwrap();let right=unit(p(-1.,1.)).unwrap();let mut u=vec![0.];for i in 1..points.len(){u.push(u[i-1]+(points[i].x-points[i-1].x).hypot(points[i].y-points[i-1].y).sqrt());}let total=*u.last().unwrap();for t in &mut u{*t/=total;}let q=solve(&points,&u,left,right).unwrap();let(max,_)=error(&points,&u,&q).unwrap();let mut count=0;assert!(matches!(fit_run_observed(&points,left,right,&FitPolicy{squared_error:max,max_refits:2},|_,_|count+=1),FitOutcome::Fitted{..}));assert_eq!(count,0);}

}

#[cfg(test)]
mod damped_refit_tests {
    use super::*;

    fn pt(x: f64, y: f64) -> Point { Point { x, y } }

    // Measured on Paul New period (002E), arc 0 (PN-3 repro, v11.2 warn
    // tag): a deep hook whose raster samples made the all-or-nothing Newton
    // reparametrisation fail (CandidateFailed) and bottom out unresolved.
    fn measured_hook_arc() -> Vec<Point> {
        vec![
            pt(700.5284365239951, 0.0011130230473815556),
            pt(700.5276576403832, 999.5472654835204),
            pt(700.0891265597148, 999.9857965641887),
            pt(0.44563279857397503, 999.9928982820943),
            pt(0.008030624145048803, 999.9828417402697),
        ]
    }

    #[test]
    fn damped_resolves_arc_the_all_or_nothing_reparam_abandons() {
        let pts = measured_hook_arc();
        let (lt, rt) = adjacent_chord_tangents(&pts).unwrap();
        let policy = FitPolicy { squared_error: 0.25, max_refits: 8 };
        // Receipt: the undamped fitter abandons this arc (measured
        // CandidateFailed under the dual-init budget).
        assert!(matches!(fit_run(&pts, lt, rt, &policy), FitOutcome::SplitUnresolved { .. }));
        // The damped reparam (clamped Newton + Schneider fallback, monotone
        // by construction) resolves it under the same bound and budget.
        match fit_run_damped(&pts, lt, rt, &policy) {
            FitOutcome::Fitted { parameters, max_squared_error, .. } => {
                assert!(max_squared_error <= policy.squared_error, "rescued fit exceeds its own bound: {max_squared_error}");
                assert!(parameters.windows(2).all(|w| w[0] <= w[1]), "parameters must stay monotone");
            }
            other => panic!("damped refit must resolve the measured arc, got {other:?}"),
        }
    }

    #[test]
    fn damped_matches_undamped_on_a_clean_cubic_sample() {
        // Exact cubic samples (no raster noise): both fitters succeed and
        // land on equivalent curves - the damped path must not perturb the
        // cases the primary path already resolves.
        let q = [pt(0.0, 0.0), pt(30.0, 90.0), pt(120.0, 90.0), pt(150.0, 0.0)];
        let pts: Vec<Point> = (0..=12).map(|i| evaluate(&q, i as f64 / 12.0)).collect();
        // Exact endpoint tangents of the sampled cubic, generous bound:
        // both fitters must succeed without a split request.
        let lt = unit(sub(q[1], q[0])).unwrap();
        let rt = unit(sub(q[2], q[3])).unwrap(); // inward at the right end (module convention)
        let policy = FitPolicy { squared_error: 4.0, max_refits: 16 };
        let a = fit_run(&pts, lt, rt, &policy);
        let b = fit_run_damped(&pts, lt, rt, &policy);
        match (a, b) {
            (FitOutcome::Fitted { controls: ca, .. }, FitOutcome::Fitted { controls: cb, .. }) => {
                for (pa, pb) in ca.iter().zip(cb.iter()) {
                    assert!((pa.x - pb.x).abs() < 1.0 && (pa.y - pb.y).abs() < 1.0, "controls diverge: {ca:?} vs {cb:?}");
                }
            }
            (a, b) => panic!("both fitters must fit a clean cubic sample: {a:?} / {b:?}"),
        }
    }

    #[test]
    fn split_unresolved_carries_visible_budget_exhausted_stop() {
        // r292-REV: stop visibility on a clean solvable geometry - a quarter
        // circle (radius 10, center origin, angle 0..pi/2, 9 samples). The
        // module's tangent convention is INWARD at both ends (solve builds
        // q2 = p3 + right*b with b > 0 required; adjacent_chord_tangents doc;
        // existing clean-cubic test uses rt = unit(q2 - q3)), so the right
        // tangent is (1,0), not the forward tangent (-1,0) - the forward
        // value was measured to fail both initial candidates (stop None) in
        // w1-r292-focused-stop-tests.log. The cubic approximation of a
        // circular arc cannot meet squared_error 1e-9, so with max_refits = 0
        // the refit loop exits at its first budget check and the
        // SplitUnresolved outcome must carry Some(RefitStop::BudgetExhausted).
        let pts: Vec<Point> = (0..9)
            .map(|i| {
                let a = (i as f64) * std::f64::consts::FRAC_PI_2 / 8.0;
                pt(10.0 * a.cos(), 10.0 * a.sin())
            })
            .collect();
        let policy = FitPolicy { squared_error: 1.0e-9, max_refits: 0 };
        match fit_run(&pts, pt(0.0, 1.0), pt(1.0, 0.0), &policy) {
            FitOutcome::SplitUnresolved { stop, .. } => {
                assert_eq!(stop, Some(RefitStop::BudgetExhausted), "budget-exhausted stop must be visible");
            }
            other => panic!("quarter circle beyond the error bound must stay unresolved, got {other:?}"),
        }
    }

    #[test]
    fn no_initial_solve_carries_none_stop() {
        // r292: measured stop-None semantics - this zigzag input (unit-x
        // endpoint tangents) returns SplitUnresolved with stop None: no
        // usable initial candidate (solve or error skip in the dual-init
        // loop), so the refit loop is never entered and no stop record
        // exists. Measured in the r289-RETRY full run (2151/1/6): the
        // predecessor of this pin expected Some(BudgetExhausted) here and
        // got None.
        let pts: Vec<Point> = (0..9)
            .map(|i| pt(i as f64, if i % 2 == 0 { 0.0 } else { 2.0 }))
            .collect();
        let policy = FitPolicy { squared_error: 1.0e-9, max_refits: 0 };
        match fit_run(&pts, pt(1.0, 0.0), pt(1.0, 0.0), &policy) {
            FitOutcome::SplitUnresolved { stop, .. } => {
                assert_eq!(stop, None, "no refit stop record must stay visible as None");
            }
            other => panic!("zigzag beyond the error bound must stay unresolved, got {other:?}"),
        }
    }
}
