//! Experimental source-frame integer emission. Legacy fitting remains unchanged.
use crate::{capture::MeasuredContour,capture_fit::{fit_captured_with_span_provenance,round_and_clean_ring},cubic_fit::FitPolicy,reference_slice::ReferenceRing,lever_api::{SourceMask,NodeBudget,LeverReport,area_error,missing_extrema,count_nodes}};
#[derive(Clone,Debug)]
pub struct GeneratedDrawing {pub rings:Vec<ReferenceRing>,pub baseline:Vec<ReferenceRing>,pub reports:Vec<LeverReport>,pub refused:Vec<String>,pub baseline_area:f64,pub final_area:f64,pub baseline_missing_extrema:usize,pub final_missing_extrema:usize,pub source_fit_spans:usize,pub fallback:bool,pub dropped:usize,pub fallback_line_spans:usize,pub sub_grid_floor:usize,pub ambiguous_stubs:usize,pub ambig_declined:usize,pub fallback_provenance:Vec<crate::capture_fit::FallbackSpanProvenance>}
/// Output x is bbox-local; y is the original source tile's y-up coordinate.
/// Restore source y before integer quantization. Never add the origin again.
/// Inputs used together must share their source canvas coordinate system.
pub fn fit_from_source_frame(captured:&MeasuredContour,gray:&[u8],scale:f64,policy:&FitPolicy)->Result<GeneratedDrawing,String>{fit_from_source_frame_hooked(captured,gray,scale,policy,None).map_err(String::from)}
/// `protect`: optional hook called ONCE with the rings right before strict node reduction (after refine_emitted and
/// refine_tails); returned original (ring,node) indices are kept by the reduction. None = byte-identical legacy behaviour.
/// Typed failure of the hooked path. ProtectedConstraint = a requested protection could not be applied (contract
/// error, e.g. protected id out of range): hard fail, never a silently unprotected result.
#[derive(Clone,Debug)]
pub enum FrameFitError{Message(String),ProtectedConstraint(crate::lever_api::LeverError)}
impl From<&str> for FrameFitError{fn from(s:&str)->Self{Self::Message(s.into())}}
impl From<String> for FrameFitError{fn from(s:String)->Self{Self::Message(s)}}
impl From<FrameFitError> for String{fn from(e:FrameFitError)->String{match e{FrameFitError::Message(s)=>s,FrameFitError::ProtectedConstraint(l)=>format!("protected constraint failed: {l:?}")}}}
pub fn fit_from_source_frame_hooked(captured:&MeasuredContour,gray:&[u8],scale:f64,policy:&FitPolicy,protect:Option<&dyn Fn(&[ReferenceRing],&SourceMask)->crate::node_objective::Protected>)->Result<GeneratedDrawing,FrameFitError>{fit_from_source_frame_full(captured,gray,scale,policy,protect,&[])}
/// Full merged entry: `protect_emitted` indexes the E0 emitted integer baseline (after round_and_clean_ring)
/// and is enforced by refine_emitted_guided; `protect` hook computes E1 (post-refine, pre-removal) indices
/// enforced by strict node reduction. Either protection failing is a hard error, never silently unprotected.
pub fn fit_from_source_frame_full(captured:&MeasuredContour,gray:&[u8],scale:f64,policy:&FitPolicy,protect:Option<&dyn Fn(&[ReferenceRing],&SourceMask)->crate::node_objective::Protected>,protect_emitted:&[crate::emitted_geometry_refine::ProtectedNode])->Result<GeneratedDrawing,FrameFitError>{
 let mut no_e0:Option<&mut dyn FnMut(&[ReferenceRing])->Result<Vec<crate::emitted_geometry_refine::ProtectedNode>,FrameFitError>>=None;
 fit_from_source_frame_inner(captured,gray,scale,policy,protect,&mut no_e0,protect_emitted)
}
/// Inner: `protect_emitted_fn`, when Some, computes the E0 protection from the actual E0 baseline rings
/// (post round_and_clean_ring) at the moment they exist - no blind cross-frame identity transfer.
/// `protect_emitted_static` is used when no closure is given (legacy slice path).
fn fit_from_source_frame_inner(captured:&MeasuredContour,gray:&[u8],scale:f64,policy:&FitPolicy,protect:Option<&dyn Fn(&[ReferenceRing],&SourceMask)->crate::node_objective::Protected>,protect_emitted_fn:&mut Option<&mut dyn FnMut(&[ReferenceRing])->Result<Vec<crate::emitted_geometry_refine::ProtectedNode>,FrameFitError>>,protect_emitted_static:&[crate::emitted_geometry_refine::ProtectedNode])->Result<GeneratedDrawing,FrameFitError>{
 if !scale.is_finite()||scale<=0.0||!policy.squared_error.is_finite()||policy.squared_error<0.0||!captured.origin_x.is_finite()||!captured.origin_y.is_finite(){return Err("invalid drawing frame or policy".into())}
 if captured.width.checked_mul(captured.height)!=Some(gray.len()){return Err("source dimensions do not match gray bytes".into())}
 let (mut float,source_fit_spans,fallback,dropped,fevents,astubs,declined,fprov)=fit_captured_with_span_provenance(&captured.rings,scale,policy);
 // SubGridSpan is a typed stop below the source's resolving power, not an
 // unresolved hard fail: the gate input counts only unresolved-class events.
 let fallback_line_spans=fevents.iter().filter(|e|e.reason!=crate::capture_fit::FallbackReason::SubGridSpan).count();
 let sub_grid_floor=fevents.len()-fallback_line_spans;
 let dy=captured.origin_y*scale;
 if !dy.is_finite(){return Err("source-frame translation overflow".into())}
 for ring in &mut float {ring.start.y+=dy;for span in &mut ring.spans {match span {crate::reference_slice::Span::Line{end}=>end.y+=dy,crate::reference_slice::Span::Cubic{control_one,control_two,end}=>{control_one.y+=dy;control_two.y+=dy;end.y+=dy;}}}}

 let baseline:Vec<_>=float.iter().map(|r|round_and_clean_ring(r,1.0)).collect();
 if baseline.is_empty(){return Err("empty generated drawing".into())}
 let mask=SourceMask{w:captured.width,h:captured.height,ink:gray.to_vec(),scale,origin:(-captured.origin_x*scale,0.0)};
 if !mask.valid(){return Err("invalid source mask".into())}
 let _flatten_budget_max=crate::flatten_budget::max_total_segments(captured.width,captured.height).ok_or("flatten budget: no declarable budget")?;
 crate::flatten_budget::check_flatten_budget(&baseline,&mask,_flatten_budget_max).map_err(|e|format!("flatten budget: {e:?}"))?;
 let protect_emitted:Vec<crate::emitted_geometry_refine::ProtectedNode>=match protect_emitted_fn{Some(f)=>f(&baseline)?,None=>protect_emitted_static.to_vec()};
 let budget=NodeBudget{max_nodes:count_nodes(&baseline),max_nodes_per_ring:baseline.iter().map(|r|r.spans.len()).collect()};
 let baseline_area=area_error(&baseline,&mask);if !baseline_area.is_finite(){return Err("non-finite baseline source objective".into())}let baseline_missing_extrema=missing_extrema(&baseline);
 let mut rings=baseline.clone();let mut reports=Vec::new();let mut refused=Vec::new();
 let cfg=crate::emitted_geometry_refine::RefineConfig{max_snap:crate::emitted_geometry_refine::DERIVED_MAX_SNAP,run_int_refine:true,max_area_evals:crate::emitted_geometry_refine::derived_eval_budget(budget.max_nodes)};
 match crate::emitted_geometry_refine::refine_emitted_guided(&rings,&mask,&budget,&cfg,&protect_emitted){Ok((out,report))=>{rings=out;reports.push(report)},Err(e)=>{if !protect_emitted.is_empty(){return Err(FrameFitError::Message(format!("guided emission refinement failed (E0 protection): {e:?}")))}refused.push(format!("emission refinement refused: {e:?}"))}}
 match crate::tail_refine::refine_tails(&rings,&mask,&budget,&crate::tail_refine::TailConfig::default()){Ok((out,report))=>{
  // E0 preservation through the tail stage: protected predicates verified against the tail output;
  // any violation (or identity instability) drops the tail candidate to its exact input, never silent.
  if !protect_emitted.is_empty(){
   let stable=out.len()==rings.len()&&out.iter().zip(&rings).all(|(a,b)|a.spans.len()==b.spans.len());
   let end=|rs:&[ReferenceRing],ring:usize,node:usize|->Option<crate::reference_slice::Point>{match rs.get(ring)?.spans.get(node)?{crate::reference_slice::Span::Line{end}=>Some(*end),crate::reference_slice::Span::Cubic{end,..}=>Some(*end)}};
   let holds=stable&&protect_emitted.iter().all(|pn|match (end(&out,pn.ring,pn.node),end(&rings,pn.ring,pn.node)){
    (Some(a),Some(b))=>match pn.kind{crate::emitted_geometry_refine::Protect::Corner=>a.x==b.x&&a.y==b.y,crate::emitted_geometry_refine::Protect::Extremum{x_axis:true}=>a.x==b.x,crate::emitted_geometry_refine::Protect::Extremum{x_axis:false}=>a.y==b.y},
    _=>false});
   if holds{rings=out;reports.push(report)}else{refused.push("handle refinement candidate dropped: E0 protected predicate violated or identity unstable (exact-input fallback)".into())}
  }else{rings=out;reports.push(report)}},
 Err(e)=>refused.push(format!("handle refinement refused: {e:?}"))}
 let protected:crate::node_objective::Protected=protect.map(|f|f(&rings,&mask)).unwrap_or_default();
 match crate::node_objective::try_apply_protected(&rings,&mask,&budget,crate::node_objective::Policy::STRICT,&protected){Ok((out,report))=>{rings=out;reports.push(report)},Err(e)=>{if !protected.is_empty(){return Err(FrameFitError::ProtectedConstraint(e))}refused.push(format!("strict node reduction refused: {e:?}"))}}
 let final_area=area_error(&rings,&mask);let final_missing_extrema=missing_extrema(&rings);
 if !final_area.is_finite()||final_area>baseline_area||final_missing_extrema>baseline_missing_extrema||count_nodes(&rings)>budget.max_nodes{return Err("drawing refinement violated the global source-quality guard".into())}
 Ok(GeneratedDrawing{rings,baseline,reports,refused,baseline_area,final_area,baseline_missing_extrema,final_missing_extrema,source_fit_spans,fallback,dropped,fallback_line_spans,sub_grid_floor,ambiguous_stubs:astubs.len(),ambig_declined:declined.len(),fallback_provenance:fprov})
}


// ---------- E0/E1 map_frame_identity consumer (owner reference guided path) ----------
/// Font-frame -> this glyph's source-tile frame mapping for reference rings.
/// `px = (font_x - xmin)*px_per_unit + pad_px`, `py = (ymax - font_y)*px_per_unit + pad_px`
/// describe how the source raster was produced (recorded by the rasterizer's receipt);
/// the consumer converts through the EXACT mask inverse so reference and drawing share one frame.
#[derive(Clone,Debug)]
pub struct ReferenceFrameMap { pub xmin: f64, pub ymax: f64, pub px_per_unit: f64, pub pad_px: f64 }

/// Guided drawing with the E0/E1 identity evidence attached.
#[derive(Clone,Debug)]
pub struct GuardedGuidedDrawing {
    pub drawing: GeneratedDrawing,
    /// E0 identity set (post round_and_clean_ring baseline) consumed by refine_emitted_guided.
    pub e0: crate::reference_guided::FrameIdentity,
    /// E1 identity set (post refine, pre-removal) consumed by strict node reduction.
    pub e1: crate::reference_guided::FrameIdentity,
    pub selection: Option<GuidedSelection>,
    pub chosen_rings: Vec<ReferenceRing>,
}

/// fit + reference-guided E0/E1 protection consumer. `map_frame_identity` is called against the
/// ACTUAL frame inputs at the moment they exist (E0 baseline inside the fit; E1 post-refine
/// pre-removal via the protect hook); identities are never transferred across identity changes.
/// The reference rings arrive in the original font frame and are mapped through `fmap` + the
/// exact mask inverse; the original pin SHA is kept in the new pin's provenance string.
pub fn fit_captured_source_frame_guarded_guided(
    src:&CapturedSource,glyph_id:&str,scale:f64,policy:&FitPolicy,
    reference:&PinnedReference,gcfg:&crate::reference_guided::GuideConfig,fmap:&ReferenceFrameMap,
)->Result<GuardedGuidedDrawing,GuidedError>{
 if src.contour.rings.is_empty(){return Err(GuidedError::Route(RouteError::EmptyContour))}
 // verify the ORIGINAL reference binding before any transform: a broken original pin is a typed
 // refusal, never re-pinned into validity. The mapped re-pin below is a frame artifact only.
 reference_transfer::verify_pin(reference).map_err(GuidedError::Transfer)?;
 if reference.pin.glyph_id!=glyph_id{return Err(GuidedError::Transfer(TransferError::GlyphMismatch{pin:reference.pin.glyph_id.clone(),captured:glyph_id.into()}))}
 if !fmap.xmin.is_finite()||!fmap.ymax.is_finite()||!fmap.px_per_unit.is_finite()||fmap.px_per_unit<=0.0||!fmap.pad_px.is_finite(){
  return Err(GuidedError::Route(RouteError::Drawing("invalid reference frame map".into())))}
 // reference rings -> source-tile drawing frame (mask inverse: x=origin.0+px*scale, y=origin.1-py*scale; frame mask origin=(-origin_x*scale,0))
 let map_point=|p:crate::reference_slice::Point|->crate::reference_slice::Point{
  let px=(p.x-fmap.xmin)*fmap.px_per_unit+fmap.pad_px;
  let py=(fmap.ymax-p.y)*fmap.px_per_unit+fmap.pad_px;
  crate::reference_slice::Point{x:(px-src.contour.origin_x)*scale,y:-py*scale}};
 let mapped_rings:Vec<ReferenceRing>=reference.rings.iter().map(|r|ReferenceRing{start:map_point(r.start),spans:r.spans.iter().map(|sp|match sp{
   crate::reference_slice::Span::Line{end}=>crate::reference_slice::Span::Line{end:map_point(*end)},
   crate::reference_slice::Span::Cubic{control_one,control_two,end}=>crate::reference_slice::Span::Cubic{control_one:map_point(*control_one),control_two:map_point(*control_two),end:map_point(*end)}}).collect()}).collect();
 let provenance=format!("{}|mapped-to-source-frame:xmin={} ymax={} ppu={} pad={} scale={}|original-pin-sha256={}",reference.pin.provenance_reference,fmap.xmin,fmap.ymax,fmap.px_per_unit,fmap.pad_px,scale,reference.pin.sha256_hex);
 let mapped_ref=PinnedReference{pin:reference_transfer::make_pin(glyph_id,&provenance,&mapped_rings),rings:mapped_rings};
 let e0_store=std::cell::RefCell::new(None::<crate::reference_guided::FrameIdentity>);
 let e1_store=std::cell::RefCell::new(None::<crate::reference_guided::FrameIdentity>);
 let map_err=std::cell::RefCell::new(None::<String>);
 let mut e0_fn=|baseline:&[ReferenceRing]|->Result<Vec<crate::emitted_geometry_refine::ProtectedNode>,FrameFitError>{
  let id=crate::reference_guided::map_frame_identity("E0",glyph_id,baseline,&mapped_ref,gcfg).map_err(|e|FrameFitError::Message(format!("E0 map_frame_identity refused: {e:?}")))?;
  let mut out=Vec::new();
  for &(ring,node) in &id.corner_nodes{out.push(crate::emitted_geometry_refine::ProtectedNode{ring,node,kind:crate::emitted_geometry_refine::Protect::Corner});}
  for &(ring,node,x_axis) in &id.extremum_nodes{out.push(crate::emitted_geometry_refine::ProtectedNode{ring,node,kind:crate::emitted_geometry_refine::Protect::Extremum{x_axis}});}
  *e0_store.borrow_mut()=Some(id);
  Ok(out)};
 let e1_hook=|rings:&[ReferenceRing],_mask:&SourceMask|->crate::node_objective::Protected{
  match crate::reference_guided::map_frame_identity("E1",glyph_id,rings,&mapped_ref,gcfg){
   Ok(id)=>{let mut set=crate::node_objective::Protected::new();
    for &(ring,node) in &id.corner_nodes{set.insert((ring,node));}
    for &(ring,node,_) in &id.extremum_nodes{set.insert((ring,node));}
    *e1_store.borrow_mut()=Some(id);set}
   Err(e)=>{*map_err.borrow_mut()=Some(format!("E1 map_frame_identity refused: {e:?}"));crate::node_objective::Protected::new()}}};
 let drawing=fit_from_source_frame_inner(&src.contour,&src.gray,scale,policy,Some(&e1_hook),&mut Some(&mut e0_fn),&[]).map_err(|e|GuidedError::Route(RouteError::Drawing(String::from(e))))?;
 if let Some(e)=map_err.borrow_mut().take(){return Err(GuidedError::Route(RouteError::Drawing(e)))}
 let e0=e0_store.borrow_mut().take().ok_or(GuidedError::Route(RouteError::Drawing("E0 identity was not produced".into())))?;
 let e1=e1_store.borrow_mut().take().ok_or(GuidedError::Route(RouteError::Drawing("E1 identity was not produced".into())))?;
 // rebind check: the consumed identities must bind to the exact frame inputs that survive in the output
 if e0.input_hash!=crate::lever_api::hash_rings(&drawing.baseline){return Err(GuidedError::Route(RouteError::Drawing("E0 identity does not bind to the emitted baseline".into())))}
 Ok(GuardedGuidedDrawing{chosen_rings:drawing.rings.clone(),drawing,e0,e1,selection:None})
}

#[cfg(test)] mod tests {
 use super::*;
 use crate::reference_slice::{Point,Span};
 fn points(rings:&[ReferenceRing])->Vec<Point>{let mut out=Vec::new();for ring in rings {out.push(ring.start);for span in &ring.spans {match span {Span::Line{end}=>out.push(*end),Span::Cubic{control_one,control_two,end}=>out.extend([*control_one,*control_two,*end])}}}out}
 #[test] fn source_frame_integer_and_repeat(){
  let mut gray=vec![255u8;144];for y in 3..9 {for x in 3..9 {gray[y*12+x]=0;}}
  let c=crate::capture::capture_gray(12,12,&gray,0.25).unwrap();
  assert!(c.origin_y<0.0);
  let p=FitPolicy{squared_error:0.25,max_refits:8};
  let a=fit_from_source_frame(&c,&gray,1.0,&p).unwrap();let b=fit_from_source_frame(&c,&gray,1.0,&p).unwrap();
  assert!(a.final_area<=a.baseline_area);assert!(a.final_missing_extrema<=a.baseline_missing_extrema);assert!(count_nodes(&a.rings)<=count_nodes(&a.baseline));
  assert_eq!(crate::lever_api::hash_rings(&a.rings),crate::lever_api::hash_rings(&b.rings));
  assert!(points(&a.rings).iter().all(|p|p.x.is_finite()&&p.y.is_finite()&&p.x==p.x.round()&&p.y==p.y.round()&&p.y<0.0));
  let mask=SourceMask{w:12,h:12,ink:gray,scale:1.0,origin:(-c.origin_x,0.0)};
  assert_eq!(area_error(&a.rings,&mask),a.final_area);
 }
 #[test] fn source_frame_refuses_bad_length(){let c=MeasuredContour{width:2,height:2,rings:vec![],origin_x:0.0,origin_y:0.0};assert!(fit_from_source_frame(&c,&[255],1.0,&FitPolicy{squared_error:1.0,max_refits:4}).is_err());}
}

// ---------- real route: bytes/capture leg -> generated drawing (source frame) ----------
use crate::capture_dispatch::{self,CapturedSource,SourceReceipt};
use crate::jpeg_source::Limits;

/// Typed route rejects: no silent fallback, no stringly route failures.
/// The draw leg's internal guard failures remain its existing String errors,
/// wrapped here unchanged (D2/D3/D4 modules are not rewritten).
#[derive(Debug)]
pub enum RouteError {
    /// Decode/capture leg failed (empty input, unsupported signature, jpeg, capture).
    Dispatch(crate::capture_dispatch::DispatchError),
    /// The capture leg succeeded but produced zero rings.
    EmptyContour,
    /// fit_from_source_frame's own typed-context guard fired; detail kept verbatim.
    Drawing(String),
}

/// A generated drawing plus the source lineage that produced it.
#[derive(Debug)]
pub struct RoutedDrawing { pub drawing: GeneratedDrawing, pub receipt: SourceReceipt }

/// Capture leg -> source-frame generated drawing.
/// The output y is ALREADY in the original source tile's y-up frame and the
/// shared canvas origin/scale is applied exactly once, inside
/// `fit_from_source_frame`: callers must NOT add origin_y (or any transform)
/// again. Inputs used together must share their source canvas coordinate system.
pub fn fit_captured_source_frame(src:&CapturedSource,scale:f64,policy:&FitPolicy)->Result<RoutedDrawing,RouteError>{
 if src.contour.rings.is_empty(){return Err(RouteError::EmptyContour)}
 let drawing=fit_from_source_frame(&src.contour,&src.gray,scale,policy).map_err(RouteError::Drawing)?;
 Ok(RoutedDrawing{drawing,receipt:src.receipt.clone()})
}

/// Full real route: source bytes -> decode -> capture -> source-frame generated
/// drawing. Same frame contract as `fit_captured_source_frame`.
pub fn fit_bytes_source_frame(bytes:&[u8],scale:f64,rdp_eps:f64,policy:&FitPolicy,png_limits:&crate::capture::DecodeLimits,jpeg_limits:Limits)->Result<RoutedDrawing,RouteError>{
 let src=capture_dispatch::capture_source(bytes,rdp_eps,png_limits,jpeg_limits).map_err(RouteError::Dispatch)?;
 fit_captured_source_frame(&src,scale,policy)
}

#[cfg(test)]
mod route_tests {
 use super::*;
 fn square_source()->CapturedSource{
  let mut gray=vec![255u8;144];for y in 3..9{for x in 3..9{gray[y*12+x]=0;}}
  let contour=crate::capture::capture_gray(12,12,&gray,0.25).unwrap();
  CapturedSource{gray,outline_contour:None,outline_gray:None,receipt:crate::capture_dispatch::SourceReceipt{source_kind:crate::capture_dispatch::SourceKind::PngConvertedGrayWhiteAlpha,jpeg_identity:None,frame_band_measured:((0,0,0,0),0),frame_band_evidence:crate::capture_dispatch::FrameBandEvidence::NoSignal,width:12,height:12,decoder_limits:None,png_limits:None},contour}
 }
 fn policy()->FitPolicy{FitPolicy{squared_error:0.25,max_refits:8}}
 #[test]
 fn route_matches_manual_chain_no_extra_transform(){
  let src=square_source();
  let manual=fit_from_source_frame(&src.contour,&src.gray,10.0,&policy()).unwrap();
  let routed=fit_captured_source_frame(&src,10.0,&policy()).unwrap();
  assert_eq!(crate::lever_api::hash_rings(&routed.drawing.rings),crate::lever_api::hash_rings(&manual.rings));
  assert_eq!(routed.receipt.source_kind,src.receipt.source_kind);assert_eq!((routed.receipt.width,routed.receipt.height),(src.contour.width,src.contour.height));assert_eq!(routed.receipt.jpeg_identity.is_none(),true);
  // frame contract preserved through the route: y stays in the source frame (<=0 here)
  let mut ys=Vec::new();for r in &routed.drawing.rings{ys.push(r.start.y);for s in &r.spans{match s{crate::reference_slice::Span::Line{end}=>ys.push(end.y),crate::reference_slice::Span::Cubic{control_one,control_two,end}=>{ys.push(control_one.y);ys.push(control_two.y);ys.push(end.y);}}}}
  assert!(ys.iter().all(|y|y.is_finite()&&*y<=0.0));
 }
 #[test]
 fn empty_contour_is_typed_reject(){
  let mut src=square_source();src.contour.rings.clear();
  assert!(matches!(fit_captured_source_frame(&src,10.0,&policy()),Err(RouteError::EmptyContour)));
 }
 #[test]
 fn bytes_route_typed_rejects(){
  let l=Limits{max_input_bytes:1<<20,max_pixels:1<<20,max_working_bytes:1<<22};
  assert!(matches!(fit_bytes_source_frame(&[],10.0,0.25,&policy(),&crate::capture::DecodeLimits::default(),l),Err(RouteError::Dispatch(crate::capture_dispatch::DispatchError::UnsupportedSignature)))); // current DispatchError has no dedicated EmptyInput variant; empty bytes reject as typed UnsupportedSignature
  assert!(matches!(fit_bytes_source_frame(b"GIF89a.....",10.0,0.25,&policy(),&crate::capture::DecodeLimits::default(),l),Err(RouteError::Dispatch(crate::capture_dispatch::DispatchError::UnsupportedSignature))));
 }
}

// ---------- reference-guided candidate consumption (P2 owner-drawing intake) ----------
// Route contract: learning targets alone is not closure - this path CONSUMES them.
// Candidates are the guard-passed [baseline, refined] outlines of THIS glyph only; a
// glyph-local target set is never spread to other glyphs. TransferConfig is always
// caller-explicit here: this route never reads TransferConfig::default().
use crate::reference_transfer::{self,PinnedReference,TransferConfig,TransferError,ObjectiveScore};

#[derive(Debug)]
pub enum GuidedError {
    Route(RouteError),
    Transfer(TransferError),
}

/// P6 evidence for one guided selection.
#[derive(Clone,Debug)]
pub struct GuidedSelection {
    /// Candidate labels in the order they were scored: ["baseline","refined"].
    pub candidates: [&'static str;2],
    pub chosen: usize,
    pub chosen_score: ObjectiveScore,
    pub other_score: ObjectiveScore,
    /// reference nodes that found a candidate node within the explicit config's max_node_dist.
    pub matched_nodes: usize,
    pub reference_nodes: usize,
    pub pin_sha256: String,
}

/// A routed drawing plus the reference-guided selection that consumed the targets.
/// `chosen_rings` is the outline downstream stages must use; when `selection` is None
/// (no reference supplied) it equals `drawing.rings`.
#[derive(Clone,Debug)]
pub struct GuidedDrawing {
    pub drawing: GeneratedDrawing,
    pub selection: Option<GuidedSelection>,
    pub chosen_rings: Vec<ReferenceRing>,
}

/// fit_from_source_frame + reference-guided candidate selection, one glyph only.
/// The source-frame contract is unchanged: chosen_rings' y is already in the source
/// tile's y-up frame; callers must NOT add origin_y again.
pub fn fit_captured_source_frame_guided(
    src:&CapturedSource,glyph_id:&str,scale:f64,policy:&FitPolicy,
    reference:Option<(&PinnedReference,&TransferConfig)>,
)->Result<GuidedDrawing,GuidedError>{
 if src.contour.rings.is_empty(){return Err(GuidedError::Route(RouteError::EmptyContour))}
 let drawing=fit_from_source_frame(&src.contour,&src.gray,scale,policy).map_err(RouteError::Drawing).map_err(GuidedError::Route)?;
 let mut out=GuidedDrawing{chosen_rings:drawing.rings.clone(),drawing,selection:None};
 if let Some((reference,cfg))=reference{
  // targets learned against THIS glyph's refined geometry (candidates keep its ring order)
  let targets=reference_transfer::learn_targets(reference,glyph_id,&out.drawing.rings,cfg).map_err(GuidedError::Transfer)?;
  let candidates=vec![out.drawing.baseline.clone(),out.drawing.rings.clone()];
  let (chosen,score)=reference_transfer::select_candidate(&targets,&candidates).map_err(GuidedError::Transfer)?;
  let other=reference_transfer::score_candidate(&targets,&candidates[1-chosen]).map_err(GuidedError::Transfer)?;
  let matched=targets.reference_nodes-score.missing_nodes;
  out.selection=Some(GuidedSelection{candidates:["baseline","refined"],chosen,
   pin_sha256:targets.pin.sha256_hex.clone(),reference_nodes:targets.reference_nodes,
   matched_nodes:matched,chosen_score:score,other_score:other});
  out.chosen_rings=candidates[chosen].clone();
 }
 Ok(out)
}

/// Full real route with reference guidance: source bytes -> decode -> capture ->
/// source-frame drawing -> target consumption. Same frame contract as above.
pub fn fit_bytes_source_frame_guided(
    bytes:&[u8],glyph_id:&str,scale:f64,rdp_eps:f64,policy:&FitPolicy,png_limits:&crate::capture::DecodeLimits,jpeg_limits:Limits,
    reference:Option<(&PinnedReference,&TransferConfig)>,
)->Result<GuidedDrawing,GuidedError>{
 let src=capture_dispatch::capture_source(bytes,rdp_eps,png_limits,jpeg_limits).map_err(RouteError::Dispatch).map_err(GuidedError::Route)?;
 fit_captured_source_frame_guided(&src,glyph_id,scale,policy,reference)
}

#[cfg(test)]
mod guided_tests {
 use super::*;
 use crate::reference_transfer::{make_pin,TransferConfig};
 fn disk_source()->CapturedSource{
  let (w,h)=(24usize,24usize);
  let mut gray=vec![255u8;w*h];
  for j in 0..h{for i in 0..w{let x=i as f64+0.5-12.0;let y=12.0-(j as f64+0.5);if x*x+y*y<=64.0{gray[j*w+i]=0;}}}
  let contour=crate::capture::capture_gray(w,h,&gray,0.25).unwrap();
  CapturedSource{gray,outline_contour:None,outline_gray:None,receipt:crate::capture_dispatch::SourceReceipt{source_kind:crate::capture_dispatch::SourceKind::PngConvertedGrayWhiteAlpha,jpeg_identity:None,frame_band_measured:((0,0,0,0),0),frame_band_evidence:crate::capture_dispatch::FrameBandEvidence::NoSignal,width:w,height:h,decoder_limits:None,png_limits:None},contour}
 }
 fn policy()->FitPolicy{FitPolicy{squared_error:0.25,max_refits:8}}
 // explicit, caller-owned config - never TransferConfig::default() (its shipped values are arbitrary)
 fn cfg()->TransferConfig{TransferConfig{smooth_sin:0.05233595624294397,max_node_dist:0.003,max_ring_cost:0.3}}
 #[test]
 fn selection_consumes_targets_and_drives_output(){
  let src=disk_source();
  let base=fit_from_source_frame(&src.contour,&src.gray,10.0,&policy()).unwrap();
  // premise: this fixture's refinement actually changes the outline
  assert_ne!(crate::lever_api::hash_rings(&base.baseline),crate::lever_api::hash_rings(&base.rings),"fixture requires baseline != refined");
  // reference pinned to the REFINED outline -> selection must choose refined (index 1)
  let rref=crate::reference_transfer::PinnedReference{pin:make_pin("g","test-fixture",&base.rings),rings:base.rings.clone()};
  let g=fit_captured_source_frame_guided(&src,"g",10.0,&policy(),Some((&rref,&cfg()))).unwrap();
  let sel=g.selection.as_ref().unwrap();
  assert_eq!(sel.chosen,1,"refined-pinned reference must select refined: {:?}",sel.chosen_score);
  assert_eq!(crate::lever_api::hash_rings(&g.chosen_rings),crate::lever_api::hash_rings(&base.rings));
  assert_eq!(sel.reference_nodes,sel.matched_nodes,"every reference node matched: {:?}",sel.chosen_score);
  // reference pinned to the BASELINE outline -> selection must choose baseline (index 0)
  let bref=crate::reference_transfer::PinnedReference{pin:make_pin("g","test-fixture",&base.baseline),rings:base.baseline.clone()};
  let g2=fit_captured_source_frame_guided(&src,"g",10.0,&policy(),Some((&bref,&cfg()))).unwrap();
  let sel2=g2.selection.as_ref().unwrap();
  assert_eq!(sel2.chosen,0,"baseline-pinned reference must select baseline: {:?}",sel2.chosen_score);
  assert_eq!(crate::lever_api::hash_rings(&g2.chosen_rings),crate::lever_api::hash_rings(&base.baseline));
 }
 #[test]
 fn typed_rejects_and_no_reference_passthrough(){
  let src=disk_source();
  let base=fit_from_source_frame(&src.contour,&src.gray,10.0,&policy()).unwrap();
  // wrong glyph id -> typed GlyphMismatch (glyph-local: no spreading)
  let rref=crate::reference_transfer::PinnedReference{pin:make_pin("g","test-fixture",&base.rings),rings:base.rings.clone()};
  assert!(matches!(fit_captured_source_frame_guided(&src,"OTHER",10.0,&policy(),Some((&rref,&cfg()))),
   Err(GuidedError::Transfer(TransferError::GlyphMismatch{..}))));
  // tampered rings after pinning -> typed PinMismatch
  let mut bad=rref.clone();bad.rings[0].start=crate::reference_slice::Point{x:999.0,y:0.0};
  assert!(matches!(fit_captured_source_frame_guided(&src,"g",10.0,&policy(),Some((&bad,&cfg()))),
   Err(GuidedError::Transfer(TransferError::PinMismatch{..}))));
  // empty contour -> typed EmptyContour
  let mut e=disk_source();e.contour.rings.clear();
  assert!(matches!(fit_captured_source_frame_guided(&e,"g",10.0,&policy(),None),Err(GuidedError::Route(RouteError::EmptyContour))));
  // no reference -> selection None, output unchanged from the plain route
  let g=fit_captured_source_frame_guided(&src,"g",10.0,&policy(),None).unwrap();
  assert!(g.selection.is_none());
  assert_eq!(crate::lever_api::hash_rings(&g.chosen_rings),crate::lever_api::hash_rings(&base.rings));
 }
}
