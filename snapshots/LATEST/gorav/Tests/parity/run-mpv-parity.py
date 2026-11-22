#!/usr/bin/env python3
"""Per-class receipt parity harness: gorav-play vs mpv (lane L12, unit u9).

gdb L12 metric ruling (2026-11-01, relayed via coordination - peer-attributed,
unverified by us against an authenticated gdb record): ACCEPT ffprobe
-count_frames (stream.nb_read_frames) as the pinned corpus reference, with the
EXACT ffprobe+ffmpeg version/build pinned and re-measure on version drift.
REJECT same-oracle parity: an ffprobe-fed Linux gorav stub vs the ffprobe
reference is HARNESS ONLY, never a parity PASS. Real count parity needs THREE
counters: the independent ffprobe corpus reference, mpv's own pipeline
counter, and the REAL gorav's child-bound decoded counter. Count-only metric -
NOT pixel, timing or AV-sync parity. No mpv patch; no drawn-frame proxy
(L12-F1/F2: drawn is not decoded, and mpv has no decoded-frame property in any
checked upstream - v0.34.1..v0.39.0 + master).

Grounded receipt contracts (verified against goreda/gorav base
d4c9d43c5fec75dcc55015edc9c1aa82ca589fa3, Sources/gorav-play/GorAVPlay.swift):
- gorav-play prints telemetry on stdout: "gorav play telemetry:
  displayUploaded=N ..." and "gorav play controls: ... endReason=X"; errors go
  to stderr as "GORAV_PLAY_ERROR: ...". Exit codes: 0 clean, 1 playback/predicate
  failure, 2 usage error, 3 unsupported host. displayUploaded is an UPLOADED
  (drawn-side) count.
  CHILD-BOUND DECODED COUNTER (u9; contract verified byte-exact against
  canonical main 48310fa837b1034370c1b26b43a511f56f691ceb,
  Sources/gorav-play/GorAVPlay.swift sha256
  36e7d781a30114dd2a6b2bccc0e63395c9f2d11e7fd0f4005e0b2bd3b9594f1d):
  the default leg prints "gorav play decoded: leg=default
  childDecodedFrames=<UInt64> hbBound=1 runID=<id>" where the count is read
  back from the player's OWN per-run heartbeat file ($GORAV_HB_FILE, advanced
  by ShellFrameSource at the decoder's own emit points; child-side freshness
  guard mtime >= launch). The harness binds a run ONLY when: GORAV_HB_FILE is
  a unique per-run path (harness-set, mandatory); exactly one decoded line
  exists; leg=default (the --metal leg, runID '-', is EXCLUDED - parity runs
  the default leg only); hbBound=1; childDecodedFrames parses as UInt64; and
  the decoded line's runID equals the single same-process "gorav play
  integrity:" line's runID, AND both equal the EXPECTED per-run label the
  harness generated and exported as GORAV_RUN_ID for that invocation
  (ShellFrameSource falls back to the literal 'norunid' when unset, so mutual
  equality alone would bind vacuously; 'norunid' and '-' can never match a
  generated label). hbBound=0 (any hbNote), missing/duplicate/
  unparseable lines, runID mismatch, nonzero exit or timeout: the counter is
  NOT BOUND - decoded_frames=None, a typed NOT_RUN input, NEVER zero and
  never inherited from another run. Completion/failure semantics of the
  process are unchanged (a crash before telemetry is still FAIL, D3).
- mpv runs null-output decode (--vo=null --ao=null --untimed) as a PLAYBACK
  COMPLETION receipt only (exit code + no crash). mpv's own pipeline counter
  (candidate: raw-video byte count at fixed geometry/format - gdb brainstorm,
  UNVERIFIED) is absent until validated; absent counter = typed missing
  measurement, never zero.

Comparator v3 (count-only):
- stub mode (--gorav-mode=stub): stub-gorav's ffprobe-fed count vs the pinned
  ffprobe reference. Same oracle by construction: verdicts are HARNESS_PASS /
  HARNESS_FAIL, NEVER PASS. This validates harness plumbing only.
- real mode (--gorav-mode=real): requires ALL of reference, gorav child-bound
  decoded and mpv pipeline counters present and equal, plus both sides
  completed. Any absent counter is a typed NOT_RUN (missing measurement).
- completed: both sides finished without error (gorav rc=0, no
  GORAV_PLAY_ERROR, endReason present; mpv rc=0).

Reference gates (mandatory, fail-closed):
- corpus.reference must pin ffprobe_version + ffmpeg build line and each play
  class must pin reference_decoded_frames; absent -> typed NOT_RUN
  (reference unmeasured).
- the venue ffprobe is verified against the pinned version/build strings;
  mismatch -> typed NOT_RUN (reference drift - re-measure per ruling).
- the harness re-measures nb_read_frames live on the pin-verified clip with
  the pinned tool; divergence from the pinned reference on identical tool +
  bytes is a FAIL (deterministic-input anomaly), never a silent override.

Ops support: classes whose ops are exactly ["play"] are runnable. seek,
pause-resume and subtitle sidecar classes produce a typed NOT_RUN.

Missing inputs are NOT RUN, never PASS: absent corpus clip, reference pin,
gorav binary, mpv binary or ffprobe binary yields a typed NOT_RUN line.
Exit codes: 0 = at least one REAL PASS and no FAIL; 1 = at least one
FAIL/HARNESS_FAIL; 3 = ZERO REAL PASS - including harness-only runs
(HARNESS_PASS never lifts the exit code; automation must gate on the SUMMARY
pass= field, not the exit code); argparse usage errors exit 2. NOT_RUN never
counts as a run (D1).
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path

RUN_TIMEOUT_SECONDS = 120

GORAV_UNSUPPORTED_MARKER = 'unsupported on this host'

REFERENCE_PROBE_ARGS = ['-v', 'error', '-count_frames', '-select_streams', 'v:0',
                        '-show_entries', 'stream=nb_read_frames',
                        '-of', 'default=noprint_wrappers=1:nokey=1']

GORAV_DECODED_MISSING = ('gorav child-bound decoded counter absent: gorav-play '
                         'telemetry exposes displayUploaded (uploaded/drawn-side) only')
MPV_COUNTER_MISSING = ('mpv own-pipeline counter absent: raw-video byte-count route '
                       'unvalidated (gdb brainstorm; team 3 verification pending)')


def valid_pin(pin):
    return isinstance(pin, str) and len(pin) == 64 and \
        all(c in '0123456789abcdef' for c in pin)


def clip_pin_status(cls, clip):
    """Mandatory pin gate for a runnable class. Returns a NOT_RUN reason
    string, or None when the clip bytes match a well-formed pin."""
    pin = cls.get('clip_sha256')
    if pin is None:
        return 'missing clip pin (gate mandatory for runnable classes)'
    if not valid_pin(pin):
        return 'malformed pin %r' % (pin,)
    actual = hashlib.sha256(clip.read_bytes()).hexdigest()
    if actual != pin:
        return 'clip pin mismatch %s (have %s)' % (pin, actual)
    return None


def reference_gate(cls, reference_block):
    """Corpus reference gate: the ffprobe tool identity AND the per-class
    reference count must both be pinned before any comparison is evidence."""
    if not isinstance(reference_block, dict):
        return 'corpus reference block absent (measurement pending)'
    if not reference_block.get('ffprobe_version') or not reference_block.get('ffmpeg_build'):
        return 'ffprobe version/build unpinned (measurement pending)'
    ref = cls.get('reference_decoded_frames')
    if not isinstance(ref, int) or ref < 0:
        return 'reference_decoded_frames unpinned for class (measurement pending)'
    return None


def verify_reference_tool(pinned_version, pinned_build, version_output):
    """Exact-string tool verification. version_output is `ffprobe -version`
    stdout. Returns a typed drift reason, or None when both pinned lines are
    reproduced verbatim."""
    lines = [l.strip() for l in version_output.splitlines() if l.strip()]
    if not any(l == pinned_version.strip() for l in lines):
        return ('reference drift: pinned ffprobe version %r not reproduced by venue tool'
                % (pinned_version,))
    if not any(l == pinned_build.strip() for l in lines):
        return ('reference drift: pinned ffmpeg build %r not reproduced by venue tool'
                % (pinned_build,))
    return None


def parse_nb_read_frames(text):
    """Exactly one non-negative integer from the probe output, else None."""
    t = text.strip()
    if re.fullmatch(r'\d+', t):
        return int(t)
    return None


def measure_reference(ffprobe, clip):
    """Live re-measurement of the pinned reference on this venue's pinned
    tool. Returns (count, note); count None = tool failure (typed NOT_RUN)."""
    try:
        proc = subprocess.run([str(ffprobe)] + REFERENCE_PROBE_ARGS + [str(clip)],
                              capture_output=True, text=True, timeout=RUN_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        return None, 'ffprobe timeout after %ds' % RUN_TIMEOUT_SECONDS
    if proc.returncode != 0:
        return None, 'ffprobe rc=%s: %s' % (proc.returncode, proc.stderr.strip()[:200])
    count = parse_nb_read_frames(proc.stdout)
    if count is None:
        return None, 'ffprobe output unparsable: %r' % (proc.stdout.strip()[:200],)
    return count, 'ffprobe nb_read_frames measured live'


def probe_reference_tool(ffprobe):
    """Returns (version_output, reason)."""
    try:
        proc = subprocess.run([str(ffprobe), '-version'],
                              capture_output=True, text=True, timeout=30)
    except (subprocess.TimeoutExpired, OSError) as e:
        return None, 'ffprobe -version failed: %s' % e
    if proc.returncode != 0:
        return None, 'ffprobe -version rc=%s' % proc.returncode
    return proc.stdout, None


def compare(gorav, mpv, reference_frames, gorav_mode):
    """Comparator v3 (count-only). gorav_mode: 'real' or 'stub'.
    Returns (verdict, detail); verdicts PASS/FAIL/NOT_RUN in real mode,
    HARNESS_PASS/HARNESS_FAIL/NOT_RUN in stub mode (never parity)."""
    harness = (gorav_mode == 'stub')
    agree = 'HARNESS_PASS' if harness else 'PASS'
    disagree = 'HARNESS_FAIL' if harness else 'FAIL'
    # Order matters (D3): typed-UNRUNNABLE and completion classification
    # come before absent-metric handling.
    if gorav.get('completed') is None or mpv.get('completed') is None:
        return ('NOT_RUN', 'receipt typed unrunnable (e.g. unsupported host)')
    if not gorav['completed'] or not mpv['completed']:
        return (disagree, 'completion gorav=%s(%s,rc=%s) mpv=%s(rc=%s)'
                % (gorav['completed'], gorav.get('end_reason'), gorav.get('rc'),
                   mpv['completed'], mpv.get('rc')))
    gd = gorav.get('decoded_frames')
    if gd is None:
        return ('NOT_RUN', 'typed missing measurement: %s' % GORAV_DECODED_MISSING)
    if gd != reference_frames:
        return (disagree, 'count gorav=%s reference(ffprobe nb_read_frames)=%s%s'
                % (gd, reference_frames,
                   ' [SAME-ORACLE: harness only, not parity]' if harness else ''))
    if harness:
        # Same oracle by construction (stub is ffprobe-fed): plumbing check.
        return (agree, 'count=%s stub-gorav agrees with ffprobe reference '
                '[SAME-ORACLE: HARNESS ONLY, never parity]' % reference_frames)
    mp = mpv.get('pipeline_frames')
    if mp is None:
        return ('NOT_RUN', 'typed missing measurement: %s' % MPV_COUNTER_MISSING)
    if mp != reference_frames:
        return (disagree, 'count divergence: reference=%s gorav=%s mpv=%s'
                % (reference_frames, gd, mp))
    return ('PASS', 'count=%s all three counters agree (reference + gorav '
            'child-bound decoded + mpv pipeline); count-only, not '
            'pixel/timing/AV-sync parity' % reference_frames)


DECODED_LINE = 'gorav play decoded:'
INTEGRITY_LINE = 'gorav play integrity:'
UINT64_MAX = 18446744073709551615


def _kv_fields(payload):
    """Split 'k=v k=v ...' into a dict, or return None if ANY token is bare
    (no '=') - a malformed token is a typed unbound condition, never a crash."""
    fields = {}
    for tok in payload.strip().split():
        if '=' not in tok:
            return None
        k, v = tok.split('=', 1)
        fields[k] = v
    return fields


def parse_decoded_binding(stdout, rc, expected_run_id):
    """Child-bound decoded counter (contract cited in the module docstring).
    expected_run_id: the unique label the harness exported as GORAV_RUN_ID for
    THIS invocation - both printed runIDs must equal it exactly (mutual
    equality alone is vacuous under the child's 'norunid' fallback).
    Returns (count, note); count None = NOT BOUND (typed NOT_RUN input, never
    zero, never inherited). Every failure mode is explicit."""
    if rc != 0:
        return None, 'nonzero exit (%s): counter not bound' % rc
    dlines = [l for l in stdout.splitlines() if l.startswith(DECODED_LINE)]
    if len(dlines) != 1:
        return None, 'decoded line count %d (need exactly 1)' % len(dlines)
    ilines = [l for l in stdout.splitlines() if l.startswith(INTEGRITY_LINE)]
    if len(ilines) != 1:
        return None, 'integrity line count %d (need exactly 1)' % len(ilines)
    d = _kv_fields(dlines[0][len(DECODED_LINE):])
    if d is None:
        return None, 'decoded line malformed (bare token without =)'
    if d.get('leg') != 'default':
        return None, 'decoded leg %r is not the default parity leg (--metal excluded)' % d.get('leg')
    if d.get('hbBound') != '1':
        return None, 'hbBound=%s (%s)' % (d.get('hbBound'), d.get('hbNote', 'no hbNote'))
    raw = d.get('childDecodedFrames')
    if raw is None or not raw.isascii() or not raw.isdigit():
        # isdigit() alone accepts non-ASCII digits (superscripts, other
        # scripts) that int() then rejects - a crash, not a typed unbound.
        return None, 'childDecodedFrames missing or non-UInt64 %r' % raw
    if int(raw) > UINT64_MAX:
        return None, 'childDecodedFrames %s exceeds UInt64 max' % raw
    drunid = d.get('runID')
    i = _kv_fields(ilines[0][len(INTEGRITY_LINE):])
    if i is None:
        return None, 'integrity line malformed (bare token without =)'
    irunid = i.get('runID')
    if drunid != irunid:
        return None, 'runID mismatch decoded=%r integrity=%r' % (drunid, irunid)
    if not drunid or drunid in ('-', 'norunid'):
        return None, 'runID %r is a fallback/excluded label, never a binding' % (drunid,)
    if drunid != expected_run_id:
        return None, 'runID %r is not this invocation expected label %r' % (drunid, expected_run_id)
    return int(raw), 'child-bound decoded via unique per-run heartbeat path + expected run label'


def parse_gorav_receipt(stdout, stderr, rc, gorav_mode, expected_run_id=None):
    """Parses gorav-play stdout/stderr per the grounded contract above.
    decoded_frames: in stub mode the stub's count IS its ffprobe-fed count
    (same-oracle, labelled downstream); in real mode the child-bound decoded
    counter is taken from the decoded/integrity line binding, or None with a
    typed reason when any binding condition fails."""
    if GORAV_UNSUPPORTED_MARKER in stdout or GORAV_UNSUPPORTED_MARKER in stderr:
        return {'decoded_frames': None, 'uploaded_frames': None,
                'completed': None, 'rc': rc}, \
            'gorav-play unsupported on this host (requires macOS)'
    m = re.search(r'displayUploaded=(\d+)', stdout)
    e = re.search(r'endReason=(\S+)', stdout)
    error = 'GORAV_PLAY_ERROR' in stderr or 'GORAV_PLAY_ERROR' in stdout
    uploaded = int(m.group(1)) if m else None
    if gorav_mode == 'stub':
        decoded = uploaded
        note = 'stub decoded = ffprobe-fed count (same-oracle)'
    else:
        decoded, note = parse_decoded_binding(stdout, rc, expected_run_id)
    receipt = {
        'decoded_frames': decoded,
        'uploaded_frames': uploaded,
        'completed': (rc == 0 and not error and e is not None),
        'end_reason': e.group(1) if e else None,
        'rc': rc,
    }
    return receipt, 'gorav receipt parsed from stdout telemetry (mode=%s); %s' % (gorav_mode, note)


def run_gorav(binary, clip, hold_seconds, gorav_mode):
    env = None
    hb_path = None
    run_id = None
    if gorav_mode == 'real':
        # Mandatory unique per-run heartbeat path (freshness primary binding;
        # the child's mtime>=launch guard is the secondary) AND a unique
        # expected run label (the decoded/integrity runID cross-check is only
        # meaningful against a label this invocation generated - the child's
        # 'norunid' fallback must never bind). The path must NOT pre-exist
        # with content: the child creates/writes it this run.
        run_id = 'l12-%s-%s' % (os.getpid(), uuid.uuid4().hex[:12])
        fd, hb_path = tempfile.mkstemp(prefix='gorav-hb-', suffix='.txt')
        os.close(fd)
        os.unlink(hb_path)
        env = dict(os.environ, GORAV_HB_FILE=hb_path, GORAV_RUN_ID=run_id)
    try:
        proc = subprocess.run([str(binary), str(clip), str(hold_seconds)],
                              capture_output=True, text=True, timeout=RUN_TIMEOUT_SECONDS,
                              env=env)
    except subprocess.TimeoutExpired:
        return {'decoded_frames': None, 'uploaded_frames': None, 'completed': False,
                'end_reason': None, 'rc': 'timeout'}, \
            'gorav timeout after %ds (counter not bound)' % RUN_TIMEOUT_SECONDS
    finally:
        if hb_path is not None:
            try:
                os.unlink(hb_path)
            except OSError:
                pass
    return parse_gorav_receipt(proc.stdout, proc.stderr, proc.returncode, gorav_mode,
                               expected_run_id=run_id)


def run_mpv(binary, clip):
    """mpv as a PLAYBACK COMPLETION receipt only: null-output decode to
    end-of-file, terminal state from the real exit code. No frame metric is
    taken from mpv until an own-pipeline counter route is validated."""
    try:
        proc = subprocess.run([str(binary), '--vo=null', '--ao=null', '--untimed', str(clip)],
                              capture_output=True, text=True, timeout=RUN_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        return {'pipeline_frames': None, 'completed': False,
                'rc': 'timeout'}, 'mpv timeout after %ds' % RUN_TIMEOUT_SECONDS
    receipt = {'pipeline_frames': None, 'completed': proc.returncode == 0,
               'rc': proc.returncode}
    return receipt, 'mpv completion receipt from exit code (no frame counter qualified)'


def self_test():
    """Comparator + gates + receipt parsers without gorav, mpv or ffprobe."""
    ok = []
    ref_block = {'ffprobe_version': 'ffprobe version 4.4.2-0ubuntu0.22.04.1',
                 'ffmpeg_build': 'built with gcc 11 (Ubuntu 11.2.0-19ubuntu1)'}
    cls_ready = {'id': 't', 'clip_sha256': '0' * 64, 'reference_decoded_frames': 75}
    # Reference gate (fail-closed)
    ok.append(('reference gate open when fully pinned',
               reference_gate(cls_ready, ref_block) is None))
    ok.append(('reference gate: missing class count -> NOT_RUN',
               reference_gate({'id': 't', 'clip_sha256': '0' * 64}, ref_block) is not None))
    ok.append(('reference gate: unpinned tool -> NOT_RUN',
               reference_gate(cls_ready, {'ffprobe_version': None, 'ffmpeg_build': None}) is not None))
    ok.append(('reference gate: absent block -> NOT_RUN',
               reference_gate(cls_ready, None) is not None))
    # Tool verification (exact strings)
    out = (ref_block['ffprobe_version'] + '\nCopyright (c) 2007-2021\n'
           + ref_block['ffmpeg_build'] + '\nconfiguration: --enable-x\n')
    ok.append(('tool verify: pinned lines reproduced -> open',
               verify_reference_tool(ref_block['ffprobe_version'], ref_block['ffmpeg_build'], out) is None))
    ok.append(('tool verify: version drift -> typed reason',
               verify_reference_tool('ffprobe version 9.9', ref_block['ffmpeg_build'], out) is not None))
    ok.append(('tool verify: build drift -> typed reason',
               verify_reference_tool(ref_block['ffprobe_version'], 'built with clang', out) is not None))
    # Probe output parsing
    ok.append(('nb_read_frames parse: "75" -> 75', parse_nb_read_frames('75\n') == 75))
    ok.append(('nb_read_frames parse: garbage -> None', parse_nb_read_frames('N/A\n') is None))
    # Comparator v3
    g = {'decoded_frames': 75, 'uploaded_frames': 75, 'completed': True,
         'end_reason': 'endOfStream', 'rc': 0}
    m = {'pipeline_frames': 75, 'completed': True, 'rc': 0}
    ok.append(('real: all three counters agree -> PASS',
               compare(g, m, 75, 'real')[0] == 'PASS'))
    ok.append(('real: gorav decoded absent -> NOT_RUN typed missing',
               compare(dict(g, decoded_frames=None), m, 75, 'real')[0] == 'NOT_RUN'))
    ok.append(('real: mpv pipeline absent -> NOT_RUN typed missing',
               compare(g, dict(m, pipeline_frames=None), 75, 'real')[0] == 'NOT_RUN'))
    ok.append(('real: divergence -> FAIL lists three counters',
               compare(g, dict(m, pipeline_frames=74), 75, 'real')[0] == 'FAIL'))
    ok.append(('stub: agreement -> HARNESS_PASS (never PASS)',
               compare(g, dict(m, pipeline_frames=None), 75, 'stub')[0] == 'HARNESS_PASS'))
    ok.append(('stub: divergence -> HARNESS_FAIL',
               compare(dict(g, decoded_frames=73), m, 74, 'stub')[0] == 'HARNESS_FAIL'))
    ok.append(('stub: mpv pipeline absence does not block harness check',
               compare(g, {'pipeline_frames': None, 'completed': True, 'rc': 0}, 75, 'stub')[0] == 'HARNESS_PASS'))
    ok.append(('stub: completion failure -> HARNESS_FAIL (not plain FAIL)',
               compare(g, dict(m, completed=False, rc=1), 75, 'stub')[0] == 'HARNESS_FAIL'))
    ok.append(('mpv incomplete -> FAIL',
               compare(g, dict(m, completed=False, rc=1), 75, 'real')[0] == 'FAIL'))
    ok.append(('gorav incomplete -> FAIL',
               compare(dict(g, completed=False, rc=1, end_reason='decodeFailed'), m, 75, 'real')[0] == 'FAIL'))
    ok.append(('unrunnable receipt -> NOT_RUN (D3)',
               compare({'decoded_frames': None, 'completed': None, 'rc': 3}, m, 75, 'real')[0] == 'NOT_RUN'))
    # gorav receipt parsing
    sample_out = ('gorav play: windowOnScreen=1\n'
                  'gorav play telemetry: displayUploaded=250 displayNoPixel=0 audioCallbackRealBytes=100\n'
                  'gorav play controls: pauses=0 resumes=0 pausedWallSeconds=0.0 pauseOutcome=none '
                  'resumeOutcome=none pausedSilenceFrames=0 clockSource=audio closedByUser=0 endReason=endOfStream\n')
    r, _ = parse_gorav_receipt(sample_out, '', 0, 'real', expected_run_id='run-7f')
    ok.append(('real-mode gorav: uploaded parsed, decoded typed absent',
               r['uploaded_frames'] == 250 and r['decoded_frames'] is None and r['completed'] is True))
    r2, note2 = parse_gorav_receipt(
        'gorav-play: real display/audio sinks require macOS (AppKit/CoreAudio); unsupported on this host\n', '', 3, 'real')
    ok.append(('gorav unsupported host -> typed NOT_RUN',
               r2['completed'] is None and 'unsupported on this host' in note2))
    r3, _ = parse_gorav_receipt('', 'GORAV_PLAY_ERROR: boom\n', 1, 'real')
    ok.append(('gorav error -> not completed', r3['completed'] is False))
    rs, _ = parse_gorav_receipt(sample_out, '', 0, 'stub')
    ok.append(('stub-mode gorav: fed count treated as stub decoded',
               rs['decoded_frames'] == 250 and rs['completed'] is True))
    # Child-bound decoded counter (u9): positive + negative fixtures for the
    # decoded/integrity line binding (contract pinned in module docstring).
    bound_out = (sample_out.replace(
        'gorav play controls:',
        'gorav play integrity: ledgerAllowsSuccess=1 ledgerWriteOK=1 admissionBound=1 audioFailedStops=0 runID=run-7f\n'
        'gorav play controls:')
        + 'gorav play decoded: leg=default childDecodedFrames=75 hbBound=1 runID=run-7f\n')
    rb, nb = parse_gorav_receipt(bound_out, '', 0, 'real', expected_run_id='run-7f')
    ok.append(('real: bound decoded line + matching integrity runID -> 75',
               rb['decoded_frames'] == 75 and rb['completed'] is True))
    hb0 = bound_out.replace('childDecodedFrames=75 hbBound=1', 'hbBound=0 hbNote=GORAV_HB_FILE-unset')
    ok.append(('real: hbBound=0 -> counter NOT bound (never zero)',
               parse_gorav_receipt(hb0, '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: missing decoded line -> NOT bound',
               parse_gorav_receipt(sample_out, '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: duplicate decoded lines -> NOT bound',
               parse_gorav_receipt(bound_out + 'gorav play decoded: leg=default childDecodedFrames=75 hbBound=1 runID=run-7f\n', '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: non-UInt64 count -> NOT bound',
               parse_gorav_receipt(bound_out.replace('childDecodedFrames=75', 'childDecodedFrames=7x'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: runID mismatch vs integrity -> NOT bound',
               parse_gorav_receipt(bound_out.replace('hbBound=1 runID=run-7f', 'hbBound=1 runID=run-99'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: metal leg excluded (runID -, leg != default) -> NOT bound',
               parse_gorav_receipt(bound_out.replace('leg=default', 'leg=metal').replace('runID=run-7f\n', 'runID=-\n'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: nonzero exit -> NOT bound despite printed count',
               parse_gorav_receipt(bound_out, '', 1, 'real')[0]['decoded_frames'] is None))
    ok.append(('real: missing integrity line -> NOT bound',
               parse_gorav_receipt(bound_out.replace('gorav play integrity: ledgerAllowsSuccess=1 ledgerWriteOK=1 admissionBound=1 audioFailedStops=0 runID=run-7f\n', ''), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: decoded/integrity runIDs differ from expected label -> NOT bound',
               parse_gorav_receipt(bound_out.replace('runID=run-7f', 'runID=run-99'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: norunid fallback equal on both lines is a vacuous match -> NOT bound',
               parse_gorav_receipt(bound_out.replace('runID=run-7f', 'runID=norunid'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: norunid on both lines is rejected even when expected is norunid (never a binding)',
               parse_gorav_receipt(bound_out.replace('runID=run-7f', 'runID=norunid'), '', 0, 'real', expected_run_id='norunid')[0]['decoded_frames'] is None))
    ok.append(('real: malformed decoded line (bare token) -> NOT bound, no crash',
               parse_gorav_receipt(bound_out.replace('hbBound=1 runID=run-7f', 'hbBound=1 baretoken runID=run-7f'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: malformed integrity line (bare token) -> NOT bound, no crash',
               parse_gorav_receipt(bound_out.replace('audioFailedStops=0 runID', 'audioFailedStops=0 baretoken runID'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: non-ASCII digits (\\u2077\\u2075 superscripts) -> NOT bound, no crash',
               parse_gorav_receipt(bound_out.replace('childDecodedFrames=75', 'childDecodedFrames=\u2077\u2075'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: count above UInt64 max -> NOT bound',
               parse_gorav_receipt(bound_out.replace('childDecodedFrames=75', 'childDecodedFrames=18446744073709551616'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] is None))
    ok.append(('real: count exactly UInt64 max -> bound (valid boundary)',
               parse_gorav_receipt(bound_out.replace('childDecodedFrames=75', 'childDecodedFrames=18446744073709551615'), '', 0, 'real', expected_run_id='run-7f')[0]['decoded_frames'] == 18446744073709551615))
    # Pin gate (gdb u5 HOLD)
    import tempfile as _tf
    d = _tf.mkdtemp()
    cp = Path(d) / 'c.bin'
    cp.write_bytes(b'x')
    ok.append(('missing pin -> gate failure',
               clip_pin_status({'id': 't'}, cp) is not None))
    ok.append(('malformed pin -> gate failure',
               clip_pin_status({'id': 't', 'clip_sha256': 'zz'}, cp) is not None))
    ok.append(('valid-looking pin, wrong bytes -> mismatch',
               clip_pin_status({'id': 't', 'clip_sha256': '0' * 64}, cp) is not None))
    good = hashlib.sha256(b'x').hexdigest()
    ok.append(('matching pin -> gate open',
               clip_pin_status({'id': 't', 'clip_sha256': good}, cp) is None))
    # Timeout wrapper
    import stat as _stat
    hang = Path(d) / 'hang.sh'
    hang.write_text('#!/bin/sh\nsleep 5\n')
    hang.chmod(hang.stat().st_mode | _stat.S_IEXEC)
    global RUN_TIMEOUT_SECONDS
    saved = RUN_TIMEOUT_SECONDS
    RUN_TIMEOUT_SECONDS = 1
    try:
        rt, note = run_gorav(hang, cp, 1, 'stub')
    finally:
        RUN_TIMEOUT_SECONDS = saved
    # Real-mode END-TO-END regressions (u9r4): exercise run_gorav itself with
    # synthetic children, not only the parser - team 3 found real mode was
    # never executed anywhere (module lacked the tempfile import).
    child_src = '''#!/usr/bin/env python3
import os, sys, time
mode = os.environ.get('SYNTH_CHILD_MODE', 'compliant')
sidecar = os.environ.get('SYNTH_SIDECAR')
hb = os.environ.get('GORAV_HB_FILE')
rid = os.environ.get('GORAV_RUN_ID', 'norunid')
if sidecar:
    open(sidecar, 'a').write('%s\\t%s\\n' % (hb, rid))
if mode == 'compliant':
    if hb:
        open(hb, 'w').write('75\\n')
    print('gorav play integrity: ledgerAllowsSuccess=1 ledgerWriteOK=1 admissionBound=1 audioFailedStops=0 runID=%s' % rid)
    print('gorav play decoded: leg=default childDecodedFrames=75 hbBound=1 runID=%s' % rid)
elif mode == 'norunid':
    print('gorav play integrity: ledgerAllowsSuccess=1 ledgerWriteOK=1 admissionBound=1 audioFailedStops=0 runID=norunid')
    print('gorav play decoded: leg=default childDecodedFrames=75 hbBound=1 runID=norunid')
elif mode == 'wrongid':
    print('gorav play integrity: ledgerAllowsSuccess=1 ledgerWriteOK=1 admissionBound=1 audioFailedStops=0 runID=run-999')
    print('gorav play decoded: leg=default childDecodedFrames=75 hbBound=1 runID=run-999')
elif mode == 'hb0':
    print('gorav play integrity: ledgerAllowsSuccess=1 ledgerWriteOK=1 admissionBound=1 audioFailedStops=0 runID=%s' % rid)
    print('gorav play decoded: leg=default hbBound=0 hbNote=heartbeat-file-stale-or-missing-this-run runID=%s' % rid)
elif mode == 'slow':
    time.sleep(30)
sys.exit(0)
'''
    cdir = tempfile.mkdtemp()
    child = Path(cdir) / 'synth-child.py'
    child.write_text(child_src)
    os.chmod(child, 0o755)
    sidecar = Path(cdir) / 'seen.tsv'
    os.environ['SYNTH_SIDECAR'] = str(sidecar)
    try:
        os.environ['SYNTH_CHILD_MODE'] = 'compliant'
        r1, _ = run_gorav(child, Path(cdir) / 'c.bin', 0, 'real')
        ok.append(('real e2e: compliant synthetic child -> decoded 75 bound through run_gorav',
                   r1['decoded_frames'] == 75))
        r2, _ = run_gorav(child, Path(cdir) / 'c.bin', 0, 'real')
        seen = [l.split('\t') for l in sidecar.read_text().splitlines()]
        ok.append(('real e2e: GORAV_HB_FILE and GORAV_RUN_ID unique per invocation',
                   len(seen) == 2 and seen[0][0] != seen[1][0] and seen[0][1] != seen[1][1]
                   and all(x[0] != 'None' and x[1] != 'None' for x in seen)))
        ok.append(('real e2e: heartbeat path removed after each run',
                   all(not Path(x[0]).exists() for x in seen)))
        os.environ['SYNTH_CHILD_MODE'] = 'norunid'
        ok.append(('real e2e: norunid child -> NOT bound',
                   run_gorav(child, Path(cdir) / 'c.bin', 0, 'real')[0]['decoded_frames'] is None))
        os.environ['SYNTH_CHILD_MODE'] = 'wrongid'
        ok.append(('real e2e: wrong-runID child -> NOT bound',
                   run_gorav(child, Path(cdir) / 'c.bin', 0, 'real')[0]['decoded_frames'] is None))
        os.environ['SYNTH_CHILD_MODE'] = 'hb0'
        ok.append(('real e2e: hbBound=0 child -> NOT bound',
                   run_gorav(child, Path(cdir) / 'c.bin', 0, 'real')[0]['decoded_frames'] is None))
        os.environ['SYNTH_CHILD_MODE'] = 'slow'
        saved = RUN_TIMEOUT_SECONDS
        RUN_TIMEOUT_SECONDS = 1
        try:
            rt, _ = run_gorav(child, Path(cdir) / 'c.bin', 0, 'real')
        finally:
            RUN_TIMEOUT_SECONDS = saved
        ok.append(('real e2e: timeout child -> typed timeout, counter NOT bound',
                   rt['rc'] == 'timeout' and rt['decoded_frames'] is None))
    finally:
        os.environ.pop('SYNTH_CHILD_MODE', None)
        os.environ.pop('SYNTH_SIDECAR', None)
    ok.append(('hanging binary -> typed timeout receipt',
               rt['completed'] is False and rt['rc'] == 'timeout'))
    failures = 0
    for name, passed in ok:
        print('selftest %-52s %s' % (name, 'ok' if passed else 'FAIL'))
        if not passed:
            failures += 1
    print('MPV_PARITY_SELFTEST_PASS' if failures == 0 else 'MPV_PARITY_SELFTEST_FAILURES=%d' % failures)
    return 0 if failures == 0 else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, default=Path('fixtures/corpus/mpv-parity.json'))
    parser.add_argument('--gorav', type=Path)
    parser.add_argument('--gorav-mode', choices=['real', 'stub'],
                        help='required for a run: real gorav-play vs ffprobe-fed stub')
    parser.add_argument('--mpv', type=Path)
    parser.add_argument('--ffprobe', type=Path)
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        sys.exit(self_test())
    if not args.gorav_mode:
        print('NOT_RUN --gorav-mode {real,stub} is required (no implicit mode: '
              'same-oracle runs must be labelled harness-only)')
        sys.exit(3)

    corpus = json.loads(args.corpus.read_text(encoding='utf-8'))
    clips_root = Path(corpus['clips_root'])
    reference_block = corpus.get('reference')
    passes = 0
    harness_passes = 0
    fails = 0
    notruns = 0
    for cls in corpus['classes']:
        cid = cls['id']
        ops = cls.get('ops', [])
        if ops != ['play']:
            print('%s NOT_RUN comparator v3 supports play-only classes; ops=%s have no verified ops-receipt model'
                  % (cid, ops))
            notruns += 1
            continue
        clip = clips_root / cls['clip']
        if not clip.exists():
            print('%s NOT_RUN missing clip %s' % (cid, clip))
            notruns += 1
            continue
        pin_status = clip_pin_status(cls, clip)
        if pin_status is not None:
            print('%s NOT_RUN %s' % (cid, pin_status))
            notruns += 1
            continue
        ref_status = reference_gate(cls, reference_block)
        if ref_status is not None:
            print('%s NOT_RUN %s' % (cid, ref_status))
            notruns += 1
            continue
        if not args.ffprobe or not args.ffprobe.exists():
            print('%s NOT_RUN missing ffprobe binary (reference tool)' % cid)
            notruns += 1
            continue
        vout, vreason = probe_reference_tool(args.ffprobe)
        if vout is None:
            print('%s NOT_RUN %s' % (cid, vreason))
            notruns += 1
            continue
        drift = verify_reference_tool(reference_block['ffprobe_version'],
                                      reference_block['ffmpeg_build'], vout)
        if drift is not None:
            print('%s NOT_RUN %s (re-measure required per ruling)' % (cid, drift))
            notruns += 1
            continue
        ref_live, rnote = measure_reference(args.ffprobe, clip)
        if ref_live is None:
            print('%s NOT_RUN %s' % (cid, rnote))
            notruns += 1
            continue
        if ref_live != cls['reference_decoded_frames']:
            print('%s FAIL deterministic-input anomaly: pinned reference %s but '
                  'same-version tool measures %s on pin-verified bytes'
                  % (cid, cls['reference_decoded_frames'], ref_live))
            fails += 1
            continue
        if not args.gorav or not args.gorav.exists():
            print('%s NOT_RUN missing gorav-play binary' % cid)
            notruns += 1
            continue
        if not args.mpv or not args.mpv.exists():
            print('%s NOT_RUN missing mpv binary' % cid)
            notruns += 1
            continue
        hold = cls.get('hold_seconds', 1)
        greceipt, gnote = run_gorav(args.gorav, clip, hold, args.gorav_mode)
        if greceipt['completed'] is None:
            print('%s NOT_RUN %s' % (cid, gnote))
            notruns += 1
            continue
        if greceipt.get('rc') == 'timeout':
            print('%s %s %s' % (cid, 'HARNESS_FAIL' if args.gorav_mode == 'stub' else 'FAIL', gnote))
            fails += 1
            continue
        mreceipt, mnote = run_mpv(args.mpv, clip)
        verdict, detail = compare(greceipt, mreceipt, cls['reference_decoded_frames'],
                                  args.gorav_mode)
        print('%s %s %s' % (cid, verdict, detail))
        if verdict == 'PASS':
            passes += 1
        elif verdict == 'HARNESS_PASS':
            harness_passes += 1
        elif verdict in ('FAIL', 'HARNESS_FAIL'):
            fails += 1
        else:
            notruns += 1
    # Aggregate (D1): NOT_RUN never counts as a run.
    print('SUMMARY pass=%d harness_pass=%d fail=%d not_run=%d'
          % (passes, harness_passes, fails, notruns))
    if fails:
        sys.exit(1)
    if passes == 0:
        if harness_passes:
            print('HARNESS_ONLY_RUN %d stub agreement(s) - SAME-ORACLE plumbing '
                  'check, NOT parity; real count parity needs the Mac gorav-play '
                  'gate and an mpv own-pipeline counter' % harness_passes)
        else:
            print('NO_CLASS_PASS')
        sys.exit(3)
    if notruns:
        print('PARTIAL_RUN %d class(es) not run' % notruns)
    sys.exit(0)


if __name__ == '__main__':
    main()
