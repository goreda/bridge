#!/usr/bin/env python3
"""W-0221: run the REAL FramePump consuming loop against fixed vectors (Linux Swift).

Compiles the complete, unmodified production file (pin-checked) together with a
test-only shim (AtomicU64 + TimingLedger stand-ins, whose real files are outside
the packet) and Tests/parity/LoopParity.swift, then runs
fixtures/corpus/loop-parity.json. Nothing in the production file is copied or edited.

  python3 Tests/parity/run-loop-parity.py --source Sources/GorAVPlaybackCore/PlaybackCore.swift
  python3 Tests/parity/run-loop-parity.py --source ... --negative-controls

--negative-controls compiles a PERTURBED COPY per control in a temp dir (the pin
check is skipped for the copy only, and the real file is never touched) and
requires the suite to FAIL for every control.
"""
import argparse, hashlib, subprocess, tempfile
from pathlib import Path

SOURCE_SHA256 = 'd51e131eb6240279bbb207c7d1b323d947d6d3fb41fb0d4fdcf709a1419f2260'
# (name, exact text in production file, replacement) - one-line arithmetic/ordering changes
CONTROLS = [
    ('drift-sign-flip', 'paceAnchorPts! + (decisionNow - paceAnchorWall)', 'paceAnchorPts! - (decisionNow - paceAnchorWall)'),
    ('deadline-off-by-one-frame', 'paceAnchorPts! + (decisionNow - paceAnchorWall)', 'paceAnchorPts! + (decisionNow - paceAnchorWall) + frame.durationSeconds'),
    ('seek-anchor-wall-zero', 'paceAnchorPts = a; paceAnchorWall = clock.nowSeconds()', 'paceAnchorPts = a; paceAnchorWall = 0'),
    ('retry-limit-100-to-1000', 'if guardCount > 100 {', 'if guardCount > 1000 {'),
    ('drop-stale-wait-fence', 'if pullRevision != (commit?.revision ?? presentationRevision) || seekBarrierInFlight {', 'if false {'),
    ('no-order-reset-on-seek', '        lastPts = -Double.infinity\n        lastDuration = 0.0\n        if let a = seekAnchorSeconds {', '        if let a = seekAnchorSeconds {'),
]

def build_and_run(swiftc, src_text, root, scratch):
    prod = scratch / 'PlaybackCore.swift'
    prod.write_text(src_text)
    binary = scratch / 'loop-parity'
    subprocess.run([swiftc, '-swift-version', '5', '-parse-as-library', str(prod),
                    str(root / 'Tests/parity/LoopShim.swift'), str(root / 'Tests/parity/LoopParity.swift'),
                    '-o', str(binary)], check=True, timeout=120)
    return subprocess.run([str(binary), str(root / 'fixtures/corpus/loop-parity.json')],
                          capture_output=True, text=True, timeout=60)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--source', type=Path, required=True)
    ap.add_argument('--swiftc', default='swiftc')
    ap.add_argument('--negative-controls', action='store_true')
    a = ap.parse_args()
    raw = a.source.read_bytes()
    actual = hashlib.sha256(raw).hexdigest()
    if actual != SOURCE_SHA256:
        raise SystemExit('source pin mismatch: ' + actual)
    root = Path(__file__).resolve().parents[2]
    text = raw.decode('utf-8')
    with tempfile.TemporaryDirectory(prefix='loop-parity-') as d:
        r = build_and_run(a.swiftc, text, root, Path(d))
        print(r.stdout, end='')
        if r.returncode:
            raise SystemExit('loop parity FAILED on the pinned production file')
    print('SOURCE_SHA256 ' + actual)
    if a.negative_controls:
        bad = 0
        for name, old, new in CONTROLS:
            if text.count(old) != 1:
                raise SystemExit('control %s: expected exactly one match, found %d' % (name, text.count(old)))
            with tempfile.TemporaryDirectory(prefix='loop-neg-') as d:
                r = build_and_run(a.swiftc, text.replace(old, new), root, Path(d))
            fails = [l for l in r.stdout.splitlines() if l.startswith('FAIL')]
            print('NEGATIVE CONTROL %-28s exit=%d failing_checks=%d  e.g. %s' % (name, r.returncode, len(fails), fails[0][:110] if fails else '-'))
            if r.returncode == 0: bad += 1
        if bad: raise SystemExit('%d negative control(s) did NOT fail' % bad)
        print('all %d negative controls fail as required' % len(CONTROLS))
    print('Scope: unmodified production FramePump/AVSyncDecider/MediaWallAnchor/CancelCommit on a virtual monotonic clock with scripted source and recording sink; AtomicU64 and TimingLedger are test stand-ins. Not native display, audio, HDR, real decoder queue (QueuedFrameSource barrier) or full-package parity.')

if __name__ == '__main__':
    main()
