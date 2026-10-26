//! Four-way drawing benchmark (next-version work list item 5): measures
//! KNI and the external reference tracers on the same population with the
//! same metrics and the same frame pins as the canonical harness
//! (core/examples/canonical_path_run.rs): scan-domain IoU at the declared
//! threshold on the source tile canvas, rendered by
//! economy_eval::ProductionEvaluator with the manifest capture epsilon and
//! the declared flatten steps. No harness-owned numeric constants: every
//! number is a CLI input or comes from the manifest.
//!
//! Modes:
//!   potrace|autotrace|vtracer  INPUT is a directory of per-glyph SVG files
//!                              named <glyphname>.svg, traced from the same
//!                              tiles binarized at THRESHOLD.
//!   kni-otf                    INPUT is an OTF built by the canonical
//!                              harness (production arm); outlines are read
//!                              back through cff_reader, so KNI is measured
//!                              on exactly the bytes it ships.
//!
//! Per glyph and engine the TSV carries: node/segment counts, cubic ratio,
//! join classification (smooth vs corner at TANGENT_TOL_DEG), curvature
//! breaks (cubic-cubic joins over the same tolerance), and scan-domain IoU.
//! Every failure is a typed row; nothing drops silently.
//!
//! Usage:
//!   race_external MANIFEST TILEDIR MODE INPUT THRESHOLD FLATTEN_STEPS \
//!       TANGENT_TOL_DEG OUT_TSV

use kni_core::capture::capture_png;
use kni_core::cff_reader::{sha256_hex, CffReader};
use kni_core::economy_eval::{EvalConfig, ProductionEvaluator, RenderLimits};
use kni_core::reference_slice::{DrawnGlyph, Point, ReferenceRing, Span};

#[derive(Clone)]
pub struct GlyphRow { pub cp: String, pub name: String, pub path: String }

pub struct ManifestCfg {
    pub scale: f64, pub eps: f64, pub upm: u16, pub glyphs: Vec<GlyphRow>,
}

pub fn parse_manifest(text: &str, tiledir: &str) -> Result<ManifestCfg, String> {
    let (mut scale, mut eps, mut upm) = (None, None, None);
    let mut glyphs = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') { continue; }
        let p: Vec<&str> = line.split_whitespace().collect();
        match p[0] {
            "scale" => scale = Some(p[1].parse::<f64>().map_err(|_| "bad scale")?),
            "rdp_epsilon" => eps = Some(p[1].parse::<f64>().map_err(|_| "bad rdp_epsilon")?),
            "upm" => upm = Some(p[1].parse::<u16>().map_err(|_| "bad upm")?),
            "glyph" => {
                if p.len() < 4 { return Err(format!("bad glyph row: {line}")); }
                let raw = p[3];
                let resolved = raw.strip_prefix("@TILEDIR@/").map(|r| format!("{tiledir}/{r}")).unwrap_or(raw.to_string());
                glyphs.push(GlyphRow { cp: p[1].to_string(), name: p[2].to_string(), path: resolved });
            }
            _ => {}
        }
    }
    Ok(ManifestCfg { scale: scale.ok_or("missing scale")?, eps: eps.ok_or("missing rdp_epsilon")?, upm: upm.ok_or("missing upm")?, glyphs })
}

// ---------- minimal SVG path parsing (M/L/H/V/C/Z, absolute and relative) ----------

/// Input byte caps. Every read below goes through read_capped, which reads
/// at most cap+1 bytes from the same open handle and refuses over cap;
/// there is no metadata-length check anywhere.
pub const MAX_TILE_BYTES: u64 = 32 * 1024 * 1024;
pub const MAX_SVG_BYTES: u64 = 64 * 1024 * 1024;
pub const MAX_MANIFEST_BYTES: u64 = 16 * 1024 * 1024;
pub const MAX_OTF_BYTES: u64 = 64 * 1024 * 1024;

/// Read at most `cap` bytes from `path`. Opens once and reads through
/// take(cap + 1); a file larger than cap is a typed refusal, never a
/// truncated read.
pub fn read_capped(path: &str, cap: u64, what: &str) -> Result<Vec<u8>, String> {
    use std::io::Read;
    let f = std::fs::File::open(path).map_err(|e| format!("{what} open: {e}"))?;
    let mut buf = Vec::new();
    f.take(cap + 1).read_to_end(&mut buf).map_err(|e| format!("{what} read: {e}"))?;
    if buf.len() as u64 > cap { return Err(format!("{what} over {cap} bytes")); }
    Ok(buf)
}

/// Tile content pin: the filename must end in `__<12 hex>.png` and that
/// fragment must prefix the file's sha256 (the custody scheme of the tile
/// folder). A missing or malformed pin is a refusal, never a silent skip.
pub fn verify_tile_pin(path: &str, png_sha: &str) -> Result<(), String> {
    let base = path.rsplit('/').next().unwrap_or("");
    let stem = base.strip_suffix(".png").ok_or_else(|| format!("tile_pin_malformed:{base}"))?;
    let (_, frag) = stem.rsplit_once("__").ok_or_else(|| format!("tile_pin_malformed:{base}"))?;
    if frag.len() != 12 || !frag.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(format!("tile_pin_malformed:{base}"));
    }
    let frag = frag.to_ascii_lowercase();
    if !png_sha.starts_with(&frag) { return Err(format!("tile_sha_mismatch:{frag}")); }
    Ok(())
}

/// Reject glyph names that could escape the SVG directory or carry shell/
/// path semantics. Typed refusal, never a silent skip.
pub fn safe_glyph_name(name: &str) -> Result<(), String> {
    if name.is_empty() || name.len() > 128 { return Err("glyph name length".into()); }
    if name == "." || name == ".." || name.contains("..") || name.contains('/') || name.contains('\\') { return Err(format!("unsafe glyph name: {name}")); }
    if !name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.')) { return Err(format!("unsafe glyph name: {name}")); }
    Ok(())
}

#[derive(Clone, Copy, Default)]
struct Xform { a: f64, b: f64, c: f64, d: f64 } // x' = a + c*x, y' = b + d*y
impl Xform { fn apply(&self, p: Point) -> Point { Point { x: self.a + self.c * p.x, y: self.b + self.d * p.y } } }

/// One parsed `<g transform="...">` group: the transform plus the byte span
/// of the group's content, so it applies only to paths inside the group.
struct GXform { xf: Xform, content_start: usize, content_end: usize }

/// Compose two diagonal affines: (outer . inner)(p) = outer(inner(p)).
fn compose(outer: Xform, inner: Xform) -> Xform {
    Xform {
        a: outer.a + outer.c * inner.a,
        b: outer.b + outer.d * inner.b,
        c: outer.c * inner.c,
        d: outer.d * inner.d,
    }
}

/// Strict subset: one optional `<g transform="...">` group, double-quoted,
/// no whitespace around `=`, translate/scale items only, exactly two finite
/// numeric args each, composed in document order (NOT commutative). Any
/// other transform spelling, any path-level transform, an unterminated
/// group, or more than one transform group is a typed refusal - nothing is
/// silently ignored.
/// Significant markup for the group scan. Found by walking every `<` in
/// document order, so a `<glyph>`/`<garbage>` element or a comment before a
/// real group can never swallow it.
enum Markup { Comment, GroupOpen, GroupClose }

/// Next significant markup token after the start of `s`. Group openers are
/// `<g` followed by ASCII whitespace or `>`; `<g` followed by a letter is a
/// different element and skipped; `<g/>`, `</g >` and any other boundary are
/// typed refusals, never silently ignored.
fn next_markup(s: &str) -> Result<Option<(usize, Markup)>, String> {
    for (i, _) in s.match_indices('<') {
        let rest = &s[i..];
        if rest.starts_with("<!--") { return Ok(Some((i, Markup::Comment))); }
        if rest.starts_with("</g>") { return Ok(Some((i, Markup::GroupClose))); }
        if rest.starts_with("</g") { return Err(format!("g close: unsupported spelling at byte offset {i}")); }
        if rest.starts_with("<g/>") { return Err("g group: self-closing <g/> outside the supported subset".into()); }
        if rest.starts_with("<g") {
            match rest[2..].chars().next() {
                Some(c) if c.is_ascii_whitespace() || c == '>' => return Ok(Some((i, Markup::GroupOpen))),
                Some('/') => return Err("g group: self-closing <g/> outside the supported subset".into()),
                Some(c) if c.is_ascii_alphabetic() => continue, // <glyph>, <garbage>: other elements
                Some(_) => return Err(format!("g tag: unsupported boundary at byte offset {i}")),
                None => return Err("g tag: truncated".into()),
            }
        }
        // any other element: skipped, scanning continues
    }
    Ok(None)
}

fn parse_g_transform(svg: &str) -> Result<Option<GXform>, String> {
    // Bounded XML-subset scan over the whole document: group openers,
    // group closers and comments in document order, with depth tracking.
    // Nesting, self-closing groups, stray closers, unbalanced documents and
    // unterminated comments are all typed refusals - with nesting refused,
    // a transform group's matching close is unambiguous.
    let mut group: Option<GXform> = None;
    let mut depth = 0usize;
    let mut base = 0usize;
    loop {
        let (i, mk) = match next_markup(&svg[base..])? { Some(x) => x, None => break };
        let abs = base + i;
        match mk {
            Markup::Comment => {
                let end = svg[abs + 4..].find("-->").ok_or("comment: unterminated")?;
                base = abs + 4 + end + 3;
            }
            Markup::GroupClose => {
                if depth == 0 { return Err(format!("g group: stray </g> at byte {abs}")); }
                depth -= 1;
                if depth == 0 {
                    if let Some(g) = group.as_mut() { if g.content_end == 0 { g.content_end = abs; } }
                }
                base = abs + 4;
            }
            Markup::GroupOpen => {
                if depth >= 1 { return Err(format!("g group: nested group at byte {abs} outside the supported subset")); }
                depth += 1;
                let after = &svg[abs..];
                let close = after.find('>').ok_or("g tag: unterminated")?;
                let tag = &after[..close];
                if tag.ends_with('/') { return Err("g group: self-closing <g/> outside the supported subset".into()); }
                if tag.contains("transform") {
                    let val = tag.split("transform=\"").nth(1)
                        .ok_or_else(|| "g transform: unsupported attribute form (only transform=\"...\", double quotes, no spaces)".to_string())?;
                    let j = val.find('"').ok_or("g transform: unterminated value")?;
                    let t = &val[..j];
                    if group.is_some() { return Err("g transform: more than one transform group".into()); }
                    let xf = parse_transform_list(t)?;
                    group = Some(GXform { xf, content_start: abs + close + 1, content_end: 0 });
                }
                base = abs + close + 1;
            }
        }
    }
    if depth != 0 { return Err("g group: unbalanced, missing </g>".into()); }
    Ok(group)
}

fn parse_transform_list(t: &str) -> Result<Xform, String> {
    if t.trim().is_empty() { return Err("g transform: empty".into()); }
    if !t.trim_end().ends_with(')') { return Err(format!("g transform: unterminated item in: {t}")); }
    let mut xf = Xform { a: 0.0, b: 0.0, c: 1.0, d: 1.0 };
    for m in t.split(')').filter(|s| !s.trim().is_empty()) {
        let m = m.trim();
        let (name, arg) = m.split_once('(').ok_or_else(|| format!("g transform: bad item: {m}"))?;
        let name = name.trim();
        if !matches!(name, "translate" | "scale") { return Err(format!("g transform: unsupported function: {name}")); }
        let mut nums = Vec::new();
        for tok in arg.split([',', ' ']).filter(|s| !s.is_empty()) {
            let v: f64 = tok.parse().map_err(|_| format!("g transform: bad number {tok} in {m}"))?;
            if !v.is_finite() { return Err(format!("g transform: nonfinite value in {m}")); }
            nums.push(v);
        }
        if nums.len() != 2 { return Err(format!("g transform: expected 2 args in {m}")); }
        let op = if name == "translate" { Xform { a: nums[0], b: nums[1], c: 1.0, d: 1.0 } } else { Xform { a: 0.0, b: 0.0, c: nums[0], d: nums[1] } };
        // Document order: transform="A B" maps p -> A(B(p)).
        xf = compose(xf, op);
        if ![xf.a, xf.b, xf.c, xf.d].iter().all(|v| v.is_finite()) {
            return Err(format!("g transform: composition overflow at: {m}"));
        }
    }
    Ok(xf)
}

fn path_fill(tag: &str) -> Option<String> {
    for key in ["fill:#", "fill=\"#"] {
        if let Some(i) = tag.find(key) {
            let rest = &tag[i + key.len()..];
            let end = rest.find(|c| c == '"' || c == ';').unwrap_or(rest.len().min(6));
            return Some(rest[..end].to_lowercase());
        }
    }
    None
}

fn parse_path_d(d: &str) -> Result<Vec<(Point, Vec<Span>)>, String> {
    let b = d.as_bytes();
    let mut i = 0usize;
    let mut tok = Vec::new();
    while i < b.len() {
        let c = b[i] as char;
        if c.is_ascii_alphabetic() { tok.push(c.to_string()); i += 1; }
        else if c.is_ascii_digit() || c == '-' || c == '+' || c == '.' {
            let s = i;
            if c == '-' || c == '+' { i += 1; }
            while i < b.len() && ((b[i] as char).is_ascii_digit() || b[i] == b'.') { i += 1; }
            tok.push(d[s..i].to_string());
        } else if c.is_ascii_whitespace() || c == ',' { i += 1; }
        else { return Err(format!("path: unexpected character {c:?}")); }
    }
    let mut rings: Vec<(Point, Vec<Span>)> = Vec::new();
    let mut cur = Point { x: 0.0, y: 0.0 };
    let mut start = cur;
    let mut spans: Vec<Span> = Vec::new();
    let mut idx = 0usize;
    let mut last_cmd = 'M';
    let num = |idx: &mut usize| -> Result<f64, String> {
        if *idx >= tok.len() { return Err("path: truncated".into()); }
        let v: f64 = tok[*idx].parse().map_err(|_| "path: bad number")?;
        if !v.is_finite() { return Err("path: number overflow".into()); }
        *idx += 1; Ok(v)
    };
    while idx < tok.len() {
        let idx_before = idx;
        let cmd = if tok[idx].len() == 1 && tok[idx].chars().next().unwrap().is_ascii_alphabetic() {
            let c = tok[idx].chars().next().unwrap(); idx += 1; c
        } else {
            // implicit repeat: after M/m implicit is L/l; after Z there is
            // no implicit continuation - leftover tokens are a typed error.
            match last_cmd { 'M' => 'L', 'm' => 'l', 'Z' | 'z' => return Err("path: tokens after close".into()), c => c }
        };
        last_cmd = cmd;
        let rel = cmd.is_ascii_lowercase();
        let c = cmd.to_ascii_uppercase();
        match c {
            'M' => {
                if !spans.is_empty() { rings.push((start, std::mem::take(&mut spans))); }
                let (mut x, mut y) = (num(&mut idx)?, num(&mut idx)?);
                if rel { x += cur.x; y += cur.y; }
                cur = Point { x, y }; start = cur;
            }
            'L' => {
                let (mut x, mut y) = (num(&mut idx)?, num(&mut idx)?);
                if rel { x += cur.x; y += cur.y; }
                cur = Point { x, y }; spans.push(Span::Line { end: cur });
            }
            'H' => {
                let mut x = num(&mut idx)?; if rel { x += cur.x; }
                cur = Point { x, y: cur.y }; spans.push(Span::Line { end: cur });
            }
            'V' => {
                let mut y = num(&mut idx)?; if rel { y += cur.y; }
                cur = Point { x: cur.x, y }; spans.push(Span::Line { end: cur });
            }
            'C' => {
                let (mut x1, mut y1) = (num(&mut idx)?, num(&mut idx)?);
                let (mut x2, mut y2) = (num(&mut idx)?, num(&mut idx)?);
                let (mut x3, mut y3) = (num(&mut idx)?, num(&mut idx)?);
                if rel { x1 += cur.x; y1 += cur.y; x2 += cur.x; y2 += cur.y; x3 += cur.x; y3 += cur.y; }
                spans.push(Span::Cubic { control_one: Point { x: x1, y: y1 }, control_two: Point { x: x2, y: y2 }, end: Point { x: x3, y: y3 } });
                cur = Point { x: x3, y: y3 };
            }
            'Z' => {
                if cur.x != start.x || cur.y != start.y { spans.push(Span::Line { end: start }); }
                if spans.is_empty() { return Err("path: empty subpath".into()); }
                cur = start;
                rings.push((start, std::mem::take(&mut spans)));
            }
            other => return Err(format!("path: unsupported command {other} (subset: M/L/H/V/C/Z only, no scientific notation)")),
        }
        if idx == idx_before { return Err("path: no progress, unconsumed tokens".into()); }
    }
    if !spans.is_empty() { rings.push((start, spans)); }
    Ok(rings)
}

pub fn signed_area(start: Point, spans: &[Span]) -> f64 {
    let mut area = 0.0; let mut cur = start;
    let mut edge = |p: Point| { area += cur.x * p.y - p.x * cur.y; cur = p; };
    for s in spans { match s { Span::Line { end } => edge(*end), Span::Cubic { end, .. } => edge(*end) } }
    area += cur.x * start.y - start.x * cur.y;
    area / 2.0
}

/// Next `<path` tag with a real boundary (whitespace, `/` or `>` after the
/// name), skipping comments entirely - a `<path` inside a comment is never
/// parsed, and `<pathology>` is not a path. Unterminated comments are typed
/// refusals.
fn next_path_tag(s: &str) -> Result<Option<usize>, String> {
    // Iterative cursor: constant stack no matter how many comments precede
    // the path (a comment-dense input must return Result, never abort).
    let mut base = 0usize;
    loop {
        let mut advanced = false;
        for (i, _) in s[base..].match_indices('<') {
            let rest = &s[base + i..];
            if rest.starts_with("<!--") {
                let end = rest[4..].find("-->").ok_or("comment: unterminated")?;
                base += i + 4 + end + 3;
                advanced = true;
                break;
            }
            if rest.starts_with("<path")
                && matches!(rest[5..].chars().next(), Some(c) if c.is_ascii_whitespace() || c == '/' || c == '>')
            {
                return Ok(Some(base + i));
            }
        }
        if !advanced { return Ok(None); }
    }
}

pub fn parse_svg(svg: &str, mode: &str, canvas: (usize, usize)) -> Result<Vec<(Point, Vec<Span>, bool)>, String> {
    // returns (start, spans, is_white)
    let group = parse_g_transform(svg)?;
    let mut out = Vec::new();
    let mut base = 0usize;
    let mut rest = svg;
    while let Some(i) = next_path_tag(rest)? {
        let abs = base + i;
        let after = &rest[i..];
        let close = after.find('>').ok_or("path tag")?;
        let tag = &after[..close];
        if tag.contains("transform") { return Err("path transform: unsupported (coordinates must be path data only)".into()); }
        let d_pos = tag.find("d=\"").ok_or("path d")?;
        let d_rest = &tag[d_pos + 3..];
        let d_end = d_rest.find('"').ok_or("path d end")?;
        let d = &d_rest[..d_end];
        let fill = path_fill(tag).unwrap_or_else(|| "000000".into());
        let is_white = fill == "ffffff" || fill == "fff";
        // The group transform applies only to paths inside the group span.
        let xf = match &group {
            Some(g) if abs >= g.content_start && abs < g.content_end => g.xf,
            _ => Xform { a: 0.0, b: 0.0, c: 1.0, d: 1.0 },
        };
        for (start, spans) in parse_path_d(d)? {
            let xf_start = xf.apply(start);
            let xf_spans: Vec<Span> = spans.iter().map(|s| match s {
                Span::Line { end } => Span::Line { end: xf.apply(*end) },
                Span::Cubic { control_one, control_two, end } => Span::Cubic { control_one: xf.apply(*control_one), control_two: xf.apply(*control_two), end: xf.apply(*end) },
            }).collect();
            let finite = [xf_start.x, xf_start.y].iter().all(|v| v.is_finite())
                && xf_spans.iter().all(|s| match s {
                    Span::Line { end } => end.x.is_finite() && end.y.is_finite(),
                    Span::Cubic { control_one, control_two, end } => [control_one, control_two, end].iter().all(|p| p.x.is_finite() && p.y.is_finite()),
                });
            if !finite { return Err("g transform: nonfinite output coordinate".into()); }
            out.push((xf_start, xf_spans, is_white));
        }
        base = abs + close + 1;
        rest = &svg[base..];
    }
    if out.is_empty() { return Err("svg: no paths".into()); }
    // Background drop for color tools: a white ring covering the whole canvas.
    if mode != "potrace" {
        let (w, h) = (canvas.0 as f64, canvas.1 as f64);
        out.retain(|(s, spans, white)| {
            if !white { return true; }
            let (mut minx, mut miny, mut maxx, mut maxy) = (f64::MAX, f64::MAX, f64::MIN, f64::MIN);
            let mut visit = |p: Point| { minx = minx.min(p.x); miny = miny.min(p.y); maxx = maxx.max(p.x); maxy = maxy.max(p.y); };
            visit(*s);
            for sp in spans { match sp { Span::Line { end } => visit(*end), Span::Cubic { control_one, control_two, end } => { visit(*control_one); visit(*control_two); visit(*end); } } }
            !(minx <= 0.5 && miny <= 0.5 && maxx >= w - 0.5 && maxy >= h - 0.5)
        });
    }
    Ok(out)
}

// ---------- join classification ----------

fn join_metrics(rings: &[ReferenceRing], tol_deg: f64) -> (usize, usize, usize) {
    let (mut smooth, mut corner, mut cbreaks) = (0usize, 0usize, 0usize);
    let tol = tol_deg.to_radians();
    for r in rings {
        let n = r.spans.len();
        if n == 0 { continue; }
        let dir_out = |prev_end: Point, s: &Span| -> Point {
            match s { Span::Line { end } => Point { x: end.x - prev_end.x, y: end.y - prev_end.y },
                      Span::Cubic { control_one, .. } => Point { x: control_one.x - prev_end.x, y: control_one.y - prev_end.y } }
        };
        let dir_in = |prev_end: Point, s: &Span| -> Point {
            match s { Span::Line { end } => Point { x: end.x - prev_end.x, y: end.y - prev_end.y },
                      Span::Cubic { control_two, end, .. } => Point { x: end.x - control_two.x, y: end.y - control_two.y } }
        };
        // vertex between span i-1 (ending at v) and span i
        let mut ends: Vec<Point> = Vec::with_capacity(n);
        {
            for s in &r.spans { let c = match s { Span::Line { end } => *end, Span::Cubic { end, .. } => *end }; ends.push(c); }
        }
        for i in 0..n {
            let v = ends[(i + n - 1) % n];
            let s_prev = &r.spans[(i + n - 1) % n];
            let s_cur = &r.spans[i];
            let before_v = if i == 0 { r.start } else { ends[(i + n - 2) % n] };
            let din = dir_in(before_v, s_prev);
            let dout = dir_out(v, s_cur);
            let (li, lo) = ((din.x * din.x + din.y * din.y).sqrt(), (dout.x * dout.x + dout.y * dout.y).sqrt());
            if li == 0.0 || lo == 0.0 { corner += 1; continue; }
            let cos = ((din.x * dout.x + din.y * dout.y) / (li * lo)).clamp(-1.0, 1.0);
            let ang = cos.acos();
            if ang <= tol { smooth += 1; } else {
                corner += 1;
                if matches!(s_prev, Span::Cubic { .. }) && matches!(s_cur, Span::Cubic { .. }) { cbreaks += 1; }
            }
        }
    }
    (smooth, corner, cbreaks)
}

fn main() -> Result<(), String> {
    let a: Vec<String> = std::env::args().collect();
    if a.len() != 9 {
        return Err("usage: race_external MANIFEST TILEDIR MODE INPUT THRESHOLD FLATTEN_STEPS TANGENT_TOL_DEG OUT_TSV".into());
    }
    let manifest_path = std::path::PathBuf::from(&a[1]);
    let tiledir = &a[2];
    let mode = a[3].as_str();
    let input = &a[4];
    let threshold: u8 = a[5].parse().map_err(|_| "bad threshold")?;
    let flatten_steps: usize = a[6].parse().map_err(|_| "bad flatten steps")?;
    let tol_deg: f64 = a[7].parse().map_err(|_| "bad tangent tol")?;
    let out_path = &a[8];
    if !matches!(mode, "potrace" | "autotrace" | "vtracer" | "kni-otf") { return Err("bad mode".into()); }
    let text = String::from_utf8(read_capped(&a[1], MAX_MANIFEST_BYTES, "manifest")?).map_err(|_| "manifest: not utf8".to_string())?;
    let _ = &manifest_path;
    let mc_cfg = parse_manifest(&text, tiledir)?;
    let k = if mode == "kni-otf" { mc_cfg.scale } else { 1.0 };

    let font = if mode == "kni-otf" {
        let bytes = read_capped(input, MAX_OTF_BYTES, "otf")?;
        let sha = sha256_hex(&bytes);
        Some(CffReader::from_bytes(&bytes, &sha).map_err(|e| format!("otf parse: {e:?}"))?)
    } else { None };

    let mut tsv = String::from("glyph\tcodepoint\tengine\tnodes\tsegments_line\tsegments_cubic\tcubic_ratio\tjoins_smooth\tjoins_corner\tcurvature_breaks\tiou_scan_domain\tnotes\n");
    for g in &mc_cfg.glyphs {
        let mut notes: Vec<String> = Vec::new();
        if let Err(e) = safe_glyph_name(&g.name) { tsv.push_str(&format!("{}\t{}\t{}\t-\t-\t-\t-\t-\t-\t-\t-\tglyph_name_refused:{e}\n", g.name, g.cp, mode)); continue; }
        let png = match read_capped(&g.path, MAX_TILE_BYTES, "tile") { Ok(b) => b, Err(e) => { tsv.push_str(&format!("{}\t{}\t{}\t-\t-\t-\t-\t-\t-\t-\t-\ttile_read_error:{e}\n", g.name, g.cp, mode)); continue; } };
        let png_sha = sha256_hex(&png);
        if let Err(e) = verify_tile_pin(&g.path, &png_sha) {
            tsv.push_str(&format!("{}\t{}\t{}\t-\t-\t-\t-\t-\t-\t-\t-\t{e}\n", g.name, g.cp, mode)); continue;
        }
        let mc = match capture_png(&png, mc_cfg.eps) { Ok(m) => m, Err(e) => { tsv.push_str(&format!("{}\t{}\t{}\t-\t-\t-\t-\t-\t-\t-\t-\tcapture_refused:{e}\n", g.name, g.cp, mode)); continue; } };
        let (w, h) = (mc.width, mc.height);
        let rings: Vec<ReferenceRing> = if mode == "kni-otf" {
            let f = font.as_ref().unwrap();
            let cp = u32::from_str_radix(g.cp.trim_start_matches("0x"), 16).map_err(|_| "bad cp")?;
            match f.read_codepoint(cp) {
                Ok(Some(rg)) => rg.drawn(g.name.clone()).rings,
                Ok(None) => { tsv.push_str(&format!("{}\t{}\t{}\t-\t-\t-\t-\t-\t-\t-\t-\tnot_shipped:absent_from_cff_charstrings\n", g.name, g.cp, mode)); continue; }
                Err(e) => { tsv.push_str(&format!("{}\t{}\t{}\t-\t-\t-\t-\t-\t-\t-\t-\totf_read_refused:{e:?}\n", g.name, g.cp, mode)); continue; }
            }
        } else {
            let svg_path = format!("{input}/{}.svg", g.name);
            let svg = match read_capped(&svg_path, MAX_SVG_BYTES, "svg").and_then(|b| String::from_utf8(b).map_err(|_| "svg: not utf8".to_string())) { Ok(s) => s, Err(e) => { tsv.push_str(&format!("{}\t{}\t{}\t-\t-\t-\t-\t-\t-\t-\t-\tsvg_read_error:{e}\n", g.name, g.cp, mode)); continue; } };
            let parsed = match parse_svg(&svg, mode, (w, h)) { Ok(p) => p, Err(e) => { tsv.push_str(&format!("{}\t{}\t{}\t-\t-\t-\t-\t-\t-\t-\t-\tsvg_parse_error:{e}\n", g.name, g.cp, mode)); continue; } };
            let mut rr: Vec<ReferenceRing> = Vec::new();
            for (start, spans, is_white) in parsed {
                // image px (y-down) -> evaluator font frame (y-up), capture origin
                let conv = |p: Point| Point { x: p.x - mc.origin_x, y: -p.y - mc.origin_y };
                let mut st = conv(start);
                let mut sp: Vec<Span> = spans.iter().map(|s| match s {
                    Span::Line { end } => Span::Line { end: conv(*end) },
                    Span::Cubic { control_one, control_two, end } => Span::Cubic { control_one: conv(*control_one), control_two: conv(*control_two), end: conv(*end) },
                }).collect();
                // Winding normalization per tool SVG convention (font frame,
                // post-conversion): potrace and vtracer author counter
                // subpaths opposite to their outer rings, so their winding is
                // kept as-is. autotrace emits counters as separate white
                // paths authored in the same convention as ink; force ink
                // positive and white negative so the nonzero rasterizer
                // yields black-minus-white.
                if mode == "autotrace" {
                    let area = signed_area(st, &sp);
                    let want_positive = !is_white;
                    if area != 0.0 && (area > 0.0) != want_positive {
                        let mut rev: Vec<Span> = Vec::with_capacity(sp.len());
                        let pts: Vec<Point> = sp.iter().map(|s| match s { Span::Line { end } => *end, Span::Cubic { end, .. } => *end }).collect();
                        for (i, s) in sp.iter().enumerate().rev() {
                            let from = if i == 0 { st } else { pts[i - 1] };
                            match s {
                                Span::Line { .. } => rev.push(Span::Line { end: from }),
                                Span::Cubic { control_one, control_two, .. } => rev.push(Span::Cubic { control_one: *control_two, control_two: *control_one, end: from }),
                            }
                        }
                        st = *pts.last().unwrap(); sp = rev;
                    }
                }
                rr.push(ReferenceRing { start: st, spans: sp });
            }
            rr
        };
        let (mut line, mut cubic, mut nodes) = (0usize, 0usize, 0usize);
        for r in &rings {
            nodes += 1 + r.spans.len().saturating_sub(1);
            for s in &r.spans { match s { Span::Line { .. } => line += 1, Span::Cubic { .. } => cubic += 1 } }
        }
        let total = line + cubic;
        let cubic_ratio = if total == 0 { 0.0 } else { cubic as f64 / total as f64 };
        let (smooth, corner, cbreaks) = join_metrics(&rings, tol_deg);
        let cfg = EvalConfig {
            frame_id: format!("RACE-{}-SCAN{}", mode, threshold),
            scale_k: k, threshold, canvas: (w, h), capture_eps: mc_cfg.eps, flatten_steps,
            expected_source_sha256: png_sha, advance: mc_cfg.upm,
            render_limits: RenderLimits { max_pixels: w * h, max_flatten_steps: flatten_steps, max_edges: 16 * w * h, max_working_bytes: 268435456 },
        };
        let iou_s = match ProductionEvaluator::new(cfg, &png) {
            Ok(ev) => match ev.render_mask(&DrawnGlyph { glyph_id: g.name.clone(), rings: rings.clone() }) {
                Ok(cover) => {
                    let src = ev.source_mask();
                    if cover.len() != src.len() {
                        notes.push(format!("iou_unassessable:mask_len:cover:{}:src:{}", cover.len(), src.len())); "-".into()
                    } else {
                        let (mut inter, mut uni) = (0u64, 0u64);
                        for (i2, &c) in cover.iter().enumerate() { let s = src[i2]; if c && s { inter += 1; } if c || s { uni += 1; } }
                        if uni == 0 { notes.push("iou_unassessable:empty_union".into()); "-".into() } else { format!("{:.6}", inter as f64 / uni as f64) }
                    }
                }
                Err(e) => { notes.push(format!("iou_unassessable:render_refused:{e:?}")); "-".into() }
            },
            Err(e) => { notes.push(format!("evaluator_refused:{e}")); "-".into() }
        };
        let note = if notes.is_empty() { "-".into() } else { notes.join(",") };
        tsv.push_str(&format!("{}\t{}\t{}\t{}\t{}\t{}\t{:.6}\t{}\t{}\t{}\t{}\t{}\n", g.name, g.cp, mode, nodes, line, cubic, cubic_ratio, smooth, corner, cbreaks, iou_s, note));
    }
    // Atomic-ish publish: write temp, then rename, so a failed run never
    // leaves a partial TSV at the output path.
    let tmp = format!("{out_path}.tmp");
    std::fs::write(&tmp, tsv).map_err(|e| format!("write tmp: {e}"))?;
    std::fs::rename(&tmp, out_path).map_err(|e| format!("rename: {e}"))?;
    Ok(())
}
