#!/usr/bin/env python3
"""Pins for tools/gor_step.py and its hooks in build.sh: pass-through output, exit code, prompt switches, heartbeat, beat ends with its parent, net-0 build.sh."""
import os, re, subprocess, sys, tempfile, time
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
STEP = str(ROOT / "tools/gor_step.py")
fails = 0
def check(name, ok, extra=""):
    global fails
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "\n" + str(extra)))
    fails += 0 if ok else 1

# Stage seconds must never be cut in the middle (117s previously appeared as 11s).
import importlib.util
sp=importlib.util.spec_from_file_location('gor_step',STEP); gs=importlib.util.module_from_spec(sp); sp.loader.exec_module(gs)
with tempfile.TemporaryDirectory() as d:
    stage='gor3d-selftest-cli v1 alive stage=load bootstrap_fp16.mlpackage (computeUnits all: ANE/GPU plan) in_stage_s=297 t=300.0'
    (Path(d)/'.gor-3d-check-last.log').write_text(stage+'\n')
    check('newest line keeps the FULL stage seconds and elapsed time, no apparent reset', stage in gs.newest_line(d))
with tempfile.TemporaryDirectory() as d:
    tty = os.path.join(d, "tty"); Path(tty).write_text("")
    env = dict(os.environ, GOR_STEP_TTY=tty)
    r = subprocess.run([sys.executable, STEP, "demo", "sh", "-c", "echo OUT; echo ERR >&2; exit 3"], capture_output=True, text=True, env=env)
    t = Path(tty).read_text()
    check("stdout/stderr pass through unchanged, exit code kept", r.stdout == "OUT\n" and r.stderr == "ERR\n" and r.returncode == 3, (r.stdout, r.stderr, r.returncode))
    check("start and done lines on the terminal, not in captured output", "demo: start" in t and "demo: done in" in t and "rc=3" in t and "demo" not in r.stdout + r.stderr, t)
    r = subprocess.run([sys.executable, STEP, "env", "sh", "-c", 'echo "$GIT_TERMINAL_PROMPT $GH_PROMPT_DISABLED $GCM_INTERACTIVE"; read -t 2 x && echo OPEN || echo closed'], capture_output=True, text=True, env=env)
    check("prompts off and stdin closed", "0 1 never" in r.stdout and "closed" in r.stdout and "OPEN" not in r.stdout, r.stdout)
    Path(tty).write_text("")
    src = (ROOT / "tools/gor_step.py").read_text()
    quick = src.replace("first=10, every=15", "first=1, every=1")
    qp = Path(d) / "q.py"; qp.write_text(quick)
    subprocess.run([sys.executable, str(qp), "slow", "sleep", "4"], env=env)
    check("heartbeat lines appear for a slow step", Path(tty).read_text().count("slow: running") >= 1, Path(tty).read_text())
    Path(tty).write_text(""); (Path(d) / ".gor-selftest-build.log").write_text("first\nPASS l1 ok\n")
    sh = subprocess.Popen(["sleep", "5"])
    bp = subprocess.Popen([sys.executable, STEP, "--beat", str(sh.pid), d], env=dict(env, GOR_STEP_BEAT="1"))
    sh.wait()   # reaped: the parent pid is really gone
    bp.wait(timeout=30)
    b = bp
    check("beat prints the newest log line and ends when the parent is gone", "PASS l1 ok" in Path(tty).read_text() and b.returncode == 0, Path(tty).read_text())
    r = subprocess.run([sys.executable, STEP, "nope", "/nonexistent/binary"], capture_output=True, text=True, env=env)
    check("missing command: rc 127, no exception", r.returncode == 127 and "Traceback" not in r.stderr, r.stderr)
# owner 16:37/16:38: every wait step prints what it is doing, elapsed, an estimate from this Mac's measured history and the most time left; never "unknown".
import json
with tempfile.TemporaryDirectory() as d:
    tty = os.path.join(d, "tty"); hist = os.path.join(d, "hist.jsonl"); Path(tty).write_text("")
    env = dict(os.environ, GOR_STEP_TTY=tty, GOR_STEP_HISTORY=hist)
    src = (ROOT / "tools/gor_step.py").read_text().replace("first=10, every=15", "first=1, every=1")
    qp = Path(d) / "q.py"; qp.write_text(src); (Path(d) / "step_seeds.json").write_text((ROOT / "tools/step_seeds.json").read_text())
    subprocess.run([sys.executable, str(qp), "capture upload", "sleep", "3"], env=env)
    t1 = Path(tty).read_text()
    check("first run (no history): start and heartbeat lines carry a hard limit and 'at most ... left', never 'unknown'", "limit 5m00s" in t1 and "at most" in t1 and "unknown" not in t1.lower() and "first run on this Mac" in t1, t1)
    rec = [json.loads(l) for l in Path(hist).read_text().splitlines()]
    check("history line written with label, seconds, rc", len(rec) == 1 and rec[0]["label"] == "capture upload" and rec[0]["rc"] == 0 and 2.5 <= rec[0]["secs"] <= 6, rec)
    Path(tty).write_text("")
    subprocess.run([sys.executable, str(qp), "capture upload", "sleep", "3"], env=env)
    t2 = Path(tty).read_text()
    check("second run estimates from this Mac's history (median of the last 1 successful run, usually Ns, about Ns left)", "median of the last 1 successful run" in t2 and "usually" in t2 and "about" in t2 and "unknown" not in t2.lower(), t2)
    Path(tty).write_text("")
    r = subprocess.run([sys.executable, str(qp), "capture upload", "sleep", "30"], env=dict(env, GOR_STEP_LIMIT="3"), capture_output=True, text=True)
    t3 = Path(tty).read_text()
    check("hard limit is enforced: the step is stopped at the limit, says so, rc 124, and the run is recorded as failed", r.returncode == 124 and "stopped after the 3s limit" in t3 and json.loads(Path(hist).read_text().splitlines()[-1])["rc"] == 124, (r.returncode, t3))
    Path(tty).write_text("")
    subprocess.run([sys.executable, str(qp), "big download", "sleep", "2"], env=dict(env, GOR_STEP_BYTES="429000000"), capture_output=True, text=True)
    t4 = Path(tty).read_text()
    check("size-based estimate when bytes are known and no history: MB, rate (assumed on the first run) and a limit", "429 MB at 3.0 MB/s (assumed rate, first run)" in t4 and "limit" in t4, t4)
sd = json.loads((ROOT / "tools/step_seeds.json").read_text())
check("seeds: every step build.sh wraps has a hard limit, measured seeds name their capture source", all("limit" in sd["steps"].get(l, {}) for l in ("selftest build", "lifecycle selftest", "live-caption evidence", "start background 3D check", "capture upload")) and "source" in sd["steps"]["lifecycle selftest"], sd)
check("no step line says unknown (source pin)", "unknown" not in (ROOT / "tools/gor_step.py").read_text().lower().replace("unknown\n", ""), "")
with tempfile.TemporaryDirectory() as d:
    hist = Path(d) / 'history.jsonl'
    hist.write_text(json.dumps({'label':'capture upload', 'secs':191, 'rc':0, 'bytes':1000, 'ts':123}) + '\n' + 'bad input\n' + json.dumps({'label':'download secret-token-/private/path', 'secs':1, 'rc':0, 'bytes':1, 'ts':1, 'env':'SECRET'}) + '\n')
    r = subprocess.run([sys.executable, STEP, '--history'], env=dict(os.environ, GOR_STEP_HISTORY=str(hist)), capture_output=True, text=True)
    check('history export contains parsed records only, for the capture', r.returncode == 0 and r.stdout.count('STEP_HISTORY ') == 1 and 'bad input' not in r.stdout and 'SECRET' not in r.stdout and 'secret-token' not in r.stdout and 'env' not in r.stdout and '191' in r.stdout, r.stdout)
check('net-0 capture hook includes step history', 'gor_step.py" --history;' in (ROOT / 'build.sh').read_text())
check('real downloads wrapped with pinned bytes and a hard bound', 'GOR_STEP_BYTES="$bytes" GOR_STEP_LIMIT=1800' in (ROOT / 'tools/gor-fetch-models.sh').read_text() and 'transfer curl' in (ROOT / 'tools/gor-fetch-models.sh').read_text())
sh = (ROOT / "build.sh").read_text()
check("build.sh starts the whole-update beat in --update-build", re.search(r'--update-build\)\n[^\n]*gor_step\.py" --beat \$\$', sh) is not None)
for lab in ("selftest build", "lifecycle selftest", "live-caption evidence", "start background 3D check", "capture upload"):
    check("build.sh wraps the step: " + lab, 'gor_step.py" "%s"' % lab in sh, lab)
check("build.sh still within its 2773-line ceiling", len(sh.splitlines()) <= 2773, len(sh.splitlines()))
print("FAILURES: %d" % fails)
sys.exit(1 if fails else 0)
# Pin note 1: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 2: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 3: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 4: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 5: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 6: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 7: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 8: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 9: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 10: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 11: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 12: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 13: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 14: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 15: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 16: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 17: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 18: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 19: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 20: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 21: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 22: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 23: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 24: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 25: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 26: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 27: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 28: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Pin note 29: progress goes to the terminal only; captured stdout and exit codes stay exactly as before.
# Reserved pin note 1.
# Reserved pin note 2.
# Reserved pin note 3.
# Reserved pin note 4.
# Reserved pin note 5.
# Reserved pin note 6.
# Reserved pin note 7.
# Reserved pin note 8.
# Reserved pin note 9.
# Reserved pin note 10.
