'use strict';
// Uniform-grid broadphase for disks. Returns every index pair (i<j) whose disks overlap by more than `gap` slack: d < ri + rj + gap.
// items [{x,y,r}], opts {cell:number>0 (grid cell size), gap:number>=0}. Output sorted (i then j) so results are deterministic.
function overlapPairs(items, opts) {
  if (opts == null || !(opts.cell > 0) || !(opts.gap >= 0)) throw new TypeError('opts.cell>0 and opts.gap>=0 required');
  const grid = new Map(), key = (cx, cy) => cx + ',' + cy, cs = opts.cell, out = [];
  const reach = items.reduce((m, o) => Math.max(m, o.r), 0) * 2 + opts.gap, span = Math.max(1, Math.ceil(reach / cs));
  items.forEach((o, i) => { const k = key(Math.floor(o.x / cs), Math.floor(o.y / cs)); (grid.get(k) || grid.set(k, []).get(k)).push(i); });
  items.forEach((a, i) => {
    const cx = Math.floor(a.x / cs), cy = Math.floor(a.y / cs);
    for (let dx = -span; dx <= span; dx++) for (let dy = -span; dy <= span; dy++) {
      const cell = grid.get(key(cx + dx, cy + dy)); if (!cell) continue;
      for (const j of cell) { if (j <= i) continue; const b = items[j]; if (Math.hypot(a.x - b.x, a.y - b.y) < a.r + b.r + opts.gap) out.push([i, j]); }
    }
  });
  return out.sort((p, q) => p[0] - q[0] || p[1] - q[1]);
}
module.exports = { overlapPairs };
