'use strict';
// Pairwise disk overlap relaxation with a per-item displacement budget. Generic: every tuning value is an argument.
// items: [{x,y,r}] (mutated copy returned). opts: {passes:int>=1, budget:(item,i)=>number>=0, gap:number>=0}
// A pair at distance d with radii ra+rb+gap > d has separation sep=(ra+rb+gap)-d>0 and is pushed apart half each.
// Budget spends |movement|; it is never refunded, so a later opposing move cannot restore it.
function resolveOverlaps(items, opts) {
  for (const k of ['passes', 'budget', 'gap']) if (opts == null || opts[k] === undefined) throw new TypeError('missing option: ' + k);
  const it = items.map(o => ({ x: o.x, y: o.y, r: o.r }));
  const used = new Float64Array(it.length);
  const cap = it.map((o, i) => { const b = opts.budget(o, i); if (!(b >= 0)) throw new RangeError('budget must be >= 0'); return b; });
  for (let p = 0; p < opts.passes; p++) {
    for (let i = 0; i < it.length; i++) for (let j = i + 1; j < it.length; j++) {
      const a = it[i], b = it[j]; let dx = b.x - a.x, dy = b.y - a.y; let d = Math.hypot(dx, dy);
      const sep = a.r + b.r + opts.gap - d; if (!(sep > 0)) continue;
      if (d === 0) { dx = 1; dy = 0; d = 1; }
      const nx = dx / d, ny = dy / d, half = sep / 2;
      const ma = Math.min(half, Math.max(0, cap[i] - used[i])), mb = Math.min(half, Math.max(0, cap[j] - used[j]));
      a.x -= nx * ma; a.y -= ny * ma; used[i] += ma; b.x += nx * mb; b.y += ny * mb; used[j] += mb;
    }
  }
  return { items: it, used: Array.from(used) };
}
module.exports = { resolveOverlaps };
