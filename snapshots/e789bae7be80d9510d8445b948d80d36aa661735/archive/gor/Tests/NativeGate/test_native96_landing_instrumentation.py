#!/usr/bin/env python3
"""native96 (instrumentation-only overlay) seek-landing observability.

Source-contract assertions, NO behavior change: (1) PlaybackCore counts
preSeekLanding discards on a dedicated live counter
(liveSeekLandingDrops) at the existing discard site; (2)
GorAVEmbeddedSession surfaces it as EmbeddedSnapshot.seekLandingDrops
(live from the running pump, honest nil otherwise) and stamps seekTrace
tokens with the master clock; (3) the C gate samples
presented/seekLandingDrops/anchor/timePos every ~2s during the
resume-landing wait while the 10s bound and the pass condition stay
UNCHANGED. Purpose: the next parked-seek run must distinguish decode
catch-up progressing (drops growing) from a presentation stall (flat).
Runs on Linux (text-only); mutants (drop the increment, drop the
snapshot fill, drop the sampling) MUST be detected.

STRENGTH LABEL: text-contract, not behavioral. It does not run a pump;
the behavioral evidence is the next native macOS run's C3 sample lines.

NOT_RUN here (explicit, no inferred acceptance):
  - Any decoder/pump execution: macOS venue only.
  - swift test targets: no Swift toolchain in this workspace.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # archive/gor
PUMP = (ROOT / 'Packages/gorav/Sources/GorAVPlaybackCore/PlaybackCore.swift').read_text()
SESSION = (ROOT / 'Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift').read_text()
GATE = (ROOT / 'Sources/gor/Engine/GorAVNativeGate.swift').read_text()

DECL = 'public private(set) var liveSeekLandingDrops = 0'
INC = 'liveSeekLandingDrops += 1'
SNAP_FIELD = 'public var seekLandingDrops: Int?'
SNAP_FILL = 's.seekLandingDrops = await pump.liveSeekLandingDrops'
TRACE_TS = 't=\\(String(format: "%.3f", trackerClockNow()))'
SAMPLE = 'C3.resume-landing-sample'
LASTPTS_DECL = 'public private(set) var liveSeekLandingLastDropPTS: Double? = nil'
LASTPTS_SET = 'liveSeekLandingLastDropPTS = frame.ptsSeconds'
LASTPTS_SNAP = 'public var seekLandingLastDropPTS: Double?'
LASTPTS_FILL = 's.seekLandingLastDropPTS = await pump.liveSeekLandingLastDropPTS'
SEEKTRACE_DUMP = 'C3.resume-landing-seekTrace'
# native100 (goreda T2 blind spot): refused landing shows + unbounded
# decoded-pts reach
FENCED_DECL = 'public private(set) var liveSeekLandingFencedShows = 0'
ADMITNIL_DECL = 'public private(set) var liveSeekLandingFencedAdmitNil = 0'
SINKFALSE_DECL = 'public private(set) var liveSeekLandingFencedSinkFalse = 0'
LASTDEC_DECL = 'public private(set) var liveSeekLandingLastDecodedPTS: Double? = nil'
MAXDEC_DECL = 'public private(set) var liveSeekLandingMaxDecodedPTS: Double? = nil'
FENCED_SNAP = 'public var seekLandingFencedShows: Int?'
ADMITNIL_SNAP = 'public var seekLandingFencedAdmitNil: Int?'
SINKFALSE_SNAP = 'public var seekLandingFencedSinkFalse: Int?'
LASTDEC_SNAP = 'public var seekLandingLastDecodedPTS: Double?'
MAXDEC_SNAP = 'public var seekLandingMaxDecodedPTS: Double?'
FENCED_FILL = 's.seekLandingFencedShows = await pump.liveSeekLandingFencedShows'
ADMITNIL_FILL = 's.seekLandingFencedAdmitNil = await pump.liveSeekLandingFencedAdmitNil'
SINKFALSE_FILL = 's.seekLandingFencedSinkFalse = await pump.liveSeekLandingFencedSinkFalse'
LASTDEC_FILL = 's.seekLandingLastDecodedPTS = await pump.liveSeekLandingLastDecodedPTS'
MAXDEC_FILL = 's.seekLandingMaxDecodedPTS = await pump.liveSeekLandingMaxDecodedPTS'
FENCED_INC = 'liveSeekLandingFencedShows += 1'
ADMITNIL_INC = 'liveSeekLandingFencedAdmitNil += 1'
SINKFALSE_INC = 'liveSeekLandingFencedSinkFalse += 1'
LASTDEC_SET = 'liveSeekLandingLastDecodedPTS = frame.ptsSeconds'
FAILOBS = 'C3.resume-landing-failobs'


def check(pump, session, gate):
    fails = []
    if DECL not in pump:
        fails.append('pump: liveSeekLandingDrops declaration missing')
    if INC not in pump:
        fails.append('pump: preSeekLanding increment missing')
    else:
        # the increment must be inside the preSeekLanding discard branch
        site = pump.index('note: "preSeekLanding"')
        branch = pump[pump.rindex('if paceAnchorPts == nil', 0, site):site]
        if INC not in branch:
            fails.append('pump: increment is not in the preSeekLanding branch')
    if SNAP_FIELD not in session:
        fails.append('session: snapshot seekLandingDrops field missing')
    if SNAP_FILL not in session:
        fails.append('session: snapshot live fill missing')
    if TRACE_TS not in session:
        fails.append('session: seekTrace master-clock stamp missing')
    # native99: last-dropped-pts surface (separates catch-up vs re-decode
    # loop vs predicate mismatch) + C failure-path seekTrace dump
    if LASTPTS_DECL not in pump:
        fails.append('pump: liveSeekLandingLastDropPTS declaration missing')
    if LASTPTS_SET not in pump:
        fails.append('pump: lastDropPTS set missing')
    else:
        site = pump.index('note: "preSeekLanding"')
        branch = pump[pump.rindex('if paceAnchorPts == nil', 0, site):site]
        if LASTPTS_SET not in branch:
            fails.append('pump: lastDropPTS set is not in the preSeekLanding branch')
    if LASTPTS_SNAP not in session:
        fails.append('session: snapshot seekLandingLastDropPTS field missing')
    if LASTPTS_FILL not in session:
        fails.append('session: snapshot lastDropPTS fill missing')
    if SAMPLE not in gate:
        fails.append('gate: resume-landing sampling missing')
    else:
        # the 10s bound and the pass condition must be unchanged
        if 'systemUptime + 10' not in gate:
            fails.append('gate: 10s resume-landing bound changed')
        if 'time >= 8 && anchor >= 7.5' not in gate:
            fails.append('gate: resume-landing pass condition changed')
        if 'systemUptime + 2' not in gate:
            fails.append('gate: ~2s sample cadence missing')
        if 'lastDropPTS=' not in gate:
            fails.append('gate: sample line missing lastDropPTS')
        for f in ['fenced=', 'admitNil=', 'sinkFalse=', 'lastDecPTS=', 'maxDecPTS=']:
            if f not in gate:
                fails.append('gate: sample line missing ' + f)
        if SEEKTRACE_DUMP not in gate:
            fails.append('gate: failure-path seekTrace dump missing')
        if FAILOBS not in gate:
            fails.append('gate: failure-path landing-counters dump missing')
    # native100: refused landing shows + unbounded decoded-pts reach
    for name, needle in [('fenced decl', FENCED_DECL), ('admitNil decl', ADMITNIL_DECL),
                         ('sinkFalse decl', SINKFALSE_DECL), ('lastDec decl', LASTDEC_DECL),
                         ('maxDec decl', MAXDEC_DECL), ('fenced inc', FENCED_INC),
                         ('admitNil inc', ADMITNIL_INC), ('sinkFalse inc', SINKFALSE_INC),
                         ('lastDec set', LASTDEC_SET)]:
        if needle not in pump:
            fails.append('pump: ' + name + ' missing')
    if LASTDEC_SET in pump:
        # the decoded-pts set must sit BEFORE the preSeekLanding drop branch
        # (unbounded: >=target frames fence AFTER that branch continues)
        drop = pump.index('note: "preSeekLanding"')
        set_at = pump.index(LASTDEC_SET)
        if set_at > drop:
            fails.append('pump: lastDecPTS set is not before the preSeekLanding branch')
    if ADMITNIL_INC in pump:
        # the admit-nil split must sit at the typed-refusal fence, the
        # sink-false split at the refused shows
        admit = pump.index('note: commit.admissionExhausted')
        if ADMITNIL_INC not in pump[pump.rindex('} else {', 0, admit):admit]:
            fails.append('pump: admitNil split is not at the tryAdmit-nil fence')
    if pump.count(SINKFALSE_INC) != 2:
        fails.append('pump: sinkFalse split must cover both show paths (commit + non-commit)')
    for name, needle in [('fenced snap', FENCED_SNAP), ('admitNil snap', ADMITNIL_SNAP),
                         ('sinkFalse snap', SINKFALSE_SNAP), ('lastDec snap', LASTDEC_SNAP),
                         ('maxDec snap', MAXDEC_SNAP), ('fenced fill', FENCED_FILL),
                         ('admitNil fill', ADMITNIL_FILL), ('sinkFalse fill', SINKFALSE_FILL),
                         ('lastDec fill', LASTDEC_FILL), ('maxDec fill', MAXDEC_FILL)]:
        if needle not in session:
            fails.append('session: ' + name + ' missing')
    return fails


def main():
    fails = check(PUMP, SESSION, GATE)
    for name, args in [
        ('increment dropped', (PUMP.replace(INC, '// mutant', 1), SESSION, GATE)),
        ('snapshot fill dropped', (PUMP, SESSION.replace(SNAP_FILL, '// mutant', 1), GATE)),
        ('sampling dropped', (PUMP, SESSION, GATE.replace(SAMPLE, 'mutant', 1))),
        ('lastDropPTS set dropped', (PUMP.replace(LASTPTS_SET, '// mutant', 1), SESSION, GATE)),
        ('seekTrace dump dropped', (PUMP, SESSION, GATE.replace(SEEKTRACE_DUMP, 'mutant', 1))),
        ('fencedShow splits dropped', (PUMP.replace(FENCED_INC, '// mutant'), SESSION, GATE)),
        ('admitNil split dropped', (PUMP.replace(ADMITNIL_INC, '// mutant', 1), SESSION, GATE)),
        ('sinkFalse split halved', (PUMP.replace(SINKFALSE_INC, '// mutant', 1), SESSION, GATE)),
        ('lastDecPTS set dropped', (PUMP.replace(LASTDEC_SET, '// mutant', 1), SESSION, GATE)),
        ('fenced fill dropped', (PUMP, SESSION.replace(FENCED_FILL, '// mutant', 1), GATE)),
        ('failobs dump dropped', (PUMP, SESSION, GATE.replace(FAILOBS, 'mutant', 1))),
    ]:
        if not check(*args):
            fails.append('mutant undetected: ' + name)
    if fails:
        for f in fails:
            print('FAIL:', f)
        raise SystemExit(1)
    print('PASS: landing drop counter + fenced-show splits + decoded-pts reach + C sampling; 10s bound unchanged')


if __name__ == '__main__':
    main()
