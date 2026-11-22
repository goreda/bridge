#!/usr/bin/env python3
"""Update continuation delivery-receipt gate. An older runner installs the tree and re-execs build.sh --update-build
without recording the delivery; the continuation must record it (verified) or refuse visibly before any build.
Fixed code must pass; every mutant must fail. Portable (python3 + git). Swift/native NOT_RUN."""
import json, os, re, subprocess, sys, tempfile
from pathlib import Path
R = Path(__file__).resolve().parents[2]
SRC, BUILD = (R / 'tools/gor_provenance.py').read_text(), (R / 'build.sh').read_text()
ENV = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@t')

def sh(*a, cwd=None):
    return subprocess.run(a, cwd=cwd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=ENV)

def fixture(td):
    td = Path(td); repo = td / 'repo'; g = repo / 'archive/gor'
    for rel, text in {'Package.swift': '// pkg\n', 'build.sh': 'echo hi\n', 'Sources/gor/a.swift': 'let a = 1\n',
                      'Packages/p/Sources/p.swift': 'let p = 1\n', 'tools/t.py': 'x=1\n'}.items():
        (g / rel).parent.mkdir(parents=True, exist_ok=True); (g / rel).write_text(text)
    sh('git', 'init', '-q', '-b', 'main', cwd=repo); sh('git', 'add', '-A', cwd=repo); sh('git', 'commit', '-q', '-m', 'one', cwd=repo)
    sh('git', 'update-ref', 'refs/remotes/origin/main', 'HEAD', cwd=repo)
    project = td / 'project'; sh('cp', '-Rp', str(g), str(project))
    return repo, project

def run(tool, repo, project):
    p = subprocess.run([sys.executable, str(tool), 'ensure-delivery', str(repo), str(project), 'main'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return p.returncode, p.stdout + p.stderr

def cases(src):
    res = {}
    with tempfile.TemporaryDirectory() as td:
        tool = Path(td) / 'gor_provenance.py'; tool.write_text(src)
        for name in ('old_runner_missing_receipt', 'present_receipt_kept', 'stale_receipt_rerecorded', 'byte_mismatch_refused',
                     'extra_compiled_input_refused', 'local_asset_allowed', 'bad_receipt_not_trusted', 'head_moved_refused', 'head_moved_no_receipt_refused'):
            sub = Path(td) / name; sub.mkdir(); repo, project = fixture(sub)
            rec = project / '.gor-delivery.json'
            head = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD']).decode().strip()
            if name == 'old_runner_missing_receipt':
                code, out = run(tool, repo, project)
                res[name] = code == 0 and rec.exists() and json.loads(rec.read_text())['source_commit'] == head and 'recorded' in out
            elif name == 'present_receipt_kept':
                run(tool, repo, project); before = rec.read_bytes() if rec.exists() else None; code, out = run(tool, repo, project)
                res[name] = before is not None and code == 0 and rec.read_bytes() == before and 'present and verified' in out
            elif name == 'stale_receipt_rerecorded':
                run(tool, repo, project); old = json.loads(rec.read_text()) if rec.exists() else {'version': 2}; old['source_commit'] = '0' * 40; rec.write_text(json.dumps(old) + '\n')
                code, out = run(tool, repo, project)
                res[name] = code == 0 and rec.exists() and json.loads(rec.read_text())['source_commit'] == head
            elif name == 'byte_mismatch_refused':
                (project / 'Sources/gor/a.swift').write_text('let a = 2\n'); code, out = run(tool, repo, project)
                res[name] = code != 0 and not rec.exists() and 'REFUSED' in out
            elif name == 'extra_compiled_input_refused':
                (project / 'Sources/gor/extra.swift').write_text('let e = 1\n'); code, out = run(tool, repo, project)
                res[name] = code != 0 and not rec.exists()
            elif name == 'local_asset_allowed':
                (project / 'Resources/vendor').mkdir(parents=True); (project / 'Resources/vendor/bin.dat').write_text('x'); code, out = run(tool, repo, project)
                res[name] = code == 0 and rec.exists()
            elif name == 'head_moved_refused':  # valid receipt, then one local commit; origin/main and installed bytes unchanged
                run(tool, repo, project); before = rec.read_bytes() if rec.exists() else None
                (repo / 'archive/gor/tools/t.py').write_text('x=2\n'); sh('git', 'commit', '-q', '-am', 'local', cwd=repo)
                code, out = run(tool, repo, project)
                res[name] = before is not None and code != 0 and 'REFUSED' in out and rec.read_bytes() == before
            elif name == 'head_moved_no_receipt_refused':
                (repo / 'archive/gor/tools/t.py').write_text('x=2\n'); sh('git', 'commit', '-q', '-am', 'local', cwd=repo)
                code, out = run(tool, repo, project)
                res[name] = code != 0 and not rec.exists()
            else:  # valid receipt, installed Swift then altered: refused, and the earlier receipt file is left byte-identical (no new trusted receipt)
                run(tool, repo, project); before_bad = rec.read_bytes() if rec.exists() else None; (project / 'Sources/gor/a.swift').write_text('let a = 3\n'); code, out = run(tool, repo, project)
                res[name] = code != 0 and rec.exists() and rec.read_bytes() == before_bad
    return res

def static_cases(build):
    case = build.split('    --update-build)', 1)[1].split('        shift ;;', 1)[0]
    call = re.search(r'if ! /usr/bin/python3 "\$project_root/tools/gor_provenance.py" ensure-delivery "\$\(gor_sidecar\)" "\$project_root" "\$\(gor_sidecar_branch\)"; then\n(.*?)\n        fi\n', case, re.S)
    res = {'call_present': bool(call)}
    res['refuses_visibly_exit1'] = bool(call) and 'echo ' in call.group(1) and '>&2' in call.group(1) and 'exit 1' in call.group(1)
    res['before_install_and_build'] = bool(call) and case.index('ensure-delivery') < case.index('gor_install_architecture_assets') < case.index('gor_install_selftest_fixtures')
    res['bootstrap_and_t0_kept'] = 'GOR_UPDATE_T0' in case and 'Upgrade from an older runner' in case and 'gor_install_selftest_fixtures' in case
    return res

def check(label, got, expect_red=None):
    bad = sorted(k for k, v in got.items() if v is not True)
    if expect_red is None: assert not bad, (label, bad)
    else: assert expect_red in bad, (label, 'mutant survived', bad)

check('fixed', cases(SRC)); check('fixed-static', static_cases(BUILD))
print('PASS fixed: old-runner entry records the receipt; present kept; stale re-recorded; mismatch/extra input refused with no new receipt; HEAD != origin tip refused; local assets allowed; build.sh gate refuses visibly before install/build')
# (the closed-input check is defended twice: installed-vs-tree and snapshot-vs-tree; the mutant removes both)
def mut(text, a, b):
    assert a in text, a[:60]; out = text.replace(a, b, 1); assert out != text; return out
M = {
 'no-head-check': (mut(SRC, "    if tip != head:\n        raise Refusal('sidecar HEAD is not the fetched tip of origin/' + branch)\n    try:\n        record", "    try:\n        record"), 'head_moved_refused'),
 'noop-existence-only': (mut(SRC, "    return record_delivery(repo, project, branch), True\n", "    return {'source_commit': tip, 'tree': '', 'file_count': 0}, False\n"), 'old_runner_missing_receipt'),
 'trust-existing-receipt': (mut(SRC, "        if record.get('source_commit') == tip and record.get('version') == 2:\n            tree, manifest, count, snap = verify_installed(repo, tip, project)\n            if (record.get('tree'), record.get('tree_manifest_sha256'), record.get('source_snapshot_sha256'), record.get('file_count')) == (tree, manifest, snap, count):\n                return record, False\n",
                            "        return record, False\n"), 'stale_receipt_rerecorded'),
 'no-reverify-of-present': (mut(SRC, "            tree, manifest, count, snap = verify_installed(repo, tip, project)\n            if (record.get('tree'), record.get('tree_manifest_sha256'), record.get('source_snapshot_sha256'), record.get('file_count')) == (tree, manifest, snap, count):\n                return record, False\n",
                            "            return record, False\n"), 'bad_receipt_not_trusted'),
 'receipt-written-before-verify': (mut(SRC, "    return record_delivery(repo, project, branch), True\n", "    (Path(project) / RECORD).write_text(json.dumps({'version': 2, 'source_commit': tip}) + '\\n')\n    return record_delivery(repo, project, branch), True\n"), 'byte_mismatch_refused'),
 'extra-input-ignored': (mut(mut(mut(SRC, '        retire_update_sources(repo, tip, project)', '        pass'), "    if extra:\n        raise Refusal('installed build inputs not in the delivered tree", "    if False:\n        raise Refusal('installed build inputs not in the delivered tree"), "    if set(records) != set(expected):", "    if False:"), 'extra_compiled_input_refused'),
}
for name, (src, key) in M.items(): check(name, cases(src), expect_red=key)
B = {
 'gate-removed': (re.sub(r'        # Delivery receipt gate:.*?\n        fi\n', '', BUILD, count=1, flags=re.S), 'call_present'),
 'failure-swallowed': (mut(BUILD, 'ensure-delivery "$(gor_sidecar)" "$project_root" "$(gor_sidecar_branch)"; then', 'ensure-delivery "$(gor_sidecar)" "$project_root" "$(gor_sidecar_branch)" || :; if false; then'), 'call_present'),
 'silent-exit': (mut(BUILD, "            echo 'update provenance: delivery receipt missing or unverifiable", "            : 'update provenance: delivery receipt missing or unverifiable"), 'refuses_visibly_exit1'),
}
moved = BUILD.split('        # Delivery receipt gate:', 1)
gate = '        # Delivery receipt gate:' + moved[1].split('        update_t0=', 1)[0]
late = BUILD.replace(gate, '', 1).replace('        open_app=false   # the selftest owns every launch', gate + '        open_app=false   # the selftest owns every launch', 1)
assert late != BUILD; B['gate-after-install'] = (late, 'before_install_and_build')
for name, (b, key) in B.items():
    assert b != BUILD, name; check(name, static_cases(b), expect_red=key)
print('PASS mutants: %d source/gate mutants each caught' % (len(M) + len(B)))
