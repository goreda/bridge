//! SliceC emission-lane plug: decompose is the default structure lane
//! (chief 2026-10-18 20:17 "implement wiring with SliceC", 20:55 "ship
//! blocker"). Contract, chief-accepted with the four 20:16 amendments:
//!
//! Input:  (glyph_name, rings: &[ReferenceRing], advance) plus a shared
//!         PartRegistry across the font.
//! Output: Parts { shapes } or ExactCarry { reason }, plus one typed
//!         ledger row per glyph (`master_glyphs_parts_residual` rows are
//!         the ExactCarry ones).
//!
//! Amendment pins honored here:
//! 1. Ring-type conversion is pinned AT THE PLUG: `reference_ring_to_contour`
//!    below is the single ReferenceRing -> StrokeContour conversion point
//!    (Move(start), one op per span, Close).
//! 2. PartShape carries no holes; a holed part is emitted as a minted
//!    part glyph in the registry (Component form), holes riding the glyph.
//! 3. IoU ledger conventions: px = max-bbox-span/640, nonzero winding,
//!    union over all part rings INCLUDING holes, 6 decimals in rows.
//! 4. ExactCarry reason enum + part glyph names <glyph>._part.<class>
//!    (duplicates suffixed .2/.3), part advance = 0, no-export.
//! 5. Owner rule armed 2026-10-18 21:36 (chief-formalized, SliceC pin v2):
//!    every minted part's ink stays inside the source glyph silhouette on
//!    the pinned ledger grid; any part with outside_px > 0 flips the
//!    glyph to ExactCarry PartProtrusion (gate preempts LowIoU).
//!
//! Chief-accepted lane conventions (20:55): LOW_IOU_CARRY_THRESHOLD =
//! 0.99; typed DecomposeError Structure/PixelBudget maps to
//! AmbiguousStructure; panics are bugs and never reach this contract.

use crate::decompose::{decompose_with, DecomposeError, DecomposeParams};
use crate::model::{MasterGlyph, Op, Pt, StrokeContour};
use crate::raster::{bounds_of, rasterize};
use kni_core::reference_slice::{ReferenceRing, Span};
use std::collections::HashMap;

/// Union IoU below which the lane carries the source outline exactly.
/// Chief-accepted convention 2026-10-18 20:55.
pub const LOW_IOU_CARRY_THRESHOLD: f64 = 0.99;

/// Why the lane kept the source outline instead of decomposed parts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExactCarryReason {
    EmptyOutline,
    /// Reserved for a lane-side timeout; decompose itself always returns.
    NonTerminating,
    LowIoU,
    AmbiguousStructure,
    /// Owner rule 2026-10-18 21:36: a minted part carried ink outside the
    /// source glyph silhouette on the pinned ledger grid. Requirement:
    /// outside_px = 0 for EVERY part; overlaps between parts are legal
    /// only inside the silhouette (owner h pattern), and a protrusion
    /// carved back by another part's counter ring is still a violation.
    PartProtrusion,
}

/// One shape of a decomposed glyph: a reference to a minted part glyph
/// with placement. Identity placement: parts are minted in glyph
/// coordinates, so pos = (0,0), scale = 1, angle = 0.
#[derive(Debug, Clone)]
pub enum PartShape {
    Component {
        part_glyph: String,
        pos: Pt,
        scale: f64,
        angle: f64,
        alignment: Option<String>,
        anchor: Option<Pt>,
    },
    Path(StrokeContour),
}

#[derive(Debug, Clone)]
pub struct Parts {
    pub shapes: Vec<PartShape>,
}

#[derive(Debug, Clone)]
pub enum PartsOut {
    Parts(Parts),
    ExactCarry { reason: ExactCarryReason },
}

/// A part glyph minted into the shared registry: no-export, advance 0,
/// holes carried as counter rings (opposite winding, per Decomposition).
#[derive(Debug, Clone)]
pub struct MintedPartGlyph {
    pub name: String,
    pub contour: StrokeContour,
    pub holes: Vec<StrokeContour>,
    pub advance: f64,
    pub export: bool,
}

/// Shared part registry across the font: one mint per (glyph, part).
#[derive(Debug, Default)]
pub struct PartRegistry {
    pub minted: Vec<MintedPartGlyph>,
}

impl PartRegistry {
    fn mint(&mut self, source_glyph: &str, class: crate::decompose::PartClass, contour: StrokeContour, holes: Vec<StrokeContour>, counts: &mut HashMap<String, u32>) -> String {
        let base = format!("{class:?}").to_lowercase();
        let k = counts.entry(base.clone()).or_default();
        *k += 1;
        let name = if *k == 1 {
            format!("{source_glyph}._part.{base}")
        } else {
            format!("{source_glyph}._part.{base}.{k}")
        };
        self.minted.push(MintedPartGlyph { name: name.clone(), contour, holes, advance: 0.0, export: false });
        name
    }
}

/// Typed per-glyph ledger row. `reason` is Some exactly for the
/// `master_glyphs_parts_residual` rows (ExactCarry).
#[derive(Debug, Clone)]
pub struct WireLedgerRow {
    pub glyph: String,
    pub parts: usize,
    pub iou: f64,
    pub reason: Option<ExactCarryReason>,
    /// Row-format note token (chief 2026-10-18 21:04: pinned as part of the
    /// row format). Single lowercase-hyphen token, never contains spaces.
    /// Defined values: `no-usable-contours` (input carried zero usable
    /// rings). Any new value is a contract change.
    pub note: Option<&'static str>,
}

/// Canonical pinned row grammar (SliceC row pin target):
///
///   parts-row = "glyph " name " PARTS n=" count " iou " iou6 " parts [" names "]"
///   carry-row = "glyph " name " EXACTCARRY reason=" reason " iou " iou6 [ " note=" token ]
///   iou6      = fixed six decimals; separator is a SPACE on both row kinds
///   names     = ", "-joined minted part names in emission order
///   token     = [a-z0-9-]+, defined: no-usable-contours
///
///   header    = "wire-summary glyphs " G " parts " P " exactcarry " C
///               " panics " X " minted " M " reasons " reasons-json
///   reasons-json: JSON object, keys sorted (BTreeMap order); M = parts
///   glyphs minted into the registry this font (publish gate: M > 0).
impl WireLedgerRow {
    /// Emit the canonical row. `names` is the emitted part-name list for
    /// PARTS rows (empty on carries).
    pub fn to_line(&self, names: &[String]) -> String {
        match self.reason {
            None => format!("glyph {} PARTS n={} iou {:.6} parts [{}]", self.glyph, self.parts, self.iou, names.join(", ")),
            Some(r) => {
                let mut line = format!("glyph {} EXACTCARRY reason={r:?} iou {:.6}", self.glyph, self.iou);
                if let Some(n) = self.note {
                    line.push_str(" note=");
                    line.push_str(n);
                }
                line
            }
        }
    }
}

/// Canonical header line (pin target; `minted` = registry mints this run,
/// the publish gate's parts>0 check).
pub fn wire_summary_line(glyphs: usize, parts: usize, carries: usize, panics: usize, minted: usize, reasons: &std::collections::BTreeMap<String, u32>) -> String {
    let kv: Vec<String> = reasons.iter().map(|(k, v)| format!("\"{k}\": {v}")).collect();
    format!("wire-summary glyphs {glyphs} parts {parts} exactcarry {carries} panics {panics} minted {minted} reasons {{{}}}", kv.join(", "))
}

/// The single ReferenceRing -> StrokeContour conversion point (amendment 1).
/// 1:1: Move(start), one Line/Curve per span, Close. No tolerance, no
/// normalization, no implicit chord.
pub fn reference_ring_to_contour(r: &ReferenceRing) -> StrokeContour {
    let mut ops = Vec::with_capacity(r.spans.len() + 2);
    ops.push(Op::Move((r.start.x, r.start.y)));
    for s in &r.spans {
        match *s {
            Span::Line { end } => ops.push(Op::Line((end.x, end.y))),
            Span::Cubic { control_one, control_two, end } => {
                ops.push(Op::Curve((control_one.x, control_one.y), (control_two.x, control_two.y), (end.x, end.y)))
            }
        }
    }
    ops.push(Op::Close);
    StrokeContour { stroke: String::new(), ops }
}

/// Union IoU of the decomposition against the source under the pinned
/// ledger conventions (px = max-bbox-span/640, nonzero winding, union
/// over every part ring including holes).
/// The pinned ledger grid, shared by wire_iou and the protrusion gate so
/// both measure the identical rasterization (px = max-bbox-span/640,
/// nonzero winding, offset (0.5, 0.5), boundary inclusive). Returns
/// (width, height, source silhouette mask, per-part masks in emission
/// order); each part mask is its outer ring MINUS its counter rings,
/// exactly as wire_iou's union step treats them.
/// Fine flattening (256 samples per curve segment) for the protrusion/IoU
/// raster gate. check::stroke_polygon uses 32 samples per segment, so a
/// part cut from a curve (flattened over a shorter piece) is traced more
/// finely than the source it came from; the chord gap then reads as ink
/// outside the source. Measured on Marq h: outside_px 1/3/21 at grid
/// 640/1280/2560, growing with grid, while piece boundaries are exact
/// splits of the source segments. Both sides use this one flattening so
/// only genuine protrusion remains visible.
fn fine_polygon(c: &StrokeContour) -> Vec<Pt> {
    use crate::model::SegKind;
    let mut poly = Vec::new();
    for s in c.segments() {
        match s.kind {
            SegKind::Line => poly.push(s.p0),
            SegKind::Curve => {
                let (p0, c1, c2, p1) = (s.p0, s.c1.unwrap(), s.c2.unwrap(), s.p1);
                for i in 0..256 {
                    let t = i as f64 / 256.0;
                    let mt = 1.0 - t;
                    poly.push((
                        mt * mt * mt * p0.0 + 3.0 * mt * mt * t * c1.0 + 3.0 * mt * t * t * c2.0 + t * t * t * p1.0,
                        mt * mt * mt * p0.1 + 3.0 * mt * mt * t * c1.1 + 3.0 * mt * t * t * c2.1 + t * t * t * p1.1,
                    ));
                }
            }
        }
    }
    poly
}

pub fn pinned_masks(src_contours: &[StrokeContour], d: &crate::decompose::Decomposition) -> (usize, usize, Vec<bool>, Vec<Vec<bool>>) {
    pinned_masks_at(src_contours, d, 640)
}

/// pinned_masks at a caller-chosen grid resolution. Diagnostic probe only:
/// the production gate stays pinned to 640 via pinned_masks.
pub fn pinned_masks_at(src_contours: &[StrokeContour], d: &crate::decompose::Decomposition, grid: u32) -> (usize, usize, Vec<bool>, Vec<Vec<bool>>) {
    let src_polys: Vec<Vec<Pt>> = src_contours.iter().map(fine_polygon).collect();
    let bnds = bounds_of(&[&src_polys], 2.0);
    let span = (bnds.2 - bnds.0).max(bnds.3 - bnds.1);
    let px = span / f64::from(grid);
    let (w, h, src) = rasterize(&src_polys, true, bnds, px, (0.5, 0.5));
    let parts = d
        .parts
        .iter()
        .map(|p| {
            let polys: Vec<Vec<Pt>> = std::iter::once(&p.contour).chain(p.holes.iter()).map(fine_polygon).collect();
            let (_, _, m) = rasterize(&polys, true, bnds, px, (0.5, 0.5));
            m
        })
        .collect();
    (w, h, src, parts)
}

/// Union IoU over pre-rasterized pinned-grid masks.
fn union_iou_of(src: &[bool], parts: &[Vec<bool>]) -> f64 {
    let mut union = vec![false; src.len()];
    for m in parts {
        for i in 0..src.len() {
            union[i] |= m[i];
        }
    }
    let inter = union.iter().zip(src).filter(|(&u, &s)| u && s).count();
    let uni = union.iter().zip(src).filter(|(&u, &s)| u || s).count();
    inter as f64 / uni.max(1) as f64
}

pub fn wire_iou(src_contours: &[StrokeContour], d: &crate::decompose::Decomposition) -> f64 {
    let (_, _, src, parts) = pinned_masks(src_contours, d);
    union_iou_of(&src, &parts)
}

/// Per-part ink pixels outside the source silhouette on the pinned ledger
/// grid (owner rule 2026-10-18 21:36 CHECK), in emission order.
pub fn part_outside_px(src_contours: &[StrokeContour], d: &crate::decompose::Decomposition) -> Vec<usize> {
    part_outside_px_at(src_contours, d, 640)
}

/// part_outside_px at a caller-chosen grid resolution (diagnostic probe).
pub fn part_outside_px_at(src_contours: &[StrokeContour], d: &crate::decompose::Decomposition, grid: u32) -> Vec<usize> {
    let (_, _, src, parts) = pinned_masks_at(src_contours, d, grid);
    parts.iter().map(|m| m.iter().zip(src.iter()).filter(|(&p, &s)| p && !s).count()).collect()
}

/// The lane decision, factored for direct testing: parts and IoU in,
/// Parts vs ExactCarry out. Boundary is inclusive: exactly the threshold
/// stays PARTS.
pub fn decide(part_count: usize, iou: f64) -> PartsOut {
    if iou < LOW_IOU_CARRY_THRESHOLD {
        PartsOut::ExactCarry { reason: ExactCarryReason::LowIoU }
    } else {
        let _ = part_count;
        PartsOut::Parts(Parts { shapes: Vec::new() })
    }
}

/// The lane decision with the owner-rule protrusion gate armed
/// (2026-10-18 21:36 PLUG GATE): any part with outside_px > 0 flips the
/// glyph to ExactCarry PartProtrusion. Gate precedence: PartProtrusion
/// preempts LowIoU when both apply (protrusion is the validity gate;
/// LowIoU measures coverage). Zero outside_px everywhere falls through
/// to the unchanged IoU threshold.
pub fn decide_gated(part_count: usize, iou: f64, outside_px: &[usize]) -> PartsOut {
    if outside_px.iter().any(|&n| n > 0) {
        PartsOut::ExactCarry { reason: ExactCarryReason::PartProtrusion }
    } else {
        decide(part_count, iou)
    }
}

/// The plug: one glyph of supplied rings in, Parts or ExactCarry plus the
/// typed ledger row out. Minted part glyphs accumulate in `registry`.
/// `upm` is fixed at 1000 by the reader contract (cff_reader rejects
/// anything else); decompose's raster scale is self-scaling via
/// px = span/640, so upm carries no geometry here.
pub fn decompose_rings_into_parts(
    glyph_name: &str,
    rings: &[ReferenceRing],
    advance: f64,
    registry: &mut PartRegistry,
    params: &DecomposeParams,
) -> (PartsOut, WireLedgerRow) {
    let no_usable = rings.is_empty();
    let contours: Vec<StrokeContour> = rings.iter().map(reference_ring_to_contour).collect();
    let g = MasterGlyph { name: glyph_name.to_string(), advance, upm: 1000.0, contours };
    let d = match decompose_with(&g, params) {
        Ok(d) => d,
        Err(DecomposeError::EmptyOutline) => {
            return (
                PartsOut::ExactCarry { reason: ExactCarryReason::EmptyOutline },
                WireLedgerRow {
                    glyph: glyph_name.into(),
                    parts: 0,
                    iou: 1.0,
                    reason: Some(ExactCarryReason::EmptyOutline),
                    note: if no_usable { Some("no-usable-contours") } else { None },
                },
            );
        }
        Err(_) => {
            return (
                PartsOut::ExactCarry { reason: ExactCarryReason::AmbiguousStructure },
                WireLedgerRow { glyph: glyph_name.into(), parts: 0, iou: 1.0, reason: Some(ExactCarryReason::AmbiguousStructure), note: None },
            );
        }
    };
    let (_, _, src, part_masks) = pinned_masks(&g.contours, &d);
    let iou = union_iou_of(&src, &part_masks);
    let outside_px: Vec<usize> = part_masks
        .iter()
        .map(|m| m.iter().zip(src.iter()).filter(|(&p, &s)| p && !s).count())
        .collect();
    if let PartsOut::ExactCarry { reason } = decide_gated(d.parts.len(), iou, &outside_px) {
        return (
            PartsOut::ExactCarry { reason },
            WireLedgerRow { glyph: glyph_name.into(), parts: d.parts.len(), iou, reason: Some(reason), note: None },
        );
    }
    let mut counts = HashMap::new();
    let shapes: Vec<PartShape> = d
        .parts
        .into_iter()
        .map(|p| {
            let name = registry.mint(glyph_name, p.class, p.contour, p.holes, &mut counts);
            PartShape::Component { part_glyph: name, pos: (0.0, 0.0), scale: 1.0, angle: 0.0, alignment: None, anchor: None }
        })
        .collect();
    let n = shapes.len();
    (PartsOut::Parts(Parts { shapes }), WireLedgerRow { glyph: glyph_name.into(), parts: n, iou, reason: None, note: None })
}
