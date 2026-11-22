#!/usr/bin/env python3
"""Run the real bootstrap in a bare temp directory, never below a source tree.
Linux/stdlib and Python3.9-compatible. No install, build, app swap or launch.
"""
from pathlib import Path
import hashlib, json, shutil, subprocess, tempfile
ROOT = Path(__file__).resolve().parents[2]
script = (ROOT / 'build.sh').read_text()
bootstrap = script[script.index('gor_install_architecture_assets() {'):script.index('# ── gor_selftest (176b)')]

def invoke(body):
    with tempfile.TemporaryDirectory(prefix='gor-bare-bootstrap-') as tmp:
        base = Path(tmp)
        # This temp root and its ancestors must not supply an accidental helper.
        assert not any((p / 'Tests/Structure/threed_split.py').exists() for p in [base] + list(base.parents))
        source, project = base / 'source', base / 'project'
        source.mkdir(); project.mkdir()
        for d in ['Packages', 'scripts', 'tools', 'architecture', 'docs', 'selftest-fixtures', 'plan', 'models']:
            (source / d).mkdir()
        for name in ['ARCHITECTURE.md', 'VENDOR.md', 'ffmpeg-provider.lock', '.swift-format', 'scripts/arch-check.sh', 'scripts/linux-model-tests.py', 'plan/QUEUE.md']:
            (source / name).write_text('# fixture\n')
        for name in ['tools/architecture.py', 'scripts/arch_check.py', 'Tests/Structure/threed_split.py', 'Tests/Structure/section_source.py']:
            p = source / name; p.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(ROOT / name, p)
        # Five stations and a real helper-compatible manifest. The fixture is
        # compact, but the actual checker/import/helper/CLI all run unchanged.
        stations, header, order = {}, [], []
        original = ''
        for name in ['Source', 'Depth', 'Prepare', 'Render', 'Control']:
            section = 'ThreeDMenu.swift' if name == 'Control' else name + '.swift'
            text = '// BEGIN relocated ' + section + ' fixture\n// menu fixture\n// END relocated ' + section + '\n'
            rel = 'Sources/gor/Stereo/' + name + '.swift'
            p = source / rel; p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text)
            stations[name] = {'file': rel, 'header_lines': 0, 'sections': [{'name': section, 'lines': 3, 'pre_blank_lines': 0, 'sha256_after': hashlib.sha256(text.encode()).hexdigest()}]}
            order.append(section); original += text
        (source / 'Tests/Structure/threed-split-manifest.json').write_text(json.dumps({'header': header, 'stations': stations, 'order': order, 'original': {'sha256': hashlib.sha256(original.encode()).hexdigest()}}))
        ledger = source / 'Tests/MenuStructure/required-items.json'; ledger.parent.mkdir(parents=True)
        ledger.write_text(json.dumps({'required': {'fixture': ['Sources/gor/Stereo/Control.swift', '// menu fixture']}, 'orders': [], 'removals': []}))
        # Only fixture release bytes are listed, using production integrity code.
        files = sorted(p for p in source.rglob('*') if p.is_file())
        (source / 'architecture/delivery.tsv').write_text('path\tsha256\tmode\n' + ''.join(str(p.relative_to(source)) + '\t' + hashlib.sha256(p.read_bytes()).hexdigest() + '\t' + oct(p.stat().st_mode & 0o777) + '\n' for p in files))
        # Installer is the only stub. It verifies stage-vs-source ownership and
        # runs the real staged CLI again with subprocess traceback detection.
        audit = base / 'audit.py'
        audit.write_text('''from pathlib import Path
import subprocess, sys
stage, source = map(Path, sys.argv[1:])
assert (stage/'Tests/Structure/threed_split.py').is_file()
assert (stage/'Tests/Structure/section_source.py').is_file()
for rel in ['Tests/Structure/threed-split-manifest.json','Tests/MenuStructure/required-items.json','Sources/gor/Stereo/Control.swift']:
 assert (source/rel).is_file() and not (stage/rel).exists(), rel
assert not (stage/'Tests/Structure/retirements.json').exists()
p = subprocess.run([sys.executable,str(stage/'scripts/arch_check.py'),'--root',str(source),'--integrity-only'],capture_output=True,text=True)
assert 'Traceback (most recent call last)' not in p.stdout+p.stderr, p.stdout+p.stderr
assert p.returncode==0, p.stdout+p.stderr
print('BARE_STAGE_GATE_PASS')
''')
        command = '''project_root="$2"
gor_install_tree() {
 /usr/bin/python3 "$3" "$1" "$source" || exit 1
 mkdir -p "$project_root"
 cp -Rp "$1/." "$project_root/" || exit 1
}
'''.replace('"$3"', '"' + str(audit) + '"') + body + '\nsource="$1"\ngor_install_architecture_assets "$source"\n'
        result = subprocess.run(['bash', '-c', command, 'bare-bootstrap', str(source), str(project)], capture_output=True, text=True, cwd=base)
        return result

fixed = invoke(bootstrap)
assert 'Traceback (most recent call last)' not in fixed.stdout + fixed.stderr, fixed.stdout + fixed.stderr
assert fixed.returncode == 0 and 'BARE_STAGE_GATE_PASS' in fixed.stdout, fixed.stdout + fixed.stderr
print('PASS real bootstrap and staged CLI in bare temp root; staged module/source-root data separated; no subprocess traceback')
# Delete the entire new module staging stanza, replaying the actual owner fault.
a = bootstrap.index('    # The staged gate imports this code closure')
b = bootstrap.index('    /usr/bin/python3 - "$source_root" "$staged"', a)
old = invoke(bootstrap[:a] + bootstrap[b:])
assert old.returncode != 0 and 'Traceback (most recent call last)' in old.stderr and 'threed_split.py not found' in old.stderr, old.stdout + old.stderr
print('PASS omitted-helper mutant RED with original missing-module traceback, not a false-positive full-tree run')
missing_resolver=invoke(bootstrap.replace(' Tests/Structure/section_source.py; do','; do',1))
assert missing_resolver.returncode!=0 and 'section_source.py' in missing_resolver.stdout+missing_resolver.stderr,missing_resolver.stdout+missing_resolver.stderr
print('PASS omitted transitive resolver mutant RED; source-root code cannot mask incomplete staged code closure')
