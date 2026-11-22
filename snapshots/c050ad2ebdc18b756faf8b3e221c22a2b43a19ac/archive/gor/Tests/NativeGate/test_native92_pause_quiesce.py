#!/usr/bin/env python3
"""native92 (qualifier: product overlay) pause-quiesce wiring regression.

Source-contract assertions on the local overlay in
Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift:
setPaused must quiesce the sink (audio.pauseAudio) BEFORE any pause state
moves (plane .pause, pump.pause), and un-quiesce (audio.resumeAudio, which
re-anchors a new clock generation) BEFORE pump.resume restarts PCM - the
ShellFrameSource macro pause precedent and the AudioUnitSink M1 counter
contract (ring HELD, intentional silence on its own counter, folded into the
pacing receipt on resume before the cell clears). A typed-false quiesce or a
nil sink must REFUSE the whole transition typed (throw; no state moves) -
never a frozen picture over an un-quiesced sink. Runs on Linux (text-only);
includes order-swap / silent-false mutants that MUST be detected.

NOT_RUN here (explicit, no inferred acceptance):
  - swift pause-resume-tests (M1 FramePump contract target): Linux-capable
    upstream, but this workspace has no Swift toolchain.
  - Runtime sink-quiesce counter advance under a real AudioUnit pause:
    macOS venue only; native92 is the verifier.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # archive/gor
SESSION = (ROOT / 'Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift').read_text()
SINK = (ROOT / 'Packages/gorav/Sources/GorAVMacShell/AudioUnitSink.swift').read_text()

PAUSE_THROW = 'throw EmbeddedRefusal.illegalState("pauseAudioQuiesceRefused")'
RESUME_THROW = 'throw EmbeddedRefusal.illegalState("resumeAudioQuiesceRefused")'


def check_session(src):
    fails = []
    # native111: the idempotent exits are now traced (traceControl before
    # return); the guard text itself is the stable anchor.
    pause_anchor = 'guard plane.state == .playing else {'
    resume_anchor = 'guard plane.state == .paused else {'
    if pause_anchor not in src:
        return ['pause branch anchor missing']
    if resume_anchor not in src:
        return ['resume branch anchor missing']
    pause_leg = src[src.index(pause_anchor):src.index(resume_anchor)]
    for needle in ['audio.pauseAudio()', 'applyOrReport(.pause)', 'await pump.pause()', PAUSE_THROW]:
        if needle not in pause_leg:
            fails.append('pause leg missing ' + needle)
    if not fails:
        if not (pause_leg.index('audio.pauseAudio()') < pause_leg.index('applyOrReport(.pause)')
                < pause_leg.index('await pump.pause()')):
            fails.append('pause leg order: quiesce < plane pause < pump.pause violated')
        if 'guard let audio, audio.pauseAudio() else' not in pause_leg:
            fails.append('pause leg quiesce refusal is not an atomic guard-let throw')
    resume_leg = src[src.index(resume_anchor):src.index('public func togglePause')]
    for needle in ['audio.resumeAudio()', 'applyOrReport(.resume)', 'await pump.resume()', RESUME_THROW]:
        if needle not in resume_leg:
            fails.append('resume leg missing ' + needle)
    if not fails:
        if not (resume_leg.index('audio.resumeAudio()') < resume_leg.index('applyOrReport(.resume)')
                < resume_leg.index('await pump.resume()')):
            fails.append('resume leg order: un-quiesce < plane resume < pump.resume violated')
        if 'guard let audio, audio.resumeAudio() else' not in resume_leg:
            fails.append('resume leg quiesce refusal is not an atomic guard-let throw')
    if 's.audioIntentionalSilenceFrames = audio.pausedSilenceFrames' not in src:
        fails.append('snapshot silence counter sourcing missing')
    # native111: the silent exits and both refusal throws are traced.
    for needle in ['traceControl("pauseIgnored state=', 'traceControl("resumeIgnored state=',
                   'traceControl("pauseAudioRefused state=', 'traceControl("resumeAudioRefused state=',
                   'traceControl("toggle state=']:
        if needle not in src:
            fails.append('native111 control trace missing ' + needle)
    return fails


def check_sink(src):
    fails = []
    if 'if pausedFlag?.load() != 0 {\n            memset(dst, 0, n)\n            pausedSilenceRT?.fetchAdd(UInt64(wholeFrames))' not in src:
        fails.append('render quiesce branch (silence counted under pausedFlag) missing')
    pa = src[src.index('public func pauseAudio()'):src.index('public func resumeAudio()')]
    ra = src[src.index('public func resumeAudio()'):src.index('public func samplePacingAnchor')]
    if 'pausedFlag?.store(1)' not in pa:
        fails.append('pauseAudio does not set the quiesce flag')
    if 'p.notePausedSilence(pausedSilenceRT?.load() ?? 0)' not in ra:
        fails.append('resumeAudio does not fold the silence receipt')
    if not fails and not (ra.index('p.notePausedSilence') < ra.index('pausedSilenceRT?.store(0)')
                          < ra.index('pausedFlag?.store(0)')):
        fails.append('resumeAudio order: fold < counter clear < flag clear violated')
    return fails


fails = check_session(SESSION) + check_sink(SINK)
assert not fails, fails

# Mutants MUST be detected (silent-false / order-swap / dropped-fold).
# native111: the refusal block carries a traceControl before the throw;
# the mutant targets the guard-let line alone so it stays surgical.
bad = SESSION.replace('guard let audio, audio.pauseAudio() else {',
                      '_ = audio?.pauseAudio()\n            if false {')
assert check_session(bad), 'silent-false mutant (discarded Bool) not detected'
bad = SESSION.replace('throw EmbeddedRefusal.illegalState("pauseAudioQuiesceRefused")', '()')
assert check_session(bad), 'silent-false mutant (dropped typed throw) not detected'
bad = SESSION.replace('applyOrReport(.pause)', 'await pump.pause()\n            applyOrReport(.pause)', 1)
assert check_session(bad), 'order-swap mutant (pump.pause before quiesce) not detected'
bad = SINK.replace('p.notePausedSilence(pausedSilenceRT?.load() ?? 0)\n        pausedSilenceRT?.store(0)',
                   'pausedSilenceRT?.store(0)')
assert check_sink(bad), 'dropped-fold mutant not detected'

print('PASS native92 pause-quiesce wiring: pause quiesce<plane<pump + atomic typed refusal, '
      'resume un-quiesce(re-anchor)<plane<pump, sink counter contract anchors, 3 mutants detected')
print('NOT_RUN swift pause-resume-tests (M1 FramePump contract): no Swift toolchain in this workspace')
print('NOT_RUN runtime sink-quiesce counter advance: macOS AudioUnit venue only; native92 verifies')
