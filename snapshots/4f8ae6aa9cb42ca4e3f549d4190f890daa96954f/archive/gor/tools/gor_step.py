#!/usr/bin/env python3
"""Live progress for ./build.sh --update (owner rule 16:27: any step that can run more than 10 s prints a live line to his terminal and never blocks on a prompt).
Two modes, both write to the controlling terminal (/dev/tty, or the file in GOR_STEP_TTY for tests) and stay silent when there is none:
  gor_step.py LABEL cmd [args...]   run cmd with stdin closed and every credential/prompt switch off, child stdout/stderr pass through UNCHANGED (so $(...) capture and
                                    `>>log` redirects keep working), print "start", a heartbeat every 15 s once the step passes 10 s, and "done in Ns rc=N". Exit code = child's.
  gor_step.py --beat PID ROOT       background heartbeat for the whole update: every 20 s a line with elapsed time and the newest line of the selftest/build logs; ends by itself
                                    when PID (the update shell) is gone.
Never raises into the update: any internal error falls back to running the command without progress lines."""
import json, os, re, signal, statistics, subprocess, sys, time

NOPROMPT = {"GIT_TERMINAL_PROMPT": "0", "GCM_INTERACTIVE": "never", "GIT_ASKPASS": "/usr/bin/true", "SSH_ASKPASS": "/usr/bin/true",
            "GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1", "HOMEBREW_NO_AUTO_UPDATE": "1", "DEBIAN_FRONTEND": "noninteractive"}
LOGS = (".gor-selftest-build.log", ".gor-selftest-last.txt", ".gor-3d-check-last.log")


def say(msg):
    target = os.environ.get("GOR_STEP_TTY") or "/dev/tty"
    try:
        with open(target, "a") as t:
            t.write("[update %s] %s\n" % (time.strftime("%H:%M:%S"), msg))
    except OSError:
        pass


def newest_line(root):
    best = None
    for name in LOGS + ("/tmp/gor_build.log",):
        path = name if name.startswith("/") else os.path.join(root, name)
        try:
            m = os.path.getmtime(path)
        except OSError:
            continue
        if best is None or m > best[0]:
            best = (m, path)
    if not best:
        return "no log yet"
    try:
        with open(best[1], "rb") as f:
            f.seek(max(0, os.path.getsize(best[1]) - 4096))
            lines = [l.strip() for l in f.read().decode("utf-8", "replace").splitlines() if l.strip()]
    except OSError:
        return "log unreadable"
    return "%s (%ds ago): %s" % (os.path.basename(best[1]), time.time() - best[0], (lines[-1] if lines else "")[:512])


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def beat(pid, root, every=20):
    t0 = time.time()
    while alive(pid):
        time.sleep(every)
        if alive(pid):
            say("whole update: %s elapsed; its steps print their own usual time and limit; newest log: %s" % (fmt(time.time() - t0), newest_line(root)))
    return 0


# Owner 16:37/16:38: every wait step says what it is doing, elapsed, an estimate from this Mac's measured history and the most time it can still take. Always a number.
# History: one JSON line per finished step in GOR_STEP_HISTORY (default ~/Library/Application Support/gor/step-history.jsonl). Seeds + hard limits: tools/step_seeds.json.
HISTORY = os.environ.get("GOR_STEP_HISTORY") or os.path.expanduser("~/Library/Application Support/gor/step-history.jsonl")


def seeds():
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "step_seeds.json")) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {"default": {"limit": 900, "rate_bps_assumed": 3000000}, "steps": {}}


def history(label, path=None):
    out = []
    try:
        with open(path or HISTORY) as f:
            for line in f:
                try:
                    r = json.loads(line)
                except ValueError:
                    continue
                if r.get("label") == label:
                    out.append(r)
    except OSError:
        pass
    return out


def record(label, secs, rc, nbytes=None, path=None):
    try:
        p = path or HISTORY
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "a") as f:
            f.write(json.dumps({"label": label, "secs": round(secs, 1), "rc": rc, "bytes": nbytes, "ts": int(time.time())}) + "\n")
    except OSError:
        pass


def plan(label, nbytes=None, hist=None, seed=None):
    """(typical_seconds, limit_seconds, basis). typical: median of the last 5 successful runs on this Mac; else the measured seed; else bytes / measured-or-assumed rate; else the limit itself.
    limit: the hard bound (stopped after it): the seed limit, but at least 1.5x the slowest recent successful run."""
    sd = seed if seed is not None else seeds()
    ent = dict(sd.get("default", {}), **sd.get("steps", {}).get(label, {}))
    limit = float(os.environ.get("GOR_STEP_LIMIT") or ent.get("limit", 900))
    h = hist if hist is not None else history(label)
    ok = [r for r in h if r.get("rc") == 0][-5:]
    if ok:
        secs = [float(r["secs"]) for r in ok]
        return statistics.median(secs), (limit if os.environ.get("GOR_STEP_LIMIT") else max(limit, 1.5 * max(secs))), "median of the last %d successful run%s on this Mac" % (len(ok), "" if len(ok) == 1 else "s")
    if nbytes:
        rates = [r["bytes"] / r["secs"] for r in h if r.get("rc") == 0 and r.get("bytes") and r.get("secs")]
        rate = statistics.median(rates) if rates else float(ent.get("rate_bps_assumed", 3000000))
        return nbytes / rate, max(limit, 1.5 * nbytes / rate), "%d MB at %.1f MB/s (%s)" % (nbytes // 1000000, rate / 1e6, "measured here" if rates else "assumed rate, first run")
    if ent.get("measured"):
        return float(statistics.median(ent["measured"])), limit, "measured on this Mac in an earlier update (%s)" % ent.get("source", "capture")
    return None, limit, "first run on this Mac, no timing yet"


def fmt(s):
    s = int(round(s))
    return "%ds" % s if s < 120 else "%dm%02ds" % (s // 60, s % 60)


def status(label, elapsed, typical, limit, basis):
    left = max(0.0, limit - elapsed)
    if typical is None:
        return "%s: running %s, %s; will stop by itself after at most %s more (limit %s)" % (label, fmt(elapsed), basis, fmt(left), fmt(limit))
    if elapsed <= typical:
        return "%s: running %s, usually %s (%s), about %s left, at most %s left (limit %s)" % (label, fmt(elapsed), fmt(typical), basis, fmt(typical - elapsed), fmt(left), fmt(limit))
    return "%s: running %s, longer than the usual %s (%s); at most %s left (limit %s)" % (label, fmt(elapsed), fmt(typical), basis, fmt(left), fmt(limit))


def step(label, cmd, first=10, every=15):
    env = dict(os.environ, **NOPROMPT)
    t0 = time.time()
    nbytes = int(os.environ["GOR_STEP_BYTES"]) if os.environ.get("GOR_STEP_BYTES", "").isdigit() else None
    typical, limit, basis = plan(label, nbytes)
    say(status(label, 0, typical, limit, basis).replace(": running 0s", ": start"))
    try:
        p = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, env=env, start_new_session=True)
    except OSError as e:
        say("%s: cannot run (%s)" % (label, e))
        return 127
    last = t0
    timed_out = False
    while True:
        try:
            rc = p.wait(timeout=min(2, max(0.01, limit - (time.time() - t0))))
            break
        except subprocess.TimeoutExpired:
            now = time.time()
            if now - t0 >= limit:
                timed_out = True
                say("%s: stopped after the %s limit" % (label, fmt(limit)))
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                rc = p.wait()
                rc = 124
                break
            if now - t0 >= first and now - last >= every:
                last = now
                say(status(label, now - t0, typical, limit, basis))
    secs = time.time() - t0
    say("%s: done in %s rc=%d" % (label, fmt(secs), rc))
    record(label, secs, rc, nbytes)
    return rc


def safe_history_label(label):
    fixed = set(seeds().get("steps", {}))
    if label in fixed:
        return True
    # Lock IDs contain no paths, addresses or arbitrary command text.
    if not isinstance(label, str) or not re.fullmatch(r"download [a-z0-9-]+", label):
        return False
    try:
        lock = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models", "models.lock.tsv")
        with open(lock) as f:
            return label[9:] in {line.split("\t")[0] for line in f if "\tusable\t" in line}
    except OSError:
        return False


def export_history():
    """Only parsed numeric step records, no arbitrary text from the history file enters captures."""
    try:
        rows = []
        with open(HISTORY) as f:
            for line in f:
                try:
                    r = json.loads(line)
                    if not safe_history_label(r.get("label")):
                        continue
                    rows.append({"label": r["label"], "secs": float(r["secs"]), "rc": int(r["rc"]), "bytes": int(r["bytes"]) if r.get("bytes") else None, "ts": int(r["ts"])})
                except (ValueError, TypeError, KeyError):
                    continue
        for r in rows[-100:]:
            print("STEP_HISTORY " + json.dumps(r, ensure_ascii=True))
    except OSError:
        print("STEP_HISTORY no completed steps recorded yet")
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--history":
        return export_history()
    if len(argv) >= 4 and argv[1] == "--beat":
        return beat(int(argv[2]), argv[3], float(os.environ.get("GOR_STEP_BEAT", "20")))
    if len(argv) >= 3:
        return step(argv[1], argv[2:])
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
