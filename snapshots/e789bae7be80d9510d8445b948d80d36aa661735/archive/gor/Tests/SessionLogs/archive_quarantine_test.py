#!/usr/bin/env python3
"""A deterministic unowned-root refusal is a terminal quarantined state, not a per-launch retry.
Portable (python3 only). Fixed code must pass; every mutant must fail. Swift/native NOT_RUN.
Run: python3 Tests/SessionLogs/archive_quarantine_test.py"""
import json, os, shutil, subprocess, sys, tempfile
from pathlib import Path
R = Path(__file__).resolve().parents[2]
BUILD = (R / 'build.sh').read_text()
PATHS = (R / 'tools/session_log_paths.py').read_text()
HELPER = BUILD.split("<<'GOR_SESSION_HELPER'", 1)[1].split('\nGOR_SESSION_HELPER', 1)[0]

def tree(root):
    out = {}
    for p in sorted(Path(root).rglob('*')):
        st = p.lstat(); out[str(p.relative_to(root))] = (st.st_size, st.st_mtime_ns, p.read_bytes() if p.is_file() else None)
    return out

def setup(td, helper=HELPER, paths=PATHS):
    td = Path(td); home = td / 'home'; res = td / 'res'; res.mkdir(); home.mkdir()
    (res / 'helper.py').write_text(helper); (res / 'session_log_paths.py').write_text(paths)
    shutil.copy(R / 'tools/bounded_log_archives.py', res / 'bounded_log_archives.py')
    state = home / 'Library/Application Support/gor/log-sessions'; state.mkdir(parents=True)
    unowned = td / 'unowned' / 'gor-log-session-35850'; unowned.mkdir(parents=True)
    (unowned / 'gor_diag.log').write_text('stale session text\n'); (unowned / 'wt_full.log').write_text('more\n')
    rec = {'id': '35850-ec76957926c8870b', 'pid': 35850, 'identity': 'Mon Jan  1 00:00:00 2001', 'bundle': str(td / 'bundle'),
           'config': str(td / 'config'), 'log_root': str(unowned), 'started': 1.0}
    (state / (rec['id'] + '.json')).write_text(json.dumps(rec))
    return home, res, state, unowned, rec

def launch(home, res):
    child = subprocess.Popen(['sleep', '60'])
    try:
        env = dict(os.environ, HOME=str(home), GOR_LOG_SESSION_DIR='')
        errf = Path(home) / ('arm-stderr-%d.txt' % child.pid)
        with open(errf, 'wb') as ef:
            r = subprocess.run([sys.executable, str(res / 'helper.py'), 'arm', str(child.pid), str(home / 'b'), str(home / 'c'), str(home / 'l')],
                               env=env, stdout=subprocess.DEVNULL, stderr=ef, timeout=60)
        r.stderr = errf.read_text(errors='replace')
        return r
    finally:
        child.kill(); child.wait()

def cases(helper=HELPER, paths=PATHS):
    res = {}
    with tempfile.TemporaryDirectory() as td:
        home, rdir, state, unowned, rec = setup(td, helper, paths)
        before = tree(unowned.parent)
        r1 = launch(home, rdir)
        log1 = (state / 'archive-failures.log').read_text() if (state / 'archive-failures.log').exists() else ''
        r2 = launch(home, rdir)
        log2 = (state / 'archive-failures.log').read_text() if (state / 'archive-failures.log').exists() else ''
        qpath = state / (rec['id'] + '.quarantined')
        res['first_launch_quarantines'] = qpath.exists() and not (state / (rec['id'] + '.json')).exists() and not (state / (rec['id'] + '.collecting')).exists()
        res['one_logged_line_no_retry'] = sum(rec['id'] in l for l in log1.splitlines()) == 1 and 'QUARANTINED' in log1 and r1.stderr.count(rec['id']) == 1 and 'FAILED' not in log1
        res['second_launch_does_no_work'] = sum(rec['id'] in l for l in log2.splitlines()) == 1 and r2.stderr.count(rec['id']) == 0 and qpath.exists() and r2.returncode == 0
        res['quarantine_record_typed'] = qpath.exists() and json.loads(qpath.read_text()).get('quarantined', {}).get('error') == 'UnownedRoot'
        res['unowned_root_untouched'] = tree(unowned.parent) == before
        res['no_adoption_marker_created'] = not (unowned / '.owner').exists()
    # valid owned/transient failure keeps the bounded retry and is not quarantined
    with tempfile.TemporaryDirectory() as td:
        home, rdir, state, unowned, rec = setup(td, helper, paths)
        ns = {}; code = helper.split("if sys.argv[1]=='arm':", 1)[0]
        old_home = os.environ.get('HOME'); os.environ['HOME'] = str(home); sys.path.insert(0, str(rdir))
        try:
            for m in ('session_log_paths',): sys.modules.pop(m, None)
            exec(compile(code, 'helper', 'exec'), ns)
        finally:
            if old_home is None: os.environ.pop('HOME', None)
            else: os.environ['HOME'] = old_home
        pending = state / 'recx.json'; pending.write_text(json.dumps(dict(rec, id='recx')))
        calls = []
        seq = iter([OSError('transient'), '/tmp/out.zip'])
        def flaky(record, reason, final=True, live=False):
            calls.append(1); v = next(seq)
            if isinstance(v, Exception): raise v
            return v
        ns['archive'] = flaky; ns['time'].sleep = lambda *_: None
        ns['finish'](pending, 'next-launch-recovery')
        res['transient_error_still_retried_then_consumed'] = len(calls) == 2 and not pending.exists() and not pending.with_suffix('.quarantined').exists()
        always = []
        def failing(record, reason, final=True, live=False): always.append(1); raise OSError('io')
        pending.write_text(json.dumps(dict(rec, id='recx'))); ns['archive'] = failing
        try: ns['finish'](pending, 'next-launch-recovery'); raised = False
        except OSError: raised = True
        res['transient_exhaustion_still_raises_and_keeps_record'] = raised and len(always) == ns['FINAL_ATTEMPTS'] and pending.exists() and not pending.with_suffix('.quarantined').exists()
        sys.path.remove(str(rdir)); sys.modules.pop('session_log_paths', None)
    with tempfile.TemporaryDirectory() as td:
        home, rdir, state, unowned, rec = setup(td, helper, paths)
        a = state / (rec['id'] + '.json'); claim = a.with_suffix('.collecting'); a.rename(claim)
        ns = {}; code = helper.split("if sys.argv[1]=='arm':", 1)[0]
        old_home = os.environ.get('HOME'); os.environ['HOME'] = str(home); sys.path.insert(0, str(rdir)); sys.modules.pop('session_log_paths', None)
        try: exec(compile(code, 'helper', 'exec'), ns)
        finally:
            if old_home is None: os.environ.pop('HOME', None)
            else: os.environ['HOME'] = old_home
        calls = []
        ns['archive'] = lambda *a, **k: calls.append(1)
        ns['finish'](a, 'next-launch-recovery')  # the json is gone: another process holds the claim
        res['concurrent_claim_second_finisher_noop'] = calls == [] and claim.exists() and not a.exists()
        sys.path.remove(str(rdir)); sys.modules.pop('session_log_paths', None)
    # the typed refusal itself, with the ownership guard kept
    with tempfile.TemporaryDirectory() as td:
        home, rdir, state, unowned, rec = setup(td, helper, paths)
        import importlib.util
        spec = importlib.util.spec_from_file_location('slp_t', rdir / 'session_log_paths.py'); mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        before = tree(unowned)
        try: mod.entries(unowned, session={'started': 1.0, 'pid': 1}); ref = False; typed = False
        except OSError as e: ref = True; typed = type(e).__name__ == 'UnownedRoot'
        res['guard_refuses_typed'] = ref and typed and tree(unowned) == before
        (unowned / '.owner').write_text('gor-log-session-v1')
        res['valid_owner_still_accepted'] = mod.valid(unowned) is True
    return res

def load_ns(helper, paths, td_args):
    home, rdir, state, unowned, rec = td_args
    ns = {}; code = helper.split("if sys.argv[1]=='arm':", 1)[0]
    os.environ['HOME'] = str(home); sys.path.insert(0, str(rdir)); sys.modules.pop('session_log_paths', None)
    exec(compile(code, 'helper', 'exec'), ns)
    return ns

def write_safety_cases(helper=HELPER, paths=PATHS):
    res = {}
    old_home = os.environ.get('HOME')
    try:
        # symlinks at the old predictable temp name and at the final name are never followed
        with tempfile.TemporaryDirectory() as td:
            args = setup(td, helper, paths); home, rdir, state, unowned, rec = args
            outside = Path(td) / 'outside.txt'; outside.write_text('KEEP')
            for suffix in ('.quarantining', '.quarantined'):
                (state / (rec['id'] + suffix)).symlink_to(outside)
            before = tree(unowned.parent)
            ns = load_ns(helper, paths, args)
            pending = state / (rec['id'] + '.json')
            ns['finish'](pending, 'next-launch-recovery')
            final = state / (rec['id'] + '.quarantined')
            res['symlink_not_followed'] = outside.read_text() == 'KEEP' and not (state / (rec['id'] + '.quarantining')).read_text() == 'KEEP' if (state / (rec['id'] + '.quarantining')).exists() and not (state / (rec['id'] + '.quarantining')).is_symlink() else outside.read_text() == 'KEEP'
            res['final_is_regular_record'] = final.exists() and not final.is_symlink() and json.loads(final.read_text()).get('quarantined', {}).get('error') == 'UnownedRoot'
            res['symlink_case_root_untouched'] = tree(unowned.parent) == before
            sys.path.remove(str(rdir)); sys.modules.pop('session_log_paths', None)
        # write failures: no partial .quarantined, no leftover temp, record restored, nothing outside the metadata dir
        for point in ('fsync', 'replace'):
            with tempfile.TemporaryDirectory() as td:
                args = setup(td, helper, paths); home, rdir, state, unowned, rec = args
                outside = Path(td) / 'outside.txt'; outside.write_text('KEEP')
                before = tree(unowned.parent); outside_before = tree(td) if False else None
                ns = load_ns(helper, paths, args)
                pending = state / (rec['id'] + '.json'); osmod = ns['os']; real = getattr(osmod, point)
                def boom(*a, **k): raise OSError('injected write failure')
                setattr(osmod, point, boom)
                try:
                    try: ns['finish'](pending, 'next-launch-recovery'); raised = False
                    except OSError: raised = True
                finally: setattr(osmod, point, real)
                left = sorted(p.name for p in state.iterdir())
                res['write_failure_%s_raises_and_restores' % point] = raised and pending.exists() and not (state / (rec['id'] + '.quarantined')).exists() and not (state / (rec['id'] + '.collecting')).exists()
                res['write_failure_%s_no_partial_or_temp' % point] = not any(n.startswith('.quarantine-') or n.endswith('.quarantining') for n in left) and outside.read_text() == 'KEEP'
                res['write_failure_%s_root_untouched' % point] = tree(unowned.parent) == before
                sys.path.remove(str(rdir)); sys.modules.pop('session_log_paths', None)
    finally:
        if old_home is None: os.environ.pop('HOME', None)
        else: os.environ['HOME'] = old_home
    return res

def check(label, d, expect_red=None):
    bad = sorted(k for k, v in d.items() if v is not True)
    if expect_red is None: assert not bad, (label, bad)
    else: assert expect_red in bad, (label, 'mutant survived', bad)

if __name__ == '__main__':
    check('fixed', cases())
    check('fixed-write-safety', write_safety_cases())
    print('PASS fixed: unowned root is quarantined once, no retry on the second launch, no read/adopt/delete')
    mut = {
      'retry-permanent': (HELPER.replace("                if permanent_refusal(error):break\n", ""), PATHS, 'one_logged_line_no_retry'),
      'rescans-quarantined': (HELPER.replace("target=claim.with_suffix('.quarantined')", "target=claim.with_suffix('.json')"), PATHS, 'second_launch_does_no_work'),
      'adopt-root': (HELPER.replace("    data=json.dumps(meta).encode()\n", "    (pathlib.Path(record['log_root'])/'.owner').write_text('gor-log-session-v1')\n    data=json.dumps(meta).encode()\n"), PATHS, 'unowned_root_untouched'),
      'delete-root': (HELPER.replace("    data=json.dumps(meta).encode()\n", "    __import__('shutil').rmtree(record['log_root'])\n    data=json.dumps(meta).encode()\n"), PATHS, 'unowned_root_untouched'),
      'no-guard': (HELPER, PATHS.replace("if Path(root)!=Path('/tmp') and not valid(root):raise UnownedRoot('unowned session log directory')", "pass"), 'guard_refuses_typed'),
      'untyped-guard': (HELPER, PATHS.replace("raise UnownedRoot('unowned session log directory')", "raise OSError('unowned session log directory')"), 'guard_refuses_typed'),
      'quarantine-all-errors': (HELPER.replace("    return isinstance(error,session_log_paths.UnownedRoot)", "    return True"), PATHS, 'transient_error_still_retried_then_consumed'),
    }
    for name, (h, p, key) in mut.items():
        assert h != HELPER or p != PATHS, name + ' mutation did not apply'
        check(name, cases(h, p), expect_red=key)
    wmut = {
      'predictable-temp-write_text': (HELPER.replace("    fd,tmp=tempfile.mkstemp(prefix='.quarantine-',suffix='.tmp',dir=str(claim.parent))\n    try:\n        with os.fdopen(fd,'wb') as f:\n            f.write(data);f.flush();os.fsync(f.fileno())\n        os.replace(tmp,target)", "    tmp=claim.with_suffix('.quarantining')\n    try:\n        tmp.write_text(json.dumps(meta));os.fsync(os.open(str(tmp),os.O_RDONLY))\n        os.replace(tmp,target)"), 'symlink_not_followed'),
      'temp-left-behind': (HELPER.replace("        try:os.unlink(tmp)\n        except OSError:pass\n        raise", "        raise"), 'write_failure_replace_no_partial_or_temp'),
      'direct-final-write': (HELPER.replace("    fd,tmp=tempfile.mkstemp(prefix='.quarantine-',suffix='.tmp',dir=str(claim.parent))\n    try:\n        with os.fdopen(fd,'wb') as f:\n            f.write(data);f.flush();os.fsync(f.fileno())\n        os.replace(tmp,target)", "    tmp=target\n    try:\n        with open(tmp,'wb') as f:\n            f.write(data);f.flush();os.fsync(f.fileno())"), 'write_failure_replace_raises_and_restores'),
      'claim-dropped-before-write': (HELPER.replace("    data=json.dumps(meta).encode()\n", "    data=json.dumps(meta).encode();claim.unlink()\n").replace("    claim.unlink()\n    # One line", "    # One line"), 'write_failure_replace_raises_and_restores'),
    }
    for name, (h, key) in wmut.items():
        assert h != HELPER, name + ' mutation did not apply'
        check(name, write_safety_cases(h), expect_red=key)
    print('PASS mutants: %d each caught (retry, rescan, adopt, delete, no guard, untyped, over-broad)' % len(mut))
    print('PASS write-safety mutants: %d each caught (predictable temp, temp left behind, non-atomic write, claim dropped early)' % len(wmut))
