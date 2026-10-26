use kni_core::{reference_slice, economy};
#[path = "../src/construction_region.rs"]
mod construction_region;
use construction_region::*;
use reference_slice::{DrawnGlyph,Point,ReferenceRing,Span};
fn p(x:f64,y:f64)->Point{Point{x,y}}
fn ln(x:f64,y:f64)->Span{Span::Line{end:p(x,y)}}
fn fixture()->(DrawnGlyph,DrawnGlyph,RegionConfig,Vec<ConstructionRegion>){
 let b=DrawnGlyph{glyph_id:"synthetic".into(),rings:vec![
  ReferenceRing{start:p(0.,0.),spans:vec![ln(10.,0.),ln(10.,10.),ln(0.,10.),ln(0.,0.)]},
  ReferenceRing{start:p(2.,2.),spans:vec![ln(2.,8.),ln(8.,8.),ln(8.,2.),ln(2.,2.)]}]};
 let mut c=b.clone();c.rings[0].spans.insert(0,ln(5.,0.));
 let cfg=RegionConfig{source_pin:"synthetic-source".into(),frame_pin:"font-units".into(),glyph_id:b.glyph_id.clone(),flatten_steps:8};
 let range=|ring,first,end,role|SpanRange{ring,first,end,role};
 let rs=vec![ConstructionRegion{id:"ink".into(),kind:RegionKind::Ink,hypothesis_ref:"supplied-ink".into(),baseline:vec![range(0,0,1,RingRole::Outer)],candidate:vec![range(0,0,2,RingRole::Outer)],source_chains:vec![vec![p(0.,0.),p(10.,0.)]]},
 ConstructionRegion{id:"counter".into(),kind:RegionKind::Counter,hypothesis_ref:"supplied-counter".into(),baseline:vec![range(1,0,4,RingRole::Hole)],candidate:vec![range(1,0,4,RingRole::Hole)],source_chains:vec![vec![p(2.,2.),p(2.,8.),p(8.,8.),p(8.,2.),p(2.,2.)]]}];
 (b,c,cfg,rs)
}
#[test]fn ink_counter_and_paired_split(){let(b,c,cfg,rs)=fixture();let out=measure_regions(&cfg,&b,&c,&rs).unwrap();assert_eq!(out.len(),2);assert_eq!(out[0].kind,RegionKind::Counter);assert_eq!(out[0].id,"counter");assert_eq!(out[0].hypothesis_ref,"supplied-counter");assert_eq!(out[1].id,"ink");assert_eq!(out[1].hypothesis_ref,"supplied-ink");for r in out{assert_eq!(r.baseline.squared_error,0.);assert_eq!(r.candidate.maximum_deviation,0.);assert_eq!(r.construction,economy::ConstructionComparison::Unknown);assert_eq!(r.metric_label,"sampled boundary metrics");assert_eq!(r.hypothesis_status,"candidate, not accepted hypothesis");}}
#[test]fn detects_local_displacement(){let(b,mut c,cfg,mut rs)=fixture();rs.truncate(1);c.rings[0].start.y=1.;c.rings[0].spans[0]=ln(5.,1.);c.rings[0].spans[1]=ln(10.,1.);let out=measure_regions(&cfg,&b,&c,&rs).unwrap();assert_eq!(out[0].baseline.squared_error,0.);assert_eq!(out[0].candidate.squared_error,1.);assert_eq!(out[0].candidate.maximum_deviation,1.);}
#[test]fn deterministic_region_order(){let(b,c,cfg,mut rs)=fixture();let a=measure_regions(&cfg,&b,&c,&rs).unwrap();rs.reverse();let z=measure_regions(&cfg,&b,&c,&rs).unwrap();assert_eq!(format!("{a:?}"),format!("{z:?}"));}
#[test]fn unknown_kind_or_role_abstains(){let(b,c,cfg,mut rs)=fixture();rs[0].kind=RegionKind::Unknown;assert_eq!(measure_regions(&cfg,&b,&c,&rs).unwrap_err(),RegionError::UnknownStructure);rs[0].kind=RegionKind::Ink;rs[0].candidate[0].role=RingRole::Unknown;assert_eq!(measure_regions(&cfg,&b,&c,&rs).unwrap_err(),RegionError::UnknownStructure);}
#[test]fn invalid_membership_and_overlap(){let(b,c,cfg,rs)=fixture();for(end,expect)in[(0,RegionError::InvalidRange),(999,RegionError::InvalidRange)]{let mut x=rs.clone();x[0].baseline[0].end=end;assert_eq!(measure_regions(&cfg,&b,&c,&x).unwrap_err(),expect);}let mut x=rs.clone();x[0].baseline.clear();assert_eq!(measure_regions(&cfg,&b,&c,&x).unwrap_err(),RegionError::EmptyMembership);let mut x=rs.clone();let dup=x[0].baseline[0].clone();x[0].baseline.push(dup);assert_eq!(measure_regions(&cfg,&b,&c,&x).unwrap_err(),RegionError::Overlap);}
#[test]fn overlap_across_regions_abstains(){let(b,c,cfg,mut rs)=fixture();let mut same=rs[0].clone();same.id="other".into();rs.push(same);assert_eq!(measure_regions(&cfg,&b,&c,&rs).unwrap_err(),RegionError::Overlap);}
#[test]fn source_and_pins_fail_closed(){let(b,c,mut cfg,mut rs)=fixture();cfg.flatten_steps=0;assert_eq!(measure_regions(&cfg,&b,&c,&rs).unwrap_err(),RegionError::InvalidResolution);cfg.flatten_steps=8;cfg.source_pin.clear();assert_eq!(measure_regions(&cfg,&b,&c,&rs).unwrap_err(),RegionError::MissingPin);cfg.source_pin="synthetic".into();rs[0].source_chains[0][0].x=f64::NAN;assert_eq!(measure_regions(&cfg,&b,&c,&rs).unwrap_err(),RegionError::InvalidSource);}
#[test]fn cubic_sampling_is_caller_controlled(){let(b,mut c,cfg,mut rs)=fixture();rs.truncate(1);c.rings[0].spans.drain(0..2);c.rings[0].spans.insert(0,Span::Cubic{control_one:p(0.,5.),control_two:p(10.,5.),end:p(10.,0.)});rs[0].candidate[0].end=1;let out=measure_regions(&cfg,&b,&c,&rs).unwrap();assert!(out[0].candidate.maximum_deviation>0.);assert_eq!(out[0].construction,economy::ConstructionComparison::Unknown);}

struct Mock{pin:&'static str,frame:&'static str,verifiable:bool}
impl economy::FontEconomyEvaluator for Mock{
 fn assess(&mut self,_b:&DrawnGlyph,_c:&DrawnGlyph)->Option<economy::FontAssessment>{
  if !self.verifiable{return None;}
  Some(economy::FontAssessment{source_pin:self.pin.into(),render_frame_pin:self.frame.into(),domain:"test".into(),threshold:128,font_iou:1.0,regions:vec![economy::RegionAssessment{region_id:"ring0".into(),squared_fit_error:0.0,maximum_deviation:0.0,construction:economy::ConstructionComparison::Preserved,extrema_preserved:true,corners_preserved:true,continuity_preserved:true}]})
 }
}
#[test]fn wrapper_preserves_global_and_returns_local(){let(b,c,cfg,rs)=fixture();let mut ev=Mock{pin:"synthetic-source",frame:"font-units",verifiable:true};let(g,local)=assess_with_regions(&mut ev,&cfg,&b,&c,&rs).unwrap();assert_eq!(g.regions.len(),1);assert_eq!(g.regions[0].region_id,"ring0");assert_eq!(local.len(),2);}
#[test]fn wrapper_pin_mismatch_abstains(){let(b,c,cfg,rs)=fixture();let mut ev=Mock{pin:"synthetic-source",frame:"other-frame",verifiable:true};assert_eq!(assess_with_regions(&mut ev,&cfg,&b,&c,&rs).unwrap_err(),RegionError::PinMismatch);}
#[test]fn wrapper_unverified_font_abstains(){let(b,c,cfg,rs)=fixture();let mut ev=Mock{pin:"synthetic-source",frame:"font-units",verifiable:false};assert_eq!(assess_with_regions(&mut ev,&cfg,&b,&c,&rs).unwrap_err(),RegionError::UnverifiedFont);}
