//! K1: outline_spacing - scanline profiles from KNI-generated outlines.
//!
//! Shared K1/K2/K3 code contract (chief architect, 2026-10-14): this module
//! owns the geometric minimum every downstream spacing/kern worker consumes
//! for one glyph: per-row NONZERO ink intervals, enclosed counter area,
//! side-aperture areas and whole-form side profiles.
//!
//! Input is a KNI-GENERATED outline only, flattened to closed polylines in
//! font units at a shared UPM. Ready-made fonts are NOT an input plane:
//! nothing here reads a kerned font, a GPOS table, or any pre-existing
//! kern/spacing data. The DrawnGlyph adapter lives OUTSIDE this crate
//! (metrics must not depend on core; the chief architect owns the
//! core/examples integration driver and the lib.rs/Cargo registration).

/// Explicit numeric policy source: the merge/zero-width guard in font
/// units (chief-architect fix, 2026-10-14: the guard is a named, documented
/// policy, never a buried constant, so it cannot merge away and lose
/// events). 1-unit stair structures are far above it.
pub const MERGE_GUARD_UNITS: f64 = 1e-9;

/// One ink run on a scan row: [left, right) with right > left.
#[derive(Debug, Clone, Copy, PartialEq)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct InkInterval {
    pub left: f64,
    pub right: f64,
}

/// One horizontal scan of the outline.
#[derive(Debug, Clone, PartialEq)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct ScanRow {
    /// Scanline y in the outline's own font-units frame.
    pub y: f64,
    /// Quadrature weight: the vertical span this row stands for, clipped
    /// to the ink bounds. CONTRACT (2026-10-14): interior rows are uniform
    /// (weight == ScanPolicy::row_step); only boundary rows may clip. Sum
    /// of weights over rows == exact ink bounds height. Area integrals
    /// MUST be weight-multiplied.
    pub weight: f64,
    /// Sorted, disjoint, nonzero-width ink intervals (NONZERO fill rule).
    /// Empty on rows with no ink; such rows are never skipped, so gap rows
    /// (i-dot gaps, apertures) stay represented across the whole form.
    pub ink: Vec<InkInterval>,
    /// True covered span [span_lo, span_hi) this row stands for (additive,
    /// 2026-10-15 P2-seam fix). Always satisfies span_hi - span_lo ==
    /// weight. For full grid cells span == y +- weight/2; for anchored
    /// boundary rows clipped to the ink bounds the grid midpoint y may sit
    /// OUTSIDE the bounds, and then y +- weight/2 is NOT the covered span —
    /// consumers must use these fields, never the midpoint arithmetic.
    pub span_lo: f64,
    pub span_hi: f64,
}

impl ScanRow {
    /// Raw per-row gaps strictly between ink intervals (ink on both sides
    /// on this row). No enclosed-vs-aperture classification; the
    /// enclosed-only aggregate is OutlineProfile::counter_area.
    pub fn inner_gaps(&self) -> Vec<InkInterval> {
        let mut out = Vec::new();
        for w in self.ink.windows(2) {
            if w[1].left - w[0].right > MERGE_GUARD_UNITS {
                out.push(InkInterval { left: w[0].right, right: w[1].left });
            }
        }
        out
    }
}

/// Whole-form scanline profile of one KNI-generated glyph outline.
#[derive(Debug, Clone, PartialEq)]
#[derive(serde::Serialize, serde::Deserialize)]
pub struct OutlineProfile {
    pub glyph_id: String,
    pub source_pin: String,
    pub upm: u16,
    /// Raw glyph-origin reference in the same frame as the coordinates.
    /// Downstream origin_distance is glyph-origin to glyph-origin, never
    /// ink-to-ink (chief architect frame rule, 2026-10-14).
    pub origin: [f64; 2],
    /// Rows sorted ascending by y; every sampled row of [min_y, max_y) is
    /// present (empty-ink rows included, never skipped).
    pub rows: Vec<ScanRow>,
    /// [min_x, min_y, max_x, max_y] of the flattened outline.
    pub bounds: [f64; 4],
    /// Row-weighted total ink area.
    pub ink_area: f64,
    /// Enclosed white area: white components touching no bounds edge.
    pub counter_area: f64,
    /// Side aperture: white components open ONLY to the left bounds edge
    /// (not to top/bottom/right). Zero for closed forms ('o', 'H').
    pub open_left: f64,
    /// Side aperture: white components open ONLY to the right bounds edge
    /// ('c', 'e'). Zero for closed forms.
    pub open_right: f64,
    /// Production receipt (chief-architect fix, 2026-10-14): ring transfer
    /// is flattened polylines, CFF cubics are NOT analyzed analytically;
    /// the method is always "bounded_curve_flatten+scanline" and this
    /// output is never auto-labeled "exact full outline".
    pub profile_method: String,
    /// Receipt: scan row pitch actually used (ScanPolicy::row_step).
    pub row_step: f64,
    /// Receipt: flatten tolerance reported by the transfer (verbatim).
    pub flatten_tolerance: f64,
}

impl OutlineProfile {
    /// Whole-form LEFT side profile: (y, leftmost ink x) for every inked
    /// row. Raw measured ink edge, no offset policy (the side_walls Wall
    /// offset surrogate is not applied at this layer).
    pub fn left_side_profile(&self) -> Vec<(f64, f64)> {
        self.rows.iter().filter_map(|r| r.ink.first().map(|iv| (r.y, iv.left))).collect()
    }
    /// Whole-form RIGHT side profile: (y, rightmost ink x), every inked row.
    pub fn right_side_profile(&self) -> Vec<(f64, f64)> {
        self.rows.iter().filter_map(|r| r.ink.last().map(|iv| (r.y, iv.right))).collect()
    }
}

/// Flattened outline input. Metrics-crate local: no core dependency. This
/// is the plain transfer type the core DrawnGlyph adapter (example driver)
/// fills: Span::Line ends directly, Span::Cubic flattened with the caller's
/// tolerance; ring closure is implicit (last point connects to first).
#[derive(Debug, Clone, PartialEq)]
pub struct OutlineInput {
    pub glyph_id: String,
    pub source_pin: String,
    pub upm: u16,
    /// Glyph origin in the same font-units frame as the ring coordinates.
    pub origin: [f64; 2],
    /// Transfer receipt: the bounded_curve_flatten tolerance the adapter
    /// used flattening cubics to these polylines (0.0 when the rings were
    /// already polylines). Carried into the profile receipt verbatim.
    pub flatten_tolerance: f64,
    /// Closed rings as flattened polylines in font units.
    pub rings: Vec<Vec<[f64; 2]>>,
}

/// Scan resolution and resource bound; explicit, never a hidden constant.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ScanPolicy {
    /// Scan row pitch in font units. Must be finite and > 0.
    pub row_step: f64,
    /// Hard resource bound: refuse when the form needs more rows.
    pub max_rows: usize,
    /// Merge/zero-width guard in font units; explicit numeric policy
    /// (see MERGE_GUARD_UNITS), must be finite and > 0.
    pub merge_guard: f64,
    /// Common y-grid anchor (contract, 2026-10-14): None = grid anchored
    /// at the glyph's own min_y (single-glyph default; phases differ per
    /// glyph, pair matching via align_pair_rows). Some(a) = shared grid:
    /// every row y is the exact grid midpoint a + (i + 0.5) * row_step,
    /// bit-identical across glyphs scanned with the same policy, so pair
    /// consumers exact-match on y. Boundary rows may sample up to one
    /// row_step outside the ink bounds; their weight covers only the
    /// in-bounds span.
    pub grid_anchor_y: Option<f64>,
}

impl Default for ScanPolicy {
    fn default() -> Self {
        Self { row_step: 4.0, max_rows: 4096, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }
    }
}

/// Typed refusals; no silent fallbacks.
#[derive(Debug, Clone, PartialEq)]
pub enum ProfileError {
    /// No rings, rings with no points, or no surviving ring after
    /// ring-level degenerate exclusions (typed whole-glyph drop).
    Empty,
    /// A non-finite coordinate.
    NonFinite,
    /// RETIRED (always-output contract): demoted to the ring-level typed
    /// exclusion `RingExclusion`; never returned any more, kept so the
    /// receipt vocabulary stays stable.
    DegenerateRing { ring: usize },
    /// Zero-width or zero-height form (nothing to scan).
    DegenerateBounds,
    /// policy.row_step was non-finite or <= 0.
    BadPolicy,
    /// policy.max_rows exceeded; the required row count is reported.
    ResourceBound { required_rows: usize },
}

/// Typed ring-level exclusion (stage Profile): a ring that cannot
/// participate leaves with a receipt entry; the glyph continues on its
/// surviving rings (always-output contract).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RingExclusion {
    /// Index of the ring in the input ring vector.
    pub ring: usize,
    /// Why the ring left the profile.
    pub reason: RingExclusionReason,
}

/// Ring-level exclusion reasons (typed, stable receipt vocabulary).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RingExclusionReason {
    /// Ring with fewer than 2 points (carries the actual point count).
    DegenerateRing { points: usize },
}

struct Dsu {
    parent: Vec<usize>,
}
impl Dsu {
    fn new(n: usize) -> Self {
        Self { parent: (0..n).collect() }
    }
    fn find(&mut self, mut a: usize) -> usize {
        while self.parent[a] != a {
            self.parent[a] = self.parent[self.parent[a]];
            a = self.parent[a];
        }
        a
    }
    fn union(&mut self, a: usize, b: usize) {
        let ra = self.find(a);
        let rb = self.find(b);
        if ra != rb {
            self.parent[rb] = ra;
        }
    }
}

/// Build the whole-form profile of one outline under an explicit policy.
/// The ring-level exclusion receipt is dropped; use
/// `profile_outline_with_exclusions` when the caller writes a ledger.
pub fn profile_outline(input: &OutlineInput, policy: ScanPolicy) -> Result<OutlineProfile, ProfileError> {
    profile_outline_with_exclusions(input, policy).0
}

/// `profile_outline` + the typed ring-level exclusion receipt (stage
/// Profile): every degenerate ring is skipped and receipted and the glyph
/// is built from its surviving rings; only when NO ring survives does the
/// glyph drop (typed `ProfileError::Empty`). An input with no degenerate
/// ring takes the identical accumulation path as before (bit-identical).
pub fn profile_outline_with_exclusions(input: &OutlineInput, policy: ScanPolicy) -> (Result<OutlineProfile, ProfileError>, Vec<RingExclusion>) {
    let mut exclusions = Vec::new();
    (profile_outline_inner(input, policy, &mut exclusions), exclusions)
}

fn profile_outline_inner(input: &OutlineInput, policy: ScanPolicy, exclusions: &mut Vec<RingExclusion>) -> Result<OutlineProfile, ProfileError> {
    if !policy.row_step.is_finite() || policy.row_step <= 0.0
        || !policy.merge_guard.is_finite() || policy.merge_guard <= 0.0
        || policy.grid_anchor_y.map(|a| !a.is_finite()).unwrap_or(false)
    {
        return Err(ProfileError::BadPolicy);
    }
    if !input.flatten_tolerance.is_finite() || input.flatten_tolerance < 0.0 {
        return Err(ProfileError::NonFinite);
    }
    let guard = policy.merge_guard;
    if input.rings.is_empty() {
        return Err(ProfileError::Empty);
    }
    let mut minx = f64::INFINITY;
    let mut miny = f64::INFINITY;
    let mut maxx = f64::NEG_INFINITY;
    let mut maxy = f64::NEG_INFINITY;
    let mut any = false;
    // Ring-level typed exclusion (always-output contract): a degenerate
    // ring is skipped and receipted; bounds accumulate over survivors only.
    let mut rings: Vec<&Vec<[f64; 2]>> = Vec::with_capacity(input.rings.len());
    let mut ring_y_extent: Vec<(f64, f64)> = Vec::with_capacity(input.rings.len());
    for (ri, ring) in input.rings.iter().enumerate() {
        if ring.len() < 2 {
            exclusions.push(RingExclusion { ring: ri, reason: RingExclusionReason::DegenerateRing { points: ring.len() } });
            continue;
        }
        let (mut rminy, mut rmaxy) = (f64::INFINITY, f64::NEG_INFINITY);
        for p in ring {
            if !p[0].is_finite() || !p[1].is_finite() {
                return Err(ProfileError::NonFinite);
            }
            any = true;
            minx = minx.min(p[0]);
            miny = miny.min(p[1]);
            maxx = maxx.max(p[0]);
            maxy = maxy.max(p[1]);
            rminy = rminy.min(p[1]);
            rmaxy = rmaxy.max(p[1]);
        }
        rings.push(ring);
        ring_y_extent.push((rminy, rmaxy));
    }
    if !any {
        return Err(ProfileError::Empty);
    }
    let height = maxy - miny;
    let width = maxx - minx;
    if !(height > 0.0) || !(width > 0.0) {
        return Err(ProfileError::DegenerateBounds);
    }
    let step = policy.row_step;
    // Grid cell index range covering [miny, maxy).
    let (i0, i1) = match policy.grid_anchor_y {
        None => (0i64, (height / step).ceil() as i64 - 1),
        Some(anchor) => (
            ((miny - anchor) / step).floor() as i64,
            ((maxy - anchor) / step).ceil() as i64 - 1,
        ),
    };
    let n_rows = (i1 - i0 + 1) as usize;
    if n_rows > policy.max_rows {
        return Err(ProfileError::ResourceBound { required_rows: n_rows });
    }
    if !input.origin[0].is_finite() || !input.origin[1].is_finite() {
        return Err(ProfileError::NonFinite);
    }

    // Pre-collect non-horizontal edges; ring closure is implicit.
    let mut edges: Vec<(f64, f64, f64, f64)> = Vec::new();
    for ring in &rings {
        let n = ring.len();
        for k in 0..n {
            let a = ring[k];
            let b = ring[(k + 1) % n];
            if a[1] != b[1] {
                edges.push((a[0], a[1], b[0], b[1]));
            }
        }
    }

    // One row scan, shared by the grid rows and the derived thin-ring rows.
    let scan = |y: f64, covered: f64, span_lo: f64, span_hi: f64,
                edges: &Vec<(f64, f64, f64, f64)>| -> (ScanRow, Vec<(f64, f64)>, f64) {
        let mut xs: Vec<(f64, i32)> = Vec::new();
        for &(x0, y0, x1, y1) in edges {
            let (ya, yb) = if y0 < y1 { (y0, y1) } else { (y1, y0) };
            // Half-open scanline rule: consistent vertex handling.
            if y >= ya && y < yb {
                let t = (y - y0) / (y1 - y0);
                xs.push((x0 + t * (x1 - x0), if y1 > y0 { 1 } else { -1 }));
            }
        }
        xs.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap());
        let mut ink: Vec<InkInterval> = Vec::new();
        let mut winding = 0i32;
        let mut prev: Option<f64> = None;
        for &(x, d) in &xs {
            if winding != 0 {
                if let Some(px) = prev {
                    if x - px > guard {
                        ink.push(InkInterval { left: px, right: x });
                    }
                }
            }
            winding += d;
            prev = Some(x);
        }
        let row_ink: f64 = ink.iter().map(|iv| iv.right - iv.left).sum();
        let mut white: Vec<(f64, f64)> = Vec::new();
        let mut cursor = minx;
        for iv in &ink {
            if iv.left - cursor > guard {
                white.push((cursor, iv.left));
            }
            cursor = cursor.max(iv.right);
        }
        if maxx - cursor > guard {
            white.push((cursor, maxx));
        }
        (ScanRow { y, weight: covered, ink, span_lo, span_hi }, white, covered * row_ink)
    };

    let mut rows: Vec<ScanRow> = Vec::with_capacity(n_rows);
    let mut white_rows: Vec<Vec<(f64, f64)>> = Vec::with_capacity(n_rows);
    let mut ink_area = 0.0;
    for i in i0..=i1 {
        let (y, covered, span_lo, span_hi) = match policy.grid_anchor_y {
            Some(anchor) => {
                let cell_start = anchor + i as f64 * step;
                let y = anchor + (i as f64 + 0.5) * step;
                let lo = cell_start.max(miny);
                let hi = (cell_start + step).min(maxy);
                (y, hi - lo, lo, hi)
            }
            None => {
                let row_y0 = miny + i as f64 * step;
                let covered = step.min(maxy - row_y0);
                (row_y0 + covered * 0.5, covered, row_y0, row_y0 + covered)
            }
        };
        let (row, white, contrib) = scan(y, covered, span_lo, span_hi, &edges);
        ink_area += contrib;
        white_rows.push(white);
        rows.push(row);
    }

    // Thin-ring coverage (OUR CANDIDATE derivation, always-output): the
    // uniform grid can step OVER a ring thinner than row_step whose extent
    // falls between two row midpoints; that ring's ink then vanishes from
    // the profile (Marq dash class: ~3-unit slivers on a 10-unit pitch).
    // Any ring with height >= step necessarily contains a grid midpoint,
    // so only sub-step rings can be missed. For each missed ring add ONE
    // derived row: y at the ring's own mid-height, weight = the ring's own
    // height, span = the ring's own y-extent. No constants: every parameter
    // is the ring's own measure. Glyphs whose rings are all grid-covered
    // get an empty supplement and a bit-identical row set.
    let mut supplementary: Vec<(ScanRow, Vec<(f64, f64)>, f64)> = Vec::new();
    for &(rminy, rmaxy) in &ring_y_extent {
        let rheight = rmaxy - rminy;
        if !(rheight > 0.0) {
            continue; // zero-height ring: no scannable band (degenerate class)
        }
        let covered = rows.iter().any(|r| r.y >= rminy && r.y < rmaxy);
        if !covered {
            supplementary.push(scan((rminy + rmaxy) / 2.0, rheight, rminy, rmaxy, &edges));
        }
    }
    if !supplementary.is_empty() {
        // Bound accounting in two derived parts: policy.max_rows bounds the
        // GRID rows (the manifest scan_max_rows derivation, checked above).
        // Supplementary rows are bounded by the input's own ring count -
        // one row per grid-missed ring, and the ring count is an input
        // property, not a loop - so total rows <= max_rows + ring count
        // with no runaway path. Refusing on the sum would reject profiles
        // the manifest bound provably cannot anticipate: the generator
        // sees inventory heights only, never ring counts.
        for (row, white, contrib) in supplementary {
            ink_area += contrib;
            let pos = rows.partition_point(|r| r.y < row.y);
            rows.insert(pos, row);
            white_rows.insert(pos, white);
        }
    }
    let n_rows = rows.len();

    // White-component flood fill across adjacent rows (x-overlap links).
    let total_white: usize = white_rows.iter().map(|r| r.len()).sum();
    let mut dsu = Dsu::new(total_white);
    let mut offsets = Vec::with_capacity(n_rows + 1);
    offsets.push(0usize);
    for r in &white_rows {
        offsets.push(offsets.last().unwrap() + r.len());
    }
    for i in 0..n_rows.saturating_sub(1) {
        for (ai, &(al, ar)) in white_rows[i].iter().enumerate() {
            for (bi, &(bl, br)) in white_rows[i + 1].iter().enumerate() {
                if al < br + guard && bl < ar + guard {
                    dsu.union(offsets[i] + ai, offsets[i + 1] + bi);
                }
            }
        }
    }
    // Component classification: which bounds edges it touches.
    #[derive(Default, Clone, Copy)]
    struct Touch {
        left: bool,
        right: bool,
        vertical: bool, // top or bottom edge
        area: f64,
    }
    // BTreeMap, not HashMap: the component areas are f64 ACCUMULATED in
    // iteration order below (counter_area / open_left / open_right), and
    // HashMap iteration order is randomized per instance - the same glyph
    // then summed to different ULPs on different runs/builds (measured:
    // counter_area drifting by 2 ULP across in-process repetitions on a
    // 24-counter synthetic). Root indices are deterministic (DSU unions run
    // in scan order), so key-ordered iteration makes the sums bit-stable.
    let mut comps: std::collections::BTreeMap<usize, Touch> = std::collections::BTreeMap::new();
    for (i, wr) in white_rows.iter().enumerate() {
        for (j, &(wl, wrx)) in wr.iter().enumerate() {
            let root = dsu.find(offsets[i] + j);
            let e = comps.entry(root).or_default();
            if wl <= minx + guard {
                e.left = true;
            }
            if wrx >= maxx - guard {
                e.right = true;
            }
            if i == 0 || i == n_rows - 1 {
                e.vertical = true;
            }
            e.area += rows[i].weight * (wrx - wl);
        }
    }
    let mut counter_area = 0.0;
    let mut open_left = 0.0;
    let mut open_right = 0.0;
    for t in comps.values() {
        match (t.left, t.right, t.vertical) {
            (false, false, false) => counter_area += t.area,
            (true, false, false) => open_left += t.area,
            (false, true, false) => open_right += t.area,
            _ => {} // exterior background or through-channel: outside the form
        }
    }

    Ok(OutlineProfile {
        glyph_id: input.glyph_id.clone(),
        source_pin: input.source_pin.clone(),
        upm: input.upm,
        origin: input.origin,
        rows,
        bounds: [minx, miny, maxx, maxy],
        ink_area,
        counter_area,
        open_left,
        open_right,
        profile_method: "bounded_curve_flatten+scanline".to_string(),
        row_step: policy.row_step,
        flatten_tolerance: input.flatten_tolerance,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
        vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
    }
    fn input(rings: Vec<Vec<[f64; 2]>>) -> OutlineInput {
        OutlineInput {
            glyph_id: "g".to_string(),
            source_pin: "sha256:test:g".to_string(),
            upm: 1000,
            origin: [0.0, 0.0],
            flatten_tolerance: 0.5,
            rings,
        }
    }

    #[test]
    fn rectangle_exact_area_and_profiles() {
        let p = profile_outline(&input(vec![rect(0.0, 0.0, 100.0, 200.0)]),
                                ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }).unwrap();
        assert_eq!(p.bounds, [0.0, 0.0, 100.0, 200.0]);
        assert_eq!(p.rows.len(), 50);
        assert!(p.rows.iter().all(|r| r.ink.len() == 1));
        assert!((p.ink_area - 20_000.0).abs() < 1e-9);
        assert_eq!(p.counter_area, 0.0);
        assert_eq!(p.open_left, 0.0);
        assert_eq!(p.open_right, 0.0);
        let l = p.left_side_profile();
        let r = p.right_side_profile();
        assert_eq!(l.len(), 50);
        assert!(l.iter().all(|&(_, x)| x == 0.0));
        assert!(r.iter().all(|&(_, x)| x == 100.0));
    }

    #[test]
    fn counter_enclosed_when_ring_opposite_orientation() {
        // 'o': outer ring + opposite-wound inner ring.
        let outer = rect(0.0, 0.0, 100.0, 100.0);
        let inner: Vec<[f64; 2]> = rect(30.0, 30.0, 70.0, 70.0).into_iter().rev().collect();
        let p = profile_outline(&input(vec![outer, inner]),
                                ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }).unwrap();
        assert!((p.counter_area - 1_600.0).abs() < 1e-9, "counter {}", p.counter_area);
        assert!((p.ink_area - 8_400.0).abs() < 1e-9);
        assert_eq!(p.open_left, 0.0);
        assert_eq!(p.open_right, 0.0);
    }

    #[test]
    fn nonzero_fill_rule_same_orientation_fills() {
        // Same winding inside: nonzero fill keeps the inner region inked.
        let outer = rect(0.0, 0.0, 100.0, 100.0);
        let inner = rect(30.0, 30.0, 70.0, 70.0);
        let p = profile_outline(&input(vec![outer, inner]),
                                ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }).unwrap();
        assert!((p.ink_area - 10_000.0).abs() < 1e-9);
        assert_eq!(p.counter_area, 0.0);
    }

    #[test]
    fn right_side_aperture_detected() {
        // 'c'-like form: opening to the right, y in 20..80, x in 40..100.
        let c = vec![
            [0.0, 0.0], [100.0, 0.0], [100.0, 20.0], [40.0, 20.0],
            [40.0, 80.0], [100.0, 80.0], [100.0, 100.0], [0.0, 100.0],
        ];
        let p = profile_outline(&input(vec![c]),
                                ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }).unwrap();
        assert!((p.open_right - 3_600.0).abs() < 1e-9, "open_right {}", p.open_right);
        assert_eq!(p.open_left, 0.0);
        assert_eq!(p.counter_area, 0.0);
        assert!((p.ink_area - 6_400.0).abs() < 1e-9);
    }

    #[test]
    fn h_channels_are_exterior_not_counter() {
        // 'H': side channels open to top/bottom; none count as counter or
        // side aperture, but per-row gaps stay visible via inner_gaps.
        let stems = vec![
            rect(0.0, 0.0, 30.0, 100.0),
            rect(70.0, 0.0, 100.0, 100.0),
            rect(0.0, 40.0, 100.0, 60.0),
        ];
        let p = profile_outline(&input(stems),
                                ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }).unwrap();
        assert_eq!(p.counter_area, 0.0);
        assert_eq!(p.open_left, 0.0);
        assert_eq!(p.open_right, 0.0);
        let row70 = p.rows.iter().find(|r| (r.y - 70.0).abs() < 1e-9).unwrap();
        assert_eq!(row70.inner_gaps(), vec![InkInterval { left: 30.0, right: 70.0 }]);
    }

    #[test]
    fn gap_rows_kept_not_skipped() {
        // 'i'-like: dot and stem separated by a white band.
        let p = profile_outline(
            &input(vec![rect(0.0, 0.0, 50.0, 32.0), rect(0.0, 52.0, 50.0, 100.0)]),
            ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }).unwrap();
        assert_eq!(p.rows.len(), 25);
        assert!(!p.rows[7].ink.is_empty());
        for r in &p.rows[8..13] {
            assert!(r.ink.is_empty(), "gap row at y={} must stay present", r.y);
        }
        assert!(!p.rows[13].ink.is_empty());
        assert!((p.ink_area - 4_000.0).abs() < 1e-9);
    }

    #[test]
    fn origin_reference_preserved() {
        let mut i = input(vec![rect(10.0, 0.0, 60.0, 100.0)]);
        i.origin = [12.5, -3.0];
        let p = profile_outline(&i, ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }).unwrap();
        assert_eq!(p.origin, [12.5, -3.0]);
        assert_eq!(p.upm, 1000);
        assert_eq!(p.source_pin, "sha256:test:g");
        assert_eq!(p.profile_method, "bounded_curve_flatten+scanline");
        assert_eq!(p.row_step, 4.0);
        assert_eq!(p.flatten_tolerance, 0.5);
    }

    #[test]
    fn typed_refusals() {
        let pol = ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None };
        assert_eq!(profile_outline(&input(vec![]), pol), Err(ProfileError::Empty));
        // MARQ-DEGEN: a degenerate ring no longer refuses the glyph; with no
        // surviving ring the whole glyph is a typed drop (Empty), receipted
        // per ring in the exclusion ledger.
        assert_eq!(profile_outline(&input(vec![vec![[0.0, 0.0]]]), pol),
                   Err(ProfileError::Empty));
        let (_, excl) = profile_outline_with_exclusions(&input(vec![vec![[0.0, 0.0]]]), pol);
        assert_eq!(excl, vec![RingExclusion { ring: 0, reason: RingExclusionReason::DegenerateRing { points: 1 } }]);
        let mut bad = input(vec![rect(0.0, 0.0, 10.0, 10.0)]);
        bad.rings[0][1][0] = f64::NAN;
        assert_eq!(profile_outline(&bad, pol), Err(ProfileError::NonFinite));
        // Zero-height form.
        assert_eq!(profile_outline(&input(vec![vec![[0.0, 5.0], [100.0, 5.0]]]), pol),
                   Err(ProfileError::DegenerateBounds));
        assert_eq!(profile_outline(&input(vec![rect(0.0, 0.0, 10.0, 10.0)]),
                                   ScanPolicy { row_step: 0.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }),
                   Err(ProfileError::BadPolicy));
        assert_eq!(profile_outline(&input(vec![rect(0.0, 0.0, 100.0, 10_000.0)]),
                                   ScanPolicy { row_step: 4.0, max_rows: 10, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }),
                   Err(ProfileError::ResourceBound { required_rows: 2500 }));
    }
}

/// One shared-y segment of a pair alignment: exact union-boundary
/// segmentation, piecewise-constant in the scan model. `left`/`right` are
/// the covering row's ink intervals from each profile (empty when that
/// profile has a gap row there). Segments are ascending, non-overlapping,
/// and at least one side always carries a covering row.
#[derive(Debug, Clone, PartialEq)]
pub struct AlignedRow {
    pub y: f64,
    pub weight: f64,
    pub left: Vec<InkInterval>,
    pub right: Vec<InkInterval>,
}

fn row_at<'a>(rows: &'a [ScanRow], y: f64) -> Option<&'a ScanRow> {
    // Rows are ascending and contiguous in their TRUE covered spans; find
    // the row whose [span_lo, span_hi) contains y.
    let i = rows.partition_point(|r| r.span_hi <= y);
    let r = rows.get(i)?;
    if y >= r.span_lo - MERGE_GUARD_UNITS {
        Some(r)
    } else {
        None
    }
}

/// Pair alignment for K2/K3 (contract answer 2026-10-14): cross-glyph
/// shared-row matching is SPAN OVERLAP, never exact f64 y equality — each
/// profile's grid is anchored at its own min_y. This is the exact
/// piecewise-constant segmentation over the union of both row grids: no
/// resampling, no new approximation, no grid negotiation.
pub fn align_pair_rows(a: &OutlineProfile, b: &OutlineProfile) -> Vec<AlignedRow> {
    let mut cuts: Vec<f64> = Vec::with_capacity((a.rows.len() + b.rows.len()) * 2);
    for r in a.rows.iter().chain(b.rows.iter()) {
        cuts.push(r.span_lo);
        cuts.push(r.span_hi);
    }
    cuts.sort_by(|x, y| x.partial_cmp(y).unwrap());
    let mut out = Vec::new();
    for w in cuts.windows(2) {
        let (y0, y1) = (w[0], w[1]);
        if y1 - y0 <= MERGE_GUARD_UNITS {
            continue;
        }
        let y = (y0 + y1) * 0.5;
        let ra = row_at(&a.rows, y);
        let rb = row_at(&b.rows, y);
        if ra.is_none() && rb.is_none() {
            continue; // outside both forms' y ranges
        }
        out.push(AlignedRow {
            y,
            weight: y1 - y0,
            left: ra.map(|r| r.ink.clone()).unwrap_or_default(),
            right: rb.map(|r| r.ink.clone()).unwrap_or_default(),
        });
    }
    out
}

#[cfg(test)]
mod pair_tests {
    use super::*;

    fn rect_input(x0: f64, y0: f64, x1: f64, y1: f64) -> OutlineInput {
        OutlineInput {
            glyph_id: "g".to_string(),
            source_pin: "sha256:test:g".to_string(),
            upm: 1000,
            origin: [0.0, 0.0],
            flatten_tolerance: 0.5,
            rings: vec![vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]],
        }
    }

    #[test]
    fn align_pair_rows_span_overlap_not_f64_equality() {
        let pol = ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None };
        let a = profile_outline(&rect_input(0.0, 0.0, 100.0, 100.0), pol).unwrap();
        let b = profile_outline(&rect_input(50.0, 30.0, 150.0, 130.0), pol).unwrap();
        // Grids anchored at own min_y: no shared f64 y values at all.
        assert!(a.rows.iter().all(|ra| b.rows.iter().all(|rb| ra.y != rb.y)));
        let aligned = align_pair_rows(&a, &b);
        assert!(!aligned.is_empty());
        // Full coverage of the union y range 0..130, no both-empty rows.
        let total: f64 = aligned.iter().map(|r| r.weight).sum();
        assert!((total - 130.0).abs() < 1e-9, "total {}", total);
        assert!(aligned.iter().all(|r| !r.left.is_empty() || !r.right.is_empty()));
        // Overlap region carries both inks.
        let mid = aligned.iter().find(|r| (r.y - 31.0).abs() < 1e-9).unwrap();
        assert_eq!(mid.left, vec![InkInterval { left: 0.0, right: 100.0 }]);
        assert_eq!(mid.right, vec![InkInterval { left: 50.0, right: 150.0 }]);
        // Below b's range: right side empty.
        let low = aligned.iter().find(|r| r.y > 1.0 && r.y < 3.0).unwrap();
        assert!(low.right.is_empty());
        assert!(!low.left.is_empty());
    }

    #[test]
    fn anchored_common_grid_exact_y_across_glyphs() {
        let pol = ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS,
                               grid_anchor_y: Some(0.0) };
        let a = profile_outline(&rect_input(0.0, 0.0, 100.0, 100.0), pol).unwrap();
        let b = profile_outline(&rect_input(50.0, 30.0, 150.0, 130.0), pol).unwrap();
        let ys: std::collections::HashSet<u64> = a.rows.iter().map(|r| r.y.to_bits()).collect();
        for r in &b.rows {
            if r.y <= 98.0 {
                assert!(ys.contains(&r.y.to_bits()), "y {} not on shared grid", r.y);
            }
        }
        assert_eq!(a.rows[0].y, 2.0);
        assert_eq!(b.rows[0].y, 30.0);
        // Weights still sum to each glyph's exact bounds height.
        let ha: f64 = a.rows.iter().map(|r| r.weight).sum();
        let hb: f64 = b.rows.iter().map(|r| r.weight).sum();
        assert!((ha - 100.0).abs() < 1e-9, "ha {}", ha);
        assert!((hb - 100.0).abs() < 1e-9, "hb {}", hb);
    }

    #[test]
    fn weights_sum_to_exact_bounds_height() {
        let pol = ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None };
        let p = profile_outline(&rect_input(0.0, 0.0, 100.0, 197.0), pol).unwrap();
        let h: f64 = p.rows.iter().map(|r| r.weight).sum();
        assert!((h - 197.0).abs() < 1e-9, "h_eff {}", h);
        assert!((p.rows.last().unwrap().weight - 1.0).abs() < 1e-9); // clipped tail row
    }
}

// ---------------------------------------------------------------------------
// P3: emitted-outline profile input adapter (chief architect assignment,
// 2026-10-14). Final EMITTED outline -> OutlineProfile, preserving every
// counter/scan interval, with explicit frame + UPM validation. No new
// sampling policy: ScanPolicy and the flatten tolerance are passed in
// explicitly by the caller and carried into the receipt verbatim.
// ---------------------------------------------------------------------------

/// One span of a final emitted contour (target frame, font units).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum EmittedSpan {
    Line { end: [f64; 2] },
    Cubic { control_one: [f64; 2], control_two: [f64; 2], end: [f64; 2] },
}

/// One contour of the final emitted outline. Closure is implicit (the
/// adapter closes each ring last->first in the OutlineInput transfer);
/// explicit repeated-start closure points are preserved harmlessly.
#[derive(Debug, Clone, PartialEq)]
pub struct EmittedContour {
    pub start: [f64; 2],
    pub spans: Vec<EmittedSpan>,
}

/// Final emitted outline for one glyph, in the DIRECT declared coordinate
/// frame (font units at `upm`, y direction as emitted). Frame transforms
/// are upstream (output_binding ExplicitTransformRequired lane); this
/// adapter validates, it never transforms or normalizes.
#[derive(Debug, Clone, PartialEq)]
pub struct EmittedGlyph {
    pub glyph_id: String,
    pub source_pin: String,
    /// Declared UPM of the emitted frame.
    pub upm: u16,
    /// Glyph origin in the same frame as the coordinates.
    pub origin: [f64; 2],
    pub contours: Vec<EmittedContour>,
}

/// Typed adapter refusals; no silent fallbacks.
#[derive(Debug, Clone, PartialEq)]
pub enum AdapterError {
    /// No contours at all.
    NoContours,
    /// Contour with no spans.
    EmptyContour { contour: usize },
    /// Non-finite coordinate or origin. Span index None = start/origin.
    NonFinite { contour: usize, span: Option<usize> },
    /// Declared UPM disagrees with the run's shared UPM (UPM ortak).
    UpmMismatch { declared: u16, expected: u16 },
    /// Flatten tolerance non-finite or <= 0.
    BadFlattenTolerance,
    /// Downstream profile build refused; passed through unchanged.
    Profile(ProfileError),
}

/// Bounded recursive cubic subdivision cap (transfer mechanics, named and
/// documented; not a sampling policy). At the cap the chord is emitted.
pub const MAX_FLATTEN_DEPTH: u32 = 24;

fn dist_to_chord(p: [f64; 2], a: [f64; 2], b: [f64; 2]) -> f64 {
    let dx = b[0] - a[0];
    let dy = b[1] - a[1];
    let len = (dx * dx + dy * dy).sqrt();
    if len <= MERGE_GUARD_UNITS {
        let d1 = ((p[0] - a[0]).powi(2) + (p[1] - a[1]).powi(2)).sqrt();
        return d1;
    }
    ((p[0] - a[0]) * dy - (p[1] - a[1]) * dx).abs() / len
}

fn flatten_cubic(
    p0: [f64; 2],
    p1: [f64; 2],
    p2: [f64; 2],
    p3: [f64; 2],
    tol: f64,
    depth: u32,
    out: &mut Vec<[f64; 2]>,
) {
    let flat = dist_to_chord(p1, p0, p3).max(dist_to_chord(p2, p0, p3));
    if flat <= tol || depth == 0 {
        out.push(p3);
        return;
    }
    let mid = |a: [f64; 2], b: [f64; 2]| [(a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5];
    let q0 = mid(p0, p1);
    let q1 = mid(p1, p2);
    let q2 = mid(p2, p3);
    let r0 = mid(q0, q1);
    let r1 = mid(q1, q2);
    let s = mid(r0, r1);
    flatten_cubic(p0, q0, r0, s, tol, depth - 1, out);
    flatten_cubic(s, r1, q2, p3, tol, depth - 1, out);
}

/// P3 adapter entry: final emitted outline -> whole-form profile.
///
/// Every contour is flattened (bounded_curve_flatten, explicit tolerance)
/// and passed through as one ring; no contour, counter or scan interval is
/// dropped or merged beyond the explicit MERGE_GUARD_UNITS policy. Frame
/// validation: UPM match against the run's shared UPM, finite origin and
/// coordinates, non-empty contours. Sampling policy is NOT chosen here:
/// `policy` is the caller's, explicit.
pub fn profile_from_emitted(
    glyph: &EmittedGlyph,
    expected_upm: u16,
    policy: ScanPolicy,
    flatten_tolerance: f64,
) -> Result<OutlineProfile, AdapterError> {
    if glyph.upm != expected_upm {
        return Err(AdapterError::UpmMismatch { declared: glyph.upm, expected: expected_upm });
    }
    if !flatten_tolerance.is_finite() || flatten_tolerance <= 0.0 {
        return Err(AdapterError::BadFlattenTolerance);
    }
    if glyph.contours.is_empty() {
        return Err(AdapterError::NoContours);
    }
    if !glyph.origin[0].is_finite() || !glyph.origin[1].is_finite() {
        return Err(AdapterError::NonFinite { contour: 0, span: None });
    }
    let mut rings: Vec<Vec<[f64; 2]>> = Vec::with_capacity(glyph.contours.len());
    for (ci, contour) in glyph.contours.iter().enumerate() {
        if contour.spans.is_empty() {
            return Err(AdapterError::EmptyContour { contour: ci });
        }
        if !contour.start[0].is_finite() || !contour.start[1].is_finite() {
            return Err(AdapterError::NonFinite { contour: ci, span: None });
        }
        let mut ring: Vec<[f64; 2]> = vec![contour.start];
        for (si, span) in contour.spans.iter().enumerate() {
            match *span {
                EmittedSpan::Line { end } => {
                    if !end[0].is_finite() || !end[1].is_finite() {
                        return Err(AdapterError::NonFinite { contour: ci, span: Some(si) });
                    }
                    ring.push(end);
                }
                EmittedSpan::Cubic { control_one, control_two, end } => {
                    let pts = [control_one, control_two, end];
                    if pts.iter().any(|p| !p[0].is_finite() || !p[1].is_finite()) {
                        return Err(AdapterError::NonFinite { contour: ci, span: Some(si) });
                    }
                    let p0 = *ring.last().unwrap();
                    flatten_cubic(p0, control_one, control_two, end,
                                  flatten_tolerance, MAX_FLATTEN_DEPTH, &mut ring);
                }
            }
        }
        // Drop an explicit repeated-start closure point: ring closure is
        // implicit in the transfer, a duplicate last==first adds nothing.
        if ring.len() > 1 && ring.last() == Some(&contour.start) {
            ring.pop();
        }
        rings.push(ring);
    }
    let input = OutlineInput {
        glyph_id: glyph.glyph_id.clone(),
        source_pin: glyph.source_pin.clone(),
        upm: glyph.upm,
        origin: glyph.origin,
        flatten_tolerance,
        rings,
    };
    profile_outline(&input, policy).map_err(AdapterError::Profile)
}

#[cfg(test)]
mod p3_adapter_tests {
    use super::*;

    const K: f64 = 0.5522847498307936; // circle cubic arc constant

    fn policy() -> ScanPolicy {
        ScanPolicy { row_step: 4.0, max_rows: 1000, merge_guard: MERGE_GUARD_UNITS,
                     grid_anchor_y: None }
    }
    fn glyph(contours: Vec<EmittedContour>) -> EmittedGlyph {
        EmittedGlyph { glyph_id: "g".into(), source_pin: "sha256:emitted:g".into(),
                       upm: 1000, origin: [0.0, 0.0], contours }
    }
    fn rect_contour(x0: f64, y0: f64, x1: f64, y1: f64) -> EmittedContour {
        EmittedContour {
            start: [x0, y0],
            spans: vec![
                EmittedSpan::Line { end: [x1, y0] },
                EmittedSpan::Line { end: [x1, y1] },
                EmittedSpan::Line { end: [x0, y1] },
                EmittedSpan::Line { end: [x0, y0] },
            ],
        }
    }
    fn circle_contour(cx: f64, cy: f64, r: f64) -> EmittedContour {
        let k = K * r;
        EmittedContour {
            start: [cx + r, cy],
            spans: vec![
                EmittedSpan::Cubic { control_one: [cx + r, cy + k], control_two: [cx + k, cy + r], end: [cx, cy + r] },
                EmittedSpan::Cubic { control_one: [cx - k, cy + r], control_two: [cx - r, cy + k], end: [cx - r, cy] },
                EmittedSpan::Cubic { control_one: [cx - r, cy - k], control_two: [cx - k, cy - r], end: [cx, cy - r] },
                EmittedSpan::Cubic { control_one: [cx + k, cy - r], control_two: [cx + r, cy - k], end: [cx + r, cy] },
            ],
        }
    }

    #[test]
    fn emitted_cubic_circle_profiles_to_disk() {
        let g = glyph(vec![circle_contour(100.0, 100.0, 100.0)]);
        let p = profile_from_emitted(&g, 1000, policy(), 0.5).unwrap();
        let expect = std::f64::consts::PI * 100.0 * 100.0;
        let rel = (p.ink_area - expect).abs() / expect;
        assert!(rel < 0.05, "ink_area {} vs {} (rel {})", p.ink_area, expect, rel);
        assert_eq!(p.counter_area, 0.0);
        assert_eq!(p.open_left, 0.0);
        assert_eq!(p.open_right, 0.0);
        assert_eq!(p.bounds, [0.0, 0.0, 200.0, 200.0]);
        // Receipt: caller's policy/tolerance carried explicitly.
        assert_eq!(p.profile_method, "bounded_curve_flatten+scanline");
        assert_eq!(p.row_step, 4.0);
        assert_eq!(p.flatten_tolerance, 0.5);
    }

    #[test]
    fn emitted_counter_preserved_through_adapter() {
        let mut inner = rect_contour(30.0, 30.0, 70.0, 70.0);
        inner.spans.reverse(); // opposite winding for the counter ring
        let g = glyph(vec![rect_contour(0.0, 0.0, 100.0, 100.0), inner]);
        let p = profile_from_emitted(&g, 1000, policy(), 0.25).unwrap();
        assert!((p.counter_area - 1_600.0).abs() < 1e-9, "counter {}", p.counter_area);
        assert!((p.ink_area - 8_400.0).abs() < 1e-9);
        assert_eq!(p.flatten_tolerance, 0.25);
    }

    #[test]
    fn explicit_closure_point_is_deduped() {
        // Last span end == start (explicit closure): accepted, deduped.
        let g = glyph(vec![rect_contour(0.0, 0.0, 100.0, 200.0)]);
        let p = profile_from_emitted(&g, 1000, policy(), 0.5).unwrap();
        assert!((p.ink_area - 20_000.0).abs() < 1e-9);
        assert_eq!(p.rows.len(), 50);
    }

    #[test]
    fn adapter_typed_refusals() {
        assert_eq!(profile_from_emitted(&glyph(vec![rect_contour(0.0, 0.0, 10.0, 10.0)]), 2048, policy(), 0.5),
                   Err(AdapterError::UpmMismatch { declared: 1000, expected: 2048 }));
        assert_eq!(profile_from_emitted(&glyph(vec![rect_contour(0.0, 0.0, 10.0, 10.0)]), 1000, policy(), 0.0),
                   Err(AdapterError::BadFlattenTolerance));
        assert_eq!(profile_from_emitted(&glyph(vec![]), 1000, policy(), 0.5),
                   Err(AdapterError::NoContours));
        assert_eq!(profile_from_emitted(&glyph(vec![EmittedContour { start: [0.0, 0.0], spans: vec![] }]), 1000, policy(), 0.5),
                   Err(AdapterError::EmptyContour { contour: 0 }));
        let nan_ctrl = EmittedContour {
            start: [0.0, 0.0],
            spans: vec![EmittedSpan::Cubic { control_one: [f64::NAN, 1.0], control_two: [2.0, 2.0], end: [3.0, 3.0] }],
        };
        assert_eq!(profile_from_emitted(&glyph(vec![nan_ctrl]), 1000, policy(), 0.5),
                   Err(AdapterError::NonFinite { contour: 0, span: Some(0) }));
        let mut bad_origin = glyph(vec![rect_contour(0.0, 0.0, 10.0, 10.0)]);
        bad_origin.origin = [f64::INFINITY, 0.0];
        assert!(matches!(profile_from_emitted(&bad_origin, 1000, policy(), 0.5),
                         Err(AdapterError::NonFinite { .. })));
    }
}

#[cfg(test)]
mod seam_hardening_tests {
    //! P2-seam hardening (owner push 2026-10-15): prove the exact geometry
    //! K3's intersection/overlap detection consumes from align_pair_rows.
    use super::*;

    fn rect_input(x0: f64, y0: f64, x1: f64, y1: f64) -> OutlineInput {
        OutlineInput {
            glyph_id: "g".into(), source_pin: "sha256:test:g".into(), upm: 1000,
            origin: [0.0, 0.0], flatten_tolerance: 0.5,
            rings: vec![vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]],
        }
    }
    fn pol() -> ScanPolicy {
        ScanPolicy { row_step: 4.0, max_rows: 1000, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None }
    }

    #[test]
    fn aligned_intervals_verbatim_for_intersection_detection() {
        // Overlap seam: right glyph's ink sits INSIDE the left glyph's ink
        // span (as seen before translations). The aligned rows must carry
        // both sides' intervals bit-verbatim, so K3's strict-overlap test
        // (l_left < r_right && r_left < l_right) sees exact geometry.
        let a = profile_outline(&rect_input(0.0, 0.0, 120.0, 100.0), pol()).unwrap();
        let b = profile_outline(&rect_input(80.0, 30.0, 200.0, 130.0), pol()).unwrap();
        let aligned = align_pair_rows(&a, &b);
        let mid = aligned.iter().find(|r| (r.y - 31.0).abs() < 1e-9).unwrap();
        assert_eq!(mid.left, a.rows.iter().find(|r| r.y + r.weight * 0.5 > 30.0 && r.y - r.weight * 0.5 < 32.0).unwrap().ink);
        assert_eq!(mid.right, b.rows.iter().find(|r| r.y + r.weight * 0.5 > 30.0 && r.y - r.weight * 0.5 < 32.0).unwrap().ink);
        // And verbatim means the downstream intersection test fires:
        let (li, ri) = (mid.left[0], mid.right[0]);
        assert!(li.left < ri.right && ri.left < li.right, "overlap must be detectable on verbatim intervals");
    }

    #[test]
    fn aligned_reconstructs_exact_refinement_of_source_rows() {
        // Preservation invariant (K3's diff-proof made executable): every
        // source row's ink equals the union of aligned segments' verbatim
        // ink over the same y-span, for BOTH sides.
        let pol = ScanPolicy { grid_anchor_y: Some(1.0), ..pol() };
        let a = profile_outline(&rect_input(0.0, 0.0, 100.0, 97.0), pol).unwrap();
        let b = profile_outline(&rect_input(50.0, 13.0, 150.0, 144.0), pol).unwrap();
        let aligned = align_pair_rows(&a, &b);
        for (src_rows, pick_left) in [(&a.rows, true), (&b.rows, false)] {
            for sr in src_rows {
                let s0 = sr.y - sr.weight * 0.5;
                let s1 = sr.y + sr.weight * 0.5;
                // Every aligned segment fully inside this row's span must
                // carry exactly this row's ink (or be a gap-row segment).
                for ar in &aligned {
                    let a0 = ar.y - ar.weight * 0.5;
                    let a1 = ar.y + ar.weight * 0.5;
                    if a0 >= s0 - MERGE_GUARD_UNITS && a1 <= s1 + MERGE_GUARD_UNITS {
                        let v = if pick_left { &ar.left } else { &ar.right };
                        assert_eq!(*v, sr.ink, "segment at y={} not verbatim for source row y={}", ar.y, sr.y);
                    }
                }
            }
        }
    }

    #[test]
    fn merge_guard_skips_only_sub_guard_segments() {
        // Grids offset by 5e-10 (< MERGE_GUARD_UNITS): the sliver segment is
        // skipped; total weight loss stays below the explicit guard policy.
        let pa = pol();
        let pb = ScanPolicy { grid_anchor_y: Some(5e-10), ..pol() };
        let a = profile_outline(&rect_input(0.0, 0.0, 100.0, 100.0), pa).unwrap();
        let b = profile_outline(&rect_input(200.0, 0.0, 300.0, 100.0), pb).unwrap();
        let aligned = align_pair_rows(&a, &b);
        let total: f64 = aligned.iter().map(|r| r.weight).sum();
        let union = 100.0_f64; // both spans coincide: [0,100)
        // Each of the ~25 staggered grid boundaries can drop at most one
        // guard-width sliver; bound the loss by cuts * guard, never tighter.
        assert!((total - union).abs() < MERGE_GUARD_UNITS * 64.0,
                "weight loss beyond guard policy: {}", union - total);
        // Every surviving segment is wider than the guard.
        assert!(aligned.iter().all(|r| r.weight > MERGE_GUARD_UNITS));
    }
}

#[cfg(test)]
mod p2_eacute_u_fixture_tests {
    //! Hub-merge support (coordination ref: parent message 2026-10-15 22:47): Eacute->u fixture,
    //! span-truth regression at clipped boundary rows, and a K3-style
    //! integer consumer verification over align_pair_rows output.
    //! NOT a new API: exercises existing profile_outline/align_pair_rows.
    use super::*;

    /// Eacute-shaped: body [0,120]x[0,700] + accent [30,90]x[720,1015].
    /// Accent top 1015 is OFF the anchored-0 step-4 grid: the top boundary
    /// cell [1012,1016) is clipped to the true covered span [1012,1015)
    /// while its grid midpoint y=1014 sits inside. This is the P2 seam
    /// geometry (accent-zone boundary row).
    fn eacute_shaped(accent_top: f64) -> OutlineInput {
        OutlineInput {
            glyph_id: "Eacute".into(), source_pin: "sha256:test:Eacute".into(),
            upm: 2048, origin: [0.0, 0.0], flatten_tolerance: 0.5,
            rings: vec![
                vec![[0.0, 0.0], [120.0, 0.0], [120.0, 700.0], [0.0, 700.0]],
                vec![[30.0, 720.0], [90.0, 720.0], [90.0, accent_top], [30.0, accent_top]],
            ],
        }
    }
    /// u-shaped: single rect [200,320]x[0,700], integer geometry.
    fn u_shaped() -> OutlineInput {
        OutlineInput {
            glyph_id: "u".into(), source_pin: "sha256:test:u".into(),
            upm: 2048, origin: [0.0, 0.0], flatten_tolerance: 0.5,
            rings: vec![vec![[0.0, 0.0], [120.0, 0.0], [120.0, 700.0], [0.0, 700.0]]
                .iter().map(|p| [p[0] + 200.0, p[1]]).collect()],
        }
    }
    fn anchored_pol() -> ScanPolicy {
        ScanPolicy { row_step: 4.0, max_rows: 1000, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) }
    }

    /// K3-style consumer mirror (generated_outline_kern.rs L448-526 logic):
    /// strict overlap test + nearest-left-wall gap on verbatim intervals.
    fn k3_style_intersects(l: &[InkInterval], r: &[InkInterval], shift: f64) -> bool {
        l.iter().any(|li| r.iter().any(|ri| li.left < ri.right + shift && ri.left + shift < li.right))
    }
    fn k3_style_gap(l: &[InkInterval], r: &[InkInterval]) -> Option<f64> {
        r.iter().filter_map(|ri| {
            l.iter().filter(|li| li.right <= ri.left).map(|li| ri.left - li.right)
                .fold(None, |acc: Option<f64>, g| Some(acc.map_or(g, |a| a.min(g))))
        }).fold(None, |acc, g| Some(acc.map_or(g, |a| a.min(g)))
        )
    }

    #[test]
    fn eacute_accent_top_boundary_row_span_is_true() {
        let p = profile_outline(&eacute_shaped(1015.0), anchored_pol()).unwrap();
        let top = p.rows.last().unwrap();
        // Grid cell [1012,1016), midpoint 1014, clipped to [1012,1015).
        assert_eq!(top.y, 1014.0);
        assert_eq!(top.weight, 3.0);
        assert_eq!(top.span_lo, 1012.0);
        assert_eq!(top.span_hi, 1015.0);
        assert_eq!(top.ink, vec![InkInterval { left: 30.0, right: 90.0 }]);
        // Global invariant on every row.
        for r in &p.rows {
            assert!((r.span_hi - r.span_lo - r.weight).abs() <= MERGE_GUARD_UNITS);
            assert!(r.span_lo >= -MERGE_GUARD_UNITS && r.span_hi <= 1015.0 + MERGE_GUARD_UNITS);
        }
    }

    #[test]
    fn eacute_u_aligned_segments_carry_accent_ink_on_true_span_only() {
        let a = profile_outline(&eacute_shaped(1015.0), anchored_pol()).unwrap();
        let b = profile_outline(&u_shaped(), anchored_pol()).unwrap();
        let aligned = align_pair_rows(&a, &b);
        let accent = InkInterval { left: 30.0, right: 90.0 };
        for ar in &aligned {
            let lo = ar.y - ar.weight * 0.5;
            let hi = ar.y + ar.weight * 0.5;
            let has_accent = ar.left.contains(&accent);
            // Accent ink exists exactly on true spans inside [720,1015).
            let in_accent_zone = lo >= 720.0 - MERGE_GUARD_UNITS && hi <= 1015.0 + MERGE_GUARD_UNITS
                && hi > 720.0 && lo < 1015.0;
            assert_eq!(has_accent, in_accent_zone,
                "accent ink mis-assigned at segment [{lo},{hi})");
            // No aligned segment may carry ANY left ink above the true top.
            if lo >= 1015.0 - MERGE_GUARD_UNITS {
                assert!(ar.left.is_empty(), "phantom ink above true top at [{lo},{hi})");
            }
        }
        // The true top boundary must appear as a cut: segments tile to 1015.
        let max_hi = aligned.iter().map(|r| r.y + r.weight * 0.5).fold(0.0_f64, f64::max);
        assert_eq!(max_hi, 1015.0);
    }

    #[test]
    fn k3_consumer_integer_verification() {
        // Integer geometry end-to-end: gaps exact integers, no phantom
        // intersection, detection fires exactly on real overlap.
        let a = profile_outline(&eacute_shaped(1015.0), anchored_pol()).unwrap();
        let b = profile_outline(&u_shaped(), anchored_pol()).unwrap();
        let aligned = align_pair_rows(&a, &b);
        for ar in &aligned {
            assert_eq!(ar.weight.fract(), 0.0, "non-integer segment weight");
            // Untranslated: gap is exactly 80 (=200-120) on body rows,
            // 110 (=200-90) on accent rows; never negative, never overlap.
            assert!(!k3_style_intersects(&ar.left, &ar.right, 0.0));
            if let (Some(li), Some(_)) = (ar.left.first(), ar.right.first()) {
                let g = k3_style_gap(&ar.left, &ar.right).unwrap();
                let lo = ar.y - ar.weight * 0.5;
                let expect = if lo >= 720.0 { 110.0 } else { 80.0 };
                if li.left == 0.0 || li.left == 30.0 {
                    assert_eq!(g, expect, "gap at segment lo={lo}");
                }
            }
        }
        // Kern overshoot of -100: u ink shifts to [100,220]; body rows
        // overlap ([0,120] vs [100,220]) but accent rows must NOT.
        for ar in &aligned {
            let lo = ar.y - ar.weight * 0.5;
            let hit = k3_style_intersects(&ar.left, &ar.right, -100.0);
            let body = lo < 700.0 - MERGE_GUARD_UNITS;
            assert_eq!(hit, body && !ar.left.is_empty() && !ar.right.is_empty(),
                "intersection mis-detected at segment lo={lo}");
        }
    }

    fn lb_rect(x0: f64, y0: f64, x1: f64, y1: f64) -> Vec<[f64; 2]> {
        vec![[x0, y0], [x1, y0], [x1, y1], [x0, y1]]
    }
    fn lb_input(rings: Vec<Vec<[f64; 2]>>) -> OutlineInput {
        OutlineInput {
            glyph_id: "g".to_string(),
            source_pin: "sha256:test:g".to_string(),
            upm: 1000,
            origin: [0.0, 0.0],
            flatten_tolerance: 0.5,
            rings,
        }
    }

    #[test]
    fn degenerate_ring_is_a_typed_exclusion_and_the_glyph_ships() {
        // Two real rectangles + one 1-point ring: the glyph profiles from
        // its surviving rings, bit-identical to the same input WITHOUT the
        // degenerate ring, and the ring leaves a typed exclusion row.
        let good = vec![lb_rect(0.0, 0.0, 100.0, 200.0), lb_rect(200.0, 0.0, 300.0, 200.0)];
        let mut with_bad = good.clone();
        with_bad.push(vec![[7.0, 7.0]]);
        let pol = ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None };
        let (res, excl) = profile_outline_with_exclusions(&lb_input(with_bad), pol);
        let p = res.unwrap();
        assert_eq!(excl, vec![RingExclusion { ring: 2, reason: RingExclusionReason::DegenerateRing { points: 1 } }]);
        let p_ref = profile_outline(&lb_input(good), pol).unwrap();
        assert_eq!(format!("{p:?}"), format!("{p_ref:?}"), "surviving rings: profile bit-identical");
    }

    #[test]
    fn all_rings_degenerate_is_a_typed_whole_glyph_drop() {
        let pol = ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None };
        let (res, excl) = profile_outline_with_exclusions(&lb_input(vec![vec![[1.0, 1.0]], vec![]]), pol);
        assert_eq!(res, Err(ProfileError::Empty), "no surviving ring: typed drop");
        assert_eq!(excl.len(), 2, "both rings receipted");
    }

    #[test]
    fn thin_ring_between_grid_rows_gets_a_derived_row() {
        // Big grid-covered body + one 2-unit sliver far off the 10-unit
        // anchored grid: the sliver must surface in the profile via one
        // derived row (y = its own mid-height, weight = its own height).
        let body = lb_rect(0.0, 0.0, 100.0, 50.0);
        let sliver = lb_rect(10.0, 53.0, 60.0, 55.0); // 50x2, band [53,55): no anchor-0/10 midpoint (rows at 45,55,...)
        let pol = ScanPolicy { row_step: 10.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) };
        let p = profile_outline(&lb_input(vec![body, sliver]), pol).unwrap();
        let derived: Vec<_> = p.rows.iter().filter(|r| r.y == 54.0).collect();
        assert_eq!(derived.len(), 1, "one derived row at the sliver's own mid-height");
        assert_eq!(derived[0].weight, 2.0, "weight derived from the sliver's own height");
        assert_eq!(derived[0].span_lo, 53.0);
        assert_eq!(derived[0].span_hi, 55.0);
        assert!(derived[0].ink.iter().any(|iv| (iv.left - 10.0).abs() < 1e-9 && (iv.right - 60.0).abs() < 1e-9),
            "derived row carries the sliver ink interval");
        assert!((p.ink_area - (100.0 * 50.0 + 50.0 * 2.0)).abs() < 1e-6,
            "ink_area includes the sliver: {}", p.ink_area);
    }

    #[test]
    fn grid_covered_rings_get_no_supplement_bit_identical_rows() {
        // All rings grid-covered: the row set is exactly the plain grid.
        let body = lb_rect(0.0, 0.0, 100.0, 200.0);
        let pol = ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None };
        let p = profile_outline(&lb_input(vec![body]), pol).unwrap();
        assert_eq!(p.rows.len(), 50, "no supplementary rows on the covered path");
        assert!(p.rows.iter().all(|r| r.weight == 4.0), "all rows are grid rows");
        assert!((p.ink_area - 20_000.0).abs() < 1e-9);
    }

    #[test]
    fn dash_like_slivers_all_surface() {
        // Marq dash class: 18 thin slivers on a 10-unit anchored grid.
        let mut rings = Vec::new();
        for k in 0..18 {
            let y = 1.0 + k as f64 * 6.0; // off-grid bands, 2 units tall
            rings.push(lb_rect(50.0 + (k % 5) as f64, y, 300.0 - (k % 3) as f64, y + 2.0));
        }
        let pol = ScanPolicy { row_step: 10.0, max_rows: 1000, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: Some(0.0) };
        let p = profile_outline(&lb_input(rings), pol).unwrap();
        assert!(p.ink_area > 0.0, "the dash ships ink");
        for k in 0..18 {
            let y = 1.0 + k as f64 * 6.0;
            assert!(p.rows.iter().any(|r| r.y >= y && r.y < y + 2.0),
                "sliver {k} band [{y},{}) is scanned by some row (grid or derived)", y + 2.0);
        }
        let derived = p.rows.iter().filter(|r| r.weight == 2.0).count();
        assert_eq!(derived, 15, "only the grid-missed slivers get a derived row (3 land on midpoints)");
    }

    #[test]
    fn wrapper_matches_exclusion_variant_result() {
        let pol = ScanPolicy { row_step: 4.0, max_rows: 100, merge_guard: MERGE_GUARD_UNITS, grid_anchor_y: None };
        let i = lb_input(vec![lb_rect(0.0, 0.0, 10.0, 10.0), vec![[0.0, 0.0]]]);
        let a = profile_outline(&i, pol);
        let (b, excl) = profile_outline_with_exclusions(&i, pol);
        assert_eq!(format!("{a:?}"), format!("{b:?}"));
        assert_eq!(excl.len(), 1);
    }
}
