//! Fixture-runner for the `iou_report` contract. It loads an explicit manifest,
//! measures jobs from `core/tests/fixtures`, and writes TSV, receipt-summary and
//! numeric-summary outputs. It has no pass/fail threshold.
use kni_core::capture::{capture_png, decode_png_gray};
use kni_core::cubic_fit::FitPolicy;
use kni_core::economy_eval::{sha256_hex, EvalConfig, RenderLimits};
use kni_core::iou_adapter::evidence_from_eval;
use kni_core::iou_report::{
    build_report, run_jobs, Exclusion, IouError, IouJob, OutlineStage, ResourceLimits, SourceInput,
};
use kni_core::reference_slice::DrawnGlyph;
use std::collections::BTreeSet;
use std::path::PathBuf;

#[derive(Clone, Debug)]
struct JobSpec {
    glyph: String,
    source: PathBuf,
    sha256: String,
}
#[derive(Clone, Debug)]
struct Spec {
    style: String,
    frame_id: String,
    scale_k: f64,
    capture_eps: f64,
    fit_squared_error: f64,
    fit_max_refits: usize,
    advance: u16,
    ink_threshold: Option<u8>,
    flatten_steps: Option<usize>,
    max_pixels: u64,
    max_edges: u64,
    max_png_bytes: u64,
    max_png_working_bytes: u64,
    jobs: Vec<JobSpec>,
    exclusions: Vec<Exclusion>,
}

fn need<'a>(
    mut it: impl Iterator<Item = &'a str>,
    what: &str,
    line: usize,
) -> Result<&'a str, String> {
    it.next()
        .ok_or_else(|| format!("manifest line {line}: missing {what}"))
}
fn no_extra<'a>(
    mut it: impl Iterator<Item = &'a str>,
    what: &str,
    line: usize,
) -> Result<(), String> {
    if it.next().is_some() {
        Err(format!("manifest line {line}: extra {what} field"))
    } else {
        Ok(())
    }
}
fn parse_spec(text: &str) -> Result<Spec, String> {
    let mut style = None;
    let mut frame_id = None;
    let mut scale_k = None;
    let mut capture_eps = None;
    let mut fit_squared_error = None;
    let mut fit_max_refits = None;
    let mut advance = None;
    let mut ink_threshold = None;
    let mut flatten_steps = None;
    let mut max_pixels = None;
    let mut max_edges = None;
    let mut max_png_bytes = None;
    let mut max_png_working_bytes = None;
    let mut jobs = Vec::new();
    let mut exclusions = Vec::new();
    let mut expected = BTreeSet::new();
    for (i, raw) in text.lines().enumerate() {
        let line_no = i + 1;
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut it = line.split_whitespace();
        match it.next().unwrap() {
            "style" => {
                style = Some(need(it.by_ref(), "style", line_no)?.to_string());
                no_extra(it, "style", line_no)?;
            }
            "frame_id" => {
                frame_id = Some(need(it.by_ref(), "frame_id", line_no)?.to_string());
                no_extra(it, "frame_id", line_no)?;
            }
            "scale_k" => {
                scale_k = Some(
                    need(it.by_ref(), "scale_k", line_no)?
                        .parse::<f64>()
                        .map_err(|_| format!("manifest line {line_no}: bad scale_k"))?,
                );
                no_extra(it, "scale_k", line_no)?;
            }
            "capture_eps" => {
                capture_eps = Some(
                    need(it.by_ref(), "capture_eps", line_no)?
                        .parse::<f64>()
                        .map_err(|_| format!("manifest line {line_no}: bad capture_eps"))?,
                );
                no_extra(it, "capture_eps", line_no)?;
            }
            "fit_squared_error" => {
                fit_squared_error = Some(
                    need(it.by_ref(), "fit_squared_error", line_no)?
                        .parse::<f64>()
                        .map_err(|_| format!("manifest line {line_no}: bad fit_squared_error"))?,
                );
                no_extra(it, "fit_squared_error", line_no)?;
            }
            "fit_max_refits" => {
                fit_max_refits = Some(
                    need(it.by_ref(), "fit_max_refits", line_no)?
                        .parse::<usize>()
                        .map_err(|_| format!("manifest line {line_no}: bad fit_max_refits"))?,
                );
                no_extra(it, "fit_max_refits", line_no)?;
            }
            "advance" => {
                advance = Some(
                    need(it.by_ref(), "advance", line_no)?
                        .parse::<u16>()
                        .map_err(|_| format!("manifest line {line_no}: bad advance"))?,
                );
                no_extra(it, "advance", line_no)?;
            }
            "iou_ink_threshold" => {
                ink_threshold = Some(
                    need(it.by_ref(), "iou_ink_threshold", line_no)?
                        .parse::<u8>()
                        .map_err(|_| format!("manifest line {line_no}: bad iou_ink_threshold"))?,
                );
                no_extra(it, "iou_ink_threshold", line_no)?;
            }
            "iou_flatten_steps" => {
                flatten_steps = Some(
                    need(it.by_ref(), "iou_flatten_steps", line_no)?
                        .parse::<usize>()
                        .map_err(|_| format!("manifest line {line_no}: bad iou_flatten_steps"))?,
                );
                no_extra(it, "iou_flatten_steps", line_no)?;
            }
            "max_pixels" => {
                max_pixels = Some(
                    need(it.by_ref(), "max_pixels", line_no)?
                        .parse::<u64>()
                        .map_err(|_| format!("manifest line {line_no}: bad max_pixels"))?,
                );
                no_extra(it, "max_pixels", line_no)?;
            }
            "max_edges" => {
                max_edges = Some(
                    need(it.by_ref(), "max_edges", line_no)?
                        .parse::<u64>()
                        .map_err(|_| format!("manifest line {line_no}: bad max_edges"))?,
                );
                no_extra(it, "max_edges", line_no)?;
            }
            "max_png_bytes" => {
                max_png_bytes = Some(
                    need(it.by_ref(), "max_png_bytes", line_no)?
                        .parse::<u64>()
                        .map_err(|_| format!("manifest line {line_no}: bad max_png_bytes"))?,
                );
                no_extra(it, "max_png_bytes", line_no)?;
            }
            "max_png_working_bytes" => {
                max_png_working_bytes = Some(
                    need(it.by_ref(), "max_png_working_bytes", line_no)?
                        .parse::<u64>()
                        .map_err(|_| {
                            format!("manifest line {line_no}: bad max_png_working_bytes")
                        })?,
                );
                no_extra(it, "max_png_working_bytes", line_no)?;
            }
            "job" => {
                let glyph = need(it.by_ref(), "glyph", line_no)?.to_string();
                let source = PathBuf::from(need(it.by_ref(), "source", line_no)?);
                let sha256 = need(it.by_ref(), "source sha256", line_no)?.to_string();
                no_extra(it, "job", line_no)?;
                expected.insert((glyph.clone(), "job"));
                jobs.push(JobSpec {
                    glyph,
                    source,
                    sha256,
                });
            }
            "exclude" => {
                let glyph = need(it.by_ref(), "glyph", line_no)?.to_string();
                let reason = it.collect::<Vec<_>>().join(" ");
                if reason.is_empty() {
                    return Err(format!("manifest line {line_no}: missing exclusion reason"));
                }
                expected.insert((glyph.clone(), "exclude"));
                exclusions.push(Exclusion {
                    style: String::new(),
                    glyph_id: glyph,
                    reason,
                });
            }
            other => return Err(format!("manifest line {line_no}: unknown key {other:?}")),
        }
    }
    let (
        Some(style),
        Some(frame_id),
        Some(scale_k),
        Some(capture_eps),
        Some(fit_squared_error),
        Some(fit_max_refits),
        Some(advance),
        Some(max_pixels),
        Some(max_edges),
        Some(max_png_bytes),
        Some(max_png_working_bytes),
    ) = (
        style,
        frame_id,
        scale_k,
        capture_eps,
        fit_squared_error,
        fit_max_refits,
        advance,
        max_pixels,
        max_edges,
        max_png_bytes,
        max_png_working_bytes,
    )
    else {
        return Err("manifest: missing required scalar key".into());
    };
    if style.is_empty() {
        return Err("manifest: empty style".into());
    }
    if !(scale_k.is_finite() && scale_k > 0.0) {
        return Err("manifest: bad scale_k".into());
    }
    if !(capture_eps.is_finite() && capture_eps > 0.0) {
        return Err("manifest: bad capture_eps".into());
    }
    if !(fit_squared_error.is_finite() && fit_squared_error > 0.0) {
        return Err("manifest: bad fit_squared_error".into());
    }
    match (ink_threshold, flatten_steps) {
        (Some(_), Some(_)) => {}
        (None, None) => {
            return Err("manifest: iou_ink_threshold and iou_flatten_steps are required".into())
        }
        _ => {
            return Err(
                "manifest: iou_ink_threshold and iou_flatten_steps must be declared together"
                    .into(),
            )
        }
    }
    if jobs.is_empty() && exclusions.is_empty() {
        return Err("manifest: no jobs or exclusions".into());
    }
    for e in &mut exclusions {
        e.style = style.clone();
    }
    Ok(Spec {
        style,
        frame_id,
        scale_k,
        capture_eps,
        fit_squared_error,
        fit_max_refits,
        advance,
        ink_threshold,
        flatten_steps,
        max_pixels,
        max_edges,
        max_png_bytes,
        max_png_working_bytes,
        jobs,
        exclusions,
    })
}

fn opt(v: Option<f64>) -> String {
    v.map_or("null".into(), |x| format!("{x:.9}"))
}
fn usage() -> String {
    "usage: iou_fixture_report --manifest MANIFEST --fixture-root DIR --tsv OUT --summary OUT --numbers OUT [--workers N]".into()
}

fn run() -> Result<(), String> {
    let mut manifest = None;
    let mut fixture_root = None;
    let mut tsv = None;
    let mut summary = None;
    let mut numbers = None;
    let mut workers = Some(1usize);
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let mut value = |name: &str| {
            args.next()
                .ok_or_else(|| format!("missing value for {name}"))
        };
        match a.as_str() {
            "--manifest" => manifest = Some(PathBuf::from(value("--manifest")?)),
            "--fixture-root" => fixture_root = Some(PathBuf::from(value("--fixture-root")?)),
            "--tsv" => tsv = Some(PathBuf::from(value("--tsv")?)),
            "--summary" => summary = Some(PathBuf::from(value("--summary")?)),
            "--numbers" => numbers = Some(PathBuf::from(value("--numbers")?)),
            "--workers" => {
                workers = Some(
                    value("--workers")?
                        .parse::<usize>()
                        .map_err(|_| "bad --workers".to_string())?,
                )
            }
            "--help" | "-h" => {
                println!("{}", usage());
                return Ok(());
            }
            other => return Err(format!("unknown argument {other:?}; {}", usage())),
        }
    }
    let (Some(manifest), Some(fixture_root), Some(tsv), Some(summary), Some(numbers)) =
        (manifest, fixture_root, tsv, summary, numbers)
    else {
        return Err(usage());
    };
    let spec = parse_spec(
        &std::fs::read_to_string(&manifest).map_err(|e| format!("read manifest: {e}"))?,
    )?;
    let ink_threshold = spec.ink_threshold.unwrap();
    let flatten_steps = spec.flatten_steps.unwrap();
    let mut jobs = Vec::new();
    let mut expected = Vec::new();
    let mut expected_seen = BTreeSet::new();
    for job in &spec.jobs {
        if expected_seen.insert(job.glyph.clone()) {
            expected.push((spec.style.clone(), job.glyph.clone()));
        }
        let path = fixture_root.join(&job.source);
        let png = std::fs::read(&path).map_err(|e| {
            IouError::SourceRead {
                glyph: job.glyph.clone(),
                detail: format!("{}: {e}", path.display()),
            }
            .to_string()
        });
        let built = (|| -> Result<IouJob, IouError> {
            let png = png.map_err(|detail| IouError::SourceRead {
                glyph: job.glyph.clone(),
                detail,
            })?;
            let now = sha256_hex(&png);
            if now != job.sha256 {
                return Err(IouError::SourcePinMismatch {
                    glyph: job.glyph.clone(),
                    stage1_pin: job.sha256.clone(),
                    now,
                });
            }
            let (w, h, _) = decode_png_gray(&png).map_err(|detail| IouError::SourceDecode {
                glyph: job.glyph.clone(),
                detail,
            })?;
            let render_limits = RenderLimits {
                max_pixels: usize::try_from(spec.max_pixels).map_err(|_| {
                    IouError::ResourceLimitExceeded {
                        glyph: job.glyph.clone(),
                        what: "max_pixels".into(),
                        value: spec.max_pixels,
                        limit: usize::MAX as u64,
                    }
                })?,
                max_flatten_steps: flatten_steps,
                max_edges: usize::try_from(spec.max_edges).map_err(|_| {
                    IouError::ResourceLimitExceeded {
                        glyph: job.glyph.clone(),
                        what: "max_edges".into(),
                        value: spec.max_edges,
                        limit: usize::MAX as u64,
                    }
                })?,
                max_working_bytes: usize::try_from(spec.max_png_working_bytes).map_err(|_| {
                    IouError::ResourceLimitExceeded {
                        glyph: job.glyph.clone(),
                        what: "max_png_working_bytes".into(),
                        value: spec.max_png_working_bytes,
                        limit: usize::MAX as u64,
                    }
                })?,
            };
            let cfg = EvalConfig {
                frame_id: spec.frame_id.clone(),
                scale_k: spec.scale_k,
                threshold: ink_threshold,
                canvas: (w, h),
                capture_eps: spec.capture_eps,
                flatten_steps,
                expected_source_sha256: job.sha256.clone(),
                advance: spec.advance,
                render_limits,
            };
            let measured =
                capture_png(&png, spec.capture_eps).map_err(|detail| IouError::SourceDecode {
                    glyph: job.glyph.clone(),
                    detail,
                })?;
            let policy = FitPolicy {
                squared_error: spec.fit_squared_error,
                max_refits: spec.fit_max_refits,
            };
            let (rings, ..) =
                kni_core::capture_fit::fit_captured(&measured.rings, spec.scale_k, &policy);
            let outline = if rings.is_empty() {
                Err(IouError::EmptyOutline {
                    glyph: job.glyph.clone(),
                })
            } else {
                Ok(DrawnGlyph {
                    glyph_id: job.glyph.clone(),
                    rings,
                })
            };
            let limits = ResourceLimits {
                max_pixels: spec.max_pixels,
                max_flatten_steps: flatten_steps,
                max_edges: spec.max_edges,
                max_png_bytes: spec.max_png_bytes,
                max_png_working_bytes: spec.max_png_working_bytes,
            };
            let evidence = evidence_from_eval(
                &cfg,
                (measured.origin_x, measured.origin_y),
                (0.0, 0.0),
                limits,
            );
            Ok(IouJob {
                style: spec.style.clone(),
                glyph_id: job.glyph.clone(),
                source: SourceInput::Png(png),
                outline,
                evidence,
                stage: OutlineStage::PreEmit,
            })
        })();
        jobs.push(match built {
            Ok(j) => j,
            Err(error) => {
                let limits = ResourceLimits {
                    max_pixels: spec.max_pixels,
                    max_flatten_steps: flatten_steps,
                    max_edges: spec.max_edges,
                    max_png_bytes: spec.max_png_bytes,
                    max_png_working_bytes: spec.max_png_working_bytes,
                };
                IouJob {
                    style: spec.style.clone(),
                    glyph_id: job.glyph.clone(),
                    source: SourceInput::Gray {
                        w: 0,
                        h: 0,
                        gray: Vec::new(),
                    },
                    outline: Err(error),
                    evidence: kni_core::iou_report::FrameEvidence {
                        scale_k: Some(spec.scale_k),
                        origin: Some((0.0, 0.0)),
                        ink_threshold: Some(ink_threshold),
                        flatten_steps: Some(flatten_steps),
                        canvas: Some((0, 0)),
                        translation: Some((0.0, 0.0)),
                        limits: Some(limits),
                    },
                    stage: OutlineStage::PreEmit,
                }
            }
        });
    }
    for e in &spec.exclusions {
        if expected_seen.insert(e.glyph_id.clone()) {
            expected.push((spec.style.clone(), e.glyph_id.clone()));
        }
    }
    let exclusion_count = spec.exclusions.len();
    let out = run_jobs(&jobs, workers);
    let duplicate_count = out.duplicates.len();
    let report = build_report(&expected, out.rows, spec.exclusions, out.duplicates, None)
        .map_err(|e| format!("inventory refused: {e}"))?;
    std::fs::write(&tsv, report.to_tsv()).map_err(|e| format!("write {}: {e}", tsv.display()))?;
    std::fs::write(&summary, report.to_receipt())
        .map_err(|e| format!("write {}: {e}", summary.display()))?;
    let o = report.overall();
    let json = format!("{{\n  \"expected_total\": {},\n  \"rows\": {},\n  \"excluded_rows\": {},\n  \"duplicate_job_diagnostics\": {},\n  \"overall\": {{\n    \"total\": {},\n    \"measured\": {},\n    \"failed\": {},\n    \"excluded\": {},\n    \"mean\": {},\n    \"median\": {},\n    \"min\": {},\n    \"target\": null,\n    \"below_target\": null\n  }}\n}}\n", expected.len(), report.rows().len(), exclusion_count, duplicate_count, o.total, o.measured, o.failed, o.excluded, opt(o.mean), opt(o.median), opt(o.min));
    std::fs::write(&numbers, json).map_err(|e| format!("write {}: {e}", numbers.display()))?;
    println!("iou_fixture_report expected={} rows={} excluded={} duplicate_job_diagnostics={} measured={} failed={}", expected.len(), report.rows().len(), exclusion_count, duplicate_count, o.measured, o.failed);
    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("iou_fixture_report\tERROR\t{e}");
        std::process::exit(1);
    }
}
