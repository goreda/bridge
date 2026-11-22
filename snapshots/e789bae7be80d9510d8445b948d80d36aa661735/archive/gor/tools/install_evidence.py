#!/usr/bin/env python3
"""Install evidence inside the ./build.sh --update capture (3D-CHECK install v1 lines), added after the owner saw an old 3D menu although the update said it
built the newer commit. It answers three questions from the Mac itself, read-only, bounded, never blocking:
  1. which bytes are installed: sha256 of <project>/gor.app/Contents/MacOS/gor and its modification time;
  2. which process is actually running: every gor process (pgrep -x gor) with pid, start time and executable path, and whether that path is the installed bundle
     and whether the process started before the installed executable was written (a stale process that never relaunched);
  3. whether another gor.app exists that the owner could launch instead (project dir leftovers gor.app.instinct-*, gor.app.previous, /Applications, ~/Applications,
     ~/Downloads, Desktop): path and executable sha256, flagged when it differs from the installed one.
Environment: GOR_SKIP_INSTALL_EVIDENCE=1 disables it. Output is capped at 40 lines."""
import hashlib, os, subprocess, sys, time


def sha(path):
    try:
        h = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None


def sh(cmd, limit=10):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=limit).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def processes():
    rows = []
    for pid in sh(["/usr/bin/pgrep", "-x", "gor"]).split():
        info = sh(["/bin/ps", "-p", pid, "-o", "lstart=,command="]).strip()
        exe = sh(["/usr/sbin/lsof", "-p", pid, "-Fn", "-a", "-d", "txt"]).splitlines()
        path = next((l[1:] for l in exe if l.startswith("n") and l.endswith("/Contents/MacOS/gor")), "")
        rows.append((pid, info[:24].strip(), path))
    return rows


def other_apps(root, installed):
    home = os.path.expanduser("~")
    found = []
    for base in (root, "/Applications", home + "/Applications", home + "/Downloads", home + "/Desktop"):
        try:
            names = sorted(os.listdir(base))
        except OSError:
            continue
        for n in names:
            exe = os.path.join(base, n, "Contents/MacOS/gor")
            if n.startswith("gor.app") and os.path.isfile(exe) and os.path.realpath(os.path.join(base, n)) != os.path.realpath(installed):
                found.append(exe)
    return found[:8]


def evidence(root):
    if os.environ.get("GOR_SKIP_INSTALL_EVIDENCE"):
        return []
    app = os.path.join(root, "gor.app")
    exe = os.path.join(app, "Contents/MacOS/gor")
    out = []
    isha = sha(exe)
    mt = os.path.getmtime(exe) if os.path.isfile(exe) else None
    out.append("3D-CHECK install v1 installed_exe_sha256=%s mtime=%s" % (isha or "MISSING", time.strftime("%H:%M:%S", time.localtime(mt)) if mt else "-"))
    procs = processes()
    out.append("3D-CHECK install v1 running_gor_processes=%d" % len(procs))
    for pid, started, path in procs:
        same = bool(path) and os.path.realpath(path) == os.path.realpath(exe)
        out.append("3D-CHECK install v1 proc pid=%s started=%s exe=%s is_installed_bundle=%s" % (pid, started or "?", path or "?", "yes" if same else "NO"))
    for other in other_apps(root, app):
        s = sha(other)
        out.append("3D-CHECK install v1 other_app %s sha256=%s %s" % (other, s or "?", "same" if s == isha else "DIFFERS"))
    return out[:40]


if __name__ == "__main__":
    print("\n".join(evidence(sys.argv[1] if len(sys.argv) > 1 else ".")))
# Reading guide for the capture: if running_gor_processes shows is_installed_bundle=NO, the owner is looking at a process that does not come from the
# freshly installed bundle (stale process or a different copy); if other_app lines say DIFFERS, a Dock or Finder launch can open older bytes.
# This file only reads; it never kills, moves or launches anything.
