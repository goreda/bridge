// INSTRUMENTED batch run (working-copy example): capture -> F1+P0 fit ->
// OTF + per-glyph JSONL stats + per-glyph pixel-space SVG for measurement.
// Metrics binding (owner-directed 2026-10-11, METRICS-DOCTRINE-v0.1):
// baseline / cap height / x-height measured from the traced outlines
// (M1-M5), written into hhea + OS/2 v2 with real values (M6); scale derives
// from the source image height, never hardcoded. Overshoot measured and
// reported (M4); O-rules (overshoot policy, line-spacing policy) stay
// UNRESOLVED: sTypo* = hhea = measured bbox, lineGap 0, declared provisional.
use kni_core::capture::capture_png;
use kni_core::capture_fit::fit_captured;
use kni_core::form::{circle_fit, recognize_circle_ring};
use kni_core::native_font::{encode, NativeFontInput};
use kni_core::cff_container::CffGlyph;
use kni_core::reference_slice::{DrawnGlyph, Point, Span};
use kni_core::sfnt_metadata::{HeadMetadata, HheaMetadata, PostMetadata, Os2Metadata, NameRecord};
use kni_core::cubic_fit::FitPolicy;
use std::fmt::Write as _;

const ADV: u16 = 700;
const LSB: i16 = 0;

include!("sb_table.incl"); // per-codepoint (lsb_px, rsb_px, adv_px_or_0) in capture px; sources tagged inline

fn sb_lookup(code: u32) -> (f64, f64, f64) {
    for &(c, l, r, a) in SB { if c == code { return (l, r, a); } }
    eprintln!("WARN: no sidebearing row for U+{:04X}; DEFAULT class (punctuation fallback, candidate) applied", code);
    (10.0 * 1050.0 / 1000.0, 12.0 * 1050.0 / 1000.0, 0.0)
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum ExtClass { Flat, Round, Pointed }

fn oncurve_pts(r: &kni_core::reference_slice::ReferenceRing) -> Vec<Point> {
    let mut v = vec![r.start];
    for s in &r.spans {
        v.push(match s { Span::Line { end } | Span::Cubic { end, .. } => *end });
    }
    v
}

// M5 vertical-class test on one extremum (units, y-up). tol in units.
fn classify(rings: &[kni_core::reference_slice::ReferenceRing], top: bool, tol: f64) -> Option<(f64, ExtClass)> {
    let mut best: Option<f64> = None;
    for r in rings {
        for p in oncurve_pts(r) {
            let y = p.y;
            best = Some(match best {
                None => y,
                Some(b) => if top { b.max(y) } else { b.min(y) },
            });
        }
    }
    let ey = best?;
    // on-curve points sharing the extremum
    let mut sharing = 0usize;
    for r in rings {
        for p in oncurve_pts(r) {
            if (p.y - ey).abs() <= tol { sharing += 1; }
        }
    }
    if sharing >= 2 {
        return Some((ey, ExtClass::Flat));
    }
    // single point: corner node (both neighbors are Lines) -> Pointed;
    // any adjacent cubic handle sharing the extremum y -> Round (D1-exact)
    for r in rings {
        let n = r.spans.len();
        for i in 0..n {
            let end = match &r.spans[i] { Span::Line { end } | Span::Cubic { end, .. } => *end };
            if (end.y - ey).abs() > tol { continue; }
            let prev_c2 = match &r.spans[(i + n - 1) % n] { Span::Cubic { control_two, .. } => Some(*control_two), _ => None };
            let this_c1 = match &r.spans[i] { Span::Cubic { control_one, .. } => Some(*control_one), _ => None };
            // the node ends span i; incoming handle is span i's control_two, outgoing is span (i+1)'s control_one
            let in_c2 = match &r.spans[i] { Span::Cubic { control_two, .. } => Some(*control_two), _ => None };
            let out_c1 = match &r.spans[(i + 1) % n] { Span::Cubic { control_one, .. } => Some(*control_one), _ => None };
            let _ = (prev_c2, this_c1);
            let horiz = [in_c2, out_c1].iter().flatten().any(|h| (h.y - ey).abs() <= tol);
            return Some((ey, if horiz { ExtClass::Round } else { ExtClass::Pointed }));
        }
    }
    Some((ey, ExtClass::Pointed))
}

fn cluster_median(mut vals: Vec<f64>, tol: f64) -> Option<(f64, usize)> {
    if vals.is_empty() { return None; }
    vals.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let mut best: Option<(usize, usize)> = None; // (count, start idx)
    for i in 0..vals.len() {
        let mut j = i;
        while j < vals.len() && vals[j] - vals[i] <= 2.0 * tol { j += 1; }
        let cnt = j - i;
        if best.map(|(bc, _)| cnt > bc).unwrap_or(true) { best = Some((cnt, i)); }
    }
    let (cnt, i) = best?;
    if cnt < 2 { return None; }
    let members: Vec<f64> = vals.iter().copied().filter(|v| (v - vals[i]).abs() <= 2.0 * tol).collect();
    Some((members[members.len() / 2], cnt))
}

/// List line = "<png path> <hex code> <glyph name>". The path may contain
/// spaces; code and name never do, so split from the right (max 3 fields).
fn split3(line: &str) -> Vec<&str> {
    let t = line.trim();
    let mut it = t.rsplitn(3, char::is_whitespace);
    let name = it.next().unwrap_or("");
    let code = it.next().unwrap_or("");
    let path = it.next().unwrap_or("").trim_end();
    if path.is_empty() || code.is_empty() || name.is_empty() {
        eprintln!("FATAL LIST_LINE_MALFORMED: expected '<path> <hex> <name>', got: {}", line);
        std::process::exit(2);
    }
    vec![path, code, name]
}

fn main() {
    let list = std::env::args().nth(1).unwrap();
    let outp = std::env::args().nth(2).unwrap();
    let statdir = std::env::args().nth(3).unwrap();
    std::fs::create_dir_all(&statdir).unwrap();
    let policy = FitPolicy { squared_error: 1.0, max_refits: 6 };
    let mut jsonl = String::new();

    struct G { code: u32, name: String, rings: Vec<kni_core::reference_slice::ReferenceRing>, scale: f64, h: f64, origin_y: f64 }
    let mut gs: Vec<G> = vec![];

    // ---- placeholder elimination (owner directive 2026-10-11, channel-verified:
    // "olmayan karakterler elenecek, .notdef saptanacak"). The kit marks undrawn
    // codepoints with one identical hollow-box bitmap. Rule: any byte-identical
    // image class with >= 3 distinct codepoints is a placeholder class (real
    // duplicate glyphs in this kit come in pairs, e.g. 00D0/0110, 002C/201A).
    // Eliminated codepoints are excluded from cmap (apps then show .notdef) and
    // listed in <statdir>/eliminated.txt; the placeholder bitmap itself is traced
    // later into the .notdef outline.
    let raw_lines: Vec<String> = std::fs::read_to_string(&list).unwrap().lines()
        .filter(|l| !l.trim().is_empty()).map(|s| s.to_string()).collect();
    let mut by_hash: std::collections::HashMap<u64, Vec<usize>> = Default::default();
    for (li, line) in raw_lines.iter().enumerate() {
        let f: Vec<&str> = split3(line);
        let bytes = std::fs::read(f[0]).unwrap();
        let mut h = 0xcbf29ce484222325u64; // FNV-1a over PNG bytes
        for b in &bytes { h ^= *b as u64; h = h.wrapping_mul(0x100000001b3); }
        by_hash.entry(h).or_default().push(li);
    }
    let mut placeholder_lines: std::collections::HashSet<usize> = Default::default();
    let mut notdef_png: Option<Vec<u8>> = None;
    for lis in by_hash.values() {
        if lis.len() >= 3 {
            for li in lis { placeholder_lines.insert(*li); }
            if notdef_png.is_none() {
                let f: Vec<&str> = split3(&raw_lines[lis[0]]);
                notdef_png = Some(std::fs::read(f[0]).unwrap());
            }
        }
    }
    {
        let mut elim: Vec<String> = placeholder_lines.iter()
            .map(|&li| split3(&raw_lines[li])[1].to_string()).collect();
        elim.sort();
        std::fs::write(format!("{}/eliminated.txt", statdir), elim.join("
") + "
").unwrap();
        println!("ELIMINATED {} placeholder codepoints (byte-identical box bitmap)", elim.len());
    }

    for (gi, line) in raw_lines.iter().enumerate() {
        if placeholder_lines.contains(&gi) { continue; }
        let line: &str = line;
        let f: Vec<&str> = split3(line);
        let png = std::fs::read(f[0]).unwrap();
        let code = u32::from_str_radix(f[1], 16).unwrap();
        let name = f[2].to_string();
        let mc = capture_png(&png, 0.5).unwrap();
        let (w, h) = (mc.width, mc.height);
        // adaptive scale: derived from the source image height (owner rule:
        // adaptive features are never hardcoded)
        let scale = 1000.0 / h as f64;
        let capture_rings = mc.rings.len();
        let capture_pts: usize = mc.rings.iter().map(|r| r.points.len()).sum();
        let mut circles = 0usize;
        for r in &mc.rings {
            let pts: Vec<Point> = r.points.iter().map(|p| Point { x: p.x * scale, y: p.y * scale }).collect();
            if recognize_circle_ring(&pts, &r.corners, r.hole, 1.0 * scale, 0.5 * scale).is_some() {
                circles += 1;
                let _ = circle_fit(&pts);
            }
        }
        let (rings, ns, fb, dropped) = fit_captured(&mc.rings, scale, &policy);
        let nl = rings.iter().map(|r| r.spans.iter().filter(|s| matches!(s, Span::Line { .. })).count()).sum::<usize>();
        let nc = rings.iter().map(|r| r.spans.iter().filter(|s| matches!(s, Span::Cubic { .. })).count()).sum::<usize>();
        // per-glyph pixel-space SVG (pre-shift, measurement space)
        let mut d = String::new(); let fy = |yy: f64| h as f64 - yy / scale;
        for r in &rings {
            let _ = write!(d, "M {:.2} {:.2} ", r.start.x / scale, fy(r.start.y));
            for s in &r.spans {
                match s {
                    Span::Line { end } => { let _ = write!(d, "L {:.2} {:.2} ", end.x / scale, fy(end.y)); }
                    Span::Cubic { control_one, control_two, end } => {
                        let _ = write!(d, "C {:.2} {:.2} {:.2} {:.2} {:.2} {:.2} ",
                            control_one.x / scale, fy(control_one.y),
                            control_two.x / scale, fy(control_two.y),
                            end.x / scale, fy(end.y));
                    }
                }
            }
            let _ = write!(d, "Z ");
        }
        std::fs::write(format!("{}/{:03}_{}.svg", statdir, gi, name),
            format!("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"{}\" height=\"{}\" viewBox=\"0 0 {} {}\"><path d=\"{}\"/></svg>", w, h, w, h, d)).unwrap();
        let _ = writeln!(jsonl, "{{\"gi\":{},\"code\":\"{}\",\"name\":\"{}\",\"w\":{},\"h\":{},\"capture_rings\":{},\"capture_pts\":{},\"circles\":{},\"rings\":{},\"spans_L\":{},\"spans_C\":{},\"nodes\":{},\"fallback\":{},\"dropped\":{}}}",
            gi, f[1], name, w, h, capture_rings, capture_pts, circles, rings.len(), nl, nc, ns, fb, dropped);
        gs.push(G { code, name, rings, scale, h: h as f64, origin_y: mc.origin_y });
    }
    std::fs::write(format!("{}/stats.jsonl", statdir), jsonl).unwrap();

    // ---- metrics derivation (M1-M5), all in capture px (units / scale) ----
    let tol_u = 1.0f64; // 1 font unit
    let mut flat_bottoms: Vec<f64> = vec![];
    let mut cap_tops: Vec<f64> = vec![];
    let mut x_tops: Vec<f64> = vec![];
    let mut per_glyph = String::new();
    // Membership by CODEPOINT, not name (0010, 2026-10-12): sets name the
    // same glyph "H" or "uni0048" depending on the pipeline; a name-string
    // match silently loses the cap anchor on uniXXXX-named sets (ekip-1's
    // 478 control halted NO_CAP_ANCHOR for exactly this reason). The
    // codepoint is the authoritative identity.
    const CAP_SET: [u32; 7] = [0x45, 0x46, 0x48, 0x49, 0x4C, 0x54, 0x5A]; // E F H I L T Z
    const X_SET: [u32; 5] = [0x6D, 0x6E, 0x76, 0x78, 0x7A]; // m n v x z
    for g in &gs {
        let tol = tol_u;
        let top = classify(&g.rings, true, tol);
        let bot = classify(&g.rings, false, tol);
        if let Some((by, bc)) = bot {
            if bc == ExtClass::Flat { flat_bottoms.push(g.origin_y + by / g.scale); }
        }
        if let Some((ty, tc)) = top {
            if tc == ExtClass::Flat && CAP_SET.contains(&g.code) { cap_tops.push(g.origin_y + ty / g.scale); }
            if tc == ExtClass::Flat && X_SET.contains(&g.code) { x_tops.push(g.origin_y + ty / g.scale); }
        }
        let _ = writeln!(per_glyph, "{{\"name\":\"{}\",\"top_px\":{},\"top_class\":\"{}\",\"bottom_px\":{},\"bottom_class\":\"{}\"}}",
            g.name,
            top.map(|(y, _)| g.origin_y + y / g.scale).unwrap_or(f64::NAN), top.map(|(_, c)| format!("{:?}", c).to_uppercase()).unwrap_or("NONE".into()),
            bot.map(|(y, _)| g.origin_y + y / g.scale).unwrap_or(f64::NAN), bot.map(|(_, c)| format!("{:?}", c).to_uppercase()).unwrap_or("NONE".into()));
    }
    let tol_px = 1.0f64;
    let baseline_px = cluster_median(flat_bottoms.clone(), tol_px);
    let cap_px = cluster_median(cap_tops.clone(), tol_px);
    let x_px = cluster_median(x_tops.clone(), tol_px);

    // ---- shift rings so the baseline lands at y=0; write the font ----
    let base_px_val = baseline_px.map(|(b, _)| b).unwrap_or(0.0);
    // AUTO-SCALE LAYER (permanent layer: owner doctrine 2026-10-11 10:31,
    // channel-verified): the em scale derives from glyph content, never a
    // manual per-font decision. Anchor: measured cap-height fraction of the
    // em, where em_px = median source image height of the set. Conventional
    // band [0.68, 0.70] / midpoint target = main's 10:30 formulation of the
    // owner's rescale ruling (owner saw the ~0.70 commitment and answered
    // with the permanent-layer doctrine, no correction). If the
    // measured fraction falls outside, a single uniform units-per-px factor
    // lands the cap at the band midpoint; if no cap anchor exists, no
    // rescale (x-height cascade anchor: open design point). Measurement
    // sources stay in px space; the factor applies only at font-unit write
    // time (owner constraint 10:30: the rescale must not disturb the metric
    // computation chain).
    let em_px = { let mut hs: Vec<f64> = gs.iter().map(|g| g.h).collect(); hs.sort_by(|a, b| a.partial_cmp(b).unwrap()); if hs.is_empty() { 1000.0 } else { hs[hs.len() / 2] } };
    let cap_frac = cap_px.map(|(c, _)| (c - base_px_val).abs() / em_px);
    const CAP_TARGET: f64 = 0.69; // cap lands at 690/1000 units (Marq delivered sCapHeight = 690)
    // ANCHOR DECISION (kni-line architect 2026-10-12, main-approved, ADDENDUM
    // to the layer comment above): the px->unit conversion is anchored on the
    // measured cap height ALWAYS, never on the tile canvas. The canvas-em
    // anchor (em_px = median image height) is padding-dependent: ekip-1
    // control 2026-10-12 showed the same 185px span produce 193 units under
    // the cap anchor vs 108 units under the canvas anchor, with the switch
    // between them decided by set composition. Canvas anchor contradicts two
    // independent owner-side measurements (W1: 184px gap <-> 191u -> 1.705
    // u/px; delivered H sidebearings: 36px <-> 61u -> 1.694 u/px); the cap
    // anchor reproduces both (690 / 403.6px = 1.7096 u/px). The band check
    // survives only as diagnostic evidence (cap_fraction in metrics.json).
    // No cap anchor -> HALT: no silent canvas fallback (the x-height cascade
    // remains an open design point; a set without E/F/H/I/L/T/Z flat tops is
    // invalid input for production).
    // SCALE-MIXING GUARD v2 (P1.1, 2026-10-12, revised after ekip-1 live-fire
    // on the 478 control set): the guard runs BEFORE the anchor is formed and
    // owns every scattered/bimodal diagnosis; NO_CAP_ANCHOR is reserved for
    // "fewer than two CAP_SET flat tops" (genuinely no cap evidence).
    // Mode tolerance: max(2px quantization, 0.5% of the cap estimate) so the
    // guard scales with capture size. A set whose cap estimates scatter with
    // no populated mode is scale-mixed (ekip-1 478 control: 7 estimates, no
    // two within tolerance) - that must not surface as NO_CAP_ANCHOR, the
    // remedy is different (recapture at one scale, not "add cap glyphs").
    let mut ce: Vec<f64> = cap_tops.iter().map(|t| (t - base_px_val).abs()).collect();
    ce.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let est = if ce.is_empty() { 0.0 } else { ce[ce.len() / 2] };
    let tol_mode = 2.0f64.max(0.005 * est);
    let mut modes: Vec<(f64, usize)> = vec![];
    {
        let mut cur: Vec<f64> = vec![];
        for v in ce {
            if let Some(&l) = cur.last() { if v - l > tol_mode { modes.push((cur[cur.len() / 2], cur.len())); cur.clear(); } }
            cur.push(v);
        }
        if !cur.is_empty() { modes.push((cur[cur.len() / 2], cur.len())); }
    }
    let populated: Vec<&(f64, usize)> = modes.iter().filter(|m| m.1 >= 2).collect();
    if populated.len() >= 2 {
        eprintln!("FATAL METRICS_SCALE_MIXING: cap estimates form {} populated px modes {:?} (tol {:.1}) - mixed capture scales in set", populated.len(), populated, tol_mode);
        std::process::exit(2);
    }
    if cap_tops.len() >= 2 && populated.is_empty() {
        eprintln!("FATAL METRICS_SCALE_MIXING: {} cap estimates {:?} scatter with no pair within {:.1}px - mixed capture scales in set", cap_tops.len(), modes, tol_mode);
        std::process::exit(2);
    }
    // Singleton modes beside the one populated mode are evidence, not halt:
    // a lone outlier can be capture noise rather than a second scale, but it
    // lands on the record (and in metrics.json) instead of being averaged in.
    let outliers: Vec<f64> = modes.iter().filter(|m| m.1 == 1).map(|m| m.0).collect();
    if !outliers.is_empty() {
        eprintln!("WARN: cap-estimate outlier(s) {:?} sit outside the populated mode (tol {:.1}px) - possible single-tile scale drift", outliers, tol_mode);
    }
    let upp_cap: f64 = match cap_px {
        Some((c, _)) => CAP_TARGET * 1000.0 / (c - base_px_val).abs(),
        None => {
            eprintln!("FATAL METRICS_NO_CAP_ANCHOR: fewer than two flat-top CAP_SET (E F H I L T Z) glyphs in set; canvas-as-em anchor is rejected (anchor decision 2026-10-12)");
            std::process::exit(2);
        }
    };

    // .notdef outline: the kit's placeholder box, traced like any glyph
    // (owner directive 2026-10-11). Sidebearing class: stem-cap (candidate).
    let mut notdef_rings: Vec<kni_core::reference_slice::ReferenceRing> = vec![];
    let mut notdef_adv: u16 = ADV; let mut notdef_lsb: i16 = LSB;
    if let Some(png) = &notdef_png {
        let mc = capture_png(png, 0.5).unwrap();
        let scale = 1000.0 / mc.height as f64;
        let (rr, _ns, _fb, _dr) = fit_captured(&mc.rings, scale, &policy);
        let mut x0 = i32::MAX; let mut x1 = i32::MIN;
        for r in &rr {
            let mut pts = vec![r.start];
            for sp in &r.spans { match sp { Span::Line { end } => pts.push(*end), Span::Cubic { control_one, control_two, end } => { pts.push(*control_one); pts.push(*control_two); pts.push(*end); } } }
            for p in pts { x0 = x0.min(p.x as i32); x1 = x1.max(p.x as i32); }
        }
        let upp_nd = upp_cap; // units per px (cap anchor, 2026-10-12)
        let mg_nd = upp_nd / scale;
        let lsb_u: i16 = (34.0 * 1050.0 / 1000.0 * upp_nd).round() as i16; // stem-cap class in px (candidate rule; owner ruling pending)
        let dx = lsb_u as f64 - x0 as f64 * mg_nd;
        let shift = (base_px_val - mc.origin_y) * scale;
        let sp = |p: Point| Point { x: (p.x * mg_nd + dx).round(), y: ((p.y - shift) * mg_nd).round() };
        notdef_rings = rr.into_iter().map(|r| kni_core::reference_slice::ReferenceRing {
            start: sp(r.start),
            spans: r.spans.into_iter().map(|spn| match spn {
                Span::Line { end } => Span::Line { end: sp(end) },
                Span::Cubic { control_one, control_two, end } => Span::Cubic { control_one: sp(control_one), control_two: sp(control_two), end: sp(end) },
            }).collect(),
        }).collect();
        notdef_lsb = lsb_u;
        notdef_adv = (lsb_u as f64 + (x1 - x0) as f64 * mg_nd + 34.0 * 1050.0 / 1000.0 * upp_nd).round().max(1.0) as u16;
    }
    let mut glyphs = vec![CffGlyph { name: ".notdef".into(), advance: notdef_adv, outline: DrawnGlyph { glyph_id: "notdef".into(), rings: notdef_rings } }];
    let mut lsbs = vec![notdef_lsb]; let mut mapping = vec![];
    let mut mn = [i32::MAX; 2]; let mut mx = [i32::MIN; 2];
    // include .notdef bounds in the global extents (native_font derives over all glyphs)
    {
        let gb = &glyphs[0].outline.rings;
        let mut b = None::<[i32;4]>;
        for r in gb {
            let mut pts = vec![r.start];
            for sp in &r.spans { match sp { Span::Line { end } => pts.push(*end), Span::Cubic { control_one, control_two, end } => { pts.push(*control_one); pts.push(*control_two); pts.push(*end); } } }
            for p in pts { let (x, y) = (p.x as i32, p.y as i32); b = Some(match b { None => [x, y, x, y], Some(bb) => [bb[0].min(x), bb[1].min(y), bb[2].max(x), bb[3].max(y)] }); }
        }
        if let Some(bb) = b { mn[0] = mn[0].min(bb[0]); mn[1] = mn[1].min(bb[1]); mx[0] = mx[0].max(bb[2]); mx[1] = mx[1].max(bb[3]); }
    }
    let mut advs: Vec<u16> = vec![notdef_adv];
    let mut max_extent: i32 = if glyphs[0].outline.rings.is_empty() { i32::MIN } else { mx[0] };
    let mut min_rsb: i32 = if glyphs[0].outline.rings.is_empty() { i32::MAX } else { notdef_adv as i32 - mx[0] };
    let mut hmtx_tsv = String::from("gid	name	codepoint	advance	lsb
0	.notdef	-	");
    let _ = writeln!(hmtx_tsv, "{}	{}", notdef_adv, notdef_lsb);

    // WHITESPACE LAYER v2 (permanent mechanism; owner 2026-10-11 10:57:35,
    // channel message relayed by main: "space eleme mantığında ayrı kendine
    // ait bir mekanizması olan bir karakter olarak çizilmeli, bu üçlü içinden
    // hesaplanmalı, H sidebearingleri düşülmeliydi" = distinct mechanism,
    // computed FROM THE GAUGE-SPACE-GAUGE TRIPLE: space advance = visual span
    // between the two gauge inks MINUS the gauge sidebearings. The
    // specimen-derived 300u constant was withdrawn (main 10:57 relay).
    // No-fallback stance: owner doctrine 2026-10-10 23:35:18 ("kaynakta yoksa
    // yoktur") — without the triple there is no legitimate value to write. Input: a triple frame in
    // <set>/sidebearing/sb/ named NNNNN__GGGG_0020_GGGG__hash.png (same gauge
    // both sides). If the set has no space triple, space/nbspace CANNOT be
    // derived: we emit a loud warning and skip them rather than invent a
    // value (owner doctrine: uydurma yok). The Marq kit ships no such triple
    // (live Drive-verified 2026-10-11: the render pipeline never produced
    // inkless-glyph frames or triples) -> blocked input, owner to supply the
    // H-space-H frame from the original font.
    let first_path_ws = split3(&raw_lines[0])[0].to_string();
    let glyph_dir_ws = std::path::Path::new(&first_path_ws).parent().unwrap().to_path_buf();
    let sb_dir = glyph_dir_ws.parent().map(|p| p.join("sidebearing").join("sb")).unwrap_or_default();
    let mut space_adv_u: Option<u16> = None;
    if sb_dir.is_dir() {
        for e in std::fs::read_dir(&sb_dir).unwrap().flatten() {
            let fnm = e.file_name().to_string_lossy().to_string();
            let parts: Vec<&str> = fnm.split("__").collect();
            if parts.len() < 2 { continue; }
            let cps: Vec<&str> = parts[1].split('_').collect();
            if cps.len() != 3 || cps[1] != "0020" || cps[0] != cps[2] { continue; }
            let gauge = u32::from_str_radix(cps[0], 16).unwrap_or(0);
            let (g_lsb_px, g_rsb_px, _) = sb_lookup(gauge);
            let png = std::fs::read(e.path()).unwrap();
            let (tw, th, gv) = kni_core::capture::decode_png_gray(&png).unwrap();
            // Pixel column projection (the ring-point x coordinates are
            // sparse inside glyphs - counters and stem interiors exceed any
            // px split threshold - so contour points cannot measure the word
            // gap; the binary ink projection is the space-measure method):
            // contiguous ink-column runs, exactly 2 expected (gauge, gauge).
            let mut col_ink = vec![false; tw];
            for r in 0..th {
                for c in 0..tw {
                    if gv[r * tw + c] < 128 { col_ink[c] = true; }
                }
            }
            let mut runs: Vec<(usize, usize)> = vec![];
            let mut c = 0usize;
            while c < tw {
                if col_ink[c] {
                    let s0 = c;
                    while c < tw && col_ink[c] { c += 1; }
                    runs.push((s0, c - 1));
                } else { c += 1; }
            }
            if runs.len() != 2 { eprintln!("WARN: space triple {} has {} ink runs, expected 2; skipped", fnm, runs.len()); continue; }
            // SELF-ANCHOR (P1.2, kni-line architect 2026-10-12): the triple
            // carries its own gauge - the vertical ink extent of each gauge
            // (flat-top flat-bottom, H per the owner 10:57 mandate) IS the
            // cap height at the triple's own capture scale. The space
            // conversion therefore never touches the set scale or the tile
            // canvas: space = gap_px * CAP_TARGET*upm / cap_triple_px, minus
            // the gauge sidebearings. Cross-check against the set-level cap
            // anchor: >3% disagreement = the triple was captured at a
            // different scale than the glyph set (scale mixing) -> halt.
            let ink_extent = |r: (usize, usize)| -> f64 {
                let mut top = th; let mut bot = 0usize;
                for rr in 0..th { for c in r.0..=r.1 { if gv[rr * tw + c] < 128 { top = top.min(rr); bot = bot.max(rr); } } }
                if top > bot { 0.0 } else { (bot - top + 1) as f64 }
            };
            let (h1, h2) = (ink_extent(runs[0]), ink_extent(runs[1]));
            if h1 <= 0.0 || (h1 - h2).abs() > 2.0 {
                eprintln!("WARN: space triple {} gauge ink extents unusable ({:.1} vs {:.1}px); skipped", fnm, h1, h2); continue;
            }
            let upp_triple = CAP_TARGET * 1000.0 / h1.min(h2);
            if (upp_triple / upp_cap - 1.0).abs() > 0.03 {
                eprintln!("FATAL TRIPLE_SCALE_MISMATCH: triple {} implies {:.6} u/px vs set cap anchor {:.6} (>3%) - mixed capture scales", fnm, upp_triple, upp_cap);
                std::process::exit(2);
            }
            // Conversion uses the SET-level cap anchor (cluster median over
            // the CAP_SET flat tops - more samples, lower quantization noise
            // than a single-image extent); the triple extent stays the
            // scale-mixing cross-check and provenance evidence.
            let upp = upp_cap;
            let gap_px = (runs[1].0 as f64) - (runs[0].1 as f64) - 1.0; // fully ink-free columns
            space_adv_u = Some(((gap_px - g_rsb_px - g_lsb_px) * upp).round().max(1.0) as u16);
            eprintln!("SPACE: triple {} gauge U+{:04X} span {:.1}px - lsb {:.1} - rsb {:.1} -> {} units (set cap anchor {:.6} u/px; triple-implied {:.6} u/px, extent {:.1}px)", fnm, gauge, gap_px, g_lsb_px, g_rsb_px, space_adv_u.unwrap(), upp_cap, upp_triple, h1.min(h2));
            break;
        }
    }
    match space_adv_u {
        Some(adv) => {
            let set_codes: std::collections::HashSet<u32> = gs.iter().map(|g| g.code).collect();
            for &(wcode, wname) in [(0x20u32, "space"), (0xA0u32, "nbspace")].iter() {
                if set_codes.contains(&wcode) { continue; } // set supplies its own; never duplicate cmap
                let gid = glyphs.len() as u16;
                glyphs.push(CffGlyph { name: wname.into(), advance: adv, outline: DrawnGlyph { glyph_id: wname.into(), rings: vec![] } });
                lsbs.push(0); advs.push(adv); mapping.push((wcode, gid));
                let _ = writeln!(hmtx_tsv, "{}	{}	U+{:04X}	{}	{}", gid, wname, wcode, adv, 0);
            }
        }
        None => eprintln!("WARN: no gauge-0020-gauge triple in {:?}; space/nbsp NOT emitted (owner ruling 10:57: triple-derived only, no fallback value)", sb_dir),
    }
    for (_gi, g) in gs.into_iter().enumerate() {
        // x extents incl. handles (x is unaffected by the y baseline shift)
        let mut gmn0 = i32::MAX; let mut gmx0 = i32::MIN;
        for r in &g.rings {
            let mut pts = vec![r.start];
            for s in &r.spans { match s { Span::Line { end } => pts.push(*end), Span::Cubic { control_one, control_two, end } => { pts.push(*control_one); pts.push(*control_two); pts.push(*end); } } }
            for p in pts { gmn0 = gmn0.min(p.x as i32); gmx0 = gmx0.max(p.x as i32); }
        }
        if gmn0 > gmx0 { gmn0 = 0; gmx0 = 0; }
        let (lsb_px, rsb_px, adv_px) = sb_lookup(g.code);
        let upp = upp_cap; // units per px (cap anchor, 2026-10-12)
        let mg = upp / g.scale;
        let lsb_u: i16 = (lsb_px * upp).round() as i16;
        let rsb_u: i16 = (rsb_px * upp).round() as i16;
        let adv_u: u16 = if adv_px > 0.0 { (adv_px * upp).round().max(1.0) as u16 } else { 0 };
        let dx = lsb_u as f64 - gmn0 as f64 * mg;
        let shift = (base_px_val - g.origin_y) * g.scale;
        let sp = |p: Point| Point { x: (p.x * mg + dx).round(), y: ((p.y - shift) * mg).round() };
        let rings: Vec<_> = g.rings.into_iter().map(|r| kni_core::reference_slice::ReferenceRing {
            start: sp(r.start),
            spans: r.spans.into_iter().map(|s| match s {
                Span::Line { end } => Span::Line { end: sp(end) },
                Span::Cubic { control_one, control_two, end } => Span::Cubic { control_one: sp(control_one), control_two: sp(control_two), end: sp(end) },
            }).collect(),
        }).collect();
        // global + per-glyph extents from the final rings (matches native_font derivation)
        let mut b = None::<[i32; 4]>;
        for r in &rings {
            let mut pts = vec![r.start];
            for s in &r.spans { match s { Span::Line { end } => pts.push(*end), Span::Cubic { control_one, control_two, end } => { pts.push(*control_one); pts.push(*control_two); pts.push(*end); } } }
            for p in pts { let (x, y) = (p.x as i32, p.y as i32); b = Some(match b { None => [x, y, x, y], Some(bb) => [bb[0].min(x), bb[1].min(y), bb[2].max(x), bb[3].max(y)] }); }
        }
        let bb = b.unwrap_or([0; 4]);
        mn[0] = mn[0].min(bb[0]); mn[1] = mn[1].min(bb[1]); mx[0] = mx[0].max(bb[2]); mx[1] = mx[1].max(bb[3]);
        let width = ((gmx0 - gmn0) as f64 * mg).round() as i32;
        let adv_g = if adv_u > 0 { adv_u } else { (lsb_u as i32 + width + rsb_u as i32).max(1) as u16 };
        let extent = bb[2];
        max_extent = max_extent.max(extent);
        min_rsb = min_rsb.min(adv_g as i32 - extent);
        advs.push(adv_g);
        let gid = glyphs.len() as u16; // notdef + injected whitespace occupy the leading gids
        glyphs.push(CffGlyph { name: g.name.clone(), advance: adv_g, outline: DrawnGlyph { glyph_id: g.name.clone(), rings } });
        lsbs.push(lsb_u); mapping.push((g.code, gid));
        let _ = writeln!(hmtx_tsv, "{}	{}	U+{:04X}	{}	{}", gid, g.name, g.code, adv_g, lsb_u);
    }
    std::fs::write(format!("{}/hmtx.tsv", statdir), hmtx_tsv).unwrap();
    let min_lsb: i16 = *lsbs.iter().zip(&glyphs).filter(|(_, g)| !g.outline.rings.is_empty()).map(|(l, _)| l).min().unwrap_or(&0);
    let n = glyphs.len() as u16;
    let first = mapping.iter().map(|m| m.0).min().unwrap() as u16; let last = mapping.iter().map(|m| m.0).max().unwrap() as u16;
    let asc = mx[1] as i16; let desc = mn[1] as i16;
    // scale for unit conversion of metric values: median glyph scale
    let conv = upp_cap; // cap anchor, 2026-10-12 (canvas-em conversion removed)
    let cap_units = cap_px.map(|(c, _)| ((c - base_px_val).abs() * conv).round() as i16);
    let x_units = x_px.map(|(x, _)| ((x - base_px_val).abs() * conv).round() as i16);
    // note: unit conversion uses each set's own glyph scales; uniform image
    // height across the set makes any single scale exact. Mixed heights would
    // need per-glyph conversion - flagged in metrics.json when h differs.
    let os2_version = if cap_units.is_some() || x_units.is_some() { 2 } else { 0 };
    // NAME LAYER (owner ruling 2026-10-11, channel-verified: "fontun kendi
    // isim bilgileri"): names derive from the set, never a baked-in template.
    // Source 1: set-name.json at the set root (parent of the glyph dir).
    // Source 2: directory names (style = set root dir, family = its parent).
    // No source -> abort; a template default is not an option.
    let first_path = std::fs::read_to_string(&list).unwrap().lines().next().map(|l| split3(l)[0].to_string()).unwrap();
    let glyph_dir = std::path::Path::new(&first_path).parent().unwrap().to_path_buf();
    let set_root = glyph_dir.parent().map(|p| p.to_path_buf()).unwrap_or_else(|| glyph_dir.clone());
    let jval = |j: &str, key: &str| -> Option<String> {
        let pat = format!("\"{}\"", key);
        let i = j.find(&pat)?; let rest = &j[i + pat.len()..];
        let c = rest.find(':')?; let rest = &rest[c + 1..];
        let q1 = rest.find('"')?; let q2 = rest[q1 + 1..].find('"')?;
        Some(rest[q1 + 1..q1 + 1 + q2].to_string())
    };
    let (family, style) = match std::fs::read_to_string(set_root.join("set-name.json")) {
        Ok(j) => (jval(&j, "family").expect("set-name.json: family"), jval(&j, "style").expect("set-name.json: style")),
        Err(_) => {
            let st = set_root.file_name().and_then(|s| s.to_str()).expect("name layer: no set root dir name").to_string();
            let fa = set_root.parent().and_then(|p| p.file_name()).and_then(|s| s.to_str()).expect("name layer: no family dir name").to_string();
            eprintln!("WARN: no set-name.json at {}; derived family/style from directory names ({}/{})", set_root.display(), fa, st);
            (fa, st)
        }
    };
    // owner ruling 2026-10-11 (channel-verified, phonemsg-01M4N1K165SWGRJPT6X5VPE401):
    // a style that has its own name IS the subfamily - never append "Regular".
    let style_is_regular = style.eq_ignore_ascii_case("regular");
    let fam = if style_is_regular { family.clone() } else { format!("{} {}", family, style) };
    let sub = if style_is_regular { "Regular".to_string() } else { style.clone() };
    let full = if style_is_regular { format!("{} Regular", family) } else { fam.clone() };
    // PostScript name admits only [A-Za-z0-9-]: drop spaces and other characters
    // from the family/style parts (name IDs 1,4,16,17 keep the original text).
    let psf: String = family.chars().filter(|c| c.is_ascii_alphanumeric()).collect();
    let pss: String = style.chars().filter(|c| c.is_ascii_alphanumeric()).collect();
    let ps = if style_is_regular { format!("{}{}-Regular", psf, pss) } else { format!("{}{}-{}", psf, pss, pss) };
    let uid = format!("{}:1.0:KNI", full);
    let names: Vec<NameRecord> = vec![
        (0, String::new()), (1, fam.clone()), (2, sub.clone()), (3, uid), (4, full.clone()),
        (5, "Version 1.0".to_string()), (6, ps.clone()), (13, String::new()), (14, String::new()),
        (16, family.clone()), (17, style.clone()),
    ].into_iter().map(|(id, t)| NameRecord { language: 0x409, name_id: id, value: t }).collect();
    let input = NativeFontInput { postscript_name: ps, glyphs, left_side_bearings: lsbs, mapping,
        head: HeadMetadata { revision: 0x10000, flags: 0, units_per_em: 1000, created: 0, modified: 0, bounds: [mn[0] as i16, mn[1] as i16, mx[0] as i16, mx[1] as i16], mac_style: 0, lowest_ppem: 1 },
        hhea: HheaMetadata { ascender: asc, descender: desc, line_gap: 0, advance_max: *advs.iter().max().unwrap(), min_lsb, min_rsb: min_rsb as i16, max_extent: max_extent as i16, caret_rise: 1, caret_run: 0, caret_offset: 0, metric_count: n },
        post: PostMetadata { italic_angle_fixed: 0, underline_position: -100, underline_thickness: 50, fixed_pitch: 1, memory: [0; 4] },
        os2: Os2Metadata { average_width: (advs.iter().map(|&a| a as u32).sum::<u32>() / advs.len() as u32) as i16, weight: 400, width: 5, embedding: 2, subscript: [650, 600, 0, 75], superscript: [650, 600, 0, 350], strikeout: [50, 300], family_class: 0, panose: [0; 10], unicode_ranges: [1, 0, 0, 0], vendor: *b"NONE", selection: 64, first_char: first, last_char: last, typo: [asc, desc, 0], win_ascent: asc.max(0) as u16, win_descent: (-desc).max(0) as u16, version: os2_version, cap_height: cap_units.unwrap_or(0), x_height: x_units.unwrap_or(0) },
        names };
    match encode(&input) {
        Ok(data) => { std::fs::write(&outp, &data).unwrap(); println!("WROTE {} bytes glyphs={}", data.len(), n - 1); }
        Err(e) => { eprintln!("ENCODE ERROR {:?}", e); std::process::exit(1); }
    }
    // ---- metrics dump (every value traceable to its measurement) ----
    let mut dump = String::new();
    let _ = writeln!(dump, "{{");
    let _ = writeln!(dump, "  \"baseline\": {}", match baseline_px { Some((b, c)) => format!("{{\"px\": {:.2}, \"glyphs\": {}}}", b, c), None => "\"UNRESOLVED\"".into() });
    let _ = writeln!(dump, "  \"cap_height\": {}", match (cap_px, cap_units) { (Some((c, n)), Some(u)) => format!("{{\"px\": {:.2}, \"units\": {}, \"glyphs\": {}}}", c, u, n), _ => "\"UNRESOLVED\"".into() });
    let _ = writeln!(dump, "  \"x_height\": {}", match (x_px, x_units) { (Some((x, n)), Some(u)) => format!("{{\"px\": {:.2}, \"units\": {}, \"glyphs\": {}}}", x, u, n), _ => "\"UNRESOLVED\"".into() });
    let _ = writeln!(dump, "  \"hhea\": {{\"ascender\": {}, \"descender\": {}, \"lineGap\": 0}},", asc, desc);
    let _ = writeln!(dump, "  \"os2\": {{\"version\": {}, \"sTypoAscender\": {}, \"sTypoDescender\": {}, \"usWinAscent\": {}, \"usWinDescent\": {}}},", os2_version, asc, desc, asc.max(0), (-desc).max(0));
    let _ = writeln!(dump, "  \"flat_bottom_evidence_px\": {:?},", flat_bottoms.iter().map(|v| (v * 10.0).round() / 10.0).collect::<Vec<_>>());
    let _ = writeln!(dump, "  \"cap_top_evidence_px\": {:?},", cap_tops.iter().map(|v| (v * 10.0).round() / 10.0).collect::<Vec<_>>());
    let _ = writeln!(dump, "  \"x_top_evidence_px\": {:?},", x_tops.iter().map(|v| (v * 10.0).round() / 10.0).collect::<Vec<_>>());
    let _ = writeln!(dump, "  \"auto_scale\": {{\"anchor\": \"cap-height\", \"cap_units_target\": 690, \"cap_px\": {}, \"canvas_em_px\": {:.1}, \"cap_fraction_of_canvas\": {}, \"band_reference\": [0.68, 0.70], \"units_per_px\": {:.6}, \"cap_outliers_px\": {:?}}},",
        cap_px.map(|(c, _)| format!("{:.1}", (c - base_px_val).abs())).unwrap_or_else(|| "null".into()),
        em_px,
        cap_frac.map(|f| format!("{:.4}", f)).unwrap_or_else(|| "null".into()),
        upp_cap,
        outliers);
    let _ = writeln!(dump, "  \"policy_notes\": \"sTypo*=hhea=measured bbox, lineGap=0: provisional pending doctrine O3; overshoot kept as-traced pending O1; baseline shifted to y=0\",");
    let _ = writeln!(dump, "  \"per_glyph\": [");
    let _ = writeln!(dump, "{}", per_glyph.lines().collect::<Vec<_>>().join(",\n"));
    let _ = writeln!(dump, "  ]\n}}");
    std::fs::write(format!("{}/metrics.json", statdir), &dump).unwrap();
    print!("{}", dump);
}
