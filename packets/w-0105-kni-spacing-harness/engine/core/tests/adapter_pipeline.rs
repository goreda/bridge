// Adapter -> supplied outline -> SVG integration expectations, NOT_RUN.
use kni_core::decision_evidence_envelope::PinClaim;
use kni_core::method_domains::{prepare_domains,PolicySlot,DomainMethod,SourceLandmarks,DomainBoundary};
use kni_core::reference_slice::{ReferenceGlyph,ReferenceRing,Span,Point,preserve_reference,GlyphSliceResult};
use kni_core::svg_outline::{outline_svg,FillRule,SourceViewport};
fn pin()->PinClaim {PinClaim{algorithm:String::from("fixture"),claimed_digest:String::from("unverified"),subject_ref:String::from("square")}}
fn glyph()->ReferenceGlyph {ReferenceGlyph{glyph_id:String::from("square"),source_pin:pin(),rings:vec![ReferenceRing{start:Point{x:0.,y:0.},spans:vec![Span::Line{end:Point{x:10.,y:0.}},Span::Line{end:Point{x:10.,y:10.}},Span::Line{end:Point{x:0.,y:10.}},Span::Line{end:Point{x:0.,y:0.}}]}],declared_junction_decision_required:true}}
fn slot(method:DomainMethod)->PolicySlot {PolicySlot{domain_method:method,domain_method_source:pin(),ranking:None,ranking_binding:None,calibration_revision:None,holdout_evidence:vec![]}}
fn svg(g:ReferenceGlyph)->String {
    let GlyphSliceResult::Drawn{output,..}=preserve_reference(g) else {panic!();};
    outline_svg(&output,SourceViewport{x:0.,y:0.,width:10.,height:10.},FillRule::NonZero).unwrap()
}
const EXPECTED:&str="<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><path d=\"M0 0L10 0L10 10L0 10L0 0Z\" fill-rule=\"nonzero\"/></svg>";
#[test]
fn whole_contour_keeps_source_seam_and_supplied_output() {
    let g=glyph();let domains=prepare_domains(&g,&[],&slot(DomainMethod::WholeContour));
    assert_eq!(domains.domains.len(),1);
    assert_eq!((domains.domains[0].start_endpoint,domains.domains[0].end_endpoint),(0,4));
    assert!(domains.unresolved.iter().any(|b|matches!(b,DomainBoundary::JunctionConnectionUnresolved)));
    assert_eq!(svg(g),EXPECTED);
}
#[test]
fn landmarks_only_split_declared_domains_without_changing_geometry() {
    let g=glyph();let landmarks=vec![SourceLandmarks{ring_index:0,endpoint_indices:vec![0,2],source_evidence:pin()}];
    let domains=prepare_domains(&g,&landmarks,&slot(DomainMethod::LandmarkRegions));
    assert_eq!(domains.domains.len(),2);
    assert_eq!((domains.domains[0].start_endpoint,domains.domains[0].end_endpoint),(0,2));
    assert_eq!((domains.domains[1].start_endpoint,domains.domains[1].end_endpoint),(2,0));
    assert!(domains.domains.iter().all(|d|d.representations.len()==3));
    assert_eq!(svg(g),EXPECTED);
}
#[test]
fn missing_or_invalid_landmarks_never_guess_a_junction() {
    for landmarks in [vec![],vec![SourceLandmarks{ring_index:0,endpoint_indices:vec![0],source_evidence:pin()}],vec![SourceLandmarks{ring_index:0,endpoint_indices:vec![0,99],source_evidence:pin()}]] {
        let g=glyph();let domains=prepare_domains(&g,&landmarks,&slot(DomainMethod::LandmarkRegions));
        assert!(domains.domains.is_empty());
        assert!(!domains.unresolved.is_empty());
        assert_eq!(svg(g),EXPECTED);
    }
}
