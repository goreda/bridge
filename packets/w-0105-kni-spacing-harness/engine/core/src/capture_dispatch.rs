//! Signature dispatch to existing PNG grayscale or JPEG raw-Y capture.
//! No image conversion, scale inference or decoder budget defaults.
// Signature dispatch surface retained for existing PNG grayscale or JPEG raw-Y capture.
#[allow(unused_imports)]
use crate::capture::{capture_gray,capture_png,decode_png_gray,decode_png_gray_bounded,DecodeLimits,MeasuredContour};
use crate::jpeg_source::{self,IdentityReceipt,Limits,JpegError};
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum SourceKind { PngConvertedGrayWhiteAlpha, JpegRawY }
#[derive(Clone,Debug)]
pub struct SourceReceipt {
 pub source_kind:SourceKind,
 pub jpeg_identity:Option<IdentityReceipt>,
 pub width:usize,pub height:usize,
 pub decoder_limits:Option<Limits>,
 /// PNG path: the exact DecodeLimits the caller supplied (None on JPEG path).
 pub png_limits:Option<DecodeLimits>,
 /// Measured frame band: (top,bottom,left,right) px and the ink cells inside
 /// the band. When it holds ink, the OUTLINE domain (outline_contour /
 /// outline_gray) is traced from a band-cleared copy; the original capture
 /// keeps driving the measurement domain. ((0,0,0,0),0) on the decode-only
 /// path.
 pub frame_band_measured:((usize,usize,usize,usize),usize),
 /// Typed discriminator: which frame-evidence rule fired for this tile
 /// (the receipt's per-tile proof of WHY ink was or was not cleared).
 pub frame_band_evidence:FrameBandEvidence,
}
/// The frame-evidence decision for one tile, recorded on the receipt.
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum FrameBandEvidence {
 /// Declared frame-free style (PreserveAllInk): no measurement, nothing cleared.
 DeclaredAbsent,
 /// Measured: no per-edge frame-like line on any edge; nothing cleared.
 NoSignal,
 /// The closed-ring proof fired; only the proven ring was cleared.
 RingProofCleared,
 /// Declared framed style (SeparatePresentRing) whose closed ring was not
 /// found on this tile: nothing cleared (under-clearing is the safe direction).
 DeclaredRingNotFound,
 /// Per-edge fill-heuristic lines were present but the closed-ring proof
 /// failed or never proved an inner boundary (midline cap): letterform ink,
 /// preserved. Carries the per-edge band that was NOT acted on, so the
 /// receipt shows exactly what the fill heuristic would have eaten.
 PerEdgeRejectedNoRing((usize,usize,usize,usize)),
}
impl FrameBandEvidence{
 /// Typed receipt tag for the per-tile discriminator row.
 pub fn receipt_tag(&self)->String{
  match self{
   FrameBandEvidence::DeclaredAbsent=>"declared_absent\tcleared_ring_count\t0".to_string(),
   FrameBandEvidence::NoSignal=>"no_signal\tcleared_ring_count\t0".to_string(),
   FrameBandEvidence::RingProofCleared=>"ring_proof_cleared\tcleared_ring_count\t1".to_string(),
   FrameBandEvidence::DeclaredRingNotFound=>"declared_ring_not_found\tcleared_ring_count\t0".to_string(),
   FrameBandEvidence::PerEdgeRejectedNoRing((t,b,l,r))=>format!("per_edge_rejected_no_ring\tcleared_ring_count\t0\trejected_band_px\tt{t} b{b} l{l} r{r}"),
  }
 }
}
#[derive(Debug)]
pub enum DispatchError { UnsupportedSignature, Jpeg(JpegError), Capture(String) }
#[derive(Debug)]
pub struct CapturedSource { pub contour:MeasuredContour,pub gray:Vec<u8>,pub receipt:SourceReceipt,
 /// Presentation-border exclusion (the tile's printed edge frame is a source
 /// artifact, never font content): when the measured frame band holds ink,
 /// these carry the band-cleared trace and gray for the OUTLINE domain.
 /// `contour`/`gray` stay the original capture and keep driving the
 /// measurement domain (spacing, vertical metrics, tolerances) unchanged.
 /// None when no frame band was measured - outline domain == original.
 pub outline_contour:Option<MeasuredContour>,pub outline_gray:Option<Vec<u8>> }
#[derive(Debug)]
pub struct DecodedSource {pub width:usize,pub height:usize,pub gray:Vec<u8>,pub receipt:SourceReceipt}
/// Limits are explicit operational inputs; no guessed resource expansion.
pub fn decode_source(bytes:&[u8],png_limits:&DecodeLimits,jpeg_limits:Limits)->Result<DecodedSource,DispatchError>{
 if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
  let(w,h,gray)=decode_png_gray_bounded(bytes,png_limits).map_err(|e|DispatchError::Capture(e.to_string()))?;
  Ok(DecodedSource{width:w,height:h,gray,receipt:SourceReceipt{source_kind:SourceKind::PngConvertedGrayWhiteAlpha,jpeg_identity:None,width:w,height:h,decoder_limits:None,png_limits:Some(*png_limits),frame_band_measured:((0,0,0,0),0),frame_band_evidence:FrameBandEvidence::NoSignal}})
 } else if bytes.starts_with(&[255,216]) {
  // Single dispatcher: jpeg_source::decode_any (input bound, then first-SOF frame_kind). SOF2 -> bounded progressive decoder (its receipt names it); everything else keeps the baseline decoder and its typed refusals.
  let d=jpeg_source::decode_any(bytes,jpeg_limits).map_err(DispatchError::Jpeg)?;
  Ok(DecodedSource{width:d.w,height:d.h,gray:d.pixels,receipt:SourceReceipt{source_kind:SourceKind::JpegRawY,jpeg_identity:Some(d.receipt),width:d.w,height:d.h,decoder_limits:Some(jpeg_limits),png_limits:None,frame_band_measured:((0,0,0,0),0),frame_band_evidence:FrameBandEvidence::NoSignal}})
 } else {Err(DispatchError::UnsupportedSignature)}
}
/// Tile-frame handling policy. It is an explicit operational input declared
/// per style through the style-spec channel, never guessed inside the engine.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum FramePolicy {
 /// The printed presentation frame is a possible source artifact: a band is
 /// cleared only as a jointly-proven CLOSED frame ring whose growth ends on
 /// an interior line that fails the frame predicate (never at the midline
 /// cap alone), and the OUTLINE domain traces that ring-cleared copy while
 /// the measurement domain keeps the original capture. The per-edge growth
 /// of measure_frame_band is NOT a clearing rule: a full-height letterform
 /// stem flush to a tight crop edge is one contiguous ink run holding the
 /// continuity floor, so it seeds the "frame" and the band grows over the
 /// stem's full width (the Mercator H class: both stems of an 80x99 crop
 /// measured as l12/r13 and erased). The rejected per-edge measurement is
 /// recorded on the receipt as PerEdgeRejectedNoRing evidence.
 Measure,
 /// The style declares that its tiles carry no presentation frame at all
 /// (the frame was removed at the capture source): every pixel of the tile
 /// is glyph content, so no band is measured and no pixel is cleared. The
 /// outline domain IS the original capture; source ink is preserved one to
 /// one.
 PreserveAllInk,
 /// The style declares that its tiles CARRY a printed presentation frame: a
 /// closed rectangle ring hugging the tile edges. The band is measured from
 /// joint ring evidence alone (one contiguous end-to-end ink line per edge,
 /// the SAME measured thickness on all four edges, corners closed by
 /// construction) and only that proven ring is cleared for the OUTLINE
 /// domain: an edge-fused letterform stripe has no four-edge corroboration
 /// and can never extend the band. A tile without the full closed ring is a
 /// no-op - nothing is measured, nothing is cleared. The measurement domain
 /// keeps the original capture either way.
 SeparatePresentRing,
}
pub fn capture_source(bytes:&[u8],rdp_eps:f64,png_limits:&DecodeLimits,jpeg_limits:Limits)->Result<CapturedSource,DispatchError>{
 capture_source_with_policy(bytes,rdp_eps,png_limits,jpeg_limits,FramePolicy::Measure)
}
pub fn capture_source_with_policy(bytes:&[u8],rdp_eps:f64,png_limits:&DecodeLimits,jpeg_limits:Limits,frame_policy:FramePolicy)->Result<CapturedSource,DispatchError>{
 let decoded=decode_source(bytes,png_limits,jpeg_limits)?;
 let (measured,evidence)=match frame_policy {
  // Undeclared/measured styles: clearing is GATED by the closed-ring proof
  // (S10 capture regression): the per-edge fill
  // heuristic is measured for the receipt but never drives clearing - a
  // broken-frame false negative (frame ink kept) is the accepted direction,
  // a stem-loss false positive is not.
  FramePolicy::Measure=>{
   let per_edge=measure_frame_band(decoded.width,decoded.height,&decoded.gray);
   let ring=measure_frame_ring_proven(decoded.width,decoded.height,&decoded.gray);
   if ring.1>0 { (ring,FrameBandEvidence::RingProofCleared) }
   else if per_edge.0!=(0,0,0,0) { (((0,0,0,0),0),FrameBandEvidence::PerEdgeRejectedNoRing(per_edge.0)) }
   else { (((0,0,0,0),0),FrameBandEvidence::NoSignal) }
  },
  // Declared frame-free style: nothing is measured out, nothing is cleared.
  FramePolicy::PreserveAllInk=>(((0,0,0,0),0),FrameBandEvidence::DeclaredAbsent),
  // Declared framed style: only the jointly-proven closed frame ring.
  FramePolicy::SeparatePresentRing=>{
   let ring=measure_present_frame_ring(decoded.width,decoded.height,&decoded.gray);
   let ev=if ring.1>0 {FrameBandEvidence::RingProofCleared} else {FrameBandEvidence::DeclaredRingNotFound};
   (ring,ev)
  },
 };
 // The frame stays IN the measurement domain (profiles, spacing, kern - the
 // declared em box); the OUTLINE domain traces a band-cleared copy so the
 // printed frame never becomes a contour at all.
 let contour=capture_gray(decoded.width,decoded.height,&decoded.gray,rdp_eps).map_err(DispatchError::Capture)?;
 let (outline_contour,outline_gray)=if measured.1>0 {
  let mut cleared=decoded.gray.clone();
  clear_frame_band(decoded.width,decoded.height,&mut cleared,measured.0);
  let oc=capture_gray(decoded.width,decoded.height,&cleared,rdp_eps).map_err(DispatchError::Capture)?;
  (Some(oc),Some(cleared))
 } else { (None,None) };
 let mut receipt=decoded.receipt;
 receipt.frame_band_measured=measured;
 receipt.frame_band_evidence=evidence;
 Ok(CapturedSource{contour,gray:decoded.gray,receipt,outline_contour,outline_gray})
}

/// Border-frame handling: the tile's printed edge frame is a source
/// presentation artifact, never font content, so no emitted contour may come
/// from it. The band is MEASURED at capture; the shipped outline is traced
/// from the band-cleared copy and measurement itself is unchanged (the
/// declared em box keeps driving spacing). A presentation frame is, by evidence, a
/// CONTINUOUS dark line
/// along a tile edge; letterform bleed is sparse. Per edge, the frame band is
/// measured from the tile itself: if the outermost line is less than half ink
/// there is no frame on that edge (band 0); otherwise the band extends inward
/// while lines hold at least half of that outermost line's ink fraction.
/// Only the measured band is cleared to white: interior ink - including
/// letterforms that legitimately bleed to the tile edge - is preserved, minus
/// nothing outside the band. No invented threshold: the only constants are the
/// continuity floor (1/2) applied to the tile's own outermost line.
/// Returns ((top,bottom,left,right) band px, cells cleared).
pub fn measure_frame_band(w:usize,h:usize,gray:&[u8])->((usize,usize,usize,usize),usize){
 let n=w*h;
 if n==0||gray.len()!=n{return ((0,0,0,0),0);}
 let ink=|v:u8| v<128; // the trace iso 0.5, reused
 let row_frac=|y:usize|->f64{if w==0{return 0.0;}(0..w).filter(|&x|ink(gray[y*w+x])).count() as f64/w as f64};
 let col_frac=|x:usize|->f64{if h==0{return 0.0;}(0..h).filter(|&y|ink(gray[y*w+x])).count() as f64/h as f64};
 // A frame line is ONE contiguous ink run; a line broken into several runs
 // (stripe letterforms like Paul New percent/perthousand, bleed blobs) is
 // letterform evidence, never frame. Seed and extension both require it.
 let row_runs=|y:usize|->usize{let mut r=0;let mut p=false;for x in 0..w{let i=ink(gray[y*w+x]);if i&&!p{r+=1;}p=i;}r};
 let col_runs=|x:usize|->usize{let mut r=0;let mut p=false;for y in 0..h{let i=ink(gray[y*w+x]);if i&&!p{r+=1;}p=i;}r};
 let band=|frac:&dyn Fn(usize)->f64,runs:&dyn Fn(usize)->usize,limit:usize|->usize{
  let f0=frac(0);
  if f0<0.5||runs(0)!=1{return 0;}
  let floor=0.5*f0;
  let mut b=1;
  while b<limit&&frac(b)>=floor&&runs(b)==1{b+=1;}
  b
 };
 let limit_x={let q=w/2;if q>1{q}else{1}}; // never eat past the midline
 let limit_y={let q=h/2;if q>1{q}else{1}};
 let top=band(&row_frac,&row_runs,limit_y);
 let bottom=band(&|y| row_frac(h-1-y),&|y| row_runs(h-1-y),limit_y);
 let left=band(&col_frac,&col_runs,limit_x);
 let right=band(&|x| col_frac(w-1-x),&|x| col_runs(w-1-x),limit_x);
 let (t,b,l,r)=(top,bottom,left,right);
 let mut cells=0usize;
 if t+b+l+r>0{
  for y in 0..h{for x in 0..w{
   if (y<t||y>=h-b||x<l||x>=w-r)&&ink(gray[y*w+x]){cells+=1;}
  }}
 }
 ((t,b,l,r),cells)
}
/// Legacy per-edge diagnostic helper. Production capture does NOT use this
/// destructive heuristic; it requires the ring proof in capture_source_with_policy.
/// Retained for reproducing historical band measurements and unit controls.
pub fn clear_measured_frame_band(w:usize,h:usize,gray:&mut [u8])->((usize,usize,usize,usize),usize){
 let n=w*h;
 if n==0||gray.len()!=n{return ((0,0,0,0),0);}
 let (band,_)=measure_frame_band(w,h,gray);
 let cells=clear_frame_band(w,h,gray,band);
 (band,cells)
}
/// Clear exactly the given (top,bottom,left,right) band to white in place;
/// returns the ink cells cleared. The production capture path clears the
/// band its policy measured - never a re-measured one.
pub fn clear_frame_band(w:usize,h:usize,gray:&mut [u8],band:(usize,usize,usize,usize))->usize{
 let n=w*h;
 if n==0||gray.len()!=n{return 0;}
 let (top,bottom,left,right)=band;
 let ink=|v:u8| v<128;
 let mut cells=0usize;
 for y in 0..top{for x in 0..w{if ink(gray[y*w+x]){gray[y*w+x]=255;cells+=1;}}}
 for y in h-bottom..h{for x in 0..w{if ink(gray[y*w+x]){gray[y*w+x]=255;cells+=1;}}}
 for x in 0..left{for y in 0..h{if ink(gray[y*w+x]){gray[y*w+x]=255;cells+=1;}}}
 for x in w-right..w{for y in 0..h{if ink(gray[y*w+x]){gray[y*w+x]=255;cells+=1;}}}
 cells
}
/// Closed-ring depth walk shared by the frame proofs: grows depth t while
/// ALL FOUR edges satisfy the frame-line predicate at the next depth, never
/// past the midline. Returns (depth, stopped_by_cap): stopped_by_cap means
/// the walk ended at the geometric midline limit, not on a failing line, so
/// no interior boundary was proven (solid letterform tile, not a frame).
fn frame_ring_depth(w:usize,h:usize,gray:&[u8],line_is_frame:&dyn Fn(usize,&dyn Fn(usize)->u8)->bool)->(usize,bool){
 let limit_x={let q=w/2;if q>1{q}else{1}}; // never eat past the midline
 let limit_y={let q=h/2;if q>1{q}else{1}};
 let limit=if limit_x<limit_y{limit_x}else{limit_y};
 let mut t=0usize;
 while t<limit{
  let d=t;
  let top=line_is_frame(w,&|x| gray[d*w+x]);
  let bottom=line_is_frame(w,&|x| gray[(h-1-d)*w+x]);
  let left=line_is_frame(h,&|y| gray[y*w+d]);
  let right=line_is_frame(h,&|y| gray[y*w+(w-1-d)]);
  if top&&bottom&&left&&right{t+=1;}else{break;}
 }
 (t,t>=limit&&limit>0&&t>0)
}
/// The frame-line predicate shared by the ring proofs: one contiguous ink
/// run touching both ends of the line, holding the 1/2 continuity floor.
fn frame_line_predicate()->impl Fn(usize,&dyn Fn(usize)->u8)->bool {
 |len:usize,at:&dyn Fn(usize)->u8|->bool{
  if len==0{return false;}
  let ink=|v:u8| v<128;
  if !ink(at(0))||!ink(at(len-1)){return false;}
  let mut runs=0usize;let mut prev=false;let mut cells=0usize;
  for i in 0..len{let k=ink(at(i));if k{cells+=1;if !prev{runs+=1;}}prev=k;}
  runs==1&&cells*2>=len
 }
}
/// Presentation-frame measurement for undeclared/measured styles
/// (FramePolicy::Measure): the closed-ring proof of
/// measure_present_frame_ring, PLUS the requirement that the proof terminate
/// on an interior line that FAILS the frame predicate. A "ring" whose growth
/// stops only at the midline cap never proved an inner boundary: solid
/// letterform tiles (a tight-cropped hyphen, I, l) are all ink, and clearing
/// to the midline would erase the glyph. A tile whose edges do not all carry
/// the ring is a no-op. No new constants: the 1/2 continuity floor and the
/// midline cap are the existing ones.
pub fn measure_frame_ring_proven(w:usize,h:usize,gray:&[u8])->((usize,usize,usize,usize),usize){
 let n=w*h;
 if n==0||gray.len()!=n{return ((0,0,0,0),0);}
 let pred=frame_line_predicate();
 let (t,cap)=frame_ring_depth(w,h,gray,&pred);
 if t==0||cap{return ((0,0,0,0),0);}
 let ink=|v:u8| v<128;
 let mut cells=0usize;
 for y in 0..h{for x in 0..w{
  if (y<t||y>=h-t||x<t||x>=w-t)&&ink(gray[y*w+x]){cells+=1;}
 }}
 ((t,t,t,t),cells)
}
/// Presentation-frame separation for declared-framed tiles
/// (FramePolicy::SeparatePresentRing). The printed frame is, by evidence, a
/// CLOSED RECTANGLE RING: one contiguous ink line per tile edge, every line
/// running corner to corner (the corners close the ring), all four edges at
/// the SAME printed thickness. The band is measured depth by depth and grows
/// only while ALL FOUR edges satisfy the line predicate at the next depth,
/// so letterform ink fused with one edge - a percent/perthousand stripe, a
/// bleed bar - has no four-edge corroboration and can never extend the band
/// (the per-edge growth of measure_frame_band could, and did: 58 px on the
/// pinned percent tile, deleting a real stripe). A tile whose edges do not
/// all carry the ring is a no-op. No stripe thickness or fullness heuristic,
/// no hardcoded px: the only constant is the 1/2 continuity floor already
/// used by the measured-band rule. Returns ((top,bottom,left,right) band px,
/// ink cells in band); the band is the measured uniform thickness on every
/// edge.
pub fn measure_present_frame_ring(w:usize,h:usize,gray:&[u8])->((usize,usize,usize,usize),usize){
 let n=w*h;
 if n==0||gray.len()!=n{return ((0,0,0,0),0);}
 let pred=frame_line_predicate();
 let (t,_)=frame_ring_depth(w,h,gray,&pred);
 if t==0{return ((0,0,0,0),0);}
 let ink=|v:u8| v<128;
 let mut cells=0usize;
 for y in 0..h{for x in 0..w{
  if (y<t||y>=h-t||x<t||x>=w-t)&&ink(gray[y*w+x]){cells+=1;}
 }}
 ((t,t,t,t),cells)
}

#[cfg(test)]
mod border_frame_tests{
 use super::*;
 fn framed(w:usize,h:usize)->Vec<u8>{
  let mut g=vec![255u8;w*h];
  for x in 0..w{for y in 0..2{g[y*w+x]=0;g[(h-1-y)*w+x]=0;}}
  for y in 0..h{for x in 0..2{g[y*w+x]=0;g[y*w+(w-1-x)]=0;}}
  g
 }
 #[test]
 fn frame_band_measured_and_cut_interior_preserved(){
  let (w,h)=(40usize,30usize);
  let mut g=framed(w,h);
  for y in 10..16{for x in 12..20{g[y*w+x]=0;}}
  let ((t,b,l,r),_)=clear_measured_frame_band(w,h,&mut g);
  assert_eq!((t,b,l,r),(2,2,2,2));
  for y in 10..16{for x in 12..20{assert_eq!(g[y*w+x],0,"interior ink must survive");}}
  // pixel-level: the frame cells are white after the cut
  for y in 0..h{for x in 0..2{assert_eq!(g[y*w+x],255,"frame column must be cleared");}}
  for x in 0..w{for y in 0..2{assert_eq!(g[y*w+x],255,"frame row must be cleared");}}
  // contour-level: capture normalizes origin to the content bbox min, so the
  // only surviving ring is the interior square: one ring, bbox ~= 8x6 px
  // (iso 0.5 can extend half a pixel past the ink cells).
  let mc=capture_gray(w,h,&g,0.75).expect("interior blob traces");
  assert_eq!(mc.rings.len(),1,"frame ring must be gone, only the interior square remains");
  let r=&mc.rings[0];
  let mnx=r.raw.iter().map(|p|p.x).fold(f64::INFINITY,f64::min);
  let mxx=r.raw.iter().map(|p|p.x).fold(f64::NEG_INFINITY,f64::max);
  let mny=r.raw.iter().map(|p|p.y).fold(f64::INFINITY,f64::min);
  let mxy=r.raw.iter().map(|p|p.y).fold(f64::NEG_INFINITY,f64::max);
  assert!((mxx-mnx-8.0).abs()<=1.0,"content width must be the interior square, not the frame: {}",mxx-mnx);
  assert!((mxy-mny-6.0).abs()<=1.0,"content height must be the interior square, not the frame: {}",mxy-mny);
 }
 #[test]
 fn letterform_bleed_without_frame_is_preserved(){
  let (w,h)=(20usize,20usize);
  let mut g=vec![255u8;w*h];
  for y in 8..12{for x in 0..6{g[y*w+x]=0;}} // bar bleeding off the left edge, no frame
  let before=g.clone();
  let ((t,b,l,r),cells)=clear_measured_frame_band(w,h,&mut g);
  assert_eq!((t,b,l,r),(0,0,0,0));
  assert_eq!(cells,0);
  assert_eq!(g,before,"sparse edge contact is letterform, not frame");
 }
 #[test]
 fn frame_cut_keeps_bleed_beyond_band(){
  let (w,h)=(20usize,20usize);
  let mut g=framed(w,h);
  for y in 8..12{for x in 0..8{g[y*w+x]=0;}} // bar bleeding into the frame band
  let ((t,b,l,r),_)=clear_measured_frame_band(w,h,&mut g);
  assert_eq!((t,b,l,r),(2,2,2,2));
  for y in 8..12{for x in 2..8{assert_eq!(g[y*w+x],0,"bleed beyond the band must survive");}}
 }
 #[test]
 fn clean_interior_is_byte_untouched(){
  let (w,h)=(20usize,20usize);
  let mut g=vec![255u8;w*h];
  for y in 5..10{for x in 5..10{g[y*w+x]=0;}}
  let before=g.clone();
  let (bands,cells)=clear_measured_frame_band(w,h,&mut g);
  assert_eq!(bands,(0,0,0,0));
  assert_eq!(cells,0);
  assert_eq!(g,before);
 }
}

#[cfg(test)]
mod present_ring_tests{
 use super::*;
 /// 2px closed frame ring on all four edges + interior letterform.
 fn framed(w:usize,h:usize)->Vec<u8>{
  let mut g=vec![255u8;w*h];
  for x in 0..w{for y in 0..2{g[y*w+x]=0;g[(h-1-y)*w+x]=0;}}
  for y in 0..h{for x in 0..2{g[y*w+x]=0;g[y*w+(w-1-x)]=0;}}
  g
 }
 #[test]
 fn closed_ring_is_measured_uniformly_on_all_four_edges(){
  let (w,h)=(40usize,30usize);
  let mut g=framed(w,h);
  for y in 10..16{for x in 12..20{g[y*w+x]=0;}} // interior letterform blob
  let (band,cells)=measure_present_frame_ring(w,h,&g);
  assert_eq!(band,(2,2,2,2));
  assert!(cells>0);
  let before=g.clone();
  let cleared=clear_frame_band(w,h,&mut g,band);
  assert_eq!(cleared,cells);
  for y in 10..16{for x in 12..20{assert_eq!(g[y*w+x],0,"interior ink must survive");}}
  for y in 0..h{for x in 0..w{
   let in_band=y<2||y>=h-2||x<2||x>=w-2;
   if !in_band{assert_eq!(g[y*w+x],before[y*w+x],"no pixel outside the band may change");}
  }}
 }
 #[test]
 fn edge_fused_stripe_never_extends_the_ring(){
  // The percent-tile defect class: a full-height stripe fused with the
  // right edge is letterform, not frame; the joint rule keeps the band at
  // the proven ring thickness where the per-edge rule ran 10px deep.
  let (w,h)=(30usize,20usize);
  let mut g=framed(w,h);
  for y in 2..h-2{for x in w-10..w{g[y*w+x]=0;}} // wide stripe fused to the right edge
  let (band,_)=measure_present_frame_ring(w,h,&g);
  assert_eq!(band,(2,2,2,2),"the stripe must not extend the proven ring");
  let kept=g.clone();
  clear_frame_band(w,h,&mut g,band);
  for y in 2..h-2{for x in w-10..w-2{assert_eq!(g[y*w+x],0,"stripe ink beyond the ring must survive ({y},{x})");}}
  let _=kept;
 }
 #[test]
 fn no_closed_ring_is_a_noop(){
  // Letterform bleed only: no frame at all.
  let (w,h)=(20usize,20usize);
  let mut g=vec![255u8;w*h];
  for y in 8..12{for x in 0..6{g[y*w+x]=0;}}
  let before=g.clone();
  let (band,cells)=measure_present_frame_ring(w,h,&g);
  assert_eq!(band,(0,0,0,0));
  assert_eq!(cells,0);
  assert_eq!(g,before);
 }
 #[test]
 fn three_edges_are_not_a_ring(){
  // Frame lines on three edges only: not a proven presentation frame.
  let (w,h)=(30usize,20usize);
  let mut g=vec![255u8;w*h];
  for x in 0..w{for y in 0..2{g[y*w+x]=0;g[(h-1-y)*w+x]=0;}}
  for y in 0..h{for x in 0..2{g[y*w+x]=0;}}
  let before=g.clone();
  let (band,cells)=measure_present_frame_ring(w,h,&g);
  assert_eq!(band,(0,0,0,0));
  assert_eq!(cells,0);
  assert_eq!(g,before,"partial edge coverage is never cleared");
 }
 #[test]
 fn a_broken_frame_line_is_a_noop_not_a_guess(){
  // The top line is broken into two runs: the joint proof fails, nothing
  // is cleared (under-clearing is the safe direction).
  let (w,h)=(30usize,20usize);
  let mut g=framed(w,h);
  g[0*w+15]=255; // hole in the top frame line
  let before=g.clone();
  let (band,cells)=measure_present_frame_ring(w,h,&g);
  assert_eq!(band,(0,0,0,0));
  assert_eq!(cells,0);
  assert_eq!(g,before);
 }
 #[test]
 fn frame_only_tile_clears_to_empty_glyph(){
  let (w,h)=(40usize,30usize);
  let mut g=framed(w,h);
  let (band,cells)=measure_present_frame_ring(w,h,&g);
  assert_eq!(band,(2,2,2,2));
  assert_eq!(clear_frame_band(w,h,&mut g,band),cells);
  assert!(g.iter().all(|&v| v==255));
 }
 #[test]
 fn midline_is_never_crossed(){
  // Even a pathological full-ink tile stops at the midline.
  let (w,h)=(8usize,8usize);
  let g=vec![0u8;w*h];
  let (band,_)=measure_present_frame_ring(w,h,&g);
  assert_eq!(band,(4,4,4,4));
 }
}

#[cfg(test)]
mod ring_proven_tests{
 use super::*;
 /// Mercator H class: full-height letterform bars flush to both side edges
 /// of a tight crop, joined by a crossbar. No printed frame anywhere.
 fn h_like(w:usize,h:usize)->Vec<u8>{
  let mut g=vec![255u8;w*h];
  for y in 0..h{for x in 0..6{g[y*w+x]=0;} for x in w-7..w{g[y*w+x]=0;}}
  for y in h/2-2..h/2+2{for x in 0..w{g[y*w+x]=0;}}
  g
 }
 #[test]
 fn edge_flush_stems_seed_per_edge_but_have_no_ring(){
  let (w,h)=(40usize,30usize);
  let g=h_like(w,h);
  // the defect class, pinned: the per-edge fill heuristic seeds on the stems
  let (per_edge,_)=measure_frame_band(w,h,&g);
  assert!(per_edge.2>0&&per_edge.3>0,"stems seed the per-edge rule: {per_edge:?}");
  // the closed-ring proof refuses: nothing may be cleared
  assert_eq!(measure_frame_ring_proven(w,h,&g),((0,0,0,0),0));
 }
 #[test]
 fn solid_bar_tile_reaches_midline_cap_and_is_unproven(){
  // hyphen/I class: a solid bar filling its tight crop (bbox == ink); every
  // edge line stays frame-like to the midline, so no inner boundary is ever
  // proven.
  let (w,h)=(24usize,11usize);
  let g=vec![0u8;w*h];
  let pred=frame_line_predicate();
  let (t,cap)=frame_ring_depth(w,h,&g,&pred);
  assert!(t>0&&cap,"solid bar grows to the midline cap: t={t} cap={cap}");
  assert_eq!(measure_frame_ring_proven(w,h,&g),((0,0,0,0),0),"no proven inner boundary: nothing cleared");
 }
 #[test]
 fn closed_ring_with_interior_is_proven(){
  let (w,h)=(40usize,30usize);
  let mut g=vec![255u8;w*h];
  for x in 0..w{for y in 0..2{g[y*w+x]=0;g[(h-1-y)*w+x]=0;}}
  for y in 0..h{for x in 0..2{g[y*w+x]=0;g[y*w+(w-1-x)]=0;}}
  for y in 10..16{for x in 12..20{g[y*w+x]=0;}} // interior letterform
  let (band,cells)=measure_frame_ring_proven(w,h,&g);
  assert_eq!(band,(2,2,2,2),"the proven ring still fires");
  assert!(cells>0);
 }
 #[test]
 fn broken_ring_line_is_unproven(){
  let (w,h)=(40usize,30usize);
  let mut g=vec![255u8;w*h];
  for x in 0..w{for y in 0..2{g[y*w+x]=0;g[(h-1-y)*w+x]=0;}}
  for y in 0..h{for x in 0..2{g[y*w+x]=0;g[y*w+(w-1-x)]=0;}}
  g[15]=255; // hole in the top frame line
  assert_eq!(measure_frame_ring_proven(w,h,&g),((0,0,0,0),0));
 }
 #[test]
 fn policy_measure_preserves_edge_flush_stems_and_records_evidence(){
  // capture-level, through FramePolicy::Measure on real PNG bytes: the H
  // class tile ships its full outline and the receipt carries the typed
  // discriminator naming the rejected per-edge band.
  let (w,h)=(40usize,30usize);
  let g=h_like(w,h);
  let png=crate::curve_stress::encode_png_gray(w,h,&g).expect("png encode");
  let pl=DecodeLimits{max_input_bytes:1<<20,max_pixels:1<<20,max_working_bytes:1<<24};
  let jl=Limits{max_input_bytes:1<<20,max_pixels:1<<20,max_working_bytes:1<<24};
  let src=capture_source_with_policy(&png,0.5,&pl,jl,FramePolicy::Measure).expect("capture");
  assert_eq!(src.receipt.frame_band_measured,((0,0,0,0),0),"no band cleared");
  assert!(src.outline_contour.is_none(),"outline domain == original capture");
  match src.receipt.frame_band_evidence{
   FrameBandEvidence::PerEdgeRejectedNoRing((_,_,l,r))=>assert!(l>0&&r>0,"receipt names the rejected band"),
   other=>panic!("expected PerEdgeRejectedNoRing, got {other:?}"),
  }
  // the shipped contour spans the full tile width: both stems present
  let mnx=src.contour.rings.iter().flat_map(|r| r.raw.iter()).map(|p| p.x).fold(f64::INFINITY,f64::min);
  let mxx=src.contour.rings.iter().flat_map(|r| r.raw.iter()).map(|p| p.x).fold(f64::NEG_INFINITY,f64::max);
  assert!(mxx-mnx>30.0,"both stems retained in the traced outline: w={}",mxx-mnx);
 }
 #[test]
 fn policy_measure_still_clears_a_proven_ring(){
  let (w,h)=(40usize,30usize);
  let mut g=vec![255u8;w*h];
  for x in 0..w{for y in 0..2{g[y*w+x]=0;g[(h-1-y)*w+x]=0;}}
  for y in 0..h{for x in 0..2{g[y*w+x]=0;g[y*w+(w-1-x)]=0;}}
  for y in 10..16{for x in 12..20{g[y*w+x]=0;}}
  let png=crate::curve_stress::encode_png_gray(w,h,&g).expect("png encode");
  let pl=DecodeLimits{max_input_bytes:1<<20,max_pixels:1<<20,max_working_bytes:1<<24};
  let jl=Limits{max_input_bytes:1<<20,max_pixels:1<<20,max_working_bytes:1<<24};
  let src=capture_source_with_policy(&png,0.5,&pl,jl,FramePolicy::Measure).expect("capture");
  assert_eq!(src.receipt.frame_band_measured.0,(2,2,2,2),"proven ring cleared");
  assert_eq!(src.receipt.frame_band_evidence,FrameBandEvidence::RingProofCleared);
  assert!(src.outline_contour.is_some(),"outline domain traced from the ring-cleared copy");
 }
}
