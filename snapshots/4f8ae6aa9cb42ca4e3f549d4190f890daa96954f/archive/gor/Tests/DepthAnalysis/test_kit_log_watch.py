#!/usr/bin/env python3
"""s41 pins: kit_log_watch against a synthetic capture-channel branch.

Builds a bare 'origin' with a gor-capture-mac branch carrying a good log
capture, a numeric (non-log) capture, and a failing log capture; runs the
watch against a clone; asserts verdicts, exit codes, and the exactly-once
state file. Box-independent: no models, no clips. Requires git.

Run: python3 Tests/DepthAnalysis/test_kit_log_watch.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))
sys.path.insert(0, HERE)
import kit_log_watch as kw  # noqa: E402
from test_mac_log_check import GOOD  # noqa: E402

BAD = GOOD.replace("[2026-11-09T10:00:33] gor3d-selftest v1 rtstage "
                   "name=surround ms=0.41 n=36 max_ms=0.9\n", "")
NUMERIC = ("gor-periodic numeric capture\nutc=2026-11-09T10:00:00Z\n"
           "BEGIN gor_direct.log\nwt_full cpuPercent=12.0\nEND gor_direct.log\n")


def git(repo, *args, env=None):
    e = dict(os.environ)
    e.update(GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t",
             GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t",
             GIT_TERMINAL_PROMPT="0")
    if env:
        e.update(env)
    p = subprocess.run(["git", "-C", repo] + list(args), env=e,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert p.returncode == 0, (args, p.stderr.decode())
    return p


def make_origin(root, captures):
    """Bare origin + a seed clone that commits captures/<name> files."""
    origin = os.path.join(root, "origin.git")
    subprocess.run(["git", "init", "--bare", origin], check=True,
                   stdout=subprocess.DEVNULL)
    seed = os.path.join(root, "seed")
    subprocess.run(["git", "clone", origin, seed], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.makedirs(os.path.join(seed, "captures"), exist_ok=True)
    for name, text in captures.items():
        with open(os.path.join(seed, "captures", name), "w") as f:
            f.write(text)
    git(seed, "add", "captures")
    git(seed, "commit", "--allow-empty", "-m", "captures")
    git(seed, "branch", "-M", kw.BRANCH)
    git(seed, "push", "origin", kw.BRANCH)
    return origin


def clone(root, origin, name):
    dst = os.path.join(root, name)
    subprocess.run(["git", "clone", origin, dst], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return dst


EXP = json.load(open(kw.mlc.stc.EXPECTED))

with tempfile.TemporaryDirectory() as root:
    # --- 1. no capture branch on origin: rc 0, no results
    origin = make_origin(root, {})
    subprocess.run(["git", "-C", origin, "branch", "-D", kw.BRANCH],
                   check=True, stdout=subprocess.DEVNULL)
    repo = clone(root, origin, "r1")
    results, tip = kw.check_captures(repo, EXP, {"checked": {}})
    assert results == [] and tip is None
    rc = kw.main(["--repo", repo, "--state", os.path.join(root, "s1.json")])
    assert rc == 0, rc
    print("PASS no capture branch: rc 0, nothing checked")

with tempfile.TemporaryDirectory() as root:
    # --- 2. good + numeric + bad captures
    origin = make_origin(root, {
        "260109-100000.txt": GOOD,
        "260109-100001.txt": NUMERIC,
        "260109-100002.txt": BAD,
    })
    repo = clone(root, origin, "r2")
    state_path = os.path.join(root, "s2.json")
    rc = kw.main(["--repo", repo, "--state", state_path, "--json"])
    assert rc == 1, rc  # BAD log present
    state = json.load(open(state_path))
    got = state["checked"]
    assert got["captures/260109-100000.txt"] == "PASS", got
    assert got["captures/260109-100001.txt"] == "not-a-log", got
    assert got["captures/260109-100002.txt"] == "FAIL", got
    print("PASS good/numeric/bad captures: verdicts PASS / not-a-log / FAIL")

    # --- 3. second run: exactly-once, nothing new, rc 0
    results, tip = kw.check_captures(repo, EXP, state)
    assert results == [], results
    rc = kw.main(["--repo", repo, "--state", state_path])
    assert rc == 0, rc
    print("PASS rerun: no new captures, rc 0")

    # --- 4. only a good log: rc 0
with tempfile.TemporaryDirectory() as root:
    origin = make_origin(root, {"260109-100000.txt": GOOD})
    repo = clone(root, origin, "r3")
    rc = kw.main(["--repo", repo, "--state", os.path.join(root, "s3.json")])
    assert rc == 0, rc
    print("PASS all-good captures: rc 0")

print("kit_log_watch: all pins hold")
