// Test the real library API: a #[path] harness copy of jpeg_source.rs cannot
// resolve the source's internal `crate::jpeg_progressive` dispatch (the copy's
// Limits/DecodedGray/JpegError would be distinct types from the crate's own),
// and every item under test here is public.
use kni_core::jpeg_source::{decode,Limits,JpegError};
fn segment(out:&mut Vec<u8>,marker:u8,bytes:&[u8]){out.extend_from_slice(&[255,marker]);out.extend_from_slice(&((bytes.len()+2) as u16).to_be_bytes());out.extend_from_slice(bytes);}
fn fixture(dc:i32,color:bool)->Vec<u8>{
 let n=if color{3}else{1};let mut out=vec![255,216];segment(&mut out,0xe0,b"JFIF\0\x01\x01\0\0\x01\0\x01\0\0");let mut q=vec![0];q.extend_from_slice(&[1;64]);segment(&mut out,0xdb,&q);
 let mut sof=vec![8,0,8,0,8,n];for i in 0..n{sof.extend_from_slice(&[i+1,0x11,0]);}segment(&mut out,0xc0,&sof);
 let mut tables=vec![0,0,0,0,12];tables.extend_from_slice(&[0;12]);tables.extend(0..12);tables.push(0x10);tables.push(1);tables.extend_from_slice(&[0;15]);tables.push(0);segment(&mut out,0xc4,&tables);
 let mut sos=vec![n];for i in 0..n{sos.extend_from_slice(&[i+1,0]);}sos.extend_from_slice(&[0,63,0]);segment(&mut out,0xda,&sos);
 let mut bits=Vec::new();for c in 0..n{let v=if c==0{dc}else{0};let size=32-v.unsigned_abs().leading_zeros();for k in (0..4).rev(){bits.push(((size>>k)&1) as u8);}let value=if v>=0{v}else{v+(1<<size)-1};for k in (0..size).rev(){bits.push(((value>>k)&1) as u8);}bits.push(0);}
 while bits.len()%8!=0{bits.push(1);}for chunk in bits.chunks(8){let byte=chunk.iter().fold(0,|a,&b|(a<<1)|b);out.push(byte);if byte==255{out.push(0);}}out.extend_from_slice(&[255,217]);out
}
fn limits()->Limits{Limits{max_input_bytes:100000,max_pixels:10000,max_working_bytes:200000}}
#[test]fn dc_reference_pixels_and_hashes(){
 let cases=[(0,false,"d31f9048b78461ac216a03b34f05ecabac98aacc8321b6e994a5ac263b62909f",128),(80,false,"8f4bd25d514d92140bc1de761f34f26b5669c67e3f6518609ace887e4d96224e",138),(-80,false,"98e4567020742266ce0eef68423eb9baf2832fbd8086dc58a85afcfbb4b29389",118),(0,true,"6ff35cb5a5164a54288416ed05e94d8dc476d6be1ace90171018eda1538bc032",128),(80,true,"d4ac06ab6546a10541697718d50ea1a743239db4d201c291772cf698e72a2fef",138)];
 for (dc,color,sha,value) in cases {let bytes=fixture(dc,color);let original=bytes.clone();let decoded=decode(&bytes,limits()).unwrap();assert_eq!(decoded.receipt.orig_sha256,sha);assert_eq!(decoded.pixels,vec![value;64]);assert_eq!(bytes,original);assert_eq!(decoded,decode(&bytes,limits()).unwrap());println!("fixture dc={dc} color={color} max_abs=0 mean_abs=0 histogram=0:64");}
}
#[test]fn cross_file_identity(){let a=decode(&fixture(0,false),limits()).unwrap();let b=decode(&fixture(0,true),limits()).unwrap();assert_ne!(a.receipt.orig_sha256,b.receipt.orig_sha256);assert_eq!(a.receipt.decoded_gray_sha256,b.receipt.decoded_gray_sha256);}
#[test]fn truncated_prefixes(){let good=fixture(0,false);for n in 0..good.len(){assert!(decode(&good[..n],limits()).is_err(),"prefix {n}");}}
#[test]fn signature_and_resource(){assert_eq!(decode(b"not jpeg",limits()),Err(JpegError::BadSignature));let mut l=limits();l.max_pixels=1;assert_eq!(decode(&fixture(0,false),l),Err(JpegError::ResourceLimit));}
#[test]fn progressive_and_trailing_refusal(){let mut b=fixture(0,false);let p=b.windows(2).position(|v|v==[255,192]).unwrap();b[p+1]=194;assert_ne!(b,fixture(0,false));assert!(matches!(decode(&b,limits()),Err(JpegError::UnsupportedMode)));let mut b=fixture(0,false);b.push(0);assert_ne!(b,fixture(0,false));assert_eq!(decode(&b,limits()),Err(JpegError::TrailingData));}
#[test]fn frozen_oracle_suite(){
 let cases:&[(&str,&[u8],&[u8],&[u8],bool)]=&[
("gray_dc0",include_bytes!("fixtures/jpeg_source/gray_dc0.jpg"),include_bytes!("fixtures/jpeg_source/gray_dc0.gray"),include_bytes!("fixtures/jpeg_source/gray_dc0.real-gray"),true),
("gray_dc_half_negative",include_bytes!("fixtures/jpeg_source/gray_dc_half_negative.jpg"),include_bytes!("fixtures/jpeg_source/gray_dc_half_negative.gray"),include_bytes!("fixtures/jpeg_source/gray_dc_half_negative.real-gray"),true),
("gray_ac1",include_bytes!("fixtures/jpeg_source/gray_ac1.jpg"),include_bytes!("fixtures/jpeg_source/gray_ac1.gray"),include_bytes!("fixtures/jpeg_source/gray_ac1.real-gray"),true),
("gray_dense",include_bytes!("fixtures/jpeg_source/gray_dense.jpg"),include_bytes!("fixtures/jpeg_source/gray_dense.gray"),include_bytes!("fixtures/jpeg_source/gray_dense.real-gray"),true),
("gray_dense_max",include_bytes!("fixtures/jpeg_source/gray_dense_max.jpg"),include_bytes!("fixtures/jpeg_source/gray_dense_max.gray"),include_bytes!("fixtures/jpeg_source/gray_dense_max.real-gray"),false),
("gray_dense_domain",include_bytes!("fixtures/jpeg_source/gray_dense_domain.jpg"),include_bytes!("fixtures/jpeg_source/gray_dense_domain.gray"),include_bytes!("fixtures/jpeg_source/gray_dense_domain.real-gray"),false),
("gray_clip_hi",include_bytes!("fixtures/jpeg_source/gray_clip_hi.jpg"),include_bytes!("fixtures/jpeg_source/gray_clip_hi.gray"),include_bytes!("fixtures/jpeg_source/gray_clip_hi.real-gray"),false),
("gray_clip_lo",include_bytes!("fixtures/jpeg_source/gray_clip_lo.jpg"),include_bytes!("fixtures/jpeg_source/gray_clip_lo.gray"),include_bytes!("fixtures/jpeg_source/gray_clip_lo.real-gray"),false),
("ycbcr_444",include_bytes!("fixtures/jpeg_source/ycbcr_444.jpg"),include_bytes!("fixtures/jpeg_source/ycbcr_444.gray"),include_bytes!("fixtures/jpeg_source/ycbcr_444.real-gray"),true),
("ycbcr_422",include_bytes!("fixtures/jpeg_source/ycbcr_422.jpg"),include_bytes!("fixtures/jpeg_source/ycbcr_422.gray"),include_bytes!("fixtures/jpeg_source/ycbcr_422.real-gray"),true),
("ycbcr_420",include_bytes!("fixtures/jpeg_source/ycbcr_420.jpg"),include_bytes!("fixtures/jpeg_source/ycbcr_420.gray"),include_bytes!("fixtures/jpeg_source/ycbcr_420.real-gray"),true),
("gray_restart",include_bytes!("fixtures/jpeg_source/gray_restart.jpg"),include_bytes!("fixtures/jpeg_source/gray_restart.gray"),include_bytes!("fixtures/jpeg_source/gray_restart.real-gray"),true),
("bisect_255",include_bytes!("fixtures/jpeg_source/bisect_255.jpg"),include_bytes!("fixtures/jpeg_source/bisect_255.gray"),include_bytes!("fixtures/jpeg_source/bisect_255.real-gray"),true),
("bisect_511",include_bytes!("fixtures/jpeg_source/bisect_511.jpg"),include_bytes!("fixtures/jpeg_source/bisect_511.gray"),include_bytes!("fixtures/jpeg_source/bisect_511.real-gray"),true),
("bisect_1023",include_bytes!("fixtures/jpeg_source/bisect_1023.jpg"),include_bytes!("fixtures/jpeg_source/bisect_1023.gray"),include_bytes!("fixtures/jpeg_source/bisect_1023.real-gray"),false),
("bisect_2046",include_bytes!("fixtures/jpeg_source/bisect_2046.jpg"),include_bytes!("fixtures/jpeg_source/bisect_2046.gray"),include_bytes!("fixtures/jpeg_source/bisect_2046.real-gray"),false),
("bisect_2048",include_bytes!("fixtures/jpeg_source/bisect_2048.jpg"),include_bytes!("fixtures/jpeg_source/bisect_2048.gray"),include_bytes!("fixtures/jpeg_source/bisect_2048.real-gray"),false),
("bisect_4095",include_bytes!("fixtures/jpeg_source/bisect_4095.jpg"),include_bytes!("fixtures/jpeg_source/bisect_4095.gray"),include_bytes!("fixtures/jpeg_source/bisect_4095.real-gray"),false),
("bisect_8190",include_bytes!("fixtures/jpeg_source/bisect_8190.jpg"),include_bytes!("fixtures/jpeg_source/bisect_8190.gray"),include_bytes!("fixtures/jpeg_source/bisect_8190.real-gray"),false),
("bisect_65535",include_bytes!("fixtures/jpeg_source/bisect_65535.jpg"),include_bytes!("fixtures/jpeg_source/bisect_65535.gray"),include_bytes!("fixtures/jpeg_source/bisect_65535.real-gray"),false),
("range_0",include_bytes!("fixtures/jpeg_source/range_0.jpg"),include_bytes!("fixtures/jpeg_source/range_0.gray"),include_bytes!("fixtures/jpeg_source/range_0.real-gray"),true),
("range_8",include_bytes!("fixtures/jpeg_source/range_8.jpg"),include_bytes!("fixtures/jpeg_source/range_8.gray"),include_bytes!("fixtures/jpeg_source/range_8.real-gray"),true),
("range_16",include_bytes!("fixtures/jpeg_source/range_16.jpg"),include_bytes!("fixtures/jpeg_source/range_16.gray"),include_bytes!("fixtures/jpeg_source/range_16.real-gray"),true),
("range_24",include_bytes!("fixtures/jpeg_source/range_24.jpg"),include_bytes!("fixtures/jpeg_source/range_24.gray"),include_bytes!("fixtures/jpeg_source/range_24.real-gray"),true),
("range_32",include_bytes!("fixtures/jpeg_source/range_32.jpg"),include_bytes!("fixtures/jpeg_source/range_32.gray"),include_bytes!("fixtures/jpeg_source/range_32.real-gray"),true),
("range_48",include_bytes!("fixtures/jpeg_source/range_48.jpg"),include_bytes!("fixtures/jpeg_source/range_48.gray"),include_bytes!("fixtures/jpeg_source/range_48.real-gray"),true),
("range_64",include_bytes!("fixtures/jpeg_source/range_64.jpg"),include_bytes!("fixtures/jpeg_source/range_64.gray"),include_bytes!("fixtures/jpeg_source/range_64.real-gray"),true),
("range_96",include_bytes!("fixtures/jpeg_source/range_96.jpg"),include_bytes!("fixtures/jpeg_source/range_96.gray"),include_bytes!("fixtures/jpeg_source/range_96.real-gray"),true),
("range_128",include_bytes!("fixtures/jpeg_source/range_128.jpg"),include_bytes!("fixtures/jpeg_source/range_128.gray"),include_bytes!("fixtures/jpeg_source/range_128.real-gray"),true),
("range_192",include_bytes!("fixtures/jpeg_source/range_192.jpg"),include_bytes!("fixtures/jpeg_source/range_192.gray"),include_bytes!("fixtures/jpeg_source/range_192.real-gray"),true),
("range_256",include_bytes!("fixtures/jpeg_source/range_256.jpg"),include_bytes!("fixtures/jpeg_source/range_256.gray"),include_bytes!("fixtures/jpeg_source/range_256.real-gray"),true),
("range_384",include_bytes!("fixtures/jpeg_source/range_384.jpg"),include_bytes!("fixtures/jpeg_source/range_384.gray"),include_bytes!("fixtures/jpeg_source/range_384.real-gray"),true),
("range_512",include_bytes!("fixtures/jpeg_source/range_512.jpg"),include_bytes!("fixtures/jpeg_source/range_512.gray"),include_bytes!("fixtures/jpeg_source/range_512.real-gray"),false),
("range_768",include_bytes!("fixtures/jpeg_source/range_768.jpg"),include_bytes!("fixtures/jpeg_source/range_768.gray"),include_bytes!("fixtures/jpeg_source/range_768.real-gray"),false),
("range_1023",include_bytes!("fixtures/jpeg_source/range_1023.jpg"),include_bytes!("fixtures/jpeg_source/range_1023.gray"),include_bytes!("fixtures/jpeg_source/range_1023.real-gray"),false),
("image_checker",include_bytes!("fixtures/jpeg_source/image_checker.jpg"),include_bytes!("fixtures/jpeg_source/image_checker.gray"),include_bytes!("fixtures/jpeg_source/image_checker.real-gray"),true),
("image_gradient",include_bytes!("fixtures/jpeg_source/image_gradient.jpg"),include_bytes!("fixtures/jpeg_source/image_gradient.gray"),include_bytes!("fixtures/jpeg_source/image_gradient.real-gray"),true),
("image_noise",include_bytes!("fixtures/jpeg_source/image_noise.jpg"),include_bytes!("fixtures/jpeg_source/image_noise.gray"),include_bytes!("fixtures/jpeg_source/image_noise.real-gray"),true),
 ];let mut defects=Vec::new();
 for &(name,input,oracle,real,inside) in cases {
  let decoded=decode(input,limits()).unwrap();assert_eq!(decoded.pixels.len(),oracle.len());
  for (label,expected) in [("Pillow",oracle),("real-IDCT-descriptive",real)] {
   let mut histogram=[0usize;256];let mut total=0usize;let mut max=0u8;
   for (&a,&b) in decoded.pixels.iter().zip(expected){let e=a.abs_diff(b);histogram[e as usize]+=1;total+=e as usize;max=max.max(e);}
   println!("{name} target={label} inside_oracle_range={inside} max_abs={max} mean_abs={} histogram={histogram:?}",total as f64/expected.len() as f64);
   if label=="Pillow"&&inside&&max>1{defects.push(format!("{name}: {max}"));}
   if label=="real-IDCT-descriptive"&&(name.contains("dc")||name.contains("clip")){assert_eq!(max,0,"DC mathematical exact {name}");}
  }
  assert_eq!(decoded,decode(input,limits()).unwrap());
 }
 assert!(defects.is_empty(),"range-calibrated defects: {defects:?}");
}
#[test]fn png_path_unchanged(){
 let png=include_bytes!("fixtures/jpeg_source/png_guard.png");let (w,h,p)=kni_core::capture::decode_png_gray(png).unwrap();assert_eq!((w,h),(8,8));
 let mut expected=vec![255;64];for y in 2..=6{for x in 2..=6{expected[y*8+x]=0;}}assert_eq!(p,expected);
 let c=kni_core::capture::capture_png(png,0.0).unwrap();assert_eq!((c.width,c.height),(8,8));assert_eq!((c.origin_x,c.origin_y),(2.0,-7.0));assert_eq!(c.rings.len(),1);let r=&c.rings[0];assert!(!r.hole);assert_eq!(r.corners,vec![1,6]);
 let points:Vec<(f64,f64)>=r.points.iter().map(|p|(p.x,p.y)).collect();assert_eq!(points,vec![(0.,3.5),(0.,0.5),(0.5,0.),(4.5,0.),(5.,0.5),(5.,4.5),(4.5,5.),(0.5,5.),(0.,4.5)]);
}

#[test]fn malformed_modes_tables_restart(){
 let source=include_bytes!("fixtures/jpeg_source/gray_dc0.jpg");
 for (marker,offset,value) in [(0xc0,4,12),(0xc0,8,0),(0xc0,9,0),(0xdb,4,0x10)] {
  let mut bytes=source.to_vec();let p=bytes.windows(2).position(|v|v==[255,marker]).unwrap();bytes[p+offset]=value;assert_ne!(bytes.as_slice(),source.as_slice(),"mutation {marker:x}/{offset} must change bytes");assert!(decode(&bytes,limits()).is_err());
 }
 let mut bytes=include_bytes!("fixtures/jpeg_source/gray_restart.jpg").to_vec();let p=bytes.windows(2).position(|v|v==[255,208]).unwrap();bytes[p+1]=209;assert_ne!(bytes.as_slice(),include_bytes!("fixtures/jpeg_source/gray_restart.jpg").as_slice());assert!(matches!(decode(&bytes,limits()),Err(JpegError::RestartSequence)));
}

#[test]fn working_budget_and_config_identity(){
 let input=fixture(0,false);let mut low=limits();low.max_working_bytes=1;assert_eq!(decode(&input,low),Err(JpegError::ResourceLimit));
 let d=decode(&input,limits()).unwrap();assert_eq!(d.receipt.config_pin.len(),64);assert_eq!(d.receipt.orig_len,input.len());assert_eq!(d.receipt.dtype,"u8");assert_eq!(d.receipt.stride,8);
}
#[test]fn stable_error_codes(){
 use JpegError::*;
 let cases=[(BadSignature,"bad_signature"),(Truncated,"truncated"),(UnsupportedMode,"unsupported_mode"),(UnsupportedPrecision,"unsupported_precision"),(UnsupportedColour,"unsupported_colour"),(UnsupportedSampling,"unsupported_sampling"),(UnsupportedScan,"unsupported_scan"),(UnsupportedQuantization,"unsupported_quantization"),(MalformedDimensions,"malformed_dimensions"),(MalformedTable,"malformed_table"),(MalformedEntropy,"malformed_entropy"),(MalformedMarker,"malformed_marker"),(RestartSequence,"restart_sequence"),(CoefficientBound,"coefficient_bound"),(ArithmeticOverflow,"arithmetic_overflow"),(ResourceLimit,"resource_limit"),(AllocationFailed,"allocation_failed"),(TrailingData,"trailing_data")];
 for (error,code) in cases{assert_eq!(error.code(),code);}
 // This asserts the enum/accessor contract, not allocation failure injection.
}
#[test]fn induced_typed_refusals(){
 let src=include_bytes!("fixtures/jpeg_source/gray_dc0.jpg");
 // Mutations address actual marker payload bytes and prove non-no-op.
 let cases=[(0xc0,4,12,JpegError::UnsupportedPrecision),
 (0xc0,8,0,JpegError::MalformedDimensions),
 (0xc0,9,2,JpegError::UnsupportedColour),
 (0xc0,11,0x22,JpegError::UnsupportedSampling),
 (0xdb,4,0x10,JpegError::UnsupportedQuantization),
 (0xdb,5,0,JpegError::MalformedTable),
 (0xda,4,0,JpegError::UnsupportedScan),
 (0xda,3,1,JpegError::MalformedMarker)];
 for (marker,offset,value,expected) in cases {
  let mut b=src.to_vec();let pos=b.windows(2).position(|v|v==[255,marker]).unwrap();b[pos+offset]=value;assert_ne!(b.as_slice(),src.as_slice());
  assert_eq!(decode(&b,limits()),Err(expected),"marker={marker:x} offset={offset}");
 }
 // AC symbol with run=1,size=0 is neither EOB nor ZRL.
 let mut entropy=fixture(0,false);let dht=entropy.windows(2).position(|v|v==[255,196]).unwrap();let mut cursor=dht+4;let end=dht+2+u16::from_be_bytes([entropy[dht+2],entropy[dht+3]]) as usize;let mut used_eob=None;while cursor<end{let info=entropy[cursor];let count:usize=entropy[cursor+1..cursor+17].iter().map(|&v|v as usize).sum();let values=cursor+17;if info==0x10{used_eob=Some(values+entropy[values..values+count].iter().position(|&v|v==0).unwrap());break;}cursor=values+count;}let at=used_eob.unwrap();assert_eq!(entropy[at],0);entropy[at]=0x10;assert_ne!(entropy,fixture(0,false));assert_eq!(decode(&entropy,limits()),Err(JpegError::MalformedEntropy));
 // Valid repeated category-11 positive differences accumulate DC until q255 exceeds i32.
 let mut bound=fixture(2047,false);let sof=bound.windows(2).position(|v|v==[255,192]).unwrap();bound[sof+7..sof+9].copy_from_slice(&65528u16.to_be_bytes());let q=bound.windows(2).position(|v|v==[255,219]).unwrap();bound[q+5..q+69].fill(255);let sos=bound.windows(2).position(|v|v==[255,218]).unwrap();let start=sos+2+u16::from_be_bytes([bound[sos+2],bound[sos+3]]) as usize;bound.truncate(start);for _ in 0..8191{bound.extend_from_slice(&[0xbf,0xfe]);}bound.extend_from_slice(&[255,217]);let large=Limits{max_input_bytes:100000,max_pixels:600000,max_working_bytes:2000000};assert_eq!(decode(&bound,large),Err(JpegError::CoefficientBound));
 // Unexpected standalone marker is a syntax refusal, not truncation concealment.
 let mut bad=src.to_vec();bad[2]=0;assert_ne!(bad.as_slice(),src.as_slice());assert_eq!(decode(&bad,limits()),Err(JpegError::MalformedMarker));
 let mut arithmetic=limits();arithmetic.max_pixels=usize::MAX;arithmetic.max_working_bytes=usize::MAX;
 assert_eq!(decode(src,arithmetic),Err(JpegError::ArithmeticOverflow));
}
