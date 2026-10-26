//! Generated-outline spacing entry point. All numeric policy is explicit.
use kni_core::{capture::capture_gray,capture_dispatch::decode_source,jpeg_source::Limits,cubic_fit::FitPolicy,reference_slice::{Point,Span,DrawnGlyph}};
use kni_metrics::{outline_spacing::{OutlineInput,ScanPolicy,profile_outline},self_anchored_spacing::{SpacingPolicy,FontContext,solve_spacing}};
use std::{fs,path::PathBuf,fmt::Write as _};
#[path="support/cubic_flatten.rs"] mod cubic_flatten;
use cubic_flatten::flatten_cubic;
#[path="support/generated_native_fixture.rs"] mod generated_native_fixture;
fn scalar(s:&str)->Result<f64,String>{let v:f64=s.parse().map_err(|_|format!("bad scalar {s}"))?;if !v.is_finite()||v<=0.0{return Err("policy values must be finite and positive".into())}Ok(v)}
fn main()->Result<(),String>{
 let a:Vec<String>=std::env::args().collect();
 if a.len()!=17{return Err("usage: generated_outline_spacing MANIFEST OUTPUT_DIR SCALE RDP_EPS FIT_SE REFITS ROW_STEP FLATTEN_TOL MAX_ROWS MAX_PAIR_EVALS MAX_PAIRS MAX_JPEG_BYTES MAX_PIXELS MAX_WORKING_BYTES FLATTEN_DEPTH MAX_FLATTEN_POINTS".into())}
 // MANIFEST columns: glyph_id, codepoint_hex, path, source_pin. One font/style.
 let out=PathBuf::from(&a[2]);if out.exists(){return Err("output already exists".into())}
 let(scale,eps,se,row_step,flat)=(scalar(&a[3])?,scalar(&a[4])?,scalar(&a[5])?,scalar(&a[7])?,scalar(&a[8])?);
 let refits:usize=a[6].parse().map_err(|_|"bad refits")?;let max_rows:usize=a[9].parse().map_err(|_|"bad max_rows")?;
 let max_pairs_eval:u64=a[10].parse().map_err(|_|"bad pair bound")?;let max_pairs:usize=a[11].parse().map_err(|_|"bad pair count")?;
 let max_bytes:usize=a[12].parse().map_err(|_|"bad byte bound")?;
 let max_pixels:usize=a[13].parse().map_err(|_|"bad pixel bound")?;let working:usize=a[14].parse().map_err(|_|"bad working bound")?;let depth:usize=a[15].parse().map_err(|_|"bad flatten depth")?;
 let mut flat_remaining:usize=a[16].parse().map_err(|_|"bad flatten point bound")?;
 let raw=fs::read_to_string(&a[1]).map_err(|e|e.to_string())?;let mut lines=raw.lines();
 if lines.next()!=Some("glyph_id\tcodepoint_hex\tpath\tsource_pin"){return Err("manifest header mismatch".into())}
 let mut codepoints=Vec::new();let mut profiles=Vec::new();let mut drawn=Vec::<DrawnGlyph>::new();let mut geometry=String::from("kind\tglyph\tvalues\n");let mut identity=String::from("glyph_id\tcodepoint_hex\tsource_pin\n");let mut trace=String::new();let mut ids=std::collections::BTreeSet::new();let mut cps=std::collections::BTreeSet::new();
 for line in lines {let v:Vec<_>=line.split('\t').collect();if v.len()!=4||v.iter().any(|s|s.is_empty())||!v[0].bytes().all(|b|b.is_ascii_alphanumeric()||b"._-".contains(&b))||!ids.insert(v[0].to_string()){return Err("bad or duplicate identity".into())}
  let cp=u32::from_str_radix(v[1].trim_start_matches("U+"),16).map_err(|_|"bad codepoint")?;if char::from_u32(cp).is_none()||!cps.insert(cp){return Err("invalid unicode".into())}
  codepoints.push((v[0].to_string(),cp));
  let bytes=fs::read(v[2]).map_err(|e|e.to_string())?;if v[3].len()!=64||!v[3].bytes().all(|b|b.is_ascii_hexdigit()&&!b.is_ascii_uppercase())||kni_core::economy_eval::sha256_hex(&bytes)!=v[3]{return Err(format!("source pin mismatch {}",v[0]));}
  let decoded=decode_source(&bytes,&kni_core::capture::DecodeLimits{max_input_bytes:max_bytes,max_pixels:max_pixels,max_working_bytes:working},Limits{max_input_bytes:max_bytes,max_pixels,max_working_bytes:working}).map_err(|e|format!("decode {}: {:?}",v[0],e))?;
  let captured=capture_gray(decoded.width,decoded.height,&decoded.gray,eps)?;
  let drawing=kni_core::generated_draw::fit_from_source(&captured,&decoded.gray,scale,&FitPolicy{squared_error:se,max_refits:refits})?;
  writeln!(trace,"drawing {} baseline_area={} final_area={} reports={:?} refused={:?}",v[0],drawing.baseline_area,drawing.final_area,drawing.reports,drawing.refused).unwrap();
  let (mut rings,spans,fb,dropped)=(drawing.rings,drawing.source_fit_spans,drawing.fallback,drawing.dropped);
  // Restore the shared source y frame after local source-quality checks.
  // Inputs must share their canvas coordinate system; no font baseline is inferred.
  let shift=Point{x:0.0,y:captured.origin_y*scale};
  let translate=|p:&mut Point|{p.x+=shift.x;p.y+=shift.y;};
  for ring in &mut rings {translate(&mut ring.start);for span in &mut ring.spans {match span {Span::Line{end}=>translate(end),Span::Cubic{control_one,control_two,end}=>{translate(control_one);translate(control_two);translate(end);}}}}

  let mut polygons=Vec::new();
  for r in &rings {let mut poly=vec![[r.start.x,r.start.y]];let mut start=r.start;writeln!(geometry,"R\t{}\t{},{}",v[0],start.x,start.y).unwrap();
   for span in &r.spans {match span {
    Span::Line{end}=>{poly.push([end.x,end.y]);writeln!(geometry,"L\t{}\t{},{}",v[0],end.x,end.y).unwrap();start=*end},
    Span::Cubic{control_one,control_two,end}=>{let before=poly.len();flatten_cubic([start,*control_one,*control_two,*end],flat,depth,flat_remaining,&mut poly).map_err(|e|e.to_string())?;flat_remaining-=poly.len()-before;writeln!(geometry,"C\t{}\t{},{},{},{},{},{}",v[0],control_one.x,control_one.y,control_two.x,control_two.y,end.x,end.y).unwrap();start=*end}
   }}polygons.push(poly);
  }
  let profile=profile_outline(&OutlineInput{glyph_id:v[0].into(),source_pin:v[3].into(),upm:1000,origin:[0.0,0.0],rings:polygons,flatten_tolerance:flat},ScanPolicy{row_step,max_rows,merge_guard:kni_metrics::outline_spacing::MERGE_GUARD_UNITS,grid_anchor_y:Some(0.0)}).map_err(|e|format!("profile {}: {:?}",v[0],e))?;
  writeln!(identity,"{}\t{}\t{}",v[0],v[1],v[3]).unwrap();writeln!(trace,"{} spans={} fallback={} dropped={} source={:?} capture_origin=({}, {}) scale={} profile_frame=x_local_y_source_shared_canvas",v[0],spans,fb,dropped,decoded.receipt,captured.origin_x,captured.origin_y,scale).unwrap();profiles.push(profile);drawn.push(DrawnGlyph{glyph_id:v[0].into(),rings});
 }
 let policy=SpacingPolicy{sample_resolution:row_step,max_pair_evaluations:max_pairs_eval,max_pairs,pair_min_shared_rows:1,lambda:Some(0.0),dcap:None, contrast_floor:false,cadence_class_pass:false,class_channel_targets:false};
 let context=FontContext{glyph_codepoints:codepoints.clone(),..FontContext::default()};
 let solved=solve_spacing(&profiles,Some(&context),&policy).map_err(|e|format!("spacing: {:?}",e))?;
 fs::create_dir(&out).map_err(|e|e.to_string())?;
 let native=generated_native_fixture::export_fixture(&drawn,&solved,&codepoints,&out)?;
 writeln!(trace,"b_ledger_rows={}",native.b_ledger.len()).unwrap();
 let names:std::collections::BTreeMap<_,_>=native.raw_to_cff.iter().cloned().collect();
 let reverse:std::collections::BTreeMap<_,_>=native.raw_to_cff.iter().map(|(raw,cff)|(cff.clone(),raw.clone())).collect();
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
 for(name,data)in [("declared.json",declared),("kern-receipt.txt",format!("{:?}",kern)),("spacing-excluded.txt",format!("{:?}",solved.excluded_pairs)),("outlines.tsv",geometry),("identity.tsv",identity),("spacing.tsv",metrics),("pair-positions.tsv",pairs),("trace.txt",trace),("spacing-policy.txt",solved.policy_derivation)]{fs::write(out.join(name),data).map_err(|e|e.to_string())?;}
 Ok(())
}
