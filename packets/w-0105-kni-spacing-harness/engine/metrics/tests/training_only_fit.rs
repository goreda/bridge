use kni_metrics::training_only_fit::*;
use kni_metrics::gen::{GlyphKnowledge,GlyphWall};
use std::collections::{BTreeMap,BTreeSet};
fn p(c:char)->String{std::iter::repeat(c).take(64).collect()}
fn assignment(g:&str,query:bool)->GeometryAssignment{
 GeometryAssignment{glyph:g.into(),knowledge:GlyphKnowledge{case:'x',freq_weight:0,right_class:1,left_class:1},wall:GlyphWall{advance:100.0,rows:BTreeMap::from([(0,(0.0,80.0)),(100,(0.0,80.0))])},outline_pin:p('a'),prototype_pin:p('b'),query_only:query}
}
fn rows()->Vec<Observation>{vec![Observation{row_pin:p('1'),left:"a".into(),right:"b".into(),kern:-20},Observation{row_pin:p('2'),left:"b".into(),right:"a".into(),kern:-30}]}
fn excluded()->BTreeSet<String>{BTreeSet::from(["q".into(),"r".into()])}
#[test]fn training_medians_query_and_receipt(){
 let f=fit(&rows(),&[assignment("a",false),assignment("b",false)],&excluded(),&p('b')).unwrap();
 assert_eq!(f.inputs.targets.cell_median[&(1,1,'x','x')],-25.0);
 let before=f.artifact_sha256();
 let query=predict_query(&f,&assignment("q",true),&assignment("r",true));
 assert_eq!(query.predicted,Some(-25));assert!(query.unavailable_reason.is_none());
 assert_eq!(before,f.artifact_sha256());assert_eq!(before.len(),64);
 assert_eq!(query.query_outline_pins.len(),2);assert_eq!(query.mechanism.as_deref(),Some("cell"));
}
#[test]fn target_glyph_exclusion_not_just_pair_exclusion(){
 let mut r=rows();r[0].left="q".into();
 assert!(matches!(fit(&r,&[assignment("a",false),assignment("b",false)],&excluded(),&p('b')),Err(FitError::TargetGlyphInTraining(_))));
 assert!(matches!(fit(&rows(),&[assignment("q",false)],&excluded(),&p('b')),Err(FitError::TargetGlyphInTraining(_))));
}
#[test]fn query_cannot_fit_and_missing_geometry_is_explicit(){
 assert!(matches!(fit(&rows(),&[assignment("a",true)],&excluded(),&p('b')),Err(FitError::QueryInFit)));
 assert!(matches!(fit(&rows(),&[],&excluded(),&p('b')),Err(FitError::MissingTrainingGeometry(_))));
}
#[test]fn malformed_pins_duplicates_and_empty_are_errors(){
 assert!(matches!(fit(&[],&[],&excluded(),&p('b')),Err(FitError::NoTrainingRows)));
 assert!(matches!(fit(&rows(),&[],&excluded(),"bad"),Err(FitError::MissingPin)));
 let mut r=rows();r.push(r[0].clone());
 assert!(matches!(fit(&r,&[assignment("a",false),assignment("b",false)],&excluded(),&p('b')),Err(FitError::DuplicateRow)));
}
#[test]fn deterministic_permutation(){
 let a=fit(&rows(),&[assignment("a",false),assignment("b",false)],&excluded(),&p('b')).unwrap();
 let mut r=rows();r.reverse();
 let b=fit(&r,&[assignment("b",false),assignment("a",false)],&excluded(),&p('b')).unwrap();
 assert_eq!(a.artifact_sha256(),b.artifact_sha256());
}
#[test]fn bad_query_never_silent_fallback(){
 let f=fit(&rows(),&[assignment("a",false),assignment("b",false)],&excluded(),&p('b')).unwrap();
 let mut q=assignment("q",true);q.wall.rows.clear();
 let out=predict_query(&f,&q,&assignment("r",true));assert!(out.predicted.is_none());assert!(out.unavailable_reason.is_some());
 let out=predict_query(&f,&assignment("q",false),&assignment("r",true));assert!(out.unavailable_reason.is_some());
}
