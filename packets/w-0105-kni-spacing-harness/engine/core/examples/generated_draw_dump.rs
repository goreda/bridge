//! Baseline/refined raw-ring diagnostic dump (baş mimar approved, receipt-only, fitter untouched).
//! Mirrors generated_outline_spacing fit path exactly (same decode/capture/fit/Y-restore),
//! persists per glyph: source_pin, origin, scale, all params, baseline rings, refined rings.
use kni_core::{capture::capture_gray,capture_dispatch::decode_source,jpeg_source::Limits,cubic_fit::FitPolicy,generated_draw::fit_from_source,reference_slice::{Point,Span,ReferenceRing},lever_api::{count_nodes,missing_extrema}};
use std::fmt::Write as _;
fn rings_json(rings:&[ReferenceRing])->String{let mut s=String::from("[");for(i,r)in rings.iter().enumerate(){if i>0{s.push(',')}write!(s,"{{\"start\":[{},{}],\"spans\":[",r.start.x,r.start.y).unwrap();for(j,p)in r.spans.iter().enumerate(){if j>0{s.push(',')}match p{Span::Line{end}=>write!(s,"{{\"kind\":\"L\",\"end\":[{},{}]}}",end.x,end.y).unwrap(),Span::Cubic{control_one:a,control_two:b,end}=>write!(s,"{{\"kind\":\"C\",\"c1\":[{},{}],\"c2\":[{},{}],\"end\":[{},{}]}}",a.x,a.y,b.x,b.y,end.x,end.y).unwrap()}}s.push_str("]}")}s.push(']');s}
fn yrestore(rings:&mut [ReferenceRing],dy:f64){for r in rings{let t=|p:&mut Point|p.y+=dy;t(&mut r.start);for s in &mut r.spans{match s{Span::Line{end}=>t(end),Span::Cubic{control_one:a,control_two:b,end}=>{t(a);t(b);t(end)}}}}}
fn main()->Result<(),String>{
 let a:Vec<String>=std::env::args().collect();
 if a.len()!=12{return Err("usage: generated_draw_dump MANIFEST OUTPUT_DIR SCALE EPS SE REFITS ROW_STEP FLATTEN_TOL MAX_BYTES MAX_PIXELS MAX_WORKING_BYTES".into())}
 let out=std::path::PathBuf::from(&a[2]);if out.exists(){return Err("output already exists".into())}
 std::fs::create_dir(&out).map_err(|e|e.to_string())?;
 let num=|i:usize|a[i].parse::<f64>().map_err(|_|format!("bad scalar {i}"));
 let scale=num(3)?;let eps=num(4)?;let se=num(5)?;
 let refits:usize=a[6].parse().map_err(|_|"bad refits")?;
 let row_step=num(7)?;let flat=num(8)?;
 let n=|i:usize|a[i].parse::<usize>().map_err(|_|format!("bad bound {i}"));
 let bytes_lim=n(9)?;let pix_lim=n(10)?;let work_lim=n(11)?;
 let raw=std::fs::read_to_string(&a[1]).map_err(|e|e.to_string())?;let mut lines=raw.lines();
 if lines.next()!=Some("glyph_id\tcodepoint_hex\tpath\tsource_pin"){return Err("manifest header mismatch".into())}
 let mut manifest=String::from("glyph_id\tsource_pin\tjson\n");
 for line in lines{let v:Vec<_>=line.split('\t').collect();if v.len()!=4{return Err("bad manifest row".into())}
  let bytes=std::fs::read(v[2]).map_err(|e|e.to_string())?;
  if kni_core::economy_eval::sha256_hex(&bytes)!=v[3]{return Err(format!("source pin mismatch {}",v[0]))}
  let d=decode_source(&bytes,&kni_core::capture::DecodeLimits{max_input_bytes:bytes_lim,max_pixels:pix_lim,max_working_bytes:work_lim},Limits{max_input_bytes:bytes_lim,max_pixels:pix_lim,max_working_bytes:work_lim}).map_err(|e|format!("decode {}: {:?}",v[0],e))?;
  let cap=capture_gray(d.width,d.height,&d.gray,eps)?;
  let g=fit_from_source(&cap,&d.gray,scale,&FitPolicy{squared_error:se,max_refits:refits})?;
  let dy=cap.origin_y*scale;
  let mut baseline=g.baseline.clone();let mut refined=g.rings.clone();
  yrestore(&mut baseline,dy);yrestore(&mut refined,dy);
  let mut j=String::new();
  write!(j,"{{\"glyph_id\":\"{}\",\"source_pin\":\"{}\",\"frame\":\"x_local_y_source_shared_canvas\",\"label\":\"source_tile_y_up, common baseline NOT explicitly calibrated\",\"origin_x\":{},\"origin_y\":{},\"scale\":{},\"params\":{{\"rdp_eps\":{},\"fit_se\":{},\"refits\":{},\"row_step\":{},\"flatten_tol\":{}}},\"source\":{{\"width\":{},\"height\":{}}},\"baseline_area\":{},\"final_area\":{},\"baseline_nodes\":{},\"refined_nodes\":{},\"baseline_missing_extrema\":{},\"refined_missing_extrema\":{},\"fallback\":{},\"dropped\":{},\"baseline_rings\":{},\"refined_rings\":{}}}",
   v[0],v[3],cap.origin_x,cap.origin_y,scale,eps,se,refits,row_step,flat,d.width,d.height,g.baseline_area,g.final_area,count_nodes(&g.baseline),count_nodes(&g.rings),missing_extrema(&g.baseline),missing_extrema(&g.rings),g.fallback,g.dropped,rings_json(&baseline),rings_json(&refined)).unwrap();
  let name=format!("{}.json",v[0]);
  std::fs::write(out.join(&name),&j).map_err(|e|e.to_string())?;
  std::fs::write(out.join(format!("{}.receipt.txt",v[0])),format!("source_receipt={:?}\nreports={:?}\nrefused={:?}\n",d.receipt,g.reports,g.refused)).map_err(|e|e.to_string())?;
  writeln!(manifest,"{}\t{}\t{}",v[0],v[3],name).unwrap();
 }
 std::fs::write(out.join("manifest.tsv"),manifest).map_err(|e|e.to_string())?;
 Ok(())
}
