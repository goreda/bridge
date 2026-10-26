//! Unhinted integer-domain CFF1/OTTO writer, independent validation NOT_RUN.
//! Cubics are retained, no quadratic conversion or silent quantization.
use crate::reference_slice::{DrawnGlyph,Point,Span};
use std::collections::BTreeMap;

#[derive(Clone, Debug)]
pub enum ContainerError { UnrepresentableCoordinate,OpenContour,InvalidName,TooManyGlyphs,MissingTable,DuplicateTable,InvalidHead,InvalidGlyphOrder,SizeOverflow,InvalidMetadata }
#[derive(Clone, Debug)]
pub struct CffGlyph { pub name:String,pub advance:u16,pub outline:DrawnGlyph }

/// Maps the shared ink-bounds error onto container errors: coordinate-domain
/// failures are UnrepresentableCoordinate, ring-shape failures OpenContour
/// (the same variants charstring uses for those conditions).
fn ink_err(e:crate::ink_bounds::InkError)->ContainerError{match e{crate::ink_bounds::InkError::NonFinite|crate::ink_bounds::InkError::OutOfI16=>ContainerError::UnrepresentableCoordinate,crate::ink_bounds::InkError::OpenRing|crate::ink_bounds::InkError::EmptyRing=>ContainerError::OpenContour}}
fn number(v:f64,out:&mut Vec<u8>)->Result<(),ContainerError> {
    if !v.is_finite()||v.fract()!=0.0||v< -32768.0||v>32767.0 {return Err(ContainerError::UnrepresentableCoordinate);}
    out.push(28);out.extend_from_slice(&(v as i16).to_be_bytes());Ok(())
}
fn delta(a:Point,b:Point,out:&mut Vec<u8>)->Result<(),ContainerError> {number(b.x-a.x,out)?;number(b.y-a.y,out)}
pub fn charstring(g:&CffGlyph)->Result<Vec<u8>,ContainerError> {
    let mut out=Vec::new();number(g.advance as f64,&mut out)?;
    for ring in &g.outline.rings {number(ring.start.x,&mut Vec::new())?;number(ring.start.y,&mut Vec::new())?;for span in &ring.spans {let points=match span {Span::Line{end}=>vec![*end],Span::Cubic{control_one,control_two,end}=>vec![*control_one,*control_two,*end]};for p in points {number(p.x,&mut Vec::new())?;number(p.y,&mut Vec::new())?;}}}
    let mut current=Point{x:0.,y:0.};
    for ring in &g.outline.rings {
        if ring.spans.is_empty(){return Err(ContainerError::OpenContour);}
        delta(current,ring.start,&mut out)?;out.push(21);current=ring.start;
        for span in &ring.spans {match span {
            Span::Line{end}=>{delta(current,*end,&mut out)?;out.push(5);current=*end;},
            Span::Cubic{control_one,control_two,end}=>{delta(current,*control_one,&mut out)?;delta(*control_one,*control_two,&mut out)?;delta(*control_two,*end,&mut out)?;out.push(8);current=*end;}
        }}
        if current!=ring.start{return Err(ContainerError::OpenContour);}
    }
    out.push(14);Ok(out)
}
fn index(objects:&[Vec<u8>])->Result<Vec<u8>,ContainerError> {
    let count=u16::try_from(objects.len()).map_err(|_|ContainerError::TooManyGlyphs)?;
    let mut out=count.to_be_bytes().to_vec();if count==0{return Ok(out);}
    out.push(4);let mut offset=1u32;out.extend_from_slice(&offset.to_be_bytes());
    for object in objects {offset=offset.checked_add(u32::try_from(object.len()).map_err(|_|ContainerError::SizeOverflow)?).ok_or(ContainerError::SizeOverflow)?;out.extend_from_slice(&offset.to_be_bytes());}
    for object in objects{out.extend_from_slice(object);}Ok(out)
}
fn dict_integer(v:u32,out:&mut Vec<u8>){out.push(29);out.extend_from_slice(&v.to_be_bytes());}
fn top_dict(charset:u32,strings:u32,private:u32,bounds:[i16;4])->Vec<u8>{
    let mut out=vec![141,12,6]; // Explicit CharstringType 2.
    for b in bounds{out.push(28);out.extend_from_slice(&b.to_be_bytes());}out.push(5);
    dict_integer(charset,&mut out);out.push(15);
    dict_integer(strings,&mut out);out.push(17);
    dict_integer(0,&mut out);dict_integer(private,&mut out);out.push(18);out
}
/// Initial exact subset uses 1000-unit coordinates and integer Type2 operands.
/// Caller must bind this frame; FontMatrix default is 0.001, no scale inference.
pub fn cff_one(postscript_name:&str,glyphs:&[CffGlyph])->Result<Vec<u8>,ContainerError>{
    cff_one_jobs(postscript_name,glyphs,1)
}
/// Jobs-aware variant (P2-PAR, the W14 pattern): per-glyph charstring +
/// ink-bounds jobs are pure; outcomes are collected indexed and folded in
/// glyph order, so the emitted CFF bytes equal the serial loop at any job
/// count (oracle-tested in this file). The first error in glyph order wins,
/// exactly like the serial early-`?`. jobs == 1 runs inline on the calling
/// thread; jobs > 1 uses scoped std threads (kni-core carries no rayon).
pub fn cff_one_jobs(postscript_name:&str,glyphs:&[CffGlyph],jobs:usize)->Result<Vec<u8>,ContainerError>{
    if postscript_name.is_empty()||!postscript_name.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'-'){return Err(ContainerError::InvalidName);}
    if glyphs.is_empty()||glyphs[0].name!=".notdef"{return Err(ContainerError::InvalidGlyphOrder);}
    if postscript_name.len()>63{return Err(ContainerError::InvalidName);}
    let work=|g:&CffGlyph|->Result<(Vec<u8>,Option<[i16;4]>),ContainerError>{
        let cs=charstring(g)?;
        let b=crate::ink_bounds::integer_outward_bounds(&g.outline).map_err(ink_err)?;
        Ok((cs,b))
    };
    let n=glyphs.len();
    let results:Vec<Result<(Vec<u8>,Option<[i16;4]>),ContainerError>>=if jobs<=1||n<=1{
        glyphs.iter().map(work).collect()
    }else{
        let w=jobs.min(n);
        let chunk=n.div_ceil(w);
        let mut slots:Vec<Option<Result<(Vec<u8>,Option<[i16;4]>),ContainerError>>>=Vec::new();
        slots.resize_with(n,||None);
        std::thread::scope(|s|{
            let mut guards=Vec::new();
            for (ci,slot_chunk) in slots.chunks_mut(chunk).enumerate(){
                let glyph_chunk=&glyphs[ci*chunk..ci*chunk+slot_chunk.len()];
                let work=&work;
                guards.push(s.spawn(move||{
                    for (slot,g) in slot_chunk.iter_mut().zip(glyph_chunk){*slot=Some(work(g));}
                }));
            }
            for g in guards{g.join().expect("cff worker thread panicked");}
        });
        slots.into_iter().map(|s|s.expect("cff reduce: glyph job slot empty (incomplete coverage)")).collect()
    };
    // Ordered reduce: the first error in glyph order wins (the serial
    // early-`?`); charstring bytes and bounds fold in glyph order.
    let mut bounds=None::<[i16;4]>;
    let mut charstrings=Vec::with_capacity(n);
    for r in results{let (cs,b)=r?;charstrings.push(cs);bounds=crate::ink_bounds::union_bounds(bounds,b);}
    let bounds=bounds.unwrap_or([0;4]);
    let mut seen_names=std::collections::BTreeSet::new();if glyphs.iter().any(|g|!seen_names.insert(&g.name)){return Err(ContainerError::InvalidName);}
    let name=index(&[postscript_name.as_bytes().to_vec()])?;
    let mut names=Vec::new();let mut charset=vec![0];
    for (i,g) in glyphs.iter().enumerate().skip(1){
        if g.name.is_empty()||!g.name.bytes().all(|b|b.is_ascii_alphanumeric()||b==b'.'||b==b'_'){return Err(ContainerError::InvalidName);}
        let sid=u16::try_from(390usize+i).map_err(|_|ContainerError::TooManyGlyphs)?;
        charset.extend_from_slice(&sid.to_be_bytes());names.push(g.name.as_bytes().to_vec());
    }
    let strings=index(&names)?;let subrs=vec![0,0];
    let chars=index(&charstrings)?;
    let provisional=index(&[top_dict(0,0,0,bounds)])?;
    let charset_offset=u32::try_from(4+name.len()+provisional.len()+strings.len()+subrs.len()).map_err(|_|ContainerError::SizeOverflow)?;
    let chars_offset=charset_offset.checked_add(charset.len() as u32).ok_or(ContainerError::SizeOverflow)?;
    let private_offset=chars_offset.checked_add(u32::try_from(chars.len()).map_err(|_|ContainerError::SizeOverflow)?).ok_or(ContainerError::SizeOverflow)?;
    if private_offset>i32::MAX as u32{return Err(ContainerError::SizeOverflow);}
    let top=index(&[top_dict(charset_offset,chars_offset,private_offset,bounds)])?;
    let mut out=vec![1,0,4,4];out.extend(name);out.extend(top);out.extend(strings);out.extend(subrs);out.extend(charset);out.extend(chars);Ok(out)
}
pub fn maxp_cff(count:u16)->Vec<u8>{let mut out=vec![0,0,0x50,0];out.extend_from_slice(&count.to_be_bytes());out}
pub fn hmtx(metrics:&[(u16,i16)])->Vec<u8>{let mut out=Vec::new();for(a,l)in metrics{out.extend_from_slice(&a.to_be_bytes());out.extend_from_slice(&l.to_be_bytes());}out}
pub fn checksum(bytes:&[u8])->u32{bytes.chunks(4).fold(0u32,|sum,chunk|{let mut word=[0;4];word[..chunk.len()].copy_from_slice(chunk);sum.wrapping_add(u32::from_be_bytes(word))})}

/// Caller supplies independently constructed/validated support-table bytes.
/// Mandatory OS/2 included; presence is not semantic cross-table validation.
pub fn assemble_otto(tables:Vec<([u8;4],Vec<u8>)>)->Result<Vec<u8>,ContainerError>{
    let mut sorted=BTreeMap::new();for(tag,data)in tables{if sorted.insert(tag,data).is_some(){return Err(ContainerError::DuplicateTable);}}
    for tag in [*b"CFF ",*b"cmap",*b"head",*b"hhea",*b"hmtx",*b"maxp",*b"name",*b"OS/2",*b"post"] {if !sorted.contains_key(&tag){return Err(ContainerError::MissingTable);}}
    let head=sorted.get_mut(b"head").ok_or(ContainerError::MissingTable)?;if head.len()!=54{return Err(ContainerError::InvalidHead);}head[8..12].fill(0);
    let count=u16::try_from(sorted.len()).map_err(|_|ContainerError::SizeOverflow)?;if count>4095{return Err(ContainerError::SizeOverflow);}let power=1u16<<(15-count.leading_zeros());
    let mut out=b"OTTO".to_vec();out.extend_from_slice(&count.to_be_bytes());out.extend_from_slice(&(power*16).to_be_bytes());out.extend_from_slice(&(15-count.leading_zeros() as u16).to_be_bytes());out.extend_from_slice(&(count*16-power*16).to_be_bytes());
    let mut offset=12usize+16*sorted.len();let mut payload=Vec::new();let mut head_offset=0;
    for(tag,data)in sorted{if tag==*b"head"{head_offset=offset;}out.extend_from_slice(&tag);out.extend_from_slice(&checksum(&data).to_be_bytes());out.extend_from_slice(&u32::try_from(offset).map_err(|_|ContainerError::SizeOverflow)?.to_be_bytes());out.extend_from_slice(&u32::try_from(data.len()).map_err(|_|ContainerError::SizeOverflow)?.to_be_bytes());payload.extend_from_slice(&data);while payload.len()%4!=0{payload.push(0);}offset=12+16*count as usize+payload.len();}
    out.extend(payload);let adjustment=0xb1b0afbAu32.wrapping_sub(checksum(&out));out[head_offset+8..head_offset+12].copy_from_slice(&adjustment.to_be_bytes());Ok(out)
}

#[cfg(test)]
mod par_tests {
    use super::*;
    use crate::reference_slice::{DrawnGlyph,Point,ReferenceRing,Span};

    fn p(x:f64,y:f64)->Point{Point{x,y}}
    fn rect(x0:f64,y0:f64,x1:f64,y1:f64)->ReferenceRing{
        ReferenceRing{start:p(x0,y0),spans:vec![
            Span::Line{end:p(x1,y0)},Span::Line{end:p(x1,y1)},
            Span::Line{end:p(x0,y1)},Span::Line{end:p(x0,y0)}]}
    }
    fn glyph(name:&str,i:usize)->CffGlyph{
        let o=i as f64*10.0;
        let mut rings=vec![rect(o,0.0,o+100.0,300.0+o)];
        if i%2==1{rings.push(ReferenceRing{start:p(o+200.0,0.0),spans:vec![
            Span::Cubic{control_one:p(o+250.0,100.0),control_two:p(o+250.0,200.0),end:p(o+200.0,300.0)},
            Span::Line{end:p(o+200.0,0.0)}]});}
        CffGlyph{name:name.into(),advance:600,outline:DrawnGlyph{glyph_id:name.into(),rings}}
    }
    fn fixture()->Vec<CffGlyph>{
        let mut v=vec![glyph(".notdef",0)];
        for i in 1..8{v.push(glyph(&format!("G{i}"),i));}
        v
    }

    /// Full CFF byte equality between the serial entry point and every job
    /// count (the serial cff_one body is the oracle: it IS the jobs=1 call).
    #[test]
    fn cff_one_jobs_is_byte_identical_at_1_2_4_8(){
        let g=fixture();
        let want=cff_one_jobs("Test-Font",&g,1).unwrap();
        assert!(!want.is_empty());
        for jobs in [2usize,4,8]{
            let got=cff_one_jobs("Test-Font",&g,jobs).unwrap();
            assert_eq!(got,want,"CFF bytes, jobs={jobs}");
        }
    }

    /// The first error in glyph order wins at any job count (serial early-?).
    #[test]
    fn first_error_in_glyph_order_wins(){
        let mut g=fixture();
        // glyph 2: open contour (ring not closed); glyph 4: unrepresentable coordinate.
        g[2].outline.rings[0].spans.pop();
        g[4].outline.rings[0].spans.push(Span::Line{end:p(1.5,0.0)});
        for jobs in [1usize,2,8]{
            let e=cff_one_jobs("Test-Font",&g,jobs).unwrap_err();
            assert!(matches!(e,ContainerError::OpenContour),"jobs={jobs}: {e:?}");
        }
    }

    /// Edge cases: single glyph and two glyphs with more jobs than glyphs.
    #[test]
    fn short_glyph_lists_are_identical(){
        for n in [1usize,2]{
            let g=fixture()[..n].to_vec();
            let want=cff_one_jobs("Test-Font",&g,1).unwrap();
            for jobs in [2usize,8]{
                assert_eq!(cff_one_jobs("Test-Font",&g,jobs).unwrap(),want,"n={n} jobs={jobs}");
            }
        }
    }
}
