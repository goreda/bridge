//! Run-path audit (work-list item 10): complete provenance, trace and
//! consumer diagnostics over the artifacts a run path leaves in its out
//! dir. Detection only: the audit measures the directory after the writers
//! ran. It never mutates, gates or refuses a run artifact, and it never
//! edits the receipt - the audit is written last and stands as a sibling
//! record.
//!
//! Three kinds of fact stay in separate columns, never merged:
//! - identity: run pins (population sha, family, subfamily, postscript
//!   name, style id, run path, emitter) plus the artifact name and its
//!   writer stage (the trace dimension);
//! - read state: a typed per-artifact state (written / written_probe /
//!   conditional_absent / expected_absent / not_run / self_referential);
//! - counts: data rows and byte length, `not_measured` when the artifact
//!   kind carries no row count.
//!
//! Formal-approach rule (owner, 2026-10-18 16:09): no language-, glyph- or
//! style-specific settings or code. Artifact names here are engine-internal
//! constants; the two style-derived file names (the receipt and the OTF)
//! come from the run config's style id, never from a literal style name.
//!
//! Boundary: a run that fails before its manifest parses cannot build a
//! run identity; that path's record is run-failure-receipt.txt (single
//! writer: run_failure.rs), not this audit.

use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::path::Path;

/// File name of the audit artifact inside the run's out dir.
pub const RUN_AUDIT_FILENAME: &str = "run-audit.tsv";
/// Emitter tag for the identity block. Bumped only on a layout change.
pub const EMITTER: &str = "kni-pipeline-run-audit-v1";

/// Which run path the audit closes. The path decides which writer stages
/// were reachable; artifacts of an unreachable stage are `not_run`, never
/// `expected_absent`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RunPath {
    /// Manifest run_mode=stage1_only: run control and stage 1 only.
    Stage1Only,
    /// Stage 1 retained zero glyphs: the population floor ships a minimal
    /// OTF; stages past encode-emit never ran.
    PopulationFloor,
    /// The full chain: stage 1, profiles, spacing, kern gate, encode/emit.
    Full,
}

impl RunPath {
    pub fn tag(self) -> &'static str {
        match self {
            Self::Stage1Only => "stage1_only",
            Self::PopulationFloor => "population_floor",
            Self::Full => "full",
        }
    }

    fn reaches(self, stage: Stage) -> bool {
        match self {
            Self::Stage1Only => matches!(stage, Stage::RunControl | Stage::Stage1Capture | Stage::Observer),
            Self::PopulationFloor => matches!(stage, Stage::RunControl | Stage::Stage1Capture | Stage::EncodeEmit),
            Self::Full => true,
        }
    }
}

/// Writer stage: the trace dimension of every artifact row.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Stage {
    RunControl,
    Stage1Capture,
    Stage2Profiles,
    Stage3Spacing,
    KernGate,
    EncodeEmit,
    Observer,
}

impl Stage {
    pub fn tag(self) -> &'static str {
        match self {
            Self::RunControl => "run_control",
            Self::Stage1Capture => "stage1_capture",
            Self::Stage2Profiles => "stage2_profiles",
            Self::Stage3Spacing => "stage3_spacing",
            Self::KernGate => "kern_gate",
            Self::EncodeEmit => "encode_emit",
            Self::Observer => "observer",
        }
    }
}

/// Whether the writer always emits the artifact when its stage runs.
/// `Probe` artifacts are always written but are probe-grade diagnostics,
/// marked so a consumer never mistakes them for production records.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Conditionality {
    Always,
    Conditional,
    Probe,
}

/// Artifact name: an engine-internal literal, or derived from the run
/// config's style id (receipt and OTF names are style-id functions, not
/// literals - see run_config::RunConfig::{receipt_file_name, otf_file_name}).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NameRef {
    Literal(&'static str),
    StyleDerived { prefix: &'static str, suffix: &'static str },
}

impl NameRef {
    fn resolve(self, style_id: &str) -> String {
        match self {
            Self::Literal(n) => n.to_string(),
            Self::StyleDerived { prefix, suffix } => format!("{prefix}{style_id}{suffix}"),
        }
    }
}

/// One registry entry: an artifact the current run paths can write.
#[derive(Clone, Copy, Debug)]
pub struct ArtifactSpec {
    pub name: NameRef,
    pub stage: Stage,
    pub conditionality: Conditionality,
}

use Conditionality::{Always, Conditional, Probe};
use NameRef::{Literal, StyleDerived};
use Stage::{EncodeEmit, KernGate, Observer, RunControl, Stage1Capture, Stage2Profiles, Stage3Spacing};

/// The artifact registry of the current run paths. Coverage is guarded by
/// the `registry_covers_every_main_rs_out_dir_write` test: a new
/// `out_dir.join("...")` write in main.rs that is not registered (or
/// declared exempt there) fails the suite.
static REGISTRY: &[ArtifactSpec] = &[
    ArtifactSpec { name: Literal("pair_visual_report.tsv"), stage: Stage::RunControl, conditionality: Conditional },
    ArtifactSpec { name: Literal("pair_visual_report.pin.tsv"), stage: Stage::RunControl, conditionality: Conditional },
    ArtifactSpec { name: Literal("receipt.txt"), stage: RunControl, conditionality: Conditional },
    ArtifactSpec { name: Literal("run-failure-receipt.txt"), stage: RunControl, conditionality: Conditional },
    ArtifactSpec { name: StyleDerived { prefix: "receipt-", suffix: ".txt" }, stage: RunControl, conditionality: Always },
    ArtifactSpec { name: Literal("stage1-cache.txt"), stage: Stage1Capture, conditionality: Always },
    ArtifactSpec { name: Literal("line-audit.tsv"), stage: Stage1Capture, conditionality: Always },
    ArtifactSpec { name: Literal("corner-wiring.tsv"), stage: Stage1Capture, conditionality: Conditional },
    ArtifactSpec { name: Literal("fallback-glyphs.tsv"), stage: Stage1Capture, conditionality: Conditional },
    ArtifactSpec { name: Literal("fallback-audit.tsv"), stage: Stage1Capture, conditionality: Conditional },
    ArtifactSpec { name: Literal("profile-metadata.tsv"), stage: Stage2Profiles, conditionality: Probe },
    ArtifactSpec { name: Literal("run-provenance.tsv"), stage: Stage2Profiles, conditionality: Probe },
    ArtifactSpec { name: Literal("anchor-audit-signs.tsv"), stage: Stage3Spacing, conditionality: Always },
    ArtifactSpec { name: Literal("anchor-audit-flags.tsv"), stage: Stage3Spacing, conditionality: Always },
    ArtifactSpec { name: Literal("spacing.tsv"), stage: Stage3Spacing, conditionality: Always },
    ArtifactSpec { name: Literal("export-gate-pairs.tsv"), stage: Stage3Spacing, conditionality: Always },
    ArtifactSpec { name: Literal("spacing-pair-ledger.tsv"), stage: Stage3Spacing, conditionality: Always },
    ArtifactSpec { name: Literal("spacing-hold-reasons.txt"), stage: Stage3Spacing, conditionality: Always },
    ArtifactSpec { name: Literal("kern-ledger.tsv"), stage: KernGate, conditionality: Always },
    ArtifactSpec { name: Literal("kern-diagnostic.tsv"), stage: KernGate, conditionality: Always },
    ArtifactSpec { name: Literal("kern-hold-summary.tsv"), stage: KernGate, conditionality: Always },
    ArtifactSpec { name: Literal("kern-hold-flags.tsv"), stage: KernGate, conditionality: Always },
    ArtifactSpec { name: Literal("rounding-ledger.txt"), stage: KernGate, conditionality: Always },
    ArtifactSpec { name: StyleDerived { prefix: "font-", suffix: ".otf.provenance.json" }, stage: EncodeEmit, conditionality: Conditional },
    ArtifactSpec { name: StyleDerived { prefix: "font-", suffix: ".otf" }, stage: EncodeEmit, conditionality: Always },
    ArtifactSpec { name: StyleDerived { prefix: "font-", suffix: ".glyphs" }, stage: EncodeEmit, conditionality: Always },
    ArtifactSpec { name: Literal("mapping.tsv"), stage: EncodeEmit, conditionality: Always },
    ArtifactSpec { name: Literal("encode-closure-audit.tsv"), stage: EncodeEmit, conditionality: Always },
    ArtifactSpec { name: Literal("post_metrics_ledger.tsv"), stage: EncodeEmit, conditionality: Conditional },
    ArtifactSpec { name: Literal("iou.tsv"), stage: EncodeEmit, conditionality: Conditional },
    ArtifactSpec { name: Literal("iou-population.tsv"), stage: EncodeEmit, conditionality: Conditional },
    ArtifactSpec { name: Literal("floor.otf"), stage: EncodeEmit, conditionality: Conditional },
    ArtifactSpec { name: Literal("merge-visibility-mov1.jsonl"), stage: Observer, conditionality: Conditional },
];

/// The full registry. The audit row for the audit file itself is appended
/// by the collector as `self_referential`.
pub fn registry() -> &'static [ArtifactSpec] {
    REGISTRY
}

/// Typed read state of one artifact. Identity and counts live in their own
/// columns; this column carries state only.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ArtifactState {
    /// Reachable, written by the run.
    Written,
    /// Reachable, written by the run, probe-grade (never a production record).
    ProbeWritten,
    /// Reachable, conditional, and the condition did not fire.
    ConditionalAbsent,
    /// Reachable, expected always written, and missing: the anomaly signal
    /// a consumer needs. Detection only; nothing is repaired here.
    ExpectedAbsent,
    /// The run path never reached the writer stage.
    NotRun,
    /// The audit file itself: it cannot honestly measure its own bytes.
    SelfReferential,
}

impl ArtifactState {
    pub fn tag(self) -> &'static str {
        match self {
            Self::Written => "written",
            Self::ProbeWritten => "written_probe",
            Self::ConditionalAbsent => "conditional_absent",
            Self::ExpectedAbsent => "expected_absent",
            Self::NotRun => "not_run",
            Self::SelfReferential => "self_referential",
        }
    }

    fn from_tag(tag: &str) -> Option<Self> {
        Some(match tag {
            "written" => Self::Written,
            "written_probe" => Self::ProbeWritten,
            "conditional_absent" => Self::ConditionalAbsent,
            "expected_absent" => Self::ExpectedAbsent,
            "not_run" => Self::NotRun,
            "self_referential" => Self::SelfReferential,
            _ => return None,
        })
    }
}

/// Run identity pins. Identity only: no counts, no state.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RunIdentity {
    pub population_sha256: String,
    pub family: String,
    pub subfamily: String,
    pub postscript_name: String,
    pub style_id: String,
    pub emitter: String,
}

/// Collapse tab/newline so one field stays one field (same discipline as
/// run_failure receipt details). Data, never an invention.
fn clean(v: &str) -> String {
    v.replace(['\t', '\n', '\r'], " ")
}

/// One audit row: identity columns (artifact, writer stage), the typed
/// state column, and the count columns (rows, bytes).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ArtifactRow {
    pub artifact: String,
    pub stage: Stage,
    pub state: ArtifactState,
    /// Data rows for .tsv artifacts (comment and header lines excluded);
    /// None = not_measured (artifact kind carries no row count, or the
    /// artifact is absent).
    pub rows: Option<usize>,
    pub bytes: Option<u64>,
}

/// Count data rows of a .tsv artifact: non-empty, non-comment lines minus
/// the single header line. Saturates at zero for a header-only file.
fn tsv_data_rows(path: &Path) -> Result<usize, String> {
    let f = fs::File::open(path).map_err(|e| format!("audit measure {}: {e}", path.display()))?;
    let content_lines = BufReader::new(f)
        .lines()
        .map_while(Result::ok)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .count();
    Ok(content_lines.saturating_sub(1))
}

/// Measure the out dir against the registry for one run path. Pure
/// measurement: presence, byte length and .tsv data-row counts; no value is
/// recomputed from run internals.
pub fn collect_run_audit(out_dir: &Path, identity: &RunIdentity, path: RunPath) -> Result<Vec<ArtifactRow>, String> {
    let mut rows = Vec::with_capacity(registry().len() + 1);
    for spec in registry() {
        let name = spec.name.resolve(&identity.style_id);
        let file = out_dir.join(&name);
        let state = if !path.reaches(spec.stage) {
            ArtifactState::NotRun
        } else if file.is_file() {
            match spec.conditionality {
                Probe => ArtifactState::ProbeWritten,
                _ => ArtifactState::Written,
            }
        } else {
            match spec.conditionality {
                Conditional => ArtifactState::ConditionalAbsent,
                _ => ArtifactState::ExpectedAbsent,
            }
        };
        let (rows_count, bytes) = match state {
            ArtifactState::Written | ArtifactState::ProbeWritten => {
                let len = fs::metadata(&file).map_err(|e| format!("audit measure {}: {e}", file.display()))?.len();
                let r = if name.ends_with(".tsv") { Some(tsv_data_rows(&file)?) } else { None };
                (r, Some(len))
            }
            _ => (None, None),
        };
        rows.push(ArtifactRow { artifact: name, stage: spec.stage, state, rows: rows_count, bytes });
    }
    // Self row last in collection order; the renderer sorts by stage/name.
    rows.push(ArtifactRow {
        artifact: RUN_AUDIT_FILENAME.to_string(),
        stage: Stage::RunControl,
        state: ArtifactState::SelfReferential,
        rows: None,
        bytes: None,
    });
    rows.sort_by(|a, b| (a.stage, &a.artifact).cmp(&(b.stage, &b.artifact)));
    Ok(rows)
}

/// The always-written audit artifact: an identity block (identity only),
/// then typed rows. Rendering only: no value is recomputed here.
pub fn render_run_audit_tsv(identity: &RunIdentity, path: RunPath, rows: &[ArtifactRow]) -> String {
    let mut out = String::new();
    out.push_str("# run-audit-v1: run-path artifact audit (detection only; written last; never mutates or refuses run artifacts)\n");
    out.push_str(&format!("# identity\tpopulation_sha256\t{}\n", clean(&identity.population_sha256)));
    out.push_str(&format!("# identity\tfamily\t{}\n", clean(&identity.family)));
    out.push_str(&format!("# identity\tsubfamily\t{}\n", clean(&identity.subfamily)));
    out.push_str(&format!("# identity\tpostscript_name\t{}\n", clean(&identity.postscript_name)));
    out.push_str(&format!("# identity\tstyle_id\t{}\n", clean(&identity.style_id)));
    out.push_str(&format!("# identity\trun_path\t{}\n", path.tag()));
    out.push_str(&format!("# identity\temitter\t{}\n", clean(&identity.emitter)));
    let count = |v: Option<usize>| v.map(|n| n.to_string()).unwrap_or_else(|| "not_measured".to_string());
    let bytes = |v: Option<u64>| v.map(|n| n.to_string()).unwrap_or_else(|| "not_measured".to_string());
    out.push_str("artifact\twriter_stage\tstate\trows\tbytes\n");
    for r in rows {
        out.push_str(&format!("{}\t{}\t{}\t{}\t{}\n", clean(&r.artifact), r.stage.tag(), r.state.tag(), count(r.rows), bytes(r.bytes)));
    }
    out
}

/// Counts of one written audit, for the caller's own diagnostics. The audit
/// never edits the receipt; these counts are returned, not appended.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct AuditSummary {
    pub artifacts: usize,
    pub written: usize,
    pub probe_written: usize,
    pub conditional_absent: usize,
    pub expected_absent: usize,
    pub not_run: usize,
}

/// Write the audit into the run's out dir. Create-new semantics: an
/// existing run-audit.tsv is never overwritten (one attempt per out dir,
/// the engine's own rule). The audit file itself carries the
/// self_referential row.
pub fn write_run_audit(out_dir: &Path, identity: &RunIdentity, path: RunPath) -> Result<AuditSummary, String> {
    let rows = collect_run_audit(out_dir, identity, path)?;
    let text = render_run_audit_tsv(identity, path, &rows);
    let file = out_dir.join(RUN_AUDIT_FILENAME);
    fs::create_dir_all(out_dir).map_err(|e| format!("run audit create out dir: {e}"))?;
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&file)
        .and_then(|mut f| f.write_all(text.as_bytes()))
        .map_err(|e| format!("run audit write {}: {e}", file.display()))?;
    let mut s = AuditSummary { artifacts: rows.len(), ..AuditSummary::default() };
    for r in &rows {
        match r.state {
            ArtifactState::Written => s.written += 1,
            ArtifactState::ProbeWritten => s.probe_written += 1,
            ArtifactState::ConditionalAbsent => s.conditional_absent += 1,
            ArtifactState::ExpectedAbsent => s.expected_absent += 1,
            ArtifactState::NotRun => s.not_run += 1,
            ArtifactState::SelfReferential => {}
        }
    }
    Ok(s)
}

// ---------- consumer side: closure check of an audit against a run dir ----------

/// Typed consumer-side mismatch. Verification is a ledger, never a refusal:
/// every finding is a row with the audit's claim and the measured actual.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AuditMismatch {
    /// Audit row claims written (or probe) but the file is absent.
    MissingFile { artifact: String },
    /// Audit row claims absent (conditional_absent / expected_absent /
    /// not_run) but the file is present.
    UnexpectedPresent { artifact: String, state: String },
    /// Byte length drift between the audit row and the file.
    BytesDrift { artifact: String, audit: u64, actual: u64 },
    /// Data-row count drift between the audit row and the file.
    RowsDrift { artifact: String, audit: usize, actual: usize },
    /// A file sits in the out dir with no audit row covering it.
    UnregisteredOutput { file: String },
    /// A registry artifact has no row in the audit at all.
    AuditGap { artifact: String },
    /// An audit row is not parseable as the declared layout.
    MalformedRow { line: String },
    /// The identity block is missing the style id needed to resolve the
    /// style-derived names.
    MissingIdentityField { field: String },
}

/// Parse the identity block's `# identity<tab>key<tab>value` lines.
fn parse_identity(text: &str) -> Vec<(String, String)> {
    text.lines()
        .filter_map(|l| l.strip_prefix("# identity\t"))
        .filter_map(|rest| rest.split_once('\t'))
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect()
}

/// Consumer closure check: parse one run-audit.tsv and verify every row
/// against the out dir it describes, then check the dir and the registry
/// against the audit. Returns the typed mismatch ledger (empty = the audit
/// closes). Never repairs, never refuses.
pub fn verify_run_audit(out_dir: &Path, audit_text: &str) -> Vec<AuditMismatch> {
    let mut mismatches = Vec::new();
    let identity = parse_identity(audit_text);
    let style_id = match identity.iter().find(|(k, _)| k == "style_id") {
        Some((_, v)) => v.clone(),
        None => {
            mismatches.push(AuditMismatch::MissingIdentityField { field: "style_id".into() });
            String::new()
        }
    };
    let mut seen: Vec<String> = Vec::new();
    for line in audit_text.lines() {
        if line.is_empty() || line.starts_with('#') || line == "artifact\twriter_stage\tstate\trows\tbytes" {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() != 5 {
            mismatches.push(AuditMismatch::MalformedRow { line: line.to_string() });
            continue;
        }
        let (artifact, state_tag, rows_tag, bytes_tag) = (fields[0], fields[2], fields[3], fields[4]);
        let state = match ArtifactState::from_tag(state_tag) {
            Some(s) => s,
            None => {
                mismatches.push(AuditMismatch::MalformedRow { line: line.to_string() });
                continue;
            }
        };
        seen.push(artifact.to_string());
        let file = out_dir.join(artifact);
        match state {
            ArtifactState::Written | ArtifactState::ProbeWritten => {
                if !file.is_file() {
                    mismatches.push(AuditMismatch::MissingFile { artifact: artifact.to_string() });
                    continue;
                }
                if bytes_tag != "not_measured" {
                    match bytes_tag.parse::<u64>() {
                        Ok(claim) => {
                            let actual = fs::metadata(&file).map(|m| m.len()).unwrap_or(0);
                            if claim != actual {
                                mismatches.push(AuditMismatch::BytesDrift { artifact: artifact.to_string(), audit: claim, actual });
                            }
                        }
                        Err(_) => mismatches.push(AuditMismatch::MalformedRow { line: line.to_string() }),
                    }
                }
                if rows_tag != "not_measured" {
                    match rows_tag.parse::<usize>() {
                        Ok(claim) => match tsv_data_rows(&file) {
                            Ok(actual) if claim == actual => {}
                            Ok(actual) => mismatches.push(AuditMismatch::RowsDrift { artifact: artifact.to_string(), audit: claim, actual }),
                            Err(_) => mismatches.push(AuditMismatch::MalformedRow { line: line.to_string() }),
                        },
                        Err(_) => mismatches.push(AuditMismatch::MalformedRow { line: line.to_string() }),
                    }
                }
            }
            ArtifactState::ConditionalAbsent | ArtifactState::ExpectedAbsent | ArtifactState::NotRun => {
                if file.is_file() {
                    mismatches.push(AuditMismatch::UnexpectedPresent { artifact: artifact.to_string(), state: state_tag.to_string() });
                }
            }
            ArtifactState::SelfReferential => {
                if !file.is_file() {
                    mismatches.push(AuditMismatch::MissingFile { artifact: artifact.to_string() });
                }
            }
        }
    }
    // Completeness, both directions: every registry artifact has a row, and
    // every out-dir file is covered by a row.
    for spec in REGISTRY {
        let name = spec.name.resolve(&style_id);
        if !seen.iter().any(|s| s == &name) {
            mismatches.push(AuditMismatch::AuditGap { artifact: name });
        }
    }
    if !style_id.is_empty() {
        if let Ok(entries) = fs::read_dir(out_dir) {
            let mut files: Vec<String> = entries
                .filter_map(|e| e.ok())
                .filter(|e| e.file_type().map(|t| t.is_file()).unwrap_or(false))
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .collect();
            files.sort();
            for f in files {
                if !seen.iter().any(|s| s == &f) {
                    mismatches.push(AuditMismatch::UnregisteredOutput { file: f });
                }
            }
        }
    }
    mismatches
}

/// The mismatch ledger as typed TSV rows. Rendering only.
pub fn render_mismatches_tsv(mismatches: &[AuditMismatch]) -> String {
    let mut out = String::from("mismatch\tartifact\tdetail\n");
    for m in mismatches {
        match m {
            AuditMismatch::MissingFile { artifact } => out.push_str(&format!("missing_file\t{artifact}\tstate claims written, file absent\n")),
            AuditMismatch::UnexpectedPresent { artifact, state } => out.push_str(&format!("unexpected_present\t{artifact}\tstate={state} but file exists\n")),
            AuditMismatch::BytesDrift { artifact, audit, actual } => out.push_str(&format!("bytes_drift\t{artifact}\taudit={audit} actual={actual}\n")),
            AuditMismatch::RowsDrift { artifact, audit, actual } => out.push_str(&format!("rows_drift\t{artifact}\taudit={audit} actual={actual}\n")),
            AuditMismatch::UnregisteredOutput { file } => out.push_str(&format!("unregistered_output\t{file}\tfile has no audit row\n")),
            AuditMismatch::AuditGap { artifact } => out.push_str(&format!("audit_gap\t{artifact}\tregistry artifact missing from audit\n")),
            AuditMismatch::MalformedRow { line } => out.push_str(&format!("malformed_row\t\t{}\n", line.replace('\t', " "))),
            AuditMismatch::MissingIdentityField { field } => out.push_str(&format!("missing_identity_field\t\t{field}\n")),
        }
    }
    out
}

/// Convenience path-based check for a consumer holding only the directory.
pub fn verify_run_dir(out_dir: &Path) -> Result<Vec<AuditMismatch>, String> {
    let text = fs::read_to_string(out_dir.join(RUN_AUDIT_FILENAME))
        .map_err(|e| format!("run audit read {}: {e}", out_dir.join(RUN_AUDIT_FILENAME).display()))?;
    Ok(verify_run_audit(out_dir, &text))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn identity() -> RunIdentity {
        RunIdentity {
            population_sha256: "deadbeef".into(),
            family: "Test".into(),
            subfamily: "Regular".into(),
            postscript_name: "Test-Regular".into(),
            style_id: "s1".into(),
            emitter: EMITTER.into(),
        }
    }

    fn temp_dir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("kni-run-audit-test-{}-{}", tag, std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn registry_covers_every_main_rs_out_dir_write() {
        // Every literal `out_dir.join("NAME")` artifact write in main.rs
        // must be a registered artifact (or a declared exemption). This is
        // the drift guard: a new run artifact added without a registry row
        // fails here, so the audit stays complete by construction.
        let main_rs = include_str!("main.rs");
        let needle = "out_dir.join(\"";
        let mut names = Vec::new();
        let mut rest = main_rs;
        while let Some(i) = rest.find(needle) {
            rest = &rest[i + needle.len()..];
            if let Some(end) = rest.find('"') {
                let name = &rest[..end];
                if name.contains('.') && !names.contains(&name.to_string()) {
                    names.push(name.to_string());
                }
            }
        }
        // Declared exemptions: literals that are not run-artifact writes.
        // - floor.otf is registered; no exemptions needed today.
        let exemptions: [&str; 0] = [];
        let registered: Vec<String> = REGISTRY.iter().map(|s| s.name.resolve("s1")).collect();
        for n in &names {
            assert!(
                registered.iter().any(|r| r == n) || exemptions.contains(&n.as_str()),
                "out_dir artifact {n} is not in the run-audit registry"
            );
        }
        assert!(names.len() >= 19, "expected at least 19 literal out_dir joins, found {names:?}");
    }

    #[test]
    fn registry_names_resolve_uniquely() {
        let mut names: Vec<String> = REGISTRY.iter().map(|s| s.name.resolve("s1")).collect();
        let total = names.len();
        names.sort();
        names.dedup();
        assert_eq!(total, names.len(), "duplicate resolved registry names");
    }

    #[test]
    fn render_separates_identity_state_and_counts() {
        let rows = vec![
            ArtifactRow { artifact: "kern-ledger.tsv".into(), stage: Stage::KernGate, state: ArtifactState::Written, rows: Some(42), bytes: Some(1000) },
            ArtifactRow { artifact: "iou.tsv".into(), stage: Stage::EncodeEmit, state: ArtifactState::ConditionalAbsent, rows: None, bytes: None },
        ];
        let tsv = render_run_audit_tsv(&identity(), RunPath::Full, &rows);
        // Identity lives only in the comment block.
        assert!(tsv.contains("# identity\tpopulation_sha256\tdeadbeef\n"));
        assert!(tsv.contains("# identity\trun_path\tfull\n"));
        // Typed state and counts in their own columns.
        assert!(tsv.contains("kern-ledger.tsv\tkern_gate\twritten\t42\t1000\n"));
        assert!(tsv.contains("iou.tsv\tencode_emit\tconditional_absent\tnot_measured\tnot_measured\n"));
        assert!(tsv.contains("artifact\twriter_stage\tstate\trows\tbytes\n"));
    }

    #[test]
    fn collect_classifies_states_and_measures_counts() {
        let d = temp_dir("collect");
        // written tsv: 2 comment lines + header + 3 data rows.
        fs::write(d.join("kern-ledger.tsv"), "# c1\n# c2\nleft\tright\na\tb\nc\td\ne\tf\n").unwrap();
        // probe artifact.
        fs::write(d.join("run-provenance.tsv"), "run_out\tx\nemitter\ty\n").unwrap();
        // always artifact missing on a reachable stage: stage1-cache.txt.
        let rows = collect_run_audit(&d, &identity(), RunPath::Full).unwrap();
        let get = |n: &str| rows.iter().find(|r| r.artifact == n).unwrap();
        let kern = get("kern-ledger.tsv");
        assert_eq!(kern.state, ArtifactState::Written);
        assert_eq!(kern.rows, Some(3));
        assert_eq!(kern.bytes, Some(fs::metadata(d.join("kern-ledger.tsv")).unwrap().len()));
        assert_eq!(get("run-provenance.tsv").state, ArtifactState::ProbeWritten);
        assert_eq!(get("stage1-cache.txt").state, ArtifactState::ExpectedAbsent);
        assert_eq!(get("corner-wiring.tsv").state, ArtifactState::ConditionalAbsent);
        assert_eq!(get(RUN_AUDIT_FILENAME).state, ArtifactState::SelfReferential);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn unreachable_stages_are_not_run_never_expected_absent() {
        let d = temp_dir("notrun");
        let rows = collect_run_audit(&d, &identity(), RunPath::Stage1Only).unwrap();
        let get = |n: &str| rows.iter().find(|r| r.artifact == n).unwrap();
        // Stage1Only reaches run_control and stage1_capture only.
        assert_eq!(get("stage1-cache.txt").state, ArtifactState::ExpectedAbsent);
        assert_eq!(get("kern-ledger.tsv").state, ArtifactState::NotRun);
        assert_eq!(get("mapping.tsv").state, ArtifactState::NotRun);
        assert_eq!(get("encode-closure-audit.tsv").state, ArtifactState::NotRun);
        let rows_floor = collect_run_audit(&d, &identity(), RunPath::PopulationFloor).unwrap();
        let getf = |n: &str| rows_floor.iter().find(|r| r.artifact == n).unwrap();
        assert_eq!(getf("font-s1.otf").state, ArtifactState::ExpectedAbsent);
        assert_eq!(getf("kern-ledger.tsv").state, ArtifactState::NotRun);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn write_refuses_to_overwrite() {
        let d = temp_dir("nooverwrite");
        write_run_audit(&d, &identity(), RunPath::Full).unwrap();
        let err = write_run_audit(&d, &identity(), RunPath::Full).unwrap_err();
        assert!(err.contains("run audit write"), "{err}");
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn verify_closes_on_consistent_dir() {
        let d = temp_dir("verify-ok");
        fs::write(d.join("kern-ledger.tsv"), "left\tright\na\tb\n").unwrap();
        fs::write(d.join("font-s1.otf"), b"OTFBYTES").unwrap();
        write_run_audit(&d, &identity(), RunPath::Full).unwrap();
        let mismatches = verify_run_dir(&d).unwrap();
        // Only the expected-absent always-artifacts are absent; the dir
        // itself is consistent with the audit.
        assert_eq!(mismatches, Vec::new(), "{mismatches:?}");
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn verify_flags_drift_and_gaps() {
        let d = temp_dir("verify-drift");
        fs::write(d.join("kern-ledger.tsv"), "left\tright\na\tb\n").unwrap();
        write_run_audit(&d, &identity(), RunPath::Full).unwrap();
        // Drift the file after the audit.
        fs::write(d.join("kern-ledger.tsv"), "left\tright\na\tb\nc\td\n").unwrap();
        // An unregistered file appears.
        fs::write(d.join("stray.txt"), b"x").unwrap();
        let text = fs::read_to_string(d.join(RUN_AUDIT_FILENAME)).unwrap();
        let mismatches = verify_run_audit(&d, &text);
        assert!(mismatches.iter().any(|m| matches!(m, AuditMismatch::RowsDrift { artifact, audit: 1, actual: 2 } if artifact == "kern-ledger.tsv")), "{mismatches:?}");
        assert!(mismatches.iter().any(|m| matches!(m, AuditMismatch::BytesDrift { artifact, .. } if artifact == "kern-ledger.tsv")), "{mismatches:?}");
        assert!(mismatches.iter().any(|m| matches!(m, AuditMismatch::UnregisteredOutput { file } if file == "stray.txt")), "{mismatches:?}");
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn verify_flags_unexpected_presence_and_audit_gap() {
        let d = temp_dir("verify-gap");
        write_run_audit(&d, &identity(), RunPath::Stage1Only).unwrap();
        // A not_run artifact appears anyway.
        fs::write(d.join("kern-ledger.tsv"), "left\tright\n").unwrap();
        let text = fs::read_to_string(d.join(RUN_AUDIT_FILENAME)).unwrap();
        let mismatches = verify_run_audit(&d, &text);
        assert!(mismatches.iter().any(|m| matches!(m, AuditMismatch::UnexpectedPresent { artifact, .. } if artifact == "kern-ledger.tsv")), "{mismatches:?}");
        // Drop a row from the audit: the registry artifact becomes a gap.
        let cut: String = text.lines().filter(|l| !l.starts_with("mapping.tsv\t")).map(|l| format!("{l}\n")).collect();
        let mismatches2 = verify_run_audit(&d, &cut);
        assert!(mismatches2.iter().any(|m| matches!(m, AuditMismatch::AuditGap { artifact } if artifact == "mapping.tsv")), "{mismatches2:?}");
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn malformed_rows_are_typed_not_fatal() {
        let d = temp_dir("malformed");
        let text = "# identity\tstyle_id\ts1\nartifact\twriter_stage\tstate\trows\tbytes\nbroken-row\n";
        let mismatches = verify_run_audit(&d, text);
        assert!(mismatches.iter().any(|m| matches!(m, AuditMismatch::MalformedRow { .. })), "{mismatches:?}");
        // Every registry artifact is a gap (no rows), which is also typed.
        assert!(mismatches.iter().any(|m| matches!(m, AuditMismatch::AuditGap { .. })));
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn render_is_deterministic() {
        let d = temp_dir("determinism");
        fs::write(d.join("spacing.tsv"), "glyph_id\tlsb\na\t1\n").unwrap();
        let id = identity();
        let a = render_run_audit_tsv(&id, RunPath::Full, &collect_run_audit(&d, &id, RunPath::Full).unwrap());
        let b = render_run_audit_tsv(&id, RunPath::Full, &collect_run_audit(&d, &id, RunPath::Full).unwrap());
        assert_eq!(a, b);
        let _ = fs::remove_dir_all(&d);
    }

    #[test]
    fn mismatch_render_is_typed() {
        let ms = vec![
            AuditMismatch::MissingFile { artifact: "x.tsv".into() },
            AuditMismatch::RowsDrift { artifact: "y.tsv".into(), audit: 1, actual: 2 },
        ];
        let tsv = render_mismatches_tsv(&ms);
        assert!(tsv.contains("missing_file\tx.tsv\t"));
        assert!(tsv.contains("rows_drift\ty.tsv\taudit=1 actual=2"));
    }
    #[test]
    fn generated_master_is_registered_measured_and_missing_is_visible() {
        let d = temp_dir("master-registered");
        let mut id = identity();
        id.style_id = "Another-Style".into();
        let name = "font-Another-Style.glyphs";
        fs::write(d.join(name), b"native master bytes").unwrap();
        for path in [RunPath::Full, RunPath::PopulationFloor] {
            let rows = collect_run_audit(&d, &id, path).unwrap();
            let master = rows.iter().find(|r| r.artifact == name).unwrap();
            assert_eq!(master.stage, Stage::EncodeEmit);
            assert_eq!(master.state, ArtifactState::Written);
            assert_eq!(master.bytes, Some(19));
            assert_eq!(master.rows, None);
        }
        write_run_audit(&d, &id, RunPath::Full).unwrap();
        let audit = fs::read_to_string(d.join(RUN_AUDIT_FILENAME)).unwrap();
        assert!(verify_run_audit(&d, &audit).is_empty());
        fs::write(d.join(name), b"changed").unwrap();
        assert!(verify_run_audit(&d, &audit).iter().any(|m| matches!(m,
            AuditMismatch::BytesDrift { artifact, .. } if artifact == name)));
        fs::remove_file(d.join(name)).unwrap();
        assert!(verify_run_audit(&d, &audit).iter().any(|m| matches!(m,
            AuditMismatch::MissingFile { artifact } if artifact == name)));
        let rows = collect_run_audit(&d, &id, RunPath::Full).unwrap();
        assert_eq!(rows.iter().find(|r| r.artifact == name).unwrap().state, ArtifactState::ExpectedAbsent);
        let rows = collect_run_audit(&d, &id, RunPath::Stage1Only).unwrap();
        assert_eq!(rows.iter().find(|r| r.artifact == name).unwrap().state, ArtifactState::NotRun);
        let _ = fs::remove_dir_all(d);
    }

}
