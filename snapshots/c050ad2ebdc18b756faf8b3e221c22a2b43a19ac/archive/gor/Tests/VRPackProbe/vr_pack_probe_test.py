#!/usr/bin/env python3
"""Pins for tools/vr_pack_probe.py using a fake mpv: clean run, failing pack writes the safe marker, baseline failure changes nothing, all-pass clears the marker."""
import os, stat, sys, tempfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_pack_probe as P

fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "\n" + str(extra)))
    fails += 0 if ok else 1

def fake(d, body):
    root = Path(d); (root / "gor.app/Contents/MacOS").mkdir(parents=True, exist_ok=True)
    (root / "Resources/vendor/mpv/scripts").mkdir(parents=True, exist_ok=True)
    (root / "Resources/vendor/mpv/scripts/vr180-look.lua").write_text("-- stub\n")
    m = root / "gor.app/Contents/MacOS/mpv"; m.write_text("#!/bin/sh\n" + body); m.chmod(m.stat().st_mode | stat.S_IEXEC)
    return root

# Default automatic/background execution must never launch a window, even if mpv exists.
with tempfile.TemporaryDirectory() as d:
    marker=str(Path(d)/"marker");Path(marker).write_text("unchanged")
    launched=Path(d)/"launched";r=fake(d,"touch "+str(launched)+"\nexit 0\n")
    os.environ.pop("GOR_EXPLICIT_VISIBLE_GPU_PROBE",None)
    out=P.probe(str(r),marker)
    check("normal/background probe starts no process and changes no settings",not launched.exists() and Path(marker).read_text()=="unchanged" and "explicit_opt_in" in out[0],out)
    P.one(str(r/"gor.app/Contents/MacOS/mpv"),"stub","sbs",1)
    check("direct one() cannot bypass no-window default",not launched.exists())
os.environ["GOR_EXPLICIT_VISIBLE_GPU_PROBE"]="1"
original_hidden_flags=P.hidden_flags
class Result:
    stdout="--focus-on-open Flag\n--window-minimized Flag\n"
original_run=P.subprocess.run
P.subprocess.run=lambda *a,**k:Result()
check("GPU nofocus/minimize flags require supported options",P.hidden_flags("fake")==["--no-focus-on-open","--window-minimized=yes"])
Result.stdout="--focus-on-open Flag\n"
P.hidden_flags.cache_clear()
try:P.hidden_flags("fake");check("missing minimized capability refuses visible fixture",False)
except RuntimeError:check("missing minimized capability refuses visible fixture",True)
P.subprocess.run=original_run
P.hidden_flags=lambda mpv:["--no-focus-on-open","--window-minimized=yes"]
with tempfile.TemporaryDirectory() as d:
    marker = str(Path(d) / "m/vr-pack-safe")
    os.environ["GOR_VR_PACKS"] = "tb,anaglyph"
    r = fake(d, "exit 0\n")
    out = P.probe(str(r), marker)
    check("all pass: PASS and no marker", out[0].startswith("3D-CHECK vr-pack v1 verdict=PASS") and not os.path.exists(marker), out)
    r = fake(d, 'case "$*" in *vr_pack=anaglyph*) echo "[vo/gpu] shader compile failed: boom" >&2; exit 2;; esac\nexit 0\n')
    out = P.probe(str(r), marker)
    check("one pack fails: FAIL, marker written, others reported", "verdict=FAIL failed=anaglyph" in out[0] and "tb PASS" in " ".join(out) and os.path.exists(marker) and "boom" in " ".join(out), out)
    r = fake(d, "exit 0\n")
    out = P.probe(str(r), marker)
    check("later all-pass removes the marker", out[0].startswith("3D-CHECK vr-pack v1 verdict=PASS") and not os.path.exists(marker), out)
    r = fake(d, "echo 'shader compile failed' >&2; exit 1\n")
    out = P.probe(str(r), marker)
    check("baseline failure: NOT_RUN, marker untouched", "verdict=NOT_RUN reason=baseline_failed" in out[0] and not os.path.exists(marker), out)
    os.environ["GOR_SKIP_VR_PACK_PROBE"] = "1"
    check("skip env gives no lines", P.probe(str(r), marker) == [])
    del os.environ["GOR_SKIP_VR_PACK_PROBE"]
    empty = Path(d) / "e"; (empty / "Resources/vendor/mpv/scripts").mkdir(parents=True); (empty / "Resources/vendor/mpv/scripts/vr180-look.lua").write_text("x")
    os.environ["PATH"] = "/nonexistent"
    out = P.probe(str(empty), marker)
    check("no mpv found is NOT_RUN", "reason=no_mpv" in out[0] or "reason=no_script" in out[0], out)
os.environ['PATH']='/usr/bin:/bin'
os.environ['GOR_VR_PACK_TIMEOUT']='1'
with tempfile.TemporaryDirectory() as d:
    marker=str(Path(d)/'marker');Path(marker).write_text('keep exact bytes')
    r=fake(d,'echo "GPU presented frames"; sleep 10\n')
    import time
    t=time.monotonic(); out=P.probe(str(r),marker)
    check('timeout kills probe process group, stays inconclusive and leaves marker unchanged', time.monotonic()-t<7 and 'NOT_RUN' in out[0] and Path(marker).read_text()=='keep exact bytes' and any('GPU presented frames' in l for l in out),out)
    r=fake(d,'case "$*" in *vr_pack=tb*) sleep 10;; esac\nexit 0\n')
    out=P.probe(str(r),marker)
    check('pack timeout after clean baseline leaves VR marker untouched, never shader FAIL', 'reason=teardown_or_probe_timeout' in out[0] and Path(marker).read_text()=='keep exact bytes',out)
print("FAILURES: %d" % fails)
sys.exit(1 if fails else 0)

# Not covered here (needs the Mac): a real mpv with a real GPU compiling the real vr180-look.lua. The first update capture after this lands shows that
# as the `3D-CHECK vr-pack v1` lines inside the update result commit. Until then the fake-mpv pins above are the only evidence, and Swift is uncompiled.
# Every pin runs in a temp dir; the real marker under ~/Library/Application Support/gor is never touched because the marker path is passed in.
# PATH is cleared in the last pin so a developer machine with mpv installed cannot turn the no_mpv case into a pass.
# The fake mpv is a shell script that inspects its own arguments for the vr_pack value, which is the same switch the real run uses.
# A failing pack is simulated by printing a shader compile failure on stderr and exiting 2, the shape mpv uses for a broken --glsl-shaders / hook.
# The baseline pin proves the safety rule: when even vr_pack=off fails, the probe must not write the marker.
# The all-pass pin after a failure proves the marker is removed again, so a one-off GPU hiccup does not leave packing off for good.
# Run: python3 Tests/VRPackProbe/vr_pack_probe_test.py (exit 0 = all pass).
