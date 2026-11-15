#!/usr/bin/env python3
"""check.py - W-gdb-054 bounded executable gate.

Runs, in order, everything bounded:
 1. carrier integrity: CARRIER.sha256 must match the files on disk
 2. build: make e2e_client + test_wire (gcc, bounded)
 3. mutant A (no-server): tests/test_wire on a port with no listener must
    produce exactly the six observed FAIL sites and WIRE RESULT: FAIL (6)
 4. mutant B (fix): gen_mutants.py output run_e2e_fix.sh must print
    WIRE RESULT: PASS and E2E RESULT: PASS

Prints one line per check; exits 0 only when all four pass.
"""
import hashlib
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent
EXPECTED_FAIL_SITES = [
    "tests/test_wire.c:49", "tests/test_wire.c:61", "tests/test_wire.c:66",
    "tests/test_wire.c:75", "tests/test_wire.c:77", "tests/test_wire.c:82",
]


def run(cmd, timeout, **kw):
    return subprocess.run(cmd, cwd=ROOT, timeout=timeout,
                          capture_output=True, text=True, **kw)


def check_carrier():
    ok = True
    for line in (ROOT / "CARRIER.sha256").read_text().splitlines():
        want, rel = line.split(None, 1)
        got = hashlib.sha256((ROOT / rel).read_bytes()).hexdigest()
        if got != want:
            print(f"FAIL carrier mismatch: {rel}")
            ok = False
    if ok:
        print("PASS carrier-integrity")
    return ok


def check_build():
    r = run(["make", "tests/e2e_client", "tests/test_wire"], timeout=180)
    if r.returncode != 0:
        print("FAIL build:", r.stdout[-400:], r.stderr[-400:])
        return False
    print("PASS build")
    return True


def check_mutant_no_server():
    # Mutant A: no synthetic server anywhere on 8971; test_wire must FAIL at
    # exactly the six observed sites. This is the observed cause: every
    # server-dependent assertion fails when nothing listens.
    r = run(["./tests/test_wire", "8971"], timeout=60)
    out = r.stdout
    sites = re.findall(r"FAIL (tests/test_wire\.c:\d+)", out)
    if sites == EXPECTED_FAIL_SITES and "WIRE RESULT: FAIL (6)" in out:
        print("PASS mutant-A-no-server (exactly the 6 observed sites)")
        return True
    print(f"FAIL mutant-A-no-server: sites={sites} tail={out[-200:]!r}")
    return False


def check_mutant_fix():
    g = run([sys.executable, "gen_mutants.py"], timeout=30)
    if g.returncode != 0:
        print("FAIL gen_mutants:", g.stdout, g.stderr)
        return False
    r = run(["sh", "tests/run_e2e_fix.sh"], timeout=180)
    out = r.stdout
    if "WIRE RESULT: PASS" in out and "E2E RESULT: PASS" in out and r.returncode == 0:
        print("PASS mutant-B-fixed-e2e")
        return True
    print(f"FAIL mutant-B-fixed-e2e rc={r.returncode} tail={out[-300:]!r} err={r.stderr[-200:]!r}")
    return False


def main():
    results = [check_carrier(), check_build(), check_mutant_no_server(), check_mutant_fix()]
    passed = sum(results)
    print(f"b7-transport-flake: {passed}/4 checks PASS")
    return 0 if passed == 4 else 1


if __name__ == "__main__":
    sys.exit(main())
