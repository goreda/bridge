//! PROPOSAL, UNBUILT. engine/core/examples/jpeg_collection_probe.rs
//! CALLER code only: per-glyph source identity + decode/capture/capture-fit coverage ledger.
//! No decoder, capture or fit edits. No pixel IoU (decoder pixel identity is by hash only).
//! Not a run authorization: a real-collection run needs its own authorization.
//!
//! Required explicit args (no defaults, missing/invalid => error, exit 2):
//!   --manifest FILE  --expected-ids FILE  --root DIR  --out FILE  --pins FILE
//!   --max-input-bytes N --max-pixels N --max-working-bytes N   (decode_source Limits)
//!   --rdp-eps F  --fit-scale F(>0)  --fit-squared-error F  --fit-max-refits N
//!   --calibration-status LABEL   (e.g. diagnostic_uncalibrated | declared:<text>; echoed, never inferred)
//! Manifest: TSV, header + exactly-N-cell rows. Required columns: glyph_id, path, sha256, size.
//!   path must be relative, no '..', unique; resolved (canonical) input must stay inside canonical --root.
//!   sha256/size are the manifest's EXPECTED identity; a mismatch refuses the row (no decode).
//!   Blank lines, header-only manifests, extra/short cells are typed errors.
//! --expected-ids: one glyph_id per line, the full expected set (e.g. all 62). Manifest ids must equal it
//!   exactly (no guessed glyph/codepoint mapping here).
//! --pins FILE: TSV name<TAB>value lines naming source/base/dependency/overlay pins; echoed with its sha256.
//! Output is created with create_new (never overwrites) and must not alias any input.
//! Every manifest row is in the denominator (success-only filtering is not done).
//! Output ledger: one TSV row per glyph (all fields on one row) plus a '#summary' block.
//!
//! Needs on the hub side: `pub mod jpeg_source; pub mod capture_dispatch;` in lib.rs overlay
//! (the lib.rs in goreda/kni main does not list them), crate name kni_core.

use kni_core::capture::{capture_gray, MeasuredContour};
use kni_core::capture_dispatch::{decode_source, DispatchError, SourceKind};
use kni_core::capture_fit::fit_captured;
use kni_core::cubic_fit::FitPolicy;
use kni_core::jpeg_source::Limits;
use kni_core::reference_slice::Span;
use std::collections::BTreeMap;
use std::panic::{catch_unwind, AssertUnwindSafe};

// ---------- typed errors ----------
#[derive(Debug)]
enum ProbeError {
    Arg(String),
    Manifest(ManifestError),
    Io(String),
}
#[derive(Debug)]
enum ManifestError {
    Empty,
    ZeroRows,
    BlankRow { line: usize },
    PathNotRelative { line: usize },
    DuplicatePath { line: usize, path: String },
    BadSha { line: usize },
    BadSize { line: usize },
    ExpectedSetMismatch { missing: Vec<String>, unexpected: Vec<String> },
    MissingColumn(&'static str),
    DuplicateColumn(String),
    RowLen { line: usize, have: usize, need: usize },
    EmptyField { line: usize, column: &'static str },
    DuplicateGlyphId { line: usize, id: String },
}
impl From<ManifestError> for ProbeError { fn from(e: ManifestError) -> Self { ProbeError::Manifest(e) } }

impl std::fmt::Display for ManifestError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ManifestError::Empty => write!(f, "manifest is empty"),
            ManifestError::ZeroRows => write!(f, "manifest has zero rows"),
            ManifestError::BlankRow { line } => write!(f, "manifest row {line} is blank"),
            ManifestError::PathNotRelative { line } => write!(f, "manifest row {line} path is not relative"),
            ManifestError::DuplicatePath { line, path } => write!(f, "manifest row {line} duplicates path {path}"),
            ManifestError::BadSha { line } => write!(f, "manifest row {line} has a malformed sha256"),
            ManifestError::BadSize { line } => write!(f, "manifest row {line} has a malformed size"),
            ManifestError::ExpectedSetMismatch { missing, unexpected } => write!(f, "expected glyph set mismatch: {} missing, {} unexpected", missing.len(), unexpected.len()),
            ManifestError::MissingColumn(c) => write!(f, "manifest misses column {c}"),
            ManifestError::DuplicateColumn(c) => write!(f, "manifest duplicates column {c}"),
            ManifestError::RowLen { line, have, need } => write!(f, "manifest row {line} has {have} fields, needs {need}"),
            ManifestError::EmptyField { line, column } => write!(f, "manifest row {line} has an empty {column}"),
            ManifestError::DuplicateGlyphId { line, id } => write!(f, "manifest row {line} duplicates glyph id {id}"),
        }
    }
}
impl std::fmt::Display for ProbeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ProbeError::Arg(m) => write!(f, "argument error: {m}"),
            ProbeError::Manifest(e) => write!(f, "manifest error: {e}"),
            ProbeError::Io(m) => write!(f, "io error: {m}"),
        }
    }
}

// ---------- SHA-256 (self-contained; the decoder's sha256_hex is private) ----------
fn sha256_hex(data: &[u8]) -> String {
    const K: [u32; 64] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    let mut h: [u32; 8] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    let mut msg = data.to_vec();
    let bitlen = (data.len() as u64).wrapping_mul(8);
    msg.push(0x80);
    while msg.len() % 64 != 56 { msg.push(0); }
    msg.extend_from_slice(&bitlen.to_be_bytes());
    for chunk in msg.chunks(64) {
        let mut w = [0u32; 64];
        for i in 0..16 { w[i] = u32::from_be_bytes([chunk[4*i], chunk[4*i+1], chunk[4*i+2], chunk[4*i+3]]); }
        for i in 16..64 {
            let s0 = w[i-15].rotate_right(7) ^ w[i-15].rotate_right(18) ^ (w[i-15] >> 3);
            let s1 = w[i-2].rotate_right(17) ^ w[i-2].rotate_right(19) ^ (w[i-2] >> 10);
            w[i] = w[i-16].wrapping_add(s0).wrapping_add(w[i-7]).wrapping_add(s1);
        }
        let mut v = h;
        for i in 0..64 {
            let s1 = v[4].rotate_right(6) ^ v[4].rotate_right(11) ^ v[4].rotate_right(25);
            let ch = (v[4] & v[5]) ^ ((!v[4]) & v[6]);
            let t1 = v[7].wrapping_add(s1).wrapping_add(ch).wrapping_add(K[i]).wrapping_add(w[i]);
            let s0 = v[0].rotate_right(2) ^ v[0].rotate_right(13) ^ v[0].rotate_right(22);
            let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
            let t2 = s0.wrapping_add(maj);
            v[7] = v[6]; v[6] = v[5]; v[5] = v[4]; v[4] = v[3].wrapping_add(t1);
            v[3] = v[2]; v[2] = v[1]; v[1] = v[0]; v[0] = t1.wrapping_add(t2);
        }
        for i in 0..8 { h[i] = h[i].wrapping_add(v[i]); }
    }
    h.iter().map(|x| format!("{:08x}", x)).collect()
}

// ---------- args ----------
struct Args {
    manifest: String, expected_ids: String, pins: String, calibration: String, root: String, out: String,
    limits: Limits, rdp_eps: f64, fit_scale: f64, fit_sq_err: f64, fit_refits: usize,
}
fn parse_args() -> Result<Args, ProbeError> {
    let mut m: BTreeMap<String, String> = BTreeMap::new();
    let v: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < v.len() {
        let k = v[i].strip_prefix("--").ok_or_else(|| ProbeError::Arg(format!("unexpected argument {}", v[i])))?;
        let val = v.get(i + 1).ok_or_else(|| ProbeError::Arg(format!("--{} needs a value", k)))?;
        if m.insert(k.to_string(), val.clone()).is_some() { return Err(ProbeError::Arg(format!("--{} given twice", k))); }
        i += 2;
    }
    let take = |m: &mut BTreeMap<String, String>, k: &str| m.remove(k).ok_or_else(|| ProbeError::Arg(format!("missing required --{}", k)));
    let usz = |s: String, k: &str| s.parse::<usize>().map_err(|_| ProbeError::Arg(format!("--{} not an unsigned integer", k)));
    let flt = |s: String, k: &str| s.parse::<f64>().ok().filter(|x| x.is_finite() && *x >= 0.0).ok_or_else(|| ProbeError::Arg(format!("--{} not a finite non-negative number", k)));
    let a = Args {
        manifest: take(&mut m, "manifest")?, expected_ids: take(&mut m, "expected-ids")?, pins: take(&mut m, "pins")?,
        calibration: take(&mut m, "calibration-status")?, root: take(&mut m, "root")?, out: take(&mut m, "out")?,
        limits: Limits {
            max_input_bytes: usz(take(&mut m, "max-input-bytes")?, "max-input-bytes")?,
            max_pixels: usz(take(&mut m, "max-pixels")?, "max-pixels")?,
            max_working_bytes: usz(take(&mut m, "max-working-bytes")?, "max-working-bytes")?,
        },
        rdp_eps: flt(take(&mut m, "rdp-eps")?, "rdp-eps")?,
        fit_scale: flt(take(&mut m, "fit-scale")?, "fit-scale")?,
        fit_sq_err: flt(take(&mut m, "fit-squared-error")?, "fit-squared-error")?,
        fit_refits: usz(take(&mut m, "fit-max-refits")?, "fit-max-refits")?,
    };
    if a.fit_scale <= 0.0 { return Err(ProbeError::Arg("--fit-scale must be > 0".into())); }
    if a.calibration.trim().is_empty() { return Err(ProbeError::Arg("--calibration-status must be non-empty".into())); }
    if let Some(k) = m.keys().next() { return Err(ProbeError::Arg(format!("unknown argument --{}", k))); }
    Ok(a)
}

// ---------- manifest ----------
struct Row { glyph_id: String, path: String, sha256: String, size: u64 }
fn rel_path_ok(p: &str) -> bool {
    use std::path::{Component, Path};
    let pp = Path::new(p);
    !p.is_empty() && !pp.is_absolute() && pp.components().all(|c| matches!(c, Component::Normal(_)))
}
fn parse_manifest(text: &str) -> Result<Vec<Row>, ManifestError> {
    let mut it = text.lines().enumerate();
    let (_, header) = it.next().ok_or(ManifestError::Empty)?;
    if header.trim().is_empty() { return Err(ManifestError::Empty); }
    let cols: Vec<&str> = header.trim_end_matches('\r').split('\t').collect();
    for (i, c) in cols.iter().enumerate() { if cols[..i].contains(c) { return Err(ManifestError::DuplicateColumn(c.to_string())); } }
    let ix = |n: &'static str| cols.iter().position(|c| *c == n).ok_or(ManifestError::MissingColumn(n));
    let (gi, pi, hi, si) = (ix("glyph_id")?, ix("path")?, ix("sha256")?, ix("size")?);
    let need = cols.len();
    let mut rows: Vec<Row> = Vec::new();
    for (n, l) in it {
        let ln = n + 1;
        if l.trim().is_empty() { return Err(ManifestError::BlankRow { line: ln }); }
        let f: Vec<&str> = l.trim_end_matches('\r').split('\t').collect();
        if f.len() != need { return Err(ManifestError::RowLen { line: ln, have: f.len(), need }); }
        if f[gi].is_empty() { return Err(ManifestError::EmptyField { line: ln, column: "glyph_id" }); }
        if !rel_path_ok(f[pi]) { return Err(ManifestError::PathNotRelative { line: ln }); }
        if f[hi].len() != 64 || !f[hi].bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)) { return Err(ManifestError::BadSha { line: ln }); }
        let size = f[si].parse::<u64>().map_err(|_| ManifestError::BadSize { line: ln })?;
        if rows.iter().any(|r| r.glyph_id == f[gi]) { return Err(ManifestError::DuplicateGlyphId { line: ln, id: f[gi].to_string() }); }
        if rows.iter().any(|r| r.path == f[pi]) { return Err(ManifestError::DuplicatePath { line: ln, path: f[pi].to_string() }); }
        rows.push(Row { glyph_id: f[gi].to_string(), path: f[pi].to_string(), sha256: f[hi].to_string(), size });
    }
    if rows.is_empty() { return Err(ManifestError::ZeroRows); }
    Ok(rows)
}
fn check_expected(rows: &[Row], expected_text: &str) -> Result<(), ManifestError> {
    let exp: Vec<&str> = expected_text.lines().map(|l| l.trim_end_matches('\r')).collect();
    let mut missing: Vec<String> = exp.iter().filter(|e| !rows.iter().any(|r| r.glyph_id == **e)).map(|s| s.to_string()).collect();
    let unexpected: Vec<String> = rows.iter().filter(|r| !exp.contains(&r.glyph_id.as_str())).map(|r| r.glyph_id.clone()).collect();
    let mut seen = Vec::new();
    for e in &exp { if e.is_empty() || seen.contains(e) { missing.push(format!("<bad expected line: {:?}>", e)); } seen.push(*e); }
    if missing.is_empty() && unexpected.is_empty() { Ok(()) } else { Err(ManifestError::ExpectedSetMismatch { missing, unexpected }) }
}

// ---------- ledger row ----------
#[derive(Default)]
struct Ledger {
    glyph_id: String, path: String,
    source_sha256: String, source_len: String,
    encoding: String,                // png | jpeg | unknown | unread
    width: String, height: String,
    decoder_status: String,          // ok | unsupported:<code> | malformed:<code> | limit:<code> | signature | png_error | read_error
    capture_status: String,          // ok | error:<msg> | not_attempted
    capturefit_status: String,       // ok | panic | not_attempted
    gray_len_ok: String,             // yes | NO | n/a
    gray_sha256: String,             // caller's hash of the decoded gray bytes
    receipt_check: String,           // jpeg: match | MISMATCH:<field> ; png: n/a_png_own_mode
    rings: String, hole_rings: String, spans: String, line_spans: String, cubic_spans: String, emitted_span_end_count: String,
    closure_status: String, fit_count: String, fit_fallback: String, fit_dropped: String, fit_flag: String, expected_identity: String,
}
const NA: &str = "-";
fn clean(s: &str) -> String { s.replace(['\t', '\n', '\r'], " ") }
fn fill_na(l: &mut Ledger) {
    for f in [&mut l.source_sha256, &mut l.source_len, &mut l.encoding, &mut l.width, &mut l.height, &mut l.decoder_status,
        &mut l.capture_status, &mut l.capturefit_status, &mut l.gray_len_ok, &mut l.gray_sha256, &mut l.receipt_check,
        &mut l.rings, &mut l.hole_rings, &mut l.spans, &mut l.line_spans, &mut l.cubic_spans, &mut l.emitted_span_end_count,
        &mut l.closure_status, &mut l.fit_count, &mut l.fit_fallback, &mut l.fit_dropped, &mut l.fit_flag, &mut l.expected_identity] { if f.is_empty() { *f = NA.to_string(); } }
}
const HEADER: &str = "glyph_id\tpath\tsource_sha256\tsource_len\tencoding\twidth\theight\tdecoder_status\tcapture_status\tcapturefit_status\tgray_len_eq_wh\tgray_sha256\treceipt_check\trings\thole_rings\tspans\tline_spans\tcubic_spans\temitted_span_end_count\tclosure_status\tfit_count\tfit_fallback\tfit_dropped\tfit_flag\texpected_identity";
fn line(l: &Ledger) -> String {
    [&l.glyph_id, &l.path, &l.source_sha256, &l.source_len, &l.encoding, &l.width, &l.height, &l.decoder_status, &l.capture_status,
     &l.capturefit_status, &l.gray_len_ok, &l.gray_sha256, &l.receipt_check, &l.rings, &l.hole_rings, &l.spans, &l.line_spans,
     &l.cubic_spans, &l.emitted_span_end_count, &l.closure_status, &l.fit_count, &l.fit_fallback, &l.fit_dropped, &l.fit_flag, &l.expected_identity]
        .iter().map(|s| clean(s)).collect::<Vec<_>>().join("\t")
}

fn not_attempted(l: &mut Ledger) { l.capture_status = "not_attempted".into(); l.capturefit_status = "not_attempted".into(); }
fn probe_one(a: &Args, canon_root: &std::path::Path, row: &Row) -> Ledger {
    use std::io::Read;
    let mut l = Ledger { glyph_id: row.glyph_id.clone(), path: row.path.clone(), ..Default::default() };
    l.encoding = "unread".into();
    // resolved input must stay inside canonical root (symlink / .. escape refused)
    let full = match std::fs::canonicalize(canon_root.join(&row.path)) {
        Ok(p) if p.starts_with(canon_root) => p,
        Ok(_) => { l.decoder_status = "path_escape_refused".into(); not_attempted(&mut l); fill_na(&mut l); return l; }
        Err(e) => { l.decoder_status = format!("read_error:{:?}", e.kind()); not_attempted(&mut l); fill_na(&mut l); return l; }
    };
    // metadata preflight against the explicit input limit BEFORE allocating
    let file = match std::fs::File::open(&full) { Ok(f) => f, Err(e) => { l.decoder_status = format!("read_error:{:?}", e.kind()); not_attempted(&mut l); fill_na(&mut l); return l; } };
    let meta_len = match file.metadata() { Ok(m) if m.is_file() => m.len(), _ => { l.decoder_status = "read_error:not_a_regular_file".into(); not_attempted(&mut l); fill_na(&mut l); return l; } };
    l.source_len = meta_len.to_string();
    l.expected_identity = format!("size={} sha256={}", row.size, row.sha256);
    if meta_len != row.size { l.decoder_status = "source_identity_refused:size".into(); not_attempted(&mut l); fill_na(&mut l); return l; }
    if meta_len > a.limits.max_input_bytes as u64 { l.decoder_status = "limit:input_over_max_input_bytes_before_read".into(); not_attempted(&mut l); fill_na(&mut l); return l; }
    // bounded read (one byte over the stated size detects growth); snapshot must equal metadata length
    let mut bytes: Vec<u8> = Vec::new();
    if bytes.try_reserve_exact(meta_len as usize).is_err() { l.decoder_status = "limit:allocation_failed".into(); not_attempted(&mut l); fill_na(&mut l); return l; }
    if let Err(e) = file.take(meta_len + 1).read_to_end(&mut bytes) { l.decoder_status = format!("read_error:{:?}", e.kind()); not_attempted(&mut l); fill_na(&mut l); return l; }
    if bytes.len() as u64 != meta_len { l.decoder_status = "source_unstable_during_read".into(); not_attempted(&mut l); fill_na(&mut l); return l; }
    l.source_sha256 = sha256_hex(&bytes);
    l.encoding = if bytes.starts_with(b"\x89PNG\r\n\x1a\n") { "png" } else if bytes.starts_with(&[255, 216]) { "jpeg" } else { "unknown" }.into();
    if l.source_sha256 != row.sha256 { l.decoder_status = "source_identity_refused:sha256".into(); not_attempted(&mut l); fill_na(&mut l); return l; }

    let decoded = match catch_unwind(AssertUnwindSafe(|| decode_source(&bytes, &kni_core::capture::DecodeLimits{max_input_bytes:a.limits.max_input_bytes,max_pixels:a.limits.max_pixels,max_working_bytes:a.limits.max_working_bytes}, a.limits))) {
        Err(_) => { l.decoder_status = "decode_panic".into(); not_attempted(&mut l); fill_na(&mut l); return l; }
        Ok(Ok(d)) => d,
        Ok(Err(e)) => {
            l.decoder_status = match e {
                DispatchError::UnsupportedSignature => "signature".to_string(),
                DispatchError::Jpeg(j) => {
                    let c = j.code();
                    let g = if c.starts_with("unsupported_") { "unsupported" } else if c == "resource_limit" || c == "allocation_failed" { "limit" } else { "malformed" };
                    format!("{}:{}", g, c)
                }
                DispatchError::Capture(m) => format!("png_error:{}", m),
            };
            not_attempted(&mut l); fill_na(&mut l); return l;
        }
    };
    l.width = decoded.width.to_string(); l.height = decoded.height.to_string();
    l.gray_sha256 = sha256_hex(&decoded.gray);
    // pixel coverage: graylen == w*h (checked multiplication); invalid => typed refusal, no downstream
    l.gray_len_ok = match decoded.width.checked_mul(decoded.height) { Some(n) if n == decoded.gray.len() => "yes", _ => "NO" }.into();
    if l.gray_len_ok != "yes" { l.decoder_status = "gray_len_invalid".into(); not_attempted(&mut l); fill_na(&mut l); return l; }
    // receipt identity: jpeg raw-Y hash must equal the caller's hash (internal consistency, NOT an independent pixel oracle)
    l.receipt_check = match (&decoded.receipt.source_kind, &decoded.receipt.jpeg_identity) {
        (SourceKind::JpegRawY, Some(r)) => {
            if r.decoded_gray_sha256 != l.gray_sha256 { "MISMATCH:gray_sha256".into() }
            else if r.orig_sha256 != l.source_sha256 { "MISMATCH:orig_sha256".into() }
            else if r.w != decoded.width || r.h != decoded.height || r.stride != decoded.width { "MISMATCH:dims_or_stride".into() }
            else if r.orig_len != bytes.len() { "MISMATCH:orig_len".into() }
            else { "match".to_string() }
        }
        (SourceKind::JpegRawY, None) => "MISMATCH:receipt_missing".into(),
        (SourceKind::PngConvertedGrayWhiteAlpha, _) => "n/a_png_own_mode".into(),
    };
    if l.receipt_check.starts_with("MISMATCH") {
        l.decoder_status = format!("identity_refused:{}", &l.receipt_check["MISMATCH:".len()..]);
        not_attempted(&mut l); fill_na(&mut l); return l;
    }
    l.decoder_status = "ok".into();

    let contour: MeasuredContour = match catch_unwind(AssertUnwindSafe(|| capture_gray(decoded.width, decoded.height, &decoded.gray, a.rdp_eps))) {
        Ok(Ok(c)) => { l.capture_status = "ok".into(); c }
        Ok(Err(m)) => { l.capture_status = format!("error:{}", m); l.capturefit_status = "not_attempted".into(); fill_na(&mut l); return l; }
        Err(_) => { l.capture_status = "panic".into(); l.capturefit_status = "not_attempted".into(); fill_na(&mut l); return l; }
    };
    l.rings = contour.rings.len().to_string();
    l.hole_rings = contour.rings.iter().filter(|r| r.hole).count().to_string();
    let policy = FitPolicy { squared_error: a.fit_sq_err, max_refits: a.fit_refits };
    match catch_unwind(AssertUnwindSafe(|| fit_captured(&contour.rings, a.fit_scale, &policy))) {
        Ok((fitted, count, fallback, dropped)) => {
            l.capturefit_status = "ok".into();
            let (mut lines, mut cubics, mut open_rings) = (0usize, 0usize, 0usize);
            for r in &fitted {
                let mut last = r.start;
                for s in &r.spans { match s { Span::Line { end } => { lines += 1; last = *end; } Span::Cubic { end, .. } => { cubics += 1; last = *end; } } }
                // exact endpoint closure only; nesting/orientation are NOT verified here
                if r.spans.is_empty() || last.x != r.start.x || last.y != r.start.y { open_rings += 1; }
            }
            l.line_spans = lines.to_string(); l.cubic_spans = cubics.to_string();
            l.spans = (lines + cubics).to_string();
            l.emitted_span_end_count = (lines + cubics).to_string(); // a count of span ends, not a native closed-node claim
            l.closure_status = if open_rings == 0 { "endpoints_closed_all".to_string() } else { format!("endpoint_open_rings={}", open_rings) };
            l.fit_count = count.to_string(); l.fit_fallback = fallback.to_string(); l.fit_dropped = dropped.to_string();
            l.fit_flag = if !fallback && dropped == 0 && open_rings == 0 { "clean" } else { "FLAGGED" }.into();
        }
        Err(_) => { l.capturefit_status = "panic".into(); }
    }
    fill_na(&mut l);
    l
}

fn preflight_out(a: &Args, inputs: &[&str]) -> Result<std::path::PathBuf, ProbeError> {
    let out = std::path::Path::new(&a.out);
    if out.exists() { return Err(ProbeError::Io("--out already exists (no overwrite)".into())); }
    let parent = out.parent().filter(|p| !p.as_os_str().is_empty()).unwrap_or(std::path::Path::new("."));
    let parent = std::fs::canonicalize(parent).map_err(|e| ProbeError::Io(format!("out parent: {}", e)))?;
    let name = out.file_name().ok_or_else(|| ProbeError::Io("--out has no file name".into()))?;
    let target = parent.join(name);
    for i in inputs { if let Ok(c) = std::fs::canonicalize(i) { if c == target { return Err(ProbeError::Io(format!("--out aliases input {}", i))); } } }
    let root = std::fs::canonicalize(&a.root).map_err(|e| ProbeError::Io(format!("root: {}", e)))?;
    if target.starts_with(&root) { return Err(ProbeError::Io("--out must be outside --root".into())); }
    Ok(target)
}

fn run() -> Result<(), ProbeError> {
    use std::io::Write;
    let a = parse_args()?;
    let rd = |p: &str, what: &str| std::fs::read(p).map_err(|e| ProbeError::Io(format!("{}: {}", what, e)));
    let manifest_bytes = rd(&a.manifest, "manifest")?;
    let expected_bytes = rd(&a.expected_ids, "expected-ids")?;
    let pins_bytes = rd(&a.pins, "pins")?;
    let as_text = |b: &Vec<u8>, w: &str| String::from_utf8(b.clone()).map_err(|_| ProbeError::Io(format!("{} not UTF-8", w)));
    let rows = parse_manifest(&as_text(&manifest_bytes, "manifest")?)?;
    check_expected(&rows, &as_text(&expected_bytes, "expected-ids")?)?;
    let pins_text = as_text(&pins_bytes, "pins")?;
    let target = preflight_out(&a, &[&a.manifest, &a.expected_ids, &a.pins])?;
    let canon_root = std::fs::canonicalize(&a.root).map_err(|e| ProbeError::Io(format!("root: {}", e)))?;
    let ledgers: Vec<Ledger> = rows.iter().map(|r| probe_one(&a, &canon_root, r)).collect();

    let mut out = String::new();
    out.push_str(HEADER); out.push('\n');
    for l in &ledgers { out.push_str(&line(l)); out.push('\n'); }
    // summary: denominator is every manifest row
    let by = |f: &dyn Fn(&Ledger) -> String| { let mut m: BTreeMap<String, usize> = BTreeMap::new(); for l in &ledgers { *m.entry(f(l)).or_insert(0) += 1; } m };
    out.push_str(&format!("#summary\tmanifest_rows\t{}\n", rows.len()));
    for (name, m) in [
        ("encoding", by(&|l| l.encoding.clone())),
        ("decoder_status", by(&|l| l.decoder_status.clone())),
        ("capture_status", by(&|l| l.capture_status.clone())),
        ("capturefit_status", by(&|l| l.capturefit_status.clone())),
        ("fit_flag", by(&|l| l.fit_flag.clone())),
        ("closure_status", by(&|l| l.closure_status.clone())),
        ("gray_len_eq_wh", by(&|l| l.gray_len_ok.clone())),
        ("receipt_check", by(&|l| l.receipt_check.clone())),
    ] { for (k, n) in m { out.push_str(&format!("#summary\t{}\t{}\t{}\n", name, k, n)); } }
    let exe_sha = std::env::current_exe().ok().and_then(|p| std::fs::read(p).ok()).map(|b| sha256_hex(&b)).unwrap_or_else(|| "unavailable".into());
    out.push_str(&format!("#summary\tpin\tmanifest_sha256\t{}\n", sha256_hex(&manifest_bytes)));
    out.push_str(&format!("#summary\tpin\texpected_ids_sha256\t{}\n", sha256_hex(&expected_bytes)));
    out.push_str(&format!("#summary\tpin\tpins_file_sha256\t{}\n", sha256_hex(&pins_bytes)));
    out.push_str(&format!("#summary\tpin\tprobe_binary_sha256\t{}\n", exe_sha));
    out.push_str("#summary\tpin\tbuild_claim\tnone: binary hash is of the running executable; host build from source is not asserted\n");
    for p in pins_text.lines().filter(|l| !l.trim().is_empty()) { out.push_str(&format!("#summary\tdeclared_pin\t{}\n", clean(p))); }
    out.push_str(&format!("#summary\tcalibration_status\t{}\n", clean(&a.calibration)));
    out.push_str("#summary\tcalibration_note\tfit_scale is a caller-declared diagnostic input, not production calibration; no frame K/baseline/origin binding is made here\n");
    out.push_str("#summary\tlimits_semantics\tmax_input_bytes: metadata preflight and bounded read before any decode; max_pixels/max_working_bytes: passed to decode_source, enforced by the decoder (JPEG) and by the bounded PNG decoder (DecodeLimits mirroring the same values)\n");
    out.push_str("#summary\tgray_hash_note\tdecoder receipt consistency check only, not an independent pixel oracle\n");
    out.push_str(&format!("#summary\tpolicy\tmax_input_bytes={} max_pixels={} max_working_bytes={} rdp_eps={} fit_scale={} fit_squared_error={} fit_max_refits={}\n",
        a.limits.max_input_bytes, a.limits.max_pixels, a.limits.max_working_bytes, a.rdp_eps, a.fit_scale, a.fit_sq_err, a.fit_refits));
    let mut f = std::fs::OpenOptions::new().write(true).create_new(true).open(&target).map_err(|e| ProbeError::Io(format!("out: {}", e)))?;
    f.write_all(out.as_bytes()).map_err(|e| ProbeError::Io(format!("out write: {}", e)))?;
    Ok(())
}

fn main() {
    if let Err(e) = run() { eprintln!("jpeg_collection_probe: {:?}", e); std::process::exit(2); }
}

#[cfg(test)]
mod tests {
    use super::*;
    const H: &str = "glyph_id\tpath\tsha256\tsize\n";
    const S: &str = "0000000000000000000000000000000000000000000000000000000000000000";
    fn row(id: &str, p: &str) -> String { format!("{}\t{}\t{}\t10\n", id, p, S) }
    #[test] fn sha_empty() { assert_eq!(sha256_hex(b""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"); }
    #[test] fn sha_abc() { assert_eq!(sha256_hex(b"abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"); }
    #[test] fn sha_multiblock() { assert_eq!(sha256_hex(&[b'a'; 1000]), "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"); }
    #[test] fn manifest_missing_column() { assert!(matches!(parse_manifest(&format!("glyph_id\tfile\tsha256\tsize\nA\tx\t{}\t1\n", S)), Err(ManifestError::MissingColumn("path")))); }
    #[test] fn manifest_missing_sha_col() { assert!(matches!(parse_manifest("glyph_id\tpath\tsize\nA\tx\t1\n"), Err(ManifestError::MissingColumn("sha256")))); }
    #[test] fn manifest_row_len_exact() { assert!(matches!(parse_manifest(&format!("{}A\tx\t{}\t1\textra\n", H, S)), Err(ManifestError::RowLen { .. }))); assert!(matches!(parse_manifest(&format!("{}A\n", H)), Err(ManifestError::RowLen { .. }))); }
    #[test] fn manifest_dup_id_and_path() {
        assert!(matches!(parse_manifest(&format!("{}{}{}", H, row("A", "x"), row("A", "y"))), Err(ManifestError::DuplicateGlyphId { .. })));
        assert!(matches!(parse_manifest(&format!("{}{}{}", H, row("A", "x"), row("B", "x"))), Err(ManifestError::DuplicatePath { .. })));
    }
    #[test] fn manifest_empty_header_only_blank() {
        assert!(matches!(parse_manifest(""), Err(ManifestError::Empty)));
        assert!(matches!(parse_manifest(H), Err(ManifestError::ZeroRows)));
        assert!(matches!(parse_manifest(&format!("{}{}\n{}", H, row("A", "x"), row("B", "y"))), Err(ManifestError::BlankRow { .. })));
    }
    #[test] fn manifest_path_contract() {
        for bad in ["/abs/x.jpg", "../x.jpg", "a/../x.jpg", "./x.jpg", ""] { assert!(!rel_path_ok(bad), "{}", bad); }
        assert!(rel_path_ok("dir/x.jpg"));
        assert!(matches!(parse_manifest(&format!("{}{}", H, row("A", "../x"))), Err(ManifestError::PathNotRelative { .. })));
    }
    #[test] fn manifest_bad_sha_size() {
        assert!(matches!(parse_manifest("glyph_id\tpath\tsha256\tsize\nA\tx\tZZ\t1\n"), Err(ManifestError::BadSha { .. })));
        assert!(matches!(parse_manifest(&format!("glyph_id\tpath\tsha256\tsize\nA\tx\t{}\t-1\n", S)), Err(ManifestError::BadSize { .. })));
    }
    #[test] fn manifest_ok_extra_cols_in_header() { let r = parse_manifest(&format!("w\tglyph_id\tpath\tsha256\tsize\n1\tA\tx.jpg\t{}\t7\n", S)).unwrap(); assert_eq!((r[0].glyph_id.as_str(), r[0].path.as_str(), r[0].size), ("A", "x.jpg", 7)); }
    #[test] fn expected_set_exact() {
        let rows = parse_manifest(&format!("{}{}{}", H, row("A", "x"), row("B", "y"))).unwrap();
        assert!(check_expected(&rows, "A\nB\n").is_ok());
        assert!(matches!(check_expected(&rows, "A\nB\nC\n"), Err(ManifestError::ExpectedSetMismatch { .. })));
        assert!(matches!(check_expected(&rows, "A\n"), Err(ManifestError::ExpectedSetMismatch { .. })));
    }
}
