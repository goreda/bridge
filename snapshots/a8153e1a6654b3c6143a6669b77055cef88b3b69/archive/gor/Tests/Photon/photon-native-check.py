#!/usr/bin/env python3
"""Candidate-only native checks, no CI dispatch or route changes.
Imports the existing locked-provider implementation and reuses its provisioned
source/include/library contract for EVERY Swift command. Native-owner coverage
uses the existing diagnostic evaluator, not end-to-end capture/presentation.
"""
from pathlib import Path
import atexit
import hashlib
import importlib.util
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
RECEIPT = Path('/tmp/photon-native-receipts.json')
PROVIDER_FILE = Path('/tmp/photon-native-provider.json')


def load_provider():
    spec = importlib.util.spec_from_file_location('gorav_private_provider', ROOT / 'tools/build-with-gorav-provider.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if module.PROVIDER_NAME != '7.1-full-codec' or module.DEPLOYMENT_TARGET != '13.0':
        raise RuntimeError('native check requires locked 7.1-full-codec provider and macOS 13.0 floor')
    return module


def stage_fonts():
    """Stage the repo's REAL Resources/fonts as the test resource root and
    verify the copy byte-for-byte (block 190m font repair). No substitute
    fixture: the intended layout itself is under test. Returns the staged
    root (containing fonts/) or None after printing a FAIL line."""
    src = ROOT / 'Resources' / 'fonts'
    if not src.is_dir():
        print('FAIL: intended layout Resources/fonts missing from checkout')
        return None
    payload = [p for p in src.rglob('*') if p.is_file()]
    if not payload:
        print('FAIL: intended layout Resources/fonts is empty')
        return None
    # Unique task-owned root: never delete a fixed shared path, never
    # collide with a concurrent run. Cleaned up only at this task's exit.
    stage = Path(tempfile.mkdtemp(prefix='photon-test-resources-'))
    atexit.register(lambda: shutil.rmtree(stage, ignore_errors=True))
    shutil.copytree(src, stage / 'fonts')
    for p in payload:
        q = stage / 'fonts' / p.relative_to(src)
        if not q.is_file() or hashlib.sha256(q.read_bytes()).digest() != hashlib.sha256(p.read_bytes()).digest():
            print(f'FAIL: staged copy diverges from intended layout: {p}')
            return None
    return stage


def xctest_result(text, expected):
    # Read real XCTest case results as well as its aggregate. A green command
    # with an unmatched filter, missing summaries, or any skip is NOT a pass.
    cases = re.findall(r"Test Case '([^']+)' (passed|failed|skipped)", text)
    states = dict(cases)
    passed = sum(value == 'passed' for value in states.values())
    skipped = sum(value == 'skipped' for value in states.values())
    failed = sum(value == 'failed' for value in states.values())
    summaries = re.findall(r'Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?', text)
    totals = [(int(total), int(skip or 0), int(fail)) for total, skip, fail in summaries]
    detail = {'expected': expected, 'passed': passed, 'skipped': skipped,
              'failed': failed, 'summaries': totals}
    if failed or any(fail for _, _, fail in totals):
        return 'FAIL', detail
    if skipped or any(skip for _, skip, _ in totals):
        return 'NOT_RUN', detail
    if passed != expected or not totals or max(total for total, _, _ in totals) != expected:
        return 'NOT_RUN', detail
    return 'PASS', detail


def main():
    if platform.system() != 'Darwin':
        print('NOT_RUN: macOS required')
        return 77
    # Refuse a legacy-provider override, never silently mix it into this lane.
    if os.environ.get('GORAV_PROVIDER', '7.1-full-codec') != '7.1-full-codec':
        print('FAIL: remove legacy provider override for this 7.1-only check')
        return 1
    os.environ['GORAV_PROVIDER'] = '7.1-full-codec'
    os.environ['MACOSX_DEPLOYMENT_TARGET'] = '13.0'
    if len(sys.argv) == 3 and sys.argv[1] == '--provision':
        provider = load_provider()
        source = provider.provision()
        Path(sys.argv[2]).write_text(json.dumps({'source': str(source), 'libraries': provider.LIBRARIES,
                                               'provider': provider.PROVIDER_NAME,
                                               'deployment_target': provider.DEPLOYMENT_TARGET}))
        return 0
    rows = []
    metadata = {}
    def save():
        RECEIPT.write_text(json.dumps({'provider': metadata, 'results': rows}, indent=2) + '\n')
    def invoke(name, cwd, command, timeout):
        log = Path('/tmp') / ('photon-' + name + '.log')
        with log.open('w') as out:
            try:
                code = subprocess.run(command, cwd=cwd, stdout=out, stderr=subprocess.STDOUT,
                                      env=os.environ.copy(), timeout=timeout).returncode
            except subprocess.TimeoutExpired:
                code = 124
        return code, log
    code, log = invoke('provider', ROOT, [sys.executable, str(Path(__file__).resolve()),
                                         '--provision', str(PROVIDER_FILE)], 900)
    rows.append({'step': 'provider', 'exit': code, 'log': str(log), 'status': 'PASS' if code == 0 else 'FAIL'})
    save()
    if code:
        print(log.read_text()[-6000:])
        return 1
    provider = json.loads(PROVIDER_FILE.read_text())
    metadata.update(provider)
    source = Path(provider['source'])
    # Font repair (block 190m): stage the intended Resources/fonts layout
    # BEFORE any suite runs and hand it to the test host. Without staging,
    # Bundle.main is the toolchain runner and every font lookup misses
    # (run9/run10 retry storm, ungated by selected-suite PASS).
    stage = stage_fonts()
    if stage is None:
        return 1
    os.environ['GOR_TEST_RESOURCE_ROOT'] = str(stage)
    metadata['test_resource_root'] = str(stage)
    # Exactly the current build-with-gorav-provider.py Swift argument shape.
    flags = ['-Xcc', '-I' + str(source)]
    for library in provider['libraries']:
        flags += ['-Xlinker', '-L' + str(source / library)]
    steps = [
        ('app-build', ROOT, ['swift', 'build'] + flags, None),
        ('shader-compile', ROOT / 'Packages/gorav', ['swift', 'run'] + flags + ['stereo-shader-tests'], None),
        # Resource verification runs BEFORE the feature suites: staged
        # intended layout must resolve and register the committed fonts.
        ('font-resource', ROOT, ['swift', 'test'] + flags + ['--filter', 'PhotonFontResourceTests/testStagedFontsResolveAndRegister'], 1),
        # The actual automatic startup route is a SEPARATE strict step -
        # unselected, the startup fix would exist but never execute.
        ('font-startup', ROOT, ['swift', 'test'] + flags + ['--filter', 'PhotonFontResourceTests/testAutomaticStartupSelectsStagedFont'], 1),
        ('close-lifecycle', ROOT, ['swift', 'test'] + flags + ['--filter', 'PhotonHostCloseLifecycleTests'], 5),
        ('distance-model', ROOT, ['swift', 'test'] + flags + ['--filter', 'PhotonDistanceModelNativeTests'], 4),
        ('native-owner-evaluation', ROOT, ['swift', 'test'] + flags + ['--filter', 'PhotonNativeInputOwnerTests'], 1),
        # Deliberate-missing suite LAST: its single expected registration
        # error must not pollute the strict gates of the other suites.
        ('font-fallback-bounded', ROOT, ['swift', 'test'] + flags + ['--filter', 'PhotonFontResourceTests/testMissingResourceFallsBackBounded'], 1),
    ]
    # Qualification gates (block 190m font repair): with the intended layout
    # staged, ANY font resolution/registration failure in a suite is a
    # qualification FAIL even when its XCTest cases pass (run9/run10 logged
    # 860+ errors under green suites). The deliberate-missing suite instead
    # requires the failure to stay BOUNDED: at most one registration error.
    FONT_STRICT = 'font-strict'
    FONT_BOUNDED = 'font-bounded'
    gates = {
        'font-resource': FONT_STRICT,
        'font-startup': FONT_STRICT,
        'close-lifecycle': FONT_STRICT,
        'distance-model': FONT_STRICT,
        'native-owner-evaluation': FONT_STRICT,
        'font-fallback-bounded': FONT_BOUNDED,
    }
    for name, cwd, command, count in steps:
        code, log = invoke(name, cwd, command, 900 if name == 'app-build' else 300)
        text = log.read_text()
        detail = {}
        status = 'NOT_RUN' if code == 77 else ('PASS' if code == 0 else 'FAIL')
        if code == 0 and count is not None:
            status, detail = xctest_result(text, count)
        if status == 'PASS' and gates.get(name) == FONT_STRICT:
            if '[PhotonFont] Registration error' in text or '[GORResources] fonts unavailable' in text:
                status = 'FAIL'
                detail['font_gate'] = 'unexpected font resolution/registration failure with staged resources'
        if status == 'PASS' and gates.get(name) == FONT_BOUNDED:
            if text.count('[PhotonFont] Registration error') > 1:
                status = 'FAIL'
                detail['font_gate'] = 'deliberate-missing fallback was not bounded (retry storm)'
        row = {'step': name, 'exit': code, 'status': status, 'log': str(log), **detail}
        rows.append(row)
        save()
        print(name, status, code, log, flush=True)
        if status != 'PASS':
            print(text[-6000:])
            return 77 if status == 'NOT_RUN' else 1
    # PASS here covers named commands/tests only, never native acceptance or
    # ordinary playback. The app-build entry is compile evidence alone.
    return 0


if __name__ == '__main__':
    sys.exit(main())
