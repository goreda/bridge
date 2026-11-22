#!/usr/bin/env python3
"""Run actual ffprobe with the argument list read from the product source.

No Swift execution is claimed. The production argument literal is decoded as
JSON after replacing its sole path identifier with a path placeholder.
"""
from pathlib import Path
import json
import re
import shutil
import subprocess
import sys
import tempfile
import wave

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
s = (ROOT / 'Sources/gor/Engine/GorAVLocalOffer.swift').read_text()
match = re.search(r'p.arguments = (\[[^\n]+\])', s)
assert match
literal = match.group(1)
assert literal.endswith(', path]')
args = json.loads(literal[:-len('path]')] + '"<PATH>"]')
assert args == ['-v', 'error', '-show_format', '-show_streams', '-of', 'json', '--', '<PATH>']
assert 'done.wait(timeout: .now() + timeoutSeconds)' in s
assert 'kill(p.processIdentifier, SIGKILL)' in s
ffprobe = shutil.which('ffprobe')
if not ffprobe:
    raise SystemExit('NOT_RUN ffprobe unavailable')

def invoke(arguments, cwd):
    return subprocess.run([ffprobe] + arguments, cwd=cwd, capture_output=True, text=True, timeout=10)

with tempfile.TemporaryDirectory() as work:
    root = Path(work)
    for name in ['normal.wav', '-version', '-show_format', 'a b "quoted".wav']:
        with wave.open(str(root / name), 'wb') as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(8000)
            out.writeframes(b'\0\0' * 800)
        for path in [name, str(root / name)]:
            result = invoke([path if value == '<PATH>' else value for value in args], work)
            assert result.returncode == 0, result.stderr
            payload = json.loads(result.stdout)
            assert payload['format']['format_name'] == 'wav'
            assert payload['streams'][0]['codec_type'] == 'audio'
    legacy = invoke([value for value in args[:-1] if value != '--'] + ['-version'], work)
    try:
        payload = json.loads(legacy.stdout)
    except json.JSONDecodeError:
        payload = {}
    assert payload.get('format', {}).get('format_name') != 'wav', 'old option-path witness stopped reproducing'
    missing = invoke(args[:-1] + ['-no-such-media-file'], work)
    assert missing.returncode != 0
print('PASS real ffprobe: 8 product-argument file probes, option-name legacy failure, missing-file refusal')
print('NOT RUN Swift/AppKit target, DemuxerPolicy admission, or playback')
