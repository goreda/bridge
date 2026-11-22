"""Run real migrated SwiftPM model targets; never build the macOS shell on Linux."""
import json
from pathlib import Path
import subprocess

app_root = Path(__file__).resolve().parents[1]
root = app_root / 'Packages/GorKit'
if not (root / 'Package.swift').exists():
    print('SKIP GorKit targets=0 tests-ran=0; separate Linux package not yet created; native app never built here')
    raise SystemExit(0)
package = json.loads(subprocess.check_output(['swift', 'package', 'dump-package'], cwd=root, text=True))
model_names = {'GorCore', 'GorPlaybackModel', 'GorSubtitles', 'GorStereo', 'GorSources', 'GorEffects', 'GorCapture', 'GorFit'}
models = [target for target in package['targets'] if target['name'] in model_names]
if not models:
    print('SKIP Linux SwiftPM build/test: migrated core/feature targets=0; M2 not landed. Existing executable requires macOS. No test coverage claimed.')
for model in models:
    name = model['name']
    tests = [t for t in package['targets'] if t['type'] == 'test' and t['name'] == name + 'Tests']
    assert tests, name + ' needs its own test target'
    subprocess.run(['swift', 'build', '--target', name, '-Xswiftc', '-swift-version', '-Xswiftc', '6', '-Xswiftc', '-strict-concurrency=complete', '-Xswiftc', '-warnings-as-errors'], cwd=root, check=True)
    listing = subprocess.check_output(['swift', 'test', 'list', '--filter', name + 'Tests'], cwd=root, text=True)
    count = len([line for line in listing.splitlines() if line.startswith(name + 'Tests.')])
    assert count, name + 'Tests has no discovered tests'
    subprocess.run(['swift', 'test', '--filter', name + 'Tests', '-Xswiftc', '-swift-version', '-Xswiftc', '6', '-Xswiftc', '-strict-concurrency=complete', '-Xswiftc', '-warnings-as-errors'], cwd=root, check=True)
    print(name + ': Linux tests=' + str(count))
