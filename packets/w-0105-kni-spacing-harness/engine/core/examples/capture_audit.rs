//! Canonical capture -> fit -> explicit integer quantization -> Type2 audit.
//! All fitting/frame parameters are caller supplied; no font-specific constants.
use kni_core::{capture::capture_png,capture_fit::fit_captured,cubic_fit::FitPolicy,
    reference_slice::{Point,Span,DrawnGlyph},cff_container::{CffGlyph,charstring}};
fn point(p:Point)->String {format!("[{:.17},{:.17}]",p.x,p.y)}
fn q(p:Point,tx:f64,ty:f64)->Point {Point{x:(p.x+tx).round(),y:(p.y+ty).round()}}
fn main()->Result<(),Box<dyn std::error::Error>> {
    let a:Vec<String>=std::env::args().collect();
    if a.len()!=10 {return Err("usage: capture_audit TILE OUTPUT RDP_EPS SCALE SQUARED_ERROR MAX_REFITS ADVANCE TX TY".into());}
    let eps:f64=a[3].parse()?;let scale:f64=a[4].parse()?;let se:f64=a[5].parse()?;
    let refits:usize=a[6].parse()?;let advance:u16=a[7].parse()?;let tx:f64=a[8].parse()?;let ty:f64=a[9].parse()?;
    if ![eps,scale,se,tx,ty].iter().all(|v|v.is_finite())||eps<=0.||scale<=0.||se<=0. {return Err("invalid parameters".into());}
    let png=std::fs::read(&a[1])?;let mc=capture_png(&png,eps)?;
    let policy=FitPolicy{squared_error:se,max_refits:refits};
    let (mut rings,spans,fallback,dropped)=fit_captured(&mc.rings,scale,&policy);
    let mut floating=Vec::new();
    for r in &rings {
        let mut segments=Vec::new();
        for s in &r.spans {segments.push(match s {Span::Line{end}=>format!("{{\"L\":{}}}",point(*end)),Span::Cubic{control_one,control_two,end}=>format!("{{\"C\":[{},{},{}]}}",point(*control_one),point(*control_two),point(*end))});}
        floating.push(format!("{{\"start\":{},\"spans\":[{}]}}",point(r.start),segments.join(",")));
    }
    for r in &mut rings {r.start=q(r.start,tx,ty);for s in &mut r.spans {match s {Span::Line{end}=>*end=q(*end,tx,ty),Span::Cubic{control_one,control_two,end}=>{*control_one=q(*control_one,tx,ty);*control_two=q(*control_two,tx,ty);*end=q(*end,tx,ty);}}}}
    let glyph=CffGlyph{name:"audit".into(),advance,outline:DrawnGlyph{glyph_id:"audit".into(),rings}};
    let bytes=charstring(&glyph).map_err(|e|format!("integer encoding rejected: {:?}",e))?;
    let source_hex=png.iter().map(|b|format!("{:02x}",b)).collect::<String>();
    let hex=bytes.iter().map(|b|format!("{:02x}",b)).collect::<String>();
    let json=format!("{{\"schema\":\"kni.capture-audit.v1\",\"source_png_hex\":\"{}\",\"path\":\"capture_png>fit_captured>integer_charstring\",\"parameters\":{{\"rdp_eps\":{},\"squared_error\":{},\"max_refits\":{}}},\"frame\":{{\"scale\":{},\"translation\":[{},{}],\"capture_origin\":[{},{}],\"tile_size\":[{},{}],\"quantization\":\"nearest_integer\"}},\"measurement\":{{\"captured_rings\":{},\"fit_spans\":{},\"fallback\":{},\"dropped_rings\":{},\"charstring_bytes\":{}}},\"float_rings\":[{}],\"charstring_hex\":\"{}\"}}\n",source_hex,eps,se,refits,scale,tx,ty,mc.origin_x,mc.origin_y,mc.width,mc.height,mc.rings.len(),spans,fallback,dropped,bytes.len(),floating.join(","),hex);
    std::fs::write(&a[2],json)?;Ok(())
}
