#!/usr/bin/env python3
"""Compile exact production timing declarations against fixed parity vectors.

No package changes, FFmpeg, network, account or native device is needed.
"""
import argparse
import hashlib
from pathlib import Path
import subprocess
import tempfile

SOURCE_SHA256 = 'd51e131eb6240279bbb207c7d1b323d947d6d3fb41fb0d4fdcf709a1419f2260'
DECLARATIONS = ('public enum FrameDecision:', 'public struct MediaWallAnchor:',
                'public enum SyncMaster:', 'public struct AVSyncDecider:')

def extract(source, marker):
    # These four declarations have balanced braces and no brace-bearing strings.
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        if source[end] == '{': depth += 1
        elif source[end] == '}': depth -= 1
        end += 1
    return source[start:end]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--swiftc', default='swiftc')
    args = parser.parse_args()
    raw = args.source.read_bytes()
    actual = hashlib.sha256(raw).hexdigest()
    if actual != SOURCE_SHA256:
        raise SystemExit('source pin mismatch: ' + actual)
    root = Path(__file__).resolve().parents[2]
    text = raw.decode('utf-8')
    declarations = '\n\n'.join(extract(text, m) for m in DECLARATIONS)
    with tempfile.TemporaryDirectory(prefix='clock-parity-') as scratch:
        scratch = Path(scratch)
        extracted = scratch / 'TimingDeclarations.swift'
        binary = scratch / 'clock-parity'
        extracted.write_text(declarations + '\n')
        subprocess.run([args.swiftc, '-parse-as-library', str(extracted),
                        str(root / 'Tests/parity/ClockParity.swift'), '-o', str(binary)], check=True, timeout=60)
        subprocess.run([str(binary), str(root / 'fixtures/corpus/clock-parity.json')], check=True, timeout=10)
    print('SOURCE_SHA256 ' + actual)
    print('Scope: extracted production timing declarations; not FramePump, native display, audio, HDR or full-package parity.')

if __name__ == '__main__':
    main()
