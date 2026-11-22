#!/usr/bin/env python3
"""P29-CHROME golden vectors (DR-0019): formula-derived expected behaviour for
photon-chrome.lua v1.1's state/adaptive layer, emitted as JSON for the Linux
witness (chrome-state-tests) and the gor-lane harness. Formula-derived here
(no Lua interpreter on this host); the gor lane re-derives truth from the
authoritative Lua before the Swift model leaves inert. Source pin: instinct
main photon-chrome.lua SHA256 d0ebe78af3dd3d2ed13bdd7d2f0960f7803cf31e709b96a40191c78285ee92ca,
photon-common.lua helpers (HUE_EMA_ALPHA 0.08, smooth_hue, char_track, asym_smooth)."""
import json, math

CHROME_FILTER = 1.0
FILTER_STRENGTH = 0.75
ARC_MAX = 120.0 / 360.0
HUE_EMA_ALPHA = 0.08
CONTRAST_BASE = 0.11 / 2
CONTRAST_SCENE_GAIN = 0.22 / 2
CONTRAST_CLAMP_MAX = 0.44 / 2
SAT_FLOOR, SAT_CEIL, SAT_STRENGTH_MIN = 0.15, 0.55, 0.35
TIER1_TAU, TIER1_CUT_TAU = 0.35, 0.6
CHAR_TAU, CHAR_DZ, CHAR_DWELL, CHAR_EASE, CHAR_CUT_EASE = 9.0, 0.36, 2.5, 3.0, 0.8

def clamp(v, lo, hi): return max(lo, min(hi, v))

def lerp_hue(a, b, t):
    d = b - a
    if d > 0.5: d -= 1.0
    elif d < -0.5: d += 1.0
    h = a + d * t
    if h < 0: h += 1.0
    elif h >= 1.0: h -= 1.0
    return h

def hue_circ(a, b):
    d = max(a, b) - min(a, b)
    return 1.0 - d if d > 0.5 else d

class Sim:
    """Exact replica of the source state machine (Lua semantics)."""
    def __init__(self):
        self.enabled = False
        self.target_enabled = False
        self.manual_active = False
        self.manual_pos = CHROME_FILTER
        self.sat = 0.0
        self.contrast = 0.25
        self.hue = None
        self.hue_smoothed = None
        self.is_cut = False
        self.has_feed = False
        self.strength_resolved = FILTER_STRENGTH
        self.contrast_resolved = CONTRAST_BASE
        self.pos_resolved = CHROME_FILTER
        self.strength_rendered = FILTER_STRENGTH
        self.contrast_rendered = CONTRAST_BASE
        self.pos_rendered = CHROME_FILTER
        self.arc_clamped = False
        self.signal = CHROME_FILTER
        self.committed = CHROME_FILTER
        self.rendered = CHROME_FILTER
        self.dwell_start = None
        self.t1 = 0.0
        self.tc = 0.0
        self.saw_file_loaded = False
        self.saw_target = False

    def smooth_hue(self, raw, snap):
        if snap or self.hue_smoothed is None: return raw
        return lerp_hue(self.hue_smoothed, raw, HUE_EMA_ALPHA)

    def char_track(self, raw, now, dt, is_cut):
        self.signal += (1 - math.exp(-dt / CHAR_TAU)) * (raw - self.signal)
        drift = max(self.signal, self.committed) - min(self.signal, self.committed)
        if drift <= CHAR_DZ and not is_cut:
            self.dwell_start = None
        else:
            if self.dwell_start is None: self.dwell_start = now
            if is_cut or now - self.dwell_start >= CHAR_DWELL:
                self.committed = self.signal
                self.dwell_start = None
        tau = CHAR_CUT_EASE if is_cut else CHAR_EASE
        self.rendered += (1 - math.exp(-dt / tau)) * (self.committed - self.rendered)
        return self.rendered

    def resolve(self, now):
        if self.sat < 0:
            self.strength_resolved = FILTER_STRENGTH
        else:
            sat_t = SAT_STRENGTH_MIN + clamp((self.sat - SAT_FLOOR) / (SAT_CEIL - SAT_FLOOR), 0, 1) * (1 - SAT_STRENGTH_MIN)
            self.strength_resolved = FILTER_STRENGTH * sat_t
        self.contrast_resolved = clamp(CONTRAST_BASE + self.contrast * CONTRAST_SCENE_GAIN, 0, CONTRAST_CLAMP_MAX)
        if self.manual_active:
            self.pos_resolved = self.manual_pos
            self.arc_clamped = False
        elif self.hue_smoothed is None:
            self.pos_resolved = CHROME_FILTER
            self.arc_clamped = False
        else:
            h = self.hue_smoothed
            in_arc = 0 <= h <= ARC_MAX
            if in_arc: hia = h
            else: hia = 0.0 if hue_circ(h, 0) <= hue_circ(h, ARC_MAX) else ARC_MAX
            self.arc_clamped = not in_arc
            self.pos_resolved = hia / ARC_MAX * 3.0
        dt1 = min(now - (self.t1 if self.t1 > 0 else now - 0.1), 1.0)
        self.t1 = now
        tau = TIER1_CUT_TAU if self.is_cut else TIER1_TAU
        self.strength_rendered += (1 - math.exp(-dt1 / tau)) * (self.strength_resolved - self.strength_rendered)
        self.contrast_rendered += (1 - math.exp(-dt1 / tau)) * (self.contrast_resolved - self.contrast_rendered)
        dtc = min(now - (self.tc if self.tc > 0 else now - 0.1), 1.0)
        self.tc = now
        self.pos_rendered = self.char_track(self.pos_resolved, now, dtc, self.is_cut)

    def ingest(self, hue, sat, contrast, is_cut, now):
        first = not self.has_feed
        self.sat, self.contrast, self.is_cut, self.has_feed = sat, contrast, is_cut, True
        self.hue = hue
        if hue is not None:
            self.hue_smoothed = self.smooth_hue(hue, is_cut or self.hue_smoothed is None)
        if not self.enabled: return
        self.resolve(now)
        if first:
            self.strength_rendered = self.strength_resolved
            self.contrast_rendered = self.contrast_resolved

    def toggle(self, now):
        self.enabled = not self.enabled
        self.target_enabled = self.enabled
        if self.enabled: self.resolve(now)

    def filter_toggle(self, now):
        if not self.enabled: return
        if not self.manual_active: self.manual_active, self.manual_pos = True, 0.0
        elif self.manual_pos < 3: self.manual_pos += 1
        else: self.manual_active = False
        snap = self.manual_pos if self.manual_active else CHROME_FILTER
        self.signal = self.committed = self.rendered = snap
        self.dwell_start = None
        self.pos_rendered = snap
        self.resolve(now)

    def pause(self, now):
        if not self.manual_active: return False
        self.manual_active = False
        if self.enabled: self.resolve(now)
        return True

    def file_loaded(self, now):
        self.saw_file_loaded = True
        self.has_feed = False
        self.sat, self.contrast = 0.10, 0.35
        self.hue = self.hue_smoothed = None
        self.signal = self.committed = self.rendered = CHROME_FILTER
        self.dwell_start = None
        self.manual_active = False
        self.tc = self.t1 = 0.0
        self.resolve(now)
        self.pos_rendered = self.pos_resolved
        self.strength_rendered = self.strength_resolved
        self.contrast_rendered = self.contrast_resolved
        self.maybe_carryover()

    def set_target(self, v):
        self.target_enabled = v
        self.saw_target = True
        self.maybe_carryover()

    def maybe_carryover(self):
        if not (self.saw_file_loaded and self.saw_target): return
        if self.target_enabled and not self.enabled: self.enabled = True
        elif not self.target_enabled and self.enabled: self.enabled = False

    def expect(self):
        return {"hueSmoothed": self.hue_smoothed, "strengthRendered": self.strength_rendered,
                "contrastRendered": self.contrast_rendered, "posResolved": self.pos_resolved,
                "posRendered": self.pos_rendered, "arcClamped": self.arc_clamped,
                "enabled": self.enabled, "hasFeed": self.has_feed,
                "manualActive": self.manual_active, "manualPos": self.manual_pos,
                "committed": self.committed}

vectors = []


# --- timestamp quantization shim -------------------------------------------
# JSON number parsing is not guaranteed bit-exact across runtimes (Foundation's
# JSONSerialization vs Python json), and the dwell-confirm threshold compares
# absolute timestamps. All times are therefore quantized to integer MICROSECONDS
# before entering the sim, and steps carry nowUs (exact integers) instead of
# float seconds. The witness computes now = Double(nowUs) / 1e6, which is the
# identical correctly-rounded division on both sides.
def _q(now):
    return round(now * 1e6) / 1e6
for _m in ("ingest", "toggle", "filter_toggle", "pause", "file_loaded"):
    _orig = getattr(Sim, _m)
    def _wrap(self, *args, _orig=_orig):
        return _orig(self, *args[:-1], _q(args[-1]))
    setattr(Sim, _m, _wrap)

# V1 hue-EMA jitter: alternating +/-0.01 around 0.10, 20 feeds, no cut.
sim = Sim(); sim.toggle(0.0); steps = [{"op": "toggle", "now": 0.0}]
for i in range(20):
    h = 0.10 + (0.01 if i % 2 == 0 else -0.01)
    sim.ingest(h, 0.3, 0.25, False, (i + 1) * 0.1)
    steps.append({"op": "ingest", "now": (i + 1) * 0.1, "hue": h, "sat": 0.3, "contrast": 0.25,
                  "isCut": False, "expect": sim.expect()})
vectors.append({"name": "V1-hue-ema-jitter", "steps": steps})

# V2 cut reset: 5 feeds at 0.1 then a cut to 0.30 (snap + cut taus).
sim = Sim(); sim.toggle(0.0); steps = [{"op": "toggle", "now": 0.0}]
for i in range(5):
    sim.ingest(0.1, 0.3, 0.25, False, (i + 1) * 0.1)
    steps.append({"op": "ingest", "now": (i + 1) * 0.1, "hue": 0.1, "sat": 0.3, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
sim.ingest(0.30, 0.3, 0.25, True, 0.6)
steps.append({"op": "ingest", "now": 0.6, "hue": 0.30, "sat": 0.3, "contrast": 0.25, "isCut": True, "expect": sim.expect()})
sim.ingest(0.30, 0.3, 0.25, False, 0.7)
steps.append({"op": "ingest", "now": 0.7, "hue": 0.30, "sat": 0.3, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
vectors.append({"name": "V2-cut-reset", "steps": steps})

# V3 dwell-confirm: establish 0.05 long enough for the tau-9 long-EMA to
# commit near 0.45 (~12s: drift past the 0.36 dead zone at ~9.6s, dwell 2.5s),
# then jump to 0.30 and verify: no commit while drift is inside the dead zone,
# dwell-armed commit once the signal has been wrong for 2.5s, then eased render.
sim = Sim(); sim.toggle(0.0); steps = [{"op": "toggle", "now": 0.0}]
for i in range(150):  # 15s at 0.05
    sim.ingest(0.05, 0.3, 0.25, False, (i + 1) * 0.1)
    if (i + 1) % 10 == 0 or i > 143:
        steps.append({"op": "ingest", "now": (i + 1) * 0.1, "hue": 0.05, "sat": 0.3, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
    else:
        steps.append({"op": "ingest", "now": (i + 1) * 0.1, "hue": 0.05, "sat": 0.3, "contrast": 0.25, "isCut": False})
committed_before = None
for i in range(120):  # 12s at 0.30
    sim.ingest(0.30, 0.3, 0.25, False, 15.0 + (i + 1) * 0.1)
    if committed_before is None and sim.committed > 0.5:
        committed_before = 15.0 + (i + 1) * 0.1
    if (i + 1) % 5 == 0 or (committed_before and 15.0 + (i + 1) * 0.1 >= committed_before - 0.3):
        steps.append({"op": "ingest", "now": 15.0 + (i + 1) * 0.1, "hue": 0.30, "sat": 0.3, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
    else:
        steps.append({"op": "ingest", "now": 15.0 + (i + 1) * 0.1, "hue": 0.30, "sat": 0.3, "contrast": 0.25, "isCut": False})
vectors.append({"name": "V3-dwell-confirm", "steps": steps, "commitTime": committed_before})

# V4 hue outside arc: 0.5 pins green endpoint, 0.95 pins red endpoint.
sim = Sim(); sim.toggle(0.0); steps = [{"op": "toggle", "now": 0.0}]
sim.ingest(0.5, 0.3, 0.25, False, 0.1)
steps.append({"op": "ingest", "now": 0.1, "hue": 0.5, "sat": 0.3, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
sim.ingest(0.95, 0.3, 0.25, True, 0.2)
steps.append({"op": "ingest", "now": 0.2, "hue": 0.95, "sat": 0.3, "contrast": 0.25, "isCut": True, "expect": sim.expect()})
vectors.append({"name": "V4-hue-outside-arc", "steps": steps})

# V5 manual cycle + pause clear.
sim = Sim(); sim.toggle(0.0); steps = [{"op": "toggle", "now": 0.0}]
sim.ingest(0.1, 0.3, 0.25, False, 0.1)
steps.append({"op": "ingest", "now": 0.1, "hue": 0.1, "sat": 0.3, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
for i in range(5):
    sim.filter_toggle(0.2 + i * 0.1)
    steps.append({"op": "filterToggle", "now": 0.2 + i * 0.1, "expect": sim.expect()})
sim.filter_toggle(0.7)  # back to manual red
steps.append({"op": "filterToggle", "now": 0.7, "expect": sim.expect()})
sim.pause(0.8)
steps.append({"op": "pause", "now": 0.8, "expect": sim.expect()})
vectors.append({"name": "V5-manual-cycle-pause", "steps": steps})

# V6 file-loaded reset + first-feed snap.
sim = Sim(); sim.toggle(0.0); steps = [{"op": "toggle", "now": 0.0}]
for i in range(5):
    sim.ingest(0.05, 0.5, 0.4, False, (i + 1) * 0.1)
    steps.append({"op": "ingest", "now": (i + 1) * 0.1, "hue": 0.05, "sat": 0.5, "contrast": 0.4, "isCut": False, "expect": sim.expect()})
sim.file_loaded(1.0)
steps.append({"op": "fileLoaded", "now": 1.0, "expect": sim.expect()})
sim.ingest(0.2, 0.5, 0.4, False, 1.1)
steps.append({"op": "ingest", "now": 1.1, "hue": 0.2, "sat": 0.5, "contrast": 0.4, "isCut": False, "expect": sim.expect()})
vectors.append({"name": "V6-file-loaded-reset", "steps": steps})

# V7 carryover rendezvous: target declared before file-loaded.
sim = Sim(); sim.set_target(True)
steps = [{"op": "setTargetEnabled", "value": True, "now": 0.0, "expect": sim.expect()}]
sim.file_loaded(0.1)
steps.append({"op": "fileLoaded", "now": 0.1, "expect": sim.expect()})
vectors.append({"name": "V7-carryover-rendezvous", "steps": steps})

# V8 tier1 ease trajectory: snap high then ease down with tau 0.35.
sim = Sim(); sim.toggle(0.0); steps = [{"op": "toggle", "now": 0.0}]
sim.ingest(0.1, 0.55, 0.25, False, 0.1)  # sat at ceiling: strength target 0.75, first-feed snap
steps.append({"op": "ingest", "now": 0.1, "hue": 0.1, "sat": 0.55, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
for i in range(10):  # sat drops to floor: ease toward 0.2625
    sim.ingest(0.1, 0.15, 0.25, False, 0.2 + i * 0.1)
    steps.append({"op": "ingest", "now": 0.2 + i * 0.1, "hue": 0.1, "sat": 0.15, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
vectors.append({"name": "V8-tier1-ease", "steps": steps})

# V9 HDR sentinel + nil-hue hold: sat -1 keeps flat strength; nil hue holds smoothed.
sim = Sim(); sim.toggle(0.0); steps = [{"op": "toggle", "now": 0.0}]
sim.ingest(0.1, 0.3, 0.25, False, 0.1)
steps.append({"op": "ingest", "now": 0.1, "hue": 0.1, "sat": 0.3, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
sim.ingest(None, -1, 0.25, False, 0.2)
steps.append({"op": "ingest", "now": 0.2, "hue": None, "sat": -1, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
sim.ingest(None, -1, 0.25, False, 0.3)
steps.append({"op": "ingest", "now": 0.3, "hue": None, "sat": -1, "contrast": 0.25, "isCut": False, "expect": sim.expect()})
vectors.append({"name": "V9-hdr-sentinel-nil-hue", "steps": steps})

import sys

for _v in vectors:
    for _s in _v["steps"]:
        _s["nowUs"] = int(round(_s.pop("now") * 1e6))
if "commitTime" in [k for v in vectors for k in v]:
    pass

out = sys.argv[1] if len(sys.argv) > 1 else "chrome-vectors.json"
with open(out, "w") as f:
    json.dump({"source": "photon-chrome.lua v1.1 SHA256 d0ebe78af3dd3d2ed13bdd7d2f0960f7803cf31e709b96a40191c78285ee92ca",
               "derivation": "formula-derived (no Lua interpreter on the Linux host); gor lane re-derives from authoritative Lua",
               "vectors": vectors}, f, indent=1)
print(f"wrote {out}: {len(vectors)} vectors, {sum(len(v['steps']) for v in vectors)} steps")
