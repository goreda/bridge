//! Verification-only exact GPOS lane. OpenType PairPos Format 1, VF2=0.
//! CONVENTION: binary format counts/offsets, not artistic thresholds.
//! Legacy gpos.rs is NOT used here: its nonzero VF2, unsorted second-glyph
//! records and unchecked casts remain a separate unresolved production risk.
//! No class matrix: unlisted pairs remain absent, explicit zeros stay present.
use crate::export_gpos::PairTarget;
use std::collections::BTreeMap;
fn word(out:&mut Vec<u8>,v:u16) {out.extend_from_slice(&v.to_be_bytes());}
fn offset(v:usize)->Result<u16,String>{u16::try_from(v).map_err(|_|"GPOS Offset16/count overflow".into())}

/// Exact locked targets only. Sorting is internal; duplicate keys are errors.
/// Offset overflow is refused, not silently wrapped or auto-split.
pub fn write(targets:&[PairTarget])->Result<Vec<u8>,String>{
    let mut groups:BTreeMap<u16,BTreeMap<u16,i16>>=BTreeMap::new();
    for t in targets {
        if !t.locked {return Err("verification writer requires exact locked targets".into());}
        let v=i16::try_from(t.kern).map_err(|_|"kern outside OpenType int16")?;
        if groups.entry(t.left).or_default().insert(t.right,v).is_some(){return Err("duplicate concrete pair".into());}
    }
    let n=offset(groups.len())?;
    let header=10+2*groups.len();
    let mut sets=Vec::new();let mut offsets=Vec::new();
    for recs in groups.values(){
        offsets.push(offset(header+sets.len())?);
        word(&mut sets,offset(recs.len())?);
        for (&r,&v) in recs {word(&mut sets,r);sets.extend_from_slice(&v.to_be_bytes());}
    }
    let covoff=offset(header+sets.len())?;
    let mut sub=Vec::new();
    for v in [1,covoff,4,0,n]{word(&mut sub,v);}
    for o in offsets {word(&mut sub,o);}
    sub.extend_from_slice(&sets);
    word(&mut sub,1);word(&mut sub,n);
    for &l in groups.keys(){word(&mut sub,l);}
    // One DFLT script / default LangSys / kern feature / PairPos lookup.
    let mut script=Vec::new();
    word(&mut script,1);script.extend_from_slice(b"DFLT");word(&mut script,8);
    for v in [4,0,0,0xffff,1,0]{word(&mut script,v);}
    let mut feature=Vec::new();
    word(&mut feature,1);feature.extend_from_slice(b"kern");word(&mut feature,8);
    for v in [0,1,0]{word(&mut feature,v);}
    let mut lookups=Vec::new();
    for v in [1,4,2,0,1,8]{word(&mut lookups,v);}
    lookups.extend_from_slice(&sub);
    let mut out=vec![0,1,0,0];
    for o in [10,10+script.len(),10+script.len()+feature.len()] {word(&mut out,offset(o)?);}
    out.extend_from_slice(&script);out.extend_from_slice(&feature);out.extend_from_slice(&lookups);
    Ok(out)
}
