//! Reference-guided candidate generation (P2 v2). UNCOMPILED: needs cargo check on hub. v1 NOT_COMPLETE.
//! Core works on FITTED FINAL RINGS + an explicit SourceMask supplied by the caller, so it never assumes a frame.
//! Entry points: fit_from_source_with_reference (bbox-local, generated_draw) and
//! fit_from_source_frame_with_reference (source-frame, generated_draw_frame; production path). Each builds its own
//! correct mask and returns its own drawing type in its own frame. Unguided entries are untouched.
use crate::{capture::MeasuredContour,cubic_fit::FitPolicy,reference_slice::{Point,ReferenceRing,Span},
 lever_api::{SourceMask,area_error,missing_extrema,count_nodes},
 reference_transfer::{self as rt,PinnedReference,TransferConfig,TransferError,NodeRole},
 emitted_geometry_refine::{DERIVED_MAX_SNAP}};
/// Both values must be supplied by the caller (no Default). None => typed missing-config, nothing runs.
#[derive(Clone,Copy,Debug,Default)]
pub struct GuideConfig { pub max_node_dist:Option<f64>, pub max_ring_cost:Option<f64>, /// REQUIRED when the reference has any cubic (explicit precision criterion); ignored for line-only references
 pub smooth_sin:Option<f64> }
#[derive(Clone,Debug,PartialEq)]
pub enum GuidanceStatus {
 /// Guided candidate passed the source guard and won the target-score selection.
 Applied,
 /// Valid reference, but no target could be consumed (nothing changed).
 NoTargetApplicable,
 /// Valid inputs; guidance not used (source guard, score, correspondence). Reason recorded.
 Refused(String),
 /// Pin/glyph/SHA/config invalid. Reference NOT used and must never be reported as used.
 Invalid(String) }
#[derive(Clone,Debug)]
pub struct GuidanceReport { pub status:GuidanceStatus, pub pin_sha256:String, pub glyph_id:String, pub smooth_sin_used:Option<f64>, pub line_only_exact_mode:bool, pub reference_grid_observed:Option<f64>, pub protected_matched_corner_nodes:usize, pub protection_note:Option<String>, pub max_node_dist:Option<f64>, pub max_ring_cost:Option<f64>,
 pub matched_targets:usize, pub unmatched_targets:usize, pub extremum_snaps_applied:usize, pub extremum_snaps_skipped_over_max_snap:usize,
 /// COUNT ONLY: corners are not yet protected from the unguided node reduction.
 pub corner_targets_counted:usize, pub oblique_tangent_targets_not_applied:usize,
 pub unguided_target_score:Option<f64>, pub guided_target_score:Option<f64>, pub selected_guided:bool }
fn report(reference:&PinnedReference,glyph_id:&str,cfg:&GuideConfig)->GuidanceReport{GuidanceReport{status:GuidanceStatus::NoTargetApplicable,pin_sha256:reference.pin.sha256_hex.clone(),glyph_id:glyph_id.into(),smooth_sin_used:None,line_only_exact_mode:false,reference_grid_observed:None,protected_matched_corner_nodes:0,protection_note:None,max_node_dist:cfg.max_node_dist,max_ring_cost:cfg.max_ring_cost,
 matched_targets:0,unmatched_targets:0,extremum_snaps_applied:0,extremum_snaps_skipped_over_max_snap:0,corner_targets_counted:0,oblique_tangent_targets_not_applied:0,unguided_target_score:None,guided_target_score:None,selected_guided:false}}
/// Observation only (reported, never turned into an error bound): Some(1.0) when every coordinate is exactly integer.
/// Integer-valued coordinates do NOT prove 1-unit quantization uncertainty.
pub fn observed_grid(reference:&[ReferenceRing])->Option<f64>{
 let int=|v:f64|v==v.round();
 for r in reference{if !(int(r.start.x)&&int(r.start.y)){return None}for s in &r.spans{match s{Span::Line{end}=>{if !(int(end.x)&&int(end.y)){return None}}
  Span::Cubic{control_one:a,control_two:b,end}=>{if ![a.x,a.y,b.x,b.y,end.x,end.y].iter().all(|v|int(*v)){return None}}}}}
 Some(1.0)
}
/// smooth_sin policy. Line-only reference: no smooth bound is needed; TransferConfig requires a positive value, so
/// f64::MIN_POSITIVE is passed, making `cross.abs()<=smooth_sin` an exact-zero test. That is a comparison mode, NOT a
/// numeric certificate: it can miss exactly collinear lines after frame normalisation rounding (reported via line_only_exact_mode).
/// Reference with any cubic: the caller's explicit smooth_sin criterion is REQUIRED; otherwise typed ambiguity.
pub fn smooth_sin_for(reference:&[ReferenceRing],explicit:Option<f64>)->Result<(f64,bool),String>{
 let any_cubic=reference.iter().any(|r|r.spans.iter().any(|s|matches!(s,Span::Cubic{..})));
 if !any_cubic{return Ok((f64::MIN_POSITIVE,true))}
 match explicit{Some(e) if e.is_finite()&&e>0.0&&e<1.0=>Ok((e,false)),Some(_)=>Err("explicit smooth_sin must be finite in (0,1)".into()),
  None=>Err("reference has cubics: explicit smooth_sin (precision criterion) required; smooth/corner classification ambiguous".into())}
}
fn snap_extrema(rings:&[ReferenceRing],t:&rt::TransferTargets,rep:&mut GuidanceReport)->Vec<ReferenceRing>{
 let mut out=rings.to_vec();
 for tg in &t.targets{
  let Some((ci,k))=tg.captured else{continue};
  if tg.role==NodeRole::Corner{rep.corner_targets_counted+=1;continue}
  if tg.extremum_x==tg.extremum_y{if tg.tangent.is_some(){rep.oblique_tangent_targets_not_applied+=1}continue}
  let n=out[ci].spans.len();let node:Point=match &out[ci].spans[k]{Span::Line{end}=>*end,Span::Cubic{end,..}=>*end};
  let (ex,_)=(tg.extremum_x,0);
  let mut apply=|p:&mut Point|{let d=if ex{node.x-p.x}else{node.y-p.y};
   if d==0.0{return}
   if d.abs()>DERIVED_MAX_SNAP{rep.extremum_snaps_skipped_over_max_snap+=1;return}
   if ex{p.x=node.x}else{p.y=node.y}rep.extremum_snaps_applied+=1};
  if let Span::Cubic{control_two,..}=&mut out[ci].spans[k]{apply(control_two)}
  if let Span::Cubic{control_one,..}=&mut out[ci].spans[(k+1)%n]{apply(control_one)}
 }
 out
}
/// Shared core. `final_rings` = fitted final rings of the unguided path, `mask` = the exact mask that path used.
/// Order: config + pin/glyph validation BEFORE any derived geometry; then targets; then candidate; then guard; then selection.
/// Returns (Some(guided_rings) only when selected, report). Output is in the caller's frame, untouched otherwise.
pub fn guide_final_rings(glyph_id:&str,final_rings:&[ReferenceRing],mask:&SourceMask,reference:&PinnedReference,cfg:&GuideConfig)->(Option<Vec<ReferenceRing>>,GuidanceReport){
 let mut rep=report(reference,glyph_id,cfg);
 let (Some(nd),Some(rc))=(cfg.max_node_dist,cfg.max_ring_cost) else{rep.status=GuidanceStatus::Invalid("missing guide config: max_node_dist and max_ring_cost are required".into());return(None,rep)};
 if let Err(e)=rt::verify_pin(reference){rep.status=GuidanceStatus::Invalid(format!("pin invalid: {e:?}"));return(None,rep)}
 if reference.pin.glyph_id!=glyph_id{rep.status=GuidanceStatus::Invalid(format!("pin glyph {} != target glyph {}",reference.pin.glyph_id,glyph_id));return(None,rep)}
 // flatten budget guard (public entry, fail-closed): no declared budget = Invalid; baseline over budget = Refused. Never flatten an unchecked input.
 let max_total=match crate::flatten_budget::max_total_segments(mask.w,mask.h){Some(m)=>m,None=>{rep.status=GuidanceStatus::Invalid("flatten budget unavailable: mask dimensions do not yield a bounded budget".into());return(None,rep)}};
 if let Err(e)=crate::flatten_budget::check_flatten_budget(final_rings,mask,max_total){rep.status=GuidanceStatus::Refused(format!("flatten budget refused: {e:?}"));return(None,rep)}
 let (smooth_sin,line_only)=match smooth_sin_for(&reference.rings,cfg.smooth_sin){Ok(s)=>s,Err(e)=>{rep.status=GuidanceStatus::Refused(format!("reference guidance refused: {e}"));return(None,rep)}};
 rep.smooth_sin_used=Some(smooth_sin);rep.line_only_exact_mode=line_only;rep.reference_grid_observed=observed_grid(&reference.rings);
 let tc=TransferConfig{smooth_sin,max_node_dist:nd,max_ring_cost:rc};
 let targets=match rt::learn_targets(reference,glyph_id,final_rings,&tc){Ok(t)=>t,Err(e)=>{rep.status=match e{TransferError::BadPin(_)|TransferError::PinMismatch{..}|TransferError::GlyphMismatch{..}|TransferError::Config(_)=>GuidanceStatus::Invalid(format!("{e:?}")),_=>GuidanceStatus::Refused(format!("reference guidance refused: {e:?}"))};return(None,rep)}};
 rep.matched_targets=targets.targets.iter().filter(|t|t.captured.is_some()).count();rep.unmatched_targets=targets.targets.len()-rep.matched_targets;
 let guided=snap_extrema(final_rings,&targets,&mut rep);
 if rep.extremum_snaps_applied==0{rep.status=GuidanceStatus::NoTargetApplicable;return(None,rep)}
 // flatten budget guard (guided candidate, same max as the baseline): a guided candidate that would exceed the declared budget is refused, never flattened.
 if crate::flatten_budget::check_flatten_budget(&guided,mask,max_total).is_err(){rep.status=GuidanceStatus::Refused("flatten budget refused: guided candidate over budget".into());return(None,rep)}
 let (ga,ua)=(area_error(&guided,mask),area_error(final_rings,mask));
 if !ga.is_finite()||ga>ua||missing_extrema(&guided)>missing_extrema(final_rings)||count_nodes(&guided)>count_nodes(final_rings){
  rep.status=GuidanceStatus::Refused(format!("reference guidance refused: source guard (guided area {ga} vs unguided {ua})"));return(None,rep)}
 rep.unguided_target_score=rt::score_candidate(&targets,final_rings).ok().map(|s|s.total);rep.guided_target_score=rt::score_candidate(&targets,&guided).ok().map(|s|s.total);
 match(rep.unguided_target_score,rep.guided_target_score){(Some(u),Some(g)) if g<u=>{rep.selected_guided=true;rep.status=GuidanceStatus::Applied;(Some(guided),rep)}
  _=>{rep.status=GuidanceStatus::Refused("reference guidance refused: guided candidate not better on target score".into());(None,rep)}}
}
pub struct GuidedLocal{pub drawing:crate::generated_draw::GeneratedDrawing,pub guidance:GuidanceReport}
pub struct GuidedFrame{pub drawing:crate::generated_draw_frame::GeneratedDrawing,pub guidance:GuidanceReport}
/// bbox-local entry (wrapper path). Mask matches generated_draw::fit_from_source exactly.
pub fn fit_from_source_with_reference(glyph_id:&str,captured:&MeasuredContour,gray:&[u8],scale:f64,policy:&FitPolicy,reference:&PinnedReference,cfg:&GuideConfig)->Result<GuidedLocal,String>{
 let mut d=crate::generated_draw::fit_from_source(captured,gray,scale,policy)?;
 let mask=SourceMask{w:captured.width,h:captured.height,ink:gray.to_vec(),scale,origin:(-captured.origin_x*scale,-captured.origin_y*scale)};
 let (g,rep)=guide_final_rings(glyph_id,&d.rings,&mask,reference,cfg);
 if let Some(r)=g{d.final_area=area_error(&r,&mask);d.final_missing_extrema=missing_extrema(&r);d.rings=r}
 Ok(GuidedLocal{drawing:d,guidance:rep})
}
/// Production source-frame entry. Mask matches generated_draw_frame::fit_from_source_frame exactly (origin y = 0 because y is restored to source tile).
pub fn fit_from_source_frame_with_reference(glyph_id:&str,captured:&MeasuredContour,gray:&[u8],scale:f64,policy:&FitPolicy,reference:&PinnedReference,cfg:&GuideConfig)->Result<GuidedFrame,String>{
 let mut d=crate::generated_draw_frame::fit_from_source_frame(captured,gray,scale,policy)?;
 let mask=SourceMask{w:captured.width,h:captured.height,ink:gray.to_vec(),scale,origin:(-captured.origin_x*scale,0.0)};
 let (g,rep)=guide_final_rings(glyph_id,&d.rings,&mask,reference,cfg);
 if let Some(r)=g{d.final_area=area_error(&r,&mask);d.final_missing_extrema=missing_extrema(&r);d.rings=r}
 Ok(GuidedFrame{drawing:d,guidance:rep})
}
/// TARGET MAPPER (A1 ownership). Maps the reference to the identity set of ONE frame: `rings` is that frame's exact input
/// (E0 = after round_and_clean_ring for D2; E1 = after D2+tail, before removal for D3). Never reuse a set across frames:
/// call again per frame; `input_hash` (lever_api::hash_rings of `rings`) binds the identity set to its frame input.
#[derive(Clone,Debug)]
pub struct FrameIdentity{pub frame:&'static str,pub input_hash:u64,pub pin_sha256:String,pub glyph_id:String,
 /// (ring,node=end_of(spans)) of reference-matched Corner targets in `rings`.
 pub corner_nodes:std::collections::BTreeSet<(usize,usize)>,
 /// (ring,node) of reference-matched smooth extremum targets: (ring,node,extremum_x).
 pub extremum_nodes:Vec<(usize,usize,bool)>,
 pub unmatched_targets:usize}
#[derive(Clone,Debug,PartialEq)]
pub enum MapError{MissingConfig,Pin(String),GlyphMismatch,Ambiguity(String),Transfer(String)}
pub fn map_frame_identity(frame:&'static str,glyph_id:&str,rings:&[ReferenceRing],reference:&PinnedReference,cfg:&GuideConfig)->Result<FrameIdentity,MapError>{
 let (Some(nd),Some(rc))=(cfg.max_node_dist,cfg.max_ring_cost) else{return Err(MapError::MissingConfig)};
 rt::verify_pin(reference).map_err(|e|MapError::Pin(format!("{e:?}")))?;
 if reference.pin.glyph_id!=glyph_id{return Err(MapError::GlyphMismatch)}
 let (smooth_sin,_)=smooth_sin_for(&reference.rings,cfg.smooth_sin).map_err(MapError::Ambiguity)?;
 let t=rt::learn_targets(reference,glyph_id,rings,&TransferConfig{smooth_sin,max_node_dist:nd,max_ring_cost:rc}).map_err(|e|match e{TransferError::BadPin(_)|TransferError::PinMismatch{..}=>MapError::Pin(format!("{e:?}")),TransferError::GlyphMismatch{..}=>MapError::GlyphMismatch,_=>MapError::Transfer(format!("{e:?}"))})?;
 let mut corner_nodes=std::collections::BTreeSet::new();let mut extremum_nodes=Vec::new();let mut unmatched=0;
 for tg in &t.targets{let Some((ci,k))=tg.captured else{unmatched+=1;continue};
  if tg.role==NodeRole::Corner{corner_nodes.insert((ci,k));}else if tg.extremum_x!=tg.extremum_y{extremum_nodes.push((ci,k,tg.extremum_x))}}
 Ok(FrameIdentity{frame,input_hash:crate::lever_api::hash_rings(rings),pin_sha256:reference.pin.sha256_hex.clone(),glyph_id:glyph_id.into(),corner_nodes,extremum_nodes,unmatched_targets:unmatched})
}
