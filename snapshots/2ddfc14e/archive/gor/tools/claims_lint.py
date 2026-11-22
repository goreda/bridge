#!/usr/bin/env python3
"""192a C2 claims lint: advisory-only check for architect blocks (owner block 192a,
2026-11-10). Runs only as advisory on architect blocks: one summary line, never
fail/hold. It is not part of any build, delivery, update or receipt gate; C1 is a
compile gate only.

Lints an architect block, design, commit message, receipt or owner-message draft
for the 191z P1 evidence classes. Every factual claim should carry one P1 tag:

  [code <sha>:<path>:<line>]     code read this session at that sha
  [src <n>]                      a source listed under a "read:" line of the same document
  [meas <test-id>]               a measurement with committed output
  [owner <time/id>]              the owner's own words
  [UNKNOWN -> <test-id>]         not known; the settling test is named

Advisory findings (192a C2: only R2 and R3 remain), per line:
  R2  [src n] whose n is not listed under any "read:" line of the document
  R3  [code sha:path:line] that does not resolve in --repo (sha missing, path missing, or line out of range)

Lines starting with "read:" list evidence. Tags are stripped before scanning.

Exit: 0 clean, 1 findings, 2 usage/config error. With --receipt-out, each flagged
line is also appended as an UNKNOWN measurement item:
  [UNKNOWN -> claims-lint-<block-id>-L<n>] flagged (<rule>): <line>

Usage: claims_lint.py [--repo GIT_DIR] [--block-id ID] [--receipt-out FILE] [FILE ...]
Input defaults to stdin. --repo defaults to the containing git work tree; it must hold the
shas that [code] tags cite (for goreda/instinct work, the repo root).
"""
import argparse, os, re, subprocess, sys

TAG = re.compile(r'\[(?:code\s+[^\]]+|src\s*\d+|meas\s+[^\]]+|owner\s+[^\]]+|UNKNOWN\s*->\s*[^\]]+)\]')
CODE_TAG = re.compile(r'\[code\s+([0-9a-fA-F]{7,40}):([^:\]\s]+):(\d+)\]')
SRC_TAG = re.compile(r'\[src\s*(\d+)\]')
SRC_LIST = re.compile(r'\bsrc\s*(\d+)\s*[:.)]')


def code_claim_ok(repo, sha, path, line_no):
    def git(*args, **kw):
        return subprocess.run(['git', '-C', repo] + list(args), capture_output=True, text=True, **kw)
    if git('cat-file', '-e', sha + '^{commit}').returncode != 0:
        return False, 'sha not a commit in repo'
    if git('cat-file', '-e', '%s:%s' % (sha, path)).returncode != 0:
        return False, 'path absent at sha'
    n = int(line_no)
    if n < 1:
        return False, 'line < 1'
    out = git('show', '%s:%s' % (sha, path))
    if out.returncode != 0:
        return False, 'path unreadable at sha'
    if n > len(out.stdout.splitlines()):
        return False, 'line past end of file'
    return True, ''


def lint(text, repo, block_id):
    lines = text.splitlines()
    listed_srcs = set()
    for line in lines:
        if line.lstrip().lower().startswith('read:'):
            listed_srcs.update(SRC_LIST.findall(line))
    rejections = []
    for idx, line in enumerate(lines, 1):
        for m in SRC_TAG.finditer(line):
            if m.group(1) not in listed_srcs:
                rejections.append((idx, 'R2', '[src %s] not listed under any read: line' % m.group(1)))
        for m in CODE_TAG.finditer(line):
            ok, why = code_claim_ok(repo, m.group(1), m.group(2), m.group(3))
            if not ok:
                rejections.append((idx, 'R3', '[code %s:%s:%s] does not resolve (%s)' % (m.group(1), m.group(2), m.group(3), why)))
    return rejections


def main(argv):
    ap = argparse.ArgumentParser(description='192a C2 advisory claims lint (R2/R3 only); see module docstring')
    ap.add_argument('files', nargs='*')
    ap.add_argument('--repo', default=None)
    ap.add_argument('--block-id', default='block')
    ap.add_argument('--receipt-out', default=None)
    a = ap.parse_args(argv)
    repo = a.repo
    if repo is None:
        r = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True)
        if r.returncode != 0:
            print('claims_lint: no --repo and not inside a git work tree', file=sys.stderr)
            return 2
        repo = r.stdout.strip()
    text = ''
    if a.files:
        for f in a.files:
            with open(f, encoding='utf-8') as h:
                text += h.read() + '\n'
    else:
        text = sys.stdin.read()
    rejections = lint(text, repo, a.block_id)
    for idx, rule, why in rejections:
        line = text.splitlines()[idx - 1]
        print('FLAG L%d %s: %s | %s' % (idx, rule, why, line.strip()[:200]))
    if rejections:
        items = ['[UNKNOWN -> claims-lint-%s-L%d] flagged (%s): %s' % (a.block_id, idx, rule, text.splitlines()[idx - 1].strip()[:200]) for idx, rule, _ in rejections]
        if a.receipt_out:
            with open(a.receipt_out, 'a', encoding='utf-8') as h:
                for it in items:
                    h.write(it + '\n')
        print('claims_lint: %d advisory finding(s) (R2/R3 only); never fails a gate' % len(rejections))
        return 1
    print('claims_lint: PASS (no R2/R3 findings)')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
