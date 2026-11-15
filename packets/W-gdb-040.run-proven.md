# W-gdb-040 seek determinism digest kit
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-040

```packet-json
{
  "packet_id": "W-gdb-040",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
  "touched_files": [
    {
      "path": "scripts/ci/seek-determinism.sh",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "seek-determinism.sh -> run1.digest vs run2.digest, identical required",
    "types": "digest spec fields { target, anchor, reset, resume, decision }; byte-exact spec is the deliverable",
    "ownership_lifetime": "synthetic media descriptions only; byte-exact digest spec is the deliverable interface",
    "caller": "CI step + seek determinism runner",
    "callee": "scripts/ci/seek-determinism.sh digest compare (excerpt in packet) + hardened digest spec"
  },
  "test": {
    "command": "bash scripts/ci/seek-determinism.sh",
    "expected": "exit 0 on Linux; two runs of the fixed seek sequence produce identical digests; a seeded rng produces a field-by-field diff (negative control shown in the returned log)",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "scripts/ci/seek-determinism.sh",
      "kits/seek-determinism/"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/seek-determinism/fixtures.json",
        "block": "fixtures1"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "bash scripts/ci/seek-determinism.sh",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:15:02.315158+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "SEEK-DETERMINISM PASS",
    "inline_files": [
      {
        "path": "kits/seek-determinism/fixtures.json",
        "block": "fixtures1",
        "sha256": "c6c16d759e79b7f3fe76a62a915258d5902bf7a595370355020ab33841bdb054"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "788e22c330650fbb89ec22ea74454e01db7f089b827a626b4c273ef2896a77a7",
    "last_5_lines": [
      "SEEK-DETERMINISM PASS digests=125 byte-identical"
    ],
    "receipt_sha256": "6cf11d563877850551177df529faeecdb25b25b7dd4310d309dfc26832266ef1"
  }
}
```

## problem (what fails for the user)
the same seek sequence must produce the same decisions every run; nondeterminism here ships as flaky seeks that no single-run test catches.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: scripts/ci/seek-determinism.sh (sha256 c1bfe018, whole below) - the existing back-to-back digest compare; seek-contract-tests (84 checks) per the harness map.
- real test command: bash scripts/ci/seek-determinism.sh stays green on Linux.

## expected behaviour
a hardened kit: fixed seek sequence run twice through a candidate pipeline, every decision (target, anchor, reset, resume) digested into one comparison hash per run; identical digests required, divergence printed field-by-field; documented byte-exact digest spec.

## exact call site and interface
the existing script (pinned excerpt) is the baseline the kit hardens; digest spec is the deliverable interface.

## behaviour that must not change
the 84 seek-contract checks stay green; synthetic media descriptions only.

## acceptance test (from the product repo)
two runs produce identical digests; a seeded rng in the pipeline produces a field-by-field diff (negative control shown).

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### scripts/ci/seek-determinism.sh (sha256 c1bfe018, lines 1-85 of 85)
```sh id=source1
#!/usr/bin/env bash
# Seek determinism witness (gorav queue item 12): run real-seek-tests twice
# back-to-back and byte-compare the DIGEST log lines; nonzero exit on drift.
#
# Modes:
#   (default)               run the seek tests twice, then compare
#   --compare LOG1 LOG2     compare two existing logs (fixture mode)
#
# Env: GORAV_REAL_SEEK_CMD overrides the test command
# (default: "swift run real-seek-tests"); GORAV_KIT passes through.
# Exit 0 = digest logs byte-identical; 1 = drift or a failing test run;
# 2 = typed NOT_RUN (unrunnable command, test-side NOT_RUN, no DIGEST lines).
set -euo pipefail
exec python3 - "$@" <<'PY'
import os, re, subprocess, sys

DIGEST = re.compile(r'^DIGEST ')
NOT_RUN = re.compile(r'^NOT_RUN ', re.M)
# Targets like seek-ring-reset-tests print FAIL/FAILURES lines but exit 0;
# a failure line is a failing run even when the exit code says otherwise.
FAIL_LINE = re.compile(r'^(FAIL |FAILURES=)', re.M)

def digests(text):
    return [line for line in text.splitlines() if DIGEST.match(line)]

def compare(first, second):
    a, b = digests(first), digests(second)
    if not a or not b:
        print('NOT_RUN no_digest_lines a=%d b=%d qualification=unproven' % (len(a), len(b)))
        return 2
    if len(a) != len(b):
        print('FAIL drift digest_count a=%d b=%d' % (len(a), len(b)))
        return 1
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            print('FAIL drift line=%d\n  run1: %s\n  run2: %s' % (i, x, y))
            return 1
    print('SEEK-DETERMINISM PASS digests=%d byte-identical' % len(a))
    return 0

def run(cmd, env):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                           env=env, timeout=3600)
    except (OSError, subprocess.TimeoutExpired) as e:
        print('NOT_RUN command_unrunnable %s qualification=unproven' % e)
        sys.exit(2)
    out = p.stdout + p.stderr
    if p.returncode == 127:
        # shell could not exec the command at all: environment, not a result
        print('NOT_RUN command_unrunnable rc=127 qualification=unproven')
        sys.exit(2)
    if NOT_RUN.search(out):
        sys.stdout.write(out)
        print('NOT_RUN seek-tests reported NOT_RUN qualification=unproven')
        sys.exit(2)
    if p.returncode != 0:
        sys.stdout.write(out)
        print('FAIL seek-tests rc=%d' % p.returncode)
        sys.exit(1)
    if FAIL_LINE.search(p.stdout):
        sys.stdout.write(out)
        print('FAIL seek-tests reported failure lines')
        sys.exit(1)
    return p.stdout

args = sys.argv[1:]
if args[:1] == ['--compare']:
    if len(args) != 3:
        print('usage: seek-determinism.sh [--compare LOG1 LOG2]')
        sys.exit(2)
    with open(args[1], encoding='utf-8') as f:
        first = f.read()
    with open(args[2], encoding='utf-8') as f:
        second = f.read()
    sys.exit(compare(first, second))
if args:
    print('usage: seek-determinism.sh [--compare LOG1 LOG2]')
    sys.exit(2)
cmd = os.environ.get('GORAV_REAL_SEEK_CMD', 'swift run real-seek-tests')
env = dict(os.environ)
first = run(cmd, env)
second = run(cmd, env)
sys.exit(compare(first, second))
PY
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"seekSequence":[0.0,1.5,2.96,0.5],"digestFields":["target","anchor","reset","resume","decision"],"expect":"run1.digest == run2.digest"}
```

```text id=actual_run_log
SEEK-DETERMINISM PASS digests=125 byte-identical
```
