// Native container integration fixture authored NOT_RUN, not parser acceptance.
use kni_core::native_font::{encode,NativeFontInput};
use kni_core::cff_container::{CffGlyph,checksum};
use kni_core::reference_slice::{DrawnGlyph,ReferenceRing,Point,Span};
use kni_core::sfnt_metadata::{HeadMetadata,HheaMetadata,PostMetadata,Os2Metadata,NameRecord};
fn input()->NativeFontInput{
 let o=Point{x:0.,y:0.};
 let empty=CffGlyph{name:".notdef".into(),advance:500,outline:DrawnGlyph{glyph_id:"notdef".into(),rings:vec![]}};
 let a=CffGlyph{name:"A".into(),advance:500,outline:DrawnGlyph{glyph_id:"A".into(),rings:vec![ReferenceRing{start:o,spans:vec![Span::Line{end:Point{x:100.,y:0.}},Span::Cubic{control_one:Point{x:100.,y:100.},control_two:Point{x:0.,y:100.},end:o}]}]}};
 NativeFontInput{postscript_name:"Fixture-Regular".into(),glyphs:vec![empty,a],left_side_bearings:vec![0,0],mapping:vec![(65,1)],head:HeadMetadata{revision:0x10000,flags:0,units_per_em:1000,created:0,modified:0,bounds:[0,0,100,75],mac_style:0,lowest_ppem:1},hhea:HheaMetadata{ascender:800,descender:-200,line_gap:0,advance_max:500,min_lsb:0,min_rsb:400,max_extent:100,caret_rise:1,caret_run:0,caret_offset:0,metric_count:2},post:PostMetadata{italic_angle_fixed:0,underline_position:-100,underline_thickness:50,fixed_pitch:1,memory:[0;4]},os2:Os2Metadata{average_width:500,weight:400,width:5,embedding:2,subscript:[650,600,0,75],superscript:[650,600,0,350],strikeout:[50,300],family_class:0,panose:[0;10],unicode_ranges:[1,0,0,0],vendor:*b"TEST",selection:64,first_char:65,last_char:65,typo:[800,-200,0],win_ascent:800,win_descent:200,version:0,cap_height:0,x_height:0},names:[(1,"Fixture"),(2,"Regular"),(3,"Fixture:1"),(4,"Fixture Regular"),(5,"Version 1.0"),(6,"Fixture-Regular")].iter().map(|(id,text)|NameRecord{language:0x409,name_id:*id,value:text.to_string()}).collect()}
}
fn word(data:&[u8])->u32{u32::from_be_bytes(data.try_into().unwrap())}
#[test]fn native_directory_and_checksum(){
 let data=encode(&input()).unwrap();assert_eq!(&data[..12],&[79,84,84,79,0,9,0,128,0,3,0,16]);assert_eq!(checksum(&data),0xb1b0afba);
 let expected=[*b"CFF ",*b"OS/2",*b"cmap",*b"head",*b"hhea",*b"hmtx",*b"maxp",*b"name",*b"post"];
 for(i,tag)in expected.iter().enumerate(){let r=&data[12+i*16..28+i*16];assert_eq!(&r[..4],tag);let offset=word(&r[8..12])as usize;let length=word(&r[12..16])as usize;assert_eq!(offset%4,0);assert!(offset+length<=data.len());let mut table=data[offset..offset+length].to_vec();if tag==b"head"{table[8..12].fill(0);}assert_eq!(word(&r[4..8]),checksum(&table));if tag==b"maxp"{assert_eq!(table,vec![0,0,0x50,0,0,2]);}if tag==b"OS/2"{assert_eq!(length,78);}if tag==b"hhea"{assert_eq!(length,36);}if tag==b"post"{assert_eq!(length,32);}}
}
#[test]fn metadata_rejections(){let mut i=input();i.head.units_per_em=2048;assert!(encode(&i).is_err());let mut i=input();i.hhea.metric_count=1;assert!(encode(&i).is_err());let mut i=input();i.left_side_bearings.pop();assert!(encode(&i).is_err());let mut i=input();i.head.bounds=[0,0,99,100];assert!(encode(&i).is_err());let mut i=input();i.mapping=vec![(65,2)];assert!(encode(&i).is_err());let mut i=input();i.os2.embedding=3;assert!(encode(&i).is_err());}
#[test]fn caller_audit_is_separate(){use kni_core::native_font::{audit,NativeAuditPolicy};use kni_core::cff_fill::{SourceFill,RingRole,FillAudit};let i=input();let policy=NativeAuditPolicy{fills:vec![SourceFill::EvenOdd,SourceFill::EvenOdd],roles:vec![vec![],vec![RingRole::FilledBoundary]],chosen_average:500,require_no_clipping:true};let result=audit(&i,&policy).unwrap();assert!(result.os2_consistent);assert!(result.per_glyph_fill[1].contains(&FillAudit::CurvedDirectionUnresolved(0)));assert!(encode(&i).is_ok());}
#[test]fn regular_bold_conflict_rejects(){let mut i=input();i.os2.selection=64|32;i.head.mac_style=1;assert!(encode(&i).is_err());}
#[test]fn unsupported_native_sibling_isolated(){use kni_core::native_font::inspect_glyphs;let mut i=input();let mut bad=i.glyphs[1].clone();bad.name="bad".into();bad.outline.glyph_id="bad".into();bad.outline.rings[0].start.x=0.1;i.glyphs.push(bad);let intake=inspect_glyphs(&i.glyphs);assert_eq!(intake.encodable_indices,vec![0,1]);assert_eq!(intake.rejected.len(),1);assert_eq!(intake.rejected[0].0,2);assert_eq!(intake.rejected[0].1,"bad");}
#[test]fn encode_with_layout_none_matches_encode(){
 use kni_core::native_font::encode_with_layout;
 assert_eq!(encode_with_layout(&input(),None).unwrap(),encode(&input()).unwrap());
}
#[test]fn encode_with_layout_binds_gpos(){
 use kni_core::native_font::encode_with_layout;
 let gpos=vec![0xde,0xad,0xbe,0xef];
 let data=encode_with_layout(&input(),Some(&gpos)).unwrap();
 assert_eq!(&data[..12],&[79,84,84,79,0,10,0,128,0,3,0,32]);
 assert_eq!(checksum(&data),0xb1b0afba);
 let expected=[*b"CFF ",*b"GPOS",*b"OS/2",*b"cmap",*b"head",*b"hhea",*b"hmtx",*b"maxp",*b"name",*b"post"];
 for(i,tag)in expected.iter().enumerate(){let r=&data[12+i*16..28+i*16];assert_eq!(&r[..4],tag);let offset=word(&r[8..12])as usize;let length=word(&r[12..16])as usize;assert_eq!(offset%4,0);assert!(offset+length<=data.len());let mut table=data[offset..offset+length].to_vec();if tag==b"head"{table[8..12].fill(0);}assert_eq!(word(&r[4..8]),checksum(&table));if tag==b"GPOS"{assert_eq!(table,gpos);}}
}
#[test]fn encode_with_layout_empty_gpos_rejected(){
 use kni_core::native_font::encode_with_layout;
 assert!(encode_with_layout(&input(),Some(&[])).is_err());
}
#[test]fn ink_bounds_not_control_hull(){
 // A's cubic from (100,0) via controls (100,100),(0,100) to (0,0) has true
 // y-extent 75; the control hull claims 100 and must be rejected. The
 // fixture's ink bounds [0,0,100,75] encode.
 let mut i=input();i.head.bounds=[0,0,100,100];assert!(encode(&i).is_err());
 assert!(encode(&input()).is_ok());
}
#[test]fn encode_boundary_guards(){
 let mut i=input();i.glyphs.swap(0,1);assert!(encode(&i).is_err()); // .notdef not first
 let mut i=input();let dup=i.glyphs[1].clone();i.glyphs.push(dup);i.left_side_bearings.push(0);i.hhea.metric_count=3;assert!(encode(&i).is_err()); // duplicate glyph name
 let mut i=input();i.mapping=vec![(65,1),(65,1)];assert!(encode(&i).is_err()); // duplicate codepoint
 let mut i=input();i.mapping=vec![(65,0)];assert!(encode(&i).is_err()); // gid 0 mapped
}
#[test]fn shared_helper_interior_extrema_and_outward_integer(){
 use kni_core::ink_bounds::integer_outward_bounds;
 use kni_core::reference_slice::{DrawnGlyph,ReferenceRing};
 // Cubic x-series [0,200,-100,0]: interior extrema beyond both endpoints.
 let g=DrawnGlyph{glyph_id:"X".into(),rings:vec![ReferenceRing{start:Point{x:0.,y:0.},spans:vec![Span::Cubic{control_one:Point{x:200.,y:0.},control_two:Point{x:-100.,y:0.},end:Point{x:0.,y:0.}}]}]};
 assert_eq!(integer_outward_bounds(&g).unwrap(),Some([-22,0,71,0]));
 // Non-integer line geometry: floor on minima, ceil on maxima.
 let g=DrawnGlyph{glyph_id:"Y".into(),rings:vec![ReferenceRing{start:Point{x:0.,y:0.},spans:vec![Span::Line{end:Point{x:10.4,y:-0.4}},Span::Line{end:Point{x:0.,y:0.}}]}]};
 assert_eq!(integer_outward_bounds(&g).unwrap(),Some([0,-1,11,0]));
}
