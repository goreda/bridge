// Post-fit duplicate cleanup (development list #2): removal rules, ledger, remaining report.
use kni_core::duplicate_point_audit::{audit_duplicate_points,tidy_duplicate_points,AuditError,RemovalKind};
use kni_core::reference_slice::{DrawnGlyph,Point,ReferenceRing,Span};
use kni_core::svg_outline::{outline_svg,outline_svg_tidy,FillRule,SourceViewport};

fn p(x:f64,y:f64)->Point{Point{x,y}}
fn view()->SourceViewport{SourceViewport{x:0.,y:0.,width:100.,height:100.}}

#[test]
fn zero_length_line_removed_with_typed_ledger_row(){
    let g=DrawnGlyph{glyph_id:"dup-line".into(),rings:vec![ReferenceRing{start:p(0.,0.),spans:vec![
        Span::Line{end:p(10.,0.)},Span::Line{end:p(10.,0.)},Span::Line{end:p(10.,10.)},Span::Line{end:p(0.,0.)}]}]};
    let before=audit_duplicate_points(&g).unwrap();
    assert_eq!(before.consecutive,1);
    let (cleaned,report)=tidy_duplicate_points(&g).unwrap();
    assert_eq!(report.removals.len(),1);
    assert_eq!(report.removals[0],kni_core::duplicate_point_audit::RemovalRecord{contour:0,span_index:1,kind:RemovalKind::ZeroLengthLine,x:10.,y:0.});
    assert_eq!(cleaned.rings[0].spans.len(),3);
    assert_eq!(report.remaining.pair_count,before.pair_count-1);
    assert_eq!(report.remaining.consecutive,0);
    assert!(report.ledger_rows(&g.glyph_id).contains("kind=zero_length_line"));
}

#[test]
fn degenerate_cubic_removed_shape_bearing_cubic_kept(){
    let g=DrawnGlyph{glyph_id:"dup-cubic".into(),rings:vec![ReferenceRing{start:p(0.,0.),spans:vec![
        Span::Cubic{control_one:p(0.,0.),control_two:p(0.,0.),end:p(0.,0.)},
        Span::Cubic{control_one:p(0.,0.),control_two:p(5.,5.),end:p(10.,0.)},
        Span::Line{end:p(0.,0.)}]}]};
    let (cleaned,report)=tidy_duplicate_points(&g).unwrap();
    assert_eq!(report.removals.len(),1);
    assert_eq!(report.removals[0].kind,RemovalKind::DegenerateCubic);
    assert_eq!(cleaned.rings[0].spans.len(),2);
    // partial control coincidence is shape-bearing: kept and still counted as remaining
    assert!(report.remaining.pair_count>0);
    assert!(report.remaining.on_off>=1);
}

#[test]
fn closure_pair_and_cross_contour_shared_vertex_never_removed(){
    let g=DrawnGlyph{glyph_id:"closure".into(),rings:vec![
        ReferenceRing{start:p(0.,0.),spans:vec![Span::Line{end:p(10.,0.)},Span::Line{end:p(10.,10.)},Span::Line{end:p(0.,0.)}]},
        ReferenceRing{start:p(0.,0.),spans:vec![Span::Line{end:p(-10.,0.)},Span::Line{end:p(0.,0.)}]}]};
    let (cleaned,report)=tidy_duplicate_points(&g).unwrap();
    assert!(report.removals.is_empty());
    assert_eq!(report.remaining.explicit_closure_pairs,2);
    assert!(report.remaining.different_contour>=1);
    assert_eq!(format!("{:?}",cleaned),format!("{:?}",g));
}

#[test]
fn signed_zero_duplicate_removed(){
    let g=DrawnGlyph{glyph_id:"signed-zero".into(),rings:vec![ReferenceRing{start:p(-0.,0.),spans:vec![
        Span::Line{end:p(0.,0.)},Span::Line{end:p(10.,0.)},Span::Line{end:p(-0.,0.)}]}]};
    let (cleaned,report)=tidy_duplicate_points(&g).unwrap();
    assert_eq!(report.removals.len(),1);
    assert_eq!(cleaned.rings[0].spans.len(),2);
}

#[test]
fn nonfinite_refused_not_cleaned(){
    let g=DrawnGlyph{glyph_id:"bad".into(),rings:vec![ReferenceRing{start:p(f64::NAN,0.),spans:vec![Span::Line{end:p(1.,0.)}]}]};
    assert!(matches!(tidy_duplicate_points(&g),Err(AuditError::NonFiniteCoordinate{contour:0,position:0})));
}

#[test]
fn fully_redundant_ring_kept_and_noted(){
    let g=DrawnGlyph{glyph_id:"speck".into(),rings:vec![ReferenceRing{start:p(3.,3.),spans:vec![
        Span::Line{end:p(3.,3.)},Span::Cubic{control_one:p(3.,3.),control_two:p(3.,3.),end:p(3.,3.)}]}]};
    let (cleaned,report)=tidy_duplicate_points(&g).unwrap();
    assert_eq!(report.removals.len(),2);
    assert_eq!(report.kept_degenerate_rings,vec![0]);
    assert_eq!(cleaned.rings[0].spans.len(),2);
    assert!(report.ledger_rows(&g.glyph_id).contains("ring_kept_degenerate"));
}

#[test]
fn svg_tidy_matches_plain_bytes_when_no_duplicates(){
    let g=DrawnGlyph{glyph_id:"clean".into(),rings:vec![ReferenceRing{start:p(0.,0.),spans:vec![
        Span::Line{end:p(10.,0.)},Span::Line{end:p(10.,10.)},Span::Line{end:p(0.,0.)}]}]};
    let (svg,report)=outline_svg_tidy(&g,view(),FillRule::NonZero).unwrap();
    assert!(report.removals.is_empty());
    assert_eq!(svg,outline_svg(&g,view(),FillRule::NonZero).unwrap());
}

#[test]
fn svg_tidy_drops_duplicate_and_preserves_closure(){
    let g=DrawnGlyph{glyph_id:"dup".into(),rings:vec![ReferenceRing{start:p(0.,0.),spans:vec![
        Span::Line{end:p(10.,0.)},Span::Line{end:p(10.,0.)},Span::Line{end:p(0.,0.)}]}]};
    let (svg,report)=outline_svg_tidy(&g,view(),FillRule::NonZero).unwrap();
    assert_eq!(report.removals.len(),1);
    assert_eq!(svg,"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 100 100\"><path d=\"M0 0L10 0L0 0Z\" fill-rule=\"nonzero\"/></svg>");
    // cleaned glyph remains a valid closed outline for the plain writer
    let (cleaned,_)=tidy_duplicate_points(&g).unwrap();
    assert!(outline_svg(&cleaned,view(),FillRule::NonZero).is_ok());
}
