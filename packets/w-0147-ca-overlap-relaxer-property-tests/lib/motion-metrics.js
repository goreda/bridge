'use strict';
// Motion-trace metrics and deterministic replay comparison. trace: frames[] of Float64Array [x0,y0,x1,y1,...] (same item count each frame).
// motionMetrics(trace, {stallFrac}) -> {items, frames, stallFrames, dirFlips, meanStep, maxStep}; stall = step < stallFrac*item median step.
function motionMetrics(trace, opts) {
  if (opts == null || !(opts.stallFrac >= 0)) throw new TypeError('missing option: stallFrac');
  const F = trace.length; if (F < 2) throw new RangeError('need >= 2 frames');
  const N = trace[0].length / 2; let stall = 0, flips = 0, sum = 0, cnt = 0, mx = 0;
  for (let i = 0; i < N; i++) {
    const steps = [], dirs = [];
    for (let f = 1; f < F; f++) { const dx = trace[f][2 * i] - trace[f - 1][2 * i], dy = trace[f][2 * i + 1] - trace[f - 1][2 * i + 1]; steps.push(Math.hypot(dx, dy)); dirs.push([dx, dy]); }
    const med = steps.slice().sort((a, b) => a - b)[steps.length >> 1];
    steps.forEach(s => { if (s < opts.stallFrac * med) stall++; sum += s; cnt++; if (s > mx) mx = s; });
    for (let k = 1; k < dirs.length; k++) if (dirs[k][0] * dirs[k - 1][0] + dirs[k][1] * dirs[k - 1][1] < 0) flips++;
  }
  return { items: N, frames: F, stallFrames: stall, dirFlips: flips, meanStep: sum / cnt, maxStep: mx };
}
// replayCompare(a,b,{tol}) -> {identical, firstFrame, firstItem, maxAbs}; reports the first frame that differs by more than tol.
function replayCompare(a, b, opts) {
  if (opts == null || !(opts.tol >= 0)) throw new TypeError('missing option: tol');
  if (a.length !== b.length) throw new RangeError('frame count differs');
  let first = -1, fi = -1, max = 0;
  for (let f = 0; f < a.length; f++) {
    if (a[f].length !== b[f].length) throw new RangeError('item count differs at frame ' + f);
    for (let k = 0; k < a[f].length; k++) { const d = Math.abs(a[f][k] - b[f][k]); if (d > max) max = d; if (d > opts.tol && first < 0) { first = f; fi = k >> 1; } }
  }
  return { identical: first < 0, firstFrame: first, firstItem: fi, maxAbs: max };
}
module.exports = { motionMetrics, replayCompare };
