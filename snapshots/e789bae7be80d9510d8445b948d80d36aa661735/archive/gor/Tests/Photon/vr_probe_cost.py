#!/usr/bin/env python3
"""photon VR probe cost, NATIVE-RENDER on Linux (mpv 0.41 under Xvfb + Mesa llvmpipe software GL; NOT the owner's GPU, so
absolute ms are not Mac numbers: compare configs against the novr baseline run on the same box).
Usage: GOR_TEST_MPV=<mpv 0.41> vr_probe_cost.py OUTDIR TAG    TAG in novr | nophoton | ungated | gate | sparse
  novr     normal playback (stereo-window-owned never set)               = baseline
  nophoton VR window, photon.lua removed from the config copy              = yesterday's (92f553a2) behaviour: photon.lua did not load there
  uncapped sparse + both ffmpeg caps raised to 99 in the config copy        = ffmpeg concurrency as before the manager
  iso-*    MEASUREMENT ONLY: sparse + the named shader file(s) overwritten with a 1-pass passthrough 1.5 s after VR engage, then re-listed (photon re-adds a removed path and reloads the file) (grain, sharp, vr180, grainsharp)
  nogamma  MEASUREMENT ONLY: sparse with photon's mp.set_property_number("gamma", ...) calls made no-ops in the config copy
  noffmpeg MEASUREMENT ONLY: sparse with both ffmpeg caps set to 0 in the config copy (no photon ffmpeg child ever runs)
  cap1     MEASUREMENT ONLY: cap1 = VR cap 1 without nice;  cap1nice = the shipped VR path (cap 1 + nice -n 19, identical to the working tree)
  cap3     CONTROL: sparse with the VR ffmpeg cap raised to 3 and no nice (= 11f2fdda behaviour in VR)
  ungated  VR window, probes read back synchronously as before a885488  (vr_window forced false in the config copy)
  gate     VR window, a885488 behaviour (COST.VR.mode = "off")
  sparse   VR window, the shipped path: paced async capture shared by all probes + ffmpeg cap 1 under nice -n 19 (working tree)
Same clip, same VR engage sequence (vr180-look enabled + projection + stereo-window-owned) as Tests/VRShader/photon-vr-cost.py.
Metric: mpv --dump-stats 'video-draw' spans (video + user shaders) over the 20 s steady VR window, drops, CPU, and the
max concurrent ffmpeg processes (polled /proc every 0.1 s over 10-36 s), photon log counts of readbacks (sync) and paced captures (async) with probe frames served."""
import json, os, re, shutil, socket, statistics, subprocess, sys, time
from pathlib import Path
root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]); tag = sys.argv[2]; ISO = {"iso-grain": ["photon-grain"], "iso-sharp": ["photon-sharp"], "iso-vr180": ["vr180-look"], "iso-grainsharp": ["photon-grain", "photon-sharp"]}
assert tag in tuple(ISO) + ("nogamma", "noffmpeg", "cap3", "cap1", "cap1nice", "novr", "nophoton", "uncapped", "ungated", "gate", "sparse")
out.mkdir(parents=True, exist_ok=True)
mpv = os.environ["GOR_TEST_MPV"]; ffmpeg = os.environ.get("FFMPEG", "ffmpeg")
clip = out / "sbs-1920x540-40s.mp4"
if not clip.exists():
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc2=size=960x540:rate=30",
        "-f", "lavfi", "-i", "mandelbrot=size=960x540:rate=30", "-filter_complex", "[0][1]hstack[v]", "-map", "[v]",
        "-t", "40", "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", str(clip)], check=True)
cfg = out / ("cfg-" + tag)
shutil.rmtree(cfg, ignore_errors=True); shutil.copytree(root / "Resources/vendor/mpv", cfg)
ph = cfg / "scripts/photon.lua"; s = ph.read_text()
s = s.replace('pcall(mp.command_native, {"screenshot-raw", "video"})', 'pcall(function() mp.msg.info("harness-readback sync"); return mp.command_native({"screenshot-raw", "video"}) end)', 1)
if tag == "ungated":
    s = s.replace("function COST.vr_window()\n", "function COST.vr_window()\n    if true then return false end\n", 1)
if tag == "gate":
    assert 'COST.VR = { mode = "sparse"' in s; s = s.replace('COST.VR = { mode = "sparse"', 'COST.VR = { mode = "off"', 1)
ph.write_text(s)
if tag == 'uncapped':
    assert 'cap = 3, vr_cap = 1' in s; ph.write_text(s.replace('cap = 3, vr_cap = 1', 'cap = 99, vr_cap = 99', 1))
if tag == 'nogamma':
    assert s.count('mp.set_property_number("gamma",') >= 3
    ph.write_text(s.replace('mp.set_property_number("gamma",', 'pcall(mp.set_property_number, "photon-noop-gamma",'))
if tag == 'noffmpeg':
    assert 'cap = 3, vr_cap = 1' in s; ph.write_text(s.replace('cap = 3, vr_cap = 1', 'cap = 0, vr_cap = 0', 1))
if tag == 'cap3':
    assert 'vr_cap = 1, vr_nice = 19' in s
    ph.write_text(s.replace('vr_cap = 1, vr_nice = 19', 'vr_cap = 3, vr_nice = 0', 1).replace('"exec nice -n " .. FF.vr_nice .. " "', '"exec "', 1))
if tag in ('cap1', 'cap1nice'):
    assert 'vr_cap = 1, vr_nice = 19' in s
    if tag == 'cap1': s = s.replace('"exec nice -n " .. FF.vr_nice .. " "', '"exec "', 1)   # cap 1 without nice
    ph.write_text(s)
if tag == 'nophoton': ph.unlink()
sock, logp, dump = out / f"s-{tag}.sock", out / f"mpv-{tag}.log", out / f"ds-{tag}.txt"
for p in (sock, dump): p.unlink(missing_ok=True)
def ipc(*a):
    with socket.socket(socket.AF_UNIX) as c:
        c.settimeout(15); c.connect(str(sock)); c.sendall(json.dumps({"command": list(a)}).encode() + b"\n"); buf = b""
        while True:
            buf += c.recv(65536)
            while b"\n" in buf:
                l, buf = buf.split(b"\n", 1); j = json.loads(l)
                if "error" in j: return j
def jiff(pid):
    p = Path("/proc/%d/stat" % pid).read_text().rsplit(")", 1)[1].split(); return int(p[11]) + int(p[12])
ffmax = [0]; neutered = []
def n_ffmpeg():
    c = 0
    for d in Path("/proc").iterdir():
        if d.name.isdigit():
            try:
                if (d / "comm").read_text().strip() == "ffmpeg": c += 1
            except OSError: pass
    return c
HZ = os.sysconf("SC_CLK_TCK")
cmd = [mpv, "--config-dir=" + str(cfg), "--vo=gpu-next", "--gpu-context=x11egl", "--gpu-sw=yes", "--ao=null", "--pause=no",
       "--input-ipc-server=" + str(sock), "--log-file=" + str(logp), "--dump-stats=" + str(dump), "--vd-lavc-threads=2",
       "--script-opts-add=photon-scriptdir=" + str(cfg / "scripts"), "--script-opts-add=gor-diag=true", str(clip)]
t0 = time.monotonic()
proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    while time.monotonic() - t0 < 20 and not sock.exists(): time.sleep(.1)
    while time.monotonic() - t0 < 8: time.sleep(.1)
    if tag != "novr":
        ipc("script-message-to", "vr180_look", "vr180-look-set-enabled", "true")
        ipc("script-message-to", "vr180_look", "vr180-look-set-projection", "vr180", "0")
        ipc("set_property", "user-data/gor/stereo-window-owned", True)
        if tag in ISO:
            time.sleep(1.5)
            for f in (cfg / "shader").glob("*.glsl"):
                if any(k in f.name for k in ISO[tag]):
                    f.write_text("//!HOOK MAIN\n//!BIND HOOKED\n//!DESC passthrough\nvec4 hook() { return HOOKED_texOff(0); }\n"); neutered.append(f.name)
            cur = (ipc("get_property", "glsl-shaders") or {}).get("data") or []
            ipc("set_property", "glsl-shaders", [x for x in cur if not any(k in x for k in ISO[tag])]); time.sleep(1.0)
            ipc("set_property", "glsl-shaders", cur)
    cpu = []
    while time.monotonic() - t0 < 36:
        a, ja = time.monotonic(), jiff(proc.pid)
        for _ in range(5):
            time.sleep(.1); n = n_ffmpeg(); ffmax[0] = max(ffmax[0], n)
        b, jb = time.monotonic(), jiff(proc.pid)
        if b - t0 > 10: cpu.append(100.0 * (jb - ja) / HZ / (b - a))
    drops = (ipc("get_property", "frame-drop-count") or {}).get("data")
    shaders = (ipc("get_property", "glsl-shaders") or {}).get("data"); vfs = (ipc("get_property", "vf") or {}).get("data")
    ipc("quit"); proc.wait(timeout=15)
finally:
    if proc.poll() is None: proc.kill()
log = logp.read_text(errors="replace")
ev = []
for l in dump.read_text(errors="replace").splitlines():
    p = l.split(" ", 2)
    if len(p) == 3 and p[0].isdigit(): ev.append((int(p[0]), p[1], p[2]))
tmax = ev[-1][0]; tmin = tmax - 20_000_000_000
o, d, dv = None, [], 0
for t, k, n in ev:
    if t < tmin: continue
    if n == "video-draw" and k == "start": o = t
    elif n == "video-draw" and k == "end" and o is not None: d.append((t - o) / 1e6); o = None
    elif k == "drop-vo": dv += 1
d.sort()
caps = re.findall(r"vr probe capture ([\d.]+) ms \(n=(\d+) fail=(\d+) served=(\d+) skipped=(\d+)", log)
res = {"tag": tag, "mpv": subprocess.run([mpv, "--version"], capture_output=True, text=True).stdout.splitlines()[0],
       "date": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "window_s": 20, "video_draw_n": len(d),
       "video_draw_ms": {"mean": round(statistics.fmean(d), 2), "p50": round(d[len(d)//2], 2), "p95": round(d[int(len(d)*.95)], 2), "max": round(d[-1], 2)} if d else None,
       "drop_vo_in_window": dv, "frame_drop_count": drops, "cpu_pct_mean": round(statistics.fmean(cpu), 1),
       "neutered": neutered, "glsl_shaders": [x.rsplit("/",1)[-1] for x in (shaders or [])], "vf_n": len(vfs or []), "max_concurrent_ffmpeg": ffmax[0], "sync_readbacks_total": log.count("harness-readback sync"), "paced_captures": len(caps),
       "capture_ms_max": max([float(c[0]) for c in caps], default=None),
       "probe_frames_served": int(caps[-1][3]) if caps else None, "probe_frames_skipped": int(caps[-1][4]) if caps else None,
       "photon_errors": [l for l in log.splitlines() if "photon" in l.lower() and re.search(r"error|syntax", l, re.I)][:5]}
(out / f"vr-probe-cost-{tag}.json").write_text(json.dumps(res, indent=1)); print(json.dumps(res, indent=1))
