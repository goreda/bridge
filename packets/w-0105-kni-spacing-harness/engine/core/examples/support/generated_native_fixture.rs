//! Diagnostic scratch caller, not source font identity or original spacing.
use kni_core::{reference_slice::DrawnGlyph,native_font::NativeFontInput,sfnt_metadata::{HeadMetadata,HheaMetadata,PostMetadata,Os2Metadata,NameRecord},generated_native::{encode_generated,prepare_generated,rounding_ledger}};
use kni_metrics::self_anchored_spacing::SpacingSolution;
use std::{path::Path,fs,collections::{BTreeMap,BTreeSet}};
#[derive(Clone,Debug)]pub struct ExportIdentity{pub raw_to_cff:Vec<(String,String)>,pub exported_b:Vec<DrawnGlyph>,pub b_ledger:Vec<kni_core::generated_native::RoundingLedger>}
fn metadata()->NativeFontInput{
 let family="KNI Generated Geometry Test";
 NativeFontInput{postscript_name:"KNIGeneratedGeometryTest".into(),glyphs:vec![],left_side_bearings:vec![],mapping:vec![],head:HeadMetadata{revision:0x10000,flags:0,units_per_em:1000,created:0,modified:0,bounds:[0;4],mac_style:0,lowest_ppem:1},hhea:HheaMetadata{ascender:0,descender:0,line_gap:0,advance_max:0,min_lsb:0,min_rsb:0,max_extent:0,caret_rise:1,caret_run:0,caret_offset:0,metric_count:0},post:PostMetadata{italic_angle_fixed:0,underline_position:0,underline_thickness:0,fixed_pitch:0,memory:[0;4]},os2:Os2Metadata{average_width:0,weight:400,width:5,embedding:0,subscript:[0;4],superscript:[0;4],strikeout:[0;2],family_class:0,panose:[0;10],unicode_ranges:[0;4],vendor:*b"KNI ",selection:64,first_char:0,last_char:0,typo:[0;3],win_ascent:0,win_descent:0,version:0,cap_height:0,x_height:0},names:vec![(1,family),(2,"Diagnostic"),(3,"KNI Generated Geometry Test Diagnostic"),(4,family),(5,"Version 1.0 Diagnostic"),(6,"KNIGeneratedGeometryTest")].into_iter().map(|(id,v)|NameRecord{language:0x409,name_id:id,value:v.into()}).collect()}
}
fn clip_metadata(mut m:NativeFontInput)->NativeFontInput{m.hhea.ascender=m.head.bounds[3];m.hhea.descender=m.head.bounds[1];m.os2.typo=[m.hhea.ascender,m.hhea.descender,0];m.os2.win_ascent=m.head.bounds[3].max(0) as u16;m.os2.win_descent=(-(m.head.bounds[1] as i32)).max(0) as u16;m}
/// Writes A/B into an existing output directory, refuses existing destination
/// files. A is a zero-sided diagnostic baseline, never original spacing.
pub fn export_fixture(drawn:&[DrawnGlyph],solved:&SpacingSolution,codepoints:&[(String,u32)],out:&Path)->Result<ExportIdentity,String>{
 if drawn.is_empty(){return Err("no generated geometry".into())}
 let mut ids=BTreeSet::new();let mut raw_to_cff=Vec::new();let mut glyphs=vec![DrawnGlyph{glyph_id:".notdef".into(),rings:vec![]}];
 for (i,g) in drawn.iter().enumerate(){if !ids.insert(g.glyph_id.clone()){return Err("duplicate raw glyph id".into())}let name=format!("g{:05}",i+1);let mut copy=g.clone();copy.glyph_id=name.clone();glyphs.push(copy);raw_to_cff.push((g.glyph_id.clone(),name));}
 let gid:BTreeMap<_,_>=raw_to_cff.iter().enumerate().map(|(i,(raw,_))|(raw.as_str(),(i+1) as u16)).collect();if glyphs.len()>u16::MAX as usize{return Err("glyph count exceeds native range".into())}
 let mut seen_cp=BTreeSet::new();let mut mapping=Vec::new();for(raw,cp)in codepoints{if char::from_u32(*cp).is_none()||!seen_cp.insert(*cp){return Err("invalid/duplicate codepoint".into())}mapping.push((*cp,*gid.get(raw.as_str()).ok_or("codepoint has no raw glyph")?));}
 if mapping.is_empty(){return Err("empty codepoint mapping".into())}
 let mut rows=BTreeMap::new();for g in &solved.glyphs{if rows.insert(g.glyph_id.as_str(),(g.lsb,g.rsb,g.advance)).is_some(){return Err("duplicate solved glyph".into())}}
 if rows.len()!=drawn.len()||rows.keys().any(|k|!gid.contains_key(k)){return Err("solved glyph membership mismatch".into())}
 let mut bmetrics=vec![(".notdef".into(),0.,0.,0.)];let mut ametrics=bmetrics.clone();
 for(raw,name)in &raw_to_cff{let &(l,r,a)=rows.get(raw.as_str()).ok_or("missing solved glyph")?;bmetrics.push((name.clone(),l,r,a));ametrics.push((name.clone(),0.,0.,a));}
 let mut m=metadata();let mut cps:Vec<_>=mapping.iter().map(|r|r.0).collect();cps.sort();m.os2.first_char=cps[0].min(65535) as u16;m.os2.last_char=(*cps.last().unwrap()).min(65535) as u16;
 let bp=prepare_generated(&glyphs,&mapping,&bmetrics,&m).map_err(|e|format!("B prepare: {e:?}"))?;
 // Quantize ONCE via B, then translate by integer control-hull xmin for A.
 // This preserves every exported relative point exactly, without a second
 // fractional shift/rounding. A has zero sides in the control-hull contract.
 let mut ap=bp.clone();ap.hhea.min_lsb=0;ap.hhea.min_rsb=0;ap.hhea.max_extent=0;ap.hhea.advance_max=0;let mut all=None::<[i16;4]>;let mut amin=None::<i16>;
 for (g,l) in ap.glyphs.iter_mut().zip(&mut ap.left_side_bearings){
  let mut xs=Vec::new();for ring in &g.outline.rings{xs.push(ring.start.x);for span in &ring.spans{match span{kni_core::reference_slice::Span::Line{end}=>xs.push(end.x),kni_core::reference_slice::Span::Cubic{control_one,control_two,end}=>xs.extend([control_one.x,control_two.x,end.x])}}}
  let xmin=xs.iter().copied().fold(f64::INFINITY,f64::min);let xmax=xs.iter().copied().fold(f64::NEG_INFINITY,f64::max);
  let ink=kni_core::generated_native::ink_min_x(&g.outline).map_err(|e|format!("A ink: {e:?}"))?;let shift=ink.map_or(0.0,|x|(-x).round());let actual_lsb=ink.map_or(0.0,|x|x+shift).round();
  let width=if xs.is_empty(){0}else{u16::try_from((xmax-xmin) as i32).map_err(|_|"A width range")?};
  let advance=width as i32+actual_lsb as i32;if advance<0||advance>32767{return Err("A extent range".into())}g.advance=advance as u16;*l=actual_lsb as i16;ap.hhea.advance_max=ap.hhea.advance_max.max(g.advance);ap.hhea.max_extent=ap.hhea.max_extent.max(advance as i16);if !xs.is_empty(){amin=Some(amin.map_or(*l,|v|v.min(*l)));}
  let mut include=|p:&mut kni_core::reference_slice::Point|{p.x+=shift;let(x,y)=(p.x as i16,p.y as i16);all=Some(match all{None=>[x,y,x,y],Some(v)=>[v[0].min(x),v[1].min(y),v[2].max(x),v[3].max(y)]});};
  for ring in &mut g.outline.rings{include(&mut ring.start);for span in &mut ring.spans{match span{kni_core::reference_slice::Span::Line{end}=>include(end),kni_core::reference_slice::Span::Cubic{control_one,control_two,end}=>{include(control_one);include(control_two);include(end)}}}}
 }
 ap.head.bounds=all.unwrap_or([0;4]);ap.hhea.min_lsb=amin.unwrap_or(0);
 let a=kni_core::native_font::encode(&clip_metadata(ap.clone())).map_err(|e|format!("A encode: {e:?}"))?;let b=encode_generated(&glyphs,&mapping,&bmetrics,&clip_metadata(bp.clone())).map_err(|e|format!("B encode: {e:?}"))?;
 let mut id=String::from("raw_id\tcff_name\tgid\n");for(i,(raw,name))in raw_to_cff.iter().enumerate(){if raw.chars().any(|c|c=='\t'||c=='\n'||c=='\r'){return Err("raw id contains delimiter".into())}id.push_str(&format!("{raw}\t{name}\t{}\n",i+1));}
 let b_ledger=rounding_ledger(&glyphs,&bmetrics,&bp).map_err(|e|format!("{e:?}"))?;let ledger=format!("A: zero-sided control-hull diagnostic baseline, rounded true-ink xmin integer translation of once-quantized B geometry, no original spacing claim\nB: generated lsb/advance, exported RSB derived from control hull; ledger input ink xmin fields are GENERAL analytic values (not necessarily quantized; cubic extrema of integer control points can be fractional) - authoritative TX is the pointwise exact shift in tx-ledger.tsv\nA {:?}\nB {:?}\n",rounding_ledger(&glyphs,&ametrics,&ap).map_err(|e|format!("{e:?}"))?,b_ledger);
 fs::create_dir_all(out).map_err(|e|e.to_string())?;let a_path=out.join("A.otf");let b_path=out.join("B.otf");for p in [&a_path,&b_path,&out.join("native-identity.tsv"),&out.join("native-export-ledger.txt")]{if p.exists(){return Err("native export destination exists".into())}}
 fs::write(&a_path,a).map_err(|e|e.to_string())?;fs::write(&b_path,b).map_err(|e|e.to_string())?;fs::write(out.join("native-identity.tsv"),id).map_err(|e|e.to_string())?;fs::write(out.join("native-export-ledger.txt"),ledger).map_err(|e|e.to_string())?;
 Ok(ExportIdentity{raw_to_cff,exported_b:bp.glyphs.iter().map(|g|g.outline.clone()).collect(),b_ledger})
}
