#!/usr/bin/env python3
"""Engine-wide literal inventory generator (W2-5 wave tooling, item 9).

Faithful Python port of the canonical scanner
`metrics/tests/kern_scope_guard.rs::scan_literals` with per-occurrence line
tracking. Parity acceptance: reproduces every (file, literal) count in the
committed fixture `metrics/tests/fixtures/kern-scope-literals.tsv`.

Emits one row per literal occurrence: crate, file, line, literal.
Trivial literals {0, 1, 0.0, 1.0} are emitted (typed downstream), never
silently dropped.

Usage:
  literal_inventory.py scan ENGINE_ROOT OUT.tsv     # 7 crates, */src only
  literal_inventory.py parity ENGINE_ROOT           # kern-scope fixture check
"""
import sys, os, csv
from bisect import bisect_right

SUFFIXES = ["usize","isize","u128","i128","u64","i64","u32","i32","u16","i16","u8","i8","f64","f32"]
TRIVIAL = {"0", "1", "0.0", "1.0"}
CFG_TEST = "#[cfg(test)]"
CRATES = ["core", "metrics", "learning", "pipeline", "master", "geometry-prototypes", "guide-binding"]


def normalize(tok):
    t = tok.replace("_", "").lower()
    ishex = t.startswith(("0x", "0b", "0o"))
    for s in SUFFIXES:
        if ishex and s in ("f32", "f64"):
            continue
        if len(t) > len(s) and t.endswith(s):
            t = t[: -len(s)]
            break
    return t


def is_ident(c):
    return c.isalnum() or c == "_"


def scan_literals(src):
    """Port of kern_scope_guard.rs::scan_literals. Returns [(line, normalized_literal)]."""
    b = src
    n = len(b)
    nl = [i for i, ch in enumerate(b) if ch == "\n"]

    def line_at(pos):
        return bisect_right(nl, pos) + 1

    out = []
    i = 0
    pending_test = False
    test_depth = 0
    while i < n:
        c = b[i]
        nx = b[i + 1] if i + 1 < n else "\0"
        if c == "/" and nx == "/":
            while i < n and b[i] != "\n":
                i += 1
            continue
        if c == "/" and nx == "*":
            depth = 1
            i += 2
            while i < n and depth > 0:
                if b[i] == "/" and i + 1 < n and b[i + 1] == "*":
                    depth += 1
                    i += 2
                elif b[i] == "*" and i + 1 < n and b[i + 1] == "/":
                    depth -= 1
                    i += 2
                else:
                    i += 1
            continue
        prev_ident = i > 0 and is_ident(b[i - 1])
        # raw strings: r"..", r#".."#, br".."
        if not prev_ident and (c == "r" or (c == "b" and nx == "r")):
            j = i + (2 if c == "b" else 1)
            hashes = 0
            while j < n and b[j] == "#":
                hashes += 1
                j += 1
            if j < n and b[j] == '"':
                j += 1
                while True:
                    if j >= n:
                        break
                    if b[j] == '"':
                        k = 0
                        while k < hashes and j + 1 + k < n and b[j + 1 + k] == "#":
                            k += 1
                        if k == hashes:
                            j += 1 + hashes
                            break
                    j += 1
                i = j
                continue
        if c == '"' or (not prev_ident and c == "b" and nx == '"'):
            i += 2 if c == "b" else 1
            while i < n and b[i] != '"':
                i += 2 if b[i] == "\\" else 1
            i += 1
            continue
        if c == "'" or (not prev_ident and c == "b" and nx == "'"):
            s = i + 1 if c == "b" else i
            if s + 1 < n and b[s + 1] == "\\":
                j = s + 2
                while j < n and b[j] != "'":
                    j += 1
                i = j + 1
                continue
            if s + 2 < n and b[s + 2] == "'":
                i = s + 3
                continue
            i = s + 1  # lifetime or label
            continue
        if c == "#" and b[i : i + len(CFG_TEST)] == CFG_TEST:
            pending_test = True
            i += len(CFG_TEST)
            continue
        if c == "{":
            if pending_test:
                pending_test = False
                test_depth = 1
            elif test_depth > 0:
                test_depth += 1
            i += 1
            continue
        if c == "}":
            if test_depth > 0:
                test_depth -= 1
            i += 1
            continue
        if c == ";" and pending_test:
            pending_test = False
            i += 1
            continue
        if c.isalpha() or c == "_":
            while i < n and is_ident(b[i]):
                i += 1
            continue
        if c.isascii() and c.isdigit():
            start = i
            radix_prefix = c == "0" and nx in ("x", "b", "o")
            if radix_prefix:
                i += 2
                while i < n and is_ident(b[i]):
                    i += 1
            else:
                while i < n and (b[i].isdigit() or b[i] == "_"):
                    i += 1
                if i + 1 < n and b[i] == "." and b[i + 1].isdigit():
                    i += 1
                    while i < n and (b[i].isdigit() or b[i] == "_"):
                        i += 1
                if i < n and b[i] in ("e", "E"):
                    a = b[i + 1] if i + 1 < n else "\0"
                    a2 = b[i + 2] if i + 2 < n else "\0"
                    if a.isdigit() or (a in ("+", "-") and a2.isdigit()):
                        i += 2
                        while i < n and (b[i].isdigit() or b[i] == "_"):
                            i += 1
                while i < n and is_ident(b[i]):
                    i += 1
            tuple_index = start > 0 and b[start - 1] == "." and not (start > 1 and b[start - 2] == ".")
            if not tuple_index and test_depth == 0 and not pending_test:
                out.append((line_at(start), normalize(b[start:i])))
            continue
        i += 1
    return out


def counted(src):
    from collections import Counter
    c = Counter()
    for _, lit in scan_literals(src):
        if lit in TRIVIAL:
            continue
        c[lit] += 1
    return c


def cmd_parity(root):
    """Check the port against the committed kern-scope fixture. Exit 1 on mismatch."""
    fixture = os.path.join(root, "metrics/tests/fixtures/kern-scope-literals.tsv")
    scope, rows = [], {}
    with open(fixture) as f:
        for line in f:
            if not line.strip() or line.startswith("#"):
                continue
            c = line.rstrip("\n").split("\t")
            if c[0] == "scope":
                scope.append(c[1])
            elif c[0] == "lit":
                rows[(c[1], c[2])] = int(c[3])
    problems = []
    seen = set()
    for rel in scope:
        src = open(os.path.join(root, rel), encoding="utf-8").read()
        for lit, cnt in counted(src).items():
            key = (rel, lit)
            if key not in rows:
                problems.append(f"NEW literal {lit} x{cnt} in {rel}")
            elif rows[key] != cnt:
                problems.append(f"COUNT {lit} in {rel}: fixture {rows[key]} found {cnt}")
            else:
                seen.add(key)
    for key in rows:
        if key not in seen:
            problems.append(f"STALE row {key[1]} in {key[0]}")
    if problems:
        print(f"PARITY MISMATCHES: {len(problems)}", file=sys.stderr)
        for p in problems:
            print(p, file=sys.stderr)
        return 1
    print(f"PARITY OK: {len(rows)} fixture rows reproduced with 0 mismatches")
    return 0


def cmd_scan(root, out_path):
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        w.writerow(["crate", "file", "line", "literal"])
        total = 0
        for crate in CRATES:
            srcdir = os.path.join(root, crate, "src")
            for fn in sorted(os.listdir(srcdir)):
                if not fn.endswith(".rs"):
                    continue
                rel = f"{crate}/src/{fn}"
                src = open(os.path.join(srcdir, fn), encoding="utf-8").read()
                for line, lit in scan_literals(src):
                    w.writerow([crate, rel, line, lit])
                    total += 1
    print(f"{total} occurrences -> {out_path}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    if sys.argv[1] == "scan":
        sys.exit(cmd_scan(sys.argv[2], sys.argv[3]))
    if sys.argv[1] == "parity":
        sys.exit(cmd_parity(sys.argv[2]))
    print(__doc__)
    sys.exit(2)
