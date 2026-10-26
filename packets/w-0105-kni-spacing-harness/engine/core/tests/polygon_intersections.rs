// Authored fixtures NOT_RUN; binary64 observations, no exact topology proof.
use kni_core::reference_slice::Point;
use kni_core::polygon_intersections::{segment_relation,ring_edges_disjoint,ring_is_simple_observation,SegmentRelation};
fn p(x:f64,y:f64)->Point {Point{x,y}}
#[test]
fn crossing_contact_overlap_and_disjoint() {
    assert_eq!(segment_relation(p(0.,0.),p(2.,2.),p(0.,2.),p(2.,0.)),SegmentRelation::ProperCrossing);
    assert_eq!(segment_relation(p(0.,0.),p(2.,0.),p(2.,0.),p(2.,2.)),SegmentRelation::TouchingOrCollinearOverlap);
    assert_eq!(segment_relation(p(0.,0.),p(3.,0.),p(1.,0.),p(4.,0.)),SegmentRelation::TouchingOrCollinearOverlap);
    assert_eq!(segment_relation(p(0.,0.),p(1.,0.),p(2.,0.),p(3.,0.)),SegmentRelation::Disjoint);
}
#[test]
fn self_crossing_and_degenerate_ring_not_simple() {
    assert!(!ring_is_simple_observation(&[p(0.,0.),p(2.,2.),p(0.,2.),p(2.,0.),p(0.,0.)]));
    assert!(!ring_is_simple_observation(&[p(0.,0.),p(0.,0.),p(2.,0.),p(2.,2.),p(0.,0.)]));
    assert!(ring_is_simple_observation(&[p(0.,0.),p(2.,0.),p(2.,2.),p(0.,2.),p(0.,0.)]));
}
#[test]
fn nested_disjoint_edges_and_crossing_pairs() {
    let outer=[p(0.,0.),p(10.,0.),p(10.,10.),p(0.,10.),p(0.,0.)];
    let inner=[p(2.,2.),p(2.,8.),p(8.,8.),p(8.,2.),p(2.,2.)];
    assert!(ring_edges_disjoint(&outer,&inner));
    let crossing=[p(5.,5.),p(15.,5.),p(15.,8.),p(5.,5.)];
    assert!(!ring_edges_disjoint(&outer,&crossing));
}
#[test]
fn overflow_and_nonfinite_are_unresolved() {
    assert_eq!(segment_relation(p(f64::NAN,0.),p(1.,0.),p(0.,1.),p(1.,1.)),SegmentRelation::NumericallyUnresolved);
    assert_eq!(segment_relation(p(-f64::MAX,0.),p(f64::MAX,1.),p(0.,0.),p(0.,1.)),SegmentRelation::NumericallyUnresolved);
}
