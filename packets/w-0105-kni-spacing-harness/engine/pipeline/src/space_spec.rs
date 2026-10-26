//! Parse pinned space-evidence specifications without reading source files.
//!
//! Only slope_tile rows may repeat. Slope and pair routes are exclusive;
//! slope input requires an explicit point limit before any evidence is read.

use std::path::{Path, PathBuf};
use kni_metrics::space_measurement::{
    EdgeSampling, InkModel, RendererEdgeContract, SidebearingPolicy, SourceFrame,
};
use crate::space_evidence::validate_space_cp;

fn is_sha(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

#[derive(Debug, Clone)]
pub(crate) struct TileSpec {
    pub(crate) frame: SourceFrame,
    pub(crate) path: PathBuf,
    pub(crate) identity_ref: String,
    pub(crate) sha256: String,
}

#[derive(Debug, Clone)]
pub(crate) enum KernSpec {
    Zero { frame: SourceFrame, evidence_ref: String },
    Known { frame: SourceFrame, px: f64, evidence_ref: String },
}

#[derive(Debug, Clone)]
pub(crate) struct ShapingSpec {
    pub(crate) frame: SourceFrame,
    pub(crate) settings_ref: String,
    pub(crate) ligatures_disabled: bool,
    pub(crate) letter_spacing_px: f64,
    pub(crate) covers: Vec<String>,
}

#[derive(Debug, Clone)]
pub(crate) struct ScaleRecordSpec {
    pub(crate) frame: SourceFrame,
    pub(crate) path: PathBuf,
    pub(crate) sha256: String,
}

/// Parsed spec. Absent rows stay `None`.
#[derive(Debug, Clone)]
pub struct Spec {
    pub(crate) codepoint: u32,
    pub(crate) style_id: String,
    pub(crate) frame_id: String,
    pub(crate) hsh: Option<TileSpec>,
    pub(crate) hhh: Option<TileSpec>,
    pub(crate) hh_kern: Option<KernSpec>,
    pub(crate) hh_explicit: Option<(SourceFrame, f64, f64, String)>,
    pub(crate) hsh_kern: Option<KernSpec>,
    pub(crate) shaping: Option<ShapingSpec>,
    pub(crate) scale_record: Option<ScaleRecordSpec>,
    pub(crate) policy: SidebearingPolicy,
    pub(crate) slope_tiles: Vec<SlopeTileSpec>,
    pub(crate) slope_kern: Option<KernSpec>,
    pub(crate) renderer_contract: Option<RendererEdgeContract>,
    pub(crate) ink: Option<InkModel>,
    pub(crate) slope_max_points: Option<usize>,
}

#[derive(Debug, Clone)]
pub(crate) struct SlopeTileSpec {
    pub(crate) spaces: usize,
    pub(crate) submitted_text_ref: String,
    pub(crate) tile: TileSpec,
}

fn num(err: &dyn Fn(&str) -> String, what: &str, v: Option<&str>) -> Result<f64, String> {
    let x: f64 = v.ok_or_else(|| err(&format!("{what} missing")))?.parse().map_err(|_| err(&format!("bad {what}")))?;
    if !x.is_finite() {
        return Err(err(&format!("{what} must be finite")));
    }
    Ok(x)
}

fn boolean(err: &dyn Fn(&str) -> String, what: &str, v: Option<&str>) -> Result<bool, String> {
    match v {
        Some("true") => Ok(true),
        Some("false") => Ok(false),
        _ => Err(err(&format!("{what} must be true|false"))),
    }
}

fn frame_tok(err: &dyn Fn(&str) -> String, it: &mut std::str::SplitWhitespace) -> Result<SourceFrame, String> {
    let t = it.next().ok_or_else(|| err("f=<style>/<frame> token missing"))?;
    let rest = t.strip_prefix("f=").ok_or_else(|| err("expected f=<style>/<frame> token"))?;
    let mut p = rest.split('/');
    match (p.next(), p.next(), p.next()) {
        (Some(s), Some(f), None) if !s.is_empty() && !f.is_empty() => {
            Ok(SourceFrame { style_id: s.to_string(), frame_id: f.to_string() })
        }
        _ => Err(err("f= token must be f=<style_id>/<frame_id>")),
    }
}

fn kern_row(err: &dyn Fn(&str) -> String, it: &mut std::str::SplitWhitespace) -> Result<KernSpec, String> {
    let frame = frame_tok(err, it)?;
    match it.next() {
        Some("zero") => {
            let r = it.next().ok_or_else(|| err("kern evidence ref missing"))?.to_string();
            Ok(KernSpec::Zero { frame, evidence_ref: r })
        }
        Some("known") => {
            let px = num(err, "kern px", it.next())?;
            let r = it.next().ok_or_else(|| err("kern evidence ref missing"))?.to_string();
            Ok(KernSpec::Known { frame, px, evidence_ref: r })
        }
        _ => Err(err("kern row must be zero|known after the frame token")),
    }
}

/// Parse the spec text. `base` joins relative paths.
pub fn parse_spec(text: &str, base: &Path) -> Result<Spec, String> {
    let mut cp = None;
    let mut style = None;
    let mut frame = None;
    let mut spec = Spec {
        codepoint: 0,
        style_id: String::new(),
        frame_id: String::new(),
        hsh: None,
        hhh: None,
        hh_kern: None,
        hh_explicit: None,
        hsh_kern: None,
        shaping: None,
        scale_record: None,
        policy: SidebearingPolicy::default(),
        slope_tiles: Vec::new(),
        slope_kern: None,
        renderer_contract: None,
        ink: None,
        slope_max_points: None,
    };
    let mut seen: Vec<String> = Vec::new();
    for (ln, raw) in text.lines().enumerate() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let line_number = ln.checked_add(1).ok_or("space evidence spec: line number overflow")?;
        let err = |m: &str| format!("space evidence spec line {}: {}", line_number, m);
        let mut it = line.split_whitespace();
        let key = it.next().unwrap_or("");
        if key != "slope_tile" && seen.iter().any(|k| k == key) {
            return Err(err(&format!("duplicate row {key}")));
        }
        seen.push(key.to_string());
        match key {
            "cp" => {
                let raw = it.next().ok_or_else(|| err("cp missing"))?;
                let v = u32::from_str_radix(raw.strip_prefix("0x").unwrap_or(raw), 16).map_err(|_| err("bad cp"))?;
                validate_space_cp(v).map_err(|e| err(&e))?;
                cp = Some(v);
            }
            "style_id" => style = Some(it.next().ok_or_else(|| err("style_id missing"))?.to_string()),
            "frame_id" => frame = Some(it.next().ok_or_else(|| err("frame_id missing"))?.to_string()),
            "hsh_tile" | "hhh_tile" => {
                let f = frame_tok(&err, &mut it)?;
                let path = it.next().ok_or_else(|| err("tile path missing"))?;
                let ident = it.next().ok_or_else(|| err("tile identity_ref missing"))?.to_string();
                let sha = it.next().ok_or_else(|| err("tile sha256 missing"))?.to_string();
                if !is_sha(&sha) {
                    return Err(err("tile sha256 must be 64 lowercase hex"));
                }
                let t = TileSpec { frame: f, path: base.join(path), identity_ref: ident, sha256: sha };
                if key == "hsh_tile" { spec.hsh = Some(t) } else { spec.hhh = Some(t) }
            }
            "slope_tile" => {
                let f = frame_tok(&err, &mut it)?;
                let spaces: usize = it.next().ok_or_else(|| err("slope_tile space count missing"))?.parse().map_err(|_| err("bad slope_tile space count"))?;
                let path = it.next().ok_or_else(|| err("slope_tile path missing"))?;
                let sref = it.next().ok_or_else(|| err("slope_tile submitted_text_ref missing"))?.to_string();
                let sha = it.next().ok_or_else(|| err("slope_tile sha256 missing"))?.to_string();
                if !is_sha(&sha) {
                    return Err(err("slope_tile sha256 must be 64 lowercase hex"));
                }
                let tile = TileSpec { frame: f, path: base.join(path), identity_ref: sref.clone(), sha256: sha };
                spec.slope_tiles.push(SlopeTileSpec { spaces, submitted_text_ref: sref, tile });
            }
            "slope_kern" => spec.slope_kern = Some(kern_row(&err, &mut it)?),
            "slope_max_points" => {
                spec.slope_max_points = Some(it.next().ok_or_else(|| err("slope_max_points missing"))?.parse().map_err(|_| err("slope_max_points must be an unsigned integer"))?);
            }
            "ink_model" => {
                // ink_model border_median_delta <delta 0..255> <source_ref>
                let m = it.next().ok_or_else(|| err("ink_model name missing"))?;
                if m != "border_median_delta" {
                    return Err(err(&format!("unsupported ink_model {m}")));
                }
                let d: u8 = it.next().ok_or_else(|| err("ink_model delta missing"))?.parse().map_err(|_| err("ink_model delta must be 0..255"))?;
                let r = it.next().ok_or_else(|| err("ink_model source_ref missing"))?.to_string();
                spec.ink = Some(InkModel { delta: d, source_ref: r });
            }
            "renderer_contract" => {
                // renderer_contract <model> <transform_ref> <dpr_ref> <filter_ref> <threshold_ref> <compression_ref> <clipping_ref>
                let model = it.next().ok_or_else(|| err("renderer_contract model missing"))?;
                let sampling = match model {
                    "binary_pixel_center" => EdgeSampling::BinaryPixelCenter,
                    other => return Err(err(&format!("unsupported renderer_contract model {other}"))),
                };
                let mut r = || it.next().map(str::to_string).ok_or_else(|| err("renderer_contract ref missing"));
                spec.renderer_contract = Some(RendererEdgeContract {
                    sampling,
                    capture_transform_ref: r()?,
                    dpr_ref: r()?,
                    filter_ref: r()?,
                    threshold_ref: r()?,
                    compression_ref: r()?,
                    clipping_ref: r()?,
                });
            }
            "hh_kern" => spec.hh_kern = Some(kern_row(&err, &mut it)?),
            "hsh_kern" => spec.hsh_kern = Some(kern_row(&err, &mut it)?),
            "hh_explicit" => {
                let f = frame_tok(&err, &mut it)?;
                let l = num(&err, "lsb px", it.next())?;
                let r = num(&err, "rsb px", it.next())?;
                let rf = it.next().ok_or_else(|| err("explicit evidence ref missing"))?.to_string();
                spec.hh_explicit = Some((f, l, r, rf));
            }
            "shaping" => {
                let f = frame_tok(&err, &mut it)?;
                let settings_ref = it.next().ok_or_else(|| err("settings_ref missing"))?.to_string();
                let ligatures_disabled = boolean(&err, "ligatures_disabled", it.next())?;
                let letter_spacing_px = num(&err, "letter_spacing_px", it.next())?;
                let covers: Vec<String> = it.next().ok_or_else(|| err("covered tile sha list missing"))?
                    .split(',').map(|s| s.to_string()).collect();
                if covers.iter().any(|s| !is_sha(s)) {
                    return Err(err("covered tile shas must be 64 lowercase hex"));
                }
                spec.shaping = Some(ShapingSpec { frame: f, settings_ref, ligatures_disabled, letter_spacing_px, covers });
            }
            "scale_record" => {
                let f = frame_tok(&err, &mut it)?;
                let path = it.next().ok_or_else(|| err("scale record path missing"))?;
                let sha = it.next().ok_or_else(|| err("scale record sha256 missing"))?.to_string();
                if !is_sha(&sha) {
                    return Err(err("scale record sha256 must be 64 lowercase hex"));
                }
                spec.scale_record = Some(ScaleRecordSpec { frame: f, path: base.join(path), sha256: sha });
            }
            "sidebearing_policy" => {
                spec.policy = match it.next() {
                    Some("allow_negative") => SidebearingPolicy::AllowNegativeFinite,
                    Some("require_nonnegative") => SidebearingPolicy::RequireNonNegative,
                    _ => return Err(err("sidebearing_policy must be allow_negative|require_nonnegative")),
                };
            }
            other => return Err(err(&format!("unknown row {other}"))),
        }
        if it.next().is_some() {
            return Err(err("unexpected extra field"));
        }
    }
    spec.codepoint = cp.ok_or("space evidence spec: cp is required")?;
    spec.style_id = style.ok_or("space evidence spec: style_id is required")?;
    spec.frame_id = frame.ok_or("space evidence spec: frame_id is required")?;
    if (!spec.slope_tiles.is_empty() || spec.slope_kern.is_some() || spec.renderer_contract.is_some() || spec.ink.is_some() || spec.slope_max_points.is_some())
        && (spec.hsh.is_some() || spec.hhh.is_some() || spec.hh_explicit.is_some() || spec.hh_kern.is_some() || spec.hsh_kern.is_some())
    {
        return Err("space evidence spec: slope rows and hsh/hhh/hh_explicit/hh_kern/hsh_kern rows are exclusive routes".into());
    }
    if spec.slope_tiles.is_empty() && (spec.slope_kern.is_some() || spec.renderer_contract.is_some() || spec.ink.is_some() || spec.slope_max_points.is_some()) {
        return Err("space evidence spec: slope_kern/renderer_contract without slope_tile rows".into());
    }
    if spec.hhh.is_some() && spec.hh_explicit.is_some() {
        return Err("space evidence spec: hhh_tile and hh_explicit are exclusive".into());
    }
    if !spec.slope_tiles.is_empty() {
        let max_points = spec.slope_max_points.ok_or(
            "space evidence spec: slope_tile rows need slope_max_points (limit missing; refused before any read)",
        )?;
        if spec.slope_tiles.len() > max_points {
            return Err(format!(
                "space evidence spec: {} slope_tile rows exceed slope_max_points {max_points}; refused before any read",
                spec.slope_tiles.len(),
            ));
        }
    }
    Ok(spec)
}


#[cfg(test)]
mod tests {
    use super::*;

    const SHA: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const HEADER: &str = "cp 0x20\nstyle_id a\nframe_id b\n";

    fn parse_rows(rows: &str) -> Result<Spec, String> {
        parse_spec(&format!("{HEADER}{rows}"), Path::new("/spec-base"))
    }

    fn slope_row(spaces: usize) -> String {
        format!("slope_tile f=a/b {spaces} tile.png submitted-text {SHA}\n")
    }

    fn slope_rows() -> String {
        format!("{}{}slope_max_points 2\n", slope_row(0), slope_row(1))
    }

    fn fails(rows: &str, expected: &str) {
        let error = parse_rows(rows).expect_err("malformed spec accepted");
        assert!(error.contains(expected), "expected {expected:?}, got {error:?}");
    }

    #[test]
    fn required_headers_and_codepoint_are_checked() {
        for text in ["", "cp 20\n", "cp 20\nstyle_id a\n", "style_id a\nframe_id b\n"] {
            assert!(parse_spec(text, Path::new("/spec-base")).is_err());
        }
        for cp in ["0", "41", "d800", "110000", "xyz", "100000000"] {
            let text = format!("cp {cp}\nstyle_id a\nframe_id b\n");
            assert!(parse_spec(&text, Path::new("/spec-base")).is_err(), "{cp}");
        }
        assert_eq!(parse_rows("").unwrap().codepoint, 0x20);
    }

    #[test]
    fn comments_and_relative_paths_are_preserved() {
        let spec = parse_rows(&format!("# ignored\n\nhsh_tile f=a/b tiles/hsh.png tile-ref {SHA}\n")).unwrap();
        let tile = spec.hsh.unwrap();
        assert_eq!(tile.path, Path::new("/spec-base/tiles/hsh.png"));
        assert_eq!(tile.frame.style_id, "a");
        assert_eq!(tile.frame.frame_id, "b");
        assert_eq!(tile.identity_ref, "tile-ref");
        assert_eq!(tile.sha256, SHA);
    }

    #[test]
    fn singleton_rows_reject_duplicates() {
        let rows = [
            "cp 20\n".to_string(),
            "style_id a\n".to_string(),
            "frame_id b\n".to_string(),
            format!("hsh_tile f=a/b tile ref {SHA}\n"),
            format!("hhh_tile f=a/b tile ref {SHA}\n"),
            "hh_kern f=a/b zero ref\n".to_string(),
            "hsh_kern f=a/b known 1 ref\n".to_string(),
            "hh_explicit f=a/b 1 2 ref\n".to_string(),
            format!("shaping f=a/b settings true 0 {SHA}\n"),
            format!("scale_record f=a/b scale.txt {SHA}\n"),
            "sidebearing_policy allow_negative\n".to_string(),
            "slope_kern f=a/b zero ref\n".to_string(),
            "slope_max_points 2\n".to_string(),
            "ink_model border_median_delta 8 ref\n".to_string(),
            "renderer_contract binary_pixel_center t d f th c cl\n".to_string(),
        ];
        for row in rows {
            fails(&format!("{row}{row}"), "duplicate row");
        }
    }

    #[test]
    fn repeated_slope_tile_rows_are_the_only_repeat_exception() {
        let spec = parse_rows(&slope_rows()).unwrap();
        assert_eq!(spec.slope_tiles.len(), 2);
        assert_eq!(spec.slope_tiles[0].spaces, 0);
        assert_eq!(spec.slope_tiles[1].spaces, 1);
        assert_eq!(spec.slope_tiles[1].submitted_text_ref, "submitted-text");
        assert_eq!(spec.slope_tiles[1].tile.path, Path::new("/spec-base/tile.png"));
    }

    #[test]
    fn slope_and_pair_routes_are_exclusive_for_every_pair_row() {
        let pairs = [
            format!("hsh_tile f=a/b tile ref {SHA}\n"),
            format!("hhh_tile f=a/b tile ref {SHA}\n"),
            "hh_explicit f=a/b 1 2 ref\n".to_string(),
            "hh_kern f=a/b zero ref\n".to_string(),
            "hsh_kern f=a/b zero ref\n".to_string(),
        ];
        let slope = [
            slope_rows(),
            "slope_kern f=a/b zero ref\n".to_string(),
            "slope_max_points 2\n".to_string(),
            "ink_model border_median_delta 8 ref\n".to_string(),
            "renderer_contract binary_pixel_center t d f th c cl\n".to_string(),
        ];
        for pair in pairs {
            for row in &slope {
                fails(&format!("{pair}{row}"), "exclusive routes");
            }
        }
        fails(&format!("hhh_tile f=a/b tile ref {SHA}\nhh_explicit f=a/b 1 2 ref\n"), "hhh_tile and hh_explicit are exclusive");
    }

    #[test]
    fn slope_options_require_slope_tiles() {
        for row in [
            "slope_kern f=a/b zero ref\n",
            "slope_max_points 2\n",
            "ink_model border_median_delta 8 ref\n",
            "renderer_contract binary_pixel_center t d f th c cl\n",
        ] {
            fails(row, "without slope_tile rows");
        }
    }

    #[test]
    fn explicit_slope_limit_is_required_and_enforced_during_parse() {
        fails(&slope_row(0), "slope_max_points (limit missing");
        fails(&format!("{}slope_max_points 0\n", slope_row(0)), "exceed slope_max_points");
        fails(&format!("{}{}slope_max_points 1\n", slope_row(0), slope_row(1)), "exceed slope_max_points");
        for value in ["-1", "nope", "1.5", "99999999999999999999999999999999999999"] {
            fails(&format!("{}slope_max_points {value}\n", slope_row(0)), "unsigned integer");
        }
        fails("slope_max_points\n", "slope_max_points missing");
    }

    #[test]
    fn malformed_ink_rows_are_rejected() {
        for (row, expected) in [
            ("ink_model", "name missing"),
            ("ink_model unknown 8 ref", "unsupported ink_model"),
            ("ink_model border_median_delta", "delta missing"),
            ("ink_model border_median_delta -1 ref", "delta must be 0..255"),
            ("ink_model border_median_delta 256 ref", "delta must be 0..255"),
            ("ink_model border_median_delta 1.5 ref", "delta must be 0..255"),
            ("ink_model border_median_delta 8", "source_ref missing"),
            ("ink_model border_median_delta 8 ref extra", "unexpected extra field"),
        ] {
            fails(&format!("{}{row}\n", slope_rows()), expected);
        }
        for delta in [0, 255] {
            let spec = parse_rows(&format!("{}ink_model border_median_delta {delta} source\n", slope_rows())).unwrap();
            let ink = spec.ink.unwrap();
            assert_eq!(ink.delta, delta);
            assert_eq!(ink.source_ref, "source");
        }
    }

    #[test]
    fn malformed_renderer_contract_rows_are_rejected() {
        fails("renderer_contract\n", "model missing");
        fails("renderer_contract unknown t d f th c cl\n", "unsupported renderer_contract");
        for refs in ["", "t", "t d", "t d f", "t d f th", "t d f th c"] {
            fails(&format!("{}renderer_contract binary_pixel_center {refs}\n", slope_rows()), "ref missing");
        }
        fails(&format!("{}renderer_contract binary_pixel_center t d f th c cl extra\n", slope_rows()), "unexpected extra field");
        let spec = parse_rows(&format!("{}renderer_contract binary_pixel_center t d f th c cl\n", slope_rows())).unwrap();
        let contract = spec.renderer_contract.unwrap();
        assert_eq!(contract.sampling, EdgeSampling::BinaryPixelCenter);
        assert_eq!(contract.capture_transform_ref, "t");
        assert_eq!(contract.dpr_ref, "d");
        assert_eq!(contract.filter_ref, "f");
        assert_eq!(contract.threshold_ref, "th");
        assert_eq!(contract.compression_ref, "c");
        assert_eq!(contract.clipping_ref, "cl");
    }

    #[test]
    fn malformed_rows_finite_numbers_pins_and_tokens_are_rejected() {
        for (row, expected) in [
            ("bogus 1".to_string(), "unknown row"),
            ("hsh_tile p r short".to_string(), "f=<style>/<frame>"),
            (format!("hsh_tile f=a/b/c p r {SHA}"), "f= token must be"),
            ("hsh_tile f=a/b p r short".to_string(), "64 lowercase hex"),
            (format!("hsh_tile f=/b p r {SHA}"), "f= token must be"),
            ("hh_kern f=a/b maybe ref".to_string(), "zero|known"),
            ("hh_kern f=a/b known NaN ref".to_string(), "must be finite"),
            ("hh_explicit f=a/b inf 0 ref".to_string(), "must be finite"),
            (format!("shaping f=a/b settings maybe 0 {SHA}"), "true|false"),
            (format!("shaping f=a/b settings true -inf {SHA}"), "must be finite"),
            (format!("shaping f=a/b settings true 0 {SHA},"), "64 lowercase hex"),
            ("scale_record f=a/b record short".to_string(), "64 lowercase hex"),
            ("sidebearing_policy unknown".to_string(), "allow_negative|require_nonnegative"),
            ("slope_tile f=a/b -1 p ref short".to_string(), "bad slope_tile space count"),
            (format!("slope_tile f=a/b 1 p ref {SHA} extra"), "unexpected extra field"),
        ] {
            fails(&format!("{row}\n"), expected);
        }
    }
}
