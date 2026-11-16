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
  "product_sha": "8786bfe3e5482a891dda15248b107e50fab52463",
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
    "product_sha": "8786bfe3e5482a891dda15248b107e50fab52463",
    "command": "bash scripts/ci/seek-determinism.sh",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-16T00:00:08.158520+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "PASS",
    "inline_files": [
      {
        "path": "kits/seek-determinism/fixtures.json",
        "block": "fixtures1",
        "sha256": "c6c16d759e79b7f3fe76a62a915258d5902bf7a595370355020ab33841bdb054"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "072465e4093d166a98e9bcb8b52f5dfeb3fa5a63732416061243e85702d3afcc",
    "last_5_lines": [
      "FAIL drift step=2 field=resume run1=2000000 run2=1500000",
      "FAIL drift hash run1=['DIGEST-HASH v1 sha256=6d99793078a0a8f7fbba5094ba89f36afde09fb9f0882ff28f63aa387fe4acbf'] run2=['DIGEST-HASH v1 sha256=5f4c432bd7bdc4b62e2cedc44650ddfd078bf4fd46e3ee8b85a567834cfe7a01']",
      "KIT PASS (negative control detected)",
      "SEEK-DETERMINISM PASS digests=125 byte-identical",
      "REAL_LEG rc=0"
    ],
    "receipt_sha256": "1fe45c41f564a114e579eed1121b81bf25bb58f62d60f4bf4e2652b22a491f21"
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
#
# Kit (kits/seek-determinism/, spec DIGEST-SPEC.md):
#   --kit                   synthetic pipeline twice + seeded-rng negative control
# With GORAV_REAL_SEEK_CMD UNSET the default mode runs the kit leg (measured) and
# then tries the real leg (swift run real-seek-tests); an absent real binary is
# printed as "REAL_LEG NOT_RUN" and does not change the exit code unless
# GORAV_REQUIRE_REAL=1 (then exit 2). With GORAV_REAL_SEEK_CMD SET behaviour is the
# original strict one.
set -euo pipefail
SEEK_SELF="${BASH_SOURCE[0]}" exec python3 - "$@" <<'PY'
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

KIT = os.path.join(os.environ.get('GORAV_KIT') or os.path.join(
    os.path.dirname(os.path.abspath(os.environ.get('SEEK_SELF', ''))), '..', '..', 'kits', 'seek-determinism'))

def kit_leg(root):
    pipe, cmp_ = os.path.join(root, 'pipeline.py'), os.path.join(root, 'compare.py')
    import tempfile
    d = tempfile.mkdtemp()
    def go(name, extra=None):
        e = dict(os.environ); e.pop('KIT_RNG_SEED', None); e.update(extra or {})
        p = subprocess.run([sys.executable, pipe], capture_output=True, text=True, env=e)
        if p.returncode:
            print('FAIL kit pipeline rc=%d %s' % (p.returncode, p.stderr.strip())); return None
        f = os.path.join(d, name); open(f, 'w').write(p.stdout); return f
    r1, r2 = go('run1.digest'), go('run2.digest')
    n1, n2 = go('neg1.digest'), go('neg2.digest', {'KIT_RNG_SEED': '7'})
    if not all((r1, r2, n1, n2)):
        return 1
    c = subprocess.run([sys.executable, cmp_, r1, r2], capture_output=True, text=True)
    print('KIT run1 vs run2: ' + c.stdout.strip())
    if c.returncode != 0:
        return 1
    c = subprocess.run([sys.executable, cmp_, n1, n2], capture_output=True, text=True)
    print('KIT negative control (seeded rng, expect drift):\n' + c.stdout.rstrip())
    if c.returncode != 1 or 'field=' not in c.stdout:
        print('FAIL negative control did not produce a field-by-field diff'); return 1
    print('KIT PASS (negative control detected)')
    return 0

args = sys.argv[1:]
if args[:1] == ['--kit']:
    sys.exit(kit_leg(KIT))
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
env = dict(os.environ)
if 'GORAV_REAL_SEEK_CMD' in os.environ:
    cmd = os.environ['GORAV_REAL_SEEK_CMD']
    first = run(cmd, env)
    second = run(cmd, env)
    sys.exit(compare(first, second))
rc = kit_leg(KIT)
if rc != 0:
    sys.exit(rc)
# real leg: only meaningful where swift exists; never faked
import shutil
if shutil.which('swift') is None:
    print('REAL_LEG NOT_RUN swift_not_found qualification=unproven')
    sys.exit(2 if os.environ.get('GORAV_REQUIRE_REAL') == '1' else 0)
first = run('swift run real-seek-tests', env)
second = run('swift run real-seek-tests', env)
rrc = compare(first, second)
print('REAL_LEG rc=%d' % rrc)
sys.exit(rrc)
PY
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"seekSequence":[0.0,1.5,2.96,0.5],"digestFields":["target","anchor","reset","resume","decision"],"expect":"run1.digest == run2.digest"}
```

```text id=actual_run_log
KIT run1 vs run2: SEEK-DETERMINISM PASS digests=4 byte-identical
KIT negative control (seeded rng, expect drift):
FAIL drift step=2 field=anchor run1=2000000 run2=1500000
FAIL drift step=2 field=reset run1=1 run2=0
FAIL drift step=2 field=resume run1=2000000 run2=1500000
FAIL drift hash run1=['DIGEST-HASH v1 sha256=6d99793078a0a8f7fbba5094ba89f36afde09fb9f0882ff28f63aa387fe4acbf'] run2=['DIGEST-HASH v1 sha256=5f4c432bd7bdc4b62e2cedc44650ddfd078bf4fd46e3ee8b85a567834cfe7a01']
KIT PASS (negative control detected)
SEEK-DETERMINISM PASS digests=125 byte-identical
REAL_LEG rc=0
```
