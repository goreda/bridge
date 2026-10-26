//! Measurement example: C3/C4 rows on a captured and fitted tile.
//! Path: PNG -> capture_png -> fit_captured -> c3c4_roles (image input path).
//! Rows only: no gate, no threshold choice, no ranking. Engine code is not changed.
//!
//! Usage: c3c4_capture <tile.png> --eps E --se S --refits N --scale K [--rows]
//! Every parameter is supplied by the caller; none has a default here.
use kni_core::c3c4_roles::*;
use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured;
use kni_core::cubic_fit::FitPolicy;
use kni_core::reference_slice::{Point, ReferenceRing, Span};

fn esc(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

fn num(v: Option<f64>) -> String {
    v.map_or("null".to_string(), |x| format!("{:.17e}", x))
}

/// Fit output is in capture pixels times `scale`. Divide back so every length,
/// the noise sigma and the quantisation floor Q = 1/sqrt(12) are in pixels.
fn to_pixels(rings: &[ReferenceRing], scale: f64) -> Vec<ReferenceRing> {
    let f = |p: &Point| Point { x: p.x / scale, y: p.y / scale };
    rings
        .iter()
        .map(|r| ReferenceRing {
            start: f(&r.start),
            spans: r
                .spans
                .iter()
                .map(|s| match s {
                    Span::Line { end } => Span::Line { end: f(end) },
                    Span::Cubic { control_one, control_two, end } => Span::Cubic {
                        control_one: f(control_one),
                        control_two: f(control_two),
                        end: f(end),
                    },
                })
                .collect(),
        })
        .collect()
}

fn main() {
    let usage = "usage: c3c4_capture <tile.png> --eps E --se S --refits N --scale K [--rows]";
    let mut args = std::env::args().skip(1);
    let path = args.next().unwrap_or_else(|| { eprintln!("{usage}"); std::process::exit(2) });
    let (mut eps, mut se, mut refits, mut scale) = (None, None, None, None);
    let mut rows = false;
    while let Some(a) = args.next() {
        let mut val = |name: &str| -> String {
            args.next().unwrap_or_else(|| { eprintln!("{name} needs a value\n{usage}"); std::process::exit(2) })
        };
        match a.as_str() {
            "--eps" => eps = val("--eps").parse::<f64>().ok(),
            "--se" => se = val("--se").parse::<f64>().ok(),
            "--refits" => refits = val("--refits").parse::<usize>().ok(),
            "--scale" => scale = val("--scale").parse::<f64>().ok(),
            "--rows" => rows = true,
            other => { eprintln!("unknown argument {other}\n{usage}"); std::process::exit(2) }
        }
    }
    let (Some(eps), Some(se), Some(refits), Some(scale)) = (eps, se, refits, scale) else {
        eprintln!("--eps, --se, --refits and --scale are required\n{usage}");
        std::process::exit(2)
    };
    if !(scale.is_finite() && scale > 0.0) || !eps.is_finite() || !se.is_finite() {
        eprintln!("--eps, --se and --scale must be finite and --scale positive");
        std::process::exit(2)
    }
    let png = std::fs::read(&path).unwrap_or_else(|e| { eprintln!("read: {e}"); std::process::exit(1) });
    let mc = capture_png(&png, eps).unwrap_or_else(|e| { eprintln!("capture: {e}"); std::process::exit(1) });
    let policy = FitPolicy { squared_error: se, max_refits: refits };
    let (fitted, total_spans, fallback, dropped) = fit_captured(&mc.rings, scale, &policy);
    let rings = to_pixels(&fitted, scale);
    let noise = measure_noise(&rings);
    let c3 = c3_measure(&rings, &noise, InputPath::Image);
    let c4 = c4_measure(&rings, &noise, InputPath::Image);

    let mut o = String::new();
    o.push_str("{\"space\":\"capture pixels (fit output divided by scale)\"");
    o.push_str(&format!(",\"unit\":\"pixel\",\"angle_unit\":\"radian\",\"input_path\":\"{}\"", c3.path));
    o.push_str(&format!(",\"parameters\":{{\"eps_px\":{:?},\"squared_error\":{:?},\"refits\":{},\"scale\":{:?}}}", eps, se, refits, scale));
    o.push_str(&format!(",\"captured_rings\":{},\"dropped_rings\":{},\"output_rings\":{},\"fit_spans\":{},\"polyline_fallback\":{}", mc.rings.len(), dropped, rings.len(), total_spans, fallback));
    o.push_str(&format!(",\"noise\":{{\"sigma_px\":{:?},\"origin\":\"{:?}\",\"derivation\":\"{}\",\"quantisation_floor_px\":{:?},\"sigma_eff_px\":{:?}}}", noise.sigma, noise.origin, esc(&noise.derivation), quantization_sigma(), noise.effective_sigma()));
    o.push_str(&format!(",\"c3\":{{\"aligned\":{},\"deviant\":{},\"abstain\":{}}}", c3.aligned, c3.deviant, c3.abstain));
    o.push_str(&format!(",\"c4\":{{\"smooth\":{},\"corner\":{},\"abstain\":{}}}", c4.smooth, c4.corner, c4.abstain));
    o.push_str(&format!(",\"conventions\":[\"{}\",\"CONVENTION_AXIS_WINDOW_REL = {:?} (axis window inside measure_noise)\"]", esc(&c3.conventions.join("; ")), CONVENTION_AXIS_WINDOW_REL));
    o.push_str(",\"note\":\"measurement rows only; no gate; no numeric comparison across input paths (this is the image path)\"");
    if rows {
        let c3r: Vec<String> = c3.elements.iter().map(|e| format!("[{},{},{},{},{},\"{}\"]", e.ring, e.span, e.which, num(e.deviation_rad), num(e.tolerance_rad), match &e.class { AxisClass::Aligned => "aligned".to_string(), AxisClass::Deviant => "deviant".to_string(), AxisClass::Abstain(r) => format!("abstain: {}", esc(r)) })).collect();
        let c4r: Vec<String> = c4.nodes.iter().map(|e| format!("[{},{},{},{},\"{}\"]", e.ring, e.node, num(e.join_rad), num(e.tolerance_rad), match &e.class { JoinClass::Smooth => "smooth".to_string(), JoinClass::Corner => "corner".to_string(), JoinClass::Abstain(r) => format!("abstain: {}", esc(r)) })).collect();
        o.push_str(&format!(",\"c3_rows\":[{}],\"c4_rows\":[{}]", c3r.join(","), c4r.join(",")));
    }
    o.push('}');
    println!("{o}");
}
