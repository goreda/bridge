//! Engine-internal raster->contour capture stage.
//! Zero dependencies: own PNG decoder + zlib inflate + unfilter, marching-squares
//! iso-contours at 0.5 on the interpolated ink-strength field (plus a binary-mask
//! wrapper), RDP simplification, windowed-turn corner detection.
//! Supported input: PNG 8-bit, non-interlaced, color types 0 (gray), 2 (RGB),
//! 6 (RGBA; alpha composited over a white background). Palette (3),
//! gray+alpha (4), 16-bit and interlaced inputs are rejected with an error.
use crate::reference_slice::Point;

#[derive(Clone,Debug)]
pub struct CapturedRing { pub points: Vec<Point>, pub corners: Vec<usize>, pub hole: bool,
    /// raw (pre-RDP) traced ring in the same frame as `points`; evidence for staircase-aware line gating
    pub raw: Vec<Point> }
/// Twice the signed capture-space area of a traced ring (shoelace).
pub fn ring_area2(points: &[Point]) -> f64 {
    let mut a2 = 0.0f64;
    for i in 0..points.len() {
        let u = points[i];
        let v = points[(i + 1) % points.len()];
        a2 += u.x * v.y - v.x * u.y;
    }
    a2
}

/// Degenerate-ring rule, shared by the fit stage and the deviation
/// measurer: a ring whose capture-space area is below half a pixel square
/// draws nothing at capture resolution. capture_fit drops such rings, so
/// curve_stress::measure_glyph must not score them against the fit - the
/// drop and the measurement exemption are the same rule, kept in one place
/// here so they cannot drift apart.
pub fn is_degenerate_ring(points: &[Point]) -> bool {
    ring_area2(points).abs() / 2.0 < 0.5
}

#[derive(Clone,Debug)]
pub struct MeasuredContour { pub width: usize, pub height: usize, pub rings: Vec<CapturedRing>,
    /// content bbox min in capture pixel space (y-up); ring points are
    /// bbox-relative - add this offset to recover shared-frame coordinates
    pub origin_x: f64, pub origin_y: f64 }

/// Optional capture lineage; raw_index is recorded before traversal reversal.
#[derive(Clone,Debug)]
pub struct CaptureLineage {
    pub captured_ring_index:usize,
    pub raw_point_count:usize,
    pub reversed:bool,
    pub raw_start_index:usize,
    pub retained_raw_indices:Vec<usize>,
    pub corner_events:Vec<(usize,usize)>, // simplified index, original raw index
    pub detector_policy_receipt:String,
}

// ---------- zlib inflate ----------
struct Bits<'a>{d:&'a [u8],pos:usize}
impl<'a> Bits<'a>{
    fn get(&mut self,n:usize)->Result<u32,String>{let mut v=0u32;for i in 0..n{let b=self.pos/8; if b>=self.d.len(){return Err("inflate eof".into());} v|=(((self.d[b]>>(self.pos%8))&1) as u32)<<i; self.pos+=1;} Ok(v)}
    fn align(&mut self){self.pos=(self.pos+7)/8*8;}
}
struct Huff{lens:Vec<u8>}
impl Huff{
    fn build(lens:Vec<u8>)->Huff{Huff{lens}}
    fn decode(&self,b:&mut Bits)->Result<u32,String>{
        // canonical huffman decode
        let mut code=0i32;let mut first=0i32;
        let mut counts=[0i32;16];for &l in &self.lens{counts[l as usize]+=1;}counts[0]=0;
        for len in 1..16{
            code=(code<<1)|(b.get(1)? as i32);
            let count=counts[len];
            if code-first<count{return Ok(self.lens.iter().enumerate().filter(|(_,&l)|l as usize==len).nth((code-first) as usize).map(|(i,_)|i as u32).ok_or("huff sym")?);}
            first=(first+count)<<1;
        }
        Err("huff overflow".into())
    }
}
const LENBASE:[u32;29]=[3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258];
const LENEXT:[usize;29]=[0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0];
const DBASE:[u32;30]=[1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577];
const DEXT:[usize;30]=[0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13];
// ---------- bounded decode API (single limited entry point) ----------
/// Typed PNG decode failures. Two claim categories stay separate:
/// (a) SAFETY-BOUNDED: every allocation and inflate growth is capped BEFORE
///     it happens; malformed/hostile input ends in a typed refusal, never a
///     panic or unbounded growth.
/// (b) PNG-VALIDITY: only the fields below are validated (signature, chunk
///     framing, IHDR length/order/uniqueness, nonzero dims, bitdepth,
///     compression/filter method bytes, interlace, IEND presence, trailing
///     input, zlib header/adler, stored-block NLEN). Chunk CRCs are NOT
///     checked; this is not a full PNG spec validator.
///
/// THRESHOLD CHANGE (explicit): inputs that exceed `DecodeLimits` decoded
/// successfully before this API existed; they are now refused. Defaults are
/// 32 MiB input, 2048x2048 px, 64 MiB peak working bytes. Bit-identity is
/// claimed ONLY for previously-accepted inputs within the limits.
#[derive(Debug,Clone,PartialEq,Eq)]
pub enum PngDecodeError{
    NotPng,
    ChunkLength,
    IhdrNotFirst,
    DuplicateIhdr,
    IhdrLength{len:usize},
    ZeroDimensions{w:usize,h:usize},
    UnsupportedBitDepth(u8),
    UnsupportedCompression(u8),
    UnsupportedFilterMethod(u8),
    InterlacedUnsupported,
    UnsupportedColorType(u8),
    MissingIend,
    IendLength{len:usize},
    TrailingInputBytes{trailing:usize},
    MissingIdat,
    InputTooLarge{len:usize,max:usize},
    TooManyPixels{w:usize,h:usize,max:usize},
    WorkingBudgetExceeded{needed:usize,max:usize},
    AllocationRefused{bytes:usize},
    BadZlibHeader,
    UnsupportedPresetDictionary,
    StoredNlenMismatch,
    InflateOverrun{cap:usize},
    PrematureData{expected:usize,got:usize},
    MissingAdler{have:usize},
    BadAdler{expected:u32,got:u32},
    GarbageAfterAdler{bytes:usize},
    Inflate(String),
}
impl std::fmt::Display for PngDecodeError{
    fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{
        match self{
            PngDecodeError::NotPng=>write!(f,"not png"),
            PngDecodeError::ChunkLength=>write!(f,"chunk len"),
            PngDecodeError::IhdrNotFirst=>write!(f,"IHDR is not the first chunk"),
            PngDecodeError::DuplicateIhdr=>write!(f,"duplicate IHDR"),
            PngDecodeError::IhdrLength{len}=>write!(f,"IHDR length != 13: {}",len),
            PngDecodeError::ZeroDimensions{w,h}=>write!(f,"zero dimensions: {}x{}",w,h),
            PngDecodeError::UnsupportedBitDepth(bd)=>write!(f,"bitdepth!=8: {}",bd),
            PngDecodeError::UnsupportedCompression(c)=>write!(f,"compression method != 0: {}",c),
            PngDecodeError::UnsupportedFilterMethod(m)=>write!(f,"filter method != 0: {}",m),
            PngDecodeError::InterlacedUnsupported=>write!(f,"interlaced"),
            PngDecodeError::UnsupportedColorType(ct)=>write!(f,"colortype: {}",ct),
            PngDecodeError::MissingIend=>write!(f,"IEND missing"),
            PngDecodeError::IendLength{len}=>write!(f,"IEND length != 0: {}",len),
            PngDecodeError::TrailingInputBytes{trailing}=>write!(f,"trailing input bytes: {}",trailing),
            PngDecodeError::MissingIdat=>write!(f,"idat"),
            PngDecodeError::InputTooLarge{len,max}=>write!(f,"input too large: {}>{}",len,max),
            PngDecodeError::TooManyPixels{w,h,max}=>write!(f,"too many pixels: {}x{}>{}",w,h,max),
            PngDecodeError::WorkingBudgetExceeded{needed,max}=>write!(f,"working budget exceeded: {}>{}",needed,max),
            PngDecodeError::AllocationRefused{bytes}=>write!(f,"allocation refused: {} bytes",bytes),
            PngDecodeError::BadZlibHeader=>write!(f,"bad zlib header"),
            PngDecodeError::UnsupportedPresetDictionary=>write!(f,"preset dictionary unsupported"),
            PngDecodeError::StoredNlenMismatch=>write!(f,"stored block NLEN mismatch"),
            PngDecodeError::InflateOverrun{cap}=>write!(f,"inflate overrun beyond cap {}",cap),
            PngDecodeError::PrematureData{expected,got}=>write!(f,"premature data: {}<{}",got,expected),
            PngDecodeError::MissingAdler{have}=>write!(f,"missing adler32: {} bytes left",have),
            PngDecodeError::BadAdler{expected,got}=>write!(f,"adler32 mismatch: stored {:08x} computed {:08x}",expected,got),
            PngDecodeError::GarbageAfterAdler{bytes}=>write!(f,"garbage after adler32: {} bytes",bytes),
            PngDecodeError::Inflate(m)=>write!(f,"inflate: {}",m),
        }
    }
}
impl std::error::Error for PngDecodeError{}
/// Decode budget. `max_input_bytes` caps the compressed container,
/// `max_pixels` caps w*h, `max_working_bytes` caps the PEAK sum of the live
/// buffers (IDAT copy + inflated scanlines + reconstruction + gray output),
/// computed with checked arithmetic before any allocation. Inflate itself is
/// hard-capped at the exact expected scanline byte count derived from the
/// validated header, so expansion bombs stop at the declared image size.
#[derive(Debug,Clone,Copy,PartialEq,Eq)]
pub struct DecodeLimits{
    pub max_input_bytes:usize,
    pub max_pixels:usize,
    pub max_working_bytes:usize,
}
impl Default for DecodeLimits{
    fn default()->Self{
        // Pipeline inputs are per-glyph source crops (KB scale). Defaults sit
        // far above real inputs and far below memory pressure. These ARE a
        // behavior change for oversized-but-valid PNGs (see type docs).
        DecodeLimits{max_input_bytes:32*1024*1024,max_pixels:4_194_304,max_working_bytes:64*1024*1024}
    }
}
fn adler32(d:&[u8])->u32{let mut a=1u32;let mut b=0u32;for &x in d{a=(a+x as u32)%65521;b=(b+a)%65521;}(b<<16)|a}
/// Inflate under a hard output cap; returns the bytes AND the deflate-stream
/// byte consumption so the caller can validate the zlib trailer exactly.
fn inflate_bounded(d:&[u8],cap:usize)->Result<(Vec<u8>,usize),PngDecodeError>{
    let mut b=Bits{d,pos:0};
    let mut out=Vec::new();
    out.try_reserve_exact(cap).map_err(|_|PngDecodeError::AllocationRefused{bytes:cap})?;
    loop{
        let last=b.get(1).map_err(PngDecodeError::Inflate)?;let typ=b.get(2).map_err(PngDecodeError::Inflate)?;
        match typ{
            0=>{b.align();let n=b.get(16).map_err(PngDecodeError::Inflate)? as usize;let nn=b.get(16).map_err(PngDecodeError::Inflate)?;
                if nn as u16!=!(n as u16){return Err(PngDecodeError::StoredNlenMismatch);}
                if n>cap-out.len(){return Err(PngDecodeError::InflateOverrun{cap});}
                for _ in 0..n{out.push(b.get(8).map_err(PngDecodeError::Inflate)? as u8);}}
            1|2=>{
                let (lit,dist)=if typ==1{
                    let mut l=vec![0u8;288];for i in 0..144{l[i]=8;}for i in 144..256{l[i]=9;}for i in 256..280{l[i]=7;}for i in 280..288{l[i]=8;}
                    (Huff::build(l),Huff::build(vec![5u8;30]))
                }else{
                    let hlit=b.get(5).map_err(PngDecodeError::Inflate)? as usize+257;let hdist=b.get(5).map_err(PngDecodeError::Inflate)? as usize+1;let hclen=b.get(4).map_err(PngDecodeError::Inflate)? as usize+4;
                    const ORDER:[usize;19]=[16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];
                    let mut cl=vec![0u8;19];for i in 0..hclen{cl[ORDER[i]]=b.get(3).map_err(PngDecodeError::Inflate)? as u8;}
                    let ch=Huff::build(cl);
                    let mut lens=Vec::new();
                    while lens.len()<hlit+hdist{
                        let s=ch.decode(&mut b).map_err(PngDecodeError::Inflate)?;
                        match s{0..=15=>lens.push(s as u8),16=>{let r=b.get(2).map_err(PngDecodeError::Inflate)?+3;let p=*lens.last().ok_or(PngDecodeError::Inflate("rep first".into()))?;for _ in 0..r{lens.push(p);}},17=>{let r=b.get(3).map_err(PngDecodeError::Inflate)?+3;for _ in 0..r{lens.push(0);}},18=>{let r=b.get(7).map_err(PngDecodeError::Inflate)?+11;for _ in 0..r{lens.push(0);}},_=>return Err(PngDecodeError::Inflate("cl sym".into()))}
                    }
                    let dl=lens.split_off(hlit);
                    (Huff::build(lens),Huff::build(dl))
                };
                loop{
                    let s=lit.decode(&mut b).map_err(PngDecodeError::Inflate)?;
                    if s<256{
                        if out.len()>=cap{return Err(PngDecodeError::InflateOverrun{cap});}
                        out.push(s as u8);
                    }else if s==256{break;}else{
                        let li=(s-257) as usize;if li>=29{return Err(PngDecodeError::Inflate("len sym".into()));}
                        let len=LENBASE[li]+b.get(LENEXT[li]).map_err(PngDecodeError::Inflate)?;
                        let ds=dist.decode(&mut b).map_err(PngDecodeError::Inflate)? as usize;if ds>=30{return Err(PngDecodeError::Inflate("dist sym".into()));}
                        let d0=DBASE[ds]+b.get(DEXT[ds]).map_err(PngDecodeError::Inflate)?;let d0=d0 as usize;if d0>out.len(){return Err(PngDecodeError::Inflate("dist back".into()));}
                        let len=len as usize;
                        if len>cap-out.len(){return Err(PngDecodeError::InflateOverrun{cap});}
                        for _ in 0..len{let v=out[out.len()-d0];out.push(v);}
                    }
                }
            }
            _=>return Err(PngDecodeError::Inflate("bad block".into()))
        }
        if last==1{break;}
    }
    let consumed=(b.pos+7)/8;
    Ok((out,consumed))
}
// ---------- PNG decode -> grayscale ----------
/// The single limited decode entry point. All budget checks happen BEFORE
/// the matching allocation; inflate runs under the exact expected-byte cap;
/// the zlib trailer (adler32) is verified against the inflated bytes.
pub fn decode_png_gray_bounded(d:&[u8],limits:&DecodeLimits)->Result<(usize,usize,Vec<u8>),PngDecodeError>{
    if d.len()>limits.max_input_bytes{return Err(PngDecodeError::InputTooLarge{len:d.len(),max:limits.max_input_bytes});}
    if d.len()<8||&d[..8]!=b"\x89PNG\r\n\x1a\n"{return Err(PngDecodeError::NotPng);}
    // Pass 1: chunk-frame validation only. NOTHING is allocated or copied
    // here; the IDAT payload total is accumulated with checked arithmetic so
    // the peak-memory budget is enforced BEFORE any buffer exists.
    let mut i=8usize;let (mut w,mut h,mut ch)=(0usize,0usize,0usize);
    let mut idat_total=0usize;
    let (mut seen_ihdr,mut seen_iend,mut first_chunk)=(false,false,true);
    while i.checked_add(12).map_or(false,|hdr|hdr<=d.len()){
        let ln=u32::from_be_bytes([d[i],d[i+1],d[i+2],d[i+3]]) as usize;let typ=&d[i+4..i+8];
        let body_end=i.checked_add(12).and_then(|a|a.checked_add(ln)).ok_or(PngDecodeError::ChunkLength)?;
        if body_end>d.len(){return Err(PngDecodeError::ChunkLength);}
        let body=&d[i+8..i+8+ln];
        match typ{
            b"IHDR"=>{
                if seen_ihdr{return Err(PngDecodeError::DuplicateIhdr);}
                if !first_chunk{return Err(PngDecodeError::IhdrNotFirst);}
                if ln!=13{return Err(PngDecodeError::IhdrLength{len:ln});}
                seen_ihdr=true;
                w=u32::from_be_bytes([body[0],body[1],body[2],body[3]]) as usize;
                h=u32::from_be_bytes([body[4],body[5],body[6],body[7]]) as usize;
                if w==0||h==0{return Err(PngDecodeError::ZeroDimensions{w,h});}
                let bd=body[8];let ct=body[9];let comp=body[10];let filt=body[11];let inter=body[12];
                if bd!=8{return Err(PngDecodeError::UnsupportedBitDepth(bd));}
                if comp!=0{return Err(PngDecodeError::UnsupportedCompression(comp));}
                if filt!=0{return Err(PngDecodeError::UnsupportedFilterMethod(filt));}
                if inter!=0{return Err(PngDecodeError::InterlacedUnsupported);}
                ch=match ct{0=>1,2=>3,6=>4,_=>return Err(PngDecodeError::UnsupportedColorType(ct))};
            }
            b"IDAT"=>{idat_total=idat_total.checked_add(ln).ok_or(PngDecodeError::WorkingBudgetExceeded{needed:usize::MAX,max:limits.max_working_bytes})?;}
            b"IEND"=>{
                if ln!=0{return Err(PngDecodeError::IendLength{len:ln});}
                seen_iend=true;break
            },
            _=>{}
        }
        first_chunk=false;
        i=body_end;
    }
    if !seen_ihdr{return Err(PngDecodeError::IhdrNotFirst);}
    if !seen_iend{return Err(PngDecodeError::MissingIend);}
    let consumed=i.checked_add(12).ok_or(PngDecodeError::ChunkLength)?;
    if d.len()>consumed{return Err(PngDecodeError::TrailingInputBytes{trailing:d.len()-consumed});}
    if idat_total<2{return Err(PngDecodeError::MissingIdat);}
    let px=w.checked_mul(h).ok_or(PngDecodeError::TooManyPixels{w,h,max:limits.max_pixels})?;
    if px>limits.max_pixels{return Err(PngDecodeError::TooManyPixels{w,h,max:limits.max_pixels});}
    let stride=w.checked_mul(ch).ok_or(PngDecodeError::WorkingBudgetExceeded{needed:usize::MAX,max:limits.max_working_bytes})?;
    let expected=h.checked_mul(stride+1).ok_or(PngDecodeError::WorkingBudgetExceeded{needed:usize::MAX,max:limits.max_working_bytes})?;
    // Peak live memory: IDAT copy + inflated scanlines + reconstruction + gray.
    let peak=idat_total
        .checked_add(expected)
        .and_then(|a|a.checked_add(h*stride))
        .and_then(|a|a.checked_add(px))
        .ok_or(PngDecodeError::WorkingBudgetExceeded{needed:usize::MAX,max:limits.max_working_bytes})?;
    if peak>limits.max_working_bytes{return Err(PngDecodeError::WorkingBudgetExceeded{needed:peak,max:limits.max_working_bytes});}
    // Pass 2: budget approved; reserve the exact IDAT total once, then copy.
    let mut idat=Vec::new();
    idat.try_reserve_exact(idat_total).map_err(|_|PngDecodeError::AllocationRefused{bytes:idat_total})?;
    {
        let mut j=8usize;let mut seen_ihdr2=false;
        while j+12<=d.len(){
            let ln=u32::from_be_bytes([d[j],d[j+1],d[j+2],d[j+3]]) as usize;let typ=&d[j+4..j+8];
            let body_end=j+12+ln; // bounds already validated in pass 1
            match typ{
                b"IHDR"=>{if !seen_ihdr2{seen_ihdr2=true;}}
                b"IDAT"=>idat.extend_from_slice(&d[j+8..j+8+ln]), // body only, CRC excluded
                b"IEND"=>break,
                _=>{}
            }
            j=body_end;
        }
    }
    // zlib header: CM=8, CINFO<=7, FCHECK valid, no preset dictionary.
    let (cmf,flg)=(idat[0],idat[1]);
    if cmf&0x0f!=8||cmf>>4>7||((cmf as u16)*256+flg as u16)%31!=0{return Err(PngDecodeError::BadZlibHeader);}
    if flg&0x20!=0{return Err(PngDecodeError::UnsupportedPresetDictionary);}
    let (raw,used)=inflate_bounded(&idat[2..],expected)?;
    let trailer=&idat[2+used..];
    if trailer.len()<4{return Err(PngDecodeError::MissingAdler{have:trailer.len()});}
    if trailer.len()>4{return Err(PngDecodeError::GarbageAfterAdler{bytes:trailer.len()-4});}
    let stored=u32::from_be_bytes([trailer[0],trailer[1],trailer[2],trailer[3]]);
    let computed=adler32(&raw);
    if stored!=computed{return Err(PngDecodeError::BadAdler{expected:stored,got:computed});}
    if raw.len()<expected{return Err(PngDecodeError::PrematureData{expected,got:raw.len()});}
    let mut recon=Vec::new();
    recon.try_reserve_exact(h*stride).map_err(|_|PngDecodeError::AllocationRefused{bytes:h*stride})?;
    recon.resize(h*stride,0u8);
    for y in 0..h{
        let f=raw[y*(stride+1)];let row=&raw[y*(stride+1)+1..y*(stride+1)+1+stride];
        for x in 0..stride{
            let a=if x>=ch{recon[y*stride+x-ch]}else{0};
            let b=if y>0{recon[(y-1)*stride+x]}else{0};
            let c=if y>0&&x>=ch{recon[(y-1)*stride+x-ch]}else{0};
            let v=row[x];
            recon[y*stride+x]=match f{
                0=>v,
                1=>v.wrapping_add(a),
                2=>v.wrapping_add(b),
                3=>v.wrapping_add(((a as u16+b as u16)/2) as u8),
                4=>{let p=a as i32+b as i32-c as i32;let pa=(p-a as i32).abs();let pb=(p-b as i32).abs();let pc=(p-c as i32).abs();v.wrapping_add(if pa<=pb&&pa<=pc{a}else if pb<=pc{b}else{c})},
                _=>return Err(PngDecodeError::Inflate(format!("filter {}",f)))
            };
        }
    }
    let mut gray=Vec::new();
    gray.try_reserve_exact(px).map_err(|_|PngDecodeError::AllocationRefused{bytes:px})?;
    gray.resize(px,0u8);
    for p in 0..px{
        gray[p]=match ch{
            1=>recon[p],
            3=>((77*recon[3*p] as u32+150*recon[3*p+1] as u32+29*recon[3*p+2] as u32)>>8) as u8,
            _=>{let lum=(77*recon[4*p] as u32+150*recon[4*p+1] as u32+29*recon[4*p+2] as u32)>>8;
                let a=recon[4*p+3] as u32;
                ((lum*a+255*(255-a)+127)/255) as u8} // composite over white
        };
    }
    Ok((w,h,gray))
}
/// Compatibility wrapper: existing callers keep the String-error signature
/// at the default limits (see type docs for the threshold change). The
/// decode path itself is the bounded one; there is no unbounded route.
pub fn decode_png_gray(d:&[u8])->Result<(usize,usize,Vec<u8>),String>{
    decode_png_gray_bounded(d,&DecodeLimits::default()).map_err(|e|e.to_string())
}
// ---------- marching squares on binary mask (iso 0.5) ----------
// Saddle rule (candidate rule): saddles (the diagonal-touch
// case) ALWAYS join the ink diagonal - same-ink parts touching at a corner
// are one component (ink 8-connected, background 4-connected) and are merged
// before spanning, never emitted as separate overlapping rings. The join is
// unconditional (not center-avg gated) so antialiased corner touches below
// mid-strength still join; KNI_SADDLE_CENTER restores the center>=iso gate
// for A/B measurement.
/// Convert a sample-index coordinate to the raster's corner-origin frame.
/// Each unit raster cell spans [index, index + cell_extent]; its sample is
/// at the midpoint, not at the cell's upper-left corner. Use this conversion
/// once when capture emits the contour, before normalization and fitting.
fn sample_index_to_raster(coordinate: f64) -> f64 {
    let cell_extent = 1.0;
    coordinate + cell_extent / 2.0
}

/// Trace contours in source-pixel coordinates (x right, y down), with the
/// raster origin at the upper-left cell corner and samples at cell centers.
pub fn trace_field(w:usize,h:usize,val:&dyn Fn(i64,i64)->f64,iso:f64)->Vec<Vec<Point>>{
    let mut segs:Vec<((f64,f64),(f64,f64))>=Vec::new();
    for r in -1i64..h as i64{
        for c in -1i64..w as i64{
            let tl=val(r,c);let tr=val(r,c+1);let br=val(r+1,c+1);let bl=val(r+1,c);
            let case=(if tl>iso{8}else{0})|(if tr>iso{4}else{0})|(if br>iso{2}else{0})|(if bl>iso{1}else{0});
            if case==0||case==15{continue;}
            let hed=|v0:f64,v1:f64,y:f64,x:f64|->(f64,f64){let t=(iso-v0)/(v1-v0);(y,x+t)}; // horizontal edge: left value -> right value
            let ved=|v0:f64,v1:f64,y:f64,x:f64|->(f64,f64){let t=(iso-v0)/(v1-v0);(y+t,x)}; // vertical edge: top value -> bottom value
            let top=hed(tl,tr,r as f64,c as f64);
            let bot=hed(bl,br,(r+1) as f64,c as f64);
            let left=ved(tl,bl,r as f64,c as f64);
            let right=ved(tr,br,r as f64,(c+1) as f64);
            match case{
                1=>segs.push((left,bot)),14=>segs.push((bot,left)),
                2=>segs.push((bot,right)),13=>segs.push((right,bot)),
                3=>segs.push((left,right)),12=>segs.push((right,left)),
                4=>segs.push((right,top)),11=>segs.push((top,right)),
    // The KNI_SADDLE_CENTER switch was removed; the former default (fixed first pairing, cases 5 and 10) is the deterministic saddle rule.
                5=>{segs.push((left,top));segs.push((right,bot));}
                6=>segs.push((bot,top)),9=>segs.push((top,bot)),
                7=>segs.push((left,top)),8=>segs.push((top,left)),
                10=>{segs.push((top,right));segs.push((bot,left));}
                _=>unreachable!()
            }
        }
    }
    use std::collections::HashMap;
    let mut start:HashMap<(u64,u64),Vec<usize>>=HashMap::new();
    let key=|p:(f64,f64)|(p.0.to_bits(),p.1.to_bits());
    for (i,(a,_)) in segs.iter().enumerate(){start.entry(key(*a)).or_default().push(i);}
    let mut used=vec![false;segs.len()];
    let mut loops=Vec::new();
    for i in 0..segs.len(){
        if used[i]{continue;}
        used[i]=true;
        let mut pts=vec![segs[i].0,segs[i].1];
        loop{
            let last=*pts.last().unwrap();
            if last==pts[0]{break;}
            let next=start.get(&key(last)).and_then(|v|v.iter().find(|&&j|!used[j]).copied());
            match next{Some(j)=>{used[j]=true;pts.push(segs[j].1);},None=>break}
        }
        if pts.len()>=4&&pts.first()==pts.last(){
            pts.pop();
            loops.push(pts.into_iter().map(|(r,c)|Point{x:sample_index_to_raster(c),y:sample_index_to_raster(r)}).collect());
        }
    }
    loops
}
pub fn trace_mask(w:usize,h:usize,mask:&[bool])->Vec<Vec<Point>>{
    trace_field(w,h,&|r,c|->f64{if r>=0&&(r as usize)<h&&c>=0&&(c as usize)<w&&mask[r as usize*w+c as usize]{1.0}else{0.0}},0.5)
}
fn signed_area(p:&[Point])->f64{let mut a=0.;for i in 0..p.len(){let u=p[i];let v=p[(i+1)%p.len()];a+=u.x*v.y-v.x*u.y;}a/2.}
fn inside(p:Point,ring:&[Point])->bool{let mut w=false;let n=ring.len();for i in 0..n{let a=ring[i];let b=ring[(i+1)%n];if (a.y>p.y)!=(b.y>p.y){let x=a.x+(p.y-a.y)*(b.x-a.x)/(b.y-a.y);if p.x<x{w=!w;}}}w}
// ---------- RDP + corners ----------
/// The same RDP decisions, with indices retained before points are emitted.
fn rdp_retained_indices(p:&[Point],eps:f64)->Vec<usize>{
    let n=p.len();if n<3{return (0..n).collect();}
    // open on farthest pair seeds
    let mut keep=vec![false;n];keep[0]=true;
    let mut best=0;let mut bd=0.;for i in 0..n{let d=(p[i].x-p[0].x).hypot(p[i].y-p[0].y);if d>bd{bd=d;best=i;}}
    keep[best]=true;
    let mut stack=vec![(0,best),(best,n)];
    while let Some((i,k))=stack.pop(){
        if k<=i+1{continue;}
        let a=p[i];let b=p[if k<n{k}else{0}];let abx=b.x-a.x;let aby=b.y-a.y;let l=abx.hypot(aby);if l==0.{continue;}
        let mut mi=i+1;let mut md=0.;
        for j in i+1..k{if j>=n{break;}let d=(abx*(p[j].y-a.y)-aby*(p[j].x-a.x)).abs()/l;if d>md{md=d;mi=j;}}
        if md>eps{keep[mi]=true;stack.push((i,mi));stack.push((mi,k));}
    }
    (0..n).filter(|&i|keep[i]).collect()
}
/// Drop consecutive near-duplicate points (chord < `tol`) from a ring,
/// keeping the first of each run; the wrap pair (last vs first) is checked
/// too. Near-duplicates carry no shape information at the simplification
/// tolerance and poison the k=1 direct vertex turn (a duplicate pair can
/// read as a corner or mask the true one). T_line := the operating rdp eps
/// (addendum): the same tolerance that decided
/// the point carries no deviation evidence.
pub fn dedup_ring(p:&[Point],tol:f64)->Vec<Point>{dedup_retained_indices(p,tol).into_iter().map(|i|p[i]).collect()}
fn dedup_retained_indices(p:&[Point],tol:f64)->Vec<usize>{
    let mut out:Vec<usize>=Vec::new();
    for (i,&q) in p.iter().enumerate(){
        if let Some(&j)=out.last(){let l=p[j];if (q.x-l.x).hypot(q.y-l.y)<tol{continue;}}
        out.push(i);
    }
    if out.len()>1{let f=p[out[0]];let l=p[*out.last().unwrap()];if (f.x-l.x).hypot(f.y-l.y)<tol{out.pop();}}
    out
}
/// Windowed-turn corner detector (pub for regression testing).
/// Contract: run/wrap suppression keeps the SHARPEST candidate (smallest
/// turn cosine), see tests/capture_fit_r.rs::wrap_dedup_keeps_sharper.
pub fn corners(p:&[Point])->Vec<usize>{
    let n=p.len();let mut out=Vec::new();
    if n<3{return out;}
    // point-window turn detector; operating RDP eps is contract-bound (see 02).
    // No small-ring blindness - below 2k+1 points
    // fall back to the DIRECT vertex turn (k=1: each point is a vertex on a
    // simplified ring) instead of skipping detection entirely; a 6-point
    // rectangle ring must still report its 4 corners.
    let k=if n>=2*4+1{4usize}else{1};
    // Stub-skipping (candidate rule): on the k=1
    // (small-ring) path the direct vertex turn is poisoned when a surviving
    // near-duplicate stub (just above the dedup tolerance) is the measured
    // leg - the true 90-degree corner then reads as a shallow turn. Legs are
    // accumulated until they clear the stub band, derived from the ring
    // itself (quarter of the median chord), never a hardcoded length. Rings
    // whose chords are all structural (regular polygons, rectangles) have a
    // median-scaled stub band, so their legs stay single-step and behavior
    // is unchanged.
    let min_leg=if k==1{
        let mut ch:Vec<f64>=(0..n).map(|i|{let a=p[i];let b=p[(i+1)%n];(b.x-a.x).hypot(b.y-a.y)}).filter(|&c|c>0.0).collect();
        ch.sort_by(|a,b|a.partial_cmp(b).unwrap());
        if ch.is_empty(){0.0}else{0.25*ch[ch.len()/2]}
    }else{0.0};
    let tc=|i:usize|->f64{
        let (mut ia, mut ic)=( (i+n-k)%n, (i+k)%n );
        if k==1 && min_leg>0.0{
            let b=p[i];
            let mut j=i;
            while (p[ia].x-b.x).hypot(p[ia].y-b.y)<min_leg && (i+n-j)<n/2 { j+=1; ia=(i+n-j)%n; }
            let mut j=i;
            while (p[ic].x-b.x).hypot(p[ic].y-b.y)<min_leg && (j-i)<n/2 { j+=1; ic=(i+j)%n; }
        }
        let a=p[ia];let b=p[i];let c=p[ic];
        let v1=(b.x-a.x,b.y-a.y);let v2=(c.x-b.x,c.y-b.y);
        let l1=v1.0.hypot(v1.1);let l2=v2.0.hypot(v2.1);if l1==0.||l2==0.{return 1.0;}
        ((v1.0*v2.0+v1.1*v2.1)/(l1*l2)).clamp(-1.,1.)
    };
    // (reverted: local-turn suppression scoring mis-ranked
    // smooth/stubby geometry corpus-wide - race2 +18 nodes with worse IoU,
    // kit52 +23 cubics. Windowed suppression restored; the k=4
    // window-overshoot misplacement seen on race-3 notch rings remains an
    // OPEN issue.)
    for i in 0..n{
        if tc(i)<crate::thresholds::CORNER_TURN_COS{out.push(i);} // windowed turn sharper than 60 deg
    }
    // suppress runs: keep sharpest within k of the previous kept corner
    let mut kept:Vec<usize>=Vec::new();
    for &i in &out{
        if let Some(&j)=kept.last(){
            if i-j<k{
                if tc(i)<tc(j){*kept.last_mut().unwrap()=i;}
                continue;
            }
        }
        kept.push(i);
    }
    if kept.len()>1{ // wrap dedup: keep the SHARPER (smallest turn cosine)
        let i=kept[0];let j=*kept.last().unwrap();
        if n-(j-i)<k{ if tc(i)<tc(j){kept.pop();}else{kept.remove(0);} }
    }
    // Local-evidence corner rescue (candidate rule; gate: C never worsens, mean IoU stable at 4 decimals).
    // Windowed k=4 corners can miss true corners whose short leg is swamped by a long neighbour
    // (race-3 notch/stair jogs). Add stub-skipped local-sharp vertices that no kept corner covers.
    if k>1 {
        let mut ch:Vec<f64>=(0..n).map(|q|{let a=p[q];let b=p[(q+1)%n];(b.x-a.x).hypot(b.y-a.y)}).filter(|&c|c>0.0).collect();
        ch.sort_by(|a,b|a.partial_cmp(b).unwrap());
        let ml=if ch.is_empty(){0.0}else{0.25*ch[ch.len()/2]};
        let rgl:f64=8.0; // min local leg (px): rejects 1-3px diagonal-aliasing staircases
        let d=|a:usize,b:usize|(p[a].x-p[b].x).hypot(p[a].y-p[b].y);
        // (cos, sign) of the local stub-skipped turn
        let loc=|i:usize|->(f64,f64){
            let mut ja=1;let mut jc=1;
            while d((i+n-ja)%n,i)<ml && ja<n/2 {ja+=1;}
            while d((i+jc)%n,i)<ml && jc<n/2 {jc+=1;}
            let a=(i+n-ja)%n;let c=(i+jc)%n;
            let v1=(p[i].x-p[a].x,p[i].y-p[a].y);let v2=(p[c].x-p[i].x,p[c].y-p[i].y);
            let l1=v1.0.hypot(v1.1);let l2=v2.0.hypot(v2.1);if l1==0.||l2==0.{return (1.0,0.0);}
            if l1.min(l2)<rgl {return (1.0,0.0);}
            (((v1.0*v2.0+v1.1*v2.1)/(l1*l2)).clamp(-1.,1.), v1.0*v2.1-v1.1*v2.0)
        };
        let rgs:f64=1e9;
        let ls:Vec<(f64,f64)>=(0..n).map(|i|loc(i)).collect();
        let sharp:Vec<usize>=(0..n).filter(|&i|ls[i].0<crate::thresholds::CORNER_TURN_COS).collect();
        // group: consecutive (gap<=2) AND same turn sign = one physical corner; keep sharpest
        let mut groups:Vec<Vec<usize>>=Vec::new();
        for &i in &sharp{
            if let Some(g)=groups.last_mut(){
                let l=*g.last().unwrap();
                if i-l<=2 && (ls[l].1>0.0)==(ls[i].1>0.0) && d(l,i)<=rgs {g.push(i);continue;}
            }
            groups.push(vec![i]);
        }
        // staircase-chain rejection: clusters of >RGN alternating sharp groups (gap<=3) are diagonal aliasing, not corners
        let rgn:usize=1000;
        let rgg:usize=3;let mut chain=vec![0usize;groups.len()];
        {let mut gi=0;while gi<groups.len(){let mut gj=gi;while gj+1<groups.len() && groups[gj+1][0]-groups[gj].last().unwrap()<=rgg {gj+=1;} for q in gi..=gj{chain[q]=gj-gi+1;} gi=gj+1;}}
        let mut add=Vec::new();
        for (gidx,g) in groups.iter().enumerate(){
            if chain[gidx]>rgn{continue;}
            let best={
                let raw=|i:usize|->f64{let pr=d((i+n-1)%n,i);let nx=d(i,(i+1)%n);pr.min(nx)};
                *g.iter().max_by(|&&a,&&b|raw(a).partial_cmp(&raw(b)).unwrap()).unwrap()
            };
            // already represented by a kept corner within the group span +-1 ?
            let lo=g[0];let hi=*g.last().unwrap();
            let covered=kept.iter().any(|&c|{let cd=|a:usize,b:usize|{let x=if a>b{a-b}else{b-a};x.min(n-x)}; cd(c,lo)<=1||cd(c,hi)<=1||(c>=lo&&c<=hi)});
            // contract (wrap_dedup_keeps_sharper): a same-sign neighbour of a kept corner within k is a
            // duplicate of that physical corner and stays suppressed; opposite-sign neighbours (jogs) are distinct.
            let cdist=|a:usize,b:usize|{let x=if a>b{a-b}else{b-a};x.min(n-x)};
            let dup=tc(best)<crate::thresholds::CORNER_TURN_COS && kept.iter().any(|&c|cdist(c,best)<k && (ls[c].1>0.0)==(ls[best].1>0.0));
            if !covered && !dup{add.push(best);}
        }
        kept.extend(add);kept.sort();kept.dedup();
    }
    kept
}
/// Full capture: PNG bytes -> measured contour. Threshold: gray<128 foreground.
/// Output font coords: x right, y up, origin at content bbox min, NOT scaled (caller scales).
pub fn capture_png(d:&[u8],rdp_eps:f64)->Result<MeasuredContour,String>{capture_png_observed(d,rdp_eps,None)}
/// Optional lineage path. Geometry shares the same capture execution.
pub fn capture_png_with_lineage(d:&[u8],rdp_eps:f64)->Result<(MeasuredContour,Vec<CaptureLineage>),String>{
    let mut records=Vec::new();let out=capture_png_observed(d,rdp_eps,Some(&mut records))?;Ok((out,records))
}
fn capture_png_observed(d:&[u8],rdp_eps:f64,lineage:Option<&mut Vec<CaptureLineage>>)->Result<MeasuredContour,String>{
    let (w,h,gray)=decode_png_gray(d)?;
    capture_gray_observed(w,h,&gray,rdp_eps,lineage)
}
/// Shared decoded u8 gray -> capture, preserving existing PNG geometry.
/// Row-major, top-to-bottom, 255=paper. Decoder identity remains with caller.
pub fn capture_gray(w:usize,h:usize,gray:&[u8],rdp_eps:f64)->Result<MeasuredContour,String>{
    capture_gray_observed(w,h,gray,rdp_eps,None)
}
pub fn capture_gray_with_lineage(w:usize,h:usize,gray:&[u8],rdp_eps:f64)->Result<(MeasuredContour,Vec<CaptureLineage>),String>{
    let mut records=Vec::new();let out=capture_gray_observed(w,h,gray,rdp_eps,Some(&mut records))?;Ok((out,records))
}
fn capture_gray_observed(w:usize,h:usize,gray:&[u8],rdp_eps:f64,mut lineage:Option<&mut Vec<CaptureLineage>>)->Result<MeasuredContour,String>{
    if w==0||h==0||w.checked_mul(h)!=Some(gray.len()){return Err("gray raster size mismatch".into());}
    if !rdp_eps.is_finite()||rdp_eps<0.0{return Err("invalid capture tolerance".into());}
    let gv:Vec<f64>=gray.iter().map(|&g|1.0-(g as f64)/255.0).collect(); // ink strength
    let loops=trace_field(w,h,&|r,c|->f64{if r>=0&&(r as usize)<h&&c>=0&&(c as usize)<w{gv[r as usize*w+c as usize]}else{0.0}},0.5);
    if loops.is_empty(){return Err("no contours".into());}
    let mut rings:Vec<(Vec<Point>,f64)>=loops.into_iter().map(|p|{let a=signed_area(&p);(p,a)}).collect();
    rings.sort_by(|a,b|b.1.abs().partial_cmp(&a.1.abs()).unwrap());
    // Hole classification by containment
    // DEPTH PARITY, replacing the old "contained in a larger-area ring" rule.
    // The area test misclassified islands - a ring inside a counter is ink
    // again (registered-mark letterform inside the circle, @ inner structure,
    // slash-through-bowl class glyphs): it was marked hole and wound CW,
    // knocking the island out under nonzero fill. Even-odd nesting is the
    // rule font outlines actually follow: even depth = outer (CCW), odd
    // depth = hole (CW). Traced iso-contours do not share edges, so the
    // first-point test cannot sit on another ring's boundary.
    let mut out=Vec::new();
    let polys:Vec<Vec<Point>>=rings.iter().map(|r|r.0.clone()).collect();
    for (idx,(p,_a)) in rings.iter().enumerate(){
        let depth=(0..polys.len()).filter(|&j|j!=idx&&inside(p[0],&polys[j])).count();
        let hole=depth%2==1;
        // font coords: y up (flip), keep raw pixel scale
        let mut fp:Vec<Point>=p.iter().map(|q|Point{x:q.x,y:-q.y}).collect();
        let want_ccw=!hole;
        let reversed=(signed_area(&fp)>0.)!=want_ccw;
        if reversed{fp.reverse();}
        let retained=rdp_retained_indices(&fp,rdp_eps);
        let simplified:Vec<Point>=retained.iter().map(|&i|fp[i]).collect();
        let dedup=dedup_retained_indices(&simplified,rdp_eps);
        let sp:Vec<Point>=dedup.iter().map(|&i|simplified[i]).collect();
        let cr=corners(&sp);
        if let Some(records)=lineage.as_mut(){
            let raw_indices:Vec<usize>=dedup.iter().map(|&i|{let j=retained[i];if reversed{fp.len()-1-j}else{j}}).collect();
            let events=cr.iter().map(|&i|(i,raw_indices[i])).collect();
            records.push(CaptureLineage{captured_ring_index:idx,raw_point_count:fp.len(),reversed,
                raw_start_index:if reversed{fp.len()-1}else{0},retained_raw_indices:raw_indices,
                corner_events:events,detector_policy_receipt:format!(
                    "existing capture corners; rdp_eps={rdp_eps}; dedup_tol={rdp_eps}; window n>=9:k4 else k1; turn cosine<0.5; min_leg=quarter median chord; rescue existing rgl8/rgs1e9/rgn1000/rgg3; no new tolerances")});
        }
        out.push(CapturedRing{points:sp,corners:cr,hole,raw:fp.clone()});
    }
    // normalize origin to content bbox min
    // Origin from the RAW contour, not the RDP-kept
    // points. RDP drops points within eps of each chord, so a min over kept
    // points sits inside the true bbox by up to eps per axis (a code
    // review measured x <=1.9 u, y <=5.0 u at 100 ppem) - the docstring
    // contract "origin at content bbox min" is about the CONTENT, not the
    // simplification. raw holds the full-res contour; both points and raw
    // are shifted by the same raw-derived min, so their relative geometry
    // is unchanged.
    let mut mnx=f64::INFINITY;let mut mny=f64::INFINITY;
    for r in &out{for p in &r.raw{mnx=mnx.min(p.x);mny=mny.min(p.y);}}
    for r in &mut out{for p in &mut r.points{p.x-=mnx;p.y-=mny;} for p in &mut r.raw{p.x-=mnx;p.y-=mny;}}
    Ok(MeasuredContour{width:w,height:h,rings:out,origin_x:mnx,origin_y:mny})
}
// allow rationale: used only by bounded_decode_tests (cfg(test)): "python zlib level 9, 1039 compressed -> 1 MiB inflated".
#[allow(dead_code)]
const BOMB_DYNAMIC_ZLIB:&[u8]=&[120,218,237,193,49,1,0,0,0,194,160,245,79,109,8,95,160,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,62,3,0,240,0,1];
// allow rationale: used only by bounded_decode_tests (cfg(test)): "python zlib Z_FIXED, 6616 compressed -> 1 MiB inflated".
#[allow(dead_code)]
const BOMB_FIXED_ZLIB:&[u8]=&[120,1,99,96,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,24,5,163,96,20,140,130,81,48,10,70,193,40,160,12,0,0,0,240,0,1];

#[cfg(test)]
mod bounded_decode_tests{
    use super::*;

    fn zlib_stored(raw:&[u8])->Vec<u8>{
        let mut out=vec![0x78u8,0x01];
        let mut i=0;
        loop{
            let n=(raw.len()-i).min(65535);
            let fin=if i+n==raw.len(){1u8}else{0u8};
            out.push(fin);
            out.extend_from_slice(&(n as u16).to_le_bytes());
            out.extend_from_slice(&(!(n as u16)).to_le_bytes());
            out.extend_from_slice(&raw[i..i+n]);
            i+=n;
            if i==raw.len(){break;}
        }
        out.extend_from_slice(&adler32(raw).to_be_bytes());
        out
    }
    fn chunk(typ:&[u8;4],body:&[u8])->Vec<u8>{
        let mut v=(body.len() as u32).to_be_bytes().to_vec();
        v.extend_from_slice(typ);v.extend_from_slice(body);
        v.extend_from_slice(&0u32.to_be_bytes()); // CRC deliberately unused by this decoder
        v
    }
    fn ihdr(w:u32,h:u32,bd:u8,ct:u8,comp:u8,filt:u8,inter:u8)->Vec<u8>{
        let mut v=w.to_be_bytes().to_vec();v.extend_from_slice(&h.to_be_bytes());v.extend_from_slice(&[bd,ct,comp,filt,inter]);v
    }
    fn png(w:u32,h:u32,bd:u8,ct:u8,inter:u8,idat:&[u8],trailing:&[u8])->Vec<u8>{
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(w,h,bd,ct,0,0,inter)));
        v.extend_from_slice(&chunk(b"IDAT",idat));
        v.extend_from_slice(&chunk(b"IEND",&[]));
        v.extend_from_slice(trailing);
        v
    }
    fn scanlines_zero_filter(w:usize,h:usize,ch:usize,pixels:&[u8])->Vec<u8>{
        let mut raw=Vec::new();
        for y in 0..h{raw.push(0u8);raw.extend_from_slice(&pixels[y*w*ch..(y+1)*w*ch]);}
        raw
    }
    /// Legacy pre-API decoder, test-only reference for within-limit parity.
    fn legacy_inflate(d:&[u8])->Result<Vec<u8>,String>{
        let mut b=Bits{d,pos:0};let mut out=Vec::new();
        loop{
            let last=b.get(1)?;let typ=b.get(2)?;
            match typ{
                0=>{b.align();let n=b.get(16)? as usize;let _nn=b.get(16)?;for _ in 0..n{out.push(b.get(8)? as u8);}}
                1|2=>{
                    let (lit,dist)=if typ==1{
                        let mut l=vec![0u8;288];for i in 0..144{l[i]=8;}for i in 144..256{l[i]=9;}for i in 256..280{l[i]=7;}for i in 280..288{l[i]=8;}
                        (Huff::build(l),Huff::build(vec![5u8;30]))
                    }else{
                        let hlit=b.get(5)? as usize+257;let hdist=b.get(5)? as usize+1;let hclen=b.get(4)? as usize+4;
                        const ORDER:[usize;19]=[16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15];
                        let mut cl=vec![0u8;19];for i in 0..hclen{cl[ORDER[i]]=b.get(3)? as u8;}
                        let ch=Huff::build(cl);
                        let mut lens=Vec::new();
                        while lens.len()<hlit+hdist{
                            let s=ch.decode(&mut b)?;
                            match s{0..=15=>lens.push(s as u8),16=>{let r=b.get(2)?+3;let p=*lens.last().ok_or("rep first")?;for _ in 0..r{lens.push(p);}},17=>{let r=b.get(3)?+3;for _ in 0..r{lens.push(0);}},18=>{let r=b.get(7)?+11;for _ in 0..r{lens.push(0);}},_=>return Err("cl sym".into())}
                        }
                        let dl=lens.split_off(hlit);
                        (Huff::build(lens),Huff::build(dl))
                    };
                    loop{
                        let s=lit.decode(&mut b)?;
                        if s<256{out.push(s as u8);}else if s==256{break;}else{
                            let li=(s-257) as usize;if li>=29{return Err("len sym".into());}
                            let len=LENBASE[li]+b.get(LENEXT[li])?;
                            let ds=dist.decode(&mut b)? as usize;if ds>=30{return Err("dist sym".into());}
                            let d0=DBASE[ds]+b.get(DEXT[ds])?;let d0=d0 as usize;if d0>out.len(){return Err("dist back".into());}
                            for _ in 0..len{let v=out[out.len()-d0];out.push(v);}
                        }
                    }
                }
                _=>return Err("bad block".into())
            }
            if last==1{break;}
        }
        Ok(out)
    }
    fn legacy_decode_png_gray(d:&[u8])->Result<(usize,usize,Vec<u8>),String>{
        if d.len()<8||&d[..8]!=b"\x89PNG\r\n\x1a\n"{return Err("not png".into());}
        let mut i=8;let (mut w,mut h,mut bd,mut ct,mut inter)=(0usize,0usize,0u8,0u8,0u8);let mut idat=Vec::new();
        while i+12<=d.len(){
            let ln=u32::from_be_bytes([d[i],d[i+1],d[i+2],d[i+3]]) as usize;let typ=&d[i+4..i+8];
            if i+12+ln>d.len(){return Err("chunk len".into());}
            let body=&d[i+8..i+8+ln];
            match typ{
                b"IHDR"=>{w=u32::from_be_bytes([body[0],body[1],body[2],body[3]]) as usize;h=u32::from_be_bytes([body[4],body[5],body[6],body[7]]) as usize;bd=body[8];ct=body[9];inter=body[12];}
                b"IDAT"=>idat.extend_from_slice(body),
                b"IEND"=>break,
                _=>{}
            }
            i+=12+ln;
        }
        if bd!=8{return Err("bitdepth!=8".into());} if inter!=0{return Err("interlaced".into());}
        let ch=match ct{0=>1,2=>3,6=>4,_=>return Err("colortype".into())};
        if idat.len()<2{return Err("idat".into());}
        let raw=legacy_inflate(&idat[2..])?;
        let stride=w*ch;
        if raw.len()<h*(stride+1){return Err("raw short".into());}
        let mut recon=vec![0u8;h*stride];
        for y in 0..h{
            let f=raw[y*(stride+1)];let row=&raw[y*(stride+1)+1..y*(stride+1)+1+stride];
            for x in 0..stride{
                let a=if x>=ch{recon[y*stride+x-ch]}else{0};
                let b=if y>0{recon[(y-1)*stride+x]}else{0};
                let c=if y>0&&x>=ch{recon[(y-1)*stride+x-ch]}else{0};
                let v=row[x];
                recon[y*stride+x]=match f{
                    0=>v,
                    1=>v.wrapping_add(a),
                    2=>v.wrapping_add(b),
                    3=>v.wrapping_add(((a as u16+b as u16)/2) as u8),
                    4=>{let p=a as i32+b as i32-c as i32;let pa=(p-a as i32).abs();let pb=(p-b as i32).abs();let pc=(p-c as i32).abs();v.wrapping_add(if pa<=pb&&pa<=pc{a}else if pb<=pc{b}else{c})},
                    _=>return Err("filter".into())
                };
            }
        }
        let mut gray=vec![0u8;w*h];
        for p in 0..w*h{
            gray[p]=match ct{
                0=>recon[p],
                2=>((77*recon[3*p] as u32+150*recon[3*p+1] as u32+29*recon[3*p+2] as u32)>>8) as u8,
                6=>{let lum=(77*recon[4*p] as u32+150*recon[4*p+1] as u32+29*recon[4*p+2] as u32)>>8;
                    let a=recon[4*p+3] as u32;
                    ((lum*a+255*(255-a)+127)/255) as u8}
                ,_=>0};
        }
        Ok((w,h,gray))
    }

    // ---- bombs (safety-bounded category) ----
    #[test]
    fn compressed_bomb_stored_blocks_rejected_at_cap(){
        let bomb=png(4,4,8,0,0,&zlib_stored(&vec![0xAAu8;65535]),&[]);
        assert_eq!(decode_png_gray_bounded(&bomb,&DecodeLimits::default()),Err(PngDecodeError::InflateOverrun{cap:20}));
    }
    #[test]
    fn compressed_bomb_fixed_huffman_backrefs_rejected_at_cap(){
        // BOMB_FIXED_ZLIB: python zlib Z_FIXED, 6616 compressed -> 1 MiB inflated.
        let bomb=png(8,8,8,0,0,BOMB_FIXED_ZLIB,&[]);
        assert_eq!(decode_png_gray_bounded(&bomb,&DecodeLimits::default()),Err(PngDecodeError::InflateOverrun{cap:72}));
    }
    #[test]
    fn compressed_bomb_dynamic_huffman_backrefs_rejected_at_cap(){
        // BOMB_DYNAMIC_ZLIB: python zlib level 9, 1039 compressed -> 1 MiB inflated.
        let bomb=png(8,8,8,0,0,BOMB_DYNAMIC_ZLIB,&[]);
        assert_eq!(decode_png_gray_bounded(&bomb,&DecodeLimits::default()),Err(PngDecodeError::InflateOverrun{cap:72}));
    }
    #[test]
    fn huge_dims_rejected_before_allocation(){
        let big=png(65535,65535,8,0,0,&zlib_stored(&[0u8;1]),&[]);
        assert!(matches!(decode_png_gray_bounded(&big,&DecodeLimits::default()),Err(PngDecodeError::TooManyPixels{..})));
    }
    // ---- header validity (PNG-validity category) ----
    #[test]
    fn malformed_headers_typed_no_panic(){
        let z=zlib_stored(&scanlines_zero_filter(2,2,1,&[1,2,3,4]));
        // short IHDR (5-byte body): previously a slice-index panic path
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&[0,0,0,2,0]));
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::IhdrLength{len:5}));
        // IHDR not first
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"tEXt",&[1]));
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(2,2,8,0,0,0,0)));
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::IhdrNotFirst));
        // duplicate IHDR
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(2,2,8,0,0,0,0)));
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(2,2,8,0,0,0,0)));
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::DuplicateIhdr));
        // zero dims
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(0,2,8,0,0,0,0)));
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::ZeroDimensions{w:0,h:2}));
        // compression / filter method bytes
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(2,2,8,0,1,0,0)));
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::UnsupportedCompression(1)));
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(2,2,8,0,0,1,0)));
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::UnsupportedFilterMethod(1)));
        // missing IEND
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(2,2,8,0,0,0,0)));
        v.extend_from_slice(&chunk(b"IDAT",&z));
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::MissingIend));
        // interlace + bitdepth still typed
        assert_eq!(decode_png_gray_bounded(&png(2,2,8,0,1,&z,&[]),&DecodeLimits::default()),Err(PngDecodeError::InterlacedUnsupported));
        assert_eq!(decode_png_gray_bounded(&png(2,2,4,0,0,&z,&[]),&DecodeLimits::default()),Err(PngDecodeError::UnsupportedBitDepth(4)));
    }
    #[test]
    fn zlib_layer_typed(){
        let raw=scanlines_zero_filter(2,2,1,&[1,2,3,4]);
        let z=zlib_stored(&raw);
        // bad FCHECK
        let mut bad=z.clone(); bad[1]^=0x01;
        assert_eq!(decode_png_gray_bounded(&png(2,2,8,0,0,&bad,&[]),&DecodeLimits::default()),Err(PngDecodeError::BadZlibHeader));
        // preset dictionary bit (keep FCHECK valid: recompute FLG)
        let cmf=0x78u16; let flg=0x20u16; let pad=(31-((cmf*256+flg)%31))%31; let flg=flg+pad;
        let mut dict=z.clone(); dict[0]=cmf as u8; dict[1]=flg as u8;
        assert_eq!(decode_png_gray_bounded(&png(2,2,8,0,0,&dict,&[]),&DecodeLimits::default()),Err(PngDecodeError::UnsupportedPresetDictionary));
        // bad adler
        let mut ba=z.clone(); let n=ba.len(); ba[n-1]^=0xFF;
        assert!(matches!(decode_png_gray_bounded(&png(2,2,8,0,0,&ba,&[]),&DecodeLimits::default()),Err(PngDecodeError::BadAdler{..})));
        // garbage after adler inside IDAT
        let mut g=z.clone(); g.extend_from_slice(&[0u8;2]);
        assert_eq!(decode_png_gray_bounded(&png(2,2,8,0,0,&g,&[]),&DecodeLimits::default()),Err(PngDecodeError::GarbageAfterAdler{bytes:2}));
        // stored NLEN mismatch
        let mut nl=z.clone(); nl[5]^=0xFF; // first stored block NLEN byte
        assert_eq!(decode_png_gray_bounded(&png(2,2,8,0,0,&nl,&[]),&DecodeLimits::default()),Err(PngDecodeError::StoredNlenMismatch));
        // truncated deflate stream (drop adler + part of stream)
        let tr=z[..z.len()-6].to_vec();
        assert!(matches!(decode_png_gray_bounded(&png(2,2,8,0,0,&tr,&[]),&DecodeLimits::default()),Err(PngDecodeError::Inflate(_))|Err(PngDecodeError::MissingAdler{..})));
    }
    #[test]
    fn truncation_sweep_never_panics(){
        let p=png(3,2,8,0,0,&zlib_stored(&scanlines_zero_filter(3,2,1,&[0,64,128,192,255,32])),&[]);
        for cut in 0..p.len(){
            let _=decode_png_gray_bounded(&p[..cut],&DecodeLimits::default()); // must not panic
        }
    }
    #[test]
    fn iend_length_and_narrow_header_guards(){
        let z=zlib_stored(&scanlines_zero_filter(2,2,1,&[1,2,3,4]));
        // IEND with nonzero body
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(2,2,8,0,0,0,0)));
        v.extend_from_slice(&chunk(b"IDAT",&z));
        v.extend_from_slice(&chunk(b"IEND",&[0u8;2]));
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::IendLength{len:2}));
        // declared chunk length far beyond input: typed ChunkLength, no panic
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&u32::MAX.to_be_bytes());
        v.extend_from_slice(b"IHDR");
        v.extend_from_slice(&[0u8;4]);
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::ChunkLength));
        // truncated mid-IHDR body: typed ChunkLength
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(2,2,8,0,0,0,0)));
        v.truncate(v.len()-3);
        assert_eq!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Err(PngDecodeError::ChunkLength));
    }
    #[test]
    fn budget_is_enforced_before_any_idat_allocation(){
        // many small IDAT chunks: pass 1 totals them with checked arithmetic;
        // a total above the working budget is refused before the copy exists.
        let raw=scanlines_zero_filter(2,2,1,&[1,2,3,4]);
        let z=zlib_stored(&raw);
        let mut v=b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&chunk(b"IHDR",&ihdr(2,2,8,0,0,0,0)));
        for piece in z.chunks(2){ v.extend_from_slice(&chunk(b"IDAT",piece)); }
        v.extend_from_slice(&chunk(b"IEND",&[]));
        let lim=DecodeLimits{max_input_bytes:1<<24,max_pixels:1<<24,max_working_bytes:8};
        assert!(matches!(decode_png_gray_bounded(&v,&DecodeLimits::default()),Ok(_)));
        assert!(matches!(decode_png_gray_bounded(&v,&lim),Err(PngDecodeError::WorkingBudgetExceeded{..})));
    }
    // ---- budget / threshold behavior ----
    #[test]
    fn premature_data_typed(){
        let short=png(4,4,8,0,0,&zlib_stored(&[0u8;10]),&[]);
        assert_eq!(decode_png_gray_bounded(&short,&DecodeLimits::default()),Err(PngDecodeError::PrematureData{expected:20,got:10}));
    }
    #[test]
    fn trailing_input_typed(){
        let raw=scanlines_zero_filter(2,2,1,&[1,2,3,4]);
        let t=png(2,2,8,0,0,&zlib_stored(&raw),&[0u8;3]);
        assert_eq!(decode_png_gray_bounded(&t,&DecodeLimits::default()),Err(PngDecodeError::TrailingInputBytes{trailing:3}));
    }
    #[test]
    fn threshold_change_is_explicit(){
        // valid 4x4 PNG refused only because the caller tightened max_pixels
        let p=png(4,4,8,0,0,&zlib_stored(&scanlines_zero_filter(4,4,1,&[7u8;16])),&[]);
        let tight=DecodeLimits{max_input_bytes:32*1024*1024,max_pixels:9,max_working_bytes:64*1024*1024};
        assert_eq!(decode_png_gray_bounded(&p,&tight),Err(PngDecodeError::TooManyPixels{w:4,h:4,max:9}));
        assert!(decode_png_gray_bounded(&p,&DecodeLimits::default()).is_ok());
    }
    // ---- caller limit propagation through the adapter ----
    #[test]
    fn caller_limits_flow_through_capture_dispatch(){
        let p=png(3,2,8,0,0,&zlib_stored(&scanlines_zero_filter(3,2,1,&[0,64,128,192,255,32])),&[]);
        let jlim=crate::jpeg_source::Limits{max_input_bytes:1<<24,max_pixels:1<<24,max_working_bytes:1<<26};
        let tight=DecodeLimits{max_input_bytes:1<<24,max_pixels:4,max_working_bytes:1<<26};
        let r=crate::capture_dispatch::decode_source(&p,&tight,jlim);
        assert!(matches!(r,Err(crate::capture_dispatch::DispatchError::Capture(_))));
        let ok=crate::capture_dispatch::decode_source(&p,&DecodeLimits::default(),jlim).expect("within default limits");
        assert_eq!(ok.receipt.png_limits,Some(DecodeLimits::default()));
        assert!(ok.receipt.decoder_limits.is_none());
    }
    // ---- within-limit parity (bit-identity, scoped claim) ----
    #[test]
    fn tiny_valid_gray_roundtrip_exact(){
        let px=[10u8,20,30,40];
        let p=png(2,2,8,0,0,&zlib_stored(&scanlines_zero_filter(2,2,1,&px)),&[]);
        assert_eq!(decode_png_gray_bounded(&p,&DecodeLimits::default()),Ok((2,2,px.to_vec())));
    }
    #[test]
    fn within_limit_parity_all_colortypes_and_filters(){
        let lim=DecodeLimits::default();
        let mut cases:Vec<Vec<u8>>=Vec::new();
        let g=[0u8,64,128,192,255,32];
        cases.push(png(3,2,8,0,0,&zlib_stored(&scanlines_zero_filter(3,2,1,&g)),&[]));
        let rgb=[255u8,0,0, 0,255,0, 0,0,255, 10,20,30, 200,100,50, 1,2,3];
        cases.push(png(3,2,8,2,0,&zlib_stored(&scanlines_zero_filter(3,2,3,&rgb)),&[]));
        let rgba=[255u8,0,0,255, 0,255,0,128, 0,0,255,0, 10,20,30,77, 200,100,50,201, 1,2,3,99];
        cases.push(png(3,2,8,6,0,&zlib_stored(&scanlines_zero_filter(3,2,4,&rgba)),&[]));
        let mut raw=Vec::new();let mut seed=7u8;
        for f in 0..5u8{raw.push(f);for _ in 0..8{seed=seed.wrapping_mul(31).wrapping_add(17);raw.push(seed);}}
        cases.push(png(8,5,8,0,0,&zlib_stored(&raw),&[]));
        for (idx,c) in cases.iter().enumerate(){
            let new=decode_png_gray_bounded(c,&lim).unwrap_or_else(|e|panic!("case {} rejected: {:?}",idx,e));
            let old=legacy_decode_png_gray(c).expect("legacy accepts within-limit input");
            assert_eq!(new,old,"bit-identity case {}",idx);
            assert_eq!(decode_png_gray(c).expect("wrapper"),old);
        }
    }
}
