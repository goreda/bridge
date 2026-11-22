#!/usr/bin/env python3
"""Compile and execute the actual Swift distance model, not a mirror.

Default source is the production file in this gor tree. This test installs
nothing, reads no device input and does not change source or a running app.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--swiftc', default=os.environ.get('SWIFTC') or shutil.which('swiftc'))
parser.add_argument('--source', type=Path)
parser.add_argument('--mutants', action='store_true', help='Run bounded compiled semantic negative controls')
args = parser.parse_args()
if not args.swiftc:
    parser.error('Swift compiler required; set SWIFTC or pass --swiftc')
root = Path(__file__).resolve().parents[2]
source = args.source or root / 'Sources/gor/Stereo/VRDistanceModel.swift'
fixture = Path(__file__).with_name('vr_distance_model_swift_main.swift')
real = source.read_text()
main = fixture.read_text()

def run_case(source_text, label, modes):
    ok = True
    with tempfile.TemporaryDirectory(prefix='vr-distance-swift-') as directory:
        directory = Path(directory)
        model = directory / 'VRDistanceModel.swift'
        model.write_text(source_text)
        (directory / 'main.swift').write_text(main)
        for mode in modes:
            binary = directory / ('model-' + mode)
            result = subprocess.run([args.swiftc, '-swift-version', '6',
                                     '-strict-concurrency=complete', '-' + mode,
                                     str(model), str(directory / 'main.swift'),
                                     '-o', str(binary)], capture_output=True, text=True)
            print(f'{label}/{mode} compile_exit={result.returncode}')
            if result.stdout: print(result.stdout, end='')
            if result.stderr: print(result.stderr, end='')
            if result.returncode:
                return False, False
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            print(result.stdout, end='')
            if result.stderr: print(result.stderr, end='')
            print(f'{label}/{mode} runtime_exit={result.returncode}')
            ok = ok and result.returncode == 0
    return True, ok

compiled, passed = run_case(real, 'production', ['Onone', 'O'])
if not compiled or not passed:
    sys.exit(1)
if args.mutants:
    controls = [
        ('early-classification', 'o.reason = "no-osd-size"', 'o.reason = "no-input"'),
        ('ok-boundary', 'holdOkBoundaryS = 0.5', 'holdOkBoundaryS = 0.25'),
        ('hold-boundary', 'distanceHoldS = 2.0', 'distanceHoldS = 1.0'),
        ('cap-sign', '* (ipdEff + sToday) - ipdEff', '* (ipdEff + sToday) + ipdEff'),
        ('shift-limit', 'shaderShiftLimit = 0.8', 'shaderShiftLimit = 1.0'),
        ('cap-met', 'o.capMet = capMet', 'o.capMet = true'),
        ('nudge-sign', 'shift - excess - ipdNudge', 'shift - excess + ipdNudge'),
    ]
    for label, before, after in controls:
        if real.count(before) != 1:
            raise SystemExit('Negative-control source anchor changed: ' + label)
        compiled, passed = run_case(real.replace(before, after, 1), label, ['Onone'])
        if not compiled or passed:
            raise SystemExit('Negative control did not produce a compiled runtime failure: ' + label)
        print('CAUGHT ' + label)
print('PASS actual Swift distance regression')
