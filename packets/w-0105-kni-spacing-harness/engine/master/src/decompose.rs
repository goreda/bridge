//! Slice A of MASTER-GLYPHS-PARTS: generic decomposition of a flat export
//! outline into structural parts (stem, arms, legs, bowls) from geometry
//! alone, with part identity provenance.
//!
//! Language-agnostic: nothing here reads a glyph name, a Unicode range or a
//! per-glyph part count. Method: rasterize the silhouette, take its
//! topological skeleton, open the skeleton graph at junctions, group
//! skeleton branches into parts by two geometric merge rules, then assign
//! the ORIGINAL vector boundary to parts so every visible edge stays on the
//! source geometry (wrap cuts happen only inside ink).
//!
//! Merge rules (both geometric):
//! A. STRAIGHT-THROUGH: at a junction, two branches leaving in opposite
//!    directions (within `smooth_deg` of a straight line) are one part.
//! B. COUNTER CYCLE: two or more unmerged branches between the same two
//!    junctions that enclose a hole (outside the ink) are one bowl.
//!
//! Labels come from measured geometry (axis angle against the glyph's own
//! principal axis, length/width aspect, curved share of the boundary,
//! counter ownership, free ends), not from names. Every label decision is
//! recorded in `Provenance::rule` with the numbers that drove it.
//!
//! Rotation: INTENDED invariance, not yet proven: the glyph principal axis
//! comes from the ink itself (PCA) and label angles are relative to that
//! axis, but the raster skeleton of a rotated glyph is noisier and the
//! rotation regression test currently fails. When the ink is
//! near-isotropic (ring, square) there is no glyph axis and labels fall
//! back to the font y-axis; the provenance says which frame was used.
//!
//! CONVENTION-tagged literals are classifier conventions (like the
//! validator's smooth/corner tolerances), each exposed in
//! `DecomposeParams`; none is a measurement of any glyph.

use crate::check::stroke_polygon;
use crate::model::{MasterGlyph, Op, Pt, Seg, SegKind, StrokeContour};
use crate::raster::{bounds_of, rasterize};
use std::collections::{HashMap, HashSet, VecDeque};

/// Resource guard: raster cell budget (not a measurement).
pub const MAX_RASTER_PIXELS: usize = 1 << 26;
/// Resource guard: thinning iteration cap (not a measurement).
pub const MAX_THIN_ITERS: usize = 4096;
/// Resource guard: boundary samples per segment (not a measurement).
pub const MAX_SEG_SAMPLES: usize = 4096;

/// CONVENTION: default straight-through tolerance at a junction (degrees
/// away from 180). Matches the validator's corner floor spirit.
pub const DEFAULT_SMOOTH_DEG: f64 = 30.0;
/// CONVENTION: a bar whose axis sits within this angle of the glyph axis is
/// a stem.
pub const DEFAULT_STEM_DEG: f64 = 25.0;
/// CONVENTION: a bar whose axis sits beyond this angle from the glyph axis
/// is an arm; between stem and arm angles it is a diagonal (leg or arm by
/// where its mass sits along the glyph axis).
pub const DEFAULT_ARM_DEG: f64 = 65.0;
/// CONVENTION: skeleton length / stroke width below this is a mark, not a
/// bar.
pub const DEFAULT_BAR_ASPECT: f64 = 2.0;
/// CONVENTION: a low-curvature part whose moment aspect exceeds this AND
/// whose axis sits within `stem_deg` of the FONT y-axis is a stem by
/// geometry alone (vertical-extent-dominant bar); junction topology is
/// only a tiebreaker. Value 10 from the chief ruling on the owner h
/// reference (stem aspect 10.84, arch aspect 11.67 but 34.6 deg off the
/// font y-axis, so the angle guard separates them). Font-general: no
/// glyph, script, or font-specific input.
pub const DEFAULT_STEM_BAR_ASPECT: f64 = 10.0;
/// CONVENTION: an open part whose boundary is at least half curves is an
/// arm (arch), not a bar.
pub const DEFAULT_CURVE_RATIO_ARM: f64 = 0.5;
/// CONVENTION: skeleton end branches shorter than this many cells are
/// thinning spurs and merge into their neighbour.
pub const DEFAULT_PRUNE_CELLS: usize = 4;
/// CONVENTION: a partition root owning less than this fraction of the
/// glyph ink is an orphan (skeleton spur sliver or boundary bleed) and
/// joins the nearest substantial part.
pub const DEFAULT_ORPHAN_INK_FRAC: f64 = 0.02;
/// CONVENTION: an attached root with less than this fraction of the
/// glyph ink is a fragment of a split stroke (arch cap, bar tip fork)
/// and joins the neighbour it shares the longest boundary with.
/// Detached marks share no boundary with any region and never merge.
pub const DEFAULT_FRAGMENT_INK_FRAC: f64 = 0.12;
/// CONVENTION: a part below this ink fraction AND below `bar_aspect`
/// elongation is a mark; above it the angle rules decide.
pub const DEFAULT_MARK_INK_FRAC: f64 = 0.15;
/// CONVENTION: a stem-parallel part whose skeleton bends at least this
/// many degrees across a pass-through node is an arm, not a stem. A
/// right-angle arch reads 80-90 deg here; junction jogs read up to ~50.
pub const DEFAULT_BEND_DEG: f64 = 60.0;
/// CONVENTION: a cut line detours through a shared junction point only
/// when the point lies within this many stroke widths of the chord.
pub const DEFAULT_CUT_CORRIDOR_WIDTHS: f64 = 2.0;
/// CONVENTION: branch direction is measured over this many skeleton cells
/// from a node. Branches shorter than twice this window carry no turn
/// measurement (derived: one window at each end).
pub const DEFAULT_DIR_WINDOW_CELLS: usize = 8;
/// CONVENTION: PCA eigenvalue gap below this fraction of the trace means
/// the ink has no principal axis (ring, square).
pub const AXIS_DEGENERATE: f64 = 0.05;

#[derive(Debug, Clone, Copy)]
pub struct DecomposeParams {
    /// Target raster cells across the longest bbox side.
    pub raster_cells: usize,
    pub smooth_deg: f64,
    pub stem_deg: f64,
    pub arm_deg: f64,
    pub bar_aspect: f64,
    /// See DEFAULT_STEM_BAR_ASPECT.
    pub stem_bar_aspect: f64,
    pub curve_ratio_arm: f64,
    pub prune_cells: usize,
    pub orphan_ink_frac: f64,
    pub fragment_ink_frac: f64,
    pub mark_ink_frac: f64,
    pub bend_deg: f64,
    pub cut_corridor_widths: f64,
    pub dir_window_cells: usize,
}

impl Default for DecomposeParams {
    fn default() -> Self {
        DecomposeParams {
            raster_cells: 640,
            smooth_deg: DEFAULT_SMOOTH_DEG,
            stem_deg: DEFAULT_STEM_DEG,
            arm_deg: DEFAULT_ARM_DEG,
            bar_aspect: DEFAULT_BAR_ASPECT,
            stem_bar_aspect: DEFAULT_STEM_BAR_ASPECT,
            curve_ratio_arm: DEFAULT_CURVE_RATIO_ARM,
            prune_cells: DEFAULT_PRUNE_CELLS,
            orphan_ink_frac: DEFAULT_ORPHAN_INK_FRAC,
            fragment_ink_frac: DEFAULT_FRAGMENT_INK_FRAC,
            mark_ink_frac: DEFAULT_MARK_INK_FRAC,
            bend_deg: DEFAULT_BEND_DEG,
            cut_corridor_widths: DEFAULT_CUT_CORRIDOR_WIDTHS,
            dir_window_cells: DEFAULT_DIR_WINDOW_CELLS,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum DecomposeError {
    EmptyOutline,
    PixelBudget { pixels: u128, limit: usize },
    /// Assembly produced output violating the one-closed-ring structural
    /// contract (see `check_structure`); refused instead of returned.
    Structure(String),
}

/// Geometric class of a part. The vocabulary (stem/arm/leg/bowl) is the
/// master drawing standard's; assignment here is purely geometric.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PartClass {
    Stem,
    Arm,
    Leg,
    Bowl,
    /// Small detached component (dot, accent, mark of any script).
    Mark,
}

impl PartClass {
    pub fn as_str(self) -> &'static str {
        match self {
            PartClass::Stem => "stem",
            PartClass::Arm => "arm",
            PartClass::Leg => "leg",
            PartClass::Bowl => "bowl",
            PartClass::Mark => "mark",
        }
    }
}

/// Identity provenance of one part: what it was built from and why it got
/// its label.
#[derive(Debug, Clone)]
pub struct Provenance {
    /// Skeleton branch ids merged into this part.
    pub branches: Vec<usize>,
    /// Source boundary runs: (contour index, first segment, last segment)
    /// in source contour order. Counter contours owned whole are listed in
    /// `counters`.
    pub runs: Vec<(usize, usize, usize)>,
    /// Counter contours this part carries (source contour indices).
    pub counters: Vec<usize>,
    /// Part principal axis, degrees from font +x (undirected, [0,180)).
    pub axis_deg: f64,
    /// Angle between part axis and glyph axis in degrees, [0,90]. None when
    /// the glyph has no principal axis (near-isotropic ink).
    pub rel_axis_deg: Option<f64>,
    /// Skeleton length / mean stroke width (both in font units).
    pub aspect: f64,
    /// Curved boundary length / total boundary length of the part.
    pub curvature: f64,
    /// Free (degree-1) skeleton ends in this part.
    pub free_ends: usize,
    /// Part centroid along the glyph axis, normalized to the glyph bbox
    /// [0,1] (0 = low end). None when no glyph axis exists.
    pub axis_pos: Option<f64>,
    /// Human-readable decision path with the measured numbers.
    pub rule: String,
}

#[derive(Debug, Clone)]
pub struct Part {
    pub name: String,
    pub class: PartClass,
    /// The part's outer ring: exactly one closed ring per structural
    /// stroke (the B/C source adapter refuses interior Move/Close).
    pub contour: StrokeContour,
    /// Counter rings owned by this part, each one closed ring. They cut
    /// holes out of `contour` (bowls); empty for open strokes.
    pub holes: Vec<StrokeContour>,
    pub provenance: Provenance,
}

#[derive(Debug, Clone)]
pub struct Decomposition {
    /// The master glyph: each part contributes its outer ring followed by
    /// its counter rings. Ring stroke names carry the grouping: a ring
    /// named `<part>.counterN` is a HOLE of part `<part>`. Every counter
    /// ring is emitted with winding OPPOSITE to its owner's outer ring,
    /// so a nonzero (sum-of-windings) fill subtracts the counters and the
    /// exported glyph preserves the source ink; a per-ring union fill
    /// (`inside_union`) is NOT a valid consumer of this export.
    pub glyph: MasterGlyph,
    pub parts: Vec<Part>,
    /// Glyph principal axis, degrees from font +x; None when the ink is
    /// near-isotropic.
    pub glyph_axis_deg: Option<f64>,
    /// Raster cell size used, in font units.
    pub cell: f64,
}

// ---------------- skeleton internals ----------------

#[derive(Debug, Clone)]
struct Branch {
    /// Node ids at both ends; usize::MAX marks the single loop of a
    /// node-less cycle (whole skeleton is one ring).
    a: usize,
    b: usize,
    /// Ordered pixel indices (row-major) from end a to end b, inclusive of
    /// junction-cluster boundary pixels.
    pixels: Vec<usize>,
    /// Path length in cells.
    len: f64,
}

struct Skeleton {
    w: usize,
    h: usize,
    deg: Vec<u8>,
    /// Distance transform of the ink, in cells.
    dist: Vec<f32>,
    nodes: Vec<Vec<usize>>,
    branches: Vec<Branch>,
}

const NB8: [(isize, isize); 8] = [
    (-1, 0), (1, 0), (0, -1), (0, 1),
    (-1, -1), (1, -1), (-1, 1), (1, 1),
];

fn neighbors8(w: usize, h: usize, i: usize) -> impl Iterator<Item = usize> {
    let (x, y) = ((i % w) as isize, (i / w) as isize);
    NB8.iter().filter_map(move |&(dx, dy)| {
        let (nx, ny) = (x + dx, y + dy);
        if nx >= 0 && ny >= 0 && (nx as usize) < w && (ny as usize) < h {
            Some(ny as usize * w + nx as usize)
        } else {
            None
        }
    })
}

/// Two-pass 3-4 chamfer distance transform, distances in cells.
fn distance_transform(mask: &[bool], w: usize, h: usize) -> Vec<f32> {
    let inf = 1e9f32;
    let mut d = vec![inf; mask.len()];
    for (i, &m) in mask.iter().enumerate() {
        if m {
            d[i] = 0.0;
        }
    }
    // The transform measures INK depth: distance to the nearest background.
    // Seed: ink pixels start large, background zero, then relax.
    for (i, &m) in mask.iter().enumerate() {
        d[i] = if m { inf } else { 0.0 };
    }
    for j in 0..h {
        for i in 0..w {
            let p = j * w + i;
            if d[p] == 0.0 {
                continue;
            }
            let mut best = d[p];
            if i > 0 {
                best = best.min(d[p - 1] + 3.0);
                if j > 0 {
                    best = best.min(d[p - 1 - w] + 4.0);
                }
                if j + 1 < h {
                    best = best.min(d[p - 1 + w] + 4.0);
                }
            }
            if j > 0 {
                best = best.min(d[p - w] + 3.0);
            }
            d[p] = best;
        }
    }
    for j in (0..h).rev() {
        for i in (0..w).rev() {
            let p = j * w + i;
            if d[p] == 0.0 {
                continue;
            }
            let mut best = d[p];
            if i + 1 < w {
                best = best.min(d[p + 1] + 3.0);
                if j > 0 {
                    best = best.min(d[p + 1 - w] + 4.0);
                }
                if j + 1 < h {
                    best = best.min(d[p + 1 + w] + 4.0);
                }
            }
            if j + 1 < h {
                best = best.min(d[p + w] + 3.0);
            }
            d[p] = best;
        }
    }
    for v in d.iter_mut() {
        *v /= 3.0;
    }
    d
}

/// Pixel-level despur: delete endpoint stubs of at most 3 cells hanging off
/// a junction. Staircase edges spawn deg-3 pixels via 1-2 cell stubs; left
/// in place they fragment the graph into thickets.

fn thin(mask: &[bool], w: usize, h: usize) -> Vec<bool> {
    let mut m = mask.to_vec();
    let at = |m: &[bool], x: isize, y: isize| -> bool {
        if x < 0 || y < 0 || x >= w as isize || y >= h as isize {
            false
        } else {
            m[y as usize * w + x as usize]
        }
    };
    for _ in 0..MAX_THIN_ITERS {
        let mut changed = false;
        for step in 0..2 {
            let mut kill: Vec<usize> = Vec::new();
            for j in 0..h as isize {
                for i in 0..w as isize {
                    if !at(&m, i, j) {
                        continue;
                    }
                    let p2 = at(&m, i, j + 1);
                    let p3 = at(&m, i + 1, j + 1);
                    let p4 = at(&m, i + 1, j);
                    let p5 = at(&m, i + 1, j - 1);
                    let p6 = at(&m, i, j - 1);
                    let p7 = at(&m, i - 1, j - 1);
                    let p8 = at(&m, i - 1, j);
                    let p9 = at(&m, i - 1, j + 1);
                    let ring = [p2, p3, p4, p5, p6, p7, p8, p9];
                    let b: usize = ring.iter().filter(|&&v| v).count();
                    if !(2..=6).contains(&b) {
                        continue;
                    }
                    let mut a = 0;
                    for k in 0..8 {
                        if !ring[k] && ring[(k + 1) % 8] {
                            a += 1;
                        }
                    }
                    if a != 1 {
                        continue;
                    }
                    let gate = if step == 0 {
                        !(p2 && p4 && p6) && !(p4 && p6 && p8)
                    } else {
                        !(p2 && p4 && p8) && !(p2 && p6 && p8)
                    };
                    if gate {
                        kill.push(j as usize * w + i as usize);
                    }
                }
            }
            if kill.is_empty() {
                continue;
            }
            changed = true;
            for p in kill {
                m[p] = false;
            }
        }
        if !changed {
            break;
        }
    }
    m
}

fn build_skeleton(mask: &[bool], w: usize, h: usize) -> Skeleton {
    let dist = distance_transform(mask, w, h);
    let skel = thin(mask, w, h);
    let skel = destaircase(&skel, w, h);
    let mut deg = vec![0u8; skel.len()];
    for (i, &s) in skel.iter().enumerate() {
        if s {
            deg[i] = neighbors8(w, h, i).filter(|&q| skel[q]).count() as u8;
        }
    }
    // Nodes: endpoints (deg 1) each alone; junction pixels (deg >= 3)
    // clustered by 8-connectivity.
    let mut node_of = vec![-1i32; skel.len()];
    let mut nodes: Vec<Vec<usize>> = Vec::new();
    for (i, &s) in skel.iter().enumerate() {
        if s && deg[i] == 1 {
            node_of[i] = nodes.len() as i32;
            nodes.push(vec![i]);
        }
    }
    for (i, &s) in skel.iter().enumerate() {
        if !(s && deg[i] >= 3) || node_of[i] >= 0 {
            continue;
        }
        let id = nodes.len() as i32;
        let mut cluster = vec![i];
        node_of[i] = id;
        let mut q = VecDeque::from([i]);
        while let Some(p) = q.pop_front() {
            for n in neighbors8(w, h, p) {
                if skel[n] && deg[n] >= 3 && node_of[n] < 0 {
                    node_of[n] = id;
                    cluster.push(n);
                    q.push_back(n);
                }
            }
        }
        nodes.push(cluster);
    }
    // Branches: trace from node pixels outward.
    let mut branches: Vec<Branch> = Vec::new();
    let mut used: HashSet<(u32, u32)> = HashSet::new();
    let edge = |u: usize, v: usize| -> (u32, u32) {
        if u < v {
            (u as u32, v as u32)
        } else {
            (v as u32, u as u32)
        }
    };
    let step_len = |u: usize, v: usize| -> f64 {
        let dx = (u % w) as f64 - (v % w) as f64;
        let dy = (u / w) as f64 - (v / w) as f64;
        dx.hypot(dy)
    };
    for (nid, pixels) in nodes.iter().enumerate() {
        for &p in pixels {
            for q in neighbors8(w, h, p) {
                if !skel[q] || node_of[q] == nid as i32 || used.contains(&edge(p, q)) {
                    continue;
                }
                let mut path = vec![p, q];
                let mut len = step_len(p, q);
                used.insert(edge(p, q));
                let (mut prev, mut cur) = (p, q);
                let end;
                loop {
                    if node_of[cur] >= 0 {
                        end = node_of[cur] as usize;
                        break;
                    }
                    // cur is a deg-2 pixel (a deg-1 pixel is a node).
                    let next = neighbors8(w, h, cur).find(|&n| {
                        skel[n] && n != prev && (node_of[n] < 0 || node_of[n] != node_of[cur])
                    });
                    match next {
                        Some(n) => {
                            // A junction pixel entered mid-branch ends it.
                            if node_of[n] >= 0 || deg[n] != 2 {
                                used.insert(edge(cur, n));
                                len += step_len(cur, n);
                                path.push(n);
                                end = if node_of[n] >= 0 {
                                    node_of[n] as usize
                                } else {
                                    nid
                                };
                                break;
                            }
                            used.insert(edge(cur, n));
                            len += step_len(cur, n);
                            path.push(n);
                            prev = cur;
                            cur = n;
                        }
                        None => {
                            end = nid;
                            break;
                        }
                    }
                }
                branches.push(Branch { a: nid, b: end, pixels: path, len });
            }
        }
    }
    // Node-less cycle: the whole skeleton is one ring (O-like shapes).
    if nodes.is_empty() {
        if let Some(start) = skel.iter().position(|&s| s) {
            let mut path = vec![start];
            let mut len = 0.0;
            let mut prev = start;
            let mut cur = neighbors8(w, h, start).find(|&n| skel[n]).unwrap_or(start);
            while cur != start {
                path.push(cur);
                len += step_len(prev, cur);
                let next = neighbors8(w, h, cur)
                    .find(|&n| skel[n] && n != prev)
                    .unwrap_or(start);
                prev = cur;
                cur = next;
                if path.len() > skel.len() {
                    break;
                }
            }
            len += step_len(prev, cur);
            branches.push(Branch { a: usize::MAX, b: usize::MAX, pixels: path, len });
        }
    }
    consolidate(&mut nodes, &mut branches);
    // Leftover skeleton pixels (blobs that thinned to a point, fragments
    // dropped by consolidation): each component is a degenerate branch so
    // its ink still gets a part.
    {
        let mut covered = vec![false; skel.len()];
        for n in &nodes {
            for &p in n {
                covered[p] = true;
            }
        }
        for b in &branches {
            for &p in &b.pixels {
                covered[p] = true;
            }
        }
        let mut i = 0;
        while i < skel.len() {
            if skel[i] && !covered[i] {
                let mut comp = vec![i];
                covered[i] = true;
                let mut q = VecDeque::from([i]);
                while let Some(p) = q.pop_front() {
                    for n2 in neighbors8(w, h, p) {
                        if skel[n2] && !covered[n2] {
                            covered[n2] = true;
                            comp.push(n2);
                            q.push_back(n2);
                        }
                    }
                }
                branches.push(Branch { a: usize::MAX, b: usize::MAX, pixels: comp, len: 0.0 });
            }
            i += 1;
        }
    }
    Skeleton { w, h, deg, dist, nodes, branches }
}

/// Resource guard: junction nodes linked by a branch at most this many
/// cells long are one junction zone (staircase artifact guard).
const NODE_MERGE_CELLS: usize = 12;

/// Collapse junction thickets: absorb tiny self-loops into their node and
/// merge junction-node pairs joined by a branch of <= NODE_MERGE_CELLS.
fn consolidate(nodes: &mut Vec<Vec<usize>>, branches: &mut Vec<Branch>) {
    // incident branch count per node
    let mut incident: HashMap<usize, usize> = HashMap::new();
    for b in branches.iter() {
        if b.a != usize::MAX {
            *incident.entry(b.a).or_default() += 1;
        }
        if b.b != usize::MAX && b.b != b.a {
            *incident.entry(b.b).or_default() += 1;
        }
    }
    let is_junction = |n: usize, incident: &HashMap<usize, usize>| incident.get(&n).copied().unwrap_or(0) >= 3;
    // tiny self-loops are thinning rings: absorb
    branches.retain(|b| !(b.a == b.b && b.pixels.len() <= NODE_MERGE_CELLS));
    // union-find over nodes
    let mut parent: Vec<usize> = (0..nodes.len()).collect();
    fn find(p: &mut Vec<usize>, mut x: usize) -> usize {
        while p[x] != x {
            p[x] = p[p[x]];
            x = p[x];
        }
        x
    }
    loop {
        let mut merged = false;
        for b in branches.iter() {
            if b.a == usize::MAX || b.a == b.b || b.pixels.len() > NODE_MERGE_CELLS {
                continue;
            }
            let (ra, rb) = (find(&mut parent, b.a), find(&mut parent, b.b));
            if ra == rb {
                continue;
            }
            let _ = is_junction;
            let ia = incident.get(&ra).copied().unwrap_or(0);
            let ib = incident.get(&rb).copied().unwrap_or(0);
            // merge junction thickets and staircase chains: any short
            // branch between non-endpoint nodes collapses
            if ia >= 2 && ib >= 2 {
                let (keep, drop_) = (ra.min(rb), ra.max(rb));
                parent[drop_] = keep;
                *incident.entry(keep).or_default() += incident.get(&drop_).copied().unwrap_or(0);
                // the connecting branch becomes cluster interior
                merged = true;
            }
        }
        if !merged {
            break;
        }
        // apply: remap branch endpoints, absorb absorbed-branch pixels
        let mut absorbed: Vec<Vec<usize>> = (0..nodes.len()).map(|_| Vec::new()).collect();
        let mut keep_branches: Vec<Branch> = Vec::new();
        for b in branches.iter() {
            if b.a == usize::MAX {
                keep_branches.push(b.clone());
                continue;
            }
            let (ra, rb) = (find(&mut parent, b.a), find(&mut parent, b.b));
            if ra == rb && b.pixels.len() <= NODE_MERGE_CELLS {
                absorbed[ra].extend(b.pixels.iter().copied());
            } else {
                let mut nb = b.clone();
                nb.a = ra;
                nb.b = rb;
                keep_branches.push(nb);
            }
        }
        // rebuild node list with roots only
        let mut remap: HashMap<usize, usize> = HashMap::new();
        let mut new_nodes: Vec<Vec<usize>> = Vec::new();
        for (i, px) in nodes.iter().enumerate() {
            let r = find(&mut parent, i);
            if r == i {
                remap.insert(i, new_nodes.len());
                let mut cluster = px.clone();
                cluster.extend(absorbed[i].iter().copied());
                new_nodes.push(cluster);
            } else {
                let root = r;
                // append later via absorbed trick: stash into absorbed[root]
                absorbed[root].extend(px.iter().copied());
            }
        }
        for (i, extra) in absorbed.iter().enumerate() {
            if extra.is_empty() {
                continue;
            }
            if let Some(&slot) = remap.get(&i) {
                new_nodes[slot].extend(extra.iter().copied());
            }
        }
        // dedupe cluster pixels
        for c in new_nodes.iter_mut() {
            c.sort_unstable();
            c.dedup();
        }
        // remap branch endpoints to new ids
        for b in keep_branches.iter_mut() {
            if b.a != usize::MAX {
                b.a = remap[&b.a];
            }
            if b.b != usize::MAX {
                b.b = remap[&b.b];
            }
        }
        // drop branches fully inside a cluster now
        keep_branches.retain(|b| !(b.a == b.b && b.pixels.len() <= NODE_MERGE_CELLS));
        *nodes = new_nodes;
        *branches = keep_branches;
        // recompute incident
        incident.clear();
        for b in branches.iter() {
            if b.a != usize::MAX {
                *incident.entry(b.a).or_default() += 1;
            }
            if b.b != usize::MAX && b.b != b.a {
                *incident.entry(b.b).or_default() += 1;
            }
        }
    }
}

/// Remove staircase junction artifacts from a thinned skeleton: on a
/// diagonal or curved stroke the medial axis is a staircase, and the
/// staircase corners read as deg-3 "junctions" that do not correspond to
/// any real branching. A junction pixel whose skeleton neighbours stay
/// 8-connected WITHOUT it is redundant: deleting it cannot disconnect the
/// skeleton. Real junctions (three arms leaving in separated directions)
/// survive. Removals in one pass form an independent set (no two
/// adjacent): the connectivity argument is per pixel on one snapshot.
/// Iterate to a fixpoint.
fn destaircase(skel: &[bool], w: usize, h: usize) -> Vec<bool> {
    let mut skel = skel.to_vec();
    loop {
        // candidates on one snapshot
        let mut cand: Vec<usize> = Vec::new();
        for p in 0..skel.len() {
            if !skel[p] {
                continue;
            }
            let nb: Vec<usize> = neighbors8(w, h, p).filter(|&q| skel[q]).collect();
            if nb.len() < 3 {
                continue;
            }
            let mut seen = vec![false; nb.len()];
            let mut stack = vec![0usize];
            seen[0] = true;
            while let Some(a) = stack.pop() {
                for b in 0..nb.len() {
                    if seen[b] {
                        continue;
                    }
                    let (ax, ay) = (nb[a] % w, nb[a] / w);
                    let (bx, by) = (nb[b] % w, nb[b] / w);
                    if ax.abs_diff(bx) <= 1 && ay.abs_diff(by) <= 1 {
                        seen[b] = true;
                        stack.push(b);
                    }
                }
            }
            if seen.iter().all(|&s| s) {
                cand.push(p);
            }
        }
        if cand.is_empty() {
            return skel;
        }
        // greedy independent set: never remove two adjacent pixels together
        let mut blocked: HashSet<usize> = HashSet::new();
        let mut removed = false;
        for &p in &cand {
            if blocked.contains(&p) {
                continue;
            }
            skel[p] = false;
            removed = true;
            for q in neighbors8(w, h, p) {
                blocked.insert(q);
            }
        }
        if !removed {
            return skel;
        }
    }
}

/// Union-find over branch ids.
#[derive(Clone)]
struct Uf {
    parent: Vec<usize>,
}

impl Uf {
    fn new(n: usize) -> Uf {
        Uf { parent: (0..n).collect() }
    }
    fn find(&mut self, mut x: usize) -> usize {
        while self.parent[x] != x {
            self.parent[x] = self.parent[self.parent[x]];
            x = self.parent[x];
        }
        x
    }
    fn union(&mut self, a: usize, b: usize) {
        let (ra, rb) = (self.find(a), self.find(b));
        if ra != rb {
            self.parent[rb.max(ra)] = ra.min(rb);
        }
    }
}

/// Outward direction of a branch at its `node` end, measured over the first
/// few pixels (cells).
fn branch_dir(sk: &Skeleton, br: &Branch, node: usize, upto: usize) -> Pt {
    // window scaled to the local stroke width: staircase-proof tangents
    let seed = if br.b == node && br.a != node { br.pixels.last() } else { br.pixels.first() };
    let local = seed.map(|&p| (sk.dist[p] as usize).saturating_mul(2)).unwrap_or(0);
    let upto = upto.max(local.min(16)).min(br.pixels.len().max(2));
    let rev = br.b == node && br.a != node;
    let n = br.pixels.len().min(upto.max(2));
    let (p0, p1) = if rev {
        let l = br.pixels.len();
        (br.pixels[l - 1], br.pixels[l - n])
    } else {
        (br.pixels[0], br.pixels[n - 1])
    };
    let c = |p: usize| ((p % sk.w) as f64, (p / sk.w) as f64);
    let (a, b) = (c(p0), c(p1));
    (b.0 - a.0, b.1 - a.1)
}

/// The part's maximum turn along its own LONGEST skeleton run. A
/// genuinely bent stroke (an arch) turns along its main run; a stub
/// absorbed from a neighbour leaves its junction at the neighbour's angle
/// but lies off the longest run, so it must not speak for this part.
/// When the part's branch graph is a tree the longest run is its diameter
/// (weighted by branch length); cyclic parts fall back to pair checks at
/// shared nodes. Every choice is deterministic: the start node is the
/// smallest node id, farthest-vertex ties break to the smallest node id,
/// so HashSet iteration order cannot leak into the result.
fn longest_run_turn(sk: &Skeleton, branch_ids: &[usize], dir_window_cells: usize) -> f64 {
    let real: Vec<usize> = branch_ids
        .iter()
        .copied()
        .filter(|&i| {
            let b = &sk.branches[i];
            !(b.a == usize::MAX && b.b == usize::MAX)
        })
        .collect();
    let mut adj: HashMap<usize, Vec<usize>> = HashMap::new();
    let mut vset: HashSet<usize> = HashSet::new();
    for &i in &real {
        let b = &sk.branches[i];
        for &n in &[b.a, b.b] {
            if n != usize::MAX {
                adj.entry(n).or_default().push(i);
                vset.insert(n);
            }
        }
    }
    let mut turn_deg = 0.0f64;
    if !real.is_empty() && real.len() + 1 == vset.len() {
        // tree: weighted diameter by branch length, then sum the turns
        let other = |b: &Branch, n: usize| -> usize {
            if b.a == n {
                b.b
            } else {
                b.a
            }
        };
        // farthest vertex by path length; equal lengths take the smaller id
        let farthest = |start: usize| -> (usize, HashMap<usize, (usize, usize)>) {
            let mut dist: HashMap<usize, f64> = HashMap::new();
            let mut parent: HashMap<usize, (usize, usize)> = HashMap::new();
            let mut stack = vec![start];
            dist.insert(start, 0.0);
            let mut best = start;
            while let Some(n) = stack.pop() {
                let dn = dist[&n];
                let db = dist[&best];
                if dn > db || (dn == db && n < best) {
                    best = n;
                }
                for &bi in adj.get(&n).map(|v| v.as_slice()).unwrap_or(&[]) {
                    let b = &sk.branches[bi];
                    let m = other(b, n);
                    if m == usize::MAX || dist.contains_key(&m) {
                        continue;
                    }
                    dist.insert(m, dn + b.len);
                    parent.insert(m, (n, bi));
                    stack.push(m);
                }
            }
            (best, parent)
        };
        let start_node = vset.iter().copied().min().unwrap();
        let (u, _) = farthest(start_node);
        let (v, parent) = farthest(u);
        // walk v back to u, summing turns at internal nodes
        let mut path_branches: Vec<usize> = Vec::new();
        let mut cur = v;
        while cur != u {
            let (prev, bi) = parent[&cur];
            path_branches.push(bi);
            cur = prev;
        }
        path_branches.reverse();
        let mut node = u;
        let mut prev_branch: Option<usize> = None;
        for &bi in &path_branches {
            let b = &sk.branches[bi];
            if let Some(pi) = prev_branch {
                let pb = &sk.branches[pi];
                if pb.pixels.len() >= 2 * dir_window_cells && b.pixels.len() >= 2 * dir_window_cells {
                    let di = branch_dir(sk, pb, node, dir_window_cells);
                    let dj = branch_dir(sk, b, node, dir_window_cells);
                    turn_deg += 180.0 - dir_angle(di, dj);
                }
            }
            node = other(b, node);
            prev_branch = Some(bi);
        }
    } else {
        // cyclic (or degenerate) part: pair checks at shared nodes,
        // longest branches first
        let mut spine: Vec<usize> = real.clone();
        spine.sort_by(|&a, &b| sk.branches[b].pixels.len().cmp(&sk.branches[a].pixels.len()));
        spine.truncate(4);
        for (x, &i) in spine.iter().enumerate() {
            for &j in &spine[x + 1..] {
                let (bi, bj) = (&sk.branches[i], &sk.branches[j]);
                for &ni in &[bi.a, bi.b] {
                    if ni == usize::MAX {
                        continue;
                    }
                    for &nj in &[bj.a, bj.b] {
                        if ni == nj
                            && bi.pixels.len() >= 2 * dir_window_cells
                            && bj.pixels.len() >= 2 * dir_window_cells
                        {
                            let di = branch_dir(sk, bi, ni, dir_window_cells);
                            let dj = branch_dir(sk, bj, nj, dir_window_cells);
                            turn_deg = turn_deg.max(180.0 - dir_angle(di, dj));
                        }
                    }
                }
            }
        }
    }
    turn_deg
}

/// Angle between two directions in degrees, [0,180].
fn dir_angle(u: Pt, v: Pt) -> f64 {
    let (lu, lv) = (u.0.hypot(u.1), v.0.hypot(v.1));
    if lu < 1e-12 || lv < 1e-12 {
        return 0.0;
    }
    let c = ((u.0 * v.0 + u.1 * v.1) / (lu * lv)).clamp(-1.0, 1.0);
    c.acos().to_degrees()
}

/// Polygon area (signed) of a pixel path closed straight, cells squared.
fn path_area(w: usize, path: &[usize]) -> f64 {
    let mut a = 0.0;
    for k in 0..path.len() {
        let (p, q) = (path[k], path[(k + 1) % path.len()]);
        a += (p % w) as f64 * (q / w) as f64 - (q % w) as f64 * (p / w) as f64;
    }
    a / 2.0
}

fn point_in_path(w: usize, path: &[usize], p: Pt) -> bool {
    let poly: Vec<Pt> = path.iter().map(|&i| ((i % w) as f64 + 0.5, (i / w) as f64 + 0.5)).collect();
    winding_number(p, &poly) != 0
}

/// Nonzero winding number of a closed polygon around a point.
fn winding_number(p: Pt, poly: &[Pt]) -> i32 {
    let mut wn = 0;
    for i in 0..poly.len() {
        let (a, b) = (poly[i], poly[(i + 1) % poly.len()]);
        let cross = (b.0 - a.0) * (p.1 - a.1) - (p.0 - a.0) * (b.1 - a.1);
        if a.1 <= p.1 {
            if b.1 > p.1 && cross > 0.0 {
                wn += 1;
            }
        } else if b.1 <= p.1 && cross < 0.0 {
            wn -= 1;
        }
    }
    wn
}

/// Group branches into parts: prune spurs, then merge rules A and B.
/// Returns (union-find, cycle_merged roots).
fn group_branches(
    sk: &Skeleton,
    mask: &[bool],
    counters: &[Vec<Pt>],
    params: &DecomposeParams,
) -> (Uf, HashSet<usize>) {
    let dbg = std::env::var_os("KNI_DEBUG_GROUP").is_some();
    let mut uf = Uf::new(sk.branches.len());
    // Prune short end-spurs into their straightest neighbour at the junction.
    loop {
        let mut merged = false;
        for (i, br) in sk.branches.iter().enumerate() {
            if br.a == usize::MAX || uf.clone().find(i) != i {
                continue;
            }
            // Spur limit scales with the SPUR's own stroke width (corner
            // spurs reach at most ~1.5x the local half-width). Junction
            // core distance would inflate the limit, so measure mid-branch.
            let spur_limit = {
                let mid = br.pixels[br.pixels.len() / 2];
                let half = sk.dist[mid] as usize;
                params.prune_cells.max(half + 2)
            };
            if br.pixels.len() > spur_limit {
                continue;
            }
            let (end_node, other_node) = if sk.nodes.get(br.a).map_or(false, |n| n.len() == 1 && sk.deg[n[0]] == 1) {
                (br.a, br.b)
            } else if sk.nodes.get(br.b).map_or(false, |n| n.len() == 1 && sk.deg[n[0]] == 1) {
                (br.b, br.a)
            } else {
                continue;
            };
            let _ = end_node;
            if other_node == usize::MAX {
                continue;
            }
            let d0 = branch_dir(sk, br, other_node, params.dir_window_cells);
            let mut best: Option<(f64, usize)> = None;
            for (j, b2) in sk.branches.iter().enumerate() {
                if j == i || uf.clone().find(j) != j {
                    continue;
                }
                if b2.a != other_node && b2.b != other_node {
                    continue;
                }
                let d = branch_dir(sk, b2, other_node, params.dir_window_cells);
                let ang = dir_angle(d0, d);
                if best.map_or(true, |(ba, _)| ang > ba) {
                    best = Some((ang, j));
                }
            }
            if let Some((ang, j)) = best {
                if std::env::var_os("KNI_DEBUG_GROUP").is_some() {
                    eprintln!("spur: union {i} {j} ang {ang:.1}");
                }
                uf.union(i, j);
                merged = true;
            }
        }
        if !merged {
            break;
        }
    }
    // Rule A0: a pass-through node (exactly two incident branch roots) is
    // no junction at all: the two sides are one part.
    for (nid, _) in sk.nodes.iter().enumerate() {
        let mut inc: Vec<usize> = Vec::new();
        for (i, b) in sk.branches.iter().enumerate() {
            if b.a == nid || b.b == nid {
                let r = uf.clone().find(i);
                if !inc.contains(&r) {
                    inc.push(r);
                }
            }
        }
        if inc.len() == 2 {
            if dbg {
                eprintln!("A0 node {nid}: union {} {}", inc[0], inc[1]);
            }
            uf.union(inc[0], inc[1]);
        }
    }
    // Rule A: straight-through pairing at every junction.
    for (nid, _) in sk.nodes.iter().enumerate() {
        let mut incident: Vec<usize> = (0..sk.branches.len())
            .filter(|&i| sk.branches[i].a == nid || sk.branches[i].b == nid)
            .collect();
        loop {
            let mut best: Option<(f64, usize, usize)> = None;
            for x in 0..incident.len() {
                for y in (x + 1)..incident.len() {
                    let (i, j) = (incident[x], incident[y]);
                    if uf.clone().find(i) == uf.clone().find(j) {
                        continue;
                    }
                    let di = branch_dir(sk, &sk.branches[i], nid, params.dir_window_cells);
                    let dj = branch_dir(sk, &sk.branches[j], nid, params.dir_window_cells);
                    let dev = 180.0 - dir_angle(di, dj);
                    if dev <= params.smooth_deg && best.map_or(true, |(bd, _, _)| dev < bd) {
                        best = Some((dev, i, j));
                    }
                }
            }
            match best {
                Some((dev, i, j)) => {
                    if dbg {
                        eprintln!("A node {nid}: union {i} {j} dev {dev:.1}");
                    }
                    uf.union(i, j);
                    incident.retain(|&k| k != j);
                }
                None => break,
            }
        }
    }
    // Rule B: parallel unmerged branches between the same node pair that
    // enclose a hole merge into one bowl.
    let mut by_pair: HashMap<(usize, usize), Vec<usize>> = HashMap::new();
    for (i, br) in sk.branches.iter().enumerate() {
        if br.a == usize::MAX {
            continue;
        }
        if uf.clone().find(i) != i {
            continue; // already merged by rule A
        }
        let key = (br.a.min(br.b), br.a.max(br.b));
        by_pair.entry(key).or_default().push(i);
    }
    let mut cycle_roots: HashSet<usize> = HashSet::new();
    for (_key, group) in by_pair.iter() {
        if group.len() < 2 {
            continue;
        }
        // Outermost pair = largest enclosed area.
        let mut best: Option<(f64, usize, usize)> = None;
        for x in 0..group.len() {
            for y in (x + 1)..group.len() {
                let (i, j) = (group[x], group[y]);
                let mut ring = sk.branches[i].pixels.clone();
                ring.extend(sk.branches[j].pixels.iter().rev());
                let area = path_area(sk.w, &ring).abs();
                if best.map_or(true, |(ba, _, _)| area > ba) {
                    best = Some((area, i, j));
                }
            }
        }
        let Some((_, i, j)) = best else { continue };
        let mut ring = sk.branches[i].pixels.clone();
        ring.extend(sk.branches[j].pixels.iter().rev());
        let encloses_hole = counters
            .iter()
            .flat_map(|c| c.first())
            .any(|&p| point_in_path(sk.w, &ring, p))
            || {
                // No drawn counter: is the ring's centroid outside the ink?
                let (mut sx, mut sy) = (0.0, 0.0);
                for &p in &ring {
                    sx += (p % sk.w) as f64 + 0.5;
                    sy += (p / sk.w) as f64 + 0.5;
                }
                let c = (sx / ring.len() as f64, sy / ring.len() as f64);
                let (cx, cy) = (c.0 as usize, c.1 as usize);
                cx < sk.w && cy < sk.h && !mask[cy * sk.w + cx]
            };
        // Parallel branches between the same junction pair are one stroke
        // band seen twice (medial-axis fork): always merge; the bowl flag
        // follows only when they enclose a hole.
        for &g in group {
            uf.union(g, group[0]);
        }
        if encloses_hole {
            cycle_roots.insert(uf.clone().find(group[0]));
        }
    }
    // A node-less loop is a bowl when it encloses a counter.
    for (i, br) in sk.branches.iter().enumerate() {
        if br.a != usize::MAX || br.pixels.len() < 8 {
            continue;
        }
        let inside = counters.iter().flat_map(|c| c.first()).any(|&p| point_in_path(sk.w, &br.pixels, p));
        if inside {
            cycle_roots.insert(i);
        }
    }
    (uf, cycle_roots)
}

// ---------------- region partition ----------------

/// Multi-source BFS over the ink from skeleton pixels; every ink cell gets
/// the part (uf root) of the nearest skeleton branch.
fn partition(sk: &Skeleton, mask: &[bool], uf: &mut Uf) -> Vec<i32> {
    let mut label = vec![-1i32; mask.len()];
    let mut q: VecDeque<usize> = VecDeque::new();
    for (i, br) in sk.branches.iter().enumerate() {
        let root = uf.find(i) as i32;
        for &p in &br.pixels {
            if label[p] < 0 {
                label[p] = root;
                q.push_back(p);
            }
        }
    }
    while let Some(p) = q.pop_front() {
        for n in neighbors8(sk.w, sk.h, p) {
            if mask[n] && label[n] < 0 {
                label[n] = label[p];
                q.push_back(n);
            }
        }
    }
    label
}

/// Nearest labeled cell to a font-unit point, searching rings up to `r`
/// cells. Coordinates: cell (i,j) spans [b0+i*px, b0+(i+1)*px).
fn label_at(
    label: &[i32],
    w: usize,
    h: usize,
    b: (f64, f64),
    px: f64,
    p: Pt,
    r: isize,
) -> Option<i32> {
    let ci = ((p.0 - b.0) / px).floor() as isize;
    let cj = ((p.1 - b.1) / px).floor() as isize;
    let mut best: Option<(f64, i32)> = None;
    for dj in -r..=r {
        for di in -r..=r {
            let (i, j) = (ci + di, cj + dj);
            if i < 0 || j < 0 || i >= w as isize || j >= h as isize {
                continue;
            }
            let l = label[j as usize * w + i as usize];
            if l < 0 {
                continue;
            }
            let d = (di * di + dj * dj) as f64;
            if best.map_or(true, |(bd, _)| d < bd) {
                best = Some((d, l));
            }
        }
    }
    best.map(|(_, l)| l)
}

// ---------------- boundary assignment ----------------

fn split_line(s: &Seg, t: f64) -> (Seg, Seg) {
    let m = (s.p0.0 + t * (s.p1.0 - s.p0.0), s.p0.1 + t * (s.p1.1 - s.p0.1));
    let mut a = *s;
    let mut bseg = *s;
    a.p1 = m;
    bseg.p0 = m;
    (a, bseg)
}

/// de Casteljau split of a cubic at t (exact).
fn split_curve(s: &Seg, t: f64) -> (Seg, Seg) {
    let (p0, c1, c2, p1) = (s.p0, s.c1.unwrap(), s.c2.unwrap(), s.p1);
    let l = |a: Pt, b: Pt| (a.0 + t * (b.0 - a.0), a.1 + t * (b.1 - a.1));
    let (q0, q1, q2) = (l(p0, c1), l(c1, c2), l(c2, p1));
    let (r0, r1) = (l(q0, q1), l(q1, q2));
    let m = l(r0, r1);
    (
        Seg { kind: SegKind::Curve, p0, c1: Some(q0), c2: Some(r0), p1: m },
        Seg { kind: SegKind::Curve, p0: m, c1: Some(r1), c2: Some(q2), p1 },
    )
}

fn split_seg(s: &Seg, t: f64) -> (Seg, Seg) {
    match s.kind {
        SegKind::Line => split_line(s, t),
        SegKind::Curve => split_curve(s, t),
    }
}

fn seg_eval(s: &Seg, t: f64) -> Pt {
    match s.kind {
        SegKind::Line => (s.p0.0 + t * (s.p1.0 - s.p0.0), s.p0.1 + t * (s.p1.1 - s.p0.1)),
        SegKind::Curve => {
            let (p0, c1, c2, p1) = (s.p0, s.c1.unwrap(), s.c2.unwrap(), s.p1);
            let mt = 1.0 - t;
            (
                mt * mt * mt * p0.0 + 3.0 * mt * mt * t * c1.0 + 3.0 * mt * t * t * c2.0 + t * t * t * p1.0,
                mt * mt * mt * p0.1 + 3.0 * mt * mt * t * c1.1 + 3.0 * mt * t * t * c2.1 + t * t * t * p1.1,
            )
        }
    }
}

fn seg_len_approx(s: &Seg) -> f64 {
    match s.kind {
        SegKind::Line => (s.p1.0 - s.p0.0).hypot(s.p1.1 - s.p0.1),
        SegKind::Curve => {
            let mut l = 0.0;
            let mut prev = s.p0;
            for k in 1..=16 {
                let p = seg_eval(s, k as f64 / 16.0);
                l += (p.0 - prev.0).hypot(p.1 - prev.1);
                prev = p;
            }
            l
        }
    }
}

/// One source-contour piece owned by a part.
#[derive(Debug, Clone)]
struct Piece {
    contour: usize,
    seg_index: usize,
    seg: Seg,
    root: i32,
}

/// Assign source boundary segments to parts, splitting segments at region
/// transitions. Outer contours only; counters are owned wholesale later.

/// Does this boundary segment face a hole region OWNED by `root`? Such
/// segments are emitted separately as the region's counter ring (verbatim
/// matched source counter or traced raster ring); keeping them in the
/// outer ring would draw that boundary twice and break the winding.
/// Segments facing UNOWNED regions (wedges shared by several parts) are
/// union silhouette and must stay: they appear nowhere else.
fn piece_faces_owned_region(
    seg: &Seg,
    root: i32,
    mask: &[bool],
    region_grid: &[i32],
    hole_surround: &[HashSet<i32>],
    w: usize,
    h: usize,
    b: (f64, f64),
    px: f64,
) -> bool {
    let side = |p: Pt, n: Pt, sign: f64| -> i32 {
        let x = p.0 + sign * n.0 * px;
        let y = p.1 + sign * n.1 * px;
        let i = ((x - b.0) / px).floor() as isize;
        let j = ((y - b.1) / px).floor() as isize;
        if i < 0 || j < 0 || i >= w as isize || j >= h as isize {
            return -2; // outside the raster is exterior
        }
        let c = j as usize * w + i as usize;
        if mask[c] {
            -1
        } else {
            region_grid[c] // >= 1 region, -2 exterior
        }
    };
    for t in [0.5f64, 0.25, 0.75] {
        let p = seg_eval(seg, t);
        let q0 = seg_eval(seg, (t - 0.01).max(0.0));
        let q1 = seg_eval(seg, (t + 0.01).min(1.0));
        let (tx, ty) = (q1.0 - q0.0, q1.1 - q0.1);
        let tl = (tx * tx + ty * ty).sqrt();
        if tl < 1e-12 {
            continue;
        }
        let n = (-ty / tl, tx / tl);
        let a = side(p, n, 1.0);
        let c = side(p, n, -1.0);
        let (ink_a, ink_c) = (a == -1, c == -1);
        if ink_a == ink_c {
            continue; // both ink or both background: not hole-facing evidence
        }
        let other = if ink_a { c } else { a };
        if other >= 1 {
            let set = &hole_surround[(other - 1) as usize];
            return set.len() == 1 && set.contains(&root);
        }
        return false; // exterior-facing
    }
    false
}

fn assign_boundary(
    contours: &[StrokeContour],
    outer: &[usize],
    label: &[i32],
    w: usize,
    h: usize,
    b: (f64, f64),
    px: f64,
) -> Vec<Piece> {
    let mut pieces = Vec::new();
    for &ci in outer {
        let segs = contours[ci].segments();
        for (si, s) in segs.iter().enumerate() {
            let len = seg_len_approx(s);
            let n = ((len / (px * 0.5)).ceil() as usize).clamp(8, MAX_SEG_SAMPLES);
            let mut ids: Vec<i32> = Vec::with_capacity(n + 1);
            for k in 0..=n {
                let p = seg_eval(s, k as f64 / n as f64);
                let id = label_at(label, w, h, b, px, p, 4)
                    .or_else(|| ids.last().copied())
                    .unwrap_or(-1);
                ids.push(id);
            }
            // Runs of equal ids -> transition parameters by bisection.
            let mut cuts: Vec<(usize, i32)> = vec![(0, ids[0])];
            for k in 1..=n {
                if ids[k] != cuts.last().unwrap().1 {
                    let (mut lo, mut hi) = ((k - 1) as f64 / n as f64, k as f64 / n as f64);
                    let from = cuts.last().unwrap().1;
                    for _ in 0..24 {
                        let mid = (lo + hi) / 2.0;
                        let p = seg_eval(s, mid);
                        let id = label_at(label, w, h, b, px, p, 4).unwrap_or(from);
                        if id == from {
                            lo = mid;
                        } else {
                            hi = mid;
                        }
                    }
                    cuts.push((usize::MAX, ids[k])); // marker; t stored below
                    let last = cuts.len() - 1;
                    cuts[last].0 = (hi * 1e9) as usize; // encode t*1e9
                    let _ = lo;
                }
            }
            // Emit pieces between consecutive cuts.
            for wnd in 0..cuts.len() {
                let (t0, root) = if wnd == 0 { (0.0, cuts[0].1) } else { (cuts[wnd].0 as f64 / 1e9, cuts[wnd].1) };
                let t1 = if wnd + 1 < cuts.len() { cuts[wnd + 1].0 as f64 / 1e9 } else { 1.0 };
                let piece_seg = if t0 <= 1e-12 && t1 >= 1.0 - 1e-12 {
                    *s
                } else {
                    let (_, tail) = split_seg(s, t0);
                    let head_t = if t1 < 1.0 - 1e-12 { (t1 - t0) / (1.0 - t0) } else { 1.0 };
                    let (head, _) = split_seg(&tail, head_t.min(1.0));
                    head
                };
                pieces.push(Piece { contour: ci, seg_index: si, seg: piece_seg, root });
            }
        }
    }
    pieces
}

// ---------------- assembly + features ----------------

fn seg_to_op(s: &Seg) -> Op {
    match s.kind {
        SegKind::Line => Op::Line(s.p1),
        SegKind::Curve => Op::Curve(s.c1.unwrap(), s.c2.unwrap(), s.p1),
    }
}

/// Enclosed background regions of the ink mask: 4-connected background
/// cells not reachable from the image border (the ink is 8-connected, so
/// the background is 4-connected for a consistent planar split).
fn background_regions(mask: &[bool], w: usize, h: usize) -> (Vec<Vec<usize>>, Vec<i32>) {
    const OUTSIDE: i32 = -2;
    let mut region = vec![0i32; w * h]; // 0 = undecided, -1 = ink, OUTSIDE = exterior
    for (c, r) in region.iter_mut().enumerate() {
        if mask[c] {
            *r = -1;
        }
    }
    let mut stack: Vec<usize> = Vec::new();
    for i in 0..w {
        stack.push(i);
        stack.push((h - 1) * w + i);
    }
    for j in 0..h {
        stack.push(j * w);
        stack.push(j * w + w - 1);
    }
    while let Some(c) = stack.pop() {
        if region[c] != 0 {
            continue;
        }
        region[c] = OUTSIDE;
        let (i, j) = (c % w, c / w);
        if i > 0 {
            stack.push(c - 1);
        }
        if i + 1 < w {
            stack.push(c + 1);
        }
        if j > 0 {
            stack.push(c - w);
        }
        if j + 1 < h {
            stack.push(c + w);
        }
    }
    let mut regions: Vec<Vec<usize>> = Vec::new();
    for c in 0..w * h {
        if region[c] != 0 {
            continue;
        }
        // ids start at 1: 0 is the undecided sentinel
        let id = regions.len() as i32 + 1;
        let mut cells = Vec::new();
        region[c] = id;
        stack.push(c);
        while let Some(c2) = stack.pop() {
            cells.push(c2);
            let (i, j) = (c2 % w, c2 / w);
            if i > 0 && region[c2 - 1] == 0 {
                region[c2 - 1] = id;
                stack.push(c2 - 1);
            }
            if i + 1 < w && region[c2 + 1] == 0 {
                region[c2 + 1] = id;
                stack.push(c2 + 1);
            }
            if j > 0 && region[c2 - w] == 0 {
                region[c2 - w] = id;
                stack.push(c2 - w);
            }
            if j + 1 < h && region[c2 + w] == 0 {
                region[c2 + w] = id;
                stack.push(c2 + w);
            }
        }
        regions.push(cells);
    }
    (regions, region)
}

/// Boundary of a cell region as one closed polygon in CELL coordinates.
/// Directed cracks keep the region on the left (counterclockwise in
/// y-up); at pinch vertices the sharpest left turn keeps each loop
/// simple; loops sharing a vertex stitch into one walk; island loops
/// (negative area: ink inside the region, drawn by another part's ring)
/// are dropped; collinear corners merge exactly (integer cell corners).
/// Deterministic: walks start at the smallest vertex, ties break to the
/// smallest next vertex.
fn trace_region_ring(cells: &[usize], w: usize, h: usize) -> Vec<Pt> {
    let set: HashSet<usize> = cells.iter().copied().collect();
    let has = |i: i64, j: i64| {
        i >= 0 && j >= 0 && (i as usize) < w && (j as usize) < h && set.contains(&(j as usize * w + i as usize))
    };
    let mut edges: HashMap<(i64, i64), Vec<(i64, i64)>> = HashMap::new();
    for &c in cells {
        let (i, j) = ((c % w) as i64, (c / w) as i64);
        if !has(i, j - 1) {
            edges.entry((i, j)).or_default().push((i + 1, j));
        }
        if !has(i + 1, j) {
            edges.entry((i + 1, j)).or_default().push((i + 1, j + 1));
        }
        if !has(i, j + 1) {
            edges.entry((i + 1, j + 1)).or_default().push((i, j + 1));
        }
        if !has(i - 1, j) {
            edges.entry((i, j + 1)).or_default().push((i, j));
        }
    }
    let area2 = |poly: &[(i64, i64)]| -> i64 {
        let mut a = 0i64;
        for k in 0..poly.len().saturating_sub(1) {
            a += poly[k].0 * poly[k + 1].1 - poly[k + 1].0 * poly[k].1;
        }
        a
    };
    let mut loops: Vec<Vec<(i64, i64)>> = Vec::new();
    while !edges.is_empty() {
        let start = *edges.keys().min().unwrap();
        let mut pts = vec![start];
        let mut cur = start;
        let mut prev: Option<(i64, i64)> = None;
        loop {
            let next = {
                let outs = edges.get_mut(&cur).unwrap();
                let pick = match prev {
                    None => *outs.iter().min().unwrap(),
                    Some(d) => *outs
                        .iter()
                        .max_by(|&&a, &&b| {
                            let (ca, cb2) = (d.0 * a.1 - d.1 * a.0, d.0 * b.1 - d.1 * b.0);
                            let (da, db) = (d.0 * a.0 + d.1 * a.1, d.0 * b.0 + d.1 * b.1);
                            (ca, da, a).cmp(&(cb2, db, b))
                        })
                        .unwrap(),
                };
                outs.retain(|&o| o != pick);
                pick
            };
            // note: candidate deltas are absolute vertices; recompute dir below
            let d = (next.0 - cur.0, next.1 - cur.1);
            pts.push(next);
            prev = Some(d);
            cur = next;
            if cur == start {
                break;
            }
        }
        edges.retain(|_, v| !v.is_empty());
        if area2(&pts) > 0 {
            loops.push(pts);
        }
    }
    // Stitch loops sharing a vertex into one walk.
    loop {
        let mut merged = false;
        'outer: for a in 0..loops.len() {
            for b in (a + 1)..loops.len() {
                for (ia, &va) in loops[a].iter().enumerate() {
                    if let Some(ib) = loops[b].iter().position(|&vb| vb == va) {
                        // rotate b to start at the shared vertex
                        let mut rb: Vec<(i64, i64)> = loops[b][ib..].to_vec();
                        rb.extend_from_slice(&loops[b][1..=ib]);
                        let mut m = loops[a][..=ia].to_vec();
                        m.extend_from_slice(&rb);
                        m.extend_from_slice(&loops[a][ia + 1..]);
                        loops[a] = m;
                        loops.remove(b);
                        merged = true;
                        break 'outer;
                    }
                }
            }
        }
        if !merged {
            break;
        }
    }
    // Largest remaining loop is the region boundary walk (a 4-connected
    // region has one outer walk; pinches were stitched above).
    loops.sort_by_key(|l| std::cmp::Reverse(area2(l)));
    let ring = loops.into_iter().next().unwrap_or_default();
    // Collinear merge (exact on integer corners), closing point dropped.
    let mut pts: Vec<(i64, i64)> = ring;
    if pts.len() > 1 && pts.first() == pts.last() {
        pts.pop();
    }
    let mut out: Vec<(i64, i64)> = Vec::with_capacity(pts.len());
    for k in 0..pts.len() {
        let p = pts[(k + pts.len() - 1) % pts.len()];
        let c = pts[k];
        let n = pts[(k + 1) % pts.len()];
        if (c.0 == p.0 && c.0 == n.0) || (c.1 == p.1 && c.1 == n.1) {
            continue;
        }
        out.push(c);
    }
    out.iter().map(|&(x, y)| (x as f64, y as f64)).collect()
}

/// Reverse a ring's traversal so its winding flips. Geometry is
/// preserved segment for segment (curve control points swap).
fn reverse_ops(ops: &[Op]) -> Vec<Op> {
    let mut segs: Vec<(Op, Pt)> = Vec::new(); // (segment op, its start)
    let mut cur: Option<Pt> = None;
    let mut closed = false;
    for op in ops {
        match *op {
            Op::Move(p) => cur = Some(p),
            Op::Line(p) => {
                if let Some(st) = cur {
                    segs.push((Op::Line(p), st));
                    cur = Some(p);
                }
            }
            Op::Curve(c1, c2, p) => {
                if let Some(st) = cur {
                    segs.push((Op::Curve(c1, c2, p), st));
                    cur = Some(p);
                }
            }
            Op::Close => closed = true,
        }
    }
    let Some(last) = cur else { return ops.to_vec() };
    let mut out = vec![Op::Move(last)];
    for (op, seg_start) in segs.into_iter().rev() {
        match op {
            Op::Line(_) => out.push(Op::Line(seg_start)),
            Op::Curve(c1, c2, _) => out.push(Op::Curve(c2, c1, seg_start)),
            _ => {}
        }
    }
    if closed {
        out.push(Op::Close);
    }
    out
}

/// Per-part PCA moments accumulator over owned cells.
#[derive(Default)]
struct Moments {
    n: f64,
    sx: f64,
    sy: f64,
    sxx: f64,
    syy: f64,
    sxy: f64,
}

impl Moments {
    fn add(&mut self, x: f64, y: f64) {
        self.n += 1.0;
        self.sx += x;
        self.sy += y;
        self.sxx += x * x;
        self.syy += y * y;
        self.sxy += x * y;
    }
    /// Principal axis angle (deg from +x) and degeneracy flag.
    fn axis(&self) -> Option<(f64, bool)> {
        if self.n < 2.0 {
            return None;
        }
        let (mx, my) = (self.sx / self.n, self.sy / self.n);
        let cxx = self.sxx / self.n - mx * mx;
        let cyy = self.syy / self.n - my * my;
        let cxy = self.sxy / self.n - mx * my;
        let tr = cxx + cyy;
        let det = cxx * cyy - cxy * cxy;
        let disc = (tr * tr / 4.0 - det).max(0.0).sqrt();
        let (l1, l2) = (tr / 2.0 + disc, tr / 2.0 - disc);
        let angle = 0.5 * (2.0 * cxy).atan2(cxx - cyy).to_degrees();
        let angle = angle.rem_euclid(180.0);
        let degenerate = tr <= 1e-12 || (l1 - l2) / (l1 + l2).max(1e-12) < AXIS_DEGENERATE;
        Some((angle, degenerate))
    }
}
/// Fold the angle between two undirected axes to [0,90].
fn axis_rel(a: f64, b: f64) -> f64 {
    let d = (a - b).rem_euclid(180.0);
    d.min(180.0 - d)
}

fn signed_area(ops: &[Op]) -> f64 {
    let c = StrokeContour { stroke: String::new(), ops: ops.to_vec() };
    let segs = c.segments();
    let mut a = 0.0;
    for s in &segs {
        for (p, q) in [(s.p0, s.p1)] {
            a += p.0 * q.1 - q.0 * p.1;
        }
        if let (Some(c1), Some(c2)) = (s.c1, s.c2) {
            // cubic contribution to the area integral
            let (p0, p1) = (s.p0, s.p1);
            a += (3.0 / 10.0) * (p0.0 * c1.1 - c1.0 * p0.1)
                + (3.0 / 20.0) * (c1.0 * c2.1 - c2.0 * c1.1 + p0.0 * c2.1 - c2.0 * p0.1 + c1.0 * p1.1 - p1.0 * c1.1)
                + (3.0 / 10.0) * (c2.0 * p1.1 - p1.0 * c2.1);
        }
    }
    a / 2.0
}

/// Decompose a flat export outline into structural parts.
///
/// Input: a MasterGlyph whose contours are the flat outline (one closed
/// subpath each, export style: counters are separate opposite-winding
/// contours). The glyph name is carried through but never read.
pub fn decompose(g: &MasterGlyph) -> Result<Decomposition, DecomposeError> {
    decompose_with(g, &DecomposeParams::default())
}

pub fn decompose_with(g: &MasterGlyph, params: &DecomposeParams) -> Result<Decomposition, DecomposeError> {
    let contours = &g.contours;
    if contours.is_empty() {
        return Err(DecomposeError::EmptyOutline);
    }
    let polys: Vec<Vec<Pt>> = contours.iter().map(stroke_polygon).collect();
    // Degenerate / open contour policy (chief 2026-10-18: stated with a log
    // line, never silent). A contour under 3 polygon points is admitted -
    // contour indices stay stable for hole/counter provenance - but
    // contributes no ink to the mask or the part rings; a contour with no
    // trailing Close is filled as closed by a straight chord (the model's
    // implicit closing segment). Both cases are logged per contour.
    for (i, (c, p)) in contours.iter().zip(&polys).enumerate() {
        if p.len() < 3 {
            eprintln!("decompose: glyph {}: contour {i} degenerate ({} polygon points); admitted, contributes no ink", g.name, p.len());
        }
        if !matches!(c.ops.last(), Some(Op::Close)) {
            eprintln!("decompose: glyph {}: contour {i} open; filled as closed by straight chord", g.name);
        }
    }
    if polys.iter().all(|p| p.len() < 3) {
        return Err(DecomposeError::EmptyOutline);
    }
    // Dominant winding sign (largest contour): contours wound against it
    // are REVERSED for boundary assembly so ring pieces chain in one
    // direction. The ink mask keeps the SOURCE's original windings:
    // nonzero sum-of-windings is the glyph's own fill semantics.
    let areas: Vec<f64> = contours.iter().map(|c| signed_area(&c.ops)).collect();
    let big = areas
        .iter()
        .enumerate()
        .max_by(|a, b| a.1.abs().partial_cmp(&b.1.abs()).unwrap_or(std::cmp::Ordering::Equal))
        .map(|(i, _)| i)
        .ok_or(DecomposeError::EmptyOutline)?;
    let outer_sign = areas[big].signum();
    let orig_contours = contours;
    let mut norm = contours.to_vec();
    for (i, c) in norm.iter_mut().enumerate() {
        if areas[i] * outer_sign < 0.0 {
            c.ops = reverse_ops(&c.ops);
        }
    }
    let contours = &norm[..];
    let outer: Vec<usize> = (0..contours.len()).collect();

    // Raster.
    let bnds = bounds_of(&[&polys], 2.0);
    let span = (bnds.2 - bnds.0).max(bnds.3 - bnds.1);
    if span <= 0.0 {
        return Err(DecomposeError::EmptyOutline);
    }
    let px = span / params.raster_cells as f64;
    let pix = (((bnds.2 - bnds.0) / px).ceil() as u128) * (((bnds.3 - bnds.1) / px).ceil() as u128);
    if pix > MAX_RASTER_PIXELS as u128 {
        return Err(DecomposeError::PixelBudget { pixels: pix, limit: MAX_RASTER_PIXELS });
    }
    let (w, h, mask) = rasterize(&polys, true, bnds, px, (0.5, 0.5));
    if mask.iter().all(|&m| !m) {
        return Err(DecomposeError::EmptyOutline);
    }

    // Holes are the enclosed BACKGROUND REGIONS of the union raster, not
    // source contour copies: a source counter partially covered by other
    // strokes does not bound the actual background. Each region's ring is
    // the exact cell-boundary polygon; where a source contour bounds the
    // region EXACTLY (same background cells), the smooth source ring is
    // emitted instead. Probes enter grouping in skeleton cell coordinates
    // (grouping must not change under translation or scale of the source).
    let (regions, region_grid) = background_regions(&mask, w, h);
    let hole_cells: Vec<Vec<Pt>> = regions.iter().map(|r| trace_region_ring(r, w, h)).collect();
    let hole_polys: Vec<Vec<Pt>> = hole_cells
        .iter()
        .map(|r| r.iter().map(|&(x, y)| (bnds.0 + x * px, bnds.1 + y * px)).collect())
        .collect();
    // One-to-one match: region cells are exactly the background cells
    // inside the source counter's ring.
    let src_counters: Vec<usize> = (0..orig_contours.len()).filter(|&i| areas[i] * outer_sign < 0.0).collect();
    let region_set: Vec<HashSet<usize>> = regions.iter().map(|r| r.iter().copied().collect()).collect();
    let mut hole_match: Vec<Option<usize>> = vec![None; regions.len()];
    for (ri, cells) in regions.iter().enumerate() {
        for &ci in &src_counters {
            let poly = &polys[ci];
            let cb = bounds_of(&[std::slice::from_ref(poly)], 0.0);
            let inside = |idx: usize| {
                let p = (
                    bnds.0 + (idx % w) as f64 * px + 0.5 * px,
                    bnds.1 + (idx / w) as f64 * px + 0.5 * px,
                );
                crate::raster::inside_merged(p, std::slice::from_ref(poly))
            };
            if !cells.iter().all(|&c| inside(c)) {
                continue;
            }
            let i0 = ((cb.0 - bnds.0) / px).floor().max(0.0) as usize;
            let i1 = ((cb.2 - bnds.0) / px).ceil().min(w as f64) as usize;
            let j0 = ((cb.1 - bnds.1) / px).floor().max(0.0) as usize;
            let j1 = ((cb.3 - bnds.1) / px).ceil().min(h as f64) as usize;
            let mut exact = true;
            'scan: for j in j0..j1 {
                for i in i0..i1 {
                    let idx = j * w + i;
                    if !mask[idx] && inside(idx) && !region_set[ri].contains(&idx) {
                        exact = false;
                        break 'scan;
                    }
                }
            }
            if exact {
                hole_match[ri] = Some(ci);
                break;
            }
        }
    }

    // Skeleton, grouping, partition.
    let sk = build_skeleton(&mask, w, h);
    let (mut uf, cycle_roots) = group_branches(&sk, &mask, &hole_cells, params);
    let mut label = partition(&sk, &mask, &mut uf);

    // Effective part root of a skeleton branch: partition roots absorbed
    // by orphan/fragment merges keep their branches through this map.
    let mut eff: HashMap<i32, i32> = HashMap::new();

    // Boundary assignment (outer contours).
    let mut pieces = assign_boundary(contours, &outer, &label, w, h, (bnds.0, bnds.1), px);

    // Hole ownership: the set of partition roots whose ink touches the
    // region (8-neighborhood of its cells). Labels are pre-merge here; the
    // orphan/fragment remaps below rewrite each set, and a region becomes a
    // part's counter only when the REMAPPED set is exactly that part's
    // root: the exterior ring of one connected ink mass encloses its
    // holes, so the counter ring carves background the outer ring would
    // otherwise fill. A region shared by several final parts (a wedge
    // between strokes) stays unowned: it lies outside every part's
    // exterior ring, so the ring union already leaves it background, and
    // emitting a counter ring for it would ADD ink under nonzero fill.
    let mut hole_surround: Vec<HashSet<i32>> = Vec::with_capacity(regions.len());
    for cells in regions.iter() {
        let mut surround: HashSet<i32> = HashSet::new();
        for &c in cells {
            let (i, j) = (c % w, c / w);
            for dj in -1isize..=1 {
                for di in -1isize..=1 {
                    let (i2, j2) = (i as isize + di, j as isize + dj);
                    if i2 < 0 || j2 < 0 || i2 >= w as isize || j2 >= h as isize {
                        continue;
                    }
                    let l = label[j2 as usize * w + i2 as usize];
                    if l >= 0 {
                        surround.insert(l);
                    }
                }
            }
        }
        hole_surround.push(surround);
    }

    // Roots present in the partition.
    let mut roots: Vec<i32> = label.iter().copied().filter(|&l| l >= 0).collect();
    roots.sort_unstable();
    roots.dedup();
    // Extra roots that own no ink but own pieces (boundary bleed).
    for p in &pieces {
        if p.root >= 0 && !roots.contains(&p.root) {
            roots.push(p.root);
        }
    }
    roots.sort_unstable();

    // Per-part moments + features.
    let mut moments: HashMap<i32, Moments> = HashMap::new();
    let mut all = Moments::default();
    for j in 0..h {
        for i in 0..w {
            let idx = j * w + i;
            if !mask[idx] {
                continue;
            }
            let (x, y) = (bnds.0 + (i as f64 + 0.5) * px, bnds.1 + (j as f64 + 0.5) * px);
            all.add(x, y);
            if label[idx] >= 0 {
                moments.entry(label[idx]).or_default().add(x, y);
            }
        }
    }
    // Boundary-only roots (own pieces, no raster ink): synthesize moments
    // from piece sample points so centroid, axis_pos and orphan checks
    // never see a missing entry.
    for &root in &roots {
        if moments.contains_key(&root) {
            continue;
        }
        let mut m = Moments::default();
        for p in pieces.iter().filter(|p| p.root == root) {
            for k in 0..=4 {
                let pt = seg_eval(&p.seg, k as f64 / 4.0);
                m.add(pt.0, pt.1);
            }
        }
        if m.n > 0.0 {
            moments.insert(root, m);
        }
    }
    let glyph_axis = all.axis().and_then(|(a, degen)| if degen { None } else { Some(a) });

    // Glyph bbox along the axis for axis_pos normalization.
    let gbb = (bnds.0, bnds.1, bnds.2, bnds.3);

    // Orphan absorption (owner directive: orphan boundary pieces join the
    // nearest part). A root owning a sliver of ink (skeleton spur fragment)
    // folds into the nearest substantial part before assembly.
    {
        let total = all.n;
        let junk: Vec<i32> = roots
            .iter()
            .copied()
            .filter(|&r| {
                !cycle_roots.contains(&(r as usize))
                    && moments.get(&r).map(|m| m.n).unwrap_or(0.0) < params.orphan_ink_frac * total
            })
            .collect();
        if !junk.is_empty() && junk.len() < roots.len() {
            // A sliver folds only into a part it TOUCHES: folding a
            // detached blob into a distant part would make that part own
            // two disjoint ink regions, which the one-ring-per-part
            // contract cannot emit. Detached small roots stay parts.
            // 8-connected to match skeleton connectivity: diagonal contact
            // is contact.
            let mut adjacent: HashSet<(i32, i32)> = HashSet::new();
            for j in 0..h {
                for i in 0..w {
                    let a = label[j * w + i];
                    if a < 0 {
                        continue;
                    }
                    for (di, dj) in [(1isize, 0isize), (0, 1), (1, 1), (-1, 1)] {
                        let (i2, j2) = (i as isize + di, j as isize + dj);
                        if i2 < 0 || j2 < 0 || i2 >= w as isize || j2 >= h as isize {
                            continue;
                        }
                        let b = label[j2 as usize * w + i2 as usize];
                        if b >= 0 && b != a {
                            adjacent.insert((a.min(b), a.max(b)));
                        }
                    }
                }
            }
            let centroid = |r: i32| -> (f64, f64) {
                let m = moments.get(&r).unwrap();
                (m.sx / m.n.max(1.0), m.sy / m.n.max(1.0))
            };
            // Cascade: a sliver folds into the nearest substantial root it
            // TOUCHES, and an absorbed sliver extends its target, so chains
            // of slivers (a shattered staircase bar) fold link by link.
            // Sorted iteration + nearest-target ties to the smaller root id
            // keep the result order-independent. A sliver touching nothing
            // substantial, even through other slivers, is a detached blob
            // and stays its own part.
            let mut remap: HashMap<i32, i32> = HashMap::new();
            let mut remaining: Vec<i32> = junk.clone();
            remaining.sort_unstable();
            loop {
                let mut progressed = false;
                let mut next: Vec<i32> = Vec::new();
                for &jr in &remaining {
                    let (jx, jy) = centroid(jr);
                    let target = roots
                        .iter()
                        .copied()
                        .filter(|r| !junk.contains(r) || remap.contains_key(r))
                        .map(|r| remap.get(&r).copied().unwrap_or(r))
                        .filter(|&r| adjacent.contains(&(jr.min(r), jr.max(r))) || {
                            // adjacency recorded against a sliver's ORIGINAL
                            // root id: resolve both sides before the check
                            false
                        })
                        .min_by(|&a, &b| {
                            let (ax, ay) = centroid(a);
                            let (bx, by) = centroid(b);
                            let da = (ax - jx).powi(2) + (ay - jy).powi(2);
                            let db = (bx - jx).powi(2) + (by - jy).powi(2);
                            da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
                        });
                    // The adjacency set records ORIGINAL root ids: a sliver
                    // touching an already-absorbed sliver touches its
                    // target. Check original-id adjacency, then resolve.
                    let target = target.or_else(|| {
                        roots
                            .iter()
                            .copied()
                            .filter(|&r| adjacent.contains(&(jr.min(r), jr.max(r))))
                            .filter_map(|r| remap.get(&r).copied().or(if junk.contains(&r) { None } else { Some(r) }))
                            .min_by(|&a, &b| {
                                let (ax, ay) = centroid(a);
                                let (bx, by) = centroid(b);
                                let da = (ax - jx).powi(2) + (ay - jy).powi(2);
                                let db = (bx - jx).powi(2) + (by - jy).powi(2);
                                da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
                            })
                    });
                    match target {
                        Some(t) => {
                            remap.insert(jr, t);
                            progressed = true;
                        }
                        None => next.push(jr),
                    }
                }
                remaining = next;
                if !progressed || remaining.is_empty() {
                    break;
                }
            }
            if !remap.is_empty() {
                for l in label.iter_mut() {
                    if let Some(&t) = remap.get(l) {
                        *l = t;
                    }
                }
                for p in pieces.iter_mut() {
                    if let Some(&t) = remap.get(&p.root) {
                        p.root = t;
                    }
                }
                for set in hole_surround.iter_mut() {
                    let mapped: HashSet<i32> =
                        set.iter().map(|&l| remap.get(&l).copied().unwrap_or(l)).collect();
                    *set = mapped;
                }
                roots.retain(|r| !remap.contains_key(r));
                // deterministic float accumulation: apply in sorted order
                let mut applied: Vec<i32> = remap.keys().copied().collect();
                applied.sort_unstable();
                for jr in applied {
                    let t = remap[&jr];
                    eff.insert(jr, t);
                    if let Some(m) = moments.remove(&jr) {
                        let e = moments.entry(t).or_default();
                        e.n += m.n;
                        e.sx += m.sx;
                        e.sy += m.sy;
                        e.sxx += m.sxx;
                        e.syy += m.syy;
                        e.sxy += m.sxy;
                    }
                }
            }
        }
    }

    // Attached-fragment merge: a root in the small-ink band attached to a
    // larger region is a fragment of a stroke the skeleton split (arch
    // cap, bar tip fork, serif chunk); it joins the neighbouring region it
    // shares the longest boundary with. Detached marks share no boundary
    // and stay.
    {
        let total = all.n;
        let mut remap: HashMap<i32, i32> = HashMap::new();
        for &r in &roots {
            if cycle_roots.contains(&(r as usize)) {
                continue;
            }
            let frac = moments.get(&r).map(|m| m.n).unwrap_or(0.0) / total.max(1.0);
            if frac >= params.fragment_ink_frac {
                continue;
            }
            // shared-boundary cell-pair tally per neighbour region
            let mut contact: HashMap<i32, usize> = HashMap::new();
            for j in 0..h {
                for i in 0..w {
                    let idx = j * w + i;
                    if label[idx] != r {
                        continue;
                    }
                    for q in neighbors8(w, h, idx) {
                        let l = label[q];
                        if l >= 0 && l != r {
                            *contact.entry(l).or_default() += 1;
                        }
                    }
                }
            }
            if let Some((&t, _)) = contact
                .iter()
                .max_by(|(r1, n1), (r2, n2)| n1.cmp(n2).then_with(|| r2.cmp(r1)))
            {
                remap.insert(r, t);
            }
        }
        // Resolve targets to surviving roots: a small root may pick
        // another small root; follow the chain to a survivor and drop
        // cycles. Deterministic: keys processed in sorted order.
        let remap = resolve_remap(&remap);
        if !remap.is_empty() {
            for l in label.iter_mut() {
                if let Some(&t) = remap.get(l) {
                    *l = t;
                }
            }
            for p in pieces.iter_mut() {
                if let Some(&t) = remap.get(&p.root) {
                    p.root = t;
                }
            }
            for set in hole_surround.iter_mut() {
                let mapped: HashSet<i32> =
                    set.iter().map(|&l| remap.get(&l).copied().unwrap_or(l)).collect();
                *set = mapped;
            }
            roots.retain(|r| !remap.contains_key(r));
            let mut applied: Vec<i32> = remap.keys().copied().collect();
            applied.sort_unstable();
            for &jr in &applied {
                eff.insert(jr, remap[&jr]);
            }
            for jr in applied {
                let t = remap[&jr];
                if let Some(m) = moments.remove(&jr) {
                    let e = moments.entry(t).or_default();
                    e.n += m.n;
                    e.sx += m.sx;
                    e.sy += m.sy;
                    e.sxx += m.sxx;
                    e.syy += m.syy;
                    e.sxy += m.sxy;
                }
            }
        }
    }

    let mut parts: Vec<Part> = Vec::new();
    let mut part_roots: Vec<i32> = Vec::new();
    for &root in &roots {
        let branch_ids: Vec<usize> = (0..sk.branches.len()).filter(|&i| eff_root(&mut uf, &eff, i) == root).collect();
        // Skeleton length and mean width over this part's branches.
        let mut len_cells = 0.0;
        let mut widths: Vec<f64> = Vec::new();
        for &i in &branch_ids {
            len_cells += sk.branches[i].len;
            for &p in &sk.branches[i].pixels {
                widths.push(sk.dist[p] as f64);
            }
        }
        widths.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
        let length = len_cells * px;
        let width = if widths.is_empty() { 0.0 } else { 2.0 * widths[widths.len() / 2] * px };
        let aspect = if width > 1e-9 { length / width } else { f64::INFINITY };
        let free_ends = branch_ids
            .iter()
            .flat_map(|&i| [sk.branches[i].a, sk.branches[i].b])
            .filter(|&n| sk.nodes.get(n).map_or(false, |pxs| pxs.len() == 1 && sk.deg[pxs[0]] == 1))
            .count();
        // Max tangent turn along one branch: ~0 deg for a straight bar,
        // ~90 deg for an L-shaped stroke (arch + column). Directions point
        // away from each end node, so a straight branch reads 180.
        let mut turn_deg = 0.0f64;
        for &i in &branch_ids {
            let b = &sk.branches[i];
            // one direction window at each end, or the branch carries no
            // turn measurement
            if b.a == usize::MAX || b.b == usize::MAX || b.a == b.b || b.pixels.len() < 2 * params.dir_window_cells {
                continue;
            }
            let da = branch_dir(&sk, b, b.a, params.dir_window_cells);
            let db = branch_dir(&sk, b, b.b, params.dir_window_cells);
            turn_deg = turn_deg.max(180.0 - dir_angle(da, db));
        }
        // Bends are measured along the part's own longest skeleton run
        // (see longest_run_turn).
        turn_deg = turn_deg.max(longest_run_turn(&sk, &branch_ids, params.dir_window_cells));

        // Pieces of this part, grouped by contour in source order.
        let mut my: Vec<&Piece> = pieces.iter().filter(|p| p.root == root).collect();
        my.sort_by_key(|p| (p.contour, p.seg_index));
        // Keep only pieces lying on the UNION silhouette: pieces covered by
        // another source contour's ink are interior; drawing them would
        // make self-intersecting rings. A piece is on the silhouette when
        // a sample point has a non-ink cell within two raster cells.
        my.retain(|p| {
            [0.25, 0.5, 0.75].iter().any(|&t| {
                let pt = seg_eval(&p.seg, t);
                let ci = ((pt.0 - bnds.0) / px).floor() as isize;
                let cj = ((pt.1 - bnds.1) / px).floor() as isize;
                let mut edge = false;
                for dj in -2isize..=2 {
                    for di in -2isize..=2 {
                        let (i, j) = (ci + di, cj + dj);
                        if i < 0
                            || j < 0
                            || i >= w as isize
                            || j >= h as isize
                            || label[(j as usize) * w + i as usize] < 0
                        {
                            edge = true;
                        }
                    }
                }
                edge
            })
        });
        let mut curve_len = 0.0;
        let mut line_len = 0.0;
        let mut longest_piece = 0.0f64;
        for p in &my {
            let l = seg_len_approx(&p.seg);
            longest_piece = longest_piece.max(l);
            match p.seg.kind {
                SegKind::Line => line_len += l,
                SegKind::Curve => curve_len += l,
            }
        }
        let curvature = if curve_len + line_len > 1e-9 { curve_len / (curve_len + line_len) } else { 0.0 };

        // Shared skeleton junction points (vector coords): where this
        // part's branches meet another part's branches. Cut lines route
        // through these so neighbouring parts' cuts coincide and no
        // junction ink falls between the contours.
        let mut jpts: Vec<Pt> = Vec::new();
        {
            let mut node_set: HashSet<usize> = HashSet::new();
            for &bi in &branch_ids {
                node_set.insert(sk.branches[bi].a);
                node_set.insert(sk.branches[bi].b);
            }
            node_set.remove(&usize::MAX);
            // iterate in sorted order: junction routing order affects the
            // emitted cut sequence, so HashSet iteration must not leak in
            let mut node_ids: Vec<usize> = node_set.iter().copied().collect();
            node_ids.sort_unstable();
            for &n in &node_ids {
                let mut inc_roots: HashSet<i32> = HashSet::new();
                for (bi, b) in sk.branches.iter().enumerate() {
                    if b.a == n || b.b == n {
                        inc_roots.insert(eff_root(&mut uf, &eff, bi));
                    }
                }
                if inc_roots.len() >= 2 && inc_roots.contains(&root) {
                    let cells = &sk.nodes[n];
                    if cells.is_empty() {
                        continue;
                    }
                    let (mut sx, mut sy) = (0.0f64, 0.0f64);
                    for &p in cells {
                        sx += (p % w) as f64 + 0.5;
                        sy += (p / w) as f64 + 0.5;
                    }
                    let m = cells.len() as f64;
                    jpts.push((bnds.0 + sx / m * px, bnds.1 + sy / m * px));
                }
            }
        }
        // Cut helper: route from -> to through the shared junction points
        // near the chord, ordered along it.
        let cut_to = |ops: &mut Vec<Op>, from: Pt, to: Pt| {
            let (dx, dy) = (to.0 - from.0, to.1 - from.1);
            let len2 = dx * dx + dy * dy;
            if len2 < 1e-12 {
                return;
            }
            let len = len2.sqrt();
            let mut via: Vec<(f64, Pt)> = jpts
                .iter()
                .copied()
                .filter_map(|j| {
                    let t = ((j.0 - from.0) * dx + (j.1 - from.1) * dy) / len2;
                    let perp = ((j.0 - from.0) * dy - (j.1 - from.1) * dx).abs() / len;
                    // near the chord corridor only (within two stroke widths)
                    if t > -0.25 && t < 1.25 && perp < params.cut_corridor_widths * width.max(px * 4.0) {
                        Some((t, j))
                    } else {
                        None
                    }
                })
                .collect();
            via.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal));
            via.dedup_by(|a, b| (a.1 .0 - b.1 .0).abs() < 1e-9 && (a.1 .1 - b.1 .1).abs() < 1e-9);
            for (_, j) in via {
                ops.push(Op::Line(j));
            }
            ops.push(Op::Line(to));
        };

        // Drop pieces facing a hole region owned by this part (emitted
        // separately as the region's counter ring below).
        my.retain(|p| {
            !piece_faces_owned_region(&p.seg, root, &mask, &region_grid, &hole_surround, w, h, (bnds.0, bnds.1), px)
        });

        // Assemble contour: fully owned source contours emit verbatim;
        // partial pieces chain by endpoint continuity across contours.
        let mut ops: Vec<Op> = Vec::new();
        let mut runs: Vec<(usize, usize, usize)> = Vec::new();
        let mut by_contour: HashMap<usize, Vec<&Piece>> = HashMap::new();
        for p in &my {
            by_contour.entry(p.contour).or_default().push(p);
        }
        let mut contour_ids: Vec<usize> = by_contour.keys().copied().collect();
        contour_ids.sort_unstable();
        // Fully owned contours (exact per-segment coverage) emit verbatim.
        let mut partial: Vec<&Piece> = Vec::new();
        for &ci in &contour_ids {
            let list = &by_contour[&ci];
            let src_segs = contours[ci].segments();
            let total_segs = src_segs.len();
            // Whole-contour shortcut only when the part owns EVERY source
            // segment COMPLETE: exact endpoint (and control point) equality
            // proves no boundary split stole a piece of any segment. The
            // shortcut is verbatim emission with its own Move, so it is
            // valid only when no OTHER contour contributes pieces to this
            // part; mixing verbatim ops and a chained partial chain would
            // emit two subpaths and break the one-ring contract.
            let full = contour_ids.len() == 1
                && list.len() == total_segs
                && list.iter().enumerate().all(|(i, p)| {
                    p.seg_index == i
                        && p.seg.kind == src_segs[i].kind
                        && p.seg.p0 == src_segs[i].p0
                        && p.seg.p1 == src_segs[i].p1
                        && p.seg.c1 == src_segs[i].c1
                        && p.seg.c2 == src_segs[i].c2
                });
            if full {
                ops.extend(contours[ci].ops.iter().cloned());
                runs.push((ci, 0, total_segs.saturating_sub(1)));
            } else {
                partial.extend(list.iter().copied());
            }
        }
        if !partial.is_empty() {
            let list = &partial;
            // Chain pieces by exact endpoint continuity ACROSS source
            // contours: the union silhouette runs through whichever source
            // contour drew it, so a part's ring may change source contour
            // at an overlap edge. Split source segments yield several
            // pieces with the same seg_index; only a true endpoint match
            // may join without a cut.
            let eps = 1e-9 * (bnds.2 - bnds.0).max(bnds.3 - bnds.1) + 1e-12;
            let mut pool: Vec<&Piece> = list.clone();
            let mut run_list: Vec<Vec<&Piece>> = Vec::new();
            while !pool.is_empty() {
                let mut chain: Vec<&Piece> = vec![pool.remove(0)];
                loop {
                    let end = chain.last().unwrap().seg.p1;
                    let next = pool
                        .iter()
                        .position(|p| (p.seg.p0.0 - end.0).abs() < eps && (p.seg.p0.1 - end.1).abs() < eps);
                    match next {
                        Some(i) => chain.push(pool.remove(i)),
                        None => break,
                    }
                }
                run_list.push(chain);
            }
            if run_list.len() >= 2 {
                let end = run_list.last().unwrap().last().unwrap().seg.p1;
                let start = run_list[0].first().unwrap().seg.p0;
                // cyclic: the last chain continues into the first
                if (start.0 - end.0).abs() < eps && (start.1 - end.1).abs() < eps {
                    let first = run_list.remove(0);
                    run_list.last_mut().unwrap().extend(first);
                    let last = run_list.pop().unwrap();
                    run_list.insert(0, last);
                }
            }
            let ring_start = run_list[0].first().unwrap().seg.p0;
            let mut prev_end: Option<Pt> = None;
            for r in &run_list {
                // provenance: maximal same-contour subsequences of the chain
                let mut run_start = 0usize;
                for k in 1..=r.len() {
                    if k == r.len() || r[k].contour != r[run_start].contour {
                        runs.push((r[run_start].contour, r[run_start].seg_index, r[k - 1].seg_index));
                        run_start = k;
                    }
                }
                match prev_end {
                    None => ops.push(Op::Move(r.first().unwrap().seg.p0)),
                    Some(e) => cut_to(&mut ops, e, r.first().unwrap().seg.p0),
                }
                for p in r {
                    ops.push(seg_to_op(&p.seg));
                }
                prev_end = Some(r.last().unwrap().seg.p1);
            }
            // Mis-chaining guard (measured on the woven-pattern tail:
            // numbersign/hyphen/period carry 13-22x more excess ink than
            // loss, concentrated in 1-4 rings per glyph): a walk chained
            // through shared junctions can pass a point already on the
            // ring and continue into a spurious loop (an out-and-back
            // tooth, or a rectangle wrapping background or a neighbour's
            // ink). Split the walk at each return-to-ring vertex and drop
            // a split loop that fills zero area or covers none of this
            // part's own raster cells; genuine silhouette pinches cover
            // own cells and stay. Continuity is preserved: the loop starts
            // and ends at the same vertex, so the next op still starts
            // where the previous one ended.
            {
                let same_pt = |a: Pt, b: Pt| (a.0 - b.0).abs() < eps && (a.1 - b.1).abs() < eps;
                let area_eps = 0.25 * px * px; // quarter cell: below raster resolution
                let covers_own = |poly: &[Pt]| -> bool {
                    // even-odd cell-center test over the polygon bbox;
                    // curve pieces enter as chords (zero/own distinction only)
                    let (mut x0, mut y0, mut x1, mut y1) =
                        (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
                    for &(x, y) in poly {
                        x0 = x0.min(x);
                        y0 = y0.min(y);
                        x1 = x1.max(x);
                        y1 = y1.max(y);
                    }
                    let i0 = (((x0 - bnds.0) / px).floor() as isize).max(0);
                    let i1 = (((x1 - bnds.0) / px).floor() as isize).min(w as isize - 1);
                    let j0 = (((y0 - bnds.1) / px).floor() as isize).max(0);
                    let j1 = (((y1 - bnds.1) / px).floor() as isize).min(h as isize - 1);
                    for j in j0..=j1 {
                        let cy = bnds.1 + (j as f64 + 0.5) * px;
                        for i in i0..=i1 {
                            let c = j as usize * w + i as usize;
                            let l = label[c];
                            if l < 0 || eff.get(&l).copied().unwrap_or(l) != root {
                                continue;
                            }
                            let cx = bnds.0 + (i as f64 + 0.5) * px;
                            let mut inside = false;
                            for k in 0..poly.len().saturating_sub(1) {
                                let (ax, ay) = poly[k];
                                let (bx, by) = poly[k + 1];
                                if (ay > cy) != (by > cy) {
                                    let xin = ax + (cy - ay) * (bx - ax) / (by - ay);
                                    if xin > cx {
                                        inside = !inside;
                                    }
                                }
                            }
                            if inside {
                                return true;
                            }
                        }
                    }
                    false
                };
                let shoelace2 = |poly: &[Pt]| -> f64 {
                    let mut a = 0.0f64;
                    for k in 0..poly.len().saturating_sub(1) {
                        a += poly[k].0 * poly[k + 1].1 - poly[k + 1].0 * poly[k].1;
                    }
                    a
                };
                let orig = std::mem::take(&mut ops);
                let mut out_ops: Vec<Op> = Vec::with_capacity(orig.len());
                let mut verts: Vec<Pt> = Vec::with_capacity(orig.len());
                for op in orig.iter().cloned() {
                    let end = match op {
                        Op::Move(p) | Op::Line(p) => Some(p),
                        Op::Curve(_, _, p) => Some(p),
                        Op::Close => None,
                    };
                    match end {
                        Some(p) => {
                            if !verts.is_empty() {
                                if let Some(s) = verts.iter().rposition(|&v| same_pt(v, p)) {
                                    let mut poly = verts[s..].to_vec();
                                    poly.push(p);
                                    if shoelace2(&poly).abs() <= area_eps || !covers_own(&poly) {
                                        out_ops.truncate(s + 1);
                                        verts.truncate(s + 1);
                                        continue;
                                    }
                                }
                            }
                            verts.push(p);
                            out_ops.push(op);
                        }
                        None => out_ops.push(op),
                    }
                }
                // Never empty a part's ring: fall back to the unfiltered walk.
                ops = if out_ops.len() >= 2 { out_ops } else { orig };
            }
            // close the ring through the shared junctions
            if let Some(e) = prev_end {
                cut_to(&mut ops, e, ring_start);
            }
        }
        // Owned holes travel with the part as SEPARATE closed rings: the
        // smooth source ring where a source counter bounds the region
        // exactly, else the region's raster ring.
        // Flattened ring polygon for enclosure tests: curve pieces sampled
        // at the same quarter points used elsewhere in this file.
        let mut ring_pts: Vec<Pt> = Vec::new();
        {
            let mut cur: Option<Pt> = None;
            for op in &ops {
                match *op {
                    Op::Move(p) => {
                        cur = Some(p);
                        ring_pts.push(p);
                    }
                    Op::Line(p) => {
                        cur = Some(p);
                        ring_pts.push(p);
                    }
                    Op::Curve(c1, c2, p) => {
                        if let Some(p0) = cur {
                            for &t in &[0.25f64, 0.5, 0.75] {
                                let u = 1.0 - t;
                                ring_pts.push((
                                    u * u * u * p0.0 + 3.0 * u * u * t * c1.0 + 3.0 * u * t * t * c2.0 + t * t * t * p.0,
                                    u * u * u * p0.1 + 3.0 * u * u * t * c1.1 + 3.0 * u * t * t * c2.1 + t * t * t * p.1,
                                ));
                            }
                        }
                        cur = Some(p);
                        ring_pts.push(p);
                    }
                    Op::Close => {}
                }
            }
        }
        let ring_bbox = ring_pts.iter().fold(
            (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY),
            |(a, b, c, d), &(x, y)| (a.min(x), b.min(y), c.max(x), d.max(y)),
        );
        let pt_in_ring = |x: f64, y: f64| -> bool {
            let mut inside = false;
            for k in 0..ring_pts.len() {
                let (ax, ay) = ring_pts[k];
                let (bx, by) = ring_pts[(k + 1) % ring_pts.len()];
                if (ay > y) != (by > y) {
                    let xin = ax + (y - ay) * (bx - ax) / (by - ay);
                    if xin > x {
                        inside = !inside;
                    }
                }
            }
            inside
        };
        let owned_counters: Vec<usize> = (0..regions.len())
            .filter(|&ri| {
                if hole_surround[ri].len() == 1 && hole_surround[ri].contains(&root) {
                    return true;
                }
                // Ring-enclosed background (measured route (a), weave
                // crossings): when the assembled ring fully encloses a
                // background region this part borders (or one no part
                // borders), the region is this part's counter even though
                // the part's INK does not surround it - not carving it
                // fills the region with excess ink. Every bordering part
                // whose ring encloses the region carves it, so the ring
                // union leaves it background.
                if !(hole_surround[ri].is_empty() || hole_surround[ri].contains(&root)) || ring_pts.len() < 3 {
                    return false;
                }
                let cells = &regions[ri];
                let (mut x0, mut y0, mut x1, mut y1) =
                    (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
                for &c in cells {
                    let cx = bnds.0 + ((c % w) as f64 + 0.5) * px;
                    let cy = bnds.1 + ((c / w) as f64 + 0.5) * px;
                    x0 = x0.min(cx);
                    y0 = y0.min(cy);
                    x1 = x1.max(cx);
                    y1 = y1.max(cy);
                }
                if x1 < ring_bbox.0 || x0 > ring_bbox.2 || y1 < ring_bbox.1 || y0 > ring_bbox.3 {
                    return false;
                }
                cells.iter().all(|&c| {
                    pt_in_ring(
                        bnds.0 + ((c % w) as f64 + 0.5) * px,
                        bnds.1 + ((c / w) as f64 + 0.5) * px,
                    )
                })
            })
            .collect();

        let holes: Vec<StrokeContour> = owned_counters
            .iter()
            .map(|&ri| match hole_match[ri] {
                Some(ci) => StrokeContour { stroke: String::new(), ops: orig_contours[ci].ops.clone() },
                None => {
                    let poly = &hole_polys[ri];
                    let mut ops = Vec::with_capacity(poly.len() + 2);
                    if let Some(&p0) = poly.first() {
                        ops.push(Op::Move(p0));
                        for &p in &poly[1..] {
                            ops.push(Op::Line(p));
                        }
                    }
                    ops.push(Op::Close);
                    StrokeContour { stroke: String::new(), ops }
                }
            })
            .collect();
        if ops.is_empty() {
            continue;
        }
        if !matches!(ops.last(), Some(Op::Close)) {
            ops.push(Op::Close);
        }

        // Features + label.
        let m = moments.get(&root);
        let (axis_deg, _degen) = m.and_then(|mm| mm.axis()).unwrap_or((0.0, true));
        let rel = glyph_axis.map(|ga| axis_rel(axis_deg, ga));
        let axis_pos = glyph_axis.and_then(|ga| {
            let (ax, ay) = (ga.to_radians().cos(), ga.to_radians().sin());
            let m2 = m?;
            let (cx, cy) = (m2.sx / m2.n, m2.sy / m2.n);
            let lo = (gbb.0 * ax + gbb.1 * ay)
                .min(gbb.2 * ax + gbb.1 * ay)
                .min(gbb.0 * ax + gbb.3 * ay)
                .min(gbb.2 * ax + gbb.3 * ay);
            let hi = (gbb.0 * ax + gbb.1 * ay)
                .max(gbb.2 * ax + gbb.1 * ay)
                .max(gbb.0 * ax + gbb.3 * ay)
                .max(gbb.2 * ax + gbb.3 * ay);
            if hi - lo < 1e-9 {
                Some(0.5)
            } else {
                Some(((cx * ax + cy * ay) - lo) / (hi - lo))
            }
        });
        let is_cycle = cycle_roots.contains(&(root as usize));
        // Classification feature: only counters the part's INK surrounds
        // make a bowl. Ring-enclosed wedges carved at assembly (route (a))
        // remove excess ink; they are not glyph structure and must not
        // relabel a bar as a bowl.
        let owns_counter = (0..regions.len())
            .any(|ri| hole_surround[ri].len() == 1 && hole_surround[ri].contains(&root));
        let elongation = if width > 1e-9 { longest_piece / width } else { f64::INFINITY };
        let ink_frac = moments.get(&root).map(|m| m.n).unwrap_or(0.0) / all.n.max(1.0);
        let (class, rule) = classify(
            is_cycle,
            owns_counter,
            elongation,
            ink_frac,
            turn_deg,
            aspect,
            curvature,
            axis_deg,
            rel,
            axis_pos,
            glyph_axis.is_some(),
            params,
        );
        part_roots.push(root);
        parts.push(Part {
            name: String::new(), // named after sorting below
            class,
            contour: StrokeContour { stroke: String::new(), ops },
            holes,
            provenance: Provenance {
                branches: branch_ids,
                runs,
                counters: owned_counters,
                axis_deg,
                rel_axis_deg: rel,
                aspect,
                curvature,
                free_ends,
                axis_pos,
                rule,
            },
        });
    }

    // Shared-boundary counters: a background region whose boundary is split
    // between several parts is owned by none of them when no single part
    // ring fully encloses it (measured: Marq "a" counter, iou 0.5979). The
    // union then fills it with ink. Hand every such region to the largest
    // part bordering it, as that part's counter ring; the other bordering
    // parts' rings cover the remainder, so the union keeps it background
    // and the protrusion gate still verifies the result.
    {
        let claimed: HashSet<usize> = parts.iter().flat_map(|p| p.provenance.counters.iter().copied()).collect();
        for ri in 0..regions.len() {
            if claimed.contains(&ri) || hole_surround[ri].is_empty() {
                continue;
            }
            let mut best: Option<(usize, f64)> = None;
            for (pi, r) in part_roots.iter().enumerate() {
                if !hole_surround[ri].contains(r) {
                    continue;
                }
                let n = moments.get(r).map(|m| m.n).unwrap_or(0.0);
                if best.map_or(true, |(_, bn)| n > bn) {
                    best = Some((pi, n));
                }
            }
            let Some((pi, _)) = best else { continue };
            let hole = match hole_match[ri] {
                Some(ci) => StrokeContour { stroke: String::new(), ops: orig_contours[ci].ops.clone() },
                None => {
                    let poly = &hole_polys[ri];
                    let mut ops = Vec::with_capacity(poly.len() + 2);
                    if let Some(&p0) = poly.first() {
                        ops.push(Op::Move(p0));
                        for &q in &poly[1..] {
                            ops.push(Op::Line(q));
                        }
                    }
                    ops.push(Op::Close);
                    StrokeContour { stroke: String::new(), ops }
                }
            };
            parts[pi].holes.push(hole);
            parts[pi].provenance.counters.push(ri);
        }
    }

    // Names: largest part of a class takes the bare name, then .2, .3...
    let mut order: Vec<usize> = (0..parts.len()).collect();
    order.sort_by(|&a, &b| {
        let na = moments.get(&(roots[a])).map(|m| m.n).unwrap_or(0.0);
        let nb = moments.get(&(roots[b])).map(|m| m.n).unwrap_or(0.0);
        nb.partial_cmp(&na).unwrap_or(std::cmp::Ordering::Equal)
    });
    let mut class_count: HashMap<&'static str, usize> = HashMap::new();
    for (rank, &pi) in order.iter().enumerate() {
        let base = parts[pi].class.as_str();
        let seen = class_count.entry(base).or_insert(0);
        *seen += 1;
        let name = if *seen == 1 { base.to_string() } else { format!("{}.{}", base, seen) };
        parts[pi].name = name.clone();
        parts[pi].contour.stroke = name.clone();
        for (hi, h) in parts[pi].holes.iter_mut().enumerate() {
            h.stroke = format!("{name}.counter{}", hi + 1);
        }
        // Export contract: a counter ring SUBTRACTS from its owner's ring
        // under nonzero (sum-of-windings) fill. Force each hole's winding
        // opposite to the outer ring so the exported glyph keeps its ink
        // under that consumer instead of filling counters back in.
        let outer_sign = signed_area(&parts[pi].contour.ops).signum();
        if outer_sign != 0.0 {
            for h in parts[pi].holes.iter_mut() {
                if signed_area(&h.ops).signum() == outer_sign {
                    h.ops = reverse_ops(&h.ops);
                }
            }
        }
        let _ = rank;
    }

    let master = MasterGlyph {
        name: g.name.clone(),
        advance: g.advance,
        upm: g.upm,
        contours: parts
            .iter()
            .flat_map(|p| std::iter::once(p.contour.clone()).chain(p.holes.iter().cloned()))
            .collect(),
    };
    let d = Decomposition { glyph: master, parts, glyph_axis_deg: glyph_axis, cell: px };
    // Never hand B/C structurally invalid output.
    check_structure(&d).map_err(DecomposeError::Structure)?;
    Ok(d)
}

#[allow(clippy::too_many_arguments)]
fn classify(
    is_cycle: bool,
    owns_counter: bool,
    elongation: f64,
    ink_frac: f64,
    turn_deg: f64,
    aspect: f64,
    curvature: f64,
    axis_deg: f64,
    rel: Option<f64>,
    axis_pos: Option<f64>,
    has_glyph_axis: bool,
    params: &DecomposeParams,
) -> (PartClass, String) {
    if is_cycle || owns_counter {
        return (
            PartClass::Bowl,
            format!(
                "bowl: {} (aspect {:.2}, curvature {:.2})",
                if owns_counter { "owns counter" } else { "cycle encloses hole" },
                aspect,
                curvature
            ),
        );
    }
    // Elongation is measured on the OWNED BOUNDARY (longest piece / stroke
    // width): junction zones corrupt skeleton lengths, the vector boundary
    // is exact. A SMALL part that is not elongated is a mark (dot, accent);
    // a large stubby region still goes through the angle rules.
    if elongation < params.bar_aspect && ink_frac < params.mark_ink_frac {
        return (
            PartClass::Mark,
            format!(
                "mark: elongation {:.2} < bar_aspect {:.2}, ink {:.1}%",
                elongation,
                params.bar_aspect,
                ink_frac * 100.0
            ),
        );
    }
    // Geometry primary (chief ruling 2026-10-17, ported to 073372e
    // 2026-10-18): a vertical-extent-dominant bar is a stem regardless of
    // junction topology; junction bends are only a tiebreaker. Measured
    // against the FONT y-axis so a slanted glyph axis cannot relabel a
    // true stem (owner h stem: axis 89.1 deg, aspect 10.84, junction at
    // its base, previously read arm).
    let rel_font = axis_rel(axis_deg, 90.0);
    if aspect > params.stem_bar_aspect && rel_font <= params.stem_deg && curvature < params.curve_ratio_arm {
        return (
            PartClass::Stem,
            format!(
                "stem: vertical-dominant bar, aspect {:.2} > {:.0}, axis {:.1} deg from font y-axis",
                aspect, params.stem_bar_aspect, rel_font
            ),
        );
    }
    if curvature >= params.curve_ratio_arm {
        return (
            PartClass::Arm,
            format!("arm: curvature {:.2} >= {:.2} (open curve)", curvature, params.curve_ratio_arm),
        );
    }
    // No glyph axis: measure against the font y-axis (90 deg from +x).
    let rel = rel.unwrap_or_else(|| axis_rel(axis_deg, 90.0));
    let frame = if has_glyph_axis { "glyph axis" } else { "font y-axis" };
    if rel <= params.stem_deg && turn_deg >= params.bend_deg {
        return (
            PartClass::Arm,
            format!("arm: axis {:.1} deg from {} but skeleton bends {:.0} deg", rel, frame, turn_deg),
        );
    }
    if rel <= params.stem_deg {
        (PartClass::Stem, format!("stem: bar axis {:.1} deg from {} (<= {:.0})", rel, frame, params.stem_deg))
    } else if rel >= params.arm_deg {
        (PartClass::Arm, format!("arm: bar axis {:.1} deg from {} (>= {:.0})", rel, frame, params.arm_deg))
    } else {
        let pos = axis_pos.unwrap_or(0.5);
        if pos >= 0.5 {
            (PartClass::Arm, format!("arm: diagonal bar {:.1} deg from {}, mass at {:.2} of axis", rel, frame, pos))
        } else {
            (PartClass::Leg, format!("leg: diagonal bar {:.1} deg from {}, mass at {:.2} of axis", rel, frame, pos))
        }
    }
}

/// Structural contract expected by the shared B/C source adapter: every
/// part contour and every counter ring is ONE closed ring - a single
/// leading Move, drawing ops, a single trailing Close, no interior
/// Move/Close. A structural stroke never carries several subpaths.
pub fn check_structure(d: &Decomposition) -> Result<(), String> {
    fn is_ring(c: &StrokeContour) -> bool {
        c.ops.len() >= 3
            && matches!(c.ops.first(), Some(Op::Move(_)))
            && matches!(c.ops.last(), Some(Op::Close))
            && c.ops[1..c.ops.len() - 1]
                .iter()
                .all(|op| !matches!(op, Op::Move(_) | Op::Close))
    }
    for p in &d.parts {
        if !is_ring(&p.contour) {
            return Err(format!("part {} contour is not one closed ring", p.name));
        }
        for h in &p.holes {
            if !is_ring(h) {
                return Err(format!("part {} counter ring is not one closed ring", p.name));
            }
        }
    }
    Ok(())
}

/// Effective part root of a skeleton branch: partition roots absorbed by
/// orphan/fragment merges keep their branch identity through `eff`.
fn eff_root(uf: &mut Uf, eff: &HashMap<i32, i32>, i: usize) -> i32 {
    let mut r = uf.find(i) as i32;
    while let Some(&t) = eff.get(&r) {
        r = t;
    }
    r
}

/// Resolve fragment-merge targets to surviving roots: a small root may
/// pick another small root, so follow each chain to a root outside the
/// map; drop remap members caught in a cycle (A->B, B->A). Deterministic:
/// keys are visited in sorted order.
fn resolve_remap(target: &HashMap<i32, i32>) -> HashMap<i32, i32> {
    let mut out = HashMap::new();
    let mut keys: Vec<i32> = target.keys().copied().collect();
    keys.sort_unstable();
    for &k in &keys {
        let mut seen = vec![k];
        let mut cur = k;
        let resolved = loop {
            let t = target[&cur];
            if !target.contains_key(&t) {
                break Some(t);
            }
            if seen.contains(&t) {
                break None;
            }
            seen.push(t);
            cur = t;
        };
        if let Some(t) = resolved {
            out.insert(k, t);
        }
    }
    out
}

#[cfg(test)]
mod tests {

    fn hline_skeleton() -> super::Skeleton {
        // 20x20 grid; center node 0 at (10,10), leaves: 1 left (5,10),
        // 2 up (10,5), 3 right (15,10); three equal-length branches.
        let w = 20usize;
        let px = |x: usize, y: usize| y * w + x;
        super::Skeleton {
            w,
            h: 20,
            deg: vec![0u8; w * 20],
            dist: vec![1.0f32; w * 20],
            nodes: vec![vec![px(10, 10)], vec![px(5, 10)], vec![px(10, 5)], vec![px(15, 10)]],
            branches: vec![
                super::Branch { a: 0, b: 1, pixels: vec![px(10,10),px(9,10),px(8,10),px(7,10),px(6,10),px(5,10)], len: 5.0 },
                super::Branch { a: 0, b: 2, pixels: vec![px(10,10),px(10,9),px(10,8),px(10,7),px(10,6),px(10,5)], len: 5.0 },
                super::Branch { a: 0, b: 3, pixels: vec![px(10,10),px(11,10),px(12,10),px(13,10),px(14,10),px(15,10)], len: 5.0 },
            ],
        }
    }

    #[test]
    fn longest_run_turn_is_deterministic_on_diameter_ties() {
        // Three equal-length diameter candidates: paths 1-2 and 2-3 turn
        // 90 deg at the center, path 1-3 turns 0. The deterministic
        // tie-break (smallest node id) must always pick path 1-2: 90 deg,
        // regardless of HashSet iteration order (fresh state every call).
        let sk = hline_skeleton();
        for _ in 0..64 {
            let t = super::longest_run_turn(&sk, &[0, 1, 2], 2);
            assert_eq!(t, 90.0, "tie-break must be stable, got {t}");
        }
    }

    #[test]
    fn reverse_ops_flips_winding_and_keeps_fill() {
        use super::{Op, Pt, StrokeContour};
        use crate::check::stroke_polygon;
        use crate::raster::inside_merged;
        let ring = vec![
            Op::Move((0.0, 0.0)),
            Op::Line((10.0, 0.0)),
            Op::Curve((10.0, 10.0), (5.0, 12.0), (0.0, 10.0)),
            Op::Close,
        ];
        let rev = super::reverse_ops(&ring);
        let a = super::signed_area(&ring);
        let b = super::signed_area(&rev);
        assert_eq!(b, -a);
        assert!(a.abs() > 0.0);
        let inside = |ops: &[Op], p: Pt| inside_merged(p, &[stroke_polygon(&StrokeContour { stroke: String::new(), ops: ops.to_vec() })]);
        for p in [(5.0, 5.0), (1.0, 1.0), (9.0, 9.0), (-1.0, 5.0), (5.0, -1.0), (11.0, 5.0)] {
            assert_eq!(inside(&ring, p), inside(&rev, p), "fill changed at {p:?}");
        }
    }
    use super::resolve_remap;
    use std::collections::HashMap;

    #[test]
    fn remap_chain_resolves_to_survivor() {
        // two adjacent small roots: 1 -> 2, 2 -> 9 (survivor)
        let target: HashMap<i32, i32> = [(1, 2), (2, 9)].into_iter().collect();
        let out = resolve_remap(&target);
        assert_eq!(out.get(&1), Some(&9));
        assert_eq!(out.get(&2), Some(&9));
    }

    #[test]
    fn remap_cycle_is_dropped() {
        // A <-> B: neither may be removed
        let target: HashMap<i32, i32> = [(1, 2), (2, 1)].into_iter().collect();
        let out = resolve_remap(&target);
        assert!(out.is_empty());
    }

    #[test]
    fn remap_self_loop_is_dropped() {
        let target: HashMap<i32, i32> = [(1, 1)].into_iter().collect();
        let out = resolve_remap(&target);
        assert!(out.is_empty());
    }
}

/// Debug helper: skeleton statistics for a glyph (not part of the API).
pub fn debug_skeleton_stats(g: &MasterGlyph) {
    let contours = &g.contours;
    let polys: Vec<Vec<Pt>> = contours.iter().map(stroke_polygon).collect();
    let bnds = bounds_of(&[&polys], 2.0);
    let span = (bnds.2 - bnds.0).max(bnds.3 - bnds.1);
    let px = span / 640.0;
    let (w, h, mask) = rasterize(&polys, true, bnds, px, (0.5, 0.5));
    let ink = mask.iter().filter(|&&m| m).count();
    let sk = build_skeleton(&mask, w, h);
    let skel_n = sk.branches.iter().map(|b| b.pixels.len()).sum::<usize>();
    eprintln!("grid {w}x{h} ink {ink} skel_px {skel_n} nodes {} branches {}", sk.nodes.len(), sk.branches.len());
    let mut degs: Vec<usize> = sk.nodes.iter().map(|n| n.len()).collect();
    degs.sort_unstable();
    eprintln!("node cluster sizes: {:?}", degs);
    let mut bl: Vec<usize> = sk.branches.iter().map(|b| b.pixels.len()).collect();
    bl.sort_unstable();
    eprintln!("branch pixel lens: {:?}", bl);
}

/// Debug helper: run thinning on a mask.
pub fn debug_thin(mask: &[bool], w: usize, h: usize) -> Vec<bool> {
    thin(mask, w, h)
}

/// Debug helper: skeleton graph dump for a glyph.
pub fn debug_skeleton_graph(g: &MasterGlyph) {
    let contours = &g.contours;
    let polys: Vec<Vec<Pt>> = contours.iter().map(stroke_polygon).collect();
    let bnds = bounds_of(&[&polys], 2.0);
    let span = (bnds.2 - bnds.0).max(bnds.3 - bnds.1);
    let px = span / 640.0;
    let (w, h, mask) = rasterize(&polys, true, bnds, px, (0.5, 0.5));
    let sk = build_skeleton(&mask, w, h);
    eprintln!("grid {w}x{h} px {px:.3} nodes {} branches {}", sk.nodes.len(), sk.branches.len());
    for (i, n) in sk.nodes.iter().enumerate() {
        let c = n.iter().fold((0.0, 0.0), |a, &p| (a.0 + (p % w) as f64 / n.len() as f64, a.1 + (p / w) as f64 / n.len() as f64));
        eprintln!("node {i}: {} px at cell ({:.0},{:.0})", n.len(), c.0, c.1);
    }
    for (i, b) in sk.branches.iter().enumerate() {
        eprintln!("branch {i}: {} -> {}, {} px, len {:.1}", b.a, b.b, b.pixels.len(), b.len);
    }
}

/// Debug helper: ASCII dump of the partition (one char per 4x4 cells).
pub fn debug_partition(g: &MasterGlyph) {
    let contours = &g.contours;
    let polys: Vec<Vec<Pt>> = contours.iter().map(stroke_polygon).collect();
    let bnds = bounds_of(&[&polys], 2.0);
    let span = (bnds.2 - bnds.0).max(bnds.3 - bnds.1);
    let px = span / 640.0;
    let (w, h, mask) = rasterize(&polys, true, bnds, px, (0.5, 0.5));
    let sk = build_skeleton(&mask, w, h);
    let (mut uf, _c) = group_branches(&sk, &mask, &[], &DecomposeParams::default());
    let label = partition(&sk, &mask, &mut uf);
    let mut roots: Vec<i32> = label.iter().copied().filter(|&l| l >= 0).collect();
    roots.sort_unstable();
    roots.dedup();
    eprintln!("roots: {:?}", roots);
    let step = 6;
    for j in (0..h).rev().step_by(step) {
        let mut row = String::new();
        for i in (0..w).step_by(step) {
            let idx = j * w + i;
            row.push(if !mask[idx] {
                '.'
            } else if label[idx] < 0 {
                '?'
            } else {
                let r = roots.iter().position(|&r| r == label[idx]).unwrap_or(0);
                char::from_digit((r % 36) as u32, 36).unwrap()
            });
        }
        eprintln!("{}", row);
    }
    for (i, b) in sk.branches.iter().enumerate() {
        eprintln!("branch {i} (part {}): {} -> {}, {} px", uf.find(i), b.a, b.b, b.pixels.len());
    }
}

/// Debug helper: per-branch geometry and grouping for a glyph.
pub fn debug_part_geometry(g: &MasterGlyph) {
    let contours = &g.contours;
    let polys: Vec<Vec<Pt>> = contours.iter().map(stroke_polygon).collect();
    let bnds = bounds_of(&[&polys], 2.0);
    let span = (bnds.2 - bnds.0).max(bnds.3 - bnds.1);
    let px = span / 640.0;
    let (w, h, mask) = rasterize(&polys, true, bnds, px, (0.5, 0.5));
    let sk = build_skeleton(&mask, w, h);
    let (mut uf, _) = group_branches(&sk, &mask, &[], &DecomposeParams::default());
    eprintln!("== {} grid {w}x{h} px {px:.3} branches {}", g.name, sk.branches.len());
    for (i, b) in sk.branches.iter().enumerate() {
        let mut ws: Vec<f32> = b.pixels.iter().map(|&p| sk.dist[p]).collect();
        ws.sort_by(|a, b2| a.partial_cmp(b2).unwrap_or(std::cmp::Ordering::Equal));
        let med = if ws.is_empty() { 0.0 } else { ws[ws.len() / 2] };
        eprintln!(
            "branch {i} (part {}): {} -> {}, {} px len {:.1} meddist {:.1} aspect {:.2}",
            uf.find(i),
            b.a,
            b.b,
            b.pixels.len(),
            b.len,
            med,
            b.len / (2.0 * med as f64).max(1e-9)
        );
    }
    let label = partition(&sk, &mask, &mut uf);
    let mut roots: Vec<i32> = label.iter().copied().filter(|&l| l >= 0).collect();
    roots.sort_unstable();
    roots.dedup();
    let ink = mask.iter().filter(|&&m| m).count();
    eprintln!("roots {:?} ink {} nodes {}", roots, ink, sk.nodes.len());
}

/// Debug helper: per-part and total reconstruction IoU against the source.
pub fn debug_iou(g: &MasterGlyph) {
    let d = decompose(g).expect("decompose");
    let src_polys: Vec<Vec<Pt>> = g.contours.iter().map(stroke_polygon).collect();
    let bnds = bounds_of(&[&src_polys], 2.0);
    let span = (bnds.2 - bnds.0).max(bnds.3 - bnds.1);
    let px = span / 640.0;
    let (w, h, src) = rasterize(&src_polys, true, bnds, px, (0.5, 0.5));
    let mut union = vec![false; w * h];
    for p in &d.parts {
        let polys: Vec<Vec<Pt>> = std::iter::once(&p.contour)
            .chain(p.holes.iter())
            .map(|c| stroke_polygon(c))
            .collect();
        let (_, _, m) = rasterize(&polys, true, bnds, px, (0.5, 0.5));
        let mut inter = 0usize;
        let mut own = 0usize;
        for i in 0..w * h {
            if m[i] {
                own += 1;
                if src[i] {
                    inter += 1;
                }
            }
            union[i] |= m[i];
        }
        let uni = own + src.iter().filter(|&&s| s).count() - inter;
        eprintln!("part {} class {:?} cells {} IoU-vs-src {:.3}", p.name, p.class, own, inter as f64 / uni.max(1) as f64);
    }
    let inter = union.iter().zip(&src).filter(|(&u, &s)| u && s).count();
    let uni = union.iter().zip(&src).filter(|(&u, &s)| u || s).count();
    eprintln!("TOTAL IoU {:.4}", inter as f64 / uni as f64);
    // coarse maps: source silhouette, union silhouette, then diff
    for (tag, m) in [("SRC", &src), ("UNION", &union)] {
        eprintln!("--- {tag}");
        for j in (0..h).step_by(16) {
            let mut line = String::new();
            for i in (0..w).step_by(8) {
                let mut on = false;
                for dj in 0..16.min(h - j) {
                    for di in 0..8.min(w - i) {
                        if m[(j + dj) * w + i + di] {
                            on = true;
                        }
                    }
                }
                line.push(if on { '#' } else { '.' });
            }
            eprintln!("{line}");
        }
    }
    // coarse map of missing ink (X) and extra ink (+)
    for j in (0..h).step_by(8) {
        let mut line = String::new();
        for i in (0..w).step_by(4) {
            let mut miss = false;
            let mut extra = false;
            for dj in 0..8.min(h - j) {
                for di in 0..4.min(w - i) {
                    let idx = (j + dj) * w + i + di;
                    if src[idx] && !union[idx] {
                        miss = true;
                    }
                    if union[idx] && !src[idx] {
                        extra = true;
                    }
                }
            }
            line.push(if miss && extra { 'B' } else if miss { 'X' } else if extra { '+' } else { '.' });
        }
        eprintln!("{line}");
    }
}
