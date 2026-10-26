//! Outline output bytes only, no annotations, rendering or inferred fill policy.
use crate::reference_slice::{DrawnGlyph, Point, Span};

#[derive(Clone, Copy, Debug)]
pub enum FillRule { NonZero, EvenOdd }

#[derive(Clone, Copy, Debug)]
pub struct SourceViewport { pub x: f64, pub y: f64, pub width: f64, pub height: f64 }

#[derive(Clone, Debug)]
pub enum SvgError { NonFinite, InvalidViewport, NoOutline, OpenContour }

fn point(p: Point) -> bool { p.x.is_finite() && p.y.is_finite() }

/// Requires an explicit caller viewport and fill rule; no policy defaults.
/// Coordinates are preserved as supplied, including source-axis direction.
pub fn outline_svg(glyph: &DrawnGlyph, viewport: SourceViewport, fill: FillRule) -> Result<String, SvgError> {
    if ![viewport.x,viewport.y,viewport.width,viewport.height].iter().all(|v| v.is_finite()) {
        return Err(SvgError::NonFinite);
    }
    if viewport.width <= 0.0 || viewport.height <= 0.0 { return Err(SvgError::InvalidViewport); }
    if glyph.rings.is_empty() { return Err(SvgError::NoOutline); }
    let mut path = String::new();
    for ring in &glyph.rings {
        if !point(ring.start) { return Err(SvgError::NonFinite); }
        if ring.spans.is_empty() { return Err(SvgError::NoOutline); }
        path.push_str(&format!("M{} {}",ring.start.x,ring.start.y));
        let mut end = ring.start;
        for span in &ring.spans {
            match span {
                Span::Line { end: p } => {
                    if !point(*p) { return Err(SvgError::NonFinite); }
                    path.push_str(&format!("L{} {}",p.x,p.y)); end = *p;
                },
                Span::Cubic { control_one: a,control_two: b,end: p } => {
                    if !point(*a) || !point(*b) || !point(*p) { return Err(SvgError::NonFinite); }
                    path.push_str(&format!("C{} {} {} {} {} {}",a.x,a.y,b.x,b.y,p.x,p.y)); end = *p;
                },
            }
        }
        if end != ring.start { return Err(SvgError::OpenContour); }
        // Z closes the already closed subpath; it never inserts a missing edge.
        path.push('Z');
    }
    let rule = match fill { FillRule::NonZero => "nonzero",FillRule::EvenOdd => "evenodd" };
    Ok(format!("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"{} {} {} {}\"><path d=\"{}\" fill-rule=\"{}\"/></svg>",
        viewport.x,viewport.y,viewport.width,viewport.height,path,rule))
}
/// Explicit intentional empty output, missing source still rejected by outline_svg.
pub fn intentional_empty_svg(input:&crate::reference_slice::IntentionalEmptyGlyph,viewport:SourceViewport)->Result<String,SvgError>{
    let _declared_intent=&input.intent;
    if ![viewport.x,viewport.y,viewport.width,viewport.height].iter().all(|v|v.is_finite()){return Err(SvgError::NonFinite);}
    if viewport.width<=0.0||viewport.height<=0.0{return Err(SvgError::InvalidViewport);}
    Ok(format!("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"{} {} {} {}\"></svg>",viewport.x,viewport.y,viewport.width,viewport.height))
}

/// Hygienic emit variant: post-fit duplicate cleanup at the emission point, then
/// the same serializer. Returns the SVG bytes with the typed removal ledger;
/// outline_svg keeps its supplied-coordinate byte contract unchanged. Cleanup
/// removes only spans that draw nothing (see duplicate_point_audit::tidy_duplicate_points);
/// all geometry-bearing coordinates are preserved exactly as supplied.
pub fn outline_svg_tidy(glyph: &DrawnGlyph, viewport: SourceViewport, fill: FillRule) -> Result<(String, crate::duplicate_point_audit::TidyReport), SvgError> {
    let (cleaned, report) = crate::duplicate_point_audit::tidy_duplicate_points(glyph)
        .map_err(|crate::duplicate_point_audit::AuditError::NonFiniteCoordinate { .. }| SvgError::NonFinite)?;
    let svg = outline_svg(&cleaned, viewport, fill)?;
    Ok((svg, report))
}
