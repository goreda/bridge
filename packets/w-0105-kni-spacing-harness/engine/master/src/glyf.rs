//! Bounded TrueType simple-outline decoder. Quadratics are degree-elevated
//! into the existing cubic model with explicit binary64 arithmetic.
//! Composite outlines are not supported in this simple-only stage.
use crate::model::{Op,Pt};
use crate::otf::ReadError;
fn bad(gid:u16,reason:&'static str)->ReadError{ReadError::BadGlyf{gid,reason}}
fn u16be(d:&[u8],p:&mut usize)->Result<u16,ReadError>{let b=d.get(*p..p.checked_add(2).ok_or(ReadError::Truncated("glyf"))?).ok_or(ReadError::Truncated("glyf"))?;*p+=2;Ok(u16::from_be_bytes([b[0],b[1]]))}
fn byte(d:&[u8],p:&mut usize)->Result<u8,ReadError>{let b=*d.get(*p).ok_or(ReadError::Truncated("glyf"))?;*p+=1;Ok(b)}
fn mid(a:Pt,b:Pt)->Pt{(a.0/2.+b.0/2.,a.1/2.+b.1/2.)}
fn quad(out:&mut Vec<Op>,start:Pt,control:Pt,end:Pt){out.push(Op::Curve((start.0+(control.0-start.0)*(2./3.),start.1+(control.1-start.1)*(2./3.)),(end.0+(control.0-end.0)*(2./3.),end.1+(control.1-end.1)*(2./3.)),end));}
fn contour(points:&[(Pt,bool)])->Vec<Op>{let n=points.len();let (start,first,count)=if points[0].1{(points[0].0,1,n-1)}else if points[n-1].1{(points[n-1].0,0,n-1)}else{(mid(points[n-1].0,points[0].0),0,n)};let mut out=vec![Op::Move(start)];let mut current=start;let mut i=0;while i<count{let(p,on)=points[(first+i)%n];if on{out.push(Op::Line(p));current=p;i+=1;}else{let(next,next_on)=if i+1<count{points[(first+i+1)%n]}else{(start,true)};let end=if next_on{next}else{mid(p,next)};quad(&mut out,current,p,end);current=end;i+=if next_on&&i+1<count{2}else{1};}}if current!=start{out.push(Op::Line(start));}out.push(Op::Close);out}
pub(crate) fn decode_simple(d:&[u8],gid:u16)->Result<Vec<Vec<Op>>,ReadError>{if d.is_empty(){return Ok(vec![])}if d.len()<10{return Err(ReadError::Truncated("glyf header"))}let mut p=0;let contours=u16be(d,&mut p)? as i16;if contours<0{return Err(ReadError::Unsupported("composite glyf outlines".into()))}p=10;if contours==0&&d.len()==10{return Ok(vec![])}let mut ends=Vec::new();for _ in 0..contours{let e=u16be(d,&mut p)? as usize;if ends.last().is_some_and(|x|e<=*x){return Err(bad(gid,"non-increasing contour endpoints"))}ends.push(e);}let count=ends.last().map_or(0,|e|e+1);let instructions=u16be(d,&mut p)? as usize;p=p.checked_add(instructions).ok_or(ReadError::Truncated("glyf instructions"))?;if p>d.len(){return Err(ReadError::Truncated("glyf instructions"))}let mut flags=Vec::with_capacity(count);while flags.len()<count{let f=byte(d,&mut p)?;if f&0x80!=0{return Err(bad(gid,"reserved simple flag"))}let copies=if f&8!=0{byte(d,&mut p)? as usize+1}else{1};if copies>count-flags.len(){return Err(bad(gid,"flag repeat exceeds point count"))}flags.extend(std::iter::repeat(f).take(copies));}let mut xy=[Vec::with_capacity(count),Vec::with_capacity(count)];for axis in 0..2{let(short,same)=if axis==0{(2,16)}else{(4,32)};let mut value=0i32;for f in &flags{let delta=if f&short!=0{let v=byte(d,&mut p)? as i32;if f&same!=0{v}else{-v}}else if f&same!=0{0}else{u16be(d,&mut p)? as i16 as i32};value=value.checked_add(delta).ok_or_else(||bad(gid,"coordinate overflow"))?;if !(-32768..=32767).contains(&value){return Err(bad(gid,"coordinate outside int16 range"))}xy[axis].push(value as f64);}}let mut output=Vec::new();let mut start=0;for end in ends{let points=(start..=end).map(|i|((xy[0][i],xy[1][i]),flags[i]&1!=0)).collect::<Vec<_>>();output.push(contour(&points));start=end+1;}Ok(output)}

// Resource guard, not a shape tolerance. Only active recursion cycles are refused; sibling references are legal.
// CONVENTION: maximum active glyph levels includes root.
const MAX_COMPONENT_DEPTH:usize=32;
// CONVENTION: one action is a visit, emitted op, or transformed op.
const MAX_PROCESSING_ACTIONS:usize=1<<20;
pub(crate) fn decode_font(data:&[u8],ranges:&[(usize,usize)],root:u16)->Result<Vec<Vec<Op>>,ReadError>{
 let mut seen=std::collections::BTreeSet::new();let mut remaining=MAX_PROCESSING_ACTIONS;
 expand(data,ranges,root,0,&mut seen,&mut remaining)
}
fn expand(data:&[u8],ranges:&[(usize,usize)],gid:u16,depth:usize,seen:&mut std::collections::BTreeSet<u16>,remaining:&mut usize)->Result<Vec<Vec<Op>>,ReadError>{
 if depth>=MAX_COMPONENT_DEPTH{return Err(ReadError::Budget{gid})}
 *remaining=remaining.checked_sub(1).ok_or(ReadError::Budget{gid})?;
 if !seen.insert(gid){return Err(bad(gid,"cyclic component reference"))}
 let(s,e)=*ranges.get(gid as usize).ok_or(ReadError::GlyphIndexOutOfRange(gid))?;let d=data.get(s..e).ok_or(ReadError::Truncated("glyf range"))?;
 if d.is_empty(){seen.remove(&gid);return Ok(vec![])}if d.len()<10{return Err(ReadError::Truncated("glyf header"))}
 let mut cursor=0;let contours=u16be(d,&mut cursor)? as i16;
 if contours>=0{let out=decode_simple(d,gid)?;let cost=out.iter().map(|c|c.len()).sum::<usize>();*remaining=remaining.checked_sub(cost).ok_or(ReadError::Budget{gid})?;seen.remove(&gid);return Ok(out)}
 if contours != -1{return Err(bad(gid,"invalid composite contour count"))}
 cursor=10;let mut out=Vec::new();let mut instructions=false;
 loop{
  let flags=u16be(d,&mut cursor)?;let child=u16be(d,&mut cursor)?;
  // Known composite flags. Reserved bits never affect interpretation silently.
  if flags & !0x1fef !=0{return Err(bad(gid,"reserved composite flags"))}
  if flags&2==0{return Err(ReadError::Unsupported("glyf component point attachment".into()))}
  let(x,y)=if flags&1!=0{(u16be(d,&mut cursor)? as i16 as f64,u16be(d,&mut cursor)? as i16 as f64)}else{(byte(d,&mut cursor)? as i8 as f64,byte(d,&mut cursor)? as i8 as f64)};
  let transforms=usize::from(flags&8!=0)+usize::from(flags&64!=0)+usize::from(flags&128!=0);if transforms>1||flags&0x1800==0x1800{return Err(bad(gid,"conflicting composite transform flags"))}
  let f2=|p:&mut usize|->Result<f64,ReadError>{Ok(u16be(d,p)? as i16 as f64/16384.)};
  let(a,b,c,z)=if flags&8!=0{let a=f2(&mut cursor)?;(a,0.,0.,a)}else if flags&64!=0{(f2(&mut cursor)?,0.,0.,f2(&mut cursor)?)}else if flags&128!=0{(f2(&mut cursor)?,f2(&mut cursor)?,f2(&mut cursor)?,f2(&mut cursor)?)}else{(1.,0.,0.,1.)};
  // Missing offset interpretation is ambiguous when a transform is present.
  if transforms>0&&flags&0x1800==0{return Err(ReadError::Unsupported("transformed glyf component needs explicit scaled/unscaled offset flag".into()))}
  let(dx,dy)=if flags&0x0800!=0{(a.hypot(c)*x,z.hypot(b)*y)}else{(x,y)};// ROUND_XY_TO_GRID is a pixel-grid hint; no grid fitting in this font-unit reader.
  let map=|p:Pt|->Result<Pt,ReadError>{let q=(a*p.0+c*p.1+dx,b*p.0+z*p.1+dy);if !q.0.is_finite()||!q.1.is_finite(){Err(bad(gid,"nonfinite transformed coordinate"))}else{Ok(q)}};
  for contour in expand(data,ranges,child,depth+1,seen,remaining)?{let mut transformed=Vec::with_capacity(contour.len());for op in contour{*remaining=remaining.checked_sub(1).ok_or(ReadError::Budget{gid})?;transformed.push(match op{Op::Move(p)=>Op::Move(map(p)?),Op::Line(p)=>Op::Line(map(p)?),Op::Curve(p,q,r)=>Op::Curve(map(p)?,map(q)?,map(r)?),Op::Close=>Op::Close});}out.push(transformed);}
  instructions|=flags&0x100!=0;if flags&0x20==0{break}
 }
 if instructions{let n=u16be(d,&mut cursor)? as usize;cursor=cursor.checked_add(n).ok_or(ReadError::Truncated("composite instructions"))?;if cursor>d.len(){return Err(ReadError::Truncated("composite instructions"))}}
 seen.remove(&gid);Ok(out)
}
#[cfg(test)]mod composite_tests{
 use super::*;
 fn simple()->Vec<u8>{let mut d=vec![0u8;10];d[..2].copy_from_slice(&1i16.to_be_bytes());d.extend(2u16.to_be_bytes());d.extend(0u16.to_be_bytes());d.extend([1,1,1]);for x in [0i16,12,-12,0,0,12]{d.extend(x.to_be_bytes());}d}
 fn component(gid:u16,x:i16,y:i16,more:bool)->Vec<u8>{let mut d=Vec::new();d.extend((3u16|if more{32}else{0}).to_be_bytes());d.extend(gid.to_be_bytes());d.extend(x.to_be_bytes());d.extend(y.to_be_bytes());d}
 fn composite(parts:Vec<Vec<u8>>)->Vec<u8>{let mut d=vec![0u8;10];d[..2].copy_from_slice(&(-1i16).to_be_bytes());for p in parts{d.extend(p)}d}
 fn font(glyphs:Vec<Vec<u8>>)->(Vec<u8>,Vec<(usize,usize)>){let mut bytes=Vec::new();let mut ranges=Vec::new();for g in glyphs{let s=bytes.len();bytes.extend(g);ranges.push((s,bytes.len()));}(bytes,ranges)}
 #[test]fn translated_nested_component(){let(d,r)=font(vec![simple(),composite(vec![component(0,20,30,false)]),composite(vec![component(1,-10,5,false)])]);let ops=decode_font(&d,&r,2).unwrap();assert_eq!(ops[0][0],Op::Move((10.,35.)));assert_eq!(ops[0][1],Op::Line((22.,35.)));}
 #[test]fn repeats_accepted_cycles_refused(){let(d,r)=font(vec![simple(),composite(vec![component(0,0,0,true),component(0,20,0,false)])]);assert_eq!(decode_font(&d,&r,1).unwrap().len(),2);let(d,r)=font(vec![composite(vec![component(0,0,0,false)])]);assert!(matches!(decode_font(&d,&r,0),Err(ReadError::BadGlyf{..})));}
 #[test]fn depth_and_missing_child_refused(){let mut gs=vec![simple()];for i in 0..34{gs.push(composite(vec![component(i,0,0,false)]));}let(d,r)=font(gs);assert!(matches!(decode_font(&d,&r,34),Err(ReadError::Budget{..})));let(d,r)=font(vec![composite(vec![component(7,0,0,false)])]);assert!(matches!(decode_font(&d,&r,0),Err(ReadError::GlyphIndexOutOfRange(7))));}
 #[test]fn explicit_unscaled_transform_and_instruction_bounds(){let mut c=component(0,20,30,false);c[..2].copy_from_slice(&(3u16|8|0x1000).to_be_bytes());c.extend(8192i16.to_be_bytes());let(d,r)=font(vec![simple(),composite(vec![c])]);let ops=decode_font(&d,&r,1).unwrap();assert_eq!(ops[0][1],Op::Line((26.,30.)));let mut c=component(0,0,0,false);c[..2].copy_from_slice(&(3u16|0x100).to_be_bytes());let(d,r)=font(vec![simple(),composite(vec![c])]);assert!(matches!(decode_font(&d,&r,1),Err(ReadError::Truncated(_))));}
}
#[cfg(test)]mod v2_composite_guards{
 use super::*;
 fn leaf()->Vec<u8>{let mut d=vec![0;10];d[..2].copy_from_slice(&1i16.to_be_bytes());d.extend([0,0,0,0,0x37,10,20]);d}
 fn comp(child:u16,flags:u16,matrix:&[i16])->Vec<u8>{let mut d=vec![0;10];d[..2].copy_from_slice(&(-1i16).to_be_bytes());d.extend(flags.to_be_bytes());d.extend(child.to_be_bytes());d.extend(4i16.to_be_bytes());d.extend(6i16.to_be_bytes());for n in matrix{d.extend(n.to_be_bytes())}d}
 fn pack(gs:Vec<Vec<u8>>)->(Vec<u8>,Vec<(usize,usize)>){let mut d=vec![];let mut r=vec![];for g in gs{let s=d.len();d.extend(g);r.push((s,d.len()));}(d,r)}
 #[test]fn scaled_and_two_by_two_offsets(){let(d,r)=pack(vec![leaf(),comp(0,3|8|0x800,&[8192])]);assert_eq!(decode_font(&d,&r,1).unwrap()[0][0],Op::Move((7.,13.)));let(d,r)=pack(vec![leaf(),comp(0,3|128|0x800,&[16384,8192,0,16384])]);let expected=(14.,25.+6.*(1.25f64).sqrt());let q=decode_font(&d,&r,1).unwrap();if let Op::Move(p)=q[0][0]{assert!((p.0-expected.0).abs()<1e-12&&(p.1-expected.1).abs()<1e-12)}else{panic!()}}
 #[test]fn instructions_on_early_component_are_read_after_last(){let mut root=comp(0,3|32|0x100,&[]);let last=comp(0,3,&[]);root.extend(&last[10..]);root.extend([0,1,0xAA,0,0]);let(d,r)=pack(vec![leaf(),root.clone()]);assert_eq!(decode_font(&d,&r,1).unwrap().len(),2);root.truncate(root.len()-5);root.extend([0,4,0xAA,0,0]);let(d,r)=pack(vec![leaf(),root]);assert!(matches!(decode_font(&d,&r,1),Err(ReadError::Truncated(_))));}
 #[test]fn inclusive_32_active_levels(){let mut gs=vec![leaf()];for i in 0..32{gs.push(comp(i,3,&[]));}let(d,r)=pack(gs);assert!(decode_font(&d,&r,31).is_ok());assert!(matches!(decode_font(&d,&r,32),Err(ReadError::Budget{..})));}
}

#[cfg(test)]mod simple_guards{
 use super::*;
 fn raw(ends:&[u16],instructions:&[u8],flags:&[u8],coords:&[u8])->Vec<u8>{let mut d=vec![0;10];d[..2].copy_from_slice(&(ends.len()as u16).to_be_bytes());for e in ends{d.extend(e.to_be_bytes())}d.extend((instructions.len()as u16).to_be_bytes());d.extend(instructions);d.extend(flags);d.extend(coords);d}
 #[test]fn short_vectors_same_bits_and_instructions(){let d=raw(&[2],&[0,1,2],&[0x31,0x37,0x06],&[5,3,7,2]);let o=decode_simple(&d,0).unwrap();assert_eq!(o[0][1],Op::Line((5.,7.)));assert!(o[0].iter().any(|v|matches!(v,Op::Curve(..))));}
 #[test]fn multiple_contours_and_mixed_on_off(){let d=raw(&[2,5],&[],&[0x31,0x30,0x31,0x31,0x30,0x31],&[]);assert_eq!(decode_simple(&d,0).unwrap().len(),2);}
 #[test]fn reserved_overlap_and_endpoint_guards(){assert!(matches!(decode_simple(&raw(&[0],&[],&[0xB1],&[]),0),Err(ReadError::BadGlyf{..})));assert!(decode_simple(&raw(&[0],&[],&[0x71],&[]),0).is_ok());for ends in [&[1,1][..],&[2,1][..]]{assert!(matches!(decode_simple(&raw(ends,&[],&[],&[]),0),Err(ReadError::BadGlyf{..})));}}
 #[test]fn zero_contour_header_and_instruction_bounds(){assert!(decode_simple(&[0;10],0).unwrap().is_empty());let mut d=vec![0;10];d.extend([0,2,0]);assert!(matches!(decode_simple(&d,0),Err(ReadError::Truncated(_))));}
}
#[cfg(test)]mod v3_guard_tests{
 use super::*;
 #[test]fn coordinate_range(){let mut d=vec![0;10];d[..2].copy_from_slice(&1i16.to_be_bytes());d.extend([0,1,0,0,1,1]);for v in [32767i16,1,0,0]{d.extend(v.to_be_bytes())}assert!(matches!(decode_simple(&d,0),Err(ReadError::BadGlyf{reason:"coordinate outside int16 range",..})));}
 #[test]fn processing_budget_exhaustion(){let d=[0u8;10];let mut active=std::collections::BTreeSet::new();let mut remaining=0;assert!(matches!(expand(&d,&[(0,10)],0,0,&mut active,&mut remaining),Err(ReadError::Budget{gid:0})));}
}
#[cfg(test)]mod v4_budget_tests{
 use super::*;
 fn leaf()->Vec<u8>{let mut d=vec![0;10];d[..2].copy_from_slice(&1i16.to_be_bytes());d.extend([0,1,0,0,0x39,1]);d}
 #[test]fn repeat_flag_success_and_emitted_charge(){let d=leaf();let out=decode_simple(&d,0).unwrap();let cost=1+out.iter().map(|c|c.len()).sum::<usize>();for n in [cost-1,cost]{let mut seen=std::collections::BTreeSet::new();let mut budget=n;let r=expand(&d,&[(0,d.len())],0,0,&mut seen,&mut budget);assert_eq!(r.is_ok(),n==cost);}}
 #[test]fn transformed_operation_charge(){let mut d=leaf();let end=d.len();let mut c=vec![0;10];c[..2].copy_from_slice(&(-1i16).to_be_bytes());c.extend([0,3,0,0,0,0,0,0]);d.extend(c);let ranges=[(0,end),(end,d.len())];let ops=decode_simple(&d[..end],0).unwrap().iter().map(|c|c.len()).sum::<usize>();let required=2+2*ops;for n in [required-1,required]{let mut seen=std::collections::BTreeSet::new();let mut budget=n;assert_eq!(expand(&d,&ranges,1,0,&mut seen,&mut budget).is_ok(),n==required);}}
}
