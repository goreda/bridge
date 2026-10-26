//! Initial caller-bound CFF font path. Parser/render/native acceptance NOT_RUN.
// Initial caller-bound CFF font path surface retained while parser/render/native acceptance is NOT_RUN.
#[allow(unused_imports)]
use crate::cff_container::{CffGlyph,ContainerError,cff_one,maxp_cff,hmtx,assemble_otto};
use crate::sfnt_metadata::{self,HeadMetadata,HheaMetadata,PostMetadata,Os2Metadata,NameRecord};
#[derive(Clone,Debug)]
pub struct NativeFontInput {pub postscript_name:String,pub glyphs:Vec<CffGlyph>,pub left_side_bearings:Vec<i16>,pub mapping:Vec<(u32,u16)>,pub head:HeadMetadata,pub hhea:HheaMetadata,pub post:PostMetadata,pub os2:Os2Metadata,pub names:Vec<NameRecord>}
pub fn encode(input:&NativeFontInput)->Result<Vec<u8>,ContainerError>{
    encode_with_layout(input,None)
}
/// Optional layout attachment: caller-supplied GPOS bytes are bound into the
/// sfnt directory; checksum/directory/length stay with assemble_otto. Empty
/// GPOS bytes are rejected (no zero-length directory entry). GPOS content is
/// not parsed or validated here.
pub fn encode_with_layout(input:&NativeFontInput,gpos:Option<&[u8]>)->Result<Vec<u8>,ContainerError>{
    encode_with_layout_gsub(input,gpos,None)
}
/// Jobs-aware variant (P2-PAR): threads the worker count into the per-glyph
/// CFF encode; metadata guards, table layout and checksums are unchanged, so
/// the emitted OTF bytes equal the serial path at any job count.
pub fn encode_with_layout_jobs(input:&NativeFontInput,gpos:Option<&[u8]>,jobs:usize)->Result<Vec<u8>,ContainerError>{
    encode_with_layout_gsub_jobs(input,gpos,None,jobs)
}
/// Same as encode_with_layout with an optional caller-supplied GSUB table
/// (e.g. a 'liga' feature for sequence glyphs, which carry no cmap entry).
/// Empty GSUB bytes are rejected, mirroring the GPOS rule.
pub fn encode_with_layout_gsub(input:&NativeFontInput,gpos:Option<&[u8]>,gsub:Option<&[u8]>)->Result<Vec<u8>,ContainerError>{
    encode_with_layout_gsub_jobs(input,gpos,gsub,1)
}
/// Jobs-aware GSUB variant (P2-PAR): identical encode contract, jobs threaded.
pub fn encode_with_layout_gsub_jobs(input:&NativeFontInput,gpos:Option<&[u8]>,gsub:Option<&[u8]>,jobs:usize)->Result<Vec<u8>,ContainerError>{
    let count=u16::try_from(input.glyphs.len()).map_err(|_|ContainerError::TooManyGlyphs)?;
    if count==0||input.left_side_bearings.len()!=input.glyphs.len()||input.hhea.metric_count!=count||input.hhea.advance_max!=input.glyphs.iter().map(|g|g.advance).max().unwrap_or(0){return Err(ContainerError::InvalidMetadata);}
    // Encode-boundary intake guards: .notdef first, unique glyph names,
    // unique cmap codepoints and in-range nonzero gids. The container and
    // cmap builders keep their own identical guards; these reject earlier.
    if input.glyphs[0].name!=".notdef"{return Err(ContainerError::InvalidGlyphOrder);}
    {let mut seen=std::collections::BTreeSet::new();if input.glyphs.iter().any(|g|!seen.insert(&g.name)){return Err(ContainerError::InvalidName);}}
    {let mut codes:Vec<u32>=input.mapping.iter().map(|m|m.0).collect();codes.sort_unstable();if codes.windows(2).any(|w|w[0]==w[1])||input.mapping.iter().any(|&(_,g)|g==0||g>=count){return Err(ContainerError::InvalidMetadata);}}
    let bold=input.os2.selection&32!=0;let italic=input.os2.selection&1!=0;
    if (input.head.mac_style&1!=0)!=bold||(input.head.mac_style&2!=0)!=italic||input.os2.selection&0xfc00!=0||(input.os2.version<4&&input.os2.selection&0x0380!=0)||input.os2.selection&64!=0&&(bold||italic){return Err(ContainerError::InvalidMetadata);}
    for id in [1,2,3,4,5,6]{if !input.names.iter().any(|r|r.name_id==id&&!r.value.is_empty()){return Err(ContainerError::InvalidMetadata);}}
    if input.names.iter().filter(|r|r.name_id==6).any(|r|r.value!=input.postscript_name){return Err(ContainerError::InvalidMetadata);}
    let cff=crate::cff_container::cff_one_jobs(&input.postscript_name,&input.glyphs,jobs)?;
    // FRAME-EXTREMA-TRUE-INK: head/hhea extents are true cubic ink extrema, floor/ceil outward;
    // control points never contribute (not a control hull, not design metrics).
    // OS/2 selection gate: reserved bits 10-15 refused; bits 7-9 only when version>=4.
    // Metadata derivation from true cubic ink extrema (shared ink_bounds
    // helper), outward floor/ceil at the integer boundary. Output geometry
    // is not re-transformed. Control points never contribute.
    let mut all_bounds=None::<[i16;4]>;let mut derived_min_lsb=None::<i16>;let mut derived_min_rsb=None::<i16>;let mut derived_max_extent=None::<i16>;
    for(g,lsb)in input.glyphs.iter().zip(&input.left_side_bearings){
        let gb=crate::ink_bounds::integer_outward_bounds(&g.outline).map_err(ink_err)?;
        if let Some(b)=gb{all_bounds=crate::ink_bounds::union_bounds(all_bounds,gb);let extent=i16::try_from(*lsb as i32+b[2] as i32-b[0] as i32).map_err(|_|ContainerError::InvalidMetadata)?;let rsb=i16::try_from(g.advance as i32-extent as i32).map_err(|_|ContainerError::InvalidMetadata)?;derived_min_lsb=Some(derived_min_lsb.map_or(*lsb,|v|v.min(*lsb)));derived_min_rsb=Some(derived_min_rsb.map_or(rsb,|v|v.min(rsb)));derived_max_extent=Some(derived_max_extent.map_or(extent,|v|v.max(extent)));}
    }
    if input.head.bounds!=all_bounds.unwrap_or([0;4])||input.hhea.min_lsb!=derived_min_lsb.unwrap_or(0)||input.hhea.min_rsb!=derived_min_rsb.unwrap_or(0)||input.hhea.max_extent!=derived_max_extent.unwrap_or(0){return Err(ContainerError::InvalidMetadata);}
    let metrics:Vec<_>=input.glyphs.iter().zip(&input.left_side_bearings).map(|(g,l)|(g.advance,*l)).collect();
    let mut tables=vec![(*b"CFF ",cff),(*b"head",sfnt_metadata::head(&input.head)?),(*b"hhea",sfnt_metadata::hhea(&input.hhea)),(*b"hmtx",hmtx(&metrics)),(*b"maxp",maxp_cff(count)),(*b"name",sfnt_metadata::name(&input.names)?),(*b"cmap",sfnt_metadata::cmap(&input.mapping,count)?),(*b"OS/2",sfnt_metadata::os2(&input.os2)?),(*b"post",sfnt_metadata::post(&input.post))];
    if let Some(bytes)=gpos{if bytes.is_empty(){return Err(ContainerError::InvalidMetadata);}tables.push((*b"GPOS",bytes.to_vec()));}
    if let Some(bytes)=gsub{if bytes.is_empty(){return Err(ContainerError::InvalidMetadata);}tables.push((*b"GSUB",bytes.to_vec()));}
    assemble_otto(tables)
}
/// Maps the shared ink-bounds error onto container errors: coordinate-domain
/// failures are UnrepresentableCoordinate, ring-shape failures OpenContour
/// (the same variants charstring uses for those conditions).
fn ink_err(e:crate::ink_bounds::InkError)->ContainerError{match e{crate::ink_bounds::InkError::NonFinite|crate::ink_bounds::InkError::OutOfI16=>ContainerError::UnrepresentableCoordinate,crate::ink_bounds::InkError::OpenRing|crate::ink_bounds::InkError::EmptyRing=>ContainerError::OpenContour}}
/// Explicit audit pass distinct from raw encoding. No inferred fill conversion.
#[derive(Clone,Debug)]
pub struct NativeAuditPolicy {pub fills:Vec<crate::cff_fill::SourceFill>,pub roles:Vec<Vec<crate::cff_fill::RingRole>>,pub chosen_average:i16,pub require_no_clipping:bool}
#[derive(Clone,Debug)]
pub struct NativeAudit {pub per_glyph_fill:Vec<Vec<crate::cff_fill::FillAudit>>,pub os2_consistent:bool}
pub fn audit(input:&NativeFontInput,policy:&NativeAuditPolicy)->Result<NativeAudit,ContainerError>{
 if policy.fills.len()!=input.glyphs.len()||policy.roles.len()!=input.glyphs.len(){return Err(ContainerError::InvalidMetadata);}
 let per_glyph_fill=input.glyphs.iter().zip(&policy.fills).zip(&policy.roles).map(|((g,fill),roles)|crate::cff_fill::audit(&g.outline,*fill,roles)).collect();
 let candidates=crate::os2_consistency::candidate_ranges(&input.mapping,crate::os2_ranges::ASSIGNED_SPANS)?;
 let advances:Vec<_>=input.glyphs.iter().map(|g|g.advance).collect();
 let os2_consistent=crate::os2_consistency::verify(&input.os2,&input.mapping,&advances,candidates,policy.chosen_average,[input.head.bounds[1],input.head.bounds[3]],policy.require_no_clipping).is_ok();
 Ok(NativeAudit{per_glyph_fill,os2_consistent})
}
/// Native representability intake only. No silent renumbering/cmap rewriting.
#[derive(Clone,Debug)]
pub struct NativeGlyphIntake {pub encodable_indices:Vec<usize>,pub rejected:Vec<(usize,String,ContainerError)>}
pub fn inspect_glyphs(glyphs:&[CffGlyph])->NativeGlyphIntake{
 let mut out=NativeGlyphIntake{encodable_indices:Vec::new(),rejected:Vec::new()};
 for(index,glyph)in glyphs.iter().enumerate(){match crate::cff_container::charstring(glyph){Ok(_)=>out.encodable_indices.push(index),Err(reason)=>out.rejected.push((index,glyph.outline.glyph_id.clone(),reason))}}
 out
}
