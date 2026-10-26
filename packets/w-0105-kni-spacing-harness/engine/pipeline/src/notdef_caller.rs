//! Bounded pinned capture context and a plain CP -> (path, SHA) population.
//! All captured CPs remain inputs. No supported/cmap/absence/exclusion gate.
use crate::bound_detector_validator::{self as validator, BadNotdef, CoreBoundedDecoder,
    DetectionState, EvidenceBinding, PixelPopulation, ValidationLimits};
use kni_core::{cff_reader::sha256_hex, jpeg_source::Limits, scale_context::ScaleContext};
use std::{collections::{BTreeMap,BTreeSet},io::Read,path::{Component,Path,PathBuf}};
fn within(root:&Path,path:&Path)->Result<PathBuf,BadNotdef>{
    if path.components().any(|c|matches!(c,Component::ParentDir)){return Err(BadNotdef::ContextMismatch);}
    let path=if path.is_absolute(){path.to_path_buf()}else{root.join(path)};
    let path=path.canonicalize().map_err(|_|BadNotdef::Io)?;
    if !path.starts_with(root){return Err(BadNotdef::ContextMismatch);} Ok(path)
}
fn pinned(path:&Path,pin:&str,cap:usize,budget:&mut usize)->Result<Vec<u8>,BadNotdef>{
    if pin.len()!=64 || !pin.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b)){return Err(BadNotdef::Grammar);}
    let mut file=std::fs::File::open(path).map_err(|_|BadNotdef::Io)?;
    if !file.metadata().map_err(|_|BadNotdef::Io)?.is_file(){return Err(BadNotdef::Io);}
    let mut bytes=Vec::new();let mut chunk=[0u8;8192];
    loop{let n=file.read(&mut chunk).map_err(|_|BadNotdef::Io)?;if n==0{break;}
        let length=bytes.len().checked_add(n).ok_or(BadNotdef::ResourceLimit)?;
        if length>cap{return Err(BadNotdef::ResourceLimit);}
        *budget=budget.checked_sub(n.checked_mul(3).ok_or(BadNotdef::ResourceLimit)?).ok_or(BadNotdef::ResourceLimit)?;
        bytes.try_reserve_exact(n).map_err(|_|BadNotdef::ResourceLimit)?;bytes.extend_from_slice(&chunk[..n]);}
    *budget=budget.checked_sub(128).ok_or(BadNotdef::ResourceLimit)?;
    if sha256_hex(&bytes)!=pin{return Err(BadNotdef::ShaMismatch);}Ok(bytes)
}
#[allow(clippy::too_many_arguments)]
pub fn load(evidence:Option<&EvidenceBinding>,capture:Option<(&Path,&str)>,root:&Path,style:&str,
    scale:&ScaleContext,_supported:&BTreeSet<u32>,_required_sources:&[(u32,PathBuf)],image_limits:Limits)
    ->Result<DetectionState,BadNotdef>{
    let Some(evidence)=evidence else{return Ok(DetectionState::MissingPixelEvidence)};
    let (capture_path,capture_sha)=capture.ok_or(BadNotdef::MissingPixelEvidence)?;
    if evidence.style!=style || evidence.capture!=capture_sha || evidence.frame!=scale.frame_binding()
        || evidence.scale.to_bits()!=scale.units_per_px().to_bits(){return Err(BadNotdef::ContextMismatch);}
    let root=root.canonicalize().map_err(|_|BadNotdef::Io)?;
    let path=within(&root,capture_path)?;
    let mut left=image_limits.max_working_bytes;
    let bytes=pinned(&path,capture_sha,image_limits.max_input_bytes,&mut left)?;
    let text=std::str::from_utf8(&bytes).map_err(|_|BadNotdef::Grammar)?;
    let mut lines=text.lines();
    if lines.next()!=Some("kni-capture-manifest\tv1"){return Err(BadNotdef::Grammar);}
    let mut context=BTreeMap::new();let mut population=PixelPopulation::new();
    for (row,line) in lines.enumerate(){
        if row>=131_072{return Err(BadNotdef::ResourceLimit);}
        if line.split('\t').take(5).count()>4{return Err(BadNotdef::Grammar);}
        let f:Vec<_>=line.split('\t').collect();
        match f.as_slice(){
            [key,value] if ["style","cohort","frame"].contains(key)=>{
                if context.insert(*key,*value).is_some(){return Err(BadNotdef::Duplicate);}
            }
            ["source",cp,path,pin]=>{
                if population.len()>=65_535{return Err(BadNotdef::ResourceLimit);}
                let scalar=u32::from_str_radix(cp.strip_prefix("0x").unwrap_or(cp),16).map_err(|_|BadNotdef::Grammar)?;
                validator::validate_codepoint(scalar)?;
                if Path::new(path).is_absolute(){return Err(BadNotdef::ContextMismatch);}
                let path=within(&root,Path::new(path))?;
                left=left.checked_sub(path.as_os_str().len().checked_add(256).ok_or(BadNotdef::ResourceLimit)?).ok_or(BadNotdef::ResourceLimit)?;
                if population.insert(scalar,(path,(*pin).into())).is_some(){return Err(BadNotdef::Duplicate);}
            }
            _=>return Err(BadNotdef::Grammar),
        }
    }
    if context.get("style")!=Some(&style)||context.get("cohort")!=Some(&scale.cohort())
        ||context.get("frame")!=Some(&scale.frame_binding()){return Err(BadNotdef::ContextMismatch);}
    validator::load(evidence,&population,scale,&root,ValidationLimits{image:image_limits,
        max_record_bytes:image_limits.max_input_bytes,max_record_rows:131_072,max_witnesses:65_535,
        max_aggregate_working_bytes:left},&CoreBoundedDecoder)
}
