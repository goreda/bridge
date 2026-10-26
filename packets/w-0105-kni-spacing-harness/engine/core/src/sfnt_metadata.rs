//! Caller-controlled support-table encoders. No inferred design/licensing values.
use crate::cff_container::ContainerError;
fn u16b(out:&mut Vec<u8>,v:u16){out.extend_from_slice(&v.to_be_bytes());}
fn i16b(out:&mut Vec<u8>,v:i16){out.extend_from_slice(&v.to_be_bytes());}
fn u32b(out:&mut Vec<u8>,v:u32){out.extend_from_slice(&v.to_be_bytes());}
#[derive(Clone,Debug)]
pub struct HeadMetadata {pub revision:u32,pub flags:u16,pub units_per_em:u16,pub created:i64,pub modified:i64,pub bounds:[i16;4],pub mac_style:u16,pub lowest_ppem:u16}
pub fn head(m:&HeadMetadata)->Result<Vec<u8>,ContainerError>{
    if m.units_per_em!=1000||m.bounds[0]>m.bounds[2]||m.bounds[1]>m.bounds[3] {return Err(ContainerError::InvalidHead);}
    let mut out=Vec::new();for v in [0x00010000,m.revision,0,0x5f0f3cf5]{u32b(&mut out,v);}u16b(&mut out,m.flags);u16b(&mut out,m.units_per_em);out.extend_from_slice(&m.created.to_be_bytes());out.extend_from_slice(&m.modified.to_be_bytes());for v in m.bounds{i16b(&mut out,v);}u16b(&mut out,m.mac_style);u16b(&mut out,m.lowest_ppem);i16b(&mut out,2);i16b(&mut out,0);i16b(&mut out,0);Ok(out)
}
#[derive(Clone,Debug)]
pub struct HheaMetadata {pub ascender:i16,pub descender:i16,pub line_gap:i16,pub advance_max:u16,pub min_lsb:i16,pub min_rsb:i16,pub max_extent:i16,pub caret_rise:i16,pub caret_run:i16,pub caret_offset:i16,pub metric_count:u16}
pub fn hhea(m:&HheaMetadata)->Vec<u8>{let mut out=Vec::new();u32b(&mut out,0x00010000);for v in [m.ascender,m.descender,m.line_gap]{i16b(&mut out,v);}u16b(&mut out,m.advance_max);for v in [m.min_lsb,m.min_rsb,m.max_extent,m.caret_rise,m.caret_run,m.caret_offset,0,0,0,0,0]{i16b(&mut out,v);}u16b(&mut out,m.metric_count);out}
#[derive(Clone,Debug)]
pub struct PostMetadata {pub italic_angle_fixed:i32,pub underline_position:i16,pub underline_thickness:i16,pub fixed_pitch:u32,pub memory:[u32;4]}
pub fn post(m:&PostMetadata)->Vec<u8>{let mut out=Vec::new();u32b(&mut out,0x00030000);out.extend_from_slice(&m.italic_angle_fixed.to_be_bytes());i16b(&mut out,m.underline_position);i16b(&mut out,m.underline_thickness);u32b(&mut out,m.fixed_pitch);for v in m.memory{u32b(&mut out,v);}out}
/// Version0 full78-byte OS/2. All design, embedding and range fields explicit.
#[derive(Clone,Debug)]
pub struct Os2Metadata {pub average_width:i16,pub weight:u16,pub width:u16,pub embedding:u16,pub subscript:[i16;4],pub superscript:[i16;4],pub strikeout:[i16;2],pub family_class:i16,pub panose:[u8;10],pub unicode_ranges:[u32;4],pub vendor:[u8;4],pub selection:u16,pub first_char:u16,pub last_char:u16,pub typo:[i16;3],pub win_ascent:u16,pub win_descent:u16,pub version:u16,pub cap_height:i16,pub x_height:i16}
pub fn os2(m:&Os2Metadata)->Result<Vec<u8>,ContainerError>{
    if !(1..=1000).contains(&m.weight)||!(1..=9).contains(&m.width)||m.first_char>m.last_char||![0,2,4,8].contains(&(m.embedding&15))||m.embedding&0xfcf1!=0||m.selection&0xfc00!=0||(m.version<4&&m.selection&0x0380!=0)||m.selection&64!=0&&m.selection&33!=0{return Err(ContainerError::InvalidMetadata);}
    let mut out=Vec::new();u16b(&mut out,m.version);i16b(&mut out,m.average_width);for v in [m.weight,m.width,m.embedding]{u16b(&mut out,v);}for v in m.subscript.into_iter().chain(m.superscript).chain(m.strikeout).chain([m.family_class]){i16b(&mut out,v);}out.extend_from_slice(&m.panose);for v in m.unicode_ranges{u32b(&mut out,v);}out.extend_from_slice(&m.vendor);for v in [m.selection,m.first_char,m.last_char]{u16b(&mut out,v);}for v in m.typo{i16b(&mut out,v);}u16b(&mut out,m.win_ascent);u16b(&mut out,m.win_descent);if m.version>=1{u32b(&mut out,0);u32b(&mut out,0);}if m.version>=2{i16b(&mut out,m.x_height);i16b(&mut out,m.cap_height);u16b(&mut out,0);u16b(&mut out,32);u16b(&mut out,1);}Ok(out)
}
#[derive(Clone,Debug)]
pub struct NameRecord {pub language:u16,pub name_id:u16,pub value:String}
/// Windows Unicode BMP platform3/encoding1 records, UTF16BE strings.
pub fn name(records:&[NameRecord])->Result<Vec<u8>,ContainerError>{
    let mut sorted=records.to_vec();sorted.sort_by_key(|r|(r.language,r.name_id));
    if sorted.windows(2).any(|w|(w[0].language,w[0].name_id)==(w[1].language,w[1].name_id)){return Err(ContainerError::InvalidMetadata);}
    let count=u16::try_from(sorted.len()).map_err(|_|ContainerError::SizeOverflow)?;
    let storage=6usize+12*sorted.len();let mut out=Vec::new();u16b(&mut out,0);u16b(&mut out,count);u16b(&mut out,u16::try_from(storage).map_err(|_|ContainerError::SizeOverflow)?);let mut strings=Vec::new();
    for record in sorted {if record.name_id==6&&(record.value.is_empty()||record.value.len()>63||!record.value.bytes().all(|b|(33..=126).contains(&b)&&!b"[](){}<>/%".contains(&b))){return Err(ContainerError::InvalidName);}let bytes:Vec<u8>=record.value.encode_utf16().flat_map(u16::to_be_bytes).collect();for v in [3,1,record.language,record.name_id,u16::try_from(bytes.len()).map_err(|_|ContainerError::SizeOverflow)?,u16::try_from(strings.len()).map_err(|_|ContainerError::SizeOverflow)?]{u16b(&mut out,v);}strings.extend(bytes);}out.extend(strings);Ok(out)
}
/// Unicode full repertoire Windows3/10 format12; one explicit group per codepoint.
/// 0013 (fmt4 decision 2026-10-12): a Windows 3/1 BMP format-4 subtable now
/// accompanies format 12. Windows consumers that read format 4 first are
/// blind to a format-12-only font. Format 4 carries BMP codepoints only
/// (< 0xFFFF); format 12 keeps the full repertoire. One segment per
/// codepoint plus the mandatory 0xFFFF terminator, mirroring the explicit
/// per-codepoint style of the format-12 groups; idRangeOffset is 0
/// everywhere (identity via idDelta, no glyphIdArray).
pub fn cmap(mapping:&[(u32,u16)],glyph_count:u16)->Result<Vec<u8>,ContainerError>{
    let mut sorted=mapping.to_vec();sorted.sort_by_key(|m|m.0);
    if sorted.iter().any(|&(c,g)|c>0x10ffff||(0xd800..=0xdfff).contains(&c)||g==0||g>=glyph_count)||sorted.windows(2).any(|w|w[0].0==w[1].0){return Err(ContainerError::InvalidMetadata);}
    let bmp:Vec<(u32,u16)>=sorted.iter().copied().filter(|&(c,_)|c<0xffff).collect();
    let segs=bmp.len()+1; // + terminal 0xFFFF segment
    // 0014 (baş mimar review 2026-10-12): guard on the actual 16-bit length
    // field, not the segment count - 16+8*segs must fit u16.
    if 16+8*segs>0xffff{return Err(ContainerError::SizeOverflow);}
    let seg_x2=(2*segs) as u16;
    let mut es=0u16;let mut pw=1u16;while pw*2<=segs as u16{pw*=2;es+=1;}
    let sr2=2*pw;let rshift=seg_x2-sr2;
    let mut f4=Vec::new();
    u16b(&mut f4,4);u16b(&mut f4,(16+8*segs) as u16);u16b(&mut f4,0);
    u16b(&mut f4,seg_x2);u16b(&mut f4,sr2);u16b(&mut f4,es);u16b(&mut f4,rshift);
    for &(c,_) in &bmp{u16b(&mut f4,c as u16);} u16b(&mut f4,0xffff);
    u16b(&mut f4,0);
    for &(c,_) in &bmp{u16b(&mut f4,c as u16);} u16b(&mut f4,0xffff);
    for &(c,g) in &bmp{u16b(&mut f4,(g as i32-c as i32) as u16);} u16b(&mut f4,1); // terminal: (0-0xFFFF) mod 2^16 -> glyph 0
    for _ in 0..segs{u16b(&mut f4,0);}
    let mut f12=Vec::new();
    u16b(&mut f12,12);u16b(&mut f12,0);u32b(&mut f12,u32::try_from(16+12*sorted.len()).map_err(|_|ContainerError::SizeOverflow)?);u32b(&mut f12,0);u32b(&mut f12,sorted.len() as u32);for(c,g)in sorted{u32b(&mut f12,c);u32b(&mut f12,c);u32b(&mut f12,g as u32);}
    let hlen=4+2*8;
    let mut out=Vec::new();
    u16b(&mut out,0);u16b(&mut out,2);
    u16b(&mut out,3);u16b(&mut out,1);u32b(&mut out,hlen as u32);
    u16b(&mut out,3);u16b(&mut out,10);u32b(&mut out,(hlen+f4.len()) as u32);
    out.extend(f4);out.extend(f12);Ok(out)
}

#[cfg(test)]
mod os2_selection_gate_tests {
    use super::*;
    fn m(version: u16, selection: u16) -> Os2Metadata {
        Os2Metadata { average_width: 500, weight: 400, width: 5, embedding: 0, subscript: [0; 4], superscript: [0; 4], strikeout: [0; 2], family_class: 0,
            panose: [0; 10], unicode_ranges: [0; 4], vendor: *b"TEST", selection, first_char: 0, last_char: 0, typo: [0; 3], win_ascent: 0, win_descent: 0, version, cap_height: 700, x_height: 500 }
    }
    #[test] fn v2_bit7_fails() { assert!(os2(&m(2, 0x40 | 0x80)).is_err()); assert!(os2(&m(3, 0x80)).is_err()); }
    #[test] fn v2_bits_8_9_fail() { assert!(os2(&m(2, 0x100)).is_err()); assert!(os2(&m(2, 0x200)).is_err()); }
    #[test] fn v4_use_typo_passes_with_byte_fields() {
        let b = os2(&m(4, 0x80)).unwrap();
        assert_eq!(u16::from_be_bytes([b[0], b[1]]), 4);
        assert_eq!(u16::from_be_bytes([b[62], b[63]]), 0x80);
        assert_eq!(i16::from_be_bytes([b[86], b[87]]), 500);
        assert_eq!(i16::from_be_bytes([b[88], b[89]]), 700);
    }
    #[test] fn reserved_bits_fail_in_every_version() {
        for v in [0u16, 2, 4] { for bit in 10..16 { assert!(os2(&m(v, 1 << bit)).is_err(), "v{v} bit{bit}"); } }
        assert!(os2(&m(4, 0xfc00 | 0x80)).is_err());
    }
    #[test] fn v2_without_bits_7_to_9_still_passes() { assert!(os2(&m(2, 0x40)).is_ok()); }
}
