"""Supplementary C1 declaration probe, not an AppKit SDK typecheck.
Extract direct view member names, preserving type/extension ownership, then let
Swift reject property/zero-argument method and duplicate method collisions.
Method bodies and unrelated framework types cannot hide these diagnostics.
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os, re, subprocess, tempfile

def members(sources):
    result, parents = {}, {}
    # Remove comments and strings before brace counting, including shader literals.
    strip = r'//[^\n]*|/\*[\s\S]*?\*/|"""[\s\S]*?"""|"(?:\\.|[^"\\])*"'
    token = re.compile(r'\b(class|struct|enum|extension)\s+(\w+)([^{}]*?)\{|\b(var|let)\s+(\w+)|\bfunc\s+(\w+)\s*\(\s*\)|[{}]')
    for source in sources:
        text = re.sub(strip, '', source)
        stack = []
        for match in token.finditer(text):
            kind, owner, suffix, prop, name, method = match.groups()
            if kind:
                stack.append(owner)
                result.setdefault(owner, [])
                base = re.search(r':\s*(\w+)', suffix)
                if base: parents[owner] = base[1]
            elif match.group() == '{': stack.append(None)
            elif match.group() == '}':
                if stack: stack.pop()
            elif stack and stack[-1]:
                # Static and instance members may legally share a base name.
                prefix = text[max(text.rfind('\n', 0, match.start()), text.rfind(';', 0, match.start()), text.rfind('{', 0, match.start())) + 1:match.start()]
                static = bool(re.search(r'\b(static|class)\s*$', prefix))
                result[stack[-1]].append((name or method, bool(prop), static))
    views = {'NSView', 'NSControl', 'NSButton', 'NSStackView', 'NSTextField', 'NSScrollView', 'NSTableView', 'NSOutlineView', 'NSVisualEffectView'}
    while True:
        expanded = views | {name for name, base in parents.items() if base in views}
        if expanded == views: break
        views = expanded
    return {name: declarations for name, declarations in result.items() if name in views}

def probe(declarations, swiftc):
    with tempfile.TemporaryDirectory() as folder:
        p = Path(folder) / 'view-names.swift'
        p.write_text('\n'.join('class ' + owner + ' {\n' + '\n'.join(
            ('static ' if static else '') + ('var ' + name + ': Int { 0 }' if prop else 'func ' + name + '() {}')
            for name, prop, static in values) + '\n}' for owner, values in declarations.items()))
        return subprocess.run([swiftc, '-typecheck', str(p)], capture_output=True, text=True)

def run():
    root = Path(__file__).resolve().parents[2]
    swiftc = os.environ.get('SWIFTC', 'swiftc')
    sources = [p.read_text() for p in (root / 'Sources/gor').glob('*.swift')]
    declarations = members(sources)
    assert 'ThreeDCornerTuneView' in declarations
    good = probe(declarations, swiftc)
    assert good.returncode == 0, good.stderr
    for mutant in ['private var layout: Int { 0 }; override func layout() {}',
                   'override func layout() {}; override func layout() {}']:
        bad = probe(members(['class Collision: NSView { ' + mutant + ' }']), swiftc)
        assert bad.returncode != 0 and 'invalid redeclaration' in bad.stderr, bad.stderr
    old = (lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDCornerTune.swift'+' '):_b.index('// END relocated '+'ThreeDCornerTune.swift'+'\n')])((_threed_split().path(root)).read_text()).replace('cornerLayout', 'layout')
    bad = probe(members([old]), swiftc)
    assert bad.returncode != 0 and 'invalid redeclaration' in bad.stderr, bad.stderr
    extension = members(['class ExtensionProbe: NSView { var layout: Int { 0 } }', 'extension ExtensionProbe { func layout() {} }'])
    assert probe(extension, swiftc).returncode != 0
    print('PASS C1 view member names: %d view types, production rename mutant + duplicate override + extension collision rejected by Swift' % len(declarations))

if __name__ == '__main__': run()
