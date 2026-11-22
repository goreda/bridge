"""s41: receive-side watch for owner-Mac gor logs arriving over the capture channel.

The owner kit/update flow ships append-only captures to the gor-capture-mac
branch of the origin remote: gor-capture-channel.py send --file <stamp>.txt
-> captures/<stamp>.txt on that branch (verified remote ACK owner-side).
The first Mac gor-log (s39 rehearsal) reaches us the same way; this watch
is the automatic check on our side:

1. fetch refs/heads/gor-capture-mac from origin (absent branch = no captures)
2. list captures/*.txt at the tip
3. for every capture not yet checked (state file), if it contains
   gor3d-selftest v1 lines, run mac_log_check on it and print the per-family
   verdict block; non-log captures (periodic numeric captures) are recorded
   as skipped, never parsed as logs
4. persist verdicts in a state file so each capture is checked exactly once

CLI: python3 kit_log_watch.py --repo PATH [--state PATH] [--expected PATH] [--json]

Exit 0 = no branch / no new captures / every new log PASS.
Exit 1 = at least one new log had a MISSING/FORMAT-BUG/FAIL family.
Exit 2 = usage error.
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import mac_log_check as mlc  # noqa: E402

BRANCH = "gor-capture-mac"
CAPTURES_PREFIX = "captures/"
SELFTEST_MARK = "gor3d-selftest v1"


def git(repo, *args, check=True):
    p = subprocess.run(["git", "-C", repo] + list(args),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       timeout=60)
    if check and p.returncode:
        raise RuntimeError("git " + args[0] + " failed: "
                           + p.stderr.decode(errors="replace").strip())
    return p


def fetch_tip(repo):
    """-> tip sha of the capture branch, None when origin has no such branch."""
    p = git(repo, "ls-remote", "--heads", "origin", "refs/heads/" + BRANCH)
    rows = p.stdout.decode().split()
    if not rows:
        return None
    tip = rows[0]
    git(repo, "fetch", "--no-tags", "origin", "refs/heads/" + BRANCH)
    if git(repo, "rev-parse", "FETCH_HEAD").stdout.decode().strip() != tip:
        raise RuntimeError("remote changed during fetch; rerun")
    return tip


def capture_paths(repo, tip):
    out = git(repo, "ls-tree", "-r", "--name-only", tip,
              "--", CAPTURES_PREFIX).stdout.decode().splitlines()
    return sorted(p for p in out if p.startswith(CAPTURES_PREFIX)
                  and p.endswith(".txt"))


def load_state(path):
    try:
        return json.load(open(path))
    except (OSError, ValueError):
        return {"checked": {}}


def check_captures(repo, exp, state, tip=None):
    """Check every unchecked log capture. -> (results, tip).

    results: list of dicts {path, verdict, families?} in capture order.
    verdict: PASS | FAIL | not-a-log
    """
    if tip is None:
        tip = fetch_tip(repo)
        if tip is None:
            return [], None
    results = []
    for path in capture_paths(repo, tip):
        if path in state["checked"]:
            continue
        text = git(repo, "show", tip + ":" + path).stdout.decode(
            errors="replace")
        entry = {"path": path}
        if SELFTEST_MARK not in text:
            entry["verdict"] = "not-a-log"
        else:
            per_run = mlc.check_log(text.splitlines(), exp)
            if per_run is None:
                # mark present but no parseable run: treat as a failing log
                entry["verdict"] = "FAIL"
                entry["families"] = {"_parse": "MISSING"}
            else:
                fams = {f.name: f.status for run in per_run for f in run}
                entry["families"] = fams
                entry["verdict"] = ("PASS" if all(
                    s == "PASS" for s in fams.values()) else "FAIL")
        state["checked"][path] = entry["verdict"]
        results.append(entry)
    return results, tip


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--state", default=None,
                    help="state file (default <repo>/.git/kit-log-watch-state.json)")
    ap.add_argument("--expected", default=mlc.stc.EXPECTED)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    exp = json.load(open(args.expected))
    state_path = args.state or os.path.join(args.repo, ".git",
                                            "kit-log-watch-state.json")
    state = load_state(state_path)
    try:
        results, tip = check_captures(args.repo, exp, state)
    except RuntimeError as e:
        print("kit-log-watch: " + str(e))
        return 2
    if tip is None:
        print("kit-log-watch: no " + BRANCH + " branch on origin; "
              "no captures yet")
        return 0

    worst = 0
    for r in results:
        if r["verdict"] == "not-a-log":
            print(f"  [skip] {r['path']} (no selftest lines; numeric capture)")
            continue
        print(f"  [{r['verdict']}] {r['path']}")
        if r["verdict"] != "PASS":
            worst = 1
            for name, status in sorted(r["families"].items()):
                if status != "PASS":
                    print(f"      {status}: {name}")
    tmp = state_path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f, indent=1, sort_keys=True)
    os.replace(tmp, state_path)
    if args.json:
        print(json.dumps({"tip": tip, "results": results}))
    print(f"kit-log-watch: {len(results)} new capture(s) at {tip[:12]}, "
          + ("all logs PASS" if worst == 0 else "FAILING LOG PRESENT"))
    return worst


if __name__ == "__main__":
    sys.exit(main())
