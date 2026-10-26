// Authored arithmetic expectations, NOT_RUN, not reconstruction acceptance.
use kni_core::cubic_evaluation::{evaluate_cubic,SourceCubic,CubicEvaluationError};
use kni_core::decision_evidence_envelope::PinClaim;
use kni_core::reference_slice::Point;

fn source() -> SourceCubic {
    SourceCubic { source_pin:PinClaim { algorithm:String::from("fixture"),claimed_digest:String::from("not-a-real-hash"),subject_ref:String::from("synthetic-line-cubic") },
        ring_index:2,span_index:7,start:Point { x:-0.,y:0. },control_one:Point { x:1.,y:2. },control_two:Point { x:2.,y:4. },end:Point { x:3.,y:6. } }
}

#[test]
fn endpoints_exact_and_original_bits_retained() {
    let s = source();
    let first = evaluate_cubic(&s,0.).unwrap();
    let last = evaluate_cubic(&s,1.).unwrap();
    assert_eq!(first.evaluated_point.x.to_bits(),s.start.x.to_bits());
    assert_eq!(last.evaluated_point,s.end);
    assert_eq!(first.source.source_pin.claimed_digest,s.source_pin.claimed_digest);
    assert_eq!(first.source.ring_index,2);
    assert_eq!(first.source.span_index,7);
    assert_eq!(first.source.control_one,s.control_one);
}

#[test]
fn explicit_dyadic_parameters_match_linear_cubic() {
    for (t,x,y) in [(0.25,0.75,1.5),(0.5,1.5,3.),(0.75,2.25,4.5)] {
        assert_eq!(evaluate_cubic(&source(),t).unwrap().evaluated_point,Point { x,y });
    }
}

#[test]
fn parameters_fail_without_clamping() {
    for t in [-0.1,1.1] {
        assert!(matches!(evaluate_cubic(&source(),t),Err(CubicEvaluationError::ParameterOutOfRange)));
    }
    for t in [f64::NAN,f64::INFINITY,f64::NEG_INFINITY] {
        assert!(matches!(evaluate_cubic(&source(),t),Err(CubicEvaluationError::NonFiniteParameter)));
    }
}

#[test]
fn nonfinite_control_fails_without_mutating_source() {
    let mut s = source();
    s.control_two.x = f64::INFINITY;
    assert!(matches!(evaluate_cubic(&s,0.5),Err(CubicEvaluationError::NonFiniteSource)));
    assert!(s.control_two.x.is_infinite());
}
