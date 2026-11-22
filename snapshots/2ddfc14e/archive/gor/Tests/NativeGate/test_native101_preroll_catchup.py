#!/usr/bin/env python3
"""native101 (isolated, revertible product fix) post-seek preroll cheap catch-up.

Source-contract assertions, no bound and no landing-condition change:
(1) FFmpegSoftwareDecoder arms a preroll skip window at BOTH seek paths
with the seek target ticks, resets its skip counter there, and skips
decoded pre-target frames pre-retention/pre-emission in pipelineStep
(decoded, never emitted - reference chain intact), closing the window at
the first frame at/above the target; (2) the skip is counted and surfaced
(decoder seekPrerollSkipped -> EmbeddedSnapshot.seekPrerollSkipped -> the
C gate sample/failobs lines and the B gate FAIL-OBS lines); (3) the
pump's preSeekLanding predicate, the 10s resume bound and the C pass
condition are UNCHANGED (backstop intact). Runs on Linux (text-only);
mutants (drop the skip, drop the window close, drop one seek-site arm,
drop the counter fill) MUST be detected.

STRENGTH LABEL: text-contract, not behavioral. It does not decode
anything; the behavioral evidence is the next native macOS run's
prerollSkipped growth and landing time.

NOT_RUN here (explicit, no inferred acceptance):
  - Any decoder/pump execution: macOS venue only.
  - swift test targets: no Swift toolchain in this workspace.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # archive/gor
DEC = (ROOT / 'Packages/gorav/Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift').read_text()
SESSION = (ROOT / 'Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift').read_text()
GATE = (ROOT / 'Sources/gor/Engine/GorAVNativeGate.swift').read_text()
BGATE = (ROOT / 'Packages/gorav/Sources/b-gate-tests/main.swift').read_text()
PUMP = (ROOT / 'Packages/gorav/Sources/GorAVPlaybackCore/PlaybackCore.swift').read_text()

WINDOW_DECL = 'private var l3SeekPrerollBeforePTS: Int64?'
SKIPCOUNT_DECL = 'private var l3SeekPrerollSkipped = 0'
ACCESSOR = 'public var seekPrerollSkipped: Int { l3OnQueue { l3SeekPrerollSkipped } }'
ARM_COORD = 'l3SeekPrerollBeforePTS = ticks'
ARM_LEGACY = 'self.l3SeekPrerollBeforePTS = ts'
SKIP_INC = 'self.l3SeekPrerollSkipped += 1'
SEEN_DECL = 'private var l3SeekPrerollSeen = 0'
SEEN_INC = 'self.l3SeekPrerollSeen += 1'
# native101r3 (goreda T2): the guard must key on the EVERY-pre-target-frame
# counter, never the skipped-only counter (sticky at 31), and a per-turn
# skip cap must force a leak/yield before the 128-iteration stall guard
LEAK_GUARD = 'if self.l3SeekPrerollSeen % 32 != 0, prerollSkipsThisTurn < 24 {'
STICKY_GUARD = 'l3SeekPrerollSkipped % 32'
TURN_CAP_DECL = 'var prerollSkipsThisTurn = 0'
TURN_CAP_INC = 'prerollSkipsThisTurn += 1'
WINDOW_CLOSE = 'self.l3SeekPrerollBeforePTS = nil'
B_GATE_PUMPEND = 'pumpEnd=\\(String(describing: snap.pumpEndReason))'
C_GATE_PUMPEND = 'pumpEnd=\\(String(describing: s.pumpEndReason))'
SNAP_FIELD = 'public var seekPrerollSkipped: Int?'
SNAP_FILL = 's.seekPrerollSkipped = decoder?.seekPrerollSkipped'
PUMP_PREDICATE = 'frame.ptsSeconds < landing'


def check(dec, session, gate, bgate, pump):
    fails = []
    for name, needle in [('window decl', WINDOW_DECL), ('skip counter decl', SKIPCOUNT_DECL),
                         ('accessor', ACCESSOR), ('coordinated arm', ARM_COORD),
                         ('legacy arm', ARM_LEGACY), ('skip increment', SKIP_INC),
                         ('window close', WINDOW_CLOSE)]:
        if needle not in dec:
            fails.append('decoder: ' + name + ' missing')
    if LEAK_GUARD not in dec:
        fails.append('decoder: bounded-burst leak guard missing (native100 pump:-9 regression)')
    if STICKY_GUARD in dec:
        fails.append('decoder: leak guard keys on the skipped-only counter (r2 sticky-leak defect)')
    for name, needle in [('seen decl', SEEN_DECL), ('seen inc', SEEN_INC),
                         ('turn cap decl', TURN_CAP_DECL), ('turn cap inc', TURN_CAP_INC)]:
        if needle not in dec:
            fails.append('decoder: ' + name + ' missing')
    if dec.count('l3SeekPrerollSeen = 0') < 3:  # decl + 2 seek sites
        fails.append('decoder: seen counter not reset at both seek sites')
    # every pre-target frame must count BEFORE the skip/leak decision
    if SEEN_INC in dec and LEAK_GUARD in dec and dec.index(SEEN_INC) > dec.index(LEAK_GUARD):
        fails.append('decoder: seen counter incremented after the leak decision')
    if SKIP_INC in dec and 'if let mark = self.l3SeekPrerollBeforePTS {' in dec:
        # the skip must free the frame and continue INSIDE pipelineStep,
        # BEFORE the retention/lease/emission section (the -24 order guard
        # comment marks the emission boundary)
        guard_at = dec.index('presentation order fault')
        skip_at = dec.index(SKIP_INC)
        if skip_at > guard_at:
            fails.append('decoder: preroll skip is not before emission')
        # exactly one emission-site close (plus the two seek-site re-arms
        # which assign, not nil-close): the window must close once per use
        if dec.count('if let mark = self.l3SeekPrerollBeforePTS {') != 1:
            fails.append('decoder: expected exactly one preroll window site')
        # both seek arms must reset the counter too
        if dec.count('l3SeekPrerollSkipped = 0') < 3:  # decl + 2 seek sites
            fails.append('decoder: skip counter not reset at both seek sites')
    if SNAP_FIELD not in session:
        fails.append('session: snapshot seekPrerollSkipped field missing')
    if SNAP_FILL not in session:
        fails.append('session: snapshot preroll fill missing')
    if gate.count('prerollSkipped=') != 2:
        fails.append('gate: C sample + failobs must both carry prerollSkipped')
    if bgate.count('prerollSkipped=%@') != 1 \
            or bgate.count('prerollSkipped=\\(String(describing: snap.seekPrerollSkipped))') != 1:
        fails.append('bgate: FAIL-OBS sample + dump must carry prerollSkipped')
    # native101r2: the failure-path dumps must carry the pump end reason so
    # a decoder failure code (e.g. -9) is visible in the B/C fail output
    if B_GATE_PUMPEND not in bgate:
        fails.append('bgate: FAIL-OBS dump missing pumpEnd')
    if C_GATE_PUMPEND not in gate:
        fails.append('gate: C failobs dump missing pumpEnd')
    # backstops and bounds unchanged
    if PUMP_PREDICATE not in pump:
        fails.append('pump: preSeekLanding backstop predicate changed')
    if 'systemUptime + 10' not in gate or 'time >= 8 && anchor >= 7.5' not in gate:
        fails.append('gate: 10s bound or pass condition changed')
    return fails


def main():
    fails = check(DEC, SESSION, GATE, BGATE, PUMP)
    for name, args in [
        ('skip dropped', (DEC.replace(SKIP_INC, '// mutant', 1), SESSION, GATE, BGATE, PUMP)),
        ('window close dropped', (DEC.replace('self.l3SeekPrerollBeforePTS = nil\n', '// mutant\n', 1),
                                  SESSION, GATE, BGATE, PUMP)),
        ('legacy arm dropped', (DEC.replace(ARM_LEGACY, '// mutant', 1), SESSION, GATE, BGATE, PUMP)),
        ('counter fill dropped', (DEC, SESSION.replace(SNAP_FILL, '// mutant', 1), GATE, BGATE, PUMP)),
        ('backstop dropped', (DEC, SESSION, GATE, BGATE, PUMP.replace(PUMP_PREDICATE, 'false &&', 1))),
        ('leak guard dropped', (DEC.replace(LEAK_GUARD, 'if true {', 1), SESSION, GATE, BGATE, PUMP)),
        ('bgate pumpEnd dropped', (DEC, SESSION, GATE, BGATE.replace(B_GATE_PUMPEND, 'mutant', 1), PUMP)),
        ('sticky leak guard (r2 defect)', (DEC.replace(LEAK_GUARD, 'if self.l3SeekPrerollSkipped % 32 != 31 {', 1),
                                           SESSION, GATE, BGATE, PUMP)),
        ('turn cap dropped', (DEC.replace(', prerollSkipsThisTurn < 24', '', 1), SESSION, GATE, BGATE, PUMP)),
        ('seen increment dropped', (DEC.replace(SEEN_INC, '// mutant', 1), SESSION, GATE, BGATE, PUMP)),
    ]:
        if not check(*args):
            fails.append('mutant undetected: ' + name)
    if fails:
        for f in fails:
            print('FAIL:', f)
        raise SystemExit(1)
    print('PASS: decoder-side preroll skip armed at both seeks, counted + surfaced; pump backstop + bounds unchanged')


if __name__ == '__main__':
    main()
