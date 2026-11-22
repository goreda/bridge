#!/usr/bin/env python3
"""X1 (owner 14:48) pins: tools/update_3d_check.py, the 3D first-Mac check that runs inside `./build.sh --update`, run as a subprocess against a fake project
(stub gor.app binary, REAL mac_log_check + expected file). Plus text pins for the build.sh hook (non-blocking, rides the existing result) and for the Swift
headless flag / per-shot play log. NOT covered: a real compile, CoreML/Metal, a real update run on a Mac (Linux only, Swift uncompiled).
Run: python3 Tests/Update3DCheck/update_3d_check_test.py
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import time, os, re, shutil, subprocess, sys, tempfile, importlib.util
from pathlib import Path

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "Tests" / "DepthAnalysis"))
from test_mac_log_check import GOOD  # noqa: E402  (importing it also runs its own pins)

fails = 0


def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ((" :: " + str(extra)[:600]) if (extra and not ok) else ""))
    fails += 0 if ok else 1


good_log = re.sub(r"^\[[^\]]*\] ", "", GOOD, flags=re.M)   # a real stdout log has no timestamp prefix
tmp = Path(tempfile.mkdtemp(prefix="u3d-"))


def project(name, body):
    """A fake built project: gor.app stub whose --selftest3d prints `body`, real depth_analysis tools."""
    p = tmp / name
    (p / "gor.app/Contents/MacOS").mkdir(parents=True)
    (p / "tools/depth_analysis").mkdir(parents=True)
    for name in ("gor_step.py", "step_seeds.json"):
        shutil.copy(ROOT / "tools" / name, p / "tools" / name)
    for f in (ROOT / "tools/depth_analysis").glob("*"):
        if f.is_file() and f.suffix in (".py", ".json"):
            shutil.copy(f, p / "tools/depth_analysis" / f.name)
    (p / "good.log").write_text(good_log)
    exe = p / "gor.app/Contents/MacOS/gor"
    exe.write_text('#!/bin/bash\n[ "$1" = "--selftest3d" ] || exit 9\n' + body)
    exe.chmod(0o755)
    return p


BEGIN = 'echo "gor3d-selftest-cli v1 begin build=stub kit=/k"\n'
END = 'echo "gor3d-selftest-cli v1 end code=0 errors=0 meaning=ok"\n'
CAT = 'cat "$(dirname "$0")/../../../good.log"\n'


def run(p, *extra, applog=None):
    args = [sys.executable, str(ROOT / "tools/update_3d_check.py"), str(p)] + list(extra)
    if applog:
        args += ["--app-log", str(applog)]
    return subprocess.run(args, capture_output=True, text=True, env=dict(os.environ, HOME="/Users/someone"))


applog = tmp / "gor_direct.log"
applog.write_text("noise\ngor3d-shot v1 shot=3 pts=1.000 menu_mode=vr180 parsed=yes method=dibr_golden key=v4|x\ngor3d-osd v1 3D fallback\n3d-synth: dibr_golden\nother\n")
r = run(project("ok", BEGIN + CAT + END), applog=applog)
check("pass: verdict PASS, exit 0", r.returncode == 0 and "verdict=PASS" in r.stdout, r.stdout + r.stderr)
check("pass: per-family lines and checker text present", "3D-CHECK family" in r.stdout and "MAC-LOG PASS" in r.stdout and r.stdout.startswith("BEGIN 3D check") and r.stdout.rstrip().endswith("END 3D check"))
check("pass: app-log per-shot and OSD lines carried, noise dropped", "app-log: gor3d-shot v1 shot=3" in r.stdout and "app-log: gor3d-osd v1" in r.stdout and "noise" not in r.stdout)
check("output is bounded", len(r.stdout.splitlines()) < 450, len(r.stdout.splitlines()))

#194s: real stage begin lines are not additional CLI runs; errors still fail.
stages = 'echo "gor3d-selftest-cli v1 stage self-test total begin t=0.0"\necho "gor3d-selftest-cli v1 stage render vr180 begin t=1.0"\n'
r = run(project("nested", BEGIN + stages + CAT + END))
check("nested stage begins: complete PASS invocation", "verdict=PASS" in r.stdout and "cli_complete=True" in r.stdout, r.stdout)
r = run(project("nested-fail", BEGIN + stages + CAT + 'echo "gor3d-selftest-cli v1 end code=2 errors=5 meaning=failed"\nexit 2\n'))
check("nested stage failure stays FAIL with complete CLI and errors5", "verdict=FAIL" in r.stdout and "cli_complete=True" in r.stdout and "errors=5" in r.stdout and "rc=2" in r.stdout, r.stdout)
r = run(project("duplicate-begin", BEGIN + BEGIN + CAT + END))
check("two invocation begins remain incomplete FAIL", "verdict=FAIL" in r.stdout and "cli_complete=False" in r.stdout, r.stdout)

r = run(project("missfam", BEGIN + 'sed "/rtstage name=surround/d" "$(dirname "$0")/../../../good.log"\n' + END))
check("missing family: verdict FAIL, still exit 0", r.returncode == 0 and "verdict=FAIL" in r.stdout and "MISSING" in r.stdout, r.stdout)
r = run(project("cut", BEGIN + CAT))
check("log cut short (no end line): FAIL", r.returncode == 0 and "verdict=FAIL" in r.stdout and "cli_complete=False" in r.stdout, r.stdout)
r = run(project("kit", BEGIN + 'echo "gor3d-selftest-cli v1 kit_missing encoder_fp16.mlpackage"\necho "gor3d-selftest-cli v1 end code=3 errors=0 meaning=x"\nexit 3\n'))
check("kit missing: NOT_RUN(kit_missing), exit 0", r.returncode == 0 and "verdict=NOT_RUN(kit_missing)" in r.stdout, r.stdout)
r = run(project("slow", "sleep 20\n"), "--timeout", "1")
check("timeout is a FAIL line, not a hang", r.returncode == 0 and "verdict=FAIL" in r.stdout and "timeout" in (tmp / "slow/.gor-3d-check-last.log").read_text(), r.stdout)
empty = tmp / "noapp"; empty.mkdir()
r = run(empty)
check("no built app: NOT_RUN, exit 0", r.returncode == 0 and "reason=no_built_app" in r.stdout, r.stdout)
r = run(project("home", BEGIN + 'echo "gor3d-selftest-cli v1 note /Users/someone/Library/x"\n' + CAT + END))
check("home path scrubbed", "/Users/someone" not in r.stdout)
r = subprocess.run([sys.executable, str(ROOT / "tools/update_3d_check.py")], capture_output=True, text=True)
check("no args: usage, exit 0", r.returncode == 0 and "Usage:" in r.stdout)

# model fetch before the self-test: the update itself brings the kit, failures are reported, nothing blocks
fp = project("fetch", BEGIN + CAT + END)
(fp / "tools").mkdir(exist_ok=True)
(fp / "tools/gor-fetch-models.sh").write_text('#!/bin/bash\necho "kit  vda-coreml-kit installed"\ntouch "$(dirname "$0")/../FETCHED"\n')
r = run(fp)
check("fetch script runs first and its output is in the report", (fp / "FETCHED").exists() and "3D-CHECK fetch-models rc=0" in r.stdout and "fetch: kit  vda-coreml-kit installed" in r.stdout and r.stdout.index("fetch-models") < r.stdout.index("3D-CHECK v1 verdict"), r.stdout)
(fp / "tools/gor-fetch-models.sh").write_text('#!/bin/bash\necho "FAIL moge2-coreml-kit: gh not signed in (run gh auth login)" >&2\nexit 1\n')
r = run(fp)
check("fetch failure is reported verbatim, update check still exits 0", r.returncode == 0 and "fetch-models rc=1" in r.stdout and "gh not signed in" in r.stdout and "verdict=PASS" in r.stdout, r.stdout)
(fp / "tools/gor-fetch-models.sh").write_text("#!/bin/bash\nsleep 20\n")
r = subprocess.run([sys.executable, str(ROOT / "tools/update_3d_check.py"), str(fp)], capture_output=True, text=True, env=dict(os.environ, GOR_UPDATE_3D_FETCH_TIMEOUT="1"))
check("fetch timeout is a line, not a hang", r.returncode == 0 and "fetch-models rc=124" in r.stdout, r.stdout)
(fp / "FETCHED").unlink(missing_ok=True) if hasattr(Path, "unlink") else None
(fp / "tools/gor-fetch-models.sh").write_text('#!/bin/bash\ntouch "$(dirname "$0")/../FETCHED"\n')
r = subprocess.run([sys.executable, str(ROOT / "tools/update_3d_check.py"), str(fp)], capture_output=True, text=True, env=dict(os.environ, GOR_SKIP_3D_FETCH="1"))
check("GOR_SKIP_3D_FETCH skips the fetch", not (fp / "FETCHED").exists() and "fetch-models" not in r.stdout)

# no-prompt pin: the fetch must never wait on a credential prompt or stdin, and must say what it is doing
(fp / "tools/gor-fetch-models.sh").write_text('#!/bin/bash\necho "env $GIT_TERMINAL_PROMPT $GH_PROMPT_DISABLED $GCM_INTERACTIVE"\nread -t 3 x && echo "STDIN-READABLE" || echo "stdin-closed"\n')
r = run(fp)
check("fetch runs with prompts disabled and stdin closed", "fetch: env 0 1 never" in r.stdout and "stdin-closed" in r.stdout and "STDIN-READABLE" not in r.stdout, r.stdout)
src = (ROOT / "tools/update_3d_check.py").read_text()
check("fetch streams progress to the terminal with a 30 s heartbeat", 'say("3D kit download starting' in src and "last >= 30" in src and "/dev/tty" in src)
check("start line names download and on-disk size", "about 1.1 GB download, about 1.85 GB on disk" in src)
check("git credential fill cannot prompt", "GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GIT_ASKPASS=/usr/bin/true git credential fill" in (ROOT / "tools/gor-fetch-models.sh").read_text())

# stall watchdog: a selftest whose log stops growing is stopped early, sampled, and reported; a stale-forever writer loop cannot eat the 20 min budget
sp = project("stall", "echo begin; sleep 30\n")
t0 = time.time()
r = subprocess.run([sys.executable, str(ROOT / "tools/update_3d_check.py"), str(sp)], capture_output=True, text=True, env=dict(os.environ, GOR_UPDATE_3D_STALL="2", GOR_SKIP_3D_FETCH="1", GOR_SKIP_VR_PACK_PROBE="1"))
check("stalled selftest is stopped early and reported", r.returncode == 0 and time.time() - t0 < 25 and "stalled seconds=" in (sp / ".gor-3d-check-last.log").read_text() and "verdict=FAIL" in r.stdout, (time.time() - t0, r.stdout))
swift = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDSelfTest.swift'+' '):_b.index('// END relocated '+'ThreeDSelfTest.swift'+'\n')])((_threed_split().path(ROOT)).read_text())
check("clip writer loop is bounded (E-G e22a969b4 version)", "writerStallLimit" in swift and "while !input.isReadyForMoreMediaData { Thread" not in swift)
check("finishWriting wait is bounded", "g.wait(timeout: .now() + writerStallLimit) == .timedOut" in swift and "g.wait()" not in swift)

# retirement of the abandoned kit's launchd job: only when present, only that plist
fh = tmp / "fakehome"; (fh / "Library/LaunchAgents").mkdir(parents=True)
other = fh / "Library/LaunchAgents/com.other.job.plist"; other.write_text("x")
kit_plist = fh / "Library/LaunchAgents/com.gor.first-mac-kit.plist"
fb = tmp / "fakebin"; fb.mkdir(); (fb / "launchctl").write_text('#!/bin/sh\necho "$@" >> "%s/lc.log"\n' % tmp); (fb / "launchctl").chmod(0o755)
fenv = dict(os.environ, HOME=str(fh), PATH=str(fb) + ":" + os.environ["PATH"])
cmd = [sys.executable, str(ROOT / "tools/update_3d_check.py"), str(empty)]
r = subprocess.run(cmd, capture_output=True, text=True, env=fenv)
check("kit job absent: no-op, launchctl not called", r.returncode == 0 and "first-mac-kit" not in r.stdout and not (tmp / "lc.log").exists(), r.stdout)
kit_plist.write_text("<plist/>")
r = subprocess.run(cmd, capture_output=True, text=True, env=fenv)
check("kit job present: bootout called, plist removed, other jobs untouched", r.returncode == 0 and "retired launchd job com.gor.first-mac-kit" in r.stdout and not kit_plist.exists() and other.exists() and "bootout" in (tmp / "lc.log").read_text(), r.stdout)
r = subprocess.run(cmd, capture_output=True, text=True, env=fenv)
check("second run is a no-op again", "first-mac-kit" not in r.stdout)

# build.sh hook pins: ONE changed line inside gor_update_result_commit, no net lines (build.sh sits on its size ceiling)
b = (ROOT / "build.sh").read_text()
res = b[b.index("gor_update_result_commit() {"):b.index("gor_update_exit_trap() {")]
hook = [l for l in res.splitlines() if "update_3d_check.py" in l]
check("exactly one hook line, inside the result commit", len(hook) == 1, hook)
h = hook[0] if hook else ""
check("hook runs only after a fresh update selftest, is skippable, and cannot fail the update", 'update_results_fresh" = true' in h and "GOR_SKIP_3D_CHECK" in h and "2>&1 || :)" in h)
check("hook line follows the subtitle probe and precedes the failure-custody block", res.index("subtitle-capture.py") < res.index("update_3d_check.py") < res.index("Failure custody"))
check("build.sh is valid bash", subprocess.run(["bash", "-n", str(ROOT / "build.sh")]).returncode == 0)

# Swift text pins (not compiled)
sw = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDSelfTestCLI.swift'+' '):_b.index('// END relocated '+'ThreeDSelfTestCLI.swift'+'\n')])((_threed_split().path(ROOT)).read_text()); mn = (ROOT / "Sources/gor/App/main.swift").read_text()
check("main.swift exits before NSApplication on the flag", mn.index("ThreeDSelfTestCLI.requested") < mn.index("NSApplication.shared"))
check("Swift begin/end shapes match the checker", 'gor3d-selftest-cli v1 begin ' in sw and 'gor3d-selftest-cli v1 end code=' in sw and "errors=" in sw and "kit_missing" in sw)
check("headless run leaves the app's once-per-build marker alone", 'appendingPathComponent("gor3d-selftest-cli-' in sw)
pl = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDShotPlayLog.swift'+' '):_b.index('// END relocated '+'ThreeDShotPlayLog.swift'+'\n')])((_threed_split().path(ROOT)).read_text()); co = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])((_threed_split().path(ROOT)).read_text())
tmpl = [l.strip() for l in co.splitlines() if l.strip().startswith('return "v5|')][0][len('return "'):-1]
slots = re.split(r"\|", re.sub(r"\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)", "S", tmpl))
check("render key v5 template has 11 slots", len(slots) == 11, slots)
check("play log field arithmetic matches (9 + ipd fields)", "parts.count == 9 + ipdLen" in pl and "comfort ? 3 : 2" in pl)
check("coordinator logs shot at show, OSD before the toggle, shotEnded at 2D", "ThreeDShotPlayLog.logShot(shot: hit.shot" in co and co.index("ThreeDShotPlayLog.logOSD(text)") < co.index("guard MainActor.assumeIsolated({ThreeDStore.shared.snapshot.effects[.osdLine] != .bool(false)})") and "ThreeDShotPlayLog.shotEnded()" in co)
check("no forbidden engine words in the new Swift", not re.search(r"\b(MPVCommand|ipcCommand|IPCClient|PersistentEventConnection)\b|mpv\.conf", sw + mn + pl, re.I))

check('shot logger accepts v5 span prefix without dropping parsed fields', 'parts[0] == "v5", parts[1] == "span-p5p95"' in pl and 'parts.remove(at: 1)' in pl)
# Previous failure is captured before launching the next run, bounded and home-scrubbed.
prior=project('prior-result', BEGIN+CAT+END)
(prior/'.gor-3d-check-background.log').write_text('private noise '*20000+'\n3d-load end package=bootstrap_fp16.mlpackage device=cpuOnly elapsed_ms=30000 outcome=timeout\n3D-CHECK v1 verdict=FAIL rc=2 seconds=498 cli_complete=True selftest_exit=2 errors=1\n')
sp=importlib.util.spec_from_file_location('u3d',ROOT/'tools/update_3d_check.py');mod=importlib.util.module_from_spec(sp);sp.loader.exec_module(mod)
evidence='\n'.join(mod.previous_evidence(str(prior),str(applog)))
check('previous failure and model stage are available before relaunch, bounded/no unrelated raw lines', 'verdict=FAIL rc=2 seconds=498' in evidence and 'package=bootstrap_fp16.mlpackage' in evidence and 'private noise' not in evidence and len(evidence)<200000)
# Actual detached launch returns before a slow worker, with all output fds closed.
p = project('background', 'sleep 1\necho "gor3d-selftest-cli v1 stage load bootstrap_fp16.mlpackage end ms=1000 t=1.0"\n' + BEGIN + CAT + END)
start=time.monotonic(); rr=run(p, '--background', applog=applog)
check('background launcher returns in <1s without waiting for CoreML', time.monotonic()-start<1 and 'background STARTED' in rr.stdout, rr.stdout)
bg=p/'.gor-3d-check-background.log'
for _ in range(60):
    if bg.exists() and 'END 3D check' in bg.read_text(): break
    time.sleep(.1)
check('background result is reported later in log', bg.exists() and 'END 3D check' in bg.read_text() and 'background-result:' in applog.read_text())
check('only completed CoreML loads become measured history', '1000' in (p/'.gor-coreml-load-history.jsonl').read_text())
failedlaunch=run(tmp/'missing-root', '--background')
check('background launch failure exits 0 with explicit NOT_STARTED, never blocks update', failedlaunch.returncode==0 and 'NOT_STARTED' in failedlaunch.stdout)
check('STARTED line names expected-duration evidence and hard bound without inventing a successful first-load measurement', 'expected_duration=' in rr.stdout and 'total_limit_s=1800' in rr.stdout)
check('build hook launches background not full check, explicit180s bound cannot inflate from history', '--background' in h and 'start background 3D check' in h and 'GOR_STEP_LIMIT=180' in h)
# Execute the actual shell enumerator against controlled argv. Headless workers must survive a repeated updater.
full_build = (ROOT/"build.sh").read_text()
enumerator = full_build[full_build.index("gor_pids() {"):full_build.index("# 174 items 3+11:")]
script = 'app_name=gor; app_bundle=/test/gor.app; build_uid=1\n' + enumerator + r'''
pgrep() { printf '11\n12\n13\n14\n15\n'; }
ps() { case "$3" in 11) echo /test/gor.app/Contents/MacOS/gor;; 12) echo '/test/gor.app/Contents/MacOS/gor --selftest3d';; 13) echo '/test/gor.app/Contents/MacOS/gor --gor-model-load-probe model all';; 14) echo '/test/gor.app/Contents/MacOS/gor --gor-prepare-worker job';; 15) echo /other/gor;; esac; }
gor_pids
'''
actual = subprocess.run(['bash', '-c', script], capture_output=True, text=True)
check('real updater pid enumerator retains UI only; excludes all headless worker roles', actual.returncode == 0 and actual.stdout.strip() == '11', actual.stdout + actual.stderr)
check('updater TERM carries sender PID, targets and replacement reason', '[GOR-signal] sender=build.sh sender_pid=$$ target_pids=$pids signal=SIGTERM reason=replace_ui_bundle' in full_build)
check('watchdog own TERM has a sender and distinct reason', 'reason=no_log_growth' in (ROOT/'tools/update_3d_check.py').read_text())
shutil.rmtree(tmp, ignore_errors=True)
# A real worker emits a run UUID and supervisor/worker IDs before any model work.
r = run(project("run-binding", BEGIN + CAT + END), "--background-worker")
check("background run marker emitted and included in final result", re.search(r"3D-CHECK run run_id=[a-f0-9]{32} supervisor_pid=\d+ worker_pid=\d+ build_manifest=unavailable",r.stdout) is not None, r.stdout)
print("FAILURES: %d" % fails)
sys.exit(1 if fails else 0)
