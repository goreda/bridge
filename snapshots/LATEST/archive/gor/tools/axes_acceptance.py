#!/usr/bin/env python3
"""191a Mac UI acceptance. Runs the compiled installed menu runner, then compares decoded Off/reopen pixels.
No source-text pin or menu-route claim can produce a pixel PASS. A missing runner/sentinel/frame is a failure.
The fixture is public ToS footage; evidence contains no owner film paths. Execution is bounded by the caller's
180-second gor_step supervisor. A fresh directory per attempt prevents stale screenshots from passing.
"""
import hashlib
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import time

FIXTURE_SHA = 'b7eaa61e065d9682e5d3bc2ceae3c79f46a799e792260419dffd38b10bc49956'


def image_bytes(ffmpeg, path):
    """Compare decoded RGB samples, not PNG compression bytes or metadata."""
    header = path.read_bytes()[:24]
    if header[:8] != b'\x89PNG\r\n\x1a\n' or len(header) != 24:
        raise ValueError('invalid_png_header')
    size = struct.unpack('>II', header[16:24])
    p = subprocess.run([str(ffmpeg), '-v', 'error', '-nostdin', '-i', str(path),
                        '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgb24', 'pipe:1'],
                       stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
    if p.returncode or not p.stdout:
        raise ValueError('image_decode_failed:' + path.name)
    return size, p.stdout


def compare(directory, ffmpeg):
    directory = Path(directory)
    completion = json.loads((directory / 'complete.json').read_text())
    if completion.get('complete') is not True:
        raise ValueError('runner_not_complete')
    if completion.get('failures'):
        raise ValueError('menu_runner_failures')
    cases = completion.get('cases')
    if not isinstance(cases, list) or not cases:
        raise ValueError('no_menu_cases')
    reference = image_bytes(ffmpeg, directory / 'source-reference.png')
    files = sorted(set(directory.glob('*__off.png')) | set(directory.glob('*__off_reopen.png')))
    if not files:
        raise ValueError('no_off_evidence')
    rows = []
    for path in files:
        actual = image_bytes(ffmpeg, path)
        same = actual == reference
        rows.append(dict(file=path.name, equal=same, rgb_bytes=len(actual[1]),
                         sha256=hashlib.sha256(actual[1]).hexdigest()))
    reopens = [r for r in rows if r['file'].endswith('__off_reopen.png')]
    if len(reopens) < 9:
        raise ValueError('source_reopen_matrix_incomplete')
    formats = list(directory.glob('*.png'))
    if len(formats) < len(cases):
        raise ValueError('source_output_frame_matrix_incomplete')
    result = dict(complete=True, cases=len(cases), off_comparisons=rows,
                  off_pixel_verdict='PASS' if all(r['equal'] for r in rows) else 'FAIL',
                  format_pixels='REQUIRES_VISUAL_INSPECTION',
                  source_sha256=FIXTURE_SHA)
    (directory / 'pixel-verdict.json').write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    return result


def live_gor_instances(binary):
    """Exact executable/argv, same user. Process titles alone may hide full argv."""
    rows=subprocess.run(['/bin/ps','-axo','pid=,uid=,comm='],capture_output=True,text=True,timeout=5,check=True).stdout
    live=[];binary=str(binary)
    for row in rows.splitlines():
        fields=row.strip().split(None,2)
        if len(fields)!=3 or not fields[0].isdigit() or fields[1]!=str(os.getuid()):continue
        pid,_,exe=fields
        if exe!=binary and Path(exe).name!=Path(binary).name:continue
        command=subprocess.run(['/bin/ps','-ww','-p',pid,'-o','command='],capture_output=True,text=True,timeout=5)
        if command.returncode:continue # Process exited between snapshots.
        args=command.stdout.strip()
        if exe!=binary and args!=binary and not args.startswith(binary+' '):continue
        if any(flag in args for flag in (' --selftest3d',' --gor-model-load-probe',' --gor-prepare-worker')):continue
        live.append(pid)
    return live

def stop_interactive(binary,term_seconds=10,kill_seconds=3):
    """Stop only identities present at entry. A new/reused PID blocks relaunch."""
    def identity(pid):
        p=subprocess.run(['/bin/ps','-ww','-p',pid,'-o','lstart=,comm='],capture_output=True,text=True,timeout=5)
        return p.stdout.strip() if p.returncode==0 else ''
    targets={pid:identity(pid) for pid in live_gor_instances(binary)}
    print('RELAUNCH stop_requested pids='+(','.join(sorted(targets)) or 'none'),flush=True)
    def signal_owned(sig):
        for pid,stamp in targets.items():
            if stamp and identity(pid)==stamp:
                try:os.kill(int(pid),sig)
                except ProcessLookupError:pass
                print('RELAUNCH signal='+sig.name+' pid='+pid+' identity_checked=true',flush=True)
    def gone(seconds):
        deadline=time.monotonic()+seconds
        while True:
            remaining=[pid for pid,stamp in targets.items() if stamp and identity(pid)==stamp]
            if not remaining:return True
            if time.monotonic()>=deadline:return False
            time.sleep(.1)
    signal_owned(signal.SIGTERM)
    if not gone(term_seconds):signal_owned(signal.SIGKILL);gone(kill_seconds)
    remaining=live_gor_instances(binary)
    print('RELAUNCH stop_verified remaining='+(','.join(remaining) or 'none'),flush=True)
    return not remaining


def run(root, seconds=160):
    root = Path(root).resolve()
    fixture = root / 'tools/depth_analysis/kit/x2_tos_reference/tos_input_320x180_48f.mp4'
    binary = root / 'gor.app/Contents/MacOS/gor'
    ffmpeg = root / 'Resources/vendor/ffmpeg/bin/ffmpeg'
    if hashlib.sha256(fixture.read_bytes()).hexdigest() != FIXTURE_SHA:
        raise ValueError('fixture_hash_mismatch')
    if not binary.is_file() or not ffmpeg.is_file():
        raise ValueError('built_app_or_image_decoder_missing')
    if live_gor_instances(binary):
        raise ValueError('interactive_gor_running_refused')
    directory = root / '.gor-axes-acceptance' / str(time.time_ns())
    directory.mkdir(parents=True)
    env = dict(os.environ, GOR_AXES_ACCEPTANCE_DIR=str(directory),
               GOR_AXES_ACCEPTANCE_FILM=str(fixture))
    start = time.monotonic()
    with (directory / 'runner.log').open('w') as output:
        child = subprocess.Popen([str(binary), str(fixture)], env=env, stdin=subprocess.DEVNULL,
                                 stdout=output, stderr=output, start_new_session=True)
        try:
            while not (directory / 'complete.json').exists():
                if child.poll() is not None:
                    raise ValueError('runner_exited_before_completion')
                if time.monotonic() - start > seconds:
                    raise TimeoutError('runner_deadline')
                time.sleep(.2)
            cases = json.loads((directory / 'complete.json').read_text()).get('cases') or []
            expected = 1 + 2 * len(cases)  # reference + one format grab + one Off-reopen grab per pair
            deadline = time.monotonic() + 15  # mpv encodes screenshots asynchronously; wait for the flush
            while len(list(directory.glob('*.png'))) < expected and time.monotonic() < deadline:
                time.sleep(.5)
            result = compare(directory, ffmpeg)
            print('3D-AXES pixels off=%s cases=%d elapsed_s=%d evidence=%s formats=REQUIRES_VISUAL_INSPECTION' %
                  (result['off_pixel_verdict'], result['cases'], time.monotonic()-start, directory), flush=True)
            return 0 if result['off_pixel_verdict'] == 'PASS' else 1
        finally:
            if child.poll() is None:
                print('3D-AXES signal sender=axes_acceptance sender_pid=%d target_pid=%d signal=SIGTERM reason=acceptance_child_cleanup' % (os.getpid(), child.pid), flush=True)
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                    child.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait(timeout=2)
                except ProcessLookupError:
                    pass


def main():
    try:
        if sys.argv[1]=='--list-interactive':
            print('\n'.join(live_gor_instances(Path(sys.argv[2]))));return 0
        if sys.argv[1]=='--stop-interactive':return 0 if stop_interactive(Path(sys.argv[2])) else 1
        return run(sys.argv[1])
    except (OSError, ValueError, TimeoutError, subprocess.SubprocessError) as error:
        # Exception classes and a controlled reason only. Never dump private app stderr.
        print('3D-AXES pixels verdict=FAIL reason=%s' % type(error).__name__, flush=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
