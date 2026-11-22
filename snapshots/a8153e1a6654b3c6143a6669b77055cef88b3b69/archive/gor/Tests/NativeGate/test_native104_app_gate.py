#!/usr/bin/env python3
"""native104 (observation/driver-only overlay) D-stage app gate: normal AppDelegate path.

Source-contract assertions: (1) a D-stage driver exists that runs the
NORMAL AppDelegate lifecycle (main.swift keeps AppDelegate() under
--gorav-app-gate and only installs GorAVAppGate; the C gate's isolated
delegate selection is UNCHANGED); (2) the only AppDelegate touch is an
additive read-only seam (goravHostForAppGate) with goravHost still
private; (3) the driver takes media through the normal argv route and
FAILS D1 if the engine route is not gorav (no silent mpv fallback);
(4) the D checks use the production host's existing gate surface with
C3-parity bounds (20s first frame, 2s pause witness, 10s seek landing,
time>=8 && anchor>=7.5) and report venue/scanout as OBSERVED, never
verified; (5) D0 is emitted unconditionally at install, before app.run(); (6) the
driver exits directly after D7 - it never calls NSApp.terminate, because
the normal quit path's 6s watchdog (AppDelegate.swift:3341) would
_exit(70) and mask the gate verdict; (7) D4's pause/resume cycle is gated
on a bounded anchor+audio-admission witness (5s, PARTIAL note only, never
a verdict row) and a bounded resume-applied witness (2s) folded into
D4.resume-advance's verdict - these witnesses ADD worst-case ~7s of stage
time without changing the original check bounds or verdict semantics.
Runs on Linux (text-only); mutants (drop the install, drop the
gorav-route check, relax the seek condition, widen the seam, drop
install-time D0, reintroduce terminate, drop the saved-fd bypass, move
the dup after D0, drop the anchor witness, drop the resume witness, drop
the resumed conjunct, shift any wait bound) MUST be detected.

STRENGTH LABEL: text-contract, not behavioral. It does not boot the app;
the behavioral evidence is the next native macOS run's D-stage lines.

NOT_RUN here (explicit, no inferred acceptance):
  - App boot, AppDelegate lifecycle, scanout, macOS 13: macOS venue only.
  - swift build of Sources/gor: no Swift toolchain in this workspace.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # archive/gor
MAIN = (ROOT / 'Sources/gor/App/main.swift').read_text()
APPGATE = (ROOT / 'Sources/gor/Engine/GorAVAppGate.swift').read_text()
DELEGATE = (ROOT / 'Sources/gor/App/AppDelegate.swift').read_text()

C_TERNARY = ('CommandLine.arguments.contains("--gorav-native-gate")\n'
             '    ? MainActor.assumeIsolated { GorAVNativeGate() } : AppDelegate()')
INSTALL = 'GorAVAppGate.install(appDelegate: d)'
SEAM = 'var goravHostForAppGate: GorAVPlayerHost? { MainActor.assumeIsolated { goravHost } }'
PRIVATE_HOST = 'private var goravHost: GorAVPlayerHost?'


def check(main, appgate, delegate):
    fails = []
    if C_TERNARY not in main:
        fails.append('main: C gate delegate selection changed')
    if INSTALL not in main:
        fails.append('main: D-stage install missing')
    if '--gorav-app-gate' not in main:
        fails.append('main: --gorav-app-gate flag missing')
    if SEAM not in delegate:
        fails.append('delegate: additive gate seam missing')
    if PRIVATE_HOST not in delegate:
        fails.append('delegate: goravHost no longer private (seam widened)')
    for needle in ['"stage": "D"',
                   'await wait(30)',
                   'Foundation.exit(failed ? 1 : 0)',
                   'D0.driver-enter',
                   'dup(STDOUT_FILENO)',
                   'FileHandle(fileDescriptor: gDStageOutFD, closeOnDealloc: false)',
                   'D0.argv',
                   'D0.instances',
                   'D0.atexit',
                   'D0.will-terminate',
                   'D1.wait-begin',
                   'D1.poll',
                   'note("D4.anchor-witness"',
                   '!s.audioFirstAdmissionWallSeconds.isEmpty',
                   'isPaused == false',
                   'resumed && t0 != nil',
                   'activePlayerEngine) } ?? "nil"',
                   'engine == "gorav"',
                   'goravHostForAppGate',
                   'gateWindowVisible',
                   'await wait(20)',
                   'await wait(2)',
                   'await wait(10)',
                   'time >= 8 && anchor >= 7.5',
                   'D6.scanout',
                   'scanout verification NOT_RUN',
                   'gateCloseReport?.cleanShutdown']:
        if needle not in appgate:
            fails.append('appgate: missing ' + needle)
    # the driver must never fabricate the engine route or acceptance
    if 'no owner acceptance' not in appgate:
        fails.append('appgate: no-acceptance scope note missing')
    # D0 must be emitted at install, before observer registration (native104
    # venue FAIL: zero D lines when the notification chain was pre-empted)
    i_d0 = appgate.find('note("D0.scope"')
    i_obs = appgate.find('addObserver')
    if i_d0 < 0 or i_obs < 0 or i_d0 > i_obs:
        fails.append('appgate: D0.scope not emitted before observer registration')
    i_dup = appgate.find('dup(STDOUT_FILENO)')
    if i_dup < 0 or i_d0 < 0 or i_dup > i_d0:
        fails.append('appgate: stdout not duped before the first D0 emit')
    # anchor-witness is observation (PARTIAL note), never a verdict row
    if 'line("D4.anchor-witness"' in appgate:
        fails.append('appgate: anchor-witness promoted to a verdict row')
    # native108 A1 compile FAIL class: optional chaining on the NON-optional
    # [Double] field (EmbeddedSnapshot.audioFirstAdmissionWallSeconds)
    if 'audioFirstAdmissionWallSeconds?' in appgate:
        fails.append('appgate: optional chaining on non-optional [Double] (compile error class native108-A1)')
    # every wait bound is locked individually (occurrence counts)
    for lit, want in [('await wait(30)', 1), ('await wait(20)', 1), ('await wait(10)', 1),
                      ('await wait(5)', 1), ('await wait(2)', 3)]:
        if appgate.count(lit) != want:
            fails.append('appgate: wait bound shifted: %s count=%d want=%d' % (lit, appgate.count(lit), want))
    # direct exit only: the normal quit watchdog _exit(70)s and masks the verdict
    if 'NSApp.terminate(nil)' in appgate:
        fails.append('appgate: graceful terminate reintroduced (quit watchdog masks the gate verdict)')
    return fails


def main():
    fails = check(MAIN, APPGATE, DELEGATE)
    for name, args in [
        ('install dropped', (MAIN.replace(INSTALL, '// mutant', 1), APPGATE, DELEGATE)),
        ('route check dropped', (MAIN, APPGATE.replace('engine == "gorav"', 'true', 1), DELEGATE)),
        ('seek condition relaxed', (MAIN, APPGATE.replace('time >= 8 && anchor >= 7.5', 'time >= 4', 1), DELEGATE)),
        ('seam widened', (MAIN, APPGATE, DELEGATE.replace(PRIVATE_HOST, 'var goravHost: GorAVPlayerHost?', 1))),
        ('route timeout shortened', (MAIN, APPGATE.replace('await wait(30)', 'await wait(5)', 1), DELEGATE)),
        ('install-time D0 dropped', (MAIN, APPGATE.replace('g.note("D0.scope"', 'g.note("D0.dropped"', 1), DELEGATE)),
        ('graceful terminate reintroduced', (MAIN, APPGATE + '\nNSApp.terminate(nil)\n', DELEGATE)),
        ('saved-fd bypass dropped', (MAIN, APPGATE.replace('FileHandle(fileDescriptor: gDStageOutFD, closeOnDealloc: false)', 'FileHandle.standardOutput'), DELEGATE)),
        ('dup moved after D0', (MAIN, APPGATE.replace('gDStageOutFD = dup(STDOUT_FILENO)\n', '', 1), DELEGATE)),
        ('anchor witness dropped', (MAIN, APPGATE.replace('D4.anchor-witness', 'D4.dropped', 1), DELEGATE)),
        ('resume witness dropped', (MAIN, APPGATE.replace('isPaused == false', 'true'), DELEGATE)),
        ('resumed conjunct dropped', (MAIN, APPGATE.replace('resumed && t0 != nil', 't0 != nil', 1), DELEGATE)),
        ('anchor wait zeroed', (MAIN, APPGATE.replace('await wait(5)', 'await wait(0)', 1), DELEGATE)),
        ('anchor witness made verdict', (MAIN, APPGATE.replace('note("D4.anchor-witness"', 'line("D4.anchor-witness", true', 1), DELEGATE)),
        ('resume wait widened', (MAIN, APPGATE.replace('await wait(2)', 'await wait(10)', 1), DELEGATE)),
        ('optional chaining reintroduced', (MAIN, APPGATE.replace('!s.audioFirstAdmissionWallSeconds.isEmpty', '!(s.audioFirstAdmissionWallSeconds?.isEmpty ?? true)', 1), DELEGATE)),
    ]:
        if not check(*args):
            fails.append('mutant undetected: ' + name)
    if fails:
        for f in fails:
            print('FAIL:', f)
        raise SystemExit(1)
    print('PASS: D-stage app gate drives the normal AppDelegate path; C gate + gor path unchanged, C3-parity bounds')


if __name__ == '__main__':
    main()
