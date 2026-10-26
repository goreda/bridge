//! Exact coincident-coordinate observations. No geometry is changed.
use crate::reference_slice::{DrawnGlyph,Point,ReferenceRing,Span};
use std::collections::BTreeMap;
#[derive(Clone,Copy,Debug,PartialEq,Eq)]pub enum PointRole{OnCurve,OffCurve}
#[derive(Clone,Debug,PartialEq,Eq)]pub struct Location{pub contour:usize,pub position:usize,pub role:PointRole,pub closure_endpoint:bool}
#[derive(Clone,Debug,Default,PartialEq,Eq)]pub struct DuplicateAudit{pub point_count:usize,pub pair_count:usize,pub consecutive:usize,pub non_adjacent:usize,pub same_contour:usize,pub different_contour:usize,pub on_on:usize,pub on_off:usize,pub off_off:usize,pub explicit_closure_pairs:usize,pub nonclosure_pairs:usize}
#[derive(Clone,Debug,PartialEq,Eq)]pub enum AuditError{NonFiniteCoordinate{contour:usize,position:usize}}
fn key(p:Point)->(u64,u64){let k=|x:f64|if x==0.{0}else{x.to_bits()};(k(p.x),k(p.y))}
/// Every unordered coincident-coordinate pair is counted, not only neighbors.
/// Consecutive means neighboring serialized points within one contour.
/// Explicit start/final-end closure pair is counted and separately labelled.
/// Coordinates use binary64 equality with signed zero normalized; no tolerance.
pub fn audit_duplicate_points(g:&DrawnGlyph)->Result<DuplicateAudit,AuditError>{let mut points=BTreeMap::<(u64,u64),Vec<Location>>::new();let mut report=DuplicateAudit::default();for(contour,ring)in g.rings.iter().enumerate(){let mut stream=vec![(ring.start,PointRole::OnCurve,false)];for(i,s)in ring.spans.iter().enumerate(){let final_span=i+1==ring.spans.len();match s{Span::Line{end}=>stream.push((*end,PointRole::OnCurve,final_span&&*end==ring.start)),Span::Cubic{control_one,control_two,end}=>{stream.push((*control_one,PointRole::OffCurve,false));stream.push((*control_two,PointRole::OffCurve,false));stream.push((*end,PointRole::OnCurve,final_span&&*end==ring.start));}}}for(position,(p,role,closure_endpoint))in stream.into_iter().enumerate(){if !p.x.is_finite()||!p.y.is_finite(){return Err(AuditError::NonFiniteCoordinate{contour,position})}let loc=Location{contour,position,role,closure_endpoint};let prior=points.entry(key(p)).or_default();for other in prior.iter(){report.pair_count+=1;let same=other.contour==contour;report.same_contour+=usize::from(same);report.different_contour+=usize::from(!same);let consecutive=same&&other.position+1==position;report.consecutive+=usize::from(consecutive);report.non_adjacent+=usize::from(!consecutive);match(other.role,role){(PointRole::OnCurve,PointRole::OnCurve)=>report.on_on+=1,(PointRole::OffCurve,PointRole::OffCurve)=>report.off_off+=1,_=>report.on_off+=1}let closure=same&&other.position==0&&closure_endpoint;report.explicit_closure_pairs+=usize::from(closure);report.nonclosure_pairs+=usize::from(!closure);}prior.push(loc);report.point_count+=1;}}Ok(report)}
impl DuplicateAudit{pub fn row(&self,glyph_id:&str)->String{format!("glyph={:?} points={} coincident_pairs={} consecutive={} non_adjacent={} same_contour={} different_contour={} on_on={} on_off={} off_off={} explicit_closure_pairs={} nonclosure_pairs={} scope=exact_coordinate_pairs_not_proven_redundancy\n",glyph_id,self.point_count,self.pair_count,self.consecutive,self.non_adjacent,self.same_contour,self.different_contour,self.on_on,self.on_off,self.off_off,self.explicit_closure_pairs,self.nonclosure_pairs)}}

// ---- post-fit emit hygiene (development list #2): provably redundant duplicate removal ----

/// What tidy_duplicate_points removed. Only shapes that draw nothing are removed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RemovalKind {
    /// Line span whose end equals the current point: zero drawn length.
    ZeroLengthLine,
    /// Cubic span with both controls and end on the current point: zero drawn area.
    DegenerateCubic,
}

/// One typed ledger entry per removed span; span_index refers to the ORIGINAL ring.
#[derive(Clone, Debug, PartialEq)]
pub struct RemovalRecord { pub contour: usize, pub span_index: usize, pub kind: RemovalKind, pub x: f64, pub y: f64 }

#[derive(Clone, Debug, Default, PartialEq)]
pub struct TidyReport {
    pub removals: Vec<RemovalRecord>,
    /// Rings whose every span was redundant: the original ring is kept (an emptied
    /// ring is not an outline) and the contour index is reported here instead.
    pub kept_degenerate_rings: Vec<usize>,
    /// Coincident pairs still present after cleaning, counted by audit_duplicate_points
    /// on the cleaned glyph (closure pairs, cross-contour shared vertices and
    /// shape-bearing control coincidences are never removed).
    pub remaining: DuplicateAudit,
}

/// Post-fit duplicate cleanup at the emission point. Removes only spans whose
/// deletion cannot change the drawn geometry (RemovalKind); every removal is one
/// typed ledger row, nothing is dropped silently. Point equality is binary64 ==
/// (signed zero compares equal, the geometric reading). Closure is preserved:
/// removing a span whose end equals the current point never moves the endpoint.
/// Shape-bearing coincidences (partial control coincidence, loop cubics whose end
/// returns to the current point over off-point controls), cross-contour shared
/// vertices and the explicit closure pair are kept and stay countable in
/// TidyReport.remaining. Non-finite coordinates are refused, never cleaned.
pub fn tidy_duplicate_points(g: &DrawnGlyph) -> Result<(DrawnGlyph, TidyReport), AuditError> {
    for (contour, ring) in g.rings.iter().enumerate() {
        if !ring.start.x.is_finite() || !ring.start.y.is_finite() {
            return Err(AuditError::NonFiniteCoordinate { contour, position: 0 });
        }
        let mut position = 1usize;
        for span in &ring.spans {
            let pts: &[Point] = match span {
                Span::Line { end } => std::slice::from_ref(end),
                Span::Cubic { control_one, control_two, end } => {
                    if !control_one.x.is_finite() || !control_one.y.is_finite() { return Err(AuditError::NonFiniteCoordinate { contour, position }); }
                    position += 1;
                    if !control_two.x.is_finite() || !control_two.y.is_finite() { return Err(AuditError::NonFiniteCoordinate { contour, position }); }
                    position += 1;
                    std::slice::from_ref(end)
                }
            };
            if !pts[0].x.is_finite() || !pts[0].y.is_finite() { return Err(AuditError::NonFiniteCoordinate { contour, position }); }
            position += 1;
        }
    }
    let mut cleaned = DrawnGlyph { glyph_id: g.glyph_id.clone(), rings: Vec::with_capacity(g.rings.len()) };
    let mut report = TidyReport::default();
    for (contour, ring) in g.rings.iter().enumerate() {
        let mut cur = ring.start;
        let mut spans: Vec<Span> = Vec::with_capacity(ring.spans.len());
        for (span_index, span) in ring.spans.iter().enumerate() {
            match span {
                Span::Line { end } => {
                    if *end == cur {
                        report.removals.push(RemovalRecord { contour, span_index, kind: RemovalKind::ZeroLengthLine, x: end.x, y: end.y });
                    } else {
                        spans.push(span.clone());
                        cur = *end;
                    }
                }
                Span::Cubic { control_one, control_two, end } => {
                    if *control_one == cur && *control_two == cur && *end == cur {
                        report.removals.push(RemovalRecord { contour, span_index, kind: RemovalKind::DegenerateCubic, x: end.x, y: end.y });
                    } else {
                        spans.push(span.clone());
                        cur = *end;
                    }
                }
            }
        }
        if spans.is_empty() && !ring.spans.is_empty() {
            report.kept_degenerate_rings.push(contour);
            cleaned.rings.push(ring.clone());
        } else {
            cleaned.rings.push(ReferenceRing { start: ring.start, spans });
        }
    }
    report.remaining = audit_duplicate_points(&cleaned)?;
    Ok((cleaned, report))
}

impl TidyReport {
    /// Typed ledger rows, one per removal and per kept degenerate ring, then a summary.
    pub fn ledger_rows(&self, glyph_id: &str) -> String {
        let mut out = String::new();
        for r in &self.removals {
            let kind = match r.kind { RemovalKind::ZeroLengthLine => "zero_length_line", RemovalKind::DegenerateCubic => "degenerate_cubic" };
            out.push_str(&format!("tidy\tglyph={:?}\tcontour={}\tspan={}\tkind={}\tx={}\ty={}\n", glyph_id, r.contour, r.span_index, kind, r.x, r.y));
        }
        for contour in &self.kept_degenerate_rings {
            out.push_str(&format!("tidy\tglyph={:?}\tcontour={}\tkind=ring_kept_degenerate\tnote=all_spans_redundant_original_ring_retained\n", glyph_id, contour));
        }
        out.push_str(&format!("tidy-summary\tglyph={:?}\tremoved={}\tkept_degenerate_rings={}\tremaining_pairs={}\tremaining_consecutive={}\tremaining_explicit_closure_pairs={}\n",
            glyph_id, self.removals.len(), self.kept_degenerate_rings.len(), self.remaining.pair_count, self.remaining.consecutive, self.remaining.explicit_closure_pairs));
        out
    }
}
