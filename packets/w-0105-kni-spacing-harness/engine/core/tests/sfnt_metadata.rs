// Authored exact-byte fixtures, all NOT_RUN.
use kni_core::sfnt_metadata::{cmap,name,NameRecord};
// 0013 (fmt4 decision 2026-10-12): cmap is now a two-subtable table -
// Windows 3/1 BMP format 4 first, then the full-repertoire Windows 3/10
// format 12. Exact-byte fixture updated to the new contract.
#[test]fn cmap_a_exact(){assert_eq!(cmap(&[(65,1)],2).unwrap(),vec![0,0,0,2,0,3,0,1,0,0,0,20,0,3,0,10,0,0,0,52,0,4,0,32,0,0,0,4,0,4,0,1,0,0,0,65,255,255,0,0,0,65,255,255,255,192,0,1,0,0,0,0,0,12,0,0,0,0,0,28,0,0,0,0,0,0,0,1,0,0,0,65,0,0,0,65,0,0,0,1]);}
// 0014 (baş mimar review 2026-10-12): segment-content assertions, not just
// subtable presence. fmt4 must carry exactly the BMP codepoints plus the
// 0xFFFF terminator with identity idDelta mapping; fmt12 carries the full
// repertoire including the non-BMP codepoint.
#[test]fn cmap_fmt4_bmp_only(){
    let v=cmap(&[(0x41,1),(0x2044,2),(0x1F600,3)],4).unwrap();
    assert_eq!(&v[0..4],[0,0,0,2]); // two subtables
    let f4_off=u32::from_be_bytes([v[8],v[9],v[10],v[11]]) as usize;
    let f12_off=u32::from_be_bytes([v[16],v[17],v[18],v[19]]) as usize;
    assert!(f4_off<f12_off);
    let f4=&v[f4_off..f12_off]; let f12=&v[f12_off..];
    let at=|b:&[u8],i:usize|u16::from_be_bytes([b[i],b[i+1]]);
    assert_eq!(at(f4,0),4); // format
    assert_eq!(at(f4,2) as usize,f4.len()); // length covers the subtable
    let segs=(at(f4,6)/2) as usize;
    assert_eq!(segs,3); // two BMP codepoints + terminator
    assert_eq!(f4.len(),16+8*segs);
    let end:Vec<u16>=(0..segs).map(|i|at(f4,14+2*i)).collect();
    let start:Vec<u16>=(0..segs).map(|i|at(f4,16+2*segs+2*i)).collect();
    let delta:Vec<u16>=(0..segs).map(|i|at(f4,16+4*segs+2*i)).collect();
    let roff:Vec<u16>=(0..segs).map(|i|at(f4,16+6*segs+2*i)).collect();
    assert_eq!(end,vec![0x41,0x2044,0xFFFF]);
    assert_eq!(start,end);
    assert_eq!(delta[0],1u16.wrapping_sub(0x41));
    assert_eq!(delta[1],2u16.wrapping_sub(0x2044));
    assert_eq!(delta[2],1); // terminator maps 0xFFFF to glyph 0
    assert!(roff.iter().all(|&r|r==0));
    assert_eq!(at(f12,0),12);
    let ng=u32::from_be_bytes([f12[12],f12[13],f12[14],f12[15]]) as usize;
    assert_eq!(ng,3); // full repertoire: both BMP + the non-BMP codepoint
    assert!(f12.windows(4).any(|w|w==[0x00,0x01,0xF6,0x00])); // 0x1F600 in fmt12
}
// 0014: the guard is on the 16-bit length field (16+8*segs <= 0xFFFF), so
// 8188 BMP codepoints fit and 8189 overflow.
#[test]fn cmap_fmt4_length_guard(){
    let ok:Vec<(u32,u16)>=(1..=8188u32).map(|c|(c,c as u16)).collect();
    assert!(cmap(&ok,8191).is_ok());
    let over:Vec<(u32,u16)>=(1..=8189u32).map(|c|(c,c as u16)).collect();
    assert!(cmap(&over,8191).is_err());
}
#[test]fn name_one_exact(){assert_eq!(name(&[NameRecord{language:0x409,name_id:1,value:String::from("A")}]).unwrap(),vec![0,0,0,1,0,18,0,3,0,1,4,9,0,1,0,2,0,0,0,65]);}
#[test]fn rejects_bad_mapping(){assert!(cmap(&[(0xd800,1)],2).is_err());assert!(cmap(&[(65,0)],2).is_err());assert!(cmap(&[(65,1),(65,1)],2).is_err());}
#[test]fn postscript_name_rejects_forbidden(){for text in ["bad name","bad/name",""]{assert!(name(&[NameRecord{language:0x409,name_id:6,value:text.into()}]).is_err());}}
