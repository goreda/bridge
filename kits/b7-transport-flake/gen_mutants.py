#!/usr/bin/env python3
"""gen_mutants.py - W-gdb-054: produce the two executable mutants.

Mutant A (no-server): nothing to generate - check.py runs tests/test_wire
with no synthetic server listening (observed cause of the 6 FAILs).

Mutant B (fix): tests/run_e2e_fix.sh - the carrier run_e2e.sh with the fixed
`sleep 1` startup window replaced by a bounded readiness poll (deadline 5s,
hard fail with a named error), on a distinct port to avoid collisions.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
src = (ROOT / "tests" / "run_e2e.sh").read_text()

POLL = (
    "python3 - \"$PORT\" <<'PYEOF'\n"
    "import socket, sys, time\n"
    "port = int(sys.argv[1]); deadline = time.monotonic() + 5.0\n"
    "while True:\n"
    "    s = socket.socket()\n"
    "    try:\n"
    "        s.connect((\"127.0.0.1\", port)); s.close(); break\n"
    "    except OSError:\n"
    "        s.close()\n"
    "        if time.monotonic() > deadline:\n"
    "            print(\"readiness-timeout: synth server not listening after 5.0s\", file=sys.stderr)\n"
    "            sys.exit(2)\n"
    "        time.sleep(0.1)\n"
    "PYEOF\n"
)

if "sleep 1\n" not in src:
    print("carrier run_e2e.sh does not contain the expected `sleep 1` line", file=sys.stderr)
    sys.exit(2)

mutant = src.replace("PORT=8971", "PORT=8973")
mutant = mutant.replace("sleep 1\n", POLL)
out = ROOT / "tests" / "run_e2e_fix.sh"
out.write_text(mutant)
out.chmod(0o755)
print("wrote tests/run_e2e_fix.sh (port 8973, bounded readiness poll 5.0s)")
