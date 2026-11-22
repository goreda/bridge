#!/usr/bin/env python3
"""Execute pixel comparator against actual decoded PNGs and failure mutants.
These are supplementary harness tests, not Mac menu acceptance.
The real verdict is produced only by the installed app on the Mac.
"""
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import tempfile
import zlib

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('axes', ROOT / 'tools/axes_acceptance.py')
a = importlib.util.module_from_spec(spec)
spec.loader.exec_module(a)
ffmpeg = shutil.which('ffmpeg')
if not ffmpeg:
    raise SystemExit('NOT_RUN: ffmpeg required for actual decoded image tests')


def png(path, color, width=8, height=8):
    def chunk(kind, data):
        body = kind + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))
    raw = b''.join(b'\0' + bytes(color) * width for _ in range(height))
    path.write_bytes(b'\x89PNG\r\n\x1a\n' +
                     chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
                     chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def completion(root, **changes):
    obj = dict(complete=True, failures=[], cases=list(range(9)))
    obj.update(changes)
    (root / 'complete.json').write_text(json.dumps(obj))


def refuses(root, reason):
    try:
        a.compare(root, ffmpeg)
    except (ValueError, OSError) as error:
        print('PASS rejects ' + reason)
        return
    raise AssertionError('accepted ' + reason)


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    completion(root)
    png(root / 'source-reference.png', (10, 20, 30))
    for i in range(9):
        png(root / ('source%d__off_reopen.png' % i), (10, 20, 30))
    result = a.compare(root, ffmpeg)
    assert result['off_pixel_verdict'] == 'PASS'
    assert result['format_pixels'] == 'REQUIRES_VISUAL_INSPECTION'
    print('PASS nine actual decoded Off/reopen images equal the source')
    png(root / 'source0__off_reopen.png', (11, 20, 30))
    assert a.compare(root, ffmpeg)['off_pixel_verdict'] == 'FAIL'
    print('PASS one RGB sample change is a pixel FAIL')
    png(root / 'source0__off_reopen.png', (10, 20, 30), width=4, height=16)
    assert a.compare(root, ffmpeg)['off_pixel_verdict'] == 'FAIL'
    print('PASS same byte count at wrong geometry is a pixel FAIL')
    completion(root, complete=False)
    refuses(root, 'incomplete runner')
    completion(root, failures=['route failed'])
    refuses(root, 'failed actual menu selector')
    completion(root, cases=[])
    refuses(root, 'no matrix')
    completion(root)
    (root / 'source8__off_reopen.png').unlink()
    refuses(root, 'incomplete reopen matrix')
    (root / 'source-reference.png').unlink()
    refuses(root, 'missing source reference')

assert a.live_gor_instances(Path('/nonexistent/gor-binary-for-guard-test')) == []
print('PASS live-instance guard is empty when no matching process exists')

source = (ROOT / 'tools/axes_acceptance.py').read_text()
assert 'start_new_session=True' in source and 'child.wait(timeout=3)' in source
assert 'time.time_ns()' in source
assert 'interactive_gor_running_refused' in source
assert 'expected = 1 + 2 * len(cases)' in source
print('PASS fresh attempt directory, bounded cleanup, no stale-image reuse')
print('PASS interactive-instance refusal and screenshot flush wait are wired')

# Capture 041010 regression: shortened argv hid an old exact-path process from pgrep -f.
from unittest.mock import patch
from types import SimpleNamespace
import signal,os
uid=str(os.getuid());binary='/test space/gor.app/Contents/MacOS/gor'
rows={'68565':('old',binary,'gor'),'84996':('fresh',binary,binary),'77':('other','/other/gor','/other/gor'),'88':('worker',binary,binary+' --selftest3d')}
rows.pop('84996')
def boundary(cmd,**kwargs):
 if '-axo' in cmd:return SimpleNamespace(stdout=''.join(pid+' '+uid+' '+row[1]+'\n' for pid,row in rows.items()),returncode=0)
 pid=cmd[cmd.index('-p')+1];row=rows.get(pid)
 if row is None:return SimpleNamespace(stdout='',returncode=1)
 return SimpleNamespace(stdout=(row[0]+' '+row[1]) if cmd[-1]=='lstart=,comm=' else row[2],returncode=0)
signals=[]
def signal_boundary(pid,sig):
 signals.append((pid,sig))
 if sig==signal.SIGKILL:rows.pop(str(pid),None)
with patch.object(a.subprocess,'run',side_effect=boundary),patch.object(a.os,'kill',side_effect=signal_boundary):
 assert a.live_gor_instances(Path(binary))==['68565']
 assert a.stop_interactive(Path(binary),term_seconds=0,kill_seconds=0)
 assert signals==[(68565,signal.SIGTERM),(68565,signal.SIGKILL)]
 assert set(rows)=={'77','88'}
 # A new process appearing during old-process exit blocks launch, never gets signaled.
 rows['68565']=('old',binary,'gor');signals.clear()
 def reused(pid,sig):
  signals.append((pid,sig));rows['68565']=('reused',binary,'gor')
 with patch.object(a.os,'kill',side_effect=reused):
  assert not a.stop_interactive(Path(binary),term_seconds=0,kill_seconds=0)
 assert signals==[(68565,signal.SIGTERM)]
print('PASS capture041010 shortened-argv old process detected, TERM/KILL verified before launch, unrelated/worker untouched, reused PID blocks launch')
bs=(ROOT/'build.sh').read_text()
assert '--list-interactive "$bin"' in bs and '--stop-interactive "$bin"' in bs
assert 'st_quit || return 1; open -g -n "$app" --args --gor-no-activate' in bs
assert "__import__('axes_acceptance').live_gor_instances(binary)" in (ROOT/'gor-selftest.sh').read_text()
print('PASS selftest/relaunch/l1 share one exact-path enumerator, inspection error cannot become gone')
