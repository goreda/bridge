//! Proposed baseline-subset JPEG -> raw luma. No capture integration.

pub const DECODER_VERSION: &str = "kni.jpeg-source.v1-q14";
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JpegError { BadSignature, Truncated, UnsupportedMode, UnsupportedPrecision, UnsupportedColour, UnsupportedSampling, UnsupportedScan, UnsupportedQuantization, MalformedDimensions, MalformedTable, MalformedEntropy, MalformedMarker, RestartSequence, CoefficientBound, ArithmeticOverflow, ResourceLimit, AllocationFailed, TrailingData }
impl JpegError { pub fn code(&self)->&'static str {match self {
 Self::BadSignature=>"bad_signature",Self::Truncated=>"truncated",Self::UnsupportedMode=>"unsupported_mode",Self::UnsupportedPrecision=>"unsupported_precision",Self::UnsupportedColour=>"unsupported_colour",Self::UnsupportedSampling=>"unsupported_sampling",Self::UnsupportedScan=>"unsupported_scan",Self::UnsupportedQuantization=>"unsupported_quantization",Self::MalformedDimensions=>"malformed_dimensions",Self::MalformedTable=>"malformed_table",Self::MalformedEntropy=>"malformed_entropy",Self::MalformedMarker=>"malformed_marker",Self::RestartSequence=>"restart_sequence",Self::CoefficientBound=>"coefficient_bound",Self::ArithmeticOverflow=>"arithmetic_overflow",Self::ResourceLimit=>"resource_limit",Self::AllocationFailed=>"allocation_failed",Self::TrailingData=>"trailing_data"}} }
#[derive(Debug, Clone, Copy)]
pub struct Limits { pub max_input_bytes: usize, pub max_pixels: usize, pub max_working_bytes:usize }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IdentityReceipt { pub orig_sha256: String, pub decoded_gray_sha256: String, pub orig_len:usize, pub w: usize, pub h: usize, pub dtype:&'static str, pub value_range:(u8,u8), pub row_order:&'static str, pub stride:usize, pub serialization:&'static str, pub subset_status:&'static str, pub config_pin:String, pub decoder_version: &'static str, pub beyond_nominal_quantized_11bit:bool }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodedGray { pub w: usize, pub h: usize, pub pixels: Vec<u8>, pub receipt: IdentityReceipt }
#[derive(Clone)]
pub(crate) struct Huff { entries: Vec<(u16,u8,u8)> }
impl Huff {
    pub(crate) fn new(counts: &[u8], values: &[u8]) -> Result<Self,JpegError> {
        let mut entries=Vec::new();entries.try_reserve_exact(values.len()).map_err(|_|JpegError::AllocationFailed)?; let mut code=0u32; let mut n=0;
        for (i,&count) in counts.iter().enumerate() {
            let bits=i+1;
            for _ in 0..count {
                if code >= (1u32<<bits)-1 {return Err(JpegError::MalformedTable);}
                entries.push((code as u16,bits as u8,*values.get(n).ok_or(JpegError::Truncated)?)); n+=1; code+=1;
            }
            code<<=1;
        }
        if n!=values.len() || n==0 {return Err(JpegError::MalformedTable);}
        Ok(Self{entries})
    }
    pub(crate) fn symbol(&self,b:&mut Bits<'_>)->Result<u8,JpegError>{
        let mut code=0u16;
        for bits in 1..=16 { code=(code<<1)|b.bit()? as u16;
            if let Some(e)=self.entries.iter().find(|e|e.0==code&&e.1==bits){return Ok(e.2);}
        } Err(JpegError::MalformedTable)
    }
}
pub(crate) struct Bits<'a>{pub(crate) data:&'a[u8],pub(crate) pos:usize,pub(crate) byte:u8,pub(crate) left:u8}
impl<'a> Bits<'a>{
 pub(crate) fn bit(&mut self)->Result<u8,JpegError>{
  if self.left==0 {self.byte=*self.data.get(self.pos).ok_or(JpegError::Truncated)?;self.pos+=1;
   if self.byte==255 {let next=*self.data.get(self.pos).ok_or(JpegError::Truncated)?;self.pos+=1;if next!=0{return Err(if (0xd0..=0xd7).contains(&next){JpegError::RestartSequence}else{JpegError::Truncated});}}
   self.left=8;
  } self.left-=1;Ok((self.byte>>self.left)&1)
 }
 pub(crate) fn number(&mut self,n:u8)->Result<i32,JpegError>{let mut v=0i32;for _ in 0..n{v=(v<<1)|self.bit()? as i32;} Ok(if n>0&&v<(1<<(n-1)){v-((1<<n)-1)}else{v})}
 pub(crate) fn align(&mut self)->Result<(),JpegError>{if self.left>0 && self.byte&((1u16<<self.left)-1) as u8 != ((1u16<<self.left)-1) as u8{return Err(JpegError::MalformedEntropy);}self.left=0;Ok(())}
 pub(crate) fn restart(&mut self,index:u8)->Result<(),JpegError>{self.align()?;if self.data.get(self.pos)!=Some(&255){return Err(JpegError::RestartSequence);}self.pos+=1;while self.data.get(self.pos)==Some(&255){self.pos+=1;}if self.data.get(self.pos)!=Some(&(0xd0+index)){return Err(JpegError::RestartSequence);}self.pos+=1;Ok(())}
}
pub(crate) const ZZ:[usize;64]=[0,1,8,16,9,2,3,10,17,24,32,25,18,11,4,5,12,19,26,33,40,48,41,34,27,20,13,6,7,14,21,28,35,42,49,56,57,50,43,36,29,22,15,23,30,37,44,51,58,59,52,45,38,31,39,46,53,60,61,54,47,55,62,63];
const BASIS:[[i64;8];8]=[
[11585,16069,15137,13623,11585,9102,6270,3196],
[11585,13623,6270,-3196,-11585,-16069,-15137,-9102],
[11585,9102,-6270,-16069,-11585,3196,15137,13623],
[11585,3196,-15137,-9102,11585,13623,-6270,-16069],
[11585,-3196,-15137,9102,11585,-13623,-6270,16069],
[11585,-9102,-6270,16069,-11585,-3196,15137,-13623],
[11585,-13623,6270,3196,-11585,16069,-15137,9102],
[11585,-16069,15137,-13623,11585,-9102,6270,-3196],
];
pub(crate) fn idct(coeff:&[i64;64])->Result<[u8;64],JpegError>{
 let mut out=[0u8;64];let denom=4i128*(1i128<<28);
 if coeff[1..].iter().all(|&c|c==0){let v=((coeff[0]+4).div_euclid(8)+128).clamp(0,255) as u8;return Ok([v;64]);}
 for y in 0..8 {for x in 0..8 {
  let mut sum=0i128;
  for v in 0..8{for u in 0..8{let term=(coeff[v*8+u] as i128).checked_mul(BASIS[x][u] as i128).and_then(|a|a.checked_mul(BASIS[y][v] as i128)).ok_or(JpegError::ArithmeticOverflow)?;sum=sum.checked_add(term).ok_or(JpegError::ArithmeticOverflow)?;}}
  let rounded=(sum+denom/2).div_euclid(denom);
  out[y*8+x]=(rounded+128).clamp(0,255) as u8;
 }} Ok(out)
}
#[derive(Clone)]struct Component{id:u8,h:usize,v:usize,q:usize,dc:usize,ac:usize,predictor:i32,beyond_nominal:bool}
fn block(b:&mut Bits<'_>,c:&mut Component,q:&[u16;64],dc:&Huff,ac:&Huff)->Result<[u8;64],JpegError>{
 let mut coeff=[0i64;64];let cat=dc.symbol(b)?;if cat>11{return Err(JpegError::MalformedTable);}
 c.predictor=c.predictor.checked_add(b.number(cat)?).ok_or(JpegError::ArithmeticOverflow)?;
 if !(-1024..=1023).contains(&c.predictor){c.beyond_nominal=true;}
 coeff[0]=(c.predictor as i64).checked_mul(q[0] as i64).ok_or(JpegError::ArithmeticOverflow)?;if i32::try_from(coeff[0]).is_err(){return Err(JpegError::CoefficientBound);}
 let mut k=1usize;
 while k<64 {let s=ac.symbol(b)?;let run=(s>>4) as usize;let n=s&15;
  if n==0 {if run==0{break;}if run!=15{return Err(JpegError::MalformedEntropy);}k+=16;if k>64{return Err(JpegError::MalformedEntropy);}continue;}
  if n>10{return Err(JpegError::MalformedEntropy);}k+=run;if k>=64{return Err(JpegError::MalformedEntropy);}
  let i=ZZ[k];coeff[i]=b.number(n)? as i64*q[i] as i64;k+=1;
 }idct(&coeff)
}
pub(crate) fn take<'a>(data:&'a[u8],pos:&mut usize,n:usize)->Result<&'a[u8],JpegError>{let end=pos.checked_add(n).ok_or(JpegError::ArithmeticOverflow)?;let s=data.get(*pos..end).ok_or(JpegError::Truncated)?;*pos=end;Ok(s)}
pub(crate) fn u16be(b:&[u8])->usize{((b[0] as usize)<<8)|b[1] as usize}
pub(crate) fn zeroes(n:usize)->Result<Vec<u8>,JpegError>{let mut v=Vec::new();v.try_reserve_exact(n).map_err(|_|JpegError::AllocationFailed)?;v.resize(n,0);Ok(v)}
/// Peak working bytes `decode` charges against `max_working_bytes`: a pure
/// function of the input length and the declared pixel bound (table budget,
/// fixed component state, pixel buffer and the sha/peak allowance). Exposed
/// so callers that replay the decoder's budget accounting (the pipeline's
/// parallel evidence loader) use the exact formula the decoder enforces.
pub fn working_budget_required(data_len:usize,pixels_bound:usize)->Option<usize>{
 let table_budget=9usize.checked_mul(256*std::mem::size_of::<(u16,u8,u8)>())?;
 let fixed_budget=table_budget.checked_add(4*std::mem::size_of::<[u16;64]>()+3*std::mem::size_of::<Component>()+std::mem::size_of::<[i64;64]>()+std::mem::size_of::<[u8;64]>()+std::mem::size_of::<[u32;64]>()+std::mem::size_of::<[u32;8]>())?;
 let hash_peak=data_len.max(pixels_bound).checked_add(72+3*64)?;
 fixed_budget.checked_add(pixels_bound).and_then(|v|v.checked_add(hash_peak))
}
/// Supported subset is declared in jpeg-source-v1 design. Never applies EXIF orientation.
pub fn decode(data:&[u8],limits:Limits)->Result<DecodedGray,JpegError>{
 let pixels_bound=limits.max_pixels;
 let total_budget=working_budget_required(data.len(),pixels_bound).ok_or(JpegError::ArithmeticOverflow)?;
 if total_budget>limits.max_working_bytes{return Err(JpegError::ResourceLimit);}
 if data.len()>limits.max_input_bytes{return Err(JpegError::ResourceLimit);}if data.get(..2)!=Some(&[255,216][..]){return Err(JpegError::BadSignature);}
 let mut pos=2;let mut quant:[Option<[u16;64]>;4]=[None,None,None,None];let mut dc:[Option<Huff>;4]=[None,None,None,None];let mut ac:[Option<Huff>;4]=[None,None,None,None];
 let mut components:Vec<Component>=Vec::new();components.try_reserve_exact(3).map_err(|_|JpegError::AllocationFailed)?;let(mut w,mut h)=(0usize,0usize);let mut restart=0usize;let mut jfif=false;let mut adobe=None;
 loop {
  if take(data,&mut pos,1)?[0]!=255{return Err(JpegError::MalformedMarker);}
  let mut marker=take(data,&mut pos,1)?[0];while marker==255{marker=take(data,&mut pos,1)?[0];}
  if marker==0xda && components.is_empty(){return Err(JpegError::MalformedMarker);}
  if marker==0xd9{return Err(JpegError::MalformedMarker);}
  if marker==0xd8||marker==0x00||(0xd0..=0xd7).contains(&marker){return Err(JpegError::MalformedMarker);}
  if (0xc1..=0xcf).contains(&marker)&&marker!=0xc4 {return Err(JpegError::UnsupportedMode);}
  if marker==0xdc{return Err(JpegError::UnsupportedMode);}
  let size=u16be(take(data,&mut pos,2)?);if size<2{return Err(JpegError::MalformedMarker);}let seg=take(data,&mut pos,size-2)?;
  match marker {
   0xe0=>{if seg.starts_with(b"JFIF\0"){if seg.len()<14{return Err(JpegError::MalformedMarker);}jfif=true;}},
   0xee=>{if seg.starts_with(b"Adobe"){if seg.len()<12{return Err(JpegError::MalformedMarker);}adobe=Some(seg[11]);}},
   0xe1..=0xed|0xef|0xfe=>{},
   0xdb=>{let mut i=0;while i<seg.len(){let info=take(seg,&mut i,1)?[0];let id=(info&15) as usize;if info>>4!=0{return Err(JpegError::UnsupportedQuantization);}if id>3{return Err(JpegError::MalformedTable);}let q=take(seg,&mut i,64)?;let mut table=[0u16;64];for k in 0..64{if q[k]==0{return Err(JpegError::MalformedTable);}table[ZZ[k]]=q[k] as u16;}quant[id]=Some(table);}},
   0xc4=>{let mut i=0;while i<seg.len(){let info=take(seg,&mut i,1)?[0];let id=(info&15) as usize;if id>3||info>>4>1{return Err(JpegError::MalformedTable);}let counts=take(seg,&mut i,16)?;let n=counts.iter().map(|&v|v as usize).sum();if n>256{return Err(JpegError::MalformedTable);}let table=Huff::new(counts,take(seg,&mut i,n)?)?;if info>>4==0{dc[id]=Some(table);}else{ac[id]=Some(table);}}},
   0xdd=>{if seg.len()!=2{return Err(JpegError::MalformedMarker);}restart=u16be(seg);},
   0xc0=>{
    if !components.is_empty(){return Err(JpegError::UnsupportedMode);}if seg.len()<6{return Err(JpegError::Truncated);}if seg[0]!=8{return Err(JpegError::UnsupportedPrecision);}
    h=u16be(&seg[1..3]);w=u16be(&seg[3..5]);let n=seg[5] as usize;if n!=1&&n!=3{return Err(JpegError::UnsupportedColour);}if seg.len()!=6+3*n{return Err(JpegError::MalformedDimensions);}
    if w==0||h==0{return Err(JpegError::MalformedDimensions);}if w.checked_mul(h).ok_or(JpegError::ArithmeticOverflow)?>limits.max_pixels{return Err(JpegError::ResourceLimit);}
    for s in seg[6..].chunks_exact(3){let hh=(s[1]>>4) as usize;let vv=(s[1]&15) as usize;if hh==0||vv==0||hh>4||vv>4||s[2]>3{return Err(JpegError::MalformedTable);}if components.iter().any(|c|c.id==s[0]){return Err(JpegError::MalformedMarker);}components.push(Component{id:s[0],h:hh,v:vv,q:s[2] as usize,dc:0,ac:0,predictor:0,beyond_nominal:false});}
    if components.iter().map(|c|c.h*c.v).sum::<usize>()>10{return Err(JpegError::UnsupportedSampling);}
    if n==1&&(components[0].h!=1||components[0].v!=1){return Err(JpegError::UnsupportedSampling);}
   },
   0xda=>{
    let n=components.len();if adobe.is_some()&&adobe!=Some(1){return Err(JpegError::UnsupportedColour);}if seg.len()!=1+2*n+3||seg[0] as usize!=n{return Err(JpegError::UnsupportedScan);}
    if seg[1+2*n..]!=[0,63,0]{return Err(JpegError::UnsupportedScan);}
    if n==3 {if adobe.is_some()&&adobe!=Some(1){return Err(JpegError::UnsupportedColour);}if !jfif&&adobe!=Some(1){return Err(JpegError::UnsupportedColour);}if components.iter().enumerate().any(|(i,c)|c.id!=(i+1) as u8){return Err(JpegError::UnsupportedColour);}}
    for i in 0..n{if seg[1+2*i]!=components[i].id{return Err(JpegError::UnsupportedScan);}let selector=seg[2+2*i];if selector>>4>3||selector&15>3{return Err(JpegError::MalformedTable);}components[i].dc=(selector>>4) as usize;components[i].ac=(selector&15) as usize;}
    let mh=components.iter().map(|c|c.h).max().unwrap();let mv=components.iter().map(|c|c.v).max().unwrap();
    if components[0].h!=mh||components[0].v!=mv||components.iter().any(|c|mh%c.h!=0||mv%c.v!=0){return Err(JpegError::UnsupportedSampling);}
    let cols=(w+8*mh-1)/(8*mh);let rows=(h+8*mv-1)/(8*mv);let total=cols.checked_mul(rows).ok_or(JpegError::ArithmeticOverflow)?;
    let mut pixels=zeroes(w*h)?;let mut bits=Bits{data,pos,byte:0,left:0};let mut rst=0u8;
    for m in 0..total {
     if restart>0&&m>0&&m%restart==0{bits.restart(rst)?;rst=(rst+1)%8;for c in &mut components{c.predictor=0;}}
     for (ci,c) in components.iter_mut().enumerate(){let qt=quant[c.q].as_ref().ok_or(JpegError::MalformedTable)?;let dt=dc[c.dc].as_ref().ok_or(JpegError::MalformedTable)?;let at=ac[c.ac].as_ref().ok_or(JpegError::MalformedTable)?;
      for by in 0..c.v{for bx in 0..c.h{let samples=block(&mut bits,c,qt,dt,at)?;if ci==0{let x0=(m%cols)*mh*8+bx*8;let y0=(m/cols)*mv*8+by*8;for y in 0..8{for x in 0..8{if x0+x<w&&y0+y<h{pixels[(y0+y)*w+x0+x]=samples[y*8+x];}}}}}}
     }
    }
    bits.align()?;pos=bits.pos;
    if take(data,&mut pos,1)?[0]!=255{return Err(JpegError::MalformedMarker);}let mut end=take(data,&mut pos,1)?[0];while end==255{end=take(data,&mut pos,1)?[0];}
    if end==0xda{return Err(JpegError::UnsupportedScan);}if end!=0xd9{return Err(if (0xd0..=0xd7).contains(&end){JpegError::RestartSequence}else{JpegError::MalformedMarker});}if pos!=data.len(){return Err(JpegError::TrailingData);}
    let receipt=IdentityReceipt{orig_sha256:sha256_hex(data)?,decoded_gray_sha256:sha256_hex(&pixels)?,orig_len:data.len(),w,h,dtype:"u8",value_range:(0,255),row_order:"top_to_bottom",stride:w,serialization:"one_byte_per_sample_row_major",subset_status:"supported_declared_subset",config_pin:sha256_hex(b"kni.jpeg-source.config.v1\nIDCT=Q14-direct\nround=floor(x+0.5)\nDC=exact\noutput=raw-Y\ntrailing=refuse\n")?,decoder_version:DECODER_VERSION,beyond_nominal_quantized_11bit:components.iter().any(|c|c.beyond_nominal)};return Ok(DecodedGray{w,h,pixels,receipt});
   },
   _=>return Err(JpegError::UnsupportedMode),
  }
 }
}

pub(crate) fn sha256_hex(data: &[u8]) -> Result<String,JpegError> {
    const K: [u32; 64] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    let mut h: [u32; 8] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    let size=data.len().checked_add(72).ok_or(JpegError::ArithmeticOverflow)?;
    let mut m=Vec::new();m.try_reserve_exact(size).map_err(|_|JpegError::AllocationFailed)?;m.extend_from_slice(data);
    m.push(0x80);
    while m.len() % 64 != 56 { m.push(0); }
    m.extend_from_slice(&((data.len() as u64) * 8).to_be_bytes());
    for chunk in m.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 { w[i] = u32::from_be_bytes([chunk[4*i],chunk[4*i+1],chunk[4*i+2],chunk[4*i+3]]); }
        for i in 16..64 {
            let s0 = w[i-15].rotate_right(7) ^ w[i-15].rotate_right(18) ^ (w[i-15] >> 3);
            let s1 = w[i-2].rotate_right(17) ^ w[i-2].rotate_right(19) ^ (w[i-2] >> 10);
            w[i] = w[i-16].wrapping_add(s0).wrapping_add(w[i-7]).wrapping_add(s1);
        }
        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ (!v[4] & v[6]);
            let t1 = v[7].wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(maj);
            v[7]=v[6]; v[6]=v[5]; v[5]=v[4]; v[4]=v[3].wrapping_add(t1);
            v[3]=v[2]; v[2]=v[1]; v[1]=v[0]; v[0]=t1.wrapping_add(t2);
        }
        for i in 0..8 { h[i] = h[i].wrapping_add(v[i]); }
    }
    let mut out=String::new();out.try_reserve_exact(64).map_err(|_|JpegError::AllocationFailed)?;
    const HEX:&[u8;16]=b"0123456789abcdef";
    for word in h {for shift in (0..8).rev(){out.push(HEX[((word>>(shift*4))&15) as usize] as char);}}
    Ok(out)
}

/// Frame type of a JPEG, read from the FIRST SOFn marker only (bounded marker walk, no entropy decode, no allocation).
/// Used by `capture_dispatch::decode_source` so that one dispatcher routes every consumer (stage 1, IoU, bound-detector validator, budget meta).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FrameKind { BaselineSof0, ProgressiveSof2 }
pub fn frame_kind(data: &[u8]) -> Result<FrameKind, JpegError> {
    if data.get(..2) != Some(&[255, 216][..]) { return Err(JpegError::BadSignature); }
    let mut pos = 2usize;
    loop {
        if data.get(pos) != Some(&255) { return if pos >= data.len() { Err(JpegError::Truncated) } else { Err(JpegError::MalformedMarker) }; }
        while data.get(pos) == Some(&255) { pos += 1; }
        let marker = *data.get(pos).ok_or(JpegError::Truncated)?;
        pos += 1;
        match marker {
            0xc0 => return Ok(FrameKind::BaselineSof0),
            0xc2 => return Ok(FrameKind::ProgressiveSof2),
            0xc1 | 0xc3 | 0xc5..=0xc7 | 0xc9..=0xcb | 0xcd..=0xcf | 0xdc => return Err(JpegError::UnsupportedMode),
            0x00 | 0x01 | 0xd0..=0xd9 => return Err(JpegError::MalformedMarker), // SOI again, RSTn, EOI or TEM before any frame header
            _ => {
                let hi = *data.get(pos).ok_or(JpegError::Truncated)? as usize; let lo = *data.get(pos + 1).ok_or(JpegError::Truncated)? as usize;
                let size = (hi << 8) | lo; if size < 2 { return Err(JpegError::MalformedMarker); }
                pos = pos.checked_add(size).ok_or(JpegError::ArithmeticOverflow)?;
                if pos > data.len() { return Err(JpegError::Truncated); }
                if marker == 0xda { return Err(JpegError::MalformedMarker); } // scan before any frame header
            }
        }
    }
}
/// Single native dispatcher. SOF0/other -> `decode` (kni.jpeg-source.v1-q14); SOF2 -> `crate::jpeg_progressive::decode` (landed W4 module, same Limits,
/// same raw-Y 8-bit row-major top-down IdentityReceipt, its own decoder_version/config_pin). No conversion, no Pillow/sips equivalence claim, no fallback.
pub fn decode_any(data: &[u8], limits: Limits) -> Result<DecodedGray, JpegError> {
    // Input bound FIRST, before any marker walk (both decoders repeat it).
    if data.len() > limits.max_input_bytes { return Err(JpegError::ResourceLimit); }
    match frame_kind(data) {
        Ok(FrameKind::ProgressiveSof2) => crate::jpeg_progressive::decode(data, limits),
        // SOF0, and every header frame_kind itself refuses: the baseline decoder runs unchanged and keeps its own typed refusals (no behaviour change for non-SOF2 input).
        Ok(FrameKind::BaselineSof0) | Err(_) => decode(data, limits),
    }
}
#[cfg(test)]
mod frame_kind_tests {
    use super::*;
    fn seg(m: u8, body: &[u8]) -> Vec<u8> { let mut v = vec![255, m]; let n = body.len() + 2; v.push((n >> 8) as u8); v.push(n as u8); v.extend_from_slice(body); v }
    fn jpeg(sof: u8) -> Vec<u8> { let mut v = vec![255, 216]; v.extend(seg(0xe0, b"JFIF\0\x01\x01\0\0\x01\0\x01\0\0")); v.extend(seg(sof, &[8, 0, 8, 0, 8, 1, 1, 0x11, 0])); v }
    #[test] fn sof0_is_baseline() { assert_eq!(frame_kind(&jpeg(0xc0)), Ok(FrameKind::BaselineSof0)); }
    #[test] fn sof2_is_progressive() { assert_eq!(frame_kind(&jpeg(0xc2)), Ok(FrameKind::ProgressiveSof2)); }
    #[test] fn other_sof_is_unsupported_mode() { for m in [0xc1u8, 0xc3, 0xc9, 0xca, 0xcf] { assert_eq!(frame_kind(&jpeg(m)), Err(JpegError::UnsupportedMode)); } }
    #[test] fn dht_marker_c4_is_not_a_frame_header() { let mut v = vec![255, 216]; v.extend(seg(0xc4, &[0; 17])); v.extend(seg(0xc2, &[8, 0, 8, 0, 8, 1, 1, 0x11, 0])); assert_eq!(frame_kind(&v), Ok(FrameKind::ProgressiveSof2)); }
    #[test] fn scan_before_frame_is_malformed() { let mut v = vec![255, 216]; v.extend(seg(0xda, &[0, 0])); assert_eq!(frame_kind(&v), Err(JpegError::MalformedMarker)); }
    #[test] fn truncated_and_bad_signature() { assert_eq!(frame_kind(&[255, 216]), Err(JpegError::Truncated)); assert_eq!(frame_kind(&[0, 0]), Err(JpegError::BadSignature)); }
    #[test] fn decode_any_checks_input_bound_before_marker_walk() { let lim = Limits { max_input_bytes: 3, max_pixels: 64, max_working_bytes: 1 << 20 }; assert_eq!(decode_any(&jpeg(0xc2), lim).err(), Some(JpegError::ResourceLimit)); assert_eq!(decode_any(&[0, 0, 0, 0], lim).err(), Some(JpegError::ResourceLimit)); }
    #[test] fn decode_any_sof_other_keeps_baseline_typed_refusal() { let lim = Limits { max_input_bytes: 1 << 20, max_pixels: 64, max_working_bytes: 1 << 20 }; assert_eq!(decode_any(&jpeg(0xc9), lim).err(), Some(JpegError::UnsupportedMode)); assert_eq!(decode_any(&[1, 2, 3, 4], lim).err(), Some(JpegError::BadSignature)); }
    #[test] fn no_fill_loop_on_overlong_size() { let v = vec![255, 216, 255, 0xe0, 0xff, 0xff]; assert_eq!(frame_kind(&v), Err(JpegError::Truncated)); }
}
