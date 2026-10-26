use kni_core::{capture::{capture_png,capture_png_with_lineage},cubic_fit::FitPolicy,reference_slice::DrawnGlyph,cff_container::{charstring,CffGlyph},source_provenance::ParentBinding};
fn main(){let a:Vec<String>=std::env::args().collect();let mc=capture_png(&std::fs::read(&a[1]).unwrap(),0.5).unwrap();let(indexed,lineage)=capture_png_with_lineage(&std::fs::read(&a[1]).unwrap(),0.5).unwrap();assert_eq!(mc.rings.len(),indexed.rings.len());for (a,b) in mc.rings.iter().zip(&indexed.rings){assert_eq!(a.points,b.points);assert_eq!(a.raw,b.raw);assert_eq!(a.corners,b.corners);}assert_eq!(lineage.len(),indexed.rings.len());let policy=FitPolicy{squared_error:0.1,max_refits:6};let k=690./403.5087719298246;
let (rings,_,_,_,provenance)=kni_core::capture_fit::fit_captured_with_provenance(&indexed.rings,k,&policy);
let base=kni_core::capture_fit::fit_captured(&mc.rings,k,&policy).0;
let glyph=|rings|CffGlyph{name:"probe".into(),advance:1000,outline:DrawnGlyph{glyph_id:"probe".into(),rings}};
let b=charstring(&glyph(base)).unwrap();let p=charstring(&glyph(rings)).unwrap();assert_eq!(b,p,"observer must not change canonical charstring");std::fs::write(&a[2],p).unwrap();
let (mut exact,mut synthetic,mut unresolved)=(0,0,0);for r in provenance{for s in r.emitted{match s.binding{ParentBinding::ExactRoundedParent{..}=>exact+=1,ParentBinding::SyntheticClosure{..}=>synthetic+=1,ParentBinding::Unresolved{..}=>unresolved+=1}}}
println!("exact={exact} synthetic={synthetic} unresolved={unresolved}");}
