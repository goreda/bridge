#!/usr/bin/env python3
"""Process-boundary caller regressions. Pass built example binary explicitly."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import sys


def repin(root):
    files = sorted(p for p in root.glob('*.tsv') if p.name != 'pins.tsv')
    (root / 'pins.tsv').write_text('file\tsha256\n' + ''.join(
        p.name + '\t' + hashlib.sha256(p.read_bytes()).hexdigest() + '\n' for p in files))


def run(binary, root, out, expected=None):
    p = subprocess.run([str(binary), str(root), str(out)], capture_output=True, text=True)
    if expected is None:
        assert p.returncode == 0, p.stderr
        assert 'dataset_kind=SYNTHETIC' in p.stdout, p.stdout
    else:
        assert p.returncode != 0 and expected in p.stderr, (p.returncode, p.stdout, p.stderr)
    return p


def main():
    p = argparse.ArgumentParser()
    p.add_argument('binary', type=Path)
    p.add_argument('fixture', type=Path)
    a = p.parse_args()
    binary = a.binary.resolve()
    with tempfile.TemporaryDirectory(prefix='kern-caller-') as td:
        base = Path(td)
        def copy(name):
            dst = base / name
            shutil.copytree(a.fixture, dst)
            return dst
        root = copy('good')
        out, repeat = base / 'a', base / 'b'
        run(binary, root, out)
        run(binary, root, repeat)
        checker = Path(__file__).with_name('check_production_ledger.py')
        subprocess.run([sys.executable, str(checker), str(root), str(out), '--repeat-output', str(repeat)], check=True)
        subprocess.run([sys.executable, str(Path(__file__).with_name('check_verified_gpos.py')), str(out)], check=True)
        assert (out / 'verification.gpos').read_bytes() == (repeat / 'verification.gpos').read_bytes()
        before = {f.name: f.read_bytes() for f in out.iterdir()}
        run(binary, root, out, 'refusing overwrite')
        assert before == {f.name: f.read_bytes() for f in out.iterdir()}
        bad = copy('tampered')
        (bad / 'training_anchors.tsv').write_text((bad / 'training_anchors.tsv').read_text() + '9\t9\t1\tunauthenticated\n')
        run(binary, bad, base / 'bad-a', 'Pin: hash mismatch')
        assert not (base / 'bad-a').exists()
        bad = copy('heldout')
        manifest = bad / 'learning_source_manifest.tsv'
        manifest.write_text(manifest.read_text().replace('\tlearning\t', '\theld-out\t'))
        repin(bad)
        run(binary, bad, base / 'bad-b', 'Binding: held-out font present in calibration')
        bad = copy('revision')
        f = bad / 'evidence_bindings.tsv'
        text = f.read_text().replace('synthetic-model', 'wrong-model', 1)
        f.write_text(text)
        repin(bad)
        run(binary, bad, base / 'bad-c', 'Binding: evidence font/model/context mismatch')
        bad = copy('missing-pin')
        f = bad / 'pins.tsv'
        f.write_text('\n'.join(f.read_text().splitlines()[:-1]) + '\n')
        run(binary, bad, base / 'bad-d', 'Pin: missing')
        bad = copy('bad-row')
        f = bad / 'classes.tsv'
        f.write_text('a\tL\n')
        repin(bad)
        run(binary, bad, base / 'bad-e', 'Input: classes.tsv: invalid row width')
        bad = copy('no-walls')
        (bad / 'wall_evidence.tsv').write_text('gid\tfont_revision\tevidence\n')
        repin(bad)
        blank = base / 'abstain'
        run(binary, bad, blank)
        lines = (blank / 'verified-pairs.tsv').read_text().splitlines()
        assert len(lines) == 1, lines
        assert 'glyph lacks verified walls' in (blank / 'concrete-pairs.tsv').read_text()
    print('caller regression mechanics PASS (synthetic only)')


if __name__ == '__main__':
    main()
