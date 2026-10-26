'use strict';
// Soft-zone wall force plus hard edge clamp for one disk in an axis-aligned rectangle. Pure; every constant is an argument.
// state {x,y,vx,vy,r}; rect {x0,y0,x1,y1}; params {zone>0, force>=0, damp 0..1}; returns a new state.
function boundaryStep(state, rect, params) {
  for (const k of ['zone', 'force', 'damp']) if (params == null || !(params[k] >= 0)) throw new TypeError('missing or negative param: ' + k);
  if (!(params.zone > 0)) throw new RangeError('zone must be > 0');
  const s = { x: state.x, y: state.y, vx: state.vx, vy: state.vy, r: state.r };
  const side = (pos, v, lo, hi) => {
    let dLo = pos - s.r - lo, dHi = hi - (pos + s.r);
    if (dLo < params.zone) { const t = Math.min(1, Math.max(0, 1 - dLo / params.zone)); v += params.force * t * t; if (v < 0) v *= 1 - params.damp * t; }
    if (dHi < params.zone) { const t = Math.min(1, Math.max(0, 1 - dHi / params.zone)); v -= params.force * t * t; if (v > 0) v *= 1 - params.damp * t; }
    if (pos - s.r < lo) { pos = lo + s.r; if (v < 0) v = 0; }
    if (pos + s.r > hi) { pos = hi - s.r; if (v > 0) v = 0; }
    return [pos, v];
  };
  [s.x, s.vx] = side(s.x, s.vx, rect.x0, rect.x1); [s.y, s.vy] = side(s.y, s.vy, rect.y0, rect.y1);
  return s;
}
module.exports = { boundaryStep };
