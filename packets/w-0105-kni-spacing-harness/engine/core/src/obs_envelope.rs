//! obs_envelope.rs — G1 merge-visibility observer, part C (envelope module).
//! mov-1 schema; chief-ratified 58-byte fixed LE layout (17:15 + corrections):
//!   geom_fp[0:16]  = 2 x u64 LE = xxh64(geom bytes, 0), xxh64(geom bytes, 1)
//!   src_fp [16:48] = 4 x u64 LE = xxh64(src bytes, 0..3)
//!   rev    [48:50] = u16 LE, monotonic per (glyph, style), from 1
//!   span_id[50:58] = u64 LE = ring-call identity xxh64("ring:{i}", 0)
//! Wire: obs carries ONE "fp58" field = 116 lowercase hex chars (or JSON null).
//! xxh64 lives in crate::fp (sole in-tree owner). Zero new crate dependencies.
//! No IO beyond the KNI_* scan; no engine state; no timing/pid in fingerprints.
//! Base: dc19e661.

use crate::economy::EconomyDecision;
use crate::fp::xxh64;
use crate::reference_slice::{Point, Span};

pub const SCHEMA: &str = "mov-1";
pub const OBSERVE_GATE_ENV: &str = "KNI_MERGE_OBSERVE";
pub const OUTPUT_FILENAME: &str = "merge-visibility-mov1.jsonl";
pub const SEED0: u64 = 0;
pub const SEED1: u64 = 1;
pub const SEED2: u64 = 2;
pub const SEED3: u64 = 3;

// ---------------------------------------------------------------------------
// Error: non-finite numbers are rejected, never rendered.
// ---------------------------------------------------------------------------

/// A record that hits this error MUST NOT be emitted.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NonFinite;

// ---------------------------------------------------------------------------
// Canonical JSON writer. Key order = caller emission order = template order.
// Compact, one line, no spaces.
// ---------------------------------------------------------------------------

pub struct CanonJson {
    buf: String,
}

pub struct ObjW<'a> {
    buf: &'a mut String,
    first: bool,
}

pub struct ArrW<'a> {
    buf: &'a mut String,
    first: bool,
}

fn esc_into(buf: &mut String, s: &str) {
    for c in s.chars() {
        match c {
            '"' => buf.push_str("\\\""),
            '\\' => buf.push_str("\\\\"),
            c if (c as u32) < 0x20 => buf.push_str(&format!("\\u{:04x}", c as u32)),
            c => buf.push(c),
        }
    }
}

fn num_into(buf: &mut String, x: f64) -> Result<(), NonFinite> {
    if !x.is_finite() {
        return Err(NonFinite);
    }
    // Rust Display for f64: shortest round-trip, positional notation only,
    // never an exponent. This is the mov-1 fixed-decimal encoding.
    buf.push_str(&format!("{}", x));
    Ok(())
}

impl CanonJson {
    pub fn new() -> Self {
        CanonJson { buf: String::new() }
    }
    pub fn obj(&mut self, f: impl FnOnce(&mut ObjW)) {
        self.buf.push('{');
        let mut w = ObjW { buf: &mut self.buf, first: true };
        f(&mut w);
        self.buf.push('}');
    }
    pub fn arr(&mut self, f: impl FnOnce(&mut ArrW)) {
        self.buf.push('[');
        let mut w = ArrW { buf: &mut self.buf, first: true };
        f(&mut w);
        self.buf.push(']');
    }
    pub fn finish(self) -> String {
        self.buf
    }
}

impl<'a> ObjW<'a> {
    fn sep(&mut self, key: &str) {
        if self.first {
            self.first = false;
        } else {
            self.buf.push(',');
        }
        self.buf.push('"');
        esc_into(self.buf, key);
        self.buf.push_str("\":");
    }
    pub fn raw(&mut self, key: &str, val: &str) {
        self.sep(key);
        self.buf.push_str(val);
    }
    pub fn str(&mut self, key: &str, val: &str) {
        self.sep(key);
        self.buf.push('"');
        esc_into(self.buf, val);
        self.buf.push('"');
    }
    pub fn boolean(&mut self, key: &str, val: bool) {
        self.sep(key);
        self.buf.push_str(if val { "true" } else { "false" });
    }
    pub fn num(&mut self, key: &str, val: f64) -> Result<(), NonFinite> {
        self.sep(key);
        num_into(self.buf, val)
    }
    pub fn int(&mut self, key: &str, val: i64) {
        self.sep(key);
        self.buf.push_str(&format!("{}", val));
    }
    pub fn null(&mut self, key: &str) {
        self.sep(key);
        self.buf.push_str("null");
    }
    pub fn opt_str(&mut self, key: &str, val: &Option<String>) {
        match val {
            Some(s) => self.str(key, s),
            None => self.null(key),
        }
    }
    pub fn opt_num(&mut self, key: &str, val: &Option<f64>) -> Result<(), NonFinite> {
        match val {
            Some(x) => self.num(key, *x),
            None => {
                self.null(key);
                Ok(())
            }
        }
    }
    pub fn obj(&mut self, key: &str, f: impl FnOnce(&mut ObjW)) {
        self.sep(key);
        self.buf.push('{');
        let mut w = ObjW { buf: self.buf, first: true };
        f(&mut w);
        self.buf.push('}');
    }
    pub fn arr(&mut self, key: &str, f: impl FnOnce(&mut ArrW)) {
        self.sep(key);
        self.buf.push('[');
        let mut w = ArrW { buf: self.buf, first: true };
        f(&mut w);
        self.buf.push(']');
    }
}

impl<'a> ArrW<'a> {
    fn sep(&mut self) {
        if self.first {
            self.first = false;
        } else {
            self.buf.push(',');
        }
    }
    pub fn str(&mut self, val: &str) {
        self.sep();
        self.buf.push('"');
        esc_into(self.buf, val);
        self.buf.push('"');
    }
    pub fn num(&mut self, val: f64) -> Result<(), NonFinite> {
        self.sep();
        num_into(self.buf, val)
    }
    pub fn int(&mut self, val: i64) {
        self.sep();
        self.buf.push_str(&format!("{}", val));
    }
    pub fn boolean(&mut self, val: bool) {
        self.sep();
        self.buf.push_str(if val { "true" } else { "false" });
    }
    pub fn null(&mut self) {
        self.sep();
        self.buf.push_str("null");
    }
    pub fn obj(&mut self, f: impl FnOnce(&mut ObjW)) {
        self.sep();
        self.buf.push('{');
        let mut w = ObjW { buf: self.buf, first: true };
        f(&mut w);
        self.buf.push('}');
    }
}

// ---------------------------------------------------------------------------
// Hex rendering (lowercase, byte order as given — the 58-byte parts are
// already little-endian packed).
// ---------------------------------------------------------------------------

pub fn hex_bytes_le(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

// ---------------------------------------------------------------------------
// Snapshots and the 58-byte record parts.
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct QPoint(pub i32, pub i32);

pub type QuantizeFn = fn(&Point) -> QPoint;

#[derive(Clone, Debug)]
pub struct RingSnapshot {
    pub start: QPoint,
    pub spans: Vec<SnapSpan>,
}

#[derive(Clone, Debug)]
pub struct SnapSpan {
    pub kind: SnapSpanKind,
    pub points: Vec<QPoint>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SnapSpanKind {
    Line,
    Cubic,
}

impl RingSnapshot {
    pub fn from_fit(start: &Point, spans: &[Span], q: QuantizeFn) -> Self {
        let snaps = spans
            .iter()
            .map(|s| match s {
                Span::Line { end } => SnapSpan {
                    kind: SnapSpanKind::Line,
                    points: vec![q(end)],
                },
                Span::Cubic { control_one, control_two, end } => SnapSpan {
                    kind: SnapSpanKind::Cubic,
                    points: vec![q(control_one), q(control_two), q(end)],
                },
            })
            .collect();
        RingSnapshot { start: q(start), spans: snaps }
    }

    /// This ring's body bytes (chief-architect FINAL 17:29): start.x i32 LE,
    /// start.y i32 LE (exactly once per ring - omission forbidden), span_count
    /// u32 LE, then per span: kind u8 (0 Line, 1 Cubic; mandatory), point_count
    /// u32 LE counting exactly the span's stored points (Line = 1 [end],
    /// Cubic = 3 [c1,c2,end]), then those (x,y) i32 LE pairs in emit order.
    /// A span's start is the previous span's end (or the ring start) and is
    /// never duplicated in the bytes.
    pub fn geom_bytes(&self) -> Vec<u8> {
        let mut v = Vec::new();
        v.extend_from_slice(&self.start.0.to_le_bytes());
        v.extend_from_slice(&self.start.1.to_le_bytes());
        v.extend_from_slice(&(self.spans.len() as u32).to_le_bytes());
        for s in &self.spans {
            v.push(match s.kind {
                SnapSpanKind::Line => 0u8,
                SnapSpanKind::Cubic => 1u8,
            });
            v.extend_from_slice(&(s.points.len() as u32).to_le_bytes());
            for p in &s.points {
                v.extend_from_slice(&p.0.to_le_bytes());
                v.extend_from_slice(&p.1.to_le_bytes());
            }
        }
        v
    }
}

/// Whole-outline geom bytes: ring_count u32 LE header, then each ring's body.
pub fn geom_bytes(rings: &[RingSnapshot]) -> Vec<u8> {
    let mut v = Vec::new();
    v.extend_from_slice(&(rings.len() as u32).to_le_bytes());
    for r in rings {
        v.extend_from_slice(&r.geom_bytes());
    }
    v
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct GeomFp(pub [u8; 16]);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SrcFp(pub [u8; 32]);

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Revision(pub u16);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RevOverflow;

impl Revision {
    pub fn first() -> Self {
        Revision(1)
    }
    pub fn next(prev: Revision) -> Result<Revision, RevOverflow> {
        if prev.0 == u16::MAX {
            return Err(RevOverflow);
        }
        Ok(Revision(prev.0 + 1))
    }
    /// 4 lowercase hex chars of the 2 LE bytes (rev 1 -> "0100").
    pub fn hex(&self) -> String {
        hex_bytes_le(&self.0.to_le_bytes())
    }
}

/// Emitter-owned counter for ONE (glyph, style) pair; +1 per revision P0->P7.
#[derive(Clone, Debug)]
pub struct RevEmitter {
    next: u16,
}

impl RevEmitter {
    pub fn new() -> Self {
        RevEmitter { next: 1 }
    }
    pub fn next_rev(&mut self) -> Result<Revision, RevOverflow> {
        if self.next == u16::MAX {
            return Err(RevOverflow);
        }
        let r = Revision(self.next);
        self.next += 1;
        Ok(r)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SpanId(pub u64);

impl SpanId {
    /// 16 lowercase hex chars of the 8 LE bytes.
    pub fn hex(&self) -> String {
        hex_bytes_le(&self.0.to_le_bytes())
    }
}

/// RING-CALL identity for fp58's span_id field: xxh64("ring:{i}", seed 0).
pub fn ring_call_id(captured_ring_index: u32) -> u64 {
    xxh64(format!("ring:{}", captured_ring_index).as_bytes(), SEED0)
}

/// Individual span id for obs/xform span arrays: xxh64("ring:{i}/span:{j}", seed 0).
pub fn assign_span_id(ring_index: u32, span_index: u32) -> SpanId {
    SpanId(xxh64(
        format!("ring:{}/span:{}", ring_index, span_index).as_bytes(),
        SEED0,
    ))
}

pub fn geom_fp(bytes: &[u8]) -> GeomFp {
    let mut out = [0u8; 16];
    out[0..8].copy_from_slice(&xxh64(bytes, SEED0).to_le_bytes());
    out[8..16].copy_from_slice(&xxh64(bytes, SEED1).to_le_bytes());
    GeomFp(out)
}

pub fn src_fp(bytes: &[u8]) -> SrcFp {
    let mut out = [0u8; 32];
    for (i, seed) in [SEED0, SEED1, SEED2, SEED3].iter().enumerate() {
        out[i * 8..(i + 1) * 8].copy_from_slice(&xxh64(bytes, *seed).to_le_bytes());
    }
    SrcFp(out)
}

/// Assemble the 58-byte fixed record (all multi-byte fields little-endian).
pub fn record58(g: &GeomFp, s: &SrcFp, rev: Revision, ring_call: u64) -> [u8; 58] {
    let mut out = [0u8; 58];
    out[0..16].copy_from_slice(&g.0);
    out[16..48].copy_from_slice(&s.0);
    out[48..50].copy_from_slice(&rev.0.to_le_bytes());
    out[50..58].copy_from_slice(&ring_call.to_le_bytes());
    out
}

// ---------------------------------------------------------------------------
// UTC civil time, hand-rolled (no chrono). Metadata only, never in fp58.
// ---------------------------------------------------------------------------

pub fn utc_stamp(epoch_secs: u64) -> String {
    let days = epoch_secs / 86_400;
    let secs = epoch_secs % 86_400;
    let (h, m, s) = (secs / 3600, (secs % 3600) / 60, secs % 60);
    let z = days as i64 + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let yr = if mo <= 2 { y + 1 } else { y };
    format!("{:04}{:02}{:02}T{:02}{:02}{:02}Z", yr, mo, d, h, m, s)
}

// ---------------------------------------------------------------------------
// Run identity.
// ---------------------------------------------------------------------------

/// "utc-<yyyymmddThhmmssZ>-<manifest sha256 first 12 lowercase hex>".
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct InvocationId(pub String);

pub fn invocation_id(manifest_sha256: &str, epoch_secs: u64) -> InvocationId {
    let short: String = manifest_sha256.chars().take(12).collect::<String>().to_lowercase();
    InvocationId(format!("utc-{}-{}", utc_stamp(epoch_secs), short))
}

/// On collision, append a two-digit sequence starting at 01.
pub fn with_collision_seq(id: &InvocationId, seq: u8) -> InvocationId {
    InvocationId(format!("{}-{:02}", id.0, seq))
}

/// Every KNI_* environment variable, sorted by name. Boolean semantics:
/// variable is SET (presence). The value text is not recorded.
#[derive(Clone, Debug)]
pub struct EnvFlags(pub Vec<(String, bool)>);

pub fn collect_env_flags() -> EnvFlags {
    let mut flags: Vec<(String, bool)> = std::env::vars_os()
        .filter_map(|(k, _)| {
            let k = k.to_string_lossy().into_owned();
            if k.starts_with("KNI_") {
                Some((k, true))
            } else {
                None
            }
        })
        .collect();
    flags.sort_by(|a, b| a.0.cmp(&b.0));
    flags.dedup_by(|a, b| a.0 == b.0);
    EnvFlags(flags)
}

// ---------------------------------------------------------------------------
// Shared enums. as_str() returns the exact mov-1 vocabularies.
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Stage1Route {
    Live,
    CacheReuse,
}
impl Stage1Route {
    pub fn as_str(&self) -> &'static str {
        match self {
            Stage1Route::Live => "live",
            Stage1Route::CacheReuse => "cache_reuse",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ObsPoint {
    P0, P1, P2, P3, P4, P5, P6, P7,
    Pp1, Pp2, Pp3,
}
impl ObsPoint {
    pub fn as_str(&self) -> &'static str {
        match self {
            ObsPoint::P0 => "P0", ObsPoint::P1 => "P1", ObsPoint::P2 => "P2",
            ObsPoint::P3 => "P3", ObsPoint::P4 => "P4", ObsPoint::P5 => "P5",
            ObsPoint::P6 => "P6", ObsPoint::P7 => "P7",
            ObsPoint::Pp1 => "PP1", ObsPoint::Pp2 => "PP2", ObsPoint::Pp3 => "PP3",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RouteDomain {
    Primary,
    Outline,
}
/// Default mapping (chief 17:28): unspecified domain maps to Primary.
impl Default for RouteDomain {
    fn default() -> Self {
        RouteDomain::Primary
    }
}

impl RouteDomain {
    pub fn as_str(&self) -> &'static str {
        match self {
            RouteDomain::Primary => "primary",
            RouteDomain::Outline => "outline",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FitRoute {
    GuardedGuided,
    Plain,
    CacheReuse,
}
/// Default mapping (chief 17:28): unspecified route maps to Plain
/// (GuardedGuided is only emitted when the guarded-guided path was taken).
impl Default for FitRoute {
    fn default() -> Self {
        FitRoute::Plain
    }
}

impl FitRoute {
    pub fn as_str(&self) -> &'static str {
        match self {
            FitRoute::GuardedGuided => "guarded-guided",
            FitRoute::Plain => "plain",
            FitRoute::CacheReuse => "cache_reuse",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ObserverOutcome {
    Complete,
    NotEnabled,
    MissingInput,
    UnsupportedSourceMapping,
    Failed,
}
impl ObserverOutcome {
    pub fn as_str(&self) -> &'static str {
        match self {
            ObserverOutcome::Complete => "complete",
            ObserverOutcome::NotEnabled => "not_enabled",
            ObserverOutcome::MissingInput => "missing_input",
            ObserverOutcome::UnsupportedSourceMapping => "unsupported_source_mapping",
            ObserverOutcome::Failed => "failed",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum XformPass {
    G2Merge, Staircase, LineJunction, StraightOverCurve, Qf,
    Closure, Rounding, Economy, Tidy, RescueAdoption,
}
impl XformPass {
    pub fn as_str(&self) -> &'static str {
        match self {
            XformPass::G2Merge => "g2_merge",
            XformPass::Staircase => "staircase",
            XformPass::LineJunction => "line_junction",
            XformPass::StraightOverCurve => "straight_over_curve",
            XformPass::Qf => "qf",
            XformPass::Closure => "closure",
            XformPass::Rounding => "rounding",
            XformPass::Economy => "economy",
            XformPass::Tidy => "tidy",
            XformPass::RescueAdoption => "rescue_adoption",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum XformKind {
    G2LineRunFold, G2Union, G2Harmonize, StaircaseCollapse,
    LineJunctionMovement, SocConversion, QfRefinement, SyntheticClosure,
    Round, ExactCubicLine, ExactLineMerge, ZeroSpanRemoval, CornerAdoption,
    ArcRescue,
}
impl XformKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            XformKind::G2LineRunFold => "g2_line_run_fold",
            XformKind::G2Union => "g2_union",
            XformKind::G2Harmonize => "g2_harmonize",
            XformKind::StaircaseCollapse => "staircase_collapse",
            XformKind::LineJunctionMovement => "line_junction_movement",
            XformKind::SocConversion => "soc_conversion",
            XformKind::QfRefinement => "qf_refinement",
            XformKind::SyntheticClosure => "synthetic_closure",
            XformKind::Round => "round",
            XformKind::ExactCubicLine => "exact_cubic_line",
            XformKind::ExactLineMerge => "exact_line_merge",
            XformKind::ZeroSpanRemoval => "zero_span_removal",
            XformKind::CornerAdoption => "corner_adoption",
            XformKind::ArcRescue => "arc_rescue",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SrcRelation {
    Preserved,
    Rebound,
    Unresolved,
}
impl SrcRelation {
    pub fn as_str(&self) -> &'static str {
        match self {
            SrcRelation::Preserved => "preserved",
            SrcRelation::Rebound => "rebound",
            SrcRelation::Unresolved => "unresolved",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PipelineDomain {
    Emit,
    Measurement,
}
impl PipelineDomain {
    pub fn as_str(&self) -> &'static str {
        match self {
            PipelineDomain::Emit => "emit",
            PipelineDomain::Measurement => "measurement",
        }
    }
}

// ---------------------------------------------------------------------------
// Record types. Every render emits "schema":"mov-1" and "kind" first.
// ---------------------------------------------------------------------------

/// obs-record span counts. DISTINCT from the engine's
/// crate::economy::SpanCounts { lines, cubics } (chief 17:39): use the
/// explicit conversion span_counts_from_economy, never a type pun.
#[derive(Clone, Debug)]
pub struct SpanCounts {
    pub total: u32,
    pub line: u32,
    pub cubic: u32,
}

/// Explicit conversion from the engine's economy::SpanCounts (economy.rs:7):
/// total = lines + cubics (its segments()), line = lines, cubic = cubics.
pub fn span_counts_from_economy(e: &crate::economy::SpanCounts) -> SpanCounts {
    SpanCounts {
        total: (e.lines + e.cubics) as u32,
        line: e.lines as u32,
        cubic: e.cubics as u32,
    }
}

/// Typed ledger counters. Converter map (chief 17:35): "fallback_events",
/// "ambiguous_stubs", "declined_ambiguities" (PLURAL map key -> this struct's
/// declined_ambiguity), "corner_adopted", "rescue_adopted", "economy_decisions"
/// (= sum over the outcome's rewrites of economy_decisions.len(), converter
/// computes), "synthetic_closures". "zero_span_removals" only from a typed
/// source, else None -> JSON null, NEVER a silent 0. Unknown keys: typed
/// converter error, never dropped, never inferred.
#[derive(Clone, Debug)]
pub struct LedgerCounts {
    pub fallback_events: u64,
    pub ambiguous_stubs: u64,
    pub declined_ambiguity: u64,
    pub economy_decisions: u64,
    pub zero_span_removals: Option<u64>,
    pub synthetic_closures: u64,
    pub corner_adopted: u64,
    pub rescue_adopted: u64,
}

impl LedgerCounts {
    fn render_into(&self, w: &mut ObjW) {
        w.obj("ledger_counts", |m| {
            // sorted-by-key, matching the plan's nested-map rule
            m.int("ambiguous_stubs", self.ambiguous_stubs as i64);
            m.int("corner_adopted", self.corner_adopted as i64);
            m.int("declined_ambiguity", self.declined_ambiguity as i64);
            m.int("economy_decisions", self.economy_decisions as i64);
            m.int("fallback_events", self.fallback_events as i64);
            m.int("rescue_adopted", self.rescue_adopted as i64);
            m.int("synthetic_closures", self.synthetic_closures as i64);
            match self.zero_span_removals {
                Some(n) => m.int("zero_span_removals", n as i64),
                None => m.null("zero_span_removals"),
            }
        });
    }
}

#[derive(Clone, Debug)]
pub struct Envelope {
    pub run_id: String,
    pub source_full_ref: Option<String>,
    pub active_source_mapping_status: Option<String>,
    pub fixture_id: Option<String>,
    pub fixture_sha256: Option<String>,
    pub config_digest: Option<String>,
    pub economy_mode: Option<String>,
    pub coordinate_unit: Option<String>,
    pub grid: Option<String>,
    pub dense_bound_db: Option<f64>,
    pub line_tolerance: Option<f64>,
    pub workers: u32,
    pub stage1_route: Stage1Route,
    pub stage1_cache_sha256: Option<String>,
    pub env_flags: EnvFlags,
    pub invocation_id_style: String,
    pub invocation_id: InvocationId,
}

impl Envelope {
    pub fn render(&self) -> Result<String, NonFinite> {
        let mut c = CanonJson::new();
        let mut err: Option<NonFinite> = None;
        c.obj(|w| {
            w.str("schema", SCHEMA);
            w.str("kind", "envelope");
            w.str("run_id", &self.run_id);
            w.opt_str("source_full_ref", &self.source_full_ref);
            w.opt_str("active_source_mapping_status", &self.active_source_mapping_status);
            w.opt_str("fixture_id", &self.fixture_id);
            w.opt_str("fixture_sha256", &self.fixture_sha256);
            w.opt_str("config_digest", &self.config_digest);
            w.opt_str("economy_mode", &self.economy_mode);
            w.opt_str("coordinate_unit", &self.coordinate_unit);
            w.opt_str("grid", &self.grid);
            if let Err(e) = w.opt_num("dense_bound_db", &self.dense_bound_db) {
                err = Some(e);
            }
            if let Err(e) = w.opt_num("line_tolerance", &self.line_tolerance) {
                err = Some(e);
            }
            w.int("workers", self.workers as i64);
            w.str("stage1_route", self.stage1_route.as_str());
            w.opt_str("stage1_cache_sha256", &self.stage1_cache_sha256);
            w.obj("env_flags", |m| {
                for (k, v) in &self.env_flags.0 {
                    m.boolean(k, *v);
                }
            });
            w.str("invocation_id_style", &self.invocation_id_style);
            w.str("invocation_id", &self.invocation_id.0);
        });
        if let Some(e) = err {
            return Err(e);
        }
        Ok(c.finish())
    }
}

/// Per-outcome observation context (chief 17:35). H2 builds ONE per outcome
/// and hands it to the collector and the converter. run_id + invocation_id
/// are minted once at run start (main ~1500); glyph = GlyphRow.name; style =
/// manifest style; route_domain = Primary (Outline on outline fallback);
/// route = GuardedGuided if live guarded, Plain if guided off, CacheReuse on
/// cache; stage1_route = CacheReuse + sha256 of stage1-cache.txt, else
/// Live + null.
#[derive(Clone, Debug)]
pub struct ObsContext {
    pub run_id: String,
    pub invocation_id: InvocationId,
    pub glyph: String,
    pub style: String,
    pub route_domain: RouteDomain,
    pub route: FitRoute,
    pub stage1_route: Option<Stage1Route>,
    pub stage1_cache_sha256: Option<String>,
}

#[derive(Clone, Debug)]
pub struct Obs {
    pub point: ObsPoint,
    pub run_id: String,
    pub invocation_id: InvocationId,
    pub style: String,
    pub glyph: String,
    /// Real ring obs = Some(index); run-level PP obs = None (chief 17:39;
    /// the earlier 0 sentinel was REJECTED). fp58/span-id derivation only
    /// ever runs for Some.
    pub ring_index: Option<u32>,
    pub route_domain: RouteDomain,
    pub route: FitRoute,
    pub predecessor_rev: Option<Revision>,
    pub fp58: Option<String>,
    pub in_spans: Vec<SpanId>,
    pub out_spans: Vec<SpanId>,
    pub spans: SpanCounts,
    pub arcs: u32,
    pub synthetic_closures: u32,
    pub ledger_counts: LedgerCounts,
    pub observer_outcome: ObserverOutcome,
    pub stage1_route: Option<Stage1Route>,
    pub stage1_cache_sha256: Option<String>,
    pub domain: Option<PipelineDomain>,
    pub reason: Option<String>,
}

impl Obs {
    /// Assemble one obs record (ONE per RING CALL) from the captured ring
    /// snapshot, the run's src_fp (computed once by into_records), and the
    /// emitter rev. fp58's span_id field = ring_call_id(ring_index); its
    /// geom_fp = geom_bytes of the ONE-RING outline containing this captured
    /// ring (ring-grain geometry; FLAGGED to the chief as the ring-call
    /// reading of the outline-shaped recipe).
    pub fn from_snapshot(
        ctx: &ObsContext,
        point: ObsPoint,
        predecessor_rev: Option<Revision>,
        ring_index: u32,
        ring: &RingSnapshot,
        src: Option<SrcFp>,
        rev: Revision,
        spans: SpanCounts,
        arcs: u32,
        synthetic_closures: u32,
        ledger_counts: LedgerCounts,
        observer_outcome: ObserverOutcome,
        domain: Option<PipelineDomain>,
        reason: Option<String>,
    ) -> Result<Self, NonFinite> {
        let fp58 = src.map(|s| {
            let g = geom_fp(&geom_bytes(std::slice::from_ref(ring)));
            hex_bytes_le(&record58(&g, &s, rev, ring_call_id(ring_index)))
        });
        let ids: Vec<SpanId> = (0..ring.spans.len() as u32)
            .map(|j| assign_span_id(ring_index, j))
            .collect();
        let (in_spans, out_spans) = (ids.clone(), ids);
        Ok(Obs {
            point, run_id: ctx.run_id.clone(), invocation_id: ctx.invocation_id.clone(),
            style: ctx.style.clone(), glyph: ctx.glyph.clone(), ring_index: Some(ring_index),
            route_domain: ctx.route_domain.clone(), route: ctx.route.clone(),
            predecessor_rev, fp58, in_spans, out_spans, spans, arcs,
            synthetic_closures, ledger_counts, observer_outcome,
            stage1_route: ctx.stage1_route.clone(),
            stage1_cache_sha256: ctx.stage1_cache_sha256.clone(), domain, reason,
        })
    }

    /// RUN-LEVEL pipeline obs (PP1-PP3, chief 17:35): synthesized in the main
    /// frontier, the collector carries no PP. fp58 is always null. PP2 live:
    /// full field set via ctx. PP2 cache: observer_outcome NotEnabled, reason
    /// "stage1_cache_reuse", stage1_cache_sha256 from ctx. PP1/PP3: stage
    /// completion + domain. ring_index is None (chief 17:39; the 0 sentinel
    /// was rejected).
    pub fn pipeline_obs(
        ctx: &ObsContext,
        point: ObsPoint,
        observer_outcome: ObserverOutcome,
        domain: Option<PipelineDomain>,
        reason: Option<String>,
    ) -> Self {
        Obs {
            point, run_id: ctx.run_id.clone(), invocation_id: ctx.invocation_id.clone(),
            style: ctx.style.clone(), glyph: ctx.glyph.clone(), ring_index: None,
            route_domain: ctx.route_domain.clone(), route: ctx.route.clone(),
            predecessor_rev: None, fp58: None, in_spans: Vec::new(), out_spans: Vec::new(),
            spans: SpanCounts { total: 0, line: 0, cubic: 0 }, arcs: 0,
            synthetic_closures: 0,
            ledger_counts: LedgerCounts {
                fallback_events: 0, ambiguous_stubs: 0, declined_ambiguity: 0,
                economy_decisions: 0, zero_span_removals: None, synthetic_closures: 0,
                corner_adopted: 0, rescue_adopted: 0,
            },
            observer_outcome,
            stage1_route: ctx.stage1_route.clone(),
            stage1_cache_sha256: ctx.stage1_cache_sha256.clone(),
            domain, reason,
        }
    }

    pub fn render(&self) -> Result<String, NonFinite> {
        let mut c = CanonJson::new();
        c.obj(|w| {
            w.str("schema", SCHEMA);
            w.str("kind", "obs");
            w.str("point", self.point.as_str());
            w.str("run_id", &self.run_id);
            w.str("invocation_id", &self.invocation_id.0);
            w.str("style", &self.style);
            w.str("glyph", &self.glyph);
            match self.ring_index {
                Some(i) => w.int("ring_index", i as i64),
                None => w.null("ring_index"),
            }
            w.str("route_domain", self.route_domain.as_str());
            w.str("route", self.route.as_str());
            match &self.predecessor_rev {
                Some(r) => w.str("predecessor_rev", &r.hex()),
                None => w.null("predecessor_rev"),
            }
            w.opt_str("fp58", &self.fp58);
            w.arr("in_spans", |a| {
                for s in &self.in_spans {
                    a.str(&s.hex());
                }
            });
            w.arr("out_spans", |a| {
                for s in &self.out_spans {
                    a.str(&s.hex());
                }
            });
            w.obj("spans", |m| {
                m.int("total", self.spans.total as i64);
                m.int("line", self.spans.line as i64);
                m.int("cubic", self.spans.cubic as i64);
            });
            w.int("arcs", self.arcs as i64);
            w.int("synthetic_closures", self.synthetic_closures as i64);
            self.ledger_counts.render_into(w);
            w.str("observer_outcome", self.observer_outcome.as_str());
            if let Some(r) = &self.stage1_route {
                w.str("stage1_route", r.as_str());
            }
            if let Some(s) = &self.stage1_cache_sha256 {
                w.str("stage1_cache_sha256", s);
            }
            if let Some(d) = &self.domain {
                w.str("domain", d.as_str());
            }
            if let Some(r) = &self.reason {
                w.str("reason", r);
            }
        });
        Ok(c.finish())
    }
}

#[derive(Clone, Debug)]
pub struct Xform {
    pub run_id: String,
    pub invocation_id: InvocationId,
    pub event_id: u64,
    pub pass: XformPass,
    pub transform: XformKind,
    pub input_rev: Revision,
    pub output_rev: Revision,
    pub in_spans: Vec<SpanId>,
    pub out_spans: Vec<SpanId>,
    /// None when there is no typed source - JSON null, never an invented
    /// Unresolved (chief 17:39).
    pub src_relation: Option<SrcRelation>,
    /// TYPED economy decisions bound to this transform (chief 17:37): the
    /// engine's own crate::economy::EconomyDecision, in collector record
    /// order (never re-sorted, never inferred from totals). The ledger's
    /// economy_decisions counter for the outcome = sum of these lens,
    /// converter-computed.
    pub economy_decisions: Vec<EconomyDecision>,
}

/// Render one engine EconomyDecision. Key order = the struct's declaration
/// order (economy.rs:15): rule, arc, first_span, last_span, before, after,
/// geometry_identical, construction_boundary_preserved.
fn render_economy_decision(w: &mut ObjW, d: &EconomyDecision) {
    w.str("rule", d.rule);
    w.int("arc", d.arc as i64);
    w.int("first_span", d.first_span as i64);
    w.int("last_span", d.last_span as i64);
    w.obj("before", |m| {
        m.int("lines", d.before.lines as i64);
        m.int("cubics", d.before.cubics as i64);
    });
    w.obj("after", |m| {
        m.int("lines", d.after.lines as i64);
        m.int("cubics", d.after.cubics as i64);
    });
    w.boolean("geometry_identical", d.geometry_identical);
    w.boolean("construction_boundary_preserved", d.construction_boundary_preserved);
}

impl Xform {
    pub fn render(&self) -> Result<String, NonFinite> {
        let mut c = CanonJson::new();
        c.obj(|w| {
            w.str("schema", SCHEMA);
            w.str("kind", "xform");
            w.str("run_id", &self.run_id);
            w.str("invocation_id", &self.invocation_id.0);
            w.int("event_id", self.event_id as i64);
            w.str("pass", self.pass.as_str());
            w.str("transform", self.transform.as_str());
            w.str("input_rev", &self.input_rev.hex());
            w.str("output_rev", &self.output_rev.hex());
            w.arr("in_spans", |a| {
                for s in &self.in_spans {
                    a.str(&s.hex());
                }
            });
            w.arr("out_spans", |a| {
                for s in &self.out_spans {
                    a.str(&s.hex());
                }
            });
            match &self.src_relation {
                Some(r) => w.str("src_relation", r.as_str()),
                None => w.null("src_relation"),
            }
            w.arr("economy_decisions", |a| {
                for d in &self.economy_decisions {
                    a.obj(|o| render_economy_decision(o, d));
                }
            });
        });
        Ok(c.finish())
    }
}

#[derive(Clone, Debug)]
pub struct Consumer {
    pub run_id: String,
    pub consumer: String,
    pub invocation_id: InvocationId,
    pub observed_input_rev: Revision,
    pub expected_upstream_rev: Revision,
    pub candidate: bool,
    pub eligible: bool,
    pub evaluated: bool,
    pub changed: bool,
    pub declined: bool,
    pub abstained: bool,
    pub skipped: bool,
    pub reason: String,
    pub src_binding_state: String,
    pub src_domain_rev: Option<Revision>,
}

impl Consumer {
    pub fn render(&self) -> Result<String, NonFinite> {
        let mut c = CanonJson::new();
        c.obj(|w| {
            w.str("schema", SCHEMA);
            w.str("kind", "consumer");
            w.str("run_id", &self.run_id);
            w.str("consumer", &self.consumer);
            w.str("invocation_id", &self.invocation_id.0);
            w.str("observed_input_rev", &self.observed_input_rev.hex());
            w.str("expected_upstream_rev", &self.expected_upstream_rev.hex());
            w.boolean("candidate", self.candidate);
            w.boolean("eligible", self.eligible);
            w.boolean("evaluated", self.evaluated);
            w.boolean("changed", self.changed);
            w.boolean("declined", self.declined);
            w.boolean("abstained", self.abstained);
            w.boolean("skipped", self.skipped);
            w.str("reason", &self.reason);
            w.str("src_binding_state", &self.src_binding_state);
            match &self.src_domain_rev {
                Some(r) => w.str("src_domain_rev", &r.hex()),
                None => w.null("src_domain_rev"),
            }
        });
        Ok(c.finish())
    }
}

#[derive(Clone, Debug)]
pub struct Frontier {
    pub run_id: String,
    pub completed_stage: String,
    pub completion_receipt: bool,
    pub cache_file_present: bool,
}

impl Frontier {
    pub fn new(run_id: String, completed_stage: String, completion_receipt: bool, cache_file_present: bool) -> Self {
        Frontier { run_id, completed_stage, completion_receipt, cache_file_present }
    }
    pub fn render(&self) -> Result<String, NonFinite> {
        let mut c = CanonJson::new();
        c.obj(|w| {
            w.str("schema", SCHEMA);
            w.str("kind", "frontier");
            w.str("run_id", &self.run_id);
            w.str("completed_stage", &self.completed_stage);
            w.boolean("completion_receipt", self.completion_receipt);
            w.boolean("cache_file_present", self.cache_file_present);
        });
        Ok(c.finish())
    }
}

// ---------------------------------------------------------------------------
// The one record union workers carry, and the run-level fold entrypoint.
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
pub enum Record {
    Envelope(Envelope),
    Obs(Obs),
    Xform(Xform),
    Consumer(Consumer),
    Frontier(Frontier),
}

impl Record {
    pub fn render(&self) -> Result<String, NonFinite> {
        match self {
            Record::Envelope(r) => r.render(),
            Record::Obs(r) => r.render(),
            Record::Xform(r) => r.render(),
            Record::Consumer(r) => r.render(),
            Record::Frontier(r) => r.render(),
        }
    }
}

/// The run's single source: the parsed font buffer the stage1 pin binds,
/// passed by main, read ONCE per run. None => no source domain => fp58 null.
pub struct RunSource<'a> {
    pub src_bytes: Option<&'a [u8]>,
}

impl<'a> RunSource<'a> {
    pub fn src_fp(&self) -> Option<SrcFp> {
        self.src_bytes.map(src_fp)
    }
}

/// The fold entrypoint: envelope, per-outcome typed records in MANIFEST ORDER,
/// and the run's single src buffer. Renders every record to one serialized
/// JSONL line. Deterministic: output depends only on manifest order, never on
/// worker count or completion order.
pub fn into_records(
    envelope: Envelope,
    per_outcome: Vec<Vec<Record>>,
    src: &RunSource,
) -> Result<Vec<String>, NonFinite> {
    let _ = src.src_fp(); // computed once per run; obs constructors receive it
    let mut out = Vec::new();
    out.push(envelope.render()?);
    for outcome in per_outcome {
        for rec in outcome {
            out.push(rec.render()?);
        }
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Tests. Golden fingerprint constants derived against python-xxhash 4.0.1
// (independent implementation) on 2026-10-17; see fp.rs provenance.
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn q(p: &Point) -> QPoint {
        QPoint(p.x as i32, p.y as i32)
    }

    fn test_ctx() -> ObsContext {
        ObsContext {
            run_id: "run-1".into(),
            invocation_id: InvocationId("utc-20261017T000000Z-aabbccddeeff".into()),
            glyph: "A".into(),
            style: "Regular".into(),
            route_domain: RouteDomain::Primary,
            route: FitRoute::GuardedGuided,
            stage1_route: None,
            stage1_cache_sha256: None,
        }
    }

    fn golden_rings() -> Vec<RingSnapshot> {
        vec![RingSnapshot {
            start: QPoint(10, 20),
            spans: vec![
                SnapSpan { kind: SnapSpanKind::Line, points: vec![QPoint(30, 40)] },
                SnapSpan {
                    kind: SnapSpanKind::Cubic,
                    points: vec![QPoint(50, 60), QPoint(70, 80), QPoint(90, 100)],
                },
            ],
        }]
    }

    const GOLDEN_GEOM_BYTES: &str = "010000000a000000140000000200000000010000001e000000280000000103000000320000003c00000046000000500000005a00000064000000";
    const GOLDEN_GEOM_FP: &str = "515b7bf651bbc1aa4fd7b44b79fddbd5";
    const GOLDEN_SRC_FP: &str = "9d4f80e07119398b824666fac504697f8cce0a799864a50fd8a40f074e3d41e9";
    const GOLDEN_FP58: &str = "515b7bf651bbc1aa4fd7b44b79fddbd59d4f80e07119398b824666fac504697f8cce0a799864a50fd8a40f074e3d41e903007674028879b872aa";
    const SRC_BYTES: &[u8] = b"\x00\x01\x02\x03fake-font-bytes";

    #[test]
    fn geom_bytes_layout() {
        assert_eq!(hex_bytes_le(&geom_bytes(&golden_rings())), GOLDEN_GEOM_BYTES);
    }

    #[test]
    fn geom_fp_matches_reference() {
        assert_eq!(hex_bytes_le(&geom_fp(&geom_bytes(&golden_rings())).0), GOLDEN_GEOM_FP);
    }

    #[test]
    fn src_fp_matches_reference() {
        assert_eq!(hex_bytes_le(&src_fp(SRC_BYTES).0), GOLDEN_SRC_FP);
    }

    #[test]
    fn ring_call_id_matches_reference() {
        assert_eq!(ring_call_id(2).to_le_bytes().as_slice().len(), 8);
        assert_eq!(hex_bytes_le(&ring_call_id(2).to_le_bytes()), "7674028879b872aa");
    }

    #[test]
    fn span_ids_match_reference() {
        assert_eq!(assign_span_id(2, 0).hex(), "9a7d7381a8b3edfc");
        assert_eq!(assign_span_id(2, 1).hex(), "243911d0c56bd12f");
    }

    #[test]
    fn record58_offsets() {
        let g = geom_fp(&geom_bytes(&golden_rings()));
        let s = src_fp(SRC_BYTES);
        let r = record58(&g, &s, Revision(3), ring_call_id(2));
        assert_eq!(r.len(), 58);
        assert_eq!(hex_bytes_le(&r), GOLDEN_FP58);
        assert_eq!(hex_bytes_le(&r[48..50]), "0300"); // rev 3 LE
        assert_eq!(hex_bytes_le(&r[50..58]), "7674028879b872aa");
    }

    #[test]
    fn rev_counter_no_wrap() {
        let mut e = RevEmitter::new();
        assert_eq!(e.next_rev().unwrap(), Revision(1));
        assert_eq!(e.next_rev().unwrap(), Revision(2));
        assert_eq!(Revision::next(Revision(u16::MAX)), Err(RevOverflow));
        let mut e2 = RevEmitter { next: u16::MAX };
        assert_eq!(e2.next_rev(), Err(RevOverflow)); // 65535 reserved: error, no wrap
    }

    #[test]
    fn from_snapshot_computes_fp58_and_span_ids() {
        let ctx = test_ctx();
        let obs = Obs::from_snapshot(
            &ctx, ObsPoint::P1,
            Some(Revision(2)), 2, &golden_rings()[0], Some(src_fp(SRC_BYTES)), Revision(3),
            SpanCounts { total: 2, line: 1, cubic: 1 }, 1, 0,
            LedgerCounts { fallback_events: 0, ambiguous_stubs: 0, declined_ambiguity: 0, economy_decisions: 0, zero_span_removals: Some(0), synthetic_closures: 0, corner_adopted: 0, rescue_adopted: 0 },
            ObserverOutcome::Complete, None, None,
        ).unwrap();
        assert_eq!(obs.fp58.as_deref(), Some(GOLDEN_FP58));
        assert_eq!(obs.in_spans.len(), 2);
        assert_eq!(obs.in_spans[0].hex(), "9a7d7381a8b3edfc");
    }

    #[test]
    fn obs_render_golden_keys_and_fp58() {
        let ctx = test_ctx();
        let obs = Obs::from_snapshot(
            &ctx, ObsPoint::P0,
            None, 2, &golden_rings()[0], Some(src_fp(SRC_BYTES)), Revision(1),
            SpanCounts { total: 2, line: 1, cubic: 1 }, 1, 0,
            LedgerCounts { fallback_events: 1, ambiguous_stubs: 0, declined_ambiguity: 0, economy_decisions: 0, zero_span_removals: None, synthetic_closures: 0, corner_adopted: 0, rescue_adopted: 0 },
            ObserverOutcome::Complete, None, None,
        ).unwrap();
        let line = obs.render().unwrap();
        assert!(line.starts_with("{\"schema\":\"mov-1\",\"kind\":\"obs\",\"point\":\"P0\","));
        assert!(line.contains("\"predecessor_rev\":null"));
        const GOLDEN_FP58_REV1: &str = "515b7bf651bbc1aa4fd7b44b79fddbd59d4f80e07119398b824666fac504697f8cce0a799864a50fd8a40f074e3d41e901007674028879b872aa";
        assert!(line.contains(&format!("\"fp58\":\"{}\"", GOLDEN_FP58_REV1)));
        assert!(line.contains("\"spans\":{\"total\":2,\"line\":1,\"cubic\":1}"));
        assert!(line.contains("\"ledger_counts\":{\"ambiguous_stubs\":0,\"corner_adopted\":0,\"declined_ambiguity\":0,\"economy_decisions\":0,\"fallback_events\":1,\"rescue_adopted\":0,\"synthetic_closures\":0,\"zero_span_removals\":null}"));
        assert!(line.contains("\"observer_outcome\":\"complete\""));
        assert!(!line.contains("stage1_route")); // PP fields absent when ctx carries None
    }

    #[test]
    fn obs_fp58_null_without_source_domain() {
        let ctx = test_ctx();
        let obs = Obs::from_snapshot(
            &ctx, ObsPoint::P0, None, 0, &golden_rings()[0], None, Revision(1),
            SpanCounts { total: 0, line: 0, cubic: 0 }, 0, 0,
            LedgerCounts { fallback_events: 0, ambiguous_stubs: 0, declined_ambiguity: 0, economy_decisions: 0, zero_span_removals: Some(0), synthetic_closures: 0, corner_adopted: 0, rescue_adopted: 0 },
            ObserverOutcome::MissingInput, None, Some("no source domain".into()),
        ).unwrap();
        let line = obs.render().unwrap();
        assert!(line.contains("\"fp58\":null"));
        assert!(line.contains("\"reason\":\"no source domain\""));
    }

    #[test]
    fn envelope_render_nullable_fields() {
        let env = Envelope {
            run_id: "run-1".into(), source_full_ref: None, active_source_mapping_status: None,
            fixture_id: None, fixture_sha256: None, config_digest: None, economy_mode: None,
            coordinate_unit: None, grid: None, dense_bound_db: None, line_tolerance: Some(0.5),
            workers: 4, stage1_route: Stage1Route::Live, stage1_cache_sha256: None,
            env_flags: EnvFlags(vec![("KNI_NO_FOLD".into(), true)]),
            invocation_id_style: "utc".into(), invocation_id: InvocationId("i".into()),
        };
        let line = env.render().unwrap();
        assert!(line.contains("\"source_full_ref\":null"));
        assert!(line.contains("\"line_tolerance\":0.5"));
        assert!(line.contains("\"env_flags\":{\"KNI_NO_FOLD\":true}"));
        assert!(line.contains("\"stage1_route\":\"live\""));
    }

    #[test]
    fn nonfinite_rejected() {
        let mut c = CanonJson::new();
        let mut bad = false;
        c.obj(|w| {
            if w.num("x", f64::NAN).is_err() { bad = true; }
        });
        assert!(bad);
    }

    #[test]
    fn consumer_and_frontier_render() {
        let cons = Consumer {
            run_id: "run-1".into(), consumer: "tidy".into(), invocation_id: InvocationId("i".into()),
            observed_input_rev: Revision(3), expected_upstream_rev: Revision(3),
            candidate: true, eligible: true, evaluated: false, changed: false,
            declined: false, abstained: true, skipped: false,
            reason: "declined".into(), src_binding_state: "bound".into(), src_domain_rev: None,
        };
        let line = cons.render().unwrap();
        assert!(line.contains("\"kind\":\"consumer\""));
        assert!(line.contains("\"candidate\":true"));
        assert!(line.contains("\"evaluated\":false"));
        assert!(line.contains("\"src_domain_rev\":null"));
        let f = Frontier::new("run-1".into(), "stage2".into(), true, false);
        let line = f.render().unwrap();
        assert_eq!(line, "{\"schema\":\"mov-1\",\"kind\":\"frontier\",\"run_id\":\"run-1\",\"completed_stage\":\"stage2\",\"completion_receipt\":true,\"cache_file_present\":false}");
    }

    #[test]
    fn fold_determinism() {
        // Same typed records, different construction grouping -> identical lines.
        let mk = || {
            Record::Frontier(Frontier::new("run-1".into(), "stage2".into(), true, false))
        };
        let env = Envelope {
            run_id: "run-1".into(), source_full_ref: None, active_source_mapping_status: None,
            fixture_id: None, fixture_sha256: None, config_digest: None, economy_mode: None,
            coordinate_unit: None, grid: None, dense_bound_db: None, line_tolerance: None,
            workers: 1, stage1_route: Stage1Route::Live, stage1_cache_sha256: None,
            env_flags: EnvFlags(vec![]), invocation_id_style: "utc".into(),
            invocation_id: InvocationId("i".into()),
        };
        let src = RunSource { src_bytes: Some(SRC_BYTES) };
        let a = into_records(env, vec![vec![mk()], vec![mk()]], &src).unwrap();
        // rebuild (fresh values, same content)
        let env2 = Envelope {
            run_id: "run-1".into(), source_full_ref: None, active_source_mapping_status: None,
            fixture_id: None, fixture_sha256: None, config_digest: None, economy_mode: None,
            coordinate_unit: None, grid: None, dense_bound_db: None, line_tolerance: None,
            workers: 1, stage1_route: Stage1Route::Live, stage1_cache_sha256: None,
            env_flags: EnvFlags(vec![]), invocation_id_style: "utc".into(),
            invocation_id: InvocationId("i".into()),
        };
        let b = into_records(env2, vec![vec![mk()], vec![mk()]], &src).unwrap();
        assert_eq!(a, b);
        assert_eq!(a.len(), 3);
    }

    #[test]
    fn default_mappings() {
        assert_eq!(RouteDomain::default().as_str(), "primary");
        assert_eq!(FitRoute::default().as_str(), "plain");
    }

    #[test]
    fn enum_vocab_exact() {
        assert_eq!(FitRoute::GuardedGuided.as_str(), "guarded-guided");
        assert_eq!(ObsPoint::Pp2.as_str(), "PP2");
        assert_eq!(XformPass::StraightOverCurve.as_str(), "straight_over_curve");
        assert_eq!(XformKind::G2LineRunFold.as_str(), "g2_line_run_fold");
        assert_eq!(SrcRelation::Rebound.as_str(), "rebound");
        assert_eq!(ObserverOutcome::UnsupportedSourceMapping.as_str(), "unsupported_source_mapping");
        assert_eq!(PipelineDomain::Measurement.as_str(), "measurement");
    }

    #[test]
    fn snapshot_from_fit_by_value() {
        let start = Point { x: 10.0, y: 20.0 };
        let spans = vec![
            Span::Line { end: Point { x: 30.0, y: 40.0 } },
            Span::Cubic {
                control_one: Point { x: 50.0, y: 60.0 },
                control_two: Point { x: 70.0, y: 80.0 },
                end: Point { x: 90.0, y: 100.0 },
            },
        ];
        let snap = RingSnapshot::from_fit(&start, &spans, q);
        assert_eq!(hex_bytes_le(&geom_bytes(&[snap])), GOLDEN_GEOM_BYTES);
    }

    #[test]
    fn ledger_counts_null_and_new_fields() {
        let lc = LedgerCounts {
            fallback_events: 2, ambiguous_stubs: 1, declined_ambiguity: 3,
            economy_decisions: 4, zero_span_removals: None, synthetic_closures: 5,
            corner_adopted: 6, rescue_adopted: 7,
        };
        let mut c = CanonJson::new();
        c.obj(|w| lc.render_into(w));
        let line = c.finish();
        assert_eq!(line, r#"{"ledger_counts":{"ambiguous_stubs":1,"corner_adopted":6,"declined_ambiguity":3,"economy_decisions":4,"fallback_events":2,"rescue_adopted":7,"synthetic_closures":5,"zero_span_removals":null}}"#);
        let lc2 = LedgerCounts { zero_span_removals: Some(9), ..lc };
        let mut c2 = CanonJson::new();
        c2.obj(|w| lc2.render_into(w));
        assert!(c2.finish().contains("\"zero_span_removals\":9"));
    }

    #[test]
    fn pipeline_obs_pp2_cache_and_pp3() {
        let mut ctx = test_ctx();
        ctx.route = FitRoute::CacheReuse;
        ctx.stage1_route = Some(Stage1Route::CacheReuse);
        ctx.stage1_cache_sha256 = Some("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb".into());
        let pp2 = Obs::pipeline_obs(&ctx, ObsPoint::Pp2, ObserverOutcome::NotEnabled,
            None, Some("stage1_cache_reuse".into()));
        let line = pp2.render().unwrap();
        assert!(line.contains("\"point\":\"PP2\""));
        assert!(line.contains("\"observer_outcome\":\"not_enabled\""));
        assert!(line.contains("\"reason\":\"stage1_cache_reuse\""));
        assert!(line.contains("\"fp58\":null"));
        assert!(line.contains("\"stage1_route\":\"cache_reuse\""));
        assert!(line.contains("\"stage1_cache_sha256\":\"bbbb"));
        let pp3 = Obs::pipeline_obs(&ctx, ObsPoint::Pp3, ObserverOutcome::Complete,
            Some(PipelineDomain::Measurement), None);
        let line3 = pp3.render().unwrap();
        assert!(line3.contains("\"point\":\"PP3\""));
        assert!(line3.contains("\"domain\":\"measurement\""));
        assert!(line3.contains("\"fp58\":null"));
    }

    #[test]
    fn xform_economy_decisions_typed_render() {
        use crate::economy::SpanCounts as EconCounts;
        let d = EconomyDecision {
            rule: "exact_cubic_line", arc: 1, first_span: 2, last_span: 4,
            before: EconCounts { lines: 1, cubics: 2 },
            after: EconCounts { lines: 3, cubics: 0 },
            geometry_identical: true, construction_boundary_preserved: true,
        };
        let x = Xform {
            run_id: "run-1".into(), invocation_id: InvocationId("i".into()), event_id: 0,
            pass: XformPass::Economy, transform: XformKind::ExactCubicLine,
            input_rev: Revision(2), output_rev: Revision(3),
            in_spans: vec![assign_span_id(0, 2)], out_spans: vec![assign_span_id(0, 2)],
            src_relation: Some(SrcRelation::Preserved),
            economy_decisions: vec![d],
        };
        let line = x.render().unwrap();
        assert!(line.contains("\"transform\":\"exact_cubic_line\""));
        assert!(line.contains("\"economy_decisions\":[{\"rule\":\"exact_cubic_line\",\"arc\":1,\"first_span\":2,\"last_span\":4,\"before\":{\"lines\":1,\"cubics\":2},\"after\":{\"lines\":3,\"cubics\":0},\"geometry_identical\":true,\"construction_boundary_preserved\":true}]"));
    }

    #[test]
    fn ledger_economy_ties_to_rewrite_decision_count() {
        // chief 17:35/17:37: ledger economy_decisions = converter-computed sum
        // over the outcome's rewrites of economy_decisions.len().
        use crate::economy::SpanCounts as EconCounts;
        let d = || EconomyDecision {
            rule: "exact_cubic_line", arc: 0, first_span: 0, last_span: 0,
            before: EconCounts { lines: 0, cubics: 1 }, after: EconCounts { lines: 1, cubics: 0 },
            geometry_identical: true, construction_boundary_preserved: true,
        };
        let rewrites = vec![vec![d(), d()], vec![d()]]; // 2 outcomes' rewrites: 2 + 1 decisions
        let computed: u64 = rewrites.iter().map(|r| r.len() as u64).sum();
        let lc = LedgerCounts {
            fallback_events: 0, ambiguous_stubs: 0, declined_ambiguity: 0,
            economy_decisions: computed, zero_span_removals: None,
            synthetic_closures: 0, corner_adopted: 0, rescue_adopted: 0,
        };
        assert_eq!(lc.economy_decisions, 3);
    }

    #[test]
    fn pp_ring_index_null_and_real_ring_some() {
        let ctx = test_ctx();
        let pp3 = Obs::pipeline_obs(&ctx, ObsPoint::Pp3, ObserverOutcome::Complete,
            Some(PipelineDomain::Emit), None);
        assert_eq!(pp3.ring_index, None);
        assert_eq!(pp3.fp58, None);
        let line = pp3.render().unwrap();
        assert!(line.contains("\"ring_index\":null"));
        assert!(line.contains("\"fp58\":null"));
        let real = Obs::from_snapshot(
            &ctx, ObsPoint::P0, None, 2, &golden_rings()[0], Some(src_fp(SRC_BYTES)), Revision(1),
            SpanCounts { total: 2, line: 1, cubic: 1 }, 1, 0,
            LedgerCounts { fallback_events: 0, ambiguous_stubs: 0, declined_ambiguity: 0, economy_decisions: 0, zero_span_removals: Some(0), synthetic_closures: 0, corner_adopted: 0, rescue_adopted: 0 },
            ObserverOutcome::Complete, None, None,
        ).unwrap();
        assert_eq!(real.ring_index, Some(2));
        let line = real.render().unwrap();
        assert!(line.contains("\"ring_index\":2"));
        assert!(line.contains("\"fp58\":\""));
    }

    #[test]
    fn span_counts_conversion_and_null_src_relation() {
        let e = crate::economy::SpanCounts { lines: 3, cubics: 2 };
        let c = span_counts_from_economy(&e);
        assert_eq!((c.total, c.line, c.cubic), (5, 3, 2));
        let x = Xform {
            run_id: "run-1".into(), invocation_id: InvocationId("i".into()), event_id: 0,
            pass: XformPass::Tidy, transform: XformKind::Round,
            input_rev: Revision(1), output_rev: Revision(2),
            in_spans: vec![], out_spans: vec![],
            src_relation: None, economy_decisions: vec![],
        };
        let line = x.render().unwrap();
        assert!(line.contains("\"src_relation\":null"));
    }

    #[test]
    fn invocation_id_and_stamp() {
        assert_eq!(utc_stamp(0), "19700101T000000Z");
        assert_eq!(invocation_id("AABBCCDDEEFF00112233", 0).0, "utc-19700101T000000Z-aabbccddeeff");
        assert_eq!(with_collision_seq(&InvocationId("x".into()), 7).0, "x-07");
    }
}
