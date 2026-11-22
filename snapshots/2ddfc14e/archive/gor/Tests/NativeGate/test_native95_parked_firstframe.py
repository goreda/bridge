#!/usr/bin/env python3
"""native95 (product overlay) parked-seek first-frame watch regression.

Source-contract assertions on the local overlay in
Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift: after
a PARKED coordinated seek (wasPausedAtSeek) the .committedAndReset +
audioOutcome == .nativeReady return branch must re-arm
startFirstFrameWatch() when pump.currentPaceAnchor is still nil. The
RULES.md:69 render-order gate is vacuous while paused (SeekComposition
parkedVideo skips the frame0 wait), frame0 presents only after resume, and
the contract there ("the resume path's first-frame watch delivers
acceptFirstFrame there") is otherwise unmet: the open-path watch (:483/
:751) is cancelled at seek commit and the resume leg arms none, so
.firstFrame never fires for the post-seek generation (native94 B2 parked
seek: no .firstFrame within 10s). The generation guard in acceptFirstFrame
and tracker.firstFrame's one-per-generation must stay untouched. Runs on
Linux (text-only); includes a drop-the-re-arm mutant that MUST be detected.

STRENGTH LABEL: text-contract, not behavioral. It does NOT run a pump or
present frames; the behavioral proof (paused seek + resume emits
.firstFrame at the landing anchor) is the native95 macOS run.

NOT_RUN here (explicit, no inferred acceptance):
  - A parked seek against a real decoder/sink: macOS venue only.
  - swift test targets: no Swift toolchain in this workspace.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # archive/gor
SESSION = (ROOT / 'Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift').read_text()

REARM = 'startFirstFrameWatch()'
GUARD = 'tracker.firstFrame(anchor: anchor, clockNow: trackerClockNow(), generation: generation)'


def branch_of(src, start_anchor, end_anchor):
    if start_anchor not in src or end_anchor not in src:
        return None
    return src[src.index(start_anchor):src.index(end_anchor)]


def check(src):
    fails = []
    branch = branch_of(src, 'if audioOutcome == .nativeReady {', 'Audio muted/closed typed')
    if branch is None:
        return ['committedAndReset nativeReady branch anchors missing']
    if 'acceptFirstFrame(anchor: anchor, generation: tracker.generation)' not in branch:
        fails.append('immediate anchor accept missing from nativeReady branch')
    if REARM not in branch:
        fails.append('nativeReady branch missing parked-seek watch re-arm')
    else:
        # the re-arm must be the parked+anchor-nil else of the immediate accept
        if 'else if wasPausedAtSeek' not in branch:
            fails.append('re-arm is not gated on wasPausedAtSeek (must not re-arm non-parked seeks)')
        accept = branch.index('acceptFirstFrame(anchor: anchor, generation: tracker.generation)')
        if not branch.index(REARM) > accept:
            fails.append('re-arm must follow the immediate accept (anchor-nil fallback)')
    # generation guard and one-shot semantics untouched
    if GUARD not in src:
        fails.append('acceptFirstFrame generation guard changed or missing')
    if 'let watchGeneration = tracker.generation' not in src:
        fails.append('startFirstFrameWatch generation capture missing')
    if src.count(REARM) < 3:
        fails.append('expected watch arming at both open paths plus the parked-seek re-arm')
    return fails


def main():
    fails = check(SESSION)
    branch = branch_of(SESSION, 'if audioOutcome == .nativeReady {', 'Audio muted/closed typed')
    mutant = SESSION.replace(branch, branch.replace(REARM, '// mutant: re-arm dropped', 1))
    if not check(mutant):
        fails.append('mutant undetected: re-arm dropped')
    if fails:
        for f in fails:
            print('FAIL:', f)
        raise SystemExit(1)
    print('PASS: parked seek re-arms the first-frame watch; generation guard intact')


if __name__ == '__main__':
    main()
