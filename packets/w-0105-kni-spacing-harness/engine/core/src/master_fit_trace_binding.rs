//! Structural binding between a supplied `MasterFitResult` and a supplied
//! `MasterFitTrace` (measurement-only identity map).
//!
//! STRUCTURAL_BINDING_ONLY. Both inputs are public mutable structs and are
//! not cryptographically linked: the shape/kind checks here cannot prove the
//! two values came from the same run, the same source captures, or the same
//! coordinates. This module provides NO authenticated provenance and NO
//! geometry validation. `source_pin` values are carried as the supplied
//! claims, unverified. Raw indices (`start_map`, `raw_interval`, split
//! chains) are carried as supplied: each names a position in the
//! corresponding supplied master's captured ring `raw` point array (the
//! trace's own index space), not a CaptureLineage pre-reversal tracer
//! index. Without the `MasterSet` and its raw ring lengths their bounds are
//! explicitly UNVERIFIED, and no frame, grid or precision validation is
//! implied. Trace identity is scoped to this supplied fit result/topology
//! and is NOT stable across refits.
//!
//! The binding never reads coordinates to match identity, never mutates or
//! refits outlines, and adds no serialization, registry or production
//! wiring. Span geometry is not copied; only identity data is cloned.
//!
//! Validation order: the canonical per-column leaf-sequence guard (path and
//! kind, in DFS order) runs BEFORE per-emission structural walks. Variants a
//! mutated input would trip earlier through that guard (`MalformedPath`,
//! `PathIntoLeaf`, `NonTerminalPath`, `LeafKindMismatch`), or that the
//! per-column canonical guards plus exact span-index order already preclude
//! (`OrderedLeafCountMismatch`, `OrderedLeafMismatch`), are DEFENSIVE:
//! retained as defense in depth, not tested coverage. `ResultKindMismatch`
//! and the split-record
//! walk checks remain reachable. Column entries must appear in column-ID
//! order (position == column id); a shuffle keeping the same id set is
//! rejected, never reindexed. Span indices must match the canonical
//! per-ring concatenation exactly (0,1,2,... over columns in ID order, DFS
//! leaf order within each); input is never sorted or rewritten to fit.

use crate::cubic_fit::FitPolicy;
use crate::master_fit_context::{
    fit_master_set_traced, AxisCoordinate, DecisionNode, MasterFitError, MasterFitResult,
    MasterFitTrace, MasterSet, SpanEmission, SpanKind, MAX_SPLIT_DEPTH,
};
use crate::reference_slice::Span;
use std::collections::BTreeMap;

/// Scope of every binding produced here: structural identity only, never
/// authenticated provenance or geometry validation.
pub const BINDING_SCOPE: &str = "STRUCTURAL_BINDING_ONLY";

/// Identity binding of one supplied fit result to one supplied trace.
#[derive(Clone, Debug, PartialEq)]
pub struct MasterFitTraceBinding {
    /// Always `BINDING_SCOPE`.
    pub scope: &'static str,
    pub glyph_id: String,
    /// Receipt carried verbatim from the supplied result; never re-derived.
    pub receipt: String,
    /// Policy echoes carried exactly as supplied by the trace; no
    /// synthesized defaults. `split_fraction` is the DECLARED split target
    /// constant, never a measured per-master fraction (measured fractions
    /// live in `SplitRecord::actual_fraction`, not in this binding).
    pub squared_error: f64,
    pub max_refits: usize,
    pub tangent_lookahead_fraction: f64,
    pub max_split_depth: usize,
    /// DECLARED split target as supplied; not a measured fraction.
    pub split_fraction: f64,
    pub masters: Vec<MasterBinding>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct MasterBinding {
    /// Index into the supplied result/trace master order.
    pub master_index: usize,
    pub master_id: String,
    pub axes: Vec<AxisCoordinate>,
    /// The supplied claim, unverified.
    pub source_pin: String,
    pub rings: Vec<RingBinding>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct RingBinding {
    pub correspondence_id: String,
    /// Position in the supplied master's captured ring array, as supplied
    /// by the trace's ring map; bounds UNVERIFIED (no MasterSet here).
    pub captured_ring_index: usize,
    /// Position in that ring's `raw` point array, as supplied by the
    /// trace's start map; bounds UNVERIFIED.
    pub start_raw_index: usize,
    /// 1:1 with the result ring's spans, same order.
    pub spans: Vec<SpanBinding>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct SpanBinding {
    pub span_index_in_ring: usize,
    pub kind: SpanKind,
    pub source_column: usize,
    /// L/R leaf path of the deciding leaf in the column's decision tree.
    pub source_path: String,
    /// This master's wrapped raw interval of the source column, as
    /// supplied: (start, end) positions in the ring's `raw` point array;
    /// bounds UNVERIFIED.
    pub column_raw_interval: (usize, usize),
    /// `SplitRecord.selected_raw_index` down `source_path`, in traversal
    /// order; each a position in the supplied master's captured ring `raw`
    /// point array, as supplied; bounds UNVERIFIED.
    pub split_chain: Vec<usize>,
}

/// Which glyph-id slot disagreed with the result's glyph id.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GlyphIdLocation {
    Trace,
    Outline { master_index: usize },
}

/// Which master-indexed map of the trace failed validation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MapKind {
    RingMap,
    StartMap,
    RawInterval,
}

/// Typed binding errors. Every malformed-input path returns one of these:
/// recursion is bounded by `MAX_SPLIT_DEPTH`, and no unwrap/expect or
/// unchecked indexing is used on malformed public input.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TraceBindingError {
    /// `compatible_topology=false` in the supplied result.
    CompatibleTopologyFalse,
    /// Degenerate empty structure: no masters / no rings / a ring with no
    /// columns / a result ring with no spans.
    EmptyMasters,
    EmptyRings,
    EmptyColumnSet { ring: usize },
    EmptyResultRing { ring: usize, master_index: usize },
    GlyphIdMismatch { location: GlyphIdLocation, expected: String, found: String },
    MasterCountMismatch { result: usize, trace: usize },
    MasterIdMismatch { index: usize, result_id: String, trace_id: String },
    DuplicateMasterId { master_id: String },
    RingCountMismatch { master_index: usize, result: usize, trace: usize },
    EmptyCorrespondenceId { ring: usize },
    DuplicateCorrespondenceId { correspondence_id: String },
    /// ring_map reused one captured ring for two correspondences in one master.
    CapturedRingReused { master_index: usize, captured_ring_index: usize, first_ring: usize, second_ring: usize },
    MasterMapOutOfRange { ring: usize, column: Option<usize>, map: MapKind, master_index: usize },
    MasterMapDuplicate { ring: usize, column: Option<usize>, map: MapKind, master_index: usize },
    MasterMapMissing { ring: usize, column: Option<usize>, map: MapKind, master_index: usize },
    ColumnIdOutOfRange { ring: usize, column: usize },
    ColumnIdDuplicate { ring: usize, column: usize },
    ColumnIdMissing { ring: usize, column: usize },
    /// Producer contract: a column entry's position in `columns` must equal
    /// its `column` id. A shuffle keeping the same id set is rejected;
    /// never reindexed.
    ColumnIdOutOfOrder { ring: usize, position: usize, column: usize },
    /// start_map entry differs from the first column's raw start.
    StartMapMismatch { ring: usize, master_index: usize, start_map: usize, first_column_start: usize },
    /// Adjacent columns do not join: column end != next column start.
    ColumnJoinMismatch { ring: usize, master_index: usize, column: usize, end: usize, next_start: usize },
    /// Final column end does not wrap to the first column start.
    ColumnWrapMismatch { ring: usize, master_index: usize, last_end: usize, first_start: usize },
    /// A Split node's stored path/depth disagrees with DFS traversal.
    SplitPathMismatch { ring: usize, column: usize, expected: String, found: String },
    SplitDepthMismatch { ring: usize, column: usize, path: String, expected: usize, found: usize },
    EmissionMasterIndexOutOfRange { ring: usize, column: usize, master_index: usize },
    /// An emission's named source_column differs from the column containing it.
    SourceColumnMismatch { ring: usize, containing_column: usize, named_column: usize },
    /// One master's emission list in one column is not exactly the canonical
    /// DFS terminal list, in order, exactly once.
    ColumnLeafCountMismatch { ring: usize, column: usize, master_index: usize, emissions: usize, terminals: usize },
    ColumnLeafSequenceMismatch { ring: usize, column: usize, master_index: usize, position: usize },
    SpanIndexOutOfRange { ring: usize, master_index: usize, span_index: usize, ring_len: usize },
    SpanIndexDuplicate { ring: usize, master_index: usize, span_index: usize },
    /// `span_index_in_ring` must equal the emission's position in the
    /// canonical per-ring concatenation (columns 0..ncols in column-ID
    /// order, then canonical DFS leaf order within each column): exactly
    /// 0,1,2,... in that order. Input is never sorted or rewritten to fit.
    SpanIndexOutOfOrder { ring: usize, master_index: usize, column: usize, expected: usize, found: usize },
    /// A result-ring span index received no emission. REACHABLE: exact
    /// order proves the master's emissions map onto 0..M-1 in order
    /// (injection), not that they cover the result ring (surjection); a
    /// result ring longer than the canonical emission count leaves the
    /// tail unset and is rejected here.
    SpanIndexHole { ring: usize, master_index: usize, span_index: usize },
    /// DEFENSIVE after the canonical sequence guard: a path disagreeing
    /// with the canonical DFS terminal list is rejected as
    /// `ColumnLeafSequenceMismatch` first. Not tested coverage.
    MalformedPath { ring: usize, column: usize, path: String },
    /// DEFENSIVE after the canonical sequence guard (see `MalformedPath`).
    PathIntoLeaf { ring: usize, column: usize, path: String },
    /// DEFENSIVE after the canonical sequence guard (see `MalformedPath`).
    NonTerminalPath { ring: usize, column: usize, path: String },
    SplitMasterIndexOutOfRange { ring: usize, column: usize, path: String, master_index: usize },
    SplitRecordMissing { ring: usize, column: usize, path: String, master_index: usize },
    SplitRecordDuplicate { ring: usize, column: usize, path: String, master_index: usize },
    /// Terminal leaf kind differs from the emitted span kind. DEFENSIVE
    /// after the canonical sequence guard, which compares kind first (see
    /// `MalformedPath`). Not tested coverage.
    LeafKindMismatch { ring: usize, master_index: usize, span_index: usize, leaf: SpanKind, emitted: SpanKind },
    /// Emitted span kind differs from the actual result span kind.
    /// REACHABLE: a result-side span variant change with a coherent trace
    /// passes the sequence guard and is rejected here.
    ResultKindMismatch { ring: usize, master_index: usize, span_index: usize, emitted: SpanKind, result: SpanKind },
    /// DEFENSIVE after the canonical guards: per-column count+sequence
    /// checks plus the exact canonical span-index order already force every
    /// master's ordered (column, path, kind) leaf list onto the same
    /// canonical concatenation. Retained as defense in depth, not tested
    /// coverage.
    OrderedLeafCountMismatch { master_index: usize, expected: usize, found: usize },
    /// DEFENSIVE after the canonical guards (see `OrderedLeafCountMismatch`).
    OrderedLeafMismatch { master_index: usize, position: usize },
    /// A decision-tree node sits deeper than `MAX_SPLIT_DEPTH`, the engine's
    /// own declared recursion bound for these trees; no tree the fitter
    /// produces exceeds it. Keeps recursion over this public input bounded.
    TreeDepthExceeded { ring: usize, column: usize, path: String, depth: usize, bound: usize },
}

fn span_kind(span: &Span) -> SpanKind {
    match span {
        Span::Line { .. } => SpanKind::Line,
        Span::Cubic { .. } => SpanKind::Cubic,
    }
}

/// Exactly one (master_index -> value) entry per valid master index; rejects
/// out-of-range, duplicate and missing entries. Values themselves are NOT
/// bounds-checked (no MasterSet/raw counts available).
fn map_pairs(
    entries: &[(usize, usize)],
    nm: usize,
    ring: usize,
    column: Option<usize>,
    map: MapKind,
) -> Result<Vec<usize>, TraceBindingError> {
    let mut out: Vec<Option<usize>> = vec![None; nm];
    for &(mi, v) in entries {
        if mi >= nm {
            return Err(TraceBindingError::MasterMapOutOfRange { ring, column, map, master_index: mi });
        }
        if out[mi].is_some() {
            return Err(TraceBindingError::MasterMapDuplicate { ring, column, map, master_index: mi });
        }
        out[mi] = Some(v);
    }
    let mut res = Vec::with_capacity(nm);
    for (mi, e) in out.into_iter().enumerate() {
        let Some(v) = e else {
            return Err(TraceBindingError::MasterMapMissing { ring, column, map, master_index: mi });
        };
        res.push(v);
    }
    Ok(res)
}

/// Same contract for raw_interval triples (master_index, start, end);
/// returns (start, end) per master. Bounds UNVERIFIED.
fn map_triples(
    entries: &[(usize, usize, usize)],
    nm: usize,
    ring: usize,
    column: usize,
) -> Result<Vec<(usize, usize)>, TraceBindingError> {
    let mut out: Vec<Option<(usize, usize)>> = vec![None; nm];
    for &(mi, a, b) in entries {
        if mi >= nm {
            return Err(TraceBindingError::MasterMapOutOfRange { ring, column: Some(column), map: MapKind::RawInterval, master_index: mi });
        }
        if out[mi].is_some() {
            return Err(TraceBindingError::MasterMapDuplicate { ring, column: Some(column), map: MapKind::RawInterval, master_index: mi });
        }
        out[mi] = Some((a, b));
    }
    let mut res = Vec::with_capacity(nm);
    for (mi, e) in out.into_iter().enumerate() {
        let Some(v) = e else {
            return Err(TraceBindingError::MasterMapMissing { ring, column: Some(column), map: MapKind::RawInterval, master_index: mi });
        };
        res.push(v);
    }
    Ok(res)
}

/// Canonical DFS terminal list of one column tree (left before right, the
/// order spans are emitted in). Validates each Split node's stored path and
/// depth against the traversal.
fn dfs_terminals(
    node: &DecisionNode,
    path: String,
    depth: usize,
    ring: usize,
    column: usize,
    out: &mut Vec<(String, SpanKind)>,
) -> Result<(), TraceBindingError> {
    if depth > MAX_SPLIT_DEPTH {
        return Err(TraceBindingError::TreeDepthExceeded { ring, column, path, depth, bound: MAX_SPLIT_DEPTH });
    }
    match node {
        DecisionNode::AllStraight => {
            out.push((path, SpanKind::Line));
            Ok(())
        }
        DecisionNode::AllCubic => {
            out.push((path, SpanKind::Cubic));
            Ok(())
        }
        DecisionNode::Split { depth: d, path: p, left, right, .. } => {
            if *p != path {
                return Err(TraceBindingError::SplitPathMismatch { ring, column, expected: path, found: p.clone() });
            }
            if *d != depth {
                return Err(TraceBindingError::SplitDepthMismatch { ring, column, path, expected: depth, found: *d });
            }
            let mut lp = path.clone();
            lp.push('L');
            dfs_terminals(left, lp, depth + 1, ring, column, out)?;
            let mut rp = path;
            rp.push('R');
            dfs_terminals(right, rp, depth + 1, ring, column, out)
        }
    }
}

/// Walk one emission's L/R path from the column root to its terminal leaf,
/// collecting this master's absolute raw split index at each traversed
/// split. Exactly one split record per master per traversed split is
/// required; master indices in traversed splits must be valid.
fn walk_split_chain(
    root: &DecisionNode,
    path: &str,
    mi: usize,
    nm: usize,
    ring: usize,
    column: usize,
) -> Result<(SpanKind, Vec<usize>), TraceBindingError> {
    let mut node = root;
    let mut chain = Vec::new();
    for ch in path.chars() {
        match node {
            DecisionNode::Split { splits, left, right, .. } => {
                let mut found: Option<usize> = None;
                for s in splits {
                    if s.master_index >= nm {
                        return Err(TraceBindingError::SplitMasterIndexOutOfRange {
                            ring, column, path: path.to_string(), master_index: s.master_index,
                        });
                    }
                    if s.master_index == mi {
                        if found.is_some() {
                            return Err(TraceBindingError::SplitRecordDuplicate {
                                ring, column, path: path.to_string(), master_index: mi,
                            });
                        }
                        found = Some(s.selected_raw_index);
                    }
                }
                let Some(raw) = found else {
                    return Err(TraceBindingError::SplitRecordMissing {
                        ring, column, path: path.to_string(), master_index: mi,
                    });
                };
                chain.push(raw);
                if chain.len() > MAX_SPLIT_DEPTH {
                    return Err(TraceBindingError::TreeDepthExceeded {
                        ring, column, path: path.to_string(), depth: chain.len() - 1, bound: MAX_SPLIT_DEPTH,
                    });
                }
                node = match ch {
                    'L' => left.as_ref(),
                    'R' => right.as_ref(),
                    _ => return Err(TraceBindingError::MalformedPath { ring, column, path: path.to_string() }),
                };
            }
            DecisionNode::AllStraight | DecisionNode::AllCubic => {
                return Err(TraceBindingError::PathIntoLeaf { ring, column, path: path.to_string() });
            }
        }
    }
    match node {
        DecisionNode::AllStraight => Ok((SpanKind::Line, chain)),
        DecisionNode::AllCubic => Ok((SpanKind::Cubic, chain)),
        DecisionNode::Split { .. } => Err(TraceBindingError::NonTerminalPath { ring, column, path: path.to_string() }),
    }
}

/// Pure structural bind of a supplied result to a supplied trace. All
/// length equality is checked explicitly before any pairing; no truncating
/// zip is relied on anywhere.
pub fn bind_master_fit_trace(
    result: &MasterFitResult,
    trace: &MasterFitTrace,
) -> Result<MasterFitTraceBinding, TraceBindingError> {
    use TraceBindingError as B;
    if !result.compatible_topology {
        return Err(B::CompatibleTopologyFalse);
    }
    let nm = result.masters.len();
    if nm == 0 {
        return Err(B::EmptyMasters);
    }
    // glyph ids: result, trace and every outline agree
    if trace.glyph_id != result.glyph_id {
        return Err(B::GlyphIdMismatch {
            location: GlyphIdLocation::Trace,
            expected: result.glyph_id.clone(),
            found: trace.glyph_id.clone(),
        });
    }
    for (mi, m) in result.masters.iter().enumerate() {
        if m.outline.glyph_id != result.glyph_id {
            return Err(B::GlyphIdMismatch {
                location: GlyphIdLocation::Outline { master_index: mi },
                expected: result.glyph_id.clone(),
                found: m.outline.glyph_id.clone(),
            });
        }
    }
    // ordered unique master ids and counts
    if trace.master_ids.len() != nm {
        return Err(B::MasterCountMismatch { result: nm, trace: trace.master_ids.len() });
    }
    for (mi, m) in result.masters.iter().enumerate() {
        let tid = &trace.master_ids[mi];
        if *tid != m.master_id {
            return Err(B::MasterIdMismatch { index: mi, result_id: m.master_id.clone(), trace_id: tid.clone() });
        }
        if result.masters[..mi].iter().any(|p| p.master_id == m.master_id) {
            return Err(B::DuplicateMasterId { master_id: m.master_id.clone() });
        }
    }
    // ring counts and degenerate empty result rings
    let nrings = trace.rings.len();
    if nrings == 0 {
        return Err(B::EmptyRings);
    }
    for (mi, m) in result.masters.iter().enumerate() {
        if m.outline.rings.len() != nrings {
            return Err(B::RingCountMismatch { master_index: mi, result: m.outline.rings.len(), trace: nrings });
        }
        for (ri, r) in m.outline.rings.iter().enumerate() {
            if r.spans.is_empty() {
                return Err(B::EmptyResultRing { ring: ri, master_index: mi });
            }
        }
    }
    // unique nonempty correspondence ids (the result carries none to compare)
    for (ri, ring) in trace.rings.iter().enumerate() {
        if ring.correspondence_id.is_empty() {
            return Err(B::EmptyCorrespondenceId { ring: ri });
        }
        if trace.rings[..ri].iter().any(|p| p.correspondence_id == ring.correspondence_id) {
            return Err(B::DuplicateCorrespondenceId { correspondence_id: ring.correspondence_id.clone() });
        }
    }

    let mut ring_bindings: Vec<Vec<RingBinding>> = (0..nm).map(|_| Vec::with_capacity(nrings)).collect();
    let mut leaf_seq: Vec<Vec<(usize, String, SpanKind)>> = (0..nm).map(|_| Vec::new()).collect();
    let mut reused: Vec<BTreeMap<usize, usize>> = (0..nm).map(|_| BTreeMap::new()).collect();

    for (ri, ring) in trace.rings.iter().enumerate() {
        let ring_captured = map_pairs(&ring.ring_map, nm, ri, None, MapKind::RingMap)?;
        let ring_start = map_pairs(&ring.start_map, nm, ri, None, MapKind::StartMap)?;
        // ring_map cannot reuse a captured ring within a master
        for (mi, &c) in ring_captured.iter().enumerate() {
            if let Some(&first) = reused[mi].get(&c) {
                return Err(B::CapturedRingReused {
                    master_index: mi, captured_ring_index: c, first_ring: first, second_ring: ri,
                });
            }
            reused[mi].insert(c, ri);
        }
        // contiguous unique column ids 0..ncols, with per-column raw intervals
        let ncols = ring.columns.len();
        if ncols == 0 {
            return Err(B::EmptyColumnSet { ring: ri });
        }
        let mut col_seen: Vec<bool> = vec![false; ncols];
        let mut col_raw: Vec<Option<Vec<(usize, usize)>>> = vec![None; ncols];
        for c in &ring.columns {
            if c.column >= ncols {
                return Err(B::ColumnIdOutOfRange { ring: ri, column: c.column });
            }
            if col_seen[c.column] {
                return Err(B::ColumnIdDuplicate { ring: ri, column: c.column });
            }
            col_seen[c.column] = true;
            col_raw[c.column] = Some(map_triples(&c.raw_interval, nm, ri, c.column)?);
        }
        // producer contract: column POSITION == column ID; a shuffle that
        // keeps the same id set is rejected, never reindexed
        for (position, c) in ring.columns.iter().enumerate() {
            if c.column != position {
                return Err(B::ColumnIdOutOfOrder { ring: ri, position, column: c.column });
            }
        }
        let mut col_raw_checked: Vec<Vec<(usize, usize)>> = Vec::with_capacity(ncols);
        for (v, seen) in col_seen.iter().enumerate() {
            if !seen {
                return Err(B::ColumnIdMissing { ring: ri, column: v });
            }
            let Some(raw) = col_raw[v].take() else {
                return Err(B::ColumnIdMissing { ring: ri, column: v });
            };
            col_raw_checked.push(raw);
        }
        let col_raw = col_raw_checked;
        // start_map equals the first column raw start; adjacent columns join;
        // the final column wraps to the first (per master)
        for mi in 0..nm {
            let first_start = col_raw[0][mi].0;
            if ring_start[mi] != first_start {
                return Err(B::StartMapMismatch {
                    ring: ri, master_index: mi, start_map: ring_start[mi], first_column_start: first_start,
                });
            }
            for j in 0..ncols.saturating_sub(1) {
                let end = col_raw[j][mi].1;
                let next_start = col_raw[j + 1][mi].0;
                if end != next_start {
                    return Err(B::ColumnJoinMismatch { ring: ri, master_index: mi, column: j, end, next_start });
                }
            }
            let last_end = col_raw[ncols - 1][mi].1;
            if last_end != first_start {
                return Err(B::ColumnWrapMismatch { ring: ri, master_index: mi, last_end, first_start });
            }
        }
        // canonical DFS terminal list per column (validates Split path/depth)
        let mut col_leaves: Vec<Vec<(String, SpanKind)>> = vec![Vec::new(); ncols];
        for c in &ring.columns {
            let mut leaves = Vec::new();
            dfs_terminals(&c.decision, String::new(), 0, ri, c.column, &mut leaves)?;
            col_leaves[c.column] = leaves;
        }

        // emission-level structural checks, once per ring
        for c in &ring.columns {
            for e in &c.emitted {
                if e.master_index >= nm {
                    return Err(B::EmissionMasterIndexOutOfRange {
                        ring: ri, column: c.column, master_index: e.master_index,
                    });
                }
                if e.source_column != c.column {
                    return Err(B::SourceColumnMismatch {
                        ring: ri, containing_column: c.column, named_column: e.source_column,
                    });
                }
            }
        }

        for mi in 0..nm {
            let result_ring = &result.masters[mi].outline.rings[ri];
            let rlen = result_ring.spans.len();
            let mut bound: Vec<Option<SpanBinding>> = vec![None; rlen];
            // canonical span-index order: across columns 0..ncols in
            // column-ID order, this master's emissions (in canonical DFS
            // leaf order, already enforced above) must index the result
            // ring exactly 0,1,2,... in that order
            let mut expected_span_index: usize = 0;
            for c in &ring.columns {
                // this master's emission list must equal the canonical DFS
                // terminal list exactly once, in order
                let mine: Vec<&SpanEmission> =
                    c.emitted.iter().filter(|e| e.master_index == mi).collect();
                let leaves = &col_leaves[c.column];
                if mine.len() != leaves.len() {
                    return Err(B::ColumnLeafCountMismatch {
                        ring: ri, column: c.column, master_index: mi,
                        emissions: mine.len(), terminals: leaves.len(),
                    });
                }
                for (pos, (e, (lpath, lkind))) in mine.iter().zip(leaves.iter()).enumerate() {
                    if e.source_path != *lpath || e.kind != *lkind {
                        return Err(B::ColumnLeafSequenceMismatch { ring: ri, column: c.column, master_index: mi, position: pos });
                    }
                }
                for e in mine {
                    let idx = e.span_index_in_ring;
                    if idx >= rlen {
                        return Err(B::SpanIndexOutOfRange { ring: ri, master_index: mi, span_index: idx, ring_len: rlen });
                    }
                    if bound[idx].is_some() {
                        return Err(B::SpanIndexDuplicate { ring: ri, master_index: mi, span_index: idx });
                    }
                    if idx != expected_span_index {
                        return Err(B::SpanIndexOutOfOrder {
                            ring: ri, master_index: mi, column: c.column,
                            expected: expected_span_index, found: idx,
                        });
                    }
                    expected_span_index += 1;
                    let (leaf_kind, chain) = walk_split_chain(&c.decision, &e.source_path, mi, nm, ri, c.column)?;
                    if leaf_kind != e.kind {
                        return Err(B::LeafKindMismatch { ring: ri, master_index: mi, span_index: idx, leaf: leaf_kind, emitted: e.kind });
                    }
                    let rkind = span_kind(&result_ring.spans[idx]);
                    if rkind != e.kind {
                        return Err(B::ResultKindMismatch { ring: ri, master_index: mi, span_index: idx, emitted: e.kind, result: rkind });
                    }
                    bound[idx] = Some(SpanBinding {
                        span_index_in_ring: idx,
                        kind: e.kind,
                        source_column: e.source_column,
                        source_path: e.source_path.clone(),
                        column_raw_interval: col_raw[c.column][mi],
                        split_chain: chain,
                    });
                }
            }
            let mut spans = Vec::with_capacity(rlen);
            for (i, b) in bound.into_iter().enumerate() {
                let Some(b) = b else {
                    return Err(B::SpanIndexHole { ring: ri, master_index: mi, span_index: i });
                };
                spans.push(b);
            }
            for b in &spans {
                leaf_seq[mi].push((b.source_column, b.source_path.clone(), b.kind));
            }
            ring_bindings[mi].push(RingBinding {
                correspondence_id: ring.correspondence_id.clone(),
                captured_ring_index: ring_captured[mi],
                start_raw_index: ring_start[mi],
                spans,
            });
        }
    }

    // every master has one identical ordered (column, path, kind) leaf list
    for mi in 1..nm {
        if leaf_seq[mi].len() != leaf_seq[0].len() {
            return Err(B::OrderedLeafCountMismatch {
                master_index: mi, expected: leaf_seq[0].len(), found: leaf_seq[mi].len(),
            });
        }
        for (pos, (a, b)) in leaf_seq[0].iter().zip(leaf_seq[mi].iter()).enumerate() {
            if a != b {
                return Err(B::OrderedLeafMismatch { master_index: mi, position: pos });
            }
        }
    }

    let masters = result
        .masters
        .iter()
        .enumerate()
        .map(|(mi, m)| MasterBinding {
            master_index: mi,
            master_id: m.master_id.clone(),
            axes: m.axes.clone(),
            source_pin: m.source_pin.clone(),
            rings: std::mem::take(&mut ring_bindings[mi]),
        })
        .collect();
    Ok(MasterFitTraceBinding {
        scope: BINDING_SCOPE,
        glyph_id: result.glyph_id.clone(),
        receipt: result.receipt.clone(),
        squared_error: trace.squared_error,
        max_refits: trace.max_refits,
        tangent_lookahead_fraction: trace.tangent_lookahead_fraction,
        max_split_depth: trace.max_split_depth,
        split_fraction: trace.split_fraction,
        masters,
    })
}

// ----- producer composition: atomic fit+bind triple -----

/// Error of the composed producer: the fit itself failed, or the fresh
/// trace failed structural binding. The `Bind` arm is a producer
/// self-check failure path: a freshly produced pair is expected to bind,
/// but the binder is typed-fallible and no panic path is used.
#[derive(Clone, Debug, PartialEq)]
pub enum FitBindError {
    Fit(MasterFitError),
    Bind(TraceBindingError),
}

/// Atomic product of one traced fit run: the result, its trace, and the
/// structural binding between them, constructed together. Fields are
/// private and the ONLY constructor is `fit_master_set_bound`, so a
/// consumer of this type cannot pair a result from one fit with the trace
/// of another. This is an OWNERSHIP/atomicity guarantee, not authenticated
/// provenance: STRUCTURAL_BINDING_ONLY still applies to every part.
#[derive(Clone, Debug)]
pub struct BoundMasterFit {
    result: MasterFitResult,
    trace: MasterFitTrace,
    binding: MasterFitTraceBinding,
}

impl BoundMasterFit {
    pub fn result(&self) -> &MasterFitResult { &self.result }
    pub fn trace(&self) -> &MasterFitTrace { &self.trace }
    pub fn binding(&self) -> &MasterFitTraceBinding { &self.binding }
}

/// Fit a master set with tracing and bind the fresh pair atomically.
/// Composes the existing `fit_master_set_traced` producer with
/// `bind_master_fit_trace`; the existing traced/binder APIs remain
/// available.
pub fn fit_master_set_bound(
    set: &MasterSet,
    policy: &FitPolicy,
) -> Result<BoundMasterFit, FitBindError> {
    let (result, trace) = fit_master_set_traced(set, policy).map_err(FitBindError::Fit)?;
    let binding = bind_master_fit_trace(&result, &trace).map_err(FitBindError::Bind)?;
    Ok(BoundMasterFit { result, trace, binding })
}
