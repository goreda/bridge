#!/usr/bin/env python3
"""native94 (product overlay) coordinated-seek watermark regression.

Source-contract assertions on the local overlay in
Packages/gorav/Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift:
the coordinated seek (performSeek, used by the embedded session via
tryBegin) must reset the delivery watermark (l3LastDeliveredPTS) and the
fallback preroll mark (l3DiscardBeforePTS) in its readyWon branch, with
legacy-seek parity (:2221). The resets must be UNCONDITIONAL in that
branch: backward seeks decode from a pre-target keyframe and forward
seeks can still emit preroll below the pre-seek watermark when the pump
had pulled ahead of the presentation position, so direction gating
would reintroduce the fault on one side. A coordinated BACKWARD-flag seek decodes from
the pre-target keyframe; the pump's seekLandingTarget contract
(PlaybackCore.swift, RULES.md:69) discards pre-target frames, so those
preroll pts are legitimate. With the pre-seek watermark kept, the first
post-seek frame pts-regresses against it and trips the -24 presentation
order fault (the native93 B2 paused-seek failure "pump:-24"). The -24
guard itself must stay unchanged.

STRENGTH LABEL: text-contract, not behavioral. Runs on Linux
(text-only); includes mutants (each reset line removed - the -24 fault
then stays armed at the pre-target keyframe below the old watermark)
that MUST be detected. It does NOT decode frames; the behavioral
backward/forward preroll proof is the native94 macOS run.

NOT_RUN here (explicit, no inferred acceptance):
  - A coordinated backward seek on a real decoder: macOS venue with the
    FFmpeg build only; native94 is the verifier.
  - swift seek/pause test targets: no Swift toolchain in this workspace.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # archive/gor
DECODER = (ROOT / 'Packages/gorav/Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift').read_text()

RESET_WM = 'l3LastDeliveredPTS = nil'
RESET_PR = 'l3DiscardBeforePTS = nil'
EPOCH_BUMP = 'l3PresentationEpoch &+= 1'
GUARD_NEEDLE = 'presentation order fault: pts regression'


def branch_of(src, start_anchor, end_anchor):
    if start_anchor not in src or end_anchor not in src:
        return None
    return src[src.index(start_anchor):src.index(end_anchor)]


def check(src):
    fails = []
    branch = branch_of(src, 'if readyWon {', 'deregisterDecoderOnQueue(); terminated = true')
    if branch is None:
        return ['performSeek readyWon branch anchors missing']
    for needle in [RESET_WM, RESET_PR, EPOCH_BUMP]:
        if needle not in branch:
            fails.append('readyWon branch missing ' + needle)
    # direction-agnostic coverage: no conditional may gate the resets
    # (a direction-gated reset would reintroduce -24 on the other side)
    lines = branch.split(EPOCH_BUMP)[0].split('\n')[1:]  # drop the 'if readyWon {' anchor line itself
    code = [l for l in lines if l.strip() and not l.strip().startswith('//')]
    head = '\n'.join(code)
    if 'if ' in head or 'guard ' in head or '?' in head:
        fails.append('readyWon resets are conditionally gated; must be unconditional (backward AND forward preroll)')
    if not fails:
        # resets must land no later than the epoch bump (all on nativeQueue;
        # order pins intent and legacy parity, :2216-2223)
        if not (branch.index(RESET_WM) < branch.index(EPOCH_BUMP)
                and branch.index(RESET_PR) < branch.index(EPOCH_BUMP)):
            fails.append('readyWon resets must precede the epoch bump (legacy parity)')
    # the -24 regression guard must remain, unmodified
    if GUARD_NEEDLE not in src:
        fails.append('-24 pts-regression guard missing or reworded')
    if src.count(RESET_WM) < 3 or src.count(RESET_PR) < 3:
        fails.append('expected resets at open/legacy-seek/coordinated-seek sites')
    return fails


def main():
    fails = check(DECODER)
    # mutants: dropping either reset from the coordinated branch must be caught
    for needle, name in [(RESET_WM, 'watermark-reset-dropped'), (RESET_PR, 'preroll-reset-dropped')]:
        branch = branch_of(DECODER, 'if readyWon {', 'deregisterDecoderOnQueue(); terminated = true')
        mutant_branch = branch.replace(needle, '// mutant: ' + name, 1)
        mutant = DECODER.replace(branch, mutant_branch)
        if not check(mutant):
            fails.append('mutant undetected: ' + name)
    if fails:
        for f in fails:
            print('FAIL:', f)
        raise SystemExit(1)
    print('PASS: coordinated seek resets delivery watermark + preroll mark; -24 guard intact')


if __name__ == '__main__':
    main()
