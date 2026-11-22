#!/usr/bin/env python3
"""s43: first-Mac-run risk walk, Linux model tests for the update+launch path
(cd ~/Downloads/gor && ./build.sh --update, then app launch + 3D menu).

One pin per step whose failure would be SILENT. Steps already covered by
their own suites (kit fetch: Tests/ThreeDKit/kit_fetch_test.py; models:
Tests/ThreeDModels; menu: Tests/ThreeDMenu; gate: Tests/StereoSource;
degrade FSM: Tests/ThreeDDegrade) are not duplicated here.

Run: python3 Tests/FirstRun/test_first_run_risk.py
"""
import os
import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[2]
S = root / "Sources" / "gor"
ad = (S / "AppDelegate.swift").read_text()
menu = (S / "ThreeDMenu.swift").read_text()
build = (root / "build.sh").read_text()
bad = 0


def check(n, ok):
    global bad
    print(("PASS " if ok else "FAIL ") + n)
    bad += (not ok)


# T1: log-writer launch failure must NOT lose the gor log: the catch reopens
# the same log path directly and writes a named line. Without this the whole
# s39/s40/s41 first-log pipeline goes blind with no sign why.
catch = ad[ad.index("} catch {", ad.index("gor-log-writer")):]
catch = catch[:catch.index("setbuf(stdout")]
check("T1 log-writer fallback: freopen the same log + named loss line",
      'freopen(logPath, "a", stdout)' in catch
      and 'freopen(logPath, "a", stderr)' in catch
      and "log telemetry unavailable" in catch)

# T2: the bundle must actually carry the writer binary and its config, or the
# first launch has no log at all (silent until someone looks).
check("T2 build.sh installs gor-log-writer + gor-log-config.json into the bundle",
      "gor-log-writer" in build and 'gor-log-config.json' in build
      and 'Contents/MacOS' in build)

# T3: a malformed gor-log-config.json must fall back to defaults, never crash
# or disable the log silently.
cfg = ad[ad.index("gor-log-config"):ad.index("let writer = Process()")]
check("T3 log config: malformed json -> timestamp/cpu_info default true",
      'config["timestamp"] ?? true' in cfg and 'config["cpu_info"] ?? true' in cfg)

# T4: every gor.3d.* UserDefaults key read/written outside ThreeDMenu must be
# a key ThreeDMenu itself loads and persists (a reader the menu does not know
# diverges silently), and absent-key defaults must agree with the menu
# defaults.
menu_keys = set(re.findall(r'"gor\.3d\.(\w+)"', menu))
others = {}
for f in S.glob("*.swift"):
    if f.name == "ThreeDMenu.swift":
        continue
    for m in re.finditer(r'forKey:\s*"gor\.3d\.(\w+)"', f.read_text()):
        others.setdefault(m.group(1), f.name)
unknown = {k: v for k, v in others.items() if k not in menu_keys}
check("T4 gor.3d.* keys read elsewhere are all menu-owned " +
      (str(others) if others else "(none)"), not unknown)
fps = (S / "FilmPrepareStatus.swift").read_text()
check("T4b osdLine absent-key default (show) matches the menu default (true)",
      'object(forKey: "gor.3d.osdLine") != nil, !UserDefaults.standard.bool' in fps
      and "osdLine = true" in menu)

# T5: the fetch script's gh path fails LOUD when gh is absent (the exact
# first-run situation on a Mac without the GitHub CLI): rc 1 and a named
# FAIL line, never a silent skip. Runs the real script with a stripped PATH.
lock = "id\tstatus\tlicense\trepo\trevision\tfile\tsha256\tbytes\tuse\n" \
    "vda-coreml-kit\tusable\tApache-2.0\thttps://github.com/goreda/gorav\t" \
    "gor-kit-2026-11-09\tkit.tar\t" + "0" * 64 + "\t1\tx\n"
with tempfile.TemporaryDirectory() as d:
    t = pathlib.Path(d)
    (t / "lock.tsv").write_text(lock)
    minimal = t / "bin"
    minimal.mkdir()
    for tool in ("bash", "shasum", "sha256sum", "mkdir", "cat", "rm", "tar",
                 "grep", "tr", "sort", "cut", "dirname", "printf", "mv", "cp",
                 "command", "curl"):
        p = subprocess.run(["/bin/bash", "-c", f"command -v {tool}"],
                           capture_output=True, text=True).stdout.strip()
        if p and os.path.exists(p):
            try:
                os.symlink(p, minimal / os.path.basename(p))
            except FileExistsError:
                pass
    env = {"PATH": str(minimal),
           "GOR_MODELS_LOCK": str(t / "lock.tsv"),
           "GOR_MODELS_DIR": str(t / "m"),
           "HOME": str(t)}
    r = subprocess.run(["/bin/bash", str(root / "tools/gor-fetch-models.sh")],
                       env=env, capture_output=True, text=True, timeout=60)
    check("T5 gh absent and no GitHub sign-in: rc 1 + one plain FAIL line naming the single need (83e169e8 contract)",
          r.returncode == 1 and "needs a GitHub sign-in" in (r.stdout + r.stderr))

# T6: render-prefs.json missing/corrupt -> documented defaults, never a crash
# or a zero/garbage screen geometry.
rp = (S / "RenderPrefsReader.swift").read_text()
check("T6 render-prefs: missing/corrupt file -> RenderPrefsValue() defaults",
      "else { return RenderPrefsValue() }" in rp
      and "m == nil ? RenderPrefsValue()" in rp
      and "defaultScreenDeg" in rp)

# T7 (fixed, s43): StagedRunPaths.prepare() failing used to exit the app BEFORE the log writer starts with no evidence anywhere. quitDebug writes
# Library/Logs/gor/quit-debug.log without the writer; the line replaces the old one (net zero, AppDelegate ceiling 3706).
guard = re.search(r"guard StagedRunPaths\.prepare\(\) else \{[^}]*\}", ad)
body = guard.group(0) if guard else ""
check("T7 staged-prepare failure leaves a quit-debug line before exit(1)",
      'quitDebug("staged prepare failed")' in body and body.index("quitDebug") < body.index("exit(1)") and len(ad.split("\n")) - 1 <= 3706)

print("first-run risk: " + ("all pins hold" if not bad else f"{bad} FAIL"))
sys.exit(1 if bad else 0)
