//! profiles_par — jobs-aware stage-2 outline-profile computation (W14 PROFILES-PAR).
//!
//! The profile stage (bounded flatten + scan-profile construction, one job per
//! glyph) has no cross-glyph state: every per-glyph input is immutable (the
//! `GlyphRow`, the measurement `DrawnGlyph`, the stage-1 pin map, the run
//! config) and every shared output (the `glyph_skip` receipt rows, the
//! exclusion ledger, the skipped-name set, the profile vector) is written
//! exactly once, in manifest order, by the reduce. This is the profiles
//! analogue of the stage-1 par-fit driver (`stage1_drive`/`stage1_reduce`):
//!
//!   - jobs == 1: inline on the calling thread in manifest order, STOPPING
//!     after the first run-fatal outcome (the old serial early-exit);
//!   - jobs > 1: an explicit rayon pool of exactly `jobs` workers, indexed
//!     range `into_par_iter`, order-preserving collect; all jobs run and the
//!     reduce still picks the first run-fatal in manifest order. A pool that
//!     cannot be built is an error, never a silent serial fallback.
//!
//! Bit-identity contract: for any job count the emitted profile vector, the
//! receipt rows, the exclusion ledger and the post-stage `processed`/`drawn`
//! retain results equal the former serial loop byte for byte (proved by the
//! oracle tests in this module, which keep the old loop verbatim). A panic in
//! one glyph's profile work becomes a typed run-fatal outcome for that glyph
//! instead of tearing the process down from a pool thread (stage-1
//! precedent); the first fatal in manifest order wins.

use std::collections::{BTreeSet, HashMap};

use kni_core::cff_reader::sha256_hex;
use kni_core::flatten_budget;
use kni_core::reference_slice::DrawnGlyph;
use kni_metrics::outline_spacing::{profile_outline_with_exclusions, OutlineInput, OutlineProfile, RingExclusionReason, ScanPolicy};

use crate::fit_bench;
use crate::run_config::{Jobs, RunConfig};
use crate::{declared_convention, drawing_polys, fit_bytes_source_frame_meta, invalid_profile_reason, GlyphRow, PNG_DECODE_LIMITS, PROFILE_RING_SKIP_STAGE, STAGE1_WORKER_STACK_BYTES};

/// What one glyph's profile job concluded. `Fatal` ends the run (source I/O,
/// pin-tamper, bound-H refusal); `Excluded` is a typed per-glyph exclusion
/// (the glyph leaves the solve population with a `glyph_skip` ledger row and
/// the run continues degraded); `Profiled` carries the built profile.
#[derive(Debug)]
pub enum ProfileResult {
    /// Profile, ring-skip receipt rows, and the exact slab geometry of the same flattened rings (stage-4 measurement authority).
    Profiled(OutlineProfile, String, Option<kni_metrics::exact_rows::ExactSlabs>),
    Excluded(String, String),
    Fatal(String, String),
}

/// One glyph's outcome, tagged with its manifest index so the reduce can
/// verify exact 0..n coverage (duplicate, gap or out-of-order is refused).
#[derive(Debug)]
pub struct ProfileOutcome {
    pub idx: usize,
    pub result: ProfileResult,
}

impl ProfileOutcome {
    fn fatal(idx: usize, msg: String) -> ProfileOutcome {
        ProfileOutcome { idx, result: ProfileResult::Fatal(msg, String::new()) }
    }
    fn is_fatal(&self) -> bool {
        matches!(self.result, ProfileResult::Fatal(..))
    }
}

/// One glyph's profile job, verbatim semantics of the former serial loop
/// body: read + pin check (integrity failures are run-fatal), bounded flatten
/// with the budget derived from the glyph's own source tile dimensions
/// (declared bounded-input convention), scan-profile construction, then the
/// pre-solve validation (non-finite or structurally invalid profile, no ink).
/// Per-glyph refusals are typed exclusions; only the bound H of a
/// declared-convention style keeps the old run-fatal semantics. Pure: no
/// shared mutable state, safe on a pool worker.
fn profile_compute(g: &GlyphRow, dg: &DrawnGlyph, stage1_pins: &HashMap<String, String>, rc: &RunConfig, upm: u16) -> ProfileResult {
    // SPEED-1 bench wiring (KNI_FIT_BENCH_OUT): worker-side per-glyph and
    // sub-stage timing. Inactive unless the bench is installed; no engine
    // behavior, ledger or byte change either way.
    let _bench_profile = fit_bench::ProfileGlyphGuard::start(&g.name);
    let bench_part = fit_bench::ProfilePartGuard::start(&g.name, "read_pin");
    let bytes = match fs::read(&g.image) {
        Ok(b) => b,
        Err(e) => return ProfileResult::Fatal(format!("read {}: {e}", g.image.display()), String::new()),
    };
    let pin = sha256_hex(&bytes);
    match stage1_pins.get(&g.name) {
        Some(p1) if *p1 == pin => {}
        Some(p1) => return ProfileResult::Fatal(format!("glyph {}: source PNG changed after stage 1 fit (stage1 pin {p1} != stage2 {pin}); refusing", g.name), String::new()),
        None => return ProfileResult::Fatal(format!("glyph {}: no stage 1 capture pin recorded; refusing", g.name), String::new()),
    }
    drop(bench_part);
    let h_bound = g.codepoint == Some(0x48) && !g.is_ligature() && declared_convention::record_for(rc.scale().id()).is_some();
    let mut ring_rows = String::new();
    let mut exact_out: Option<kni_metrics::exact_rows::ExactSlabs> = None;
    let built: Result<OutlineProfile, String> = (|| {
        let bench_part = fit_bench::ProfilePartGuard::start(&g.name, "flatten");
        let meta = fit_bytes_source_frame_meta(&bytes)?;
        let budget = flatten_budget::max_total_segments(meta.0, meta.1)
            .ok_or_else(|| "flatten budget unavailable".to_string())?;
        let polys = drawing_polys(dg, rc.flatten_tolerance().value(), budget)?;
        drop(bench_part);
        let bench_part = fit_bench::ProfilePartGuard::start(&g.name, "scan_profile");
        let profiled = {
            // Ring-level typed exclusions (always-output contract,
            // MARQ-DEGEN): a degenerate ring leaves with a ring_skip
            // ledger row (stage 2 = profile construction) and the glyph
            // continues on its surviving rings; only a glyph with NO
            // surviving ring drops (typed profile refusal below).
            exact_out = kni_metrics::exact_rows::ExactSlabs::from_rings(&polys).ok();
            let (res, ring_exclusions) = profile_outline_with_exclusions(
                &OutlineInput {
                    glyph_id: g.name.clone(), source_pin: pin, upm,
                    origin: [0.0, 0.0], flatten_tolerance: rc.flatten_tolerance().value(), rings: polys,
                },
                ScanPolicy { row_step: rc.scan_row_step().value(), max_rows: rc.scan_max_rows(), merge_guard: 1.0, grid_anchor_y: Some(0.0) },
            );
            for rx in &ring_exclusions {
                let code = match rx.reason {
                    RingExclusionReason::DegenerateRing { .. } => "degenerate_ring",
                };
                eprintln!("ring_skip glyph {} ({}): ring {} {}", g.name, g.cp_display(), rx.ring, code);
                ring_rows.push_str(&format!("ring_skip\t{}\tcp\t{}\tring\t{}\treason_code\t{}\tstage\t{}\n",
                    g.name, g.cp_display(), rx.ring, code, PROFILE_RING_SKIP_STAGE));
            }
            res.map_err(|e| format!("profile refused: {e:?}"))
        };
        drop(bench_part);
        profiled
    })();
    let prof = match built {
        Ok(prof) => prof,
        Err(reason) => {
            return if h_bound {
                ProfileResult::Fatal(format!("glyph {}: bound H profile stage refused: {reason}", g.name), ring_rows)
            } else {
                ProfileResult::Excluded(reason, ring_rows)
            };
        }
    };
    if let Some(reason) = invalid_profile_reason(&prof) {
        return ProfileResult::Excluded(reason, ring_rows);
    }
    if prof.ink_area <= 0.0 {
        let _bench_part = fit_bench::ProfilePartGuard::start(&g.name, "classify_no_ink");
        // Typed classification (MARQ-DEGEN b): legitimate empty tile vs
        // capture/profile loss. The source bytes are already pinned
        // above; a tile WITH an inked row at the iso scan whose profile
        // carries no ink is the capture/profile-loss class (typed),
        // never a legitimate empty glyph.
        let reason = match kni_core::capture_dispatch::decode_source(&bytes, &PNG_DECODE_LIMITS, kni_core::jpeg_source::Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 }) {
            Ok(decoded) => match crate::scale_wiring::measure_ink_rows(&decoded.gray, decoded.width, decoded.height) {
                Some(_) => "profile has no ink (source tile inked at iso scan: capture/profile loss, typed)".to_string(),
                None => "profile has no ink (source tile carries no inked row at iso scan: legitimate empty, typed)".to_string(),
            },
            Err(e) => format!("profile has no ink (source tile undecodable for classification: {e:?})"),
        };
        return if h_bound {
            ProfileResult::Fatal(format!("glyph {}: bound H profile stage refused: {reason}", g.name), ring_rows)
        } else {
            ProfileResult::Excluded(reason, ring_rows)
        };
    }
    ProfileResult::Profiled(prof, ring_rows, exact_out)
}

use std::fs;

/// Run `profile_compute` so that a panic in the profile work becomes a typed
/// run-fatal outcome for that glyph instead of tearing the process down from
/// a pool thread.
fn guarded(idx: usize, name: &str, f: impl FnOnce() -> ProfileOutcome) -> ProfileOutcome {
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(o) => o,
        Err(p) => {
            let msg = p.downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| p.downcast_ref::<String>().cloned()).unwrap_or_else(|| "non-string panic payload".into());
            ProfileOutcome::fatal(idx, format!("stage-2 profile panicked on glyph {name}: {msg}"))
        }
    }
}

/// Drive `n` indexed profile jobs. jobs == 1: inline on the calling thread in
/// manifest order, STOPPING after the first fatal outcome (the old serial
/// early-exit). jobs > 1: an explicit rayon pool of exactly `jobs` workers,
/// indexed range into_par_iter, order-preserving collect (all jobs run; the
/// reduce still picks the first fatal in manifest order). A pool that cannot
/// be built is an error, never a silent serial fallback.
fn profiles_drive<F: Fn(usize) -> ProfileOutcome + Sync>(n: usize, jobs: Jobs, f: F) -> Result<Vec<ProfileOutcome>, String> {
    use rayon::prelude::*;
    if jobs.get() == 1 {
        let mut v = Vec::with_capacity(n);
        for i in 0..n { let o = f(i); let stop = o.is_fatal(); v.push(o); if stop { break; } }
        return Ok(v);
    }
    let pool = rayon::ThreadPoolBuilder::new().num_threads(jobs.get()).stack_size(STAGE1_WORKER_STACK_BYTES).build()
        .map_err(|e| format!("stage-2 profile worker pool (jobs={}) could not be built: {e}", jobs.get()))?;
    Ok(pool.install(|| (0..n).into_par_iter().map(|i| f(i)).collect()))
}

/// Stage 2 entry point (the single main.rs call site). Computes one outline
/// profile per `processed` glyph at the given job count and folds the
/// outcomes into the run ledgers in manifest order: `glyph_skip` receipt
/// rows, `exclusions`, the skipped-name retain of `processed`/`drawn` and the
/// `glyph_skip_total` receipt row land exactly where the serial loop put
/// them. Returns the solve-population profiles in manifest order.
/// The stage-2 parallel entry point, returning the exact slab geometry of every profiled glyph
/// (same flattened rings the profiles are built from).
pub fn run_profiles_stage_exact(
    processed: &mut Vec<(&GlyphRow, DrawnGlyph)>,
    drawn: &mut Vec<DrawnGlyph>,
    stage1_pins: &HashMap<String, String>,
    rc: &RunConfig,
    upm: u16,
    receipt: &mut String,
    exclusions: &mut Vec<(String, Option<u32>, String)>,
    jobs: Jobs,
) -> Result<(Vec<OutlineProfile>, Vec<String>, kni_metrics::generated_outline_kern::ExactMap), String> {
    let outcomes = profiles_drive(processed.len(), jobs, |i| {
        let (g, dg) = &processed[i];
        guarded(i, &g.name, || ProfileOutcome { idx: i, result: profile_compute(g, dg, stage1_pins, rc, upm) })
    })?;
    let _ = drawn;
    let _ = exclusions;
    profiles_reduce_exact(processed, drawn, outcomes, receipt, exclusions)
}

/// profiles-reduce-seq: fold outcomes in manifest order into the receipt, the
/// exclusion ledger and the skipped-name set. The only place stage-2 shared
/// state is written; the byte layout is exactly what the former in-loop code
/// wrote. The driver returns outcomes already in manifest order (indexed
/// collect); this function VERIFIES that: outcome k must carry idx == k,
/// every index 0..n must be covered exactly once, and the first fatal in
/// manifest order ends the fold with its error. A short list is only valid
/// when its last outcome is that fatal (the jobs=1 early stop).
///
/// This is the reduce plus the exact slab geometry of every profiled glyph (stage-4 measurement authority).
/// The sampled-only 2-tuple wrappers were removed (dead_code zero-warning cleanup); oracle tests map off the third field.
fn profiles_reduce_exact(
    processed: &mut Vec<(&GlyphRow, DrawnGlyph)>,
    drawn: &mut Vec<DrawnGlyph>,
    outcomes: Vec<ProfileOutcome>,
    receipt: &mut String,
    exclusions: &mut Vec<(String, Option<u32>, String)>,
) -> Result<(Vec<OutlineProfile>, Vec<String>, kni_metrics::generated_outline_kern::ExactMap), String> {
    let mut exact_map: kni_metrics::generated_outline_kern::ExactMap = Default::default();
    let _ = drawn;
    let _ = exclusions;
    let mut profiles: Vec<OutlineProfile> = Vec::new();
    // Pre-solve validation exclusions are typed skips (`glyph_skip` receipt
    // row). Always-output: a glyph the profile stage cannot measure leaves
    // the SOLVE population only; it stays in `processed`/`drawn` and ships
    // with a declared fallback advance (see stage2_and_beyond), never dropped
    // from the font. The skipped names return to the caller for that wiring.
    let mut skipped_names: BTreeSet<String> = BTreeSet::new();
    let mut next = 0usize;
    for o in outcomes {
        if o.idx != next { return Err(format!("stage-2 profile reduce: outcome index {} where {} was expected (duplicate, gap or out-of-order)", o.idx, next)); }
        let (g, _) = processed.get(o.idx).map(|(g, d)| (*g, d)).ok_or_else(|| format!("stage-2 profile reduce: outcome index {} outside the {} glyphs", o.idx, processed.len()))?;
        next += 1;
        match o.result {
            ProfileResult::Fatal(msg, ring_rows) => { receipt.push_str(&ring_rows); return Err(msg); }
            ProfileResult::Excluded(reason, ring_rows) => {
                receipt.push_str(&ring_rows);
                eprintln!("excluded glyph {} ({}) from the solve population: {}", g.name, g.cp_display(), reason);
                receipt.push_str(&format!("glyph_skip\t{}\tcp\t{}\treason\t{}\n", g.name, g.cp_display(), reason));
                skipped_names.insert(g.name.clone());
            }
            ProfileResult::Profiled(prof, ring_rows, exact) => {
                receipt.push_str(&ring_rows);
                if let Some(x) = exact { exact_map.insert(prof.glyph_id.clone(), x); }
                profiles.push(prof);
            }
        }
    }
    if next != processed.len() { return Err(format!("stage-2 profile reduce: {} outcomes for {} glyphs (incomplete coverage)", next, processed.len())); }
    if !skipped_names.is_empty() {
        receipt.push_str(&format!("glyph_skip_total\t{}\t(profile invalid before solve; excluded from the solve population)\n", skipped_names.len()));
    }
    Ok((profiles, skipped_names.into_iter().collect(), exact_map))
}

#[cfg(test)]
mod profiles_par_tests {
    use super::*;
    use crate::run_config::{FitErrorPolicy, RunConfig};
    use kni_core::reference_slice::{Point, ReferenceRing, Span};
    use kni_core::scale_context::ScaleContext;
    use std::path::PathBuf;

    // ---- fixture helpers -------------------------------------------------

    fn crc32(data: &[u8]) -> u32 {
        let mut c = 0xFFFF_FFFFu32;
        for &b in data { c ^= b as u32; for _ in 0..8 { c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 }; } }
        !c
    }
    fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], body: &[u8]) {
        out.extend_from_slice(&(body.len() as u32).to_be_bytes());
        let mut c = kind.to_vec(); c.extend_from_slice(body);
        out.extend_from_slice(&c); out.extend_from_slice(&crc32(&c).to_be_bytes());
    }
    /// 8-bit gray PNG, stored (uncompressed) deflate: test fixture encoder only.
    fn png_gray(w: usize, h: usize, px: &[u8]) -> Vec<u8> {
        let mut raw = Vec::new();
        for y in 0..h { raw.push(0); raw.extend_from_slice(&px[y * w..(y + 1) * w]); }
        let mut z = vec![0x78, 0x01];
        let mut it = raw.chunks(65535).peekable();
        while let Some(c) = it.next() {
            z.push(if it.peek().is_none() { 1 } else { 0 });
            z.extend_from_slice(&(c.len() as u16).to_le_bytes()); z.extend_from_slice(&(!(c.len() as u16)).to_le_bytes()); z.extend_from_slice(c);
        }
        let (mut a, mut b) = (1u32, 0u32);
        for &x in &raw { a = (a + x as u32) % 65521; b = (b + a) % 65521; }
        z.extend_from_slice(&((b << 16) | a).to_be_bytes());
        let mut out = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
        let mut ihdr = Vec::new();
        ihdr.extend_from_slice(&(w as u32).to_be_bytes()); ihdr.extend_from_slice(&(h as u32).to_be_bytes()); ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);
        chunk(&mut out, b"IHDR", &ihdr); chunk(&mut out, b"IDAT", &z); chunk(&mut out, b"IEND", &[]);
        out
    }
    /// Glyph i source tile: a filled rect whose size depends on i.
    fn tile(i: usize) -> Vec<u8> {
        let (w, h) = (48usize, 48usize);
        let mut px = vec![255u8; w * h];
        for y in 0..h { for x in 0..w {
            if x >= 8 + (i % 3) && x < 40 - (i % 2) && y >= 6 && y < 42 - (i % 4) { px[y * w + x] = 0; }
        } }
        png_gray(w, h, &px)
    }
    /// Measurement drawing for glyph i: one closed rect ring in font units.
    fn drawn(i: usize) -> DrawnGlyph {
        let (w, h) = (120.0 + 15.0 * i as f64, 300.0 + 20.0 * i as f64);
        let p = |x: f64, y: f64| Point { x, y };
        DrawnGlyph {
            glyph_id: format!("G{i}"),
            rings: vec![ReferenceRing {
                start: p(0.0, 0.0),
                spans: vec![
                    Span::Line { end: p(w, 0.0) },
                    Span::Line { end: p(w, h) },
                    Span::Line { end: p(0.0, h) },
                    Span::Line { end: p(0.0, 0.0) },
                ],
            }],
        }
    }
    fn rc(style_id: &str) -> RunConfig {
        let input = RunConfig::legacy_defaults_input(Some(FitErrorPolicy::Fixed), PathBuf::from("cap"), PathBuf::from("out"), "s1");
        RunConfig::new(input, ScaleContext::from_convention(style_id, "test", 2.0, 1000.0, "cohort", "frame").unwrap()).unwrap()
    }
    /// 8 glyphs (no H: the bound-H wiring is covered by its own unit test);
    /// glyph 5 is a corrupt PNG -> typed exclusion; glyph 6 has an empty
    /// measurement drawing -> typed exclusion (refused profile or no ink).
    fn fixture(tag: &str) -> (Vec<GlyphRow>, HashMap<String, String>, PathBuf) {
        let dir = std::env::temp_dir().join(format!("kni_s2par_{tag}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir); fs::create_dir_all(&dir).unwrap();
        let mut rows = Vec::new();
        let mut pins = HashMap::new();
        for i in 0..8usize {
            let bytes = if i == 5 { b"not a png".to_vec() } else { tile(i) };
            let f = format!("g{i}.png");
            fs::write(dir.join(&f), &bytes).unwrap();
            let name = format!("G{i}");
            pins.insert(name.clone(), sha256_hex(&bytes));
            rows.push(GlyphRow { codepoint: Some(0x41 + i as u32), name, image: dir.join(&f), scale: None, extra_cps: vec![] });
        }
        (rows, pins, dir)
    }
    fn state(rows: &[GlyphRow]) -> (Vec<(&GlyphRow, DrawnGlyph)>, Vec<DrawnGlyph>) {
        let processed: Vec<(&GlyphRow, DrawnGlyph)> = rows.iter().enumerate().map(|(i, g)| {
            let dg = if i == 6 { DrawnGlyph { glyph_id: g.name.clone(), rings: vec![] } } else { drawn(i) };
            (g, dg)
        }).collect();
        let drawn: Vec<DrawnGlyph> = processed.iter().map(|(_, d)| d.clone()).collect();
        (processed, drawn)
    }

    /// OLD serial loop, kept verbatim (from the pre-W14 stage2_and_beyond) as
    /// the oracle: one shared receipt, direct mutation of the run state,
    /// early return on the first fatal.
    fn old_serial_stage2(
        processed: &mut Vec<(&GlyphRow, DrawnGlyph)>,
        drawn: &mut Vec<DrawnGlyph>,
        stage1_pins: &HashMap<String, String>,
        rc: &RunConfig,
        upm: u16,
        receipt: &mut String,
        exclusions: &mut Vec<(String, Option<u32>, String)>,
    ) -> Result<(Vec<OutlineProfile>, Vec<String>), String> {
        let _ = exclusions;
        let mut profiles: Vec<OutlineProfile> = Vec::new();
        let mut skipped_names: std::collections::BTreeSet<String> = std::collections::BTreeSet::new();
        for (g, dg) in processed.iter().map(|(g, d)| (*g, d)) {
            let bytes = fs::read(&g.image).map_err(|e| format!("read {}: {e}", g.image.display()))?;
            let pin = sha256_hex(&bytes);
            match stage1_pins.get(&g.name) {
                Some(p1) if *p1 == pin => {}
                Some(p1) => return Err(format!("glyph {}: source PNG changed after stage 1 fit (stage1 pin {p1} != stage2 {pin}); refusing", g.name)),
                None => return Err(format!("glyph {}: no stage 1 capture pin recorded; refusing", g.name)),
            }
            let h_bound = g.codepoint == Some(0x48) && !g.is_ligature() && declared_convention::record_for(rc.scale().id()).is_some();
            let exclude = |receipt: &mut String, reason: String, skipped: &mut std::collections::BTreeSet<String>| {
                eprintln!("excluded glyph {} ({}) from the solve population: {}", g.name, g.cp_display(), reason);
                receipt.push_str(&format!("glyph_skip\t{}\tcp\t{}\treason\t{}\n", g.name, g.cp_display(), reason));
                skipped.insert(g.name.clone());
            };
            let mut ring_rows = String::new();
            let built: Result<OutlineProfile, String> = (|| {
                let meta = fit_bytes_source_frame_meta(&bytes)?;
                let budget = flatten_budget::max_total_segments(meta.0, meta.1)
                    .ok_or_else(|| "flatten budget unavailable".to_string())?;
                let polys = drawing_polys(dg, rc.flatten_tolerance().value(), budget)?;
                {
                    let (res, ring_exclusions) = profile_outline_with_exclusions(
                        &OutlineInput {
                            glyph_id: g.name.clone(), source_pin: pin, upm,
                            origin: [0.0, 0.0], flatten_tolerance: rc.flatten_tolerance().value(), rings: polys,
                        },
                        ScanPolicy { row_step: rc.scan_row_step().value(), max_rows: rc.scan_max_rows(), merge_guard: 1.0, grid_anchor_y: Some(0.0) },
                    );
                    for rx in &ring_exclusions {
                        let code = match rx.reason {
                            RingExclusionReason::DegenerateRing { .. } => "degenerate_ring",
                        };
                        ring_rows.push_str(&format!("ring_skip\t{}\tcp\t{}\tring\t{}\treason_code\t{}\tstage\t{}\n",
                            g.name, g.cp_display(), rx.ring, code, PROFILE_RING_SKIP_STAGE));
                    }
                    res.map_err(|e| format!("profile refused: {e:?}"))
                }
            })();
            receipt.push_str(&ring_rows);
            let prof = match built {
                Ok(prof) => prof,
                Err(reason) => {
                    if h_bound { return Err(format!("glyph {}: bound H profile stage refused: {reason}", g.name)); }
                    exclude(receipt, reason, &mut skipped_names);
                    continue;
                }
            };
            if let Some(reason) = invalid_profile_reason(&prof) {
                exclude(receipt, reason, &mut skipped_names);
                continue;
            }
            if prof.ink_area <= 0.0 {
                let reason = match kni_core::capture_dispatch::decode_source(&bytes, &PNG_DECODE_LIMITS, kni_core::jpeg_source::Limits { max_input_bytes: 1 << 24, max_pixels: 1 << 24, max_working_bytes: 1 << 26 }) {
                    Ok(decoded) => match crate::scale_wiring::measure_ink_rows(&decoded.gray, decoded.width, decoded.height) {
                        Some(_) => "profile has no ink (source tile inked at iso scan: capture/profile loss, typed)".to_string(),
                        None => "profile has no ink (source tile carries no inked row at iso scan: legitimate empty, typed)".to_string(),
                    },
                    Err(e) => format!("profile has no ink (source tile undecodable for classification: {e:?})"),
                };
                if h_bound { return Err(format!("glyph {}: bound H profile stage refused: {reason}", g.name)); }
                exclude(receipt, reason, &mut skipped_names);
                continue;
            }
            profiles.push(prof);
        }
        let _ = processed;
        let _ = drawn;
        if !skipped_names.is_empty() {
            receipt.push_str(&format!("glyph_skip_total\t{}\t(profile invalid before solve; excluded from the solve population)\n", skipped_names.len()));
        }
        Ok((profiles, skipped_names.into_iter().collect()))
    }

    fn names(processed: &[(&GlyphRow, DrawnGlyph)]) -> Vec<String> {
        processed.iter().map(|(g, _)| g.name.clone()).collect()
    }

    // ---- tests ------------------------------------------------------------

    /// The parallel stage equals the old serial loop byte for byte at every
    /// job count: profile vector (full PartialEq), receipt text, skipped-name
    /// set, post-stage processed/drawn population. Always-output: profile
    /// skips leave the solve population only; every glyph stays shipped.
    #[test]
    fn parallel_profiles_match_the_old_serial_loop_at_jobs_1_2_4_8() {
        let (rows, pins, dir) = fixture("eq");
        let cfg = rc("s1");
        let oracle = {
            let (mut processed, mut drawn) = state(&rows);
            let (mut receipt, mut exclusions) = (String::new(), Vec::new());
            let (profiles, skipped) = old_serial_stage2(&mut processed, &mut drawn, &pins, &cfg, 1000, &mut receipt, &mut exclusions).unwrap();
            assert!(skipped.iter().any(|n| n == "G5"), "corrupt glyph must be a solve-population skip");
            assert!(skipped.iter().any(|n| n == "G6"), "empty-drawing glyph must be a solve-population skip");
            assert!(exclusions.is_empty(), "stage-2 skips no longer enter the stage-1 exclusion ledger");
            assert_eq!(profiles.len(), 6, "6 of 8 glyphs profile");
            assert_eq!(names(&processed).len(), 8, "every glyph stays in the shipped population");
            (profiles, receipt, skipped, names(&processed), drawn.iter().map(|d| d.glyph_id.clone()).collect::<Vec<_>>())
        };
        for jobs in [1usize, 2, 4, 8] {
            let (mut processed, mut drawn) = state(&rows);
            let (mut receipt, mut exclusions) = (String::new(), Vec::new());
            let (profiles, skipped) = run_profiles_stage_exact(&mut processed, &mut drawn, &pins, &cfg, 1000, &mut receipt, &mut exclusions, Jobs::new(jobs).unwrap()).map(|(p, s, _)| (p, s)).unwrap();
            assert_eq!(profiles, oracle.0, "profiles, jobs={jobs}");
            assert_eq!(receipt, oracle.1, "receipt, jobs={jobs}");
            assert_eq!(skipped, oracle.2, "skipped-name set, jobs={jobs}");
            assert_eq!(names(&processed), oracle.3, "processed population, jobs={jobs}");
            assert_eq!(drawn.iter().map(|d| d.glyph_id.clone()).collect::<Vec<_>>(), oracle.4, "drawn population, jobs={jobs}");
        }
        let _ = fs::remove_dir_all(dir);
    }

    /// Integrity failures stay run-fatal with the exact serial message, and
    /// the FIRST fatal in manifest order wins at any job count.
    #[test]
    fn first_fatal_in_manifest_order_wins_at_every_jobs_level() {
        // Glyph 2 loses its stage-1 pin; glyph 5's recorded pin is wrong.
        let (rows, mut pins, dir) = fixture("fatal");
        pins.remove("G2");
        pins.insert("G5".to_string(), "0".repeat(64));
        let cfg = rc("s1");
        let expected = {
            let (mut processed, mut drawn) = state(&rows);
            let (mut receipt, mut exclusions) = (String::new(), Vec::new());
            old_serial_stage2(&mut processed, &mut drawn, &pins, &cfg, 1000, &mut receipt, &mut exclusions).unwrap_err()
        };
        assert!(expected.starts_with("glyph G2: no stage 1 capture pin recorded"), "{expected}");
        for jobs in [1usize, 4] {
            let (mut processed, mut drawn) = state(&rows);
            let (mut receipt, mut exclusions) = (String::new(), Vec::new());
            let e = run_profiles_stage_exact(&mut processed, &mut drawn, &pins, &cfg, 1000, &mut receipt, &mut exclusions, Jobs::new(jobs).unwrap()).map(|(p, s, _)| (p, s)).unwrap_err();
            assert_eq!(e, expected, "fatal message, jobs={jobs}");
        }
        let _ = fs::remove_dir_all(dir);
    }

    /// Bound-H classification is unchanged: on a declared-convention style a
    /// profile-stage refusal of H (0x48) is run-fatal; any other glyph with
    /// the same failure is an ordinary typed exclusion.
    #[test]
    fn bound_h_refusal_is_run_fatal_only_on_declared_convention_styles() {
        let (rows, pins, dir) = fixture("hbound");
        let corrupt = |rows: &[GlyphRow], name: &str| {
            let g = rows.iter().find(|g| g.name == name).unwrap();
            fs::write(&g.image, b"not a png").unwrap();
        };
        // H corrupt on Marq/Alternate (declared record): fatal.
        let mut rows_h: Vec<GlyphRow> = rows.iter().map(|g| GlyphRow { codepoint: g.codepoint, name: g.name.clone(), image: g.image.clone(), scale: g.scale, extra_cps: g.extra_cps.clone() }).collect();
        rows_h[3].codepoint = Some(0x48);
        rows_h[3].name = "H".to_string();
        corrupt(&rows_h, "H");
        let mut pins_h = pins.clone();
        pins_h.remove("G3");
        pins_h.insert("H".to_string(), sha256_hex(b"not a png"));
        let cfg_marq = rc("Marq/Alternate");
        let e = {
            let (mut processed, mut drawn) = state(&rows_h);
            let (mut receipt, mut exclusions) = (String::new(), Vec::new());
            run_profiles_stage_exact(&mut processed, &mut drawn, &pins_h, &cfg_marq, 1000, &mut receipt, &mut exclusions, Jobs::new(2).unwrap()).map(|(p, s, _)| (p, s)).unwrap_err()
        };
        assert!(e.starts_with("glyph H: bound H profile stage refused: "), "{e}");
        // Same failure on a non-record style id: ordinary exclusion.
        let cfg_plain = rc("s1");
        let (mut processed, mut drawn) = state(&rows_h);
        let (mut receipt, mut exclusions) = (String::new(), Vec::new());
        let (profiles, skipped) = run_profiles_stage_exact(&mut processed, &mut drawn, &pins_h, &cfg_plain, 1000, &mut receipt, &mut exclusions, Jobs::new(2).unwrap()).map(|(p, s, _)| (p, s)).unwrap();
        assert!(skipped.iter().any(|n| n == "H"), "H must be a solve-population skip on a non-record style");
        assert_eq!(profiles.len() + skipped.len(), 8);
        let _ = fs::remove_dir_all(dir);
    }

    /// The driver uses the pool for jobs > 1 and runs inline for jobs == 1;
    /// jobs == 1 stops after the first fatal (the old serial early-exit).
    #[test]
    fn pool_is_used_for_jobs_gt_1_and_jobs_1_stops_at_first_fatal() {
        let seen = std::sync::Mutex::new(Vec::<(Option<usize>, usize)>::new());
        let f = |i: usize| { seen.lock().unwrap().push((rayon::current_thread_index(), rayon::current_num_threads())); ProfileOutcome { idx: i, result: ProfileResult::Excluded("x".into(), String::new()) } };
        profiles_drive(6, Jobs::new(4).unwrap(), &f).unwrap();
        { let v = seen.lock().unwrap(); assert_eq!(v.len(), 6); assert!(v.iter().all(|(idx, n)| idx.is_some() && *n == 4), "{v:?}"); }
        seen.lock().unwrap().clear();
        profiles_drive(3, Jobs::new(1).unwrap(), &f).unwrap();
        let v = seen.lock().unwrap(); assert_eq!(v.len(), 3); assert!(v.iter().all(|(idx, _)| idx.is_none()), "jobs=1 runs inline on the caller: {v:?}");
        let calls = std::sync::atomic::AtomicUsize::new(0);
        let f = |i: usize| { calls.fetch_add(1, std::sync::atomic::Ordering::SeqCst); if i == 2 { ProfileOutcome::fatal(i, "boom".into()) } else { ProfileOutcome { idx: i, result: ProfileResult::Excluded("x".into(), String::new()) } } };
        let outs = profiles_drive(8, Jobs::new(1).unwrap(), &f).unwrap();
        assert_eq!(outs.len(), 3, "jobs=1 stops profiling after the first fatal");
        assert_eq!(calls.load(std::sync::atomic::Ordering::SeqCst), 3);
    }

    /// A panic in one glyph's profile work is a typed run-fatal outcome, and
    /// in parallel the first fatal in MANIFEST order wins (a later panic
    /// never masks an earlier refusal).
    #[test]
    fn panic_is_typed_and_first_manifest_order_fatal_wins_in_parallel() {
        let quiet = std::panic::take_hook(); std::panic::set_hook(Box::new(|_| {}));
        let mk = |panic_at: &'static [usize], fatal_at: Option<usize>| move |i: usize| {
            if panic_at.contains(&i) { guarded(i, &format!("G{i}"), || panic!("boom {i}")) }
            else if Some(i) == fatal_at { ProfileOutcome::fatal(i, "earlier refusal".into()) }
            else { ProfileOutcome { idx: i, result: ProfileResult::Excluded("x".into(), String::new()) } }
        };
        let red = |outs: Vec<ProfileOutcome>| {
            let rows: Vec<GlyphRow> = (0..8).map(|i| GlyphRow { codepoint: Some(0x41 + i as u32), name: format!("G{i}"), image: PathBuf::from("unused"), scale: None, extra_cps: vec![] }).collect();
            let mut processed: Vec<(&GlyphRow, DrawnGlyph)> = rows.iter().map(|g| (g, DrawnGlyph { glyph_id: g.name.clone(), rings: vec![] })).collect();
            let mut drawn: Vec<DrawnGlyph> = Vec::new();
            profiles_reduce_exact(&mut processed, &mut drawn, outs, &mut String::new(), &mut Vec::new()).map(|(p, s, _)| (p, s)).unwrap_err()
        };
        // fatal at 2, panics at 5 and 6: the earlier fatal wins.
        let e = red(profiles_drive(8, Jobs::new(4).unwrap(), mk(&[5, 6], Some(2))).unwrap());
        assert_eq!(e, "earlier refusal");
        // panic at 1, fatal at 4: the panic (earlier) wins and is typed.
        let e = red(profiles_drive(8, Jobs::new(4).unwrap(), mk(&[1], Some(4))).unwrap());
        assert_eq!(e, "stage-2 profile panicked on glyph G1: boom 1");
        // jobs=1 gives the same answer as jobs=4.
        assert_eq!(red(profiles_drive(8, Jobs::new(1).unwrap(), mk(&[1], Some(4))).unwrap()), "stage-2 profile panicked on glyph G1: boom 1");
        std::panic::set_hook(quiet);
    }

    /// The reduce refuses malformed outcome lists (duplicate, gap,
    /// out-of-order, over- and under-coverage) instead of folding them.
    #[test]
    fn reduce_validates_index_coverage() {
        let rows: Vec<GlyphRow> = (0..4).map(|i| GlyphRow { codepoint: Some(0x41 + i as u32), name: format!("G{i}"), image: PathBuf::from("unused"), scale: None, extra_cps: vec![] }).collect();
        let red = |ids: Vec<usize>| {
            let mut processed: Vec<(&GlyphRow, DrawnGlyph)> = rows.iter().map(|g| (g, DrawnGlyph { glyph_id: g.name.clone(), rings: vec![] })).collect();
            let mut drawn: Vec<DrawnGlyph> = Vec::new();
            profiles_reduce_exact(&mut processed, &mut drawn, ids.into_iter().map(|idx| ProfileOutcome { idx, result: ProfileResult::Excluded("x".into(), String::new()) }).collect(), &mut String::new(), &mut Vec::new()).map(|(p, s, _)| (p, s))
        };
        assert!(red(vec![0, 1, 2, 3]).is_ok());
        for bad in [vec![0, 1, 1, 3], vec![0, 2, 3], vec![1, 0, 2, 3], vec![0, 1, 2, 3, 4], vec![0, 1, 2], vec![]] {
            assert!(red(bad.clone()).is_err(), "{bad:?}");
        }
    }
}
