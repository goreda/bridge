//! Measurement harness (development list #2): duplicate pairs in shipped stage-1 rings.
//! Reads a pipeline stage1-cache.txt, audits every shipped glyph with
//! audit_duplicate_points (BEFORE), applies tidy_duplicate_points (AFTER) and prints
//! per-glyph and total counts. Detection + cleanup measurement only; the cache is
//! read, never written. Usage: duplicate_tidy_stage1 <stage1-cache.txt> [--rows]
use kni_core::duplicate_point_audit::{audit_duplicate_points,tidy_duplicate_points};
use kni_core::reference_slice::{DrawnGlyph,Point,ReferenceRing,Span};

fn bits(s:&str)->Result<f64,String>{u64::from_str_radix(s,16).map(f64::from_bits).map_err(|e|format!("bad hex bits {s:?}: {e}"))}

fn parse(cache:&str)->Result<Vec<DrawnGlyph>,String>{
    let mut glyphs:Vec<DrawnGlyph>=Vec::new();
    // section: 0 = none, 1 = shipped rings, 2 = measurement rings (skipped)
    let mut section=0u8;
    for line in cache.lines(){
        let f:Vec<&str>=line.split('\t').collect();
        match f[0]{
            "glyph"=>{
                // ring blocks open with a png_sha256 field; a second glyph row
                // carrying source_pin is the per-glyph receipt summary, not rings
                if f.get(4)==Some(&"png_sha256"){
                    let name=f.get(1).ok_or("glyph row without name")?.to_string();
                    glyphs.push(DrawnGlyph{glyph_id:name,rings:vec![]});
                    section=0;
                }
            }
            "ring"=>{
                if f.len()!=4{return Err(format!("malformed ring row: {line:?}"));}
                let start=Point{x:bits(f[1])?,y:bits(f[2])?};
                let n:usize=f[3].parse().map_err(|e|format!("bad span count: {e}"))?;
                let g=glyphs.last_mut().ok_or("ring before glyph")?;
                g.rings.push(ReferenceRing{start,spans:Vec::with_capacity(n)});
                section=1;
            }
            "mring"=>{section=2;}
            "L"=>{
                if section==1{
                    if f.len()!=3{return Err(format!("malformed L row: {line:?}"));}
                    let g=glyphs.last_mut().ok_or("span before glyph")?;
                    let r=g.rings.last_mut().ok_or("span before ring")?;
                    r.spans.push(Span::Line{end:Point{x:bits(f[1])?,y:bits(f[2])?}});
                }
            }
            "C"=>{
                if section==1{
                    if f.len()!=7{return Err(format!("malformed C row: {line:?}"));}
                    let g=glyphs.last_mut().ok_or("span before glyph")?;
                    let r=g.rings.last_mut().ok_or("span before ring")?;
                    r.spans.push(Span::Cubic{control_one:Point{x:bits(f[1])?,y:bits(f[2])?},control_two:Point{x:bits(f[3])?,y:bits(f[4])?},end:Point{x:bits(f[5])?,y:bits(f[6])?}});
                }
            }
            "receipt_lines"|"end"=>{section=0;}
            _=>{}
        }
    }
    Ok(glyphs)
}

fn main()->Result<(),String>{
    let mut args=std::env::args().skip(1);
    let path=args.next().ok_or("usage: duplicate_tidy_stage1 <stage1-cache.txt> [--rows]")?;
    let rows=args.any(|a|a=="--rows");
    let cache=std::fs::read_to_string(&path).map_err(|e|format!("read {path}: {e}"))?;
    let glyphs=parse(&cache)?;
    let mut total_before=0usize;let mut total_after=0usize;let mut glyphs_with=0usize;let mut removed=0usize;
    let mut sum_closure=0usize;let mut sum_nonclosure=0usize;let mut sum_consecutive=0usize;let mut sum_on_on=0usize;let mut sum_on_off=0usize;let mut sum_off_off=0usize;let mut sum_same=0usize;let mut sum_diff=0usize;
    for g in &glyphs{
        let before=audit_duplicate_points(g).map_err(|e|format!("audit {}: {e:?}",g.glyph_id))?;
        let (_cleaned,report)=tidy_duplicate_points(g).map_err(|e|format!("tidy {}: {e:?}",g.glyph_id))?;
        if before.pair_count>0{
            glyphs_with+=1;
            if rows{
                println!("glyph\t{}\tpairs_before\t{}\tpairs_after\t{}\tremoved\t{}\tclosure_pairs\t{}\tnonclosure_before\t{}",
                    g.glyph_id,before.pair_count,report.remaining.pair_count,report.removals.len(),
                    before.explicit_closure_pairs,before.nonclosure_pairs);
            }
        }
        if rows{for line in report.ledger_rows(&g.glyph_id).lines().filter(|l|l.starts_with("tidy\t")){println!("{line}");}}
        sum_closure+=before.explicit_closure_pairs;sum_nonclosure+=before.nonclosure_pairs;sum_consecutive+=before.consecutive;
        sum_on_on+=before.on_on;sum_on_off+=before.on_off;sum_off_off+=before.off_off;sum_same+=before.same_contour;sum_diff+=before.different_contour;
        total_before+=before.pair_count;
        total_after+=report.remaining.pair_count;
        removed+=report.removals.len();
    }
    println!("duplicate-tidy-stage1\tglyphs\t{}\tglyphs_with_pairs\t{}\tpairs_before\t{}\tpairs_after\t{}\tspans_removed\t{}",
        glyphs.len(),glyphs_with,total_before,total_after,removed);
    println!("breakdown-before\texplicit_closure\t{}\tnonclosure\t{}\tconsecutive\t{}\tsame_contour\t{}\tdifferent_contour\t{}\ton_on\t{}\ton_off\t{}\toff_off\t{}",
        sum_closure,sum_nonclosure,sum_consecutive,sum_same,sum_diff,sum_on_on,sum_on_off,sum_off_off);
    Ok(())
}
