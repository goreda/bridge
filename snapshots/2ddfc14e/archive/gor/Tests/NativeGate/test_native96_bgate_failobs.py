#!/usr/bin/env python3
"""native96r2 (instrumentation-only overlay) B-gate failure-path observation.

Source-contract assertions on Packages/gorav/Sources/b-gate-tests/main.swift:
on ANY B-stage failure the gate must dump (a) the wait-loop snapshot samples
(branch, generation, anchor, presentation, seekLandingDrops, timing per
sample), (b) the landing-drop counter, and (c) seekTrace lines before exit,
via failObserved; waitFor must sample the session snapshot at ~1s cadence
plus a final timeout sample. All bounds, timeouts and pass conditions are
UNCHANGED (no gate relaxation). Runs on Linux (text-only); mutants
(un-sample waitFor, revert a B-stage fail site) MUST be detected.

STRENGTH LABEL: text-contract, not behavioral. It does not run the gate;
the behavioral evidence is the FAIL-OBS block in the next macOS run log.

NOT_RUN here (explicit, no inferred acceptance):
  - The B gate itself: macOS + Metal venue only.
  - swift test targets: no Swift toolchain in this workspace.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # archive/gor
GATE = (ROOT / 'Packages/gorav/Sources/b-gate-tests/main.swift').read_text()


DECLS = '    var lastSnapshot: EmbeddedSnapshot?\n    var waitSamples: [String] = []'


def check(src):
    fails = []
    # A1 compile fix (b7393eb5): the observation vars must be declared BEFORE
    # the onEvent closure that captures them via failObserved. Text-contract
    # declaration-order assertion, NOT a compile proof.
    on_event = src.find('s.onEvent = { ev in')
    decl_at = src.find(DECLS)
    if decl_at < 0:
        fails.append('observation var declarations missing')
    elif on_event < 0 or decl_at > on_event:
        fails.append('observation vars must be declared before the onEvent closure (A1 capture error)')
    for needle in ['func failObserved(_ msg: String) async -> Never',
                   'await s.snapshot() ?? lastSnapshot',
                   'Task { await failObserved(',
                   'B-GATE FAIL-OBS sample',
                   'B-GATE FAIL-OBS seekTrace',
                   'seekLandingDrops=',
                   'lastDropPTS=%@',
                   'fenced=%@',
                   'admitNil=%@',
                   'sinkFalse=%@',
                   'lastDecPTS=%@',
                   'maxDecPTS=%@',
                   'fenced=\\(String(describing: snap.seekLandingFencedShows))',
                   'func refreshSnapshot(_ branch: String) async',
                   'await refreshSnapshot(desc + ":timeout")']:
        if needle not in src:
            fails.append('missing ' + needle)
    # every B-stage fail site must route through failObserved
    if re.search(r'\bfail\("B\d', src):
        fails.append('a B-stage fail site still bypasses failObserved')
    if src.count('failObserved(') < 20:
        fails.append('expected >=20 failObserved references (18 B-stage + check + event + decl)')
    # bounds and pass conditions unchanged
    for needle in ['waitFor("post-seek frame0", 10',
                   'no post-seek frame0 within 10s (grounded bound)',
                   'waitFor("committed firstFrame time-pos witness", 10']:
        if needle not in src:
            fails.append('bound/pass-condition changed: missing ' + needle)
    return fails


def main():
    fails = check(GATE)
    for name, mutant in [
        ('waitFor unsampled', GATE.replace('await refreshSnapshot(desc + ":timeout")', '// mutant', 1)),
        ('B-stage fail bypass', GATE.replace('failObserved("B2 no post-seek frame0', 'fail("B2 no post-seek frame0', 1)),
        ('decls moved after onEvent', GATE.replace(DECLS + '\n', '').replace(
            '    // native96r2 (local overlay', DECLS + '\n    // native96r2 (local overlay', 1)),
    ]:
        if not check(mutant):
            fails.append('mutant undetected: ' + name)
    if fails:
        for f in fails:
            print('FAIL:', f)
        raise SystemExit(1)
    print('PASS: B-gate failure path dumps samples + landing drops + fenced splits + decoded-pts + seekTrace; bounds unchanged')


if __name__ == '__main__':
    main()
