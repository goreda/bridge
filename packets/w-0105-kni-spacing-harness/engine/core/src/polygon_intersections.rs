//! Binary64 polygon intersection observations, NOT robust exact topology proof.
use crate::reference_slice::Point;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum SegmentRelation { Disjoint, ProperCrossing, TouchingOrCollinearOverlap, NumericallyUnresolved }

fn orientation(a:Point,b:Point,c:Point) -> Option<f64> {
    let value=(b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x);
    if value.is_finite() { Some(value) } else { None }
}
fn within(p:Point,a:Point,b:Point) -> bool {
    p.x >= a.x.min(b.x) && p.x <= a.x.max(b.x) && p.y >= a.y.min(b.y) && p.y <= a.y.max(b.y)
}
fn opposite(a:f64,b:f64) -> bool { (a<0.0 && b>0.0)||(a>0.0 && b<0.0) }

pub fn segment_relation(a:Point,b:Point,c:Point,d:Point) -> SegmentRelation {
    if ![a,b,c,d].iter().all(|p|p.x.is_finite()&&p.y.is_finite()) {
        return SegmentRelation::NumericallyUnresolved;
    }
    let (Some(ab_c),Some(ab_d),Some(cd_a),Some(cd_b)) =
        (orientation(a,b,c),orientation(a,b,d),orientation(c,d,a),orientation(c,d,b)) else {
        return SegmentRelation::NumericallyUnresolved;
    };
    if opposite(ab_c,ab_d)&&opposite(cd_a,cd_b) { return SegmentRelation::ProperCrossing; }
    if (ab_c==0.0&&within(c,a,b))||(ab_d==0.0&&within(d,a,b))
        ||(cd_a==0.0&&within(a,c,d))||(cd_b==0.0&&within(b,c,d)) {
        return SegmentRelation::TouchingOrCollinearOverlap;
    }
    SegmentRelation::Disjoint
}

/// True only when every edge pair is observed disjoint; unresolved means false.
pub fn ring_edges_disjoint(first:&[Point],second:&[Point]) -> bool {
    first.windows(2).all(|a|second.windows(2).all(|b|
        segment_relation(a[0],a[1],b[0],b[1])==SegmentRelation::Disjoint))
}

/// Skips only neighboring edges' shared endpoints, not repeated vertices elsewhere.
/// Collinear neighbor geometry is conservatively unresolved.
pub fn ring_is_simple_observation(points:&[Point]) -> bool {
    if points.len()<4 || points.first()!=points.last() { return false; }
    let count=points.len()-1;
    for i in 0..count {
        if points[i]==points[i+1] { return false; }
        for j in i+1..count {
            let adjacent=j==i+1||(i==0&&j==count-1);
            if adjacent {
                let (a,b,c)=if j==i+1 {(points[i],points[i+1],points[j+1])}
                    else {(points[j],points[0],points[1])};
                match orientation(a,b,c) { Some(v) if v!=0.0 => {},_=>return false }
            } else if segment_relation(points[i],points[i+1],points[j],points[j+1])!=SegmentRelation::Disjoint {
                return false;
            }
        }
    }
    true
}
