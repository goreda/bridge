//! Outline-only full parsed reference-cmap measurements. Not hmtx fidelity.
use crate::otf::{OtfFont,ReadError};
use crate::validate::Params;
use crate::vector::{vector_fidelity,MasterFill,VectorError};
#[derive(Debug,PartialEq)]pub enum FontRowError{InvalidParams,FrameMismatch,EmptyCmap,DuplicateCodepoint(u32),InvalidRow(u32),InvalidHash,IdenticalHashes}
#[derive(Debug,Clone,PartialEq)]pub struct Metrics{pub symmetric_difference_area:f64,pub area_floor:f64,pub perimeter_sum:f64,pub hausdorff:f64,pub distance_floor:f64}
#[derive(Debug,Clone,Copy,PartialEq)]pub enum ReasonClass{ReferenceUnmeasurable,CandidateMissingOrEmpty,MeasurementError}
impl ReasonClass{fn name(self)->&'static str{match self{Self::ReferenceUnmeasurable=>"reference_unmeasurable",Self::CandidateMissingOrEmpty=>"candidate_missing_or_empty",Self::MeasurementError=>"measurement_error"}}}
#[derive(Debug,Clone,Copy,PartialEq)]pub enum FontSide{Reference,Candidate,Both}
impl FontSide{fn name(self)->&'static str{match self{Self::Reference=>"reference",Self::Candidate=>"candidate",Self::Both=>"both"}}}
#[derive(Debug,Clone,PartialEq)]pub struct Unmeasurable{pub reason_class:ReasonClass,pub font:FontSide,pub reason:&'static str}
#[derive(Debug,Clone,PartialEq)]pub struct FontFidelityRow{pub codepoint:u32,pub metrics:Option<Metrics>,pub unavailable:Option<Unmeasurable>}
#[derive(Debug)]pub struct MeasurementBatch{pub rows:Vec<FontFidelityRow>,pub upm:f64,pub params:Params}
fn unavailable(cp:u32,class:ReasonClass,font:FontSide,reason:&'static str)->FontFidelityRow{FontFidelityRow{codepoint:cp,metrics:None,unavailable:Some(Unmeasurable{reason_class:class,font,reason})}}
// CONVENTION: explicit reason/class/font matching table, shared with Python.
fn valid_unavailable(u:&Unmeasurable)->bool{
 use ReasonClass::*;use FontSide::*;
 match u.reason {
 "candidate_missing"|"candidate_empty"=>u.reason_class==CandidateMissingOrEmpty&&u.font==Candidate,
 "reference_missing"|"reference_empty"|"invalid_codepoint"=>u.reason_class==ReferenceUnmeasurable&&u.font==Reference,
 "outline_nonfinite"|"reader_truncated"|"reader_signature"|"reader_missing_table"|"reader_unsupported"|"reader_bad_charstring"|"reader_bad_glyf"|"reader_glyph_index"|"reader_budget"=>(u.reason_class==ReferenceUnmeasurable&&u.font==Reference)||(u.reason_class==MeasurementError&&u.font==Candidate),
 "measurement_pitch"|"measurement_budget"|"measurement_empty"|"metric_nonfinite"=>u.reason_class==MeasurementError&&u.font==Both,
 _=>false,
 }
}
fn reader_code(e:&ReadError)->&'static str{match e{ReadError::Truncated(_)=>"reader_truncated",ReadError::NotCffOpenType=>"reader_signature",ReadError::MissingTable(_)=>"reader_missing_table",ReadError::Unsupported(_)=>"reader_unsupported",ReadError::BadCharstring{..}=>"reader_bad_charstring",ReadError::BadGlyf{..}=>"reader_bad_glyf",ReadError::GlyphIndexOutOfRange(_)=>"reader_glyph_index",ReadError::Budget{..}=>"reader_budget"}}
fn finite_outline(g:&crate::model::MasterGlyph)->bool{g.contours.iter().flat_map(|c|&c.ops).all(|o|match o{crate::model::Op::Move(p)|crate::model::Op::Line(p)=>p.0.is_finite()&&p.1.is_finite(),crate::model::Op::Curve(a,b,c)=>[a,b,c].iter().all(|p|p.0.is_finite()&&p.1.is_finite()),crate::model::Op::Close=>true})}
fn values(m:&Metrics)->[f64;5]{[m.symmetric_difference_area,m.area_floor,m.perimeter_sum,m.hausdorff,m.distance_floor]}
fn valid_params(p:Params)->bool{p.grid.is_finite()&&p.grid>0.&&p.margin.is_finite()&&p.margin>=0.}
fn one(reference:&OtfFont<'_>,candidate:&OtfFont<'_>,cp:u32,params:Params)->FontFidelityRow{
 if cp>0x10ffff||(0xd800..=0xdfff).contains(&cp){return unavailable(cp,ReasonClass::ReferenceUnmeasurable,FontSide::Reference,"invalid_codepoint")}
 // Candidate attribution wins when both sides fail: it must never be hidden
 // under an exemption for an unreadable/empty reference.
 let master=match candidate.glyph_by_codepoint(cp){Ok(Some(g))=>g,Ok(None)=>return unavailable(cp,ReasonClass::CandidateMissingOrEmpty,FontSide::Candidate,"candidate_missing"),Err(e)=>return unavailable(cp,ReasonClass::MeasurementError,FontSide::Candidate,reader_code(&e))};
 if master.contours.is_empty(){return unavailable(cp,ReasonClass::CandidateMissingOrEmpty,FontSide::Candidate,"candidate_empty")}
 if !finite_outline(&master){return unavailable(cp,ReasonClass::MeasurementError,FontSide::Candidate,"outline_nonfinite")}
 let source=match reference.glyph_by_codepoint(cp){Ok(Some(g))=>g,Ok(None)=>return unavailable(cp,ReasonClass::ReferenceUnmeasurable,FontSide::Reference,"reference_missing"),Err(e)=>return unavailable(cp,ReasonClass::ReferenceUnmeasurable,FontSide::Reference,reader_code(&e))};
 if source.contours.is_empty(){return unavailable(cp,ReasonClass::ReferenceUnmeasurable,FontSide::Reference,"reference_empty")}
 if !finite_outline(&source){return unavailable(cp,ReasonClass::ReferenceUnmeasurable,FontSide::Reference,"outline_nonfinite")}
 let f=match vector_fidelity(&master,&source,params,MasterFill::Merged){Ok(f)=>f,Err(e)=>return unavailable(cp,ReasonClass::MeasurementError,FontSide::Both,match e{VectorError::Pitch(_)=>"measurement_pitch",VectorError::EdgeBudget{..}=>"measurement_budget",VectorError::EmptyOutline=>"measurement_empty"})};
 let m=Metrics{symmetric_difference_area:f.symdiff_area,area_floor:f.area_floor,perimeter_sum:f.perimeter_sum,hausdorff:f.hausdorff,distance_floor:f.distance_floor};
 if values(&m).iter().any(|v|!v.is_finite()||*v<0.){return unavailable(cp,ReasonClass::MeasurementError,FontSide::Both,"metric_nonfinite")}FontFidelityRow{codepoint:cp,metrics:Some(m),unavailable:None}
}
pub fn measure_font_cmap(reference:&OtfFont<'_>,candidate:&OtfFont<'_>,params:Params)->Result<MeasurementBatch,FontRowError>{
 if !valid_params(params){return Err(FontRowError::InvalidParams)}
 if reference.upm()!=candidate.upm(){return Err(FontRowError::FrameMismatch)}
 let rows:Vec<_>=reference.codepoints().map(|cp|one(reference,candidate,cp,params)).collect();if rows.is_empty(){return Err(FontRowError::EmptyCmap)}Ok(MeasurementBatch{rows,upm:reference.upm(),params})
}
/// Supplied hashes must be verified against original parsed bytes by caller.
/// Same hashes are refused: this interface is for distinct-font comparisons.
pub struct MeasurementContext<'a>{pub reference_sha256:&'a str,pub candidate_sha256:&'a str,pub upm:f64,pub params:Params}
pub fn measurements_json(batch:&MeasurementBatch,ctx:MeasurementContext<'_>)->Result<String,FontRowError>{
 for h in [ctx.reference_sha256,ctx.candidate_sha256]{if h.len()!=64||!h.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b)){return Err(FontRowError::InvalidHash)}}
 if ctx.reference_sha256==ctx.candidate_sha256{return Err(FontRowError::IdenticalHashes)}
 if !valid_params(ctx.params)||ctx.upm!=batch.upm||ctx.params.grid!=batch.params.grid||ctx.params.margin!=batch.params.margin{return Err(FontRowError::FrameMismatch)}
 if !ctx.upm.is_finite()||ctx.upm<=0.{return Err(FontRowError::InvalidParams)}
 if batch.rows.is_empty(){return Err(FontRowError::EmptyCmap)}
 let mut ordered=batch.rows.clone();ordered.sort_by_key(|r|r.codepoint);for p in ordered.windows(2){if p[0].codepoint==p[1].codepoint{return Err(FontRowError::DuplicateCodepoint(p[0].codepoint))}}
 let mut counts=[0usize;3];for r in &ordered{if let Some(u)=&r.unavailable{if !valid_unavailable(u){return Err(FontRowError::InvalidRow(r.codepoint))}counts[match u.reason_class{ReasonClass::ReferenceUnmeasurable=>0,ReasonClass::CandidateMissingOrEmpty=>1,ReasonClass::MeasurementError=>2}]+=1}}
 let mut out=format!("{{\"schema\":\"kni.vector-measurements.v3\",\"reference_font_sha256\":\"{}\",\"candidate_font_sha256\":\"{}\",\"upm\":{},\"params\":{{\"grid\":{},\"margin\":{}}},\"method\":\"merged-flattened-area-sampled-hausdorff-v2\",\"scope\":\"outlines-only\",\"n_a_count\":{},\"n_a_by_class\":{{\"reference_unmeasurable\":{},\"candidate_missing_or_empty\":{},\"measurement_error\":{}}},\"glyphs\":[",ctx.reference_sha256,ctx.candidate_sha256,ctx.upm,ctx.params.grid,ctx.params.margin,counts.iter().sum::<usize>(),counts[0],counts[1],counts[2]);
 for(i,r)in ordered.iter().enumerate(){if (r.codepoint>0x10ffff||(0xd800..=0xdfff).contains(&r.codepoint))&&r.unavailable.as_ref().map_or(true,|u|u.reason!="invalid_codepoint"){return Err(FontRowError::InvalidRow(r.codepoint))}if i>0{out.push(',')}match (&r.metrics,&r.unavailable){(Some(m),None)=>{if values(m).iter().any(|v|!v.is_finite()||*v<0.)||m.distance_floor!=2.*batch.params.grid||m.area_floor!=batch.params.grid*m.perimeter_sum{return Err(FontRowError::InvalidRow(r.codepoint))}out+=&format!("{{\"codepoint\":{},\"path_label\":\"vector\",\"symmetric_difference_area\":{},\"area_floor\":{},\"perimeter_sum\":{},\"hausdorff\":{},\"distance_floor\":{}}}",r.codepoint,m.symmetric_difference_area,m.area_floor,m.perimeter_sum,m.hausdorff,m.distance_floor)},(None,Some(u))=>out+=&format!("{{\"codepoint\":{},\"status\":\"n/a\",\"reason\":\"{}\",\"reason_class\":\"{}\",\"font\":\"{}\"}}",r.codepoint,u.reason,u.reason_class.name(),u.font.name()),_=>return Err(FontRowError::InvalidRow(r.codepoint))}}
 out.push_str("]}\n");Ok(out)
}
#[cfg(test)]mod reason_table_tests{
 use super::*;
 #[test]fn all_reason_pair_permutations(){let reasons=["candidate_missing","candidate_empty","reference_missing","reference_empty","invalid_codepoint","outline_nonfinite","reader_truncated","reader_signature","reader_missing_table","reader_unsupported","reader_bad_charstring","reader_bad_glyf","reader_glyph_index","reader_budget","measurement_pitch","measurement_budget","measurement_empty","metric_nonfinite"];
 for reason in reasons{for class in [ReasonClass::ReferenceUnmeasurable,ReasonClass::CandidateMissingOrEmpty,ReasonClass::MeasurementError]{for font in [FontSide::Reference,FontSide::Candidate,FontSide::Both]{let allowed=if reason.starts_with("candidate_"){class==ReasonClass::CandidateMissingOrEmpty&&font==FontSide::Candidate}else if reason.starts_with("reference_")||reason=="invalid_codepoint"{class==ReasonClass::ReferenceUnmeasurable&&font==FontSide::Reference}else if reason.starts_with("reader_")||reason=="outline_nonfinite"{(class==ReasonClass::ReferenceUnmeasurable&&font==FontSide::Reference)||(class==ReasonClass::MeasurementError&&font==FontSide::Candidate)}else{class==ReasonClass::MeasurementError&&font==FontSide::Both};assert_eq!(valid_unavailable(&Unmeasurable{reason_class:class,font,reason}),allowed);}}}}
}
#[cfg(test)]mod invalid_codepoint_tests{
 use super::*;
 #[test]fn invalid_cp_is_row_not_batch_error(){let r=unavailable(0xd800,ReasonClass::ReferenceUnmeasurable,FontSide::Reference,"invalid_codepoint");let p=Params::from_rounding(0.5);let b=MeasurementBatch{rows:vec![r],upm:1000.,params:p};let a="a".repeat(64);let c="c".repeat(64);let s=measurements_json(&b,MeasurementContext{reference_sha256:&a,candidate_sha256:&c,upm:1000.,params:p}).unwrap();assert!(s.contains("invalid_codepoint"));assert!(s.contains("55296"));}
}
