#!/usr/bin/env python3
"""199u symbol consumer lookup and compile-input assembly witness.

Subprocess calls are intercepted to collect Swift input text only. This does
not compile Swift, execute its runtime assertions or accept their negative
controls. Actual Swift/Darwin acceptance remains a separate required run.
"""
from pathlib import Path
import contextlib
import importlib.util
import io
import runpy
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ('Tests/BlinkRoute/current_route.py',
           'Tests/Harness/ScreenCamera/subtitle_face_watchdog_test.py',
           'Tests/DisplayHeadroom/run.py',
           'Tests/LiveCaptionDiagnostics/run.py')
MARKERS = ('enum BlinkCommandRoute {', 'enum CaptureConsumerRules {',
           'final class VR180Controller {', 'struct EyeGestureCommands {',
           'private final class SubtitleFaceWatchdog',
           'private func sampleSubtitleFaces()', 'enum DisplayHeadroomDiag {',
           'final class AppDelegate:', 'final class LiveCaptionController {',
           'enum DepthCacheBudget {', 'enum SHA256Pure {')


def helper(root):
    spec = importlib.util.spec_from_file_location('symbol_station_fixture',
                                                root / 'Tests/Structure/section_source.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def compiler_inputs(root):
    captured = []
    real_run = subprocess.run

    def collect(args, *unused, **kwargs):
        args = [str(arg) for arg in args]
        if '-o' in args:
            sources = [Path(arg) for arg in args if arg.endswith('.swift')]
            assert sources, args
            captured.append('\n'.join(path.read_text() for path in sources))
            return subprocess.CompletedProcess(args, 0)
        # Only permit the exact binaries requested by these fixture scripts.
        assert len(args) == 1 and Path(args[0]).name in {'test', 'bad', 'control-test', 'run'}, args
        return subprocess.CompletedProcess(args, 1 if Path(args[0]).name == 'bad' else 0)

    try:
        subprocess.run = collect
        with contextlib.redirect_stdout(io.StringIO()):
            for relative in SCRIPTS:
                runpy.run_path(str(root / relative), run_name='station_source_assembly')
    finally:
        subprocess.run = real_run
    assert len(captured) == 6, len(captured)
    return captured


sections = helper(ROOT)
expected = compiler_inputs(ROOT)
with tempfile.TemporaryDirectory(prefix='station-symbol-') as directory:
    scratch = Path(directory)
    shutil.copytree(ROOT / 'Sources', scratch / 'Sources')
    for relative in (*SCRIPTS, 'Tests/Structure/section_source.py'):
        target = scratch / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / relative, target)
    units = set()
    for marker in MARKERS:
        hits = [path for path in sections.swift_files(ROOT) if marker in path.read_text()]
        assert len(hits) == 1, (marker, hits)
        units.add(hits[0].relative_to(ROOT))
    carrier = scratch / 'Sources/gor/ScratchStation/Symbols.swift'
    carrier.parent.mkdir()
    merged = ''
    sentinel = 'enum StationTailSentinel { static let value = 199 }\n'
    old_watchdog_tail = None
    for relative in sorted(units):
        path = scratch / relative
        text = path.read_text()
        if 'private final class SubtitleFaceWatchdog' in text:
            text += '\n' + sentinel
            old_watchdog_tail = text[text.index('private final class SubtitleFaceWatchdog'):]
        merged += '// MARK: - ' + path.name + '\n' + text
        if not merged.endswith('\n'):
            merged += '\n'
        path.unlink()  # Only a temporary scratch copy.
    carrier.write_text(merged)
    # Literal source consumers cannot keep using the removed locations.
    missing = sum(not (scratch / relative).exists() for relative in units)
    assert missing == len(units) and missing >= 4, (missing, len(units))
    assert old_watchdog_tail is not None and sentinel.strip() in old_watchdog_tail
    bounded = helper(scratch).symbol_text(scratch, 'SubtitleFaceWatchdog', kind='class')
    assert sentinel.strip() not in bounded
    print('PASS seed RED: literal paths absent for', missing, 'units; tail-to-EOF includes canary')
    actual = compiler_inputs(scratch)
    assert actual == expected, 'Swift compiler input text changed after station concatenation'
    print('PASS moved GREEN: 6 real harness compile-input groups remain identical; class tail is bounded')
print('PASS current source assembly GREEN; Swift compilation/runtime/negative controls NOT_RUN')
