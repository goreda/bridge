//! Clean-room training-only artifacts for the landed predictor.
//! No classification is inferred from names, Unicode, source groups or kerns.
//! Geometry-only classifier/prototype fitting is an upstream prerequisite.
//! Diagnostic adapter until independently reviewed and integrated.
use crate::gen::{ClassTargets,GenerationInputs,GlyphKnowledge,GlyphWall,KernPolicy};
use crate::learn::ExistingPair;
use std::collections::{BTreeMap,BTreeSet};

#[derive(Debug,Clone)]
pub struct Observation {
    pub row_pin:String,
    pub left:String,
    pub right:String,
    pub kern:i32,
}
#[derive(Debug,Clone)]
pub struct GeometryAssignment {
    pub glyph:String,
    pub knowledge:GlyphKnowledge,
    pub wall:GlyphWall,
    pub outline_pin:String,
    /// Exact pin of training-only prototype/membership artifact.
    pub prototype_pin:String,
    pub query_only:bool,
}
#[derive(Debug,Clone,PartialEq,Eq)]
pub enum FitError {
    MissingPin, DuplicateRow, DuplicatePair, DuplicateAssignment,
    QueryInFit, MissingTrainingGeometry(String), InvalidGeometry(String),
    TargetGlyphInTraining(String), NoTrainingRows, NoTrainingGaps,
    LandedPolicy(String),
}
#[derive(Debug,Clone)]
pub struct FitArtifacts {
    pub inputs:GenerationInputs,
    pub policy:KernPolicy,
    pub training_row_pins:Vec<String>,
    pub training_outline_pins:Vec<String>,
    pub prototype_pin:String,
    pub excluded_glyphs:Vec<String>,
}
fn pin(s:&str)->bool {s.len()==64 && s.bytes().all(|c|c.is_ascii_hexdigit())}
fn median(mut v:Vec<f64>)->f64 {
    v.sort_by(f64::total_cmp);
    let m=v.len()/2;
    // CONVENTION: standard even-sample midpoint median, no tuned threshold.
    if v.len()%2==0 {(v[m-1]+v[m])/2.0} else {v[m]}
}

/// Caller excludes every row incident to either target glyph before fitting.
/// This function independently refuses leakage rather than silently filtering it.
/// Assignment membership must come from the pinned training-only geometry model.
pub fn fit(
    rows:&[Observation],
    assignments:&[GeometryAssignment],
    excluded:&BTreeSet<String>,
    prototype_pin:&str,
)->Result<FitArtifacts,FitError>{
    if !pin(prototype_pin){return Err(FitError::MissingPin);}
    if rows.is_empty(){return Err(FitError::NoTrainingRows);}
    let mut seen_rows=BTreeSet::new();let mut seen_pairs=BTreeSet::new();
    let mut by_name=BTreeMap::new();
    for a in assignments {
        if !pin(&a.outline_pin)||a.prototype_pin!=prototype_pin {return Err(FitError::MissingPin);}
        if a.query_only {return Err(FitError::QueryInFit);}
        if excluded.contains(&a.glyph){return Err(FitError::TargetGlyphInTraining(a.glyph.clone()));}
        if by_name.insert(a.glyph.clone(),a).is_some(){return Err(FitError::DuplicateAssignment);}
        if !a.wall.advance.is_finite()||a.wall.advance<0.0||a.wall.rows.is_empty()||a.wall.rows.values().any(|(l,r)|!l.is_finite()||!r.is_finite()||l>r){return Err(FitError::InvalidGeometry(a.glyph.clone()));}
    }
    let mut cell:BTreeMap<(u32,u32,char,char),Vec<f64>>=BTreeMap::new();
    let mut stratum:BTreeMap<(char,char),Vec<f64>>=BTreeMap::new();let mut global=Vec::new();
    let mut existing=Vec::new();
    for row in rows {
        if !pin(&row.row_pin){return Err(FitError::MissingPin);}
        if !seen_rows.insert(row.row_pin.clone()){return Err(FitError::DuplicateRow);}
        if !seen_pairs.insert((row.left.clone(),row.right.clone())){return Err(FitError::DuplicatePair);}
        for g in [&row.left,&row.right] {if excluded.contains(g){return Err(FitError::TargetGlyphInTraining(g.clone()));}}
        let l=by_name.get(&row.left).ok_or_else(||FitError::MissingTrainingGeometry(row.left.clone()))?;
        let r=by_name.get(&row.right).ok_or_else(||FitError::MissingTrainingGeometry(row.right.clone()))?;
        let gap=crate::gen::min_gap0(&l.wall,&r.wall).ok_or(FitError::NoTrainingGaps)?;
        let kerned_gap=gap+f64::from(row.kern);
        if !kerned_gap.is_finite(){return Err(FitError::InvalidGeometry(row.left.clone()));}
        cell.entry((l.knowledge.right_class,r.knowledge.left_class,l.knowledge.case,r.knowledge.case)).or_default().push(f64::from(row.kern));
        stratum.entry((l.knowledge.case,r.knowledge.case)).or_default().push(kerned_gap);
        global.push(kerned_gap);
        existing.push(ExistingPair{left:row.left.clone(),right:row.right.clone(),kern:row.kern});
    }
    // CONVENTION: a median target can be estimated from any nonempty training
    // cell; landed KernPolicy separately enforces its support threshold.
    let targets=ClassTargets{cell_median:cell.into_iter().map(|(k,v)|(k,median(v))).collect(),stratum_mingap:stratum.into_iter().map(|(k,v)|(k,median(v))).collect(),global_mingap:median(global)};
    let inputs=GenerationInputs{glyphs:by_name.keys().cloned().collect(),knowledge:by_name.iter().map(|(g,a)|(g.clone(),a.knowledge.clone())).collect(),walls:by_name.iter().map(|(g,a)|(g.clone(),a.wall.clone())).collect(),targets,existing:crate::gen::existing_from_pairs(existing).map_err(|e|FitError::LandedPolicy(e.to_string()))?,restore:vec![]};
    crate::gen::validate_inputs(&inputs).map_err(|e|FitError::LandedPolicy(e.to_string()))?;
    let policy=crate::gen::derive_policy(&inputs).map_err(|e|FitError::LandedPolicy(e.to_string()))?;
    Ok(FitArtifacts{inputs,policy,training_row_pins:seen_rows.into_iter().collect(),training_outline_pins:by_name.values().map(|a|a.outline_pin.clone()).collect(),prototype_pin:prototype_pin.into(),excluded_glyphs:excluded.iter().cloned().collect()})
}

#[derive(Debug,Clone)]
pub struct PredictionRow {
    pub predicted:Option<i32>,
    pub mechanism:Option<String>,
    pub unavailable_reason:Option<String>,
    pub query_outline_pins:Vec<String>,
}
/// Insert raw target geometry as query ONLY after immutable fit artifacts exist.
/// It never changes targets, training inventory, policy or prototype membership.
pub fn predict_query(fit:&FitArtifacts,left:&GeometryAssignment,right:&GeometryAssignment)->PredictionRow{
    let unavailable=|reason:&str|PredictionRow{predicted:None,mechanism:None,unavailable_reason:Some(reason.into()),query_outline_pins:vec![left.outline_pin.clone(),right.outline_pin.clone()]};
    for q in [left,right]{
        if !q.query_only||!fit.excluded_glyphs.contains(&q.glyph){return unavailable("query not bound to excluded target glyph");}
        if !pin(&q.outline_pin)||q.prototype_pin!=fit.prototype_pin{return unavailable("query outline/prototype pin mismatch");}
        if !q.wall.advance.is_finite()||q.wall.advance<0.0||q.wall.rows.is_empty()||q.wall.rows.values().any(|(l,r)|!l.is_finite()||!r.is_finite()||l>r){return unavailable("invalid or unavailable query wall");}
    }
    let mut inp=fit.inputs.clone();
    for q in [left,right]{inp.knowledge.insert(q.glyph.clone(),q.knowledge.clone());inp.walls.insert(q.glyph.clone(),q.wall.clone());}
    if crate::gen::validate_inputs(&inp).is_err(){return unavailable("landed input prevalidation failed");}
    match crate::gen::predict_policy(&inp,&left.glyph,&right.glyph,None,&fit.policy){
        Some((k,m))=>PredictionRow{predicted:Some(k),mechanism:Some(m.into()),unavailable_reason:None,query_outline_pins:vec![left.outline_pin.clone(),right.outline_pin.clone()]},
        None=>unavailable("landed predictor unavailable or unrepresentable; no silent fallback"),
    }
}

impl FitArtifacts {
    /// Canonical fitted-artifact receipt. Includes every learned target, wall,
    /// membership and policy field; no timestamp or local path. Float bits avoid
    /// decimal representation ambiguity. Hash this before query evaluation.
    pub fn canonical_receipt(&self)->String{
        let mut s=String::from("training-only-fit\tmethod=median-artifact-adapter-v1\n");
        s.push_str(&format!("prototype\t{}\n",self.prototype_pin));
        for p in &self.training_row_pins{s.push_str(&format!("row\t{p}\n"));}
        for p in &self.training_outline_pins{s.push_str(&format!("outline\t{p}\n"));}
        for g in &self.excluded_glyphs{s.push_str(&format!("excluded\t{g}\n"));}
        let mut gs:Vec<_>=self.inputs.knowledge.iter().collect();gs.sort_by(|a,b|a.0.cmp(b.0));
        for (g,k) in gs{s.push_str(&format!("class\t{g}\t{}\t{}\t{}\n",k.right_class,k.left_class,k.case));}
        let mut ws:Vec<_>=self.inputs.walls.iter().collect();ws.sort_by(|a,b|a.0.cmp(b.0));
        for (g,w) in ws{for (y,(l,r)) in &w.rows{s.push_str(&format!("wall\t{g}\t{:016x}\t{y}\t{:016x}\t{:016x}\n",w.advance.to_bits(),l.to_bits(),r.to_bits()));}}
        let mut cells:Vec<_>=self.inputs.targets.cell_median.iter().collect();cells.sort_by(|a,b|a.0.cmp(b.0));
        for ((l,r,cl,cr),v) in cells{s.push_str(&format!("cell\t{l}\t{r}\t{cl}\t{cr}\t{:016x}\n",v.to_bits()));}
        let mut strata:Vec<_>=self.inputs.targets.stratum_mingap.iter().collect();strata.sort_by(|a,b|a.0.cmp(b.0));
        for ((l,r),v) in strata{s.push_str(&format!("stratum\t{l}\t{r}\t{:016x}\n",v.to_bits()));}
        s.push_str(&format!("global\t{:016x}\n",self.inputs.targets.global_mingap.to_bits()));
        s.push_str(&format!("policy\t{}\t{}\t{}\t{}\n",self.policy.noise_floor,self.policy.clamp_lo,self.policy.clamp_hi,self.policy.min_cell_support));
        let mut supports:Vec<_>=self.policy.cell_support.iter().collect();supports.sort_by(|a,b|a.0.cmp(b.0));
        for ((l,r,cl,cr),n) in supports{s.push_str(&format!("support\t{l}\t{r}\t{cl}\t{cr}\t{n}\n"));}
        let mut ex:Vec<_>=self.inputs.existing.iter().collect();ex.sort();
        for ((l,r),v) in ex{s.push_str(&format!("existing\t{l}\t{r}\t{v}\n"));}
        s
    }
    pub fn artifact_sha256(&self)->String{kni_learning::sha256::sha256_hex(self.canonical_receipt().as_bytes())}
}

/// Explicit endpoint-part query path. Legacy fit/predict_query remain unchanged.
#[derive(Debug,Clone,PartialEq,Eq)]
pub enum HeldOutPartError {
    EmptyPart,
    QueryOutsidePart,
    PartGlyphInTraining(String),
    PartNotBoundToFit(String),
    TrainingInventoryMismatch,
    PartnerMismatch(String),
    QueryOutsidePartAt(usize),
    TrainingOutlineInventoryMismatch,
}
#[derive(Debug,Clone,PartialEq,Eq)]
pub struct HeldOutPartReceipt {
    pub part_glyph_count:usize,
    pub excluded_row_count:usize,
    pub retained_row_count:usize,
}
#[derive(Debug,Clone)]
pub struct HeldOutPartPrediction {
    pub prediction:PredictionRow,
    pub receipt:HeldOutPartReceipt,
}
/// Check original row inventory against the exact fitted inventory independently.
/// A row is excluded iff either endpoint belongs to part. It is not enough to
/// filter only the pair being predicted or to filter one endpoint direction.
pub fn predict_query_held_out_part(
    fit:&FitArtifacts,
    left:&GeometryAssignment,
    right:&GeometryAssignment,
    part:&BTreeSet<String>,
    original_rows:&[Observation],
)->Result<HeldOutPartPrediction,HeldOutPartError>{
    if part.is_empty(){return Err(HeldOutPartError::EmptyPart);}
    if !part.contains(&left.glyph)&&!part.contains(&right.glyph){return Err(HeldOutPartError::QueryOutsidePart);}
    let receipt=validate_part_inventory(fit,part,original_rows)?;
    let partner_pins=trained_partner_pin_map(fit)?;
    for q in [left,right]{validate_trained_partner(fit,q,part,&partner_pins)?;}
    let mut query_fit=fit.clone();
    for q in [left,right]{if !query_fit.excluded_glyphs.contains(&q.glyph){query_fit.excluded_glyphs.push(q.glyph.clone());}}
    query_fit.excluded_glyphs.sort();
    let prediction=predict_query(&query_fit,left,right);
    Ok(HeldOutPartPrediction{prediction,receipt:receipt})
}

fn validate_trained_partner(fit:&FitArtifacts,q:&GeometryAssignment,part:&BTreeSet<String>,partner_pins:&BTreeMap<String,String>)->Result<(),HeldOutPartError>{
 if part.contains(&q.glyph){return Ok(())}
 let bad=||HeldOutPartError::PartnerMismatch(q.glyph.clone());
 let k=fit.inputs.knowledge.get(&q.glyph).ok_or_else(bad)?;let w=fit.inputs.walls.get(&q.glyph).ok_or_else(bad)?;
 if partner_pins.get(&q.glyph)!=Some(&q.outline_pin)||q.prototype_pin!=fit.prototype_pin||!q.query_only||k.case!=q.knowledge.case||k.freq_weight!=q.knowledge.freq_weight||k.left_class!=q.knowledge.left_class||k.right_class!=q.knowledge.right_class||w.advance.to_bits()!=q.wall.advance.to_bits()||w.rows.len()!=q.wall.rows.len()||w.rows.iter().any(|(y,(l,r))|q.wall.rows.get(y).is_none_or(|(a,b)|a.to_bits()!=l.to_bits()||b.to_bits()!=r.to_bits())){return Err(bad())}
 Ok(())
}
/// Validate inventory once and clone the fitted object once for a part batch.
pub fn predict_query_held_out_part_batch(fit:&FitArtifacts,pairs:&[(GeometryAssignment,GeometryAssignment)],part:&BTreeSet<String>,available_geometry_original_rows:&[Observation])->Result<Vec<HeldOutPartPrediction>,HeldOutPartError>{
 if part.is_empty(){return Err(HeldOutPartError::EmptyPart)}if pairs.is_empty(){return Ok(vec![])}
 // Validate shared inventory/pin map once. Every pair has indexed part
 // intersection and trained-partner identity checks before any prediction.
 let receipt=validate_part_inventory(fit,part,available_geometry_original_rows)?;
 let partner_pins=trained_partner_pin_map(fit)?;
 let mut query_fit=fit.clone();for(index,(l,r))in pairs.iter().enumerate(){if !part.contains(&l.glyph)&&!part.contains(&r.glyph){return Err(HeldOutPartError::QueryOutsidePartAt(index))}for q in [l,r]{validate_trained_partner(fit,q,part,&partner_pins)?;if !query_fit.excluded_glyphs.contains(&q.glyph){query_fit.excluded_glyphs.push(q.glyph.clone());}}}query_fit.excluded_glyphs.sort();
 Ok(pairs.iter().map(|(l,r)|HeldOutPartPrediction{prediction:predict_query(&query_fit,l,r),receipt:receipt.clone()}).collect())
}

fn validate_part_inventory(fit:&FitArtifacts,part:&BTreeSet<String>,original_rows:&[Observation])->Result<HeldOutPartReceipt,HeldOutPartError>{
    if part.is_empty(){return Err(HeldOutPartError::EmptyPart);}
    for g in part {
        if !fit.excluded_glyphs.contains(g){return Err(HeldOutPartError::PartNotBoundToFit(g.clone()));}
        if fit.inputs.knowledge.contains_key(g)||fit.inputs.walls.contains_key(g)||fit.inputs.existing.keys().any(|(l,r)|l==g||r==g){return Err(HeldOutPartError::PartGlyphInTraining(g.clone()));}
    }
    let retained_pins:BTreeSet<_>=fit.training_row_pins.iter().cloned().collect();
    let mut excluded_count=0;
    let mut original_pins=BTreeSet::new();
    let mut expected_retained=BTreeSet::new();
    for row in original_rows {
        if !original_pins.insert(row.row_pin.clone()){return Err(HeldOutPartError::TrainingInventoryMismatch);}
        if part.contains(&row.left)||part.contains(&row.right){
            excluded_count+=1;
            if retained_pins.contains(&row.row_pin){return Err(HeldOutPartError::PartGlyphInTraining(if part.contains(&row.left){row.left.clone()}else{row.right.clone()}));}
        } else {expected_retained.insert(row.row_pin.clone());}
    }
    if expected_retained!=retained_pins{return Err(HeldOutPartError::TrainingInventoryMismatch);}
    Ok(HeldOutPartReceipt{part_glyph_count:part.len(),excluded_row_count:excluded_count,retained_row_count:fit.training_row_pins.len()})
}

/// fit() constructs training_outline_pins from by_name.values(), a BTreeMap,
/// so pins and sorted knowledge names have the same order and glyph set. Check
/// cardinality and preserve that binding once per single query or batch.
fn trained_partner_pin_map(fit:&FitArtifacts)->Result<BTreeMap<String,String>,HeldOutPartError>{let names:BTreeSet<_>=fit.inputs.knowledge.keys().cloned().collect();if names.len()!=fit.training_outline_pins.len()||names.iter().any(|g|!fit.inputs.walls.contains_key(g)){return Err(HeldOutPartError::TrainingOutlineInventoryMismatch)}Ok(names.into_iter().zip(fit.training_outline_pins.iter().cloned()).collect())}
