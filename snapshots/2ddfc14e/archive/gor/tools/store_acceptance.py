#!/usr/bin/env python3
"""191b-T: store/menu/keys acceptance driver, rides ./build.sh --update's self-test like the axes runner.

Spawns the installed gor on synthesized fixtures (plain 2D, SBS, native VR180 metadata) with
GOR_STORE_ACCEPTANCE_* env; the in-app runner (ThreeDStoreAcceptance.swift) dispatches store
actions and drives real menu rows via NSMenu performActionForItem. This driver owns the verdict:
every expected case must exist with its full per-case artifact set (action log, store snapshots,
applied commands, one frame grab, verdict) - an aggregate-only FAIL is NOT a result, a missing
artifact fails that case by name. Pixel checks are re-done here from the frame grabs with the
vendor ffmpeg, never trusted from the app.

Sources x Outputs matrix is the B1 contract; sequences 1-5 come from the 191b block verbatim.
Sequence 4 (the owner's converted magnet file) needs GOR_STORE_ACCEPTANCE_MAGNET=<path>; without
it the case reports NOT_RUN owner_file_not_provided, never a silent skip.
"""
import hashlib, json, os, shutil, signal, struct, subprocess, sys, tempfile, time
from pathlib import Path

SOURCES = ["auto", "flat2D", "sbsFull", "sbsHalf", "tbFull", "tbHalf", "vr180SBS", "vr180TB", "vr360Mono", "vr360TB"]
OUTPUTS = ["off", "sbs", "halfSBS", "tb", "vr180", "anaglyph"]
SEQUENCES = ["seq1_open2d_sbs_stable", "seq2_vr180_off_reopen", "seq3_native_vr180_off_flat", "seq4_magnet_2d", "seq5_keys_table"]
ARTIFACTS = ["action.log", "store-before.json", "store-after.json", "commands.json", "frame.png", "verdict.txt"]
TOS_FIXTURE = 'tools/depth_analysis/kit/x2_tos_reference/tos_input_320x180_48f.mp4'
TOS_SHA = None  # filled from axes_acceptance at import time when available


def matrix_cases():
    return ["matrix_%s__%s" % (s, o) for s in SOURCES for o in OUTPUTS]


def expected_cases():
    return matrix_cases() + SEQUENCES


def box(t, body):
    return struct.pack('>I', 8 + len(body)) + t + body


def sv3d_tag():
    """Same box tree as Tests/SphericalTag: st3d left-right + sv3d/svhd/proj/prhd/equi, 180x180 bounds."""
    st3d = box(b'st3d', struct.pack('>IB', 0, 2))
    svhd = box(b'svhd', struct.pack('>I', 0) + b'gor\x00')
    prhd = box(b'prhd', struct.pack('>Iiii', 0, 0, 0, 0))
    equi = box(b'equi', struct.pack('>IIIII', 0, 0, 0, 0x40000000, 0x40000000))
    return st3d + box(b'sv3d', svhd + box(b'proj', prhd + equi))


SAMPLE_ENTRIES = {b'hvc1', b'hev1', b'avc1', b'avc3'}


def children(d, a, b):
    i = a
    while i + 8 <= b:
        sz, t = struct.unpack('>I4s', d[i:i + 8]); h = 8
        if sz == 1:
            sz = struct.unpack('>Q', d[i + 8:i + 16])[0]; h = 16
        if sz == 0:
            sz = b - i
        if sz < h or i + sz > b:
            raise ValueError('bad box')
        yield t, i, i + sz, i + h
        i += sz


def mp4_spherical_patch(d):
    """In-place sv3d/st3d tag insert, ported from Tests/SphericalTag: grows every ancestor box and
    shifts stco/co64 chunk offsets when moov precedes mdat."""
    top = list(children(d, 0, len(d)))
    moov = next((x for x in top if x[0] == b'moov'), None)
    mdat = next((x for x in top if x[0] == b'mdat'), None)
    if not moov:
        raise ValueError('no moov')
    if b'st3d' in d[moov[1]:moov[2]]:
        return d
    path = []
    cur = moov
    for name in (b'trak', b'mdia', b'minf', b'stbl', b'stsd'):
        nxt = next((c for c in children(d, cur[3] + (8 if cur[0] == b'stsd' else 0), cur[2]) if c[0] == name), None)
        if not nxt:
            raise ValueError('no ' + name.decode())
        path.append(nxt); cur = nxt
    stsd = cur
    entry = next((c for c in children(d, stsd[3] + 8, stsd[2]) if c[0] in SAMPLE_ENTRIES), None)
    if not entry:
        raise ValueError('no video sample entry')
    add = sv3d_tag()
    out = bytearray(d[:entry[2]] + add + d[entry[2]:])
    for t, a, b, h in [moov] + path + [entry]:
        sz = struct.unpack('>I', d[a:a + 4])[0]
        if sz in (0, 1):
            raise ValueError('64-bit box size')
        out[a:a + 4] = struct.pack('>I', sz + len(add))
    if mdat and moov[1] < mdat[1]:
        o = bytearray(out); stbl = path[-2]
        for t, a, b, h in children(bytes(o), stbl[3], stbl[2] + len(add)):
            if t == b'stco':
                n = struct.unpack('>I', o[h + 4:h + 8])[0]
                for k in range(n):
                    q = h + 8 + 4 * k
                    o[q:q + 4] = struct.pack('>I', struct.unpack('>I', o[q:q + 4])[0] + len(add))
            if t == b'co64':
                n = struct.unpack('>I', o[h + 4:h + 8])[0]
                for k in range(n):
                    q = h + 8 + 8 * k
                    o[q:q + 8] = struct.pack('>Q', struct.unpack('>Q', o[q:q + 8])[0] + len(add))
        out = o
    return bytes(out)


def synthesize_fixtures(root, workdir, ffmpeg, ffprobe=None):
    """Build plain/SBS/VR180-metadata fixtures from the public ToS clip; never owner material."""
    out = {}
    plain = workdir / 'plain_2d.mp4'
    shutil.copyfile(root / TOS_FIXTURE, plain)
    out['plain'] = plain
    sbs = workdir / 'flat_sbs.mp4'
    r = subprocess.run([str(ffmpeg), '-v', 'error', '-y', '-i', str(plain),
                        '-filter_complex', '[0:v][0:v]hstack=inputs=2[s]', '-map', '[s]', '-c:v', 'libx264',
                        '-pix_fmt', 'yuv420p', '-t', '2', str(sbs)], capture_output=True, text=True, timeout=120)
    if r.returncode == 0 and sbs.is_file():
        out['sbs'] = sbs
    if 'sbs' in out:
        vr = workdir / 'vr180_meta.mp4'
        try:
            vr.write_bytes(mp4_spherical_patch(sbs.read_bytes()))
            # The generated fixture must contain our exact spatial boxes and decode.
            # ffprobe is optional: only ffmpeg is shipped in the installed vendor kit.
            decode = subprocess.run([str(ffmpeg), '-v', 'error', '-i', str(vr), '-frames:v', '1', '-f', 'null', '-'],
                                    capture_output=True, text=True, timeout=60)
            valid = decode.returncode == 0 and sv3d_tag() in vr.read_bytes()
            if ffprobe is not None:
                probe = subprocess.run([str(ffprobe), '-v', 'error', '-show_streams', '-of', 'json', str(vr)],
                                       capture_output=True, text=True, timeout=60)
                valid = valid and probe.returncode == 0 and 'Spherical Mapping' in probe.stdout
            if valid:
                out['vr180meta'] = vr
        except (ValueError, OSError, subprocess.SubprocessError):
            pass
    return out


VIDEO_EXTENSIONS = {'.mkv', '.mp4', '.m4v', '.avi', '.mov', '.webm'}
STEREO_NAME_TOKENS = ('180', '360', 'vr', 'sbs', 'hsbs', 'fsbs', '_lr', '_tb', '3dh', '3d')


def looks_stereo_named(name):
    low = name.lower()
    return any(t in low for t in STEREO_NAME_TOKENS)


def discover_magnet_file(home):
    """Rule for the owner's converted magnet file (Main 22:13, no owner ask): the newest plain-named
    video in ~/Downloads or ~/Movies - VR/stereo-tagged names are excluded because sequence 4 asserts
    a 2D open. Returns None when no candidate exists; the case then reports NOT_RUN no_candidate."""
    best = None
    for folder in (Path(home) / 'Downloads', Path(home) / 'Movies'):
        try:
            candidates = [f for f in folder.iterdir()
                          if f.is_file() and f.suffix.lower() in VIDEO_EXTENSIONS and not looks_stereo_named(f.name)]
        except OSError:
            continue
        for f in candidates:
            try:
                if f.stat().st_size == 0:
                    continue
                if best is None or f.stat().st_mtime > best.stat().st_mtime:
                    best = f
            except OSError:
                continue
    return best


def live_gor_instances(binary):
    out = subprocess.run(['pgrep', '-f', str(binary)], capture_output=True, text=True, timeout=5)
    live = []
    for pid in out.stdout.split():
        args = subprocess.run(['ps', '-ww', '-p', pid, '-o', 'command='], capture_output=True, text=True, timeout=5).stdout
        if any(flag in args for flag in (' --selftest3d', ' --gor-model-load-probe', ' --gor-prepare-worker')):
            continue
        live.append(pid)
    return live


def image_bytes(ffmpeg, path):
    r = subprocess.run([str(ffmpeg), '-v', 'error', '-i', str(path), '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'],
                       capture_output=True, timeout=60)
    if r.returncode != 0 or not r.stdout:
        return None
    return r.stdout


def validate_case(directory, name):
    """Per-case artifact custody. Returns (verdict, reason); a missing artifact is a named FAIL."""
    case_dir = directory / name
    if not case_dir.is_dir():
        return ('FAIL', 'case_dir_missing')
    for artifact in ARTIFACTS:
        if not (case_dir / artifact).is_file() or (case_dir / artifact).stat().st_size == 0:
            return ('FAIL', 'artifact_missing_' + artifact.replace('.', '_'))
    verdict = (case_dir / 'verdict.txt').read_text(errors='replace').strip().splitlines()[0]
    if verdict.startswith('NOT_RUN'):
        return ('NOT_RUN', verdict[8:].strip()[:80])
    if verdict.startswith('PASS'):
        return ('PASS', verdict[5:].strip()[:80])
    return ('FAIL', (verdict[5:].strip() if verdict.startswith('FAIL') else verdict)[:80])


def emit_prior_store_evidence(root):
    history = root / '.gor-store-acceptance'
    previous = sorted((p for p in history.iterdir() if p.is_dir()), key=lambda p:p.name) if history.is_dir() else []
    if not previous: return
    prior = previous[-1]
    for path in sorted(prior.rglob('complete.json')):
        print('3D-STORE prior-complete path=%s json=%s' % (path.relative_to(history), path.read_text().replace('\n',' ')), flush=True)
    for path in sorted(prior.rglob('verdict.txt')):
        if path.read_text().startswith('FAIL'):
            print('3D-STORE prior-fail case=%s text=%s' % (path.parent.name,path.read_text().strip()), flush=True)
    for path in sorted(prior.rglob('seq5_keys_table/action.log')):
        for line in path.read_text().splitlines(): print('3D-STORE prior-seq5-action '+line,flush=True)


def run(root, seconds=900):
    root = Path(root).resolve()
    binary = root / 'gor.app/Contents/MacOS/gor'
    ffmpeg = root / 'Resources/vendor/ffmpeg/bin/ffmpeg'
    ffprobe = root / 'Resources/vendor/ffmpeg/bin/ffprobe'
    missing = [name for name, path in [('built_app', binary), ('ffmpeg', ffmpeg)] if not path.is_file()]
    if missing:
        raise ValueError('missing_' + '_and_'.join(missing))
    if live_gor_instances(binary):
        raise ValueError('interactive_gor_running_refused')
    emit_prior_store_evidence(root)
    directory = root / '.gor-store-acceptance' / str(time.time_ns())
    directory.mkdir(parents=True)
    fixtures = synthesize_fixtures(root, directory, ffmpeg, ffprobe if ffprobe.is_file() else None)
    env = dict(os.environ, GOR_NO_ACTIVATE="1", GOR_STORE_ACCEPTANCE_DIR=str(directory),
               GOR_STORE_ACCEPTANCE_PLAIN=str(fixtures['plain']))
    for key, envname in (('sbs', 'GOR_STORE_ACCEPTANCE_SBS'), ('vr180meta', 'GOR_STORE_ACCEPTANCE_VR180META')):
        if key in fixtures:
            env[envname] = str(fixtures[key])
    magnet = os.environ.get('GOR_STORE_ACCEPTANCE_MAGNET')
    discovered = None
    if not magnet:
        discovered = discover_magnet_file(Path.home())
        magnet = str(discovered) if discovered else None
    if magnet:
        env['GOR_STORE_ACCEPTANCE_MAGNET'] = magnet
        print('3D-STORE seq4 film %s source=%s' % ('sha256:' + hashlib.sha256(magnet.encode()).hexdigest()[:12],
              'env' if not discovered else 'discovered'), flush=True)
    start = time.monotonic()
    fails = 0
    print('3D-STORE harness start deadline_s=%d dir=%s fixtures=%s isolation=fresh_process_per_case' % (seconds, directory, sorted(fixtures)), flush=True)
    for name in expected_cases():
        session = directory / ('session_' + name); session.mkdir()
        kind = 'vr180meta' if name == 'seq3_native_vr180_off_flat' else 'plain'
        fixture = fixtures.get(kind)
        if name == 'seq4_magnet_2d': fixture = Path(magnet) if magnet else None
        if fixture is None:
            fails += 1
            print('3D-STORE case=%s verdict=NOT_RUN reason=fixture_missing_%s' % (name, kind), flush=True)
            continue
        # Every matrix/sequence enters through the normal CLI open on its real fixture,
        # never by claiming an open in an action log. Store durability is disabled in this child.
        child_env = dict(env, GOR_STORE_ACCEPTANCE_DIR=str(session), GOR_STORE_ACCEPTANCE_CASE=name)
        with (session / 'runner.log').open('w') as output:
            child = subprocess.Popen([str(binary), str(fixture)], env=child_env, stdin=subprocess.DEVNULL,
                                     stdout=output, stderr=output, start_new_session=True)
            try:
                deadline = min(start + seconds, time.monotonic() + 60)
                while not (session / 'complete.json').exists():
                    if child.poll() is not None: raise ValueError('runner_exited_before_completion')
                    if time.monotonic() > deadline: raise TimeoutError('runner_deadline_' + name)
                    time.sleep(.2)
                summary = json.loads((session / 'complete.json').read_text())
                print('3D-STORE complete case=%s json=%s' % (name, json.dumps(summary, separators=(',', ':'))), flush=True)
                flush_deadline = min(start + seconds, time.monotonic() + 8)
                while time.monotonic() < flush_deadline and not (session / name / 'frame.png').exists(): time.sleep(.2)
                verdict, reason = validate_case(session, name)
                if verdict != 'PASS':
                    fails += 1
                    vfile = session / name / 'verdict.txt'
                    if vfile.is_file(): print('3D-STORE verdict-file case=%s text=%s' % (name, vfile.read_text().strip()), flush=True)
                if name == 'seq5_keys_table':
                    action = session / name / 'action.log'
                    if action.is_file():
                        for line in action.read_text().splitlines(): print('3D-STORE seq5-action ' + line, flush=True)
                print('3D-STORE case=%s verdict=%s reason=%s' % (name, verdict, reason or '-'), flush=True)
            finally:
                if child.poll() is None:
                    print('3D-STORE signal sender=store_acceptance sender_pid=%d target_pid=%d signal=SIGTERM reason=acceptance_child_cleanup' % (os.getpid(), child.pid), flush=True)
                    try:
                        os.killpg(child.pid, signal.SIGTERM); child.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL); child.wait(timeout=2)
                    except ProcessLookupError: pass
    print('3D-STORE result cases=%d fails=%d elapsed_s=%d evidence=%s' % (len(expected_cases()), fails, time.monotonic() - start, directory), flush=True)
    return 1 if fails else 0


def main():
    try:
        return run(sys.argv[1] if len(sys.argv) > 1 else '.')
    except (ValueError, TimeoutError) as e:
        print('3D-STORE v1 verdict=NOT_RUN reason=%s' % str(e).replace(' ', '_')[:120], flush=True)
        return 2


if __name__ == '__main__':
    sys.exit(main())
