#!/usr/bin/env python3
"""native102 (observation-only overlay) close-leg + drain-result observability.

Source-contract assertions, no behavior/bound change (goreda T2: native101
B3 close 5139.1ms ~= drainBounded maxSeconds 5.0 without evidence):
(1) the teardown drainBounded result is OBSERVED (start/remaining/cancelled
captured into session state and copied into EmbeddedCloseReport) - the
`_ = drained` discard must NOT exist in the session cleanup; (2) the close
legs are timed separately (task await, presenter/decoder close, drain,
audio.stop) via a ContinuousClock ms helper; (3) the ring depth at close
REQUEST time is captured (pre-drain honest state); (4) the B gate prints a
B3 close-obs line and FAIL-OBS dumps the close report when present. All
bounds (B3 closeMs < 300, drain maxSeconds 5.0) UNCHANGED. Runs on Linux
(text-only); mutants (re-discard the drain result, drop a leg timing, drop
the FAIL-OBS close dump) MUST be detected.

STRENGTH LABEL: text-contract, not behavioral. It does not close a
session; the behavioral evidence is the next native macOS run's B3
close-obs line.

NOT_RUN here (explicit, no inferred acceptance):
  - Any session/teardown execution: macOS venue only.
  - swift test targets: no Swift toolchain in this workspace.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # archive/gor
SESSION = (ROOT / 'Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift').read_text()
BGATE = (ROOT / 'Packages/gorav/Sources/b-gate-tests/main.swift').read_text()

DRAIN_DISCARD = '_ = drained'
LEG_HELPER = 'private static func ms(since t: ContinuousClock.Instant) -> Double'
REPORT_FIELDS = ['public var audioRingBytesAtRequest: Int?',
                 'public var audioDrainStartBytes: Int?',
                 'public var audioDrainRemainingBytes: Int?',
                 'public var audioDrainCancelled: Bool?',
                 'public var taskAwaitMs: Double?',
                 'public var presenterDecoderCloseMs: Double?',
                 'public var audioDrainMs: Double?',
                 'public var audioStopMs: Double?']
DRAIN_CAPTURE = ['lastDrainStartBytes = audio.available',
                 'lastDrainRemainingBytes = drained.remaining',
                 'lastDrainCancelled = drained.cancelled']
REPORT_COPY = ['report.audioDrainRemainingBytes = lastDrainRemainingBytes',
               'report.audioDrainCancelled = lastDrainCancelled',
               'report.taskAwaitMs = legTaskAwaitMs',
               'report.presenterDecoderCloseMs = legPresenterDecoderCloseMs',
               'report.audioDrainMs = legAudioDrainMs',
               'report.audioStopMs = legAudioStopMs',
               'report.audioRingBytesAtRequest = audio?.available']
B3_OBS = 'B-GATE B3 close-obs'
FAILOBS_CLOSE = 'B-GATE FAIL-OBS close'


def check(session, bgate):
    fails = []
    if DRAIN_DISCARD in session:
        fails.append('session: drain result discarded again (_ = drained)')
    if LEG_HELPER not in session:
        fails.append('session: ContinuousClock ms helper missing')
    for needle in REPORT_FIELDS + DRAIN_CAPTURE + REPORT_COPY:
        if needle not in session:
            fails.append('session: missing ' + needle)
    # the drain bound is unchanged (native103 selects 0.0 only on a paused
    # close; the playing bound stays 5.0)
    if '0.0 : 5.0)' not in session and 'drainBounded(maxSeconds: 5.0)' not in session:
        fails.append('session: drain bound changed')
    if B3_OBS not in bgate:
        fails.append('bgate: B3 close-obs line missing')
    if FAILOBS_CLOSE not in bgate:
        fails.append('bgate: FAIL-OBS close-report dump missing')
    if 'report.closeMs < 300' not in bgate:
        fails.append('bgate: B3 300ms close bound changed')
    if 'var lastCloseReportForObs: EmbeddedCloseReport?' not in bgate:
        fails.append('bgate: close-report observation var missing')
    return fails


def main():
    fails = check(SESSION, BGATE)
    for name, args in [
        ('drain discarded', (SESSION.replace('lastDrainRemainingBytes = drained.remaining',
                                             '_ = drained', 1), BGATE)),
        ('leg timing dropped', (SESSION.replace('report.audioDrainMs = legAudioDrainMs',
                                                '// mutant', 1), BGATE)),
        ('failobs close dump dropped', (SESSION, BGATE.replace(FAILOBS_CLOSE, 'mutant', 1))),
    ]:
        if not check(*args):
            fails.append('mutant undetected: ' + name)
    if fails:
        for f in fails:
            print('FAIL:', f)
        raise SystemExit(1)
    print('PASS: drain result observed + close legs timed + B3 close-obs/FAIL-OBS dump; bounds unchanged')


if __name__ == '__main__':
    main()
