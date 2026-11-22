#!/usr/bin/env python3
"""Run real production-source mutants in disposable packages, never the checkout.
Usage: SWIFT=/path/to/swift python3 Tests/CaptureStats/run-mutants.py
Requires prior commits in order: ddd434cd, 04c35e1d, 79e5998d.
A compiler error is NOT a killed mutant; only a built, failing XCTest is RED.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
SWIFT = os.environ.get('SWIFT', 'swift')
MUTANTS = [
    ('capture-epoch', 'HeatTrialCapture.swift',
     'guard begin.presentationEpoch == end.presentationEpoch,', 'guard true,'),
    ('capture-process', 'HeatTrialCapture.swift',
     'guard begin.processInstanceID == end.processInstanceID,', 'guard true,'),
    ('comparison-workload', 'HeatComparison.swift',
     'guard gorav.workload == mpv.workload else', 'guard true else'),
    ('comparison-run', 'HeatComparison.swift',
     'guard gorav.runID != mpv.runID else', 'guard true else'),
    ('comparison-process', 'HeatComparison.swift',
     'guard gorav.processInstanceID != mpv.processInstanceID else', 'guard true else'),
    ('thermal-drop-saturation', 'HeatProducer.swift',
     'count == .max ? .max : count + 1',
     'count &+ 1'),
    ('cpu-regression', 'HeatProducer.swift',
     'guard user >= 0, system >= 0 else',
     'guard true else'),
    ('cpu-reset', 'HeatProducer.swift',
     'public mutating func reset() { previous = nil }',
     'public mutating func reset() {}'),
    ('stats-positive-elapsed', 'CaptureStats.swift',
     'guard elapsed.isFinite, elapsed > 0 else',
     'guard elapsed.isFinite else'),
    ('stats-reset-identity', 'MetalPresenterTelemetry.swift',
     'public static func reset() {\n        captureStatsSessionID = UUID()',
     'public static func reset() {'),
    ('stats-rate-overflow', 'CaptureStats.swift',
     'guard rate.isFinite else { throw CaptureStatsError.invalidTimestamp }',
     '// mutant permits an infinite rate'),
    ('heat-foreign-session', 'CaptureHeatReport.swift',
     'guard sample.sessionID == presenter.snapshot.sessionID else',
     'guard true else'),
    ('heat-duplicate-frame', 'CaptureHeatReport.swift',
     'guard seen.insert(sample.frameID).inserted else',
     'guard true else'),
]


def run(package):
    result = subprocess.run([SWIFT, 'test', '--package-path', str(package)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return result.returncode, result.stdout


def copy_package(destination):
    destination.mkdir()
    # Materialize relative source symlinks so only the disposable copy is mutated.
    for path in HERE.iterdir():
        if path.suffix == '.swift':
            shutil.copyfile(path, destination / path.name)


def main():
    with tempfile.TemporaryDirectory(prefix='capture-mutants-') as tmp:
        root = Path(tmp)
        baseline = root / 'baseline'
        copy_package(baseline)
        rc, output = run(baseline)
        print('BASELINE', 'GREEN' if rc == 0 else 'FAIL', flush=True)
        if rc:
            print(output)
            return 1
        for name, filename, old, new in MUTANTS:
            package = root / name
            copy_package(package)
            path = package / filename
            source = path.read_text()
            if source.count(old) != 1:
                raise RuntimeError(f'{name}: mutation anchor not unique')
            path.write_text(source.replace(old, new))
            rc, output = run(package)
            built = 'Build complete!' in output
            assertions_failed = 'XCTAssert' in output and 'failed' in output
            killed = rc != 0 and built and assertions_failed
            print(name, 'RED' if killed else 'SURVIVED_OR_INVALID', flush=True)
            # Preserve decisive assertion evidence, not pages of build chatter.
            for line in output.splitlines():
                if 'XCTAssert' in line or 'Executed ' in line:
                    print(line)
            if not killed:
                print(output)
                return 1
        print(f'{len(MUTANTS)}/{len(MUTANTS)} mutants built and killed by test assertions')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
