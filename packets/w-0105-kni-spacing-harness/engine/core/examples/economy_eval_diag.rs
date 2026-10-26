//! Diagnostic: dump base/econ rings and extrema classification for one tile.
//! args: png eps K fit_se fit_refits steps
use kni_core::{capture::capture_png,capture_fit::{fit_captured,fit_captured_with_economy},cubic_fit::FitPolicy,economy_eval::extrema_vertices,reference_slice::{ReferenceRing,Span}};
fn dump(r:&ReferenceRing)->String{let mut o=format!("start=({},{})",r.start.x,r.start.y);for s in &r.spans{match s{Span::Line{end}=>o+=&format!(" L({},{})",end.x,end.y),Span::Cubic{control_one:a,control_two:b,end}=>o+=&format!(" C({},{},{},{},{},{})",a.x,a.y,b.x,b.y,end.x,end.y)}}o}
fn main(){let a:Vec<String>=std::env::args().collect();
 let png=std::fs::read(&a[1]).unwrap();let eps:f64=a[2].parse().unwrap();let k:f64=a[3].parse().unwrap();
 let mc=capture_png(&png,eps).unwrap();let pol=FitPolicy{squared_error:a[4].parse().unwrap(),max_refits:a[5].parse().unwrap()};
 let (b,..)=fit_captured(&mc.rings,k,&pol);let (e,..)=fit_captured_with_economy(&mc.rings,k,&pol);
 for i in 0..b.len(){println!("ring{i} base: {}",dump(&b[i]));println!("ring{i} econ: {}",dump(&e[i]));
  println!("ring{i} base_extrema={:?}",extrema_vertices(&b[i]));println!("ring{i} econ_extrema={:?}",extrema_vertices(&e[i]));}}
