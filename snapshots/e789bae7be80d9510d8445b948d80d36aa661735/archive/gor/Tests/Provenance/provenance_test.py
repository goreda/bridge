#!/usr/bin/env python3
"""Delivered-source provenance, session binding, live refresh, archive state, engine records.
Portable (python3 + git only). Fixed code must pass; every mutant must fail. Swift/native NOT_RUN."""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
import contextlib, io, json, multiprocessing, os, re, subprocess, sys, tempfile, time, types
from pathlib import Path
R = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(R / 'tools'))
import importlib.util
_spec=importlib.util.spec_from_file_location('provenance_station_sections',R/'Tests/Structure/section_source.py')
_sections=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_sections)
def T(name):
    if name.startswith('Sources/gor/') and name.endswith('.swift'):
        if Path(name).name in {'Diag.swift','GeomTrace.swift','GORResources.swift','BuildID.swift','StableCacheKey.swift','SeededRandomNumberGenerator.swift'}:
            return _core_read(R/name)
        return _sections.section_text_exact(R,Path(name).name)
    return _core_read(R/name)
SRC, PATHS, BOUND, BUILD = T('tools/gor_provenance.py'), T('tools/session_log_paths.py'), T('tools/bounded_log_archives.py'), T('build.sh')
HELPER = BUILD.split("<<'GOR_SESSION_HELPER'", 1)[1].split('\nGOR_SESSION_HELPER', 1)[0]

def load(text, name):
    m = types.ModuleType(name); m.__file__ = str(R / 'tools' / 'x.py'); exec(compile(text, name, 'exec'), m.__dict__); return m

def sh(*a, cwd=None):
    subprocess.run(a, cwd=cwd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                   env=dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@t', GIT_COMMITTER_NAME='t', GIT_COMMITTER_EMAIL='t@t'))

def fixture(td):
    td = Path(td); repo = td / 'repo'; g = repo / 'archive/gor'
    for rel, text in {'Package.swift': '// pkg\n', 'build.sh': 'echo hi\n', 'Sources/gor/a.swift': 'let a = 1\n',
                      'Packages/p/Sources/p.swift': 'let p = 1\n', 'Resources/x.lua': 'return 1\n', 'tools/t.py': 'x=1\n'}.items():
        (g / rel).parent.mkdir(parents=True, exist_ok=True); (g / rel).write_text(text)
    (g / 'tools/t.py').chmod(0o755); (repo / 'archive/other.txt').write_text('not installed\n')
    sh('git', 'init', '-q', '-b', 'main', cwd=repo); sh('git', 'add', '-A', cwd=repo); sh('git', 'commit', '-q', '-m', 'one', cwd=repo)
    sh('git', 'update-ref', 'refs/remotes/origin/main', 'HEAD', cwd=repo)
    project = td / 'project'; sh('cp', '-Rp', str(g), str(project))
    return repo, project

def refused(mod, fn):
    try: fn(); return False
    except mod.Refusal: return True

def provenance_cases(mod):
    res = {}
    with tempfile.TemporaryDirectory() as td:
        repo, project = fixture(td)
        rec = mod.record_delivery(repo, project, 'main')
        head = subprocess.check_output(['git', '-C', str(repo), 'rev-parse', 'HEAD']).decode().strip()
        res['record'] = rec['source_commit'] == head and set(rec) >= {'tree_manifest_sha256', 'source_snapshot_sha256'} and rec['tree_manifest_sha256'] != rec['source_snapshot_sha256']
        ident = mod.identity(repo, project); res['verified'] = ident['verification'] == mod.VERIFIED
        # snapshot file bound to the tree: canonical snapshot verifies, and equals the identity digest
        snap = project.parent / 'snap.json'; snap.write_text(mod.snapshot_text(project))
        ident2 = mod.identity(repo, project, snap)
        res['snapshot_bound'] = ident2['verification'] == mod.VERIFIED and ident2['source_snapshot_sha256'] == mod.snapshot_sha256(_core_bytes(snap))
        # forged snapshot (hash edited) is refused
        forged = json.loads(_core_read(snap)); forged['Sources/gor/a.swift'] = '0' * 64; snap.write_text(json.dumps(forged, indent=2, sort_keys=True) + '\n')
        res['snapshot_forged_unverified'] = mod.identity(repo, project, snap)['verification'] == 'unverified'
        snap.write_text(mod.snapshot_text(project))
        # snapshot with an input that is not in the delivered tree
        extra_rec = json.loads(_core_read(snap)); extra_rec['Sources/gor/extra.swift'] = '1' * 64; snap.write_text(json.dumps(extra_rec, indent=2, sort_keys=True) + '\n')
        res['snapshot_extra_entry_unverified'] = mod.identity(repo, project, snap)['verification'] == 'unverified'
        snap.write_text(json.dumps(json.loads(mod.snapshot_text(project)), indent=4, sort_keys=True) + '\n')
        res['snapshot_noncanonical_unverified'] = mod.identity(repo, project, snap)['verification'] == 'unverified'
        snap.write_text(mod.snapshot_text(project))
        # installed byte change
        (project / 'Sources/gor/a.swift').write_text('let a = 2\n')
        res['byte_change_unverified'] = mod.identity(repo, project)['verification'] == 'unverified'
        res['byte_change_refused'] = refused(mod, lambda: mod.record_delivery(repo, project, 'main'))
        (project / 'Sources/gor/a.swift').write_text('let a = 1\n')
        # CLOSED SET: extra Swift or Packages file would be compiled but is not delivered
        (project / 'Sources/gor/extra.swift').write_text('let e = 1\n')
        res['extra_swift_refused'] = refused(mod, lambda: mod.verify_installed(repo, rec['source_commit'], project))
        (project / 'Sources/gor/extra.swift').unlink()
        (project / 'Packages/p/extra.txt').write_text('x'); res['extra_package_file_refused'] = refused(mod, lambda: mod.verify_installed(repo, rec['source_commit'], project))
        (project / 'Packages/p/extra.txt').unlink()
        (project / 'Packages/p/.build').mkdir(); (project / 'Packages/p/.build/junk.swift').write_text('x')
        res['build_dir_ignored'] = not refused(mod, lambda: mod.verify_installed(repo, rec['source_commit'], project))
        (project / 'models').mkdir(); (project / 'models/m.bin').write_text('m')
        res['local_asset_allowed'] = not refused(mod, lambda: mod.verify_installed(repo, rec['source_commit'], project))
        # symlink replacing a delivered file
        (project / 'Sources/gor/a.swift').unlink(); (project.parent / 'same.swift').write_text('let a = 1\n'); os.symlink(project.parent / 'same.swift', project / 'Sources/gor/a.swift')
        res['symlink_refused'] = refused(mod, lambda: mod.verify_installed(repo, rec['source_commit'], project))
        (project / 'Sources/gor/a.swift').unlink(); (project / 'Sources/gor/a.swift').write_text('let a = 1\n')
        # mode drift (exec bit)
        (project / 'tools/t.py').chmod(0o644)
        res['mode_drift_refused'] = refused(mod, lambda: mod.verify_installed(repo, rec['source_commit'], project))
        (project / 'tools/t.py').chmod(0o755)
        # missing delivered file
        (project / 'Resources/x.lua').unlink()
        res['missing_file_refused'] = refused(mod, lambda: mod.verify_installed(repo, rec['source_commit'], project))
        (project / 'Resources/x.lua').write_text('return 1\n')
        # identity line carries tree_manifest and snapshot distinctly, and the build passed in
        line = mod.identity_line(mod.identity(repo, project), build=ident['source_snapshot_sha256'])
        res['line_fields'] = ' tree_manifest=' + ident['tree_manifest_sha256'] in line and ' snapshot=' + ident['source_snapshot_sha256'] in line and line.endswith(' build=' + ident['source_snapshot_sha256'])
        # HEAD moved past fetched tip
        (repo / 'archive/gor/Resources/x.lua').write_text('return 2\n'); sh('git', 'commit', '-qam', 'two', cwd=repo)
        res['head_ne_tip_refused'] = refused(mod, lambda: mod.record_delivery(repo, project, 'main'))
        (project / mod.RECORD).write_text(json.dumps({'source_commit': 'a' * 40}))
        res['forged_commit_unverified'] = mod.identity(repo, project)['verification'] == 'unverified'
        cap = load(T('tools/gor-periodic-capture.py').replace("if __name__=='__main__':", "if False:"), 'cap')
        rd = Path(td) / 'res'; rd.mkdir(); (rd / 'gor-build-provenance.json').write_text(json.dumps({'verification': mod.VERIFIED}))
        res['flag_only_unverified'] = 'installed-build provenance=UNVERIFIED' in cap.build_evidence(rd)
        r = mod.write_provenance(project, repo, rd, snap)
        res['write_unverified'] = r['verification'] == 'unverified'
    return res

REAL_PFX = '[ts=2026-11-18T21:23:12.345Z cpu_system_pct=12.3 cpu_temp_c=unavailable cpu_temp_max_c=unavailable sample_age_s=0.4 temp_source=hid_cpu_average] '
def session_cases(paths):
    import io
    res = {}; now = time.time(); pstart = now - 600; B = 'd' * 64; T_ = 'b' * 40
    good = ('[GOR-IDENTITY] v1 verification=delivered-tree-installed-bytes source_commit=' + 'a' * 40 + ' tree=' + T_ + ' tree_manifest=' + 'c' * 64 + ' snapshot=' + B + ' build=' + B)
    sess = {'started': pstart + 3, 'proc_start': pstart, 'pid': 77, 'identity_line': good, 'build_id': B}
    def mk(pid, ep, lid='e', build=B, pfx=''):
        return (pfx + '[GOR-SESSION] pid=%d launch_epoch=%d launch_id=%s build=%s tree=%s\n' % (pid, ep, lid * 32, build, T_)).encode()
    eng = b'12:00:01.000 [GOR-ENGINE] event=open requested=gorav active=mpv origin=saved env=none saved=gorav override=none fallback=no_metal\n'
    stale = mk(77, int(pstart - 86400), 'a') + b'old session rows\n'
    other = mk(78, int(pstart), 'b') + b'other pid rows\n'
    cur = mk(77, int(pstart + 1), 'f') + b'current rows\n' + eng
    out, _ = paths.cut_named('gor_diag.log', stale + other + cur, sess)
    res['diag_cut_from_matching_marker'] = out is not None and out.split(b'\n', 1)[0].decode() == good and b'old session' not in out and b'other pid' not in out and b'current rows' in out
    res['diag_same_pid_old_launch_excluded'] = paths.cut_named('gor_diag.log', stale, sess)[0] is None
    res['diag_other_pid_excluded'] = paths.cut_named('gor_diag.log', other, sess)[0] is None
    res['diag_seed_without_marker_excluded'] = paths.cut_named('gor_diag.log', b'12:00:00.000 SEED OK lua=1\n', sess)[0] is None
    res['diag_other_build_excluded'] = paths.cut_named('gor_diag.log', mk(77, int(pstart + 1), 'f', build='9' * 64) + b'x\n', sess)[0] is None
    res['diag_unknown_build_bound_by_pid_time'] = paths.cut_named('gor_diag.log', mk(77, int(pstart + 1), 'f', build='unknown') + b'x\n', sess)[0] is not None
    # REAL direct-log transport: every runtime row carries the writer prefix; build.sh's first line has none
    px = lambda body: (REAL_PFX + body + '\n').encode()
    dcur = REAL_PFX.encode() + mk(77, int(pstart + 1), 'f') + px('runtime row one') + px('runtime row two')
    dcur = dcur.replace(b'\n[ts', b'\n[ts')
    d = good.encode() + b'\n' + px('build chatter') + mk(77, int(pstart - 86400), 'a', pfx=REAL_PFX) + px('prior session row') + mk(77, int(pstart + 1), 'f', pfx=REAL_PFX) + px('runtime row one') + px('runtime row two')
    o = paths.cut_named('gor_direct.log', d, sess)[0]
    res['direct_prefixed_marker_found'] = o is not None and b'runtime row two' in o and b'prior session row' not in o and o.split(b'\n', 1)[0] == good.encode()
    res['direct_identity_only_excluded'] = paths.cut_named('gor_direct.log', d.split(b'prior session')[0], sess)[0] is None
    # explicit direct bundle launch after a /tmp wipe: no build.sh first line at all, marker is the first row
    wiped = mk(77, int(pstart + 1), 'f', pfx=REAL_PFX) + px('runtime row one')
    o = paths.cut_named('gor_direct.log', wiped, sess)[0]
    res['direct_bundle_launch_no_first_line'] = o is not None and o.split(b'\n', 1)[0] == good.encode() and b'runtime row one' in o
    res['direct_other_buildid_excluded'] = paths.cut_named('gor_direct.log', mk(77, int(pstart + 1), 'f', build='9' * 64, pfx=REAL_PFX) + px('x'), sess)[0] is None
    res['direct_garbled_prefix_not_marker'] = paths.cut_named('gor_direct.log', b'[ts=x y z] ' + mk(77, int(pstart + 1), 'f') + b'\n', sess)[0] is None
    # marker survives trimming: bounded tail keeps the marker line, and a re-emitted marker keeps the launch start
    big = mk(77, int(pstart + 1), 'f') + (b'x' * 99 + b'\n') * 200 + b'last row\n'
    o, note = paths.cut_named('gor_diag.log', big, dict(sess, tail_limit=1000))
    res['tail_bounded_keeps_marker'] = o is not None and len(o) < 2200 and b'last row' in o and b'[GOR-SESSION] pid=77' in o and 'TAIL-BOUNDED' in note
    reem = mk(77, int(pstart + 1), 'f') + b'film one\n' + mk(77, int(pstart + 1), 'f') + b'film two\n'
    o = paths.cut_named('gor_diag.log', reem, sess)[0]
    res['reemit_does_not_shorten_cut'] = o is not None and b'film one' in o and b'film two' in o
    # bounded read, not materialization: a file bigger than several chunks is located without reading it whole
    size_ok = {'n': 0}
    class Spy(io.BytesIO):
        def read(self, n=-1):
            size_ok['n'] = max(size_ok['n'], n if n >= 0 else 10 ** 9); return super().read(n)
    payload = mk(77, int(pstart + 1), 'f') + b'tail row\n'
    bigfile = (b'y' * 99 + b'\n') * 60000 + payload
    sp = Spy(bigfile)
    got = paths.stream_cut('gor_diag.log', sp, len(bigfile), dict(sess, tail_limit=4096))
    res['read_bounded'] = got[0] is not None and size_ok['n'] <= 1024 * 1024 and b'tail row' in got[0] and len(got[0]) < 6000
    st = paths.engine_status({'gor_diag.log': cur})
    res['engine_recorded'] = 'rows=1' in st and 'requested=gorav active=mpv' in st
    res['engine_missing_typed'] = 'NOT_RECORDED' in paths.engine_status({'gor_diag.log': b'x\n'})
    res['engine_without_actual_values_not_counted'] = 'NOT_RECORDED' not in paths.engine_status({'gor_diag.log': b'12:00:01.000 [GOR-ENGINE] event=open requested=mpv active=mpv origin=menu\n'})
    res['engine_bad_value_rejected'] = 'NOT_RECORDED' in paths.engine_status({'gor_diag.log': b'12:00:01.000 [GOR-ENGINE] event=open requested=mpv active=mpv origin=menu env=A/B saved=none override=none\n'})
    return res

def helper_ns(text=HELPER):
    ns = {}; exec(compile(text.split("if sys.argv[1]=='arm':", 1)[0], 'helper', 'exec'), ns); return ns

def refresh_cases(ns):
    res = {}
    st = lambda: dict(pub_sig=None, prev=None, dirty_since=None, last_pub=0, backoff_until=0)
    s = st(); res['first_change_waits_quiet'] = ns['refresh_due'](s, ('a',), 100) is False
    res['quiet_change_refreshes'] = ns['refresh_due'](s, ('a',), 105) is True
    s = dict(st(), pub_sig=('a',), last_pub=100, prev=('a',)); res['clean_never_refreshes'] = ns['refresh_due'](s, ('a',), 500) is False
    s = dict(st(), pub_sig=('a',), last_pub=100, prev=('a',)); ns['refresh_due'](s, ('b',), 108); res['min_gap_respected'] = ns['refresh_due'](s, ('b',), 110) is False and ns['refresh_due'](s, ('b',), 135) is True
    s = dict(st(), pub_sig=('a',), last_pub=0); ns['refresh_due'](s, ('b',), 100)
    res['continuous_change_forced'] = ns['refresh_due'](s, ('c',), 105) is False and ns['refresh_due'](s, ('d',), 230) is True
    s = dict(st(), pub_sig=('a',), last_pub=0, prev=('b',), backoff_until=300); res['backoff_respected'] = ns['refresh_due'](s, ('b',), 200) is False
    return res

def publisher_cases(mod):
    res = {}
    entries = {'a.txt': b'hello'}
    def zips(p): return sorted(x.name for x in Path(p).glob('*-gor-log.zip'))
    with tempfile.TemporaryDirectory() as td:
        p = Path(td) / 'a'; p.mkdir(); (p / '.gor-log-archives-v2').mkdir()  # markerless empty (crashed first publish)
        out = mod.publish(entries, p, session='s'); res['markerless_empty_reinit'] = Path(out).exists() and _core_read(p / '.gor-log-archives-v2/.owner') == 'gor-log-archives-v2'
        p = Path(td) / 'b'; p.mkdir(); d = p / '.gor-log-archives-v2'; d.mkdir(); (d / 'unknown.dat').write_text('keep')  # partial wipe: files but no marker
        out = mod.publish(entries, p, session='s'); res['markerless_nonempty_preserved_fresh_state'] = _core_read(d / 'unknown.dat') == 'keep' and not (d / '.owner').exists() and Path(out).exists() and (p / '.gor-log-archives-v2-1/.owner').exists()
        out2 = mod.publish({'a.txt': b'again'}, p, session='s'); res['retry_same_session_one_zip'] = out2 == out and len(zips(p)) == 1
        p = Path(td) / 'c'; p.mkdir(); (Path(td) / 'victim').mkdir(); os.symlink(Path(td) / 'victim', p / '.gor-log-archives-v2')  # symlinked state is never followed
        out = mod.publish(entries, p, session='s'); res['symlink_state_skipped'] = os.listdir(Path(td) / 'victim') == [] and Path(out).exists() and (p / '.gor-log-archives-v2-1/.owner').exists()
        p = Path(td) / 'd'; p.mkdir(); d = p / '.gor-log-archives-v2'; d.mkdir(); (d / '.owner').write_text('someone else')
        out = mod.publish(entries, p, session='s'); res['foreign_marker_untouched'] = _core_read(d / '.owner') == 'someone else' and Path(out).exists()
        p = Path(td) / 'e'; p.mkdir()
        q = multiprocessing.get_context('fork').Queue()
        def worker():
            try: q.put(('ok', mod.publish(entries, p, session='same')))
            except Exception as e: q.put(('err', repr(e)))
        ps = [multiprocessing.get_context('fork').Process(target=worker) for _ in range(6)]
        [x.start() for x in ps]; [x.join(30) for x in ps]
        got = [q.get(timeout=5) for _ in ps]
        res['concurrent_first_publish'] = all(g[0] == 'ok' for g in got) and len(zips(p)) == 1 and _core_read(p / '.gor-log-archives-v2/.owner') == 'gor-log-archives-v2'
        p = Path(td) / 'f'; p.mkdir()
        for i in range(8): (p / ('.gor-log-archives-v2' + ('' if i == 0 else '-%d' % i))).mkdir(); ((p / ('.gor-log-archives-v2' + ('' if i == 0 else '-%d' % i))) / 'x').write_text('u')
        try: mod.publish(entries, p, session='s'); res['exhausted_typed_refusal'] = False
        except mod.LimitReached: res['exhausted_typed_refusal'] = True
    return res

def home_ns(home, text=HELPER):
    old = os.environ.get('HOME'); os.environ['HOME'] = str(home)
    try: return helper_ns(text)
    finally:
        if old is None: os.environ.pop('HOME', None)
        else: os.environ['HOME'] = old

def lifecycle_cases(home, text=HELPER):
    res = {}
    ns = home_ns(home, text); state_dir = ns['STATE']; os.environ['GOR_LOG_SESSION_DIR'] = str(home)
    # helper arm: real process, idempotent per pid, bound to the live process identity
    helper = Path(home) / 'helper.py'; helper.write_text(text)
    child = subprocess.Popen(['sleep', '60'])
    try:
        env = dict(os.environ, HOME=str(home), GOR_LOG_SESSION_DIR=str(home)); args = [sys.executable, str(helper), 'arm', str(child.pid), str(home / 'bundle'), str(home / 'config'), str(home / 'logs')]
        r1 = subprocess.run(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        r2 = subprocess.run(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        recs = list(state_dir.glob('*.json'))
        res['arm_idempotent_one_record'] = r1.returncode == 0 and r2.returncode == 0 and len(recs) == 1 and json.loads(_core_read(recs[0]))['pid'] == child.pid and bool(json.loads(_core_read(recs[0])).get('identity'))
        # arm for a dead pid refuses visibly (helper failing is a typed exit, never a silent record)
        dead = subprocess.Popen(['true']); dead.wait()
        r3 = subprocess.run([sys.executable, str(helper), 'arm', str(dead.pid), str(home / 'b'), str(home / 'c'), str(home / 'l')], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        res['arm_dead_pid_refused'] = r3.returncode != 0 and len(list(state_dir.glob('*.json'))) == 1
        r4 = subprocess.run([sys.executable, str(helper), 'bogus'], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        res['unknown_mode_typed_exit'] = r4.returncode != 0
    finally:
        child.kill(); child.wait()
    # quit path: finish() retries a bounded number of times, reports every failure, keeps the pending record
    pending = state_dir / 'rec.json'; pending.write_text(json.dumps({'id': 'rec', 'pid': 1, 'identity': 'x', 'bundle': 'b', 'config': 'c', 'started': 1}))
    calls = []
    def failing(record, reason, final=True, live=False): calls.append(reason); raise OSError('injected archive failure')
    ns['archive'] = failing; ns['time'].sleep = lambda *_: None
    try: ns['finish'](pending, 'owner-process-exited'); raised = False
    except OSError: raised = True
    log = _core_read(state_dir / 'archive-failures.log') if (state_dir / 'archive-failures.log').exists() else ''
    res['finish_bounded_retry_visible'] = raised and len(calls) == ns['FINAL_ATTEMPTS'] and log.count('[GOR-ARCHIVE] FAILED') == ns['FINAL_ATTEMPTS'] and pending.exists()
    seq = iter([OSError('first'), '/tmp/out.zip'])
    def flaky(record, reason, final=True, live=False):
        v = next(seq)
        if isinstance(v, Exception): raise v
        return v
    ns['archive'] = flaky; ns['finish'](pending, 'owner-process-exited')
    res['finish_retry_succeeds_consumes_record'] = not pending.exists() and not pending.with_suffix('.collecting').exists()
    # same-process new film: after a publish the next log growth triggers another refresh, no exit needed
    s = dict(pub_sig=None, prev=None, dirty_since=None, last_pub=-100, backoff_until=0)
    due = ns['refresh_due']
    ok = due(s, ('film1',), 10) is False and due(s, ('film1',), 15) is True
    s.update(pub_sig=('film1',), last_pub=15, dirty_since=None)
    ok = ok and due(s, ('film1',), 60) is False and due(s, ('film2',), 70) is False and due(s, ('film2',), 75) is True
    res['new_film_refreshes_without_exit'] = ok
    os.environ.pop('GOR_LOG_SESSION_DIR', None)
    res['worst_case_bound_documented'] = ns['DIRTY_MAX'] == 120 and ns['REFRESH_MIN_GAP'] == 30
    return res

def static_cases():
    res = {}
    res['pre_verify_before_install'] = BUILD.index('GOR_PRE_PROVENANCE') < BUILD.index('gor_install_tree "$src_root" "update"')
    res['post_bind_stops'] = bool(re.search(r'record-delivery "\$sync_dir" "\$project_root" "\$branch"; then\n[^\n]*\n\s*exit 1', BUILD))
    res['direct_first_line'] = 'gor_provenance.py" identity-line' in BUILD and '> "$GOR_LOG_SESSION_DIR/gor_direct.log"\ngor_mark handover' in BUILD
    res['no_mutable_head_tree'] = 'rev-parse HEAD:archive/gor' not in BUILD
    res['rollback_kept'] = 'gor_rollback()' in BUILD and 'gor_backup_write' in BUILD
    res['single_snapshot_impl'] = "<<'PY_SOURCE'" not in BUILD and 'gor_provenance.py" snapshot' in BUILD
    res['collector_uses_build_id'] = "_row.startswith('commit=')" in BUILD
    res['live_no_sampler'] = "if not final and not live:" in BUILD and "archive(record,'live-refresh',final=False,live=True)" in BUILD
    res['final_kept'] = "finish(pending,'owner-process-exited')" in BUILD and "'next-launch-recovery'" in BUILD
    app = T('Sources/gor/App/AppDelegate.swift'); diag = T('Sources/gor/GorCore/Diag.swift')
    body = app.split('private func openEmbedded(', 1)[1].split('    private func ', 1)[0]
    res['gorav_only_arms_collector'] = 'armStartupExitLogCollector(configDir:' in body
    res['marker_carries_build_tree'] = 'GorSessionMarker.write(build: BuildID.value(), tree: BuildID.tree())' in app and 'build=\\(build) tree=\\(tree)' in diag
    res['engine_record_actual_values'] = 'engineSelectionInputs.env' in app and 'engineSelectionInputs.override' in app and 'GorSessionMarker.reemit()' in diag
    res['no_menu_disable_hunk'] = 'validateMenuItem' not in diag and '.isEnabled' not in diag
    res['failure_visible_bounded'] = 'FINAL_ATTEMPTS' in BUILD and "[GOR-ARCHIVE] FAILED" in BUILD and "MAX_LIVE_FAILURES" in BUILD
    return res

def all_green(label, d):
    bad = [k for k, v in d.items() if v is not True]
    assert not bad, (label, bad)

all_green('provenance', provenance_cases(load(SRC, 'prov')))
all_green('session', session_cases(load(PATHS, 'paths')))
all_green('refresh', refresh_cases(helper_ns()))
all_green('publisher', publisher_cases(load(BOUND, 'bound')))
with tempfile.TemporaryDirectory() as _h: all_green('lifecycle', lifecycle_cases(Path(_h)))
all_green('static', static_cases())

def survives(text, a, b, runner, loader, name):
    pairs = a if isinstance(a, list) else [(a, b)]
    for x, y in pairs:
        assert x in text, (name, x[:50]); text = text.replace(x, y, 1)
    try: got = runner(loader(text, 'mut'))
    except Exception: return False
    return all(v is True for v in got.values())

M = []
def mut(group, text, a, b): M.append((group, text, a, b))
G = SRC
mut('prov', G, [("blob_id(target.read_bytes()) != blob \\\n                    or", "False \\\n                    or"), ("    bind_snapshot(repo, files, records)\n", "")], None)
mut('prov', G, [("if target.is_symlink() or not target.is_file() or blob_id", "if not target.is_file() or blob_id"), ("        if path.is_symlink() or not path.is_file():\n            raise Refusal('non-regular", "        if not path.is_file():\n            raise Refusal('non-regular")], None)
mut('prov', G, "or bool(target.stat().st_mode & 0o100) != (modes[path] == '100755')", "")
mut('prov', G, [("    if extra:\n        raise", "    if False:\n        raise"), ("    if set(records) != set(expected):", "    if False:")], None)
mut('prov', G, "    bind_snapshot(repo, files, records)\n", "")
mut('prov', G, "    if set(records) != set(expected):", "    if False:")
mut('prov', G, "        if hashlib.sha256(blobs[blob]).hexdigest() != records[path]:", "        if False:")
mut('prov', G, "    if tip != head:", "    if False:")
mut('prov', G, "tree, manifest, count, snap = verify_installed(repo, commit, project, records)", "tree, manifest, count, snap = ('t' * 40, 'm' * 64, 1, 's' * 64)")
mut('prov', G, "out = {'verification': 'unverified', 'reason'", "out = {'verification': VERIFIED, 'source_commit': 'a'*40, 'tree': 'b'*40, 'tree_manifest_sha256': 'c'*64, 'source_snapshot_sha256': 'd'*64, 'reason'")
mut('prov', G, "    snap = snapshot_sha256(json.dumps(records, indent=2, sort_keys=True) + '\\n')", "    snap = manifest_sha256(files)")
mut('prov', G, "        if snapshot_file and snapshot_sha256(Path(snapshot_file).read_bytes()) != snap:\n            raise Refusal('snapshot file bytes are not the canonical snapshot')\n", "")
P_ = PATHS
mut('sess', P_, "int(m.group(1))==int(pid) and abs(int(m.group(2))-anchor)<=tol", "int(m.group(1))==int(pid)")
mut('sess', P_, "int(m.group(1))==int(pid) and abs(int(m.group(2))-anchor)<=tol", "abs(int(m.group(2))-anchor)<=tol")
mut('sess', P_, "return bool(want) and got!='unknown' and got!=want", "return False")
mut('sess', P_, " if header:body=header.encode()+b'\\n'+body", " pass")
mut('sess', P_, "_PFX=rb'(?:\\[(?:[A-Za-z_]+=[^\\s\\]]*)(?: [A-Za-z_]+=[^\\s\\]]*)*\\] )?'", "_PFX=rb''")
mut('sess', P_, "   elif m.group(3)==L:start=lo+m.start();first=m.groups()", "   elif m.group(3)==L:pass")
mut('sess', P_, "  lo=max(0,hi-_CHUNK);f.seek(lo)", "  lo=0;f.seek(lo)")
mut('sess', P_, "return head+tail,' TAIL-BOUNDED", "return tail,' TAIL-BOUNDED")
mut('sess', P_, "if where is None:return None,'EXCLUDED '+name", "if False:return None,'EXCLUDED '+name")
mut('sess', P_, "if not rows:return 'ENGINE-RECORD NOT_RECORDED", "if False:return 'ENGINE-RECORD NOT_RECORDED")
mut('sess', P_, "(?: env=[a-z0-9_-]{1,16} saved=[a-z0-9_-]{1,16} override=[a-z0-9_-]{1,16})?", "(?: env=\\S+ saved=\\S+ override=\\S+)?")
H = HELPER
mut('refresh', H, "if cur==state['pub_sig']:state['dirty_since']=None;state['prev']=cur;return False", "")
mut('refresh', H, "now-state['last_pub']>=REFRESH_MIN_GAP and (quiet or", "(quiet or")
mut('refresh', H, "(quiet or now-state['dirty_since']>=DIRTY_MAX)", "quiet")
mut('refresh', H, "if now<state['backoff_until']:state['prev']=cur;return False", "")
mut('refresh', H, "now-state['last_pub']>=REFRESH_MIN_GAP and", "")
mut('life', H, "for attempt in range(1,FINAL_ATTEMPTS+1):", "for attempt in range(1,2):")
mut('life', H, "                if permanent_refusal(error):break\n                report_failure(record,reason,error,attempt)", "                if permanent_refusal(error):break")
mut('life', H, "    except Exception:\n        if claim.exists():claim.rename(path)\n        raise", "    except Exception:\n        raise")
B_ = BOUND
# (the wrong-marker guard is defense in depth: removing it alone is behavior-equivalent, so it has no mutant)
mut('pub', B_, "            break # non-empty without a marker: unproven, never adopted", "            _claim_empty(candidate)\n            return candidate")
mut('pub', B_, "            if candidate.is_symlink():break\n", "")
# (os.link vs os.replace for the marker differs only under a race with a foreign marker; no deterministic mutant)
mut('pub', B_, "            if all(e.startswith('.owner-') for e in entries):", "            if False:")
mut('pub', B_, "    for i in range(tries):\n        candidate=parent/(BASE if i==0 else BASE+'-%d'%i)", "    for i in range(1):\n        candidate=parent/BASE")
def _life(text):
    with tempfile.TemporaryDirectory() as h: return lifecycle_cases(Path(h), text)
runners = {'prov': (provenance_cases, load), 'sess': (session_cases, load), 'refresh': (lambda m: refresh_cases(m), lambda t, n: helper_ns(t)), 'pub': (publisher_cases, load), 'life': (_life, lambda t, n: t)}
for group, text, a, b in M:
    run, ld = runners[group]
    if survives(text, a, b, run, ld, group): raise AssertionError(('SURVIVED', group, a[:70]))
print('PASS provenance+session+refresh+publisher: fixed GREEN; %d mutants RED; Swift/native NOT_RUN' % len(M))
