//! Raster master caller: reads a manifest, captures each master PNG with capture_png, derives landmarks and
//! runs fit_master_set. No hardcoded geometry, no default policy values. The source pin of each master is the
//! SHA-256 of its PNG bytes.
//!
//! Manifest (plain text, '#' comments, ALL of glyph/rdp_eps/squared_error/max_refits/landmarks are REQUIRED,
//! each key at most once; any malformed or unknown line is a typed ManifestError, never a panic or a default):
//!   glyph <glyph_id>
//!   rdp_eps <f64>                       capture_png simplification epsilon (caller's choice, no default)
//!   squared_error <f64>                 fit policy
//!   max_refits <usize>                  fit policy
//!   landmarks auto-extrema | explicit
//!   master <master_id> <png_path> <scale> <TAG=value[,TAG=value...]>     (>= 1 required; the library needs >= 2)
//!   lm <ring> <master_id> <raw_index> <Role>   (explicit mode only; columns = order of appearance per master)
//! master_id is limited to [A-Za-z0-9_-] (it becomes a file name).
//! CONVENTIONS (explicit, not learned): ring correspondence across masters = capture ring ORDER (ring i of every
//! master is the same contour); hole/orientation come from the capture and are validated by the library.
//! auto-extrema = XMax/YMax/XMin/YMin at the MIDDLE of the first tied run of the extreme raw value, sorted along
//! the ring; it is a convention for simple convex-ish contours, not a learned or semantic landmarker.
//! Output (OUT_DIR optional): <master>.tsv and receipt.txt, written with create_new (never overwrites; existing
//! file => error). Exit 2 on any refusal.
//! Usage: master_fit_raster MANIFEST [OUT_DIR]
use kni_core::capture::capture_png;
use kni_core::cubic_fit::FitPolicy;
use kni_core::economy_eval::sha256_hex;
use kni_core::master_fit_context::*;
use kni_core::reference_slice::{Point, Span};
use std::collections::BTreeMap;
use std::io::Write;

#[derive(Debug, PartialEq)]
pub enum ManifestError { Syntax(usize, String), MissingKey(&'static str), DuplicateKey(usize, String), Io(String), Capture(String), NoMasters, NoRings, Invalid(String) }
use ManifestError as M;

#[derive(Debug)]
struct Master { id: String, path: String, scale: f64, axes: Vec<AxisCoordinate> }
#[derive(Debug)]
struct Manifest { glyph: String, rdp: f64, sq: f64, refits: usize, auto: bool, masters: Vec<Master>, lms: Vec<(usize, String, usize, LandmarkRole)> }

fn role_of(s: &str) -> Option<LandmarkRole> { Some(match s { "Start" => LandmarkRole::Start, "XMin" => LandmarkRole::XMin, "XMax" => LandmarkRole::XMax,
    "YMin" => LandmarkRole::YMin, "YMax" => LandmarkRole::YMax, "Corner" => LandmarkRole::Corner, "Smooth" => LandmarkRole::Smooth, _ => return None }) }
fn safe_id(s: &str) -> bool { !s.is_empty() && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-') }

fn parse_manifest(text: &str) -> Result<Manifest, ManifestError> {
    let (mut glyph, mut rdp, mut sq, mut refits, mut auto) = (None, None, None, None, None);
    let (mut masters, mut lms): (Vec<Master>, Vec<(usize, String, usize, LandmarkRole)>) = (vec![], vec![]);
    for (ln, raw) in text.lines().enumerate() {
        let ln = ln + 1;
        let line = raw.split('#').next().unwrap_or("").trim();
        if line.is_empty() { continue; }
        let t: Vec<&str> = line.split_whitespace().collect();
        let bad = |m: &str| M::Syntax(ln, format!("{}: {}", m, line));
        let arity = |n: usize| if t.len() == n { Ok(()) } else { Err(bad(&format!("`{}` takes {} argument(s)", t[0], n - 1))) };
        let once = |slot_set: bool| if slot_set { Err(M::DuplicateKey(ln, t[0].to_string())) } else { Ok(()) };
        match t[0] {
            "glyph" => { arity(2)?; once(glyph.is_some())?; glyph = Some(t[1].to_string()); }
            "rdp_eps" => { arity(2)?; once(rdp.is_some())?; rdp = Some(t[1].parse::<f64>().map_err(|_| bad("not a number"))?); }
            "squared_error" => { arity(2)?; once(sq.is_some())?; sq = Some(t[1].parse::<f64>().map_err(|_| bad("not a number"))?); }
            "max_refits" => { arity(2)?; once(refits.is_some())?; refits = Some(t[1].parse::<usize>().map_err(|_| bad("not an unsigned integer"))?); }
            "landmarks" => { arity(2)?; once(auto.is_some())?;
                auto = Some(match t[1] { "auto-extrema" => true, "explicit" => false, _ => return Err(bad("landmarks must be auto-extrema or explicit")) }); }
            "master" => {
                arity(5)?;
                if !safe_id(t[1]) { return Err(bad("master_id must match [A-Za-z0-9_-]+")); }
                if masters.iter().any(|m| m.id == t[1]) { return Err(M::Invalid(format!("line {}: duplicate master_id {}", ln, t[1]))); }
                let scale = t[3].parse::<f64>().map_err(|_| bad("scale not a number"))?;
                if !(scale.is_finite() && scale > 0.0) { return Err(bad("scale must be finite and > 0")); }
                let mut axes = vec![];
                for kv in t[4].split(',') {
                    let (k, v) = kv.split_once('=').ok_or_else(|| bad("axis must be TAG=value"))?;
                    let b = k.as_bytes();
                    if b.len() != 4 { return Err(bad("axis tag must be 4 bytes")); }
                    axes.push(AxisCoordinate { tag: [b[0], b[1], b[2], b[3]], value: v.parse::<f64>().map_err(|_| bad("axis value not a number"))? });
                }
                masters.push(Master { id: t[1].into(), path: t[2].into(), scale, axes });
            }
            "lm" => {
                arity(5)?;
                let ring = t[1].parse::<usize>().map_err(|_| bad("ring not an unsigned integer"))?;
                let idx = t[3].parse::<usize>().map_err(|_| bad("raw_index not an unsigned integer"))?;
                let role = role_of(t[4]).ok_or_else(|| bad("unknown landmark role"))?;
                lms.push((ring, t[2].to_string(), idx, role));
            }
            _ => return Err(bad("unknown manifest key")),
        }
    }
    let auto = auto.ok_or(M::MissingKey("landmarks"))?;
    if auto && !lms.is_empty() { return Err(M::Invalid("`lm` lines require `landmarks explicit`".into())); }
    if !auto { for (_, id, _, _) in &lms { if !masters.iter().any(|m| &m.id == id) { return Err(M::Invalid(format!("lm refers to unknown master {}", id))); } } }
    if masters.is_empty() { return Err(M::NoMasters); }
    Ok(Manifest { glyph: glyph.ok_or(M::MissingKey("glyph"))?, rdp: rdp.ok_or(M::MissingKey("rdp_eps"))?, sq: sq.ok_or(M::MissingKey("squared_error"))?,
        refits: refits.ok_or(M::MissingKey("max_refits"))?, auto, masters, lms })
}

fn mid_of_run(raw: &[Point], f: impl Fn(&Point) -> f64, max: bool) -> usize {
    let n = raw.len();
    let best = raw.iter().map(|p| f(p)).fold(if max { f64::NEG_INFINITY } else { f64::INFINITY }, |a, b| if max { a.max(b) } else { a.min(b) });
    let hit: Vec<bool> = raw.iter().map(|p| f(p) == best).collect();
    let start = (0..n).find(|&i| hit[i] && !hit[(i + n - 1) % n]).unwrap_or(0);
    let mut len = 0; while len < n && hit[(start + len) % n] { len += 1; }
    (start + len / 2) % n
}

fn build(man: &Manifest) -> Result<MasterSet, ManifestError> {
    let mut inputs = vec![];
    for m in &man.masters {
        let bytes = std::fs::read(&m.path).map_err(|e| M::Io(format!("{}: {}", m.path, e)))?;
        let captured = capture_png(&bytes, man.rdp).map_err(|e| M::Capture(format!("{}: {}", m.path, e)))?;
        println!("master {} {} rings={} origin=({},{}) sha256={}", m.id, m.path, captured.rings.len(), captured.origin_x, captured.origin_y, sha256_hex(&bytes));
        inputs.push(MasterInput { master_id: m.id.clone(), axes: m.axes.clone(), glyph_id: man.glyph.clone(), captured, scale: m.scale, source_pin: sha256_hex(&bytes) });
    }
    let nrings = inputs[0].captured.rings.len();
    if nrings == 0 { return Err(M::NoRings); }
    if let Some(m) = inputs.iter().find(|m| m.captured.rings.len() != nrings) {
        return Err(M::Invalid(format!("master {} has {} rings, {} has {} (ring correspondence is capture order)", m.master_id, m.captured.rings.len(), inputs[0].master_id, nrings)));
    }
    let mut corrs = vec![];
    for ri in 0..nrings {
        let first = &inputs[0].captured.rings[ri];
        let n = first.raw.len();
        let area: f64 = (0..n).map(|i| { let (p, q) = (first.raw[i], first.raw[(i + 1) % n]); p.x * q.y - q.x * p.y }).sum();
        let mut cols: Vec<Vec<LandmarkRef>> = vec![];
        if man.auto {
            let per: Vec<Vec<(usize, LandmarkRole)>> = inputs.iter().map(|m| { let r = &m.captured.rings[ri];
                let mut v = vec![(mid_of_run(&r.raw, |p| p.x, true), LandmarkRole::XMax), (mid_of_run(&r.raw, |p| p.y, true), LandmarkRole::YMax),
                    (mid_of_run(&r.raw, |p| p.x, false), LandmarkRole::XMin), (mid_of_run(&r.raw, |p| p.y, false), LandmarkRole::YMin)];
                v.sort_by_key(|x| x.0); v }).collect();
            for c in 0..4 { cols.push(inputs.iter().zip(&per).map(|(m, v)| LandmarkRef { master_id: m.master_id.clone(), ring_index: ri, raw_point_index: v[c].0, role: v[c].1 }).collect()); }
        } else {
            let mut by: BTreeMap<&str, Vec<(usize, LandmarkRole)>> = BTreeMap::new();
            for (r, id, i, role) in &man.lms { if *r == ri { by.entry(id.as_str()).or_default().push((*i, *role)); } }
            let ncol = by.values().map(|v| v.len()).max().unwrap_or(0);
            for c in 0..ncol { cols.push(inputs.iter().filter_map(|m| by.get(m.master_id.as_str()).and_then(|v| v.get(c))
                .map(|&(i, role)| LandmarkRef { master_id: m.master_id.clone(), ring_index: ri, raw_point_index: i, role })).collect()); }
        }
        corrs.push(ContourCorrespondence { correspondence_id: format!("ring{}", ri), hole: first.hole,
            orientation: if area > 0.0 { Orientation::Ccw } else { Orientation::Cw }, landmarks: cols });
    }
    Ok(MasterSet { inputs, correspondence: corrs })
}

fn write_new(path: &str, data: &str) -> Result<(), ManifestError> {
    let mut f = std::fs::OpenOptions::new().write(true).create_new(true).open(path).map_err(|e| M::Io(format!("{} (no-overwrite): {}", path, e)))?;
    f.write_all(data.as_bytes()).map_err(|e| M::Io(format!("{}: {}", path, e)))
}

fn run(man_path: &str, outdir: Option<String>) -> Result<(), String> {
    let text = std::fs::read_to_string(man_path).map_err(|e| format!("manifest {}: {:?}", man_path, M::Io(e.to_string())))?;
    let man = parse_manifest(&text).map_err(|e| format!("INVALID MANIFEST: {:?}", e))?;
    let set = build(&man).map_err(|e| format!("INPUT REFUSED: {:?}", e))?;
    let r = fit_master_set(&set, &FitPolicy { squared_error: man.sq, max_refits: man.refits }).map_err(|e| format!("REFUSED: {:?}", e))?;
    println!("{}", r.receipt);
    if let Some(d) = outdir {
        std::fs::create_dir_all(&d).map_err(|e| format!("{}: {}", d, e))?;
        // all ids were validated by parse_manifest (safe_id), so file names cannot escape OUT_DIR
        let mut files: Vec<(String, String)> = vec![(format!("{}/receipt.txt", d), r.receipt.clone())];
        for m in &r.masters {
            let mut o = String::from("ring\tspan\tkind\tx1\ty1\tx2\ty2\tx\ty\n");
            for (ri, ring) in m.outline.rings.iter().enumerate() { for (si, s) in ring.spans.iter().enumerate() { match s {
                Span::Line { end } => o += &format!("{}\t{}\tL\t\t\t\t\t{}\t{}\n", ri, si, end.x, end.y),
                Span::Cubic { control_one: a, control_two: b, end } => o += &format!("{}\t{}\tC\t{}\t{}\t{}\t{}\t{}\t{}\n", ri, si, a.x, a.y, b.x, b.y, end.x, end.y) } } }
            files.push((format!("{}/{}.tsv", d, m.master_id), o));
        }
        if let Some((p, _)) = files.iter().find(|(p, _)| std::path::Path::new(p).exists()) { return Err(format!("OUTPUT REFUSED: {} exists (no overwrite)", p)); }
        for (p, o) in &files { write_new(p, o).map_err(|e| format!("{:?}", e))?; }
    }
    Ok(())
}

fn main() {
    let mut args = std::env::args().skip(1);
    let Some(man) = args.next() else { eprintln!("usage: master_fit_raster MANIFEST [OUT_DIR]"); std::process::exit(2) };
    if let Err(e) = run(&man, args.next()) { println!("{}", e); std::process::exit(2); }
}

#[cfg(test)]
mod tests {
    use super::*;
    const OK: &str = "glyph o\nrdp_eps 0.5\nsquared_error 4\nmax_refits 8\nlandmarks auto-extrema\nmaster a /x.png 1 wght=300\nmaster b /y.png 1 wght=700\n";
    #[test] fn good() { let m = parse_manifest(OK).unwrap(); assert_eq!(m.masters.len(), 2); assert!(m.auto); }
    #[test] fn required_policy_not_defaulted() {
        for k in ["glyph", "rdp_eps", "squared_error", "max_refits", "landmarks"] {
            let t: String = OK.lines().filter(|l| !l.starts_with(k)).map(|l| format!("{}\n", l)).collect();
            assert!(matches!(parse_manifest(&t), Err(M::MissingKey(_))), "{}", k);
        }
    }
    #[test] fn strict_syntax() {
        for bad in ["master a /x.png 1", "master a/b /x.png 1 wght=3", "master a /x.png 0 wght=3", "master a /x.png 1 wght3", "master a /x.png 1 wgh=3",
                    "rdp_eps", "rdp_eps x", "max_refits -1", "landmarks maybe", "bogus 1", "glyph o"] {
            let t = format!("{}{}\n", OK.replace("master b /y.png 1 wght=700\n", ""), bad);
            assert!(parse_manifest(&t).is_err(), "{}", bad);
        }
        assert!(matches!(parse_manifest("glyph o\n"), Err(M::MissingKey(_)) | Err(M::NoMasters)));
    }
    #[test] fn unknown_role_and_lm_rules() {
        let t = OK.replace("auto-extrema", "explicit") + "lm 0 a 3 Wobble\n";
        assert!(matches!(parse_manifest(&t), Err(M::Syntax(..))));
        let t = OK.replace("auto-extrema", "explicit") + "lm 0 zz 3 XMax\n";
        assert!(matches!(parse_manifest(&t), Err(M::Invalid(_))));
        let t = OK.to_string() + "lm 0 a 3 XMax\n";
        assert!(matches!(parse_manifest(&t), Err(M::Invalid(_))));
    }
    #[test] fn zero_masters_refused() {
        let t = "glyph o\nrdp_eps 0.5\nsquared_error 4\nmax_refits 8\nlandmarks auto-extrema\n";
        assert_eq!(parse_manifest(t).unwrap_err(), M::NoMasters);
    }
}
