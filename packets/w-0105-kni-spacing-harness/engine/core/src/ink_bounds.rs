//! Shared cubic ink-bounds helper (P2 proposal; H adopts for native_font hull gate + cff_container FontBBox).
//! Analytic bounds use line/cubic endpoints plus interior cubic extrema on BOTH axes.
//! Control points never contribute. Integer bounds are outward: floor(min), ceil(max),
//! after snapping values within SNAP of an integer to that integer (float-root noise only).
use crate::reference_slice::{DrawnGlyph,Span};
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum InkError { NonFinite, OpenRing, EmptyRing, OutOfI16 }
pub const SNAP:f64=1e-9;
fn roots(a:f64,b:f64,c:f64)->Vec<f64>{ // roots of a t^2 + b t + c
 if a==0.0{return if b==0.0{vec![]}else{vec![-c/b]}}
 let d=b*b-4.0*a*c;if d<0.0{return vec![]}if d==0.0{return vec![-b/(2.0*a)]}
 let q=-0.5*(b+d.sqrt().copysign(b));if q==0.0{return vec![0.0]}vec![q/a,c/q]}
fn at(a:f64,b:f64,c:f64,d:f64,t:f64)->f64{let s=1.0-t;s*s*s*a+3.0*s*s*t*b+3.0*s*t*t*c+t*t*t*d}
/// Analytic ink bounds [xmin,ymin,xmax,ymax]; None when the glyph has no rings (space/.notdef-empty).
/// Validates finite coordinates, non-empty rings and exact ring closure.
pub fn analytic_ink_bounds(g:&DrawnGlyph)->Result<Option<[f64;4]>,InkError>{
 let mut b=None::<[f64;4]>;
 let mut add=|x:f64,y:f64|{b=Some(match b{None=>[x,y,x,y],Some(v)=>[v[0].min(x),v[1].min(y),v[2].max(x),v[3].max(y)]})};
 for ring in &g.rings{
  if ring.spans.is_empty(){return Err(InkError::EmptyRing)}
  let mut p=ring.start;if !p.x.is_finite()||!p.y.is_finite(){return Err(InkError::NonFinite)}add(p.x,p.y);
  for s in &ring.spans{match s{
   Span::Line{end}=>{if !end.x.is_finite()||!end.y.is_finite(){return Err(InkError::NonFinite)}add(end.x,end.y);p=*end}
   Span::Cubic{control_one:c1,control_two:c2,end:e}=>{
    if ![c1.x,c1.y,c2.x,c2.y,e.x,e.y].iter().all(|v|v.is_finite()){return Err(InkError::NonFinite)}
    add(e.x,e.y);
    let rx=roots(-p.x+3.0*c1.x-3.0*c2.x+e.x,2.0*(p.x-2.0*c1.x+c2.x),c1.x-p.x);
    let ry=roots(-p.y+3.0*c1.y-3.0*c2.y+e.y,2.0*(p.y-2.0*c1.y+c2.y),c1.y-p.y);
    for t in rx.into_iter().chain(ry){if t>0.0&&t<1.0{add(at(p.x,c1.x,c2.x,e.x,t),at(p.y,c1.y,c2.y,e.y,t))}}
    p=*e}}}
  if p!=ring.start{return Err(InkError::OpenRing)}
 }
 Ok(b)
}
fn snap(v:f64)->f64{let r=v.round();if (v-r).abs()<=SNAP{r}else{v}}
fn to_i16(v:f64)->Result<i16,InkError>{if !(-32768.0..=32767.0).contains(&v){return Err(InkError::OutOfI16)}Ok(v as i16)}
/// Integer outward bounds [xmin,ymin,xmax,ymax]: the single convention for head, hhea, CFF FontBBox and OS/2 clipping.
pub fn integer_outward_bounds(g:&DrawnGlyph)->Result<Option<[i16;4]>,InkError>{
 Ok(match analytic_ink_bounds(g)?{None=>None,Some(v)=>Some([to_i16(snap(v[0]).floor())?,to_i16(snap(v[1]).floor())?,to_i16(snap(v[2]).ceil())?,to_i16(snap(v[3]).ceil())?])})
}
/// Union of per-glyph integer outward bounds.
pub fn union_bounds(a:Option<[i16;4]>,b:Option<[i16;4]>)->Option<[i16;4]>{match(a,b){(None,x)|(x,None)=>x,(Some(a),Some(b))=>Some([a[0].min(b[0]),a[1].min(b[1]),a[2].max(b[2]),a[3].max(b[3])])}}
