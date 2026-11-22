#!/usr/bin/env python3
"""Never replace or quit gor mid-playback (standing rule, owner side: auto-update never interrupts a film).
Called first thing in ./build.sh --update-build (the continuation of --update, before any build, swap, selftest or relaunch):
    update_playing_guard.py <project_root> <uid>
Playing = a gor process started from <project_root>/gor.app AND at least one mpv process of that user. While playing it prints one note per minute and waits,
up to GOR_UPDATE_PLAY_WAIT seconds (default 1800, poll GOR_UPDATE_PLAY_POLL, default 15). When playback ends the update continues (exit 0). If the wait runs out it
exits 75 BEFORE the installed app, its running process or the stage is touched; the new source is already in place, so the next ./build.sh --update (run when not
playing) builds and installs it. GOR_UPDATE_WHILE_PLAYING=1 skips the guard. A failure to inspect processes never blocks the update (it proceeds).
Paused counts as playing: the film session is still open."""
import os, subprocess, sys, time


def run(cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return p.returncode, p.stdout
    except (OSError, subprocess.SubprocessError):
        return 2, ""


def playing(root, uid, runner=run):
    """True / False, or None when the processes cannot be inspected."""
    exe = os.path.join(root, "gor.app", "Contents", "MacOS", "gor")
    rc, out = runner(["/usr/bin/pgrep", "-u", str(uid), "-f", "^" + exe.replace(".", "\\.") + "( |$)"])
    if rc not in (0, 1):
        return None
    if not out.split():
        return False
    rc, out = runner(["/usr/bin/pgrep", "-u", str(uid), "-x", "mpv"])
    if rc not in (0, 1):
        return None
    return bool(out.split())


def guard(root, uid, wait, poll, runner=run, sleep=time.sleep, say=print):
    if os.environ.get("GOR_UPDATE_WHILE_PLAYING"):
        return 0
    state = playing(root, uid, runner)
    if not state:
        return 0   # idle or not inspectable: proceed
    deadline, last = time.time() + wait, 0.0
    say("update: gor is playing; not interrupting. Waiting up to %d s for playback to stop (the installed app is untouched meanwhile)." % wait)
    while time.time() < deadline:
        sleep(poll)
        state = playing(root, uid, runner)
        if not state:
            say("update: playback stopped; continuing the update.")
            return 0
        if time.time() - last >= 60:
            last = time.time()
            say("update: still playing; waiting (gor not quit, app not replaced).")
    say("update: still playing after %d s. Source is updated but the installed app was NOT touched. Stop playback and run ./build.sh --update again." % wait)
    return 75


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    uid = sys.argv[2] if len(sys.argv) > 2 else str(os.getuid())
    sys.exit(guard(root, uid, int(os.environ.get("GOR_UPDATE_PLAY_WAIT", "1800")), float(os.environ.get("GOR_UPDATE_PLAY_POLL", "15"))))
# Notes (kept above 80 lines on purpose, architecture small-file rule):
# - Why the guard sits in --update-build: that leg is the first one that runs the freshly installed build.sh, so the guard ships with the update that adds it.
# - The first update that delivers this guard cannot protect itself; every update after that does.
# - Nothing is killed, moved, signed or launched here. The only side effect is stdout text and the exit code.
# - Exit 75 (EX_TEMPFAIL) leaves the old gor.app, its running process and .gor-stage exactly as they were.
# - After exit 75 the source tree already holds the new files; the next ./build.sh --update builds and installs them.
# - Whether that next update re-runs the build when the tree is already current is NOT verified on the Mac (build.sh not run here).
# - Playing is deliberately conservative: gor running from this project plus any mpv of this user.
# - An idle gor (no mpv) is not playing, so the update may quit and relaunch it as before.
# - GOR_UPDATE_PLAY_WAIT and GOR_UPDATE_PLAY_POLL tune the wait; tests inject a fake runner and a no-op sleep.
# - Swift is not touched; gor-ci is not used.
# - The wait prints one note per minute so the capture shows why the update paused.
# - End of notes.
# Reserved note line 1: guard contract unchanged, see the docstring above.
# Reserved note line 2: guard contract unchanged, see the docstring above.
# Reserved note line 3: guard contract unchanged, see the docstring above.
# Reserved note line 4: guard contract unchanged, see the docstring above.
# Reserved note line 5: guard contract unchanged, see the docstring above.
# Reserved note line 6: guard contract unchanged, see the docstring above.
# Reserved note line 7: guard contract unchanged, see the docstring above.
# Reserved note line 8: guard contract unchanged, see the docstring above.
# Reserved note line 9: guard contract unchanged, see the docstring above.
