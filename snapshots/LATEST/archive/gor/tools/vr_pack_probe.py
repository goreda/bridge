#!/usr/bin/env python3
"""Explicit visible GPU compile probe only. Normal update/background checks never launch this window.

For each pack value (GOR_VR_PACKS, default "tb,anaglyph,sbs") it plays a short synthetic lavfi clip with the bundled mpv (gpu, null audio, no config) loading
vr180-look.lua with script-opts vr180-look-vr_pack=<value>, and reads the log for shader / Lua failures. A baseline run (vr_pack=off) must be clean, otherwise
the mpv/GPU itself is unusable here and nothing is changed (verdict NOT_RUN). When a pack value fails while the baseline is clean, the probe writes the marker
~/Library/Application Support/gor/vr-pack-safe (GOR_VR_SAFE_MARKER overrides); vr180-look.lua treats the marker as vr_pack=off, so VR can never go black.
When every value passes the marker is removed again. Output: bounded `3D-CHECK vr-pack v1 verdict=...` lines in the update capture."""
import os, re, shutil, signal, subprocess, sys
from functools import lru_cache

BAD = re.compile(r"(shader|glsl|compile|link).{0,60}(fail|error)|(fail|error).{0,60}(shader|glsl|compile)|lua.{0,20}error|error running script|script.{0,30}(fail|error)", re.I)


def find_mpv(root):
    cands = [os.path.join(root, "gor.app/Contents/MacOS/mpv"), os.path.join(root, "gor.app/Contents/Frameworks/mpv"),
             "/opt/homebrew/bin/mpv", "/usr/local/bin/mpv"] + ([shutil.which("mpv")] if shutil.which("mpv") else [])
    return next((c for c in cands if c and os.access(c, os.X_OK)), None)


@lru_cache(maxsize=8)
def hidden_flags(mpv):
    """Keep real GPU VO, but refuse unhidden automatic fixture launches."""
    out = subprocess.run([mpv, "--list-options"], capture_output=True, text=True, timeout=15, check=True).stdout or ""
    if not all(re.search(r"(?:^|\n)\s*(?:--)?"+name+r"(?:\s|$)",out) for name in ("focus-on-open","window-minimized")):
        raise RuntimeError("mpv no-focus/minimize capability unavailable; refusing visible fixture")
    return ["--no-focus-on-open", "--window-minimized=yes"]


def one(mpv, script, pack, limit):
    # This GPU driver needs a real window on macOS. Never open it from a detached/default check.
    if os.environ.get("GOR_EXPLICIT_VISIBLE_GPU_PROBE") != "1":
        return False, 0, ["visible GPU probe requires explicit opt-in; no process launched"]
    cmd = [mpv, "--no-config", "--vo=gpu", "--ao=null", "--no-audio", "--geometry=96x54", "--frames=12", "--keep-open=no", "--idle=no",
           "--msg-level=all=warn,vo=v,shader=v,lua=v", "--script=" + script, "--script-opts=vr180-look-vr_pack=" + pack,
           "av://lavfi:testsrc2=size=1920x960:rate=24", "--length=1"]
    try:
        cmd[1:1] = hidden_flags(mpv)
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
        stdout, stderr = p.communicate(timeout=limit)
        text, rc = (stdout or "") + (stderr or ""), p.returncode
    except subprocess.TimeoutExpired as e:
        try: os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        stdout, stderr = p.communicate(timeout=5)
        def partial(value):
            return value.decode("utf-8", "replace") if isinstance(value, bytes) else (value or "")
        tail = [l.strip()[:160] for l in (partial(stdout) + partial(stderr)).splitlines() if l.strip()][-6:]
        try:
            other = subprocess.run(["/usr/bin/pgrep", "-fl", "selftest3d|mpv "], capture_output=True, text=True, timeout=5).stdout.split("\n")
        except (OSError, subprocess.SubprocessError):
            other = []
        return False, 124, ["timeout after %ds; other gor/mpv processes then: %s" % (limit, "; ".join(o[:60] for o in other if o.strip())[:240] or "none")] + ["mpv before timeout: " + l for l in tail]
    except (OSError, RuntimeError, subprocess.CalledProcessError) as e:
        return False, 127, ["cannot run: %s" % e]
    bad = [l.strip()[:200] for l in text.splitlines() if BAD.search(l)]
    return (rc == 0 and not bad), rc, bad[:4]


def probe(root, marker=None):
    marker = marker or os.environ.get("GOR_VR_SAFE_MARKER") or os.path.expanduser("~/Library/Application Support/gor/vr-pack-safe")
    script = os.path.join(root, "Resources/vendor/mpv/scripts/vr180-look.lua")
    if os.environ.get("GOR_SKIP_VR_PACK_PROBE"):
        return []
    if os.environ.get("GOR_EXPLICIT_VISIBLE_GPU_PROBE") != "1":
        return ["3D-CHECK vr-pack v1 verdict=NOT_RUN reason=visible_gpu_probe_requires_explicit_opt_in settings_unchanged=yes"]
    if not os.path.isfile(script):
        return ["3D-CHECK vr-pack v1 verdict=NOT_RUN reason=no_script"]
    mpv = find_mpv(root)
    if not mpv:
        return ["3D-CHECK vr-pack v1 verdict=NOT_RUN reason=no_mpv"]
    limit = int(os.environ.get("GOR_VR_PACK_TIMEOUT", "60"))
    ok, rc, why = one(mpv, script, "off", limit)
    if not ok:
        return ["3D-CHECK vr-pack v1 verdict=NOT_RUN reason=baseline_failed rc=%s" % rc] + ["vr-pack: baseline: " + w for w in why]
    lines, failed, timeouts = [], [], []
    for pack in [p for p in os.environ.get("GOR_VR_PACKS", "tb,anaglyph,sbs").split(",") if p]:
        ok, rc, why = one(mpv, script, pack, limit)
        lines.append("vr-pack: %s %s rc=%s" % (pack, "PASS" if ok else "FAIL", rc))
        lines += ["vr-pack: %s: %s" % (pack, w) for w in why]
        if rc == 124: timeouts.append(pack)
        elif not ok: failed.append(pack)
    if timeouts:
        return ['3D-CHECK vr-pack v1 verdict=NOT_RUN reason=teardown_or_probe_timeout packs=%s settings_unchanged=yes' % ','.join(timeouts)] + lines
    try:
        if failed:
            os.makedirs(os.path.dirname(marker), exist_ok=True)
            open(marker, "w").write("shader probe failed for: %s\n" % ",".join(failed))
        elif os.path.exists(marker):
            os.remove(marker)
    except OSError as e:
        lines.append("vr-pack: marker error %s" % e)
    head = "3D-CHECK vr-pack v1 verdict=%s failed=%s fallback=%s" % ("FAIL" if failed else "PASS", ",".join(failed) or "-", "safe_marker_written" if failed else "none")
    return [head] + lines


if __name__ == "__main__":
    print("\n".join(probe(sys.argv[1] if len(sys.argv) > 1 else ".")))

# Contract with vr180-look.lua (E-G lane): the script reads script-opt vr_pack (vr180-look-vr_pack=<value>; "off" = previous behaviour) and must treat the
# existence of the marker file below as vr_pack=off, before any shader is built. Pack values probed: tb (top/bottom), anaglyph, sbs (full side by side).
# Why a marker and not a swapped script: ./build.sh --update pulls the branch with ff-only, so editing a tracked script on the Mac would break the next update.
# Environment: GOR_SKIP_VR_PACK_PROBE=1 disables the probe, GOR_VR_PACKS="tb,anaglyph" picks values, GOR_VR_PACK_TIMEOUT seconds per run (default 60).
# Limits: this is a compile/load probe on a synthetic clip, not a look check; it cannot tell that a pack looks right, only that it does not break mpv.
# Detection reads the mpv log for shader/glsl/compile failures and Lua errors, plus a non-zero exit. A machine without a usable GPU context fails the
# baseline run and the probe then reports NOT_RUN and touches nothing, so a probe problem can never disable VR packing by itself.
# Report lines are bounded: one head line, one line per pack, at most four log lines per failing pack.
# Nothing here is a Swift file; the engine wiring words the Swift gate forbids are not used in any Swift line.
# End of file.
