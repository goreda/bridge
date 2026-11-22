#!/usr/bin/env python3
"""192a C2: claims_lint fixture tests, R2/R3 only. Builds a real temp git repo so
[code] tags are verified against an actual sha:path:line, then runs tools/claims_lint.py
over accepted and flagged-line fixtures and pins rc, rule codes and the UNKNOWN receipt
items. claims_lint is advisory only (never part of any gate).
Run: python3 Tests/ClaimsLint/claims_lint_test.py"""
import subprocess, sys, tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
tool = root / 'tools/claims_lint.py'

tmp = Path(tempfile.mkdtemp())
repo = tmp / 'repo'
repo.mkdir()
def git(*a):
    subprocess.run(['git', '-C', str(repo)] + list(a), check=True, capture_output=True)
git('init', '-q')
git('config', 'user.email', 'lint@test')
git('config', 'user.name', 'lint')
(repo / 'foo.swift').write_text('line one\nline two\nline three\n')
git('add', 'foo.swift')
git('commit', '-qm', 'fixture')
sha = subprocess.run(['git', '-C', str(repo), 'rev-parse', 'HEAD'], check=True, capture_output=True, text=True).stdout.strip()

fails = []
def check(name, cond, detail=''):
    if not cond:
        fails.append('%s: %s' % (name, detail))

def run(text, *extra):
    p = tmp / 'block.txt'
    p.write_text(text)
    return subprocess.run([sys.executable, str(tool), '--repo', str(repo), '--block-id', 't1', *extra, str(p)], capture_output=True, text=True)

# accepted fixtures
ok_block = """read: src1: Qin et al, TeleParallax, frontiersin.org full text; src2: owner log
Y1. the film plane holds a 20 arcmin budget [src 1]
G-a. residual bound is 0.0062 px [meas render-probe-7]
P4. the pose path was fixed [code %s:foo.swift:2] [meas mac-run-3] [owner phonemsg-99]
P5. the count is [UNKNOWN -> claims-lint-t1-probe] and ships without it
plain discussion line with no claim and no tag
""" % sha
r = run(ok_block)
check('accept-clean-rc', r.returncode == 0, r.stdout + r.stderr)

# flagged-line fixtures, one rule each (192a C2: only R2 and R3 remain)
bad = {
 'R2': 'Y2. bound comes from [src 9] which no read: line lists\n',
 'R3a': 'X1. cause seen at [code deadbeef:foo.swift:1]\n',
 'R3b': 'X1. cause seen at [code %s:foo.swift:99]\n' % sha,
 'R3c': 'X1. cause seen at [code %s:nope.swift:1]\n' % sha,
}
for name, line in bad.items():
    r = run('read: src1: a listed source\n' + line)
    check(name + '-rc1', r.returncode == 1, 'rc=%d %s' % (r.returncode, r.stdout))
    check(name + '-rule', ('FLAG L2 ' + name.rstrip('abc')) in r.stdout or (' ' + name.rstrip('abc') + ':') in r.stdout, r.stdout)

# untagged numbers, hedges and bare claim words are no longer findings (R1/R4/R5 deleted by 192a C2)
r = run('G-b. acceptance budget is 20 arcmin with no tag\n')
check('R1-gone', r.returncode == 0, r.stdout)
r = run('H1. the Off path is verified [meas mac-run-3]\n')
check('R4-gone', r.returncode == 0, r.stdout)
r = run('Y4. the tolerance should typically hold on flat screens\n')
check('R5-gone', r.returncode == 0, r.stdout)

# a flagged line becomes an UNKNOWN measurement item in the receipt; the rest still applies
receipt = tmp / 'receipt.txt'
r = run('G-c. bound from [src 7] with no read: line\nY9. this line is fine [meas m-1]\n', '--receipt-out', str(receipt))
body = receipt.read_text()
check('receipt-unknown-item', '[UNKNOWN -> claims-lint-t1-L1] flagged (R2)' in body, body)
check('receipt-only-flagged', 'L2' not in body, body)

print('PASS' if not fails else 'FAILED')
for f in fails: print('FAIL', f)
sys.exit(1 if fails else 0)
