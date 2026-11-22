#!/usr/bin/env python3
"""Execute the production updater pre-install integrity guard on real and stale bytes.
No network, Darwin compile, app install, source replacement or launch is performed.
"""
from pathlib import Path
import csv, hashlib, io, re, subprocess, tempfile
root = Path(__file__).resolve().parents[2]
script = (root / 'build.sh').read_text()
start = script.index('    if ! /usr/bin/python3 "$src_root/tools/architecture.py" --root "$src_root" --integrity-only; then')
end = script.index('    gor_install_tree "$src_root" "update"', start)
guard = script[start:end]
assert 'manifest_tree_test.py' in guard
assert script.index('    cp -p "$project_root/build.sh"', script.index('gor_update()') if 'gor_update()' in script else 0) < start
rows = list(csv.DictReader(io.StringIO((root / 'architecture/delivery.tsv').read_text()), delimiter='\t'))
for row in rows:
    p = root / row['path']
    assert p.is_file(), row['path']
    assert hashlib.sha256(p.read_bytes()).hexdigest() == row['sha256'], row['path']

def invoke(src):
    # The exact production guard is run, with its real integrity implementation.
    # Real committed-tree check is separately executed after this test commits.
    command = 'src_root="$1"\nsync_dir="$2"\nbranch=main\n' + guard + '\nprintf "INSTALL_BOUNDARY_REACHED\\n"\n'
    return subprocess.run(['bash', '-c', command, 'updater-integrity-path', str(src), str(src.parents[1])], text=True, capture_output=True)

# Production integrity CLI against all actual release rows.
check = subprocess.run(['/usr/bin/python3', str(root/'tools/architecture.py'), '--root', str(root), '--integrity-only'], text=True, capture_output=True)
assert check.returncode == 0, check.stdout + check.stderr
print('PASS actual updater integrity CLI: all', len(rows), 'release checksums/modes match')

# A faithful compact tree exercises the same updater guard, production checker,
# menu preservation and fail-closed exit, without an app or install operation.
with tempfile.TemporaryDirectory(prefix='gor-update-integrity-') as tmp:
    repo = Path(tmp) / 'repo'; src = repo / 'archive/gor'; src.mkdir(parents=True)
    rels = {'Package.swift', 'build.sh', 'tools/gor_provenance.py', 'tools/architecture.py', 'Tests/MenuStructure/required-items.json', 'Tests/Structure/threed_split.py', 'Tests/Structure/section_source.py', 'Tests/Structure/threed-split-manifest.json', 'Sources/gor/Stereo/Source.swift', 'Sources/gor/Stereo/Depth.swift', 'Sources/gor/Stereo/Prepare.swift', 'Sources/gor/Stereo/Render.swift', 'Sources/gor/Stereo/Control.swift', 'Sources/gor/UI/SpineUI.swift', 'Sources/gor/Media/TorrentManager.swift'}
    rels.update({'Tests/HeadPose/degraded_input_audit_test.py','Tests/HeadPose/c1_projection_audit.py','Tests/HeadPose/fixtures/Pose192d.3083622.swift.txt','Tests/Architecture/c1_degraded_lookup_test.py'})
    rels.update({'Tests/Structure/core_source.py','Tests/Structure/199u-core-map.json','Sources/gor/Session/Diag.swift','Sources/gor/App/Build.swift'})
    menu = __import__('json').loads((root/'Tests/MenuStructure/required-items.json').read_text())
    rels.update(item[0] for item in menu['required'].values())
    for rel in rels:
        out=src/rel;out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes((root/rel).read_bytes());out.chmod((root/rel).stat().st_mode & 0o777)
    selected = [row for row in rows if row['path'] in rels]
    manifest=src/'architecture/delivery.tsv';manifest.parent.mkdir()
    def write_manifest(items):
        with manifest.open('w') as f:
            w=csv.DictWriter(f,fieldnames=['path','sha256','mode'],delimiter='\t',lineterminator='\n');w.writeheader();w.writerows(items)
    write_manifest(selected)
    # Exercise the newly added provenance pre-install guard against real Git,
    # rather than omitting its module or replacing verification with a stub.
    for args in [['init','-q','-b','main'],['config','user.name','Integrity Fixture'],['config','user.email','fixture@localhost'],['add','.'],['commit','-qm','Exact compact release'],['update-ref','refs/remotes/origin/main','HEAD']]:
        subprocess.run(['git','-C',str(repo),*args],check=True,capture_output=True)
    fixed=invoke(src);assert fixed.returncode==0 and 'INSTALL_BOUNDARY_REACHED' in fixed.stdout, fixed.stdout+fixed.stderr
    print('PASS exact production guard accepts current source bytes before install boundary')
    old={'Sources/gor/UI/SpineUI.swift':'d7df700d897113ef445171614822e2c9f0efcfb8e4e85e9848ce91a6bbedb20d','Sources/gor/Media/TorrentManager.swift':'7a92c6848875d63824947bbe37c08c472228f5b4f6d02698aa5e5d1bdb3f8682'}
    stale=[dict(row,sha256=old.get(row['path'],row['sha256'])) for row in selected]
    write_manifest(stale);failed=invoke(src)
    assert failed.returncode!=0 and 'INSTALL_BOUNDARY_REACHED' not in failed.stdout
    assert all('delivery checksum mismatch: '+p in failed.stdout for p in old)
    assert 'prior source/app retained; no build or launch' in failed.stderr
    print('PASS parent-tree manifest reproduces both owner mismatches and stops before install/build/launch')
    write_manifest(selected);p=src/'Sources/gor/UI/SpineUI.swift';original=p.read_bytes();p.write_bytes(original+b'\n// mutation\n')
    failed=invoke(src);assert failed.returncode!=0 and 'INSTALL_BOUNDARY_REACHED' not in failed.stdout
    print('PASS post-fix source mutation still fails closed; no integrity bypass')
    p.write_bytes(original)
    for rel in ['Tests/HeadPose/c1_projection_audit.py','Tests/HeadPose/fixtures/Pose192d.3083622.swift.txt']:
        changed=src/rel;original=changed.read_bytes();changed.write_bytes(original+b'\n')
        failed=invoke(src)
        assert failed.returncode!=0 and 'INSTALL_BOUNDARY_REACHED' not in failed.stdout
        assert 'delivery checksum mismatch: '+rel in failed.stdout,failed.stdout+failed.stderr
        assert 'prior source/app retained; no build or launch' in failed.stderr,failed.stderr
        changed.write_bytes(original)
    print('PASS C1 updater payload closure: real projection code and historical fixture mutations stop before install/build/launch')
print('PASS updater checksum regression; Darwin compile and owner installation remain separate')
