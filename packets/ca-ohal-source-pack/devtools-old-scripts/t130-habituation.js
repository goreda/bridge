// t130: item 64 directive 5 REAL exercise (main 25 Oct: reactN=0 smoke is not proof).
// Scripted repeated separator contact on one subject cell, then a quiet window:
// hab must rise during contacts, the reflection response must soften (habF), and quiet must restore hab.
// Run twice - default (wasm pipeline) and ?nowasm=1 (JS pipeline) - on the SAME injected state.
// usage: node devtools/t130-habituation.js [harnessPath] [nowasm 0|1] [statePath]
const H = require(process.argv[2] ? require('path').resolve(process.argv[2]) : require('path').join(__dirname, 'harness.js'));
const NOWASM = +(process.argv[3] || 0), STATE = process.argv[4] || '';
(async () => {
  const T0 = Date.now(); const el = () => ((Date.now() - T0) / 1000).toFixed(1);
  const url = 'http://127.0.0.1:8913/index.html' + (NOWASM ? '?nowasm=1' : '');
  const s = await H.serve(8913), c = await H.launch(8912, url, ['--window-size=900,600']);
  const evG = async e => { const r = await Promise.race([c.ev(e), new Promise(r2 => setTimeout(() => r2('EV-TIMEOUT'), 30000))]); if (r === 'EV-TIMEOUT') console.error(el() + 's EV STALL'); return r; };
  const wait = async (e, n) => { for (let i = 0; i < (n || 40); i++) { if (await evG(e)) return true; await c.sleep(500); } return false; };
  if (!await wait('window.__ca2 && __ca2.cells > 10')) { console.log('BOOT FAIL'); process.exit(1); }
  console.error(el() + 's booted engine=' + (await evG('__ca2.WC && __ca2.WC.ok && !__ca2.WC.off && !__ca2.WC.simOff ? "wasm" : "js"')));
  await evG(`document.getElementById('panel').classList.add('hov')`);
  for (let i = 0; i < 25; i++) { if (!await evG('__ca2.trans')) break; await c.sleep(1000); }
  const inj = STATE && require('fs').existsSync(STATE) ? JSON.parse(require('fs').readFileSync(STATE, 'utf8')) : null;
  await evG(`(function(){
__ca2.setKey('fps', 60); __ca2.setKey('separatorOn', 1);
__ca2.setKey('foodGrow', 0); __ca2.setKey('foodShrink', 0); __ca2.setKey('divideOn', 0); __ca2.setKey('eatMergeOn', 0); __ca2.setKey('symbiogenesisOn', 0); __ca2.setKey('reproChance', 0);
var INJ = ${JSON.stringify(inj)};
if (INJ) { var cs0 = __ca2.getCells();
  while (cs0.length < INJ.cells.length) { var tp0 = cs0[cs0.length - 1], d0 = Object.create(Object.getPrototypeOf(tp0)); Object.assign(d0, tp0); d0.g = JSON.parse(JSON.stringify(tp0.g)); d0.shp = JSON.parse(JSON.stringify(tp0.shp)); cs0.push(d0); }
  INJ.cells.forEach(function (sc, i) { var c = cs0[i]; for (var k in sc) { if (k === 'g' || k === 'shp') c[k] = JSON.parse(JSON.stringify(sc[k])); else c[k] = sc[k]; } });
  cs0.length = INJ.cells.length;
  var fd0 = __ca2.getFood(); fd0.length = 0; INJ.food.forEach(function (f) { fd0.push({ x: f.x, y: f.y, r: f.r }); });
  __ca2.cont.x = INJ.cont.x; __ca2.cont.y = INJ.cont.y; __ca2.cont.w = INJ.cont.w; __ca2.cont.h = INJ.cont.h; __ca2.cont.tw = INJ.cont.w; __ca2.cont.th = INJ.cont.h; __ca2.cont.ew = INJ.cont.w; __ca2.cont.eh = INJ.cont.h; }
return 1; })()`);
  const out = await evG(`(function(){
var subj = null; __ca2.getCells().forEach(function (q) { if (!subj && q.alive) subj = q; });
var segs = (__ca2.axisInfo && __ca2.axisInfo.segs) || [];
if (!subj || !segs.length) return JSON.stringify({ err: 'nosubjorsegs', segs: segs.length });
var seg = segs[0], best = 0; segs.forEach(function (sg) { var L = Math.hypot(sg[2] - sg[0], sg[3] - sg[1]); if (L > best) { best = L; seg = sg; } });
var ex = seg[2] - seg[0], ey = seg[3] - seg[1], el2 = Math.hypot(ex, ey), nx = -ey / el2, ny = ex / el2;
var mx = (seg[0] + seg[2]) / 2, my = (seg[1] + seg[3]) / 2;
var SP = 4, NC = 12, contacts = [], k;
var r = subj.radius * Math.sqrt(Math.max(0, __ca2.P.metaballStrength) / Math.max(0.001, __ca2.P.THRESHOLD));
// scripted repeated contact against the REAL separatorPass (in-page code path, not a copy):
// each iteration places the subject just outside the segment with an inward velocity,
// steps it across, then calls the real pass - the crossing branch repositions and reflects.
for (k = 0; k < NC; k++) {
  var px = mx + nx * (r + 5), py = my + ny * (r + 5);
  subj.x = px; subj.y = py; subj._sepX = px; subj._sepY = py;
  subj.vx = -nx * SP; subj.vy = -ny * SP;
  subj.x = mx + nx * (r - 5); subj.y = my + ny * (r - 5);
  var vnB = subj.vx * nx + subj.vy * ny;
  __ca2.sepStep();
  var vnA = subj.vx * nx + subj.vy * ny;
  contacts.push({ k: k, hab: +(subj.hab || 0).toFixed(4), vnBefore: +vnB.toFixed(3), vnAfter: +vnA.toFixed(3), ratio: +Math.abs(vnA / vnB).toFixed(3), sqS: +(subj.sqS || 0).toFixed(3) });
}
var habAfterContacts = subj.hab || 0;
// quiet: far from every segment, no contact - hab must restore through the real pass
subj.x = mx + nx * (r + 800); subj.y = my + ny * (r + 800); subj._sepX = subj.x; subj._sepY = subj.y; subj.vx = 0; subj.vy = 0;
var quiet = [];
for (k = 0; k < 300; k++) { __ca2.sepStep(); if (k % 60 === 0) quiet.push(+(subj.hab || 0).toFixed(4)); }
return JSON.stringify({ engine: (__ca2.WC && __ca2.WC.ok && !__ca2.WC.off && !__ca2.WC.simOff) ? 'wasm' : 'js', bnd: +subj.g.bnd.toFixed(3), contacts: contacts, habAfterContacts: +habAfterContacts.toFixed(4), quiet: quiet, habEnd: +(subj.hab || 0).toFixed(4) });})()`);
  console.log(out);
  c.close(); s.close(); process.exit(0);

})();
