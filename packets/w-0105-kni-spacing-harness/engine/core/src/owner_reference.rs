//! Owner reference intake binding (P2). UNCOMPILED. cff_reader (sha cadae94c file) -> PinnedReference.
//! Reads outline geometry for ONE codepoint. hmtx/GPOS/kern tables are never read; the Type2 width operand is parsed
//! by the reader only to interpret the outline and is not used. No file => no reference.
//! Authorship is NOT established here: `expected_file_sha256` is byte integrity only; the caller's
//! `provenance_reference` must point at the parent's owner-attachment record for that exact sha.
use crate::{cff_reader::{CffReader,ReadReject},reference_transfer::{self as rt,PinnedReference}};
#[derive(Clone,Debug,PartialEq)]
pub enum IntakeError {
 /// reader refused (sha mismatch, unsupported operator, CID, seac, unsupported cmap...). Typed, never guessed.
 Reader(ReadReject),
 EmptyGlyphId, EmptyProvenance,
 /// codepoint not mapped by the owner's cmap: the font does not draw it; no reference exists.
 CodepointNotInCmap(u32),
 /// glyph has no outline (space/.notdef-empty); nothing to transfer.
 NoOutline(u32) }
#[derive(Clone,Debug)]
pub struct IntakeReceipt { pub file_sha256:String, pub codepoint:u32, pub gid:u16, pub rings:usize, pub nodes:usize, /// charstring hint metadata only; NOT evidence of design intent.
 pub hint_stem_count_metadata_only:usize,
 /// closures the reader added (unclosed subpaths); nonzero means the owner outline relied on implicit close.
 pub implicit_closures:usize, pub units_per_em:u16, pub cmap_choice:(u16,u16,u16),
 /// hmtx, GPOS, kern are never read.
 pub spacing_tables_read:bool,
 /// the reader parses the Type2 width operand only to interpret the outline; it is not used for spacing/targets.
 pub charstring_width_parsed_but_not_used_for_spacing:bool,
 /// Some(1.0) only if every coordinate is exactly integer-valued (observed); None = fractional/unknown precision.
 pub coordinate_grid_observed:Option<f64> }
/// Build a glyph-local pinned reference. `glyph_id` is the TARGET glyph id the reference is bound to; the caller is
/// responsible for the exact owner-file glyph <-> target glyph pairing (codepoint here), never by name similarity.
pub fn owner_reference(bytes:&[u8],expected_file_sha256:&str,provenance_reference:&str,codepoint:u32,glyph_id:&str)->Result<(PinnedReference,IntakeReceipt),IntakeError>{
 if glyph_id.is_empty(){return Err(IntakeError::EmptyGlyphId)}
 if provenance_reference.is_empty(){return Err(IntakeError::EmptyProvenance)}
 let reader=CffReader::from_bytes(bytes,expected_file_sha256).map_err(IntakeError::Reader)?;
 let gid=reader.glyph_for_codepoint(codepoint).ok_or(IntakeError::CodepointNotInCmap(codepoint))?;
 let g=reader.read_glyph(gid).map_err(IntakeError::Reader)?;
 if g.rings.is_empty()||g.rings.iter().any(|r|r.spans.is_empty()){return Err(IntakeError::NoOutline(codepoint))}
 let nodes=g.rings.iter().map(|r|r.spans.len()).sum();
 let pin=rt::make_pin(glyph_id,provenance_reference,&g.rings);
 let receipt=IntakeReceipt{file_sha256:reader.sha256().to_string(),codepoint,gid,rings:g.rings.len(),nodes,hint_stem_count_metadata_only:g.stem_count,implicit_closures:g.implicit_closures,units_per_em:reader.units_per_em(),cmap_choice:reader.cmap_choice(),spacing_tables_read:false,charstring_width_parsed_but_not_used_for_spacing:true,coordinate_grid_observed:crate::reference_guided::observed_grid(&g.rings)};
 Ok((PinnedReference{pin,rings:g.rings},receipt))
}
#[cfg(test)]mod tests{use super::*;
 #[test]fn empty_provenance_and_glyph_refused_before_reading(){assert_eq!(owner_reference(&[],"x","p",65,"").unwrap_err(),IntakeError::EmptyGlyphId);assert_eq!(owner_reference(&[],"x","",65,"A").unwrap_err(),IntakeError::EmptyProvenance);}
 #[test]fn wrong_sha_or_garbage_is_reader_reject_not_reference(){let r=owner_reference(&[0u8;16],&"0".repeat(64),"owner-attachment-record",65,"A");assert!(matches!(r,Err(IntakeError::Reader(_))));}
}
