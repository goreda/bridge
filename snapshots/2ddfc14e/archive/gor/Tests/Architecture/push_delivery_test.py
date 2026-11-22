#!/usr/bin/env python3
"""Exercise the real pre-push validator against committed good/stale/non-HEAD refs."""
from pathlib import Path
import csv, hashlib, subprocess, tempfile, json
validator = Path(__file__).resolve().parents[2] / 'tools/verify-push-delivery.py'
with tempfile.TemporaryDirectory() as d:
    root = Path(d)
    p = root / 'archive/gor'
    (p / 'architecture').mkdir(parents=True)
    (p / 'Sources/gor').mkdir(parents=True)
    def git(*args):
        return subprocess.check_output(['git', '-C', d, *args], stderr=subprocess.DEVNULL).decode().strip()
    git('init', '-q'); git('config', 'user.email', 'fixture@example.invalid'); git('config', 'user.name', 'Fixture')
    (p / 'build.sh').write_text('true\n')
    (p / 'Package.swift').write_text('// fixture\n')
    source = p / 'Sources/gor/Fixture.swift'; source.write_text('// good\n')
    def emit():
        with (p / 'architecture/delivery.tsv').open('w') as f:
            w = csv.writer(f, delimiter='\t', lineterminator='\n'); w.writerow(['path', 'sha256', 'mode'])
            for name in ['build.sh', 'Package.swift', 'Sources/gor/Fixture.swift']:
                w.writerow([name, hashlib.sha256((p / name).read_bytes()).hexdigest(), '0o644'])
    def commit():
        git('add', '.'); git('commit', '-qm', 'fixture'); return git('rev-parse', 'HEAD')
    def verify(ref, good):
        result = subprocess.run(['python3', str(validator), ref], cwd=d, capture_output=True, text=True)
        assert (result.returncode == 0) == good, result.stdout + result.stderr
    emit(); initial = commit()
    (p / 'architecture/freeze-195y.json').write_text(json.dumps({'rules':'195y-r4','commit':initial,'files':{'Sources/gor/Fixture.swift':[1,git('rev-parse',initial+':archive/gor/Sources/gor/Fixture.swift')]}}))
    emit(); good = commit(); verify(good, True)
    source.write_text('// changed\n'); stale = commit(); verify(stale, False)
    emit(); fixed = commit(); verify(fixed, True); verify(stale, False)
    (p / 'Sources/New.swift').write_text('// unlisted\n'); missing = commit(); verify(missing, False)
    # Git passes the actual pushed SHA: good HEAD cannot hide a stale non-HEAD ref.
    git('checkout', '-q', fixed)
    run = subprocess.run(['python3', str(validator)], cwd=d, input=f'refs/heads/stale {stale} refs/heads/delivery {good}\n', capture_output=True, text=True)
    assert run.returncode != 0
print('PASS real push guard: good, stale checksum, repaired, unlisted file, non-HEAD ref')
