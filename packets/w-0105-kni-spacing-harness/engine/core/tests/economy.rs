use kni_core::economy::{count, exact_line_economy};
use kni_core::reference_slice::{Point, Span};
fn p(x:f64,y:f64)->Point { Point{x,y} }
fn l(x:f64,y:f64)->Span { Span::Line{end:p(x,y)} }
#[test] fn straight_integer_run_is_one_segment_and_records_rule() {
    let (s,d)=exact_line_economy(p(0.,0.),vec![l(1.,1.),l(2.,2.),l(4.,4.)],&[7,7,7]);
    assert_eq!(count(&s).segments(),1); assert_eq!(d.len(),1);
    assert_eq!(d[0].before.lines,3); assert_eq!(d[0].after.lines,1);
    assert!(d[0].geometry_identical && d[0].construction_boundary_preserved);
}
#[test] fn construction_arc_boundary_cannot_be_removed() {
    let (s,d)=exact_line_economy(p(0.,0.),vec![l(1.,0.),l(2.,0.)],&[0,1]);
    assert_eq!(s.len(),2);assert!(d.is_empty());
}
#[test] fn reversal_and_real_corner_are_kept() {
    for v in [vec![l(1.,0.),l(0.,0.)],vec![l(1.,0.),l(1.,1.)]] {
        assert_eq!(exact_line_economy(p(0.,0.),v,&[0,0]).0.len(),2);
    }
}
#[test] fn non_integer_invalid_and_nearly_collinear_geometry_is_kept() {
    for v in [vec![l(0.5,0.),l(1.,0.)],vec![l(1.,0.),l(2.,1.)],vec![l(f64::NAN,0.),l(2.,0.)]] {
        assert_eq!(exact_line_economy(p(0.,0.),v,&[0,0]).0.len(),2);
    }
    // Cross-product products round alike in binary64 but exact cross != 0.
    let n=(1u64<<f64::MANTISSA_DIGITS) as f64;
    assert_eq!(exact_line_economy(p(-n,-n),vec![l(0.,1.),l(n-1.,n)],&[0,0]).0.len(),2);
}
#[test] fn provenance_mismatch_fails_closed() {
    assert_eq!(exact_line_economy(p(0.,0.),vec![l(1.,0.),l(2.,0.)],&[0]).0.len(),2);
}
#[test] fn cubic_loop_and_zero_span_are_not_handled_here() {
    let c=Span::Cubic{control_one:p(1.,0.),control_two:p(0.,1.),end:p(0.,0.)};
    let (s,d)=exact_line_economy(p(0.,0.),vec![c,l(0.,0.)],&[0,0]);assert_eq!(s.len(),2);assert!(d.is_empty());
}
#[test] fn closure_and_idempotence_preserved() {
    let v=vec![l(1.,0.),l(2.,0.),l(2.,2.),l(0.,2.),l(0.,0.)];
    let (s,_)=exact_line_economy(p(0.,0.),v,&[0,0,1,2,3]); assert_eq!(s.len(),4);
    assert!(matches!(s.last(),Some(Span::Line{end}) if *end==p(0.,0.)));
    let (s,d)=exact_line_economy(p(0.,0.),s,&[0,1,2,3]);assert_eq!(s.len(),4);assert!(d.is_empty());
}

use kni_core::economy::*;
use kni_core::reference_slice::{DrawnGlyph,ReferenceRing};
fn glyph(n:usize)->DrawnGlyph {DrawnGlyph{glyph_id:"fixture".into(),rings:vec![ReferenceRing{start:p(0.,0.),spans:(0..n).map(|_|l(0.,0.)).collect()}]}}
fn bound()->FontEconomyBound {FontEconomyBound{font_measurement_pin:"synthetic-test-only".into(),loss_derivation:LossDerivation{source_measurement_pin:"synthetic-measurement".into(),method:"zero loss allowed for synthetic checks".into(),measurements:vec![("synthetic loss".into(),0.)]},squared_fit_budget:1.,maximum_deviation:1.,allowed_iou_loss:0.}}
fn assessment()->FontAssessment {FontAssessment{source_pin:"test-source".into(),render_frame_pin:"test-frame".into(),domain:"scan-font".into(),threshold:128,font_iou:1.,regions:vec![RegionAssessment{region_id:"test-region".into(),squared_fit_error:0.,maximum_deviation:0.,construction:ConstructionComparison::Preserved,extrema_preserved:true,corners_preserved:true,continuity_preserved:true}]}}
struct Mock { assessments:std::collections::VecDeque<Option<FontAssessment>> }
impl FontEconomyEvaluator for Mock {fn assess(&mut self,_:&DrawnGlyph,_:&DrawnGlyph)->Option<FontAssessment>{self.assessments.pop_front().flatten()}}
fn select(a:Option<FontAssessment>,b:FontEconomyBound)->(DrawnGlyph,Vec<SelectionRecord>){select_economical_glyph(glyph(4),vec![glyph(3)],&b,&mut Mock{assessments:vec![Some(assessment()),a].into()})}
#[test] fn selector_uses_count_after_all_guards(){let(g,r)=select(Some(assessment()),bound());assert_eq!(g.rings[0].spans.len(),3);assert_eq!(r[0].reason,SelectionReason::AcceptedEconomy);}
#[test] fn unknown_construction_and_corner_loss_override_economy(){for k in 0..4{let mut a=assessment();match k{0=>a.regions[0].construction=ConstructionComparison::Unknown,1=>a.regions[0].construction=ConstructionComparison::Regressed,2=>a.regions[0].corners_preserved=false,_=>a.regions[0].continuity_preserved=false};let(g,r)=select(Some(a),bound());assert_eq!(g.rings[0].spans.len(),4);assert_eq!(r[0].reason,SelectionReason::ConstructionGuard);}}
#[test] fn final_font_regression_overrides_economy(){let mut a=assessment();a.font_iou=0.9;assert_eq!(select(Some(a),bound()).1[0].reason,SelectionReason::FidelityBound);}
#[test] fn local_deviation_rejects_even_with_perfect_iou(){let mut a=assessment();a.regions[0].maximum_deviation=2.;assert_eq!(select(Some(a),bound()).1[0].reason,SelectionReason::FidelityBound);}
#[test] fn missing_evidence_and_frame_change_fail_closed(){assert_eq!(select(None,bound()).1[0].reason,SelectionReason::UnverifiedCandidate);let mut a=assessment();a.threshold=127;assert_eq!(select(Some(a),bound()).1[0].reason,SelectionReason::FrameMismatch);}
#[test] fn uncalibrated_or_nan_bound_blocks(){let mut b=bound();b.font_measurement_pin.clear();assert_eq!(select(Some(assessment()),b).1[0].reason,SelectionReason::InvalidBound);let mut b=bound();b.allowed_iou_loss=f64::NAN;assert_eq!(select(Some(assessment()),b).1[0].reason,SelectionReason::InvalidBound);}
#[test] fn no_cumulative_iou_drift(){let mut a=assessment();a.font_iou=0.9;let mut b=a.clone();b.font_iou=0.8;let mut limits=bound();limits.allowed_iou_loss=0.15;let (g,r)=select_economical_glyph(glyph(5),vec![glyph(4),glyph(3)],&limits,&mut Mock{assessments:vec![Some(assessment()),Some(a),Some(b)].into()});assert_eq!(g.rings[0].spans.len(),4);assert_eq!(r[1].reason,SelectionReason::FidelityBound);}
#[test] fn recorded_construction_improvement_cannot_be_erased_by_count(){let mut a=assessment();a.regions[0].construction=ConstructionComparison::Improved;let(g,r)=select_economical_glyph(glyph(5),vec![glyph(4),glyph(3)],&bound(),&mut Mock{assessments:vec![Some(assessment()),Some(a),Some(assessment())].into()});assert_eq!(g.rings[0].spans.len(),4);assert_eq!(r[1].reason,SelectionReason::ConstructionGuard);}

#[test] fn local_regression_inside_budget_rejects_and_is_recorded(){let mut a=assessment();a.regions[0].maximum_deviation=0.5;let(g,r)=select(Some(a),bound());assert_eq!(g.rings[0].spans.len(),4);assert_eq!(r[0].reason,SelectionReason::RegionRegression);assert_eq!(r[0].region_deltas[0].candidate_deviation,0.5);assert_eq!(r[0].bound_used.allowed_iou_loss,0.);}
#[test] fn vacuous_iou_bound_and_empty_derivation_reject(){let mut b=bound();b.allowed_iou_loss=1.;assert_eq!(select(Some(assessment()),b).1[0].reason,SelectionReason::InvalidBound);let mut b=bound();b.loss_derivation.measurements.clear();assert_eq!(select(Some(assessment()),b).1[0].reason,SelectionReason::InvalidBound);}
#[test] fn glyph_mismatch_has_own_reason(){let mut c=glyph(3);c.glyph_id="different".into();let(_,r)=select_economical_glyph(glyph(4),vec![c],&bound(),&mut Mock{assessments:vec![Some(assessment())].into()});assert_eq!(r[0].reason,SelectionReason::GlyphMismatch);}

#[test] fn exact_chord_cubic_is_line_without_tolerance(){let c=Span::Cubic{control_one:p(0.,0.),control_two:p(3.,3.),end:p(3.,3.)};let(s,r)=exact_cubic_lines(p(0.,0.),vec![c],&[0]);assert!(matches!(s[0],Span::Line{..}));assert_eq!(r[0].before.cubics,1);assert_eq!(r[0].after.lines,1);}
#[test] fn bowed_overshoot_and_closed_cubic_loops_not_degraded(){for(c1,c2,e) in [(p(0.,1.),p(2.,2.),p(3.,3.)),(p(-1.,-1.),p(2.,2.),p(3.,3.)),(p(1.,1.),p(2.,2.),p(0.,0.))]{let c=Span::Cubic{control_one:c1,control_two:c2,end:e};let(s,r)=exact_cubic_lines(p(0.,0.),vec![c],&[0]);assert!(matches!(s[0],Span::Cubic{..}));assert!(r.is_empty());}}

#[test] fn declared_iou_gate_value_is_pinned() {
    // DECLARED_CONVENTION provenance: docs/kni/2026-10-18-economy-objective-conventions.md.
    assert_eq!(ECONOMY_IOU_LOSS_GATE, 0.002);
}
#[test] fn iou_gate_boundary_exact_loss_passes_beyond_rejects() {
    let mut b = bound(); b.allowed_iou_loss = ECONOMY_IOU_LOSS_GATE;
    let mut at_gate = assessment(); at_gate.font_iou = 1.0 - ECONOMY_IOU_LOSS_GATE;
    let (g, r) = select(Some(at_gate), b.clone());
    assert_eq!(g.rings[0].spans.len(), 3);
    assert_eq!(r[0].reason, SelectionReason::AcceptedEconomy);
    let mut beyond = assessment(); beyond.font_iou = 1.0 - ECONOMY_IOU_LOSS_GATE - 1e-9;
    let (g, r) = select(Some(beyond), b);
    assert_eq!(g.rings[0].spans.len(), 4);
    assert_eq!(r[0].reason, SelectionReason::FidelityBound);
}
