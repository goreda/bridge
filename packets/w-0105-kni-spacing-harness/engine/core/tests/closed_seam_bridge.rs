// Synthetic caller seam/order and byte boundaries only, not topology or quality.
use kni_core::closed_fit::{prepare_closed,ClosureAlias,RingFitInput,AssemblyBoundary};
use kni_core::cubic_fit::FitPolicy;
use kni_core::decision_evidence_envelope::PinClaim;
use kni_core::fitter_requirements::SourceFitRun;
use kni_core::reference_slice::{DrawnGlyph,Point};
use kni_core::svg_outline::{outline_svg,SourceViewport,FillRule};
use kni_core::cff_container::{charstring,CffGlyph};
fn p(x:f64,y:f64)->Point{Point{x,y}}
fn pin()->PinClaim{PinClaim{algorithm:"fixture".into(),claimed_digest:"UNVERIFIED".into(),subject_ref:"ordered-seam".into()}}
fn input(offset:f64,ring_index:usize)->RingFitInput{
 // Caller rotates seam to index4; the second span explicitly wraps7 ->0.
 let v=[p(offset+6.,6.),p(offset,6.),p(offset,0.),p(offset+6.,0.),p(offset+6.,6.)];
 let indices=[[4,5,6],[6,7,0],[0,1,2],[2,3,4]];
 let runs=(0..4).map(|i|{let a=v[i];let b=v[i+1];SourceFitRun{source_pin:pin(),frame_pin:pin(),ring_index,span_indices:indices[i].to_vec(),points:vec![a,p((a.x+b.x)/2.,(a.y+b.y)/2.),b],start_tangent:p(b.x-a.x,b.y-a.y),end_tangent:p(a.x-b.x,a.y-b.y),tangent_binding:pin(),seam_binding:pin()}}).collect();
 RingFitInput{runs,closure_alias:ClosureAlias{final_source_index:4,first_source_index:4,binding:pin()}}
}
fn policy()->FitPolicy{FitPolicy{squared_error:0.,max_refits:0}}
fn view()->SourceViewport{SourceViewport{x:0.,y:0.,width:30.,height:6.}}
#[test]fn rotated_caller_seam_and_wrapped_span_order_preserved(){let out=prepare_closed(input(0.,0),&policy());assert!(out.boundaries.is_empty());let ring=out.closed_candidate.unwrap();assert_eq!(ring.start,p(6.,6.));assert_eq!(out.pieces.iter().map(|x|x.run_index).collect::<Vec<_>>(),vec![0,0,1,1,2,2,3,3]);assert_eq!(out.retained_source.runs[1].span_indices,vec![6,7,0]);let svg=outline_svg(&DrawnGlyph{glyph_id:"rotated".into(),rings:vec![ring]},view(),FillRule::EvenOdd).unwrap();assert_eq!(svg,"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 30 6\"><path d=\"M6 6C5 6 4 6 3 6C2 6 1 6 0 6C0 5 0 4 0 3C0 2 0 1 0 0C1 0 2 0 3 0C4 0 5 0 6 0C6 1 6 2 6 3C6 4 6 5 6 6Z\" fill-rule=\"evenodd\"/></svg>");}
#[test]fn wrapped_geometry_join_missing_suppresses_candidate(){let mut i=input(0.,0);i.runs[2].points[0]=p(0.,1.);let out=prepare_closed(i,&policy());assert!(out.closed_candidate.is_none());assert!(out.boundaries.contains(&AssemblyBoundary::JoinMismatch{run:2}));}
#[test]fn wrapped_source_join_missing_suppresses_candidate(){let mut i=input(0.,0);i.runs[2].span_indices[0]=8;let out=prepare_closed(i,&policy());assert!(out.closed_candidate.is_none());assert!(out.boundaries.contains(&AssemblyBoundary::SourceJoinMismatch{run:2}));}
#[test]fn rotated_closure_alias_missing_never_inferred(){let mut i=input(0.,0);i.closure_alias.first_source_index=0;let out=prepare_closed(i,&policy());assert!(out.closed_candidate.is_none());assert!(out.boundaries.contains(&AssemblyBoundary::ClosureAliasMismatch));}
// Decode only this writer's signed16 operand subset to distinguish opcodes from operand bytes.
fn operators(bytes:&[u8])->Vec<u8>{let mut i=0;let mut ops=Vec::new();while i<bytes.len(){if bytes[i]==28{assert!(i+2<bytes.len());i+=3;}else{ops.push(bytes[i]);i+=1;}}ops}
#[test]fn two_closed_candidates_preserve_ring_order_and_byte_boundaries(){let a=prepare_closed(input(0.,0),&policy());let b=prepare_closed(input(12.,1),&policy());assert!(a.boundaries.is_empty()&&b.boundaries.is_empty());let glyph=DrawnGlyph{glyph_id:"two".into(),rings:vec![b.closed_candidate.unwrap(),a.closed_candidate.unwrap()]};let svg=outline_svg(&glyph,view(),FillRule::EvenOdd).unwrap();assert_eq!(svg.matches('Z').count(),2);let first=svg.find("M18 6").unwrap();let second=svg.find("M6 6").unwrap();assert!(first<second);let bytes=charstring(&CffGlyph{name:"two".into(),advance:500,outline:glyph}).unwrap();let ops=operators(&bytes);let mut expected=vec![21];expected.extend([8;8]);expected.push(21);expected.extend([8;8]);expected.push(14);assert_eq!(ops,expected);assert_eq!(&bytes[..10],&[28,1,244,28,0,18,28,0,6,21]);}
#[test]fn invalid_second_ring_retained_and_compound_candidate_absent(){let a=prepare_closed(input(0.,0),&policy());let mut invalid=input(12.,1);invalid.closure_alias.final_source_index=99;let b=prepare_closed(invalid,&policy());let results=vec![a,b];assert_eq!(results.len(),2);assert!(results[0].closed_candidate.is_some());assert!(results[1].boundaries.contains(&AssemblyBoundary::ClosureAliasMismatch));assert!(!results[1].pieces.is_empty());let all:Option<Vec<_>>=results.iter().map(|r|r.closed_candidate.clone()).collect();assert!(all.is_none());}
