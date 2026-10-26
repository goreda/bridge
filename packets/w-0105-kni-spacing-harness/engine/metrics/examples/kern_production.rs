//! External file caller. Input receipts are references, not proof minted here.
#[path = "../src/gen_production.rs"]
mod gen_production;
#[path = "../src/gpos_verified.rs"]
mod gpos_verified;
mod gen { pub use kni_metrics::gen::*; }
mod export_gpos { pub use kni_metrics::export_gpos::*; }
use gen_production::*;
use kni_metrics::gen::{GenerationInputs,parse_classes,parse_targets,parse_walls};
use std::collections::{BTreeMap,BTreeSet,HashMap};
use std::path::Path;
use std::fs;

fn rows(dir:&Path, name:&str, header:&str) -> Result<Vec<Vec<String>>,String> {
    let text=fs::read_to_string(dir.join(name)).map_err(|e|format!("{name}: {e}"))?;
    let mut lines=text.lines();
    if lines.next()!=Some(header) { return Err(format!("{name}: exact header required")); }
    let n=header.split('\t').count();
    lines.enumerate().map(|(i,l)| {
        let f:Vec<_>=l.split('\t').map(str::to_string).collect();
        if f.len()!=n || l.contains('\r') || f.iter().any(|s|s.trim().is_empty()) {
            return Err(format!("{name}: invalid row {}",i+2));
        }
        Ok(f)
    }).collect()
}
fn num<T:std::str::FromStr>(s:&str)->Result<T,String> { s.parse().map_err(|_|format!("invalid numeric field {s}")) }
fn sources(dir:&Path,name:&str) -> Result<Vec<SourcePair>,String> {
    rows(dir,name,"left_gid\tright_gid\tkern_u\tevidence")?.iter().map(|r| Ok(SourcePair {
        left:num(&r[0])?,right:num(&r[1])?,kern:num(&r[2])?,evidence:r[3].clone(),
    })).collect()
}
fn legacy(dir:&Path,name:&str,width:usize)->Result<String,String> {
    let s=fs::read_to_string(dir.join(name)).map_err(|e|e.to_string())?;
    if s.lines().filter(|l|!l.starts_with('#') && !l.trim().is_empty()).any(|l|l.split('\t').count()!=width) {
        return Err(format!("{name}: invalid row width"));
    }
    Ok(s)
}
#[derive(Debug)]
enum CallerError { Binding(String), Pin(String), Input(String) }
impl std::fmt::Display for CallerError {
    fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result {
        match self { Self::Binding(s)=>write!(f,"Binding: {s}"), Self::Pin(s)=>write!(f,"Pin: {s}"), Self::Input(s)=>write!(f,"Input: {s}") }
    }
}
fn validate_pins(input:&Path)->Result<(),CallerError> {
    let expected=["binding.tsv","glyph_ids.tsv","classes.tsv","targets.tsv","walls.tsv","wall_evidence.tsv",
        "resolved_source.tsv","training_anchors.tsv","independent_holdouts.tsv","verifications.tsv","learning_source_manifest.tsv","evidence_bindings.tsv"];
    let records=rows(input,"pins.tsv","file\tsha256").map_err(CallerError::Pin)?;
    let mut pins=BTreeMap::new();
    for r in records {
        if !expected.contains(&r[0].as_str()) || pins.insert(r[0].clone(),r[1].clone()).is_some() {
            return Err(CallerError::Pin("unknown/duplicate pin filename".into()));
        }
    }
    for n in expected {
        let pin=pins.get(n).ok_or_else(||CallerError::Pin(format!("missing {n}")))?;
        let bytes=fs::read(input.join(n)).map_err(|e|CallerError::Pin(e.to_string()))?;
        let got=kni_learning::sha256::sha256_hex(&bytes);
        if &got!=pin { return Err(CallerError::Pin(format!("hash mismatch {n}"))); }
    }
    Ok(())
}
fn validate_roles(input:&Path)->Result<(),CallerError> {
    let bindings=rows(input,"binding.tsv","font_revision\tmodel_revision\tcontext\tdataset_kind").map_err(CallerError::Binding)?;
    if bindings.len()!=1 { return Err(CallerError::Binding("exactly one binding required".into())); }
    let binding=&bindings[0];
    let sources=rows(input,"learning_source_manifest.tsv","font_id\trole\tsha256\tlicense_id").map_err(CallerError::Binding)?;
    let mut seen=BTreeSet::new();
    let mut matching=false;
    for r in sources {
        if !seen.insert(r[0].clone()) { return Err(CallerError::Binding("duplicate or mixed-role font".into())); }
        if !matches!(r[1].as_str(),"learning"|"held-out") || r[2].len()!=64 || !r[2].bytes().all(|c|c.is_ascii_hexdigit()) {
            return Err(CallerError::Binding("invalid source role/pin".into()));
        }
        if r[0]==binding[0] || r[2]==binding[0] {
            if r[1]!="learning" { return Err(CallerError::Binding("held-out font present in calibration".into())); }
            matching=true;
        }
    }
    if !matching { return Err(CallerError::Binding("calibration font has no learning source binding".into())); }
    let evidence=rows(input,"evidence_bindings.tsv","file\tfont_revision\tmodel_revision\tcontext").map_err(CallerError::Binding)?;
    let required=["training_anchors.tsv","independent_holdouts.tsv","verifications.tsv","resolved_source.tsv","wall_evidence.tsv"];
    let mut bound=BTreeSet::new();
    for r in evidence {
        if !required.contains(&r[0].as_str()) || !bound.insert(r[0].clone()) || r[1]!=binding[0] || r[2]!=binding[1] || r[3]!=binding[2] {
            return Err(CallerError::Binding("evidence font/model/context mismatch or duplicate".into()));
        }
    }
    if bound.len()!=required.len() { return Err(CallerError::Binding("missing exact evidence binding".into())); }
    Ok(())
}
fn run(input:&Path,output:&Path)->Result<(),String> {
    if output.exists() { return Err("output directory already exists; refusing overwrite".into()); }
    let b=rows(input,"binding.tsv","font_revision\tmodel_revision\tcontext\tdataset_kind")?;
    if b.len()!=1 { return Err("exactly one binding required".into()); }
    let binding=Binding { font_revision:b[0][0].clone(),model_revision:b[0][1].clone(),context:b[0][2].clone() };
    let kind=&b[0][3];
    if !matches!(kind.as_str(),"SYNTHETIC"|"REAL_UNCERTIFIED"|"REAL_CERTIFIED") { return Err("unknown dataset kind".into()); }
    // REAL_CERTIFIED is an upstream claim, not certified by this caller.
    let mut ids=BTreeMap::new();
    for r in rows(input,"glyph_ids.tsv","glyph\tgid")? {
        if ids.insert(r[0].clone(),num::<u16>(&r[1])?).is_some() { return Err("duplicate glyph mapping".into()); }
    }
    let (glyphs,knowledge)=parse_classes(&legacy(input,"classes.tsv",5)?)?;
    let targets=parse_targets(&legacy(input,"targets.tsv",6)?)?;
    let walls=parse_walls(&legacy(input,"walls.tsv",5)?)?;
    let source=sources(input,"resolved_source.tsv")?;
    let anchors=sources(input,"training_anchors.tsv")?;
    let holdouts:Vec<_>=rows(input,"independent_holdouts.tsv","left_gid\tright_gid\tabsolute_error_u\tmeasurement_uncertainty_u\tevidence")?.iter().map(|r| Ok(Holdout {
        left:num(&r[0])?,right:num(&r[1])?,absolute_error:num(&r[2])?,measurement_uncertainty:num(&r[3])?,evidence:r[4].clone(),
    })).collect::<Result<_,String>>()?;
    let verifications:Vec<_>=rows(input,"verifications.tsv","left_gid\tright_gid\tkern_u\tresidual_u\tuncertainty_u\tuncertainty_evidence\toptical_evidence\tfull_geometry_evidence")?.iter().map(|r| Ok(Verification {
        binding:binding.clone(),left:num(&r[0])?,right:num(&r[1])?,kern:num(&r[2])?,measured_residual:num(&r[3])?,calibrated_uncertainty:num(&r[4])?,
        uncertainty_evidence:r[5].clone(),optical_evidence:r[6].clone(),full_geometry_evidence:r[7].clone(),
    })).collect::<Result<_,String>>()?;
    let inp=GenerationInputs { glyphs,knowledge,targets,walls,existing:HashMap::new(),restore:vec![] };
    let policy=Calibration::fit(binding.clone(),&anchors,&holdouts)?;
    let mut table=generate(&binding,&inp,&ids,&source,&policy,&verifications)?;
    let mut verified_walls=BTreeSet::new();
    for r in rows(input,"wall_evidence.tsv","gid\tfont_revision\tevidence")? {
        let id=num::<u16>(&r[0])?;
        if r[1]!=binding.font_revision || !ids.values().any(|v|*v==id) || !verified_walls.insert(id) {
            return Err("wall evidence revision/ID mismatch or duplicate".into());
        }
        let name=ids.iter().find(|(_,v)|**v==id).map(|(n,_)|n).unwrap();
        if !inp.walls.get(name).map_or(false,|w|!w.rows.is_empty()) {
            return Err("verified wall evidence without wall geometry".into());
        }
    }
    table.require_verified_walls(&verified_walls);
    let exact_targets=table.verified_targets()?;
    let gpos=gpos_verified::write(&exact_targets)?;
    let mut targets=String::from("left_gid\tright_gid\tkern_u\tlocked\n");
    for t in exact_targets { targets.push_str(&format!("{}\t{}\t{}\ttrue\n",t.left,t.right,t.kern)); }
    let (lo,hi)=policy.signed_envelope();
    let cal=format!("field\tvalue\tderivation\nnoise_floor_u\t{}\tmax-heldout-error-or-uncertainty\nlower_u\t{lo}\tmin-source-anchor\nupper_u\t{hi}\tmax-source-anchor\n",policy.noise_floor());
    let mut meta=String::from("field\tvalue\n");
    for (k,v) in [("font_revision",table.binding.font_revision.as_str()),("model_revision",table.binding.model_revision.as_str()),("context",table.binding.context.as_str()),("dataset_kind",kind.as_str())] { meta.push_str(&format!("{k}\t{v}\n")); }
    meta.push_str("claim\tmechanics-only-not-optical-or-real-font-certification\n");
    // Force provenance fields into output, rather than silencing unused warnings.
    for e in table.calibration.anchor_evidence() { meta.push_str(&format!("anchor_evidence\t{e}\n")); }
    for e in table.calibration.holdout_evidence() { meta.push_str(&format!("holdout_evidence\t{e}\n")); }
    fs::create_dir(output).map_err(|e|e.to_string())?;
    for (name,text) in [("concrete-pairs.tsv",table.to_tsv()),("verified-pairs.tsv",targets),("calibration.tsv",cal),("metadata.tsv",meta)] {
        fs::write(output.join(name),text).map_err(|e|format!("{name}: {e}"))?;
    }
    fs::write(output.join("verification.gpos"),gpos).map_err(|e|e.to_string())?;
    println!("dataset_kind={kind} concrete_rows={} verification=mechanics-only",table.rows().len());
    Ok(())
}
fn main() {
    let args:Vec<_>=std::env::args_os().collect();
    let result:Result<(),CallerError>=if args.len()==3 {
        let input=Path::new(&args[1]);
        validate_pins(input).and_then(|_|validate_roles(input)).and_then(|_|run(input,Path::new(&args[2])).map_err(CallerError::Input))
    } else {Err(CallerError::Input("usage: kern_production INPUT_DIR NEW_OUTPUT_DIR".into()))};
    if let Err(e)=result { eprintln!("kern_production: {e}"); std::process::exit(1); }
}
