# W-gdb-198y-1nstinct-13 - S1 characterization test (strengthened)
#
# Characterizes archive/gor/Sources/gor/MegaStreamManager.swift at its pinned station (GorSources) before its future move.
# Strengthening over the packet baseline: station locator, old/new duplicate-type
# rejection, and a mutation battery (byte drift, truncation, decl drop/rename/dup,
# whitespace drift, tree-level old/new duplicates).
# Source-only: reads production bytes and never writes them; runtime NOT_RUN.
# All mutation fixtures are built under temp dirs; the repo tree is untouched.
from pathlib import Path
import hashlib
import re
import tempfile

PACKET_ID = 'W-gdb-198y-1nstinct-13'
SRC_REL = 'archive/gor/Sources/gor/MegaStreamManager.swift'
STATION = 'GorSources'
PINNED_SHA256 = 'f207c003097927b7a4857c8c54337cd75fb0073ddd0e6b2a7b3cb360b384ff42'
BASELINE_TOKENS = ['LineAccumulator', 'append', 'ByteLineAccumulator', 'RelayReadyOnce', 'showMegaOSD', 'isTransferItCDN', 'streamMega', 'stopMegaRelay']
# Top-level type declarations owned by this file (kind, name). Extensions are
# additive and excluded from duplicate rejection by design.
TOPLEVEL_DECLS = {'LineAccumulator': 'class', 'ByteLineAccumulator': 'class', 'RelayReadyOnce': 'class'}

ROOT = Path(__file__).resolve().parents[5]
SOURCES_DIR = 'archive/gor/Sources'
DECL_RE = {name: re.compile(r'^(?:public\s+|final\s+|private\s+|open\s+)*' + kind + r'\s+' + name + r'\b', re.M)
           for name, kind in TOPLEVEL_DECLS.items()}


def _sha(text):
    return hashlib.sha256(text.encode()).hexdigest()


def locate_station(root):
    """Station locator: the file lives at exactly its pinned repo-relative path,
    owns its pinned station, has no same-basename shadow anywhere under Sources,
    and is not already duplicated at the future station path."""
    p = root / SRC_REL
    assert p.is_file(), f'station locator: missing pinned path {SRC_REL}'
    base = Path(SRC_REL).name
    shadow = [q for q in (root / SOURCES_DIR).rglob(base) if q != p]
    assert not shadow, f'station locator: same-basename shadow(s) at new/old station: {shadow}'
    future = root / SOURCES_DIR / STATION / base
    assert not future.exists(), f'old/new rejection: copy already present at future station {future}'
    return p.read_text()


def check_identity(text):
    assert _sha(text) == PINNED_SHA256, 'pinned source changed: rebase and review, never bless silently'


def check_declaration_boundary(text):
    for token in BASELINE_TOKENS:
        assert token in text, f'declaration boundary: token missing: {token}'
    for name, rx in DECL_RE.items():
        n = len(rx.findall(text))
        assert n == 1, f'declaration boundary: top-level {name} declared {n} times, expected exactly 1'


def check_no_duplicate_types(root):
    """Old/new duplicate-type rejection: every top-level type this file owns must
    be declared in exactly one file under Sources - this one. A copy left at the
    old path or staged at the new station fails here."""
    owners = {name: [] for name in TOPLEVEL_DECLS}
    for f in sorted((root / SOURCES_DIR).rglob('*.swift')):
        rel = f.relative_to(root).as_posix()
        try:
            text = f.read_text()
        except UnicodeDecodeError:
            continue
        for name, rx in DECL_RE.items():
            if rx.search(text):
                owners[name].append(rel)
    for name, files in owners.items():
        assert files == [SRC_REL], f'old/new duplicate-type rejection: {name} declared in {files}, expected only {SRC_REL}'


def run_all(root):
    text = locate_station(root)
    check_identity(text)
    check_declaration_boundary(text)
    check_no_duplicate_types(root)
    return text


def _make_repo(base, files):
    for rel, content in files.items():
        q = base / rel
        q.parent.mkdir(parents=True, exist_ok=True)
        q.write_text(content)


def _expect_reject(label, fn):
    try:
        fn()
    except AssertionError:
        print(f'MUTANT_REJECTED {label}')
        return
    raise SystemExit(f'MUTANT_SURVIVED {label}: check failed open')


def mutation_battery(text):
    rejected = 0
    first_decl = next(iter(TOPLEVEL_DECLS))
    first_line = next(ln for ln in text.splitlines() if DECL_RE[first_decl].match(ln))

    in_memory = [
        ('append_comment_byte_drift', text + '// mutant'),
        ('truncate_half', text[:len(text) // 2]),
        ('flip_byte_midfile', text[:len(text) // 2] + (' ' if text[len(text) // 2] != ' ' else 'x') + text[len(text) // 2 + 1:]),
        ('drop_decl_keyword', text.replace(first_line.split(first_decl)[0] + first_decl, first_line.split(first_decl)[0], 1)),
        ('rename_decl', text.replace(first_decl, first_decl + 'Moved', 1)),
        ('intra_file_duplicate_decl', text + '\n' + first_line + '\n'),
        ('whitespace_drift_trailing_space', text.replace('\n', ' \n', 1)),
    ]
    for label, mutant in in_memory:
        def combined(m=mutant):
            check_identity(m)
            check_declaration_boundary(m)
        _expect_reject(label, combined)
        rejected += 1

    base = Path(SRC_REL).name
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)

        clean = tmp / 'clean'
        _make_repo(clean, {SRC_REL: text})
        run_all(clean)  # harness self-test: an unmutated fixture must pass
        print('MUTANT_CONTROL clean_fixture_passes')

        dup_new = tmp / 'dup_new_station'
        _make_repo(dup_new, {SRC_REL: text, f'{SOURCES_DIR}/{STATION}/{base}': text})
        _expect_reject('duplicate_copy_at_new_station', lambda: run_all(dup_new))
        rejected += 1

        dup_shadow = tmp / 'dup_shadow'
        _make_repo(dup_shadow, {SRC_REL: text, f'{SOURCES_DIR}/Elsewhere/{base}': text})
        _expect_reject('same_basename_shadow_copy', lambda: run_all(dup_shadow))
        rejected += 1

        dup_type = tmp / 'dup_type'
        other = f'archive/gor/Sources/gor/{first_decl}Copy.swift'
        _make_repo(dup_type, {SRC_REL: text, other: text})
        _expect_reject('duplicate_type_second_file', lambda: run_all(dup_type))
        rejected += 1
    return rejected


def main():
    text = run_all(ROOT)
    print(f'STATION_LOCATOR {SRC_REL} station={STATION}')
    print(f'BYTE_IDENTITY sha256={_sha(text)}')
    print(f'DECLARATION_BOUNDARY {len(BASELINE_TOKENS)} tokens, {len(TOPLEVEL_DECLS)} top-level types declared exactly once')
    print('DUPLICATE_TYPE_REJECTION old/new scan clean')
    rejected = mutation_battery(text)
    print(f'MUTATION_BATTERY {rejected} mutants rejected, clean fixture passes')
    print('RUNTIME_NOT_RUN source-only characterization, no runtime execution')
    print(f'CHARACTERIZATION_PASS {PACKET_ID}: station locator, byte identity, declaration boundary, old/new duplicate-type rejection, {rejected} mutation cases rejected; source-only, not runtime')


if __name__ == '__main__':
    main()
