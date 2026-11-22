#!/usr/bin/python3
"""X1 (owner 14:48): the 3D first-Mac check that runs INSIDE `./build.sh --update`, after the update's own selftest, and rides the update's existing result
commit (capture channel). It is not a kit and asks nothing of the owner. It never changes the update's outcome: every path here prints and exits 0.

What it does on the Mac, in the project the update just built:
  1. runs `gor.app/Contents/MacOS/gor --selftest3d` (headless: no window, no NSApplication, does not touch the running gor) with a time limit,
  2. checks that log with tools/depth_analysis/mac_log_check.py (the s39 13-family checklist) and the begin/end lines of the headless run,
  3. prints a bounded block (summary line, per-family verdicts, checker text, selftest lines, the app log's per-shot gor3d-shot / gor3d-osd lines)
     that build.sh appends to the update result. Home paths are shown as ~.
Usage: update_3d_check.py PROJECT_ROOT [--timeout SECONDS] [--app-log PATH]
"""
import json, os, re, subprocess, sys, time, uuid

from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from session_log_paths import resolve
END_RE = re.compile(r"^gor3d-selftest-cli v1 end code=(\d+) errors=(\d+) ")
KEEP_RE = re.compile(r"gor3d-selftest v1 (stage|rtstage|thermal|thermal_peak|depth|note|end|begin|error)|gor3d-selftest-cli v1|3dfsm ")
PLAY_RE = re.compile(r"gor3d-shot v1|gor3d-osd v1|3d-synth:|3dfsm ")


def arg(name, default):
    a = sys.argv[2:]
    return a[a.index(name) + 1] if name in a and a.index(name) + 1 < len(a) else default


def scrub(text):
    home = os.path.expanduser("~")
    text = text.replace(home, "~") if home and home != "/" else text
    return re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)


def cli_status(lines):
    """(complete, exit_code, errors, begin_count): complete = exactly one begin line and the last cli line is the end line."""
    cli = [l for l in lines if l.startswith("gor3d-selftest-cli v1 ")]
    begins = [l for l in cli if l.startswith("gor3d-selftest-cli v1 begin ")]
    m = END_RE.match(cli[-1]) if cli else None
    ok = len(begins) == 1 and m is not None
    return ok, (int(m.group(1)) if m else None), (int(m.group(2)) if m else None), len(begins)


def say(msg):
    """Live progress to the owner's terminal (the update captures stdout, so /dev/tty is the only visible channel); silent when there is no tty."""
    try:
        with open("/dev/tty", "w") as t:
            t.write(msg + "\n")
    except OSError:
        pass


def folder_mb(path):
    total = 0
    for base, _dirs, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(base, f))
            except OSError:
                pass
    return total / 1e6


def fetch_models(root, limit):
    """The update used to build gor but never fetched the pinned CoreML kits (only the app's first 3D enable did), so a freshly updated Mac stayed 2D with
    kit_missing. Run the repo's own fetcher (sha-pinned rows, gh auth the owner already has); its output is part of the report. Never raises, never blocks."""
    script = os.path.join(root, "tools", "gor-fetch-models.sh")
    if os.environ.get("GOR_SKIP_3D_FETCH") or not os.path.isfile(script):
        return []
    t0 = time.time()
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never", GIT_ASKPASS="/usr/bin/true", GH_PROMPT_DISABLED="1", GH_NO_UPDATE_NOTIFIER="1")
    models = env.get("GOR_MODELS_DIR") or os.path.expanduser("~/Library/Application Support/gor/models")
    say("3D kit download starting (about 1.1 GB download, about 1.85 GB on disk because the kit archives stay next to their unpacked copies; first time only, up to %d min; never waits for a password prompt; a line every 30 s)" % (limit // 60))
    lines = []
    try:
        env["GOR_STEP_LIMIT"] = str(limit)
        p = subprocess.Popen([sys.executable, os.path.join(root, "tools", "gor_step.py"), "fetch models", "/bin/bash", script], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, cwd=root, env=env)
        import threading
        def pump():
            for l in p.stdout:
                lines.append(l)
                say("3D kit: " + l.rstrip()[:160])
        th = threading.Thread(target=pump, daemon=True)
        th.start()
        rc, last = None, time.time()
        while rc is None:
            try:
                rc = p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                if time.time() - t0 > limit:
                    p.kill()
                    lines.append("timeout after %ds\n" % limit)
                    rc = 124
                elif time.time() - last >= 30:
                    last = time.time()
                    say("3D kit download running %ds, %.0f MB in the models folder so far" % (time.time() - t0, folder_mb(models)))
        th.join(2)
        text = "".join(lines)
    except OSError as e:
        rc, text = 127, "cannot run: %s" % e
    tail = [l for l in text.splitlines() if l.strip()][-40:]
    return ["3D-CHECK fetch-models rc=%s seconds=%d" % (rc, int(time.time() - t0))] + ["fetch: " + l for l in tail]


def run_with_stall_watchdog(cmd, f, log, limit, stall, out, env=None):
    """Run cmd into f. Hard limit `limit` s (TimeoutExpired as before). If the log file does not grow for `stall` s the process is sampled (macOS `sample`, 3 s, text
    into the report, bounded) and terminated: the 16:33 capture showed a headless selftest idle at 0% CPU with only its begin line. Returns the exit code, or raises TimeoutExpired."""
    p = subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=env)
    t0, last_size, last_change = time.time(), -1, time.time()
    while True:
        try:
            rc = p.wait(timeout=5)
            if rc < 0:
                out.append("3D-CHECK external_signal target_pid=%d signal=%d sender=unattributed_by_waitpid own_watchdog_sent=no" % (p.pid, -rc))
            return rc
        except subprocess.TimeoutExpired:
            pass
        now = time.time()
        if now - t0 > limit:
            out.append("3D-CHECK signal sender=update_3d_check sender_pid=%d target_pid=%d signal=SIGKILL reason=selftest_total_limit limit_s=%s" % (os.getpid(), p.pid, limit))
            p.kill()
            p.wait()
            raise subprocess.TimeoutExpired(cmd, limit)
        try:
            size = os.path.getsize(log)
        except OSError:
            size = -1
        if size != last_size:
            last_size, last_change = size, now
        elif now - last_change >= stall:
            try:
                sm = subprocess.run(["/usr/bin/sample", str(p.pid), "3"], capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL).stdout
                out.append("3D-CHECK stall sample (bounded)")
                out += ["sample: " + l[:160] for l in sm.splitlines() if l.strip()][:60]
            except (OSError, subprocess.SubprocessError):
                out.append("3D-CHECK stall sample unavailable")
            out.append("3D-CHECK signal sender=update_3d_check sender_pid=%d target_pid=%d signal=SIGTERM reason=no_log_growth stall_s=%s" % (os.getpid(), p.pid, stall))
            p.terminate()
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
                p.wait()
            f.write("gor3d-selftest-cli v1 stalled seconds=%d no_log_growth_for=%d\n" % (now - t0, stall))
            return 124


def run(root, timeout, app_log):
    out = ["BEGIN 3D check (inside update; never blocks it)"]
    binary = os.path.join(root, "gor.app", "Contents", "MacOS", "gor")
    if not os.access(binary, os.X_OK):
        return out + ["3D-CHECK v1 verdict=NOT_RUN reason=no_built_app", "END 3D check"]
    out += fetch_models(root, int(os.environ.get("GOR_UPDATE_3D_FETCH_TIMEOUT", "2700")))
    log = os.path.join(root, ".gor-3d-check-last.log")
    env = dict(os.environ, GOR_3D_TEST_CLIP=os.path.join(root, "tools/depth_analysis/kit/x2_tos_reference/tos_input_320x180_48f.mp4"), GOR_3D_TEST_EVIDENCE=os.path.join(root, ".gor-3d-acceptance"))
    t0, rc = time.time(), None
    with open(log, "w") as f:
        try:
            rc = run_with_stall_watchdog([binary, "--selftest3d"], f, log, timeout, int(os.environ.get("GOR_UPDATE_3D_STALL", "300")), out, env=env)
        except subprocess.TimeoutExpired:
            f.write("gor3d-selftest-cli v1 timeout seconds=%d\n" % timeout)
        except OSError as e:
            f.write("gor3d-selftest-cli v1 spawn_failed %s\n" % e)
    secs = int(time.time() - t0)
    lines = open(log, errors="replace").read().splitlines()
    complete, code, errors, _ = cli_status(lines)
    families, text = {}, ""
    checker = os.path.join(root, "tools", "depth_analysis", "mac_log_check.py")
    if any("gor3d-selftest v1 " in l for l in lines) and os.path.exists(checker):
        p = subprocess.run([sys.executable, checker, log, "--json"], capture_output=True, text=True)
        text = p.stdout
        for line in text.splitlines():
            if line.startswith('{"runs"'):
                try:
                    runs = json.loads(line).get("runs") or []
                    families = dict(runs[-1]) if runs else {}
                except ValueError:
                    pass
    kit_missing = any("kit_missing" in l for l in lines)
    if kit_missing:
        verdict = "NOT_RUN(kit_missing)"
    else:
        verdict = "PASS" if (rc == 0 and complete and code == 0 and errors == 0 and families and all(v == "PASS" for v in families.values())) else "FAIL"
    out.append("3D-CHECK v1 verdict=%s rc=%s seconds=%d cli_complete=%s selftest_exit=%s errors=%s" % (verdict, rc, secs, complete, code, errors))
    out += ["3D-CHECK family %s %s" % kv for kv in sorted(families.items())]
    out += ["checker: " + l for l in text.splitlines() if not l.startswith('{"runs"')][:120]
    out += [l for l in lines if KEEP_RE.search(l)][-150:]
    if os.path.isfile(app_log):
        tail = open(app_log, errors="replace").read().splitlines()[-20000:]
        out += ["app-log: " + l for l in tail if PLAY_RE.search(l)][-60:]
    return out + ["END 3D check"]


def retire_first_mac_kit_job():
    """The abandoned first-Mac kit installed a launchd job (com.gor.first-mac-kit). If it exists on this Mac, unload and remove that plist; no-op otherwise.
    Only that one label's plist is touched; its state dir is left in place (nothing else is deleted)."""
    plist = os.path.join(os.path.expanduser("~"), "Library", "LaunchAgents", "com.gor.first-mac-kit.plist")
    if not os.path.isfile(plist):
        return None
    try:
        subprocess.run(["launchctl", "bootout", "gui/%d/com.gor.first-mac-kit" % os.getuid()], capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        pass
    try:
        os.remove(plist)
        return "retired launchd job com.gor.first-mac-kit (plist removed)"
    except OSError as e:
        return "launchd job com.gor.first-mac-kit plist could not be removed: %s" % type(e).__name__


def previous_evidence(root, app_log):
    """Bounded read, no waiting. Keep prior result before a fresh worker appends output."""
    result = ['BEGIN previous background 3D evidence']
    for path in (os.path.join(root, '.gor-3d-check-background.log'), os.path.join(root, '.gor-3d-check-last.log'), app_log):
        try:
            with open(path, 'rb') as f:
                f.seek(max(0, os.path.getsize(path)-131072))
                lines=f.read(131072).decode('utf-8','replace').splitlines()
        except OSError: continue
        keep=[]
        for line in lines:
            if re.match(r'^(3D-CHECK (v1 |family |vr-pack )|gor3d-selftest-cli v1 |gor3d-selftest v1 (error |end |stage |note )|3d-load(?:-probe)? |background-result: 3D-CHECK (v1 |family |vr-pack ))', line):
                keep.append(scrub(line)[:700])
        result += ['SOURCE ' + os.path.basename(path)] + keep[-80:]
    if len(result)==1: result.append('NOT_RUN no previous background evidence')
    return result + ['END previous background 3D evidence']


def background_paths(root):
    return (os.path.join(root, '.gor-3d-check-background.log'),
            os.path.join(root, '.gor-3d-check-background.pid'),
            os.path.join(root, '.gor-coreml-load-history.jsonl'))


def launch_background(root, app_log):
    """No pipes inherited by the worker: command substitution returns immediately."""
    log, pidfile, history = background_paths(root)
    try:
        pid = int(open(pidfile).read())
        os.kill(pid, 0)
        return ['3D-CHECK background RUNNING pid=%d log=%s (update does not wait)' % (pid, log)]
    except (OSError, ValueError):
        pass
    # A separate supervisor enforces a TOTAL deadline, including fetch/load/probes.
    cmd = [sys.executable, os.path.join(root, 'tools', 'gor_step.py'),
           'background 3D check', sys.executable, os.path.abspath(__file__),
           root, '--background-worker', '--app-log', app_log]
    env = dict(os.environ, GOR_STEP_LIMIT='1800', GOR_STEP_TTY=log, GOR_3D_CHECK_RUN_ID=uuid.uuid4().hex)
    expected = 'first CoreML load has already exceeded 5 min on this Mac; completion time not measured; previous 3D attempt reached its 20 min timeout'
    try:
        import gor_step
        typical, _, basis = gor_step.plan('background 3D check')
        if typical is not None: expected = 'about %s (%s); first-load time may differ' % (gor_step.fmt(typical), basis)
    except (ImportError, OSError, ValueError): pass
    say('background 3D check: expected duration: ' + expected + '; hard max 30 min; background, update does not wait; live elapsed in ' + log)
    with open(log, 'a') as out:
        child = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=out, stderr=out,
                                 start_new_session=True, close_fds=True, env=env)
    with open(pidfile, 'w') as out:
        out.write(str(child.pid))
    result = ['3D-CHECK background STARTED pid=%d log=%s expected_duration=%s total_limit_s=1800; update does not wait; no feature verdict yet' % (child.pid, log, expected)]
    try:
        rows = [json.loads(l) for l in open(history) if l.strip()]
        last = {}
        for row in rows: last[row['stage']] = row['ms']
        result += ['CoreML measured history: %s last_completed_ms=%s (not a remaining-time estimate)' % (k,v) for k,v in last.items()]
    except (OSError, ValueError, KeyError):
        result += ['CoreML measured history: no completed load measured yet']
    return result


def record_load_history(root):
    """Record completed load stages only. A heartbeat is a lower bound, not duration."""
    _, _, history = background_paths(root)
    try:
        lines = open(os.path.join(root, '.gor-3d-check-last.log')).read().splitlines()
        with open(history, 'a') as out:
            for line in lines:
                m = re.search(r' stage (load .+?) end ms=(\d+) t=', line)
                if m: out.write(json.dumps(dict(stage=m[1], ms=int(m[2]), recorded_at=time.time()))+'\n')
    except OSError:
        pass


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 0
    if '--background' in sys.argv:
        try:
            result = previous_evidence(sys.argv[1], str(resolve(arg('--app-log', '/tmp/gor_direct.log')))) + launch_background(sys.argv[1], str(resolve(arg('--app-log', '/tmp/gor_direct.log'))))
        except Exception as e:
            result = ['3D-CHECK background NOT_STARTED reason=%s; update continues; no feature verdict' % type(e).__name__]
        print(scrub("\n".join(result)))
        return 0
    run_marker=None
    if '--background-worker' in sys.argv:
        run_id=os.environ.get('GOR_3D_CHECK_RUN_ID','')
        if not re.fullmatch('[a-f0-9]{32}',run_id):run_id=uuid.uuid4().hex
        manifest='unavailable'
        try:
            fields=dict(line.split('=',1) for line in open(os.path.join(sys.argv[1],'gor.app/Contents/Resources/build-id.txt')).read().splitlines() if '=' in line)
            if re.fullmatch('[a-f0-9]{64}',fields.get('commit','')):manifest=fields['commit']
        except (OSError,ValueError):pass
        run_marker='3D-CHECK run run_id=%s supervisor_pid=%d worker_pid=%d build_manifest=%s' % (run_id,os.getppid(),os.getpid(),manifest)
        print(run_marker,flush=True)
    try:
        lines = run(sys.argv[1], float(arg("--timeout", os.environ.get("GOR_UPDATE_3D_TIMEOUT", "1200"))), str(resolve(arg("--app-log", "/tmp/gor_direct.log"))))
    except Exception as e:   # never block the update
        lines = ["3D-CHECK v1 verdict=NOT_RUN reason=helper_error:%s" % type(e).__name__]
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import vr_pack_probe
        extra = vr_pack_probe.probe(sys.argv[1])   # never blocks; fallback marker keeps VR from going black
        cut = len(lines) - 1 if lines and lines[-1].startswith("END 3D check") else len(lines)
        lines[cut:cut] = extra
        import install_evidence
        cut = len(lines) - 1 if lines and lines[-1].startswith("END 3D check") else len(lines)
        lines[cut:cut] = install_evidence.evidence(sys.argv[1])
    except Exception as e:
        lines.insert(max(len(lines) - 1, 0), "3D-CHECK vr-pack v1 verdict=NOT_RUN reason=probe_error:%s" % type(e).__name__)
    try:
        note = retire_first_mac_kit_job()
        if note:
            lines.append("3D-CHECK note " + note)
    except Exception:
        pass
    record_load_history(sys.argv[1])
    if run_marker:lines.insert(0,run_marker)
    text = scrub("\n".join(lines))
    print(text, flush=True)
    if '--background-worker' in sys.argv:
        summary = [l for l in lines if l.startswith('3D-CHECK')]
        try:
            with open(str(resolve(arg('--app-log', '/tmp/gor_direct.log'))), 'a') as out:
                out.write("\n".join('background-result: '+scrub(l) for l in summary)+'\n')
        except OSError: pass
        # Failed/missing checks must not seed a "successful" expected duration.
        return 0 if any(l.startswith('3D-CHECK v1 verdict=PASS') for l in lines) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
