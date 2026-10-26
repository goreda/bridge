//! CFF fill intent declaration and audit, never source contour reversal.
use crate::reference_slice::{DrawnGlyph,Span};
#[derive(Clone,Copy,Debug,PartialEq)]
pub enum SourceFill { NonZero,EvenOdd,Unspecified }
#[derive(Clone,Copy,Debug,PartialEq)]
pub enum RingRole { FilledBoundary,CounterBoundary,Unknown }
#[derive(Clone,Debug,PartialEq)]
pub enum FillAudit { UnspecifiedIntent,NonZeroNeedsEquivalenceProof,RoleCountMismatch,UnknownRole(usize),CurvedDirectionUnresolved(usize),DegenerateOrNonfinite(usize),DirectionMismatch(usize),DirectionObserved(usize),PolygonTopologyUnresolved(usize),CompoundIntersectionUnresolved(usize,usize) }
/// Audits supplied roles, does NOT infer nesting or establish arbitrary topology.
/// Signed shoelace is an observation, not a robust curved winding solver.
pub fn audit(glyph:&DrawnGlyph,fill:SourceFill,roles:&[RingRole])->Vec<FillAudit>{
    let mut out=Vec::new();match fill{SourceFill::Unspecified=>out.push(FillAudit::UnspecifiedIntent),SourceFill::EvenOdd=>{},SourceFill::NonZero=>out.push(FillAudit::NonZeroNeedsEquivalenceProof)}
    if roles.len()!=glyph.rings.len(){out.push(FillAudit::RoleCountMismatch);return out;}
    for index in 0..glyph.rings.len(){for other_index in 0..index{let a=&glyph.rings[index];let b=&glyph.rings[other_index];if a.spans.iter().chain(&b.spans).any(|s|matches!(s,Span::Cubic{..})){out.push(FillAudit::CompoundIntersectionUnresolved(other_index,index));}}}
    for(index,(ring,role))in glyph.rings.iter().zip(roles).enumerate(){
        if *role==RingRole::Unknown{out.push(FillAudit::UnknownRole(index));continue;}
        if ring.spans.iter().any(|s|matches!(s,Span::Cubic{..})){out.push(FillAudit::CurvedDirectionUnresolved(index));continue;}
        let mut points=vec![ring.start];for span in &ring.spans{if let Span::Line{end}=span{points.push(*end);}}
        if !crate::polygon_intersections::ring_is_simple_observation(&points){out.push(FillAudit::PolygonTopologyUnresolved(index));}
        for (other_index,other) in glyph.rings.iter().enumerate().take(index){if other.spans.iter().any(|s|matches!(s,Span::Cubic{..})){continue;}let mut other_points=vec![other.start];for span in &other.spans{if let Span::Line{end}=span{other_points.push(*end);}}if !crate::polygon_intersections::ring_edges_disjoint(&points,&other_points){out.push(FillAudit::CompoundIntersectionUnresolved(other_index,index));}}
        let mut area=0.;let mut current=ring.start;for span in &ring.spans{if let Span::Line{end}=span{area+=current.x*end.y-current.y*end.x;current=*end;}}
        if !area.is_finite()||area==0.||current!=ring.start{out.push(FillAudit::DegenerateOrNonfinite(index));}
        else if (area>0.)!=(*role==RingRole::FilledBoundary){out.push(FillAudit::DirectionMismatch(index));}else{out.push(FillAudit::DirectionObserved(index));}
    }out
}
