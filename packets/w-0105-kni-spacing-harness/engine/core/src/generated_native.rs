//! Caller-metadata construction helper for generated integer export geometry.
//! Existing native writer/assembly is unchanged. No font identity is inferred.
use crate::{reference_slice::{DrawnGlyph,Point,Span},native_font::{self,NativeFontInput},cff_container::{CffGlyph,ContainerError},ink_bounds};
use std::collections::{BTreeMap,BTreeSet};
#[derive(Clone,Debug)]
pub enum GeneratedError { InvalidMetrics, InconsistentMetrics(String), InvalidGeometry, MissingMetric(String), DuplicateGlyph, BadGlyphOrder, BadMapping, Ink(ink_bounds::InkError), Native(ContainerError) }
impl From<ink_bounds::InkError> for GeneratedError {fn from(e:ink_bounds::InkError)->Self{Self::Ink(e)}}
impl From<ContainerError> for GeneratedError {fn from(e:ContainerError)->Self{Self::Native(e)}}
fn integer(v:f64)->Result<f64,GeneratedError>{if !v.is_finite(){return Err(GeneratedError::InvalidGeometry)}let n=v.round();if !(-32768.0..=32767.0).contains(&n){return Err(GeneratedError::InvalidGeometry)}Ok(n)}
fn i16metric(v:f64)->Result<i16,GeneratedError>{if !v.is_finite()||!(-32768.0..=32767.0).contains(&v.round()){return Err(GeneratedError::InvalidMetrics)}Ok(v.round() as i16)}
fn roots(a:f64,b:f64,c:f64)->Vec<f64>{if a==0.0{return if b==0.0{vec![]}else{vec![-c/b]}}let d=b*b-4.0*a*c;if d<0.0{return vec![]}if d==0.0{return vec![-b/(2.0*a)]}let q=-0.5*(b+d.sqrt().copysign(b));vec![q/a,c/q]}
fn cubic(a:f64,b:f64,c:f64,d:f64,t:f64)->f64{let s=1.0-t;s*s*s*a+3.0*s*s*t*b+3.0*s*t*t*c+t*t*t*d}
pub fn ink_min_x(g:&DrawnGlyph)->Result<Option<f64>,GeneratedError>{
 let mut min=None::<f64>;
 let mut add=|x:f64|->Result<(),GeneratedError>{if !x.is_finite(){return Err(GeneratedError::InvalidGeometry)}min=Some(min.map_or(x,|m|m.min(x)));Ok(())};
 for ring in &g.rings{if ring.spans.is_empty(){return Err(GeneratedError::InvalidGeometry)}let mut p=ring.start;add(p.x)?;
  if !p.y.is_finite(){return Err(GeneratedError::InvalidGeometry)}
  for span in &ring.spans{match span{Span::Line{end}=>{if !end.y.is_finite(){return Err(GeneratedError::InvalidGeometry)}add(end.x)?;p=*end},Span::Cubic{control_one:b,control_two:c,end:d}=>{
   if ![b.x,b.y,c.x,c.y,d.x,d.y].iter().all(|x|x.is_finite()){return Err(GeneratedError::InvalidGeometry)}
   add(d.x)?;let aa=-p.x+3.0*b.x-3.0*c.x+d.x;let bb=2.0*(p.x-2.0*b.x+c.x);let cc=b.x-p.x;
   for t in roots(aa,bb,cc){if t>0.0&&t<1.0{add(cubic(p.x,b.x,c.x,d.x,t))?;}}p=*d;
  }}}
  if p!=ring.start{return Err(GeneratedError::InvalidGeometry)}
 }Ok(min)
}
fn ink_width(g:&DrawnGlyph)->Result<f64,GeneratedError>{
 let lo=ink_min_x(g)?;let mut reflected=g.clone();
 for ring in &mut reflected.rings{ring.start.x = -ring.start.x;for span in &mut ring.spans{match span{Span::Line{end}=>end.x = -end.x,Span::Cubic{control_one,control_two,end}=>{control_one.x = -control_one.x;control_two.x = -control_two.x;end.x = -end.x;}}}}
 Ok(match (lo,ink_min_x(&reflected)?){(Some(a),Some(b))=> -b-a,_=>0.0})
}
/// Fixed integer export grid: resolution 1, independent half-away rounding
/// has at most 1/2 unit error for each scalar. Continuous advance identity
/// ledger uses lsb, ink width, rsb and advance, hence at most 4*(1/2)=2
/// units of rounding budget only. This is diagnostic, never an ink/hull gate.
pub const EXPORT_RESOLUTION:f64=1.0;
#[derive(Clone,Debug)]pub struct RoundingLedger{pub glyph_id:String,pub input_identity_residual:f64,pub identity_rounding_bound:f64,pub lsb_error:f64,pub rsb_error:f64,pub advance_error:f64,pub exported_control_hull_width:f64,pub measured_ink_width:f64,pub requested_lsb:f64,pub actual_ink_lsb:f64,pub lsb_quantization:f64,pub exported_hull_rsb:f64,pub exported_ink_bounds_analytic:Option<[f64;4]>,pub exported_ink_bounds_int_outward:Option<[i16;4]>,pub quantized_input_ink_xmin:f64,pub x_translation:f64}
pub fn rounding_ledger(input:&[DrawnGlyph],metrics:&[(String,f64,f64,f64)],prepared:&NativeFontInput)->Result<Vec<RoundingLedger>,GeneratedError>{
 let mut out=Vec::new();for(g,(exported,l))in input.iter().zip(prepared.glyphs.iter().zip(&prepared.left_side_bearings)){
 let row=metrics.iter().find(|r|r.0==g.glyph_id).ok_or_else(||GeneratedError::MissingMetric(g.glyph_id.clone()))?;
 let mut xs=Vec::new();for ring in &exported.outline.rings{xs.push(ring.start.x);for span in &ring.spans{match span{Span::Line{end}=>xs.push(end.x),Span::Cubic{control_one,control_two,end}=>xs.extend([control_one.x,control_two.x,end.x])}}}
 let width=if xs.is_empty(){0.0}else{xs.iter().copied().fold(f64::NEG_INFINITY,f64::max)-xs.iter().copied().fold(f64::INFINITY,f64::min)};
 let in_xmin=ink_min_x(g)?.unwrap_or(row.1);let ex_xmin=ink_min_x(&exported.outline)?.unwrap_or(*l as f64);out.push(RoundingLedger{glyph_id:g.glyph_id.clone(),input_identity_residual:row.1+ink_width(g)?+row.2-row.3,identity_rounding_bound:4.0*(EXPORT_RESOLUTION/2.0),lsb_error:*l as f64-row.1,rsb_error:row.2.round()-row.2,advance_error:exported.advance as f64-row.3,exported_control_hull_width:width,measured_ink_width:ink_width(g)?,requested_lsb:row.1,actual_ink_lsb:ex_xmin,lsb_quantization:ex_xmin-row.1,exported_hull_rsb:exported.advance as f64-*l as f64-width,exported_ink_bounds_analytic:ink_bounds::analytic_ink_bounds(&exported.outline)?,exported_ink_bounds_int_outward:ink_bounds::integer_outward_bounds(&exported.outline)?,quantized_input_ink_xmin:in_xmin,x_translation:ex_xmin-in_xmin});}Ok(out)
}
/// Metrics tuples are glyph_id, lsb, rsb, advance. RSB is validated finite;
/// exported hhea RSB is derived from rounded geometry and advance, not copied.
/// Glyph order is caller-supplied and must start with .notdef for native encode.
/// Ink placement inside the advance. Declared per style through the
/// style-spec channel, never guessed inside the engine.
/// AlignToLsb: the outline is shifted so its ink xmin lands on the declared
/// lsb, and the exported hmtx lsb follows the exported integer ink xMin
/// (status quo). TileAnchoredZeroBearing: the outline keeps its declared
/// tile-anchored coordinates untouched (no ink-left-align, no shift), and
/// the exported hmtx lsb is the declared metric row's lsb (0): the interior
/// edge margins are anatomy, not bearing.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum InkPlacement { AlignToLsb, TileAnchoredZeroBearing }
pub fn prepare_generated(glyphs:&[DrawnGlyph],mapping:&[(u32,u16)],metrics:&[(String,f64,f64,f64)],metadata:&NativeFontInput)->Result<NativeFontInput,GeneratedError>{
 prepare_generated_with_placement(glyphs,mapping,metrics,metadata,InkPlacement::AlignToLsb)
}
pub fn prepare_generated_with_placement(glyphs:&[DrawnGlyph],mapping:&[(u32,u16)],metrics:&[(String,f64,f64,f64)],metadata:&NativeFontInput,placement:InkPlacement)->Result<NativeFontInput,GeneratedError>{
 if glyphs.is_empty(){return Err(GeneratedError::InvalidMetrics)}
 let mut rows=BTreeMap::new();for (id,l,r,a) in metrics{if ![l,r,a].iter().all(|v|v.is_finite())||*a<0.0||a.round()>32767.0||rows.insert(id.as_str(),(*l,*r,*a)).is_some(){return Err(GeneratedError::InvalidMetrics)}}
 if rows.len()!=glyphs.len(){return Err(GeneratedError::InvalidMetrics)}
 let mut out=metadata.clone();out.glyphs.clear();out.left_side_bearings.clear();out.mapping=mapping.to_vec();
 let mut ids=BTreeSet::new();let mut all=None::<[i16;4]>;let(mut min_l,mut min_r,mut max_e)=(None::<i16>,None::<i16>,None::<i16>);
 for g in glyphs{if !ids.insert(g.glyph_id.as_str()){return Err(GeneratedError::DuplicateGlyph)}let &(lsb,_rsb,advance)=rows.get(g.glyph_id.as_str()).ok_or_else(||GeneratedError::MissingMetric(g.glyph_id.clone()))?;
  // Validate closure/finite raw first, quantize once, then integer translate.
  ink_min_x(g)?;let mut drawn=g.clone();
  let quantize=|p:&mut Point|->Result<(),GeneratedError>{p.x=integer(p.x)?;p.y=integer(p.y)?;Ok(())};
  for ring in &mut drawn.rings{quantize(&mut ring.start)?;for span in &mut ring.spans{match span{Span::Line{end}=>quantize(end)?,Span::Cubic{control_one,control_two,end}=>{quantize(control_one)?;quantize(control_two)?;quantize(end)?;}}}}
  let shift=match placement{InkPlacement::AlignToLsb=>ink_min_x(&drawn)?.map_or(0.0,|x|(lsb-x).round()),InkPlacement::TileAnchoredZeroBearing=>0.0};
  let actual_lsb=ink_min_x(&drawn)?.map_or(lsb,|x|x+shift);
  let transform=|p:&mut Point|->Result<(),GeneratedError>{p.x=integer(p.x+shift)?;Ok(())};
  for ring in &mut drawn.rings{transform(&mut ring.start)?;for s in &mut ring.spans{match s{Span::Line{end}=>transform(end)?,Span::Cubic{control_one,control_two,end}=>{for p in [control_one,control_two,end]{transform(p)?}}}}}
  // Single convention: analytic cubic ink extrema (x and y), integer outward. Control points never count.
  let bounds=ink_bounds::integer_outward_bounds(&drawn)?;
  // hmtx lsb follows the exported integer ink xMin so head/hhea/hmtx share one convention.
  let l=match placement{InkPlacement::AlignToLsb=>match bounds{Some(b)=>b[0],None=>i16metric(actual_lsb)?},InkPlacement::TileAnchoredZeroBearing=>i16metric(lsb)?};let a=advance.round() as u16;
  if let Some(b)=bounds{let extent=i16::try_from(l as i32+b[2] as i32-b[0] as i32).map_err(|_|GeneratedError::InvalidMetrics)?;let rsb=i16::try_from(a as i32-extent as i32).map_err(|_|GeneratedError::InvalidMetrics)?;
   min_l=Some(min_l.map_or(l,|v|v.min(l)));min_r=Some(min_r.map_or(rsb,|v|v.min(rsb)));max_e=Some(max_e.map_or(extent,|v|v.max(extent)));
   all=Some(match all{None=>b,Some(v)=>[v[0].min(b[0]),v[1].min(b[1]),v[2].max(b[2]),v[3].max(b[3])]});
  }
  out.glyphs.push(CffGlyph{name:g.glyph_id.clone(),advance:a,outline:drawn});out.left_side_bearings.push(l);
 }
 out.head.bounds=all.unwrap_or([0;4]);out.hhea.metric_count=u16::try_from(glyphs.len()).map_err(|_|GeneratedError::InvalidMetrics)?;out.hhea.advance_max=out.glyphs.iter().map(|g|g.advance).max().unwrap_or(0);out.hhea.min_lsb=min_l.unwrap_or(0);out.hhea.min_rsb=min_r.unwrap_or(0);out.hhea.max_extent=max_e.unwrap_or(0);
 Ok(out)
}
pub fn encode_generated(glyphs:&[DrawnGlyph],mapping:&[(u32,u16)],metrics:&[(String,f64,f64,f64)],metadata:&NativeFontInput)->Result<Vec<u8>,GeneratedError>{
 // Encode-boundary guards: .notdef first, every GID in range, no duplicate codepoint.
 if glyphs.first().map(|g|g.glyph_id.as_str())!=Some(".notdef"){return Err(GeneratedError::BadGlyphOrder)}
 let mut cps=BTreeSet::new();for (cp,gid) in mapping{if (*gid as usize)>=glyphs.len()||!cps.insert(*cp){return Err(GeneratedError::BadMapping)}}
 Ok(native_font::encode(&prepare_generated(glyphs,mapping,metrics,metadata)?)?)}
