//! Synthetic policy/mechanics tests, not real-font optical validation.
#[path = "../src/gen_production.rs"]
mod gen_production;
// Allows testing the add-only module before the optional lib registration.
mod gen { pub use kni_metrics::gen::*; }
mod export_gpos { pub use kni_metrics::export_gpos::*; }
use gen_production::*;
use kni_metrics::gen::{ClassTargets, GenerationInputs, GlyphKnowledge};
use std::collections::{BTreeMap, HashMap};

fn binding() -> Binding {
    Binding { font_revision: "font-hash".into(), model_revision: "model-hash".into(), context: "DFLT/default/kern".into() }
}
fn anchor(l: u16, r: u16, k: i32) -> SourcePair {
    SourcePair { left:l, right:r, kern:k, evidence: format!("anchor-{l}-{r}") }
}
fn policy() -> Calibration {
    Calibration::fit(binding(), &[anchor(1,1,-80), anchor(2,2,30)],
        &[Holdout { left:3, right:3, absolute_error: 5.0, measurement_uncertainty: 2.0, evidence:"pair-heldout-hash".into() }]).unwrap()
}
fn input(value: f64) -> (GenerationInputs, BTreeMap<String,u16>) {
    let glyphs = vec!["a".to_string(),"b".to_string()];
    let knowledge = glyphs.iter().map(|g| (g.clone(),GlyphKnowledge { case:'L',freq_weight:0,right_class:1,left_class:1 })).collect();
    let inp = GenerationInputs { glyphs, knowledge,
        targets: ClassTargets { cell_median: HashMap::from([((1,1,'L','L'),value)]),
            stratum_mingap:HashMap::new(), global_mingap:0.0 },
        walls:HashMap::new(), existing:HashMap::new(), restore:vec![] };
    (inp, BTreeMap::from([("a".into(),1),("b".into(),2)]))
}
fn check(l:u16,r:u16,k:i32) -> Verification {
    Verification { binding:binding(), left:l,right:r,kern:k,measured_residual:0.0,calibrated_uncertainty:1.0,uncertainty_evidence:"pair-uncertainty-hash".into(),optical_evidence:"independent-heldout-hash".into(),full_geometry_evidence:"complete-outline-hash".into() }
}
#[test]
fn thresholds_derive_from_font_and_holdout_not_old_constants() {
    let p=policy(); assert_eq!(p.noise_floor(),5.0); assert_eq!(p.signed_envelope(),(-80,30));
    assert_eq!(p.anchor_evidence(), &["anchor-1-1".to_string(),"anchor-2-2".to_string()]);
    assert_eq!(p.holdout_evidence(), &["pair-heldout-hash".to_string()]);
    assert!(Calibration::fit(binding(), &[], &[]).is_err());
    let h=Holdout { left:1,right:1,absolute_error:1.0,measurement_uncertainty:0.0,evidence:"h".into() };
    assert!(Calibration::fit(binding(), &[anchor(1,1,0)], &[h]).is_err());
}
#[test]
fn preserves_explicit_zero_and_marks_absence_unverified() {
    let (mut inp,ids)=input(-20.0); inp.existing.insert(("a".into(),"b".into()),0);
    let out=generate(&binding(),&inp,&ids,&[anchor(1,2,0)],&policy(),&[]).unwrap();
    assert_eq!(out.rows().len(),4);
    assert_eq!(out.binding,binding());
    assert_eq!(out.calibration.noise_floor(),policy().noise_floor());
    assert_eq!(out.rows()[1].kern,Some(0)); assert_eq!(out.rows()[1].state,State::SourceUnverified);
    assert_eq!(out.rows()[2].kern,Some(-20)); assert_eq!(out.rows()[2].state,State::Unverifiable);
    assert!(out.verified_targets().unwrap().is_empty());
}
#[test]
fn verified_only_adapter_keeps_exact_zero_locked() {
    let (inp,ids)=input(-20.0);
    let out=generate(&binding(),&inp,&ids,&[anchor(1,2,0)],&policy(),&[check(1,2,0),check(2,1,-20)]).unwrap();
    let targets=out.verified_targets().unwrap(); assert_eq!(targets.len(),2);
    assert_eq!(targets[0].kern,0); assert!(targets.iter().all(|p|p.locked));
    assert_eq!((targets[1].left,targets[1].right,targets[1].kern),(2,1,-20));
}
#[test]
fn no_extrapolation_clamp_or_quota() {
    for (value,state) in [(100.0,State::RejectedExtrapolation),(2.0,State::RejectedNoise)] {
        let (inp,ids)=input(value);
        let out=generate(&binding(),&inp,&ids,&[],&policy(),&[]).unwrap();
        assert_eq!(out.rows().len(),4);
        assert!(out.rows().iter().all(|r|r.state==state && r.kern==Some(value as i32)));
    }
}
#[test]
fn deterministic_under_input_order() {
    let (mut inp,ids)=input(-20.0);
    let a=generate(&binding(),&inp,&ids,&[],&policy(),&[]).unwrap().to_tsv();
    inp.glyphs.reverse();
    let b=generate(&binding(),&inp,&ids,&[],&policy(),&[]).unwrap().to_tsv();
    assert_eq!(a,b);
}
#[test]
fn missing_is_not_zero() {
    let (mut inp,ids)=input(-20.0); inp.knowledge.clear();
    let out=generate(&binding(),&inp,&ids,&[],&policy(),&[]).unwrap();
    assert!(out.rows().iter().all(|r|r.kern.is_none() && r.state==State::MissingPrediction));
}
#[test]
fn reject_wrong_revision_unknown_ids_duplicates_and_conflicts() {
    let (mut inp,mut ids)=input(-20.0);
    let mut b=binding(); b.model_revision="other".into();
    assert!(generate(&b,&inp,&ids,&[],&policy(),&[]).is_err());
    assert!(generate(&binding(),&inp,&ids,&[anchor(1,3,0)],&policy(),&[]).is_err());
    assert!(generate(&binding(),&inp,&ids,&[anchor(1,2,0),anchor(1,2,0)],&policy(),&[]).is_err());
    inp.existing.insert(("a".into(),"b".into()),0);
    assert!(generate(&binding(),&inp,&ids,&[],&policy(),&[]).is_err());
    ids.insert("b".into(),1);
    assert!(generate(&binding(),&inp,&ids,&[],&policy(),&[]).is_err());
}
#[test]
fn reject_bad_verification_and_nonfinite_model() {
    let (mut inp,ids)=input(-20.0);
    assert!(generate(&binding(),&inp,&ids,&[],&policy(),&[check(1,2,-21)]).is_err());
    let mut v=check(1,2,-20); v.full_geometry_evidence.clear();
    assert!(generate(&binding(),&inp,&ids,&[],&policy(),&[v]).is_err());
    inp.targets.cell_median.insert((1,1,'L','L'),f64::NAN);
    assert!(generate(&binding(),&inp,&ids,&[],&policy(),&[]).is_err());
}
#[test]
fn source_not_limited_by_empirical_envelope_but_export_checks_format() {
    let (inp,ids)=input(-20.0);
    let out=generate(&binding(),&inp,&ids,&[anchor(1,2,40000)],&policy(),&[check(1,2,40000)]).unwrap();
    assert_eq!(out.rows()[1].kern,Some(40000));
    assert!(out.verified_targets().is_err());
}
#[test]
fn font_scaling_scales_thresholds() {
    let h=|e,u| Holdout { left:3,right:3,absolute_error:e,measurement_uncertainty:u,evidence:"h".into() };
    let p=Calibration::fit(binding(), &[anchor(1,1,-160),anchor(2,2,60)], &[h(10.0,4.0)]).unwrap();
    assert_eq!(p.noise_floor(),2.0*policy().noise_floor());
    assert_eq!(p.signed_envelope(),(-160,60));
}
#[test]
fn name_is_not_diacritic_authority() {
    let (mut inp,mut ids)=input(-20.0);
    let data=inp.knowledge.remove("b").unwrap();
    inp.knowledge.insert("adieresis".into(),data); inp.glyphs[1]="adieresis".into();
    ids.remove("b"); ids.insert("adieresis".into(),2);
    let out=generate(&binding(),&inp,&ids,&[],&policy(),&[]).unwrap();
    assert!(out.rows().iter().all(|r|r.state==State::Unverifiable));
}

#[test]
fn pair_uncertainty_records_are_explicit_not_imputed_confidence() {
    let (inp, ids) = input(-20.0);
    let out=generate(&binding(),&inp,&ids,&[anchor(1,2,0)],&policy(),&[check(2,1,-20)]).unwrap();
    assert_eq!(out.rows()[1].uncertainty,None);
    assert_eq!(out.rows()[1].residual,None);
    assert!(out.rows()[1].refusal_reason.is_some());
    assert_eq!(out.rows()[2].uncertainty,Some(1.0));
    assert_eq!(out.rows()[2].residual,Some(0.0));
    assert!(out.rows()[2].refusal_reason.is_none());
    assert_eq!(out.rows()[0].uncertainty,Some(policy().noise_floor()));
    assert!(out.rows()[0].uncertainty_method.contains("not-pair-confidence"));
    let mut bad=check(2,1,-20); bad.calibrated_uncertainty=f64::NAN;
    assert!(generate(&binding(),&inp,&ids,&[],&policy(),&[bad]).is_err());
}

#[test]
fn verified_walls_gate_populated_cells_without_mutating_source_values() {
    let (inp,ids)=input(-20.0);
    let mut out=generate(&binding(),&inp,&ids,&[anchor(1,2,0)],&policy(),&[check(1,2,0)]).unwrap();
    out.require_verified_walls(&std::collections::BTreeSet::from([1]));
    assert!(out.rows()[1].abstain);
    assert_eq!(out.rows()[1].kern,Some(0));
    assert_eq!(out.rows()[1].refusal_reason.as_deref(),Some("glyph lacks verified walls"));
    assert!(out.verified_targets().unwrap().is_empty());
}
