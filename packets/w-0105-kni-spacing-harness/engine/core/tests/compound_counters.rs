// Full supplied-outline observation fixtures. All expectations authored NOT_RUN.
use kni_core::decision_evidence_envelope::PinClaim;
use kni_core::reference_slice::{Point,Span,ReferenceRing,ReferenceGlyph,GlyphSliceResult,InternalBoundary,preserve_reference,preserve_reference_batch};
fn ring(points:&[(f64,f64)])->ReferenceRing {
    ReferenceRing {start:Point{x:points[0].0,y:points[0].1},spans:points[1..].iter().map(|(x,y)|Span::Line{end:Point{x:*x,y:*y}}).collect()}
}
fn glyph(rings:Vec<ReferenceRing>)->ReferenceGlyph {
    ReferenceGlyph {glyph_id:String::from("synthetic-compound"),source_pin:PinClaim{algorithm:String::from("fixture"),claimed_digest:String::from("unverified-fixture"),subject_ref:String::from("compound")},rings,declared_junction_decision_required:false}
}
fn outer()->ReferenceRing {ring(&[(0.,0.),(10.,0.),(10.,10.),(0.,10.),(0.,0.)])}
#[test]
fn two_reversed_counters_survive_full_pipeline() {
    let input=glyph(vec![outer(),ring(&[(2.,2.),(2.,4.),(8.,4.),(8.,2.),(2.,2.)]),ring(&[(2.,6.),(2.,8.),(8.,8.),(8.,6.),(2.,6.)])]);
    let GlyphSliceResult::Drawn{output,internal}=preserve_reference(input) else {panic!("expected supplied geometry");};
    assert_eq!(output.rings.len(),3);
    let relations:Vec<_>=internal.containment_observations.iter().map(|r|(r.inner_ring,r.outer_ring,r.opposite_winding)).collect();
    assert_eq!(relations,vec![(1,0,true),(2,0,true)]);
    assert_eq!(internal.pass_one.ring_count,3);
    assert_eq!(internal.pass_two.ring_count,3);
}
#[test]
fn one_counter_triangle_and_same_direction_observation() {
    let triangle=ring(&[(0.,10.),(5.,0.),(10.,10.),(0.,10.)]);
    let reverse=ring(&[(4.,6.),(6.,6.),(5.,4.),(4.,6.)]);
    let GlyphSliceResult::Drawn{internal,..}=preserve_reference(glyph(vec![triangle,reverse])) else {panic!();};
    assert_eq!(internal.containment_observations.len(),1);
    assert!(internal.containment_observations[0].opposite_winding);
    let same=ring(&[(2.,2.),(8.,2.),(8.,8.),(2.,8.),(2.,2.)]);
    let GlyphSliceResult::Drawn{internal,..}=preserve_reference(glyph(vec![outer(),same])) else {panic!();};
    assert_eq!(internal.containment_observations.len(),1);
    assert!(!internal.containment_observations[0].opposite_winding);
}
#[test]
fn touching_crossing_and_self_crossing_do_not_become_counters() {
    for bad in [ring(&[(0.,2.),(0.,4.),(4.,4.),(4.,2.),(0.,2.)]),ring(&[(5.,5.),(15.,5.),(15.,8.),(5.,5.)]),ring(&[(2.,2.),(8.,8.),(2.,8.),(8.,2.),(3.,1.),(2.,2.)])] {
        let result=preserve_reference(glyph(vec![outer(),bad]));
        if let GlyphSliceResult::Drawn{internal,..}=result {
            assert!(internal.containment_observations.is_empty());
            assert!(internal.open_boundaries.iter().any(|b|matches!(b,InternalBoundary::TouchingOrIntersectingRingsUnresolved)));
        }
        // Zero-area degeneracy may be impossible rather than an observation.
    }
}
#[test]
fn concave_crossing_with_inside_vertices_is_guarded() {
    // U-shaped concave outer; triangle bridge exits the U despite inside vertices.
    let concave=ring(&[(0.,0.),(10.,0.),(10.,10.),(7.,10.),(7.,3.),(3.,3.),(3.,10.),(0.,10.),(0.,0.)]);
    let bridge=ring(&[(1.,8.),(9.,8.),(5.,1.),(1.,8.)]);
    let GlyphSliceResult::Drawn{internal,..}=preserve_reference(glyph(vec![concave,bridge])) else {panic!();};
    assert!(internal.containment_observations.is_empty());
    assert!(internal.open_boundaries.iter().any(|b|matches!(b,InternalBoundary::TouchingOrIntersectingRingsUnresolved)));
}
#[test]
fn curved_counter_is_explicitly_unresolved_and_siblings_continue() {
    let start=Point{x:2.,y:2.};
    let curved=ReferenceRing{start,spans:vec![Span::Cubic{control_one:Point{x:2.,y:8.},control_two:Point{x:8.,y:8.},end:start}]};
    let valid=glyph(vec![outer(),curved]);
    let invalid=glyph(vec![ring(&[(0.,0.),(1.,0.),(1.,1.)])]);
    let results=preserve_reference_batch(vec![invalid,valid]);
    assert!(matches!(results[0],GlyphSliceResult::Impossible{..}));
    let GlyphSliceResult::Drawn{internal,..}=&results[1] else {panic!();};
    assert!(internal.containment_observations.is_empty());
    assert!(internal.open_boundaries.iter().any(|b|matches!(b,InternalBoundary::CurvedRingContainmentUnresolved)));
}
