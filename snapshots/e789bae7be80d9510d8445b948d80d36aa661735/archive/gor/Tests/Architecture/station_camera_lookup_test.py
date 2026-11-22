#!/usr/bin/env python3
"""Portable 199u camera lookup witness. No Swift compilation is implied.

Copies source into a scratch tree, concatenates camera units under original
filename MARKs, and checks exact adapter output before/after the move. The
old literal-path behavior must fail on that same scratch layout.
"""
from pathlib import Path
import importlib.util
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def adapter(root):
    file = root / 'Tests/Architecture/camera_source.py'
    spec = importlib.util.spec_from_file_location('camera_lookup_fixture', file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


current = adapter(ROOT)
units = sorted((ROOT / 'Sources/gor/Camera').glob('*.swift'))
units.append(ROOT / 'Sources/gor/GorCore/BuildID.swift')
logical = [str(file.relative_to(ROOT)) for file in units]
logical += ['Sources/gor/GorCaptureModel/ScreenCaptureEngine.swift']
expected = {name: current.read_source(ROOT / name) for name in logical}
with tempfile.TemporaryDirectory(prefix='station-camera-') as directory:
    scratch = Path(directory)
    shutil.copytree(ROOT / 'Sources', scratch / 'Sources')
    for name in ('Tests/Architecture/camera_source.py',
                 'Tests/Architecture/camera-s3-map.json',
                 'Tests/Structure/section_source.py',
                 'Tests/Structure/core_source.py',
                 'Tests/Structure/199u-core-map.json'):
        target = scratch / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, target)
    merged = scratch / 'Sources/gor/ScratchStation/Merged.swift'
    merged.parent.mkdir()
    text = ''
    for original in units:
        copy = scratch / original.relative_to(ROOT)
        unit = original.name
        host = current._sections.section_file(scratch,unit)
        body = current._sections.section_text_exact(scratch,unit)
        text += '// MARK: - ' + unit + '\n' + expected[str(original.relative_to(ROOT))]
        if not text.endswith('\n'):
            text += '\n'
        if host == copy:
            host.unlink()  # Private scratch source only.
        else:
            marker = '// MARK: - ' + unit + '\n'
            content = host.read_text()
            assert content.count(marker + body) == 1
            host.write_text(content.replace(marker + body,'',1))
    merged.write_text(text)
    moved = adapter(scratch)
    actual_lookup = moved._station_read
    moved._station_read = lambda path, *args, **kwargs: Path(path).read_text()
    red = 0
    for name in logical:
        try:
            moved.read_source(scratch / name)
        except FileNotFoundError:
            red += 1
    assert red == len(logical), (red, len(logical))
    print('PASS seed RED: literal-path lookup fails after concat for', red, 'units')
    moved._station_read = actual_lookup
    for name in logical:
        actual = moved.read_source(scratch / name)
        assert actual == expected[name], (name, 'reconstructed source changed')
    print('PASS moved GREEN:', len(logical), 'adapter outputs remain byte-identical')
    for name in ('Pose192d.swift', 'PoseMeasurementValidity.swift', 'BuildID.swift'):
        output = moved.materialize(scratch / 'Sources/gor/retired' / name,
                                   scratch / ('fixture-' + name))
        assert output.is_file() and 'import Foundation' in output.read_text()
    print('PASS compiler inputs materialize from MARK units, not retired paths')
    # Runtime and Sensing stay separate files in the target map, so their
    # internal guarded imports are not lifted. Exercise only planned merges.
    lift_names={'HeadPose.swift','Pose192d.swift','PoseFrameQuality.swift',
                'PoseMeasurementValidity.swift','BinocularGaze.swift',
                'BlinkEpisodes.swift','BuildID.swift'}
    lifted_lines=[];unit=None
    for line in text.splitlines(keepends=True):
        if line.startswith('// MARK: - ') and line.rstrip().endswith('.swift'):
            unit=line[len('// MARK: - '):].strip()
        if not (unit in lift_names and line.startswith('import ')):
            lifted_lines.append(line)
    merged.write_text(''.join(lifted_lines))
    lifted = adapter(scratch)
    for name in logical:
        assert lifted.read_source(scratch / name) == expected[name], (name,'import-lift reconstruction changed')
    print('PASS planned-merge import-lift GREEN: Camera/Core unit imports restored; Runtime/Sensing unchanged')
for name in logical:
    assert current.read_source(ROOT / name) == expected[name], name
print('PASS current GREEN; Swift/Darwin/gorTests NOT_RUN')
