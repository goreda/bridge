#!/usr/bin/env python3
"""MODEL test (Python port, Swift not runnable here) of two VR CPU cuts. The ports are line-for-line from
SourcePixelCrop.swift SourcePixelBounds.scan and VRMirrorThrottle.shouldRender; the test also checks the Swift source
still contains the same structure so the port cannot drift silently.
1) scan: bounding box identical to the brute-force full scan on 3000 random frames; samples touched on a full-bleed
   8192x4096 frame vs the old 33.5M.
2) mirror throttle: 10 Hz timer, 60 s idle with one text change per second and 3 sources: renders/s vs old 30/s."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import pathlib, random, re, sys
ROOT = pathlib.Path(__file__).resolve().parents[2] / "Sources/gor"
class Img:
    def __init__(s, w, h, bright): s.w, s.h, s.b, s.touch = w, h, bright, 0
    def v(s, y, x): s.touch += 1; return 1 if (y, x) in s.b else 0
def scan(img, th=0):
    w, h = img.w, img.h
    def first(y, a, b):
        x = a
        while x < b:
            if img.v(y, x): return x
            x += 1
        return -1
    def last(y, a, b):
        x = b - 1
        while x >= a:
            if img.v(y, x): return x
            x -= 1
        return -1
    top = -1; y = 0
    while y < h:
        if first(y, 0, w) >= 0: top = y; break
        y += 1
    if top < 0: return None
    bottom = top; y = h - 1
    while y > top:
        if first(y, 0, w) >= 0: bottom = y; break
        y -= 1
    x0, x1 = w, 0
    for row in (top, bottom):
        x0 = min(x0, first(row, 0, w)); x1 = max(x1, last(row, 0, w) + 1)
    if top + 1 < bottom:
        y = top + 1
        while y < bottom:
            if x0 == 0 and x1 == w: break
            if x0 > 0:
                f = first(y, 0, x0)
                if f >= 0: x0 = f
            if x1 < w:
                l = last(y, x1, w)
                if l >= 0: x1 = l + 1
            y += 1
    return (x0, top, x1, bottom + 1)
def brute(img):
    pts = img.b
    if not pts: return None
    xs = [p[1] for p in pts]; ys = [p[0] for p in pts]
    return (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
random.seed(7); bad = 0
for _ in range(3000):
    w, h = random.randint(1, 24), random.randint(1, 18)
    n = random.choice([0, 1, 2, 5, 40, w * h])
    pts = {(random.randrange(h), random.randrange(w)) for _ in range(n)}
    if scan(Img(w, h, pts)) != brute(Img(w, h, pts)): bad += 1
print("scan mismatches vs brute force:", bad, "/ 3000")
class Full(Img):
    def v(s, y, x): s.touch += 1; return 1
big = Full(8192, 4096, set()); r = scan(big)
print("full-bleed 8192x4096 touched", big.touch, "samples (old: %d), bounds %s" % (8192 * 4096, r))
# throttle
HB, HOLD = 0.5, 1.5
last = {}; until = 0.0; rend = 0; skip = 0
def should(slot, ident, stamp, has, now):
    global rend, skip
    p = last.get(slot)
    due = (not has) or p is None or p[0] != ident or p[1] != stamp or now < until or now - p[2] >= HB
    if due: last[slot] = (ident, stamp, now); rend += 1
    else: skip += 1
    return due
for tick in range(600):
    now = tick * 0.1
    for slot in range(3): should(slot, slot, (int(now) if slot == 1 else 0), True, now)
per_s = rend / 60.0
print("idle renders/s: %.1f (old 30.0), skipped %d" % (per_s, skip))
until = 61.5; rend = 0
for tick in range(600, 700):
    now = 60 + tick * 0.0 + (tick - 600) * 0.1
    for slot in range(3): should(slot, slot, 0, True, now)
print("interactive renders/s: %.1f" % (rend / 10.0 * 1.0 if False else rend / 10.0))
# 3) FanoutGovernor (VariationBroadcaster audio fan-out, the CATextLayer re-typeset driver: sample showed main thread 1971/1971
#    busy, 1419 in CATextLayer drawInContext). Port of FanoutGovernor.allow/gap; 60 Hz timer for 10 s, audio changes every tick.
def gov_run(load, mouse, floor=0.45, ceil=0.90, maxgap=0.125, audio_only_rule=True):
    last, n = 0.0, 0
    for tick in range(600):
        now = 1.0 + tick / 60.0
        k = min(1, max(0, (load - floor) / (ceil - floor))); gap = k * maxgap
        audio_only = (not mouse) if audio_only_rule else True
        if (not audio_only) or now - last >= gap: last = now; n += 1
    return n
free, half, sat, mouse_sat = gov_run(0.2, False), gov_run(0.675, False), gov_run(0.95, False), gov_run(0.95, True)
print("governor fan-outs per 10 s: load 0.20 -> %d (old 600), load 0.675 -> %d, load 0.95 -> %d (%.1f/s), pointer-driven at 0.95 -> %d" % (free, half, sat, sat / 10.0, mouse_sat))
gov_ok = free == 600 and 140 <= half <= 170 and sat <= 82 and mouse_sat == 600
# mutants must be caught: no load floor delays a light-load session; ignoring the audio-only rule delays pointer-driven fan-outs
mut1 = gov_run(0.2, False, floor=0.0) != 600
mut2 = gov_run(0.95, True, audio_only_rule=False) != 600
print("mutants caught: floor=0 %s, pointer delayed %s" % (mut1, mut2))
gov_ok = gov_ok and mut1 and mut2
vb = _s3read(ROOT / "VariationBroadcaster.swift"); th0 = _threed_split().path(ROOT.parents[1]).read_text(); sce = _s3read(ROOT / "ScreenCaptureEngine.swift"); cam = _s3read(ROOT / "Camera/Runtime.swift")
gov_ok = gov_ok and all(k in th0 for k in ["static let loadFloor = 0.45", "static let loadCeil = 0.90", "static let maxGap: TimeInterval = 0.125",
    "if !audioOnly || now - lastFanout >= Self.gap(load: load)", "CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue",
    "object(forKey: \"gorHeatGovernor\") as? Bool ?? true"]) \
    and "!self.fanoutGovernor.allow(now: now, audioOnly: !mouseMoved, load: MainLoopLoad.shared.load)" in vb \
    and "MainLoopLoad.shared.start()" in vb and "[heat] main_load=" in vb.replace("[heat] main_load=", "[heat] main_load=") and "proc_cpu_pct=" in vb and "vision_frames=" in vb \
    and "static var visionFrames = 0" in th0 and "HeatTelemetry.headTrackInterval" in cam and '"gorHeadTrackFPS"' in th0 and "?? 30))" in th0
print("governor static structure ok:", gov_ok)
# 4) hidden-view listener skip + 4 Hz resume sweep (zero visible change: a hidden view draws nothing; a view that becomes
#    visible gets exactly the block a fan-out would have run, within 0.25 s, and every fan-out runs it while visible).
def hidden_run(sweep=True, hide_from=2.0, show_at=6.0, listeners=100):
    runs = 0; skipped = set(); last_visible_run = None
    for tick in range(60 * 10):
        t = tick / 60.0
        visible = not (hide_from <= t < show_at)
        if tick % 15 == 0 and skipped and sweep and visible:
            runs += len(skipped); last_visible_run = t; skipped = set()
        audio = tick % 2 == 0                     # audio fan-out every other tick
        if audio:
            if visible: runs += listeners
            else: skipped = set(range(listeners))
    return runs, last_visible_run
base_runs, _ = hidden_run(hide_from=99, show_at=100)
runs, resumed_at = hidden_run()
print("hidden-skip model: runs %d vs %d always-run; resumed at t=%.2f (shown at 6.00)" % (runs, base_runs, resumed_at or -1))
hid_ok = runs < base_runs * 0.75 and resumed_at is not None and resumed_at - 6.0 <= 0.25
def silent_after_show(sweep):   # no audio/mouse fan-out after the view is shown again: only the sweep can resume it
    skipped = set(range(5)); resumed = None
    for tick in range(60 * 4):
        t = 6.0 + tick / 60.0
        if tick % 15 == 0 and skipped and sweep: resumed = t; skipped = set()
    return resumed
mut_sweep_caught = silent_after_show(False) is None and silent_after_show(True) is not None
print("mutant (no resume sweep) leaves a shown view stale in a silent session, caught:", mut_sweep_caught)
hid_ok = hid_ok and mut_sweep_caught
hid_ok = hid_ok and all(k in vb for k in ["if let view = entry.liveness?.value as? NSView, !view.isEffectivelyVisible", "skippedHidden.insert(entry.token)",
    "self.diagnosticTicks % 15 == 0 { self.runResumedListeners() }", "guard let view = entry.liveness?.value as? NSView, view.isEffectivelyVisible else { continue }",
    "top_sites_10s=", "mpv_cpu_pct=", "font_changed_over_same_10s=[\\(HeatTelemetry.fontSiteSummary())]"]) and "static func mpvCPUPercent() -> String" in th0 and "proc_pid_rusage(pid, RUSAGE_INFO_CURRENT" in th0
def strip_swift(src):
    """Remove // and /* */ comments (block comments may span lines and nest) and blank string-literal contents, keeping newlines.
    A `//` inside a string is therefore not a comment, and guard or write text inside a string or comment never counts."""
    out, i, n, depth = [], 0, len(src), 0
    while i < n:
        c, d = src[i], src[i:i + 2]
        if depth:
            if d == "/*": depth += 1; i += 2
            elif d == "*/": depth -= 1; i += 2
            else:
                if c == "\n": out.append(c)
                i += 1
        elif d == "//":
            while i < n and src[i] != "\n": i += 1
        elif d == "/*": depth = 1; i += 2
        elif c == '"':
            out.append('"'); i += 1
            while i < n and src[i] != '"' and src[i] != "\n":
                i += 2 if src[i] == "\\" else 1
            out.append('"'); i += 1
        else: out.append(c); i += 1
    return "".join(out)
def unguarded_writes(src):
    """Single-line guard style is REQUIRED: on every code line the number of `fontSize = PhotonFont.size` writes must not exceed the
    number of `fontSize != PhotonFont.size` guards on that same line (so a second write after one guard is flagged). Comments and
    string literals are stripped first. A multi-line `if ... {` guard is flagged on purpose; write it on one line."""
    bad = 0
    for ln in strip_swift(src).split("\n"):
        w, g = "fontSize = PhotonFont.size", "fontSize != PhotonFont.size"
        events = sorted([(m.start(), "w") for m in re.finditer(re.escape(w), ln)] + [(m.start(), "g") for m in re.finditer(re.escape(g), ln)])
        open_guards = 0
        for _, kind in events:   # a write consumes one guard that appears EARLIER on the same line
            if kind == "g": open_guards += 1
            elif open_guards: open_guards -= 1
            else: bad += 1
    return bad
fs = [f for f in ROOT.glob("*.swift") if f.name != "PhotonFont.swift" and unguarded_writes(_s3read(f))]
print("unguarded fontSize = PhotonFont.size sites left:", sorted({f.name for f in fs}))
m5d = "l.fontSize = PhotonFont.size // if l.fontSize != PhotonFont.size { guard text in a comment }"
m5e = "if l.fontSize != PhotonFont.size {\n    l.fontSize = PhotonFont.size\n}"
ok1 = "if l.fontSize != PhotonFont.size { l.fontSize = PhotonFont.size }"
m6c = "if l.fontSize != PhotonFont.size { l.fontSize = PhotonFont.size; m.fontSize = PhotonFont.size }"
m6d = "l.fontSize = PhotonFont.size /* if l.fontSize != PhotonFont.size */"
m6d2 = "/* start\nif l.fontSize != PhotonFont.size { }\n*/ l.fontSize = PhotonFont.size"
m6e = 'let s = "//"; l.fontSize = PhotonFont.size'
m6e2 = 'if l.fontSize != PhotonFont.size { l.fontSize = PhotonFont.size }; let s = "x // y"; l.fontSize = PhotonFont.size'
m7a = "l.fontSize = PhotonFont.size; if l.fontSize != PhotonFont.size { }"
m6f = 'let s = "if l.fontSize != PhotonFont.size"; l.fontSize = PhotonFont.size'
hid_mut2 = (unguarded_writes(m6c) == 1 and unguarded_writes(m6d) == 1 and unguarded_writes(m6d2) == 1 and unguarded_writes(m6e) == 1
            and unguarded_writes(m6e2) == 1 and unguarded_writes(m6f) == 1 and unguarded_writes(m7a) == 1
            and unguarded_writes("if a.fontSize != PhotonFont.size { a.fontSize = PhotonFont.size }; if b.fontSize != PhotonFont.size { b.fontSize = PhotonFont.size }") == 0)
print("gate mutants caught: same-line second write %s, block comment %s (+multi-line) %s, // inside string %s (+after guard %s), guard text in string %s" % (
    unguarded_writes(m6c) == 1, unguarded_writes(m6d) == 1, unguarded_writes(m6d2) == 1, unguarded_writes(m6e) == 1, unguarded_writes(m6e2) == 1, unguarded_writes(m6f) == 1))
hid_mut = hid_mut2 and unguarded_writes(m5d) == 1 and unguarded_writes(m5e) == 1 and unguarded_writes(ok1) == 0 and unguarded_writes("l.fontSize = PhotonFont.size") == 1
print("mutants caught: guard-text-in-comment %s, multi-line guard flagged (single-line style required) %s, plain write %s" % (unguarded_writes(m5d) == 1, unguarded_writes(m5e) == 1, unguarded_writes("l.fontSize = PhotonFont.size") == 1))
hid_ok = hid_ok and not fs and hid_mut and "skippedHidden.formIntersection(listeners.map { $0.token })" in vb
pf = _s3read(ROOT / "PhotonFont.swift")
tel_ok = pf.count("HeatTelemetry.noteFont(changed: !same, file, line)") == 2 and pf.count("file: StaticString = #fileID, line: Int = #line") == 2 and "static func fontSiteSummary() -> String" in th0
# the tally must not change which font is applied: both overloads keep the CFEqual comparison (CTFont bridging) and a single `layer.font = font` write when different
tel_ok = tel_ok and "CFEqual($0 as! CTFont, font) } ?? false" in pf and "CFEqual($0 as! CTFont, font as CTFont) } ?? false" in pf and pf.count("if !same { layer.font = font }") == 2
print("per-site font hit/miss telemetry pinned, applied-font logic untouched:", tel_ok)
mt_ok = th0.count('assert(Thread.isMainThread, "HeatTelemetry font tally is main-thread only")') == 2 \
    and "fontSiteSummary()" in vb and vb.count("HeatTelemetry.fontSiteSummary()") == 1 \
    and not re.search(r"DispatchQueue\.(global|main\.async)[^\n]*noteFont", pf + th0)
cost_ok = "Int(bitPattern: file.utf8Start)" in th0 and "static func noteFont(changed: Bool, _ file: StaticString, _ line: Int)" in th0 \
    and "split(separator" not in th0[th0.index("static func noteFont"):th0.index("static func fontSiteSummary")].split("if fontSites[k] == nil")[0]
print("font tally main-thread-only pinned: %s; hot path has no String work before the dictionary hit: %s" % (mt_ok, cost_ok))
gov_ok = gov_ok and hid_ok and tel_ok and mt_ok and cost_ok
sw = _threed_split().path(ROOT.parents[1]).read_text(); th = _threed_split().path(ROOT.parents[1]).read_text(); pc = _s3read(_pp_split().dpath(ROOT,'PPController.swift'))
st = all(k in sw for k in ["while y < height { if rowIsContent(y) { top = y; break }; y += 1 }", "if x0 == 0 && x1 == width { break }", "result = Bounds(x0: x0, y0: top, x1: x1, y1: bottom + 1)"])
st = st and "static var heartbeat: TimeInterval { HeatTelemetry.thermalPressure ? 2.0 : 0.5 }" in th and "now < interactiveUntil" in th and "vrMirrorThrottle.shouldRender(slot: index" in pc and "vrMirrorThrottle.noteInteraction" in pc
ok = gov_ok and bad == 0 and r == (0, 0, 8192, 4096) and big.touch < 20000 and abs(per_s - 6.0) < 0.5 and st
# idle: 3 slots * (1 heartbeat per 0.5 s => 2/s) + one stamp change per s on slot 1 (already on heartbeat) => ~6/s, down from 30/s
print("static structure ok:", st); print("PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
