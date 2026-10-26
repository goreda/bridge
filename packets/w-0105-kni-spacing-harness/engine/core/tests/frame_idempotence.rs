//! Half-case rounding tests for the native integer export grid (positive AND negative .5).
//! Rust f64::round is half-away-from-zero: 0.5->1, -0.5->-1. Export must not drift from that.
use kni_core::{reference_slice::{DrawnGlyph,Point,Span,ReferenceRing},generated_native::prepare_generated,native_font::NativeFontInput,sfnt_metadata::{HeadMetadata,HheaMetadata,PostMetadata,Os2Metadata,NameRecord}};
fn meta()->NativeFontInput{NativeFontInput{postscript_name:"KNIHalfCase".into(),glyphs:vec![],left_side_bearings:vec![],mapping:vec![],head:HeadMetadata{revision:0x10000,flags:0,units_per_em:1000,created:0,modified:0,bounds:[0;4],mac_style:0,lowest_ppem:1},hhea:HheaMetadata{ascender:0,descender:0,line_gap:0,advance_max:0,min_lsb:0,min_rsb:0,max_extent:0,caret_rise:1,caret_run:0,caret_offset:0,metric_count:0},post:PostMetadata{italic_angle_fixed:0,underline_position:0,underline_thickness:0,fixed_pitch:0,memory:[0;4]},os2:Os2Metadata{average_width:0,weight:400,width:5,embedding:0,subscript:[0;4],superscript:[0;4],strikeout:[0;2],family_class:0,panose:[0;10],unicode_ranges:[0;4],vendor:*b"KNI ",selection:64,first_char:0,last_char:0,typo:[0;3],win_ascent:0,win_descent:0,version:0,cap_height:0,x_height:0},names:[(1u16,"KNIHalfCase"),(2,"Diagnostic"),(3,"KNI Half Case Diagnostic"),(4,"KNIHalfCase"),(5,"Version 1.0"),(6,"KNIHalfCase")].into_iter().map(|(id,v)|NameRecord{language:0x409,name_id:id,value:v.into()}).collect()}}
fn tri(dx:f64,dy:f64)->DrawnGlyph{DrawnGlyph{glyph_id:"g".into(),rings:vec![ReferenceRing{start:Point{x:10.5+dx,y:-20.5+dy},spans:vec![Span::Line{end:Point{x:30.5+dx,y:-20.5+dy}},Span::Line{end:Point{x:30.5+dx,y:-60.5+dy}},Span::Line{end:Point{x:10.5+dx,y:-60.5+dy}},Span::Line{end:Point{x:10.5+dx,y:-20.5+dy}}]}]}}
fn points(g:&DrawnGlyph)->Vec<(f64,f64)>{let mut o=Vec::new();for r in &g.rings{o.push((r.start.x,r.start.y));for s in &r.spans{match s{Span::Line{end}=>o.push((end.x,end.y)),Span::Cubic{control_one:a,control_two:b,end}=>{o.push((a.x,a.y));o.push((b.x,b.y));o.push((end.x,end.y))}}}}o}
#[test] fn half_cases_round_away_from_zero(){
 let m=meta();
 // positive halves: 10.5 -> 11 (after xmin translate of 11-11=0 shift? lsb=11 -> shift=(11-11)=0)
 let g=tri(0.0,0.0);
 let p=prepare_generated(&[g],&[(65u32,1u16)],&[("g".into(),11.0,0.0,30.0)],&m).expect("prepare positive");
 let pts=points(&p.glyphs[0].outline);
 assert!(pts.contains(&(11.0,-21.0))&&pts.contains(&(31.0,-61.0)),"positive halves: {pts:?}");
 // negative halves: -20.5 -> -21
 assert!(pts.iter().all(|&(_,y)|y==y.round()&&y<=-21.0),"negative halves: {pts:?}");
 // shifted negative-half variant: dx=-1 gives 9.5 -> 10, dy=-1 gives -21.5 -> -22
 let g2=tri(-1.0,-1.0);
 let p2=prepare_generated(&[g2],&[(66u32,1u16)],&[("g".into(),10.0,0.0,30.0)],&m).expect("prepare negative variant");
 let pts2=points(&p2.glyphs[0].outline);
 assert!(pts2.contains(&(10.0,-22.0))&&pts2.contains(&(30.0,-62.0)),"negative halves variant: {pts2:?}");
}
#[test] fn fractional_analytic_ink_xmin_is_valid(){
 // cubic P0=(2,0) P1=(0,0) P2=(0,0) P3=(2,0): x(t)=2-6t+6t^2, extremum t=0.5 -> xmin=0.5 FRACTIONAL with integer controls.
 // Regression guard: analytic ink xmin must NOT be asserted integer (chief ruling: g=1 special case cannot be generalized).
 let ring=ReferenceRing{start:Point{x:2.0,y:0.0},spans:vec![Span::Cubic{control_one:Point{x:0.0,y:0.0},control_two:Point{x:0.0,y:0.0},end:Point{x:2.0,y:0.0}}]};
 let g=DrawnGlyph{glyph_id:"frac".into(),rings:vec![ring]};
 let xmin=kni_core::generated_native::ink_min_x(&g).expect("ink_min_x").expect("non-empty");
 assert_eq!(xmin,0.5,"fractional analytic xmin expected, got {xmin}");
 // prepare must still emit integer translated geometry with shift=(lsb-xmin).round()
 let p=prepare_generated(&[g],&[(67u32,1u16)],&[("frac".into(),1.0,0.0,30.0)],&meta()).expect("prepare fractional xmin");
 let pts=points(&p.glyphs[0].outline);
 assert!(pts.iter().all(|&(x,y)|x==x.round()&&y==y.round()),"exported points must be integer: {pts:?}");
}
