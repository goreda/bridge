#!/usr/bin/env python3
"""native103 (isolated product fix) paused-close drain skip, embedded path only.

Source-contract assertions (goreda T2 r5): a close while the pump's pause
witness says PAUSED must NOT wait the 5.0s drain - the quiesced ring
(residual HELD, AudioUnitSink renders silence without consuming) can never
drain, so the embedded teardown drops the residual with bound 0.0 and
stop() settles it as it does for any undrained remainder today. A PLAYING
close keeps drainBounded(maxSeconds: 5.0) exactly. Scope: ONLY
GorAVEmbeddedSession.cleanupLegs - the gor player paths
(ShellFrameSource, GorAVMetalShellApp) must keep their own drain logic
untouched. Bounds unchanged: B3 closeMs < 300 and the 5.0s playing-drain
bound both stay (no gate relaxation). Runs on Linux (text-only); mutants
(always-0.0, pause witness dropped, B3 bound raised) MUST be detected.

STRENGTH LABEL: text-contract, not behavioral. It does not close a
session; the behavioral evidence is the next native macOS run's B3
close-obs drainMs ~= 0 with drainRemaining == drainStart on a paused close.

NOT_RUN here (explicit, no inferred acceptance):
  - Any session/teardown execution: macOS venue only.
  - swift test targets: no Swift toolchain in this workspace.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # archive/gor
SESSION = (ROOT / 'Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift').read_text()
BGATE = (ROOT / 'Packages/gorav/Sources/b-gate-tests/main.swift').read_text()
SHELL = (ROOT / 'Packages/gorav/Sources/GorAVMacShell/ShellFrameSource.swift').read_text()
METAL = (ROOT / 'Packages/gorav/Sources/GorAVMetalPresenter/core/GorAVMetalShellApp.swift').read_text()

WITNESS = 'let pausedAtTeardown = await pump?.isPaused ?? false'
SELECT = 'await audio.drainBounded(maxSeconds: pausedAtTeardown ? 0.0 : 5.0)'
PLAYING_BOUND = '? 0.0 : 5.0)'


def check(session, bgate, shell, metal):
    fails = []
    if WITNESS not in session:
        fails.append('session: pause witness (pump isPaused) missing')
    if SELECT not in session:
        fails.append('session: paused/playing drain-bound selection missing')
    if session.count(PLAYING_BOUND) != 1:
        fails.append('session: expected exactly one drain-bound selection site')
    # the drain must still be observed (native102), never re-discarded
    if '_ = drained' in session:
        fails.append('session: drain result discarded again')
    if 'lastDrainRemainingBytes = drained.remaining' not in session:
        fails.append('session: drain observation lost')
    # bounds unchanged
    if 'report.closeMs < 300' not in bgate:
        fails.append('bgate: B3 300ms close bound changed')
    # gor player paths untouched: their drain call sites keep their shape
    if '? 0.0 : 5.0)' not in shell:
        fails.append('shell: ShellFrameSource drain selection changed (out of scope)')
    if 'drainBounded(maxSeconds: 5.0).remaining' not in metal:
        fails.append('metal: GorAVMetalShellApp drain changed (out of scope)')
    return fails


def main():
    fails = check(SESSION, BGATE, SHELL, METAL)
    for name, args in [
        ('always skip drain (playing close broken)',
         (SESSION.replace(SELECT, 'await audio.drainBounded(maxSeconds: 0.0)', 1), BGATE, SHELL, METAL)),
        ('pause witness dropped (defect returns)',
         (SESSION.replace(SELECT, 'await audio.drainBounded(maxSeconds: 5.0)', 1), BGATE, SHELL, METAL)),
        ('B3 bound raised',
         (SESSION, BGATE.replace('report.closeMs < 300', 'report.closeMs < 6000', 1), SHELL, METAL)),
        ('shell path touched',
         (SESSION, BGATE, SHELL.replace('? 0.0 : 5.0)', '? 0.0 : 2.0)', 1), METAL)),
    ]:
        if not check(*args):
            fails.append('mutant undetected: ' + name)
    if fails:
        for f in fails:
            print('FAIL:', f)
        raise SystemExit(1)
    print('PASS: paused close drops the residual without the 5s wait; playing close + gor player paths + bounds unchanged')


if __name__ == '__main__':
    main()
