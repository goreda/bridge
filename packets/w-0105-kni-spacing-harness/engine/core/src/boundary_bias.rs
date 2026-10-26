//! Measurement only: signed shortest distance from outline samples to the
//! source gray iso-.5 boundary. Positive = outside source ink (over-inking),
//! negative = inside source ink (under-inking). No geometry is changed.
use crate::lever_api::SourceMask;
use crate::reference_slice::{ReferenceRing,Span};
#[derive(Clone,Debug)]
pub struct BiasReport { pub samples:Vec<BiasSample>, pub mean_px:f64, pub median_px:f64, pub min_px:f64, pub max_px:f64, pub source_segments:usize, pub scale:f64 }
#[derive(Clone,Debug)]
pub struct BiasSample { pub ring:usize,pub span:usize,pub t:f64,pub x_px:f64,pub y_px:f64,pub signed_offset_px:f64 }
#[derive(Clone,Debug,PartialEq)]
pub enum BiasError {BadMask,NoSourceBoundary,NoOutlineSamples}
fn gray(m:&SourceMask,x:isize,y:isize)->f64 {if x<0||y<0||x>=m.w as isize||y>=m.h as isize{255.0}else{m.ink[y as usize*m.w+x as usize] as f64}}
fn interp(m:&SourceMask,x:f64,y:f64)->f64 {let (x,y)=(x-0.5,y-0.5);let (i,j)=(x.floor() as isize,y.floor() as isize);let (u,v)=(x-i as f64,y-j as f64);(1.0-v)*((1.0-u)*gray(m,i,j)+u*gray(m,i+1,j))+v*((1.0-u)*gray(m,i,j+1)+u*gray(m,i+1,j+1))}
fn source_boundary(m:&SourceMask)->Vec<((f64,f64),(f64,f64))>{
 let iso=(128.0+127.0)/2.0;let mut out=vec![];
 for y in -1..m.h as isize {for x in -1..m.w as isize {
  let p=[(x as f64+0.5,y as f64+0.5),(x as f64+1.5,y as f64+0.5),(x as f64+1.5,y as f64+1.5),(x as f64+0.5,y as f64+1.5)];
  let g=[gray(m,x,y),gray(m,x+1,y),gray(m,x+1,y+1),gray(m,x,y+1)];let mut cross=vec![];
  for e in 0..4 {let n=(e+1)%4;if (g[e]<iso)!=(g[n]<iso){let t=(iso-g[e])/(g[n]-g[e]);cross.push((e,(p[e].0+t*(p[n].0-p[e].0),p[e].1+t*(p[n].1-p[e].1))));}}
  if cross.len()==2{out.push((cross[0].1,cross[1].1));}
  else if cross.len()==4 {
   // Keep diagonally touching ink connected (8-connected ink, 4-connected background).
   if g[0]<iso {out.push((cross[0].1,cross[1].1));out.push((cross[2].1,cross[3].1));}
   else {out.push((cross[0].1,cross[3].1));out.push((cross[1].1,cross[2].1));}
  }
 }}out
}
fn distance(p:(f64,f64),a:(f64,f64),b:(f64,f64))->f64 {let v=(b.0-a.0,b.1-a.1);let d=v.0*v.0+v.1*v.1;let t=if d==0.0{0.0}else{(((p.0-a.0)*v.0+(p.1-a.1)*v.1)/d).clamp(0.0,1.0)};(p.0-a.0-t*v.0).hypot(p.1-a.1-t*v.1)}
/// Samples each span with count derived from control-polygon length in pixels.
/// This is a sample-weighted distribution, not a correction or an area score.
pub fn measure(rings:&[ReferenceRing],m:&SourceMask)->Result<BiasReport,BiasError>{
 if !m.valid(){return Err(BiasError::BadMask);}let boundary=source_boundary(m);if boundary.is_empty(){return Err(BiasError::NoSourceBoundary);}let mut samples=vec![];
 for (ri,r) in rings.iter().enumerate(){let mut cur=r.start;for (si,s) in r.spans.iter().enumerate(){
  let end=match s{Span::Line{end}|Span::Cubic{end,..}=>*end};let a=m.to_pixel(cur);let e=m.to_pixel(end);
  let (c1,c2)=match s{Span::Cubic{control_one,control_two,..}=>(m.to_pixel(*control_one),m.to_pixel(*control_two)),_=>(a,e)};
  let length=match s{Span::Line{..}=>(e.0-a.0).hypot(e.1-a.1),_=> (c1.0-a.0).hypot(c1.1-a.1)+(c2.0-c1.0).hypot(c2.1-c1.1)+(e.0-c2.0).hypot(e.1-c2.1)};let n=length.ceil().max(1.0) as usize;
  for k in 0..n {let t=k as f64/n as f64;let u=1.0-t;let p=match s{Span::Line{..}=>(a.0+ t*(e.0-a.0),a.1+t*(e.1-a.1)),_=>(u*u*u*a.0+3.0*u*u*t*c1.0+3.0*u*t*t*c2.0+t*t*t*e.0,u*u*u*a.1+3.0*u*u*t*c1.1+3.0*u*t*t*c2.1+t*t*t*e.1)};
   let d=boundary.iter().map(|&(a,b)|distance(p,a,b)).fold(f64::INFINITY,f64::min);let sign=if interp(m,p.0,p.1)<127.5{-1.0}else{1.0};samples.push(BiasSample{ring:ri,span:si,t,x_px:p.0,y_px:p.1,signed_offset_px:d*sign});
  }cur=end;
 }}if samples.is_empty(){return Err(BiasError::NoOutlineSamples);}let mut vals:Vec<f64>=samples.iter().map(|s|s.signed_offset_px).collect();vals.sort_by(|a,b|a.total_cmp(b));let n=vals.len();let median=if n%2==0{(vals[n/2-1]+vals[n/2])/2.0}else{vals[n/2]};Ok(BiasReport{mean_px:vals.iter().sum::<f64>()/n as f64,median_px:median,min_px:vals[0],max_px:vals[n-1],source_segments:boundary.len(),scale:m.scale,samples})
}
