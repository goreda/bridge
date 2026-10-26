//! Field mapping only. Routing name enters after geometric fit/query, never as a feature.
use kni_geometry_prototypes::{fitter_wall, geometry_pin, knowledge, Assignment, Geometry};
use kni_metrics::gen::{GlyphKnowledge, GlyphWall};
use kni_metrics::training_only_fit::GeometryAssignment;
pub fn map_assignment(
    route: &str,
    geometry: &Geometry,
    a: &Assignment,
) -> Result<GeometryAssignment, String> {
    if route.trim().is_empty() {
        return Err("missing_routing_identity".into());
    }
    if geometry_pin(geometry) != a.outline_pin {
        return Err("outline_pin_mismatch".into());
    }
    let k = knowledge(a).ok_or_else(|| {
        a.unavailable_reason
            .clone()
            .unwrap_or("class_unavailable".into())
    })?;
    let w = fitter_wall(geometry)?;
    Ok(GeometryAssignment {
        glyph: route.into(),
        knowledge: GlyphKnowledge {
            case: k.case,
            freq_weight: k.freq_weight,
            right_class: k.right_class,
            left_class: k.left_class,
        },
        wall: GlyphWall {
            advance: w.advance,
            rows: w.rows,
        },
        outline_pin: a.outline_pin.clone(),
        prototype_pin: a.prototype_pin.clone(),
        query_only: a.query_only,
    })
}
