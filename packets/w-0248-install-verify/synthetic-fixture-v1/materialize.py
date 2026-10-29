"""Materialize a runnable copy of the W-0248 synthetic fixture.

Usage: python3 materialize.py --dest DIR [--variant A1 .. A9]

Copies fixture-package/ and qualified-root/ into DIR, rewrites the
__FIXTURE_ROOT__ placeholder to DIR/qualified-root, then overlays the
requested variant's files (variant.json describes the defect, the
invocation and the expected outcome). Without --variant you get the
happy-path pair. This script is fixture tooling only; it is not the
product installer under test.
"""
import argparse, json, pathlib, shutil, sys

HERE = pathlib.Path(__file__).resolve().parent

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dest', required=True)
    ap.add_argument('--variant', default=None)
    a = ap.parse_args()
    dest = pathlib.Path(a.dest).resolve()
    if dest.exists():
        sys.exit('dest exists: %s' % dest)
    shutil.copytree(HERE / 'fixture-package', dest / 'fixture-package')
    shutil.copytree(HERE / 'qualified-root', dest / 'qualified-root', symlinks=True)
    root = dest / 'qualified-root'
    ready = root / 'KNI-READY.json'
    ready.write_text(ready.read_text().replace('__FIXTURE_ROOT__', str(root)))
    if a.variant:
        hits = sorted((HERE / 'variants').glob(a.variant + '*'))
        if len(hits) != 1:
            sys.exit('variant must match exactly one of: ' + ', '.join(sorted(p.name for p in (HERE / 'variants').iterdir())))
        vdir = hits[0]
        meta = json.loads((vdir / 'variant.json').read_text())
        base = dest / ('fixture-package' if meta['applies_to'] == 'fixture-package' else 'qualified-root')
        for rel in meta['overlay']:
            src = vdir / rel
            dst = base / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
            if rel == 'INSTALL-RECEIPT.json':
                r = json.loads(dst.read_text()); r['kit'] = str(root)
                dst.write_text(json.dumps(r) + '\n')
        print('variant', meta['id'], 'applied:', meta['title'])
        print('expected:', json.dumps(meta['expected'], sort_keys=True))
    print('package:', dest / 'fixture-package')
    print('kit root:', root)

if __name__ == '__main__':
    main()
