// CA2 - browser port of rr2ll2ia3target11.pde (sim, HUD, axis lines) with a redesigned config panel.
(function () {
  'use strict';
  var cv = document.getElementById('c'), cvg = document.getElementById('g');
  var ctx = cv.getContext('2d');
  var W = 0, H = 0, DPR = 1;
  // line layer: axis and boundary lines live on their own canvas at the exact device resolution (the plate canvas can run at a
  // different pixel ratio and would resample them). One effective width in whole device pixels feeds every line, CSS and canvas.
  var lnc = document.createElement('canvas'); lnc.id = 'ln'; document.body.appendChild(lnc); var lctx = lnc.getContext('2d'), DD = 1;
  function LW() { return P.axisWidth > 0 ? Math.max(1, Math.round(P.axisWidth * DD)) / DD : 0; }
  function snapC(c, S) { S = S || DD; var wd = Math.round(LW() * S), h = (wd % 2) / 2; return (Math.round(c * S - h) + h) / S; }
  function applyLW() { document.documentElement.style.setProperty('--lw', LW() + 'px'); }
  var rnd = function (a, b) { if (b === undefined) { b = a; a = 0; } return a + Math.random() * (b - a); };
  var clamp = function (v, a, b) { return v < a ? a : v > b ? b : v; };
  var lerp = function (a, b, t) { return a + (b - a) * t; };
  var map = function (v, a, b, c, d) { return c + (d - c) * (v - a) / (b - a); };
  function rand2D() { var a = Math.random() * 6.283185307; return { x: Math.cos(a), y: Math.sin(a) }; }

  // ---- parameters (names follow the pde) ----
  var P = {
    UNIVERSE_SIZE: 75, baseMutationRate: 5, mutationRateRange: 2, interactionRadius: 20, CELL_RADIUS: 10,
    GENE_MIN: -18, GENE_MAX: 18, minRadius: 5, maxRadius: 75, baseMaxSpeed: 10, maxSpeedVariation: 15,
    energyConsumptionRate: 0.058, energyGainFromInteraction: 0.004, minEnergyForReproduction: 0.22, reproMinAgeMs: 5000, reproChance: 0.02,
    THRESHOLD: 0.2, metaballStrength: 0.02, foodDensity: 0.025, foodEnergyValue: 5,
    minRefreshInterval: 10, maxRefreshInterval: 20, slowDownRadius: 20, speedReductionFactor: 50.3,
    grain: 1, grainAmount: 1, grainStrength: 4.8, grainSize: 1.2, grainSoft: 0.5, grainChroma: 0.5, grainDev: 0.4, grainFine: 0.25, grainCrystal: 0.4, grainCloud: 0.45, grainFps: 24, fps: 60, containerCorner: 18,
    bgColor: '', grainStock: 0, grainMono: 0, grainSkew: 0, grainResAdapt: 0, grainShadow: 1.8, grainMid: 1.5, grainHigh: 2.7, grainFineRatio: 0.5, grainCloudRatio: 2.2, grainDebug: 0, parasiteSize: 1,
    resolution: 1, margin: 28, gap: 14, textScale: 1, areaMin: 0.3, areaMax: 1,
    colorSpeed: 0.5, morphEase: 0.5, pixelRatio: 0, autoQuality: 1, showHud: 1, showAxis: 1, showFood: 0, axisLayer: 0, genomeOn: 1, genomeMut: 0.12, divideOn: 1, divideAt: 2.2, divideMode: 0, divideAgeMs: 20000, divideEnergy: 40, eatMergeOn: 1, eatRatio: 1.3, eatChance: 0.15, mergeChance: 0.03, mergeGene: 8, symbiosisOn: 1, symbiogenesisOn: 1, clusterCohesion: 0.35, clusterMax: 8, parasiteOn: 1, parasiteFrac: 0.06, parasiteDrain: 0.02, parasiteEff: 0.8, selectOn: 1, selStrength: 1, foodGrow: 1, foodGrowAmt: 0.6, foodGrowMax: 3, foodShrink: 0.01, cellMorph: 1, respawnMorph: 1, cellMorphMs: 1200, boundAware: 1, separatorOn: 0, boundGap: 0, boundZone: 70, boundForce: 0.8, centerGap: 18, diagLen: 0.9, axisWidth: 1, panelAlpha: 1, panelWidth: 340, blurWidth: 340, blurStrength: 16, panelRowGap: 11, spawnProtect: 1, cursorSens: 0.75, cursorSize: 1, cursorLockMs: 900, sprayMs: 120, sprayGapPx: 26, sprayBurst: 3, sprayRadius: 90, titleCircles: 1, circleHold: 1, titleLead: 1.3, titleTrack: 1,
    audioOn: 1, audioVol: 0.15, audioMode: 0, audioTone: 1600, audioMod: 0.6, audioCrackle: 0.5, audioWidth: 0.5, audioMicro: 0, audioMicroPitch: 1200, audioMicroDecay: 70, audioMicroRand: 0.5, foodColor: '#c86400', foodAlpha: 1, foodSize: 1, foodShow: 1, foodReseed: 1, foodReseedFloor: 0.2, foodReseedMin: 40, foodReseedMax: 900, foodReseedTries: 8, foodEatRate: 1.5, refreshResetEnergy: 1
  };
  // owner's chosen defaults (23:04)
  P.audioFadeMs = 5000;
  P.typeSlider = 1; P.cfgFont = 0; P.cfgFontSize = 13; P.cfgCase = 0; P.lineColor = '#111111'; P.autoInvert = 1; P.axisColor = ''; P.circColor = ''; P.ruleColor = ''; P.dragMargin = 8; P.edgeGrab = 10; P.restless = 0.8; P.edgeFit = 1; P.boundZoneR = 1.5; P.blobOutline = 1; P.plateOverlap = 0.25; P.parasiteHard = 12; P.parasiteSight = 4000; P.parasiteNerv = 0.6; P.parasiteHardMs = 20000; P.wallSmoothMs = 60; P.wallCarry = 1; P.wallSpread = 0.5; P.squashMax = 0.18; P.squashIn = 0.45; P.squashOut = 0.08; P.senseR = 1.6; P.senseSlow = 0.25; P.senseTurn = 0.12; P.senseDelay = 0.5; P.wallSubStep = 0.5; P.wallSubMax = 8; P.crowdGain = 0.12; P.crowdRel = 0.02; P.crowdSlow = 0.5; P.crowdPush = 0.3; P.habRate = 0.02; P.habDecay = 0.005; P.habMax = 0.6; P.solverIters = 0; P.solverOverlap = 1;
  P.foodMode = 2; P.foodBlobR = 70; P.foodBlobDots = 8; P.foodLife = 1; P.foodLifeMs = 300; P.foodLifeCell = 4; P.foodEatR = 0.4;
  Object.assign(P, {"UNIVERSE_SIZE": 55.95868745026389, "baseMutationRate": 9.628232288701716, "mutationRateRange": 2.6268439511457253, "interactionRadius": 12.016352372548786, "CELL_RADIUS": 34.57106164334512, "GENE_MIN": -18, "GENE_MAX": 18, "minRadius": 50, "maxRadius": 150, "baseMaxSpeed": 2, "maxSpeedVariation": 30, "energyConsumptionRate": 0.058, "energyGainFromInteraction": 0.004, "minEnergyForReproduction": 2.5, "THRESHOLD": 0.19, "metaballStrength": 0.024, "foodDensity": 0.023801395385356694, "foodEnergyValue": 20, "minRefreshInterval": 2, "maxRefreshInterval": 9, "slowDownRadius": 9, "speedReductionFactor": 37.5, "grain": 1, "grainAmount": 1.22, "grainStrength": 9.2, "grainSize": 0.3, "grainSoft": 0.82, "grainChroma": 1, "grainDev": 0.23, "grainFine": 0.25, "grainCrystal": 0.4, "grainCloud": 0.45, "grainFps": 12, "fps": 12, "containerCorner": 29, "resolution": 1, "margin": 10, "gap": 26, "textScale": 0.8, "areaMin": 0.1, "areaMax": 1, "colorSpeed": 0.74, "morphEase": 0.7, "pixelRatio": 2, "autoQuality": 1, "showHud": 1, "showAxis": 1, "showFood": 1, "axisLayer": 0, "genomeOn": 1, "genomeMut": 0.5, "divideOn": 1, "divideAt": 3, "eatMergeOn": 1, "eatRatio": 3, "eatChance": 1, "mergeChance": 0.03, "mergeGene": 8, "clusterCohesion": 0.35, "clusterMax": 10, "parasiteOn": 1, "parasiteFrac": 0.32, "parasiteDrain": 0.02, "parasiteEff": 1, "selectOn": 1, "selStrength": 4, "foodGrow": 1, "foodGrowAmt": 5, "foodGrowMax": 8, "foodShrink": 0.1, "cellMorph": 1, "respawnMorph": 1, "cellMorphMs": 2350, "boundAware": 1, "boundZone": 20, "boundForce": 3, "centerGap": 120, "diagLen": 0.83, "axisWidth": 2.3, "panelAlpha": 0, "panelWidth": 340, "blurWidth": 340, "cursorSens": 0.75, "cursorSize": 0.31, "cursorLockMs": 3000, "titleCircles": 1, "circleHold": 1, "audioOn": 1, "audioVol": 0.53, "audioMode": 1, "audioTone": 2120, "audioMod": 1, "audioCrackle": 1, "audioWidth": 1, "audioMicro": 3, "audioMicroPitch": 380, "audioMicroDecay": 400, "audioMicroRand": 1, "foodColor": "#000000", "foodAlpha": 1, "foodSize": 3.5, "foodShow": 0.51, "audioFadeMs": 5000, "dragMargin": 24, "edgeGrab": 20, "restless": 3, "edgeFit": 0.3, "boundZoneR": 0.1, "blobOutline": 1, "plateOverlap": 0.5, "parasiteHard": 39.5, "parasiteSight": 4000, "parasiteNerv": 1, "parasiteHardMs": 20000, "foodMode": 3, "foodBlobR": 70, "foodBlobDots": 8, "foodLife": 1, "foodLifeMs": 300, "foodLifeCell": 4, "foodEatR": 0.26});
  // eating radius is a fixed px distance, independent of cell radius (owner 20 Oct: no factor); migrate the stored factor with the preset radius
  P.foodEatR = Math.round(P.foodEatR * P.CELL_RADIUS * 100) / 100;
  // micro habitat (pilot): the nutrient cycle between cells and the food field - death returns biomass and colour to the
  // dots, and fed dots seed new small cells when the plate empties. Switch-gated, off by default. Every constant is a knob.
  P.habitatOn = 0; P.habitatFloor = 0; P.habitatFedMin = 20; P.habitatConv = 2; P.habitatSeedR = 0.5; P.habitatMut = 0.12;
  P.habitatSun = 1; P.habitatDeadFed = 6; P.habitatDeadR = 0.25; P.habitatDeadCol = 0.35; P.habitatHueK = 0.25;
  P.cellLife = 240; P.cellLifeVar = 0.3; // lifespan in s (0 = no aging): lightly on by default so natural death is part of the cycle; spread is the per-cell jitter
  P.habitatReapOn = 1; P.habitatReapK = 0.5; P.habitatFedShow = 0.12; // corpse->nutrient recycling is visible by default (reap leg only, reduced intensity); fed dots draw larger
  P.habitatFedDecay = 0.2; // fed decays per second: corpses are a pulse, not a permanent reservoir
  P.habitatBirthCap = 2; P.habitatNiches = 4; P.habitatNicheSun = 0.5; P.habitatNicheMix = 1; // soft birth cap (x UNIVERSE_SIZE), niche grid per axis, regional sun spread, edge smoothing
  P.habitatDrift = 0.02; P.habitatDriftAmp = 0.3; P.habitatDriftFloor = 0.2; // slow environment drift: cycles/s, amplitude, sun multiplier floor
  // formerly hardcoded biological constants (owner 21 Oct: every biological parameter adjustable). Defaults = the old constants.
  P.crowdTol = 0.5; P.orgLifeDie = -0.005; P.orgLifeGrow = 1.0025; P.orgBirth = 1.005; P.orgDead = -0.0025; P.orgBrain = 0.008; P.orgR90 = 0.0025;
  P.symEnergy = 0.00075; P.symBreak = 0.0002; P.symBreakDist = 3; P.eatDistF = 0.85; P.fuseDistF = 0.6; P.symDistF = 1.1;
  P.focusIdleMs = 4000; P.focusInMs = 4000; P.focusOutMs = 380; P.focusDepth = 14; // idle depth-of-field blur: wait, slow blur-in, swift refocus, depth px
  P.cellShapes = 1; // heritable body plans: round / string / lobed (render expands a cell into metaball sources)
  var DEFAULTS = JSON.parse(JSON.stringify(P));
  var TYPE_SIZE_MAX = 4; // the type-size KNOB range end (owner 21 Oct); manual entry is unbounded (the width fit is the only limit)
  // params locked against the OLD wild re-roll by default (Main 22:03, refined 22:05): morph cycles re-deal untouched keys inside measured healthy bands (bounded variety), never the wild ranges; admin panel unlock = wild; stale lockParams:false saves are not restored (see load below)
  var autoRefresh = true, lockParams = true;
  var BGS = [[233,233,233],[22,22,22],[255,0,0],[0,255,0],[0,0,255]];
  // title-circle hover colors: the palette's own black (22,22,22 - not pitch black) and white, plus its R G B (owner 21 Oct)
  var CIRCLE_COLS = [[22,22,22],[255,255,255],[255,0,0],[0,255,0],[0,0,255]];
  var bgIndex = 0, bg = [255,255,255], bgTarget = [233,233,233];
  
  var ready = false, parasites = [], clusterSeq = 0, env = { spd: 1, app: 0.5, bnd: 1, col: null }, cmean = {};
  var cells = [], food = [], ev = { birth: 0, death: 0, hit: 0, oob: 0 }, maxOut = 0;
  // Death-site recorder (item 64, main 25 Oct): each kill path tags the cell, each reap logs the actual reason and the exact at-death state - no inference from last-seen samples. Debug fields never touch sim math.
  var deathLog = [];
  function logDeath(c, reason) { deathLog.push({ ti: c.__ti === undefined ? -1 : c.__ti, t: Math.round(frameT || 0), reason: reason, e: +(c.energy || 0).toFixed(2), age: Math.round(c.age || 0), life: Math.round(c.life || 0), gene: +(c.gene || 0).toFixed(2), x: Math.round(c.x), y: Math.round(c.y) }); if (deathLog.length > 400) deathLog.shift(); }
  var cont = { x: 0, y: 0, w: 0, h: 0, tw: 0, th: 0, ew: 0, eh: 0, rawW: 0, rawH: 0, wvx0: 0, wvx1: 0, wvy0: 0, wvy1: 0 };
  var mouse = { x: 0, y: 0, over: false };
  var hovering = false, hoverCol = [255,255,255];
  var refreshInterval = 10, lastRefresh = performance.now();
  var keyHeld = '';
  var eased = { total: [0,0,0,1], title: [0,0,0,1], coor: [0,0,0,1], axis: [0,0,0,1], r: [255,0,0,1], g: [0,255,0,1], b: [0,0,255,1] };
  var fps = 0;

  // ---- cells ----
  function Cell(x, y, gene, mr) {
    this.x = x; this.y = y; var v = rand2D(); this.popD = UI_END + Math.random() * (CELL_END - UI_END);
    this.sv = rnd(-1, 1); this.maxSpeed = Math.max(0, P.baseMaxSpeed + this.sv * P.maxSpeedVariation);
    this.vx = v.x * this.maxSpeed; this.vy = v.y * this.maxSpeed;
    this.gene = gene; this.alive = true; this.radius = P.CELL_RADIUS; this.energy = 12; this.mutationRate = mr;
    this.hostility = Math.random(); this.speedModifier = rnd(0.7, 2.3); this.envVx = 0; this.envVy = 0; // environmental velocity (item 64 directive 3): wall/crowd-imparted motion, not self-propulsion
    var k0 = gene > 2 ? 0 : gene < -2 ? 1 : 2, cv = [0.12, 0.12, 0.12]; cv[k0] = 0.76;
    this.g = { spd: 1 + rnd(-0.3, 0.3), app: rnd(0.05, 0.95), bnd: 1 + rnd(-0.4, 0.4), col: normCol([cv[0] + rnd(0, 0.1), cv[1] + rnd(0, 0.1), cv[2] + rnd(0, 0.1)]) };
    this.cl = 0; this.maxSpeed = this.maxSpeed * (P.genomeOn ? this.g.spd : 1); this.shp = newShape(null); this.bornAt = frameT || 0;
    this.age = 0; this.life = P.cellLife > 0 ? Math.max(1, P.cellLife * (1 + rnd(-P.cellLifeVar, P.cellLifeVar))) : 0;
  }
  function normCol(v) { var s = v[0] + v[1] + v[2] || 1; return [v[0] / s, v[1] / s, v[2] / s]; }
  function speedOf(c) { return Math.max(0, P.baseMaxSpeed + c.sv * P.maxSpeedVariation) * (P.genomeOn ? c.g.spd : 1); }
  function mutGenome(g, a) {
    return { spd: clamp(g.spd * (1 + rnd(-a, a)), 0.5, 1.6), app: clamp(g.app + rnd(-a, a), 0, 1), bnd: clamp(g.bnd * (1 + rnd(-a, a)), 0.5, 2),
      col: normCol([Math.max(0.001, g.col[0] + rnd(-a, a) * 0.5), Math.max(0.001, g.col[1] + rnd(-a, a) * 0.5), Math.max(0.001, g.col[2] + rnd(-a, a) * 0.5)]) };
  }
  function mixGenome(a, b) { return { spd: (a.spd + b.spd) / 2, app: (a.app + b.app) / 2, bnd: (a.bnd + b.bnd) / 2, col: normCol([(a.col[0] + b.col[0]) / 2, (a.col[1] + b.col[1]) / 2, (a.col[2] + b.col[2]) / 2]) }; }
  // ---- body plans: round (0) and lobed (2). Legacy string (1) is no longer born or inherited: its separated source discs looked like a train.
  // Heritable, mutates with genomeMut; only the renderer sees the plan (a cell becomes several metaball sources).
  function newShape(par) {
    if (par && par.t === 1) par = Object.assign({}, par, { t: 2, asp: 1, th: 1, wig: 0, sat: Math.max(2, par.sat || 0) });
    if (!par) {
      var u = Math.random();
      if (u < 0.35) return { t: 0, asp: 1, th: 1, wig: 0, wsp: 1, sat: 0, ph: rnd(6.2832), ph2: rnd(6.2832), dir: rnd(6.2832) };
      return { t: 2, asp: 1, th: 1, wig: 0, wsp: rnd(0.3, 1.4), sat: 2 + (Math.random() < 0.4 ? 1 : 0), ph: rnd(6.2832), ph2: rnd(6.2832), dir: rnd(6.2832) };
    }
    var a = P.genomeMut, s = { t: par.t, asp: par.asp, th: par.th, wig: par.wig, wsp: par.wsp, sat: par.sat, ph: rnd(6.2832), ph2: rnd(6.2832), dir: par.dir };
    if (Math.random() < a * 0.4) s.t = Math.random() < 0.5 ? 0 : 2; // a rare body-plan jump
    s.asp = clamp(s.asp * (1 + rnd(-a, a)), 1.15, 7); s.th = clamp(s.th * (1 + rnd(-a, a) * 0.6), 0.25, 1.1);
    s.wig = clamp(s.wig + rnd(-a, a) * 0.8, 0, 1.4); s.wsp = clamp(s.wsp * (1 + rnd(-a, a) * 0.5), 0.2, 2.5);
    if (s.t === 0) { s.asp = 1; s.th = 1; s.wig = 0; }
    if (s.t === 1 && s.asp < 1.25) s.asp = 1.3;
    if (s.t === 2 && !s.sat) s.sat = 2 + (Math.random() < 0.4 ? 1 : 0);
    return s;
  }
  function mixShape(a2, b2) {
    if (!a2) return b2 ? newShape(b2) : newShape(null); if (!b2) return newShape(a2);
    var s = newShape(a2); s.t = Math.random() < 0.5 ? a2.t : b2.t; if (s.t === 1) s.t = 2;
    s.asp = (a2.asp + b2.asp) / 2; s.th = (a2.th + b2.th) / 2; s.wig = (a2.wig + b2.wig) / 2; s.wsp = (a2.wsp + b2.wsp) / 2; s.sat = Math.max(a2.sat || 0, b2.sat || 0);
    if (s.t === 1 && s.asp < 1.25) s.asp = 1.3;
    if (s.t === 2 && !s.sat) s.sat = 2;
    return s;
  }
  // fitness against the current environment (0 = perfectly adapted, 1 = far off). A refresh draws a new environment.
  function misfit(c) {
    var e = env, g = c.g, m = (Math.abs(g.spd - e.spd) / 1.1 + Math.abs(g.app - e.app) + Math.abs(g.bnd - e.bnd) / 1.5) / 3;
    if (e.col) { var cd = (Math.abs(g.col[0] - e.col[0]) + Math.abs(g.col[1] - e.col[1]) + Math.abs(g.col[2] - e.col[2])) / 2; m = (m * 3 + cd * 1.5) / 4.5; }
    return Math.min(1, m);
  }
  function newEnv() { env = { spd: rnd(0.7, 1.35), app: rnd(0.2, 0.9), bnd: rnd(0.7, 1.6), col: normCol([rnd(0.05, 1), rnd(0.05, 1), rnd(0.05, 1)]) }; }
  function limit(c, m) { var s = Math.hypot(c.vx, c.vy); if (s > m && s > 0) { c.vx *= m / s; c.vy *= m / s; } }
  function mutateGene(g) {
    var r = Math.random(), a;
    if (r < 0.26) a = Math.random() < 0.5 ? -1 : 1; else if (r < 0.9) a = Math.random() < 0.5 ? -2 : 2; else a = Math.random() < 0.5 ? -3 : 3;
    return clamp(g + a, P.GENE_MIN, P.GENE_MAX);
  }
  function organic(c) {
    var n = 0, left = null, right = null, R = P.interactionRadius;
    for (var i = 0; i < cells.length; i++) {
      var o = cells[i]; if (o === c || !o.alive) continue;
      var dx = o.x - c.x, dy = o.y - c.y;
      if (dx * dx + dy * dy < R * R) {
        n++;
        if (o.x < c.x && (!left || o.x > left.x)) left = o;
        if (o.x > c.x && (!right || o.x < right.x)) right = o;
      }
    }
    var life = c.alive ? ((n < 2 || n > 3) ? P.orgLifeDie : P.orgLifeGrow) : (n === 3 ? P.orgBirth : P.orgDead);
    var brain = n === 2 ? P.orgBrain : 0;
    var r90 = ((left ? 1 : 0) ^ (right ? 1 : 0)) ? P.orgR90 : 0;
    var d = rand2D(), t = life + brain + r90 + rnd(-0.1, 0.1);
    c.vx += d.x * t; c.vy += d.y * t;
    var q = rand2D(); c.vx = lerp(c.vx, q.x * c.maxSpeed, 0.04); c.vy = lerp(c.vy, q.y * c.maxSpeed, 0.04);
    limit(c, c.maxSpeed * (resizeDrag ? 1 + P.restless * 1.5 : 1));
  }
  function update(c) {
    if (!c.alive) return;
    var dm = Math.hypot(c.x - mouse.x, c.y - mouse.y), sm = dm < P.slowDownRadius ? P.speedReductionFactor : 1;
    var r = rand2D(); c.vx += r.x * 0.2 * sm; c.vy += r.y * 0.2 * sm;
    limit(c, c.maxSpeed * sm * c.speedModifier * (resizeDrag ? 1 + P.restless * 1.5 : 1));
    organic(c);
    c.x += c.vx + c.envVx; c.y += c.vy + c.envVy; // intrinsic (maxSpeed-limited) + environmental (item 64 directive 3): the wall/crowd-imparted channel bypasses the self-propulsion limit
    var edk = Math.pow(0.75, frameDtf * 0.06); c.envVx *= edk; c.envVy *= edk; // and the medium absorbs it (60fps-reference easing, 1:1 sim.rs update)
    if (c.shp && c.shp.t === 1) { // a string turns into its drift and swims with a side-to-side wave
      var sh2 = c.shp; sh2.svx = (sh2.svx || 0) * 0.94 + c.vx * 0.06; sh2.svy = (sh2.svy || 0) * 0.94 + c.vy * 0.06;
      var spv = Math.hypot(sh2.svx, sh2.svy);
      if (spv > 0.15) { var wa = Math.atan2(sh2.svy, sh2.svx), daa = wa - sh2.dir; while (daa > 3.1416) daa -= 6.2832; while (daa < -3.1416) daa += 6.2832; sh2.dir += daa * 0.12; }
      var swk = Math.sin(performance.now() / 700 * (1 + sh2.wsp) + sh2.ph) * sh2.wig * 0.05 * (c.maxSpeed * 0.4 + 0.4);
      c.vx += -Math.sin(sh2.dir) * swk; c.vy += Math.cos(sh2.dir) * swk;
      var vv = Math.hypot(c.vx, c.vy); if (vv > 0.05) { c.vx = lerp(c.vx, Math.cos(sh2.dir) * vv, 0.04); c.vy = lerp(c.vy, Math.sin(sh2.dir) * vv, 0.04); } // it swims where it points
    }
    var cm = c.cl && P.eatMergeOn ? cmean[c.cl] : null;
    c.energy -= P.energyConsumptionRate * (cm ? 0.85 : 1);
    if (P.selectOn && P.genomeOn) { var mf = misfit(c); c.energy -= P.selStrength * mf * 0.05; if (Math.random() < P.selStrength * 0.005 * Math.pow(mf, 1.5)) { c.alive = false; c.__dr = 'select'; } }
    if (c.energy <= 0) { c.alive = false; c.__dr = 'energy0'; }
    if (cm) {
      var ch = P.clusterCohesion; c.vx = lerp(c.vx, cm.vx, ch); c.vy = lerp(c.vy, cm.vy, ch);
      c.vx += (cm.x - c.x) * 0.01 * ch; c.vy += (cm.y - c.y) * 0.01 * ch; c.energy += (cm.e - c.energy) * 0.05;
    }
    // symbiosis: a bonded pair shares its motion and keeps its distance; the bond feeds both a little and ends
    // when a partner dies, when they drift too far apart, or on a whim
    if (P.symbiosisOn) {
      var sp = c.sym;
      if (sp && (!sp.alive || sp.sym !== c || Math.random() < P.symBreak)) { if (sp.alive && sp.sym === c) sp.sym = null; c.sym = null; }
      else if (sp) {
        var sdx = sp.x - c.x, sdy = sp.y - c.y, sdd = Math.hypot(sdx, sdy) || 1, sw = (c.radius + sp.radius) * 1.4;
        if (sdd > sw * P.symBreakDist) { sp.sym = null; c.sym = null; }
        else {
          var coh2 = P.clusterCohesion * 0.25;
          c.vx = lerp(c.vx, sp.vx, coh2); c.vy = lerp(c.vy, sp.vy, coh2);
          c.vx += sdx / sdd * (sdd - sw) * 0.004; c.vy += sdy / sdd * (sdd - sw) * 0.004;
          c.energy += P.symEnergy;
        }
      }
    } else if (c.sym) c.sym = null;
    var reach = P.genomeOn ? c.radius * (2 + 6 * c.g.app) : 0, bestD = 1e9, bx = 0, by = 0;
    for (var i = food.length - 1; i >= 0; i--) {
      var fd = Math.hypot(c.x - food[i].x, c.y - food[i].y);
      if (fd >= P.foodEatR && fd < reach && fd < bestD) { bestD = fd; bx = food[i].x; by = food[i].y; }
      // eating range reaches from the body EDGE inward: the old centre-based test (foodEatR px from the centre) never fired for bodies larger than foodEatR (owner 21 Oct: cells do not eat)
      if (fd < c.radius + P.foodEatR && Math.random() < 1 - Math.exp(-frameDtf * P.foodEatRate / 1000)) { c.energy += P.foodEnergyValue; habAte(food[i]); food[i].gone = 1; food.splice(i, 1); ev.ate = (ev.ate || 0) + 1; if (P.foodGrow) c.radius = Math.min(c.radius + P.foodGrowAmt, P.CELL_RADIUS * P.foodGrowMax); }
      // grazing rate above: a touched dot is taken at foodEatRate dots/s, not in the same frame (measured eat vacuum)
    }
    if (reach && bestD < 1e9) { c.vx += (bx - c.x) / bestD * 0.5 * c.g.app * (c.maxSpeed * 0.1 + 0.2); c.vy += (by - c.y) / bestD * 0.5 * c.g.app * (c.maxSpeed * 0.1 + 0.2); }
    if (P.divideOn && P.foodGrow && cells.length < Math.max(60, P.UNIVERSE_SIZE * 4) && c.energy > 1) { // divideMode 1: age+mass accumulation instead of the radius threshold (architect 21 Oct: the radius gate is structurally dead)
      if (P.divideMode ? (frameT - (c.bornAt || 0) >= P.divideAgeMs && c.energy >= P.divideEnergy) : (c.radius >= P.CELL_RADIUS * P.divideAt)) divide(c);
    }
    if (P.foodGrow && c.radius > P.CELL_RADIUS) c.radius = Math.max(P.CELL_RADIUS, c.radius - P.foodShrink);
    if (P.boundAware) keepIn(c);
    else if (c.x < cont.x || c.x > cont.x + cont.w || c.y < cont.y || c.y > cont.y + cont.h) { c.alive = false; c.__dr = 'oob'; ev.oob++; }
  }
  // item 64 directive 3: extra keepIn passes along the interpolated wall path (see frame()).
  // Named for testability: t129 drives it directly against JS and wasm cell states.
  function wallSubPass(subN, x0f, y0f, w0f, h0f) {
    var fx3 = cont.x, fy3 = cont.y, fw3 = cont.w, fh3 = cont.h;
    for (var sb3 = 1; sb3 <= subN; sb3++) { var st3 = sb3 / subN;
      cont.x = x0f + (fx3 - x0f) * st3; cont.y = y0f + (fy3 - y0f) * st3; cont.w = w0f + (fw3 - w0f) * st3; cont.h = h0f + (fh3 - h0f) * st3;
      for (var ci3 = 0; ci3 < cells.length; ci3++) { var cs3 = cells[ci3]; if (cs3.alive) keepIn(cs3); } }
    cont.x = fx3; cont.y = fy3; cont.w = fw3; cont.h = fh3;
  }
  // item 64 directive 6: one constraint solver per substep for plate walls, separator segments and cell
  // overlap together (solverIters iterations), instead of passes that undo each other: every iteration
  // applies all three constraint families, so they converge instead of fighting. Positional only -
  // velocity reflection stays in keepIn/separatorPass. Post-pass after both engines (1:1 by construction).
  function constraintSolver() {
    var iters = P.solverIters === undefined ? 0 : P.solverIters; if (iters < 1) return;
    var segs = P.separatorOn && P.showAxis && axisInfo.segs ? axisInfo.segs : null;
    var ov = P.solverOverlap === undefined ? 1 : P.solverOverlap;
    var gap = Math.max(0, P.boundGap || 0), x0 = cont.x + gap, x1 = cont.x + cont.w - gap, y0 = cont.y + gap, y1 = cont.y + cont.h - gap;
    for (var it = 0; it < iters; it++) {
      var moved = false, i, j, c;
      for (i = 0; i < cells.length; i++) {
        c = cells[i]; if (!c.alive) continue;
        if (it === 0) c.__solverPr = 0;
        var r = c.radius * Math.sqrt(Math.max(0, P.metaballStrength) / Math.max(0.001, P.THRESHOLD)) + Math.min(LW(), 1 / DD) / 2;
        if (segs) { // combined normals (a wedge pushed along the sum drifts out; per-segment ping-pongs forever)
          var acx = 0, acy = 0, worst = 0, anyV = false;
          for (j = 0; j < segs.length; j++) {
            var sg = segs[j], ax = sg[2] - sg[0], ay = sg[3] - sg[1], L2 = ax * ax + ay * ay, t = L2 ? clamp(((c.x - sg[0]) * ax + (c.y - sg[1]) * ay) / L2, 0, 1) : 0;
            var px = sg[0] + ax * t, py = sg[1] + ay * t, dx = c.x - px, dy = c.y - py, d = Math.hypot(dx, dy);
            if (d < r) {
              var nx2, ny2;
              if (d < 0.001) { nx2 = -ay; ny2 = ax; var nl2 = Math.hypot(nx2, ny2) || 1; nx2 /= nl2; ny2 /= nl2; if (c.vx * nx2 + c.vy * ny2 < 0) { nx2 = -nx2; ny2 = -ny2; } }
              else { nx2 = dx / d; ny2 = dy / d; }
              var need = r - d; acx += nx2 * need; acy += ny2 * need; if (need > worst) worst = need; anyV = true;
              var pr2 = need / r; if (pr2 > c.__solverPr) c.__solverPr = pr2; // pressure read by separatorPass for squash/crowd/habituation
            }
          }
          if (anyV) { var al = Math.hypot(acx, acy); if (al >= 0.001) { var st = Math.min(al, worst + 1); c.x += acx / al * st; c.y += acy / al * st; moved = true; } }
        }
      }
      if (ov > 0) for (i = 0; i < cells.length; i++) { var a2 = cells[i]; if (!a2.alive) continue;
        for (j = i + 1; j < cells.length; j++) { var b2 = cells[j]; if (!b2.alive) continue;
          var ddx = b2.x - a2.x, ddy = b2.y - a2.y, dd = Math.hypot(ddx, ddy), rr = (effR(a2) + effR(b2)) * 1;
          var over = rr - dd; if (over <= 0 || dd <= 0.0001) continue;
          var sqm = P.squashMax === undefined ? 0.18 : P.squashMax, allow = rr * sqm; // directive 2: interpenetration up to the squash depth is ABSORBED as eased squash, not flung apart (v3)
          if (over <= allow) { var sq2 = over / rr / Math.max(0.001, sqm); if (sq2 > (a2.sqS || 0)) a2.sqS = sq2; if (sq2 > (b2.sqS || 0)) b2.sqS = sq2; continue; }
          var push = (over - allow) / 2 * ov, ux = ddx / dd, uy = ddy / dd; a2.x -= ux * push; a2.y -= uy * push; b2.x += ux * push; b2.y += uy * push; moved = true;
          if (1 > (a2.sqS || 0)) a2.sqS = 1; if (1 > (b2.sqS || 0)) b2.sqS = 1; // past the squash depth: full press reads as full squash
        }
      }
      for (i = 0; i < cells.length; i++) { // the wall wins last: overlap separation may push a body out of the plate, so the clamp closes every iteration
        c = cells[i]; if (!c.alive) continue;
        var pen = 0; // directive 2: wall contact reads as squash pressure, not a silent position write
        if (c.x < x0) { pen = x0 - c.x; c.x = x0; moved = true; } else if (c.x > x1) { pen = c.x - x1; c.x = x1; moved = true; }
        if (c.y < y0) { pen = Math.max(pen, y0 - c.y); c.y = y0; moved = true; } else if (c.y > y1) { pen = Math.max(pen, c.y - y1); c.y = y1; moved = true; }
        if (pen > 0) { var sq3 = Math.min(1, pen / Math.max(1, c.radius)); if (sq3 > (c.sqS || 0)) c.sqS = sq3; }
      }
      if (!moved) break;
    }
  }
  // boundary awareness: a soft push inside the zone turns cells before the wall; the wall itself reflects (flat world, no death at the edge)
  function keepIn(c) {
    // the wall acts on the cell's edge, not its centre: the radius inset is automatic. The zone is the boundary distance knob only, independent of cell radius (owner 20 Oct)
    var gap = Math.max(0, P.boundGap || 0), r = 0; // zone/sensing geometry stays centre-based and radius-independent (owner 20 Oct); the contact clamp (wallPull below) uses the eased squashed radius effR - architect finding (c)
    var z = Math.max(0, Math.min(P.boundZone * (P.genomeOn ? c.g.bnd : 1), cont.w / 2.5, cont.h / 2.5)), F = P.boundForce, ms = c.maxSpeed + 1;
    var x0 = cont.x + r + gap, x1 = cont.x + cont.w - r - gap, y0 = cont.y + r + gap, y1 = cont.y + cont.h - r - gap, d, t, press = 0;
    d = c.x - x0; if (d < z) { t = clamp(1 - d / z, 0, 1); c.vx += F * t * t * ms * 0.25; if (c.vx < 0) c.vx *= 1 - 0.25 * t; if (t > press) press = t; }
    d = x1 - c.x; if (d < z) { t = clamp(1 - d / z, 0, 1); c.vx -= F * t * t * ms * 0.25; if (c.vx > 0) c.vx *= 1 - 0.25 * t; if (t > press) press = t; }
    d = c.y - y0; if (d < z) { t = clamp(1 - d / z, 0, 1); c.vy += F * t * t * ms * 0.25; if (c.vy < 0) c.vy *= 1 - 0.25 * t; if (t > press) press = t; }
    d = y1 - c.y; if (d < z) { t = clamp(1 - d / z, 0, 1); c.vy -= F * t * t * ms * 0.25; if (c.vy > 0) c.vy *= 1 - 0.25 * t; if (t > press) press = t; }
    // item 64: the boundary causes no permanent size loss - pressure reads as the eased squash
    // state (stepSquash/emitCell), the radius itself is never worn at a wall
    if (press > (c.sqS || 0)) c.sqS = press;
    // item 64 directive 1: sensing before contact. In the band [z, z*senseR) the cell slows and turns
    // along the wall; onset is staggered by a deterministic per-cell hash (gene+maxSpeed, no RNG):
    // no two cells react identically and never in one row. Inside z the hard push above owns the reaction.
    var zs = z * (P.senseR === undefined ? 1.6 : P.senseR);
    if (zs > z + 0.001 && (P.senseSlow || P.senseTurn)) {
      var h1 = c.gene * 0.6180339887; h1 -= Math.floor(h1);
      var h2 = c.maxSpeed * 0.7548776662; h2 -= Math.floor(h2);
      var sDel = h1 * (P.senseDelay === undefined ? 0.5 : P.senseDelay), sSl = P.senseSlow, sTu = P.senseTurn;
      for (var si = 0; si < 4; si++) {
        var sd = si === 0 ? c.x - x0 : si === 1 ? x1 - c.x : si === 2 ? c.y - y0 : y1 - c.y;
        if (sd >= zs || sd < z) continue;
        var st0 = 1 - sd / zs, st = clamp((st0 - sDel) / Math.max(1e-6, 1 - sDel), 0, 1); if (st <= 0) continue;
        var damp = 1 - sSl * st, tdr = sTu * st * ms * (h2 < 0.5 ? -1 : 1) * 0.5;
        if (si < 2) { c.vx *= damp; c.vy += tdr; } else { c.vy *= damp; c.vx += tdr; }
      }
    }
    // item 64 directive 4: crowding is a field with memory - wall/separator pressure builds it (fast in),
    // quiet releases it (slow out): squeezed cells slow and drift along the pressed edge toward its roomier
    // middle; the easing spreads the release like a crowd, not a burst. 1:1 in sim.rs keep_in.
    var cg = P.crowdGain === undefined ? 0.12 : P.crowdGain;
    if (cg > 0) {
      var ek2 = frameDtf * 0.06, kg = 1 - Math.pow(1 - cg, ek2), kr = 1 - Math.pow(1 - (P.crowdRel === undefined ? 0.02 : P.crowdRel), ek2);
      var cd0 = c.crowd || 0;
      c.crowd = press > cd0 ? cd0 + (press - cd0) * kg : cd0 - cd0 * kr;
      if (c.crowd > 0.001) {
        var csl = 1 - (P.crowdSlow === undefined ? 0.5 : P.crowdSlow) * Math.min(1, c.crowd);
        c.vx *= csl; c.vy *= csl;
        if (press > 0) {
          var cpush = (P.crowdPush === undefined ? 0.3 : P.crowdPush) * Math.min(1, c.crowd) * ms * 0.5, midX = (x0 + x1) / 2, midY = (y0 + y1) / 2;
          if (c.x - x0 < z || x1 - c.x < z) c.envVy += cpush * (c.y < midY ? 1 : -1); // crowd drift is environment-imparted (directive 4): pressed bodies drift even without self-propulsion
          if (c.y - y0 < z || y1 - c.y < z) c.envVx += cpush * (c.x < midX ? 1 : -1);
        }
      }
    }
    wallPull(c, effR(c), true); // the shared boundary-morph rule at the ONE eased squashed radius the render draws (architect finding (c): no centre-line clamp, no one-frame deflate/inflate); owner 22 Oct holds - nothing crosses, nothing clips (contact body == drawn body), pressed bodies squeeze at the wall; cells add velocity reflection
  }
  // the boundary-morph rule for ANY body: a wall that moved past it pulls it back gradually (no teleport);
  // a plain wall hit reflects. Shared by cells (keepIn) and every food kind (owner 21 Oct: one mechanism, no copies)
  function wallPull(p, r, vel) {
    // absolute wall (owner 22 Oct): nothing is ever outside, in any state - a wall that moved past a body
    // carries it (that carry IS the sweep), a plain hit reflects. Supersedes the 21 Oct gradual no-teleport pull.
    // Wall push (owner 25 Oct block 73d-1): a wall that advanced past a body resolves it to the contact
    // line and pushes it as a force (impulse proportional to the overrun depth) - it does not carry the
    // body with it; a hit with a static wall reflects at 0.7 as before.
    var gap = Math.max(0, P.boundGap || 0), rFit = Math.max(8, Math.min(cont.w, cont.h) / 2 - gap), rr = Math.min(r, rFit);
    var x0 = cont.x + rr + gap, x1 = cont.x + cont.w - rr - gap, y0 = cont.y + rr + gap, y1 = cont.y + cont.h - rr - gap;
    if (x1 < x0) { x0 = x1 = (x0 + x1) / 2; }
    if (y1 < y0) { y0 = y1 = (y0 + y1) / 2; }
    // 73d(1) anticipation: an inward-moving wall pushes each body in its path BEFORE contact - per-cell, local,
    // ramp over one own-radius to at most the wall's own speed through the decaying env channel; the contact resolve stays as the fallback
    if (P.wallCarry > 0 && vel) {
      var antR = rr;
      if (cont.wvx0 > 0 && p.x >= x0 && p.x - x0 < antR) { var kA = 1 - (p.x - x0) / antR; p.envVx += (Math.abs(cont.wvx0) * P.wallCarry - p.envVx) * kA; }
      if (cont.wvx1 < 0 && p.x <= x1 && x1 - p.x < antR) { var kB = 1 - (x1 - p.x) / antR; p.envVx += (-Math.abs(cont.wvx1) * P.wallCarry - p.envVx) * kB; }
      if (cont.wvy0 > 0 && p.y >= y0 && p.y - y0 < antR) { var kC = 1 - (p.y - y0) / antR; p.envVy += (Math.abs(cont.wvy0) * P.wallCarry - p.envVy) * kC; }
      if (cont.wvy1 < 0 && p.y <= y1 && y1 - p.y < antR) { var kD = 1 - (y1 - p.y) / antR; p.envVy += (-Math.abs(cont.wvy1) * P.wallCarry - p.envVy) * kD; }
    }
    if (p.x < x0) carrySide(p, 'x', 'vx', p.y, x0, cont.wvx0, 1, vel);
    else if (p.x > x1) carrySide(p, 'x', 'vx', p.y, x1, cont.wvx1, -1, vel);
    if (p.y < y0) carrySide(p, 'y', 'vy', p.x, y0, cont.wvy0, 1, vel);
    else if (p.y > y1) carrySide(p, 'y', 'vy', p.x, y1, cont.wvy1, -1, vel);
  }
  // item 64 directive 2: one eased squash state per cell. The target is PRESSURE SIGNALS ONLY (piston
  // carry, zone press, separator/solver overload via sqS, the crowding field) - a geometric target
  // deflates/inflates the body within one frame and freezes squash at a resting wall (architect finding c).
  // Pressure rises fast (squashIn); when the pressure ends the body regains its pre-squeeze size over time
  // (squashOut), and the recovered depth pushes it off a touching wall as environmental recoil, not
  // self-propulsion: when the wall withdraws, squeezed bodies spread back out like a released crowd, not
  // as a burst (directives 3+4). Runs once per frame in frame() for BOTH engines (post-pass, 1:1 by
  // construction) - never draw-side.
  function stepSquash() {
    var g2 = Math.max(0, P.boundGap || 0), sqm = P.squashMax === undefined ? 0.18 : P.squashMax;
    for (var i = 0; i < cells.length; i++) {
      var c = cells[i]; if (!c.alive) continue;
      var sq0 = c.sq || 0;
      var tg = Math.max(c.sqS || 0, P.boundAware ? Math.min(1, c.crowd || 0) : 0);
      var ek = frameDtf * 0.06, rate = tg > sq0 ? P.squashIn : P.squashOut; // easing per elapsed time at a 60fps reference: 12fps and 60fps run the same biology (item 64)
      c.sq = sq0 + (tg - sq0) * (1 - Math.pow(1 - rate, ek));
      if (c.sq < sq0) { // the recovered squash depth is a length: expanding against a touching wall pushes the body off it by exactly that length
        var bx = c.x - cont.x - g2, by = c.y - cont.y - g2;
        var dL = bx, dR = cont.w - g2 - bx, dT = by, dB = cont.h - g2 - by, dm = Math.min(dL, dR, dT, dB), push = (sq0 - c.sq) * c.radius * sqm;
        if (dm < c.radius) { if (dm === dL) c.envVx += push; else if (dm === dR) c.envVx -= push; else if (dm === dT) c.envVy += push; else c.envVy -= push; }
      }
      c.sqS = 0;
    }
  }
  // the one eased squash state, contact side: bodies feel and draw the same squashed radius (item 64 directive 2)
  function effR(c) { return c.radius * (1 - (P.squashMax === undefined ? 0.18 : P.squashMax) * (c.sq || 0)); }
  // one wall side of wallPull: force-push when the wall advanced inward past the body this frame (block 73d-1), else reflect
  function carrySide(p, ax, vax, along, line, wv, side, vel) {
    if (P.wallCarry > 0 && wv * side > 0) {
      var pen = side * (line - p[ax]); if (pen < 0) pen = 0; // owner 25 Oct block 73d-1: a moving wall pushes bodies as a FORCE, it does not carry them - position resolves to the contact line only (non-penetration), never placed ahead at wall speed
      p[ax] = line;
      if (vel) { // v2 (owner 25 Oct: v1 slingshot rejected): pressure-proportional approach toward at most the wall's own speed - a deep press firms the push, a light brush barely nudges, and the body can never be driven faster than the wall; momentum settles on release via the decaying env channel
        var sqm3 = P.squashMax === undefined ? 0.18 : P.squashMax, rr3 = p.radius * (1 - sqm3 * (p.sq || 0));
        var tgt3 = side * Math.abs(wv) * P.wallCarry, k3 = Math.min(1, pen / Math.max(1e-6, rr3));
        if (vax === 'vx') p.envVx += (tgt3 - p.envVx) * k3; else p.envVy += (tgt3 - p.envVy) * k3;
        var sqm2 = P.squashMax === undefined ? 0.18 : P.squashMax, cp2 = Math.min(1, (p.sq || 0) + Math.abs(wv) / Math.max(1e-6, p.radius * sqm2)); // each frame the wall outruns the body it presses one frame-depth deeper
        if (cp2 > (p.sqS || 0)) p.sqS = cp2;
      }
    } else {
      p[ax] = line;
      if (vel) p[vax] = side * Math.abs(p[vax]) * 0.7;
    }
  }
  // item 64 (main 25 Oct): the ONE shared boundary rule as the frame's last position write, in EVERY path that
  // moves bodies after keepIn - the pre-render ink re-resolve and the HUD-off collective pass relocate bodies with a
  // centre-only clamp, so the wall must win again after them (46/46 pen defect root fix, second site).
  function finalWallClamp() {
    if (!P.boundAware) return;
    for (var fci = 0; fci < cells.length; fci++) { var fcc = cells[fci]; if (fcc.alive) wallPull(fcc, effR(fcc), true); }
  }
  function divide(c) {
    var ang = Math.random() * 6.2832, nr = Math.max(P.CELL_RADIUS, c.radius * 0.62);
    c.radius = nr; c.energy /= 2;
    var bx0 = cont.x + nr, bx1 = cont.x + cont.w - nr, by0 = cont.y + nr, by1 = cont.y + cont.h - nr;
    var kx = bx1 >= bx0 ? clamp(c.x + Math.cos(ang) * nr, bx0, bx1) : (bx0 + bx1) / 2, ky = by1 >= by0 ? clamp(c.y + Math.sin(ang) * nr, by0, by1) : (by0 + by1) / 2;
    var ch = new Cell(kx, ky, rnd(100) < c.mutationRate ? mutateGene(c.gene) : c.gene, c.mutationRate);
    ch.radius = nr; ch.energy = c.energy; ch.g = mutGenome(c.g, P.genomeMut); ch.shp = newShape(c.shp); ch.maxSpeed = speedOf(ch); ch.cl = c.cl; ev.birth++; ev.divide = (ev.divide || 0) + 1; cells.push(ch);
  }
  function clusterSize(id) { var n = 0; for (var i = 0; i < cells.length; i++) if (cells[i].cl === id) n++; return n; }
  function joinCluster(a, b) {
    if (a.cl && b.cl) { if (a.cl === b.cl) return; var from = b.cl, to = a.cl; if (clusterSize(to) + clusterSize(from) > P.clusterMax) return; cells.forEach(function (c) { if (c.cl === from) c.cl = to; }); }
    else if (a.cl) { if (clusterSize(a.cl) >= P.clusterMax) return; b.cl = a.cl; } else if (b.cl) { if (clusterSize(b.cl) >= P.clusterMax) return; a.cl = b.cl; }
    else { a.cl = b.cl = ++clusterSeq; }
    ev.merge = (ev.merge || 0) + 1;
  }
  // symbiogenesis: two compatible cells in deep contact fuse into one composite organism - heavier, slower, mixed genome
  function fuseCells(a, b) {
    var big = a.radius >= b.radius ? a : b, sm = big === a ? b : a;
    big.radius = Math.min(Math.sqrt(big.radius * big.radius + sm.radius * sm.radius) * 0.92, P.CELL_RADIUS * P.foodGrowMax * 1.2);
    big.energy = (big.energy + sm.energy) * 0.85;
    big.gene = clamp(Math.round((big.gene + sm.gene) / 2), P.GENE_MIN, P.GENE_MAX);
    big.g = mixGenome(big.g, sm.g); big.shp = mixShape(big.shp, sm.shp);
    big.comp = (big.comp || 1) + (sm.comp || 1);
    big.speedModifier = clamp(big.speedModifier / 1.25, 0.2, 3);
    if (big.sym && big.sym !== sm) big.sym.sym = null;
    if (sm.sym && sm.sym !== big) sm.sym.sym = null;
    big.sym = null; sm.sym = null; sm.alive = false; sm.__dr = 'absorbed'; sm.absorbed = 1;
    ev.fuse = (ev.fuse || 0) + 1;
  }
  function birthCapF() { // soft birth cap, habitat-gated: over habitatBirthCap x UNIVERSE_SIZE the contact-birth chance decays as cap/n (never a hard wall); habitat off = untouched core behaviour
    if (!P.habitatOn || !(P.habitatBirthCap > 0)) return 1;
    var cap = P.habitatBirthCap * P.UNIVERSE_SIZE;
    return cells.length > cap ? cap / cells.length : 1;
  }
  function interact(a, b) {
    if (a === b || !a.alive || !b.alive) return;
    var dx = b.x - a.x, dy = b.y - a.y, dist = Math.hypot(dx, dy);
    if (dist >= P.interactionRadius) return;
    if (P.eatMergeOn && dist < (a.radius + b.radius) * P.eatDistF) {
      var big = a.radius >= b.radius ? a : b, sm = big === a ? b : a, ratio = big.radius / Math.max(0.01, sm.radius);
      if (ratio >= P.eatRatio) {
        if (Math.random() < P.eatChance && (!big.cl || big.cl !== sm.cl)) {
          big.radius = Math.min(Math.sqrt(big.radius * big.radius + 0.5 * sm.radius * sm.radius), P.CELL_RADIUS * P.foodGrowMax * 1.2);
          big.energy += sm.energy * 0.6 + 1; sm.alive = false; sm.__dr = 'eaten'; sm.absorbed = 1; ev.eaten = (ev.eaten || 0) + 1; return;
        }
      } else if (Math.abs(a.gene - b.gene) <= P.mergeGene && Math.random() < P.mergeChance) joinCluster(a, b);
    }
    if (P.symbiogenesisOn && dist < (a.radius + b.radius) * P.fuseDistF && Math.abs(a.gene - b.gene) <= P.mergeGene && Math.random() < P.mergeChance * 0.3) { fuseCells(a, b); return; }
    if (P.symbiosisOn && !a.sym && !b.sym && dist < (a.radius + b.radius) * P.symDistF && Math.random() < P.mergeChance * 0.5) { a.sym = b; b.sym = a; ev.pair = (ev.pair || 0) + 1; }
    var infl = map(dist, 0, P.interactionRadius, 1, 0);
    var gc = Math.trunc(infl * (b.gene - a.gene) * 0.1);
    var et = P.energyGainFromInteraction * infl * (1 - Math.abs(a.gene - b.gene) / (P.GENE_MAX - P.GENE_MIN));
    a.energy += et; b.energy -= et;
    a.gene = clamp(a.gene + gc, P.GENE_MIN, P.GENE_MAX); b.gene = clamp(b.gene - gc, P.GENE_MIN, P.GENE_MAX);
    if (a.hostility > 0.5) {
      var l = dist || 1; a.vx += (-dx / l) * 0.05 * a.hostility; a.vy += (-dy / l) * 0.05 * a.hostility;
    }
    var rab = effR(a) + effR(b);
    if (dist < rab) ev.hit++;
    if (dist < a.radius + b.radius && Math.random() < P.reproChance * birthCapF() && a.energy > P.minEnergyForReproduction && b.energy > P.minEnergyForReproduction && frameT - (a.bornAt || 0) >= P.reproMinAgeMs && frameT - (b.bornAt || 0) >= P.reproMinAgeMs) reproduce(a, b); // juveniles do not reproduce: newborns overlap their parents, and ungated contact births chained into rows (owner 21 Oct: one click must be one cell)
    var nl = dist || 1, nx = dx / nl, ny = dy / nl, sep = (rab - dist) * 0.5;
    // f9 (73d-1, 1:1 sim.rs): a squeeze pushes as a force, it never carries - a pressed pair separates at the cells' own quantum over the next frames
    if (a.__ccT !== frameT) { a.__ccT = frameT; a.__ccU = 0; } if (b.__ccT !== frameT) { b.__ccT = frameT; b.__ccU = 0; }
    var spa9 = Math.min(sep, Math.max(0, (a.maxSpeed || 0) + 1 - a.__ccU)), spb9 = Math.min(sep, Math.max(0, (b.maxSpeed || 0) + 1 - b.__ccU));
    a.x -= nx * spa9; a.y -= ny * spa9; a.__ccU += spa9; b.x += nx * spb9; b.y += ny * spb9; b.__ccU += spb9;
    var ad = a.vx * nx + a.vy * ny, bd = b.vx * nx + b.vy * ny;
    a.vx = lerp(a.vx, a.vx - nx * 2 * ad, 0.8); a.vy = lerp(a.vy, a.vy - ny * 2 * ad, 0.8);
    b.vx = lerp(b.vx, b.vx - nx * 2 * bd, 0.8); b.vy = lerp(b.vy, b.vy - ny * 2 * bd, 0.8);
    var r1 = rand2D(), r2 = rand2D();
    a.vx += r1.x * 0.3; a.vy += r1.y * 0.3; b.vx += r2.x * 0.3; b.vy += r2.y * 0.3;
  }
  function reproduce(a, b) {
    if (cells.length < P.UNIVERSE_SIZE * 4 && a.hostility < 0.6 && b.hostility < 0.6) {
      var cost = P.minEnergyForReproduction / 2 + 1; a.energy -= cost; b.energy -= cost;
      var ng = Math.trunc((a.gene + b.gene) / 2);
      if (rnd(100) < a.mutationRate) ng = mutateGene(ng);
      var nm = clamp(a.mutationRate + rnd(-P.mutationRateRange, P.mutationRateRange), 0.5, 20);
      var r = rand2D();
      ev.birth++; var kid = new Cell((a.x + b.x) / 2 + r.x * a.radius, (a.y + b.y) / 2 + r.y * a.radius, ng, nm); kid.g = mutGenome(mixGenome(a.g, b.g), P.genomeMut); kid.shp = mixShape(a.shp, b.shp); kid.maxSpeed = speedOf(kid); cells.push(kid);
    }
  }
  function checkSurvival(c) {
    if (!c.alive) return; // 1:1 with sim.rs check_survival: one death is counted once, the first killer keeps the death-log tag (item 64 counter alias)
    if (c.gene <= P.GENE_MIN || c.gene >= P.GENE_MAX) { c.alive = false; c.__dr = 'genebound'; }
    var n = 0, R = P.interactionRadius;
    for (var i = 0; i < cells.length; i++) { var o = cells[i]; if (o !== c && o.alive && Math.hypot(c.x - o.x, c.y - o.y) < R) n++; }
    if (c.energy < n * P.crowdTol) { c.alive = false; c.__dr = 'crowd'; }
  }

  // ---- simulation control ----
  var VS = 1; // container scale: pde targets are for a 1280x800 window
  // title font metrics, cached per font size: the two words' ink widths and the font's letter spacing (tracking) -
  // the average inter-letter whitespace of the title words, measured from advance widths and ink boxes, never hardcoded
  // (owner 21 Oct: the three-line title's line gap equals the letter spacing)
  var tmCache = { fs: 0, trk: 0, inkTL: 0, inkTR: 0 };
  // Ca2-Thin is bundled, so the title words' true geometry is known exactly. Units per 1 em, read from Ca2-Thin.ttf
  // (hmtx advances, glyf xMin/xMax, unitsPerEm 1000, no kerning/GPOS): CELYLAR advance 4857 ink 4746, AUTOMW advance 5111
  // ink 4987. The measured ink box is only trusted when the measured advance proves the font loaded AND the ink agrees
  // with the font within a small tolerance; a browser whose ink box is padded or rounded fails that and the font's own
  // numbers are used instead (the letter gap, advance minus ink per letter, is only ~2% of the size, so a bad box makes
  // the three-line spacing trk*titleLead collapse while the layout still works). Sane browsers keep their measurement.
  var TFONT = { TL: [4.857, 4.746], TR: [5.111, 4.987] };
  function titleMetrics(fs) {
    if (tmCache.fs === fs) return tmCache;
    var w1 = ctx.measureText(TL).width, i1 = inkLR(TL), w2 = ctx.measureText(TR).width, i2 = inkLR(TR);
    var k1 = i1[1] - i1[0], k2 = i2[1] - i2[0], tol = 0.004 * fs + 1;
    var fontOk = Math.abs(w1 - TFONT.TL[0] * fs) <= tol && Math.abs(w2 - TFONT.TR[0] * fs) <= tol; // Ca2-Thin really in use
    var inkOk = Math.abs(k1 - TFONT.TL[1] * fs) <= tol && Math.abs(k2 - TFONT.TR[1] * fs) <= tol; // false for NaN too
    if (fontOk && !inkOk) { k1 = TFONT.TL[1] * fs; k2 = TFONT.TR[1] * fs; w1 = TFONT.TL[0] * fs; w2 = TFONT.TR[0] * fs; }
    tmCache = { fs: fs, inkTL: k1, inkTR: k2, trk: ((w1 - k1) / (TL.length - 1) + (w2 - k2) / (TR.length - 1)) / 2 };
    return tmCache;
  }
  var rsbCache = { key: '', dx: 0, done: false };
  function rsbKey(fs, M, ex) { return fs.toFixed(2) + '|' + M + '|' + ex.toFixed(2) + '|' + (bg ? bg.map(Math.round).join(',') : ''); }
  // isolated pixel measure of the rendered title word on an offscreen canvas: same font, size, scale and letter
  // spacing, but no simulation ink - scanning the live canvas caught wandering cells and food dots as "title ink",
  // which shifted the word past the right margin and off the frame and made the margin look dead (owner 21 Oct)
  var rsbCv = null;
  function drawSpaced(c, txt, x0, y, ex) { for (var ci = 0; ci < txt.length; ci++) c.fillText(txt[ci], x0 + c.measureText(txt.slice(0, ci)).width + ci * ex, y); }
  // the last glyph's dot ink reaches past the metrics' bounding box: measured once per platform at 100px, scaled
  // linearly - the fit cap counts this overshoot so the visible dots (not just the metrics) stay inside the margins
  var ovsCache = -1;
  function titleOvershoot() {
    if (ovsCache >= 0) return ovsCache;
    if (!rsbCv) rsbCv = document.createElement('canvas');
    var fs = 100, c2 = rsbCv.getContext('2d', { willReadFrequently: true });
    var w = 8 * fs; rsbCv.width = w; rsbCv.height = 2 * fs;
    c2.setTransform(1, 0, 0, 1, 0, 0);
    c2.fillStyle = '#fff'; c2.fillRect(0, 0, w, 2 * fs);
    c2.font = fs + 'px "Ca2-Thin", monospace'; c2.textBaseline = 'alphabetic'; c2.textAlign = 'left'; c2.fillStyle = '#000';
    var pre = TR.length > 1 ? c2.measureText(TR.slice(0, -1)).width : 0, l = c2.measureText(TR[TR.length - 1]);
    var metric = pre + l.actualBoundingBoxRight;
    drawSpaced(c2, TR, 0, 1.5 * fs, 0);
    var img = c2.getImageData(0, 0, w, 2 * fs).data, lastX = 0;
    for (var x = w - 1; x >= 0; x--) { var hit = false; for (var y = 0; y < 2 * fs; y++) { var i = (y * w + x) * 4; if (img[i] < 160) { hit = true; break; } } if (hit) { lastX = x; break; } }
    ovsCache = Math.max(0, lastX + 1 - metric) / fs; // right overshoot per em, never negative
    return ovsCache;
  }
  function rsbScan(fs, dh, M, ex) {
    if (rsbCache.done) return;
    if (!rsbCv) rsbCv = document.createElement('canvas');
    var sx = DPR, wCss = M + 7 * fs, hCss = M + dh + 4, wPx = Math.max(1, Math.ceil(wCss * sx));
    rsbCv.width = wPx; rsbCv.height = Math.max(1, Math.ceil(hCss * sx));
    var c2 = rsbCv.getContext('2d', { willReadFrequently: true });
    c2.setTransform(sx, 0, 0, sx, 0, 0);
    var lite = (bg[0] * 299 + bg[1] * 587 + bg[2] * 114) / 1000 > 127;
    c2.fillStyle = css(bg, 1); c2.fillRect(0, 0, wCss, hCss);
    c2.font = fs + 'px "Ca2-Thin", monospace'; c2.textBaseline = 'alphabetic'; c2.textAlign = 'left';
    c2.fillStyle = lite ? '#000' : '#fff';
    var lr = [0, 0];
    if (TR.length) { var f = c2.measureText(TR[0]), pre = TR.length > 1 ? c2.measureText(TR.slice(0, -1)).width : 0, l = c2.measureText(TR[TR.length - 1]); lr = [f.actualBoundingBoxLeft, pre + l.actualBoundingBoxRight]; }
    var x0 = (wCss - M) - lr[1] - (TR.length - 1) * ex; // same right-anchor as the live draw
    drawSpaced(c2, TR, x0, M + dh, ex);
    var img; try { img = c2.getImageData(0, 0, wPx, rsbCv.height).data; } catch (e) { rsbCache.done = true; return; }
    var bgr = bg[0], bgg = bg[1], bgb = bg[2];
    for (var x = wPx - 1; x >= 0; x--) {
      for (var y = 0; y < rsbCv.height; y++) {
        var i = (y * wPx + x) * 4;
        if (Math.abs(img[i] - bgr) + Math.abs(img[i + 1] - bgg) + Math.abs(img[i + 2] - bgb) > 96) {
          rsbCache.dx = Math.max(-0.1 * fs, Math.min(0.25 * fs, (wPx - 1 - x) / sx - M)); // a padded bbox can hide the whole rsb
          rsbCache.done = true; return;
        }
      }
    }
    rsbCache.done = true;
  }
  function lay() {
    // all typography metrics derive from one font size; margin is equal on every edge
    // type size runs 0.5..2 in the config, but the effective ceiling is the fit: the widest word of the title
    // must always fit the page width inside the margins, so a manual entry can never push ink off the frame (owner 21 Oct)
    var fs = 210 * Math.min(W / 2560, H / 1600) * P.textScale, dh = 0.666 * fs; // no render cap (owner 21 Oct): typed values apply; the width fit below is the only, physical, limit
    ctx.font = fs + 'px "Ca2-Thin", monospace';
    var M = P.margin, G = P.gap;
    var tm = titleMetrics(fs), ex = tm.trk * (P.titleTrack - 1), inkTLe = tm.inkTL + (TL.length - 1) * ex, inkTRe = tm.inkTR + (TR.length - 1) * ex, trkE = tm.trk + ex;
    var inkMax = Math.max(inkTLe, inkTRe) + titleOvershoot() * fs, fit = inkMax > 0 ? (W - 2 * M) / inkMax : 1;
    if (fit < 1) {
      fs *= fit; dh = 0.666 * fs; ctx.font = fs + 'px "Ca2-Thin", monospace';
      tm = titleMetrics(fs); ex = tm.trk * (P.titleTrack - 1); inkTLe = tm.inkTL + (TL.length - 1) * ex; inkTRe = tm.inkTR + (TR.length - 1) * ex; trkE = tm.trk + ex; inkMax = Math.max(inkTLe, inkTRe) + ovsCache * fs; fit = inkMax > 0 ? (W - 2 * M) / inkMax : 1; if (fit < 1) { fs *= fit; dh = 0.666 * fs; ctx.font = fs + 'px "Ca2-Thin", monospace'; tm = titleMetrics(fs); ex = tm.trk * (P.titleTrack - 1); inkTLe = tm.inkTL + (TL.length - 1) * ex; inkTRe = tm.inkTR + (TR.length - 1) * ex; trkE = tm.trk + ex; }
    }
    // the title goes three centred lines (word / word / mouse-y) when the two words no longer fit side by side:
    // decided from the measured ink widths and the live margin, not a fixed ratio, so any margin/window works (owner 21 Oct:
    // they must never overlap; the switch is when the gap between them closes to one letter space, the 1.217 point on his screen)
    var wordGap = W - 2 * M - inkTLe - inkTRe;
    var three = wordGap < trkE, lead = three ? dh + trkE * P.titleLead : 0;
    var row = three ? 2 * lead : P.textScale > 1.03 ? dh + 15 * P.titleLead : 0; // above type size 1.03 the mouse-y value drops one row and the vertical axis starts below it
    var lr3 = inkLR('3333'), sideW = lr3[1] - lr3[0]; // widest 4-digit number, ink width
    var halfW = W / 2 - (M + sideW + G), halfH = H / 2 - (M + dh + row + G);
    return { row: row, three: three, lead: lead, fs: fs, dh: dh, M: M, G: G, ex: ex, sideW: sideW, safeW: Math.max(60, halfW * 2), safeH: Math.max(60, halfH * 2) };
  }
  function setTargets() {
    var cWHf = Math.floor(rnd(7, 8));
    var a = Math.floor(rnd(2)) === 0 ? 5120 : 2160, b = Math.floor(rnd(2)) === 0 ? 5120 : 2160;
    var tw = a / (cWHf + Math.trunc(rnd(-3.5, 1))) * VS, th = b / cWHf * VS;
    // ceiling and floor: the area never leaves the band between the typography rows / side numbers
    cont.user = false; cont.rawW = tw; cont.rawH = th; clampTargets();
  }
  function clampTargets() {
    var L = lay(), lo = Math.min(P.areaMin, P.areaMax), hi = Math.max(P.areaMin, P.areaMax);
    var ov = P.plateOverlap, ovW = 2 * (L.G + ov * L.sideW), ovH = 2 * (L.G + ov * L.dh); // the plate may reach over the texts by this share of their size
    if (cont.user) { cont.tw = clamp(cont.rawW, 60, W - P.dragMargin * 2); cont.th = clamp(cont.rawH, 60, H - P.dragMargin * 2); return; } // a size the user pulled by hand: nearly the whole viewport
    cont.tw = clamp(cont.rawW, L.safeW * lo, (L.safeW + ovW) * hi);
    cont.th = clamp(cont.rawH, L.safeH * lo, (L.safeH + ovH) * hi);
  }
  // ---- entrance: every element fades in from transparency at its own random time
  var fadeT0 = performance.now(), fadeK = {};
  // intro: no fades. Every graphic element appears at once, at its own random moment within the first INTRO_MS
  var INTRO_MS = 2000, UI_END = 800, CELL_END = 1300, FOOD_END = 1700;
  var pendingSpawn = null; // first load only: cells and food arrive in small batches after the UI intro, so the opening stays smooth
  var introStat = { frames: 0, jank: 0, worst: 0 };
  function fadeA(key) {
    var d = fadeK[key];
    if (d === undefined) d = fadeK[key] = key.charAt(0) === 'p' ? FOOD_END + Math.random() * (INTRO_MS - FOOD_END) : Math.random() * UI_END; // UI first, parasites last
    return (performance.now() - fadeT0 >= d) ? 1 : 0;
  }
  function introOn(d) { return performance.now() - fadeT0 >= d; }
  var firstSpawn = true; // the first plate after a load uses the configured values; later respawns randomize them
  function randomize(instant, staged) {
    if (!instant && P.cellMorph && ready && cells.length) { startTrans(); return; }
    trans = null; pendingSpawn = null; cells = []; food = []; parasites = []; if (P.selectOn) newEnv();
    // bounded variety (architect 21 Oct 22:05): untouched keys re-deal INSIDE the measured healthy band so a default
    // visitor still meets changing scales/relations (owner 17:54); edited keys (touched) stay pinned; admin unlock = wild ranges.
    // Bands: U 20-120 (wild 1-5 dealt dead plates), ir 0.1-20 (sweep: 0.1/6/12/20 all healthy, 20 yields clusters), mut/mr as before.
    if (!firstSpawn) {
      if (!touched.UNIVERSE_SIZE) P.UNIVERSE_SIZE = Math.floor(lockParams ? rnd(20, 120) : rnd(1, rnd(20, 200)));
      if (!touched.baseMutationRate) P.baseMutationRate = rnd(2, 8);
      if (!touched.mutationRateRange) P.mutationRateRange = rnd(1, 4);
      if (!touched.interactionRadius) P.interactionRadius = lockParams ? rnd(0.1, 20) : rnd(10, 30);
    }
    setTargets();
    if (!firstSpawn && !touched.CELL_RADIUS) P.CELL_RADIUS = Math.min(rnd(P.minRadius, P.maxRadius), Math.max(8, Math.min(cont.tw, cont.th) / 8)); // same isotropy guard as startTrans
    if (staged) { // the opening: typography first, the heavy population follows in batches (owner 20 Oct)
      pendingSpawn = { cells: Math.max(1, Math.round(P.UNIVERSE_SIZE)), food: Math.round(cont.tw * cont.th * P.foodDensity / 2), gx: cont.tw ? (W - cont.tw) / 2 : 0, gy: cont.th ? (H - cont.th) / 2 : 0 };
      newRefresh();
      return;
    }
    var gx = cont.tw ? (W - cont.tw) / 2 : 0, gy = cont.th ? (H - cont.th) / 2 : 0;
    for (var i = 0; i < P.UNIVERSE_SIZE; i++) {
      cells.push(new Cell(rnd(cont.tw) + gx, rnd(cont.th) + gy, Math.floor(rnd(P.GENE_MIN, P.GENE_MAX + 1)), P.baseMutationRate + rnd(-P.mutationRateRange, P.mutationRateRange)));
    }
    var nf = cont.tw * cont.th * P.foodDensity / 2;
    for (var j = 0; j < nf; j++) { var fp0 = foodSpot(gx, gy, cont.tw, cont.th); if (fp0) food.push({ x: fp0.x, y: fp0.y, r: Math.random() }); }
    newRefresh();
  }
  // ---- symbiotic metamorphosis: no tween. A refresh sets a new plate and new target traits; the cells keep living by their own rules
  // (movement, boundary pressure from the moving walls, reproduction, death, mutation) and the population, radius and traits drift to the new composition.
  var trans = null;
  function startTrans() {
    // same bounded deal as randomize(): per-key, edited keys pinned, admin unlock = the old wild ranges
    var tg = {
      U: touched.UNIVERSE_SIZE ? P.UNIVERSE_SIZE : Math.floor(lockParams ? rnd(20, 120) : rnd(1, rnd(20, 200))),
      mut: touched.baseMutationRate ? P.baseMutationRate : rnd(2, 8),
      mr: touched.mutationRateRange ? P.mutationRateRange : rnd(1, 4),
      ir: touched.interactionRadius ? P.interactionRadius : (lockParams ? rnd(0.1, 20) : rnd(10, 30)),
      cr: 0
    };
    setTargets();
    // isotropy guard (owner 21 Oct 15:14): a dealt radius must leave the plate's short side at least 4 cell
    // diameters across - below that the swarm is forced into single-file rows/columns (desktop rows, mobile columns)
    tg.cr = touched.CELL_RADIUS ? P.CELL_RADIUS : Math.min(rnd(P.minRadius, P.maxRadius), Math.max(8, Math.min(cont.tw, cont.th) / 8));
    // food outside the new plate is lost, the rest stays
    var x0 = (W - cont.tw) / 2, y0 = (H - cont.th) / 2; if (!P.foodLife) food = food.filter(function (f) { return f.x > x0 && f.x < x0 + cont.tw && f.y > y0 && f.y < y0 + cont.th; });
    if (P.selectOn) newEnv();
    trans = { t0: performance.now(), dur: Math.max(100, P.cellMorphMs), tg: tg };
    if (P.respawnMorph) planComposition(tg);
    newRefresh();
  }
  // ---- respawn morph: a new life cycle (new environment, fresh energy, fresh food) with a new random composition.
  // Every cell gets a place in the new composition and flows there at its own pace; surplus cells die on arrival, missing ones are born from the nearest parent.
  function planComposition(tg) {
    var gx = (W - cont.tw) / 2, gy = (H - cont.th) / 2, nC = 2 + Math.floor(Math.random() * 4), ctr = [], i, j2;
    for (i = 0; i < nC; i++) ctr.push([gx + cont.tw * rnd(0.12, 0.88), gy + cont.th * rnd(0.12, 0.88)]);
    var sg = Math.min(cont.tw, cont.th) * rnd(0.08, 0.2), pts = [];
    for (i = 0; i < Math.max(1, tg.U); i++) { // resample instead of hard-clamping: a clamp piles points onto the plate edges, and on a wide plate that is the top/bottom edges -> visible horizontal rows when a crowd chases them
      var cc = ctr[i % nC], px = 0, py = 0, okp = false;
      for (j2 = 0; j2 < 12; j2++) {
        px = cc[0] + (Math.random() + Math.random() + Math.random() - 1.5) * 2 * sg;
        py = cc[1] + (Math.random() + Math.random() + Math.random() - 1.5) * 2 * sg;
        if (px > gx + 8 && px < gx + cont.tw - 8 && py > gy + 8 && py < gy + cont.th - 8) { okp = true; break; }
      }
      if (!okp) { px = clamp(px, gx + 8, gx + cont.tw - 8); py = clamp(py, gy + 8, gy + cont.th - 8); } // pathologically tiny plate: keep the old clamp as a floor
      pts.push([px, py]);
    }
    for (i = 0; i < cells.length; i++) { if (P.refreshResetEnergy) cells[i].energy = 12; cells[i].cl = 0; cells[i].dst = null; cells[i].dying = false; cells[i].pace = rnd(0.5, 1.5); cells[i].dl = rnd(0, 0.45) * trans.dur; cells[i].durK = rnd(0.55, 1); cells[i].bend = Math.random() < 0.25 ? 0 : rnd(-1, 1); cells[i].sym = null; }
    // greedy matching, cells in random order take the nearest free place
    var free = pts.slice(), order = cells.slice().sort(function (a, b2) { return ((b2.userAdded && P.spawnProtect) ? 1 : 0) - ((a.userAdded && P.spawnProtect) ? 1 : 0) || Math.random() - 0.5; }), spawnN = 0;
    // user-added cells take places first (owner 21 Oct: added cells must join the life, not be culled): the surplus cull falls on natural-born cells only
    for (i = 0; i < order.length; i++) {
      var c = order[i];
      if (free.length) { var bi = 0, bd = 1e18; for (j2 = 0; j2 < free.length; j2++) { var d = (free[j2][0] - c.x) * (free[j2][0] - c.x) + (free[j2][1] - c.y) * (free[j2][1] - c.y); if (d < bd) { bd = d; bi = j2; } } c.dst = free.splice(bi, 1)[0]; }
      else { c.dst = pts[Math.floor(Math.random() * pts.length)]; if (!(P.spawnProtect && c.userAdded)) c.dying = true; }
    }
    trans.pending = free; trans.plan = { points: pts.length, dying: order.filter(function (c) { return c.dying; }).length, birthsDue: free.length, from: cells.length };
    // fresh food for the new cycle
    var nf = cont.tw * cont.th * P.foodDensity / 2; if (!P.foodLife) food = [];
    for (var f = 0; !P.foodLife && f < nf; f++) { var fp1 = foodSpot(gx, gy, cont.tw, cont.th); if (fp1) food.push({ x: fp1.x, y: fp1.y, r: Math.random() }); }
  }
  function stepComposition(now, dt) {
    var i, open = 0, late = now - trans.t0 > trans.dur * 1.5;
    for (i = 0; i < cells.length; i++) {
      var c = cells[i]; if (!c.dst || !c.alive) continue;
      var dx = c.dst[0] - c.x, dy = c.dst[1] - c.y, d = Math.hypot(dx, dy);
      var el = now - trans.t0 - (c.dl || 0); // every cell waits for its own moment before it takes off
      if (el <= 0) { open++; continue; }
      var win = Math.max(80, trans.dur * (c.durK || 1)), pr = clamp(el / win, 0, 1);
      var kc = 1 - Math.exp(-dt * 3 / win);
      var ease = 0.35 + 0.65 * Math.sin(pr * Math.PI); // its own speed curve: slow takeoff, full flow mid-flight, soft landing
      var k = Math.min(1, kc * c.pace * ease * 1.31);
      c.x += dx * k + (Math.random() - 0.5) * 0.6; c.y += dy * k + (Math.random() - 0.5) * 0.6;
      if (c.bend) { var lat = k * Math.min(d, 200) * c.bend * 0.35 * Math.sin(pr * Math.PI), il = 1 / (d || 1); c.x += -dy * il * lat; c.y += dx * il * lat; } // a bowed path, not a straight chase
      if (c.dying && (d < 14 || (late && Math.random() < 0.08))) { c.alive = false; c.__dr = 'dying'; ev.death++; continue; }
      if (d > 14) open++;
    }
    compSpawns(now, dt);
    return open;
  }
  function compSpawns(now, dt) { // pending composition births: parent search + Cell ctor stay JS (newShape/mutGenome are body-plan)
    var pend = trans.pending, n = cells.length, i;
    if (pend.length && n > 0) {
      var kb = 1 - Math.exp(-dt * 3 / trans.dur), cnt = Math.min(pend.length, 1 + Math.floor(pend.length * kb * 2));
      for (i = 0; i < cnt; i++) {
        var pt = pend.pop(), par = null, bd = 1e18;
        for (var m = 0; m < 12; m++) { var q = cells[Math.floor(Math.random() * n)]; if (!q.alive) continue; var dd = (q.x - pt[0]) * (q.x - pt[0]) + (q.y - pt[1]) * (q.y - pt[1]); if (dd < bd) { bd = dd; par = q; } }
        if (!par) continue;
        var ch = new Cell(par.x + rnd(-2, 2), par.y + rnd(-2, 2), mutateGene(par.gene), clamp(par.mutationRate + rnd(-P.mutationRateRange, P.mutationRateRange), 0.5, 20));
        ch.g = mutGenome(par.g, P.genomeMut); ch.shp = newShape(par.shp); ch.maxSpeed = speedOf(ch); ch.radius = par.radius * 0.5; ch.dst = pt; ch.pace = rnd(0.5, 1.5); ch.dl = 0; ch.durK = rnd(0.5, 1); ch.bend = Math.random() < 0.25 ? 0 : rnd(-1, 1); cells.push(ch); ev.birth++;
      }
    }
  }
  function transPassW(now, dt, plan) { // Rust/wasm transition pass (tr.rs): radius drift + composition chase. Returns open count, or -1 so the JS loops below run (?nowasm=1, ?nosim=1)
    var E = WC.e; if (!E || !E.tr_run || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1/.test(location.search)) return -1;
    try {
      var n = cells.length, i, c, b;
      var cp = E.tr_cells(n), cf = new Float64Array(WC.mem.buffer, cp, n * 13 + 13);
      for (i = 0; i < n; i++) { c = cells[i]; b = i * 13; cf[b] = c.x; cf[b + 1] = c.y; cf[b + 2] = c.radius; cf[b + 3] = c.mutationRate; cf[b + 4] = c.alive ? 1 : 0;
        if (plan && c.dst && c.alive) { cf[b + 5] = c.dst[0]; cf[b + 6] = c.dst[1]; cf[b + 7] = c.dl || 0; cf[b + 8] = c.durK || 1; cf[b + 9] = c.pace; cf[b + 10] = c.bend || 0; cf[b + 11] = c.dying ? 1 : 0; cf[b + 12] = 1; } else cf[b + 12] = 0; }
      var open = E.tr_run(n, now, dt, trans.t0, trans.dur, P.CELL_RADIUS, plan ? 1 : 0, Math.floor(Math.random() * 4294967296), Math.floor(Math.random() * 4294967296));
      if (open < 0) return -1;
      var st = new Float64Array(WC.mem.buffer, E.tr_stat(), 4); ev.death += st[0];
      for (i = 0; i < n; i++) { c = cells[i]; b = i * 13; c.x = cf[b]; c.y = cf[b + 1]; c.radius = cf[b + 2]; c.alive = cf[b + 4] !== 0; }
      WC.fwTr = (WC.fwTr || 0) + 1; return open;
    } catch (e) { WC.fwTrErr = String(e && e.stack || e); return -1; }
  }
  function stepTrans(now, dt) {
    if (P.respawnMorph && trans.plan) {
      var kk = 1 - Math.exp(-dt * 3 / trans.dur), tg2 = trans.tg;
      P.baseMutationRate = lerp(P.baseMutationRate, tg2.mut, kk); P.mutationRateRange = lerp(P.mutationRateRange, tg2.mr, kk);
      P.interactionRadius = lerp(P.interactionRadius, tg2.ir, kk); P.CELL_RADIUS = lerp(P.CELL_RADIUS, tg2.cr, kk); P.UNIVERSE_SIZE = lerp(P.UNIVERSE_SIZE, tg2.U, kk);
      var open = transPassW(now, dt, true);
      if (open < 0) {
        for (var ii = 0; ii < cells.length; ii++) { var cc = cells[ii]; cc.radius += (P.CELL_RADIUS - cc.radius) * Math.min(1, 0.004 * cc.mutationRate); }
        open = stepComposition(now, dt);
      } else compSpawns(now, dt);
      trans.open = open;
      if (now - trans.t0 > trans.dur * 5 || (now - trans.t0 > trans.dur && open === 0 && !trans.pending.length && Math.abs(cont.ew - cont.tw) < 1 && Math.abs(cont.eh - cont.th) < 1)) {
        for (ii = 0; ii < cells.length; ii++) { cells[ii].dst = null; cells[ii].dying = false; cells[ii].dl = 0; cells[ii].bend = 0; }
        P.UNIVERSE_SIZE = tg2.U; P.CELL_RADIUS = tg2.cr; P.baseMutationRate = tg2.mut; P.mutationRateRange = tg2.mr; P.interactionRadius = tg2.ir; trans = null; window.__ca2 && (window.__ca2.lastTransDone = performance.now());
      }
      return;
    }
    var k = 1 - Math.exp(-dt * 3 / trans.dur), tg = trans.tg;
    P.baseMutationRate = lerp(P.baseMutationRate, tg.mut, k); P.mutationRateRange = lerp(P.mutationRateRange, tg.mr, k);
    P.interactionRadius = lerp(P.interactionRadius, tg.ir, k); P.CELL_RADIUS = lerp(P.CELL_RADIUS, tg.cr, k);
    P.UNIVERSE_SIZE = lerp(P.UNIVERSE_SIZE, tg.U, k);
    var target = Math.max(1, Math.round(P.UNIVERSE_SIZE)), n = cells.length, i;
    // population pressure uses the cells' own mechanisms: a parent reproduces with a mutated gene; the weakest of a few is let go
    if (n < target * 0.97 && n > 0 && Math.random() < Math.min(1, (target - n) * 0.1)) {
      var p = cells[Math.floor(Math.random() * n)], ang = Math.random() * 6.2832;
      if (P.selectOn) for (i = 0; i < 2; i++) { var q2 = cells[Math.floor(Math.random() * n)]; if (misfit(q2) < misfit(p)) p = q2; }
      var ch = new Cell(p.x + Math.cos(ang) * p.radius, p.y + Math.sin(ang) * p.radius, mutateGene(p.gene), clamp(p.mutationRate + rnd(-P.mutationRateRange, P.mutationRateRange), 0.5, 20));
      ch.g = mutGenome(p.g, P.genomeMut); ch.shp = newShape(p.shp); ch.maxSpeed = speedOf(ch); ch.radius = p.radius * 0.5; p.energy = Math.max(1, p.energy * 0.85); ch.energy = p.energy; cells.push(ch); ev.birth++;
    } else if (n > target * 1.03 && Math.random() < Math.min(1, (n - target) * 0.1)) {
      var w = null; for (i = 0; i < 3; i++) { var q = cells[Math.floor(Math.random() * n)]; if (!w || (P.selectOn ? misfit(q) - 0.01 * q.energy > misfit(w) - 0.01 * w.energy : q.energy < w.energy)) w = q; }
      if (w) w.alive = false;
    }
    // each cell's radius drifts to the new trait at its own mutation pace
    if (transPassW(now, dt, false) < 0) for (i = 0; i < cells.length; i++) { var c = cells[i]; c.radius += (P.CELL_RADIUS - c.radius) * Math.min(1, 0.004 * c.mutationRate); }
    if (now - trans.t0 > trans.dur * 4 || (now - trans.t0 > trans.dur && Math.abs(n - target) <= Math.max(2, target * 0.05) && Math.abs(cont.ew - cont.tw) < 1 && Math.abs(cont.eh - cont.th) < 1 && Math.abs(P.CELL_RADIUS - tg.cr) < 0.5)) {
      P.UNIVERSE_SIZE = tg.U; P.CELL_RADIUS = tg.cr; P.baseMutationRate = tg.mut; P.mutationRateRange = tg.mr; P.interactionRadius = tg.ir; trans = null;
    }
  }
  function newRefresh() {
    var lo = Math.min(P.minRefreshInterval, P.maxRefreshInterval), hi = Math.max(P.minRefreshInterval, P.maxRefreshInterval);
    refreshInterval = rnd(lo, hi); lastRefresh = performance.now();
  }
  function cycleBg() { bgIndex = (bgIndex + 1) % BGS.length; bgTarget = BGS[bgIndex]; save(); }
  // shared spawn (desktop click, drag spray and the mobile touch path all use this - lane agreement 21 Oct):
  // one placement = one cell, NEVER overlapped: an overlapped spawn shoves the neighbourhood apart and the
  // displacement wave reads as a burst of contact births (owner 21 Oct: one click must be one cell)
  function spawnAt(x, y) {
    var r = P.CELL_RADIUS, px = x, py = y, ok = false, i, k;
    // the wall owns placement, not the cursor (owner 22 Oct): births land inside the plate, radius inset
    var bx0 = cont.x + r, bx1 = cont.x + cont.w - r, by0 = cont.y + r, by1 = cont.y + cont.h - r;
    x = bx1 >= bx0 ? clamp(x, bx0, bx1) : (bx0 + bx1) / 2; y = by1 >= by0 ? clamp(y, by0, by1) : (by0 + by1) / 2;
    for (var ring = 0; ring <= 4 && !ok; ring++) {
      var n = ring ? ring * 6 : 1;
      for (k = 0; k < n && !ok; k++) {
        var a = k / n * 6.2832, cx2 = x + Math.cos(a) * ring * r, cy2 = y + Math.sin(a) * ring * r, free = true;
        for (i = 0; i < cells.length; i++) { var o = cells[i]; if (Math.hypot(cx2 - o.x, cy2 - o.y) < o.radius + r) { free = false; break; } }
        if (free) { px = cx2; py = cy2; ok = true; }
      }
    }
    var nc = new Cell(px, py, Math.floor(rnd(P.GENE_MIN, P.GENE_MAX + 1)), P.baseMutationRate + rnd(-P.mutationRateRange, P.mutationRateRange));
    nc.userAdded = 1; cells.push(nc);
    return nc;
  }
  function createCell() { spawnAt(mouse.x, mouse.y); }
  function killNear() { for (var i = cells.length - 1; i >= 0; i--) if (Math.hypot(mouse.x - cells[i].x, mouse.y - cells[i].y) < cells[i].radius + 6) { habReap(cells[i]); cells.splice(i, 1); } } // the click target is the visible body: a fixed 22px missed every click once CELL_RADIUS grew past it (owner 21 Oct: D+click did not kill)
  function randomizeOne() {
    var k = Math.floor(rnd(5));
    if (k === 0) P.baseMutationRate = rnd(2, 8); else if (k === 1) P.mutationRateRange = rnd(1, 4);
    else if (k === 2) P.CELL_RADIUS = rnd(P.minRadius, P.maxRadius); else if (k === 3) P.baseMaxSpeed = rnd(1, 2); else P.foodDensity = rnd(0.01, 0.05);
  }
  function randomAction() {
    switch (Math.floor(rnd(8))) {
      case 0: createCell(); break;
      case 1: newRefresh(); break;
      case 2: P.interactionRadius = rnd(10, 50); break;
      case 3: randomizeOne(); break;
      case 4: killNear(); break;
      case 5: cycleBg(); break;
      default: randomize();
    }
  }
  var aev = { b: 0, d: 0, h: 0 };
  var curInfo3 = {}, curOn0 = false, curInfo2 = {}, curMaxR = 0, lockCell = null, lockT0 = 0, curX = 0, curY = 0, cursorScale = 1, targetCursorScale = 1, curRRnow = 0, curInfo = {}, circlesNow = [], circleCol = {}, lastCircleHit = '';
  var curEl = document.getElementById('cur'), curDot = curEl.firstElementChild;
  // boundary hover cursor: an open 90-degree angle - two strokes in the plate line's width and colour, a gap where they
  // would meet, each stroke half the logo height, oriented to the hovered edge; corners get the mirrored pair (owner 20 Oct)
  var curEdge = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  curEdge.style.cssText = 'position:fixed;left:0;top:0;display:none;pointer-events:none;z-index:8;overflow:visible;will-change:transform';
  var curEdgePath = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  curEdgePath.setAttribute('fill', 'none'); curEdgePath.setAttribute('stroke-linecap', 'butt');
  curEdge.appendChild(curEdgePath); document.body.appendChild(curEdge);
  function anglePath(t, L, g, vx, vy) { // vertex at (vx,vy) pointing along angle t; strokes stop `g` short of the vertex
    function pt(deg) { var a = (t + deg) * Math.PI / 180; return [vx + Math.cos(a) * L, vy + Math.sin(a) * L]; }
    function sh(p0) { var dx = vx - p0[0], dy = vy - p0[1], dd = Math.hypot(dx, dy) || 1, k = (dd - g) / dd; return [p0[0] + dx * k, p0[1] + dy * k]; }
    var A = pt(-135), B = pt(135), A2 = sh(A), B2 = sh(B), f = function (n) { return n.toFixed(1); };
    return 'M' + f(A[0]) + ' ' + f(A[1]) + 'L' + f(A2[0]) + ' ' + f(A2[1]) + 'M' + f(B[0]) + ' ' + f(B[1]) + 'L' + f(B2[0]) + ' ' + f(B2[1]);
  }
  var TL = 'CELYLAR', TR = 'AUTOMW';
  // circle centers (font units, 1000/em) per glyph of Ca2-Thin, measured from the font outlines
  var GL = { C: [[166, 500], [166, 167]], E: [[168, 332]], L: [[166, 167]], Y: [[136, 167], [728, 167]], A: [[333, 499]], R: [[166, 500]], U: [[166, 167]], T: [[166, 500], [499, 500]], O: [[146, 500], [146, 167]], M: [[166, 500], [806, 500], [486, 167]], W: [[573, 500], [906, 500], [166, 499], [1313, 499]] };
  var coarseUI = window.matchMedia && matchMedia('(hover: none) and (pointer: coarse)').matches;
  function onClick(e) {
    if (e.target !== cv) return;
    if (coarseUI && (panel.classList.contains('open') || panel.classList.contains('hov'))) { panel.classList.remove('open'); panel.classList.remove('hov'); return; }
    var k = keyHeld;
    if ((k === 'a' || coarseUI) && sprayMoved) { sprayMoved = false; return; } // the drag already sprayed; the release click adds no extra cell (touch holds no keys, same guard)
    // touch has no held keys: a coarse tap is the A+click equivalent - one tap, one overlap-free cell at the tap point
    // through the shared spawnAt (lane agreement 21 Oct; the drag spray's touch counterpart binds to the same spawnAt)
    if (k === 'b') cycleBg(); else if (k === 'a') createCell(); else if (k === 's') randomize(); else if (k === 'd') killNear(); else if (!k) { if (coarseUI) spawnAt(e.clientX, e.clientY); else randomAction(); }
  }

  // ---- colour helpers ----
  function lerpC(a, b, t) { return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)]; }
  function lerpA(a, b, t) { return [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t)]; }
  function css(c, a) { return 'rgba(' + (c[0] | 0) + ',' + (c[1] | 0) + ',' + (c[2] | 0) + ',' + (a === undefined ? (c[3] === undefined ? 1 : c[3]) : a) + ')'; }

  // ---- metaballs: splatted per cell (cut off where a cell adds <3% of the threshold), device-resolution buffer ----
  var off = document.createElement('canvas'), octx = off.getContext('2d'), img = null, u32 = null;
  var bufW = 0, bufH = 0, fSum, fR, fG, fB, curS = 1;
  // Rust/wasm core (wasm/ -> ca2core.wasm). Loaded async; any failure leaves WC.ok false and the JS code runs as before. ?nowasm=1 disables.
  var WC = { ok: false, off: false }, MB = { ms: 0, path: '-' };
  if (window.WebAssembly && !/[?&]nowasm=1/.test(location.search)) {
    var simd = false; try { simd = WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,96,0,1,123,3,2,1,0,10,10,1,8,0,65,0,253,15,253,98,11])); } catch (e) {} WC.simd = simd && !/[?&]nosimd=1/.test(location.search);
    fetch((WC.simd ? 'ca2core-simd.wasm' : 'ca2core.wasm') + '?v=202610221624').then(function (r) { if (!r.ok) throw new Error('http ' + r.status); return r.arrayBuffer(); }).then(function (b) { return WebAssembly.instantiate(b, {}); }).then(function (m) {
      var e = m.instance.exports; WC.mem = e.memory; WC.cells = e.cells_ptr; WC.out = e.out_ptr; WC.fieldX = e.mb_field; WC.field = e.mb_field_f32; WC.fieldF = e.mb_field_f32; if (e.sim_step) WC.e = e; WC.ok = true;
    }).catch(function (e) { WC.err = String(e); });
  }
  // ---- render sources: a round cell is one source; a string is a chain of discs along its heading; a lobed cell is a
  // main disc with small orbiting satellites. Every field path (wasm, WebGL, CPU) consumes this one list, so all draw the
  // same bodies and the wasm interface stays 6 f64 per source. One shared budget (the shader's uniform cap): when the
  // population is dense the strings shorten instead of pushing a path off its budget.
  var frameT = 0;
  var SRC_MAX = 384, SRC = { n: 0, cells: 0, built: -1, x: new Float32Array(512), y: new Float32Array(512), r: new Float32Array(512), wr: new Float32Array(512), wg: new Float32Array(512), wb: new Float32Array(512) };
  function srcGrow(n) { if (n <= SRC.x.length) return; var m = SRC.x.length * 2; while (m < n) m *= 2; ['x', 'y', 'r', 'wr', 'wg', 'wb'].forEach(function (k) { var a2 = new Float32Array(m); a2.set(SRC[k]); SRC[k] = a2; }); }
  function emitCell(c, t0, allowance, o) { // appends the cell's sources (plate-relative) to o = { x, y, r, n }
    var bx = c.x - cont.x, by = c.y - cont.y, sh = c.shp;
    // per-source squeeze (owner 22 Oct): string tails and lobed satellites narrow by their OWN distance to the gap
    // line too, so no body part ever inks past the wall (the centre-based cr below only covers the main disc)
    var pushSrc = function (sx, sy, sr) { var d = Math.min(sx - (P.boundGap > 0 ? P.boundGap : 0), cont.w - (P.boundGap > 0 ? P.boundGap : 0) - sx, sy - (P.boundGap > 0 ? P.boundGap : 0), cont.h - (P.boundGap > 0 ? P.boundGap : 0) - sy); o.x.push(sx); o.y.push(sy); o.r.push(Math.min(sr, Math.max(0.4, d))); o.n++; };
    // wall squeeze: the drawn body never crosses the gap line; a cell pressed at the wall compresses a little so the squeeze is felt (owner 21 Oct)
    var gap2 = Math.max(0, P.boundGap || 0), rFree = Math.max(1, Math.min(bx - gap2, cont.w - gap2 - bx, by - gap2, cont.h - gap2 - by));
    var cr = Math.min(c.radius, Math.max(1, rFree)) * (1 - P.squashMax * (c.sq || 0)); // eased squash state, no one-frame deflate/inflate (item 64 directive 2)
    if (P.cellShapes && sh && sh.t === 1 && allowance > 1) { // string: silhouette aspect asp, thickness th (short fat stubs are 2-3 discs)
      var rs = cr * sh.th, span = 2 * cr * sh.th * (sh.asp - 1), want = Math.min(9, Math.max(2, Math.round(span / (1.15 * rs)) + 1)), nn = Math.min(want, allowance);
      if (nn >= 2) {
        var ux = Math.cos(sh.dir), uy = Math.sin(sh.dir), px = -uy, py = ux, ds = span / (nn - 1), tq = t0 / 850 * (1 + sh.wsp) + sh.ph;
        for (var k = 0; k < nn; k++) { var d0 = -span / 2 + ds * k, off2 = sh.wig * rs * Math.sin(tq + k * 0.85); pushSrc(bx + ux * d0 + px * off2, by + uy * d0 + py * off2, rs); }
        return;
      }
    } else if (P.cellShapes && sh && sh.t === 2 && allowance > 2) { // lobed: amorf even standing alone
      var r0 = cr * 0.78, rot = t0 / 4200 * sh.wsp + sh.ph;
      pushSrc(bx, by, r0);
      for (var q2 = 0; q2 < sh.sat; q2++) {
        var aa = rot + q2 * 2.4 + sh.ph2, dd = cr * (0.42 + 0.24 * ((q2 * 0.731 + sh.ph) % 1)), rr2 = cr * (0.3 + 0.22 * ((q2 * 0.377 + sh.ph2) % 1));
        pushSrc(bx + Math.cos(aa) * dd, by + Math.sin(aa) * dd, rr2);
      }
      return;
    }
    pushSrc(bx, by, cr);
  }
  function buildSourcesW(t0) { // Rust/wasm buildSources+emitCell (bs.rs); returns false so the JS body below runs (?nowasm=1, ?nosim=1)
    var E = WC.e; if (!E || !E.bs_run || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1/.test(location.search)) return false;
    try {
      var n = cells.length, i, c, b;
      var rp = E.bs_alloc(n), rb = new Float64Array(WC.mem.buffer, rp, n * 17 + 17);
      var elapsed = performance.now() - fadeT0;
      for (i = 0; i < n; i++) {
        c = cells[i]; b = i * 17; var sh = c.shp || null;
        rb[b] = c.x; rb[b + 1] = c.y; rb[b + 2] = c.radius; rb[b + 3] = c.popD || 0; rb[b + 4] = c.alive ? 1 : 0;
        rb[b + 5] = sh ? sh.t : 0; rb[b + 6] = sh ? sh.th || 0 : 0; rb[b + 7] = sh ? sh.asp || 0 : 0; rb[b + 8] = sh ? sh.dir || 0 : 0;
        rb[b + 9] = sh ? sh.wsp || 0 : 0; rb[b + 10] = sh ? sh.ph || 0 : 0; rb[b + 11] = sh ? sh.wig || 0 : 0; rb[b + 12] = sh ? sh.sat || 0 : 0; rb[b + 13] = sh ? sh.ph2 || 0 : 0;
        var cwv = (P.genomeOn && c.g) ? c.g.col : c.cw;
        if (cwv) { rb[b + 14] = cwv[0]; rb[b + 15] = cwv[1]; rb[b + 16] = cwv[2]; }
        else if (c.gene > 2) { rb[b + 14] = 1; rb[b + 15] = 0; rb[b + 16] = 0; }
        else if (c.gene < -2) { rb[b + 14] = 0; rb[b + 15] = 1; rb[b + 16] = 0; }
        else { rb[b + 14] = 0; rb[b + 15] = 0; rb[b + 16] = 1; }
      }
      var m = E.bs_run(n, elapsed, t0, cont.x, cont.y, cont.w, cont.h, P.cellShapes ? 1 : 0, SRC_MAX, P.boundGap || 0);
      if (m < 0) return false;
      var st = new Float64Array(WC.mem.buffer, E.bs_stat(), 4), ob = E.bs_out(), c12 = st[2];
      srcGrow(m + 8);
      var obuf = WC.mem.buffer, rows = Math.floor(st[0]);
      SRC.x.set(new Float32Array(obuf, ob + 0 * c12 * 4, rows)); SRC.y.set(new Float32Array(obuf, ob + 1 * c12 * 4, rows)); SRC.r.set(new Float32Array(obuf, ob + 2 * c12 * 4, rows));
      SRC.wr.set(new Float32Array(obuf, ob + 3 * c12 * 4, rows)); SRC.wg.set(new Float32Array(obuf, ob + 4 * c12 * 4, rows)); SRC.wb.set(new Float32Array(obuf, ob + 5 * c12 * 4, rows));
      SRC.n = rows; SRC.cells = st[1]; WC.fwBs = (WC.fwBs || 0) + 1; return true;
    } catch (e) { WC.fwBsErr = String(e && e.stack || e); return false; }
  }
  function buildSources() {
    var t0 = frameT; if (t0 && SRC.built === t0) return SRC;
    SRC.built = t0;
    if (buildSourcesW(t0)) return SRC;
    var i, c, alive = 0;
    for (i = 0; i < cells.length; i++) { c = cells[i]; if (c.alive && introOn(c.popD) && c.x >= cont.x && c.x <= cont.x + cont.w && c.y >= cont.y && c.y <= cont.y + cont.h) alive++; }
    var allowance = alive > 1 ? Math.max(1, Math.floor(SRC_MAX / alive)) : SRC_MAX, n = 0, o = { x: [], y: [], r: [], n: 0 };
    for (i = 0; i < cells.length; i++) {
      c = cells[i];
      if (!c.alive || !introOn(c.popD) || c.x < cont.x || c.x > cont.x + cont.w || c.y < cont.y || c.y > cont.y + cont.h) continue;
      var wr = 0, wg = 0, wb = 0, cwv = (P.genomeOn && c.g) ? c.g.col : c.cw; if (cwv) { wr = cwv[0]; wg = cwv[1]; wb = cwv[2]; } else if (c.gene > 2) wr = 1; else if (c.gene < -2) wg = 1; else wb = 1;
      o.x.length = 0; o.y.length = 0; o.r.length = 0; o.n = 0; emitCell(c, t0, allowance, o);
      srcGrow(n + o.n + 8);
      for (var k = 0; k < o.n; k++) { SRC.x[n] = o.x[k]; SRC.y[n] = o.y[k]; SRC.r[n] = o.r[k]; SRC.wr[n] = wr; SRC.wg[n] = wg; SRC.wb[n] = wb; n++; }
    }
    SRC.n = n; SRC.cells = alive; return SRC;
  }

  // Rust/wasm sim step (ca2core sim.rs): the per-frame cell loop (update, organic, checkSurvival, hover colour, interact, keepIn) runs in wasm on
  // struct-of-arrays state packed from the cells each frame. Returns false (JS loop runs) when wasm/sim is unavailable or disabled (?nowasm=1, ?nosim=1).
  var simStamp = 0, SIMW = { ms: 0, on: false };
  function simSwim(c) { // JS body-plan swim (same as the block inside update(), applied after the wasm step: strings turn to their drift and swim with a wave)
    var sh2 = c.shp; sh2.svx = (sh2.svx || 0) * 0.94 + c.vx * 0.06; sh2.svy = (sh2.svy || 0) * 0.94 + c.vy * 0.06;
    var spv = Math.hypot(sh2.svx, sh2.svy);
    if (spv > 0.15) { var wa = Math.atan2(sh2.svy, sh2.svx), daa = wa - sh2.dir; while (daa > 3.1416) daa -= 6.2832; while (daa < -3.1416) daa += 6.2832; sh2.dir += daa * 0.12; }
    var swk = Math.sin(performance.now() / 700 * (1 + sh2.wsp) + sh2.ph) * sh2.wig * 0.05 * (c.maxSpeed * 0.4 + 0.4);
    c.vx += -Math.sin(sh2.dir) * swk; c.vy += Math.cos(sh2.dir) * swk;
    var vv = Math.hypot(c.vx, c.vy); if (vv > 0.05) { c.vx = lerp(c.vx, Math.cos(sh2.dir) * vv, 0.04); c.vy = lerp(c.vy, Math.sin(sh2.dir) * vv, 0.04); }
  }
  var WDRSN = {2: 'energy0', 3: 'crowd', 4: 'genebound', 5: 'oob', 6: 'select'}; // wasm sim.rs DRSN codes -> deathLog reasons (item 64, main 25 Oct)
  function simW(tmpRef) {
    var E = WC.e; if (E && /[?&]simab=1/.test(location.search) && (SIMW.t = !SIMW.t)) return false; if (!E || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1/.test(location.search)) { SIMW.on = false; return false; }
    try {
      var t0 = performance.now(), n = cells.length, cap = n + 256, nf = food.length, cl = Object.keys(cmean), ncm = cl.length, i, c, b;
      E.sim_cells(cap); E.sim_food(nf + 1); E.sim_cm(ncm + 1);
      var cp = E.sim_cells(cap), fxp = E.sim_food(nf + 1), fyp = E.sim_food_y(), fgp = E.sim_food_gone(), cmp = E.sim_cm(ncm + 1), cip = E.sim_cm_ids(), pp = E.sim_params();
      var buf = WC.mem.buffer, cf = new Float64Array(buf, cp, cap * 30), fx = new Float64Array(buf, fxp, nf + 1), fy = new Float64Array(buf, fyp, nf + 1), cmf = new Float64Array(buf, cmp, (ncm + 1) * 5), cid = new Float64Array(buf, cip, ncm + 1), p = new Float64Array(buf, pp, 97);
      simStamp++;
      for (i = 0; i < n; i++) {
        c = cells[i]; c._i = i; c._f = simStamp;
      }
      for (i = 0; i < n; i++) {
        c = cells[i]; b = i * 30; var g = c.g;
        cf[b] = c.x; cf[b + 1] = c.y; cf[b + 2] = c.vx; cf[b + 3] = c.vy; cf[b + 4] = c.radius; cf[b + 5] = c.energy; cf[b + 6] = c.gene; cf[b + 7] = c.alive ? 1 : 0; cf[b + 8] = c.maxSpeed; cf[b + 9] = c.speedModifier; cf[b + 10] = c.hostility; cf[b + 11] = c.mutationRate; cf[b + 12] = c.sv; cf[b + 13] = c.cl || 0;
        cf[b + 14] = (c.sym && c.sym._f === simStamp) ? c.sym._i : -1; cf[b + 15] = g.spd; cf[b + 16] = g.app; cf[b + 17] = g.bnd; cf[b + 18] = g.col[0]; cf[b + 19] = g.col[1]; cf[b + 20] = g.col[2]; cf[b + 21] = c.comp || 0; cf[b + 22] = 0; cf[b + 23] = frameT - (c.bornAt || 0); cf[b + 24] = c.sq || 0; cf[b + 25] = c.crowd || 0; cf[b + 26] = c.envVx || 0; cf[b + 27] = c.envVy || 0; cf[b + 28] = 0; cf[b + 29] = 0; // slot 23: age ms in, -1 = absorbed out; 22 is the wasm REM flag; 24: eased squash state, 25: crowd field (item 64); 26-27: environmental velocity (directive 3); 28: wasm wall-press signal out (the squash ease is a JS post-pass for both engines)
      }
      E.sim_set_n(n); E.sim_set_nf(nf);
      for (i = 0; i < nf; i++) { fx[i] = food[i].x; fy[i] = food[i].y; }
      for (i = 0; i < ncm; i++) { var m = cmean[cl[i]]; cid[i] = +cl[i]; cmf[i * 5] = m.vx; cmf[i * 5 + 1] = m.vy; cmf[i * 5 + 2] = m.x; cmf[i * 5 + 3] = m.y; cmf[i * 5 + 4] = m.e; }
      E.sim_cm_count(ncm);
      var pi = 0; p[0] = P.interactionRadius; p[1] = P.slowDownRadius; p[2] = P.speedReductionFactor; p[3] = P.baseMaxSpeed; p[4] = P.maxSpeedVariation; p[5] = P.energyConsumptionRate; p[6] = P.selectOn ? 1 : 0; p[7] = P.genomeOn ? 1 : 0; p[8] = P.selStrength; p[9] = P.eatMergeOn ? 1 : 0; p[10] = P.clusterCohesion; p[11] = P.symbiosisOn ? 1 : 0; p[12] = P.foodEatR; p[13] = P.foodEnergyValue; p[14] = P.foodGrow ? 1 : 0; p[15] = P.foodGrowAmt; p[16] = P.CELL_RADIUS; p[17] = P.foodGrowMax; p[18] = P.divideOn ? 1 : 0; p[19] = P.divideAt; p[75] = P.divideMode ? 1 : 0; p[76] = P.divideAgeMs; p[77] = P.divideEnergy;
      // 75-77: divideMode/age/mass gate
      p[20] = P.UNIVERSE_SIZE; p[21] = P.foodShrink; p[22] = P.boundAware ? 1 : 0; p[23] = P.boundZone; p[24] = P.boundForce; p[25] = P.restless; p[26] = P.eatRatio; p[27] = P.eatChance; p[28] = P.mergeGene; p[29] = P.mergeChance; p[30] = P.symbiogenesisOn ? 1 : 0; p[31] = P.energyGainFromInteraction; p[32] = P.GENE_MIN; p[33] = P.GENE_MAX; p[34] = P.minEnergyForReproduction; p[35] = P.clusterMax; p[36] = P.genomeMut; p[37] = P.mutationRateRange; p[38] = P.metaballStrength;
      p[39] = env.spd; p[40] = env.app; p[41] = env.bnd; p[42] = env.col ? 1 : 0; if (env.col) { p[43] = env.col[0]; p[44] = env.col[1]; p[45] = env.col[2]; }
      p[46] = mouse.x; p[47] = mouse.y; p[48] = mouse.over ? 1 : 0; p[49] = cont.x; p[50] = cont.y; p[51] = cont.w; p[52] = cont.h; p[53] = resizeDrag ? 1 : 0; p[54] = clusterSeq;
      p[80] = cont.wvx0 || 0; p[81] = cont.wvx1 || 0; p[82] = cont.wvy0 || 0; p[83] = cont.wvy1 || 0; p[84] = P.wallCarry === undefined ? 1 : P.wallCarry; p[85] = P.wallSpread === undefined ? 0.5 : P.wallSpread; // 80-85: piston carry edge velocities + factors (owner 25 Oct)
      p[86] = P.squashMax === undefined ? 0.18 : P.squashMax; p[87] = P.squashIn === undefined ? 0.45 : P.squashIn; p[88] = P.squashOut === undefined ? 0.08 : P.squashOut; // 86-88: eased squash state, contact+render (item 64)
      p[89] = P.senseR === undefined ? 1.6 : P.senseR; p[90] = P.senseSlow === undefined ? 0.25 : P.senseSlow; p[91] = P.senseTurn === undefined ? 0.12 : P.senseTurn; p[92] = P.senseDelay === undefined ? 0.5 : P.senseDelay; // 89-92: sensing band (item 64 directive 1)
      p[93] = P.crowdGain === undefined ? 0.12 : P.crowdGain; p[94] = P.crowdRel === undefined ? 0.02 : P.crowdRel; p[95] = P.crowdSlow === undefined ? 0.5 : P.crowdSlow; p[96] = P.crowdPush === undefined ? 0.3 : P.crowdPush; // 93-96: crowding field (item 64 directive 4)
      p[78] = frameDtf; p[79] = P.foodEatRate === undefined ? 1.5 : P.foodEatRate; // frame dt ms + grazing rate for sim.rs eat roll - 55/56 are NCM/ONLYINT, never pack them (6d7a61a collision disabled update() sitewide)
      p[57] = P.boundGap || 0; p[58] = P.reproMinAgeMs || 0; p[59] = P.reproChance === undefined ? 0.02 : P.reproChance; // 58: juvenile gate ms, 59: contact birth chance // boundGap slot for sim.rs keep_in (625f4e8 port); 44/45 are env.col
      p[60] = P.crowdTol; p[61] = P.orgLifeDie; p[62] = P.orgLifeGrow; p[63] = P.orgBirth; p[64] = P.orgDead; p[65] = P.orgBrain; p[66] = P.orgR90;
      p[67] = P.symEnergy; p[68] = P.symBreak; p[69] = P.symBreakDist; p[70] = P.eatDistF; p[71] = P.fuseDistF; p[72] = P.symDistF;
      p[73] = P.habitatOn ? 1 : 0; p[74] = P.habitatBirthCap; // habitat soft birth cap (sim.rs interact)
      var tp = performance.now(); E.sim_step(Math.floor(Math.random() * 4294967296), Math.floor(Math.random() * 4294967296));
      var ts = performance.now(); SIMW.pack = (SIMW.pack || 0) * 0.9 + (tp - t0) * 0.1; SIMW.step = (SIMW.step || 0) * 0.9 + (ts - tp) * 0.1;
      var o = new Float64Array(WC.mem.buffer, E.sim_out(), 32), nf2 = o[15];
      var kids = [];
      if (E.sim_cap && E.sim_cap() !== cap) { cap = E.sim_cap(); cp = E.sim_cells_ptr(); } // wasm grew its cell buffer on a birth burst: re-anchor before reading back
      cf = new Float64Array(WC.mem.buffer, cp, cap * 30);
      for (i = 0; i < nf2; i++) {
        b = i * 30; c = i < n ? cells[i] : new Cell(cf[b], cf[b + 1], cf[b + 6], cf[b + 11]);
        if (i >= n) { cells.push(c); c._i = i; c._f = simStamp; }
        c.x = cf[b]; c.y = cf[b + 1]; c.vx = cf[b + 2]; c.vy = cf[b + 3]; c.radius = cf[b + 4]; c.energy = cf[b + 5]; c.gene = cf[b + 6]; c.alive = cf[b + 7] !== 0; c.maxSpeed = cf[b + 8]; c.speedModifier = cf[b + 9]; c.hostility = cf[b + 10]; c.mutationRate = cf[b + 11]; c.sv = cf[b + 12]; c.cl = cf[b + 13];
        var gg = c.g; gg.spd = cf[b + 15]; gg.app = cf[b + 16]; gg.bnd = cf[b + 17]; gg.col = [cf[b + 18], cf[b + 19], cf[b + 20]]; if (cf[b + 21] > 0) c.comp = cf[b + 21]; c.absorbed = cf[b + 23] < 0 ? 1 : 0; c.sq = cf[b + 24]; c.crowd = cf[b + 25]; c.envVx = cf[b + 26]; c.envVy = cf[b + 27]; c.sqS = Math.max(c.sqS || 0, cf[b + 28]); c.wasmDr = cf[b + 29];
      }
      for (i = 0; i < nf2; i++) { var sy = cf[i * 30 + 14]; cells[i].sym = sy >= 0 ? cells[sy] : null; }
      var fg = new Float64Array(WC.mem.buffer, fgp, nf + 1);
      var lg = new Float64Array(WC.mem.buffer, E.sim_log(), o[17]); // births / fusions: body plans stay in JS (newShape/mixShape), the wasm core only reports who came from whom
      for (i = 0; i < lg.length; i += 4) { var kd = lg[i + 3], k0 = cells[lg[i]], p0 = cells[lg[i + 1]], p1 = lg[i + 2] >= 0 ? cells[lg[i + 2]] : null; if (kd === 1) k0.shp = newShape(p0.shp); else if (kd === 2) k0.shp = mixShape(p0.shp, p1.shp); else k0.shp = mixShape(k0.shp, p0.shp); }
      for (i = 0; i < cells.length; i++) { c = cells[i]; if (c.alive && c.shp && c.shp.t === 1) simSwim(c); }
      tmpRef.hc = o[16] >= 0 ? cells[o[16]] : null;
      for (i = nf - 1; i >= 0; i--) if (fg[i] !== 0) { habAte(food[i]); food[i].gone = 1; food.splice(i, 1); }
      ev.killSel = (ev.killSel || 0) + (o[20] || 0); ev.killEnergy = (ev.killEnergy || 0) + (o[21] || 0); ev.killCrowd = (ev.killCrowd || 0) + (o[22] || 0); ev.killGene = (ev.killGene || 0) + (o[23] || 0); // wasm kill-reason counters (sim.rs out[20-23], per-step, accumulated here into session totals) - actual death-path trace, no inference (main 25 Oct)
      ev.birth += o[0]; ev.divide = (ev.divide || 0) + o[1]; ev.eaten = (ev.eaten || 0) + o[2]; ev.merge = (ev.merge || 0) + o[3]; ev.fuse = (ev.fuse || 0) + o[4]; ev.pair = (ev.pair || 0) + o[5]; ev.hit += o[6]; ev.oob += o[7]; ev.ate = (ev.ate || 0) + o[8]; clusterSeq = o[10];
      for (i = cells.length - 1; i >= 0; i--) if (!cells[i].alive) { ev.death++; logDeath(cells[i], cells[i].__dr || WDRSN[cells[i].wasmDr] || 'untagged-wasm'); habReap(cells[i]); cells.splice(i, 1); }
      hovering = o[11] !== 0; tmpRef.v = [o[12], o[13], o[14]];
      SIMW.ms = SIMW.ms * 0.9 + (performance.now() - t0) * 0.1; SIMW.on = true; return true;
    } catch (e) { WC.simOff = true; WC.simErr = String(e); SIMW.on = false; return false; }
  }
  function drawMetaballsCPU(S) {
    var bw = Math.max(1, Math.ceil(cont.w * S)), bh = Math.max(1, Math.ceil(cont.h * S));
    if (bw !== bufW || bh !== bufH) {
      bufW = bw; bufH = bh; off.width = bw; off.height = bh; img = octx.createImageData(bw, bh); u32 = new Uint32Array(img.data.buffer);
      fSum = new Float32Array(bw * bh); fR = new Float32Array(bw * bh); fG = new Float32Array(bw * bh); fB = new Float32Array(bw * bh);
    } else { fSum.fill(0); fR.fill(0); fG.fill(0); fB.fill(0); }
    var ms = P.metaballStrength, TH = P.THRESHOLD, inv = 1 / S;
    var src = buildSources(), sn = src.n; // the squash ease runs once per frame in frame() (both engines): draw never mutates sim state
    if (WC.ok && !WC.off) { // Rust/wasm path (ca2core): same field + pixel pass, JS below stays as the fallback
      try {
        var nw = sn, cp = WC.cells(nw), cf = new Float64Array(WC.mem.buffer, cp, nw * 6);
        for (var i = 0; i < nw; i++) { var o6 = i * 6; cf[o6] = src.x[i]; cf[o6 + 1] = src.y[i]; cf[o6 + 2] = src.r[i]; cf[o6 + 3] = src.wr[i]; cf[o6 + 4] = src.wg[i]; cf[o6 + 5] = src.wb[i]; }
        WC.field(nw, bw, bh, S, ms, TH, bg[0] | 0, bg[1] | 0, bg[2] | 0); pfm('mb:field');
        img.data.set(new Uint8ClampedArray(WC.mem.buffer, WC.out(), bw * bh * 4)); pfm('mb:pixel loop');
        octx.putImageData(img, 0, 0); pfm('mb:putImageData');
        ctx.imageSmoothingEnabled = false; ctx.drawImage(off, 0, 0, bw, bh, cont.x, cont.y, cont.w, cont.h); ctx.globalAlpha = 1; pfm('mb:drawImage');
        return;
      } catch (e) { WC.off = true; WC.err = String(e); }
    }
    for (var i = 0; i < sn; i++) {
      var cx = src.x[i], cy = src.y[i], crd = src.r[i], r2 = ms * crd * crd;
      var Rc = crd * Math.max(3, Math.sqrt(ms / (TH * 0.03)));
      var x0 = Math.max(0, Math.floor((cx - Rc) * S)), x1 = Math.min(bw - 1, Math.ceil((cx + Rc) * S));
      var y0 = Math.max(0, Math.floor((cy - Rc) * S)), y1 = Math.min(bh - 1, Math.ceil((cy + Rc) * S));
      var wr = src.wr[i], wg = src.wg[i], wb = src.wb[i];
      for (var y = y0; y <= y1; y++) {
        var dy = (y + 0.5) * inv - cy, row = y * bw;
        for (var x = x0; x <= x1; x++) {
          var dx = (x + 0.5) * inv - cx, inf = r2 / (dx * dx + dy * dy + 0.0001);
          var i2 = inf * inf; fSum[row + x] += inf; if (wr) fR[row + x] += i2 * wr; if (wg) fG[row + x] += i2 * wg; if (wb) fB[row + x] += i2 * wb;
        }
      }
    }
    var br = bg[0] | 0, bgc = bg[1] | 0, bb = bg[2] | 0, ns = 0, band = TH * 0.08, p = 0, n = bw * bh;
    var data = img.data; pfm('mb:field');
    for (p = 0; p < n; p++) {
      var s = fSum[p], q = p << 2;
      if (s > TH * 0.96) {
        var r = fR[p], g = fG[p], b = fB[p], t = r + g + b; if (t > 0) { r /= t; g /= t; b /= t; }
        var nv = ns ? ((p * 2654435761 >>> 0) % 1000 / 500 - 1) * ns : 0, a = Math.min(1, (s - TH * 0.96) / band);
        data[q] = clamp(r * 255 + nv, 0, 255); data[q + 1] = clamp(g * 255 + nv, 0, 255); data[q + 2] = clamp(b * 255 + nv, 0, 255); data[q + 3] = a * 255;
      } else { data[q] = br; data[q + 1] = bgc; data[q + 2] = bb; data[q + 3] = 0; }
    }
    pfm('mb:pixel loop'); octx.putImageData(img, 0, 0); pfm('mb:putImageData');
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(off, 0, 0, bw, bh, cont.x, cont.y, cont.w, cont.h); ctx.globalAlpha = 1; pfm('mb:drawImage'); // exact fit to the area rectangle
  }

  // ---- GPU metaball field (WebGL fragment shader): same formula as the CPU splat, evaluated per pixel on the GPU.
  // The CPU path above stays as the fallback (no WebGL, too many cells, or ?cpu=1). colorAt() evaluates the same field analytically at one point (no GPU readback).
  var GMAX = 384, gShaderMax = 0, gl = null, glc = null, gProg = null, gProg384 = null, gU = {}, gOK = false, gSnap = null, gOn = false, gOv = 0; // GMAX: device-adaptive (initGL), 384 is only the floor; gShaderMax = compiled capacity (GMAX may be test-lowered)
  (function initGL() {
    if (/[?&]cpu=1/.test(location.search)) return;
    try {
      glc = document.createElement('canvas'); glc.width = glc.height = 1;
      gl = glc.getContext('webgl', { premultipliedAlpha: true, alpha: true, antialias: false, preserveDrawingBuffer: false, powerPreference: 'high-performance' });
      if (!gl) return;
      var dbg = gl.getExtension('WEBGL_debug_renderer_info'), rn = dbg ? String(gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL)) : '';
      if (/swiftshader|llvmpipe|software|softpipe/i.test(rn) && !/[?&]gpu=1/.test(location.search)) { gl = null; return; } // a software GL is slower than the CPU splat
      var vs = 'attribute vec2 p; void main(){ gl_Position = vec4(p, 0., 1.); }';
      function fs(gm) { return 'precision highp float;\n#define GMAX ' + gm + '\nuniform vec4 uC[GMAX]; uniform vec4 uW[GMAX]; uniform int uN; uniform float uS; uniform float uH; uniform float uTH; uniform float uBand;\n' +
        'void main(){ float px = gl_FragCoord.x / uS, py = (uH - gl_FragCoord.y) / uS; float s = 0.; vec3 w = vec3(0.);\n' +
        ' for (int i = 0; i < GMAX; i++) { if (i >= uN) break; vec4 c = uC[i]; float dx = px - c.x, dy = py - c.y; if (abs(dx) > c.w || abs(dy) > c.w) continue;\n' +
        '  float inf = c.z / (dx*dx + dy*dy + 0.0001); s += inf; w += uW[i].xyz * (inf*inf); }\n' +
        ' float lim = uTH * 0.96; if (s > lim) { float t = w.x + w.y + w.z; vec3 col = t > 0. ? w / t : vec3(0.); float a = min(1., (s - lim) / uBand); gl_FragColor = vec4(col * a, a); } else gl_FragColor = vec4(0.); }'; }
      function sh(t, src) { var o = gl.createShader(t); gl.shaderSource(o, src); gl.compileShader(o); if (!gl.getShaderParameter(o, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(o)); return o; }
      function linkProg(gm) { var p = gl.createProgram(); gl.attachShader(p, sh(gl.VERTEX_SHADER, vs)); gl.attachShader(p, sh(gl.FRAGMENT_SHADER, fs(gm))); gl.linkProgram(p); if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p)); return p; }
      // device-adaptive source capacity: each source costs two vec4 uniforms (uC+uW). Try the device limit, halve on link failure, 384 floor, 2048 ceiling. Crowd scenes exceed 384 sources; the fixed cap silently dropped to the CPU splat there.
      var maxV = gl.getParameter(gl.MAX_FRAGMENT_UNIFORM_VECTORS) || 224, gm = Math.max(384, Math.min(2048, Math.floor(maxV / 2) - 8));
      for (;; gm = gm >> 1) {
        try { gProg = linkProg(gm); GMAX = gm; gShaderMax = gm; break; } catch (e2) { if (gm <= 384) throw e2; }
      }
      if (GMAX > 384) { try { gProg384 = linkProg(384); } catch (e3) {} } // reference program for the bit-identity A/B gate (cmpGmax384)
      gl.useProgram(gProg);
      var buf = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buf); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
      var loc = gl.getAttribLocation(gProg, 'p'); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
      ['uC', 'uW', 'uN', 'uS', 'uH', 'uTH', 'uBand'].forEach(function (n) { gU[n] = gl.getUniformLocation(gProg, n); });
      gOK = true;
    } catch (e) { gOK = false; gl = null; if (window.console) console.warn('ca2: WebGL field off, CPU path', e && e.message); }
  })();
  var GMAXBUF = 2048, gT0 = 0, gN = 0, gC = new Float32Array(GMAXBUF * 4), gW = new Float32Array(GMAXBUF * 4);
  var gTC = new Float32Array(GMAXBUF * 4), gTW = new Float32Array(GMAXBUF * 4), GTILE = 256; // tiled draw: per-tile culled source lists (buffer px)
  // one tile: cull by the exact per-source influence square (the shader culls with the same Rc per pixel),
  // subdivide when a tile still exceeds the device source capacity; clamp only as a counted last resort.
  var gTStat = { subdiv: 0, leaves: 0, sumM: 0, maxM: 0, clamp: 0 }, gZeroTail = false;
  function gpuTiles(C, W, n, bx0, by0, bx1, by1, depth) {
    var m = 0, i, inv = 1 / (gSnapS || 1);
    for (i = 0; i < n; i++) {
      var sx = C[i * 4] / inv, sy = C[i * 4 + 1] / inv, sr = C[i * 4 + 3] / inv; // to buffer px
      if (sx + sr < bx0 || sx - sr > bx1 || sy + sr < by0 || sy - sr > by1) continue;
      if (m >= GMAX) break;
      gTC[m * 4] = C[i * 4]; gTC[m * 4 + 1] = C[i * 4 + 1]; gTC[m * 4 + 2] = C[i * 4 + 2]; gTC[m * 4 + 3] = C[i * 4 + 3];
      gTW[m * 4] = W[i * 4]; gTW[m * 4 + 1] = W[i * 4 + 1]; gTW[m * 4 + 2] = W[i * 4 + 2]; m++;
    }
    if (m >= GMAX && depth < 4) { gTStat.subdiv++; // too many sources reach this tile: quarter it (culling then keeps every contributing source)
      var mx = (bx0 + bx1) >> 1, my = (by0 + by1) >> 1;
      gpuTiles(C, W, n, bx0, by0, mx, my, depth + 1); gpuTiles(C, W, n, mx, by0, bx1, my, depth + 1);
      gpuTiles(C, W, n, bx0, my, mx, by1, depth + 1); gpuTiles(C, W, n, mx, my, bx1, by1, depth + 1);
      return;
    }
    if (!m) return;
    if (m >= GMAX) { gOv++; gTStat.clamp++; } // pathological density beyond 16px tiles: counted, rendered with the first GMAX in reach order
    gTStat.leaves++; gTStat.sumM += m; gTStat.maxM = Math.max(gTStat.maxM, m);
    if (gZeroTail) { gTC.fill(0, m * 4); gTW.fill(0, m * 4); } // diagnostic: rule out stale uniform tails past uN
    gl.uniform4fv(gU.uC, gTC.subarray(0, m * 4)); gl.uniform4fv(gU.uW, gTW.subarray(0, m * 4)); gl.uniform1i(gU.uN, m);
    gl.scissor(bx0, gSnapBH - by1, bx1 - bx0, by1 - by0);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  }
  var gSnapS = 0, gSnapBH = 0, gTiledForce = null;
  // shared draw body (full or tiled) so tests can render the SAME source array through both paths
  function gpuDraw(C, W, n, bw, bh, S, tiled) {
    gl.viewport(0, 0, bw, bh); gl.useProgram(gProg);
    gl.uniform1f(gU.uS, S); gl.uniform1f(gU.uH, bh); gl.uniform1f(gU.uTH, P.THRESHOLD); gl.uniform1f(gU.uBand, P.THRESHOLD * 0.08);
    gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT);
    gSnapS = S; gSnapBH = bh; gOv = 0; gTStat.subdiv = 0; gTStat.leaves = 0; gTStat.sumM = 0; gTStat.maxM = 0; gTStat.clamp = 0;
    if (!tiled || n <= 64) {
      gl.uniform4fv(gU.uC, C.subarray(0, n * 4)); gl.uniform4fv(gU.uW, W.subarray(0, n * 4)); gl.uniform1i(gU.uN, n);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    } else {
      gl.enable(gl.SCISSOR_TEST);
      var txN = Math.ceil(bw / GTILE), tyN = Math.ceil(bh / GTILE);
      for (var ty = 0; ty < tyN; ty++) for (var tx = 0; tx < txN; tx++)
        gpuTiles(C, W, n, tx * GTILE, ty * GTILE, Math.min(bw, (tx + 1) * GTILE), Math.min(bh, (ty + 1) * GTILE), 0);
      gl.disable(gl.SCISSOR_TEST);
    }
  }
  function drawMetaballs(S) {
    gOn = false;
    if (gOK && !gl.isContextLost()) {
      var ms = P.metaballStrength, TH = P.THRESHOLD, n = 0, src = window.__t119src || buildSources(), i; // __t119src: harness-only frozen source injection (t119cluster)
      for (i = 0; i < src.n; i++) {
        if (n >= GMAX) { n = -1; break; }
        gC[n * 4] = src.x[i]; gC[n * 4 + 1] = src.y[i]; gC[n * 4 + 2] = ms * src.r[i] * src.r[i]; gC[n * 4 + 3] = src.r[i] * Math.max(3, Math.sqrt(ms / (TH * 0.03)));
        gW[n * 4] = src.wr[i]; gW[n * 4 + 1] = src.wg[i]; gW[n * 4 + 2] = src.wb[i]; n++;
      }
      if (n >= 0) {
        var bw = Math.max(1, Math.ceil(cont.w * S)), bh = Math.max(1, Math.ceil(cont.h * S));
        if (glc.width !== bw || glc.height !== bh) { glc.width = bw; glc.height = bh; }
        gpuDraw(gC, gW, n, bw, bh, S, gTiledForce !== null ? gTiledForce : Math.ceil(bw / GTILE) * Math.ceil(bh / GTILE) > 1); // tiled beyond one tile; the per-pixel formula is untouched (gTiledForce: harness A/B only)
        if (gOv > 0) { var ov = gOv; gpuDraw(gC, gW, n, bw, bh, S, false); gOv = ov; } // a 16px leaf hit capacity even after subdivision (only possible at n=GMAX fully clustered, m<=n<=GMAX): never show the clamped source-dropping tiles - clear and re-render the SAME packed sources through the full pass, which holds all n<=GMAX<=gShaderMax. gpuDraw resets gOv, so restore the engagement counter.
        pfm('gpu:draw+field'); gT0 = performance.now();
        ctx.imageSmoothingEnabled = false; ctx.drawImage(glc, 0, 0, bw, bh, cont.x, cont.y, cont.w, cont.h); ctx.globalAlpha = 1; pfm('gpu:drawImage'); if (++gN > 40 && PF['gpu:drawImage'] + PF['gpu:draw+field'] > 90 && !/[?&]gpu=1/.test(location.search)) gOK = false; // too slow on this machine: back to the CPU path
        gSnap = { n: n, S: S, bw: bw, bh: bh, TH: TH }; gOn = true; return;
      }
    }
    drawMetaballsCPU(S);
  }
  function colorAtGPU(x, y) {
    var S = gSnap.S, bx = Math.min(gSnap.bw - 1, Math.floor((x - cont.x) * S)), by = Math.min(gSnap.bh - 1, Math.floor((y - cont.y) * S));
    var px = (bx + 0.5) / S, py = (by + 0.5) / S, s = 0, r = 0, g = 0, b = 0, TH = gSnap.TH;
    for (var i = 0; i < gSnap.n; i++) {
      var dx = px - gC[i * 4], dy = py - gC[i * 4 + 1], R = gC[i * 4 + 3]; if (Math.abs(dx) > R || Math.abs(dy) > R) continue;
      var inf = gC[i * 4 + 2] / (dx * dx + dy * dy + 0.0001), i2 = inf * inf; s += inf; r += i2 * gW[i * 4]; g += i2 * gW[i * 4 + 1]; b += i2 * gW[i * 4 + 2];
    }
    if (s > TH * 0.96) { var t = r + g + b; if (t > 0) { r /= t; g /= t; b /= t; } var al = Math.min(1, (s - TH * 0.96) / (TH * 0.08)); return [bg[0] + (r * 255 - bg[0]) * al, bg[1] + (g * 255 - bg[1]) * al, bg[2] + (b * 255 - bg[2]) * al]; }
    return [bg[0], bg[1], bg[2]];
  }
  function colorAt(x, y) {
    if (gOn && gSnap && x >= cont.x && x < cont.x + cont.w && y >= cont.y && y < cont.y + cont.h) return colorAtGPU(x, y);
    if (img && x >= cont.x && x < cont.x + cont.w && y >= cont.y && y < cont.y + cont.h) {
      var bx = Math.min(bufW - 1, Math.floor((x - cont.x) * curS)), by = Math.min(bufH - 1, Math.floor((y - cont.y) * curS)), q = (by * bufW + bx) * 4;
      var al = img.data[q + 3] / 255;
      return [bg[0] + (img.data[q] - bg[0]) * al, bg[1] + (img.data[q + 1] - bg[1]) * al, bg[2] + (img.data[q + 2] - bg[2]) * al];
    }
    return [bg[0], bg[1], bg[2]];
  }
  function invAt(x, y) { var c = colorAt(x, y); return [255 - c[0], 255 - c[1], 255 - c[2]]; }
  function invArea(x, y) {
    var s = [0, 0, 0], n = 0;
    for (var i = -1; i <= 1; i++) for (var j = -1; j <= 1; j++) { var c = colorAt(x + i, y + j); s[0] += c[0]; s[1] += c[1]; s[2] += c[2]; n++; }
    return [255 - s[0] / n, 255 - s[1] / n, 255 - s[2] / n];
  }

  // ink bounds of a string in the current font: [ink left from origin, ink right from origin].
  // Margins are measured from real ink, so the font's side bearings (lsb/rsb) cannot skew them.
  function inkLR(s) {
    if (!s || !s.length) return [0, 0];
    var f = ctx.measureText(s[0]), pre = s.length > 1 ? ctx.measureText(s.slice(0, -1)).width : 0, l = ctx.measureText(s[s.length - 1]);
    return [f.actualBoundingBoxLeft, pre + l.actualBoundingBoxRight];
  }

  // ---- axis lines: width, center gap and diagonal length are parameters ----
  function drawAxis(L, sT, sX, geometryOnly) {
    var M = L.M, G = L.G, fs = L.fs, dh = L.dh, cxm = W / 2, cym = H / 2;
    ctx.font = fs + 'px "Ca2-Thin", monospace';
    ctx.textAlign = 'left'; var lrT = inkLR(sT), lrX = inkLR(sX);
    var hL = M + (lrT[1] - lrT[0]) + G, hR = (W - M) - (lrX[1] - lrX[0]) - G, vTop = M + dh + L.row + G, vBot = H - M - dh - G, g = P.centerGap;
    var X = P.axisLayer === 0 ? ctx : lctx, S = P.axisLayer === 0 ? DPR : DD; // axis behind the cells lives on the plate canvas (cells cover it); on top it uses the exact-resolution layer
    X.strokeStyle = P.axisColor || css(eased.axis, 1); X.lineWidth = LW(); // visual stroke follows line width; separator collision remains a hairline
    X.lineCap = 'butt';
    var segs = [];
    if (g > 0) { segs.push([hL, cym, cxm - g, cym], [cxm + g, cym, hR, cym], [cxm, vTop, cxm, cym - g], [cxm, cym + g, cxm, vBot]); }
    else segs.push([hL, cym, hR, cym], [cxm, vTop, cxm, vBot]);
    [[0, H], [W, H]].forEach(function (cn) {
      var ex = lerp(cxm, cn[0], P.diagLen), ey = lerp(cym, cn[1], P.diagLen), dx = ex - cxm, dy = ey - cym, len = Math.hypot(dx, dy);
      if (len > g) segs.push([cxm + dx / len * g, cym + dy / len * g, ex, ey]);
    });
    for (var si = 0; !geometryOnly && si < segs.length; si++) if (P.axisWidth > 0 && fadeA('ax' + si)) { var sg = segs[si].slice(); if (sg[0] === sg[2] || sg[1] === sg[3]) for (var q = 0; q < 4; q++) sg[q] = snapC(sg[q], S); X.beginPath(); X.moveTo(sg[0], sg[1]); X.lineTo(sg[2], sg[3]); X.stroke(); }
    axisInfo = { hL: hL, hR: hR, vTop: vTop, vBot: vBot, segs: segs };
  }
  var axisInfo = {};

  // ---- axis separator (owner 22 Oct, switch, default off): the axis line behind the boundary works as a
  // separator inside the moving boundary; cells are aware of every typographic element on the page. Letter
  // ink is an obstacle; empty counters remain accessible;
  // the axis segments are hard walls with the same carry rule as the plate boundary, so a moving boundary
  // sweeps the cells through the separators as a natural result of the interaction (no separate sweep effect).
  var SEP = { c: null, mc: null, img: null, mw: 0, mh: 0 };
  var COS8 = [1, 0.7071, 0, -0.7071, -1, -0.7071, 0, 0.7071], SIN8 = [0, 0.7071, 1, 0.7071, 0, -0.7071, -1, -0.7071];
  function sepInk(x, y) {
    var d = SEP.img; if (!d) return 0;
    var ix = (x * 0.5) | 0, iy = (y * 0.5) | 0;
    if (ix < 0 || iy < 0 || ix >= SEP.mw || iy >= SEP.mh) return 0;
    return d[(iy * SEP.mw + ix) * 4 + 3] > 40 ? 1 : 0;
  }
  function sepDiskHit(x, y, r) {
    if (!SEP.img) return false;
    var x0 = Math.max(0, Math.floor((x-r)*.5)), x1 = Math.min(SEP.mw-1, Math.ceil((x+r)*.5));
    var y0 = Math.max(0, Math.floor((y-r)*.5)), y1 = Math.min(SEP.mh-1, Math.ceil((y+r)*.5)), rr = (r + 1.42) * (r + 1.42);
    for (var yy = y0; yy <= y1; yy++) for (var xx = x0; xx <= x1; xx++) {
      var dx = xx*2+1-x, dy = yy*2+1-y;
      if (dx*dx+dy*dy <= rr && SEP.img[(yy*SEP.mw+xx)*4+3] > 40) return true;
    }
    return false;
  }
  // The renderer adds source fields before thresholding. A round centre proxy misses the
  // lobes; test the same sum at glyph ink pixels, including antialias fringe.
  function sepBody(c, allowance) {
    var o = { x: [], y: [], r: [], n: 0 }, bound = 0;
    emitCell(c, frameT, allowance || SRC_MAX, o);
    var scale = Math.sqrt(Math.max(0, P.metaballStrength) * Math.max(1, o.n) / Math.max(0.001, P.THRESHOLD * 0.96));
    for (var i = 0; i < o.n; i++) { o.x[i] += cont.x - c.x; o.y[i] += cont.y - c.y; bound = Math.max(bound, Math.hypot(o.x[i], o.y[i]) + o.r[i] * scale); }
    o.bound = bound; return o;
  }
  function sepBodyField(body, x, y) {
    var field = 0;
    for (var k = 0; k < body.n; k++) { var dx = x-body.x[k], dy = y-body.y[k]; field += P.metaballStrength*body.r[k]*body.r[k]/(dx*dx+dy*dy+0.0001); }
    return field;
  }
  function sepBodyLineHit(body, x, y, sg) {
    var dx=sg[2]-sg[0], dy=sg[3]-sg[1], len=Math.hypot(dx,dy); if (!len) return false;
    var ux=dx/len, uy=dy/len, along=(x-sg[0])*ux+(y-sg[1])*uy, normal=(x-sg[0])*(-uy)+(y-sg[1])*ux;
    if (Math.abs(normal)>body.bound+1 || along < -body.bound || along > len+body.bound) return false;
    var lo=Math.max(0,along-body.bound-1), hi=Math.min(len,along+body.bound+1), n=Math.max(1,Math.ceil(hi-lo));
    for(var i=0;i<=n;i++){var t=lo+(hi-lo)*i/n;if(sepBodyField(body,sg[0]+ux*t-x,sg[1]+uy*t-y)>P.THRESHOLD*.96)return true;}
    return false;
  }
  function sepBodyHit(body, x, y) {
    if (!SEP.img || !sepDiskHit(x, y, body.bound)) return false;
    var r = body.bound + 1.42, x0 = Math.max(0, Math.floor((x-r)*.5)), x1 = Math.min(SEP.mw-1, Math.ceil((x+r)*.5));
    var y0 = Math.max(0, Math.floor((y-r)*.5)), y1 = Math.min(SEP.mh-1, Math.ceil((y+r)*.5));
    for (var yy = y0; yy <= y1; yy++) for (var xx = x0; xx <= x1; xx++) {
      if (SEP.img[(yy*SEP.mw+xx)*4+3] <= 40) continue;
      var field = 0;
      for (var k = 0; k < body.n; k++) {
        var dx = Math.max(0, Math.abs(xx*2+1-x-body.x[k])-1), dy = Math.max(0, Math.abs(yy*2+1-y-body.y[k])-1);
        field += P.metaballStrength * body.r[k] * body.r[k] / (dx*dx+dy*dy+0.0001);
      }
      if (field > P.THRESHOLD * 0.96) return true;
    }
    return false;
  }
  // ---- food and typography (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02): food obeys the cells' letter exclusion. Same mask (SEP.img via sepDiskHit), same
  // switch (separatorOn + HUD). Spawns resample on the real mask; motion that would enter ink is stopped like a wall (slide
  // along the free axis, else hold, velocity reflected); no teleport search. Parasites fly and are exempt.
  function foodInkOn() { return !!(P.separatorOn && P.showHud && SEP.img); }
  function foodOnInk(x, y) { return foodInkOn() && sepDiskHit(x, y, Math.max(0.5, P.foodSize / 2)); }
  var inkFrac = { img: null, p: 0 };
  function foodInkFrac() { // fraction of mask pixels that are ink; recounted once per rebuilt mask
    if (inkFrac.img === SEP.img) return inkFrac.p;
    var d = SEP.img, n = SEP.mw * SEP.mh, c = 0; for (var i = 3; i < d.length; i += 4) if (d[i] > 40) c++;
    inkFrac.img = d; inkFrac.p = n ? c / n : 0; return inkFrac.p;
  }
  var inkFree = { img: null, idx: null };
  function foodFreeIdx() { // free (non-ink) mask pixels, row-major, built once per rebuilt mask
    if (inkFree.img === SEP.img) return inkFree.idx;
    var d = SEP.img, n = SEP.mw * SEP.mh, c = 0, i, k = 0, a;
    for (i = 0; i < n; i++) if (d[i * 4 + 3] <= 40) c++;
    a = new Uint32Array(c); for (i = 0; i < n; i++) if (d[i * 4 + 3] <= 40) a[k++] = i;
    inkFree.img = d; inkFree.idx = a; return a;
  }
  function foodSpot(x, y, w, h) { // random point in the rect that is not on ink; work is bounded by the mask itself
    var ink = foodInkOn(), px, py, t;
    if (!ink) return { x: x + Math.random() * w, y: y + Math.random() * h };
    var p = foodInkFrac();
    if (p >= 1) return null;
    if (p <= 0.5) { // mostly free: plain draws, at most ceil(ln .001 / ln .5) = 10
      for (t = 0; t < 10; t++) { px = x + Math.random() * w; py = y + Math.random() * h; if (!foodOnInk(px, py)) return { x: px, y: py }; }
      return null;
    }
    // mostly ink: choose among the free mask pixels of the rows the rect covers (sorted index, binary search); tries never exceed that slice
    var idx = foodFreeIdx(), mw = SEP.mw, st = foodMaskPx(), r0 = Math.max(0, Math.floor(y / st)), r1 = Math.min(SEP.mh - 1, Math.floor((y + h) / st));
    var lo = lowerBound(idx, r0 * mw), hi = lowerBound(idx, (r1 + 1) * mw), n = hi - lo;
    for (t = 0; t < n; t++) {
      var q = idx[lo + Math.floor(Math.random() * n)], cx = q % mw, cy = (q - cx) / mw;
      px = (cx + Math.random()) * st; py = (cy + Math.random()) * st;
      if (px >= x && px <= x + w && py >= y && py <= y + h && !foodOnInk(px, py)) return { x: px, y: py };
    }
    return null; // no free space left (or bad luck): the spawn is skipped, nothing is forced onto ink
  }
  function lowerBound(a, v) { var lo = 0, hi = a.length; while (lo < hi) { var m = (lo + hi) >> 1; if (a[m] < v) lo = m + 1; else hi = m; } return lo; }
  function foodMaskPx() { return SEP.mw ? W / SEP.mw : 2; } // one mask pixel in page px: the exact resolution of the ink geometry
  function foodPushOut(f) { // carried along the shortest way out (first free mask pixel on each of 8 rays, bounded by the page)
    var st = foodMaskPx(), bk = -1, bl = 1e9;
    for (var k = 0; k < 8; k++) { var ln = 1, rx = f.x + COS8[k] * st, ry = f.y + SIN8[k] * st; while (ln < bl && rx > 0 && ry > 0 && rx < W && ry < H && foodOnInk(rx, ry)) { ln++; rx += COS8[k] * st; ry += SIN8[k] * st; } if (ln < bl && rx > 0 && ry > 0 && rx < W && ry < H) { bl = ln; bk = k; } }
    if (bk >= 0) { f.x += COS8[bk] * st * bl; f.y += SIN8[bk] * st * bl; } // carried to the first free mask pixel, as a wall carries a cell
    else { // no straight way out (a large inked mass): the nearest free mask pixel, scanned over the cached free list (bounded by the mask)
      var idx = foodFreeIdx(), mw = SEP.mw, bd = 1e18, bx = f.x, by = f.y, q, cx, cy, qx, qy, d2;
      for (q = 0; q < idx.length; q++) { cx = idx[q] % mw; cy = (idx[q] - cx) / mw; qx = (cx + 0.5) * st; qy = (cy + 0.5) * st; d2 = (qx - f.x) * (qx - f.x) + (qy - f.y) * (qy - f.y); if (d2 < bd && !foodOnInk(qx, qy)) { bd = d2; bx = qx; by = qy; } }
      f.x = bx; f.y = by;
    }
  }
  function foodInkGuard() {
    if (!foodInkOn()) { for (var j = 0; j < food.length; j++) food[j]._pk = 0; return; }
    var i, f, on, owned, w = 0;
    for (i = 0; i < food.length; i++) {
      f = food[i]; owned = f.blob || f.worm || f.spore; on = foodOnInk(f.x, f.y);
      if (on) {
        if (f._pk === 1) { // had a free position last frame: do not enter ink
          if (!foodOnInk(f.x, f._py)) { f.y = f._py; if (f.vy !== undefined) f.vy = -f.vy * 0.5; }
          else if (!foodOnInk(f._px, f.y)) { f.x = f._px; if (f.vx !== undefined) f.vx = -f.vx * 0.5; }
          else { f.x = f._px; f.y = f._py; if (f.vx !== undefined) { f.vx = -f.vx * 0.5; f.vy = -f.vy * 0.5; } if (foodOnInk(f.x, f.y)) foodPushOut(f); }
        } else if (f._pk === 2 || f._pk === 0) { // ink arrived under a resting dot (changing HUD digits, moving title): carried off the ink like a cell off a wall
          foodPushOut(f);
        } else if (f._pk === undefined) { if (owned) foodPushOut(f); else { f.gone = 1; continue; } } // newborn dot on ink (a mode's own birth/spawn): refused, density reseed refills elsewhere
        if (foodOnInk(f.x, f.y)) { f.gone = 1; continue; } // no free mask pixel to carry it to: dropped, never kept on ink
      }
      f._pk = foodOnInk(f.x, f.y) ? 2 : 1; f._px = f.x; f._py = f.y; food[w++] = f;
    }
    food.length = w;
  }
  function separatorPass() {
    var segs = P.showAxis && axisInfo.segs ? axisInfo.segs : null, mask = P.showHud && SEP.img ? 1 : 0;
    if (!segs && !mask) return;
    for (var i = 0; i < cells.length; i++) {
      var c = cells[i]; if (!c.alive) continue;
      if (c.__sepT !== frameT) { c.__sepT = frameT; c.__sepU = 0; } // f9: ONE positional-correction budget per cell per FRAME across every separator invocation (73d-1)
      var r = c.radius * Math.sqrt(Math.max(0, P.metaballStrength) / Math.max(0.001, P.THRESHOLD)) + Math.min(LW(), 1 / DD) / 2, j, dx, dy, d, nx, ny;
      var habF = 1 - (P.habMax === undefined ? 0.6 : P.habMax) * (c.hab || 0); // item 64 directive 5: habituation weakens the startle, quiet restores it (state updated below)
      if (segs && isFinite(c._sepX) && isFinite(c._sepY)) for (j = 0; j < segs.length; j++) {
        var es = segs[j], ex = es[2] - es[0], ey = es[3] - es[1], el = Math.hypot(ex, ey); if (!el) continue;
        var enX = -ey / el, enY = ex / el, oldD = (c._sepX - es[0]) * enX + (c._sepY - es[1]) * enY, newD = (c.x - es[0]) * enX + (c.y - es[1]) * enY;
        if (oldD * newD < 0) {
          var hitT = oldD / (oldD - newD), hitX = c._sepX + (c.x - c._sepX) * hitT, hitY = c._sepY + (c.y - c._sepY) * hitT, along = ((hitX - es[0]) * ex + (hitY - es[1]) * ey) / (el * el);
          if (along >= 0 && along <= 1) { var side = oldD > 0 ? 1 : -1; var q9g = (c.maxSpeed || 0) + 1, back9 = Math.min(r, Math.max(0, q9g - (c.__sepU || 0))); c.__sepU = (c.__sepU || 0) + back9; c.x = hitX + enX * side * back9; c.y = hitY + enY * side * back9; var nv = c.vx * enX + c.vy * enY; if (nv * side < 0) { c.vx -= (1 + 0.7 * habF) * nv * enX; c.vy -= (1 + 0.7 * habF) * nv * enY; } }
        }
      }
      var pr = 0, solverOn = (P.solverIters === undefined ? 0 : P.solverIters) > 0;
      if (segs && !solverOn) for (var it2 = 0; it2 < 3; it2++) { // combined normals: a body pinched in a wedge between two
        // segments (arm end + diagonal start) is pushed along the sum, which drifts it out of the wedge -
        // per-segment resolution ping-pongs there forever (measured: 2 stuck cells, 35 px violation, 80 iterations)
        var acx = 0, acy = 0, worst = 0, anyV = false;
        for (j = 0; j < segs.length; j++) {
          var sg = segs[j], ax = sg[2] - sg[0], ay = sg[3] - sg[1], L2 = ax * ax + ay * ay, t = L2 ? clamp(((c.x - sg[0]) * ax + (c.y - sg[1]) * ay) / L2, 0, 1) : 0;
          var px = sg[0] + ax * t, py = sg[1] + ay * t; dx = c.x - px; dy = c.y - py; d = Math.hypot(dx, dy);
          if (d < r) { // body on the line: carry off, reflect the normal velocity like wallPull
            if (d < 0.001) { nx = -ay; ny = ax; var nl = Math.hypot(nx, ny) || 1; nx /= nl; ny /= nl; if (c.vx * nx + c.vy * ny < 0) { nx = -nx; ny = -ny; } }
            else { nx = dx / d; ny = dy / d; }
            var need = r - d; acx += nx * need; acy += ny * need; if (need > worst) worst = need; anyV = true;
            var pr2 = need / r; if (pr2 > pr) pr = pr2; // pressure measured DURING resolution: the plate clamp can re-press a body the resolver just freed
            var vn = c.vx * nx + c.vy * ny; if (vn < 0) { c.vx -= vn * (1 + 0.7 * habF) * nx; c.vy -= vn * (1 + 0.7 * habF) * ny; }
          }
        }
        if (!anyV) break;
        var al = Math.hypot(acx, acy);
        if (al < 0.001) break; // perfectly opposed normals: hold position, velocity already reflected
        var q9 = (c.maxSpeed || 0) + 1, rem9 = Math.max(0, q9 - (c.__sepU || 0)); // f9: same per-cell quantum as the collective pass (maxSpeed+1), shared by every separator correction this frame
        var st = Math.min(al, worst + 1, rem9); if (st <= 0) break; c.__sepU += st; c.x += acx / al * st; c.y += acy / al * st;
      }
      // the separator narrows what presses it (same rule as the plate wall, owner 22 Oct): a giant whose body
      // cannot fit between the lines is worn down toward the base radius until it fits
      if (solverOn && (c.__solverPr || 0) > pr) pr = c.__solverPr; // directive 6: pressure measured by the unified solver
      if (pr > (c.sqS || 0)) c.sqS = Math.min(1, pr); // item 64: reversible squash, zero permanent size loss
      if (pr > (c.crowd || 0)) c.crowd = Math.min(1, pr); // directive 4: separator pressure feeds the same field (JS post-pass, both engines)
      // item 64 directive 1 (separators): sensing before contact, same rule as the boundary band - slow +
      // along-line drift in [r, r*senseR*bnd), staggered by a deterministic per-cell hash (no RNG), so no
      // two cells react identically at the hairline. JS-only like the whole separator stack (no wasm path).
      var seR = P.senseR === undefined ? 1.6 : P.senseR;
      if (segs && seR > 1 && (P.senseSlow || P.senseTurn)) {
        var sh1 = c.gene * 0.6180339887; sh1 -= Math.floor(sh1);
        var sh2 = c.maxSpeed * 0.7548776662; sh2 -= Math.floor(sh2);
        var sDel2 = sh1 * (P.senseDelay === undefined ? 0.5 : P.senseDelay), szs = r * (1 + (seR - 1) * (P.genomeOn ? c.g.bnd : 1));
        for (j = 0; j < segs.length; j++) {
          var ss = segs[j], sax = ss[2] - ss[0], say = ss[3] - ss[1], sL2 = sax * sax + say * say; if (!sL2) continue;
          var st2 = clamp(((c.x - ss[0]) * sax + (c.y - ss[1]) * say) / sL2, 0, 1);
          var spx = ss[0] + sax * st2, spy = ss[1] + say * st2, sdd = Math.hypot(c.x - spx, c.y - spy);
          if (sdd >= szs || sdd < r) continue;
          var st0 = 1 - (sdd - r) / Math.max(1e-6, szs - r), sst = clamp((st0 - sDel2) / Math.max(1e-6, 1 - sDel2), 0, 1) * habF; if (sst <= 0) { if (st0 > sDel2) c.__habT = 1; continue; }
          c.__habT = 1;
          var sdamp = 1 - (P.senseSlow === undefined ? 0.25 : P.senseSlow) * sst; c.vx *= sdamp; c.vy *= sdamp;
          var sl = Math.sqrt(sL2), stdr = (P.senseTurn === undefined ? 0.12 : P.senseTurn) * sst * (c.maxSpeed + 1) * (sh2 < 0.5 ? -1 : 1) * 0.5;
          c.vx += sax / sl * stdr; c.vy += say / sl * stdr;
        }
      }
      // directive 5 state: contact/near-contact builds habituation (genome-weighted), quiet restores it
      { var hb = P.habRate === undefined ? 0.02 : P.habRate, hbd = P.habDecay === undefined ? 0.005 : P.habDecay, hek = frameDtf * 0.06;
        if (pr > 0 || c.__habT) c.hab = Math.min(1, (c.hab || 0) + (1 - Math.pow(1 - hb, hek)) * (P.genomeOn ? c.g.bnd : 1));
        else c.hab = Math.max(0, (c.hab || 0) - (1 - Math.pow(1 - hbd, hek)));
        c.__habT = 0; }
      // Resolve the lobes against the hairline itself, without replacing it with a broad bounding wall.
      var inkBody = (mask || segs) ? sepBody(c) : null;
      if (segs) for (j=0;j<segs.length;j++) {
        var ls=segs[j]; if (!sepBodyLineHit(inkBody,c.x,c.y,ls)) continue;
        var lx=ls[2]-ls[0], ly=ls[3]-ls[1], ll=Math.hypot(lx,ly); if(!ll)continue;
        var lnx=-ly/ll, lny=lx/ll, signed=(c.x-ls[0])*lnx+(c.y-ls[1])*lny, lside=signed>=0?1:-1;
        var travel=0, cap=inkBody.bound*2+2;
        while(travel<cap && sepBodyLineHit(inkBody,c.x+lnx*lside*travel,c.y+lny*lside*travel,ls))travel+=1;
        var q9w=(c.maxSpeed||0)+1,rem9w=Math.max(0,q9w-(c.__sepU||0));if(travel>rem9w)travel=rem9w;c.__sepU=(c.__sepU||0)+travel;if(travel>0){c.x+=lnx*lside*travel;c.y+=lny*lside*travel;}if(true){var lv=c.vx*lnx+c.vy*lny;if(lv*lside<0){c.vx-=1.7*lv*lnx;c.vy-=1.7*lv*lny;}}
      }
      if (mask && sepBodyHit(inkBody, c.x, c.y)) {
        // Search real empty ink space, not bounding boxes: counters remain usable. The previous
        // eight perimeter probes missed thin strokes and let bodies sit on letter pixels.
        var foundInk = false, bestIX = c.x, bestIY = c.y;
        var stepInk = 2, maxInk = Math.max(lay().fs * 2, r * 3), gapInk = Math.max(0, P.boundGap || 0);
        for (var reachInk = stepInk; reachInk <= maxInk && !foundInk; reachInk += stepInk) {
          for (var dirInk = 0; dirInk < 24; dirInk++) {
            var angleInk = dirInk * Math.PI / 12, testIX = c.x + Math.cos(angleInk) * reachInk, testIY = c.y + Math.sin(angleInk) * reachInk;
            if (testIX < cont.x + gapInk || testIX > cont.x + cont.w - gapInk || testIY < cont.y + gapInk || testIY > cont.y + cont.h - gapInk) continue;
            var crossesInk = false;
            if (segs) for (var isg = 0; isg < segs.length; isg++) {
              var is = segs[isg]; if (sepBodyLineHit(inkBody,testIX,testIY,is)) { crossesInk=true; break; } var iex = is[2]-is[0], iey = is[3]-is[1], id0 = (c.x-is[0])*iey-(c.y-is[1])*iex, id1 = (testIX-is[0])*iey-(testIY-is[1])*iex;
              if (id0*id1 < 0) { var it = id0/(id0-id1), ix = c.x+(testIX-c.x)*it, iy = c.y+(testIY-c.y)*it, il2 = iex*iex+iey*iey, ia = il2 ? ((ix-is[0])*iex+(iy-is[1])*iey)/il2 : -1; if (ia>=0 && ia<=1) { crossesInk = true; break; } }
            }
            if (!crossesInk && !sepBodyHit(inkBody, testIX, testIY)) { bestIX = testIX; bestIY = testIY; foundInk = true; break; }
          }
        }
        if (foundInk) {
          var inkDX = bestIX - c.x, inkDY = bestIY - c.y, inkLen = Math.hypot(inkDX, inkDY) || 1;
          var q9m = (c.maxSpeed || 0) + 1, mv9 = Math.min(inkLen, Math.max(0, q9m - (c.__sepU || 0))); c.__sepU = (c.__sepU || 0) + mv9; if (mv9 > 0) { c.x += inkDX / inkLen * mv9; c.y += inkDY / inkLen * mv9; } // f9: walk toward the free point at the cell's own quantum, never teleport
          var inkVN = (c.vx * inkDX + c.vy * inkDY) / inkLen;
          if (inkVN < 0) { c.vx -= 1.7 * inkVN * inkDX / inkLen; c.vy -= 1.7 * inkVN * inkDY / inkLen; }
        }
      }
      // the plate wall stays absolute (owner 22 Oct): a separator or ink push may slide a body along the wall but never past it
      var bg0 = Math.max(0, P.boundGap || 0), bx0 = cont.x + bg0, bx1 = cont.x + cont.w - bg0, by0 = cont.y + bg0, by1 = cont.y + cont.h - bg0;
      if (c.x < bx0) { c.x = bx0; if (c.vx < 0) c.vx = -c.vx * 0.7; } else if (c.x > bx1) { c.x = bx1; if (c.vx > 0) c.vx = -c.vx * 0.7; }
      if (c.y < by0) { c.y = by0; if (c.vy < 0) c.vy = -c.vy * 0.7; } else if (c.y > by1) { c.y = by1; if (c.vy > 0) c.vy = -c.vy * 0.7; }
    }
  }
  function separatorCollectivePass() {
    if (!P.separatorOn) return;
    var tCollect=performance.now(), radiusLoss=0, segs=P.showAxis&&axisInfo.segs?axisInfo.segs:[], threshold=P.THRESHOLD*.90;
    var points=[];
    function addPoint(x,y,nx,ny){if(x>=cont.x&&x<=cont.x+cont.w&&y>=cont.y&&y<=cont.y+cont.h)points.push(x,y,nx,ny);}
    for(var j=0;j<segs.length;j++){var sg=segs[j],dx=sg[2]-sg[0],dy=sg[3]-sg[1],len=Math.hypot(dx,dy),n=Math.ceil(len);if(len)for(var q=0;q<=n;q++)addPoint(sg[0]+dx*q/n,sg[1]+dy*q/n,-dy/len,dx/len);}
    if(P.showHud&&SEP.img)for(var yy=0;yy<SEP.mh;yy++)for(var xx=0;xx<SEP.mw;xx++)if(SEP.img[(yy*SEP.mw+xx)*4+3]>40)addPoint(xx*2+1,yy*2+1,0,0);
    // Sum the same sources that will be rendered, then move contributors, never erase pixels.
    for(var pass=0;pass<12;pass++){
      var bodies=[],active=[], moves=[], hit=0,flat=[],parts=[],over=[];
      for(var ci=0;ci<cells.length;ci++)if(cells[ci].alive&&introOn(cells[ci].popD)&&cells[ci].x>=cont.x&&cells[ci].x<=cont.x+cont.w&&cells[ci].y>=cont.y&&cells[ci].y<=cont.y+cont.h) {active.push(cells[ci]);bodies.push(null);moves.push([0,0]);}
      var allowance=active.length>1?Math.max(1,Math.floor(SRC_MAX/active.length)):SRC_MAX;
      for(var k=0;k<active.length;k++){bodies[k]=sepBody(active[k],allowance);over[k]=1;}
      for(var k=0;k<active.length;k++){var b=bodies[k],c=active[k];for(var q=0;q<b.n;q++)flat.push([c.x+b.x[q],c.y+b.y[q],P.metaballStrength*b.r[q]*b.r[q],b.r[q]*Math.max(3,Math.sqrt(P.metaballStrength/(P.THRESHOLD*.03))),k]);}
      function sample(x,y,nx,ny){
        if(x<cont.x||x>cont.x+cont.w||y<cont.y||y>cont.y+cont.h)return;
        var total=0;
        for(var k=0;k<active.length;k++)parts[k]=0;
        for(var q=0;q<flat.length;q++){var fs=flat[q],dx=x-fs[0],dy=y-fs[1];if(Math.abs(dx)>fs[3]||Math.abs(dy)>fs[3])continue;var f=fs[2]/(dx*dx+dy*dy+.0001);parts[fs[4]]+=f;total+=f;}
        if(total<=threshold)return;hit++;
        // contact attribution (item 64, root of the collective slide): only a cell whose OWN ink touches the wall point
        // moves - the crowd-share gate (.002 of threshold) dragged 99%+ of transported px on non-contacting cells. Step
        // scales with the cell's own overload at the point, not the crowd total. Same ink test as sepBodyLineHit (.96).
        for(var k=0;k<active.length;k++)if(parts[k]>P.THRESHOLD*.96){if(parts[k]/threshold>over[k])over[k]=parts[k]/threshold;var c=active[k],dx=c.x-x,dy=c.y-y,mx,my;
          if(nx!==null){var side=dx*nx+dy*ny>=0?1:-1;mx=nx*side;my=ny*side;}else{var dl=Math.max(.0001,Math.hypot(dx,dy));mx=dx/dl;my=dy/dl;}
          var step=Math.min(bodies[k].bound+2,Math.max(1,bodies[k].bound*(Math.sqrt(parts[k]/threshold)-1))), m=moves[k];
          m[0]+=mx*step;m[1]+=my*step; // multi-segment coherence (item 64, main 25 Oct): per-point escape pushes accumulate as one vector per cell - contradictory pushes from different segments cancel instead of per-axis max zigzag; magnitude stays bounded by the 73d(2) quantum cap at apply time
        }
      }
      var E=WC.e, usedW=false;
      if(E&&E.sep_run&&WC.ok&&!WC.off&&!WC.simOff&&!/[?&]nosim=1/.test(location.search)) {
        var fp=E.sep_alloc(0,flat.length*5), pp=E.sep_alloc(1,points.length), cp=E.sep_alloc(2,active.length*3);
        var fb=new Float64Array(WC.mem.buffer,fp,flat.length*5), cb=new Float64Array(WC.mem.buffer,cp,active.length*3);
        for(var q=0;q<flat.length;q++)fb.set(flat[q],q*5);
        for(var k=0;k<active.length;k++)cb.set([active[k].x,active[k].y,bodies[k].bound],k*3);
        new Float64Array(WC.mem.buffer,pp,points.length).set(points);
        hit=E.sep_run(flat.length,points.length/4,active.length,threshold,P.THRESHOLD*.96);
        var mb=new Float64Array(WC.mem.buffer,E.sep_moves(),active.length*3);for(var k=0;k<active.length;k++){moves[k][0]=mb[k*3];moves[k][1]=mb[k*3+1];over[k]=mb[k*3+2];}usedW=true;
      }
      if(!usedW)for(var pi=0;pi<points.length;pi+=4)sample(points[pi],points[pi+1],points[pi+2]||points[pi+3]?points[pi+2]:null,points[pi+3]);
      if(!hit)break;
      for(var k=0;k<active.length;k++){
        var c=active[k],m=moves[k],bg=Math.max(0,P.boundGap||0),tx=clamp(c.x+m[0],cont.x+bg,cont.x+cont.w-bg),ty=clamp(c.y+m[1],cont.y+bg,cont.y+cont.h-bg),fraction=1;
        // A collective correction must stay on this cell's side of every finite wall.
        for(var j=0;j<segs.length;j++){var sg=segs[j],ex=sg[2]-sg[0],ey=sg[3]-sg[1],d0=(c.x-sg[0])*ey-(c.y-sg[1])*ex,d1=(tx-sg[0])*ey-(ty-sg[1])*ex;
          if(d0*d1<0){var t=d0/(d0-d1),hx=c.x+(tx-c.x)*t,hy=c.y+(ty-c.y)*t,ll=ex*ex+ey*ey,along=ll?((hx-sg[0])*ex+(hy-sg[1])*ey)/ll:-1;if(along>=0&&along<=1)fraction=Math.min(fraction,Math.max(0,t-.001));}}
        c._sepX=c.x;c._sepY=c.y;if(c._f5T!==frameT){c._f5T=frameT;c._f5x0=c.x;c._f5y0=c.y;} // f9: frame-tagged baseline - the collective budget spans all of this frame's invocations
        var q5=(c.maxSpeed||0)+1,rem5=Math.max(0,q5-Math.hypot(c.x-c._f5x0,c.y-c._f5y0)),mx5=(tx-c.x)*fraction,my5=(ty-c.y)*fraction,ml5=Math.hypot(mx5,my5);
        var capEff=rem5; // f9: strict per-frame budget, no pressure-proportional excess - the boundary pushes as a force, it never carries (73d-1); a pressed body exits at its own quantum over the next frames and overload still reads as reversible squash (sqS)
        if(ml5>capEff&&ml5>0){var k5=capEff/ml5;mx5*=k5;my5*=k5;}
        c.x+=mx5;c.y+=my5; // 73d(2): the TOTAL per-frame collective correction is bounded at the cell's own quantum across all passes, not per pass
        if(pass>=3&&(m[0]||m[1])){
          var pressure=Math.min(1,Math.hypot(m[0],m[1])/Math.max(1,bodies[k].bound));
          // item 64: overload reads as reversible squash, never permanent radius loss (radiusLoss stays 0)
          if (pressure > (c.sqS || 0)) c.sqS = pressure;
        }
      }
      separatorPass();
    }
    SRC.built=-1; SEP.collectMs=performance.now()-tCollect;SEP.radiusLoss=radiusLoss;
  }
  // ---- parasites: attach to a cluster/cell, drain its energy, balance themselves (no host = starvation, drained host = death) ----
  // ---- food life: the dots follow the plate like cells do, and live a Conway life (B3/S23) on a lattice anchored to the plate
  var foodT = 0, foodStat = { born: 0, died: 0, steps: 0, inflow: 0 };
  function stepFoodW() { // Rust/wasm mode-1 food step (fd1.rs); returns false when unavailable so the JS body below runs (?nowasm=1, ?nosim=1)
    var E = WC.e; if (!E || !E.fd1_tick || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1/.test(location.search)) return false;
    try {
      var n = food.length, i, f, b, x0 = cont.x, x1 = cont.x + cont.w, y0 = cont.y, y1 = cont.y + cont.h;
      var now = performance.now(), due = now - foodT >= P.foodLifeMs, needsFlow = false;
      if (!due) { for (i = 0; i < n; i++) { f = food[i]; if (f.x < x0 || f.x > x1 || f.y < y0 || f.y > y1) { needsFlow = true; break; } } if (!needsFlow) return true; } // nothing to do: no marshal at all
      var ip = E.fd1_in(n), buf = new Float64Array(WC.mem.buffer, ip, n * 3 + 3);
      for (i = 0; i < n; i++) { f = food[i]; b = i * 3; buf[b] = f.x; buf[b + 1] = f.y; buf[b + 2] = f.r; }
      foodStat.inflow += E.fd1_flow(n, x0, y0, x1, y1);
      if (!due) { for (i = 0; i < n; i++) { f = food[i]; b = i * 3; f.x = buf[b]; f.y = buf[b + 1]; } WC.fwFd = (WC.fwFd || 0) + 1; return true; }
      foodT = now;
      var m = E.fd1_tick(n, Math.max(1, P.foodLifeCell), x0, y0, x1, y1, cont.w, cont.h, P.foodDensity, Math.floor(Math.random() * 4294967296), Math.floor(Math.random() * 4294967296));
      if (m < 0) return false;
      var o = new Float64Array(WC.mem.buffer, E.fd1_out(), m * 3), st = new Float64Array(WC.mem.buffer, E.fd1_stat(), 4);
      foodStat.died += st[0]; foodStat.born += st[1]; foodStat.steps++;
      var out = new Array(m);
      for (i = 0; i < m; i++) { b = i * 3; out[i] = { x: o[b], y: o[b + 1], r: o[b + 2] }; }
      food = out; WC.fwFd = (WC.fwFd || 0) + 1; return true;
    } catch (e) { WC.fwFdErr = String(e && e.stack || e); return false; }
  }
  var reseedBudget = 0;
  function reseedFood(dtf) { // shared density reseed for every dot-field mode (0 original, 1 life, 3 swarm): one mechanism, no copies; spawns stay inside the (moving) plate
    if (!P.foodReseed) return;
    var x0 = cont.x, y0 = cont.y, gs = Math.max(1, P.foodLifeCell);
    var nf = cont.w * cont.h * P.foodDensity / 2, want = Math.max(P.foodReseedMin, nf * P.foodReseedFloor);
    if (food.length >= want) { reseedBudget = 0; return; }
    reseedBudget = Math.min(P.foodReseedMax, reseedBudget + P.foodReseedMax * dtf / 1000);
    var nb = Math.min(Math.ceil((want - food.length) / 5), Math.floor(reseedBudget / 5)), spawned = 0; // ~5 dots per 3x3 blob; isolated dots die at once under Conway's rules
    for (var b = 0; b < nb; b++) {
      var bx = 0, by = 0, ok = false;
      for (var tr = 0; tr < P.foodReseedTries && !ok; tr++) { // a seed dropped inside a cell's eat reach is eaten the same frame; look for a gap
        bx = Math.floor((x0 + rnd(Math.max(1, cont.w - 4 * gs))) / gs); by = Math.floor((y0 + rnd(Math.max(1, cont.h - 4 * gs))) / gs);
        var cx = (bx + 1.5) * gs, cy = (by + 1.5) * gs; ok = true;
        for (var ci = 0; ci < cells.length; ci++) { var cc = cells[ci], rr = cc.radius + P.foodEatR + 2 * gs; if (Math.abs(cc.x - cx) < rr && Math.abs(cc.y - cy) < rr && (cc.x - cx) * (cc.x - cx) + (cc.y - cy) * (cc.y - cy) < rr * rr) { ok = false; break; } }
      }
      if (!ok) continue;
      for (var dx = 0; dx < 3; dx++) for (var dy = 0; dy < 3; dy++) if (Math.random() < 0.55 && !foodOnInk((bx + dx + 0.5) * gs, (by + dy + 0.5) * gs)) { food.push({ x: (bx + dx + 0.5) * gs, y: (by + dy + 0.5) * gs, r: Math.random() }); spawned++; }
    }
    reseedBudget -= spawned; foodStat.born += spawned;
  }
  function stepFood() {
    if (stepFoodW()) return;
    var i, f, x0 = cont.x, x1 = cont.x + cont.w, y0 = cont.y, y1 = cont.y + cont.h;
    // dots outside the (moving) plate ride the shared boundary morph (wallPull), the same rule cells use (owner 21 Oct: one mechanism)
    for (i = 0; i < food.length; i++) {
      f = food[i];
      if (f.x < x0 || f.x > x1 || f.y < y0 || f.y > y1) { wallPull(f, P.foodSize / 2, false); foodStat.inflow++; }
    }
    // keep the dot population near the density target: seeds appear when it runs low
    var now = performance.now(); if (now - foodT < P.foodLifeMs) return; foodT = now;
    var gs = Math.max(1, P.foodLifeCell), ox = 0, oy = 0, M = 100003, map = new Map(), counts = new Map(), keep = [], k, dx, dy;
    for (i = 0; i < food.length; i++) { f = food[i]; var ix = Math.floor((f.x - ox) / gs), iy = Math.floor((f.y - oy) / gs); k = (ix + 20000) * M + (iy + 20000); if (!map.has(k)) { map.set(k, f); f.k = k; f.ix = ix; f.iy = iy; } }
    map.forEach(function (ff) { for (dx = -1; dx <= 1; dx++) for (dy = -1; dy <= 1; dy++) if (dx || dy) { var kk = (ff.ix + dx + 20000) * M + (ff.iy + dy + 20000); counts.set(kk, (counts.get(kk) || 0) + 1); } });
    var out = [], died = 0, born = 0;
    map.forEach(function (ff, kk) { var n = counts.get(kk) || 0; if (n === 2 || n === 3) out.push(ff); else died++; });
    counts.forEach(function (n, kk) {
      if (n === 3 && !map.has(kk)) { var ix2 = Math.floor(kk / M) - 20000, iy2 = (kk % M) - 20000, nx = ox + (ix2 + 0.5) * gs, ny = oy + (iy2 + 0.5) * gs; if (nx > x0 && nx < x1 && ny > y0 && ny < y1) { out.push({ x: nx, y: ny, r: Math.random() }); born++; } }
    });
    // reseeding is the shared driver (reseedFood), run from the frame dispatch for every dot mode
    food = out; foodStat.born += born; foodStat.died += died; foodStat.steps++;
  }
  // ---- food life, amorphous alternatives (no lattice: positions are continuous, shapes keep changing) ----
  // mode 2 blobs: each blob is a soft shape made of a few dots that wobble. Life-like rules on blob neighbours: alone -> shrinks, 2-3 neighbours -> grows, crowded -> shrinks or splits.
  // every mode: dots never stay outside the plate; a shrinking plate sweeps them in and they pile up against the moving walls
  function foodKeepInW(x0, y0, x1, y1) { // Rust/wasm keepIn (fd3.rs); returns false so the JS loop below runs (?nowasm=1, ?nosim=1)
    var E = WC.e; if (!E || !E.fk_run || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1/.test(location.search)) return false;
    try {
      var n = food.length, i, f, b, any = false;
      for (i = 0; i < n; i++) { f = food[i]; if (f.x < x0 || f.x > x1 || f.y < y0 || f.y > y1) { any = true; break; } }
      if (!any) return true; // no strays: no marshal at all
      var ip = E.fk_in(n), buf = new Float64Array(WC.mem.buffer, ip, n * 5 + 5);
      for (i = 0; i < n; i++) { f = food[i]; b = i * 5; buf[b] = f.x; buf[b + 1] = f.y; if (f.vx !== undefined) { buf[b + 2] = f.vx; buf[b + 3] = f.vy; buf[b + 4] = 1; } else buf[b + 4] = 0; }
      if (E.fk_run(n, x0, y0, x1, y1) < 0) return false;
      for (i = 0; i < n; i++) { f = food[i]; b = i * 5; f.x = buf[b]; f.y = buf[b + 1]; if (buf[b + 4]) { f.vx = buf[b + 2]; f.vy = buf[b + 3]; } }
      WC.fwKp = (WC.fwKp || 0) + 1; return true;
    } catch (e) { WC.fwKpErr = String(e && e.stack || e); return false; }
  }
  function foodKeepIn() {
    var x0 = cont.x, x1 = cont.x + cont.w, y0 = cont.y, y1 = cont.y + cont.h, i, f;
    if (foodKeepInW(x0, y0, x1, y1)) return;
    for (i = 0; i < food.length; i++) {
      f = food[i];
      if (f.x < x0 || f.x > x1 || f.y < y0 || f.y > y1) { f.x = clamp(f.x, x0, x1); f.y = clamp(f.y, y0, y1); if (f.vx !== undefined) { f.vx *= 0.5; f.vy *= 0.5; } }
    }
  }
  var blobs = [], blobT = 0, blobStat = { grow: 0, shrink: 0, split: 0, die: 0, born: 0 };
  function newBlob(x, y) { var b = { x: x, y: y, vx: 0, vy: 0, r: 8 + Math.random() * 10, ph: Math.random() * 6.28, w: 0.3 + Math.random() * 0.6, d: [] }; for (var k = 0; k < 4; k++) addBlobDot(b); blobs.push(b); blobStat.born++; return b; }
  function addBlobDot(b) { var f = { x: b.x, y: b.y, r: Math.random(), a: Math.random() * 6.28, f: 0.5 + Math.random() * 1.5, q: Math.random() * 6.28, blob: b }; b.d.push(f); food.push(f); }
  function stepBlobsPassW(tt, x0, y0, x1, y1) { // Rust/wasm blob per-frame pass (fd2.rs); returns false so the JS loop below runs (?nowasm=1, ?nosim=1)
    var E = WC.e; if (!E || !E.fb_run || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1/.test(location.search)) return false;
    try {
      var nb = blobs.length, nd = 0, i, k, b, f;
      for (i = 0; i < nb; i++) nd += blobs[i].d.length;
      var bp = E.fb_blobs(nb), dp = E.fb_dots(nd); // alloc both before wrapping: a resize can grow memory and detach an earlier view
      var bb = new Float64Array(WC.mem.buffer, bp, nb * 7 + 7), db = new Float64Array(WC.mem.buffer, dp, nd * 6 + 6);
      var j = 0;
      for (i = 0; i < nb; i++) { b = blobs[i]; bb[i * 7] = b.x; bb[i * 7 + 1] = b.y; bb[i * 7 + 2] = b.vx; bb[i * 7 + 3] = b.vy; bb[i * 7 + 4] = b.r; bb[i * 7 + 5] = b.ph; bb[i * 7 + 6] = b.w;
        for (k = 0; k < b.d.length; k++) { f = b.d[k]; db[j * 6] = f.a; db[j * 6 + 1] = f.f; db[j * 6 + 2] = f.q; db[j * 6 + 3] = i; j++; } }
      if (E.fb_run(nb, nd, tt, x0, y0, x1, y1, Math.floor(Math.random() * 4294967296), Math.floor(Math.random() * 4294967296)) < 0) return false;
      j = 0;
      for (i = 0; i < nb; i++) { b = blobs[i]; b.x = bb[i * 7]; b.y = bb[i * 7 + 1]; b.vx = bb[i * 7 + 2]; b.vy = bb[i * 7 + 3];
        for (k = 0; k < b.d.length; k++) { f = b.d[k]; f.x = db[j * 6 + 4]; f.y = db[j * 6 + 5]; j++; } }
      WC.fwBl = (WC.fwBl || 0) + 1; return true;
    } catch (e) { WC.fwBlErr = String(e && e.stack || e); return false; }
  }
  function stepBlobs() {
    var i, k, b, now = performance.now(), tt = now / 1000, x0 = cont.x, x1 = cont.x + cont.w, y0 = cont.y, y1 = cont.y + cont.h;
    if (!blobs.length && food.length) { blobs = []; for (i = 0; i < food.length; i++) { delete food[i].blob; } food = []; }
    for (i = blobs.length - 1; i >= 0; i--) { b = blobs[i]; b.d = b.d.filter(function (f) { return !f.gone; }); if (!b.d.length) { blobs.splice(i, 1); blobStat.die++; } }
    var R = P.foodBlobR;
    if (!stepBlobsPassW(tt, x0, y0, x1, y1)) for (i = 0; i < blobs.length; i++) {
      b = blobs[i];
      // drift, soft push from neighbours, pulled into the plate when outside
      b.vx = b.vx * 0.95 + (Math.random() - 0.5) * 0.12; b.vy = b.vy * 0.95 + (Math.random() - 0.5) * 0.12;
      for (k = 0; k < blobs.length; k += 1) if (k !== i) { var o = blobs[k], dx = b.x - o.x, dy = b.y - o.y, d2 = dx * dx + dy * dy; if (d2 < 900 && d2 > 1) { var dd = Math.sqrt(d2); b.vx += dx / dd * 0.02; b.vy += dy / dd * 0.02; } }
      b.x += b.vx; b.y += b.vy;
      if (b.x < x0 || b.x > x1 || b.y < y0 || b.y > y1) { b.x += (clamp(b.x, x0 + 4, x1 - 4) - b.x) * 0.25; b.y += (clamp(b.y, y0 + 4, y1 - 4) - b.y) * 0.25; }
      var rr = b.r * (1 + 0.25 * Math.sin(tt * b.w + b.ph)) * (0.6 + 0.08 * b.d.length);
      for (k = 0; k < b.d.length; k++) { var f = b.d[k], ang = f.a + tt * 0.25 * b.w, rad = rr * (0.45 + 0.55 * Math.abs(Math.sin(tt * f.f + f.q))); f.x = b.x + Math.cos(ang) * rad; f.y = b.y + Math.sin(ang) * rad; }
    }
    if (now - blobT >= P.foodLifeMs * 2) {
      blobT = now; var n = blobs.length, cnt = new Array(n).fill(0), a, c;
      for (a = 0; a < n; a++) for (c = a + 1; c < n; c++) { var ddx = blobs[a].x - blobs[c].x, ddy = blobs[a].y - blobs[c].y; if (ddx * ddx + ddy * ddy < R * R) { cnt[a]++; cnt[c]++; } }
      for (a = n - 1; a >= 0; a--) {
        b = blobs[a]; var nb = cnt[a];
        if (nb === 2 || nb === 3) { if (b.d.length < P.foodBlobDots) { addBlobDot(b); blobStat.grow++; } else if (Math.random() < 0.25 && blobs.length < 220) { var nbl = newBlob(b.x + (Math.random() - 0.5) * R * 0.8, b.y + (Math.random() - 0.5) * R * 0.8); nbl.x = clamp(nbl.x, x0 + 4, x1 - 4); nbl.y = clamp(nbl.y, y0 + 4, y1 - 4); for (var s = 0; s < 2; s++) { var gone = b.d.pop(); if (gone) { gone.gone = 1; var fi = food.indexOf(gone); if (fi >= 0) food.splice(fi, 1); } } blobStat.split++; } }
        else if (nb < 2 || nb > 3) { if (Math.random() < 0.35 && b.d.length > 1) { var g2 = b.d.pop(); g2.gone = 1; var fj = food.indexOf(g2); if (fj >= 0) food.splice(fj, 1); blobStat.shrink++; } else if (b.d.length <= 1 && Math.random() < 0.3) { b.d.forEach(function (f) { f.gone = 1; var fz = food.indexOf(f); if (fz >= 0) food.splice(fz, 1); }); } }
      }
      var want = Math.round(cont.w * cont.h * P.foodDensity / 2 / 12), kk = Math.min(8, want - blobs.length);
      for (k = 0; k < kk; k++) newBlob(x0 + Math.random() * cont.w, y0 + Math.random() * cont.h);
    }
  }
  function drawBlobs() {
    var ol = P.blobOutline; if (ol && !(P.axisWidth > 0)) return; ctx.fillStyle = P.foodColor; ctx.strokeStyle = P.foodColor; ctx.lineWidth = LW(); ctx.lineCap = 'round'; ctx.globalAlpha = P.foodAlpha;
    for (var i = 0; i < blobs.length; i++) {
      var b = blobs[i], d = b.d; if (!introOn(CELL_END + ((i * 0.6180339) % 1) * (FOOD_END - CELL_END))) continue; if (d.length < 3) { for (var q = 0; q < d.length; q++) { if (ol) ctx.strokeRect(d[q].x - P.foodSize / 2, d[q].y - P.foodSize / 2, P.foodSize, P.foodSize); else ctx.fillRect(d[q].x - P.foodSize / 2, d[q].y - P.foodSize / 2, P.foodSize, P.foodSize); } continue; }
      var pts = d.slice().sort(function (u, v) { return Math.atan2(u.y - b.y, u.x - b.x) - Math.atan2(v.y - b.y, v.x - b.x); }), n = pts.length;
      ctx.beginPath(); ctx.moveTo((pts[n - 1].x + pts[0].x) / 2, (pts[n - 1].y + pts[0].y) / 2);
      for (var k = 0; k < (ol ? n - 1 : n); k++) { var p1 = pts[k], p2 = pts[(k + 1) % n]; ctx.quadraticCurveTo(p1.x, p1.y, (p1.x + p2.x) / 2, (p1.y + p2.y) / 2); }
      if (ol) ctx.stroke(); else { ctx.closePath(); ctx.fill(); }
    }
    ctx.globalAlpha = 1;
  }
  // mode 3 swarm: continuous dots that flock; Life-like thinning: isolated dots fade away, dots with 2-3 near neighbours may bud a child, crowded ones die
  var swT = 0, swStat = { born: 0, died: 0 };
  function stepSwarmW() { // Rust/wasm swarm step (swarm.rs); returns false when unavailable so the JS body below runs (?nowasm=1, ?nosim=1)
    var E = WC.e; if (!E || !E.sw_run || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1/.test(location.search)) return false;
    try {
      var n = food.length, i, f, b, x0 = cont.x, x1 = cont.x + cont.w, y0 = cont.y, y1 = cont.y + cont.h, ar = cont.w * cont.h * P.foodDensity;
      var ip = E.sw_in(n), buf = new Float64Array(WC.mem.buffer, ip, n * 6 + 6);
      for (i = 0; i < n; i++) { f = food[i]; if (f.vx === undefined) { f.vx = (Math.random() - 0.5) * 0.4; f.vy = (Math.random() - 0.5) * 0.4; } b = i * 6; buf[b] = f.x; buf[b + 1] = f.y; buf[b + 2] = f.vx; buf[b + 3] = f.vy; buf[b + 4] = f.r; }
      var life = performance.now() - swT >= P.foodLifeMs * 2;
      var m = E.sw_run(n, x0, x1, y0, y1, life ? 1 : 0, n < ar ? 1 : 0, ar * 0.1, Math.floor(Math.random() * 4294967296), Math.floor(Math.random() * 4294967296));
      if (m < 0) return false;
      if (life) swT = performance.now();
      var o = new Float64Array(WC.mem.buffer, E.sw_out(), m * 7), st = new Float64Array(WC.mem.buffer, E.sw_stat(), 4), out = new Array(m), kept = new Uint8Array(n), k, src;
      swStat.died += st[0]; swStat.born += st[1];
      for (k = 0; k < m; k++) {
        b = k * 7; src = o[b + 5];
        if (src >= 0) { f = food[src]; kept[src] = 1; f.x = o[b]; f.y = o[b + 1]; f.vx = o[b + 2]; f.vy = o[b + 3]; out[k] = f; }
        else out[k] = { x: o[b], y: o[b + 1], r: o[b + 4], vx: 0, vy: 0 };
      }
      for (i = 0; i < n; i++) if (!kept[i]) food[i].gone = 1;
      food = out; return true;
    } catch (e) { return false; }
  }
  function stepSwarm() {
    if (stepSwarmW()) return;
    var i, f, x0 = cont.x, x1 = cont.x + cont.w, y0 = cont.y, y1 = cont.y + cont.h, n = food.length, G = 18, grid = new Map(), K = 10007;
    for (i = 0; i < n; i++) { f = food[i]; if (f.vx === undefined) { f.vx = (Math.random() - 0.5) * 0.4; f.vy = (Math.random() - 0.5) * 0.4; } f.gx = Math.floor(f.x / G); f.gy = Math.floor(f.y / G); var key = f.gx * K + f.gy; var arr = grid.get(key); if (arr) arr.push(f); else grid.set(key, [f]); }
    var life = performance.now() - swT >= P.foodLifeMs * 2; if (life) swT = performance.now();
    var out = [];
    for (i = 0; i < n; i++) {
      f = food[i]; var mx = 0, my = 0, sx = 0, sy = 0, c = 0, dx, dy;
      for (dx = -1; dx <= 1; dx++) for (dy = -1; dy <= 1; dy++) { var cell = grid.get((f.gx + dx) * K + (f.gy + dy)); if (cell) for (var m = 0; m < cell.length; m++) { var o = cell[m]; if (o === f) continue; var ex = o.x - f.x, ey = o.y - f.y, d2 = ex * ex + ey * ey; if (d2 < G * G) { c++; mx += ex; my += ey; if (d2 < 36 && d2 > 0.1) { sx -= ex / d2; sy -= ey / d2; } } } }
      if (c) { f.vx += mx / c * 0.004 + sx * 0.6; f.vy += my / c * 0.004 + sy * 0.6; }
      f.vx = f.vx * 0.97 + (Math.random() - 0.5) * 0.08; f.vy = f.vy * 0.97 + (Math.random() - 0.5) * 0.08;
      f.x += f.vx; f.y += f.vy;
      if (f.x < x0 || f.x > x1 || f.y < y0 || f.y > y1) { f.x += (clamp(f.x, x0 + 1, x1 - 1) - f.x) * 0.25; f.y += (clamp(f.y, y0 + 1, y1 - 1) - f.y) * 0.25; f.vx *= 0.8; f.vy *= 0.8; }
      var keep = true;
      if (life) {
        if (c < 2 && Math.random() < 0.3) { keep = false; swStat.died++; }
        else if (c > 5 && Math.random() < 0.4) { keep = false; swStat.died++; }
        else if ((c === 2 || c === 3) && Math.random() < 0.3 && n < cont.w * cont.h * P.foodDensity) { out.push({ x: f.x + (Math.random() - 0.5) * 6, y: f.y + (Math.random() - 0.5) * 6, r: Math.random(), vx: 0, vy: 0 }); swStat.born++; }
      }
      if (keep) out.push(f); else f.gone = 1;
    }
    if (life && out.length < cont.w * cont.h * P.foodDensity * 0.1) for (i = 0; i < 12; i++) { var cx = x0 + Math.random() * cont.w, cy = y0 + Math.random() * cont.h; for (var q = 0; q < 4; q++) out.push({ x: cx + (Math.random() - 0.5) * 12, y: cy + (Math.random() - 0.5) * 12, r: Math.random(), vx: 0, vy: 0 }); }
    food = out;
  }
  // mode 4 worms: living food strands. The head wanders with a wave, the body follows link by link; a worm grows at the
  // tail, splits in two when long, and cells bite pieces off it (each body dot is an ordinary edible food entry).
  var worms = [], wormT = 0, wormStat = { born: 0, died: 0, split: 0, eaten: 0 };
  function newWorm(x, y, len) {
    var w = { x: x, y: y, a: rnd(6.2832), sp: rnd(0.25, 0.8), fr: rnd(0.6, 1.6), ph: rnd(6.2832), d: [] };
    for (var i = 0; i < len; i++) { var f = { x: x, y: y, r: Math.random(), worm: w }; w.d.push(f); food.push(f); }
    worms.push(w); wormStat.born++; return w;
  }
  function wipeWorms() { for (var i = food.length - 1; i >= 0; i--) if (food[i].worm) food.splice(i, 1); worms = []; }
  function stepWormsW() { // Rust/wasm worm step (worms.rs); returns false when unavailable so the JS body below runs (?nowasm=1, ?nosim=1, ?nofoodwasm=1)
    var E = WC.e; if (!E || !E.wm_run || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1|nofoodwasm=1/.test(location.search)) return false;
    try {
      var i, k, w, f, now = performance.now();
      for (i = worms.length - 1; i >= 0; i--) { // eaten links drop out; a worm with too little body left dissolves
        w = worms[i];
        for (k = w.d.length - 1; k >= 0; k--) if (w.d[k].gone) { w.d.splice(k, 1); wormStat.eaten++; }
        if (w.d.length < 2) { w.d.forEach(function (f) { f.gone = 1; var fi = food.indexOf(f); if (fi >= 0) food.splice(fi, 1); }); worms.splice(i, 1); wormStat.died++; }
      }
      var nw = worms.length, nl = 0; for (i = 0; i < nw; i++) nl += worms[i].d.length;
      var hp = E.wm_hdr(nw), lp = E.wm_lnk(nl); // alloc before reading the buffer: a resize can grow memory and detach it
      var hb = new Float64Array(WC.mem.buffer, hp, nw * 6 + 6), lb = new Float64Array(WC.mem.buffer, lp, nl * 4 + 4);
      var all = [], li = 0, b, q;
      for (i = 0; i < nw; i++) { w = worms[i]; b = i * 6; hb[b] = w.x; hb[b + 1] = w.y; hb[b + 2] = w.a; hb[b + 3] = w.sp; hb[b + 4] = w.fr; hb[b + 5] = w.ph;
        for (k = 0; k < w.d.length; k++) { f = w.d[k]; all.push(f); q = li * 4; lb[q] = f.x; lb[q + 1] = f.y; lb[q + 2] = f.r; lb[q + 3] = i; li++; } }
      var life = now - wormT >= P.foodLifeMs * 2;
      var want = Math.round(cont.w * cont.h * P.foodDensity / 2 / 14);
      var m = E.wm_run(nw, nl, cont.x, cont.x + cont.w, cont.y, cont.y + cont.h, now / 1000, Math.max(3, P.foodSize * 1.6), life ? 1 : 0, want, Math.floor(Math.random() * 4294967296), Math.floor(Math.random() * 4294967296));
      if (m < 0) return false;
      if (life) wormT = now;
      var oh = new Float64Array(WC.mem.buffer, E.wm_ohdr(), m * 7), st = new Float64Array(WC.mem.buffer, E.wm_stat(), 4);
      var lq = st[2], ol = new Float64Array(WC.mem.buffer, E.wm_olnk(), lq * 5);
      wormStat.split += st[0]; wormStat.born += st[1];
      var outW = new Array(m);
      for (i = 0; i < m; i++) { b = i * 7; var src = oh[b + 6];
        if (src >= 0) { w = worms[src]; w.x = oh[b]; w.y = oh[b + 1]; w.a = oh[b + 2]; w.sp = oh[b + 3]; w.fr = oh[b + 4]; w.ph = oh[b + 5]; w.d = []; }
        else w = { x: oh[b], y: oh[b + 1], a: oh[b + 2], sp: oh[b + 3], fr: oh[b + 4], ph: oh[b + 5], d: [] };
        outW[i] = w; }
      for (k = 0; k < lq; k++) { b = k * 5; var widx = ol[b + 3], lsrc = ol[b + 4]; w = outW[widx];
        if (lsrc >= 0) { f = all[lsrc]; f.x = ol[b]; f.y = ol[b + 1]; f.r = ol[b + 2]; f.worm = w; }
        else { f = { x: ol[b], y: ol[b + 1], r: ol[b + 2], worm: w }; food.push(f); }
        w.d.push(f); }
      worms = outW; WC.fwWm = (WC.fwWm || 0) + 1; return true;
    } catch (e) { WC.fwWmErr = String(e && e.stack || e); return false; }
  }
  function stepWorms() {
    if (stepWormsW()) return;
    var i, k, w, now = performance.now(), tt = now / 1000, x0 = cont.x, x1 = cont.x + cont.w, y0 = cont.y, y1 = cont.y + cont.h;
    for (i = worms.length - 1; i >= 0; i--) { // eaten links drop out; a worm with too little body left dissolves
      w = worms[i];
      for (k = w.d.length - 1; k >= 0; k--) if (w.d[k].gone) { w.d.splice(k, 1); wormStat.eaten++; }
      if (w.d.length < 2) { w.d.forEach(function (f) { f.gone = 1; var fi = food.indexOf(f); if (fi >= 0) food.splice(fi, 1); }); worms.splice(i, 1); wormStat.died++; }
    }
    var SP = Math.max(3, P.foodSize * 1.6);
    for (i = 0; i < worms.length; i++) {
      w = worms[i];
      w.a += (Math.random() - 0.5) * 0.35 + Math.sin(tt * w.fr + w.ph) * 0.06;
      var m = 26;
      if (w.x < x0 + m || w.x > x1 - m || w.y < y0 + m || w.y > y1 - m) { var ca = Math.atan2((y0 + y1) / 2 - w.y, (x0 + x1) / 2 - w.x), da = ca - w.a; while (da > 3.1416) da -= 6.2832; while (da < -3.1416) da += 6.2832; w.a += da * 0.04; }
      var sp = w.sp * (1 + 0.35 * Math.sin(tt * w.fr * 2 + w.ph));
      w.x += Math.cos(w.a) * sp; w.y += Math.sin(w.a) * sp;
      var hx = w.x, hy = w.y;
      for (k = 0; k < w.d.length; k++) { var f = w.d[k], dx = hx - f.x, dy = hy - f.y, dd = Math.hypot(dx, dy) || 1, mv = dd - SP; if (mv > 0) { f.x += dx / dd * mv; f.y += dy / dd * mv; } hx = f.x; hy = f.y; }
    }
    if (now - wormT >= P.foodLifeMs * 2) {
      wormT = now;
      for (i = worms.length - 1; i >= 0; i--) {
        w = worms[i];
        if (w.d.length < 16 && Math.random() < 0.45) { var tl = w.d[w.d.length - 1], nf = { x: tl.x, y: tl.y, r: Math.random(), worm: w }; w.d.push(nf); food.push(nf); }
        if (w.d.length >= 9 && Math.random() < 0.3 && worms.length < 120) { // binary fission: the tail half walks away as its own worm
          var half = Math.ceil(w.d.length / 2), tail = w.d.splice(half), nw2 = { x: tail[0].x, y: tail[0].y, a: rnd(6.2832), sp: rnd(0.25, 0.8), fr: rnd(0.6, 1.6), ph: rnd(6.2832), d: tail };
          tail.forEach(function (f) { f.worm = nw2; }); worms.push(nw2); wormStat.split++; wormStat.born++;
        }
      }
      var want = Math.round(cont.w * cont.h * P.foodDensity / 2 / 14), kk = Math.min(5, want - worms.length);
      for (k = 0; k < kk; k++) newWorm(x0 + Math.random() * cont.w, y0 + Math.random() * cont.h, 3 + Math.floor(Math.random() * 4));
    }
  }
  function drawWorms() {
    var ol = P.blobOutline; if (ol && !(P.axisWidth > 0)) return;
    ctx.strokeStyle = P.foodColor; ctx.fillStyle = P.foodColor; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.globalAlpha = P.foodAlpha;
    ctx.lineWidth = ol ? LW() : Math.max(1.5, P.foodSize * 1.1);
    for (var i = 0; i < worms.length; i++) {
      var w = worms[i], d = w.d; if (d.length < 2) continue;
      if (!introOn(CELL_END + ((i * 0.6180339) % 1) * (FOOD_END - CELL_END))) continue;
      ctx.beginPath(); ctx.moveTo(d[0].x, d[0].y);
      for (var k = 1; k < d.length; k++) ctx.lineTo(d[k].x, d[k].y);
      ctx.stroke();
      if (!ol) { ctx.beginPath(); ctx.arc(d[0].x, d[0].y, Math.max(1, P.foodSize * 0.7), 0, 6.2832); ctx.fill(); }
    }
    ctx.globalAlpha = 1;
  }
  // mode 5 spores: rooted spores mature, pulse, and burst into drifting motes; motes that survive settle as new spores.
  // Every stage is an ordinary food entry - cells can eat a spore before it bursts or catch the motes mid-flight.
  var spores = [], sporeLast = 0, sporeStat = { born: 0, burst: 0, died: 0, eaten: 0, settled: 0 };
  function newSpore(x, y, st) { var s = { x: x, y: y, r: Math.random(), st: st || 0, age: 0, ph: Math.random() * 6.2832, vx: 0, vy: 0, spore: 1 }; spores.push(s); food.push(s); sporeStat.born++; return s; }
  function wipeSpores() { for (var i = food.length - 1; i >= 0; i--) if (food[i].spore) food.splice(i, 1); spores = []; }
  function stepSporesW() { // Rust/wasm spore step (spores.rs); returns false when unavailable so the JS body below runs (?nowasm=1, ?nosim=1, ?nofoodwasm=1)
    var E = WC.e; if (!E || !E.sp_run || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1|nofoodwasm=1/.test(location.search)) return false;
    try {
      var n = spores.length, i, s, b, k, src;
      var ip = E.sp_in(n), buf = new Float64Array(WC.mem.buffer, ip, n * 9 + 9);
      for (i = 0; i < n; i++) { s = spores[i]; b = i * 9; buf[b] = s.x; buf[b + 1] = s.y; buf[b + 2] = s.r; buf[b + 3] = s.st; buf[b + 4] = s.age; buf[b + 5] = s.ph; buf[b + 6] = s.vx; buf[b + 7] = s.vy; buf[b + 8] = s.gone ? 1 : 0; }
      var now = performance.now(), dtms = sporeLast ? Math.min(200, now - sporeLast) : 16; sporeLast = now;
      var cap = Math.max(60, Math.round(cont.w * cont.h * P.foodDensity / 2 / 8));
      var m = E.sp_run(n, cont.x, cont.x + cont.w, cont.y, cont.y + cont.h, dtms, cap, Math.floor(Math.random() * 4294967296), Math.floor(Math.random() * 4294967296));
      if (m < 0) return false;
      var o = new Float64Array(WC.mem.buffer, E.sp_out(), m * 10), st = new Float64Array(WC.mem.buffer, E.sp_stat(), 8), out = new Array(m), kept = new Uint8Array(n);
      sporeStat.eaten += st[0]; sporeStat.burst += st[1]; sporeStat.died += st[2]; sporeStat.settled += st[3]; sporeStat.born += st[4];
      for (k = 0; k < m; k++) {
        b = k * 10; src = o[b + 8];
        if (src >= 0) { s = spores[src]; kept[src] = 1; s.x = o[b]; s.y = o[b + 1]; s.r = o[b + 2]; s.st = o[b + 3]; s.age = o[b + 4]; s.ph = o[b + 5]; s.vx = o[b + 6]; s.vy = o[b + 7]; out[k] = s; }
        else { s = { x: o[b], y: o[b + 1], r: o[b + 2], st: o[b + 3], age: o[b + 4], ph: o[b + 5], vx: o[b + 6], vy: o[b + 7], spore: 1 }; food.push(s); out[k] = s; }
      }
      for (i = 0; i < n; i++) if (!kept[i]) spores[i].gone = 1;
      spores = out;
      for (i = food.length - 1; i >= 0; i--) if (food[i].gone) food.splice(i, 1);
      WC.fwSp = (WC.fwSp || 0) + 1; return true;
    } catch (e) { WC.fwSpErr = String(e && e.stack || e); return false; }
  }
  function stepSpores() {
    if (stepSporesW()) return;
    var i, now = performance.now(), dtms = sporeLast ? Math.min(200, now - sporeLast) : 16; sporeLast = now;
    var x0 = cont.x, x1 = cont.x + cont.w, y0 = cont.y, y1 = cont.y + cont.h, rooted = 0;
    var cap = Math.max(60, Math.round(cont.w * cont.h * P.foodDensity / 2 / 8));
    for (i = spores.length - 1; i >= 0; i--) {
      var s = spores[i];
      if (s.gone) { spores.splice(i, 1); sporeStat.eaten++; continue; }
      s.age += dtms;
      if (s.st === 0) {
        rooted++;
        if (s.age > 5000 + s.ph * 1200) { // mature
          if (spores.length < cap) { // burst: the spore scatters into motes
            s.gone = 1; var fi = food.indexOf(s); if (fi >= 0) food.splice(fi, 1); spores.splice(i, 1); sporeStat.burst++; sporeStat.died++;
            var nm = 4 + Math.floor(Math.random() * 4);
            for (var k2 = 0; k2 < nm; k2++) { var a2 = rnd(6.2832), v = rnd(0.6, 1.8), mo = newSpore(s.x, s.y, 1); mo.vx = Math.cos(a2) * v; mo.vy = Math.sin(a2) * v; }
          } else if (Math.random() < 0.4) { s.gone = 1; var fk = food.indexOf(s); if (fk >= 0) food.splice(fk, 1); spores.splice(i, 1); sporeStat.died++; } // crowded: some retire quietly
          else s.age = 0; // crowded: wait for another cycle
        }
      } else {
        s.vx = s.vx * 0.965 + (Math.random() - 0.5) * 0.05; s.vy = s.vy * 0.965 + (Math.random() - 0.5) * 0.05;
        s.x += s.vx; s.y += s.vy;
        if (s.x < x0 || s.x > x1) { s.vx = -s.vx * 0.6; s.x = clamp(s.x, x0, x1); }
        if (s.y < y0 || s.y > y1) { s.vy = -s.vy * 0.6; s.y = clamp(s.y, y0, y1); }
        if (s.age > 1400 + s.ph * 300) { // landing: most root as new spores, some are lost
          if (Math.random() < 0.75) { s.st = 0; s.age = 0; s.vx = 0; s.vy = 0; sporeStat.settled++; sporeStat.born++; }
          else { s.gone = 1; var fj = food.indexOf(s); if (fj >= 0) food.splice(fj, 1); spores.splice(i, 1); sporeStat.died++; }
        }
      }
    }
    var want = Math.round(cap * 0.6);
    if (rooted < want && Math.random() < 0.35) { var nb = Math.min(3, want - rooted); for (i = 0; i < nb; i++) newSpore(x0 + Math.random() * cont.w, y0 + Math.random() * cont.h, 0); }
  }
  function drawSpores() {
    var ol = P.blobOutline; if (ol && !(P.axisWidth > 0)) return;
    var now = performance.now(); ctx.strokeStyle = P.foodColor; ctx.fillStyle = P.foodColor; ctx.lineWidth = Math.max(1, LW());
    ctx.globalAlpha = P.foodAlpha;
    for (var i = 0; i < spores.length; i++) {
      var s = spores[i]; if (s.r >= P.foodShow) continue;
      if (!introOn(CELL_END + s.r * (FOOD_END - CELL_END))) continue;
      if (s.st === 1) { var ms2 = P.foodSize * 0.55; ctx.fillRect(s.x - ms2 / 2, s.y - ms2 / 2, ms2, ms2); continue; }
      var g = Math.min(1, s.age / 4500), rr = P.foodSize * (0.5 + g * 1.1);
      ctx.beginPath(); ctx.arc(s.x, s.y, rr, 0, 6.2832); if (ol) ctx.stroke(); else ctx.fill();
      if (g > 0.65) { // about to burst: a pulsing halo
        var pu = (g - 0.65) / 0.35;
        ctx.globalAlpha = P.foodAlpha * pu * (0.35 + 0.35 * Math.sin(now / 130 + s.ph));
        ctx.beginPath(); ctx.arc(s.x, s.y, rr + P.foodSize * (0.7 + 0.5 * Math.sin(now / 160 + s.ph)), 0, 6.2832); ctx.stroke();
        ctx.globalAlpha = P.foodAlpha;
      }
    }
    ctx.globalAlpha = 1;
  }
  var parStat = { rehost: 0 };
  function stepParasitesW() { // Rust/wasm parasite step (parasites.rs); returns false when unavailable so the JS body below runs (?nowasm=1, ?nosim=1, ?nofoodwasm=1)
    var E = WC.e; if (!E || !E.pa_run || !WC.ok || WC.off || WC.simOff || /[?&]nosim=1|nofoodwasm=1/.test(location.search)) return false;
    try {
      if (!P.parasiteOn || !cells.length) { parasites.length = 0; return true; }
      var n = cells.length, m = parasites.length, i, c, p, b;
      var cp = E.pa_cells(n), ep = E.pa_energy(n), pp = E.pa_in(m); // alloc before reading the buffer: a resize can grow memory and detach it
      var ci = new Float64Array(WC.mem.buffer, cp, n * 5 + 5), en = new Float64Array(WC.mem.buffer, ep, n + 1), pi = new Float64Array(WC.mem.buffer, pp, m * 7 + 7);
      var hidx = {};
      for (i = 0; i < n; i++) { c = cells[i]; c._pi = i; b = i * 5; ci[b] = c.x; ci[b + 1] = c.y; ci[b + 2] = c.radius; ci[b + 3] = c.cl || 0; ci[b + 4] = c.alive ? 1 : 0; en[i] = c.energy; }
      for (i = 0; i < m; i++) { p = parasites[i]; b = i * 7; pi[b] = p.x; pi[b + 1] = p.y; pi[b + 2] = p.e; // a spliced host keeps a stale _pi: validate identity before packing
      pi[b + 3] = (p.host && p.host.alive && cells[p.host._pi] === p.host) ? p.host._pi : -1; pi[b + 4] = p.a; pi[b + 5] = p.ph || 0; pi[b + 6] = p.lost || 0; }
      var now = performance.now();
      var q = E.pa_run(n, m, now, 1, P.parasiteFrac, P.parasiteSight, P.parasiteNerv, P.parasiteDrain, P.parasiteEff, P.parasiteHard, P.parasiteHardMs, Math.floor(Math.random() * 4294967296), Math.floor(Math.random() * 4294967296));
      if (q < 0) return false;
      for (i = 0; i < n; i++) cells[i].energy = en[i];
      var po = new Float64Array(WC.mem.buffer, E.pa_out(), q * 8), st = new Float64Array(WC.mem.buffer, E.pa_stat(), 4), out = new Array(q);
      ev.pdeath = (ev.pdeath || 0) + st[0]; ev.pbirth = (ev.pbirth || 0) + st[1]; parStat.rehost += st[2];
      for (i = 0; i < q; i++) { b = i * 8; var src = po[b + 7];
        if (src >= 0) { p = parasites[src]; p.x = po[b]; p.y = po[b + 1]; p.e = po[b + 2]; p.a = po[b + 4]; p.ph = po[b + 5]; p.lost = po[b + 6]; }
        else p = { x: po[b], y: po[b + 1], e: po[b + 2], a: po[b + 4], ph: po[b + 5], lost: po[b + 6] };
        var hh = po[b + 3]; p.host = hh >= 0 ? cells[hh] : null; out[i] = p; }
      parasites = out; WC.fwPa = (WC.fwPa || 0) + 1; return true;
    } catch (e) { WC.fwPaErr = String(e && e.stack || e); return false; }
  }
  // ---- parasites and letter circles (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02): when the plate grows over the title, a circle of a glyph (its real
  // font-outline circle from circlesNow) that lies inside the plate looks like a cell to a hostless parasite. A hostless
  // parasite whose nearest candidate is such a circle (with the same distance rule as cells) takes it for a host and rides it
  // like a cell body; a real cell closer than the circle, or the circle leaving the plate, ends the mistake. It feeds nothing, so
  // the ordinary starvation rule (parasiteHardMs / parasiteHard) decides how long a parasite can keep believing.
  function circleInPlate(c) { var nx = clamp(c.x, cont.x, cont.x + cont.w), ny = clamp(c.y, cont.y, cont.y + cont.h); return Math.hypot(c.x - nx, c.y - ny) < c.r; }
  function parasiteCircles() {
    if (!P.parasiteOn || !P.showHud || !P.titleCircles || !circlesNow.length || !parasites.length) { for (var z = 0; z < parasites.length; z++) { parasites[z].circ = null; parasites[z]._ox = undefined; } return; }
    var cand = [], i, j, p, c;
    for (i = 0; i < circlesNow.length; i++) if (circleInPlate(circlesNow[i])) cand.push(circlesNow[i]);
    var tt = performance.now() / 1000, nv = P.parasiteNerv, sight2 = P.parasiteSight * P.parasiteSight;
    for (i = 0; i < parasites.length; i++) {
      p = parasites[i];
      if (p.host) { p.circ = null; p._ox = undefined; continue; }
      if (p.circ) { var cur = null; for (j = 0; j < cand.length; j++) if (cand[j].key === p.circ.key) { cur = cand[j]; break; } p.circ = cur; } // follows the live circle (it moves with the layout) or loses it
      var bd = sight2, best = null, bc = null;
      for (j = 0; j < cells.length; j++) { c = cells[j]; if (!c.alive) continue; var d = (c.x - p.x) * (c.x - p.x) + (c.y - p.y) * (c.y - p.y); if (c.cl) d *= 0.5; if (d < bd) { bd = d; best = c; } }
      var bcd = sight2;
      for (j = 0; j < cand.length; j++) { var dd = (cand[j].x - p.x) * (cand[j].x - p.x) + (cand[j].y - p.y) * (cand[j].y - p.y); if (dd < bcd) { bcd = dd; bc = cand[j]; } }
      if (!p.circ && bc && bcd < bd) p.circ = bc; // closest candidate is a circle: believed
      else if (p.circ && best && bd < (p.circ.x - p.x) * (p.circ.x - p.x) + (p.circ.y - p.y) * (p.circ.y - p.y)) p.circ = null; // a real cell is nearer: the illusion breaks
      if (!p.circ) { p._ox = undefined; continue; }
      if (p._ox !== undefined) { p.x = p._ox; p.y = p._oy; } // the core step also nudged it toward a real cell: the believed circle owns its motion
      var ph = p.ph || (p.ph = Math.random() * 6.28), osc = Math.sin(tt * (2 + 2 * nv) + ph), dd2 = Math.hypot(p.circ.x - p.x, p.circ.y - p.y) || 1;
      var want = p.circ.r * (1.1 + 0.5 * nv * (1 + osc)), dir = dd2 > want ? 1 : -0.6 * nv, sp = Math.min(6, Math.max(1.2, dd2 * 0.08)) * (1 + 0.5 * nv * osc); // the cell-chase law of the hostless branch
      p.x += (p.circ.x - p.x) / dd2 * sp * dir + (Math.random() - 0.5) * 2 * nv; p.y += (p.circ.y - p.y) / dd2 * sp * dir + (Math.random() - 0.5) * 2 * nv;
      p._ox = p.x; p._oy = p.y;
    }
  }
  function stepParasites() { stepParasitesCore(); parasiteCircles(); }
  function stepParasitesCore() {
    if (stepParasitesW()) return;
    if (!P.parasiteOn || !cells.length) { parasites.length = 0; return; }
    var target = Math.round(cells.length * P.parasiteFrac), i, c;
    for (i = 0; i < cells.length; i++) cells[i].pc = 0;
    for (i = 0; i < parasites.length; i++) if (parasites[i].host) parasites[i].host.pc++;
    if (parasites.length < target && Math.random() < 0.08) { c = cells[Math.floor(Math.random() * cells.length)]; parasites.push({ x: c.x, y: c.y, e: 6, host: null, a: Math.random() * 6.2832 }); }
    for (i = parasites.length - 1; i >= 0; i--) {
      var p = parasites[i];
      if (p.host && !p.host.alive) { p.host = null; p.lost = performance.now(); }
      if (!p.host) {
        var best = null, bd = P.parasiteSight * P.parasiteSight; if (!p.lost) p.lost = performance.now(); if (!p.ph) p.ph = Math.random() * 6.28;
        for (var j = 0; j < cells.length; j++) { var q = cells[j], d = (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y); if (q.cl) d *= 0.5; if (d < bd) { bd = d; best = q; } }
        if (best) {
          var dd = Math.sqrt(bd) || 1, nv = P.parasiteNerv, tt = performance.now() / 1000, osc = Math.sin(tt * (2 + 2 * nv) + p.ph), want = best.radius * (1.1 + 0.5 * nv * (1 + osc)), dir = (dd > want ? 1 : -0.6 * nv), sp = Math.min(6, Math.max(1.2, dd * 0.08)) * (1 + 0.5 * nv * osc);
          p.x += (best.x - p.x) / dd * sp * dir + (Math.random() - 0.5) * 2 * nv; p.y += (best.y - p.y) / dd * sp * dir + (Math.random() - 0.5) * 2 * nv;
          if (Math.hypot(best.x - p.x, best.y - p.y) < best.radius) { p.host = best; p.lost = 0; parStat.rehost++; }
        }
        if (performance.now() - p.lost > P.parasiteHardMs) p.e -= 0.004;
      } else {
        var h = p.host, nvr = 0.85 + 0.2 * P.parasiteNerv * Math.sin(performance.now() / 400 + (p.ph || 0)), tx = h.x + Math.cos(p.a) * h.radius * nvr, ty = h.y + Math.sin(p.a) * h.radius * nvr; p.a += 0.01 + 0.03 * P.parasiteNerv * Math.sin(performance.now() / 700 + (p.ph || 0)); p.x = lerp(p.x, tx, 0.5); p.y = lerp(p.y, ty, 0.5);
        var crowd = Math.max(0, h.pc - 1), dr = P.parasiteDrain * (0.4 + Math.min(h.energy, 20) * 0.03) / (1 + 0.4 * crowd); h.energy -= dr; p.e += dr * P.parasiteEff - 0.012 * (1 + 0.7 * crowd);
      }
      if (p.e <= -P.parasiteHard) { parasites.splice(i, 1); ev.pdeath = (ev.pdeath || 0) + 1; continue; }
      if (p.e > 12 && parasites.length < cells.length * 0.8 + 3) { p.e /= 2; parasites.push({ x: p.x, y: p.y, e: p.e, host: p.host, a: Math.random() * 6.2832 }); ev.pbirth = (ev.pbirth || 0) + 1; }
    }
  }
  // ---- micro habitat: nutrient cycling between cells and the food field.
  // Death returns biomass to the field: dots near a corpse take up fed value and the corpse's colour. When the plate is
  // (nearly) empty, dots fed past the threshold seed small cells in their acquired colour plus a small mutation - the
  // population's dominant colour is the dominant eaten-dot colour, kept as a decayed memory at the eat sites.
  // Engine-agnostic by construction: the hooks sit at the two splice points (JS loop and wasm unpack) and the two eat
  // sites, so the JS and wasm sims and every food mode share identical semantics. No forces are ever added to dots, so
  // swarm isotropy is untouched; mode-owned bodies (worm links, spores, blob rings) are never converted.
  var habStat = { pulse: 0, seed: 0, ate: 0 }, habT = 0; // habT: accumulated habitat seconds, drives the drift phase
  function habHash(x, y) { var h = (Math.imul(x, 73856093) ^ Math.imul(y, 19349663)) >>> 0; h ^= h >>> 13; h = Math.imul(h, 0x5bd1e995) >>> 0; h ^= h >>> 15; return (h >>> 0) / 4294967296; }
  function habField(x, y) { // the single environment field: regional niches x slow drift; writes the sun and fedDecay multipliers exactly once
    var K = Math.floor(P.habitatNiches), niche = 1, x0 = 0, y0 = 0;
    if (K > 1 && cont.w > 0 && cont.h > 0) {
      var gx = (x - cont.x) / cont.w * K, gy = (y - cont.y) / cont.h * K; x0 = Math.floor(gx); y0 = Math.floor(gy);
      var rv = function (ix, iy) { return 1 + P.habitatNicheSun * (2 * habHash(ix, iy) - 1); };
      var fx2 = gx - x0, fy2 = gy - y0;
      var smooth = rv(x0, y0) * (1 - fx2) * (1 - fy2) + rv(x0 + 1, y0) * fx2 * (1 - fy2) + rv(x0, y0 + 1) * (1 - fx2) * fy2 + rv(x0 + 1, y0 + 1) * fx2 * fy2;
      var m = Math.max(0, Math.min(1, P.habitatNicheMix));
      niche = rv(x0, y0) * (1 - m) + smooth * m;
    }
    var dMul = 1;
    if (P.habitatDriftAmp > 0 && P.habitatDrift > 0) {
      var dk = K > 1 ? K : 4, dx0 = Math.floor((x - cont.x) / Math.max(1, cont.w) * dk), dy0 = Math.floor((y - cont.y) / Math.max(1, cont.h) * dk);
      var ph = 2 * Math.PI * P.habitatDrift * habT, off = 2 * Math.PI * habHash(dx0, dy0);
      dMul = 1 + P.habitatDriftAmp * (0.6 * Math.sin(ph + off) + 0.4 * Math.sin(1.618 * ph + 2 * off));
    }
    var sunMul = Math.max(P.habitatDriftFloor, niche * dMul); // the drift never starves the dish: sun multiplier has a floor
    return { sun: sunMul, dec: 1 + (1 - Math.min(1, sunMul)) }; // lean times rot faster
  }
  var ateHueV = null; // decayed memory of eaten-dot hues: the dominant eaten-food colour
  function habReap(c) { // one spliced cell -> one nutrient pulse into the dots around it (absorbed = eaten/fused: biomass stayed in a cell)
    if (!(P.habitatOn || P.habitatReapOn) || !c || c.absorbed) return;
    var col = c.g && c.g.col ? c.g.col : null, R = P.habitatDeadR * cont.w, R2 = R * R, fedK = P.habitatOn ? 1 : P.habitatReapK; // habitat off: the recycle leg alone runs at reduced intensity
    for (var i = 0; i < food.length; i++) {
      var f = food[i], dx = f.x - c.x, dy = f.y - c.y;
      if (dx * dx + dy * dy > R2) continue;
      f.fed = (f.fed || 0) + P.habitatDeadFed * fedK;
      if (col) {
        if (f.hr === undefined) { f.hr = col[0]; f.hg = col[1]; f.hb = col[2]; }
        else { var k = P.habitatDeadCol; f.hr += (col[0] - f.hr) * k; f.hg += (col[1] - f.hg) * k; f.hb += (col[2] - f.hb) * k; }
      }
    }
    habStat.pulse++;
  }
  function habAte(f) { // an eaten dot's hue joins the running dominant-eaten memory
    if (!P.habitatOn || !f || f.hr === undefined) return;
    var k = P.habitatHueK;
    if (!ateHueV) ateHueV = [f.hr, f.hg, f.hb];
    else { ateHueV[0] += (f.hr - ateHueV[0]) * k; ateHueV[1] += (f.hg - ateHueV[1]) * k; ateHueV[2] += (f.hb - ateHueV[2]) * k; }
    habStat.ate++;
  }
  function habSeed(f) { // a fed dot becomes a small cell: its acquired colour (or the dominant eaten colour) + mutation
    var hue = f.hr !== undefined ? [f.hr, f.hg, f.hb] : (ateHueV || [1 / 3, 1 / 3, 1 / 3]), a = P.habitatMut;
    var col = normCol([Math.max(0.001, hue[0] + rnd(-a, a)), Math.max(0.001, hue[1] + rnd(-a, a)), Math.max(0.001, hue[2] + rnd(-a, a))]);
    var k0 = col[0] >= col[1] && col[0] >= col[2] ? 0 : col[1] >= col[2] ? 1 : 2; // dominant channel picks the gene range, same convention as the ctor
    var gene = k0 === 0 ? Math.floor(rnd(3, P.GENE_MAX + 1)) : k0 === 1 ? Math.floor(rnd(P.GENE_MIN, -1)) : Math.floor(rnd(-2, 3));
    var c = new Cell(f.x, f.y, gene, P.baseMutationRate + rnd(-P.mutationRateRange, P.mutationRateRange));
    c.g.col = col; c.radius = Math.max(1, P.CELL_RADIUS * P.habitatSeedR);
    cells.push(c); habStat.seed++;
  }
  function stepHabitat(dtf) {
    if (!P.habitatOn && !P.habitatReapOn) return;
    var fullOn = !!P.habitatOn, FLAT = { sun: 1, dec: 1 };
    var dt = dtf / 1000, i, f;
    var x0 = cont.x, x1 = cont.x + cont.w, y0 = cont.y, y1 = cont.y + cont.h, inPlate = 0;
    for (i = 0; i < cells.length; i++) { var c = cells[i]; if (c.alive && c.x > x0 && c.x < x1 && c.y > y0 && c.y < y1) inPlate++; }
    if (fullOn) habT += dt;
    var seeding = fullOn && inPlate <= P.habitatFloor && cells.length < P.UNIVERSE_SIZE, sun = P.habitatSun, conv = P.habitatConv * dt * cont.w * cont.h / Math.max(1, W * H);
    for (i = food.length - 1; i >= 0; i--) {
      f = food[i];
      if (f.worm || f.spore || f.blob) continue; // mode-owned bodies stay their mode's business
      var fld = fullOn ? habField(f.x, f.y) : FLAT;
      if (f.fed > 0 && P.habitatFedDecay > 0) f.fed = Math.max(0, f.fed - P.habitatFedDecay * fld.dec * dt);
      if (fullOn && sun > 0 && f.x > x0 && f.x < x1 && f.y > y0 && f.y < y1) f.fed = (f.fed || 0) + sun * fld.sun * dt;
      if (seeding && (f.fed || 0) >= P.habitatFedMin && Math.random() < conv) { habSeed(f); f.gone = 1; food.splice(i, 1); }
    }
  }
  function stepAging(dtf) { // lifespan, the missing death channel: age ticks, and an aged-out cell dies and recycles like any other
    if (!(P.cellLife > 0)) return;
    var dt = dtf / 1000;
    for (var i = 0; i < cells.length; i++) { var c = cells[i]; if (!c.alive) continue; c.age = (c.age || 0) + dt; if (c.life && c.age >= c.life) { c.alive = false; c.__dr = 'aging'; } }
  }

  // ---- frame ----
  var res = 1, frameMs = 0;
  var lastFrameT = performance.now(), frameDtf = 16.7;
  // stage profiler (?perf=1 shows it; stage ms are exponential averages, __ca2.PF holds them)
  var PF = {}, pfT = 0, PERF = /[?&]perf=1/.test(location.search);
  function pfm(n) { var t = performance.now(); PF[n] = (PF[n] === undefined ? 0 : PF[n]) * 0.9 + (t - pfT) * 0.1; pfT = t; }
  function frame() {
    if (P.separatorOn) for (var si0 = 0; si0 < cells.length; si0++) { cells[si0]._sepX = cells[si0].x; cells[si0]._sepY = cells[si0].y; }
    var t0 = performance.now() + (window.__ca2ClockVir || 0); pfT = t0; frameT = t0; var dtf = Math.min(100, t0 - lastFrameT); lastFrameT = t0; frameDtf = dtf;
    if (resizeDrag) lastRefresh = t0;
    var pk = trans ? 1 - Math.exp(-dtf * 3 / trans.dur) : P.morphEase;
    if (resizeDrag) pk = 1 - Math.exp(-dtf / Math.max(1, P.wallSmoothMs)); // drag follow: time-based easing, frame-rate independent (owner 25 Oct organic walls)
    var pw0 = cont.ew, ph0 = cont.eh, px0 = cont.x, py0 = cont.y;
    cont.ew += (cont.tw - cont.ew) * pk; cont.eh += (cont.th - cont.eh) * pk;
    if (Math.abs(cont.ew - cont.tw) < 0.1) cont.ew = cont.tw; if (Math.abs(cont.eh - cont.th) < 0.1) cont.eh = cont.th;
    // float wall geometry: physics and drawing share the exact wall; per-frame floor() was the 1px jitter (owner 25 Oct, finding 6)
    cont.w = cont.ew; cont.h = cont.eh; cont.x = (W - cont.w) / 2; cont.y = (H - cont.h) / 2;
    cont.wvx0 = cont.x - px0; cont.wvx1 = cont.x + cont.w - (px0 + pw0); cont.wvy0 = cont.y - py0; cont.wvy1 = cont.y + cont.h - (py0 + ph0); // px/frame edge velocities for the piston carry
    // item 64 directive 3: a wall that moved more than wallSubStep x the smallest body radius in one frame
    // gets extra constraint passes along the interpolated wall path (capped by wallSubMax) - a fast drag can
    // otherwise jump a wall past a small body in a single step. Post-pass after both engines, like the
    // separator stack: identical enforcement for wasm and JS (1:1 by construction).
    var subN = 1, subX0 = px0, subY0 = py0, subW0 = pw0, subH0 = ph0;
    if (P.boundAware) {
      var maxEdge = Math.max(Math.abs(cont.wvx0), Math.abs(cont.wvx1), Math.abs(cont.wvy0), Math.abs(cont.wvy1)), minR2 = Infinity;
      for (var si3 = 0; si3 < cells.length; si3++) { var cm3 = cells[si3]; if (cm3.alive && cm3.radius < minR2) minR2 = cm3.radius; }
      if (!isFinite(minR2)) minR2 = P.CELL_RADIUS;
      subN = Math.min(P.wallSubMax === undefined ? 8 : P.wallSubMax, Math.ceil(maxEdge / Math.max(1e-6, (P.wallSubStep === undefined ? 0.5 : P.wallSubStep) * minR2)));
    }

    if (pendingSpawn) { // batched first spawn: a few cells per frame after the UI intro, food after the cells
      var el0 = t0 - fadeT0;
      if (el0 >= UI_END) { // time-boxed batches: the spawn never blocks a frame longer than ~6 ms
        var sp = pendingSpawn, bt0 = performance.now();
        while (sp.cells > 0 && performance.now() - bt0 < 6) { cells.push(new Cell(rnd(cont.tw) + sp.gx, rnd(cont.th) + sp.gy, Math.floor(rnd(P.GENE_MIN, P.GENE_MAX + 1)), P.baseMutationRate + rnd(-P.mutationRateRange, P.mutationRateRange))); sp.cells--; }
        if (el0 >= CELL_END) { var bt1 = performance.now(); while (sp.food > 0 && performance.now() - bt1 < 6) { var fp2 = foodSpot(sp.gx, sp.gy, cont.tw, cont.th); if (fp2) food.push({ x: fp2.x, y: fp2.y, r: Math.random() }); sp.food--; } }
        if (sp.cells <= 0 && sp.food <= 0) pendingSpawn = null;
      }
    }

    bg = lerpC(bg, bgTarget, P.colorSpeed);
    lctx.setTransform(DD, 0, 0, DD, 0, 0); lctx.clearRect(0, 0, W, H);
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.fillStyle = css(bg, 1); ctx.fillRect(0, 0, W, H);

    if (Math.random() < P.foodDensity && food.length < cont.w * cont.h * P.foodDensity * 2) { var fp3 = foodSpot(cont.x, cont.y, cont.w, cont.h); if (fp3) food.push({ x: fp3.x, y: fp3.y, r: Math.random() }); }
    if (Math.random() < 0.001 && food.length) food.splice(Math.floor(rnd(food.length)), 1);
    pfm('setup');
    if (P.foodMode === 1 || (P.foodMode === undefined && P.foodLife)) stepFood(); else if (P.foodMode === 2) stepBlobs(); else if (P.foodMode === 3) stepSwarm(); else if (P.foodMode === 4) stepWorms(); else if (P.foodMode === 5) stepSpores();
    if (P.foodMode !== 2 && P.foodMode !== 4 && P.foodMode !== 5) reseedFood(dtf); // structured modes keep their own populations
    pfm('food step');
    if (P.foodMode !== 4 && worms.length) wipeWorms(); if (P.foodMode !== 5 && spores.length) wipeSpores();
    foodKeepIn(); foodInkGuard(); pfm('foodKeepIn');

    if (trans) stepTrans(t0, dtf);
    pfm('stepTrans');
    // cluster state: shared motion and energy; a cluster of one dissolves, members sometimes leave on their own
    cmean = {};
    if (P.eatMergeOn) {
      for (i = 0; i < cells.length; i++) { var cc0 = cells[i]; if (!cc0.cl) continue; var m0 = cmean[cc0.cl] || (cmean[cc0.cl] = { n: 0, vx: 0, vy: 0, x: 0, y: 0, e: 0 }); m0.n++; m0.vx += cc0.vx; m0.vy += cc0.vy; m0.x += cc0.x; m0.y += cc0.y; m0.e += cc0.energy; }
      for (var kk in cmean) { var mm = cmean[kk]; mm.vx /= mm.n; mm.vy /= mm.n; mm.x /= mm.n; mm.y /= mm.n; mm.e /= mm.n; }
      for (i = 0; i < cells.length; i++) { var c1 = cells[i]; if (c1.cl && (cmean[c1.cl].n < 2 || Math.random() < 0.0005)) c1.cl = 0; }
    } else for (i = 0; i < cells.length; i++) cells[i].cl = 0;
    var clusterCount = Object.keys(cmean).length;
    pfm('cluster state'); hovering = false; var tmpHover = [255, 255, 255], hoverCell = null;
    var tmpR = { v: null }, tj0 = performance.now(), simDone = simW(tmpR); SIMW.frames = (SIMW.frames || 0) + 1; if (simDone) { tmpHover = tmpR.v; hoverCell = tmpR.hc; }
    if (!simDone) for (var i = cells.length - 1; i >= 0; i--) {
      var c = cells[i]; update(c); checkSurvival(c);
      if (mouse.over && Math.hypot(mouse.x - c.x, mouse.y - c.y) < c.radius && c.x > cont.x && c.x < cont.x + cont.w && c.y > cont.y && c.y < cont.y + cont.h) {
        hovering = true; hoverCell = c;
        var r = 0, g = 0, b = 0;
        for (var j = 0; j < cells.length; j++) {
          var o = cells[j]; if (!o.alive) continue;
          var d = Math.hypot(mouse.x - o.x, mouse.y - o.y), inf = P.metaballStrength * c.radius * c.radius / (d * d + 0.0001); inf *= inf;
          if (P.genomeOn && o.g) { r += inf * o.g.col[0]; g += inf * o.g.col[1]; b += inf * o.g.col[2]; } else if (o.gene > 2) r += inf; else if (o.gene < -2) g += inf; else b += inf;
        }
        var t = r + g + b; if (t > 0) { r /= t; g /= t; b /= t; }
        tmpHover = [r * 255, g * 255, b * 255];
      }
      for (var k = i - 1; k >= 0; k--) interact(c, cells[k]);
      if (resizeDrag && c.alive) { var ms2 = (c.maxSpeed + 1) * P.restless; c.vx += (Math.random() - 0.5) * ms2 * 2; c.vy += (Math.random() - 0.5) * ms2 * 2; }
      if (P.boundAware && c.alive) keepIn(c);
      if (!c.alive) { ev.death++; logDeath(c, c.__dr || 'untagged-js'); habReap(c); cells.splice(i, 1); }
    }
    if (!simDone) SIMW.js = (SIMW.js || 0) * 0.9 + (performance.now() - tj0) * 0.1;
    if (subN > 1) wallSubPass(subN, subX0, subY0, subW0, subH0);
    if (P.separatorOn) { ctx.save(); drawAxis(lay(), String(cells.length), String(Math.round(mouse.x)), true); ctx.restore(); separatorPass(); pfm('separator'); } // one mechanism after both engines: identical enforcement for wasm and JS (1:1 by construction)
    constraintSolver(); pfm('solver'); // item 64 directive 6: walls+segments+overlap converge in one iteration loop
    finalWallClamp(); // item 64 (main 25 Oct, 46/46 pen defect root fix): the plate wall wins last after keepIn/separatorPass/constraintSolver - same call in every path
    stepSquash(); // item 64 directive 2: one eased squash state per frame for BOTH engines, after every sqS feed (post-pass, 1:1 by construction - the wasm engine exports its press signal via the SQS slot instead of easing internally). Was draw-side (GPU/noDraw paths skipped it) + inside wasm keep_in (double ease on the CPU-draw path)
    hoverCol = hovering ? tmpHover : [255, 255, 255];
    stepParasites(); pfm('sim loop+parasites');
    stepAging(dtf); stepHabitat(dtf); pfm('habitat');
    if (window.__ca2NoDraw === 1) return; // measurement harness (main 25 Oct): everything above is the complete sim step incl. aging/habitat; mode 1 skips all rendering/audio below, mode 2 continues through the ink-mask refresh. (82c08ee left the 518327f pre-aging return in place, so stepped phases silently skipped aging/habitat until this fix.)

    var Lx = lay(), sT0 = String(cells.length), sX0 = String(Math.round(mouse.x));
    var mv = mouse.over ? invAt(mouse.x, mouse.y) : [bg[0] > 128 ? 0 : 255, bg[0] > 128 ? 0 : 255, bg[0] > 128 ? 0 : 255], k2 = 0.3;
    var tt, tl, tc, ta, trr, tgg, tbb;
    if (hovering) { tt = hoverCol.concat(1); tc = hoverCol.concat(1); ta = hoverCol.concat(1); trr = tgg = tbb = hoverCol.concat(1); tl = mv.concat(1); }
    else { tt = mv.concat(1); tc = mv.concat(50 / 255); tl = mv.concat(222 / 255); ta = mv.concat(30 / 255); trr = [255, 0, 0, 1]; tgg = [0, 255, 0, 1]; tbb = [0, 0, 255, 1]; }
    eased.total = lerpA(eased.total, tt, k2); eased.title = lerpA(eased.title, tl, k2); eased.coor = lerpA(eased.coor, tc, k2);
    eased.axis = lerpA(eased.axis, ta, k2); eased.r = lerpA(eased.r, trr, k2); eased.g = lerpA(eased.g, tgg, k2); eased.b = lerpA(eased.b, tbb, k2);

    if (P.axisLayer === 0 && P.showAxis) drawAxis(Lx, sT0, sX0);
    var rc = 0, gc = 0, bc = 0, inN = 0;
    for (i = 0; i < cells.length; i++) { var gn = cells[i].gene; if (gn > 2) rc++; else if (gn < -2) gc++; else bc++; var ci = cells[i]; if (ci.alive && ci.x > cont.x && ci.x < cont.x + cont.w && ci.y > cont.y && ci.y < cont.y + cont.h) inN++; }
    // owner 22 Oct: when the boundary stroke would be the selected background colour itself it becomes invisible -
    // then (and only then) it takes the axis line colour. Holds for the outline and the resize icons alike (one plateCol).
    var plateCol = function () {
      var c = inN ? dom : null;
      if (c && c[0] === (bgTarget[0] | 0) && c[1] === (bgTarget[1] | 0) && c[2] === (bgTarget[2] | 0)) c = null;
      return c ? css(c, 1) : (P.axisColor || css(eased.axis, 1));
    }; // empty plate takes the axis line colour (owner 21 Oct), boundary and resize icons alike
    var dom = [0, 0, 0];
    if (rc > gc && rc > bc) dom = [255, 0, 0]; else if (gc > rc && gc > bc) dom = [0, 255, 0]; else if (bc > rc && bc > gc) dom = [0, 0, 255];

    pfm('axis+tally'); var L = lay(), M = L.M, G = L.G, fs = L.fs, dh = L.dh;
    var sY = String(Math.round(mouse.y)), sX = String(Math.round(mouse.x)), sT = String(cells.length);
    var vTop = M + dh + L.row + G, vBot = H - M - dh - G, cxm = W / 2, cym = H / 2, topBase0 = M + dh;
    if (P.showHud) {
      ctx.font = fs + 'px "Ca2-Thin", monospace'; ctx.textBaseline = 'alphabetic';
      if (P.separatorOn) { // half-resolution ink mask of every HUD string: the cells' typography awareness
        var mw2 = Math.max(1, W >> 1), mh2 = Math.max(1, H >> 1);
        if (!SEP.c || SEP.c.width !== mw2 || SEP.c.height !== mh2) { SEP.c = document.createElement('canvas'); SEP.c.width = mw2; SEP.c.height = mh2; SEP.mc = SEP.c.getContext('2d', { willReadFrequently: true }); }
        SEP.mc.setTransform(0.5, 0, 0, 0.5, 0, 0); SEP.mc.clearRect(0, 0, W, H);
        SEP.mc.font = ctx.font; SEP.mc.textAlign = 'left'; SEP.mc.textBaseline = 'alphabetic'; SEP.mc.fillStyle = '#fff';
      } else if (SEP.mc) { SEP.mc = null; SEP.c = null; SEP.img = null; }
      var hi = 0, put = function (txt, col, align, x, y, ex) {
        ex = ex || 0;
        var hk = hi++;
        ctx.fillStyle = css(col); ctx.textAlign = 'left';
        var lr = inkLR(txt), wEx = (txt.length - 1) * ex, x0 = align === 'right' ? x - lr[1] - wEx : align === 'center' ? x - (lr[0] + lr[1]) / 2 - wEx / 2 : x - lr[0];
        for (var ci = 0; ci < txt.length; ci++) if (fadeA('c' + hk + ':' + ci)) { var gx = x0 + ctx.measureText(txt.slice(0, ci)).width + ci * ex; ctx.fillText(txt[ci], gx, y); if (SEP.mc) SEP.mc.fillText(txt[ci], gx, y); }
      };
      // ink-aligned margins: every edge has the same margin M
      // right-edge compensation (owner 21 Oct, font file untouched): on some platforms the final glyph's rsb leaves the
      // word's true ink short of the right margin. Pixel-measure the rendered title line once per layout and shift the
      // word by the residual so the right distance equals the top one. One frame of lag, invisible; margins/font sizes
      // re-measure themselves because they are part of the key.
      if (rsbCache.key !== rsbKey(fs, M, L.ex)) rsbCache = { key: rsbKey(fs, M, L.ex), dx: 0, done: false };
      if (!L.three) rsbScan(fs, dh, M, L.ex); // offscreen and synchronous: the compensation applies in this same frame
      // conditional (owner 21 Oct): only when the three-line title's 3rd line (the mouse-y row) vertically OVERLAPS
      // the left/right numbers on the middle axis - measured ink bands, not a fixed threshold - the numbers leave the
      // axis line and sit on the title's 3rd line, riding down with it as it grows. No overlap: nothing moves. The
      // axis line and the axis centre never move. (Ink bands: digits/caps have no descenders, so a row's ink is
      // [baseline-dh, baseline].) Guard (mobile team edge case, 780x360 ts4): when the page is so short that the 3rd
      // line itself already reaches the bottom numbers row, the move would interleave the numbers with that row -
      // the same collision the rule exists to prevent - so the numbers keep their natural place instead.
      var topBase = M + dh, botBase = H - M, midBase = cym + dh / 2;
      if (L.three) {
        var yRow = topBase + 2 * L.lead;
        if (yRow > midBase - dh && yRow <= botBase - dh) midBase = yRow;
      }
      if (L.three) { // CELLULAR / AUTOMATA / mouse-y, ink-centred, baseline step = cap height + the letter space x the line-space knob
        put(TL, eased.title, 'center', cxm, topBase, L.ex);
        put(TR, eased.title, 'center', cxm, topBase + L.lead, L.ex);
        put(sY, eased.coor, 'center', cxm, topBase + 2 * L.lead);
      } else {
        put(TL, eased.title, 'left', M, topBase, L.ex);
        put(TR, eased.title, 'right', W - M + rsbCache.dx, topBase, L.ex);
        put(sY, eased.coor, 'center', cxm, topBase + L.row);
      }
      put(sX, eased.coor, 'right', W - M, midBase);
      put(sT, eased.total, 'left', M, midBase);
      put(String(bc), eased.b, 'right', W - M, botBase);
      put(String(rc), eased.r, 'left', M, botBase);
      put(String(gc), eased.g, 'center', cxm, botBase);
      if (SEP.mc) { SEP.img = SEP.mc.getImageData(0, 0, SEP.c.width, SEP.c.height).data; SEP.mw = SEP.c.width; SEP.mh = SEP.c.height; SEP.builtT = frameT; separatorPass(); separatorCollectivePass(); foodInkGuard(); } // re-resolve against this frame's actual glyphs before bodies are drawn
    }

    if(P.separatorOn&&!P.showHud)separatorCollectivePass();
    finalWallClamp(); // item 64: the ink re-resolve above relocates bodies centre-clamped only - the wall wins last in the render and stepped-mode-2 paths too
    pfm('hud text');
    // title circles: hover turns a circle to random black or white (new random pick on every hover); the cursor reacts
    var titleHit = null;
    if (P.showHud && P.titleCircles) {
      ctx.font = fs + 'px "Ca2-Thin", monospace'; ctx.textAlign = 'left';
      ctx.textAlign = 'left'; var lrTL = inkLR(TL), lrTR = inkLR(TR);
      var x0L = L.three ? cxm - (lrTL[0] + lrTL[1]) / 2 - (TL.length - 1) * L.ex / 2 : M - lrTL[0], x0R = L.three ? cxm - (lrTR[0] + lrTR[1]) / 2 - (TR.length - 1) * L.ex / 2 : (W - M + rsbCache.dx) - lrTR[1] - (TR.length - 1) * L.ex;
      var baseTL = topBase0, baseTR = topBase0 + (L.three ? L.lead : 0);
      var u = fs / 1000, R0 = 166.5 * u, hitKey = null, hitC = null; circlesNow = [];
      [[TL, x0L, 'L', baseTL], [TR, x0R, 'R', baseTR]].forEach(function (t) {
        for (var gi = 0; gi < t[0].length; gi++) {
          var cs = GL[t[0][gi]]; if (!cs) continue; var ox = t[1] + ctx.measureText(t[0].slice(0, gi)).width + gi * L.ex;
          for (var ci = 0; ci < cs.length; ci++) {
            var cx2 = ox + cs[ci][0] * u, cy2 = t[3] - cs[ci][1] * u, key = t[2] + gi + '_' + ci;
            circlesNow.push({ key: key, x: cx2, y: cy2, r: R0 });
            if (mouse.over && Math.hypot(mouse.x - cx2, mouse.y - cy2) < R0) { hitKey = key; hitC = { x: cx2, y: cy2, r: R0 }; }
          }
        }
      });
      if (hitKey && hitKey !== lastCircleHit) { circleCol[hitKey] = CIRCLE_COLS[(Math.random() * CIRCLE_COLS.length) | 0]; targetCursorScale = 3.5; cursorScale = 3.5; }
      // hold off: the circle the cursor LEFT reverts too, not only the last one when nothing is hovered (direct circle-to-circle moves used to leave the old color stuck)
      if (lastCircleHit && lastCircleHit !== hitKey && !P.circleHold) delete circleCol[lastCircleHit];
      lastCircleHit = hitKey || '';
      circlesNow.forEach(function (c) { var v = circleCol[c.key]; if (v !== undefined) { ctx.fillStyle = css(v); ctx.beginPath(); ctx.arc(c.x, c.y, c.r + 0.6, 0, 6.2832); ctx.fill(); } });
      if (hitKey) titleHit = { c: hitC, v: circleCol[hitKey] };
    }
    // food rides the same boundary morph as cells (owner 21 Oct): dots/spores directly, blobs and worms by their owner
    if (P.boundAware) {
      for (i = 0; i < blobs.length; i++) wallPull(blobs[i], blobs[i].r, false);
      for (i = 0; i < worms.length; i++) wallPull(worms[i], P.foodSize / 2, false);
      for (i = 0; i < food.length; i++) { var ff = food[i]; if (!ff.blob && !ff.worm) wallPull(ff, P.foodSize / 2, false); }
    }
    foodInkGuard(); // the boundary carry above can move dots onto ink: re-resolve before the dots are drawn
    if (window.__ca2NoDraw) return; // measurement harness mode 2 (main 25 Oct): full sim step + aging/habitat + fresh ink mask + food boundary carry ran; only pure drawing/audio below is skipped (faithful separator-on stepped path)
    if (P.showFood && P.foodAlpha > 0 && P.foodMode === 2) drawBlobs(); else if (P.showFood && P.foodAlpha > 0 && P.foodMode === 4) drawWorms(); else if (P.showFood && P.foodAlpha > 0 && P.foodMode === 5) drawSpores(); else if (P.showFood && P.foodAlpha > 0) { ctx.globalAlpha = P.foodAlpha; ctx.fillStyle = P.foodColor; var fs = P.foodSize, fh = fs / 2; for (i = 0; i < food.length; i++) { var fd2 = food[i]; if (fd2.r < P.foodShow && introOn(CELL_END + fd2.r * (FOOD_END - CELL_END))) { var fs2 = fd2.fed > 0 && P.habitatFedShow > 0 ? fs * (1 + Math.min(3, fd2.fed * P.habitatFedShow)) : fs, fh2 = fs2 / 2; ctx.fillRect(fd2.x - fh2, fd2.y - fh2, fs2, fs2); } } ctx.globalAlpha = 1; } // food first: it sits under the cells
    pfm('sim+ui draw'); curS = DPR * res; if (cells.length || t0 - fadeT0 > INTRO_MS) { var tmb = performance.now(); drawMetaballs(curS); MB.ms = MB.ms * 0.9 + (performance.now() - tmb) * 0.1; MB.path = gOn ? 'GPU' : (WC.ok && !WC.off ? (WC.simd ? 'wasm-simd' : 'wasm') : 'JS'); } pfm('metaballs total'); // an empty intro plate skips the full-buffer pass
    if (P.parasiteOn && parasites.length) { var pc = css(eased.title, 1); ctx.fillStyle = pc; for (i = 0; i < parasites.length; i++) { var pp2 = parasites[i]; if (!fadeA('pa' + i)) continue;
      // owner 22 Oct: parasites are triangles, not dots - the circle blurred into small cells. Same ink area as the r2.2
      // dot (no size growth): apex 3.43 / base half 2.965 / rear 1.71 = area 15.2. The apex tracks the cell the parasite
      // rides or burns (smoothed pursuit, organic); the base edge breathes +/-12% at ~9 Hz like a fly's wing.
      var ta2 = pp2.h || 0;
      if (pp2.host && pp2.host.alive) ta2 = Math.atan2(pp2.host.y - pp2.y, pp2.host.x - pp2.x);
      else if (pp2.px !== undefined && (pp2.x !== pp2.px || pp2.y !== pp2.py)) ta2 = Math.atan2(pp2.y - pp2.py, pp2.x - pp2.px);
      if (pp2.h === undefined) pp2.h = ta2;
      var dh2 = ta2 - pp2.h; while (dh2 > 3.1416) dh2 -= 6.2832; while (dh2 < -3.1416) dh2 += 6.2832;
      pp2.h += dh2 * (1 - Math.exp(-dtf * 0.012)); pp2.px = pp2.x; pp2.py = pp2.y;
      var psz = P.parasiteSize > 0 ? P.parasiteSize : 1; // owner 22 Oct: size knob, 1 = the shipped size; manual entry is never clamped
      // user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02: wing tips slightly rounded, flap more apparent and coordinated with the motion.
      // Speed (smoothed px/frame) scales both beat rate and depth; at rest the beat is the shipped ~9 Hz, only a bit deeper (12% -> 22%).
      var spd2 = pp2.fx === undefined ? 0 : Math.hypot(pp2.x - pp2.fx, pp2.y - pp2.fy); pp2.fx = pp2.x; pp2.fy = pp2.y;
      pp2.sp = (pp2.sp || 0) + (Math.min(spd2, 6) - (pp2.sp || 0)) * 0.15;
      pp2.fp = (pp2.fp === undefined ? (pp2.ph || 0) : pp2.fp) + dtf * 0.0565 * (1 + 0.12 * pp2.sp);
      var fl2 = Math.sin(pp2.fp), amp2 = 0.22 + 0.025 * pp2.sp;
      var ux2 = Math.cos(pp2.h), uy2 = Math.sin(pp2.h), vx2 = -uy2, vy2 = ux2, bw2 = 2.965 * psz * (1 + amp2 * fl2), rr2 = (1.71 - 0.35 * fl2) * psz, rad2 = 0.5 * psz;
      var ax2 = pp2.x + ux2 * 3.43 * psz, ay2 = pp2.y + uy2 * 3.43 * psz, lx2 = pp2.x - ux2 * rr2 + vx2 * bw2, ly2 = pp2.y - uy2 * rr2 + vy2 * bw2, mx2 = pp2.x - ux2 * rr2 - vx2 * bw2, my2 = pp2.y - uy2 * rr2 - vy2 * bw2;
      ctx.beginPath(); // the two base corners (wing tips) rounded with arcTo
      ctx.moveTo((ax2 + lx2) / 2, (ay2 + ly2) / 2);
      ctx.arcTo(lx2, ly2, mx2, my2, rad2);
      ctx.arcTo(mx2, my2, ax2, ay2, rad2);
      ctx.lineTo(ax2, ay2);
      ctx.fill(); } ctx.globalAlpha = 1; }

    // area outline: no rounded corners. Each side stops `corner` px short of both ends, so the corner lines never meet.
    var cr = Math.min(P.containerCorner, cont.w / 2, cont.h / 2);
    lctx.strokeStyle = plateCol(); lctx.lineWidth = LW(); lctx.lineCap = 'butt';
    var bxs = [[cont.x + cr, cont.y, cont.x + cont.w - cr, cont.y], [cont.x + cont.w, cont.y + cr, cont.x + cont.w, cont.y + cont.h - cr], [cont.x + cont.w - cr, cont.y + cont.h, cont.x + cr, cont.y + cont.h], [cont.x, cont.y + cont.h - cr, cont.x, cont.y + cr]];
    for (var bi = 0; bi < 4; bi++) if (P.axisWidth > 0 && fadeA('bx' + bi)) { var bq = bxs[bi].map(snapC); lctx.beginPath(); lctx.moveTo(bq[0], bq[1]); lctx.lineTo(bq[2], bq[3]); lctx.stroke(); }

    if (P.axisLayer !== 0 && P.showAxis) drawAxis(L, sT, sX);
    // cursor: ring + dot drawn as a DOM overlay that follows the pointer (identical in every browser); the system cursor is hidden only while it shows
    var eHit = resizeDrag || (mouse.over && !panel.matches(':hover') ? edgeHit(mouse.x, mouse.y) : null);
    if (eHit) {
      var Le = Math.max(10, lay().dh / 2), gE = Math.max(4, Le * 0.22), dE, offE = Le + 2; // vertex one full arm-length out: no arm ever crosses the boundary line
      var rightE = eHit.rx !== undefined ? eHit.rx : mouse.x >= W / 2, downE = eHit.dy !== undefined ? eHit.dy : mouse.y >= H / 2; // a drag keeps the corner it grabbed
      var bxE = rightE ? cont.x + cont.w : cont.x, byE = downE ? cont.y + cont.h : cont.y;
      // owner 21 Oct: an axis with less than FLIP_T px of growth left (screen edge minus the drag margin) flips its
      // icons to point the shrink direction - vertex inside the plate, tip facing out. Width and height flip apart.
      var FLIP_T = 8;
      // owner 21 Oct: during an active drag the icons point the way the resize is going (per axis, sign of the last
      // nonzero size change, kept on the drag handle so pauses hold the direction); with no drag the ceiling rule decides
      if (resizeDrag) {
        if (resizeDrag._pw === undefined) { resizeDrag._pw = cont.tw; resizeDrag._ph = cont.th; resizeDrag._dw = 1; resizeDrag._dh = 1; }
        if (cont.tw !== resizeDrag._pw) { resizeDrag._dw = cont.tw - resizeDrag._pw; resizeDrag._pw = cont.tw; }
        if (cont.th !== resizeDrag._ph) { resizeDrag._dh = cont.th - resizeDrag._ph; resizeDrag._ph = cont.th; }
      }
      var flipW = resizeDrag ? resizeDrag._dw < 0 : (W - 2 * P.dragMargin) - cont.w < FLIP_T;
      var flipH = resizeDrag ? resizeDrag._dh < 0 : (H - 2 * P.dragMargin) - cont.h < FLIP_T;
      if (eHit.h && eHit.v) { // corner: the edge icon rotated onto the diagonal, vertex outside the corner, tip facing the plate
        // owner 22 Oct: the screen-edge ceiling rule must NOT flip corner icons - they keep their mid-page form
        // (vertex outside, tip to the plate). Only an active drag's direction rule may flip them. Edge icons unchanged.
        var flipC = resizeDrag ? (flipW || flipH) : false; // a corner drag grows both axes, so one capped axis flips the pair
        var a0 = rightE ? (downE ? 45 : -45) : (downE ? 135 : -135), r0 = a0 * Math.PI / 180;
        var gC = gE * 1.8, offC = 4.5; // wider gap between the two arms; arms lengthened by the same amount so the visible strokes keep their length; vertex hugs the corner
        dE = anglePath(flipC ? a0 : a0 + 180, Le + (gC - gE), gC, bxE + (flipC ? -1 : 1) * Math.cos(r0) * offC, byE + (flipC ? -1 : 1) * Math.sin(r0) * offC);
        if (resizeDrag) { // while a corner is dragged all four corner icons stay visible (the plate resizes symmetrically; owner 20 Oct)
          dE = '';
          [[false, false, -135], [true, false, -45], [false, true, 135], [true, true, 45]].forEach(function (q) {
            var rq = q[2] * Math.PI / 180, vx = (q[0] ? cont.x + cont.w : cont.x) + (flipC ? -1 : 1) * Math.cos(rq) * offC, vy = (q[1] ? cont.y + cont.h : cont.y) + (flipC ? -1 : 1) * Math.sin(rq) * offC;
            dE += anglePath(flipC ? q[2] : q[2] + 180, Le + (gC - gE), gC, vx, vy);
          });
        }
      } else if (eHit.h) { // vertical edge: vertex just outside it, at the pointer's height, tip facing the plate
        dE = anglePath(flipW ? (rightE ? 180 : 0) : (rightE ? 0 : 180), Le, gE, bxE + (flipW ? -1 : 1) * (rightE ? offE : -offE), clamp(mouse.y, cont.y, cont.y + cont.h));
      } else { // horizontal edge
        dE = anglePath(flipH ? (downE ? -90 : 90) : (downE ? 90 : -90), Le, gE, clamp(mouse.x, cont.x, cont.x + cont.w), byE + (flipH ? -1 : 1) * (downE ? offE : -offE));
      }
      curEdgePath.setAttribute('d', dE); curEdgePath.setAttribute('stroke', plateCol()); curEdgePath.setAttribute('stroke-width', LW());
      curEdge.style.display = P.axisWidth > 0 ? 'block' : 'none'; curEdge.style.transform = 'translate(0px,0px)';
      curEl.style.display = 'none'; cv.style.cursor = 'none'; curOn0 = false; lockCell = null;
      curInfo = { on: true, edge: true, corner: !!(eHit.h && eHit.v), ring: false };
    } else {
    curEdge.style.display = 'none';
    cursorScale += (targetCursorScale - cursorScale) * 0.75;
    var curOn = false, curRR = 0, curCol = '#000', dotOnly = false;
    if (hovering && mouse.over && hoverCell) { curOn = true; var mxr = 0; for (var q = 0; q < cells.length; q++) { var cq = cells[q]; if (cq.alive && cq.x > cont.x && cq.x < cont.x + cont.w && cq.y > cont.y && cq.y < cont.y + cont.h && cq.radius > mxr) mxr = cq.radius; }
      curMaxR += (mxr - curMaxR) * 0.3; curRR = Math.max(3, curMaxR * P.cursorSize);
      var tnow = performance.now(); if (hoverCell !== lockCell) { lockCell = hoverCell; lockT0 = tnow; } curCol = css(hoverCol, 1); }
    else if (titleHit) { curOn = true; curRR = Math.max(5, titleHit.c.r * 0.55 * (0.8 + 0.2 * cursorScale)); var iv = [255 - titleHit.v[0], 255 - titleHit.v[1], 255 - titleHit.v[2]]; curCol = css(iv); }
    var ringOn = curOn;
    if (!curOn && mouse.over && !panel.matches(':hover')) { curOn = true; dotOnly = true; }
    if (curOn) {
      curEl.style.display = 'block'; curRRnow = curRR;
      curEl.style.width = curEl.style.height = (curRR * 2) + 'px'; curEl.style.borderWidth = dotOnly ? '0px' : LW() + 'px'; curEl.style.borderColor = curCol;
      var dp = 4.4, dcol = titleHit && !(hovering && hoverCell) ? css([255 - titleHit.v[0], 255 - titleHit.v[1], 255 - titleHit.v[2]]) : css(invAt(mouse.x, mouse.y), 1); curDot.style.width = curDot.style.height = dp + 'px'; curDot.style.background = dcol; curDot.style.display = ''; curInfo3 = { dot: dcol, dp: dp };
      var tx = mouse.x, ty = mouse.y, locked = P.cursorLockMs > 0 && hovering && lockCell && lockCell.alive && performance.now() - lockT0 < P.cursorLockMs;
      if (locked) { tx = lockCell.x; ty = lockCell.y; }
      var sens = clamp(P.cursorSens, 0.05, 1), ke = locked ? Math.min(1, sens + 0.1) : sens; curX = curOn0 ? curX + (tx - curX) * ke : tx; curY = curOn0 ? curY + (ty - curY) * ke : ty; curOn0 = true; curInfo2 = { locked: locked, x: curX, y: curY, lx: lockCell ? lockCell.x : 0, ly: lockCell ? lockCell.y : 0 };
      curEl.style.transform = 'translate(' + (curX - curRR) + 'px,' + (curY - curRR) + 'px)';
      cv.style.cursor = 'none';
    } else { curEl.style.display = 'none'; cv.style.cursor = 'default'; curOn0 = false; lockCell = null; }
    curInfo = { on: curOn, ring: ringOn, dot: curInfo3.dot, dp: curInfo3.dp, lx: curInfo2.lx, ly: curInfo2.ly, locked: curInfo2.locked, maxR: curMaxR, cx: curX, cy: curY, rr: curRR, col: curCol, title: !!titleHit };
    }

     var pairN = 0, compN = 0; for (var pci = 0; pci < cells.length; pci++) { if (cells[pci].sym) pairN++; if (cells[pci].comp > 1) compN++; }
     window.__ca2 = { SIMW: SIMW, cmpGmax384: function () { // bit-identity gate for adaptive GMAX: same frozen source array (n<=384) through the 384-reference program and the device program; harness requires diffBytes=0
      if (!gOK) return 'nogl'; if (!gProg384) return 'noreference';
      var S = curS, src = buildSources(), ms = P.metaballStrength, TH = P.THRESHOLD, n = Math.min(src.n, 384), i;
      var C = new Float32Array(n * 4), W = new Float32Array(n * 4);
      for (i = 0; i < n; i++) { C[i * 4] = src.x[i]; C[i * 4 + 1] = src.y[i]; C[i * 4 + 2] = ms * src.r[i] * src.r[i]; C[i * 4 + 3] = src.r[i] * Math.max(3, Math.sqrt(ms / (TH * 0.03))); W[i * 4] = src.wr[i]; W[i * 4 + 1] = src.wg[i]; W[i * 4 + 2] = src.wb[i]; }
      var bw = Math.max(1, Math.ceil(cont.w * S)), bh = Math.max(1, Math.ceil(cont.h * S));
      if (glc.width !== bw || glc.height !== bh) { glc.width = bw; glc.height = bh; }
      function pass(prog) { gl.viewport(0, 0, bw, bh); gl.useProgram(prog); var u = {}, nm = ['uC', 'uW', 'uN', 'uS', 'uH', 'uTH', 'uBand']; for (var k = 0; k < nm.length; k++) u[nm[k]] = gl.getUniformLocation(prog, nm[k]); gl.uniform1f(u.uS, S); gl.uniform1f(u.uH, bh); gl.uniform1f(u.uTH, TH); gl.uniform1f(u.uBand, TH * 0.08); gl.clearColor(0, 0, 0, 0); gl.clear(gl.COLOR_BUFFER_BIT); gl.uniform4fv(u.uC, C); gl.uniform4fv(u.uW, W); gl.uniform1i(u.uN, n); gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4); gl.finish(); var px = new Uint8Array(bw * bh * 4); gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, px); return px; } // gl.readPixels: the drawImage readback is NOT deterministic on swiftshader (selfDiff ~1% at same-program same-input)

      var a = pass(gProg384), b = pass(gProg), c = pass(gProg), d = 0, mx = 0, dbc = 0;
      for (i = 0; i < a.length; i++) { var dd = Math.abs(a[i] - b[i]); if (dd) { d++; if (dd > mx) mx = dd; } if (b[i] !== c[i]) dbc++; }
      gl.useProgram(gProg);
      return JSON.stringify({ bytes: a.length, diffBytes: d, maxDiff: mx, selfDiff: dbc, n: n, gmax: GMAX, bw: bw, bh: bh });
    }, setGmaxTest: function (v) { GMAX = v | 0 || 384; }, setZeroTail: function (v) { gZeroTail = !!v; }, // t119 ONLY: forces subdivision/overflow paths in cmpGpuPaths; never ship-set
      t118: function (tiled, seconds) { // t118 harness: SAME FROZEN source array through full or tiled gpuDraw; a 1px readPixels after each draw forces real raster completion (glc is offscreen: rAF alone never blocks). Returns per-frame wall stats.
      if (!gOK) return 'nogl';
      if (!window.__t118pack) { // one freeze shared by both modes: full and tiled render the SAME source array/geometry
        var S0 = curS, src = buildSources(), ms0 = P.metaballStrength, TH0 = P.THRESHOLD, n0 = Math.min(src.n, gShaderMax || GMAX), j;
        var C0 = new Float32Array(n0 * 4), W0 = new Float32Array(n0 * 4);
        for (j = 0; j < n0; j++) { C0[j * 4] = src.x[j]; C0[j * 4 + 1] = src.y[j]; C0[j * 4 + 2] = ms0 * src.r[j] * src.r[j]; C0[j * 4 + 3] = src.r[j] * Math.max(3, Math.sqrt(ms0 / (TH0 * 0.03))); W0[j * 4] = src.wr[j]; W0[j * 4 + 1] = src.wg[j]; W0[j * 4 + 2] = src.wb[j]; }
        window.__t118pack = { C: C0, W: W0, n: n0, S: S0, bw: Math.max(1, Math.ceil(cont.w * S0)), bh: Math.max(1, Math.ceil(cont.h * S0)) };
      }
      var pk = window.__t118pack, S = pk.S, n = pk.n, C = pk.C, W = pk.W, i;
      var bw = pk.bw, bh = pk.bh;
      if (glc.width !== bw || glc.height !== bh) { glc.width = bw; glc.height = bh; }
      var px = new Uint8Array(4);
      return new Promise(function (done) {
        var dts = [], last = performance.now(), t0 = last, frames = 0;
        (function f() {
          gpuDraw(C, W, n, bw, bh, S, tiled); gl.finish(); gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
          var now = performance.now(); dts.push(now - last); last = now; frames++;
          if (now - t0 < seconds * 1000) requestAnimationFrame(f); else {
            dts.sort(function (a, b) { return a - b; });
            var q = function (p) { return +dts[Math.min(dts.length - 1, Math.floor(dts.length * p))].toFixed(1); };
            done(JSON.stringify({ tiled: !!tiled, frames: frames, fps: +(frames / seconds).toFixed(2), p50: q(0.5), p95: q(0.95), p99: q(0.99), max: +dts[dts.length - 1].toFixed(1), n: n, gmax: GMAX, bw: bw, bh: bh, overflow: gOv }));
          }
        })();
      });
    }, cmpOverflowCost: function () { // the overflow-frame raster cost, measured: SAME frozen source array through (a) the GPU full pass (= live baseline c20cb7e behavior at real GMAX) and (b) drawMetaballsCPU (= candidate overflow fallback); diff rule identical to cmp()
      if (!gOK) return 'nogl';
      var S = curS, src = buildSources(), ms = P.metaballStrength, TH = P.THRESHOLD, n = Math.min(src.n, gShaderMax || GMAX), i;
      var C = new Float32Array(n * 4), W = new Float32Array(n * 4);
      for (i = 0; i < n; i++) { C[i * 4] = src.x[i]; C[i * 4 + 1] = src.y[i]; C[i * 4 + 2] = ms * src.r[i] * src.r[i]; C[i * 4 + 3] = src.r[i] * Math.max(3, Math.sqrt(ms / (TH * 0.03))); W[i * 4] = src.wr[i]; W[i * 4 + 1] = src.wg[i]; W[i * 4 + 2] = src.wb[i]; }
      var bw = Math.max(1, Math.ceil(cont.w * S)), bh = Math.max(1, Math.ceil(cont.h * S));
      if (glc.width !== bw || glc.height !== bh) { glc.width = bw; glc.height = bh; }
      gpuDraw(C, W, n, bw, bh, S, false); gl.finish(); var a = new Uint8Array(bw * bh * 4); gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, a);
      var sv = ctx.drawImage; ctx.drawImage = function () {}; drawMetaballsCPU(S); ctx.drawImage = sv;
      var cd = img.data, bad = 0, mx = 0, lit = 0;
      for (var p = 0; p < bw * bh; p++) { var q = p * 4, ga = a[q + 3], ca = cd[q + 3]; var d = Math.abs(ga - ca); if (ca > 0 || ga > 0) { lit++; if (ca > 250 && ga > 250) d = Math.max(d, Math.abs(a[q] - cd[q]), Math.abs(a[q + 1] - cd[q + 1]), Math.abs(a[q + 2] - cd[q + 2])); } if (d > 8) bad++; if (d > mx) mx = d; }
      return JSON.stringify({ px: bw * bh, lit: lit, bad: bad, maxd: mx, n: n, note: 'a=GPU full (baseline), b=CPU field (overflow fallback); same frozen sources' });
    }, t119cluster: function () { // REAL gOv trigger: n=GMAX sources in a tight phyllotaxis disc (r<=18, reach 67) -> the central 16px leaves have m=GMAX -> clamp+overflow at n=GMAX exactly (the only gOv window: m<=n<=GMAX). Gate: candidate drawMetaballs output must be bit-identical to the direct full-pass reference (main c20cb7e behavior at this frame) and visibly different from the clamped tiled render it avoided; counters prove the fallback engaged and stayed on GPU.
      if (!gOK) return 'nogl';
      var S = curS, n = GMAX, i, ms = P.metaballStrength, TH = P.THRESHOLD;
      var bw = Math.max(1, Math.ceil(cont.w * S)), bh = Math.max(1, Math.ceil(cont.h * S)), cx = cont.w / 2, cy = cont.h / 2; // src coords are PLATE px (buffer = plate * S): placing the disc in buffer px put it off-canvas whenever S != 1 (empty-frame gate bug)
      var src = { n: n, x: new Float64Array(n), y: new Float64Array(n), r: new Float64Array(n), wr: new Float64Array(n), wg: new Float64Array(n), wb: new Float64Array(n) };
      for (i = 0; i < n; i++) { var ang = i * 2.39996, rad = 18 * Math.sqrt(i / n); src.x[i] = cx + rad * Math.cos(ang); src.y[i] = cy + rad * Math.sin(ang); src.r[i] = 22; src.wr[i] = 0.5; src.wg[i] = 0.5; src.wb[i] = 0.5; }
      window.__t119src = src;
      var sv = ctx.drawImage; ctx.drawImage = function () {};
      drawMetaballs(S); ctx.drawImage = sv; // candidate production path: tiled pass, overflow -> full-pass GPU re-render
      var ov = gOv, onAfter = gOn, stA = { subdiv: gTStat.subdiv, leaves: gTStat.leaves, sumM: gTStat.sumM, maxM: gTStat.maxM, clamps: gTStat.clamp };
      gl.finish(); var a = new Uint8Array(bw * bh * 4); gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, a);
      window.__t119src = null;
      var C = new Float32Array(n * 4), W = new Float32Array(n * 4);
      for (i = 0; i < n; i++) { C[i * 4] = src.x[i]; C[i * 4 + 1] = src.y[i]; C[i * 4 + 2] = ms * src.r[i] * src.r[i]; C[i * 4 + 3] = src.r[i] * Math.max(3, Math.sqrt(ms / (TH * 0.03))); W[i * 4] = src.wr[i]; W[i * 4 + 1] = src.wg[i]; W[i * 4 + 2] = src.wb[i]; }
      gpuDraw(C, W, n, bw, bh, S, false); gl.finish(); var b = new Uint8Array(bw * bh * 4); gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, b); // reference: full-pass GPU (= live baseline at this frame)
      gpuDraw(C, W, n, bw, bh, S, true); gl.finish(); var ovT = gOv, cl = gTStat.clamp, c = new Uint8Array(bw * bh * 4); gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, c); // defect avoided: clamped tiled render without fallback
      var d1 = 0, m1 = 0, d2 = 0, m2 = 0;
      for (i = 0; i < a.length; i++) { var dd = Math.abs(a[i] - b[i]); if (dd) { d1++; if (dd > m1) m1 = dd; } var ee = Math.abs(a[i] - c[i]); if (ee > 8) d2++; if (ee > m2) m2 = ee; }
      return JSON.stringify({ bytes: a.length, n: n, gmax: GMAX, S: S, bw: bw, bh: bh, ov: ov, gpuOn: onAfter, stA: stA, ovTiledOnly: ovT, clamps: cl, candVsFullDiff: d1, candVsFullMax: m1, candVsClampedDiff: d2, candVsClampedMax: m2 });
    }, cmpOverflowBaseline: function () { // the literal parent gate: candidate overflow-trigger frame vs live-baseline behavior at the SAME input. With overflow forced (setGmaxTest), (a) drawMetaballs = candidate (GPU attempt, gOv>0 -> CPU fallback), (b) drawMetaballsCPU direct = main c20cb7e behavior at n>GMAX. Same synchronous task => buildSources frozen between calls.
      if (!gOK) return 'nogl';
      var S = curS, sv = ctx.drawImage; ctx.drawImage = function () {};
      drawMetaballs(S); var gpuOnAfter = gOn, ov = gOv, a = new Uint8ClampedArray(img.data);
      drawMetaballsCPU(S); var b = img.data, bad = 0, mx = 0;
      ctx.drawImage = sv;
      for (var i = 0; i < a.length; i++) { var d = Math.abs(a[i] - b[i]); if (d > 8) bad++; if (d > mx) mx = d; }
      return JSON.stringify({ bytes: a.length, bad: bad, maxd: mx, ov: ov, gpuOn: gpuOnAfter, note: 'a=candidate drawMetaballs (overflow->CPU), b=baseline drawMetaballsCPU; same frozen sources' });
    }, t119synth: function (cap, count) { // deterministic subdivision gate: a fixed grid of small-reach sources so subdivision fires WITHOUT leaf clamping; full vs tiled must be bit-identical
      if (!gOK) return 'nogl';
      var oldG = GMAX; GMAX = cap | 0 || 64;
      var S = curS, ms = P.metaballStrength, TH = P.THRESHOLD, i, n = count || 300;
      var C = new Float32Array(n * 4), W = new Float32Array(n * 4), cols = Math.ceil(Math.sqrt(n));
      for (i = 0; i < n; i++) { var gx = 20 + (i % cols) * 43, gy = 20 + Math.floor(i / cols) * 43, r = 22; C[i * 4] = gx; C[i * 4 + 1] = gy; C[i * 4 + 2] = ms * r * r; C[i * 4 + 3] = 67; W[i * 4] = 0.4; W[i * 4 + 1] = 0.4; W[i * 4 + 2] = 0.4; } // fixed reach 67: tile m~82 > cap, 16px-leaf m~12 < cap -> subdivision without clamp
      var bw = Math.max(1, Math.ceil(cont.w * S)), bh = Math.max(1, Math.ceil(cont.h * S));
      if (glc.width !== bw || glc.height !== bh) { glc.width = bw; glc.height = bh; }
      gpuDraw(C, W, n, bw, bh, S, false); gl.finish(); var a = new Uint8Array(bw * bh * 4); gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, a);
      gpuDraw(C, W, n, bw, bh, S, true); gl.finish(); var st = { subdiv: gTStat.subdiv, leaves: gTStat.leaves, maxM: gTStat.maxM, clamps: gTStat.clamp, ov: gOv }; var b = new Uint8Array(bw * bh * 4); gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, b);
      GMAX = oldG;
      var d = 0, mx = 0;
      for (i = 0; i < a.length; i++) { var dd = Math.abs(a[i] - b[i]); if (dd) { d++; if (dd > mx) mx = dd; } }
      return JSON.stringify({ bytes: a.length, diffBytes: d, maxDiff: mx, n: n, cap: cap, subdiv: st.subdiv, leaves: st.leaves, maxM: st.maxM, clamps: st.clamps, ov: st.ov, bw: bw, bh: bh });
    }, setTiled: function (v) { gTiledForce = (v === null || v === undefined) ? null : !!v; }, cmpGpuPaths: function () { // same source array through the full pass and the tiled pass: exact old-vs-new GPU A/B (pixel gates for the thermal fix)
      if (!gOK) return 'nogl';
      if (!window.__t118pack) { // one freeze shared by both modes: full and tiled render the SAME source array/geometry
        var S0 = curS, src = buildSources(), ms0 = P.metaballStrength, TH0 = P.THRESHOLD, n0 = Math.min(src.n, gShaderMax || GMAX), j;
        var C0 = new Float32Array(n0 * 4), W0 = new Float32Array(n0 * 4);
        for (j = 0; j < n0; j++) { C0[j * 4] = src.x[j]; C0[j * 4 + 1] = src.y[j]; C0[j * 4 + 2] = ms0 * src.r[j] * src.r[j]; C0[j * 4 + 3] = src.r[j] * Math.max(3, Math.sqrt(ms0 / (TH0 * 0.03))); W0[j * 4] = src.wr[j]; W0[j * 4 + 1] = src.wg[j]; W0[j * 4 + 2] = src.wb[j]; }
        window.__t118pack = { C: C0, W: W0, n: n0, S: S0, bw: Math.max(1, Math.ceil(cont.w * S0)), bh: Math.max(1, Math.ceil(cont.h * S0)) };
      }
      var pk = window.__t118pack, S = pk.S, n = pk.n, C = pk.C, W = pk.W, i;
      var bw = pk.bw, bh = pk.bh;
      if (glc.width !== bw || glc.height !== bh) { glc.width = bw; glc.height = bh; }
      gpuDraw(C, W, n, bw, bh, S, false); gl.finish(); var a = new Uint8Array(bw * bh * 4); gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, a);
      var t0 = performance.now(); gpuDraw(C, W, n, bw, bh, S, true); gl.finish(); var tT = performance.now() - t0; var b = new Uint8Array(bw * bh * 4); gl.readPixels(0, 0, bw, bh, gl.RGBA, gl.UNSIGNED_BYTE, b);
      var st = { subdiv: gTStat.subdiv, leaves: gTStat.leaves, sumM: gTStat.sumM, maxM: gTStat.maxM, clamps: gTStat.clamp, ov: gOv }; // snapshot NOW: the timing pass below resets the counters
      t0 = performance.now(); gpuDraw(C, W, n, bw, bh, S, false); gl.finish(); var tF = performance.now() - t0; // gl.readPixels: the drawImage readback is NOT deterministic on swiftshader (same-program same-input selfDiff ~1%)

      var d = 0, mx = 0, ex = -1, ey = -1, chD = [0, 0, 0, 0], grid = {}, samples = [];
      for (i = 0; i < a.length; i++) { var dd = Math.abs(a[i] - b[i]); if (dd) { d++; chD[i & 3]++; var px2 = (i >> 2) % bw, py2 = Math.floor((i >> 2) / bw), gk = Math.floor(px2 / 256) + ',' + Math.floor(py2 / 256); grid[gk] = (grid[gk] || 0) + 1; if ((i & 3) === 0 && samples.length < 12) samples.push([px2, py2, a[i], b[i], a[i + 1], b[i + 1], a[i + 2], b[i + 2], a[i + 3], b[i + 3]]); if (dd > mx) { mx = dd; ex = px2; ey = py2; } } }
      return JSON.stringify({ bytes: a.length, diffBytes: d, maxDiff: mx, worstX: ex, worstY: ey, ch: chD, grid: grid, samples: samples, n: n, gmax: GMAX, bw: bw, bh: bh, tTiledMs: +tT.toFixed(1), tFullMs: +tF.toFixed(1), overflow: st.ov, subdiv: st.subdiv, leaves: st.leaves, sumM: st.sumM, maxM: st.maxM, clamps: st.clamps });
    }, get axisInfo() { return axisInfo; }, sepInk: sepInk, sepSources: function(){ return {src:buildSources(),mask:SEP.img,mw:SEP.mw,mh:SEP.mh,t:frameT,builtT:SEP.builtT,collectMs:SEP.collectMs,radiusLoss:SEP.radiusLoss}; }, sepDiskHit: sepDiskHit, sepBodyLineHit: function(c,sg) { return sepBodyLineHit(sepBody(c),c.x,c.y,sg); }, sepBodyHit: function(c) { return sepBodyHit(sepBody(c), c.x, c.y); }, sepCollectStep: separatorCollectivePass, sepStep: separatorPass,  get sepMask() { return { on: !!SEP.img, mw: SEP.mw, mh: SEP.mh }; }, get sepMaskT() { return SEP.builtT || 0; }, cmpWC: function () { if (!WC.ok) return 'nowasm:' + WC.err; var S = curS, sv = ctx.drawImage; ctx.drawImage = function () {}; var o = WC.off; var fdef = WC.field; WC.field = WC.fieldX; WC.off = false; var t0 = performance.now(); drawMetaballsCPU(S); var tw = performance.now() - t0; var a = new Uint8ClampedArray(img.data); WC.off = true; t0 = performance.now(); drawMetaballsCPU(S); var tj = performance.now() - t0; var b = new Uint8ClampedArray(img.data); WC.off = o; var fsv = fdef; WC.field = WC.fieldF; WC.off = false; t0 = performance.now(); drawMetaballsCPU(S); var tf = performance.now() - t0; var c32 = new Uint8ClampedArray(img.data); WC.field = fsv; WC.off = o; var d32 = 0, m32 = 0, ge2 = 0; for (var i = 0; i < b.length; i++) { var dd = Math.abs(c32[i] - b[i]); if (dd) { d32++; if (dd > m32) m32 = dd; if (dd > 2) ge2++; } } ctx.drawImage = sv; var bad = 0, mx = 0; for (var i = 0; i < a.length; i++) { var d = Math.abs(a[i] - b[i]); if (d) { bad++; if (d > mx) mx = d; } } return JSON.stringify({ bytes: a.length, diffBytes: bad, maxDiff: mx, tWasm: +tw.toFixed(1), tJS: +tj.toFixed(1), tF32: +tf.toFixed(1), f32diff: d32, f32max: m32, f32gt2: ge2, cells: cells.length }); }, WC: WC, PF: PF, pairs: pairN / 2, fusions: ev.fuse || 0, pairings: ev.pair || 0, composites: compN, cmp: function () { if (!gOK) return 'nogl'; var S = curS, sv = ctx.drawImage; var saved = ctx.drawImage; ctx.drawImage = function () {}; var t0 = performance.now(); drawMetaballs(S); var tg = performance.now() - t0; t0 = performance.now(); drawMetaballsCPU(S); var tc = performance.now() - t0; ctx.drawImage = saved; var tmp = document.createElement('canvas'); tmp.width = glc.width; tmp.height = glc.height; var tx = tmp.getContext('2d'); tx.drawImage(glc, 0, 0); var gd = tx.getImageData(0, 0, tmp.width, tmp.height).data, cd = img.data, n = tmp.width * tmp.height, bad = 0, mx = 0, sum = 0, lit = 0; for (var p = 0; p < n; p++) { var q = p * 4, ga = gd[q + 3], ca = cd[q + 3]; var d = Math.abs(ga - ca); if (ca > 0 || ga > 0) { lit++; if (ca > 250 && ga > 250) d = Math.max(d, Math.abs(gd[q] - cd[q]), Math.abs(gd[q + 1] - cd[q + 1]), Math.abs(gd[q + 2] - cd[q + 2])); } if (d > 8) bad++; if (d > mx) mx = d; sum += d; } return JSON.stringify({ px: n, lit: lit, bad: bad, maxd: mx, tGPUms: +tg.toFixed(1), tCPUms: +tc.toFixed(1), cells: gSnap && gSnap.n }); }, gpuState: function () { return { ok: gOK, on: gOn, n: gSnap && gSnap.n }; }, setGPU: function (v) { gOK = !!v && !!gl; }, colorAt: colorAt, seedKey: function (k, v) { P[k] = v; applyKey(k, v); }, /* seedKey = setKey without the touched pin: device-profile defaults (mobile seed) must not read as user edits */ setKey: function (k, v) { P[k] = v; applyKey(k, v); if (k === 'lineColor' || k === 'ruleColor' || k === 'circColor') applyLineColor(); touched[k] = 1; save(); }, cont: cont, liveTest: function (k, gens) { var q = keyToQ[k]; liveStart(k, q, P[k], { classList: { add: function () {}, remove: function () {} }, style: { setProperty: function () {}, removeProperty: function () {} } }); var lastF, lastF2, run = 0, maxRun = 0, sumAbs = 0, bins = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], t = performance.now(), mn = 1e9, mx = -1e9, saveP = P[k]; for (var g = 0; g < gens; g++) { t += LIVE_MS; stepLive(t); var f = (P[k] - q[2]) / (q[3] - q[2]); bins[Math.min(19, Math.floor(clamp(f, 0, 0.9999) * 20))]++; if (Math.abs(f - (lastF === undefined ? -9 : lastF)) < 0.01) { run++; maxRun = Math.max(maxRun, run); } else run = 0; lastF = f; sumAbs += lastF2 === undefined ? 0 : Math.abs(f - lastF2); lastF2 = f; mn = Math.min(mn, P[k]); mx = Math.max(mx, P[k]); } var cov = bins.filter(function (x) { return x > 0; }).length / 20; delete live[k]; P[k] = saveP; applyKey(k, saveP); return { key: k, min: q[2], max: q[3], seenMin: mn, seenMax: mx, coverage20: cov, bins: bins, maxRunGens: maxRun, meanStep: sumAbs / gens }; }, introStat: introStat, sim: function () { return { UI_END: UI_END, CELL_END: CELL_END, FOOD_END: FOOD_END }; }, fadeK: fadeK, INTRO: INTRO_MS, drag: function () { return resizeDrag; }, clampTargets: clampTargets, blobs: blobs, blobStat: blobStat, swStat: swStat, worms: worms, wormStat: wormStat, spores: spores, sporeStat: sporeStat, srcStat: function () { return { n: SRC.n, cells: SRC.cells }; }, shapeStat: function () { var t0 = frameT || performance.now(), asps = [], strings = 0, lobed = 0, rounds = 0, srcs = 0, i, a2, b2; for (i = 0; i < cells.length; i++) { var c = cells[i]; if (!c.alive) continue; var o = { x: [], y: [], r: [], n: 0 }; emitCell(c, t0, 99, o); srcs += o.n; var sh = c.shp || { t: 0 }; if (sh.t === 1) strings++; else if (sh.t === 2) lobed++; else rounds++; var mn = 1e9, mx = 0; for (a2 = 0; a2 < o.n; a2++) { mn = Math.min(mn, o.r[a2]); for (b2 = a2; b2 < o.n; b2++) mx = Math.max(mx, Math.hypot(o.x[a2] - o.x[b2], o.y[a2] - o.y[b2]) + o.r[a2] + o.r[b2]); } asps.push(mx / (2 * mn)); } asps.sort(function (x, y) { return x - y; }); var mean = 0; for (i = 0; i < asps.length; i++) mean += asps[i]; mean = asps.length ? mean / asps.length : 1; var sd = 0; for (i = 0; i < asps.length; i++) sd += (asps[i] - mean) * (asps[i] - mean); sd = asps.length ? Math.sqrt(sd / asps.length) : 0; var hist = [0, 0, 0, 0, 0, 0, 0], cuts = [1.05, 1.5, 2, 3, 4.5, 7, 12]; for (i = 0; i < asps.length; i++) { var bi = 0; while (bi < 6 && asps[i] >= cuts[bi]) bi++; hist[bi]++; } return { cells: asps.length, rounds: rounds, strings: strings, lobed: lobed, geneticSources: srcs, aspectMean: +mean.toFixed(3), aspectSd: +sd.toFixed(3), aspectMin: asps.length ? +asps[0].toFixed(2) : 1, aspectMed: asps.length ? +asps[Math.floor(asps.length / 2)].toFixed(2) : 1, aspectMax: asps.length ? +asps[asps.length - 1].toFixed(2) : 1, hist: hist }; }, live: live, P: P, getCells: function () { return cells; }, get sprayWaves() { return sprayWaveN; }, getFood: function () { return food; }, parStat: parStat, foodStat: foodStat, cont: cont, vTop: vTop, vBot: vBot, gap: G, margin: M, midBase: midBase, lead: L.lead, topInkBottom: M + dh, botInkTop: H - M - dh, hL: axisInfo.hL || 0, oob: ev.oob, maxOut: maxOut, stepN: function (n, dtms) { var vir0 = window.__ca2ClockVir || 0, real0 = performance.now(); for (var k = 0; k < n; k++) { window.__ca2ClockVir = vir0 + k * dtms - (performance.now() - real0); lastFrameT = performance.now() + window.__ca2ClockVir - dtms; frame(); } window.__ca2ClockVir = vir0 + n * dtms - (performance.now() - real0); }, // explicit normal-step advance: full sim step, virtual clock +dtms per step (divide age, morph, parasites, lifespan see simulated time); sim-stepped, not real rAF timing (main 25 Oct) // bounded explicit normal-step advance, same frame() path with fixed dtf; sim-stepped, not real rAF timing (main 25 Oct)
      get frameT() { return frameT; }, get deathsLive() { return ev.death; }, get transLive() { return !!trans; }, keepIn: keepIn, get simOn() { return SIMW.on; }, // measurement-harness probe hooks (main 25 Oct) // live accessors for measurement harnesses: object-literal value fields freeze between full-frame rebuilds (main 25 Oct)
      births: ev.birth, deaths: ev.death, get deathLog() { return deathLog; }, killReasons: function () { return { select: ev.killSel || 0, energy0: ev.killEnergy || 0, crowd: ev.killCrowd || 0, genebound: ev.killGene || 0 }; }, trans: !!trans, get circles() { return circlesNow; }, get transTg() { return trans && trans.tg; }, get touchedKeys() { return Object.keys(touched); }, parasites: parasites.length, clusters: clusterCount, merges: ev.merge || 0, eaten: ev.eaten || 0, divides: ev.divide || 0, pbirth: ev.pbirth || 0, pdeath: ev.pdeath || 0, env: env, getParasites: function () { return parasites; }, cur: curInfo, W: W, H: H, res: res, cells: cells.length, areaTop: cont.y, areaBottom: cont.y + cont.h, areaLeft: cont.x, areaRight: cont.x + cont.w, safeW: L.safeW, safeH: L.safeH };
    __ca2.habStat = habStat;
    __ca2.habitat = function () { var fedN = 0, fedMax = 0, hueN = 0; for (var i = 0; i < food.length; i++) { var fd = food[i].fed || 0; if (fd >= P.habitatFedMin) fedN++; if (fd > fedMax) fedMax = fd; if (food[i].hr !== undefined) hueN++; } return { on: P.habitatOn, pulse: habStat.pulse, seed: habStat.seed, ateHue: habStat.ate, dominant: ateHueV, fedEligible: fedN, fedMax: +fedMax.toFixed(2), hueDots: hueN, cells: cells.length, food: food.length }; };

    if (autoRefresh && performance.now() - lastRefresh > refreshInterval * 1000) {
      // never re-deal the universe mid-configuration: while the config area is in use (panel open, lane/panel hovered,
      // plate dragged) the timer just postpones, so the plate and its lines stay put under the user's hands (owner 20 Oct)
      if (panel.classList.contains('open') || panel.classList.contains('hov') || resizeDrag) lastRefresh = performance.now();
      else randomize();
    }
    stepLive(t0);
    syncUI(rc + gc + bc);
    var lum = (0.299 * bg[0] + 0.587 * bg[1] + 0.114 * bg[2]), fgc = lum > 128 ? '17,17,17' : '240,240,240', root = document.documentElement.style;
    root.setProperty('--fg', 'rgb(' + fgc + ')'); root.setProperty('--fg-soft', 'rgba(' + fgc + ',.35)'); root.setProperty('--bg', css(bg, 1)); root.setProperty('--panel-bg', css(bg, P.panelAlpha));
    // sound: the automaton's state drives the noise
    if (window.CA2Audio) {
      var spd = 0, mx = 0, nn = cells.length || 1; for (i = 0; i < cells.length; i++) { spd += Math.hypot(cells[i].vx, cells[i].vy); mx += cells[i].x; }
      CA2Audio.update({ density: clamp(cells.length / Math.max(20, P.UNIVERSE_SIZE * 1.5), 0, 1), activity: clamp(spd / nn / 15, 0, 1), pan: ((mx / nn) - W / 2) / (W / 2), birth: ev.birth - aev.b, death: ev.death - aev.d, hit: ev.hit - aev.h }, P);
      aev.b = ev.birth; aev.d = ev.death; aev.h = ev.hit;
    }
    applyDof(); // depth of field lives in the scene canvas now, so the grain pass lands on top of it (owner 21 Oct)
    if (window.CA2Grain && CA2Grain.ok && P.grain) { // owner 22 Oct: grain is in from the first frame - the intro+400ms hold went
      cvg.style.display = 'block';
      var GR_STOCKS = [[0.95, 0.92, 1.05], [1.00, 0.88, 1.10], [0.90, 0.90, 0.95], [1.05, 0.85, 1.15], [1.10, 0.80, 1.20], [1.00, 0.95, 1.00]]; // HP5, Portra, Ektar, Vision3, Kodachrome, Tri-X (photon)
      CA2Grain.render(cv, { amount: P.grainAmount, strength: P.grainStrength, size: P.grainSize, softness: P.grainSoft * (P.grainMono ? 0.5 : 1), chroma: P.grainChroma, development: P.grainDev, fine: P.grainFine, crystal: P.grainCrystal, cloud: P.grainCloud, mono: P.grainMono, skew: P.grainSkew, resAdapt: P.grainResAdapt, shadow: P.grainShadow, mid: P.grainMid, high: P.grainHigh, fineRatio: P.grainFineRatio, cloudRatio: P.grainCloudRatio, debug: P.grainDebug, stock: GR_STOCKS[clamp(Math.round(P.grainStock), 0, 5)] }, P.grainFps > 0 ? Math.floor(performance.now() / 1000 * P.grainFps) : 0, DPR, 1); // overlay pass: #g is a transparent layer above all UI (owner 21 Oct)
    } else cvg.style.display = 'none';
    pfm('grain+rest');
    // quality governor: keeps the frame rate by lowering resolution, raises it back when there is room
    var execMs0 = performance.now() - t0;
    if (t0 - fadeT0 <= INTRO_MS + 1000) { introStat.frames++; if (execMs0 > 1000 / P.fps * 1.5) introStat.jank++; if (execMs0 > introStat.worst) introStat.worst = Math.round(execMs0); }
    frameMs = lerp(frameMs, execMs0, 0.1);
    if (P.autoQuality) {
      var budget = 1000 / P.fps;
      if (frameMs > budget * 0.9) res = Math.max(0.35, res * 0.94); else if (frameMs < budget * 0.45) res = Math.min(P.resolution, res * 1.03);
      res = Math.min(res, P.resolution);
    } else res = P.resolution;
  }

  // ---- living knobs: double-click a knob and its parameter enters a 1-D cellular-automaton life cycle between its floor and ceiling
  // (rule 110 on a ring; value = linear function of the alive fraction). Double-click again returns to the value from before. The stored config always holds the pre-CA value.
  var live = {}, hovCA = {};
  function hash(s) { var h = 2166136261; for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }
  function lcg(st) { st.s = (Math.imul(st.s, 1664525) + 1013904223) >>> 0; return st.s / 4294967296; }
  var LIVE_N = 28, LIVE_RULE = 110, LIVE_MS = 110, LIVE_COLS = ['#ff0000', '#00ff00', '#0000ff'];
  var LIVE_CAP = { audioVol: 0.35 }; // keep live volume gentle
  // plate occupancy ring: the plate is cut into n vertical sectors; a sector is 'alive' when it holds at least the average number of cells
  function plateOcc(n) {
    var cnt = new Array(n).fill(0), i, tot = 0;
    for (i = 0; i < cells.length; i++) { var c = cells[i], s = clamp(Math.floor((c.x - cont.x) / Math.max(1, cont.w) * n), 0, n - 1); cnt[s]++; tot++; }
    var mean = tot / n, out = new Array(n); for (i = 0; i < n; i++) out[i] = cnt[i] > mean ? 1 : 0; return out;
  }
  // smart auto knobs: each parameter gets its own motion profile derived from its GROUPS meta
  // (range and quantum) instead of one hardcoded chase. A knob with hundreds of steps drifts
  // slowly through them, a knob with three steps snaps. The chase is a velocity model, so the
  // value accelerates when the target moves away and slows down as it arrives.
  function liveProfile(q, plate) {
    var range = q[3] - q[2], n = Math.max(1, Math.round(range / q[4]));
    var speed = clamp(1.8 / Math.sqrt(n + 2), 0.025, 0.45);              // top speed, fraction of range per tick
    var accel = clamp(0.05 + 0.5 / (1 + n / 12), 0.06, 0.5);            // velocity gain toward the target
    var damp = clamp(0.9 - 0.12 * Math.min(1, Math.log(n + 1) / Math.log(1000)), 0.74, 0.9);
    if (plate) { speed *= 0.2; accel *= 0.35; }                         // audio knobs keep their gentler motion
    return { vmax: range * speed, accel: accel, damp: damp };
  }
  function liveStart(k, q, orig, row) {
    var st = { s: hash(k) || 1 }, bits = [];
    for (var i = 0; i < LIVE_N; i++) bits.push(lcg(st) < 0.5 ? 1 : 0);
    var plate = /^audio/.test(k);
    live[k] = { orig: orig, bits: bits, st: st, t: performance.now(), cur: orig, vel: 0, q: q, row: row, col: LIVE_COLS[Math.floor(Math.random() * 3)], gen: 0, lastQ: orig, plate: plate, prof: liveProfile(q, plate), shift: hash(k) % LIVE_N, rule: plate ? [110, 30, 90, 54][hash(k) % 4] : LIVE_RULE };
    row.classList.add('live'); row.style.setProperty('--kc', live[k].col);
  }
  function liveStop(k) {
    var L = live[k]; if (!L) return; L.row.classList.remove('live'); L.row.style.removeProperty('--kc');
    delete live[k]; P[k] = L.orig; if (typeof touched === 'object') touched[k] = 1; applyKey(k, L.orig); save();
  }
  function stepLive(now) {
    for (var k in live) {
      var L = live[k], n = L.bits.length;
      if(L.row.classList.contains('range-editing'))continue;
      if (now - L.t >= LIVE_MS) {
        L.t = now; L.gen++;
        var nb = new Array(n), sum = 0, same = true, i;
        for (i = 0; i < n; i++) { nb[i] = (L.rule >> (L.bits[(i + n - 1) % n] * 4 + L.bits[i] * 2 + L.bits[(i + 1) % n])) & 1; sum += nb[i]; if (nb[i] !== L.bits[i]) same = false; }
        if (L.plate) { var occ = plateOcc(n); sum = 0; for (i = 0; i < n; i++) { nb[i] ^= occ[(i + L.shift) % n]; sum += nb[i]; } same = false; }
        if (sum === 0 || sum === n || same) { for (i = 0; i < 3; i++) nb[Math.floor(lcg(L.st) * n)] ^= 1; if (sum === 0) nb[Math.floor(lcg(L.st) * n)] = 1; } // keep it alive, deterministically
        L.bits = nb;
        var a = clamp((nb.reduce(function (x, y) { return x + y; }, 0) / n - 0.2) / 0.6, 0, 1);
        if (L.plate) a = clamp(a * 0.45 + 0.55 * clamp(cells.length / 250, 0, 1), 0, 1);
        // the value follows the CA: a window of the row is read as a binary fraction (so the whole range is reachable and
        // every part is equally likely), one random cell is flipped every generation so the row never settles into a cycle,
        // and the value chases that reading with a soft step - never stuck, never a ceiling-floor sweep
        nb[Math.floor(lcg(L.st) * n)] ^= 1; L.bits = nb;
        var r0 = (L.gen * 7 + L.shift) % n, rd = 0, wt = 0.5;
        for (i = 0; i < 12; i++) { rd += nb[(r0 + i) % n] * wt; wt *= 0.5; }
        rd = clamp(rd * 4096 / 4095, 0, 1);
        // the reading is mapped through its own running distribution (rank), so the whole range is used evenly
        if (!L.hist) L.hist = [];
        var lo = 0; for (i = 0; i < L.hist.length; i++) if (L.hist[i] < rd) lo++;
        var rk = L.hist.length > 8 ? (lo + lcg(L.st)) / (L.hist.length + 1) : rd;
        L.hist.push(rd); if (L.hist.length > 300) L.hist.shift();
        if (L.walk === undefined) L.walk = rk;
        L.walk += (rk - L.walk) * 0.7;
        a = clamp(0.5 + (L.walk - 0.5) * 1.3, 0, 1); // a little stretch so both ends are actually touched
        L.target = L.q[2] + (L.q[3] - L.q[2]) * a * (LIVE_CAP[k] || 1);
      }
      if (L.target === undefined) continue;
      var pr = L.prof, dT = L.target - L.cur;
      L.vel = clamp((L.vel + dT * pr.accel) * pr.damp, -pr.vmax, pr.vmax);
      L.cur += L.vel;
      var v = clamp(Math.round((L.cur - L.q[2]) / L.q[4]) * L.q[4] + L.q[2], L.q[2], L.q[3]);
      if (v !== L.lastQ) { L.lastQ = v; P[k] = v; applyKey(k, v); }
    }
  }
  // ---- persistence: every config key, versioned; unknown/removed keys are ignored, new keys keep defaults ----
  // three profiles, separate local records (owner 23 Oct): desktop 'ca2.config', mobile 'ca2.config.m' (portrait + the landscape mirror
  // live in ca2.mprof). A preview/phone save can no longer overwrite the desktop record in the same browser. Non-destructive
  // migration: 'ca2.config' is never cleared or copied (it may hold values from before the split); the mobile record starts empty and the mobile layer comes from the global _mobile + ca2.mprof.
  var STORE_D = 'ca2.config', STORE_M = 'ca2.config.m';
  function storeMode0() { return (/[?&]mobile=1/.test(location.search) || !!(window.matchMedia && matchMedia('(hover: none) and (pointer: coarse)').matches) || window.innerWidth <= 820) ? 'm' : 'd'; }
  var STORE = (storeMode0() === 'm') ? STORE_M : STORE_D, STORE_V = 6, savedLive = {}, rangeBounds = {};
    // the admin module (served by the Worker) parks unaccepted saves in 'ca2.pending'; tag them with the mode that wrote them
  try { var _si = Storage.prototype.setItem; Storage.prototype.setItem = function (k, v) { if (k === 'ca2.pending') { try { _si.call(this, 'ca2.pending.mode', curStoreMode()); } catch (e) {} } return _si.apply(this, arguments); }; } catch (e) {}
  function curStoreMode() { return (window.__ca2Mode ? window.__ca2Mode() : storeMode0()); }
  function pendingOk() { var pm = null; try { pm = localStorage.getItem('ca2.pending.mode'); } catch (e) {} return pm === curStoreMode(); } // untagged legacy records are quarantined: bytes stay in localStorage, never replayed into an unproven mode
  (function load() {
    try {
      var sv = JSON.parse(localStorage.getItem(STORE) || 'null');
      if (!sv || typeof sv !== 'object') return;
      if (sv.live && typeof sv.live === 'object') savedLive = sv.live;
      if (sv.bounds && typeof sv.bounds === 'object') rangeBounds = sv.bounds;
      var p = sv.P || {};
      Object.keys(p).forEach(function (k) { if (k in P && typeof p[k] === 'number' && isFinite(p[k])) P[k] = p[k]; });
      if (typeof p.foodColor === 'string' && /^#[0-9a-f]{6}$/i.test(p.foodColor)) P.foodColor = p.foodColor;
      if (typeof p.lineColor === 'string' && /^#[0-9a-f]{6}$/i.test(p.lineColor)) P.lineColor = p.lineColor;
      ['axisColor', 'circColor', 'ruleColor'].forEach(function (k) { if (typeof p[k] === 'string' && /^#[0-9a-f]{6}$/i.test(p[k])) P[k] = p[k]; });
      if (typeof sv.autoRefresh === 'boolean') autoRefresh = sv.autoRefresh;
      // stale visitor saves carry lockParams:false from the old default; restoring it would keep the 2-9s re-roll alive. Unlock is now a per-session admin action, so only an explicit locked:true is honored.
      if (sv.lockParams === true) lockParams = true;
      if (sv.bgTarget && sv.bgTarget.length === 3) { bgTarget = sv.bgTarget.slice(); bg = sv.bgTarget.slice(); }
      if (typeof sv.bgIndex === 'number') bgIndex = sv.bgIndex;
    } catch (e) {}
  })();
  // old configs stored foodEatR as a factor of the cell radius; the fixed px radius migrates them once
  if (P.foodEatR <= 1) P.foodEatR = Math.round(P.foodEatR * DEFAULTS.CELL_RADIUS * 100) / 100;
  function liveMap() { var m = {}; for (var lk in live) m[lk] = live[lk].orig; return m; }
  function save() { try { var Pc = Object.assign({}, P); for (var lk in live) Pc[lk] = live[lk].orig; localStorage.setItem(STORE, JSON.stringify({ v: STORE_V, P: Pc, live: liveMap(), bounds: rangeBounds, autoRefresh: autoRefresh, lockParams: lockParams, bgTarget: bgTarget, bgIndex: bgIndex })); } catch (e) {} }
  // ---- config panel: every parameter ----
  var rows = {}, statsEl = document.getElementById('stats'), ctl = document.getElementById('controls'), btns = document.getElementById('btns');
  var GROUPS = [
    ['picture', [
      ['resolution', 'resolution', 0.25, 1, 0.01], ['pixelRatio', 'pixel ratio', 0, 3, 0.25], ['fps', 'fps', 5, 120, 1],
      ['margin', 'margin', 0, 120, 1], ['gap', 'line gap', 0, 60, 1],
      ['textScale', 'type size', 0.5, TYPE_SIZE_MAX, 0.005], ['titleLead', 'line space', 0.5, 3, 0.05], ['titleTrack', 'letter space', 0.5, 2, 0.01], ['containerCorner', 'corner gap', 0, 80, 1],
      ['centerGap', 'center gap', 0, 120, 1], ['diagLen', 'diagonals', 0.2, 1.3, 0.01], ['axisWidth', 'line width', 0, 6, 0.1],
      ['areaMin', 'area floor', 0.1, 1, 0.01], ['areaMax', 'area ceiling', 0.1, 1, 0.01],
      ['morphEase', 'morph speed', 0.02, 1, 0.01], ['colorSpeed', 'color speed', 0.02, 1, 0.01]]],
    ['panel', [
      ['panelAlpha', 'panel opacity', 0, 1, 0.01], ['cfgFontSize', 'font size', 8, 28, 1], ['panelWidth', 'panel width', 200, 600, 5], ['blurWidth', 'blur width', 0, 600, 5], ['blurStrength', 'blur strength', 0, 64, 1],
      ['panelRowGap', 'row gap', 0, 30, 1], ['focusIdleMs', 'focus wait', 500, 20000, 100], ['focusInMs', 'blur in', 500, 12000, 100], ['focusOutMs', 'refocus snap', 60, 3000, 10], ['focusDepth', 'blur depth', 0, 64, 1]]],
    ['cursor', [
      ['cursorSens', 'sensitivity', 0.05, 1, 0.01], ['cursorSize', 'size', 0.2, 2, 0.01], ['cursorLockMs', 'lock ms', 0, 3000, 50], ['sprayMs', 'interval', 40, 1000, 10], ['sprayGapPx', 'spacing', 4, 200, 1], ['sprayBurst', 'burst', 1, 20, 1], ['sprayRadius', 'spread', 0, 300, 5]]],
    ['grain', [
      ['grainAmount', 'amount', 0, 2, 0.01], ['grainStrength', 'strength', 0, 10, 0.1], ['grainSize', 'size', 0.3, 6, 0.1],
      ['grainSoft', 'softness', 0, 1, 0.01], ['grainChroma', 'chroma', 0, 1, 0.01], ['grainDev', 'development', 0.1, 1.5, 0.01],
      ['grainFine', 'fine', 0, 1, 0.01], ['grainCrystal', 'crystal', 0, 1, 0.01], ['grainCloud', 'cloud', 0, 1, 0.01],
      ['grainStock', 'stock', 0, 5, 1], ['grainMono', 'mono', 0, 1, 1], ['grainSkew', 'skew', 0, 1, 0.01],
      ['grainResAdapt', 'adapt', 0, 1, 1], ['grainShadow', 'shadow', 0, 4, 0.05],
      ['grainMid', 'midtone', 0, 4, 0.05], ['grainHigh', 'highlight', 0, 4, 0.05],
      ['grainFineRatio', 'fine ratio', 0.1, 2, 0.05], ['grainCloudRatio', 'cloud ratio', 1, 5, 0.05],
      ['grainDebug', 'debug', 0, 1, 1],
      ['grainFps', 'fps', 0, 60, 1]]],
    ['cells', [
      ['UNIVERSE_SIZE', 'universe', 1, 400, 1], ['CELL_RADIUS', 'radius', 2, 100, 1], ['minRadius', 'min radius', 1, 50, 1], ['maxRadius', 'max radius', 5, 150, 1],
      ['baseMaxSpeed', 'speed', 0.5, 25, 0.5], ['maxSpeedVariation', 'variation', 0, 30, 0.5],
      ['interactionRadius', 'interaction', 5, 100, 1], ['baseMutationRate', 'mutation', 0.5, 20, 0.5], ['mutationRateRange', 'range', 0.5, 8, 0.5],
      ['energyConsumptionRate', 'energy use', 0, 0.5, 0.002], ['energyGainFromInteraction', 'energy gain', 0, 0.05, 0.001], ['minEnergyForReproduction', 'repro energy', 0.05, 10, 0.05], ['reproMinAgeMs', 'repro age', 0, 30000, 250], ['reproChance', 'chance', 0, 1, 0.005],
      ['slowDownRadius', 'mouse slow', 0, 100, 1], ['speedReductionFactor', 'slow factor', 1, 100, 0.5]]],
    ['evolution', [
      ['genomeMut', 'genome mutation', 0, 0.5, 0.01], ['divideAt', 'divide at', 1.2, 6, 0.1], ['divideMode', 'divide gate', 0, 1, 1], ['divideAgeMs', 'divide age', 1000, 120000, 1000], ['divideEnergy', 'divide energy', 5, 500, 5], ['eatRatio', 'eat ratio', 1.05, 3, 0.05], ['eatChance', 'eat chance', 0, 1, 0.01],
      ['mergeChance', 'merge chance', 0, 0.3, 0.005], ['mergeGene', 'gene distance', 0, 36, 1], ['clusterCohesion', 'cohesion', 0, 1, 0.01], ['clusterMax', 'cluster max', 2, 30, 1],
      ['parasiteFrac', 'parasite share', 0, 0.5, 0.01], ['parasiteDrain', 'parasite drain', 0, 0.2, 0.005], ['parasiteEff', 'efficiency', 0, 1, 0.01], ['selStrength', 'selection', 0, 4, 0.05]]],
    ['habitat', [
      ['habitatFedMin', 'fed threshold', 0, 200, 1], ['habitatConv', 'seed rate', 0, 50, 0.1], ['habitatSeedR', 'seed size', 0.05, 2, 0.05], ['habitatMut', 'seed mutation', 0, 1, 0.01],
      ['habitatSun', 'sunlight', 0, 20, 0.1], ['habitatDeadFed', 'corpse nutrient', 0, 50, 0.5], ['habitatDeadR', 'corpse radius', 0, 1, 0.01], ['habitatDeadCol', 'corpse colour', 0, 1, 0.01],
      ['habitatHueK', 'colour memory', 0, 1, 0.01], ['habitatFloor', 'seed floor', 0, 20, 1],
      ['habitatFedDecay', 'fed decay', 0, 10, 0.05], ['habitatBirthCap', 'birth cap', 0, 10, 0.1],
      ['habitatNiches', 'niche grid', 0, 8, 1], ['habitatNicheSun', 'niche sun', 0, 1, 0.05], ['habitatNicheMix', 'niche smoothing', 0, 1, 0.05],
      ['habitatDrift', 'env drift', 0, 1, 0.005], ['habitatDriftAmp', 'drift amplitude', 0, 1, 0.05], ['habitatDriftFloor', 'drift floor', 0, 1, 0.05],
      ['habitatReapOn', 'recycling', 0, 1, 1], ['habitatReapK', 'recycle intensity', 0, 1, 0.05], ['habitatFedShow', 'fed size', 0, 1, 0.02],
      ['cellLife', 'lifespan', 0, 900, 5], ['cellLifeVar', 'spread', 0, 1, 0.05]]],
    ['biology', [
      ['crowdTol', 'crowding', 0, 5, 0.05], ['orgLifeDie', 'death pull', -0.1, 0, 0.001], ['orgLifeGrow', 'life push', 0, 2, 0.0025], ['orgBirth', 'birth push', 0, 2, 0.005],
      ['orgDead', 'dead decay', -0.1, 0, 0.0005], ['orgBrain', 'brain push', 0, 0.1, 0.001], ['orgR90', 'flanked push', 0, 0.05, 0.0005],
      ['symEnergy', 'symbiosis feed', 0, 0.01, 0.00025], ['symBreak', 'whim break', 0, 0.01, 0.0001], ['symBreakDist', 'distance break', 1, 10, 0.1],
      ['eatDistF', 'eat contact', 0.1, 2, 0.05], ['fuseDistF', 'fusion contact', 0.1, 2, 0.05], ['symDistF', 'pair contact', 0.1, 3, 0.05]]],
    ['life', [
      ['spawnProtect', 'spawn protect', 0, 1, 1], ['boundGap', 'wall gap', 0, 200, 1], ['boundZone', 'awareness zone', 0, 200, 1], ['dragMargin', 'drag margin', 0, 100, 1], ['edgeGrab', 'border grab', 3, 40, 1], ['restless', 'restlessness', 0, 3, 0.05], ['boundForce', 'push', 0, 3, 0.05], ['cellMorphMs', 'morph time', 100, 6000, 50],
      ['wallSmoothMs', 'wall follow', 0, 400, 5], ['wallCarry', 'wall carry', 0, 2, 0.05], ['wallSpread', 'wall spread', 0, 2, 0.05],
      ['squashMax', 'squash depth', 0, 0.6, 0.01], ['squashIn', 'squash in', 0, 1, 0.01], ['squashOut', 'squash out', 0, 1, 0.01], ['senseR', 'sensing radius', 0, 4, 0.05], ['senseSlow', 'sensing slow', 0, 1, 0.01], ['senseTurn', 'sensing turn', 0, 1, 0.01], ['senseDelay', 'sensing delay', 0, 1, 0.01], ['wallSubStep', 'wall substep', 0.05, 2, 0.05], ['wallSubMax', 'wall substep max', 1, 16, 1], ['crowdGain', 'crowd build', 0, 1, 0.01], ['crowdRel', 'crowd release', 0, 1, 0.01], ['crowdSlow', 'crowd slow', 0, 1, 0.01], ['crowdPush', 'crowd drift', 0, 1, 0.01], ['habRate', 'habituation rate', 0, 0.2, 0.001], ['habDecay', 'habituation restore', 0, 0.2, 0.001], ['habMax', 'habituation depth', 0, 1, 0.01], ['solverIters', 'solver iterations', 0, 8, 1], ['solverOverlap', 'solver overlap', 0, 2, 0.05]]],
    ['sound', [
      ['audioVol', 'volume', 0, 1, 0.01], ['audioTone', 'tone', 200, 8000, 10], ['audioMod', 'modulation', 0, 1, 0.01],
      ['audioCrackle', 'micro events', 0, 1, 0.01], ['audioMicroPitch', 'micro pitch', 200, 4000, 10], ['audioMicroDecay', 'micro decay', 10, 400, 1], ['audioMicroRand', 'randomness', 0, 1, 0.01], ['audioWidth', 'stereo width', 0, 1, 0.01]]],
    ['field', [
      ['THRESHOLD', 'metaball threshold', 0.05, 0.6, 0.01], ['metaballStrength', 'metaball strength', 0.005, 0.1, 0.001],
      ['foodDensity', 'food density', 0, 0.1, 0.005], ['foodEnergyValue', 'food energy', 0, 20, 0.5], ['foodGrowAmt', 'growth step', 0, 5, 0.05], ['plateOverlap', 'plate overlap', 0, 0.5, 0.01], ['parasiteSize', 'parasite size', 0.2, 4, 0.05], ['parasiteHard', 'parasite resilience', 0, 40, 0.5], ['parasiteNerv', 'parasite nervousness', 0, 1, 0.01], ['parasiteHardMs', 'starve delay', 0, 60000, 500], ['foodEatR', 'eating radius', 2, 100, 0.5], ['foodEatRate', 'eating rate', 0, 20, 0.1], ['foodLifeMs', 'life step', 50, 2000, 10], ['foodLifeCell', 'life lattice', 1, 20, 0.5], ['foodGrowMax', 'max growth', 1, 8, 0.1], ['foodShrink', 'shrink back', 0, 0.5, 0.005],
      ['foodAlpha', 'dot opacity', 0, 1, 0.01], ['foodSize', 'dot size', 0.5, 12, 0.5], ['foodShow', 'dot frequency', 0, 1, 0.01],
      ['foodReseed', 'food reseed', 0, 1, 1], ['foodReseedFloor', 'reseed floor', 0, 1, 0.05], ['foodReseedMin', 'reseed min', 0, 500, 10], ['foodReseedMax', 'reseed rate', 0, 5000, 50], ['foodReseedTries', 'reseed tries', 1, 20, 1],
      ['minRefreshInterval', 'refresh min', 2, 60, 1], ['maxRefreshInterval', 'refresh max', 3, 90, 1], ['refreshResetEnergy', 'energy reset', 0, 1, 1]]]
  ];
  var layoutKeys = { margin: 1, gap: 1, textScale: 1, areaMin: 1, areaMax: 1 };
  // every change takes effect at once, without a respawn
  // manual entry is free of slider/sim bounds (owner 21 Oct: no hidden ceilings on typed values - the one open
  // rule is renderer validity: a radius must be a finite number above 0, or canvas arc throws every frame)
  var TGKEYS = { UNIVERSE_SIZE: 'U', baseMutationRate: 'mut', mutationRateRange: 'mr', interactionRadius: 'ir', CELL_RADIUS: 'cr' };
  function applyKey(k, v, free) {
    // an edit lands mid-morph too: retarget the in-flight lerp, else the old target pulls the edited value back (measured: ir edit 0.5 stuck at 3.73)
    if (trans && trans.tg && TGKEYS[k]) trans.tg[TGKEYS[k]] = v;
    if (k === 'CELL_RADIUS') { if (!free) { P.CELL_RADIUS = v = clamp(v, P.minRadius, P.maxRadius); } cells.forEach(function (c) { c.radius = v; }); }
    else if (k === 'minRadius' || k === 'maxRadius') { P.CELL_RADIUS = clamp(P.CELL_RADIUS, P.minRadius, Math.max(P.minRadius, P.maxRadius)); cells.forEach(function (c) { c.radius = P.CELL_RADIUS; }); }
    else if (k === 'pixelRatio') resizeCanvas();
    else if (k === 'panelWidth' && panel) panel.style.width = v + 'px';
    else if (k === 'blurWidth') { if (blurEl) blurEl.style.width = v + 'px'; if (blurLEl) blurLEl.style.width = v + 'px'; }
    else if (k === 'blurStrength') document.documentElement.style.setProperty('--bmax', v + 'px');
    else if (k === 'margin') document.documentElement.style.setProperty('--m', v + 'px');
    else if (k === 'panelRowGap') document.documentElement.style.setProperty('--rg', v + 'px');
    else if (k === 'resolution') res = v;
    else if (k === 'axisWidth') applyLW();
    else if (k === 'typeSlider') document.getElementById('panel').classList.toggle('type-slider', !!v);
    else if (k === 'cfgFontSize') applyTypo();
    else if (layoutKeys[k]) clampTargets();
    else if (k === 'baseMaxSpeed' || k === 'maxSpeedVariation') cells.forEach(function (c) { c.maxSpeed = speedOf(c); });
    else if (k === 'UNIVERSE_SIZE') {
      var n = Math.round(v), gx = cont.x, gy = cont.y;
      while (cells.length < n) cells.push(new Cell(gx + rnd(cont.w), gy + rnd(cont.h), Math.floor(rnd(P.GENE_MIN, P.GENE_MAX + 1)), P.baseMutationRate + rnd(-P.mutationRateRange, P.mutationRateRange)));
      while (cells.length > n) { var di0 = Math.floor(rnd(cells.length)); habReap(cells[di0]); cells.splice(di0, 1); }
    }
    else if (k === 'foodDensity') {
      var nf = Math.round(cont.w * cont.h * P.foodDensity / 2);
      for (var fg = 0, fq; food.length < nf && fg < nf; fg++) { fq = foodSpot(cont.x, cont.y, cont.w, cont.h); if (fq) food.push({ x: fq.x, y: fq.y, r: Math.random() }); } // out-of-frame spawn: same ink exclusion as every other spawn site (a skipped spawn counts against the bound)
      if (food.length > nf) food.length = nf;
    }
    else if (k === 'minRefreshInterval' || k === 'maxRefreshInterval') newRefresh();
  }
  function fmt(v) { return Math.abs(v) >= 100 ? String(Math.round(v)) : String(Math.round(v * 1000) / 1000); }
  var lockBox, lockVal;
  var touched = {}; // keys the user actually edited; admin push writes only these
  var SECS = [];
  GROUPS.forEach(function (grp) {
    var h = document.createElement('div'); h.className = 'grp'; h.textContent = grp[0]; ctl.appendChild(h);
    var sec = { name: grp[0], hdr: h, els: [] }; SECS.push(sec);
    grp[1].forEach(function (q) {
      var savedBound = rangeBounds[q[0]];
      if (Array.isArray(savedBound) && savedBound.length === 2 && savedBound.every(function(v){return typeof v === 'number' && isFinite(v);}) && savedBound[0] < savedBound[1]) { q[2] = savedBound[0]; q[3] = savedBound[1]; }
      var d = document.createElement('div'); d.className = 'row';
      d.dataset.key = q[0];
      d.innerHTML = '<div class="lab"><span>' + q[1] + '</span><b style="font-weight:normal"></b></div><input type="range" min="' + q[2] + '" max="' + q[3] + '" step="' + q[4] + '">';
      var inp = d.querySelector('input'), val = d.querySelector('b');
      d.classList.add('param-row');
      var nameEl = d.querySelector('.lab > span'), fullName = q[1], tail = fullName.slice(-1);
      nameEl.textContent = fullName.slice(0, -1);
      var nameTail = document.createElement('span'); nameTail.className = 'name-tail'; nameTail.textContent = tail; nameEl.appendChild(nameTail);
      var letter = document.createElement('span'); letter.className = 'type-knob'; letter.textContent = tail; letter.setAttribute('aria-hidden', 'true'); d.appendChild(letter);

      var rangeEdit = document.createElement('span'); rangeEdit.className = 'range-edit';
      var minEdit = document.createElement('input'), maxEdit = document.createElement('input'), hyphen = document.createElement('span');
      minEdit.className = 'range-min'; maxEdit.className = 'range-max'; hyphen.textContent = '-';
      [minEdit,maxEdit].forEach(function(ed,i){ed.type='text';ed.inputMode='decimal';ed.spellcheck=false;ed.setAttribute('aria-label',q[1]+(i?' maximum':' minimum'));ed.addEventListener('pointerdown',function(e){e.stopPropagation();});});
      rangeEdit.appendChild(minEdit);rangeEdit.appendChild(hyphen);rangeEdit.appendChild(maxEdit);val.parentNode.appendChild(rangeEdit);
      var holdTimer=0,holdPoint=null,holdFired=false,holdOriginal=0;
      function rangeToggle(){
        if(!d.classList.contains('range-editing')){
          if(d.querySelector('.man'))return;
          minEdit.value=fmt(q[2]);maxEdit.value=fmt(q[3]);d.classList.add('range-editing');rangeEdit.removeAttribute('data-invalid');
        }else{
          var lo=Number(minEdit.value.trim().replace(',','.')),hi=Number(maxEdit.value.trim().replace(',','.'));
          if(!minEdit.value.trim()||!maxEdit.value.trim()||!isFinite(lo)||!isFinite(hi)||lo>=hi){rangeEdit.dataset.invalid='true';minEdit.setAttribute('aria-invalid','true');maxEdit.setAttribute('aria-invalid','true');return;}
          q[2]=lo;q[3]=hi;inp.min=lo;inp.max=hi;inp.value=P[q[0]];rangeBounds[q[0]]=[lo,hi];
          if(live[q[0]]){var L=live[q[0]];L.prof=liveProfile(q,L.plate);L.target=clamp(L.target===undefined?L.cur:L.target,lo,hi);L.cur=clamp(L.cur,lo,hi);L.vel=0;}
          minEdit.removeAttribute('aria-invalid');maxEdit.removeAttribute('aria-invalid');d.classList.remove('range-editing');val.textContent=fmt(P[q[0]]);save();
        }
      }
      function holdCancel(){clearTimeout(holdTimer);holdTimer=0;holdPoint=null;}
      inp.addEventListener('pointerdown',function(e){
        try{inp.setPointerCapture(e.pointerId);}catch(ignore){}
        holdFired=false;holdOriginal=P[q[0]];holdPoint={x:e.clientX,y:e.clientY};
        if(d.classList.contains('range-editing'))e.preventDefault();
        holdTimer=setTimeout(function(){holdFired=true;holdPoint=null;P[q[0]]=holdOriginal;applyKey(q[0],holdOriginal,true);inp.value=holdOriginal;val.textContent=fmt(holdOriginal);rangeToggle();save();},650);
      });
      inp.addEventListener('pointermove',function(e){if(holdPoint&&Math.hypot(e.clientX-holdPoint.x,e.clientY-holdPoint.y)>6)holdCancel();});
      ['pointerup','pointercancel','lostpointercapture'].forEach(function(name){inp.addEventListener(name,holdCancel);});
      inp.addEventListener('click',function(e){if(holdFired){e.preventDefault();e.stopImmediatePropagation();}},true);
      inp.addEventListener('contextmenu',function(e){e.preventDefault();});
      rangeEdit.addEventListener('keydown',function(e){e.stopPropagation();if(e.key==='Escape'){d.classList.remove('range-editing');} });
      // double-click the value: type it by hand (may pass the knob's floor/ceiling; the knob itself stays inside them)
      val.addEventListener('click', function (e) {
        e.stopPropagation();
        if (d.classList.contains('range-editing') || d.querySelector('.man')) return;
        var k = q[0];
        var ed = document.createElement('input'); ed.type = 'text'; ed.className = 'man'; ed.value = fmt(P[k]);
        ed.setAttribute('inputmode', 'decimal'); ed.spellcheck = false; ed.autocomplete = 'off';
        var labH = P.typeSlider ? Math.max(val.offsetHeight, parseFloat(getComputedStyle(val).lineHeight) || 17) : val.parentNode.offsetHeight;
        ed.style.height = labH + 'px'; ed.style.lineHeight = labH + 'px';
        ed.style.caretColor = ['#ff0000', '#00ff00', '#0000ff'][Math.floor(Math.random() * 3)];
        val.style.display = 'none'; val.parentNode.appendChild(ed);
        ed.focus({ preventScroll: true }); ed.select();
        var done = false;
        var fin = function (commit) {
          if (done) return; done = true;
          var t = ed.value.trim().replace(',', '.');
          if (commit && /^[-+]?(\d+\.?\d*|\.\d+)(e[-+]?\d+)?$/i.test(t)) {
            var v = parseFloat(t);
            if (isFinite(v) && !(k === 'CELL_RADIUS' && v <= 0)) {
              if (live[k]) liveStop(k);
              P[k] = v; touched[k] = 1; applyKey(k, v, true); inp.value = v; val.textContent = fmt(v);
              if (/UNIVERSE|CELL_RADIUS|Mutation|interaction|Rate/.test(k)) { lockParams = true; if (lockBox) { lockBox.checked = true; lockVal.textContent = 'locked'; } }
              save();
            }
          }
          ed.remove(); val.style.display = '';
        };
        ed.addEventListener('keydown', function (ev) { ev.stopPropagation(); if (ev.key === 'Enter') fin(true); else if (ev.key === 'Escape') fin(false); });
        ed.addEventListener('blur', function () { fin(true); });
      });
      var downVal = null;
      inp.addEventListener('pointerdown', function () { if (!live[q[0]]) downVal = P[q[0]]; });
      inp.addEventListener('dblclick', function () {
        if(d.classList.contains('range-editing')||holdFired)return;
        var k = q[0];
        if (live[k]) { liveStop(k); inp.value = P[k]; val.textContent = fmt(P[k]); return; }
        var o = downVal === null ? P[k] : downVal; P[k] = o; touched[k] = 1; applyKey(k, o); inp.value = o; val.textContent = fmt(o); liveStart(k, q, o, d); save();
      });
      // hover: the thumb stirs with a small rule-110 life of its own (visual only, value untouched)
      inp.addEventListener('pointerenter', function () {
        inp.style.setProperty('--hc', ['#ff0000', '#00ff00', '#0000ff'][Math.floor(Math.random() * 3)]);
        var k = q[0]; if (hovCA[k]) return;
        var st = { s: (hash(k) ^ 0x9e37) || 7 }, bits = [];
        for (var i = 0; i < 16; i++) bits.push(lcg(st) < 0.5 ? 1 : 0);
        hovCA[k] = { bits: bits, st: st, dx: 0, t: setInterval(function () {
          var hh = hovCA[k]; if (!hh || inp.matches(':active')) return;
          var nb = new Array(16), sum = 0;
          for (var i = 0; i < 16; i++) { nb[i] = (110 >> (hh.bits[(i + 15) % 16] * 4 + hh.bits[i] * 2 + hh.bits[(i + 1) % 16])) & 1; sum += nb[i]; }
          if (sum === 0 || sum === 16) nb[Math.floor(lcg(hh.st) * 16)] ^= 1;
          hh.bits = nb;
          hh.dx = clamp(hh.dx + (nb[0] + nb[5] + nb[10] - 1.5) * 2 + (lcg(hh.st) - 0.5) * 2, -6, 6);
          inp.style.setProperty('--kx', hh.dx.toFixed(1) + 'px');
          inp.style.setProperty('--ks', (1 + sum / 16 * 0.4).toFixed(2));
        }, LIVE_MS) };
      });
      inp.addEventListener('pointerleave', function () {
        var k = q[0], hh = hovCA[k]; if (!hh) return;
        clearInterval(hh.t); delete hovCA[k];
        inp.style.setProperty('--kx', '0px'); inp.style.setProperty('--ks', '1');
      });
      inp.addEventListener('input', function () {
        if (d.classList.contains('range-editing') || holdFired) { inp.value=P[q[0]]; return; }
        if (live[q[0]]) { inp.value = P[q[0]]; return; }
        var v = parseFloat(inp.value); P[q[0]] = v; touched[q[0]] = 1; val.textContent = fmt(v);
        applyKey(q[0], v);
        if (q[0] === 'fps') { /* nothing */ } else if (/UNIVERSE|CELL_RADIUS|Mutation|interaction|Rate/.test(q[0])) { lockParams = true; if (lockBox) { lockBox.checked = true; lockVal.textContent = 'locked'; } }
        save();
      });
      inp.value = P[q[0]]; val.textContent = fmt(P[q[0]]);
      ctl.appendChild(d); rows[q[0]] = { inp: inp, val: val, row: d, letter: letter }; sec.els.push(d);
    });
  });
  document.getElementById('panel').classList.toggle('type-slider', !!P.typeSlider);
  var keyToQ = {}; GROUPS.forEach(function (g) { g[1].forEach(function (q) { keyToQ[q[0]] = q; }); });
  Object.keys(savedLive).forEach(function (k) {
    if (keyToQ[k] && rows[k] && typeof savedLive[k] === 'number' && isFinite(savedLive[k])) liveStart(k, keyToQ[k], savedLive[k], rows[k].row);
  });
  function toggle(label, init, fn, words) {
    words = words || ['on', 'off'];
    var l = document.createElement('label'); l.className = 'chk';
    l.innerHTML = '<span>' + label + '</span><b>' + (init ? words[0] : words[1]) + '</b><input type="checkbox" style="display:none"' + (init ? ' checked' : '') + '>';
    var c = l.querySelector('input'), b = l.querySelector('b');
    c.addEventListener('change', function () { b.textContent = c.checked ? words[0] : words[1]; var bef = Object.assign({}, P); fn(c.checked); for (var k in P) if (P[k] !== bef[k]) touched[k] = 1; save(); });
    ctl.appendChild(l); return { box: c, val: b, el: l };
  }
  function choice(label, key, opts, fn) {
    var l = document.createElement('label'); l.className = 'chk';
    l.innerHTML = '<span>' + label + '</span><b>' + opts[P[key]] + '</b>';
    var b = l.querySelector('b');
    l.addEventListener('click', function () { P[key] = (P[key] + 1) % opts.length; touched[key] = 1; b.textContent = opts[P[key]]; if (fn) fn(P[key]); save(); });
    ctl.appendChild(l); return { el: l };
  }
  var typeToggle = toggle('type slider', !!P.typeSlider, function (v) { P.typeSlider = v ? 1 : 0; document.getElementById('panel').classList.toggle('type-slider', !!v); });
  ctl.insertBefore(typeToggle.el, SECS[2].hdr); SECS[1].els.push(typeToggle.el);
  var CFG_FONTS = ['default', 'Fragment Mono', 'Times New Roman', 'Ca2-Thin', 'system sans', 'system mono'], CFG_STACK = [null, "'Fragment Mono', ui-monospace, monospace", "'Times New Roman', Times, serif", "'Ca2-Thin', monospace", "system-ui, -apple-system, 'Helvetica Neue', Arial, sans-serif", "ui-monospace, 'SF Mono', Menlo, monospace"], CFG_CASES = ['default', 'UPPER', 'lower', 'Sentence'];
  var gh = document.createElement('div'); gh.className = 'grp'; gh.textContent = 'switches'; ctl.appendChild(gh);
  var swSec = { name: 'switches', hdr: gh, els: [] }; SECS.push(swSec);
  var _toggle = toggle, _choice = choice;
  toggle = function () { var r = _toggle.apply(null, arguments); swSec.els.push(r.el); return r; };
  choice = function () { var r = _choice.apply(null, arguments); swSec.els.push(r.el); return r; };
  choice('axis layering', 'axisLayer', ['above', 'behind']);
  choice('micro sound', 'audioMicro', ['click', 'tick', 'drop', 'bubble', 'wood', 'bloom']);
  choice('sound mode', 'audioMode', ['soft white', 'pink', 'brown', 'micro crackle', 'membrane']);
  toggle('sound', !!P.audioOn, function (v) { P.audioOn = v ? 1 : 0; if (window.CA2Audio) CA2Audio.enable(v); });
  toggle('genome', !!P.genomeOn, function (v) { P.genomeOn = v ? 1 : 0; cells.forEach(function (c) { c.maxSpeed = speedOf(c); }); });
  toggle('amorphous outline', !!P.blobOutline, function (v) { P.blobOutline = v ? 1 : 0; });
  toggle('dividing', !!P.divideOn, function (v) { P.divideOn = v ? 1 : 0; });
  toggle('eat merge', !!P.eatMergeOn, function (v) { P.eatMergeOn = v ? 1 : 0; });
  toggle('symbiosis', !!P.symbiosisOn, function (v) { P.symbiosisOn = v ? 1 : 0; });
  toggle('symbiogenesis', !!P.symbiogenesisOn, function (v) { P.symbiogenesisOn = v ? 1 : 0; });
  toggle('parasites', !!P.parasiteOn, function (v) { P.parasiteOn = v ? 1 : 0; });
  toggle('selection', !!P.selectOn, function (v) { P.selectOn = v ? 1 : 0; });
  toggle('food growth', !!P.foodGrow, function (v) { P.foodGrow = v ? 1 : 0; });
  toggle('boundary awareness', !!P.boundAware, function (v) { P.boundAware = v ? 1 : 0; });
  toggle('respawn morph', !!P.respawnMorph, function (v) { P.respawnMorph = v ? 1 : 0; });
  toggle('micro habitat', !!P.habitatOn, function (v) { P.habitatOn = v ? 1 : 0; });
  choice('food life', 'foodMode', ['original', 'game of life', 'amorphous blobs', 'swarm', 'worms', 'spores']);
  toggle('body shapes', !!P.cellShapes, function (v) { P.cellShapes = v ? 1 : 0; });
  toggle('cell metamorphosis', !!P.cellMorph, function (v) { P.cellMorph = v ? 1 : 0; });
  toggle('auto invert', !!P.autoInvert, function (v) { P.autoInvert = v ? 1 : 0; invertTick(); });
  toggle('title circles', !!P.titleCircles, function (v) { P.titleCircles = v ? 1 : 0; });
  toggle('axis separator', !!P.separatorOn, function (v) { P.separatorOn = v ? 1 : 0; }); // owner 22 Oct: separator inside the moving boundary + awareness of all page typography
  toggle('circle hold', !!P.circleHold, function (v) { P.circleHold = v ? 1 : 0; });
  var lockT = toggle('refresh lock', lockParams, function (v) { lockParams = v; });
  lockBox = lockT.box; lockVal = lockT.val;
  toggle('auto refresh', autoRefresh, function (v) { autoRefresh = v; lastRefresh = performance.now(); });
  toggle('auto quality', !!P.autoQuality, function (v) { P.autoQuality = v ? 1 : 0; });
  toggle('grain', !!P.grain, function (v) { P.grain = v ? 1 : 0; });
  toggle('typography', !!P.showHud, function (v) { P.showHud = v ? 1 : 0; });
  toggle('food dots', !!P.showFood, function (v) { P.showFood = v ? 1 : 0; });
  toggle('axis lines', !!P.showAxis, function (v) { P.showAxis = v ? 1 : 0; });
  choice('config font', 'cfgFont', CFG_FONTS, applyTypo);
  choice('config case', 'cfgCase', CFG_CASES, applyTypo);
  function btn(label, fn) { var b = document.createElement('button'); b.textContent = label; b.addEventListener('click', fn); btns.appendChild(b); return b; }
  btn('respawn', function () { randomize(); });
  btn('randomize', function () { lockParams = false; lockBox.checked = false; lockVal.textContent = 'off'; randomize(); });
  btn('background', cycleBg);
  btn('reset', function () { Object.keys(live).forEach(function (k) { delete live[k]; }); Object.keys(DEFAULTS).forEach(function (k) { P[k] = DEFAULTS[k]; }); autoRefresh = true; lockParams = false; bgIndex = 0; bgTarget = BGS[0]; try { localStorage.removeItem(STORE); } catch (e) {} res = P.resolution; resize(); randomize(); location.reload(); });
  btn('copy json', function (ev) {
    var Pc = Object.assign({}, P); for (var lk in live) Pc[lk] = live[lk].orig;
    var txt = JSON.stringify(Pc, null, 1), bt = ev.currentTarget, ok = false;
    // execCommand first and synchronously (works on http pages, where navigator.clipboard does not exist)
    try { var ta = document.createElement('textarea'); ta.value = txt; ta.setAttribute('readonly', ''); ta.style.cssText = 'position:fixed;left:0;top:0;opacity:0;font-size:16px'; document.body.appendChild(ta); ta.focus(); ta.select(); ta.setSelectionRange(0, txt.length); ok = document.execCommand('copy'); document.body.removeChild(ta); } catch (er) {}
    if (!ok && navigator.clipboard && navigator.clipboard.writeText) { try { navigator.clipboard.writeText(txt).then(function () { bt.textContent = 'copied'; }, function () { bt.textContent = 'copy failed'; }); } catch (er) { bt.textContent = 'copy failed'; } return; }
    bt.textContent = ok ? 'copied' : 'copy failed'; window.ca2copy = txt; setTimeout(function () { bt.textContent = 'copy json'; }, 1500);
  });
  // perf section: its whole pool is one live timing block, placed between the copy and save buttons.
  // Soloing the perf circle hides every knob section and leaves just this block; CONFIG brings all back.
  // perf section: no rows of its own - soloing it continues the CONFIG stats block with the
  // live timing values, in the same row style (owner 21 Oct). hdr is a zero marker for solo().
  var perfHdr = document.createElement('div'); perfHdr.style.display = 'none'; ctl.appendChild(perfHdr);
  var perfSec = { name: 'perf', hdr: perfHdr, els: [] }; SECS.push(perfSec);
  // the save button is created by the server-verified admin module (owner 21 Oct: no admin trace ships publicly)
  function applyTypo() {
    var r = document.documentElement.style;
    if (CFG_STACK[P.cfgFont]) r.setProperty('--cff', CFG_STACK[P.cfgFont]); else r.removeProperty('--cff');
    document.getElementById('panel').classList.toggle('fbold', [0, 2].indexOf(P.cfgFont) >= 0); // serif titles only: Times (also the default fallback); all other active families stay unchanged
    if (P.cfgFontSize === 13) r.removeProperty('--cfs'); else r.setProperty('--cfs', P.cfgFontSize + 'px');
    var cl = ['', 'cs-u', 'cs-l', 'cs-s'], pn = document.getElementById('panel'), sc = document.getElementById('secc');
    ['cs-u', 'cs-l', 'cs-s'].forEach(function (c) { if (pn) pn.classList.remove(c); if (sc) sc.classList.remove(c); });
    if (cl[P.cfgCase]) { if (pn) pn.classList.add(cl[P.cfgCase]); if (sc) sc.classList.add(cl[P.cfgCase]); }
  }
  // auto invert: the config panel blends with what is behind it using mix-blend-mode: difference, so every pixel of text, line or
  // control that overlaps a cell, dot or colour is inverted against it (white ink on a light page reads dark, on a dark dot reads light).
  var invState = -1;
  function invertTick() {
    var pn = document.getElementById('panel'); if (!pn) return;
    pn.classList.toggle('blend', !!P.autoInvert);
    if (P.autoInvert) { pn.style.setProperty('--kl', P.lineColor === '#111111' ? '#ffffff' : P.lineColor); }
    else pn.style.removeProperty('--kl');
  }
  // knob colours (random R/G/B on hover, live CA colour) are drawn as plain elements outside the blended panel so they stay true R/G/B
  function paintKnobs() {
    var pr = document.getElementById('panel').getBoundingClientRect(), vis = pr.left < W - 4;
    for (var k in rows) {
      var R = rows[k], inp = R.inp, col = null, track = false;
      if (vis) { if (live[k]) { col = live[k].col; track = true; } else if (inp.matches(':hover')) col = inp.style.getPropertyValue('--hc') || null; }
      if (P.typeSlider && R.letter) {
        if (R.ov) R.ov.t.style.display = R.ov.l.style.display = 'none';
        inp.classList.remove('ovl');
        var rr = inp.getBoundingClientRect(), dr = R.row.getBoundingClientRect();
        var minT = +inp.min, maxT = +inp.max, fT = maxT > minT ? clamp((+inp.value - minT) / (maxT - minT), 0, 1) : 0;
        var lwT = R.letter.offsetWidth, dxT = parseFloat(inp.style.getPropertyValue('--kx')) || 0;
        R.letter.style.left = (rr.left - dr.left + fT * Math.max(0, rr.width - lwT)) + 'px';
        R.letter.style.top = (rr.top - dr.top + (rr.height - R.letter.offsetHeight) / 2) + 'px';
        R.letter.style.color = col || ''; R.letter.style.fontWeight = col ? '700' : '400';
        R.letter.style.transform = 'translateX(' + dxT + 'px) scale(' + (parseFloat(inp.style.getPropertyValue('--ks')) || 1) + ')';
        continue;
      }
      var on = !!col; inp.classList.toggle('ovl', on);
      if (!on) { if (R.ov) R.ov.t.style.display = R.ov.l.style.display = 'none'; continue; }
      var r = inp.getBoundingClientRect(); if (r.top < pr.top || r.bottom > pr.bottom) { if (R.ov) R.ov.t.style.display = R.ov.l.style.display = 'none'; continue; }
      if (!R.ov) { var t = document.createElement('div'), l = document.createElement('div'); t.style.cssText = l.style.cssText = 'position:fixed;z-index:12;pointer-events:none;box-sizing:border-box'; t.style.borderRadius = '50%'; document.body.appendChild(l); document.body.appendChild(t); R.ov = { t: t, l: l }; }
      var mn = parseFloat(inp.min), mx = parseFloat(inp.max), fr = mx > mn ? clamp((parseFloat(inp.value) - mn) / (mx - mn), 0, 1) : 0;
      var kx = parseFloat(inp.style.getPropertyValue('--kx')) || 0, ks = parseFloat(inp.style.getPropertyValue('--ks')) || 1, lw = LW(), d = 12 * ks, cx = r.left + 6 + fr * (r.width - 12) + kx, cy = r.top + r.height / 2;
      var t2 = R.ov.t, l2 = R.ov.l; t2.style.display = 'block'; t2.style.left = (cx - d / 2) + 'px'; t2.style.top = (cy - d / 2) + 'px'; t2.style.width = t2.style.height = d + 'px'; t2.style.background = col; t2.style.border = lw + 'px solid ' + col;
      l2.style.display = track ? 'block' : 'none'; if (track) { l2.style.left = r.left + 'px'; l2.style.top = (cy - lw / 2) + 'px'; l2.style.width = r.width + 'px'; l2.style.height = lw + 'px'; l2.style.background = col; }
    }
  }
  if (PERF) { var ph = document.createElement('pre'); ph.style.cssText = 'position:fixed;left:8px;bottom:8px;z-index:99;margin:0;font:11px/1.3 monospace;color:#0f0;background:rgba(0,0,0,.7);padding:6px;pointer-events:none'; document.body.appendChild(ph);
    setInterval(function () { var o = 'fps ' + Math.round(fps) + '  frame ' + frameMs.toFixed(1) + ' ms  res ' + res.toFixed(2) + '  dpr ' + DPR + '  cells ' + cells.length + '\n' + 'metaball field: ' + MB.path + '  ' + MB.ms.toFixed(2) + ' ms' + (WC.off ? '  (wasm failed: ' + WC.err + ')' : (/[?&]nowasm=1/.test(location.search) ? '  (?nowasm=1)' : (WC.ok ? '' : '  (wasm: ' + (WC.err || 'loading') + ')'))) + '\n'; for (var k in PF) if (!/total/.test(k)) o += (k + '                    ').slice(0, 18) + PF[k].toFixed(2) + '\n'; ph.textContent = o; }, 500); }
  (function swLoop() { try { paintKnobs(); } catch (e) {} requestAnimationFrame(swLoop); })();
  setInterval(invertTick, 250);
  function applyLineColor() { invertTick(); var rt = document.documentElement.style; rt.setProperty('--kl', P.lineColor); if (P.ruleColor) rt.setProperty('--kr', P.ruleColor); else rt.removeProperty('--kr'); if (P.circColor) rt.setProperty('--kc', P.circColor); else rt.removeProperty('--kc'); }
  var panel = document.getElementById('panel'), blurEl = document.getElementById('blur'), blurLEl = document.getElementById('blurl');
  panel.style.width = P.panelWidth + 'px'; blurEl.style.width = P.blurWidth + 'px'; blurLEl.style.width = P.blurWidth + 'px';
  document.documentElement.style.setProperty('--bmax', P.blurStrength + 'px');

  // ---- section circles: one per config section in the panel's right lane ----
  // title-dot size (166.5 font units), axis-line stroke, hollow; hover fills a random R/G/B (stroke too) and shows the
  // section name vertically with a typewriter animation; the circles below slide away from the label; click folds the section.
  var secc = document.createElement('div'); secc.id = 'secc'; document.body.appendChild(secc);
  // config visibility: the tab strip, the panel, the section lane and the admin circles are one hover area. The lane and the admin
  // circles sit outside the panel element, so :hover on the panel dropped while the pointer was on a circle; the panel slid away,
  // the pointer fell back on the tab strip and it slid in again (stutter). A class with a short close delay bridges the hand-over.
  var hovT = null;
  function hookHov(el) {
    el.addEventListener('pointerenter', function (e) { if (e.pointerType === 'touch') return; clearTimeout(hovT); panel.classList.add('hov'); });
    el.addEventListener('pointerleave', function (e) { if (e.pointerType === 'touch') return; clearTimeout(hovT); hovT = setTimeout(function () { panel.classList.remove('hov'); }, 220); });
  }
  [document.getElementById('tab'), panel, secc].forEach(hookHov);
  var CIRC_COLS = ['#ff0000', '#00ff00', '#0000ff'];
  // local rules a crowd of pieces can follow (p = a piece, c = its surroundings this tick)
  var RULES = {
    jitter: function (p, c) { p.vx += c.jx * 1.2; p.vy += c.jy * 1.2; },
    cohere: function (p, c) { p.vx += (c.cx - p.x) * 0.04 + c.jx * 0.5; p.vy += (c.cy - p.y) * 0.04 + c.jy * 0.5; },
    repel: function (p, c) { var dx = p.x - c.nbr.x, dy = p.y - c.nbr.y, d = Math.hypot(dx, dy) || 1; if (d < 14) { p.vx += dx / d * 0.7; p.vy += dy / d * 0.7; } else { p.vx += c.jx * 0.4; p.vy += c.jy * 0.4; } },
    align: function (p, c) { p.vx += (c.nbr.vx - p.vx) * 0.4 + c.jx * 0.3; p.vy += (c.nbr.vy - p.vy) * 0.4 + c.jy * 0.3; },
    drift: function (p, c) { var a = c.tick * 0.012; p.vx += Math.cos(a) * 0.25 + c.jx * 0.4; p.vy += Math.sin(a) * 0.25 + c.jy * 0.4; },
    swirl: function (p, c) { p.vx += -p.y / c.pd * 0.35 + c.jx * 0.3; p.vy += p.x / c.pd * 0.35 + c.jy * 0.3; },
    grid: function (p, c) { p.vx += (Math.round(p.x / 10) * 10 - p.x) * 0.1 + c.jx * 0.2; p.vy += (Math.round(p.y / 10) * 10 - p.y) * 0.1 + c.jy * 0.2; },
    rows: function (p, c) { p.vy += (Math.round(p.y / 9) * 9 - p.y) * 0.12; p.vx += Math.sin(c.tick * 0.06 + Math.round(p.y / 9)) * 0.5 + c.jx * 0.3; },
    slide: function (p, c) { p.vx += Math.sin(c.tick * 0.07) * 0.6 + c.jx * 0.3; p.vy += c.jy * 0.3; },
    pulse: function (p, c) { var k = Math.sin(c.tick * 0.12) * 0.3; p.vx += p.x / c.pd * k + c.jx * 0.3; p.vy += p.y / c.pd * k + c.jy * 0.3; },
    chain: function (p, c) { p.vx += (c.prev.x - p.x) * 0.08 + c.jx * 0.3; p.vy += (c.prev.y - p.y) * 0.08 + c.jy * 0.3; },
    flicker: function (p, c) { p.x += c.jx * 5; p.y += c.jy * 5; },
    wave: function (p, c) { p.vy += Math.cos(c.tick * 0.1 + p.x * 0.15) * 0.5; p.vx += c.jx * 0.3; },
    tide: function (p, c) { p.vx += Math.sin(c.tick * 0.03) * 0.5 + c.jx * 0.3; p.vy += Math.cos(c.tick * 0.021 + p.x * 0.05) * 0.2 + c.jy * 0.3; },
    mutate: function (p, c) { p.vx = c.nbr.vx * 0.9 + c.jx * 1.2; p.vy = c.nbr.vy * 0.9 + c.jy * 1.2; },
    frame: function (p, c) { var hx = 34, hy = 22, ex = Math.abs(p.x) - hx, ey = Math.abs(p.y) - hy; if (ex > ey) p.vx += (Math.sign(p.x || 1) * hx - p.x) * 0.1; else p.vy += (Math.sign(p.y || 1) * hy - p.y) * 0.1; p.vx += c.jx * 0.4; p.vy += c.jy * 0.4; },
    flip: function (p, c) { p.vx += ((p.b ? 24 : -24) - p.x) * 0.08 + c.jx * 0.3; p.vy += -p.y * 0.05 + c.jy * 0.3; },
    blink: function (p, c) { p.el.style.opacity = p.b ? '1' : '0.3'; p.vx += c.jx * 0.8; p.vy += c.jy * 0.8; }
  };
  // murmuration for the EVOLUTION button: once the hover cascade has divided down to the floor, the crowd repeats a 9 s flight:
  // a sudden ragged burst apart, then two sub-flocks that wheel after their own drifting centres (they stretch into streams, pass through
  // each other, merge and split; each piece follows only its nearest few neighbours), then a slow regather. Velocity steering only.
  function murmurStep(p, c, parts, m) {
    var T = 9000, now = performance.now(), u = ((now - m.t0) % T) / T, i, n = parts.length, o, dx, dy, d, tk = now / 1000;
    if (p.fg === undefined) { p.fg = Math.random() < 0.5 ? 0 : 1; p.mag = 0.5 + Math.random() * 1.5; p.ph = Math.random() * 6.283; p.bx = Math.random() - 0.5; p.by = Math.random() - 0.5; }
    var near = [], nd = [];
    for (i = 0; i < n; i++) { o = parts[i]; if (o === p) continue; dx = o.x - p.x; dy = o.y - p.y; d = dx * dx + dy * dy;
      if (near.length < 6) { near.push(o); nd.push(d); } else { var wi = 0; for (var q = 1; q < 6; q++) if (nd[q] > nd[wi]) wi = q; if (d < nd[wi]) { near[wi] = o; nd[wi] = d; } } }
    var ax = 0, ay = 0, px = 0, py = 0, sx = 0, sy = 0, k = near.length;
    for (i = 0; i < k; i++) { o = near[i]; dx = o.x - p.x; dy = o.y - p.y; d = Math.sqrt(nd[i]) || 1; ax += o.vx; ay += o.vy; px += dx; py += dy; if (d < 12) { sx -= dx / d * (12 - d); sy -= dy / d * (12 - d); } }
    var burst = u < 0.14 ? 1 - u / 0.14 : 0, gather = u > 0.84 ? (u - 0.84) / 0.16 : 0, wheel = 1 - burst - gather;
    // two drifting centres whose distance breathes: the sub-flocks split apart and come back together
    var sep = 70 * Math.sin(u * 6.283 * 2 + 0.6), g = p.fg ? 1 : -1;
    var cxo = Math.max(150 - m.hx, Math.min(W - 150 - m.hx, 0)), cyo = Math.max(150 - m.hy, Math.min(H - 150 - m.hy, 0)); // keep the wheel's centre inside the window (the button sits at the right edge)
    var wx = cxo + Math.sin(u * 6.283) * 40 + g * sep, wy = cyo + Math.cos(u * 6.283 * 1.3) * 28 + g * sep * 0.4;
    var rx = p.x - wx, ry = p.y - wy, rd = Math.hypot(rx, ry) || 1, dir = g;
    if (k) { p.vx += (ax / k - p.vx) * 0.1 + px / k * 0.012 + sx * 0.12; p.vy += (ay / k - p.vy) * 0.1 + py / k * 0.012 + sy * 0.12; }
    var wave = 0.6 + 0.8 * Math.max(0, Math.sin(tk * 2.2 + (p.x + p.y) * 0.05 + p.ph)); // density waves travelling through the flock
    p.vx += burst * (rx / rd * 1.6 * p.mag + p.bx * 2.4) + wheel * dir * (-ry / rd) * 0.5 * wave - wheel * rx * 0.004 + gather * (-p.x) * 0.045;
    p.vy += burst * (ry / rd * 1.6 * p.mag + p.by * 2.4) + wheel * dir * (rx / rd) * 0.5 * wave - wheel * ry * 0.004 + gather * (-p.y) * 0.045;
    p.vx += (Math.random() - 0.5) * 0.35; p.vy += (Math.random() - 0.5) * 0.35;
  }
  var SECT_POOL = {
    config: ['grid', 'cohere', 'jitter'], picture: ['frame', 'align', 'drift'], panel: ['rows', 'slide', 'repel', 'grid'], cursor: ['chain', 'swirl', 'jitter'],
    grain: ['flicker', 'repel', 'jitter'], cells: ['cohere', 'repel', 'pulse', 'blink'], evolution: ['mutate', 'drift', 'cohere', 'chain'], life: ['blink', 'pulse', 'cohere', 'swirl'],
    sound: ['wave', 'pulse', 'align'], field: ['tide', 'drift', 'align', 'wave'], switches: ['flip', 'blink', 'slide']
  };
  // pointer tracking for the section-button particles: where it is, and when it last started moving (reaction delays count from there)
  var PTR = { x: -999, y: -999, vx: 0, vy: 0, last: 0, start: 0 };
  document.addEventListener('pointermove', function (e) { var n = performance.now(); if (n - PTR.last > 300) PTR.start = n; PTR.vx = e.clientX - PTR.x; PTR.vy = e.clientY - PTR.y; PTR.x = e.clientX; PTR.y = e.clientY; PTR.last = n; }, { passive: true });
  // how a crowd may answer the pointer: drawn at random per button at every hover, re-drawn after a random time; each piece has its own reaction delay
  var MOUSE_POOL = {
    attract: function (p, d, k) { p.vx += d.dx / d.d * 0.9 * k; p.vy += d.dy / d.d * 0.9 * k; },
    flee: function (p, d, k) { if (d.d < 160) { p.vx -= d.dx / d.d * 1.4 * k; p.vy -= d.dy / d.d * 1.4 * k; } },
    orbit: function (p, d, k) { p.vx += -d.dy / d.d * 0.9 * k + d.dx / d.d * 0.15 * k; p.vy += d.dx / d.d * 0.9 * k + d.dy / d.d * 0.15 * k; },
    drag: function (p, d, k) { p.vx += PTR.vx * 0.12 * k; p.vy += PTR.vy * 0.12 * k; },
    shiver: function (p, d, k) { var a = Math.random() * 6.283, m = Math.min(1, 80 / d.d) * 2.2 * k; p.vx += Math.cos(a) * m; p.vy += Math.sin(a) * m; },
    mirror: function (p, d, k) { p.vx -= PTR.vx * 0.1 * k; p.vy -= PTR.vy * 0.1 * k; },
    shy: function (p, d, k) { if (d.d < 90) { p.vx += d.dy / d.d * 1.2 * k; p.vy -= d.dx / d.d * 1.2 * k; } else { p.vx += d.dx / d.d * 0.25 * k; p.vy += d.dy / d.d * 0.25 * k; } }
  };
  var MOUSE_KEYS = Object.keys(MOUSE_POOL);
  function addCirc(sec) {
    var it = document.createElement('div'); it.className = 'sci';
    var c = document.createElement('div'); c.className = 'sc';
    var lb = document.createElement('div'); lb.className = 'sl';
    var txt = sec.name.toUpperCase(), spans = [];
    for (var i = 0; i < txt.length; i++) { var sp = document.createElement('span'); sp.textContent = txt[i]; lb.appendChild(sp); spans.push(sp); }
    it.appendChild(c); it.appendChild(lb); secc.appendChild(it); sec.circ = c;
    var murm = null; // evolution button only: set once the hover division cascade has run out; the pieces then fly as a murmuration
    var caT = null, caSt = null, t1 = null, t2 = null, dividing = false, parts = [], home = null, D0 = 0, ctr = { x: 0, y: 0 }, endTimers = [], endIv = null;
    function put(p) { p.el.style.transform = 'translate(' + p.x.toFixed(1) + 'px,' + p.y.toFixed(1) + 'px) scale(' + p.k.toFixed(2) + ')'; }
    // pieces scatter freely; only the browser window bounds them (a piece bounces off the window edges, never leaves the screen)
    function inDisc(p) {
      var r = D0 * p.k / 2, ax = ctr.x + p.x, ay = ctr.y + p.y;
      if (ax < r) { p.x += r - ax; p.vx = Math.abs(p.vx); } else if (ax > W - r) { p.x -= ax - (W - r); p.vx = -Math.abs(p.vx); }
      if (ay < r) { p.y += r - ay; p.vy = Math.abs(p.vy); } else if (ay > H - r) { p.y -= ay - (H - r); p.vy = -Math.abs(p.vy); }
    }
    // stop everything that animates this circle and put it back to its resting hollow state (also used when the pointer returns mid-ending)
    function cleanup() {
      if (caT) { clearInterval(caT); if (caT._a) clearInterval(caT._a); if (caT._b) clearInterval(caT._b); caT = null; }
      if (t1) { clearTimeout(t1); t1 = null; }
      if (t2) { clearInterval(t2); t2 = null; }
      if (endIv) { clearInterval(endIv); endIv = null; }
      endTimers.forEach(clearTimeout); endTimers = [];
      parts.forEach(function (p) { if (p.el !== c) p.el.remove(); }); parts = [];
      dividing = false; murm = null; delete c.dataset.flock;
      c.style.transition = ''; c.style.transform = ''; c.style.opacity = ''; c.style.background = 'transparent'; c.style.borderColor = 'var(--kc, var(--fg))'; c.style.borderWidth = LW() + 'px';
    }
    // hover state comes from the pointer crossing the button's resting box only. The living pieces move under a
    // stationary pointer; hit-tested enter/leave on the element itself restarted the whole crowd on every mouse move.
    var hovOn = false, mvT = null;
    function stopTrack() { if (mvT) { document.removeEventListener('pointermove', mvT); mvT = null; } }
    function track() {
      stopTrack();
      mvT = function (e) {
        var ir = it.getBoundingClientRect(), pad = 4;
        var L = ir.left + c.offsetLeft, T = ir.top + c.offsetTop, R = L + c.offsetWidth, B = T + c.offsetHeight;
        if (e.clientX < L - pad || e.clientX > R + pad || e.clientY < T - pad || e.clientY > B + pad) endHover();
      };
      document.addEventListener('pointermove', mvT, { passive: true });
    }
    function startHover() { // hover area is the button only: the label under it is not part of it (hovering the title closes the button)
      if (hovOn) return; hovOn = true; c.style.pointerEvents = 'none'; track();
      cleanup();
      var col = CIRC_COLS[Math.floor(Math.random() * 3)];
      c.style.background = col; c.style.borderColor = col; c.style.borderWidth = '0px'; lb.style.color = col; c.dataset.col = col; // coloured and splitting: no stroke at all
      // measure only the resting line-height: on a re-entry while the closing squeeze is still applied (or its
      // transition still attached) the live computed value is the squeezed 0.9x one and the label comes out short,
      // clipping the last letters against the button below (owner 20 Oct)
      spans.forEach(function (sp) { sp.style.transition = 'none'; sp.style.lineHeight = ''; sp.style.transform = ''; });
      void lb.offsetWidth;
      lb.style.height = (txt.length * (parseFloat(getComputedStyle(spans[0]).lineHeight) || 17) + 14) + 'px';
      lb.classList.add('on'); // open title keeps its breathing room; closed labels leave the circles tangent (owner 22 Oct)
      if (eadmEl && eadmEl.classList.contains('on')) { // the armed code circles slide below the open title, then come back (owner 22 Oct)
        // everything under the hovered circle rides down by the label height + its margin; the lane's own bottom moves the same
        var shift = 16 + (parseFloat(lb.style.height) || 0);
        var lastSc = secc.lastElementChild && secc.lastElementChild.firstChild;
        var laneBottom = lastSc ? lastSc.getBoundingClientRect().bottom : c.getBoundingClientRect().bottom;
        var ov = laneBottom + shift - eadmEl.getBoundingClientRect().top + 8;
        if (ov > 0) eadmEl.style.transform = 'translateY(' + ov.toFixed(1) + 'px)';
      }
      // opening: letters start slightly tight vertically, line spacing eases open into place (very subtle)
      spans.forEach(function (sp) { sp.style.transition = 'none'; sp.style.opacity = '0'; sp.style.lineHeight = 'calc(var(--cfs, 13px) * 0.98)'; sp.style.transform = 'scaleY(.88)'; });
      void lb.offsetWidth;
      spans.forEach(function (sp) { sp.style.transition = 'opacity .12s linear, line-height .3s cubic-bezier(.2,.8,.3,1), transform .3s cubic-bezier(.2,.8,.3,1)'; sp.style.transitionDelay = (Math.random() * 0.2).toFixed(2) + 's'; sp.style.opacity = '1'; sp.style.lineHeight = ''; sp.style.transform = 'scaleY(1)'; });
      // the circle stirs with a small rule-110 life of its own, like the knobs - shrinking, not growing (visual only)
      caSt = { s: (hash(sec.name) ^ 0x51f3) || 9 }; var bits = [];
      for (var i = 0; i < 16; i++) bits.push(lcg(caSt) < 0.5 ? 1 : 0);
      var dx = 0;
      caT = setInterval(function () {
        var nb = new Array(16), sum = 0;
        for (var i = 0; i < 16; i++) { nb[i] = (110 >> (bits[(i + 15) % 16] * 4 + bits[i] * 2 + bits[(i + 1) % 16])) & 1; sum += nb[i]; }
        if (sum === 0 || sum === 16) nb[Math.floor(lcg(caSt) * 16)] ^= 1;
        bits = nb;
        dx = clamp(dx + (nb[0] + nb[5] + nb[10] - 1.5) * 1.5 + (lcg(caSt) - 0.5) * 2, -6, 6);
        if (!dividing) c.style.transform = 'translate(' + dx.toFixed(1) + 'px,0) scale(' + (1 - sum / 16 * 0.4).toFixed(2) + ')';
      }, 110);
      // hover keeps going: in place the circle splits into four, and the pieces keep living as a tiny vector cellular
      // automaton - every 1.3 s each piece divides into four again, always in multiples of four (the crowd is capped at 24, extra pieces die)
      c.parentNode.style.position = 'relative'; // first: offsetLeft/Top must be measured against this item, not against the fixed lane
      var cr0 = c.getBoundingClientRect(); ctr = { x: cr0.left + cr0.width / 2, y: cr0.top + cr0.height / 2 }; D0 = c.offsetWidth; home = { x: c.offsetLeft, y: c.offsetTop }; parts = [{ el: c, x: 0, y: 0, vx: 0, vy: 0, k: 0.6 }]; dividing = true;
      c.style.transition = 'transform .25s ease';
      function mk() { var n = c.cloneNode(false); n.style.position = 'absolute'; n.style.left = home.x + 'px'; n.style.top = home.y + 'px'; n.style.pointerEvents = 'none'; n.style.margin = '0'; n.style.transition = 'transform .25s ease'; n.style.background = c.style.background; n.style.borderColor = c.style.borderColor; c.parentNode.appendChild(n); return n; }
      // no count limit: every piece keeps dividing into four until it is about 4 px
      function split() {
        var out = [], did = false;
        parts.forEach(function (p) {
          if (D0 * p.k < 4) { out.push(p); return; } // pieces stop dividing at about 4 px: smaller is meaningless
          did = true;
          var off = D0 * p.k * 0.25;
          [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(function (d, j) {
            var el = j === 0 ? p.el : mk();
            out.push({ el: el, x: p.x + d[0] * off, y: p.y + d[1] * off, vx: d[0] * 2.2, vy: d[1] * 2.2, k: p.k * 0.5 });
          });
        });
        parts = out; parts.forEach(function (p) { inDisc(p); put(p); });
        if (!did && t2) { clearInterval(t2); t2 = null; if (sec.name === 'evolution' && !murm) { murm = { t0: performance.now(), hx: ctr.x, hy: ctr.y }; c.dataset.flock = '1'; } } // cascade finished (every piece at the ~4 px floor): the flock begins
      }
      t1 = setTimeout(function () { t1 = null; split(); t2 = setInterval(split, 1300); }, 700);
      // behaviour pool: each section draws from a few local rules that fit its subject; at every hover two are picked at random and every
      // piece follows one of them, chosen by its own rule-110 bit (so neighbours of one crowd act differently). No fixed script.
      var mrule = MOUSE_KEYS[Math.floor(Math.random() * MOUSE_KEYS.length)], mUntil = performance.now() + 2500 + Math.random() * 6000, mGain = 0.4 + Math.random() * 1.2;
      c.dataset.mouse = mrule;
      var pool = SECT_POOL[sec.name] || SECT_POOL.config, pick = pool.slice().sort(function () { return Math.random() - 0.5; }).slice(0, 2), tick = 0;
      c.dataset.beh = pick.join('+');
      var life = setInterval(function () {
        tick++;
        var n = parts.length, cx = 0, cy = 0, i;
        for (i = 0; i < n; i++) { cx += parts[i].x; cy += parts[i].y; } cx /= n; cy /= n;
        if (tick % 40 === 0 && Math.random() < 0.5) { var rest = pool.filter(function (r) { return pick.indexOf(r) < 0; }); if (rest.length) { pick[Math.floor(Math.random() * 2)] = rest[Math.floor(Math.random() * rest.length)]; c.dataset.beh = pick.join('+'); } }
        // rule-110 bit per piece, along the crowd's order
        var nb = new Array(n);
        for (i = 0; i < n; i++) { var l = parts[(i + n - 1) % n].b | 0, m = parts[i].b | 0, r2 = parts[(i + 1) % n].b | 0; nb[i] = (110 >> (l * 4 + m * 2 + r2)) & 1; }
        for (i = 0; i < n; i++) { parts[i].b = (tick < 2 && parts[i].b === undefined) ? (lcg(caSt) < 0.5 ? 1 : 0) : nb[i]; if (Math.random() < 0.02) parts[i].b ^= 1; }
        parts.forEach(function (p, i) {
          var cc = { jx: lcg(caSt) - 0.5, jy: lcg(caSt) - 0.5, cx: cx, cy: cy, tick: tick, i: i, n: n, nbr: parts[(i + 1 + Math.floor(lcg(caSt) * 5)) % n], prev: parts[(i + n - 1) % n], pd: Math.hypot(p.x, p.y) || 1 };
          if (murm) murmurStep(p, cc, parts, murm); else RULES[pick[p.b ? 1 : 0]](p, cc);
          p.vx *= 0.88; p.vy *= 0.88;
          var leash = murm ? 190 : 70; if (cc.pd > leash) { p.vx -= p.x / cc.pd * (cc.pd - leash) * 0.08; p.vy -= p.y / cc.pd * (cc.pd - leash) * 0.08; } // never far from the button
          var nowM = performance.now();
          if (nowM > mUntil) { mrule = MOUSE_KEYS[Math.floor(Math.random() * MOUSE_KEYS.length)]; mUntil = nowM + 2500 + Math.random() * 6000; mGain = 0.4 + Math.random() * 1.2; c.dataset.mouse = mrule; }
          if (p.md === undefined) p.md = Math.random() * 1400; // this piece's own reaction delay (ms) after the pointer starts moving
          if (nowM - PTR.last < 900 && nowM - PTR.start > p.md) { var mdx = PTR.x - (ctr.x + p.x), mdy = PTR.y - (ctr.y + p.y); MOUSE_POOL[mrule](p, { dx: mdx, dy: mdy, d: Math.hypot(mdx, mdy) || 1 }, mGain); }
          var vm = murm ? 8 : 4; p.vx = clamp(p.vx, -vm, vm); p.vy = clamp(p.vy, -vm, vm);
          p.x += p.vx; p.y += p.vy; inDisc(p); put(p);
        });
      }, 110);
      var oc = caT; caT = { _a: oc, _b: life };
    }
    function endHover() {
      if (!hovOn) return; hovOn = false; stopTrack(); c.style.pointerEvents = '';
      var col = c.dataset.col || '#000';
      // closing: letters squeeze together vertically a little and fade
      spans.forEach(function (sp) { sp.style.transition = 'opacity .2s ease-in, line-height .2s ease-in, transform .2s ease-in'; sp.style.transitionDelay = '0s'; sp.style.opacity = '0'; sp.style.lineHeight = 'calc(var(--cfs, 13px) * 0.9)'; sp.style.transform = 'scaleY(.8)'; });
      lb.style.height = '0px';
      lb.classList.remove('on');
      if (eadmEl) eadmEl.style.transform = '';
      // stop the hover life; the pieces now die one by one at random moments, one random survivor wanders cellular-automaton style,
      // grows back to the full button size, is pierced from its centre and settles as the button's hollow ring
      if (caT) { clearInterval(caT); if (caT._a) clearInterval(caT._a); if (caT._b) clearInterval(caT._b); caT = null; }
      if (t1) { clearTimeout(t1); t1 = null; }
      if (t2) { clearInterval(t2); t2 = null; }
      if (!parts.length) { cleanup(); return; }
      var sv = parts[Math.floor(Math.random() * parts.length)];
      parts.forEach(function (p) {
        if (p === sv) return;
        endTimers.push(setTimeout(function () { p.el.style.transition = 'transform .3s ease, opacity .3s ease'; p.k = 0; put(p); p.el.style.opacity = '0'; }, Math.random() * 900));
      });
      sv.el.style.opacity = '1'; sv.el.style.transition = 'transform .06s linear';
      var bits = []; for (var i = 0; i < 16; i++) bits.push(lcg(caSt) < 0.5 ? 1 : 0);
      var phase = 0, tS = performance.now(), k0 = sv.k, x0 = sv.x, y0 = sv.y, tP = 0;
      endIv = setInterval(function () {
        var now = performance.now();
        if (phase === 0) {
          var nb = new Array(16), sum = 0;
          for (var i = 0; i < 16; i++) { nb[i] = (110 >> (bits[(i + 15) % 16] * 4 + bits[i] * 2 + bits[(i + 1) % 16])) & 1; sum += nb[i]; }
          if (sum === 0 || sum === 16) nb[Math.floor(lcg(caSt) * 16)] ^= 1; bits = nb;
          var f = Math.min(1, (now - tS) / 1600), e = f * f * (3 - 2 * f), wob = (1 - f) * 5;
          sv.k = k0 + (1 - k0) * e;
          sv.x = x0 * (1 - e) + (nb[0] + nb[5] + nb[10] - 1.5) * wob; sv.y = y0 * (1 - e) + (nb[2] + nb[7] + nb[12] - 1.5) * wob;
          if (f >= 1) { sv.k = 1; sv.x = 0; sv.y = 0; phase = 1; tP = now; }
          inDisc(sv); put(sv);
        } else if (phase === 1) {
          // the hole opens until only a ring of the stroke width is left, then the same ring turns smoothly black (no gap, no flash)
          var ringP = LW() > 0 ? Math.max(0, 100 * (1 - 2 * LW() / D0)) : 100;
          var h = Math.min(ringP, (now - tP) / 450 * 100);
          sv.el.style.background = 'radial-gradient(circle closest-side, transparent ' + h.toFixed(1) + '%, ' + col + ' ' + h.toFixed(1) + '%)';
          if (h >= ringP) {
            phase = 2; clearInterval(endIv); endIv = null;
            var el = sv.el;
            el.style.transition = 'none'; el.style.background = 'transparent'; el.style.borderWidth = LW() + 'px'; el.style.borderColor = col; el.style.transform = 'scale(1)';
            void el.offsetWidth;
            // colour fades to the resting stroke colour while the ring swells a hair and settles back
            el.style.transition = 'border-color .7s ease, transform .22s ease-out';
            el.style.borderColor = 'var(--kc, var(--fg))'; el.style.transform = 'scale(1.045)';
            endTimers.push(setTimeout(function () { el.style.transition = 'transform .5s cubic-bezier(.3,1.4,.5,1)'; el.style.transform = 'scale(1)'; }, 230));
            endTimers.push(setTimeout(function () { cleanup(); }, 800));
          }
        }
      }, 40);
    }
    c.addEventListener('pointerenter', startHover);
    it.addEventListener('click', function (e) {
      e.stopPropagation();
      if (sec.name === 'config') { solo(null); panel.scrollTo({ top: 0, behavior: 'smooth' }); return; }
      if (sec.name === 'perf') { perfOn = !perfOn; solo(perfOn ? perfSec : null); lastSync = 0; return; } // perf view: the 5 config stats and the button rows stay visible, the knob sections fold away (owner 21 Oct)
      // one click: only this section stays visible, smooth-scrolled so its header middle sits on the circle's middle
      solo(sec);
      var pR = panel.getBoundingClientRect(), cR = it.getBoundingClientRect(), hR = sec.hdr.getBoundingClientRect();
      var targetY = cR.top + cR.height / 2 - pR.top - hR.height / 2;
      panel.scrollTo({ top: panel.scrollTop + (hR.top - pR.top) - targetY, behavior: 'smooth' });
    });
  }
  // solo view: a section circle shows only its own section; the CONFIG circle brings everything back
  var soloSec = null, perfOn = false, statGeom = null;
  function solo(sec) {
    soloSec = sec || null;
    SECS.forEach(function (s2) {
      var on = !sec || s2 === sec;
      s2.hdr.style.display = on ? '' : 'none';
      s2.els.forEach(function (el) { el.style.display = on ? '' : 'none'; });
      if (s2.circ) s2.circ.style.opacity = sec && s2 !== sec ? '.35' : '1';
    });
  }
  // the topmost button is the CONFIG title: one click shows every section again, scrolled to the start
  addCirc({ name: 'config', hdr: panel.querySelector('h1'), els: [] });
  SECS.forEach(addCirc);
  // ---- colour swatches: knob-size circle switches in their own lane, one per colour. OFF is hollow (default colour),
  // ON fills with a random R/G/B and applies it; hover paints the circle black; the name shows briefly on every toggle. (owner 21 Oct)
  function hex2rgb(h) { return [parseInt(h.substr(1, 2), 16), parseInt(h.substr(3, 2), 16), parseInt(h.substr(5, 2), 16)]; }
  function syncBgFromP() { // owner 22 Oct: the saved/synced background colour wins over the local cycle
    if (P.swBg && P.bgColor && /^#[0-9a-fA-F]{6}$/.test(P.bgColor)) bgTarget = hex2rgb(P.bgColor);
  }
  var SW_HOME = { background: [SECS[1].hdr, SECS[0]], 'knob lines': [SECS[2].hdr, SECS[1]], 'section lines': [SECS[2].hdr, SECS[1]], 'button rings': [SECS[2].hdr, SECS[1]], 'axis lines': [SECS[2].hdr, SECS[1]], 'food dots': [gh, SECS[8]] };
  var SW_DEFS = [
    { label: 'background', on: 'swBg', set: function (c) { if (c) { bgTarget = hex2rgb(c); P.bgColor = c; touched.bgColor = 1; } else { bgIndex = 0; bgTarget = BGS[0]; P.bgColor = ''; touched.bgColor = 1; } }, get: function () { return '#' + bgTarget.map(function (v) { return ('0' + (v | 0).toString(16)).slice(-2); }).join(''); } },
    { label: 'knob lines', on: 'swLineColor', key: 'lineColor', dflt: '#111111' },
    { label: 'section lines', on: 'swRuleColor', key: 'ruleColor', dflt: '' },
    { label: 'button rings', on: 'swCircColor', key: 'circColor', dflt: '' },
    { label: 'axis lines', on: 'swAxisColor', key: 'axisColor', dflt: '' },
    { label: 'food dots', on: 'swFoodColor', key: 'foodColor', dflt: '#000000' }
  ];
  // the switches live in the panel, in the sections the colour pickers used to sit in (owner 21 Oct:
  // not a separate lane). Each is a knob-size circle: hollow while off (param at its default),
  // a click turns it on with a random red/green/blue, another click turns it off and restores the
  // default; hovering fills the circle black; the value beside the name flashes the new state.
  // true-colour ink: the panel blends (difference) under auto invert, which would lie about colours, so the
  // visible colour chips are plain fixed elements OUTSIDE the panel, synced over their anchors every layout -
  // the same pattern as the knob hover circles (owner 21 Oct: the picker and the preview show the real colour).
  var swInks = [];
  function swInkSync() {
    for (var i = 0; i < swInks.length; i++) {
      var it = swInks[i], r = it.anchor.getBoundingClientRect();
      it.el.style.left = r.left + 'px'; it.el.style.top = r.top + 'px'; it.el.style.width = r.width + 'px'; it.el.style.height = r.height + 'px';
      var panelOpen = panel.classList.contains('open') || panel.classList.contains('hov') || panel.matches(':hover');
      it.el.style.visibility = (panelOpen && r.width && r.right > 0 && r.left < window.innerWidth && r.bottom > 0 && r.top < window.innerHeight) ? 'visible' : 'hidden'; // closed panel: nothing config stays on screen, ever (owner 22 Oct)
    }
  }
  panel.addEventListener('scroll', swInkSync); window.addEventListener('resize', swInkSync); setInterval(swInkSync, 500);
  new MutationObserver(swInkSync).observe(panel, { attributes: true, attributeFilter: ['class'] });
  function mkInk(anchor) { var el = document.createElement('div'); el.className = 'swink'; document.body.appendChild(el); var it = { el: el, anchor: anchor }; swInks.push(it); return it; }
  SW_DEFS.forEach(function (def) {
    var row = document.createElement('div'); row.className = 'row';
    row.innerHTML = '<div class="lab"><span>' + def.label + '</span><b style="font-weight:normal;transition:opacity .3s"></b></div>';
    var c = document.createElement('div'); c.className = 'swc';
    row.appendChild(c);
    // free choice is back (owner 21 Oct): a hex field in the parameter row plus a native colour picker, both
    // synced with the circle switch; any custom pick turns the switch on and is saved into the preset.
    var hex = document.createElement('input'); hex.className = 'swhex'; hex.spellcheck = false; hex.autocomplete = 'off'; hex.maxLength = 6; hex.setAttribute('aria-label', def.label + ' hex');
    var pick = document.createElement('input'); pick.type = 'color'; pick.className = 'swpick'; pick.setAttribute('aria-label', def.label + ' picker');
    row.insertBefore(hex, c); row.appendChild(pick); // code flush-left on the circle's line (owner 22 Oct)
    var home = SW_HOME[def.label]; ctl.insertBefore(row, home[0]); home[1].els.push(row);
    var bv = row.querySelector('b'), hideT = null;
    var inkC = mkInk(c);
    function apply(col) { if (def.set) def.set(col); else { P[def.key] = col; touched[def.key] = 1; applyLineColor(); } }
    function cur() { return P[def.on] ? (def.get ? def.get() : P[def.key]) : null; }
    function paint() {
      var v = cur();
      inkC.el.style.background = v || 'transparent';
      if (v) { hex.value = v.slice(1); try { pick.value = v; } catch (e) {} } // the field shows the bare code, no # (owner 22 Oct)
      else hex.value = 'default'; // off: the field carries the state word, flush-left, so the circle never floats alone
    }
    function show(flash) {
      bv.textContent = ''; // nothing beside the name (owner 22 Oct: no code text above the button); the state word lives in the code field
      hex.classList.toggle('off', !P[def.on]);
      if (flash) { bv.style.opacity = '1'; clearTimeout(hideT); hideT = setTimeout(function () { bv.style.opacity = ''; }, 1400); }
    }
    function setFree(v) { // a valid #rrggbb from the hex field or the picker: switch on, apply, save (owner 21 Oct)
      P[def.on] = 1; touched[def.on] = 1;
      apply(v); paint(); show(true); save();
    }
    c.addEventListener('pointerenter', function () { inkC.el.style.background = '#000'; });
    c.addEventListener('pointerleave', function () { paint(); });
    c.addEventListener('click', function (e) { e.stopPropagation(); pick.click(); }); // the swatch opens the native picker, nothing else (owner 22 Oct)
    var hexDone = function () {
      var t = hex.value.trim(); if (t && t[0] !== '#') t = '#' + t;
      if (/^#[0-9a-fA-F]{3}$/.test(t)) t = '#' + t[1] + t[1] + t[2] + t[2] + t[3] + t[3]; // 3-char hex accepted (owner 22 Oct)
      if (/^#[0-9a-fA-F]{6}$/.test(t)) { setFree(t.toLowerCase()); return; }
      if (!t) { P[def.on] = 0; touched[def.on] = 1; apply(def.dflt === undefined ? null : def.dflt); paint(); show(true); save(); return; } // an emptied field = default colour (owner 22 Oct)
      paint();
    };
    hex.addEventListener('focus', function () { if (!P[def.on]) hex.value = ''; }); // typing starts clean over 'default'
    hex.addEventListener('keydown', function (e) { e.stopPropagation(); if (e.key === 'Enter') { hexDone(); hex.blur(); } });
    hex.addEventListener('blur', hexDone);
    pick.addEventListener('input', function () { setFree(pick.value); });
    paint(); show(false);
  });

  // depth of field on both screen edges, one design: opening the config pulls it in like a lens (edge layer first, small
  // overshoot, soft settle); with no pointer movement for focusIdleMs the same edge field also drifts in over focusInMs;
  // any movement snaps focus back over focusOutMs. Driven by CSS vars --bk1..4, no sliding, left and right alike.
  var lastMove = performance.now();
  ['mousemove', 'pointermove', 'mousedown', 'wheel', 'touchstart', 'touchmove', 'keydown'].forEach(function (n) { window.addEventListener(n, function () { lastMove = performance.now(); }, { passive: true }); });
  // in-canvas depth of field: same four progressive levels and masks as the CSS field, painted into the scene right
  // before the grain pass - the grain stays visible over the blur (owner 21 Oct: grain above everything). The CSS
  // field is the fallback for browsers without canvas filters.
  var dofOK = typeof CanvasRenderingContext2D !== 'undefined' && 'filter' in CanvasRenderingContext2D.prototype;
  var dofK = [0, 0, 0, 0]; window.__dofK = dofK;
  var dofCv = null, dofLay = null;
  function applyDof() {
    if (!dofOK || P.blurStrength <= 0 || P.blurWidth <= 0) return;
    var on = false, i;
    for (i = 0; i < 4; i++) if (dofK[i] > 0.004) on = true;
    if (!on) return;
    var bw = Math.min(P.blurWidth, W / 2), hs = 0.5; // half-res scratch: blur is a low-pass, the softness hides the scale
    var sw = Math.max(1, Math.ceil(bw * DPR * hs)), sh = Math.max(1, Math.ceil(H * DPR * hs));
    if (!dofCv) { dofCv = document.createElement('canvas'); dofLay = document.createElement('canvas'); }
    if (dofCv.width !== sw || dofCv.height !== sh) { dofCv.width = sw; dofCv.height = sh; dofLay.width = sw; dofLay.height = sh; }
    var MSK = [[0.55, 1], [0.35, 0.75], [0.15, 0.5], [0, 0.25]]; // the CSS mask stops: strongest at the screen edge
    for (var side = 0; side < 2; side++) {
      var sx = side === 0 ? W - bw : 0; // right strip first (the config side), then its left twin
      var c2 = dofCv.getContext('2d'), l2 = dofLay.getContext('2d');
      c2.setTransform(1, 0, 0, 1, 0, 0); c2.globalCompositeOperation = 'source-over'; c2.filter = 'none';
      c2.drawImage(cv, sx * DPR, 0, bw * DPR, H * DPR, 0, 0, sw, sh);
      for (i = 0; i < 4; i++) {
        var bl = P.blurStrength * (i + 1) / 4 * dofK[i] * DPR * hs;
        if (bl < 0.05) continue;
        l2.setTransform(1, 0, 0, 1, 0, 0); l2.globalCompositeOperation = 'source-over'; l2.clearRect(0, 0, sw, sh);
        l2.filter = 'blur(' + bl.toFixed(2) + 'px)';
        l2.drawImage(dofCv, 0, 0);
        l2.filter = 'none'; l2.globalCompositeOperation = 'destination-in';
        var gr = side === 0 ? l2.createLinearGradient(sw, 0, 0, 0) : l2.createLinearGradient(0, 0, sw, 0);
        gr.addColorStop(0, 'rgba(0,0,0,1)'); gr.addColorStop(MSK[i][0], 'rgba(0,0,0,1)'); gr.addColorStop(MSK[i][1], 'rgba(0,0,0,0)');
        l2.fillStyle = gr; l2.fillRect(0, 0, sw, sh);
        c2.drawImage(dofLay, 0, 0);
      }
      ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.drawImage(dofCv, 0, 0, sw, sh, sx * DPR, 0, bw * DPR, H * DPR);
      ctx.restore();
    }
  }
  (function () {
    var tab = document.getElementById('tab'), want = false, t0 = 0, from = [0, 0, 0, 0], cur = [0, 0, 0, 0], dur = 1900;
    var idleOn = false, iT0 = 0, iFrom = [0, 0, 0, 0], iCur = [0, 0, 0, 0];
    function openNow() { return panel.classList.contains('open') || panel.classList.contains('hov') || panel.matches(':hover') || tab.matches(':hover'); }
    function ease(x) { x = clamp(x, 0, 1); return 1 - Math.pow(1 - x, 3); }
    function easeIO(x) { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); }
    function focusCurve(x) { x = clamp(x, 0, 1); return ease(x) + Math.sin(x * Math.PI * 2.2) * 0.12 * (1 - x) * Math.min(1, x * 4); }
    window.__blurState = function () { return { cfg: cur.slice(), idle: iCur.slice(), idleOn: idleOn }; };
    function loop(now) {
      var o = openNow(); if (o !== want) { want = o; t0 = now; from = cur.slice(); }
      var ion = !o && now - lastMove >= P.focusIdleMs; if (ion !== idleOn) { idleOn = ion; iT0 = now; iFrom = iCur.slice(); }
      var el = now - t0, el2 = now - iT0, root = document.documentElement.style, depth = P.focusDepth / Math.max(1, P.blurStrength);
      for (var i = 0; i < 4; i++) {
        var delay = (3 - i) * 0.14 * dur / (want ? 1 : 2.5), x = (el - delay) / (want ? dur : dur * 0.55), tgt = want ? 1 : 0, v;
        if (want) v = from[i] + (tgt - from[i]) * focusCurve(x); else v = from[i] * (1 - ease(x));
        if (x <= 0) v = from[i];
        cur[i] = want ? clamp(v, 0, 1.2) : Math.max(0, v);
        var iD = idleOn ? P.focusInMs : P.focusOutMs, id = (3 - i) * 0.12 * iD * (idleOn ? 1 : 0.3), ix = (el2 - id) / iD, iv;
        if (idleOn) iv = iFrom[i] + (1 - iFrom[i]) * easeIO(ix); else iv = iFrom[i] * (1 - ease(ix));
        if (ix <= 0) iv = iFrom[i];
        iCur[i] = Math.max(0, iv);
        var kb = Math.max(cur[i], iCur[i] * depth);
        dofK[i] = dofOK ? kb : 0;
        root.setProperty('--bk' + (i + 1), dofOK ? '0' : kb.toFixed(3));
      }
      requestAnimationFrame(loop);
    }
    requestAnimationFrame(loop);
  })();
  var admCircles = []; // filled by the verified admin module: 4 stacked circles, same lane and size as the section circles
  var eadmEl = null; // the armed code-entry widget (set by the gate): an opening section title slides it down instead of overlapping it (owner 22 Oct)
  var circSig = '';
  function placeCircles() {
    var L = lay(), u = L.fs / 1000, R0 = 166.5 * u, D = 2 * R0;
    document.documentElement.style.setProperty('--sd', D.toFixed(2) + 'px');
    var sig = [D.toFixed(2), L.M, L.dh, LW(), P.panelWidth].join('|');
    if (sig === circSig) return; circSig = sig;
    var y0 = Math.max(4, L.M + L.dh - 500 * u - R0); // first circle centred on the title's topmost circle
    secc.style.top = y0 + 'px'; // body-level fixed lane: never rides the panel scroll
    panel.style.paddingRight = (L.M + D + L.M / 2) + 'px';
    for (var i = 0; i < secc.childNodes.length; i++) {
      var c = secc.childNodes[i].firstChild;
      c.style.width = D + 'px'; c.style.height = D + 'px';
      c.style.border = LW() + 'px solid var(--kc, var(--fg))';
      // no width pin on the label: the hover split shows full-width (owner 21 Oct)
    }
    for (var j = 0; j < admCircles.length; j++) {
      if (admCircles[j].ownerDocument !== document) continue; // preview host owns adopted widget geometry
      admCircles[j].style.width = D + 'px'; admCircles[j].style.height = D + 'px';
      admCircles[j].style.border = LW() + 'px solid var(--kc, var(--fg))';
      admCircles[j].style.fontSize = '13px';
    }
  }
  document.documentElement.style.setProperty('--m', P.margin + 'px');
  document.documentElement.style.setProperty('--rg', P.panelRowGap + 'px');
  placeCircles(); applyLW(); applyLineColor(); applyTypo();
  panel.addEventListener('click', function (e) { e.stopPropagation(); });
  var lastSync = 0;

  // ---- display mode: 'd' desktop / 'm' mobile. An explicit admin choice (B/D buttons) wins;
  // otherwise the window width decides - a narrowed desktop window previews the mobile mode and its preset.
  // The mobile lane consumes this through window.__ca2Mode() / the 'ca2mode' event / body[data-camode].
  var MODE_BREAK = 820, modeSel = null, modeCur = '';
  // a phone turned sideways (or the device.html frame, which passes ?mobile=1) is still a phone: width alone must not flip it to the desktop layout when the landscape width passes the break (iphone 15 landscape = 852 > 820)
  var PHONE_HW = (/[?&]mobile=1/.test(location.search)) || !!(window.matchMedia && matchMedia('(hover: none) and (pointer: coarse)').matches);
  function modeEff() { return modeSel || ((PHONE_HW || window.innerWidth <= MODE_BREAK) ? 'm' : 'd'); }
  function modePub() {
    var m = modeEff(); if (m === modeCur) return;
    if (modeCur) { try { save(); } catch (e) {} STORE = (m === 'm') ? STORE_M : STORE_D; } // leave the old mode's record as it is, continue in the new mode's own record
    modeCur = m;
    document.body.dataset.camode = m;
    try { window.dispatchEvent(new CustomEvent('ca2mode', { detail: { mode: m, sel: modeSel, width: window.innerWidth } })); } catch (e) {}
  }
  window.__ca2Mode = modeEff;
  window.__ca2ModeSel = function () { return modeSel; };
  window.addEventListener('resize', modePub);
  modePub();

  // ---- global presets (Cloudflare Worker + D1): the public read path. Every visitor pulls the shared
  // preset and re-applies their not-yet-accepted edits on top. Admin writes live in the admin module,
  // which the Worker serves only after code verification (owner 21 Oct).
  (function presetSync() {
    var WK = 'https://ca2-presets.middots.workers.dev/', lastV = 0, GK = 'ca2.global';
    function applyG(g) {
      if (!g || typeof g !== 'object') return false; var n = 0;
      var pnd = {}; try { if (pendingOk()) pnd = JSON.parse(localStorage.getItem('ca2.pending') || '{}'); } catch (e) {}
      Object.keys(g).forEach(function (k) { if (k === '_v' || k === '_live' || !(k in P) || k in pnd) return; var v = g[k]; if (typeof v === typeof P[k] && (typeof v !== 'number' || isFinite(v)) && P[k] !== v) { P[k] = v; n++; } });
      var gl = typeof g._live === 'string' ? (function () { try { return JSON.parse(g._live); } catch (e) { return null; } })() : (g._live && typeof g._live === 'object' ? g._live : null);
      if (gl) {
        Object.keys(gl).forEach(function (k) { if (!live[k] && keyToQ[k] && rows[k] && typeof gl[k] === 'number' && isFinite(gl[k])) { liveStart(k, keyToQ[k], gl[k], rows[k].row); n++; } });
        Object.keys(live).forEach(function (k) { if (!(k in gl)) { liveStop(k); n++; } });
      }
      if (n && P.foodEatR <= 1) P.foodEatR = Math.round(P.foodEatR * DEFAULTS.CELL_RADIUS * 100) / 100;
      if (n) { syncBgFromP(); applyLineColor(); } // pulled colours must reach the CSS vars and the background, not only P
      return n;
    }
    function pullG(first) {
      fetch(WK + '?t=' + Date.now(), { cache: 'no-store' }).then(function (r) { return r.json(); }).then(function (g) {
        if (!g || !g._v || g._v === lastV) return; lastV = g._v;
        try { localStorage.setItem(GK, JSON.stringify(g)); } catch (e) {}
        if (window.__adminOn) return;
        if (applyG(g)) { lastSync = 0; syncUI(0); }
      }).catch(function () {});
    }
    try { var cg = JSON.parse(localStorage.getItem(GK) || 'null'); if (cg) { applyG(cg); lastV = cg._v || 0; } } catch (e) {}
    // edits not yet accepted by the server stay ahead of the (older) global on reload
    try { var pd0 = pendingOk() ? JSON.parse(localStorage.getItem('ca2.pending') || '{}') : {}; Object.keys(pd0).forEach(function (k) { if (k !== '_live' && k in P && typeof pd0[k] === typeof P[k]) { P[k] = pd0[k]; touched[k] = 1; } }); syncBgFromP(); } catch (e) {}
    pullG(true); setInterval(pullG, 15000);
  })();
  // capability hooks the server-verified admin module builds on (owner 21 Oct): handles only - no admin UI,
  // strings or logic ships publicly; everything user-visible comes down after the Worker verifies the code.
  window.__ca2x = {
    admCircles: admCircles, hookHov: hookHov,
    rePlace: function () { circSig = ''; placeCircles(); },
    modeSel: function () { return modeSel; }, modeSet: function (v) { modeSel = v; modePub(); },
    save: save, get STORE() { return STORE; }, STORE_V: STORE_V,
    touched: touched, liveMap: liveMap, btns: btns, panel: panel
  };
  // ---- entry gate (owner 22 Oct: restore the original design - the code entry is the 4-circle column
  // widget, never a bottom field). Zero admin trace ships publicly: a 5s hold on the title dots reveals 4
  // hollow circles stacked on the section-circle axis, typed digits fill them top to bottom, and the real
  // input stays invisible (it only catches keys). A verified answer carries the admin module itself.
  (function gate() {
    var WK = 'https://ca2-presets.middots.workers.dev/';
    var eg = document.createElement('div'); eg.id = 'eadm'; eadmEl = eg;
    var glyphs = [], acs = [];
    for (var ai = 0; ai < 4; ai++) { var ac = document.createElement('div'); ac.className = 'ac'; var ag = document.createElement('span'); ac.appendChild(ag); eg.appendChild(ac); admCircles.push(ac); glyphs.push(ag); acs.push(ac); }
    document.body.appendChild(eg);
    var box = document.createElement('input'); box.type = 'text'; box.maxLength = 4; box.setAttribute('inputmode', 'numeric'); box.autocomplete = 'off'; box.spellcheck = false; box.tabIndex = -1; box.setAttribute('aria-hidden', 'true');
    box.style.cssText = 'position:fixed;left:-200px;top:0;width:20px;height:20px;opacity:0;border:0;padding:0;outline:none';
    document.body.appendChild(box);
    circSig = ''; placeCircles(); // the 4 entry circles size with the section circles
    var armT = 0, holdIv = null, holdT0 = 0, px = 0, py = 0;
    var dotHit = function (x, y) { for (var i = 0; i < circlesNow.length; i++) { var c = circlesNow[i]; if (/^R0_/.test(c.key) && Math.hypot(x - c.x, y - c.y) < c.r) return true; } return false; };
    var clearGlyphs = function () { for (var i = 0; i < 4; i++) glyphs[i].textContent = ''; };
    // the blinking caret lives on the circle that takes the next digit, only while the hidden input really has focus (owner 22 Oct)
    var updateCur = function () { var on = armT && document.activeElement === box; for (var i = 0; i < 4; i++) { if (on && i === box.value.length) acs[i].classList.add('cur'); else acs[i].classList.remove('cur'); } };
    var disarm = function () { armT = 0; box.value = ''; clearGlyphs(); eg.classList.remove('on'); eg.classList.remove('err'); box.blur(); updateCur(); };
    var arm = function () { if (window.__adminOn) return; armT = Date.now(); box.value = ''; clearGlyphs(); eg.classList.remove('err'); eg.classList.add('on'); box.focus(); updateCur(); }; // programmatic focus is not a gesture on phones - a tap on the circles re-focuses
    var holdStop = function () { if (holdIv) { clearInterval(holdIv); holdIv = null; } };
    window.addEventListener('pointermove', function (e) { px = e.clientX; py = e.clientY; }, { passive: true });
    window.addEventListener('pointerdown', function (e) {
      holdStop(); px = e.clientX; py = e.clientY;
      if (armT && eg.classList.contains('on')) { var r = eg.getBoundingClientRect(); if (px >= r.left && px <= r.right && py >= r.top && py <= r.bottom) { e.preventDefault(); armT = Date.now(); box.focus(); updateCur(); return; } } // a tap back on the circles is activity: the 20s idle disarm restarts
      if (!dotHit(px, py)) return;
      holdT0 = performance.now();
      holdIv = setInterval(function () {
        if (!dotHit(px, py)) { holdStop(); return; }
        if (performance.now() - holdT0 < 5000) return;
        holdStop(); arm();
      }, 100);
    });
    window.addEventListener('pointerup', function (e) {
      if (!holdIv) return;
      holdStop();
      if (performance.now() - holdT0 >= 5000 && dotHit(e.clientX, e.clientY)) arm();
    });
    window.addEventListener('pointercancel', holdStop);
    eg.addEventListener('click', function () { box.focus(); });
    // an iOS long-press menu would cancel the 5s hold
    document.addEventListener('contextmenu', function (e) { if ((window.__ca2Mode ? window.__ca2Mode() : 'd') === 'm') e.preventDefault(); }, true);
    var verify = function (code) {
      fetch(WK, { method: 'POST', keepalive: true, body: JSON.stringify({ code: code, admin: true }) }).then(function (r) { return r.json(); }).then(function (r) {
        if (r && r.ok && typeof r.js === 'string') {
          disarm(); // the Worker-served module takes over the column with its own A B D U
          try { (new Function('code', 'X', r.js))(code, window.__ca2x); } catch (e) {}
        } else {
          eg.classList.add('err'); box.value = ''; setTimeout(function () { eg.classList.remove('err'); clearGlyphs(); }, 600);
        }
      }).catch(function () { box.value = ''; clearGlyphs(); });
    };
    box.addEventListener('input', function () {
      if (!armT) { box.value = ''; return; }
      box.value = box.value.replace(/\D/g, '').slice(0, 4);
      for (var i = 0; i < 4; i++) glyphs[i].textContent = box.value[i] || '';
      updateCur();
      if (box.value.length < 4) { if (Date.now() - armT > 20000) disarm(); return; }
      var code = box.value; armT = Date.now(); verify(code);
    });
    // programmatic entry for the device.html preview handoff: the frame cannot 5s-hold itself, so the
    // wrapper page hands an entered code in through this event (no admin surface either way)
    window.addEventListener('ca2code', function (e) { var c = e && e.detail && String(e.detail.code || ''); if (!/^\d{4}$/.test(c)) return; disarm(); verify(c); });
    box.addEventListener('keydown', function (e) { e.stopPropagation(); });
    box.addEventListener('focus', updateCur); box.addEventListener('blur', updateCur);
  })();
  function syncUI(total) {
    placeCircles();
    var now = performance.now(); if (now - lastSync < 300) return; lastSync = now;
    statsEl.innerHTML = '<span>Cells</span><span class="n">' + total.toFixed(2) + '</span><span>Universe</span><span class="n">' + P.UNIVERSE_SIZE.toFixed(2) + '</span><span>Refresh S</span><span class="n">' + Math.max(0, refreshInterval - (now - lastRefresh) / 1000).toFixed(2) + '</span><span>FPS</span><span class="n">' + fps.toFixed(2) + '</span><span>Res</span><span class="n">' + (res * 100).toFixed(2) + '</span>';
    if (perfOn) { // the perf circle appends its rows under the config stats - no solo, nothing above moves (owner 21 Oct)
      var pf1 = function (k) { return PF[k] === undefined ? '...' : PF[k].toFixed(2); };
      statsEl.innerHTML += '<span>Frame</span><span class="n">' + frameMs.toFixed(2) + '</span><span>Setup</span><span class="n">' + pf1('setup') + '</span><span>Sim UI</span><span class="n">' + pf1('sim+ui draw') + '</span><span>Grain Rest</span><span class="n">' + pf1('grain+rest') + '</span><span>GPU: Draw+Field</span><span class="n">' + pf1('gpu:draw+field') + '</span><span>GPU: Draw Image</span><span class="n">' + pf1('gpu:drawImage') + '</span>';
    }
    // fixed geometry: the label column and every value field are pinned (probed once per font) and the fit only measures the base rows, so a changing value or the perf toggle never moves a row
    statsEl.style.fontSize = ''; statsEl.style.gridTemplateColumns = '';
    var ns2 = statsEl.querySelectorAll('.n'), ni2;
    for (ni2 = 0; ni2 < ns2.length; ni2++) { ns2[ni2].style.fontSize = ''; ns2[ni2].style.width = ''; }
    var labFs0 = parseFloat(getComputedStyle(statsEl).fontSize) || 13, valFs0 = ns2.length ? parseFloat(getComputedStyle(ns2[0]).fontSize) || 54 : 54;
    if (!statGeom || statGeom.key !== labFs0 + '|' + getComputedStyle(statsEl).fontFamily) {
      statGeom = { key: labFs0 + '|' + getComputedStyle(statsEl).fontFamily, labEm: 0, baseLabEm: 0, valEm: 0, rowW0: 0 };
      var prb = document.createElement('div'); prb.className = 'stats'; prb.style.cssText = 'position:absolute;visibility:hidden;left:-9999px;top:0'; document.body.appendChild(prb);
      var lbls = ['Cells', 'Universe', 'Refresh S', 'FPS', 'Res'], plbls = ['Frame', 'Setup', 'Sim UI', 'Grain Rest', 'GPU: Draw+Field', 'GPU: Draw Image'], wMax = 0, wBase = 0;
      for (var pi2 = 0; pi2 < lbls.length; pi2++) { var ps = document.createElement('span'); ps.textContent = lbls[pi2]; prb.appendChild(ps); wMax = Math.max(wMax, ps.getBoundingClientRect().width); prb.removeChild(ps); }
      wBase = wMax;
      for (var pi3 = 0; pi3 < plbls.length; pi3++) { var ps2 = document.createElement('span'); ps2.textContent = plbls[pi3]; prb.appendChild(ps2); wMax = Math.max(wMax, ps2.getBoundingClientRect().width); prb.removeChild(ps2); }
      var pv = document.createElement('span'); pv.className = 'n'; pv.textContent = '999.99'; prb.appendChild(pv);
      statGeom.labEm = wBase / labFs0; statGeom.valEm = pv.getBoundingClientRect().width / valFs0;
      statGeom.rowW0 = wBase + 12 + pv.getBoundingClientRect().width; // base row width at default fonts - the fit ignores the perf rows on purpose
      document.body.removeChild(prb);
    }
    var cW = statsEl.clientWidth, fit = 1;
    if (cW > 0 && statGeom.rowW0 > cW) fit = (cW - 12) / Math.max(1, statGeom.rowW0 - 12);
    var labPx = Math.max(7, Math.floor(labFs0 * fit * 10) / 10), valPx = Math.max(12, Math.floor(valFs0 * fit));
    if (fit < 1) { statsEl.style.fontSize = labPx + 'px'; for (ni2 = 0; ni2 < ns2.length; ni2++) ns2[ni2].style.fontSize = valPx + 'px'; }
    statsEl.style.gridTemplateColumns = (statGeom.labEm * labPx) + 'px 1fr';
    for (ni2 = 0; ni2 < ns2.length; ni2++) ns2[ni2].style.width = (statGeom.valEm * valPx) + 'px';
    // perf labels longer than the pinned label column shrink individually; base rows keep their font
    var ls2 = statsEl.querySelectorAll('span:nth-child(odd)');
    for (ni2 = 0; ni2 < ls2.length; ni2++) { var lsp = ls2[ni2]; lsp.style.fontSize = ''; var nat = lsp.scrollWidth, box = lsp.clientWidth; if (ni2 >= 5 && box > 0 && nat > box + 1) lsp.style.fontSize = Math.max(7, Math.floor(labPx * box / nat * 10) / 10) + 'px'; }
    for (var lk in live) { var lr = rows[lk]; lr.inp.value = P[lk]; lr.val.textContent = fmt(P[lk]); }
    if (panel.matches(':hover')) return;
    GROUPS.forEach(function (g) { g[1].forEach(function (q) { var r = rows[q[0]], v = P[q[0]]; r.inp.value = v; r.val.textContent = fmt(v); }); });
  }

  // ---- loop / events ----
  function resizeCanvas() {
    DPR = P.pixelRatio > 0 ? P.pixelRatio : Math.min(window.devicePixelRatio || 1, 3); W = window.innerWidth; H = window.innerHeight;
    window.__ca2DPR = DPR; // mobile lane: the phone frame reads the real dpr so thin lines stay crisp
    cv.width = Math.round(W * DPR); cv.height = Math.round(H * DPR);
    DD = Math.min(window.devicePixelRatio || 1, 3); lnc.width = Math.round(W * DD); lnc.height = Math.round(H * DD); applyLW();
    // CSS size in real px, not 100vw/100vh: on iOS 100vh is the no-URL-bar height, so the bitmap got stretched and taps landed off
    var rt = document.documentElement.style; rt.setProperty('--vw', W + 'px'); rt.setProperty('--vh', H + 'px');
  }
  function resize() {
    resizeCanvas();
    VS = Math.min(W / 1280, H / 800);
    if (!cont.tw) { setTargets(); cont.ew = cont.tw; cont.eh = cont.th; } // first layout: deal the opening plate
    else clampTargets(); // later resizes keep the current universe and plate; the plate only re-fits into the new safe band, eased by the frame loop
  }
  // a viewport change (rotation, window drag, browser chrome collapsing while scrolling) re-fits the world; it must not
  // wipe it or deal a new random plate - that read as the whole page slipping mid-scroll (owner 20 Oct)
  window.addEventListener('resize', function () { resize(); });
  if (window.visualViewport) window.visualViewport.addEventListener('resize', function () { if (Math.abs(window.innerWidth - W) > 1 || Math.abs(window.innerHeight - H) > 1) resize(); });
  window.addEventListener('mousemove', function (e) { mouse.x = e.clientX; mouse.y = e.clientY; mouse.over = (e.target === cv); if (curEl.style.display === 'block') curEl.style.transform = 'translate(' + (mouse.x - curRRnow) + 'px,' + (mouse.y - curRRnow) + 'px)'; });
  document.addEventListener('mouseleave', function () { mouse.over = false; curEl.style.display = 'none'; curEdge.style.display = 'none'; });
  window.addEventListener('click', onClick);
  // grab the plate border with the mouse and pull to resize it (symmetric around the centre); cells get restless while dragging
  var resizeDrag = null;
  function edgeHit(x, y, tol) {
    var k = cont; tol = tol || P.edgeGrab; var inX = x > k.x - tol && x < k.x + k.w + tol, inY = y > k.y - tol && y < k.y + k.h + tol, h = 0, v = 0;
    if (inY && (Math.abs(x - k.x) < tol || Math.abs(x - (k.x + k.w)) < tol)) h = 1;
    if (inX && (Math.abs(y - k.y) < tol || Math.abs(y - (k.y + k.h)) < tol)) v = 1;
    return (h || v) ? { h: h, v: v } : null;
  }
  window.addEventListener('mousedown', function (e) {
    if (e.target !== cv) return;
    var hit = edgeHit(e.clientX, e.clientY);
    if (hit) { hit.rx = e.clientX >= W / 2; hit.dy = e.clientY >= H / 2; resizeDrag = hit; e.preventDefault(); return; }
    targetCursorScale = 3.5, cursorScale = 3.5;
  });
  window.addEventListener('mousemove', function (e) {
    if (!resizeDrag) return;
    cont.user = true;
    if (resizeDrag.h) cont.rawW = Math.max(60, 2 * Math.abs(e.clientX - W / 2));
    if (resizeDrag.v) cont.rawH = Math.max(60, 2 * Math.abs(e.clientY - H / 2));
    clampTargets(); // no ew=tw snap: frame() eases toward the target over wallSmoothMs (owner 25 Oct, finding 1: teleporting wall)
  });
  window.addEventListener('mouseup', function () { targetCursorScale = 1; resizeDrag = null; });  // A + drag spray: continuous spawns along the held-drag trail, paced by preset knobs (owner 21 Oct). spawnAt stays the single spawn path (click / spray / mobile touch)
  var sprayOn = false, sprayMoved = false, sprayT = 0, sprayX = 0, sprayY = 0, spraySrc = '', sprayLX = 0, sprayLY = 0; // sprayLX/LY: last SPAWN point - the gap measures distance since the last birth, not since the last event
  window.addEventListener('mousedown', function (e) { if (e.target === cv && !edgeHit(e.clientX, e.clientY)) { sprayOn = true; sprayMoved = false; sprayT = performance.now(); spraySrc = 'm'; sprayX = sprayLX = e.clientX; sprayY = sprayLY = e.clientY; } });
  window.addEventListener('mousemove', function (e) {
    if (!sprayOn) return;
    sprayX = e.clientX; sprayY = e.clientY; // the waves chase the pointer
    if (keyHeld !== 'a') return;
    var t = performance.now();
    if (t - sprayT >= P.sprayMs && Math.hypot(e.clientX - sprayLX, e.clientY - sprayLY) >= P.sprayGapPx) { sprayT = t; sprayMoved = true; sprayLX = e.clientX; sprayLY = e.clientY; spawnAt(sprayX, sprayY); } // extra density along a fast drag
  });
  var sprayWaveN = 0;
  function sprayWave() { // the gush: waves of births while the press is held, even standing still (owner 21 Oct); runs on the frame loop so a throttled timer can never starve it
    if (!sprayOn) return;
    if (spraySrc === 'm' && keyHeld !== 'a') return;
    var st = performance.now(); if (st - sprayT < P.sprayMs) return;
    sprayT = st; sprayMoved = true; sprayWaveN++;
    for (var w = 0; w < Math.max(1, P.sprayBurst); w++) { // births scatter inside the spray disc; spawnAt still refuses overlaps
      var sa = Math.random() * Math.PI * 2, sr = Math.sqrt(Math.random()) * P.sprayRadius;
      spawnAt(sprayX + Math.cos(sa) * sr, sprayY + Math.sin(sa) * sr);
    }
  }
  window.addEventListener('mouseup', function () { sprayOn = false; });

  window.addEventListener('keydown', function (e) { keyHeld = e.key.toLowerCase(); if (keyHeld === 'c') panel.classList.toggle('open'); });
  window.addEventListener('keyup', function () { keyHeld = ''; });
  ['pointerdown', 'pointerup', 'pointermove', 'mousemove', 'mousedown', 'wheel', 'scroll', 'touchstart', 'keydown', 'touchend', 'click'].forEach(function (n) { window.addEventListener(n, function () { if (window.CA2Audio && P.audioOn) CA2Audio.start(); }, { passive: true }); });
  window.addEventListener('touchstart', function (e) {
    var t = e.touches[0]; mouse.x = t.clientX; mouse.y = t.clientY; mouse.over = (e.target === cv);
    if (e.target !== cv) return;
    var hit = edgeHit(t.clientX, t.clientY, P.edgeGrab * 1.5);
    if (hit) { hit.rx = t.clientX >= W / 2; hit.dy = t.clientY >= H / 2; resizeDrag = hit; e.preventDefault(); return; }
    // no edge drag: arm the touch counterpart of the A+drag spray - hold + drag sprays through the same spawnAt,
    // paced by the same sprayMs/sprayGapPx knobs (lane agreement 21 Oct); a tap stays a tap until a spray lands
    sprayOn = true; sprayMoved = false; sprayT = performance.now(); spraySrc = 't'; sprayX = sprayLX = t.clientX; sprayY = sprayLY = t.clientY;
    targetCursorScale = 3.5; cursorScale = 3.5;
  }, { passive: false });
  window.addEventListener('touchmove', function (e) {
    var t = e.touches[0]; mouse.x = t.clientX; mouse.y = t.clientY;
    if (!resizeDrag && sprayOn) {
      sprayX = t.clientX; sprayY = t.clientY; // the waves chase the finger
      var st = performance.now();
      if (st - sprayT >= P.sprayMs && Math.hypot(t.clientX - sprayLX, t.clientY - sprayLY) >= P.sprayGapPx) { sprayT = st; sprayMoved = true; sprayLX = t.clientX; sprayLY = t.clientY; spawnAt(sprayX, sprayY); } // same gap pacing as the mouse arm (parity, 22 Oct)
    }
    if (!resizeDrag) return;
    cont.user = true;
    if (resizeDrag.h) cont.rawW = Math.max(60, 2 * Math.abs(t.clientX - W / 2));
    if (resizeDrag.v) cont.rawH = Math.max(60, 2 * Math.abs(t.clientY - H / 2));
    clampTargets(); // no ew=tw snap: frame() eases toward the target over wallSmoothMs (owner 25 Oct, finding 1: teleporting wall)
  }, { passive: true });
  window.addEventListener('touchend', function () { targetCursorScale = 1; resizeDrag = null; mouse.over = false; sprayOn = false; }, { passive: true });
  window.addEventListener('touchcancel', function () { targetCursorScale = 1; resizeDrag = null; mouse.over = false; sprayOn = false; }, { passive: true });

  var last = performance.now(), fcount = 0, ftime = last;
  var rdySet = false;
  function loop(now) {
    requestAnimationFrame(loop);
    if (!ready) return;
    if (now - last < 1000 / P.fps - 1) return;
    last = now; frame(); sprayWave(); fcount++;
    if (!rdySet) { rdySet = true; document.body.classList.add('rdy'); } // first real frame is on the canvas: reveal (boot FOUC gate)
    if (now - ftime >= 1000) { fps = fcount * 1000 / (now - ftime); fcount = 0; ftime = now; }
  }
  res = P.resolution;
  (document.fonts && document.fonts.load ? document.fonts.load('40px "Ca2-Thin"') : Promise.resolve()).catch(function () {}).then(function () {
    resize(); randomize(true, true); firstSpawn = false; fadeT0 = performance.now(); ready = true; setTimeout(function () { if (window.CA2Audio && P.audioOn) CA2Audio.start(); }, INTRO_MS + 2000); requestAnimationFrame(loop);
  });
  document.getElementById('tab').addEventListener('click', function () { panel.classList.toggle('open'); });
  var keysEl0 = document.querySelector('#panel .keys'); if (coarseUI && keysEl0) keysEl0.innerHTML = '<div><span>tap</span><span>add a cell</span></div><div><span>hold + drag</span><span>spray cells</span></div><div><span>edge drag</span><span>resize plate</span></div><div><span>tab strip</span><span>this panel</span></div>';
  if (/open/.test(location.hash)) panel.classList.add('open');
  // reveal: panel blocks fade in fast; every part of a parameter row (label, value, slider/knob, swatch, button) has its own short fade and its own random delay
  function partIn(el, base) { el.style.animation = 'ca2in ' + (0.16 + Math.random() * 0.2).toFixed(2) + 's ease-out both'; el.style.animationDelay = (base + Math.random() * 0.14).toFixed(3) + 's'; }
  [].forEach.call(panel.children, function (el) { if (el.id !== 'controls') partIn(el, Math.random() * 0.25); });
  [].forEach.call(document.querySelectorAll('#controls .row'), function (el, ri) {
    var base = Math.min(ri, 14) * 0.02, ps = el.querySelectorAll('.lab > span, .lab > b, input:not(.swpick), button, select');
    if (!ps.length) { partIn(el, base); return; }
    [].forEach.call(ps, function (p) { partIn(p, base); });
  });
})();

// ==== mobile lane: mobile preset layer + phone-frame support (lane agreement: new code only in this trailing IIFE) ====
// Owner 21 Oct: mobile needs its own presets - the desktop profile does not fit. Effective mobile config =
// desktop profile (built-in + Worker global) overridden by MOBILE_SEED, itself overridden by the Worker global's _mobile.
// In mobile mode an admin Save is rerouted (fetch wrap below) into the global's _mobile object, sent whole every time
// because the Worker merges patches shallowly. Desktop keys are never touched by this IIFE.
(function () {
  'use strict';
  var MOBILE_SEED = { CELL_RADIUS: 24, minRadius: 15, maxRadius: 60, edgeGrab: 30, panelWidth: 320, blurWidth: 260, foodEatR: 7 };
  var AUTO_W = 820; // an unselected window this narrow or smaller runs mobile mode (matches the UI lane's breakpoint)
  var MODE_Q = /[?&]mobile=1/.test(location.search); // the device.html phone frame forces mobile mode with this
  var coarse = window.matchMedia && matchMedia('(hover: none) and (pointer: coarse)').matches;
  // the device.html frame passes the phone's dpr as &dpr=; overriding devicePixelRatio makes the line canvas (DD) and every dpr consumer render hairlines like the real phone
  if (MODE_Q) {
    var dprQ = parseFloat((location.search.match(/[?&]dpr=([0-9.]+)/) || [])[1]);
    if (dprQ >= 1 && dprQ <= 4) try { Object.defineProperty(window, 'devicePixelRatio', { configurable: true, get: function () { return dprQ; } }); } catch (e) {}
  }
  function boot() {
    if (!window.__ca2 || !window.__ca2.P) { setTimeout(boot, 100); return; } // __ca2 appears with the first frame
    var P = window.__ca2.P, panel = document.getElementById('panel'), blurEl = document.getElementById('blur'), blurLEl = document.getElementById('blurl');
    var mode = null, lastMob = null, seenV = 0, applying = false, lane = false;
    var lsSel = (function () { var ls = ''; try { ls = localStorage.getItem('ca2.mode') || ''; } catch (e) {} return (ls === 'mobile' || ls === 'm') ? 'm' : (ls === 'desktop' || ls === 'd') ? 'd' : null; })();
    // an in-flight plate transition can keep lerping CELL_RADIUS toward a target dealt under the desktop bounds
    // (~230 measured) for seconds after the switch to mobile; clamp every write while the mobile layer is active
    var crHold = P.CELL_RADIUS;
    try {
      Object.defineProperty(P, 'CELL_RADIUS', {
        configurable: true, enumerable: true,
        get: function () { return crHold; },
        set: function (v) {
          // clamp only an in-flight transition lerp (owner 21 Oct: manual entry takes any valid number - no hidden
          // ceiling on hand-entered values; the transition guard was the original intent, not an entry cap)
          var lerp = window.__ca2 && window.__ca2.live && window.__ca2.live.CELL_RADIUS;
          if (mode === 'm' && lerp && typeof v === 'number' && isFinite(v)) {
            var lo = P.minRadius, hi = P.maxRadius;
            if (typeof lo === 'number' && typeof hi === 'number' && hi >= lo) v = Math.min(hi, Math.max(lo, v));
          }
          crHold = v;
        }
      });
    } catch (e) {}
    function storedG() { try { return JSON.parse(localStorage.getItem('ca2.global') || 'null'); } catch (e) { return null; } }
    function mobOf(g) { // _mobile may be an object (seeded) or a JSON string (Worker-posted); both parse to the same overrides
      var m = g && g._mobile; if (typeof m === 'string') { try { m = JSON.parse(m); } catch (e) { m = null; } }
      return (m && typeof m === 'object') ? JSON.parse(JSON.stringify(m)) : {};
    }
    function detect() {
      if (window.__ca2Mode) return window.__ca2Mode(); // the UI lane owns mode state whenever its module is present
      if (lsSel) return lsSel;
      return (coarse || MODE_Q || window.innerWidth <= AUTO_W) ? 'm' : 'd';
    }
    function layerKeys() {
      var g = storedG() || {}, o = {}, mb = mobOf(g);
      Object.keys(MOBILE_SEED).forEach(function (k) { o[k] = 1; });
      Object.keys(mb).forEach(function (k) { o[k] = 1; });
      // radius bounds must land before CELL_RADIUS so the clamp uses the new range
      return Object.keys(o).sort(function (a, b) { return (a === 'minRadius' || a === 'maxRadius' ? -1 : 0) - (b === 'minRadius' || b === 'maxRadius' ? -1 : 0); });
    }
    function applyMode() {
      var g = storedG() || {}, mob = (mode === 'm');
      var mb2 = mobOf(g);
      layerKeys().forEach(function (k) {
        var v;
        if (mob) v = (mb2[k] !== undefined) ? mb2[k] : MOBILE_SEED[k];
        else v = (g[k] !== undefined) ? g[k] : MOBILE_SEED[k]; // no desktop source offline: keep the seed value
        if (mob && profActive() === 'L') { var lmz = landMap(); if (lmz[k] !== undefined) v = lmz[k]; } // the LANDSCAPE mirror wins over the portrait layer (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02)
        if (v === undefined) return;
        // device-profile default, NOT a user edit: seedKey. setKey would mark the key touched and pin it against
        // the bounded morph deal forever (CR never moved on mobile / small viewports - measured tg.cr frozen at the seed).
        if (k === 'CELL_RADIUS' && (v < P.minRadius || v > Math.max(P.minRadius, P.maxRadius))) v = Math.min(Math.max(v, P.minRadius), Math.max(P.minRadius, P.maxRadius));
        window.__ca2.seedKey(k, v);
      });
      applying = true; try { window.dispatchEvent(new Event('resize')); } finally { applying = false; } // re-fit the world + re-derive line widths
    }
    // owner 21 Oct: on mobile the plate is dealt from a 1280x800 landscape reference scaled by window WIDTH, so it
    // squats and wastes the vertical band. Mirror the desktop deal rotated 90 degrees: portrait reference 800x1280,
    // axes swapped (the tall reference side deals the height, the short one the width), clamped by the same safe band.
    var dealW = 0, dealH = 0, dealHist = [];
    // owner 21 Oct: mobile size band - the boundary may narrow at most to a third of the screen width and may widen
    // until a gap of margin + the section button size remains on each side (the buttons are circles, so the size is the diameter, read live from --sd). Both axes, automatic deals AND manual
    // pulls alike (owner 21 Oct: manual pulls and height included).
    function bandGap() { var sd = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--sd')) || 0; return (P.margin || 0) + sd; }
    function bandW() { var g = bandGap(); return { lo: window.innerWidth / 3, hi: window.innerWidth - 2 * g }; }
    function bandH() { var g = bandGap(); return { hi: window.innerHeight - 2 * g }; }
    function dealPortrait() {
      var c = window.__ca2.cont; if (!c || c.user) return; // a hand-pulled size is the owner's, never override it
      // deal against the band itself: probe the height clamp ceiling, then deal the desktop's own ratios of the band.
      // Desktop height deals run 2160/8 .. 5120/7.5 = 270..731 against a ~580 ceiling (0.47..1.26x), so top deals fill
      // the band; a window-ratio scale (VSh) shrinks the deal on phones while the band grows with H - the squatting.
      // owner 21 Oct: deal uniformly from the whole band on both axes - no ceiling-hugging, few repeats, varied
      // aspect ratios (whole range random, no repeats, varied aspect ratios). Height range mirrors the width
      // rule: from a third of the screen height to the ceiling (mapping choice, reported).
      var bw = bandW(), bh = bandH(), loH = window.innerHeight / 3;
      var w = bw.lo, h = loH, ok = false;
      for (var t = 0; t < 8 && !ok; t++) {
        w = bw.lo + Math.random() * (bw.hi - bw.lo);
        h = loH + Math.random() * (bh.hi - loH);
        ok = true;
        for (var hi2 = 0; hi2 < dealHist.length; hi2++) if (Math.abs(dealHist[hi2][0] - w) < 24 && Math.abs(dealHist[hi2][1] - h) < 24) { ok = false; break; } // a near-repeat of a recent deal re-rolls
      }
      dealHist.push([w, h]); if (dealHist.length > 6) dealHist.shift();
      c.rawW = w; c.rawH = h;
      window.__ca2.clampTargets();
      c.tw = c.rawW; c.th = c.rawH; // the band overrides the shared area ceilings on phones
      dealW = c.rawW; dealH = c.rawH;
    }
    function portraitGuard() {
      if (mode !== 'm') return;
      var c = window.__ca2.cont; if (!c || c.user) return;
      if (c.rawW !== dealW || c.rawH !== dealH) dealPortrait(); // the sim re-dealt a landscape plate (transition): rotate it
      var bw = bandW(), bh = bandH();
      if (c.rawW < bw.lo || c.rawW > bw.hi || c.tw < bw.lo || c.tw > bw.hi || c.rawH > bh.hi || c.th > bh.hi) {
        c.rawW = Math.min(Math.max(c.rawW, bw.lo), bw.hi);
        c.rawH = Math.min(c.rawH, bh.hi);
        window.__ca2.clampTargets();
        c.tw = c.rawW; c.th = c.rawH;
        dealW = c.rawW; dealH = c.rawH;
      }
    }
    function refresh(m) { var nm = m || detect(); if (nm === mode) return; mode = nm; applyMode(); if (mode === 'm') dealPortrait(); if (typeof prof !== 'undefined' && prof) applyProf(); }
    window.addEventListener('ca2mode', function (e) {
      lane = true; if (!e.detail || !e.detail.mode) return;
      // B picked on a wide desktop window opens the phone-frame preview (owner 21 Oct); the frame is device.html
      if (e.detail.sel === 'm' && !MODE_Q && !coarse && window.innerWidth > AUTO_W && !/device\.html/.test(location.pathname)) { location.href = 'device.html'; return; }
      refresh(e.detail.mode);
    });
    window.addEventListener('resize', function () { if (applying || lane || window.__ca2Mode || lsSel) return; refresh(); }); // fallback auto-switch only while no lane module and no explicit pick
    // the other lane's pullG applies fresh desktop keys over the mobile layer; re-apply it after every global update
    var g0 = storedG(); seenV = (g0 && g0._v) || 0;
    setInterval(function () { var g = storedG(), v = g && g._v; if (v && v !== seenV) { seenV = v; if (mode === 'm') { applyMode(); landResync(); } } }, 1000);
    setInterval(portraitGuard, 200); // fast cadence: a re-dealt thin plate must not visibly ease below the width floor (owner 21 Oct)
    (function wBand() { // render-synced: intervals stall on the saturated main thread, so the eased size itself is held inside the band every painted frame
      requestAnimationFrame(wBand);
      if (mode !== 'm') return;
      var c = window.__ca2 && window.__ca2.cont; if (!c) return;
      var bw = bandW(), bh = bandH();
      if (c.user) { // manual pull: the same margin + section-button ceiling on both axes (owner 21 Oct); the third-of-screen floor stays automatic-only
        c.tw = Math.min(c.rawW, bw.hi); c.th = Math.min(c.rawH, bh.hi);
        if (c.w > bw.hi) c.w = bw.hi;
        if (c.h > bh.hi) c.h = bh.hi;
        return;
      }
      if (c.w < bw.lo) c.w = bw.lo;
      if (c.w > bw.hi) c.w = bw.hi;
      if (c.h > bh.hi) c.h = bh.hi;
    })();
    // ---- orientation profiles (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02): PORTRAIT is the existing mobile layer, unchanged. LANDSCAPE is a
    // mirror profile: only the parameters changed while in LANDSCAPE are overridden; everything else follows
    // PORTRAIT live. Overrides travel inside the global's _mobile._land (the Worker merges _mobile whole) with the
    // device-local mirror on top, so a phone keeps its unsaved landscape edits across reloads.
    var PROF_KEY = 'ca2.mprof';
    function profLoad() { try { var p = JSON.parse(localStorage.getItem(PROF_KEY) || 'null'); if (p && typeof p === 'object') { p.land = (p.land && typeof p.land === 'object') ? p.land : {}; p.active = (p.active === 'L' || p.active === 'P') ? p.active : null; return p; } } catch (e) {} return { active: null, land: {} }; }
    var prof = profLoad(); // active: pinned pick or null (= follow the window aspect)
    function profSave() { try { localStorage.setItem(PROF_KEY, JSON.stringify(prof)); } catch (e) {} }
    function profActive() { if (prof.active) return prof.active; return window.innerWidth > window.innerHeight ? 'L' : 'P'; }
    function landMap() { var mb = mobOf(storedG() || {}); var gl = (mb._land && typeof mb._land === 'object') ? mb._land : {}; return Object.assign({}, gl, prof.land); }
    var curProf = null, entryVals = null, diffBase = null, keepP = {};
    // the PORTRAIT value of a key = an unsaved portrait edit, else the global _mobile layer, else the seed. Never read it back from P while
    // LANDSCAPE is active: applyMode has already seeded the landscape bucket into P (also on a boot straight into landscape).
    function portraitBase(k) { if (keepP[k] !== undefined) return keepP[k]; var mb = mobOf(storedG() || {}); return (mb[k] !== undefined) ? mb[k] : MOBILE_SEED[k]; }
    function scalarKeys(o) { var r = {}; if (!o) return r; Object.keys(o).forEach(function (k) { var v = o[k]; if (typeof v === 'number' || typeof v === 'string' || typeof v === 'boolean') r[k] = v; }); return r; }
    function intended(o) { // live morphs ease P frame by frame; the intended value is the morph target (live[k].orig)
      var r = scalarKeys(o), lv = window.__ca2.live || {};
      Object.keys(lv).forEach(function (k) { if (lv[k] && typeof lv[k].orig === typeof r[k]) r[k] = lv[k].orig; });
      return r;
    }
    function readCfgP() { try { var c = JSON.parse(localStorage.getItem(window.__ca2x.STORE) || 'null'); return scalarKeys(c && c.P); } catch (e) { return {}; } }
    function profSeed(k, v) { window.__ca2.seedKey(k, v); } // a layer write: no touched pin, no save - never reads as an edit
    function landResync() { if (curProf !== 'L' || !diffBase) return; diffBase = readCfgP(); }
    function applyProf() {
      // the orientation profiles exist ONLY in mobile mode: the desktop is its own profile and a wide window must never
      // select LANDSCAPE there (that seeded the landscape bucket into the desktop config and persisted it)
      var act = (mode === 'm') ? profActive() : 'D';
      if (act === curProf) return;
      if (curProf === 'P') { // PORTRAIT bucket: unsaved portrait edits survive a trip through LANDSCAPE / desktop (applyMode below re-seeds the layer from the global)
        var ivP = intended(P), tkP = window.__ca2.touchedKeys || [];
        tkP.forEach(function (k) { if (ivP[k] !== undefined) keepP[k] = ivP[k]; });
      }
      if (curProf === 'L' && entryVals) { // leaving LANDSCAPE: hand every overridden key its portrait value back
        var lm0 = landMap();
        Object.keys(lm0).forEach(function (k) { var pv = portraitBase(k); if (pv === undefined) pv = entryVals[k]; if (pv !== undefined) profSeed(k, pv); });
        entryVals = null; diffBase = null;
      }
      curProf = act;
      if (act === 'D') { applyMode(); lpPaint(); return; } // desktop: layer restore only, no landscape seeding, no save
      applyMode(); // profile-aware: in L the mirror wins per key inside the layer
      if (act === 'P') { var tkA = window.__ca2.touchedKeys || []; Object.keys(keepP).forEach(function (k) { if (tkA.indexOf(k) >= 0 && typeof keepP[k] === typeof P[k]) profSeed(k, keepP[k]); else delete keepP[k]; }); } // only still-unsaved portrait edits come back
      if (act === 'L') {
        captureLand();
        entryVals = intended(P); diffBase = readCfgP();
        var lm = landMap();
        Object.keys(lm).forEach(function (k) { if (typeof lm[k] === typeof entryVals[k]) profSeed(k, lm[k]); }); // non-layer keys: the layer keys were already seeded by applyMode
      }
      try { window.__ca2x.save(); } catch (e) {}
      if (curProf === 'L') diffBase = readCfgP(); // my own save above must not read back as edits
      lpPaint();
    }
    // edits made while LANDSCAPE is active are the mirror's content (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02). Capture = keys the core marked
    // touched whose persisted (save()-written, morph-target) value changed: user edits only. Layer seeds, global
    // pulls, boot deals and in-flight morphs neither mark touched nor call save, so they can never pollute the mirror.
    function captureLand() { // returns true when the mirror changed; safe to call any time, cheap
      if (mode !== 'm' || curProf !== 'L' || !diffBase) return false;
      var cfgP = readCfgP(), tk = window.__ca2.touchedKeys || [], dirty = false;
      tk.forEach(function (k) {
        if (cfgP[k] === undefined || cfgP[k] === diffBase[k]) return;
        prof.land[k] = cfgP[k]; diffBase[k] = cfgP[k]; dirty = true;
      });
      if (dirty) { profSave(); lpPaint(); }
      return dirty;
    }
    setInterval(function () { captureLand(); }, 400); // the cadence for unsaved edits; saves sweep synchronously below
    window.addEventListener('resize', function () { if (mode === 'm' && !prof.active) applyProf(); }); // unpinned: follow the window aspect
    // ---- L / P circles (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02): top-left corner, same family as the login circles - hover (or the touch
    // press) paints a random RGB and grows the circle into a pill spelling the full word; a tap switches profile
    var lpw = null, lpEls = {};
    window.__ca2ProfFollow = function () { prof.active = null; profSave(); applyProf(); }; // device.html: the frame's viewport aspect decides the profile
    function lpPaint() {
      if (!lpw) return;
      var act = profActive();
      ['L', 'P'].forEach(function (k) {
        var b = lpEls[k]; if (!b) return;
        b.classList.toggle('on', act === k);
        b.classList.toggle('pin', prof.active === k);
      });
    }
    (function lpUI() {
      var st = document.createElement('style');
      st.textContent = '#lpl{position:fixed;top:calc(8px + env(safe-area-inset-top,0px));left:calc(8px + env(safe-area-inset-left,0px));z-index:70;display:none;gap:8px;font-family:inherit}' +
        'body[data-camode="m"] #lpl{display:flex}' +
        '.lpc{position:relative;height:var(--lpd,28px);min-width:var(--lpd,28px);width:var(--lpd,28px);box-sizing:border-box;border-radius:999px;border:1.5px solid var(--fg,#111);background:transparent;color:var(--fg,#111);padding:0 10px;cursor:pointer;overflow:hidden;white-space:nowrap;transition:width .38s cubic-bezier(.4,0,.2,1),background .38s,color .38s,border-color .38s;font-size:12px;letter-spacing:.14em;display:flex;align-items:center;justify-content:center;-webkit-tap-highlight-color:transparent;touch-action:manipulation}' +
        '.lpc i{font-style:normal}' +
        '.lpc s{display:none;text-decoration:none;font-weight:600}' +
        '.lpc.x i{display:none}.lpc.x s{display:inline}' +
        '.lpc.on{border-width:2.5px}' +
        '.lpc.pin:after{content:"";position:absolute;right:4px;top:4px;width:5px;height:5px;border-radius:50%;background:currentColor}';
      document.head.appendChild(st);
      lpw = document.createElement('div'); lpw.id = 'lpl';
      [['L', 'LANDSCAPE'], ['P', 'PORTRAIT']].forEach(function (pair) {
        var b = document.createElement('button'); b.type = 'button'; b.className = 'lpc'; b.setAttribute('aria-label', pair[1]);
        var i = document.createElement('i'); i.textContent = pair[0]; var s = document.createElement('s'); s.textContent = pair[1];
        b.appendChild(i); b.appendChild(s); lpw.appendChild(b); lpEls[pair[0]] = b;
        function rgb() { return 'rgb(' + Math.floor(Math.random() * 256) + ',' + Math.floor(Math.random() * 256) + ',' + Math.floor(Math.random() * 256) + ')'; }
        function grow() { if (b.classList.contains('x')) return; b.classList.add('x'); b.style.width = (Math.max(28, b.querySelector('s').getBoundingClientRect().width + 24)) + 'px'; var c = rgb(); b.style.background = c; b.style.borderColor = c; var m = /rgb\((\d+),(\d+),(\d+)\)/.exec(c); var lum = m ? (0.299 * m[1] + 0.587 * m[2] + 0.114 * m[3]) : 0; b.style.color = lum > 150 ? '#111' : '#fff'; }
        function shrink() { b.classList.remove('x'); b.style.width = ''; b.style.background = ''; b.style.borderColor = ''; b.style.color = ''; }
        b.addEventListener('pointerenter', grow); // the login-circle hover language: random colour + the full word (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02)
        b.addEventListener('pointerleave', shrink);
        b.addEventListener('click', function () {
          var k = pair[0];
          if (prof.active === k) { prof.active = null; } // a second tap on the pinned circle hands control back to the aspect
          else prof.active = k;
          profSave(); grow(); applyProf();
          setTimeout(function () { if (!b.matches(':hover')) shrink(); }, 900);
        });
      });
      // the profile switcher is an admin instrument (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02): it mounts with admin and leaves with ca2logout
      var lpOn = false;
      var inFrame = MODE_Q && window.parent !== window; // the device.html host owns the P/L circles (top-left of its black screen); nothing inside the preview
      function lpMount() { if (lpOn || inFrame) return; lpOn = true; document.body.appendChild(lpw); lpPaint(); }
      function lpDrop() { if (!lpOn) return; lpOn = false; if (lpw.parentNode) lpw.parentNode.removeChild(lpw); }
      window.addEventListener('ca2logout', lpDrop);
      setInterval(function () { if (window.__adminOn) lpMount(); else lpDrop(); }, 500);
    })();
    // admin saves reroute into _mobile (owner 21 Oct): the desktop lane's Worker module calls this hook right
    // before POSTing an admin save (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02 contract). Sync, never mutates its argument, never throws:
    // null = post the original body, an object = post it as the full replacement body (a Promise of either is
    // accepted by the caller). PORTRAIT keeps the 21 Oct shape: the whole effective mobile config into _mobile,
    // sent whole because the Worker merges shallowly. LANDSCAPE writes the same whole portrait config PLUS
    // _mobile._land = only the keys actually changed while in LANDSCAPE - the mirror (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02).
    // admin saves reroute into _mobile (owner 21 Oct): the desktop lane's Worker module calls this hook right
    // before POSTing an admin save (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02 contract). body = the full POST object {code, patch:{...}};
    // returns null (= post the original) or a full replacement body - never mutates, never throws, sync (a
    // returned Promise is also accepted by the caller). Mobile shape: the patch's config keys collapse into
    // patch._mobile as a JSON STRING (the Worker merges patches shallowly, so _mobile travels whole, like
    // _live). PORTRAIT keeps the 21 Oct whole-config shape; LANDSCAPE writes the whole PORTRAIT-effective
    // config with the mirror backed out PLUS _mobile._land = only the keys actually changed in LANDSCAPE
    // (user 23 Oct phonemsg-01M5MCY74RD2TRF90TZFQEXJ02). A PORTRAIT save preserves the stored mirror. Desktop saves pass through (null).
    window.__ca2RewriteAdminPatch = function (body, ctx) {
      try {
        if (!body || typeof body !== 'object' || !body.patch || typeof body.patch !== 'object') return null;
        if (detect() !== 'm') return null;
        captureLand(); // an edit followed by an immediate Save must land in the mirror, not in the portrait copy
        var out = JSON.parse(JSON.stringify(body));
        var eff = intended(P), lm = landMap();
        if (profActive() === 'L') Object.keys(lm).forEach(function (k) { var pv = portraitBase(k); if (pv === undefined && entryVals) pv = entryVals[k]; if (pv !== undefined) eff[k] = pv; }); // back the mirror out of the portrait copy
        if (Object.keys(lm).length) eff._land = lm;
        var np = { _mobile: JSON.stringify(eff) };
        // the next profile switch / save in this session must see what this save is sending, not the cache from before it (pullG refreshes it within 15 s anyway)
        try { var gg = storedG() || {}; gg._mobile = np._mobile; localStorage.setItem('ca2.global', JSON.stringify(gg)); } catch (e) {}
        if (typeof out.patch._live === 'string') np._live = out.patch._live;
        out.patch = np;
        return out;
      } catch (e) { return null; }
    };
    refresh();
    applyProf(); // settle the aspect-followed or pinned profile before the first paint after boot
  }
  boot();
  // mobile lane (owner 21 Oct): section-button spacing halved on mobile + hover division unclipped (overflow-y:auto forced x-clipping)
  (function mobileSecc() {
    var st = document.createElement('style');
    st.textContent = 'body[data-camode="m"] #secc .sl{margin-top:8px}body[data-camode="m"] #secc{overflow:visible}';
    document.head.appendChild(st);
  })();

})();
