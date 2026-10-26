//! Explicit design proxy over pixel source images. No original font exists: identity is a source-image classification assembled pixel to vector, never a font proof. The winning group's codepoints are never written to the font: the form moves to gid0 only, it is never copied into a character.
use crate::{GlyphRow,DrawnGlyph,bound_detector_validator::{DetectionState,PixelContext,PIXEL_INK_MODEL,pixel_form_sha256,BadNotdef}};
use std::{collections::{BTreeMap,HashMap},io::Read};
use kni_core::{cff_reader::sha256_hex,jpeg_source::Limits,capture::DecodeLimits};
use kni_metrics::self_anchored_spacing::GlyphSpacing;
const CLASSIFICATION:&str="repeated-pixel-form";
const HASH_BASIS:&str="pixel_form_sha256";
/// Typed proxy refusals share the bad_notdef surface without changing evidence errors.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ProxyError {
 Standard(BadNotdef),
 CandidateProxyContextMismatch,
 CandidateProxyResourceLimit,
 CandidateProxyShaMismatch,
 CandidateProxySelectionMismatch,
 CandidateProxyDecode(String),
 CandidateProxyInvalidSourceImage(String),
}
impl std::fmt::Display for ProxyError {
 fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {
  match self {
   Self::Standard(e)=>std::fmt::Display::fmt(e,f),
   Self::CandidateProxyDecode(detail)=>write!(f,"bad_notdef::CandidateProxyDecode:{detail}"),
   Self::CandidateProxyInvalidSourceImage(detail)=>write!(f,"bad_notdef::CandidateProxyInvalidSourceImage:{detail}"),
   other=>write!(f,"bad_notdef::{other:?}"),
  }
 }
}
impl std::error::Error for ProxyError {}
impl From<BadNotdef> for ProxyError { fn from(e:BadNotdef)->Self { Self::Standard(e) } }
pub fn select(glyphs:&[GlyphRow],expected_sha:&str,expected_cp:u32,root:&std::path::Path,png_limits:&DecodeLimits,limits:Limits)->Result<DetectionState,ProxyError>{
 if expected_cp==0 || char::from_u32(expected_cp).is_none(){return Err(BadNotdef::ReservedCodepoint.into());}
 if glyphs.len()>65_535{return Err(ProxyError::CandidateProxyResourceLimit);}
 let root=root.canonicalize().map_err(|_|BadNotdef::Io)?;
 let mut groups=BTreeMap::<String,Vec<(u32,&GlyphRow)>>::new();let mut snapshot=Vec::new();let mut left=limits.max_working_bytes;
 for g in glyphs {
  let path=g.image.canonicalize().map_err(|_|BadNotdef::Io)?;
  if !path.starts_with(&root){return Err(ProxyError::CandidateProxyContextMismatch);}
  let overhead=g.name.len().saturating_add(path.as_os_str().len()).saturating_add(512);
  left=left.checked_sub(overhead).ok_or(ProxyError::CandidateProxyResourceLimit)?;
  let mut f=std::fs::File::open(&path).map_err(|_|BadNotdef::Io)?;
  let n=usize::try_from(f.metadata().map_err(|_|BadNotdef::Io)?.len()).map_err(|_|ProxyError::CandidateProxyResourceLimit)?;
  let cap=limits.max_input_bytes.min(left);
  if n.saturating_add(1)>cap{return Err(ProxyError::CandidateProxyResourceLimit);}
  let mut b=Vec::new();b.try_reserve_exact(n.saturating_add(1)).map_err(|_|ProxyError::CandidateProxyResourceLimit)?;
  f.by_ref().take(n.saturating_add(1) as u64).read_to_end(&mut b).map_err(|_|BadNotdef::Io)?;
  if b.len()!=n{return Err(ProxyError::CandidateProxyResourceLimit);}
  left=left.checked_sub(n.saturating_add(1)).ok_or(ProxyError::CandidateProxyResourceLimit)?;
  let d=kni_core::capture_dispatch::decode_source(&b,png_limits,limits).map_err(|e|ProxyError::CandidateProxyDecode(format!("{e:?}")))?;
  let pin=pixel_form_sha256(d.width,d.height,&d.gray).map_err(|e|match e{BadNotdef::ResourceLimit=>ProxyError::CandidateProxyResourceLimit,other=>ProxyError::CandidateProxyInvalidSourceImage(format!("{other:?}"))})?;
  // Unencoded anonymous rows are never .notdef proxy candidates: the proxy
  // binds codepoint slots, and an anonymous glyph is always drawn.
  let Some(cp)=g.codepoint else{continue;};
  snapshot.push((cp,g.name.clone(),pin.clone()));
  groups.entry(pin).or_default().push((cp,g));
 }
 let mut state=select_groups(groups,expected_sha,expected_cp)?;
 if let DetectionState::CandidateProxy{source_snapshot,..}=&mut state{*source_snapshot=snapshot;}
 Ok(state)
}
fn select_groups(groups:BTreeMap<String,Vec<(u32,&GlyphRow)>>,expected_sha:&str,expected_cp:u32)->Result<DetectionState,ProxyError>{
 if expected_cp==0 || char::from_u32(expected_cp).is_none(){return Err(BadNotdef::ReservedCodepoint.into());}
 let max=groups.values().map(Vec::len).max().ok_or(BadNotdef::MissingPixelEvidence)?;
 if max<2{return Err(BadNotdef::MissingPixelEvidence.into());}
 if groups.values().filter(|g|g.len()==max).count()!=1{return Err(BadNotdef::AmbiguousPixelCandidate.into());}
 let (pin,mut group)=groups.into_iter().find(|(_,g)|g.len()==max).ok_or(BadNotdef::MissingPixelEvidence)?;
 group.sort_by_key(|(cp,_)|*cp);let selected=group[0];
 if pin!=expected_sha{return Err(ProxyError::CandidateProxyShaMismatch);}
 if selected.0!=expected_cp{return Err(ProxyError::CandidateProxySelectionMismatch);}
 Ok(DetectionState::CandidateProxy{selected_source_sha:pin.clone(),selected_cp:selected.0,candidate_cps:group.iter().map(|(cp,_)|*cp).collect(),selection_rule:"most-frequent-pixel-hash;within-group-lowest-cp".into(),generated_glyph_ref:selected.1.name.clone(),source_snapshot:group.iter().map(|(cp,g)|(*cp,g.name.clone(),pin.clone())).collect()})
}
pub fn assemble(state:&DetectionState,ctx:&PixelContext,drawn:&[DrawnGlyph],solved:&[GlyphSpacing],pins:&HashMap<String,String>,font_cps:&[u32],receipt:&mut String)->Result<(DrawnGlyph,f64,f64,f64),String>{
 let DetectionState::CandidateProxy{selected_source_sha,selected_cp,candidate_cps,selection_rule,generated_glyph_ref,source_snapshot}=state else{return Err("bad_notdef::CandidateProxyStateMismatch".into());};
 if ctx.source_sha256!=*selected_source_sha{return Err("bad_notdef::CandidateProxyContextMismatch".into());}
 if ctx.ink_model!=PIXEL_INK_MODEL{return Err("bad_notdef::CandidateProxyInkModelMismatch".into());}
 for cp in candidate_cps{if font_cps.contains(cp){return Err(format!("bad_notdef::CandidateProxyPopulationConflict: cp=0x{cp:x}"));}}
 for (cp,name,_) in source_snapshot{if candidate_cps.contains(cp) && name!=generated_glyph_ref && drawn.iter().any(|g|&g.glyph_id==name){return Err(format!("bad_notdef::CandidateProxyPopulationConflict: name={name}"));}}
 for (cp,name,pin) in source_snapshot {
  match pins.get(name) {
   None=>return Err(format!("bad_notdef::CandidateProxyIncompletePopulation: cp=0x{cp:x} name={name}")),
   Some(actual) if actual!=pin=>return Err(format!("bad_notdef::CandidateProxySnapshotMismatch: cp=0x{cp:x} name={name}")),
   _=>{}
  }
 }
 let mut snapshot=Vec::new();let mut ordered=source_snapshot.clone();ordered.sort();for (cp,name,pin) in ordered{snapshot.extend_from_slice(&cp.to_be_bytes());snapshot.extend_from_slice(&(name.len() as u64).to_be_bytes());snapshot.extend_from_slice(name.as_bytes());snapshot.extend_from_slice(pin.as_bytes());}
 let snapshot_sha=sha256_hex(&snapshot);
 if pins.get(generated_glyph_ref)!=Some(selected_source_sha){return Err("bad_notdef::CandidateProxyShaMismatch".into());}
 let source=drawn.iter().find(|g|&g.glyph_id==generated_glyph_ref).ok_or("bad_notdef::CandidateProxyGeneratedGlyphMissing")?;
 // Contract slot-width rule: the proxy notdef never enters the pair
 // cascade; its advance is the font's widest glyph advance.
 let advance=crate::max_glyph_advance(solved).map_err(|e|format!("bad_notdef::CandidateProxyAdvanceUnderivable:{e:?}"))?;
 if source.rings.is_empty(){return Err("bad_notdef::CandidateProxyNoInkOrInvalidMetric".into());}
 let mut proxy=source.clone();proxy.glyph_id=".notdef".into();
 let generated_sha=outline_sha(source);
 receipt.push_str(&format!("notdef_proxy\tclassification\t{CLASSIFICATION}\tdecision_basis\tsource-image\thash_basis\t{HASH_BASIS}\tpolicy\tcandidate-proxy\tcandidate_count\t{}\trule\t{}\tselected_cp\t0x{:x}\tsource_sha256\t{}\tstyle\t{}\tframe\t{}\tunits_per_px\t{}\tink_model\t{}\tgenerated_glyph_ref\t{}\tgenerated_glyph_sha256\t{}\tgenerated_sha_basis\tcoordinate-binary64-span-tags-v1\tsource_snapshot_sha256\t{snapshot_sha}\tadvance_basis\tmax-glyph-advance\tlsb\t0\trsb\t0\tadvance\t{}\n",candidate_cps.len(),selection_rule,selected_cp,selected_source_sha,ctx.style,ctx.frame,ctx.units_per_px,ctx.ink_model,generated_glyph_ref,generated_sha,advance));
 Ok((proxy,0.0,0.0,advance))
}
pub fn outline_sha(g:&DrawnGlyph)->String{
 use kni_core::reference_slice::{Point,Span};
 fn point(b:&mut Vec<u8>,p:&Point){b.extend_from_slice(&p.x.to_bits().to_be_bytes());b.extend_from_slice(&p.y.to_bits().to_be_bytes());}
 let mut b=b"kni-outline-binary64-v1\0".to_vec();b.extend_from_slice(&(g.rings.len() as u64).to_be_bytes());
 for r in &g.rings{point(&mut b,&r.start);b.extend_from_slice(&(r.spans.len() as u64).to_be_bytes());for s in &r.spans{match s{Span::Line{end}=>{b.push(1);point(&mut b,end)},Span::Cubic{control_one,control_two,end}=>{b.push(3);point(&mut b,control_one);point(&mut b,control_two);point(&mut b,end)}}}}
 sha256_hex(&b)
}
pub fn final_receipt(bytes:&[u8])->Result<String,String>{let f=kni_core::cff_reader::CffReader::from_bytes(bytes,&sha256_hex(bytes)).map_err(|e|format!("bad_notdef::CandidateProxyFinalReadback:{e:?}"))?;let g=f.read_glyph(0).map_err(|e|format!("bad_notdef::CandidateProxyFinalReadback:{e:?}"))?.drawn(".notdef".into());Ok(format!("notdef_proxy_final_gid0\toutline_sha256\t{}\tbasis\tcoordinate-binary64-span-tags-v1\tclassification\t{CLASSIFICATION}\tdecision_basis\tsource-image\n",outline_sha(&g)))}
#[cfg(test)] mod tests {
 use super::*;
 use std::path::PathBuf;
 fn tup<'a>(v:&[&'a GlyphRow])->Vec<(u32,&'a GlyphRow)>{v.iter().map(|g|(g.codepoint.unwrap(),*g)).collect()}
 fn row(cp:u32)->GlyphRow{GlyphRow{codepoint:Some(cp),extra_cps:vec![],name:format!("u{cp:x}"),image:PathBuf::from("unused"),scale:None}}
 fn ctx(pin:&str)->PixelContext{PixelContext{style:"fam-regular".into(),frame:"capture-default".into(),units_per_px:1.0,source_sha256:pin.into(),ink_model:PIXEL_INK_MODEL.into()}}
 fn png_limits()->DecodeLimits{DecodeLimits{max_input_bytes:1<<20,max_pixels:4096,max_working_bytes:1<<20}}
 fn png_gray(w:usize,h:usize,px:&[u8],extra_chunk:bool)->Vec<u8>{
  fn chunk(t:&[u8;4],b:&[u8])->Vec<u8>{let mut v=(b.len() as u32).to_be_bytes().to_vec();v.extend_from_slice(t);v.extend_from_slice(b);v.extend_from_slice(&0u32.to_be_bytes());v}
  fn adler(d:&[u8])->u32{let(mut a,mut b)=(1u32,0u32);for &x in d{a=(a+x as u32)%65521;b=(b+a)%65521;}(b<<16)|a}
  assert_eq!(px.len(),w*h);
  let mut raw=Vec::with_capacity((w+1)*h);for y in 0..h{raw.push(0);raw.extend_from_slice(&px[y*w..(y+1)*w]);}
  let mut z=vec![0x78u8,0x01,1];z.extend_from_slice(&(raw.len() as u16).to_le_bytes());z.extend_from_slice(&(!(raw.len() as u16)).to_le_bytes());z.extend_from_slice(&raw);z.extend_from_slice(&adler(&raw).to_be_bytes());
  let mut ihdr=Vec::new();ihdr.extend_from_slice(&(w as u32).to_be_bytes());ihdr.extend_from_slice(&(h as u32).to_be_bytes());ihdr.extend_from_slice(&[8,0,0,0,0]);
  let mut v=b"\x89PNG\r\n\x1a\n".to_vec();v.extend_from_slice(&chunk(b"IHDR",&ihdr));if extra_chunk{v.extend_from_slice(&chunk(b"tEXt",b"k\0v"));}v.extend_from_slice(&chunk(b"IDAT",&z));v.extend_from_slice(&chunk(b"IEND",&[]));v
 }
 #[test] fn reserved_or_non_scalar_cp_refuses_before_source_io(){
  let limits=Limits{max_input_bytes:4096,max_pixels:64,max_working_bytes:8192};
  for cp in [0,0xd800,0x110000] {
   let e=select(&[],&"a".repeat(64),cp,std::path::Path::new("missing-proxy-root"),&png_limits(),limits);
   assert!(matches!(e,Err(ProxyError::Standard(BadNotdef::ReservedCodepoint))));
  }
 }
 #[test] fn missing_source_root_is_io_not_context(){
  let limits=Limits{max_input_bytes:4096,max_pixels:64,max_working_bytes:8192};
  let root=std::env::temp_dir().join(format!("proxy-absent-{}",std::process::id())).join("missing-root");
  assert!(!root.exists());
  let e=select(&[],&"a".repeat(64),65,&root,&png_limits(),limits);
  assert!(matches!(e,Err(ProxyError::Standard(BadNotdef::Io))));
 }
 #[test] fn source_root_containment_budget_decode_and_snapshot_mutation_refuse(){
  let root=std::env::temp_dir().join(format!("proxy-root-{}",std::process::id()));let _=std::fs::remove_dir_all(&root);std::fs::create_dir(&root).unwrap();
  let pa=png_gray(2,2,&[9,9,9,9],false);let pb=png_gray(2,2,&[9,9,9,9],true);std::fs::write(root.join("a"),&pa).unwrap();std::fs::write(root.join("b"),&pb).unwrap();
  assert_ne!(sha256_hex(&pa),sha256_hex(&pb)); // file bytes differ; pixel form is identical
  let pin=pixel_form_sha256(2,2,&[9,9,9,9]).unwrap();
  let mut rows=[row(65),row(66)];rows[0].image=root.join("a");rows[1].image=root.join("b");let limits=Limits{max_input_bytes:4096,max_pixels:64,max_working_bytes:8192};let pl=png_limits();let state=select(&rows,&pin,65,&root,&pl,limits).unwrap();
  let d=[DrawnGlyph{glyph_id:rows[0].name.clone(),rings:vec![crate::notdef_routing_tests::notdef_readback_tests::quad(0.0,1.0,1.0)]}];let m=[GlyphSpacing{glyph_id:rows[0].name.clone(),lsb:0.0,rsb:0.0,advance:1.0}];let pins=HashMap::from([(rows[0].name.clone(),pin.clone()),(rows[1].name.clone(),"changed".into())]);assert_eq!(assemble(&state,&ctx(&pin),&d,&m,&pins,&[],&mut String::new()).unwrap_err().to_string(),format!("bad_notdef::CandidateProxySnapshotMismatch: cp=0x42 name={}",rows[1].name));
  let pins=HashMap::from([(rows[0].name.clone(),pin.clone())]);assert_eq!(assemble(&state,&ctx(&pin),&d,&m,&pins,&[],&mut String::new()).unwrap_err().to_string(),format!("bad_notdef::CandidateProxyIncompletePopulation: cp=0x42 name={}",rows[1].name));
  assert_eq!(select(&rows,&pin,65,&root,&pl,Limits{max_working_bytes:1,..limits}).unwrap_err().to_string(),"bad_notdef::CandidateProxyResourceLimit");
  let child=root.join("child");std::fs::create_dir(&child).unwrap();assert_eq!(select(&rows,&pin,65,&child,&pl,limits).unwrap_err().to_string(),"bad_notdef::CandidateProxyContextMismatch");
  std::fs::write(root.join("g"),b"not-an-image").unwrap();let mut bad=[row(67),row(68)];bad[0].image=root.join("a");bad[1].image=root.join("g");let e=select(&bad,&pin,65,&root,&pl,limits).unwrap_err().to_string();assert!(e.starts_with("bad_notdef::CandidateProxyDecode"),"{e}");
  let _=std::fs::remove_dir_all(root);
 }
 #[test] fn unique_largest_repeat_allows_two_aliases_and_preserves_all(){let rows:Vec<_>=(0x100..0x100+220).map(row).collect();let mut g=BTreeMap::new();g.insert("a".repeat(64),rows.iter().map(|g|(g.codepoint.unwrap(),g)).collect());let s=select_groups(g,&"a".repeat(64),0x100).unwrap();let DetectionState::CandidateProxy{candidate_cps,..}=s else{panic!()};assert_eq!(candidate_cps.len(),220);assert_eq!(rows.len(),220);let rows=[row(65),row(66)];let mut g=BTreeMap::new();g.insert("a".repeat(64),rows.iter().map(|g|(g.codepoint.unwrap(),g)).collect());assert!(select_groups(g,&"a".repeat(64),65).is_ok());}
 #[test] fn distinct_sha_tie_refuses_not_first(){let r=[row(65),row(66),row(67),row(68)];let mut g=BTreeMap::new();g.insert("a".repeat(64),tup(&[&r[0],&r[1]]));g.insert("b".repeat(64),tup(&[&r[2],&r[3]]));assert_eq!(select_groups(g,&"a".repeat(64),65).unwrap_err().to_string(),"bad_notdef::AmbiguousPixelCandidate");}
 #[test] fn wrong_pin_and_cp_refuse(){let r=[row(65),row(66)];let mut g=BTreeMap::new();g.insert("a".repeat(64),tup(&r.iter().collect::<Vec<_>>()));assert_eq!(select_groups(g.clone(),&"b".repeat(64),65).unwrap_err().to_string(),"bad_notdef::CandidateProxyShaMismatch");assert_eq!(select_groups(g,&"a".repeat(64),66).unwrap_err().to_string(),"bad_notdef::CandidateProxySelectionMismatch");}
 #[test] fn most_frequent_hash_wins_and_top_tie_refuses(){
  let r=[row(65),row(66),row(67),row(68),row(69),row(70)];let mut g=BTreeMap::new();g.insert("a".repeat(64),tup(&[&r[0],&r[1],&r[2]]));g.insert("b".repeat(64),tup(&[&r[3],&r[4]]));g.insert("c".repeat(64),tup(&[&r[5]]));
  let s=select_groups(g,&"a".repeat(64),65).unwrap();let DetectionState::CandidateProxy{selected_cp,candidate_cps,selection_rule,..}=s else{panic!()};assert_eq!(selected_cp,65);assert_eq!(candidate_cps,vec![65,66,67]);assert_eq!(selection_rule,"most-frequent-pixel-hash;within-group-lowest-cp");
  let r2=[row(68),row(69)];let mut g=BTreeMap::new();g.insert("a".repeat(64),tup(&[&r2[0],&r2[1]]));g.insert("b".repeat(64),tup(&[&r2[0],&r2[1]]));assert_eq!(select_groups(g,&"a".repeat(64),68).unwrap_err().to_string(),"bad_notdef::AmbiguousPixelCandidate");
 }
 #[test] fn singleton_and_all_unique_forms_refuse(){
  let r=[row(65)];let mut g=BTreeMap::new();g.insert("a".repeat(64),tup(&[&r[0]]));assert_eq!(select_groups(g,&"a".repeat(64),65).unwrap_err().to_string(),"bad_notdef::MissingPixelEvidence");
  let r=[row(65),row(66),row(67)];let mut g=BTreeMap::new();g.insert("a".repeat(64),tup(&[&r[0]]));g.insert("b".repeat(64),tup(&[&r[1]]));g.insert("c".repeat(64),tup(&[&r[2]]));assert_eq!(select_groups(g,&"a".repeat(64),65).unwrap_err().to_string(),"bad_notdef::MissingPixelEvidence");
 }
 #[test] fn context_sha_and_ink_model_mismatch_refuse(){
  let rows=[row(65),row(66)];let pin="a".repeat(64);let mut g=BTreeMap::new();g.insert(pin.clone(),rows.iter().map(|g|(g.codepoint.unwrap(),g)).collect());let state=select_groups(g,&pin,65).unwrap();
  let d=[DrawnGlyph{glyph_id:rows[0].name.clone(),rings:vec![crate::notdef_routing_tests::notdef_readback_tests::quad(0.0,1.0,1.0)]}];let m=[GlyphSpacing{glyph_id:rows[0].name.clone(),lsb:0.0,rsb:0.0,advance:1.0}];let pins=HashMap::from([(rows[0].name.clone(),pin.clone()),(rows[1].name.clone(),pin.clone())]);
  let mut bad=ctx(&pin);bad.source_sha256="b".repeat(64);assert_eq!(assemble(&state,&bad,&d,&m,&pins,&[],&mut String::new()).unwrap_err().to_string(),"bad_notdef::CandidateProxyContextMismatch");
  let mut bad=ctx(&pin);bad.ink_model="rgba-premul".into();assert_eq!(assemble(&state,&bad,&d,&m,&pins,&[],&mut String::new()).unwrap_err().to_string(),"bad_notdef::CandidateProxyInkModelMismatch");
 }
 #[test] fn proxy_gid0_moves_form_placeholders_absent_from_cmap(){
  let rows:Vec<_>=(0x100..0x100+220).map(row).collect();let pin="a".repeat(64);let mut groups=BTreeMap::new();groups.insert(pin.clone(),rows.iter().map(|g|(g.codepoint.unwrap(),g)).collect());let state=select_groups(groups,&pin,0x100).unwrap();
  let drawings=vec![DrawnGlyph{glyph_id:rows[0].name.clone(),rings:vec![crate::notdef_routing_tests::notdef_readback_tests::quad(0.0,100.0,100.0)]},DrawnGlyph{glyph_id:"A".into(),rings:vec![crate::notdef_routing_tests::notdef_readback_tests::quad(0.0,50.0,80.0)]}]; // zero-origin quads: the encoder normalizes x_min to 0, this keeps readback identical to the drawing
  let metrics=vec![GlyphSpacing{glyph_id:rows[0].name.clone(),lsb:0.0,rsb:100.0,advance:200.0},GlyphSpacing{glyph_id:"A".into(),lsb:0.0,rsb:220.0,advance:300.0}]; // lsb=0: the encoder translates outlines by -lsb, zero keeps the readback identical to the drawing
  let pins:HashMap<_,_>=rows.iter().map(|g|(g.name.clone(),pin.clone())).collect();let mut receipt=String::new();let (proxy,l,r,a)=assemble(&state,&ctx(&pin),&drawings,&metrics,&pins,&[0x41],&mut receipt).unwrap();
  assert!(receipt.contains("classification\trepeated-pixel-form"));assert!(receipt.contains("decision_basis\tsource-image"));assert!(receipt.contains("hash_basis\tpixel_form_sha256"));assert!(receipt.contains("rule\tmost-frequent-pixel-hash;within-group-lowest-cp"));assert!(receipt.contains("candidate_count\t220"));assert!(receipt.contains("advance_basis\tmax-glyph-advance"));
  assert!(!receipt.contains("excluded_cp_count"));assert!(!receipt.contains("identity_claim"));assert!(!receipt.contains("source_notdef_identity"));assert!(!receipt.contains("font_proof"));assert!(!receipt.contains("requested_unsupported"));
  let gs=vec![proxy,drawings[1].clone()];let mapping=[(0x41u32,1u16)];let ms=vec![(".notdef".into(),l,r,a),("A".into(),5.0,5.0,300.0)];
  let f=kni_core::generated_native::prepare_generated(&gs,&mapping,&ms,&crate::notdef_routing_tests::notdef_readback_tests::meta()).unwrap();
  assert_eq!(f.glyphs[0].advance,300);assert_eq!(f.glyphs[1].advance,300);
  let b=kni_core::native_font::encode_with_layout(&f,None).unwrap();let font=kni_core::cff_reader::CffReader::from_bytes(&b,&sha256_hex(&b)).unwrap();
  assert_eq!(font.codepoints(),vec![(0x41,1)]);
  for row in &rows{assert!(font.glyph_for_codepoint(row.codepoint.unwrap()).is_none());}
  assert_eq!(format!("{:?}",font.read_glyph(0).unwrap().rings),format!("{:?}",drawings[0].rings));
  let fin=final_receipt(&b).unwrap();assert!(fin.contains("outline_sha256"));assert!(fin.contains("classification\trepeated-pixel-form"));assert!(fin.contains("decision_basis\tsource-image"));assert!(!fin.contains("font_proof"));assert!(!fin.contains("identity_claim"));
 }
 #[test] fn candidate_cp_in_font_or_alias_in_population_refuse(){
  let rows=[row(0x100),row(0x101)];let pin="a".repeat(64);let mut g=BTreeMap::new();g.insert(pin.clone(),rows.iter().map(|g|(g.codepoint.unwrap(),g)).collect());let state=select_groups(g,&pin,0x100).unwrap();
  let d=[DrawnGlyph{glyph_id:rows[0].name.clone(),rings:vec![crate::notdef_routing_tests::notdef_readback_tests::quad(0.0,1.0,1.0)]},DrawnGlyph{glyph_id:rows[1].name.clone(),rings:vec![crate::notdef_routing_tests::notdef_readback_tests::quad(0.0,1.0,1.0)]}];
  let m=[GlyphSpacing{glyph_id:rows[0].name.clone(),lsb:0.0,rsb:0.0,advance:1.0},GlyphSpacing{glyph_id:rows[1].name.clone(),lsb:0.0,rsb:0.0,advance:1.0}];let pins=HashMap::from([(rows[0].name.clone(),pin.clone()),(rows[1].name.clone(),pin.clone())]);
  assert_eq!(assemble(&state,&ctx(&pin),&d,&m,&pins,&[0x100],&mut String::new()).unwrap_err().to_string(),"bad_notdef::CandidateProxyPopulationConflict: cp=0x100");
  assert_eq!(assemble(&state,&ctx(&pin),&d,&m,&pins,&[],&mut String::new()).unwrap_err().to_string(),format!("bad_notdef::CandidateProxyPopulationConflict: name={}",rows[1].name));
 }
 #[test] fn empty_source_never_becomes_verified_blank(){let s=DetectionState::CandidateProxy{selected_source_sha:"a".repeat(64),selected_cp:65,candidate_cps:vec![65,66],selection_rule:"test".into(),generated_glyph_ref:"a".into(),source_snapshot:vec![]};let d=[DrawnGlyph{glyph_id:"a".into(),rings:vec![]}];let m=[GlyphSpacing{glyph_id:"a".into(),lsb:0.0,rsb:0.0,advance:200.0}];assert_eq!(assemble(&s,&ctx(&"a".repeat(64)),&d,&m,&HashMap::from([("a".into(),"a".repeat(64))]),&[],&mut String::new()).unwrap_err().to_string(),"bad_notdef::CandidateProxyNoInkOrInvalidMetric");}
}
