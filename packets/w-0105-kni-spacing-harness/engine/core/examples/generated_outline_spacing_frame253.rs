//! CANDIDATE 253 SINGLE-PASS v2.1: frozen-param source-frame integer emission driver.
//! fit_from_source_frame (no caller Y-restore) + per-glyph incremental checkpoint/resume
//! + baseline/refined dual dump + quantize-idempotence + explicit-TX ledger + staged atomic publish.
//! Receipt-only additions; spacing/kern/export algorithm untouched.
use kni_core::{capture::capture_gray,capture_dispatch::decode_source,jpeg_source::Limits,cubic_fit::FitPolicy,reference_slice::{Point,Span,DrawnGlyph,ReferenceRing},lever_api::hash_rings};
use kni_metrics::{outline_spacing::{OutlineInput,ScanPolicy,profile_outline},self_anchored_spacing::{SpacingPolicy,FontContext,solve_spacing}};
use std::{fs,path::{Path,PathBuf},fmt::Write as _,time::Instant};
#[path="support/cubic_flatten.rs"] mod cubic_flatten;
use cubic_flatten::flatten_cubic;
#[path="support/generated_native_fixture.rs"] mod generated_native_fixture;
fn sha(b:&[u8])->String{kni_core::economy_eval::sha256_hex(b)}
fn atomic_write(p:&Path,body:&str)->Result<(),String>{let t=p.with_extension("tmp");fs::write(&t,body).map_err(|e|e.to_string())?;fs::rename(&t,p).map_err(|e|e.to_string())}
fn scalar(s:&str)->Result<f64,String>{let v:f64=s.parse().map_err(|_|format!("bad scalar {s}"))?;if !v.is_finite()||v<=0.0{return Err("policy values must be finite and positive".into())}Ok(v)}
fn ring_rows(g:&str,rings:&[ReferenceRing])->String{let mut s=String::new();for r in rings{writeln!(s,"R\t{}\t{},{}",g,r.start.x,r.start.y).unwrap();for sp in &r.spans{match sp{Span::Line{end}=>writeln!(s,"L\t{}\t{},{}",g,end.x,end.y).unwrap(),Span::Cubic{control_one:a,control_two:b,end}=>writeln!(s,"C\t{}\t{},{},{},{},{},{}",g,a.x,a.y,b.x,b.y,end.x,end.y).unwrap()}}}s}
fn parse_rings(body:&str,g:&str)->Result<Vec<ReferenceRing>,String>{let mut out=Vec::new();let num=|s:&str|s.parse::<f64>().map_err(|_|format!("bad ring number {s}"));for line in body.lines(){let v:Vec<_>=line.split('\t').collect();if v.len()!=3||v[1]!=g{return Err(format!("checkpoint row mismatch for {g}"))}let xy=|s:&str|->Result<(f64,f64),String>{let mut it=s.split(',');Ok((num(it.next().ok_or("x")?)?,num(it.next().ok_or("y")?)?))};match v[0]{"R"=>{let(x,y)=xy(v[2])?;out.push(ReferenceRing{start:Point{x,y},spans:Vec::new()});},"L"=>{let(x,y)=xy(v[2])?;out.last_mut().ok_or("L before R")?.spans.push(Span::Line{end:Point{x,y}});},"C"=>{let n:Vec<_>=v[2].split(',').collect();if n.len()!=6{return Err("bad C row".into())}let f:Vec<f64>=n.iter().map(|s|num(s)).collect::<Result<_,_>>()?;out.last_mut().ok_or("C before R")?.spans.push(Span::Cubic{control_one:Point{x:f[0],y:f[1]},control_two:Point{x:f[2],y:f[3]},end:Point{x:f[4],y:f[5]}});},_=>return Err("bad checkpoint kind".into())}}if out.is_empty(){return Err("empty checkpoint".into())}Ok(out)}
fn check_rings(rings:&[ReferenceRing],g:&str)->Result<(),String>{
 for r in rings{
  let mut flat:Vec<&Point>=vec![&r.start];for s in &r.spans{match s{Span::Line{end}=>flat.push(end),Span::Cubic{control_one:a,control_two:b,end}=>{flat.push(a);flat.push(b);flat.push(end)}}}
  for p in &flat{if !p.x.is_finite()||!p.y.is_finite(){return Err(format!("non-finite coord {g}"))}if p.x!=p.x.round()||p.y!=p.y.round(){return Err(format!("non-integer coord {g}: {},{}",p.x,p.y))}}
  let end=flat.last().ok_or("empty ring")?;if end.x!=r.start.x||end.y!=r.start.y{return Err(format!("open ring {g}"))}
 }
 Ok(())
}
fn main()->Result<(),String>{
 let a:Vec<String>=std::env::args().collect();
 if a.len()!=19{return Err("usage: generated_outline_spacing_frame253 MANIFEST OUTPUT_DIR SCALE RDP_EPS FIT_SE REFITS ROW_STEP FLATTEN_TOL MAX_ROWS MAX_PAIR_EVALS MAX_PAIRS MAX_JPEG_BYTES MAX_PIXELS MAX_WORKING_BYTES FLATTEN_DEPTH MAX_FLATTEN_POINTS CODE_PIN EXPECTED_COUNT".into())}
 let out=PathBuf::from(&a[2]);
 if out.join("A.otf").exists(){return Err("final outputs already exist - completed run".into())}
 if !out.exists(){fs::create_dir(&out).map_err(|e|e.to_string())?;}
 let dump=out.join("dump");if !dump.exists(){fs::create_dir(&dump).map_err(|e|e.to_string())?;}
 let(scale,eps,se,row_step,flat)=(scalar(&a[3])?,scalar(&a[4])?,scalar(&a[5])?,scalar(&a[7])?,scalar(&a[8])?);
 let refits:usize=a[6].parse().map_err(|_|"bad refits")?;let max_rows:usize=a[9].parse().map_err(|_|"bad max_rows")?;
 let max_pairs_eval:u64=a[10].parse().map_err(|_|"bad pair bound")?;let max_pairs:usize=a[11].parse().map_err(|_|"bad pair count")?;
 let max_bytes:usize=a[12].parse().map_err(|_|"bad byte bound")?;
 let max_pixels:usize=a[13].parse().map_err(|_|"bad pixel bound")?;let working:usize=a[14].parse().map_err(|_|"bad working bound")?;let depth:usize=a[15].parse().map_err(|_|"bad flatten depth")?;
 let initial_max_flatten_points:usize=a[16].parse().map_err(|_|"bad flatten point bound")?;
 let mut flat_remaining:usize=initial_max_flatten_points;
 let code_pin=&a[17];if code_pin.len()!=64||!code_pin.bytes().all(|b|b.is_ascii_hexdigit()&&!b.is_ascii_uppercase()){return Err("code pin must be lowercase sha256 hex".into())}
 let expected_count:usize=a[18].parse().map_err(|_|"bad expected count")?;
 let manifest_sha=sha(&fs::read(&a[1]).map_err(|e|e.to_string())?);
 let raw=fs::read_to_string(&a[1]).map_err(|e|e.to_string())?;let mut lines=raw.lines();
 if lines.next()!=Some("glyph_id\tcodepoint_hex\tpath\tsource_pin"){return Err("manifest header mismatch".into())}
 let params_tag=format!("scale={scale} eps={eps} se={se} refits={refits} row_step={row_step} flat={flat} max_rows={max_rows} pair_evals={max_pairs_eval} max_pairs={max_pairs} jpeg={max_bytes} pixels={max_pixels} working={working} depth={depth} maxflat_init={initial_max_flatten_points} code_pin={code_pin} expected_count={expected_count} manifest_sha256={manifest_sha}");
 let mut codepoints=Vec::new();let mut profiles=Vec::new();let mut drawn=Vec::<DrawnGlyph>::new();let mut baselines=Vec::<(String,Vec<ReferenceRing>)>::new();let mut geometry=String::from("kind\tglyph\tvalues\n");let mut identity=String::from("glyph_id\tcodepoint_hex\tsource_pin\n");let mut trace=String::new();let mut timing=String::from("glyph_id\tseconds\tpath\n");let mut ids=std::collections::BTreeSet::new();let mut cps=std::collections::BTreeSet::new();
 for line in lines {let v:Vec<_>=line.split('\t').collect();if v.len()!=4||v.iter().any(|s|s.is_empty())||!v[0].bytes().all(|b|b.is_ascii_alphanumeric()||b"._-".contains(&b))||!ids.insert(v[0].to_string()){return Err("bad or duplicate identity".into())}
  let cp=u32::from_str_radix(v[1].trim_start_matches("U+"),16).map_err(|_|"bad codepoint")?;if char::from_u32(cp).is_none()||!cps.insert(cp){return Err("invalid unicode".into())}
  codepoints.push((v[0].to_string(),cp));
  let meta_p=dump.join(format!("{}.meta",v[0]));let rings_p=dump.join(format!("{}.rings.tsv",v[0]));let base_p=dump.join(format!("{}.baseline.tsv",v[0]));
  let (rings,base,spans,fb,dropped,baseline_area,final_area,origin_x,origin_y,elapsed,path_tag):(Vec<ReferenceRing>,Vec<ReferenceRing>,usize,bool,usize,f64,f64,f64,f64,f64,&str);
  if meta_p.exists()||rings_p.exists()||base_p.exists(){
   if !(meta_p.exists()&&rings_p.exists()&&base_p.exists()){return Err(format!("partial checkpoint triplet {}: resume refused",v[0]))}
   let meta=fs::read_to_string(&meta_p).map_err(|e|e.to_string())?;
   let get=|k:&str|meta.lines().find_map(|l|l.strip_prefix(k));
   if get("glyph_id=").ok_or("checkpoint missing glyph_id")?!=v[0]{return Err(format!("checkpoint glyph_id mismatch {}",v[0]))}
   if get("source_pin=").ok_or("checkpoint missing pin")?!=v[3]{return Err(format!("checkpoint pin mismatch {}: resume refused",v[0]))}
   if get("params=").ok_or("checkpoint missing params")?!=params_tag{return Err(format!("checkpoint params mismatch {}: resume refused",v[0]))}
   let live=fs::read(v[2]).map_err(|e|e.to_string())?;if sha(&live)!=v[3]{return Err(format!("resume source live sha mismatch {}",v[0]))}
   let rings_body=fs::read_to_string(&rings_p).map_err(|e|e.to_string())?;let base_body=fs::read_to_string(&base_p).map_err(|e|e.to_string())?;
   if sha(rings_body.as_bytes())!=get("rings_sha256=").ok_or("checkpoint missing rings sha")?{return Err(format!("checkpoint rings content sha mismatch {}",v[0]))}
   if sha(base_body.as_bytes())!=get("baseline_sha256=").ok_or("checkpoint missing baseline sha")?{return Err(format!("checkpoint baseline content sha mismatch {}",v[0]))}
   let r=parse_rings(&rings_body,v[0])?;let b=parse_rings(&base_body,v[0])?;
   check_rings(&r,v[0])?;check_rings(&b,v[0])?;
   if format!("{:016x}",hash_rings(&r))!=get("refined_hash=").ok_or("checkpoint missing refined hash")?{return Err(format!("refined hash mismatch {}",v[0]))}
   if format!("{:016x}",hash_rings(&b))!=get("baseline_hash=").ok_or("checkpoint missing baseline hash")?{return Err(format!("baseline hash mismatch {}",v[0]))}
   spans=r.iter().map(|x|x.spans.len()).sum();
   if spans.to_string()!=get("refined_spans=").ok_or("checkpoint missing refined spans")?{return Err(format!("refined node count mismatch {}",v[0]))}
   let bsp:usize=b.iter().map(|x|x.spans.len()).sum();if bsp.to_string()!=get("baseline_spans=").ok_or("checkpoint missing baseline spans")?{return Err(format!("baseline node count mismatch {}",v[0]))}
   fb=get("fallback=").ok_or("checkpoint missing fallback")?=="true";dropped=get("dropped=").ok_or("checkpoint missing dropped")?.parse().map_err(|_|"bad dropped")?;
   baseline_area=get("baseline_area=").ok_or("checkpoint missing area")?.parse().map_err(|_|"bad area")?;final_area=get("final_area=").ok_or("checkpoint missing area")?.parse().map_err(|_|"bad area")?;
   origin_x=get("origin_x=").ok_or("checkpoint missing origin")?.parse().map_err(|_|"bad origin")?;origin_y=get("origin_y=").ok_or("checkpoint missing origin")?.parse().map_err(|_|"bad origin")?;
   elapsed=0.0;path_tag="checkpoint";rings=r;base=b;
  }else{
   let t0=Instant::now();
   let bytes=fs::read(v[2]).map_err(|e|e.to_string())?;if v[3].len()!=64||!v[3].bytes().all(|b|b.is_ascii_hexdigit()&&!b.is_ascii_uppercase())||sha(&bytes)!=v[3]{return Err(format!("source pin mismatch {}",v[0]));}
   let decoded=decode_source(&bytes,&kni_core::capture::DecodeLimits{max_input_bytes:max_bytes,max_pixels:max_pixels,max_working_bytes:working},Limits{max_input_bytes:max_bytes,max_pixels,max_working_bytes:working}).map_err(|e|format!("decode {}: {:?}",v[0],e))?;
   let captured=capture_gray(decoded.width,decoded.height,&decoded.gray,eps)?;
   let drawing=kni_core::generated_draw_frame::fit_from_source_frame(&captured,&decoded.gray,scale,&FitPolicy{squared_error:se,max_refits:refits})?;
   let r=drawing.rings;let b=drawing.baseline;spans=drawing.source_fit_spans;fb=drawing.fallback;dropped=drawing.dropped;baseline_area=drawing.baseline_area;final_area=drawing.final_area;origin_x=captured.origin_x;origin_y=captured.origin_y;elapsed=t0.elapsed().as_secs_f64();path_tag="fit";
   check_rings(&r,v[0])?;check_rings(&b,v[0])?;
   // per-glyph quantize-idempotence assert (candidate rings must already be integer)
   let quantized:Vec<ReferenceRing>=r.iter().map(|rg|{let mut rg=rg.clone();let q=|p:&mut Point|{p.x=p.x.round();p.y=p.y.round();};q(&mut rg.start);for s in &mut rg.spans{match s{Span::Line{end}=>q(end),Span::Cubic{control_one:a,control_two:b,end}=>{q(a);q(b);q(end)}}}rg}).collect();
   if hash_rings(&r)!=hash_rings(&quantized){return Err(format!("quantize idempotence violated {}",v[0]))}
   let rings_body=ring_rows(v[0],&r);let base_body=ring_rows(v[0],&b);
   let meta=format!("glyph_id={}\nsource_pin={}\nparams={}\norigin_x={}\norigin_y={}\nbaseline_area={}\nfinal_area={}\nfallback={}\ndropped={}\nrefined_spans={}\nbaseline_spans={}\nrefined_hash={:016x}\nbaseline_hash={:016x}\nrings_sha256={}\nbaseline_sha256={}\nidempotent=true\nseconds={}\n",v[0],v[3],params_tag,origin_x,origin_y,baseline_area,final_area,fb,dropped,r.iter().map(|x|x.spans.len()).sum::<usize>(),b.iter().map(|x|x.spans.len()).sum::<usize>(),hash_rings(&r),hash_rings(&b),sha(rings_body.as_bytes()),sha(base_body.as_bytes()),elapsed);
   atomic_write(&rings_p,&rings_body)?;atomic_write(&base_p,&base_body)?;atomic_write(&meta_p,&meta)?;rings=r;base=b;
  }
  writeln!(timing,"{}\t{}\t{}",v[0],elapsed,path_tag).unwrap();
  writeln!(trace,"drawing {} baseline_area={} final_area={} spans={} fallback={} dropped={} origin=({}, {}) path={}",v[0],baseline_area,final_area,spans,fb,dropped,origin_x,origin_y,path_tag).unwrap();
  let mut polygons=Vec::new();
  for r in &rings {let mut poly=vec![[r.start.x,r.start.y]];let mut start=r.start;writeln!(geometry,"R\t{}\t{},{}",v[0],start.x,start.y).unwrap();
   for span in &r.spans {match span {
    Span::Line{end}=>{poly.push([end.x,end.y]);writeln!(geometry,"L\t{}\t{},{}",v[0],end.x,end.y).unwrap();start=*end},
    Span::Cubic{control_one,control_two,end}=>{let before=poly.len();flatten_cubic([start,*control_one,*control_two,*end],flat,depth,flat_remaining,&mut poly).map_err(|e|e.to_string())?;flat_remaining-=poly.len()-before;writeln!(geometry,"C\t{}\t{},{},{},{},{},{}",v[0],control_one.x,control_one.y,control_two.x,control_two.y,end.x,end.y).unwrap();start=*end}
   }}polygons.push(poly);
  }
  let profile=profile_outline(&OutlineInput{glyph_id:v[0].into(),source_pin:v[3].into(),upm:1000,origin:[0.0,0.0],rings:polygons,flatten_tolerance:flat},ScanPolicy{row_step,max_rows,merge_guard:kni_metrics::outline_spacing::MERGE_GUARD_UNITS,grid_anchor_y:Some(0.0)}).map_err(|e|format!("profile {}: {:?}",v[0],e))?;
  profiles.push(profile);drawn.push(DrawnGlyph{glyph_id:v[0].into(),rings});baselines.push((v[0].to_string(),base));
  writeln!(identity,"{}\t{}\t{}",v[0],v[1],v[3]).unwrap();
 }
 if drawn.len()!=expected_count{return Err(format!("expected {} glyphs, manifest gave {}",expected_count,drawn.len()))}
 let context=FontContext{glyph_codepoints:codepoints.clone(),..FontContext::default()};
 let policy=SpacingPolicy{sample_resolution:row_step,max_pair_evaluations:max_pairs_eval,max_pairs,pair_min_shared_rows:1,lambda:Some(0.0),dcap:None, contrast_floor:false,cadence_class_pass:false,class_channel_targets:false};
 let solved=solve_spacing(&profiles,Some(&context),&policy).map_err(|e|format!("spacing: {:?}",e))?;
 // STAGED EXPORT: everything lands in private stage dir; publish (rename) only after ALL validation passes.
 let stage=out.join("stage");if stage.exists(){fs::remove_dir_all(&stage).map_err(|e|e.to_string())?;}fs::create_dir(&stage).map_err(|e|e.to_string())?;
 let native=generated_native_fixture::export_fixture(&drawn,&solved,&codepoints,&stage)?;
 let names:std::collections::BTreeMap<_,_>=native.raw_to_cff.iter().cloned().collect();
 let reverse:std::collections::BTreeMap<_,_>=native.raw_to_cff.iter().map(|(raw,cff)|(cff.clone(),raw.clone())).collect();
 // EXPLICIT TX LEDGER: source of truth = actual prepare path (b_ledger from prepared output).
 // analytic ink xmin may be FRACTIONAL (cubic extremum) - finite check only; integer-TX point identity is the proof.
 let mut txl=String::from("glyph_id\trequested_lsb\tanalytic_input_ink_xmin\ttx_pointwise_exact\tformula_diagnostic\tactual_ink_lsb\tpointwise_identity\n");
 for g in &drawn {let raw_id=&g.glyph_id;
  let sg=solved.glyphs.iter().find(|s|&s.glyph_id==raw_id).ok_or("missing solved glyph")?;
  let ink=kni_core::generated_native::ink_min_x(g).map_err(|e|format!("ink_min_x {}: {:?}",raw_id,e))?;
  let xmin=ink.ok_or_else(||format!("empty ink {}",raw_id))?;
  if !xmin.is_finite(){return Err(format!("non-finite ink xmin {}",raw_id))}
  let cff=reverse.iter().find(|(_,r)|*r==raw_id).map(|(c,_)|c.clone()).ok_or("missing cff id")?;
  let led=native.b_ledger.iter().find(|l|l.glyph_id==*cff).ok_or("missing b ledger row")?;
  // ledger x_translation is DIAGNOSTIC (raw analytic delta, not quantized; ulp-noisy) - not the TX source.
  if led.quantized_input_ink_xmin!=xmin{return Err(format!("ledger input ink xmin mismatch {}: ledger {} vs analytic {}",raw_id,led.quantized_input_ink_xmin,xmin))}
  let exported=native.exported_b.iter().find(|e|reverse.get(&e.glyph_id)==Some(raw_id)).ok_or("missing exported glyph")?;
  if g.rings.len()!=exported.rings.len(){return Err(format!("ring count mismatch {}",raw_id))}
  for(ri,(ir,er))in g.rings.iter().zip(&exported.rings).enumerate(){
   if ir.spans.len()!=er.spans.len(){return Err(format!("span count mismatch {} ring {}",raw_id,ri))}
   for(si,(is,es))in ir.spans.iter().zip(&er.spans).enumerate(){let k=|s:&Span|match s{Span::Line{..}=>0u8,Span::Cubic{..}=>1};if k(is)!=k(es){return Err(format!("span kind mismatch {} ring {} span {}",raw_id,ri,si))}}}
  let pts=|rings:&[ReferenceRing]|->Vec<(f64,f64)>{let mut o=Vec::new();for r in rings{o.push((r.start.x,r.start.y));for s in &r.spans{match s{Span::Line{end}=>o.push((end.x,end.y)),Span::Cubic{control_one:a,control_two:b,end}=>{o.push((a.x,a.y));o.push((b.x,b.y));o.push((end.x,end.y))}}}}o};
  let ip=pts(&g.rings);let ep=pts(&exported.rings);
  if ip.len()!=ep.len(){return Err(format!("exported point count mismatch {}",raw_id))}
  // PRIMARY TX: pointwise EXACT recover from integer point sequences (chief fix-1; writer untouched)
  let ((ix0,_),(ex0,_))=ip.iter().zip(&ep).next().ok_or("empty point sequence")?;
  let tx=ex0-ix0;
  let ndiff=ip.iter().zip(&ep).filter(|((ix,iy),(ex,ey))|!(*ex-*ix==tx&&*ey-*iy==0.0)).count();
  let ident=ndiff==0;
  if !ident{return Err(format!("pointwise inverse-TX identity FAILED {} ({} points deviate)",raw_id,ndiff))}
  if tx.fract()!=0.0{return Err(format!("non-integer pointwise DX {}: {}",raw_id,tx))}
  // bounded numeric crosschecks (analytic roots re-computed pre/post translate may differ by ulp)
  if (led.x_translation-tx).abs()>1e-6{return Err(format!("ledger x_translation beyond bound {}: ledger {} vs pointwise {}",raw_id,led.x_translation,tx))}
  if (led.actual_ink_lsb-(xmin+tx)).abs()>1e-6{return Err(format!("actual_ink_lsb beyond numeric bound {}",raw_id))}
  let formula=(sg.lsb-xmin).round();
  writeln!(txl,"{}\t{}\t{}\t{}\t{}\t{}\t{}",raw_id,sg.lsb,xmin,tx,formula,led.actual_ink_lsb,ident).unwrap();
 }
 let mut export_profiles=Vec::new();let mut export_solved=solved.clone();
 for glyph in &native.exported_b {let raw_id=match reverse.get(&glyph.glyph_id){Some(id)=>id,None=>continue};let source=profiles.iter().find(|p|&p.glyph_id==raw_id).ok_or("missing raw profile")?;let mut polygons=Vec::new();
 for ring in &glyph.rings {let mut poly=vec![[ring.start.x,ring.start.y]];let mut start=ring.start;for span in &ring.spans{match span{Span::Line{end}=>{poly.push([end.x,end.y]);start=*end},Span::Cubic{control_one,control_two,end}=>{let before=poly.len();flatten_cubic([start,*control_one,*control_two,*end],flat,depth,flat_remaining,&mut poly).map_err(|e|e.to_string())?;flat_remaining-=poly.len()-before;start=*end}}}polygons.push(poly);}
 let p=profile_outline(&OutlineInput{glyph_id:raw_id.clone(),source_pin:source.source_pin.clone(),upm:1000,origin:[0.0,0.0],rings:polygons,flatten_tolerance:flat},ScanPolicy{row_step,max_rows,merge_guard:kni_metrics::outline_spacing::MERGE_GUARD_UNITS,grid_anchor_y:Some(0.0)}).map_err(|e|format!("export profile: {e:?}"))?;
 let g=export_solved.glyphs.iter_mut().find(|g|&g.glyph_id==raw_id).ok_or("missing export metric")?;g.advance=g.advance.round();g.lsb=p.bounds[0];g.rsb=g.advance-g.lsb-(p.bounds[2]-p.bounds[0]);export_profiles.push(p);
 }
 let kern=kni_metrics::generated_outline_kern::generate_residual_kern(&export_solved,&export_profiles,&kni_metrics::generated_outline_kern::ExportGeometry{profile_frame:kni_metrics::generated_outline_kern::ProfileFrame::ExportedB,upm:1000,overlap_tolerance_units:0.0,drop_zero_residual:false,row_align_tolerance_units:row_step/2.0});
 let mut declared=String::from("[\n");let mut first=true;for r in kern.writer_declared_rows(){if r.written.is_none(){continue;}if !first{declared.push_str(",\n");}first=false;write!(declared,"{{\"left\":\"{}\",\"right\":\"{}\",\"requested\":{},\"written\":{},\"status\":\"{}\",\"reason\":\"\",\"evidence_class\":\"derived\"}}",names.get(&r.left).ok_or("missing left native identity")?,names.get(&r.right).ok_or("missing right native identity")?,r.requested,r.written.unwrap(),r.status).unwrap();}declared.push_str("\n]\n");
 writeln!(trace,"pairs complete={} excluded_self={} excluded_epsilon={} excluded_limit={} excluded_unmeasurable={}",solved.complete,solved.excluded_self_pairs,solved.excluded_below_epsilon,solved.excluded_pairs.len(),solved.excluded_unmeasurable).unwrap();
 let mut metrics=String::from("glyph_id\tlsb\trsb\tadvance\n");for g in &solved.glyphs{writeln!(metrics,"{}\t{}\t{}\t{}",g.glyph_id,g.lsb,g.rsb,g.advance).unwrap();}
 let mut pairs=String::from("left\tright\torigin_distance\twall_gap\toptical_cost\n");for p in &solved.pairs{writeln!(pairs,"{}\t{}\t{}\t{}\t{}",p.left,p.right,p.origin_distance,p.wall_gap,p.optical_cost).unwrap();}
 let mut bl=String::from("kind\tglyph\tvalues\n");for(gid,rings)in &baselines{bl.push_str(&ring_rows(gid,rings));}
 for(name,data)in [("declared.json",declared),("kern-receipt.txt",format!("{:?}",kern)),("spacing-excluded.txt",format!("{:?}",solved.excluded_pairs)),("outlines.tsv",geometry),("baseline-rings.tsv",bl),("identity.tsv",identity),("spacing.tsv",metrics),("pair-positions.tsv",pairs),("trace.txt",trace),("spacing-policy.txt",solved.policy_derivation),("tx-ledger.tsv",txl),("timing.tsv",timing)]{atomic_write(&stage.join(name),&data)?;}
 atomic_write(&stage.join("COMPLETE"),&format!("glyphs={} code_pin={} manifest_sha256={}\n",drawn.len(),code_pin,manifest_sha))?;
 // PUBLISH: rename stage artifacts into out; A.otf last (its presence is the completed-run gate).
 for name in ["B.otf","declared.json","kern-receipt.txt","spacing-excluded.txt","outlines.tsv","baseline-rings.tsv","identity.tsv","native-export-ledger.txt","native-identity.tsv","spacing.tsv","pair-positions.tsv","trace.txt","spacing-policy.txt","tx-ledger.tsv","timing.tsv","COMPLETE","A.otf"]{fs::rename(stage.join(name),out.join(name)).map_err(|e|format!("publish {name}: {e}"))?;}
 fs::remove_dir(&stage).map_err(|e|e.to_string())?;
 Ok(())
}
