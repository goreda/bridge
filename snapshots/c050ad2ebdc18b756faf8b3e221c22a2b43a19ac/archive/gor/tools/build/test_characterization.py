"""Golden routing/parser tests of shipped build.sh; no native commands run."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = (ROOT / 'build.sh').read_text()
PARSER = SCRIPT[SCRIPT.index('rollback_ts=""'):SCRIPT.index('case "$exit_log_zip"')]


class DispatchGoldens(unittest.TestCase):
    def invoke(self, args):
        with tempfile.TemporaryDirectory() as d:
            home = Path(d) / 'home'
            home.mkdir()
            shell = Path(d) / 'parser.sh'
            shell.write_text('''set -e
open_app=true; clean_build=false; create_dmg=false; signing_enabled=true
show_warnings=false; build_whisper=false; log_mode=direct
log_timestamp=true; log_cpu_info=true
emit() { printf '%s\\n' "$*"; }
gor_rollback() { emit "rollback:${1:-latest}"; }
gor_rollback_verified() { emit rollback:verified; }
gor_mark_verified() { emit verified; }
gor_print_unverified() { emit unverified; }
gor_selftest() { emit "selftest:$1"; }
''' + PARSER + '''
printf 'build=%s launch=%s clean=%s dmg=%s sign=%s warnings=%s whisper=%s log=%s timestamp=%s cpu=%s\\n' "$skip_build" "$open_app" "$clean_build" "$create_dmg" "$signing_enabled" "$show_warnings" "$build_whisper" "$log_mode" "$log_timestamp" "$log_cpu_info"
''')
            result = subprocess.run(['bash', str(shell), *args], env={**os.environ, 'HOME': str(home)}, capture_output=True, text=True)
            return result.returncode, result.stdout.strip(), result.stderr.strip()

    def test_entry_goldens(self):
        for args, expected in [(['--selftest'], 'selftest:lifetime'), (['--selftest-full'], 'selftest:full'), (['--verified'], 'verified'), (['--unverified'], 'unverified')]:
            with self.subTest(args=args):
                self.assertEqual(self.invoke(args), (0, expected, ''))
        for args, expected in [(['--rollback'], 'rollback:latest'), (['--rollback', 'fixture'], 'rollback:fixture'), (['--rollback', 'verified'], 'rollback:verified')]:
            with self.subTest(args=args):
                rc, out, err = self.invoke(args)
                self.assertEqual(rc, 0)
                self.assertEqual(out.splitlines()[0], expected)
                self.assertEqual(err, '')

    def test_flag_goldens(self):
        rc, out, err = self.invoke(['--no-build', '--no-launch', '--clean', '--dmg', '--no-sign', '--warnings', '--whisper', '--log', 'off', '--no-log-timestamp', '--no-log-cpu-info'])
        self.assertEqual((rc, out, err), (0, 'build=true launch=false clean=true dmg=true sign=false warnings=true whisper=true log=off timestamp=false cpu=false', ''))
        rc, out, _ = self.invoke(['--no-log-timestamp', '--log-timestamp', '--no-log-cpu-info', '--log-cpu-info'])
        self.assertEqual(rc, 0)
        self.assertTrue(out.endswith('timestamp=true cpu=true'))
        for mode in ['off', 'direct', 'filter', 'stream', 'broad', 'full']:
            self.assertEqual(self.invoke(['--log', mode])[0], 0)

    def test_refusal_goldens(self):
        for args, expected in [(['--unknown'], 'unknown build option: --unknown'), (['--log'], '--log needs a mode'), (['--log', 'bad'], 'unknown log mode: bad')]:
            self.assertEqual(self.invoke(args), (2, '', expected))

    def test_runner_real_dispatch_with_fake_home(self):
        prefix = SCRIPT[:SCRIPT.index('# Every Git invocation')]
        for flag, action in [('--install-runner', 'install'), ('--remove-runner', 'remove')]:
            with tempfile.TemporaryDirectory() as d:
                root = Path(d)
                (root / 'Tests/Runner').mkdir(parents=True)
                (root / 'build.sh').write_text(prefix)
                (root / 'Tests/Runner/runner.py').write_text('import sys;print("runner:"+sys.argv[1])')
                result = subprocess.run(['bash', str(root / 'build.sh'), flag], env={**os.environ, 'HOME': d}, text=True, capture_output=True)
                self.assertEqual((result.returncode, result.stdout.strip()), (0, 'runner:' + action))
                self.assertFalse((root / '.gor-build.lock').exists())

    def test_update_and_logging_dispatch(self):
        # Execute the actual dispatch body against recording substitutes. This
        # characterizes routing, not mutable-network installation or macOS UI.
        start = SCRIPT.index('case "${1:-}" in', SCRIPT.index('# block 176c dispatch'))
        end = SCRIPT.index('\nesac', start) + len('\nesac')
        dispatch = SCRIPT[start:end]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'dispatch.sh'
            path.write_text('set -e\ngor_update_run() { echo update:fetch-stage-install-reexec; }\n' + dispatch)
            result = subprocess.run(['bash', str(path), '--update'], env={**os.environ, 'HOME': d}, capture_output=True, text=True)
            self.assertEqual((result.returncode, result.stdout.strip()), (0, 'update:fetch-stage-install-reexec'))
        self.assertIn('exec /usr/bin/python3', SCRIPT[:SCRIPT.index('# Every Git invocation')])
        self.assertIn('if ! ( gor_install_architecture_assets', SCRIPT)
        self.assertIn('update integrity:', SCRIPT)
        self.assertIn('--integrity-only', SCRIPT)
        self.assertNotIn('architecture gate missing; build refused', SCRIPT)
        self.assertIn('--report > "$project_root/.gor-architecture-last.txt"', SCRIPT)

    def test_integrity_vs_advisory_goldens(self):
        start = SCRIPT.index('    if ! /usr/bin/python3 "$src_root/tools/architecture.py"')
        end = SCRIPT.index('    gor_install_tree "$src_root" "update"', start)
        guard = SCRIPT[start:end]
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'tools').mkdir()
            (root / 'tools/architecture.py').write_text('raise SystemExit(1)')
            path = root / 'guard.sh'
            path.write_text('set -e\nsrc_root="$1"\n' + guard + '\necho forbidden-install-or-launch\n')
            result = subprocess.run(['bash', str(path), d], env={**os.environ, 'HOME': d}, text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertNotIn('forbidden-install-or-launch', result.stdout)
            self.assertIn('prior source/app retained; no build or launch', result.stderr)
            self.assertEqual(sorted(p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()), ['guard.sh', 'tools/architecture.py'])
        start = SCRIPT.index('if [ -f "$project_root/scripts/arch_check.py" ]')
        end = SCRIPT.index('# ── swift build', start)
        advisory = SCRIPT[start:end]
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            path = root / 'advisory.sh'
            path.write_text('set -e\nproject_root="$1"\n' + advisory + '\necho continue-build\n')
            result = subprocess.run(['bash', str(path), d], env={**os.environ, 'HOME': d}, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0)
            self.assertIn('continue-build', result.stdout)
            self.assertIn('recoverable warning', result.stdout)
            self.assertEqual(sorted(p.name for p in root.iterdir()), ['.gor-architecture-last.txt', 'advisory.sh'])

    def test_push_and_update_project_goldens(self):
        start = SCRIPT.index('if [ "${1:-}" = "--push" ]')
        end = SCRIPT.index('# block 176c: staged snapshot')
        body = SCRIPT[start:end]
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            script = root / 'entries.sh'
            script.write_text('set -e\n' + body + '\nprintf "route:%s\\n" "$1"\n')
            env = {**os.environ, 'HOME': d}
            bad = subprocess.run(['bash', str(script), '--update-project', str(root)], env=env, capture_output=True, text=True)
            self.assertEqual((bad.returncode, bad.stdout.strip()), (1, 'invalid existing gor project'))
            (root / 'Sources/gor').mkdir(parents=True)
            (root / 'Package.swift').touch()
            (root / 'build.sh').touch()
            ok = subprocess.run(['bash', str(script), '--update-project', str(root)], env=env, capture_output=True, text=True)
            self.assertEqual((ok.returncode, ok.stdout.strip()), (0, 'route:--update'))
            helper = root / 'Downloads/gor-repo-sync/sync.sh'
            helper.parent.mkdir(parents=True)
            helper.touch()
            helper.chmod(0o755)
            push = subprocess.run(['bash', str(script), '--push'], env=env, capture_output=True, text=True)
            self.assertEqual((push.returncode, push.stdout.strip()), (0, 'source push from this Mac is disabled (block185); captures are sent by --update.'))


    def test_normal_update_has_no_3d_feature_windows(self):
        self.assertIn('if [ "$selftest_mode" = full ] && [ -f "$project_root/tools/owner_action_acceptance.py" ]; then', SCRIPT)
        self.assertIn('if [ "${GOR_UPDATE_FEATURE_EVIDENCE:-0}" = 1 ]; then', SCRIPT)
        self.assertIn('3D kabul: calistirilmadi', SCRIPT)
        self.assertIn("checks={'t1':passed('t1-build-launch'),'l1':passed('l1 '),'l2':passed('l2 '),'l3':passed('l3-normal-1x ')", SCRIPT)
        self.assertIn("'l4':all(passed('l4-'+n+' ') for n in ['l1','l2','l3-normal-1x'])}", SCRIPT)
        self.assertIn('GOR_LIFETIME_FULL=$([ "$selftest_mode" = full ] && echo 1 || echo 0)', SCRIPT)
        self.assertIn('gor_step.py" --beat $$', SCRIPT)

if __name__ == '__main__':
    unittest.main()
