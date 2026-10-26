//! OS/2 caller consistency guard. Unicode coverage does not imply shaping support.
use crate::sfnt_metadata::Os2Metadata;
use crate::cff_container::ContainerError;
#[derive(Clone,Copy,Debug)]
pub struct UnicodeRangeSpan {pub first:u32,pub last:u32,pub bit:u8}
/// Caller must supply a versioned complete Unicode-range definition, not a guess.
/// Coverage checked against declared map; returns candidate bits, NOT designer functionality.
pub fn candidate_ranges(mapping:&[(u32,u16)],definition:&[UnicodeRangeSpan])->Result<[u32;4],ContainerError>{
 let mut ranges=[0u32;4];for &(code,_)in mapping {if code>0x10ffff||(0xd800..=0xdfff).contains(&code){return Err(ContainerError::InvalidMetadata);}let mut covered=false;for span in definition{if span.first>span.last||span.bit>=128{return Err(ContainerError::InvalidMetadata);}if code>=span.first&&code<=span.last{ranges[(span.bit/32)as usize]|=1u32<<(span.bit%32);covered=true;}}if !covered{return Err(ContainerError::InvalidMetadata);}if code>0xffff{ranges[1]|=1<<25;}}Ok(ranges)
}
/// Caller supplies average-width rounding explicitly. No tolerance invented.
pub fn verify(m:&Os2Metadata,mapping:&[(u32,u16)],advances:&[u16],required:[u32;4],average:i16,outline_y:[i16;2],require_no_clipping:bool)->Result<(),ContainerError>{
 if advances.is_empty()||mapping.iter().any(|&(_,g)|g as usize>=advances.len())||m.average_width!=average{return Err(ContainerError::InvalidMetadata);}
 let nonzero:Vec<_>=advances.iter().copied().filter(|a|*a!=0).collect();if nonzero.is_empty(){if average!=0{return Err(ContainerError::InvalidMetadata);}}else{let sum:u64=nonzero.iter().map(|a|*a as u64).sum();let count=nonzero.len()as u64;let floor=sum/count;let ceil=(sum+count-1)/count;if average<0||((average as u64)!=floor&&(average as u64)!=ceil){return Err(ContainerError::InvalidMetadata);}}
 if m.unicode_ranges.iter().zip(required).any(|(declared,candidate)|*declared & !candidate != 0){return Err(ContainerError::InvalidMetadata);}
 let first=mapping.iter().map(|m|m.0.min(0xffff)as u16).min().unwrap_or(0xffff);let last=mapping.iter().map(|m|m.0.min(0xffff)as u16).max().unwrap_or(0xffff);
 if m.first_char!=first||m.last_char!=last||require_no_clipping&&((m.win_ascent as i32)<(outline_y[1]as i32).max(0)||(m.win_descent as i32)<(-(outline_y[0]as i32)).max(0)){return Err(ContainerError::InvalidMetadata);}Ok(())
}

/// Historical compatibility alias, does not compel designer flags.
pub fn required_ranges(mapping:&[(u32,u16)],definition:&[UnicodeRangeSpan])->Result<[u32;4],ContainerError>{candidate_ranges(mapping,definition)}
