//! Synthetic-only example. Real outlines require a separate input adapter.
use kni_core::duplicate_point_audit::audit_duplicate_points;
use kni_core::reference_slice::{DrawnGlyph,Point,ReferenceRing,Span};
fn main(){let p=|x,y|Point{x,y};let g=DrawnGlyph{glyph_id:"synthetic_closed_line_with_duplicate".into(),rings:vec![ReferenceRing{start:p(0.,0.),spans:vec![Span::Line{end:p(10.,0.)},Span::Line{end:p(10.,0.)},Span::Line{end:p(0.,0.)}]}]};print!("{}",audit_duplicate_points(&g).unwrap().row(&g.glyph_id));}
