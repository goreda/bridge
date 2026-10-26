// Format fixtures authored NOT_RUN, not valid-font or parser acceptance.
use kni_core::cff_container::{charstring,CffGlyph,maxp_cff,hmtx,checksum};
use kni_core::reference_slice::{DrawnGlyph,ReferenceRing,Point,Span};
#[test]fn scalar_table_bytes(){assert_eq!(maxp_cff(2),vec![0,0,0x50,0,0,2]);assert_eq!(hmtx(&[(500,-20)]),vec![1,244,255,236]);assert_eq!(checksum(&[1,2,3]),0x01020300);}
#[test]fn closed_line_type2_bytes(){let origin=Point{x:0.,y:0.};let g=CffGlyph{name:String::from(".notdef"),advance:500,outline:DrawnGlyph{glyph_id:String::from("fixture"),rings:vec![ReferenceRing{start:origin,spans:vec![Span::Line{end:Point{x:10.,y:0.}},Span::Line{end:origin}]}]}};assert_eq!(charstring(&g).unwrap(),vec![28,1,244,28,0,0,28,0,0,21,28,0,10,28,0,0,5,28,255,246,28,0,0,5,14]);}
#[test]fn unsupported_coordinates_reject(){let origin=Point{x:0.,y:0.};for x in [0.1,f64::NAN,f64::INFINITY,32768.,-32769.] {let g=CffGlyph{name:String::from("A"),advance:500,outline:DrawnGlyph{glyph_id:String::from("A"),rings:vec![ReferenceRing{start:origin,spans:vec![Span::Line{end:Point{x,y:0.}},Span::Line{end:origin}]}]}};assert!(charstring(&g).is_err());}}
#[test]fn open_contour_reject(){let origin=Point{x:0.,y:0.};let g=CffGlyph{name:String::from("A"),advance:500,outline:DrawnGlyph{glyph_id:String::from("A"),rings:vec![ReferenceRing{start:origin,spans:vec![Span::Line{end:Point{x:1.,y:0.}}]}]}};assert!(charstring(&g).is_err());}
#[test]fn cubic_type2_exact(){let origin=Point{x:0.,y:0.};let g=CffGlyph{name:String::from("A"),advance:0,outline:DrawnGlyph{glyph_id:String::from("A"),rings:vec![ReferenceRing{start:origin,spans:vec![Span::Cubic{control_one:Point{x:10.,y:20.},control_two:Point{x:30.,y:40.},end:origin}]}]}};assert_eq!(charstring(&g).unwrap(),vec![28,0,0,28,0,0,28,0,0,21,28,0,10,28,0,20,28,0,20,28,0,20,28,255,226,28,255,216,8,14]);}
#[test]fn cff_one_empty_notdef_exact(){use kni_core::cff_container::cff_one;let glyph=CffGlyph{name:".notdef".into(),advance:500,outline:DrawnGlyph{glyph_id:"notdef".into(),rings:vec![]}};let expected=vec![
 1,0,4,4, // header
 0,1,4,0,0,0,1,0,0,0,2,78, // Name INDEX N
 0,1,4,0,0,0,1,0,0,0,40, // Top DICT INDEX length39
 141,12,6, // Type2
 28,0,0,28,0,0,28,0,0,28,0,0,5, // BBox
 29,0,0,0,70,15,29,0,0,0,71,17, // charset/CharStrings
 29,0,0,0,0,29,0,0,0,86,18, // empty Private DICT
 0,0,0,0, // String and GlobalSubr empty INDEX
 0, // charset format0, .notdef only
 0,1,4,0,0,0,1,0,0,0,5,28,1,244,14 // CharStrings INDEX
 ];assert_eq!(cff_one("N",&[glyph]).unwrap(),expected);}
#[test]fn cff_names_reject_duplicate(){use kni_core::cff_container::cff_one;let glyph=CffGlyph{name:".notdef".into(),advance:0,outline:DrawnGlyph{glyph_id:"notdef".into(),rings:vec![]}};assert!(cff_one("N",&[glyph.clone(),glyph]).is_err());}
