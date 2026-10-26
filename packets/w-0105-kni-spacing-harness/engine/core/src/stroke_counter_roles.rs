//! Explicit structural roles plus separate geometry-derived proposals.
//! No outline mutation, raster decisions, semantic guessing or guide snapping.
use crate::reference_slice::{DrawnGlyph, Point, Span};
use crate::polygon_intersections::{ring_edges_disjoint,ring_is_simple_observation,segment_relation,SegmentRelation};
use std::collections::{BTreeMap,BTreeSet};
/// Status vocabulary: docs/research/outline-role-data-contract-proposal.md.
/// Proposed never becomes Accepted implicitly; accepted requires explicit evidence.
/// Unavailable means missing input/solution; Conflicting means competing evidence.
#[derive(Clone,Copy,Debug,PartialEq,Eq)]
pub enum RoleStatus { Accepted, Proposed, Unavailable, Conflicting }
impl RoleStatus { pub fn label(self)->&'static str {match self {Self::Accepted=>"accepted",Self::Proposed=>"proposed",Self::Unavailable=>"unavailable",Self::Conflicting=>"conflicting"}} }
#[derive(Clone,Debug,PartialEq,Eq)]
pub struct Scope {pub font:String,pub master:String,pub style:String,pub frame:String,pub source_pin:String}
#[derive(Clone,Copy,Debug,PartialEq,Eq,PartialOrd,Ord)]
pub struct EdgeAddress {pub ring:usize,pub span:usize}
#[derive(Clone,Debug)]
pub struct SourceEdge {pub edge_id:String,pub address:EdgeAddress}
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum StructureKind {PositiveStroke,NegativeCounter}
#[derive(Clone,Debug)]
pub struct Structure {
 pub id:String,pub kind:StructureKind,pub semantic_name:String,
 pub status:RoleStatus,pub evidence:String,pub edge_ids:Vec<String>,
 /// Counter-to-stroke relation; not inferred from glyph identity or winding.
 pub parent_stroke:Option<String>,
}
#[derive(Clone,Debug)]
pub struct GuideRelation {pub structure_id:String,pub edge_id:String,pub class:String,pub status:RoleStatus,pub evidence:String}
#[derive(Clone,Debug)]
pub struct Letterform {
 pub scope:Scope,pub glyph:DrawnGlyph,pub edges:Vec<SourceEdge>,
 /// Explicit positive/negative structure is a first-class input, even empty.
 pub structures:Vec<Structure>,pub guide_relations:Vec<GuideRelation>,
}
#[derive(Clone,Debug,PartialEq)]
pub struct Membership {
 pub edge_id:String,pub glyph:String,pub class:Option<String>,pub membership_evidence:Option<String>,
 pub semantic_role:Option<String>,pub structure_id:Option<String>,pub status:RoleStatus,pub reason:Option<String>,
}
#[derive(Clone,Debug)]
pub struct GuideEdge {
 pub edge_id:String,pub glyph:String,pub class:String,pub membership_evidence:String,
 pub source_pin:String,pub source_y:Vec<f64>,
}
#[derive(Clone,Debug,PartialEq)]
pub enum GeometryKind {
 ClosedNegativeSpace {inner:usize,outer:usize,depth:usize,opposite_winding:bool},
 NestedSameDirection {inner:usize,outer:usize,depth:usize},
 OpenBoundaryPocket {ring:usize,mouth_start:usize,mouth_end:usize,width:f64,depth:f64,boundary_spans:Vec<usize>},
}
#[derive(Clone,Debug,PartialEq)]
pub struct GeometryProposal {pub kind:GeometryKind,pub status:RoleStatus,pub origin:&'static str,pub limitation:&'static str}
#[derive(Clone,Debug,PartialEq)]
pub struct GeometryUnavailable {pub ring:usize,pub reason:String}
#[derive(Clone,Debug)]
pub struct RoleReport {pub scope:Scope,pub memberships:Vec<Membership>,pub geometry:Vec<GeometryProposal>,pub unavailable:Vec<GeometryUnavailable>}
#[derive(Clone,Debug,PartialEq,Eq)]
pub enum Error {InvalidScope,InvalidGlyph,InvalidEdge,DuplicateEdge,DuplicateAddress,InvalidStructure,DuplicateStructure,InvalidRelation}
fn text(s:&str)->bool {!s.trim().is_empty()&&!s.chars().any(char::is_control)}
fn pin(s:&str)->bool {s.len()==64&&s.bytes().all(|c|c.is_ascii_hexdigit())}
fn end(s:&Span)->Point {match s {Span::Line{end}|Span::Cubic{end,..}=>*end}}
fn finite(p:Point)->bool {p.x.is_finite()&&p.y.is_finite()}
fn cross(a:Point,b:Point,c:Point)->Option<f64> {let v=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);v.is_finite().then_some(v)}
fn polygon(g:&DrawnGlyph,ri:usize)->Result<Vec<Point>,String>{
 let r=&g.rings[ri];if !finite(r.start)||r.spans.is_empty(){return Err("empty or nonfinite ring".into());}
 let mut ps=vec![r.start];for s in &r.spans {match s {Span::Line{end}=>ps.push(*end),Span::Cubic{..}=>return Err("curved topology unavailable; no flattening convention selected".into())}}
 if ps.iter().any(|p|!finite(*p)){return Err("nonfinite source geometry".into())}
 if ps.last()!=ps.first(){return Err("source contour not explicitly closed".into())}
 if !ring_is_simple_observation(&ps){return Err("simple polygon topology unavailable or degenerate".into())}
 Ok(ps)
}
fn area(ps:&[Point])->Option<f64>{let a=ps.windows(2).map(|w|w[0].x*w[1].y-w[1].x*w[0].y).sum::<f64>();(a.is_finite()&&a!=0.0).then_some(a)}
fn inside(p:Point,ps:&[Point])->Option<bool>{
 let mut b=false;for w in ps.windows(2){let (a,c)=(w[0],w[1]);let z=cross(a,c,p)?;
 if z==0.0&&p.x>=a.x.min(c.x)&&p.x<=a.x.max(c.x)&&p.y>=a.y.min(c.y)&&p.y<=a.y.max(c.y){return None}
 if (a.y>p.y)!=(c.y>p.y){let x=(c.x-a.x)*(p.y-a.y)/(c.y-a.y)+a.x;if !x.is_finite(){return None}if p.x<x{b=!b}}
 }Some(b)
}
const ORIGIN:&str="derived from geometry";
const LIMITATION:&str="binary64 polygon observation; proposed structure, not semantic stroke/counter evidence";
fn pockets(ps:&[Point],ri:usize)->Result<Vec<GeometryProposal>,String>{
 // Convex hull support chords reveal concave boundary pockets without a
 // glyph whitelist, angle threshold or fixed probe depth. Collinear hull
 // points are retained so straight subdivisions do not invent a pocket.
 let n=ps.len()-1;let mut order:Vec<usize>=(0..n).collect();order.sort_by(|&a,&b|ps[a].x.total_cmp(&ps[b].x).then(ps[a].y.total_cmp(&ps[b].y)));
 let mut lower:Vec<usize>=Vec::new();let mut upper:Vec<usize>=Vec::new();
 for (chain,seq) in [(&mut lower,order.clone()),(&mut upper,order.into_iter().rev().collect())]{for k in seq {while chain.len()>=2 {let m=chain.len();let z=cross(ps[chain[m-2]],ps[chain[m-1]],ps[k]).ok_or("hull orientation overflow")?;if z<0.0{chain.pop();}else{break}}chain.push(k);}}
 lower.pop();upper.pop();lower.extend(upper);let mut hull=lower;hull.dedup();if hull.len()<3{return Err("degenerate hull".into())}
 let signed=area(ps).ok_or("area unresolved")?;
 let mut out=Vec::new();for k in 0..hull.len(){let mut a=hull[k];let mut b=hull[(k+1)%hull.len()];if signed<0.0{std::mem::swap(&mut a,&mut b)}
 let mut spans=Vec::new();let mut idx=a;while idx!=b{spans.push(idx);idx=(idx+1)%n;if spans.len()>n{return Err("hull boundary order unresolved".into())}}
 if spans.len()==1{continue}
 let p=ps[a];let q=ps[b];let width=(q.x-p.x).hypot(q.y-p.y);if !width.is_finite()||width==0.0{return Err("mouth length unresolved".into())}
 // A hull chord may meet its boundary chain only at the mouth endpoints.
 // Any extra crossing/touching makes this pocket unavailable.
 let mut depth=0.0f64;for &j in &spans {let z=cross(p,q,ps[j]).ok_or("pocket depth overflow")?;depth=depth.max(z.abs()/width);}
 if !depth.is_finite(){return Err("pocket depth nonfinite".into())}if depth==0.0{continue}
 for &j in &spans {if j==a || (j+1)%n==b {continue}if segment_relation(p,q,ps[j],ps[(j+1)%n])!=SegmentRelation::Disjoint{return Err("mouth intersects pocket boundary".into())}}
 out.push(GeometryProposal{kind:GeometryKind::OpenBoundaryPocket{ring:ri,mouth_start:a,mouth_end:b,width,depth,boundary_spans:spans},status:RoleStatus::Proposed,origin:ORIGIN,limitation:LIMITATION});
 }Ok(out)
}
/// Geometry candidates are never promoted or assigned semantic names/classes.
/// Inter-ring contact, unsupported curves or degeneracy yields unavailable.
fn geometry(g:&DrawnGlyph)->(Vec<GeometryProposal>,Vec<GeometryUnavailable>){
 let mut unavailable=Vec::new();let mut polys:BTreeMap<usize,Vec<Point>>=BTreeMap::new();
 for ri in 0..g.rings.len(){match polygon(g,ri){Ok(ps)=>{if area(&ps).is_none(){unavailable.push(GeometryUnavailable{ring:ri,reason:"area unresolved".into()})}else{polys.insert(ri,ps);}},Err(reason)=>unavailable.push(GeometryUnavailable{ring:ri,reason})}}
 let mut blocked=BTreeSet::new();let keys:Vec<_>=polys.keys().copied().collect();
 for a in 0..keys.len(){for b in a+1..keys.len(){let i=keys[a];let j=keys[b];if !ring_edges_disjoint(&polys[&i],&polys[&j]){blocked.insert(i);blocked.insert(j);}}}
 // Unsupported siblings may hide a containing ring; avoid inventing depth.
 let incomplete=polys.len()!=g.rings.len();
 for &ri in &blocked{unavailable.push(GeometryUnavailable{ring:ri,reason:"inter-ring contact or crossing unresolved".into()});}
 let mut proposals=Vec::new();for (&ri,ps) in &polys{if blocked.contains(&ri){continue}
 match pockets(ps,ri){Ok(mut p)=>proposals.append(&mut p),Err(reason)=>unavailable.push(GeometryUnavailable{ring:ri,reason})}
 if incomplete{unavailable.push(GeometryUnavailable{ring:ri,reason:"nesting unavailable because a sibling ring is unsupported".into()});continue}
 let mut parents=Vec::new();let mut uncertain=false;for (&oi,os) in &polys{if ri==oi{continue}if blocked.contains(&oi){uncertain=true;continue}match inside(ps[0],os){Some(true)=>parents.push(oi),Some(false)=>(),None=>uncertain=true}}
 if uncertain{unavailable.push(GeometryUnavailable{ring:ri,reason:"nesting relation unresolved".into()});continue}
 if parents.is_empty(){continue}parents.sort_by(|a,b|area(&polys[a]).unwrap().abs().total_cmp(&area(&polys[b]).unwrap().abs()).then(a.cmp(b)));
 let outer=parents[0];let opposite=area(ps).unwrap().is_sign_positive()!=area(&polys[&outer]).unwrap().is_sign_positive();
 let kind=if opposite{GeometryKind::ClosedNegativeSpace{inner:ri,outer,depth:parents.len(),opposite_winding:true}}else{GeometryKind::NestedSameDirection{inner:ri,outer,depth:parents.len()}};
 proposals.push(GeometryProposal{kind,status:RoleStatus::Proposed,origin:ORIGIN,limitation:LIMITATION});
 }(proposals,unavailable)
}
/// Accepted means explicit input status, not authentication or geometric proof.
/// Any unaccepted or inconsistent structural dependency withholds guide export.
pub fn derive_roles(input:&Letterform)->Result<RoleReport,Error>{
 if [&input.scope.font,&input.scope.master,&input.scope.style,&input.scope.frame].iter().any(|s|!text(s))||!pin(&input.scope.source_pin){return Err(Error::InvalidScope)}
 if !text(&input.glyph.glyph_id)||input.glyph.rings.is_empty(){return Err(Error::InvalidGlyph)}
 let mut edges=BTreeMap::new();let mut addresses=BTreeSet::new();for e in &input.edges{
 if !text(&e.edge_id)||input.glyph.rings.get(e.address.ring).and_then(|r|r.spans.get(e.address.span)).is_none(){return Err(Error::InvalidEdge)}
 if edges.insert(e.edge_id.clone(),e).is_some(){return Err(Error::DuplicateEdge)}if !addresses.insert(e.address){return Err(Error::DuplicateAddress)}
 }
 let mut structures=BTreeMap::new();for s in &input.structures{
 if !text(&s.id)||!text(&s.semantic_name)||!text(&s.evidence)||s.edge_ids.is_empty()||s.edge_ids.iter().any(|id|!edges.contains_key(id))||s.edge_ids.iter().collect::<BTreeSet<_>>().len()!=s.edge_ids.len(){return Err(Error::InvalidStructure)}
 if structures.insert(s.id.clone(),s).is_some(){return Err(Error::DuplicateStructure)}
 }
 for s in &input.structures {if s.kind==StructureKind::NegativeCounter{let parent=s.parent_stroke.as_ref().and_then(|id|structures.get(id)).ok_or(Error::InvalidStructure)?;if parent.kind!=StructureKind::PositiveStroke{return Err(Error::InvalidStructure)}}else if s.parent_stroke.is_some(){return Err(Error::InvalidStructure)}}
 for r in &input.guide_relations {let s=structures.get(&r.structure_id).ok_or(Error::InvalidRelation)?;if !text(&r.class)||!text(&r.evidence)||!s.edge_ids.contains(&r.edge_id){return Err(Error::InvalidRelation)}}
 let mut memberships=Vec::new();for (id,e) in edges{
 let owners:Vec<_>=input.structures.iter().filter(|s|s.edge_ids.contains(&id)).collect();let mut row=Membership{edge_id:id.clone(),glyph:input.glyph.glyph_id.clone(),class:None,membership_evidence:None,semantic_role:None,structure_id:None,status:RoleStatus::Unavailable,reason:Some("no explicit structural membership".into())};
 if owners.len()>1{row.status=RoleStatus::Conflicting;row.reason=Some("edge belongs to competing explicit structures".into())}
 else if let Some(s)=owners.first(){row.status=s.status;row.semantic_role=Some(s.semantic_name.clone());row.structure_id=Some(s.id.clone());row.reason=None;
 if s.kind==StructureKind::NegativeCounter {let parent=structures[s.parent_stroke.as_ref().unwrap()];if parent.status!=RoleStatus::Accepted{row.status=if parent.status==RoleStatus::Conflicting{RoleStatus::Conflicting}else{RoleStatus::Unavailable};row.reason=Some("counter parent is not accepted".into())}}
 let relations:Vec<_>=input.guide_relations.iter().filter(|r|r.edge_id==id&&r.structure_id==s.id).collect();
 if relations.len()>1 {row.status=RoleStatus::Conflicting;row.reason=Some("multiple guide relations require explicit resolution".into())}
 else if let Some(r)=relations.first(){if row.status==RoleStatus::Accepted&&r.status==RoleStatus::Accepted{
 let ring=&input.glyph.rings[e.address.ring];let start=if e.address.span==0{ring.start}else{end(&ring.spans[e.address.span-1])};
 match &ring.spans[e.address.span]{Span::Line{end} if finite(start)&&finite(*end)&&start!=*end=>{row.class=Some(r.class.clone());row.membership_evidence=Some(format!("structure={}; {}; relation={}",s.id,s.evidence,r.evidence));},_=>{row.status=RoleStatus::Unavailable;row.reason=Some("guide export requires a finite nonzero source line; curve sampling is unbound".into())}}
 }else{row.reason=Some("structure or guide relation not accepted".into());if r.status==RoleStatus::Conflicting{row.status=RoleStatus::Conflicting}else if row.status==RoleStatus::Accepted{row.status=r.status}}}
 else{row.reason=Some("structural role has no explicit guide-class relation".into())}
 }memberships.push(row);
 }
 let (geometry,unavailable)=geometry(&input.glyph);Ok(RoleReport{scope:input.scope.clone(),memberships,geometry,unavailable})
}
/// Recompute from immutable input: proposed geometry never enters guide binding.
/// Returned fields match EdgeObservation, plus finite source samples.
pub fn guide_edges(input:&Letterform)->Result<Vec<GuideEdge>,Error>{
 let report=derive_roles(input)?;let mut out=Vec::new();for row in report.memberships{if row.status!=RoleStatus::Accepted{continue}if let (Some(class),Some(evidence))=(row.class,row.membership_evidence){let e=input.edges.iter().find(|e|e.edge_id==row.edge_id).unwrap();let ring=&input.glyph.rings[e.address.ring];let start=if e.address.span==0{ring.start}else{end(&ring.spans[e.address.span-1])};out.push(GuideEdge{edge_id:row.edge_id,glyph:row.glyph,class,membership_evidence:evidence,source_pin:input.scope.source_pin.clone(),source_y:vec![start.y,end(&ring.spans[e.address.span]).y]});}}Ok(out)
}
