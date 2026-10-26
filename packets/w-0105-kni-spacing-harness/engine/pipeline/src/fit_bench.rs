//! fit_bench: per-phase timing harness (parallel-fitting program, piece 18).
//!
//! Env-gated and behavior-neutral: with `KNI_FIT_BENCH_OUT` unset every entry
//! point is a no-op (one relaxed atomic load per call). When it names a path,
//! the recorder collects, for the whole run:
//!   - one wall-clock interval per phase region (`fitting`, `profiles`,
//!     `pairs`, `assembly`), summed per phase name on re-entry;
//!   - one duration row per `process_glyph` call, recorded at the call site so
//!     a future rayon `par_iter` over glyphs measures worker-side durations
//!     with no call-site change (the recorder is global and mutex-guarded);
//!   - total run wall and the run outcome (`ok` | `refused`).
//!
//! `flush()` writes a versioned TSV (`fit_bench_v1`). Every recorder I/O
//! failure degrades to a stderr warning: the bench never changes engine
//! behavior, receipts, refusals, or emitted bytes. Nothing here knows phase
//! names beyond what callers pass; the report tooling (tooling/fit_bench)
//! derives s/glyph and before/after tables from the raw rows.
//!
//! Quality domain (W13): `record_quality_pair` adds labeled `quality` rows -
//! per glyph and per domain (`shipped` outline vs `measurement` drawing):
//! ring/node counts, fallback line spans, missing extrema, ink pixels, and
//! the fit deviation as `lever_api::area_error` (the exact-coverage L1
//! objective vs the threshold-128 mask that the N1 node-economy lever
//! optimizes). This is the measurement domain the fit-objective work (W9)
//! consumes. Row kinds are additive: `fit_bench_v1` readers must skip kinds
//! they do not know (tooling/fit_bench/report.py already does), so the
//! header version is unchanged.
//!
//! Profiles domain (SPEED-1): `ProfileGlyphGuard` / `ProfilePartGuard` add
//! labeled `profile_glyph` and `profile_part` rows - worker-side per-glyph
//! stage-2 profile-job durations and per-glyph sub-stage spans (`read_pin`,
//! `flatten`, `scan_profile`, `classify_no_ink`), with `profile_glyphs` /
//! `profile_glyph_cpu_sum_s` count and sum rows and `profile_part_total`
//! sums in first-entry order. These rows attribute the parallel `profiles`
//! phase (W14): per-glyph cpu-sum vs the phase wall clock exposes pool
//! efficiency, and the part totals name the dominant sub-stage. Stage-2
//! rows stay distinct from the stage-1 `glyph` fit rows so the
//! fit-objective tooling (W9) never mixes stage-2 time into stage-1 fit
//! seconds. Row kinds are additive: `fit_bench_v1` readers must skip kinds
//! they do not know, so the header version is unchanged.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Output path env var. Set to enable; unset/empty = fully disabled.
pub const ENV_OUT: &str = "KNI_FIT_BENCH_OUT";

/// One per-glyph fit-quality sample. Every value is measured from the
/// drawing against the exact source mask it was fitted on; nothing is
/// defaulted. `domain` labels which drawing was measured: `shipped` (the
/// outline that lands in the font) or `measurement` (the accepted-domain
/// drawing profiles/spacing/vertical metrics are computed from, when the
/// shipped outline is traced from the band-cleared source).
#[derive(Clone, Debug)]
pub struct QualitySample {
    pub name: String,
    pub domain: &'static str,
    pub rings: usize,
    pub nodes: usize,
    pub fallback_line_spans: usize,
    pub final_missing_extrema: usize,
    pub ink_px: u64,
    /// Exact-coverage L1 deviation vs the threshold-128 source mask, font
    /// units^2 (`lever_api::area_error` - the N1 lever's own objective).
    pub area_err_units2: f64,
}

static ENABLED: AtomicBool = AtomicBool::new(false);
static STATE: Mutex<Option<(Recorder, String)>> = Mutex::new(None);

/// Phase/glyph accumulator. Pure value type: all methods take explicit
/// timestamps so the unit tests drive a synthetic clock. The global wrappers
/// below are thin `Instant::now()` shells over this type.
pub struct Recorder {
    start: Instant,
    open_phase: Option<(String, Instant)>,
    phases: Vec<(String, Duration)>,
    glyphs: Vec<(String, Duration)>,
    profile_glyphs: Vec<(String, Duration)>,
    profile_parts: Vec<(String, &'static str, Duration)>,
    quality: Vec<QualitySample>,
}

impl Recorder {
    pub fn new(start: Instant) -> Self {
        Recorder { start, open_phase: None, phases: Vec::new(), glyphs: Vec::new(), profile_glyphs: Vec::new(), profile_parts: Vec::new(), quality: Vec::new() }
    }

    /// Open a phase interval. Phases never nest in this program; if one is
    /// still open it is closed at `now` first (defensive, keeps the books
    /// closed instead of dropping time on the floor).
    pub fn phase_enter_at(&mut self, name: &str, now: Instant) {
        self.phase_close_at(now);
        self.open_phase = Some((name.to_string(), now));
    }

    /// Close the open phase interval at `now`, if any.
    pub fn phase_close_at(&mut self, now: Instant) {
        if let Some((name, t0)) = self.open_phase.take() {
            self.phases.push((name, now.saturating_duration_since(t0)));
        }
    }

    /// Record one finished glyph fit.
    pub fn glyph_record(&mut self, name: &str, d: Duration) {
        self.glyphs.push((name.to_string(), d));
    }

    /// Record one finished stage-2 profile job (worker-side duration).
    pub fn profile_glyph_record(&mut self, name: &str, d: Duration) {
        self.profile_glyphs.push((name.to_string(), d));
    }

    /// Record one finished stage-2 sub-stage interval for a glyph.
    pub fn profile_part_record(&mut self, name: &str, part: &'static str, d: Duration) {
        self.profile_parts.push((name.to_string(), part, d));
    }

    /// Record one fit-quality sample.
    pub fn quality_record(&mut self, sample: QualitySample) {
        self.quality.push(sample);
    }

    /// Phase totals in first-entry order.
    fn phase_totals(&self) -> Vec<(String, Duration)> {
        let mut order: Vec<String> = Vec::new();
        let mut sums: Vec<Duration> = Vec::new();
        for (name, d) in &self.phases {
            match order.iter().position(|n| n == name) {
                Some(i) => sums[i] += *d,
                None => { order.push(name.clone()); sums.push(*d); }
            }
        }
        order.into_iter().zip(sums).collect()
    }

    /// Profile sub-stage totals in first-entry order.
    fn profile_part_totals(&self) -> Vec<(&'static str, Duration)> {
        let mut order: Vec<&'static str> = Vec::new();
        let mut sums: Vec<Duration> = Vec::new();
        for (_, part, d) in &self.profile_parts {
            match order.iter().position(|p| p == part) {
                Some(i) => sums[i] += *d,
                None => { order.push(part); sums.push(*d); }
            }
        }
        order.into_iter().zip(sums).collect()
    }

    /// Render the versioned TSV. Any still-open phase is closed at `now` so
    /// an early-return run still books its partial phase time; the row count
    /// `phases_interrupted` (emitted only when nonzero) flags that case.
    pub fn render(&self, outcome: &str, now: Instant, created_unix: u64) -> String {
        let mut r = Recorder {
            start: self.start,
            open_phase: self.open_phase.clone(),
            phases: self.phases.clone(),
            glyphs: self.glyphs.clone(),
            profile_glyphs: self.profile_glyphs.clone(),
            profile_parts: self.profile_parts.clone(),
            quality: self.quality.clone(),
        };
        let interrupted = r.open_phase.is_some();
        r.phase_close_at(now);
        let total = now.saturating_duration_since(r.start);
        let mut s = String::from("fit_bench_v1\n");
        s.push_str(&format!("created_unix\t{created_unix}\n"));
        s.push_str(&format!("outcome\t{}\n", cell(outcome)));
        s.push_str(&format!("total_s\t{:.6}\n", secs(total)));
        for (name, d) in r.phase_totals() {
            s.push_str(&format!("phase\t{}\t{:.6}\n", cell(&name), secs(d)));
        }
        if interrupted {
            s.push_str("phases_interrupted\t1\n");
        }
        let glyph_sum: Duration = r.glyphs.iter().map(|(_, d)| *d).sum();
        s.push_str(&format!("glyphs\t{}\n", r.glyphs.len()));
        s.push_str(&format!("glyph_cpu_sum_s\t{:.6}\n", secs(glyph_sum)));
        let mut rows = r.glyphs.clone();
        rows.sort_by(|a, b| a.0.cmp(&b.0));
        for (name, d) in rows {
            s.push_str(&format!("glyph\t{}\t{:.6}\n", cell(&name), secs(d)));
        }
        if !r.profile_glyphs.is_empty() {
            let psum: Duration = r.profile_glyphs.iter().map(|(_, d)| *d).sum();
            s.push_str(&format!("profile_glyphs\t{}\n", r.profile_glyphs.len()));
            s.push_str(&format!("profile_glyph_cpu_sum_s\t{:.6}\n", secs(psum)));
            let mut prows = r.profile_glyphs.clone();
            prows.sort_by(|a, b| a.0.cmp(&b.0));
            for (name, d) in prows {
                s.push_str(&format!("profile_glyph\t{}\t{:.6}\n", cell(&name), secs(d)));
            }
        }
        if !r.profile_parts.is_empty() {
            for (part, d) in r.profile_part_totals() {
                s.push_str(&format!("profile_part_total\t{}\t{:.6}\n", part, secs(d)));
            }
            let mut pparts = r.profile_parts.clone();
            pparts.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(b.1)));
            for (name, part, d) in pparts {
                s.push_str(&format!("profile_part\t{}\t{}\t{:.6}\n", cell(&name), part, secs(d)));
            }
        }
        if !r.quality.is_empty() {
            s.push_str(&format!("quality_glyphs\t{}\n", r.quality.len()));
            let mut qrows = r.quality.clone();
            qrows.sort_by(|a, b| a.name.cmp(&b.name).then(a.domain.cmp(b.domain)));
            for q in qrows {
                s.push_str(&format!(
                    "quality\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{:.6}\n",
                    cell(&q.name), q.domain, q.rings, q.nodes,
                    q.fallback_line_spans, q.final_missing_extrema, q.ink_px,
                    q.area_err_units2));
            }
        }
        s
    }
}

fn secs(d: Duration) -> f64 {
    d.as_secs() as f64 + f64::from(d.subsec_nanos()) / 1e9
}

/// TSV cell safety: glyph names are engine-side identifiers, but a stray
/// tab/newline would corrupt row shape for the report tooling.
fn cell(v: &str) -> String {
    v.replace(['\t', '\n', '\r'], " ")
}

/// Install the global recorder from `KNI_FIT_BENCH_OUT`. Unset or empty
/// leaves the bench disabled; an unreadable target path is NOT detected here
/// (writes happen once at flush and degrade to a stderr warning there).
pub fn install_from_env() {
    let path = std::env::var(ENV_OUT).unwrap_or_default();
    if path.is_empty() {
        return;
    }
    if let Ok(mut slot) = STATE.lock() {
        *slot = Some((Recorder::new(Instant::now()), path));
        ENABLED.store(true, Ordering::Relaxed);
    }
}

/// RAII phase guard: closes its phase on drop, so `?` early returns still
/// book the interval. No-op when disabled.
pub struct PhaseGuard {
    active: bool,
}

impl PhaseGuard {
    pub fn enter(name: &str) -> Self {
        if !ENABLED.load(Ordering::Relaxed) {
            return PhaseGuard { active: false };
        }
        if let Ok(mut slot) = STATE.lock() {
            if let Some((rec, _)) = slot.as_mut() {
                rec.phase_enter_at(name, Instant::now());
            }
        }
        PhaseGuard { active: true }
    }
}

impl Drop for PhaseGuard {
    fn drop(&mut self) {
        if !self.active {
            return;
        }
        if let Ok(mut slot) = STATE.lock() {
            if let Some((rec, _)) = slot.as_mut() {
                rec.phase_close_at(Instant::now());
            }
        }
    }
}

/// RAII per-glyph timer: records the fit duration on drop (success AND
/// exclusion paths). Safe to start on rayon workers: the only shared state
/// is the mutex-guarded recorder. No-op when disabled.
pub struct GlyphGuard {
    name: String,
    t0: Instant,
    active: bool,
}

impl GlyphGuard {
    pub fn start(name: &str) -> Self {
        if !ENABLED.load(Ordering::Relaxed) {
            return GlyphGuard { name: String::new(), t0: Instant::now(), active: false };
        }
        GlyphGuard { name: name.to_string(), t0: Instant::now(), active: true }
    }
}

impl Drop for GlyphGuard {
    fn drop(&mut self) {
        if !self.active {
            return;
        }
        if let Ok(mut slot) = STATE.lock() {
            if let Some((rec, _)) = slot.as_mut() {
                rec.glyph_record(&self.name, self.t0.elapsed());
            }
        }
    }
}

/// RAII per-glyph stage-2 profile timer: records the profile-job duration on
/// drop (success AND exclusion paths) under the `profile_glyph` row kind,
/// kept distinct from the stage-1 `glyph` fit rows so fit-objective tooling
/// never mixes stage-2 time into stage-1 fit seconds. Safe to start on rayon
/// workers: the only shared state is the mutex-guarded recorder. No-op when
/// disabled.
pub struct ProfileGlyphGuard {
    name: String,
    t0: Instant,
    active: bool,
}

impl ProfileGlyphGuard {
    pub fn start(name: &str) -> Self {
        if !ENABLED.load(Ordering::Relaxed) {
            return ProfileGlyphGuard { name: String::new(), t0: Instant::now(), active: false };
        }
        ProfileGlyphGuard { name: name.to_string(), t0: Instant::now(), active: true }
    }
}

impl Drop for ProfileGlyphGuard {
    fn drop(&mut self) {
        if !self.active {
            return;
        }
        if let Ok(mut slot) = STATE.lock() {
            if let Some((rec, _)) = slot.as_mut() {
                rec.profile_glyph_record(&self.name, self.t0.elapsed());
            }
        }
    }
}

/// RAII stage-2 sub-stage timer: records one named sub-stage interval of a
/// glyph's profile job on drop under the `profile_part` row kind. `part` is
/// an engine-side label (`read_pin`, `flatten`, `scan_profile`,
/// `classify_no_ink`); a sub-stage that is never entered emits no row, and a
/// glyph that exits mid-sub-stage books the partial interval. Safe on rayon
/// workers. No-op when disabled.
pub struct ProfilePartGuard {
    name: String,
    part: &'static str,
    t0: Instant,
    active: bool,
}

impl ProfilePartGuard {
    pub fn start(name: &str, part: &'static str) -> Self {
        if !ENABLED.load(Ordering::Relaxed) {
            return ProfilePartGuard { name: String::new(), part, t0: Instant::now(), active: false };
        }
        ProfilePartGuard { name: name.to_string(), part, t0: Instant::now(), active: true }
    }
}

impl Drop for ProfilePartGuard {
    fn drop(&mut self) {
        if !self.active {
            return;
        }
        if let Ok(mut slot) = STATE.lock() {
            if let Some((rec, _)) = slot.as_mut() {
                rec.profile_part_record(&self.name, self.part, self.t0.elapsed());
            }
        }
    }
}

/// Write the TSV to the installed path. Called once from `main` after `run`
/// returns, with the run outcome. Refuses to overwrite an existing file (the
/// engine's own no-overwrite convention); any failure is a stderr warning,
/// never a run failure.
pub fn flush(outcome: &str) {
    if !ENABLED.load(Ordering::Relaxed) {
        return;
    }
    let rendered = if let Ok(mut slot) = STATE.lock() {
        slot.take().map(|(rec, path)| {
            let created = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_secs())
                .unwrap_or(0);
            (rec.render(outcome, Instant::now(), created), path)
        })
    } else {
        None
    };
    ENABLED.store(false, Ordering::Relaxed);
    let Some((text, path)) = rendered else { return };
    match std::fs::OpenOptions::new().write(true).create_new(true).open(&path) {
        Ok(mut f) => {
            use std::io::Write;
            if let Err(e) = f.write_all(text.as_bytes()) {
                eprintln!("fit_bench: write {} refused: {e}", path);
            }
        }
        Err(e) => eprintln!("fit_bench: open {} refused: {e}", path),
    }
}


// ---------- W13 quality domain: the fit-objective measurement surface ----------

/// Measure one drawing against the exact source mask it was fitted on.
/// The mask frame replicates the engine's own construction for source-frame
/// rings (`generated_draw_frame`: origin `(-origin_x * scale, 0.0)`), so the
/// deviation is computed in the same frame the fit stages optimize.
/// Returns None when no honest sample exists (dimension mismatch, invalid
/// mask, flatten budget exceeded, non-finite objective); a None is a skipped
/// row, never a run failure.
pub fn sample_quality(
    name: &str,
    domain: &'static str,
    drawing: &kni_core::generated_draw_frame::GeneratedDrawing,
    contour: &kni_core::capture::MeasuredContour,
    gray: &[u8],
    scale: f64,
) -> Option<QualitySample> {
    if contour.width.checked_mul(contour.height) != Some(gray.len()) {
        return None;
    }
    let mask = kni_core::lever_api::SourceMask {
        w: contour.width,
        h: contour.height,
        ink: gray.to_vec(),
        scale,
        origin: (-contour.origin_x * scale, 0.0),
    };
    if !mask.valid() {
        return None;
    }
    let budget = kni_core::flatten_budget::max_total_segments(mask.w, mask.h)?;
    if kni_core::flatten_budget::check_flatten_budget(&drawing.rings, &mask, budget).is_err() {
        return None;
    }
    let area_err = kni_core::lever_api::area_error(&drawing.rings, &mask);
    if !area_err.is_finite() {
        return None;
    }
    let mut ink_px: u64 = 0;
    for j in 0..mask.h {
        for i in 0..mask.w {
            if mask.is_ink(i, j) {
                ink_px += 1;
            }
        }
    }
    Some(QualitySample {
        name: name.to_string(),
        domain,
        rings: drawing.rings.len(),
        nodes: drawing.rings.iter().map(|r| r.spans.len()).sum(),
        fallback_line_spans: drawing.fallback_line_spans,
        final_missing_extrema: drawing.final_missing_extrema,
        ink_px,
        area_err_units2: area_err,
    })
}

/// Record the quality pair for one finished glyph: the shipped outline when
/// the band-cleared outline fit exists (domain `shipped`), and the base
/// drawing (domain `measurement` when an outline was shipped, else
/// `shipped` - in that case the base drawing IS the shipped outline).
/// No-op when the bench is disabled. A sample that cannot be computed is a
/// stderr warning and a skipped row, never a run failure.
pub fn record_quality_pair(
    name: &str,
    base: &kni_core::generated_draw_frame::GeneratedDrawing,
    outline: &Option<kni_core::generated_draw_frame::GeneratedDrawing>,
    src: &kni_core::capture_dispatch::CapturedSource,
    scale: f64,
) {
    if !ENABLED.load(Ordering::Relaxed) {
        return;
    }
    let mut samples: Vec<QualitySample> = Vec::new();
    match outline {
        Some(o) => {
            match (&src.outline_contour, &src.outline_gray) {
                (Some(c), Some(g)) => match sample_quality(name, "shipped", o, c, g, scale) {
                    Some(s) => samples.push(s),
                    None => eprintln!("fit_bench: quality sample skipped for {name} (shipped): mask or objective not computable"),
                },
                _ => eprintln!("fit_bench: quality sample skipped for {name} (shipped): outline source missing"),
            }
            match sample_quality(name, "measurement", base, &src.contour, &src.gray, scale) {
                Some(s) => samples.push(s),
                None => eprintln!("fit_bench: quality sample skipped for {name} (measurement): mask or objective not computable"),
            }
        }
        None => match sample_quality(name, "shipped", base, &src.contour, &src.gray, scale) {
            Some(s) => samples.push(s),
            None => eprintln!("fit_bench: quality sample skipped for {name} (shipped): mask or objective not computable"),
        },
    }
    if samples.is_empty() {
        return;
    }
    if let Ok(mut slot) = STATE.lock() {
        if let Some((rec, _)) = slot.as_mut() {
            for s in samples {
                rec.quality_record(s);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t0() -> Instant { Instant::now() }
    fn at(base: Instant, ms: u64) -> Instant { base + Duration::from_millis(ms) }

    #[test]
    fn phase_intervals_sum_on_reentry_in_first_entry_order() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.phase_enter_at("fitting", at(b, 0));
        r.phase_close_at(at(b, 100));
        r.phase_enter_at("pairs", at(b, 100));
        r.phase_close_at(at(b, 150));
        r.phase_enter_at("fitting", at(b, 200));
        r.phase_close_at(at(b, 350));
        let totals = r.phase_totals();
        assert_eq!(totals.len(), 2);
        assert_eq!(totals[0], ("fitting".to_string(), Duration::from_millis(250)));
        assert_eq!(totals[1], ("pairs".to_string(), Duration::from_millis(50)));
    }

    #[test]
    fn entering_a_phase_closes_the_previous_one() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.phase_enter_at("profiles", at(b, 0));
        r.phase_enter_at("pairs", at(b, 80));
        r.phase_close_at(at(b, 100));
        let totals = r.phase_totals();
        assert_eq!(totals[0], ("profiles".to_string(), Duration::from_millis(80)));
        assert_eq!(totals[1], ("pairs".to_string(), Duration::from_millis(20)));
    }

    #[test]
    fn render_is_golden_and_glyph_rows_sort_by_name() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.phase_enter_at("fitting", at(b, 0));
        r.phase_close_at(at(b, 1000));
        r.glyph_record("b", Duration::from_millis(700));
        r.glyph_record("A", Duration::from_millis(250));
        let s = r.render("ok", at(b, 1200), 42);
        let expected = "fit_bench_v1\n\
            created_unix\t42\n\
            outcome\tok\n\
            total_s\t1.200000\n\
            phase\tfitting\t1.000000\n\
            glyphs\t2\n\
            glyph_cpu_sum_s\t0.950000\n\
            glyph\tA\t0.250000\n\
            glyph\tb\t0.700000\n";
        assert_eq!(s, expected);
    }

    #[test]
    fn open_phase_at_render_is_closed_and_flagged() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.phase_enter_at("fitting", at(b, 0));
        let s = r.render("refused", at(b, 500), 1);
        assert!(s.contains("phase\tfitting\t0.500000\n"), "{s}");
        assert!(s.contains("phases_interrupted\t1\n"), "{s}");
        assert!(s.contains("outcome\trefused\n"), "{s}");
    }

    #[test]
    fn tsv_cells_are_sanitized() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.glyph_record("a\tb\nc", Duration::from_millis(1));
        let s = r.render("ok", at(b, 1), 0);
        assert!(s.contains("glyph\ta b c\t0.001000\n"), "{s}");
    }

    #[test]
    fn empty_run_renders_zero_rows() {
        let b = t0();
        let r = Recorder::new(b);
        let s = r.render("refused", at(b, 3), 7);
        assert!(s.contains("glyphs\t0\n"), "{s}");
        assert!(s.contains("glyph_cpu_sum_s\t0.000000\n"), "{s}");
        assert!(!s.contains("phases_interrupted"), "{s}");
        assert_eq!(s.lines().count(), 6);
    }

    fn quality_sample(name: &str, domain: &'static str, nodes: usize) -> QualitySample {
        QualitySample { name: name.into(), domain, rings: 1, nodes,
            fallback_line_spans: 0, final_missing_extrema: 0, ink_px: 36, area_err_units2: 0.0 }
    }

    #[test]
    fn quality_rows_render_sorted_by_name_then_domain() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.quality_record(QualitySample { domain: "shipped", ..quality_sample("b", "shipped", 9) });
        r.quality_record(QualitySample { domain: "measurement", fallback_line_spans: 2, ..quality_sample("A", "measurement", 21) });
        r.quality_record(QualitySample { area_err_units2: 1.5, ..quality_sample("A", "shipped", 16) });
        let s = r.render("ok", at(b, 10), 7);
        let expected_tail = "quality_glyphs\t3\n\
            quality\tA\tmeasurement\t1\t21\t2\t0\t36\t0.000000\n\
            quality\tA\tshipped\t1\t16\t0\t0\t36\t1.500000\n\
            quality\tb\tshipped\t1\t9\t0\t0\t36\t0.000000\n";
        assert!(s.ends_with(expected_tail), "{s}");
        assert!(s.contains("glyphs\t0\n"), "{s}");
    }

    #[test]
    fn quality_row_cells_are_sanitized() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.quality_record(quality_sample("a\tb\nc", "shipped", 4));
        let s = r.render("ok", at(b, 1), 0);
        assert!(s.contains("quality\ta b c\tshipped\t1\t4\t0\t0\t36\t0.000000\n"), "{s}");
    }

    // Synthetic source: 12x12 gray, ink block pixels [3..9) x [3..9) (the
    // route-test square). scale = 1 unit/px, origin (0, 0): pixel (i, j) is
    // covered by the font-space rectangle x in [3, 9], y in [-9, -3].
    fn square_contour() -> kni_core::capture::MeasuredContour {
        kni_core::capture::MeasuredContour { width: 12, height: 12, rings: Vec::new(), origin_x: 0.0, origin_y: 0.0 }
    }
    fn square_gray() -> Vec<u8> {
        let mut gray = vec![255u8; 144];
        for y in 3..9 { for x in 3..9 { gray[y * 12 + x] = 0; } }
        gray
    }
    fn rect_drawing(x0: f64, y0: f64, x1: f64, y1: f64) -> kni_core::generated_draw_frame::GeneratedDrawing {
        use kni_core::reference_slice::{Point, ReferenceRing, Span};
        let pt = |x, y| Point { x, y };
        let ring = ReferenceRing { start: pt(x0, y0), spans: vec![
            Span::Line { end: pt(x1, y0) }, Span::Line { end: pt(x1, y1) },
            Span::Line { end: pt(x0, y1) }, Span::Line { end: pt(x0, y0) }] };
        kni_core::generated_draw_frame::GeneratedDrawing {
            rings: vec![ring], baseline: Vec::new(), reports: Vec::new(), refused: Vec::new(),
            baseline_area: 0.0, final_area: 0.0, baseline_missing_extrema: 0, final_missing_extrema: 0,
            source_fit_spans: 0, fallback: false, dropped: 0, fallback_line_spans: 0,
            sub_grid_floor: 0, ambiguous_stubs: 0, ambig_declined: 0, fallback_provenance: Vec::new() }
    }

    #[test]
    fn sample_quality_exact_cover_rectangle_measures_zero_error() {
        let d = rect_drawing(3.0, -3.0, 9.0, -9.0);
        let q = sample_quality("sq", "shipped", &d, &square_contour(), &square_gray(), 1.0)
            .expect("honest sample must exist");
        assert_eq!(q.nodes, 4);
        assert_eq!(q.rings, 1);
        assert_eq!(q.ink_px, 36);
        assert!(q.area_err_units2.abs() < 1e-9, "{}", q.area_err_units2);
    }

    #[test]
    fn sample_quality_shifted_rectangle_measures_the_strip() {
        // One-pixel shift right: the 1x6 strip [9,10) x [3,9) is covered but
        // not ink, the strip [3,4) x [3,9) is ink but not covered.
        let d = rect_drawing(4.0, -3.0, 10.0, -9.0);
        let q = sample_quality("sq", "shipped", &d, &square_contour(), &square_gray(), 1.0)
            .expect("honest sample must exist");
        assert!((q.area_err_units2 - 12.0).abs() < 1e-9, "{}", q.area_err_units2);
    }

    #[test]
    fn sample_quality_scale_converts_pixel_error_to_font_units() {
        // Same one-pixel shift at scale 2 units/px: the ring must be drawn in
        // font units (pixel * scale) to cover the same region.
        let d = rect_drawing(8.0, -6.0, 20.0, -18.0);
        let q = sample_quality("sq", "shipped", &d, &square_contour(), &square_gray(), 2.0)
            .expect("honest sample must exist");
        // 12 px of error area * scale^2 = 48 units^2.
        assert!((q.area_err_units2 - 48.0).abs() < 1e-9, "{}", q.area_err_units2);
    }

    #[test]
    fn sample_quality_refuses_dimension_mismatch_and_bad_scale() {
        let d = rect_drawing(3.0, -3.0, 9.0, -9.0);
        assert!(sample_quality("sq", "shipped", &d, &square_contour(), &square_gray()[..100], 1.0).is_none());
        assert!(sample_quality("sq", "shipped", &d, &square_contour(), &square_gray(), 0.0).is_none());
        assert!(sample_quality("sq", "shipped", &d, &square_contour(), &square_gray(), f64::NAN).is_none());
    }

    #[test]
    fn record_quality_pair_is_a_noop_when_disabled() {
        // The global recorder is not installed in this test binary, so the
        // entry point must do nothing (and must not panic on a real drawing).
        let d = rect_drawing(3.0, -3.0, 9.0, -9.0);
        let src = kni_core::capture_dispatch::CapturedSource {
            contour: square_contour(), gray: square_gray(),
            receipt: kni_core::capture_dispatch::SourceReceipt {
                source_kind: kni_core::capture_dispatch::SourceKind::PngConvertedGrayWhiteAlpha,
                jpeg_identity: None, frame_band_measured: ((0, 0, 0, 0), 0), frame_band_evidence: kni_core::capture_dispatch::FrameBandEvidence::NoSignal,
                width: 12, height: 12, decoder_limits: None, png_limits: None },
            outline_contour: None, outline_gray: None };
        record_quality_pair("sq", &d, &None, &src, 1.0);
    }

    #[test]
    fn profile_glyph_rows_render_sorted_with_count_and_cpu_sum() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.profile_glyph_record("b", Duration::from_millis(700));
        r.profile_glyph_record("A", Duration::from_millis(250));
        let s = r.render("ok", at(b, 1200), 42);
        let expected_tail = "profile_glyphs\t2\n\
            profile_glyph_cpu_sum_s\t0.950000\n\
            profile_glyph\tA\t0.250000\n\
            profile_glyph\tb\t0.700000\n";
        assert!(s.ends_with(expected_tail), "{s}");
        // The stage-1 glyph section is untouched when no fit rows exist.
        assert!(s.contains("glyphs\t0\n"), "{s}");
    }

    #[test]
    fn profile_part_rows_render_totals_first_entry_order_then_sorted_rows() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.profile_part_record("b", "read_pin", Duration::from_millis(10));
        r.profile_part_record("A", "read_pin", Duration::from_millis(20));
        r.profile_part_record("A", "flatten", Duration::from_millis(5));
        r.profile_part_record("b", "scan_profile", Duration::from_millis(100));
        let s = r.render("ok", at(b, 200), 7);
        let expected_tail = "profile_part_total\tread_pin\t0.030000\n\
            profile_part_total\tflatten\t0.005000\n\
            profile_part_total\tscan_profile\t0.100000\n\
            profile_part\tA\tflatten\t0.005000\n\
            profile_part\tA\tread_pin\t0.020000\n\
            profile_part\tb\tread_pin\t0.010000\n\
            profile_part\tb\tscan_profile\t0.100000\n";
        assert!(s.ends_with(expected_tail), "{s}");
    }

    #[test]
    fn profile_rows_are_absent_when_none_recorded() {
        let b = t0();
        let r = Recorder::new(b);
        let s = r.render("refused", at(b, 3), 7);
        assert!(!s.contains("profile_glyph"), "{s}");
        assert!(!s.contains("profile_part"), "{s}");
        assert_eq!(s.lines().count(), 6);
    }

    #[test]
    fn profile_glyph_row_cells_are_sanitized() {
        let b = t0();
        let mut r = Recorder::new(b);
        r.profile_glyph_record("a\tb\nc", Duration::from_millis(1));
        let s = r.render("ok", at(b, 1), 0);
        assert!(s.contains("profile_glyph\ta b c\t0.001000\n"), "{s}");
    }
}
