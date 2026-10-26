//! Geometry-only point-stream decoder. Name-bearing glyph table is not read.
//! Coordinates are decimal numbers parsed as f64: integer or fractional spelling,
//! optional exponent. Values are kept exactly as parsed; nothing is rounded.
//! Non-finite values are rejected.
use kni_geometry_prototypes::{truetype_contour, Geometry, Point, TTPoint};
use std::collections::BTreeMap;
/// gid is returned only for external routing; no name or component metadata.
/// Caller supplies advance geometry separately, not kerning or source groups.
pub fn decode(tsv: &str, advances: &BTreeMap<u32, f64>) -> Result<BTreeMap<u32, Geometry>, String> {
    let mut records: BTreeMap<u32, BTreeMap<u32, BTreeMap<u32, TTPoint>>> = BTreeMap::new();
    let mut lines = tsv.lines();
    let header = lines.next().ok_or("missing_header")?;
    if header != "gid\tcontour\tpoint\tx\ty\ton_curve" {
        return Err("point_stream_schema_mismatch".into());
    }
    for l in lines {
        let f: Vec<_> = l.split('\t').collect();
        if f.len() != 6 {
            return Err("invalid_point_row".into());
        }
        let gid = f[0].parse::<u32>().map_err(|_| "invalid_gid")?;
        let contour = f[1].parse::<u32>().map_err(|_| "invalid_contour")?;
        let ix = f[2].parse::<u32>().map_err(|_| "invalid_point_index")?;
        let x = f[3].parse::<f64>().map_err(|_| "invalid_coordinate_x")?;
        let y = f[4].parse::<f64>().map_err(|_| "invalid_coordinate_y")?;
        if !x.is_finite() {
            return Err("nonfinite_coordinate_x".into());
        }
        if !y.is_finite() {
            return Err("nonfinite_coordinate_y".into());
        }
        let on = match f[5] {
            "1" | "true" => true,
            "0" | "false" => false,
            _ => return Err("invalid_on_curve_flag".into()),
        };
        let old = records
            .entry(gid)
            .or_default()
            .entry(contour)
            .or_default()
            .insert(
                ix,
                TTPoint {
                    point: Point { x, y },
                    on_curve: on,
                },
            );
        if old.is_some() {
            return Err("duplicate_point".into());
        }
    }
    let mut out = BTreeMap::new();
    for (gid, cs) in records {
        let mut rings = Vec::new();
        for (_, ps) in cs {
            if ps.keys().enumerate().any(|(i, &k)| i as u32 != k) {
                return Err("noncontiguous_point_indices".into());
            }
            let points: Vec<_> = ps.into_values().collect();
            rings.push(truetype_contour(&points)?);
        }
        let advance = *advances.get(&gid).ok_or("missing_advance_geometry")?;
        out.insert(gid, Geometry { rings, advance });
    }
    Ok(out)
}
