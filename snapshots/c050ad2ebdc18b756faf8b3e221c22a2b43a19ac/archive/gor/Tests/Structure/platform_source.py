"""Test-only exact Platform source views using the existing MARK resolver.

Only the recorded unconditional imports are restored. Original UTF-8 unit bytes
are hash-checked. This is not a second lookup or an app/build dependency.
Other sources retain the previously installed Subtitles and Core source-view behavior.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import tempfile

ROOT = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location('platform_station_sections', ROOT / 'Tests/Structure/section_source.py')
_sections = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_sections)
_NAMES = {'QuitChildKiller.swift', 'OverlaySpaceGate.swift', 'PanelFocus.swift', 'PanelFocusTraversal.swift'}
_compile_directory = None


def _unconditional_imports(text):
    imports = set()
    depth = 0
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith('#endif'):
            depth -= 1
        if depth == 0 and line.startswith('import '):
            imports.add(line)
        if stripped.startswith('#if '):
            depth += 1
        if depth < 0:
            raise ValueError('Platform carrier conditional nesting changed')
    if depth:
        raise ValueError('Platform carrier conditional nesting changed')
    return imports


def unit_text(name, root=ROOT):
    root = Path(root)
    name = Path(name).name
    meta = json.loads((root / 'Tests/Structure/199u-platform-map.json').read_text())
    if name not in _NAMES or name not in meta['sections']:
        raise KeyError('not a Platform source unit: ' + name)
    record = meta['sections'][name]
    carrier = _sections.section_file(root, name)
    text = _sections.section_text_exact(root, name)
    digest = hashlib.sha256(text.encode()).hexdigest()
    carrier_text = carrier.read_text()
    if not any(_sections.UNIT_MARK.match(line) for line in carrier_text.splitlines()):
        if digest != record['source_sha256']:
            raise ValueError('Platform standalone source changed: ' + name)
        return text
    required = set(meta['hosts'][record['host']]['imports'])
    if not required <= _unconditional_imports(carrier_text):
        raise ValueError('Platform carrier import union changed: ' + name)
    if digest != record['body_sha256']:
        raise ValueError('Platform unit body changed: ' + name)
    lines = text.splitlines(keepends=True)
    for item in record['lifted_import_lines']:
        lines.insert(item['line'] - 1, item['text'])
    restored = ''.join(lines)
    if hashlib.sha256(restored.encode()).hexdigest() != record['source_sha256']:
        raise ValueError('Platform import reconstruction changed: ' + name)
    return restored


def _is_unit(path):
    try:
        path.relative_to(ROOT / 'Sources/gor')
    except ValueError:
        return False
    return path.name in _NAMES


def _core():
    spec = importlib.util.spec_from_file_location('platform_prior_core_view', ROOT / 'Tests/Structure/subtitles_source.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_source(path, *args, **kwargs):
    path = Path(path)
    if not _is_unit(path):
        return _core().read_source(path, *args, **kwargs)
    encoding = kwargs.get('encoding', args[0] if args else 'utf-8')
    if encoding not in (None, 'utf-8', 'utf8'):
        raise ValueError('Platform source is UTF-8')
    return unit_text(path.name)


def read_bytes(path):
    path = Path(path)
    return unit_text(path.name).encode() if _is_unit(path) else _core().read_bytes(path)


def materialize(path, destination):
    destination = Path(destination)
    destination.write_text(read_source(path))
    return destination


def compile_input(path):
    """A real compiler input with the exact original unit, never the AppKit host.

    TemporaryDirectory owns cleanup at process exit. Fixture assertion/program
    strings are unchanged. No SDK substitutes or production collaborators added.
    """
    global _compile_directory
    path = Path(path)
    if not _is_unit(path):
        raise ValueError('not a Platform compiler source input: ' + str(path))
    if _compile_directory is None:
        _compile_directory = tempfile.TemporaryDirectory(prefix='platform-source-input-')
    return materialize(path, Path(_compile_directory.name) / path.name)
