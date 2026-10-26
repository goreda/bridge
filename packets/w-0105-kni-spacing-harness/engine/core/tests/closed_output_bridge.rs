// Synthetic byte-contract bridge only, not rendering/native quality acceptance.
use kni_core::closed_fit::{prepare_closed,ClosureAlias,RingFitInput};
use kni_core::cubic_fit::FitPolicy;
use kni_core::decision_evidence_envelope::PinClaim;
use kni_core::fitter_requirements::SourceFitRun;
use kni_core::reference_slice::{DrawnGlyph,Point};
use kni_core::svg_outline::{outline_svg,SourceViewport,FillRule};
use kni_core::cff_container::{CffGlyph,charstring,checksum};
use kni_core::native_font::{encode,NativeFontInput};
use kni_core::sfnt_metadata::{HeadMetadata,HheaMetadata,PostMetadata,Os2Metadata,NameRecord};
fn p(x:f64,y:f64)->Point{Point{x,y}}
fn pin()->PinClaim{PinClaim{algorithm:"fixture".into(),claimed_digest:"UNVERIFIED".into(),subject_ref:"rectangle".into()}}
fn rectangle(size:f64)->RingFitInput{let v=[p(0.,0.),p(size,0.),p(size,size),p(0.,size),p(0.,0.)];let runs=(0..4).map(|i|{let a=v[i];let b=v[i+1];SourceFitRun{source_pin:pin(),frame_pin:pin(),ring_index:0,span_indices:vec![2*i,2*i+1,2*i+2],points:vec![a,p((a.x+b.x)/2.,(a.y+b.y)/2.),b],start_tangent:p(b.x-a.x,b.y-a.y),end_tangent:p(a.x-b.x,a.y-b.y),tangent_binding:pin(),seam_binding:pin()}}).collect();RingFitInput{runs,closure_alias:ClosureAlias{final_source_index:8,first_source_index:0,binding:pin()}}}
fn fitted(size:f64)->DrawnGlyph{let out=prepare_closed(rectangle(size),&FitPolicy{squared_error:0.,max_refits:0});assert!(out.boundaries.is_empty());assert_eq!(out.pieces.len(),8);DrawnGlyph{glyph_id:"A".into(),rings:vec![out.closed_candidate.unwrap()]}}
fn view()->SourceViewport{SourceViewport{x:0.,y:0.,width:6.,height:6.}}
fn int_bytes(value:i16,out:&mut Vec<u8>){out.push(28);out.extend(value.to_be_bytes());}
fn native_input(outline:DrawnGlyph)->NativeFontInput{
 
 let empty=CffGlyph{name:".notdef".into(),advance:500,outline:DrawnGlyph{glyph_id:"notdef".into(),rings:vec![]}};
 let a=CffGlyph{name:"A".into(),advance:500,outline:DrawnGlyph{glyph_id:"A".into(),rings:outline.rings}};
 NativeFontInput{postscript_name:"Fixture-Regular".into(),glyphs:vec![empty,a],left_side_bearings:vec![0,0],mapping:vec![(65,1)],head:HeadMetadata{revision:0x10000,flags:0,units_per_em:1000,created:0,modified:0,bounds:[0,0,6,6],mac_style:0,lowest_ppem:1},hhea:HheaMetadata{ascender:800,descender:-200,line_gap:0,advance_max:500,min_lsb:0,min_rsb:494,max_extent:6,caret_rise:1,caret_run:0,caret_offset:0,metric_count:2},post:PostMetadata{italic_angle_fixed:0,underline_position:-100,underline_thickness:50,fixed_pitch:1,memory:[0;4]},os2:Os2Metadata{average_width:500,weight:400,width:5,embedding:2,subscript:[650,600,0,75],superscript:[650,600,0,350],strikeout:[50,300],family_class:0,panose:[0;10],unicode_ranges:[1,0,0,0],vendor:*b"TEST",selection:64,first_char:65,last_char:65,typo:[800,-200,0],win_ascent:800,win_descent:200,version:0,cap_height:0,x_height:0},names:[(1,"Fixture"),(2,"Regular"),(3,"Fixture:1"),(4,"Fixture Regular"),(5,"Version 1.0"),(6,"Fixture-Regular")].iter().map(|(id,text)|NameRecord{language:0x409,name_id:*id,value:text.to_string()}).collect()}
}
#[test]fn fitted_cubic_svg_exact_bytes(){let glyph=fitted(6.);assert_eq!(outline_svg(&glyph,view(),FillRule::EvenOdd).unwrap(),"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 6 6\"><path d=\"M0 0C1 0 2 0 3 0C4 0 5 0 6 0C6 1 6 2 6 3C6 4 6 5 6 6C5 6 4 6 3 6C2 6 1 6 0 6C0 5 0 4 0 3C0 2 0 1 0 0Z\" fill-rule=\"evenodd\"/></svg>");}
#[test]fn fitted_cubic_charstring_exact_deltas(){let glyph=CffGlyph{name:"A".into(),advance:500,outline:fitted(6.)};let mut expected=Vec::new();for n in [500,0,0]{int_bytes(n,&mut expected);}expected.push(21);for (x,y) in [(1,0),(1,0),(0,1),(0,1),(-1,0),(-1,0),(0,-1),(0,-1)]{for n in [x,y,x,y,x,y]{int_bytes(n,&mut expected);}expected.push(8);}expected.push(14);assert_eq!(charstring(&glyph).unwrap(),expected);}
#[test]fn fitted_candidate_native_directory_checksum_and_cff_payload(){let glyph=fitted(6.);let input=native_input(glyph);let cff=kni_core::cff_container::cff_one(&input.postscript_name,&input.glyphs).unwrap();let data=encode(&input).unwrap();assert_eq!(&data[..4],b"OTTO");assert_eq!(checksum(&data),0xb1b0afba);assert_eq!(u16::from_be_bytes(data[4..6].try_into().unwrap()),9);let row=&data[12..28];assert_eq!(&row[..4],b"CFF ");let offset=u32::from_be_bytes(row[8..12].try_into().unwrap())as usize;let len=u32::from_be_bytes(row[12..16].try_into().unwrap())as usize;assert_eq!(&data[offset..offset+len],cff.as_slice());assert_eq!(u32::from_be_bytes(row[4..8].try_into().unwrap()),checksum(&cff));}
#[test]fn fractional_fit_svg_preserved_native_rejects_without_rounding(){let glyph=fitted(2.);let svg=outline_svg(&glyph,view(),FillRule::EvenOdd).unwrap();assert!(svg.contains("0.3333333333333333"));let before=svg.clone();let cff=CffGlyph{name:"A".into(),advance:500,outline:glyph.clone()};assert!(charstring(&cff).is_err());assert!(encode(&native_input(glyph.clone())).is_err());assert_eq!(outline_svg(&glyph,view(),FillRule::EvenOdd).unwrap(),before);}
