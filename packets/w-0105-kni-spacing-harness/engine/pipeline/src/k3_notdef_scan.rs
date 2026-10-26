//! K3 .notdef scan call-site (v4, gray) - advisory reconcile over the real
//! decoded glyph population.
//!
//! Add-only. The engine's existing .notdef delivery path
//! (resolve_notdef_or_ignore -> DetectionState -> assembly) is untouched:
//! this module only READS glyph sources, classifies them with
//! kni_pipeline::notdef_wiring::classify_tiles, and appends receipt rows.
//! No state is mutated (DetectionState arrives by shared reference), no
//! glyph is skipped, and a failed tile is a receipt row, never a run
//! failure (owner rule: a notdef problem never stops output).
//!
//! Semantics mapping (chief acceptance): a scan `Candidate` is the same
//! advisory tier as the engine's `CandidateProxy` state - identity
//! unverified, nothing dropped; a scan `ambiguous` tie surfaces like the
//! engine's Ambiguous* states; both are receipt-visible only, so the
//! existing .notdef delivery is byte-identical with or without this call.
//! The reconcile row reports agree/disagree against CandidateProxy
//! candidate_cps by sorted codepoint set.
//!
//! Data contract (K1 hasher contract, chief 15:20): the only public
//! decoded surface is the gray raster + (w, h); capture composites alpha
//! to white upstream, so a formerly transparent pixel reads as background.
//! CmapEvidence is honestly `known: false` at the tile stage - the
//! collection is source images and there is no shipped OTF cmap to
//! confirm against - so a repeated form stays `Candidate`, never dropped.
//!
//! BlankRule is derived per run, never a hidden constant: pooled Otsu
//! split over every decoded pixel + border-majority polarity (precedent:
//! pair_visual_read), background_threshold = background-class mean - 4
//! clamped to the background half. A degenerate population (fewer than
//! two distinct values, or no decodable borders) falls back to
//! BlankRule::default() and the derivation row says so.

use std::collections::HashSet;

use kni_core::capture_dispatch::{decode_source, DecodedSource};
use kni_core::jpeg_source::Limits;
use crate::notdef_wiring::{
    classify_tiles, BlankRule, Class, CmapEvidence, FnvHasher, ScanReport, Tile,
};

use crate::bound_detector_validator::{
    self as validator, CoreBoundedDecoder, DetectionState, EvidenceBinding, PixelNotdefKind,
    ValidationLimits,
};
use crate::run_config::RunConfig;
use crate::{notdef_producer, read_source_bounded, scale_wiring, GlyphRow, Manifest, PNG_DECODE_LIMITS};
use kni_core::cff_reader::sha256_hex;
use std::collections::BTreeMap;
use std::path::PathBuf;

/// Hasher swap point: FnvHasher today. PC-K1's EngineTileHasher does not
/// exist in the tree (0 hits); when the K1 author lands it (placement is
/// the chief's call), the swap is this one turbofish.
fn classify_population(tiles: &[Tile], ev: &CmapEvidence, rule: &BlankRule) -> ScanReport {
    classify_tiles::<FnvHasher>(tiles, ev, rule)
}

/// Pooled Otsu split: returns (split t, mean of values <= t, mean > t).
/// None when the population is empty or single-valued.
fn otsu_split(hist: &[u64; 256]) -> Option<(u8, f64, f64)> {
    let total: u64 = hist.iter().sum();
    if total == 0 || hist.iter().filter(|&&c| c > 0).count() < 2 {
        return None;
    }
    let sum_all: f64 = hist.iter().enumerate().map(|(i, &c)| i as f64 * c as f64).sum();
    let (mut w_b, mut sum_b) = (0u64, 0f64);
    let mut best: Option<(f64, u8, f64, f64)> = None;
    for t in 0..255usize {
        w_b += hist[t];
        sum_b += t as f64 * hist[t] as f64;
        let w_f = total - w_b;
        if w_b == 0 || w_f == 0 {
            continue;
        }
        let m_b = sum_b / w_b as f64;
        let m_f = (sum_all - sum_b) / w_f as f64;
        let between = w_b as f64 * w_f as f64 * (m_b - m_f) * (m_b - m_f);
        if best.map_or(true, |(b, _, _, _)| between > b) {
            best = Some((between, t as u8, m_b, m_f));
        }
    }
    best.map(|(_, t, m_dark, m_light)| (t, m_dark, m_light))
}

/// Per-run blank rule: pooled Otsu + border-majority polarity.
fn derive_blank_rule(decoded: &[DecodedSource]) -> (BlankRule, &'static str) {
    let mut hist = [0u64; 256];
    let (mut border_sum, mut border_n) = (0f64, 0u64);
    for d in decoded {
        for &v in &d.gray {
            hist[v as usize] += 1;
        }
        if d.width == 0 || d.height == 0 {
            continue;
        }
        let (w, h) = (d.width, d.height);
        for x in 0..w {
            border_sum += d.gray[x] as f64 + d.gray[(h - 1) * w + x] as f64;
            border_n += 2;
        }
        for y in 1..h.saturating_sub(1) {
            border_sum += d.gray[y * w] as f64 + d.gray[y * w + w - 1] as f64;
            border_n += 2;
        }
    }
    let split = match otsu_split(&hist) {
        Some(s) => s,
        None => return (BlankRule::default(), "default-degenerate"),
    };
    if border_n == 0 {
        return (BlankRule::default(), "default-degenerate");
    }
    let (split_t, m_dark, m_light) = split;
    let border_mean = border_sum / border_n as f64;
    let dark_ink_on_light = border_mean > split_t as f64;
    let m_bg = if dark_ink_on_light { m_light } else { m_dark };
    // The threshold sits 4 below the background-class mean (anti-alias
    // margin), clamped to the background half of the range.
    let background_threshold = if dark_ink_on_light {
        (m_bg.round() as i64 - 4).clamp(128, 255) as u8
    } else {
        255 - (m_bg.round() as i64 + 4).clamp(0, 127) as u8
    };
    (
        BlankRule { background_threshold, dark_ink_on_light },
        "otsu-border",
    )
}

fn csv_hex(cps: &[u32]) -> String {
    cps.iter().map(|cp| format!("{cp:#x}")).collect::<Vec<_>>().join(",")
}

fn state_kind(s: &DetectionState) -> &'static str {
    match s {
        DetectionState::PixelEvidence { .. } => "PixelEvidence",
        DetectionState::MissingPixelEvidence => "MissingPixelEvidence",
        DetectionState::AmbiguousPixelCandidate => "AmbiguousPixelCandidate",
        DetectionState::CandidateProxy { .. } => "CandidateProxy",
        DetectionState::RepeatedArt { .. } => "RepeatedArt",
        DetectionState::VerifiedBlank { .. } => "VerifiedBlank",
        DetectionState::MissingEvidence => "MissingEvidence",
        DetectionState::Ambiguous => "Ambiguous",
    }
}

/// Sorted, deduped codepoints of the scan's candidate/confirmed group.
fn scan_candidate_cps(tiles: &[Tile], report: &ScanReport) -> Vec<u32> {
    let mut cps: Vec<u32> = tiles
        .iter()
        .zip(report.classifications.iter())
        .filter(|(_, c)| matches!(c.class, Class::Candidate | Class::Notdef))
        .filter_map(|(t, _)| t.codepoint)
        .collect();
    cps.sort_unstable();
    cps.dedup();
    cps
}

/// Advisory reconcile against the existing detector state: sorted-set
/// compare against CandidateProxy candidate_cps; every other state kind
/// is recorded with no comparison basis.
fn reconcile_row(nd_state: &DetectionState, scan_cps: &[u32]) -> String {
    let scan = csv_hex(scan_cps);
    match nd_state {
        DetectionState::CandidateProxy { candidate_cps, .. } => {
            let mut proxy = candidate_cps.clone();
            proxy.sort_unstable();
            proxy.dedup();
            let verdict = if &proxy == scan_cps { "agree" } else { "disagree" };
            format!(
                "k3_notdef_scan\treconcile\t{verdict}\tstate\tCandidateProxy\tproxy_cps\t{}\tscan_cps\t{scan}\n",
                csv_hex(&proxy)
            )
        }
        other => format!(
            "k3_notdef_scan\treconcile\tno-proxy-candidate\tstate\t{}\tproxy_cps\t\tscan_cps\t{scan}\n",
            state_kind(other)
        ),
    }
}

/// The single pipeline-entry call (invoked once from main, right after the
/// nd_classification receipt block). Returns receipt rows only.
pub fn run(glyphs: &[GlyphRow], limits: Limits, nd_state: &DetectionState) -> String {
    let mut out = String::new();
    let mut kept: Vec<&GlyphRow> = Vec::new();
    let mut decoded: Vec<DecodedSource> = Vec::new();
    for g in glyphs {
        let bytes = match read_source_bounded(&g.image, limits.max_input_bytes) {
            Ok(b) => b,
            Err(e) => {
                out.push_str(&format!(
                    "k3_notdef_scan\trow_error\tglyph\t{}\tcp\t{}\tstage\tread\tdetail\t{e}\n",
                    g.name, g.cp_display()
                ));
                continue;
            }
        };
        match decode_source(&bytes, &PNG_DECODE_LIMITS, limits) {
            Ok(d) => {
                kept.push(g);
                decoded.push(d);
            }
            Err(e) => out.push_str(&format!(
                "k3_notdef_scan\trow_error\tglyph\t{}\tcp\t{}\tstage\tdecode\tdetail\t{e:?}\n",
                g.name, g.cp_display()
            )),
        }
    }
    let failed = glyphs.len() - kept.len();
    out.push_str(&format!(
        "k3_notdef_scan\tversion\tv4-gray\ttiles\t{}\tdecoded\t{}\tfailed\t{failed}\n",
        glyphs.len(),
        kept.len()
    ));
    let (rule, derivation) = derive_blank_rule(&decoded);
    out.push_str(&format!(
        "k3_notdef_scan\tblank_rule\tthreshold\t{}\tpolarity\t{}\tderivation\t{derivation}\n",
        rule.background_threshold,
        if rule.dark_ink_on_light { "dark-ink-on-light" } else { "light-ink-on-dark" }
    ));
    let tiles: Vec<Tile> = kept
        .iter()
        .zip(decoded.iter())
        .map(|(g, d)| Tile {
            glyph_name: &g.name,
            codepoint: g.codepoint,
            // max_pixels (4_194_304) bounds both axes well inside u32.
            width: d.width as u32,
            height: d.height as u32,
            gray: &d.gray,
        })
        .collect();
    // Honest tile-stage evidence: no shipped OTF cmap exists to confirm
    // against, so `known: false`; a repeated form stays Candidate and
    // drop_from_font stays false everywhere in this report.
    let ev = CmapEvidence { codepoints: HashSet::new(), known: false };
    let report = classify_population(&tiles, &ev, &rule);
    let (mut n_real, mut n_absent, mut n_malformed, mut n_cand, mut n_notdef) =
        (0usize, 0usize, 0usize, 0usize, 0usize);
    for c in &report.classifications {
        match c.class {
            Class::Real => n_real += 1,
            Class::Absent => n_absent += 1,
            Class::Malformed => n_malformed += 1,
            Class::Candidate => n_cand += 1,
            Class::Notdef => n_notdef += 1,
        }
    }
    out.push_str(&format!(
        "k3_notdef_scan\tclass_counts\treal\t{n_real}\tabsent\t{n_absent}\tmalformed\t{n_malformed}\tcandidate\t{n_cand}\tnotdef\t{n_notdef}\tambiguous\t{}\tdiagnostics\t{}\n",
        report.ambiguous as u8,
        report.diagnostics.len()
    ));
    for d in &report.diagnostics {
        out.push_str(&format!("k3_notdef_scan\tdiagnostic\t{d}\n"));
    }
    let mut ordered: Vec<_> = report.classifications.iter().collect();
    ordered.sort_by(|a, b| a.glyph_name.cmp(&b.glyph_name));
    for c in ordered {
        out.push_str(&format!(
            "k3_notdef_scan\ttile\tglyph\t{}\tclass\t{:?}\tgroup_size\t{}\tdrop_from_font\t{}\n",
            c.glyph_name, c.class, c.group_size, c.drop_from_font as u8
        ));
    }
    for group in &report.tie_groups {
        out.push_str(&format!("k3_notdef_scan\ttie_group\tmembers\t{}\n", group.join(",")));
    }
    let scan_cps = scan_candidate_cps(&tiles, &report);
    if let Some(rep) = &report.notdef_representative {
        out.push_str(&format!(
            "k3_notdef_scan\tcandidate\trepresentative\t{rep}\tcps\t{}\n",
            csv_hex(&scan_cps)
        ));
    }
    out.push_str(&reconcile_row(nd_state, &scan_cps));
    out
}

/// Keep declared, rejected, proxy and already classified evidence on the
/// current chain. Absence of a capture manifest also falls through unchanged.
pub fn route_if_missing(
    m: &Manifest, rc: &RunConfig, limits: Limits, state: DetectionState,
    rejected: bool, receipt: &mut String,
) -> DetectionState {
    if !matches!(&state, DetectionState::MissingPixelEvidence) {
        return state;
    }
    if rejected || m.notdef.is_some() || m.notdef_proxy.is_some() {
        receipt.push_str("k3_notdef_scan\tevidence_route\tskipped\treason\tdeclared-evidence-rejected\n");
        return state;
    }
    evidence_route(m, rc, limits, receipt).unwrap_or(state)
}

/// The strictly-largest form group, requiring size >= 2 and no tie at the
/// top - the validator's own winner rule, so the claim we build can never
/// win locally what the validator would refuse.
fn winner_group<'a>(forms: &'a BTreeMap<String, Vec<u32>>) -> Option<(&'a String, &'a Vec<u32>)> {
    let max = forms.values().map(Vec::len).max()?;
    if max < 2 {
        return None;
    }
    let mut top = forms.iter().filter(|(_, cps)| cps.len() == max);
    let w = top.next()?;
    if top.next().is_some() {
        return None; // tie at the top: ambiguous, never a silent claim
    }
    Some(w)
}

/// Aggregate budget charge (chief v5.1 item 1): checked subtract
/// against limits.max_working_bytes; None on overflow past the bound.
fn charge(budget: &mut usize, n: usize) -> Option<()> {
    *budget = budget.checked_sub(n)?;
    Some(())
}

/// Scan -> validated-evidence producer route (chief 2026-10-19 15:41;
/// hardened v5.1).
///
/// Called ONLY when the manifest carried no notdef evidence and nothing
/// declared was rejected (the call-site gate owns that decision): the
/// scan's winning form group becomes a CLAIM, notdef_producer::produce
/// packages it into the v3 evidence grammar, and
/// bound_detector_validator::load re-decodes the whole pinned capture
/// population and re-derives the winner from pixels. Confirmed ->
/// Some(DetectionState::PixelEvidence), which flows into the EXISTING
/// extraction/routing untouched. A bare candidate (count-1), an ambiguous
/// tie, a blank winning form, or any producer/validator refusal -> None:
/// the existing fallback runs and nothing is dropped. The scan itself
/// never drops a glyph and never bypasses the validator.
///
/// v5.1 hardening (chief review):
/// (1) every held population PNG byte is charged against
///     limits.max_working_bytes (aggregate gate: capture record + all
///     tile bytes held for the claim);
/// (2) the transient evidence record is written with create_new under a
///     unique pid+attempt name: an existing same-name file is never
///     overwritten and a symlink at the path is never followed;
/// (3) the capture record is parsed with the caller's exact grammar
///     (notdef_caller::load): context rows style/cohort/frame are
///     required and must match this run, unknown rows refuse, source
///     paths are relative-only and confined under the run root
///     (canonicalized), row/witness caps match.
pub fn evidence_route(
    m: &Manifest,
    rc: &RunConfig,
    limits: Limits,
    receipt: &mut String,
) -> Option<DetectionState> {
    let fail = |receipt: &mut String, reason: &str| {
        receipt.push_str(&format!("k3_notdef_scan\tevidence_route\tskipped\treason\t{reason}\n"));
        None
    };
    let Some((cap_path, cap_pin)) = &m.capture_manifest else {
        return fail(receipt, "no-capture-manifest");
    };
    let root = rc.capture_dir();
    let root_canon = match root.canonicalize() {
        Ok(r) => r,
        Err(_) => return fail(receipt, "capture-io"),
    };
    // Caller anchoring (notdef_caller::within): relative paths join the
    // run root, everything canonicalizes and must stay inside the root.
    let confined = |rel: &std::path::Path| -> Option<PathBuf> {
        if rel.components().any(|c| matches!(c, std::path::Component::ParentDir)) {
            return None;
        }
        let p = if rel.is_absolute() { rel.to_path_buf() } else { root_canon.join(rel) };
        let p = p.canonicalize().ok()?;
        if !p.starts_with(&root_canon) {
            return None;
        }
        Some(p)
    };
    // v5.1 (1): aggregate budget over every held PNG byte. The capture
    // record plus all tile bytes kept for the claim never exceed
    // limits.max_working_bytes.
    let mut budget = limits.max_working_bytes;
    let cap_abs = match confined(cap_path) {
        Some(p) => p,
        None => return fail(receipt, "capture-context"),
    };
    let cap_bytes = match read_source_bounded(&cap_abs, limits.max_input_bytes) {
        Ok(b) => b,
        Err(_) => return fail(receipt, "capture-read"),
    };
    if charge(&mut budget, cap_bytes.len()).is_none() {
        return fail(receipt, "aggregate-bound");
    }
    if sha256_hex(&cap_bytes) != *cap_pin {
        return fail(receipt, "capture-pin-mismatch");
    }
    let style_id = match scale_wiring::style_id_of(&m.family, &m.subfamily) {
        Ok(s) => s,
        Err(_) => return fail(receipt, "style-id"),
    };
    let style_token = match validator::encode_style_token(&style_id) {
        Ok(s) => s,
        Err(_) => return fail(receipt, "style-token"),
    };
    let scale = rc.scale();
    // Pinned population from the capture manifest, parsed with the
    // caller's exact grammar (notdef_caller::load): context rows bind
    // style/cohort/frame to this run; source rows carry relative paths
    // confined under the run root; row/witness caps match.
    let mut population: validator::PixelPopulation = BTreeMap::new();
    {
        let text = match std::str::from_utf8(&cap_bytes) {
            Ok(t) => t,
            Err(_) => return fail(receipt, "capture-grammar"),
        };
        let mut lines = text.lines();
        if lines.next() != Some("kni-capture-manifest\tv1") {
            return fail(receipt, "capture-grammar");
        }
        let mut context: BTreeMap<&str, &str> = BTreeMap::new();
        for (row, line) in lines.enumerate() {
            if row >= 131_072 {
                return fail(receipt, "capture-limit");
            }
            if line.split('\t').take(5).count() > 4 {
                return fail(receipt, "capture-grammar");
            }
            let f: Vec<&str> = line.split('\t').collect();
            match f.as_slice() {
                [key, value] if ["style", "cohort", "frame"].contains(key) => {
                    if context.insert(*key, *value).is_some() {
                        return fail(receipt, "capture-duplicate");
                    }
                }
                ["source", cp, path, pin] => {
                    if population.len() >= 65_535 {
                        return fail(receipt, "capture-limit");
                    }
                    let Ok(scalar) = u32::from_str_radix(cp.strip_prefix("0x").unwrap_or(cp), 16) else {
                        return fail(receipt, "capture-grammar");
                    };
                    if validator::validate_codepoint(scalar).is_err() {
                        return fail(receipt, "capture-grammar");
                    }
                    let rel = std::path::Path::new(path);
                    if rel.is_absolute() {
                        return fail(receipt, "capture-context");
                    }
                    let abs = match confined(rel) {
                        Some(p) => p,
                        None => return fail(receipt, "capture-context"),
                    };
                    if population.insert(scalar, (abs, (*pin).to_string())).is_some() {
                        return fail(receipt, "capture-duplicate");
                    }
                }
                _ => return fail(receipt, "capture-grammar"),
            }
        }
        if context.get("style") != Some(&style_id.as_str())
            || context.get("cohort") != Some(&scale.cohort())
            || context.get("frame") != Some(&scale.frame_binding())
        {
            return fail(receipt, "capture-context");
        }
    }
    if population.len() < 2 {
        return fail(receipt, "population-too-small");
    }
    // Scan pass: decode every pinned tile once, group by the validator's
    // canonical form hash. PNG bytes of the whole population are held for
    // the claim under the aggregate budget; decoded gray is dropped per
    // iteration.
    let mut forms: BTreeMap<String, Vec<u32>> = BTreeMap::new();
    let mut form_blank: BTreeMap<String, bool> = BTreeMap::new();
    let mut kept: BTreeMap<u32, (String, Vec<u8>, String)> = BTreeMap::new(); // cp -> (root-relative path, bytes, form)
    for (cp, (abs, pin)) in &population {
        let bytes = match read_source_bounded(abs, limits.max_input_bytes) {
            Ok(b) => b,
            Err(_) => return fail(receipt, "tile-read"),
        };
        if charge(&mut budget, bytes.len()).is_none() {
            return fail(receipt, "aggregate-bound");
        }
        if sha256_hex(&bytes) != *pin {
            return fail(receipt, "tile-pin-mismatch");
        }
        let d = match decode_source(&bytes, &PNG_DECODE_LIMITS, limits) {
            Ok(d) => d,
            Err(_) => return fail(receipt, "tile-decode"),
        };
        let form = match validator::pixel_form_sha256(d.width, d.height, &d.gray) {
            Ok(h) => h,
            Err(_) => return fail(receipt, "form-hash"),
        };
        form_blank.insert(form.clone(), d.gray.iter().all(|&v| v == 255));
        forms.entry(form.clone()).or_default().push(*cp);
        let rel = match abs.strip_prefix(&root_canon) {
            Ok(r) => r.to_string_lossy().into_owned(),
            Err(_) => return fail(receipt, "capture-context"),
        };
        kept.insert(*cp, (rel, bytes, form));
    }
    let Some((win_hash, win_cps)) = winner_group(&forms) else {
        return fail(receipt, "no-dominant-form");
    };
    if form_blank.get(win_hash) != Some(&false) {
        // A blank winning form is the existing blank-notdef fallback arm.
        return fail(receipt, "winner-blank");
    }
    // Claim: the smallest codepoint of the winning group is the selected
    // source (content-identical by construction; deterministic).
    let sel_cp = *win_cps.iter().min()?;
    let sel_pin = population.get(&sel_cp).map(|(_, pin)| pin.clone())?;
    let context = validator::PixelContext {
        style: style_token.clone(),
        frame: scale.frame_binding().to_string(),
        units_per_px: scale.units_per_px(),
        source_sha256: sel_pin,
        ink_model: validator::PIXEL_INK_MODEL.into(),
    };
    let tiles: Vec<notdef_producer::Tile> = win_cps
        .iter()
        .map(|cp| {
            let (path, bytes, _) = kept.get(cp).expect("winner cp kept");
            notdef_producer::Tile {
                cp: *cp,
                path: path.as_str(),
                bytes: bytes.as_slice(),
                role: Some(PixelNotdefKind::RepeatedForm),
            }
        })
        .collect();
    let request = notdef_producer::Request {
        context: &context,
        cohort: scale.cohort(),
        request_source: "k3-notdef-scan",
        capture_record: &cap_bytes,
        capture_sha256: cap_pin,
        space_evidence_sha256: None,
        pixel_form_sha256: win_hash,
        tiles: &tiles,
        limits,
    };
    let produced = match notdef_producer::produce(&request) {
        Ok(p) => p,
        Err(_) => return fail(receipt, "producer-refused"),
    };
    // The validator loads a pinned record file under the run root: stage
    // it transiently, validate, remove. v5.1 (2): create_new under a
    // unique pid+attempt name - an existing same-name file is never
    // overwritten and a symlink at the path is never followed.
    let mut tmp: Option<PathBuf> = None;
    for attempt in 0..100u32 {
        let cand = root.join(format!(".k3-scan-evidence-{}-{attempt}.tsv", std::process::id()));
        match std::fs::OpenOptions::new().write(true).create_new(true).open(&cand) {
            Ok(mut f) => {
                use std::io::Write;
                if f.write_all(produced.evidence.as_bytes()).is_err() {
                    let _ = std::fs::remove_file(&cand);
                    return fail(receipt, "record-write");
                }
                tmp = Some(cand);
                break;
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(_) => return fail(receipt, "record-write"),
        }
    }
    let Some(tmp) = tmp else {
        return fail(receipt, "record-custody");
    };
    let binding = EvidenceBinding {
        file: tmp.clone(),
        sha256: produced.evidence_sha.clone(),
        style: style_token,
        capture: cap_pin.clone(),
        scale: scale.units_per_px(),
        frame: scale.frame_binding().to_string(),
    };
    let vlimits = ValidationLimits {
        image: limits,
        max_record_bytes: limits.max_input_bytes,
        max_record_rows: 131_072,
        max_witnesses: 65_535,
        max_aggregate_working_bytes: limits.max_working_bytes.saturating_sub(cap_bytes.len()),
    };
    let validated = validator::load(&binding, &population, scale, &root, vlimits, &CoreBoundedDecoder);
    let _ = std::fs::remove_file(&tmp);
    match validated {
        Ok(state @ DetectionState::PixelEvidence { .. }) => {
            receipt.push_str(&format!(
                "k3_notdef_scan\tevidence_route\tconfirmed\tkind\trepeated-form\tpixel_form_sha256\t{win_hash}\tsources\t{}\n",
                win_cps.iter().map(|c| format!("{c:#x}")).collect::<Vec<_>>().join(",")
            ));
            Some(state)
        }
        Ok(_) | Err(_) => fail(receipt, "validator-refused"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Pinned tiny 2x2 8-bit gray PNGs (color type 0): all-black ink,
    // checkerboard, all-white blank.
    const PNG_INK: &[u8] = &[137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,2,0,0,0,2,8,0,0,0,0,87,221,82,248,0,0,0,11,73,68,65,84,120,156,99,96,0,1,0,0,6,0,1,254,140,103,200,0,0,0,0,73,69,78,68,174,66,96,130];
    const PNG_MIX: &[u8] = &[137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,2,0,0,0,2,8,0,0,0,0,87,221,82,248,0,0,0,12,73,68,65,84,120,156,99,96,248,15,132,0,6,0,1,255,147,209,228,137,0,0,0,0,73,69,78,68,174,66,96,130];
    const PNG_BLANK: &[u8] = &[137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,2,0,0,0,2,8,0,0,0,0,87,221,82,248,0,0,0,14,73,68,65,84,120,156,99,248,255,159,225,255,127,0,11,250,3,253,224,37,138,16,0,0,0,0,73,69,78,68,174,66,96,130];

    fn limits() -> Limits {
        Limits { max_input_bytes: 1 << 20, max_pixels: 1 << 16, max_working_bytes: 1 << 22 }
    }

    fn tempdir(tag: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("k3scan-{}-{tag}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    /// (name, codepoint, Some(png bytes) to write / None to leave missing)
    fn glyphs(dir: &std::path::Path, spec: &[(&str, u32, Option<&[u8]>)]) -> Vec<GlyphRow> {
        spec.iter()
            .map(|(name, cp, bytes)| {
                let image = dir.join(name);
                if let Some(b) = bytes {
                    std::fs::write(&image, b).unwrap();
                }
                GlyphRow { codepoint: Some(*cp), extra_cps: vec![], name: name.to_string(), image, scale: None }
            })
            .collect()
    }

    fn proxy(candidate_cps: Vec<u32>) -> DetectionState {
        DetectionState::CandidateProxy {
            selected_source_sha: "s".repeat(64),
            selected_cp: 0,
            candidate_cps,
            selection_rule: "test".into(),
            generated_glyph_ref: "g".into(),
            source_snapshot: vec![],
        }
    }

    #[test]
    fn negative_no_notdef_all_distinct() {
        let d = tempdir("no-notdef");
        let g = glyphs(&d, &[("a.png", 0x41, Some(PNG_INK)), ("b.png", 0x42, Some(PNG_MIX))]);
        let r = run(&g, limits(), &DetectionState::MissingPixelEvidence);
        assert!(r.contains("k3_notdef_scan\tversion\tv4-gray\ttiles\t2\tdecoded\t2\tfailed\t0"), "{r}");
        assert!(r.contains("k3_notdef_scan\tblank_rule\tthreshold\t251\tpolarity\tdark-ink-on-light\tderivation\totsu-border"), "{r}");
        assert!(r.contains("k3_notdef_scan\tclass_counts\treal\t2\tabsent\t0\tmalformed\t0\tcandidate\t0\tnotdef\t0\tambiguous\t0"), "{r}");
        assert!(r.contains("k3_notdef_scan\treconcile\tno-proxy-candidate\tstate\tMissingPixelEvidence"), "{r}");
        assert!(!r.contains("k3_notdef_scan\tcandidate\t"), "{r}");
    }

    #[test]
    fn candidate_reconcile_agree_and_disagree() {
        let d = tempdir("agree");
        let g = glyphs(&d, &[
            ("a.png", 0x41, Some(PNG_INK)),
            ("b.png", 0x42, Some(PNG_INK)),
            ("c.png", 0x43, Some(PNG_MIX)),
        ]);
        let agree = run(&g, limits(), &proxy(vec![0x42, 0x41]));
        assert!(agree.contains("k3_notdef_scan\tcandidate\trepresentative\ta.png\tcps\t0x41,0x42"), "{agree}");
        assert!(agree.contains("k3_notdef_scan\treconcile\tagree\tstate\tCandidateProxy\tproxy_cps\t0x41,0x42\tscan_cps\t0x41,0x42"), "{agree}");
        let disagree = run(&g, limits(), &proxy(vec![0x41]));
        assert!(disagree.contains("k3_notdef_scan\treconcile\tdisagree\tstate\tCandidateProxy\tproxy_cps\t0x41\tscan_cps\t0x41,0x42"), "{disagree}");
    }

    #[test]
    fn negative_different_tiles_tie_is_ambiguous_never_candidate() {
        let d = tempdir("tie");
        let g = glyphs(&d, &[
            ("a.png", 0x41, Some(PNG_INK)),
            ("b.png", 0x42, Some(PNG_INK)),
            ("c.png", 0x43, Some(PNG_MIX)),
            ("d.png", 0x44, Some(PNG_MIX)),
        ]);
        let r = run(&g, limits(), &proxy(vec![0x41, 0x42]));
        assert!(r.contains("k3_notdef_scan\tclass_counts\treal\t4\tabsent\t0\tmalformed\t0\tcandidate\t0\tnotdef\t0\tambiguous\t1"), "{r}");
        assert!(!r.contains("k3_notdef_scan\tcandidate\t"), "{r}");
        assert!(r.contains("k3_notdef_scan\treconcile\tdisagree"), "{r}");
    }

    #[test]
    fn negative_blank_only_population_no_candidate() {
        let d = tempdir("blank");
        let g = glyphs(&d, &[("a.png", 0x41, Some(PNG_BLANK)), ("b.png", 0x42, Some(PNG_BLANK))]);
        let r = run(&g, limits(), &DetectionState::MissingPixelEvidence);
        assert!(r.contains("derivation\tdefault-degenerate"), "{r}");
        assert!(r.contains("k3_notdef_scan\tclass_counts\treal\t0\tabsent\t2\tmalformed\t0\tcandidate\t0\tnotdef\t0\tambiguous\t0"), "{r}");
    }

    #[test]
    fn negative_mixed_failed_rows_never_panic() {
        let d = tempdir("mixed");
        let g = glyphs(&d, &[
            ("ok.png", 0x41, Some(PNG_INK)),
            ("missing.png", 0x42, None),
            ("garbage.png", 0x43, Some(b"not a png")),
        ]);
        let r = run(&g, limits(), &DetectionState::MissingPixelEvidence);
        assert!(r.contains("k3_notdef_scan\tversion\tv4-gray\ttiles\t3\tdecoded\t1\tfailed\t2"), "{r}");
        assert!(r.contains("row_error\tglyph\tmissing.png\tcp\t0x42\tstage\tread"), "{r}");
        assert!(r.contains("row_error\tglyph\tgarbage.png\tcp\t0x43\tstage\tdecode"), "{r}");
        assert!(r.contains("k3_notdef_scan\tclass_counts\treal\t1"), "{r}");
    }

    #[test]
    fn negative_order_determinism_identical_receipt() {
        let d = tempdir("order");
        let fwd = glyphs(&d, &[("a.png", 0x41, Some(PNG_INK)), ("b.png", 0x42, Some(PNG_MIX))]);
        let rev: Vec<GlyphRow> = fwd.iter().rev().map(|g| GlyphRow {
            codepoint: g.codepoint, extra_cps: g.extra_cps.clone(), name: g.name.clone(), image: g.image.clone(), scale: g.scale,
        }).collect();
        let r1 = run(&fwd, limits(), &DetectionState::MissingPixelEvidence);
        let r2 = run(&rev, limits(), &DetectionState::MissingPixelEvidence);
        assert_eq!(r1, r2, "receipt must be input-order independent");
    }

    #[test]
    fn winner_group_rule_strict_largest_no_tie() {
        let mut forms: BTreeMap<String, Vec<u32>> = BTreeMap::new();
        forms.insert("a".into(), vec![0x41, 0x42]);
        forms.insert("b".into(), vec![0x43]);
        let (h, cps) = winner_group(&forms).unwrap();
        assert_eq!(h, "a");
        assert_eq!(cps, &vec![0x41, 0x42]);
        forms.insert("c".into(), vec![0x44, 0x45]);
        assert!(winner_group(&forms).is_none(), "tie at the top is never a claim");
        let singles: BTreeMap<String, Vec<u32>> = [("x".to_string(), vec![1u32])].into_iter().collect();
        assert!(winner_group(&singles).is_none(), "singleton repeats nothing");
    }

    // ---- v5.1 route tests (chief: valid confirm, tampered pin,
    // duplicate, ambiguous, aggregate bound, temp collision) ----

    fn crc32(bytes: &[u8]) -> u32 {
        let mut c: u32 = 0xFFFF_FFFF;
        for &b in bytes {
            c ^= b as u32;
            for _ in 0..8 { c = if c & 1 != 0 { (c >> 1) ^ 0xEDB8_8320 } else { c >> 1 }; }
        }
        !c
    }
    fn chunk(tag: &[u8; 4], data: &[u8]) -> Vec<u8> {
        let mut out = (data.len() as u32).to_be_bytes().to_vec();
        out.extend_from_slice(tag);
        out.extend_from_slice(data);
        let mut crc_in = tag.to_vec(); crc_in.extend_from_slice(data);
        out.extend_from_slice(&crc32(&crc_in).to_be_bytes());
        out
    }
    /// Minimal 8-bit grayscale PNG writer (stored deflate blocks), same
    /// construction as notdef_routing_tests: controlled pixels, distinct
    /// container bytes on demand.
    fn png_gray(width: u32, height: u32, gray: &[u8], tag: Option<&str>) -> Vec<u8> {
        assert_eq!(gray.len(), (width * height) as usize);
        let mut raw = Vec::new();
        for row in 0..height as usize {
            raw.push(0u8);
            raw.extend_from_slice(&gray[row * width as usize..(row + 1) * width as usize]);
        }
        let mut z = vec![0x78u8, 0x01];
        let mut rest = raw.as_slice();
        loop {
            let n = rest.len().min(65535);
            let last = n == rest.len();
            z.push(if last { 1 } else { 0 });
            z.extend_from_slice(&(n as u16).to_le_bytes());
            z.extend_from_slice(&(!(n as u16)).to_le_bytes());
            z.extend_from_slice(&rest[..n]);
            rest = &rest[n..];
            if last { break; }
        }
        let mut a: u32 = 1; let mut b: u32 = 0;
        for &x in &raw { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
        z.extend_from_slice(&((b << 16) | a).to_be_bytes());
        let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
        let mut ihdr = width.to_be_bytes().to_vec();
        ihdr.extend_from_slice(&height.to_be_bytes());
        ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
        png.extend_from_slice(&chunk(b"IHDR", &ihdr));
        if let Some(t) = tag {
            let mut tex = b"Comment".to_vec(); tex.push(0); tex.extend_from_slice(t.as_bytes());
            png.extend_from_slice(&chunk(b"tEXt", &tex));
        }
        png.extend_from_slice(&chunk(b"IDAT", &z));
        png.extend_from_slice(&chunk(b"IEND", &[]));
        png
    }

    const GRAY_A: [u8; 64] = [7u8; 64];
    const GRAY_B: [u8; 64] = [9u8; 64];
    const GRAY_C: [u8; 64] = [3u8; 64];

    fn form_sha(png: &[u8]) -> String {
        let d = decode_source(png, &PNG_DECODE_LIMITS, limits()).unwrap();
        validator::pixel_form_sha256(d.width, d.height, &d.gray).unwrap()
    }

    fn route_rc(root: &std::path::Path) -> RunConfig {
        let ctx = kni_core::scale_context::ScaleContext::from_convention(
            "Test/Regular", "k3-route-test-v1", 2.0, 1000.0, "Test/Regular", "f1",
        ).unwrap();
        let input = RunConfig::legacy_defaults_input(
            Some(crate::run_config::FitErrorPolicy::Fixed),
            root.to_path_buf(),
            root.join("out"),
            "s1",
        );
        RunConfig::new(input, ctx).unwrap()
    }

    fn route_manifest(cap_sha: &str) -> Manifest {
        Manifest {
            os2_x_height_write: None,
            m3: crate::M3Decl::default(),
            family: "Test".into(),
            subfamily: "Regular".into(),
            postscript_name: "Test-Regular".into(),
            postscript_name_declared: None,
            vendor: *b"TEST",
            upm: 1000,
            scale: 2.0,
            capture_frame: None,
            capture_cohort: None,
            post_lsb_add: 0.0,
            post_rsb_add: 0.0,
            post_scope: kni_core::offset_scope::ScopePolicy { base: false, space: false, notdef: false, mark: false, kerning_letters: false },
            post_scope_label: "none".into(),
            rdp_epsilon: 0.25,
            fit_squared_error: 0.25,
            fit_max_refits: 8,
            fit_tolerance_policy: crate::FitTolerancePolicy::Fixed,
            flatten_tolerance: 0.5,
            scan_row_step: 10.0,
            scan_max_rows: 1000,
            sample_resolution: 10.0,
            max_pair_evaluations: 1_000_000,
            iou: None,
            max_pairs: 10_000,
            pair_min_shared_rows: 1,
            glyphs: vec![],
            space_evidence: None,
            space: None,
            derive_space_from_letter_advances: false,
            auto_sb: None, auto_sb_class_table: None, auto_sb_pool: None, auto_sb_offset_lsb: None, auto_sb_offset_rsb: None, tie_break: None,
            notdef: None,
            learned_store: None, learned_gate_evidence: None, pair_visual_same_source: false,
            notdef_proxy: None,
            capture_manifest: Some((PathBuf::from("capture-manifest.tsv"), cap_sha.to_string())),
            style_overrides: None,
            run_mode: crate::RunMode::Full,
            corner_wiring: false,
            population_sha256: "0".repeat(64),
            stage1_cache: None,
            references: vec![],
            frame_map: None,
            guide: None,
        }
    }

    /// Standard staged run root: ordinary 0x43 + same-form 0x41/0x42
    /// (same pixels, different container bytes) + v1 capture manifest
    /// with binding context rows. Returns (dir, cap_sha).
    fn route_fx(tag: &str) -> (PathBuf, String) {
        let d = tempdir(tag);
        std::fs::create_dir_all(d.join("glyph")).unwrap();
        std::fs::create_dir_all(d.join("notdef")).unwrap();
        let ordinary = png_gray(8, 8, &GRAY_B, None);
        let w65 = png_gray(8, 8, &GRAY_A, None);
        let w66 = png_gray(8, 8, &GRAY_A, Some("copy"));
        std::fs::write(d.join("glyph/t67.png"), &ordinary).unwrap();
        std::fs::write(d.join("notdef/w65"), &w65).unwrap();
        std::fs::write(d.join("notdef/w66"), &w66).unwrap();
        let cap = format!(
            "kni-capture-manifest\tv1\nstyle\tTest/Regular\nframe\tf1\ncohort\tTest/Regular\nsource\t0x43\tglyph/t67.png\t{}\nsource\t0x41\tnotdef/w65\t{}\nsource\t0x42\tnotdef/w66\t{}\n",
            sha256_hex(&ordinary), sha256_hex(&w65), sha256_hex(&w66)
        );
        let cap_sha = sha256_hex(cap.as_bytes());
        std::fs::write(d.join("capture-manifest.tsv"), &cap).unwrap();
        (d, cap_sha)
    }

    #[test]
    fn route_valid_confirm_repeated_form() {
        let (d, cap_sha) = route_fx("confirm");
        let m = route_manifest(&cap_sha);
        let rc = route_rc(&d);
        let mut receipt = String::new();
        let state = evidence_route(&m, &rc, limits(), &mut receipt).expect("route confirms");
        match &state {
            DetectionState::PixelEvidence { kind, sources, pixel_form_sha256, .. } => {
                assert_eq!(*kind, PixelNotdefKind::RepeatedForm);
                assert_eq!(sources, &vec![0x41, 0x42]);
                let w65 = std::fs::read(d.join("notdef/w65")).unwrap();
                assert_eq!(pixel_form_sha256, &form_sha(&w65));
            }
            other => panic!("expected PixelEvidence, got {other:?}"),
        }
        let w65b = std::fs::read(d.join("notdef/w65")).unwrap();
        let expect = format!("k3_notdef_scan\tevidence_route\tconfirmed\tkind\trepeated-form\tpixel_form_sha256\t{}\tsources\t0x41,0x42", form_sha(&w65b));
        assert!(receipt.contains(&expect), "{receipt}");
        let leftovers: Vec<_> = std::fs::read_dir(&d).unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().starts_with(".k3-scan-evidence-"))
            .collect();
        assert!(leftovers.is_empty(), "transient record removed after validation");
    }

    #[test]
    fn route_tampered_tile_pin_is_refused() {
        let (d, cap_sha) = route_fx("tamper");
        let mut b = std::fs::read(d.join("notdef/w66")).unwrap();
        b.push(0);
        std::fs::write(d.join("notdef/w66"), &b).unwrap();
        let m = route_manifest(&cap_sha);
        let rc = route_rc(&d);
        let mut receipt = String::new();
        assert!(evidence_route(&m, &rc, limits(), &mut receipt).is_none());
        assert!(receipt.contains("evidence_route\tskipped\treason\ttile-pin-mismatch"), "{receipt}");
    }

    #[test]
    fn route_duplicate_capture_row_is_refused() {
        let (d, _cap_sha) = route_fx("dup");
        let w65 = std::fs::read(d.join("notdef/w65")).unwrap();
        let w66 = std::fs::read(d.join("notdef/w66")).unwrap();
        let cap = format!(
            "kni-capture-manifest\tv1\nstyle\tTest/Regular\nframe\tf1\ncohort\tTest/Regular\nsource\t0x41\tnotdef/w65\t{}\nsource\t0x41\tnotdef/w66\t{}\n",
            sha256_hex(&w65), sha256_hex(&w66)
        );
        let cap_sha = sha256_hex(cap.as_bytes());
        std::fs::write(d.join("capture-manifest.tsv"), &cap).unwrap();
        let m = route_manifest(&cap_sha);
        let rc = route_rc(&d);
        let mut receipt = String::new();
        assert!(evidence_route(&m, &rc, limits(), &mut receipt).is_none());
        assert!(receipt.contains("evidence_route\tskipped\treason\tcapture-duplicate"), "{receipt}");
    }

    #[test]
    fn route_ambiguous_tie_is_never_a_claim() {
        let d = tempdir("route-tie");
        std::fs::create_dir_all(d.join("glyph")).unwrap();
        std::fs::create_dir_all(d.join("notdef")).unwrap();
        let ordinary = png_gray(8, 8, &GRAY_B, None);
        std::fs::write(d.join("glyph/t67.png"), &ordinary).unwrap();
        let a1 = png_gray(8, 8, &GRAY_A, None);
        let a2 = png_gray(8, 8, &GRAY_A, Some("a2"));
        let c1 = png_gray(8, 8, &GRAY_C, None);
        let c2 = png_gray(8, 8, &GRAY_C, Some("c2"));
        std::fs::write(d.join("notdef/w41"), &a1).unwrap();
        std::fs::write(d.join("notdef/w42"), &a2).unwrap();
        std::fs::write(d.join("notdef/w44"), &c1).unwrap();
        std::fs::write(d.join("notdef/w45"), &c2).unwrap();
        let cap = format!(
            "kni-capture-manifest\tv1\nstyle\tTest/Regular\nframe\tf1\ncohort\tTest/Regular\nsource\t0x43\tglyph/t67.png\t{}\nsource\t0x41\tnotdef/w41\t{}\nsource\t0x42\tnotdef/w42\t{}\nsource\t0x44\tnotdef/w44\t{}\nsource\t0x45\tnotdef/w45\t{}\n",
            sha256_hex(&ordinary), sha256_hex(&a1), sha256_hex(&a2), sha256_hex(&c1), sha256_hex(&c2)
        );
        let cap_sha = sha256_hex(cap.as_bytes());
        std::fs::write(d.join("capture-manifest.tsv"), &cap).unwrap();
        let m = route_manifest(&cap_sha);
        let rc = route_rc(&d);
        let mut receipt = String::new();
        assert!(evidence_route(&m, &rc, limits(), &mut receipt).is_none());
        assert!(receipt.contains("evidence_route\tskipped\treason\tno-dominant-form"), "{receipt}");
    }

    #[test]
    fn route_aggregate_bound_refuses_oversize_population() {
        let (d, cap_sha) = route_fx("aggregate");
        let cap_len = std::fs::metadata(d.join("capture-manifest.tsv")).unwrap().len() as usize;
        let tight = Limits { max_input_bytes: 1 << 20, max_pixels: 1 << 16, max_working_bytes: cap_len };
        let m = route_manifest(&cap_sha);
        let rc = route_rc(&d);
        let mut receipt = String::new();
        assert!(evidence_route(&m, &rc, tight, &mut receipt).is_none());
        assert!(receipt.contains("evidence_route\tskipped\treason\taggregate-bound"), "{receipt}");
    }

    #[test]
    fn route_temp_collision_never_overwrites_existing_file() {
        let (d, cap_sha) = route_fx("collision");
        let sentinel = b"pre-existing custody, never overwritten";
        let occupied = d.join(format!(".k3-scan-evidence-{}-0.tsv", std::process::id()));
        std::fs::write(&occupied, sentinel).unwrap();
        let m = route_manifest(&cap_sha);
        let rc = route_rc(&d);
        let mut receipt = String::new();
        let state = evidence_route(&m, &rc, limits(), &mut receipt);
        assert!(state.is_some(), "route skips the occupied name and confirms: {receipt}");
        assert_eq!(std::fs::read(&occupied).unwrap(), sentinel.to_vec(), "existing file untouched");
        let _ = std::fs::remove_file(&occupied);
    }
    #[test]
    fn gate_rejected_evidence_never_substitutes() {
        let (d, pin) = route_fx("gate-rejected");
        let m = route_manifest(&pin); let rc = route_rc(&d);
        let mut receipt = String::new();
        let state = route_if_missing(&m, &rc, limits(), DetectionState::MissingPixelEvidence, true, &mut receipt);
        assert!(matches!(state, DetectionState::MissingPixelEvidence));
        assert!(receipt.contains("declared-evidence-rejected"));
        assert!(!receipt.contains("confirmed"));
    }

    #[test]
    fn gate_declared_proxy_and_pixel_state_preserved() {
        let (d, pin) = route_fx("gate-proxy");
        let mut m = route_manifest(&pin); let rc = route_rc(&d);
        m.notdef_proxy = Some(("a".repeat(64), 0x41));
        let mut receipt = String::new();
        let state = route_if_missing(&m, &rc, limits(), DetectionState::MissingPixelEvidence, false, &mut receipt);
        assert!(matches!(state, DetectionState::MissingPixelEvidence));
        assert!(receipt.contains("declared-evidence-rejected"));
        m.notdef_proxy = None;
        let mut ignored = String::new();
        let state = route_if_missing(&m, &rc, limits(), proxy(vec![0x41, 0x42]), false, &mut ignored);
        assert!(matches!(state, DetectionState::CandidateProxy { .. }));
        assert!(ignored.is_empty());
        let pixel = evidence_route(&m, &rc, limits(), &mut ignored).unwrap();
        let mut ignored = String::new();
        let state = route_if_missing(&m, &rc, limits(), pixel, false, &mut ignored);
        assert!(matches!(state, DetectionState::PixelEvidence { .. }));
        assert!(ignored.is_empty());
    }

    #[test]
    fn gate_declared_evidence_never_substitutes() {
        let (d, pin) = route_fx("gate-declared");
        let mut m = route_manifest(&pin); let rc = route_rc(&d);
        m.notdef = Some(EvidenceBinding {
            file: d.join("missing-evidence"), sha256: "a".repeat(64),
            style: "Test/Regular".into(), capture: pin, scale: 2.0, frame: "f1".into(),
        });
        let mut receipt = String::new();
        let state = route_if_missing(&m, &rc, limits(), DetectionState::MissingPixelEvidence, false, &mut receipt);
        assert!(matches!(state, DetectionState::MissingPixelEvidence));
        assert!(receipt.contains("declared-evidence-rejected"));
    }

    #[test]
    fn route_no_capture_falls_through_and_missing_capture_is_not_fatal() {
        let (d, pin) = route_fx("gate-no-capture");
        let mut m = route_manifest(&pin); let rc = route_rc(&d);
        m.capture_manifest = None;
        let mut receipt = String::new();
        let state = route_if_missing(&m, &rc, limits(), DetectionState::MissingPixelEvidence, false, &mut receipt);
        assert!(matches!(state, DetectionState::MissingPixelEvidence));
        assert!(receipt.contains("no-capture-manifest"));
    }

}
