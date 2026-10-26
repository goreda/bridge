//! Source-aware integer emission and guarded geometric refinement.
//! Legacy fitting entry points remain unchanged. The source-aware callers use this entry point.
use crate::{capture::MeasuredContour,capture_fit::{fit_captured_with_span_provenance,round_and_clean_ring},cubic_fit::FitPolicy,reference_slice::ReferenceRing,lever_api::{SourceMask,NodeBudget,LeverReport,area_error,missing_extrema,count_nodes}};
#[derive(Clone,Debug)]
pub struct GeneratedDrawing {pub rings:Vec<ReferenceRing>,pub baseline:Vec<ReferenceRing>,pub reports:Vec<LeverReport>,pub refused:Vec<String>,pub baseline_area:f64,pub final_area:f64,pub baseline_missing_extrema:usize,pub final_missing_extrema:usize,pub source_fit_spans:usize,pub fallback:bool,pub dropped:usize,pub fallback_line_spans:usize,pub sub_grid_floor:usize,pub ambiguous_stubs:usize,pub ambig_declined:usize,pub fallback_provenance:Vec<crate::capture_fit::FallbackSpanProvenance>}
/// Count of zero-length production spans: a Line whose end equals the previous node, or a Cubic whose controls and
/// end all equal the previous node. Binary64 equality, signed zero normalised, no tolerance.
pub fn degenerate_spans(rings:&[ReferenceRing])->usize{use crate::reference_slice::Span;let z=|x:f64|x+0.0;let eq=|a:crate::reference_slice::Point,b:crate::reference_slice::Point|z(a.x)==z(b.x)&&z(a.y)==z(b.y);
 let mut n=0;for r in rings{let mut cur=r.start;for sp in &r.spans{match sp{Span::Line{end}=>{if eq(*end,cur){n+=1}cur=*end}Span::Cubic{control_one,control_two,end}=>{if eq(*end,cur)&&eq(*control_one,cur)&&eq(*control_two,cur){n+=1}cur=*end}}}}n}
/// Capture coordinates are bbox-relative and y-up. The mask origin restores the
/// source tile's top-left in that same frame: (-origin_x*K, -origin_y*K).
pub fn fit_from_source(captured:&MeasuredContour,gray:&[u8],scale:f64,policy:&FitPolicy)->Result<GeneratedDrawing,String>{
 if !scale.is_finite()||scale<=0.0||!policy.squared_error.is_finite()||policy.squared_error<0.0||!captured.origin_x.is_finite()||!captured.origin_y.is_finite(){return Err("invalid drawing frame or policy".into())}
 if captured.width.checked_mul(captured.height)!=Some(gray.len()){return Err("source dimensions do not match gray bytes".into())}
 let (float,source_fit_spans,fallback,dropped,fevents,astubs,declined,fprov)=fit_captured_with_span_provenance(&captured.rings,scale,policy);
 // SubGridSpan is a typed stop below the source's resolving power, not an
 // unresolved hard fail: the gate input counts only unresolved-class events.
 let fallback_line_spans=fevents.iter().filter(|e|e.reason!=crate::capture_fit::FallbackReason::SubGridSpan).count();
 let sub_grid_floor=fevents.len()-fallback_line_spans;
 let baseline:Vec<_>=float.iter().map(|r|round_and_clean_ring(r,1.0)).collect();
 if baseline.is_empty(){return Err("empty generated drawing".into())}
 let mask=SourceMask{w:captured.width,h:captured.height,ink:gray.to_vec(),scale,origin:(-captured.origin_x*scale,-captured.origin_y*scale)};
 if !mask.valid(){return Err("invalid source mask".into())}
 let _flatten_budget_max=crate::flatten_budget::max_total_segments(captured.width,captured.height).ok_or("flatten budget: no declarable budget")?;
 crate::flatten_budget::check_flatten_budget(&baseline,&mask,_flatten_budget_max).map_err(|e|format!("flatten budget: {e:?}"))?;
 let budget=NodeBudget{max_nodes:count_nodes(&baseline),max_nodes_per_ring:baseline.iter().map(|r|r.spans.len()).collect()};
 let baseline_area=area_error(&baseline,&mask);if !baseline_area.is_finite(){return Err("non-finite baseline source objective".into())}let baseline_missing_extrema=missing_extrema(&baseline);
 let mut rings=baseline.clone();let mut reports=Vec::new();let mut refused=Vec::new();
 let cfg=crate::emitted_geometry_refine::RefineConfig{max_snap:crate::emitted_geometry_refine::DERIVED_MAX_SNAP,run_int_refine:true,max_area_evals:crate::emitted_geometry_refine::derived_eval_budget(budget.max_nodes)};
 match crate::emitted_geometry_refine::refine_emitted(&rings,&mask,&budget,&cfg){Ok((out,report))=>{rings=out;reports.push(report)},Err(e)=>refused.push(format!("emission refinement refused: {e:?}"))}
 match crate::tail_refine::refine_tails(&rings,&mask,&budget,&crate::tail_refine::TailConfig::default()){Ok((out,report))=>{rings=out;reports.push(report)},Err(e)=>refused.push(format!("handle refinement refused: {e:?}"))}
 match crate::node_objective::try_apply(&rings,&mask,&budget,crate::node_objective::Policy::STRICT){Ok((out,report))=>{rings=out;reports.push(report)},Err(e)=>refused.push(format!("strict node reduction refused: {e:?}"))}
 // Exact-coincidence repair of production points introduced by the refinement stages (tol 0.0, no geometry change:
 // only spans whose every point equals the previous node are dropped; retracted handles of real spans are kept).
 let before_repair=rings.clone();let repaired:Vec<_>=rings.iter().map(|r|crate::capture_fit::clean_emitted_ring(r.clone(),0.0)).collect();
 let removed=count_nodes(&rings)-count_nodes(&repaired);
 if removed>0{if crate::flatten_budget::check_flatten_budget(&repaired,&mask,_flatten_budget_max).is_err(){refused.push("repair refused: flatten budget".into());}else{let a=area_error(&repaired,&mask);if a.is_finite()&&a<=area_error(&rings,&mask)&&missing_extrema(&repaired)<=missing_extrema(&rings)&&degenerate_spans(&repaired)==0{rings=repaired;refused.push(format!("repair: dropped {removed} zero-length span(s)"))}else{rings=before_repair;refused.push("repair refused: would change area or extrema".into())}}}
 let final_area=area_error(&rings,&mask);let final_missing_extrema=missing_extrema(&rings);
 // strict node budget: global ceiling AND per-ring ceiling (rings are index-stable through every stage).
 if rings.len()!=budget.max_nodes_per_ring.len()||rings.iter().zip(&budget.max_nodes_per_ring).any(|(r,cap)|r.spans.len()>*cap){return Err("drawing refinement violated the per-ring node budget".into())}
 if !final_area.is_finite()||final_area>baseline_area||final_missing_extrema>baseline_missing_extrema||count_nodes(&rings)>budget.max_nodes{return Err("drawing refinement violated the global source-quality guard".into())}
 if degenerate_spans(&rings)>0{return Err("generated drawing still holds zero-length spans after repair".into())}
 Ok(GeneratedDrawing{rings,baseline,reports,refused,baseline_area,final_area,baseline_missing_extrema,final_missing_extrema,source_fit_spans,fallback,dropped,fallback_line_spans,sub_grid_floor,ambiguous_stubs:astubs.len(),ambig_declined:declined.len(),fallback_provenance:fprov})
}
#[cfg(test)]mod tests{use super::*;#[test]fn source_length_refuses(){let c=MeasuredContour{width:2,height:2,rings:vec![],origin_x:0.,origin_y:0.};assert!(fit_from_source(&c,&[255],1.,&FitPolicy{squared_error:1.,max_refits:4}).is_err());}}

#[cfg(test)]mod source_tests{use super::*;#[test]fn rectangle_source_guard_and_repeat(){let mut gray=vec![255u8;144];for y in 3..9{for x in 3..9{gray[y*12+x]=0;}}let c=crate::capture::capture_gray(12,12,&gray,0.25).unwrap();let p=FitPolicy{squared_error:0.25,max_refits:8};let a=fit_from_source(&c,&gray,10.,&p).unwrap();let b=fit_from_source(&c,&gray,10.,&p).unwrap();assert!(a.final_area<=a.baseline_area);assert!(a.final_missing_extrema<=a.baseline_missing_extrema);assert!(count_nodes(&a.rings)<=count_nodes(&a.baseline));assert_eq!(crate::lever_api::hash_rings(&a.rings),crate::lever_api::hash_rings(&b.rings));}}

#[cfg(test)]mod p2_tests{use super::*;use crate::reference_slice::{Point,Span};
 fn p(x:f64,y:f64)->Point{Point{x,y}}
 #[test]fn degenerate_counter(){let r=ReferenceRing{start:p(0.,0.),spans:vec![Span::Line{end:p(0.,0.)},Span::Line{end:p(5.,0.)},Span::Cubic{control_one:p(5.,0.),control_two:p(5.,0.),end:p(5.,0.)},Span::Cubic{control_one:p(5.,0.),control_two:p(6.,1.),end:p(5.,0.)},Span::Line{end:p(0.,0.)}]};assert_eq!(degenerate_spans(&[r]),2);}
 #[test]fn repair_removes_only_exact_zero_spans_and_keeps_retracted_handles(){let r=ReferenceRing{start:p(0.,0.),spans:vec![Span::Line{end:p(0.,0.)},Span::Line{end:p(5.,0.)},Span::Cubic{control_one:p(5.,0.),control_two:p(5.,0.),end:p(5.,0.)},Span::Cubic{control_one:p(5.,0.),control_two:p(5.,5.),end:p(0.,5.)},Span::Line{end:p(0.,0.)}]};
  let c=crate::capture_fit::clean_emitted_ring(r,0.0);assert_eq!(degenerate_spans(&[c.clone()]),0);assert_eq!(c.spans.len(),3);assert!(matches!(c.spans[1],Span::Cubic{control_one,..} if control_one==p(5.,0.)));}
 fn shapes()->Vec<(usize,usize,Vec<u8>)>{let mut v=Vec::new();
  let mut a=vec![255u8;144];for y in 3..9{for x in 3..9{a[y*12+x]=0}}v.push((12,12,a));
  let mut b=vec![255u8;400];for y in 0..20{for x in 0..20{let (dx,dy)=(x as f64-9.5,y as f64-9.5);let d=(dx*dx+dy*dy).sqrt();if d<8.0&&d>3.5{b[y*20+x]=0}}}v.push((20,20,b));
  let mut c=vec![255u8;400];for y in 2..18{for x in 2..7{c[y*20+x]=0}}for y in 13..18{for x in 2..18{c[y*20+x]=0}}v.push((20,20,c));
  let mut d=vec![255u8;400];for y in 0..20{for x in 0..20{if (x as i32-y as i32).abs()<3{d[y*20+x]=0}}}v.push((20,20,d));
  let mut e=vec![255u8;900];for y in 0..30{for x in 0..30{let (dx,dy)=(x as f64-14.5,(y as f64-14.5)*1.6);if dx*dx+dy*dy<150.0{e[y*30+x]=0}}}v.push((30,30,e));v}
 #[test]fn corpus_no_zero_length_and_budget_holds(){let mut processed=0usize;for (i,(w,h,g)) in shapes().into_iter().enumerate(){let c=match crate::capture::capture_gray(w,h,&g,0.25){Ok(c)=>c,Err(e)=>panic!("shape {i} capture: {e:?}")};processed+=1;
  let pol=FitPolicy{squared_error:0.25,max_refits:8};let a=match fit_from_source(&c,&g,10.,&pol){Ok(a)=>a,Err(e)=>panic!("shape {i}: {e}")};
  assert_eq!(degenerate_spans(&a.rings),0,"shape {i}");assert!(count_nodes(&a.rings)<=count_nodes(&a.baseline),"shape {i}");
  for (r,b) in a.rings.iter().zip(&a.baseline){assert!(r.spans.len()<=b.spans.len(),"shape {i} per-ring")}assert!(a.final_area<=a.baseline_area);
  eprintln!("shape {i}: nodes {} -> {} area {:.1}->{:.1} refused={:?}",count_nodes(&a.baseline),count_nodes(&a.rings),a.baseline_area,a.final_area,a.refused);}assert_eq!(processed,5,"corpus must process all 5 shapes, no silent skip");}}
