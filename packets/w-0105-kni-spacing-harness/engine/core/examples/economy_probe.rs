//! Diagnostic only: caller supplies capture tolerance, fit policy and frame scale.
use kni_core::{capture::capture_png,cubic_fit::FitPolicy,reference_slice::{DrawnGlyph,Span},cff_container::{CffGlyph,charstring,cff_one}};
fn main() {
    let a:Vec<String>=std::env::args().collect();
    let png=std::fs::read(&a[1]).unwrap();let eps:f64=a[3].parse().unwrap();let scale:f64=a[4].parse().unwrap();
    let policy=FitPolicy{squared_error:a[5].parse().unwrap(),max_refits:a[6].parse().unwrap()};
    let mc=capture_png(&png,eps).unwrap();
    let (rings,count,fb,dropped,decisions)=kni_core::capture_fit::fit_captured_with_economy(&mc.rings,scale,&policy);
    let (mut l,mut c)=(0,0);
    for r in &rings {for s in &r.spans {match s {Span::Line{..}=>l+=1,Span::Cubic{..}=>c+=1}}}
    let g=CffGlyph{name:"probe".into(),advance:1000,outline:DrawnGlyph{glyph_id:"probe".into(),rings}};
    std::fs::write(format!("{}.cs",a[2]),charstring(&g).unwrap()).unwrap();
    std::fs::write(format!("{}.cff",a[2]),cff_one("EconomyProbe",&[CffGlyph{name:".notdef".into(),advance:1000,outline:DrawnGlyph{glyph_id:".notdef".into(),rings:vec![]}},g.clone()]).unwrap()).unwrap();
    println!("lines={l} cubics={c} segments={count} rings={} fallback={fb} dropped={dropped} decisions={decisions:?}",g.outline.rings.len());
}
