//! InkPlacement::TileAnchoredZeroBearing: the outline keeps its declared
//! tile-anchored coordinates (no ink-left-align shift) and the exported hmtx
//! lsb is the declared metric row's lsb. AlignToLsb keeps the status quo.
use kni_core::{reference_slice::{DrawnGlyph,Point,Span,ReferenceRing},generated_native::{prepare_generated,prepare_generated_with_placement,InkPlacement},native_font::NativeFontInput,sfnt_metadata::{HeadMetadata,HheaMetadata,PostMetadata,Os2Metadata,NameRecord}};
fn meta()->NativeFontInput{NativeFontInput{postscript_name:"KNIPlace".into(),glyphs:vec![],left_side_bearings:vec![],mapping:vec![],head:HeadMetadata{revision:0x10000,flags:0,units_per_em:1000,created:0,modified:0,bounds:[0;4],mac_style:0,lowest_ppem:1},hhea:HheaMetadata{ascender:0,descender:0,line_gap:0,advance_max:0,min_lsb:0,min_rsb:0,max_extent:0,caret_rise:1,caret_run:0,caret_offset:0,metric_count:0},post:PostMetadata{italic_angle_fixed:0,underline_position:0,underline_thickness:0,fixed_pitch:0,memory:[0;4]},os2:Os2Metadata{average_width:0,weight:400,width:5,embedding:0,subscript:[0;4],superscript:[0;4],strikeout:[0;2],family_class:0,panose:[0;10],unicode_ranges:[0;4],vendor:*b"KNI ",selection:64,first_char:0,last_char:0,typo:[0;3],win_ascent:0,win_descent:0,version:0,cap_height:0,x_height:0},names:[(1u16,"KNIPlace"),(2,"Regular"),(3,"KNIPlace"),(4,"KNIPlace"),(5,"Version 1.0"),(6,"KNIPlace")].into_iter().map(|(id,v)|NameRecord{language:0x409,name_id:id,value:v.into()}).collect()}}
fn glyph()->DrawnGlyph{DrawnGlyph{glyph_id:"g".into(),rings:vec![ReferenceRing{start:Point{x:10.0,y:-20.0},spans:vec![Span::Line{end:Point{x:30.0,y:-20.0}},Span::Line{end:Point{x:30.0,y:-60.0}},Span::Line{end:Point{x:10.0,y:-60.0}},Span::Line{end:Point{x:10.0,y:-20.0}}]}]}}
fn xs(g:&DrawnGlyph)->Vec<f64>{let mut o=vec![g.rings[0].start.x];for s in &g.rings[0].spans{match s{Span::Line{end}=>o.push(end.x),Span::Cubic{end,..}=>o.push(end.x)}}o}
#[test] fn tile_anchored_keeps_coordinates_and_zero_lsb(){
 let p=prepare_generated_with_placement(&[glyph()],&[(65u32,1u16)],&[("g".into(),0.0,0.0,696.0)],&meta(),InkPlacement::TileAnchoredZeroBearing).expect("prepare anchored");
 assert_eq!(xs(&p.glyphs[0].outline),vec![10.0,30.0,30.0,10.0,10.0],"no shift: interior margin is anatomy");
 assert_eq!(p.left_side_bearings,vec![0],"hmtx lsb is the declared row's lsb (0)");
 assert_eq!(p.glyphs[0].advance,696);
}
#[test] fn align_to_lsb_is_the_unchanged_status_quo(){
 let p=prepare_generated(&[glyph()],&[(66u32,1u16)],&[("g".into(),0.0,0.0,696.0)],&meta()).expect("prepare default");
 assert_eq!(xs(&p.glyphs[0].outline),vec![0.0,20.0,20.0,0.0,0.0],"status quo: ink left-aligned to lsb");
 let p2=prepare_generated_with_placement(&[glyph()],&[(67u32,1u16)],&[("g".into(),0.0,0.0,696.0)],&meta(),InkPlacement::AlignToLsb).expect("prepare explicit");
 assert_eq!(xs(&p2.glyphs[0].outline),vec![0.0,20.0,20.0,0.0,0.0]);
}
