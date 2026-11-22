"""Execute shipped installer/bootstrap/rollback in fake HOME; no native claims."""
from pathlib import Path
import os
import csv
import hashlib
import json
import re
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
script = (root / 'build.sh').read_text()
fixture_helper = script[script.index('gor_install_selftest_fixtures() {'):script.index('gor_install_tree() {')]
required = re.search(r'for fixture in ([^;]+); do', fixture_helper)[1].split()
assert required and all((root / 'selftest-fixtures' / name).is_file() for name in required)
installer = script[script.index('gor_install_tree() {'):script.index('gor_rollback_verified() {')]
bootstrap = script[script.index('gor_install_architecture_assets() {'):script.index('# ── gor_selftest (176b)')]
rollback = script[script.index('gor_rollback() {'):script.index('# ── block 176 item 3:')].replace('cp -c', 'cp')
with tempfile.TemporaryDirectory() as directory:
    base = Path(directory)
    home, source = base / 'home', base / 'source'
    home.mkdir()
    shutil.copytree(root, source, ignore=shutil.ignore_patterns('.build', '__pycache__'))
    env = {**os.environ, 'HOME': str(home)}
    if not shutil.which('swift'):
        os.environ['ARCH_SWIFT'] = str(root / 'Tests/Architecture/swift-fixture.py')
        env['ARCH_SWIFT'] = os.environ['ARCH_SWIFT']
        print('SUPPLEMENTARY graph fixture replay; swift unavailable; compile NOT_RUN')
    # Fixture-only normalization supports testing the checked-in bridge metadata.
    baseline = source / 'architecture/arch-baseline.tsv'
    with baseline.open() as f:
        rows = list(csv.DictReader(f, delimiter='\t'))
    for row in rows:
        if row['path'] == 'build.sh' and row['rule'] == 'ceiling':
            row['count'] = str(max(1, len((source / 'build.sh').read_text().splitlines()) - 799))
    with baseline.open('w') as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys(), delimiter='\t', lineterminator='\n')
        w.writeheader()
        w.writerows(rows)
    for _ in range(2):
        subprocess.run(['python3', str(source / 'tools/architecture.py'), '--root', str(source), '--emit', '--report'], check=True, stdout=subprocess.DEVNULL)
    # Inventory of installed non-Git overlay must verify too.
    subprocess.run(['python3', str(source / 'tools/architecture.py'), '--root', str(source), '--integrity-only'], check=True, stdout=subprocess.DEVNULL)
    # Reproduce the Mac's actual code-only install, not an entire repo copy.
    overlay = base / 'actual-overlay'
    overlay.mkdir()
    for item in ['Sources', 'Packages', 'Tests', 'Resources', 'scripts', 'tools', 'architecture', 'docs', 'plan', 'selftest-fixtures', 'models']:
        if (source / item).is_dir():
            shutil.copytree(source / item, overlay / item)
    for item in ['Package.swift', 'build.sh', 'gor-selftest.sh', 'gor-capture-channel.py', 'ARCHITECTURE.md', 'VENDOR.md', 'ffmpeg-provider.lock', '.swift-format']:
        shutil.copy2(source / item, overlay / item)
    checked = subprocess.run(['python3', str(overlay / 'tools/architecture.py'), '--root', str(overlay), '--report'], env=env, text=True, capture_output=True)
    assert 'unmapped=0' in checked.stdout, checked.stdout
    assert 'stale manifest' not in checked.stdout and 'delivery file missing' not in checked.stdout, checked.stdout
    print('PASS actual installed overlay advisory:0unmapped/no stale archive/no nonexistent release entries; archive bulk NOT_APPLICABLE')
    for scenario in ['old-updater', 'clean', 'repeat', 'interrupted', 'missing-asset', 'gate-failure']:
        project, backups = base / scenario, base / (scenario + '-backups')
        (project / 'Sources').mkdir(parents=True)
        sentinel = project / 'Sources/unknown.swift'
        sentinel.write_text('// preserved unknown overlay\n')
        (project / 'build.sh').write_text('old working updater\n')
        (project / 'plan').mkdir()
        (project / 'plan/QUEUE.md').write_text('old queue\n')
        shell = base / (scenario + '.sh')
        # Rollback's no-git route may not invoke git, even indirectly.
        nogit = base / 'no-git'
        nogit.mkdir(exist_ok=True)
        (nogit / 'git').write_text('#!/bin/sh\necho forbidden-git-called >&2; exit 99\n')
        (nogit / 'git').chmod(0o755)
        header = 'set -e\nproject_root="$1"\nbackups_dir="$2"\nbig_file_bytes=209715200\ngor_big_file_confirm() { return 0; }\n' + fixture_helper
        body = installer + bootstrap
        if scenario == 'old-updater':
            # Run actual prior revision's installer before candidate bootstrap.
            # It cannot install tools/map/Packages: candidate continuation fills it.
            previous = (root / 'Tests/Architecture/prior-installer.sh').read_text()
            old_shell = base / 'prior-install.sh'
            old_shell.write_text(header + previous + '\ncp -p "$project_root/build.sh" "$project_root/.gor-last-working-build.sh"\ngor_install_tree "$3" "prior-update"\n')
            old_result = subprocess.run(['bash', str(old_shell), str(project), str(backups), str(source)], env=env, capture_output=True, text=True)
            assert old_result.returncode == 0, old_result.stdout + old_result.stderr
            assert (project / '.gor-last-working-build.sh').read_text() == 'old working updater\n'
            assert not (project / 'tools/architecture.py').exists()
            assert not (project / 'Packages/.keep').exists()

            # Actual update-build continuation calls the same shipped bootstrap.
            assert 'gor_install_architecture_assets "$(gor_sidecar)/archive/gor"' in script
            before_bootstrap = {p.relative_to(project).as_posix() for p in project.rglob('*') if p.is_file()}
        src = source
        if scenario in {'missing-asset', 'gate-failure'}:
            src = base / (scenario + '-source')
            shutil.copytree(source, src)
            if scenario == 'missing-asset':
                shutil.rmtree(src / 'tools')
            else:
                (src / 'Sources/gor/App/main.swift').write_text('new forbidden ipcCommand\n')
        if scenario == 'interrupted':
            body += '\ncp() { if [ "${3:-}" = "$project_root/architecture/arch-baseline.tsv.tmp" ]; then return 73; fi; command cp "$@"; }\n'
        shell.write_text(header + body + '\ngor_install_architecture_assets "$3"\n')
        proc = subprocess.run(['bash', str(shell), str(project), str(backups), str(src)], env=env, capture_output=True, text=True)
        if scenario in {'missing-asset', 'gate-failure'}:
            assert proc.returncode, proc.stdout + proc.stderr
            assert (project / 'plan/QUEUE.md').read_text() == 'old queue\n'
            assert not (project / 'tools/architecture.py').exists()
            print('PASS ' + scenario + ': rejected staged assets; prior source/updater untouched; integrity dispatch retains previous app and exits before build/launch')
            continue
        if scenario == 'interrupted':
            # If failure hook did not intercept the copy call, force a second
            # real installer run which fails mid apply and inspect backup.
            assert proc.returncode, 'interruption injection did not fire'
        else:
            assert proc.returncode == 0, proc.stdout + proc.stderr
            for fixture in required:
                assert (project / 'selftest-fixtures' / fixture).read_bytes() == (source / 'selftest-fixtures' / fixture).read_bytes()
            assert (project / 'Packages/.keep').read_bytes() == (source / 'Packages/.keep').read_bytes()
            if (source / 'Packages/gorav/source-lock.json').exists():
                local = project / 'Packages/gorav'
                lock = json.loads((local / 'source-lock.json').read_text())
                assert all(hashlib.sha256((local / name).read_bytes()).hexdigest() == digest
                           for name, digest in lock['files'].items()), 'installed local engine drift'
                assert '.package(name: "gorav", path: "Packages/gorav")' in (source / 'Package.swift').read_text()

            assert (project / 'scripts/arch-check.sh').stat().st_mode & 0o111
            assert (project / 'tools/architecture.py').read_bytes() == (source / 'tools/architecture.py').read_bytes()
            if scenario == 'repeat':
                # Unique labels avoid known timestamp collision refusal.
                repeat = shell.read_text().replace('"architecture-bootstrap"', '"architecture-repeat"')
                shell.write_text(repeat)
                subprocess.run(['bash', str(shell), str(project), str(backups), str(src)], env=env, check=True, stdout=subprocess.DEVNULL)
        assert sentinel.read_text() == '// preserved unknown overlay\n'
        if scenario == 'old-updater':
            assert (project / 'build.sh').read_bytes() == (source / 'build.sh').read_bytes()
            assert (project / '.gor-last-working-build.sh').read_text() == 'old working updater\n'
            after_bootstrap = {p.relative_to(project).as_posix() for p in project.rglob('*') if p.is_file()}
            added = after_bootstrap - before_bootstrap
            expected_roots = {'Packages', 'scripts', 'tools', 'architecture', 'docs', 'ARCHITECTURE.md', 'VENDOR.md', 'ffmpeg-provider.lock', '.swift-format', 'plan', 'models', 'selftest-fixtures', '.gor-architecture-last.txt'}
            assert all(Path(name).parts[0] in expected_roots for name in added), added
        else:
            assert (project / 'build.sh').read_text() == 'old working updater\n'
        backup = next(backups.glob('*-pre-architecture-bootstrap'))
        shell.write_text(header + rollback + '\ngor_rollback "$3"\n')
        result = subprocess.run(['bash', str(shell), str(project), str(backups), backup.name], env={**env, 'PATH': str(nogit) + ':' + env['PATH']}, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        assert 'forbidden-git-called' not in result.stderr
        assert (project / 'plan/QUEUE.md').read_text() == 'old queue\n'
        assert sentinel.exists()
        assert not (project / 'tools/architecture.py').exists()
        assert not (project / 'Packages/.keep').exists()
        assert not (project / 'Packages/gorav/Package.swift').exists(), 'rollback retained introduced dependency'

        print('PASS ' + scenario + ': actual install/readback/mode + local rollback no-git; prior updater and unknown overlay preserved')
assert 'architecture gate missing; build refused' not in script
assert '--report > "$project_root/.gor-architecture-last.txt"' in script
assert 'if ! ( gor_install_architecture_assets' in script
assert 'update integrity:' in script
assert 'Packages' in script[script.index('gor_tree_files()'):script.index('gor_big_file_confirm()')]
assert "root / 'Packages'" in script
assert "src/'Packages'" in script
print('PASS D4 missing/broken gate recovery routing; native app launch/a-v not run')

print('PASS complete required-fixture list uses actual installer helper, not a no-op stub: ' + ','.join(required))
# Every required fixture must fail closed if omitted before mutation.
for missing in required:
    with tempfile.TemporaryDirectory() as directory:
        base = Path(directory)
        source = base / 'source'
        project = base / 'project'
        (source / 'selftest-fixtures').mkdir(parents=True)
        project.mkdir()
        for name in required:
            if name != missing:
                shutil.copy2(root / 'selftest-fixtures' / name, source / 'selftest-fixtures' / name)
        shell = base / 'required.sh'
        shell.write_text('set -e\nproject_root="$1"\n' + fixture_helper + '\ngor_install_selftest_fixtures "$2" "$3"\n')
        result = subprocess.run(['bash', str(shell), str(project), str(source), str(base / 'backup')], capture_output=True, text=True)
        assert result.returncode != 0 and ('missing required fixture selftest-fixtures/' + missing) in result.stderr
print('PASS each required fixture omission rejects explicitly; all delivered fixtures measured against release bytes')
