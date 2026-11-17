from pathlib import Path
import hashlib, re, tempfile

PACKET = 'W-gdb-198y-1nstinct-07'
REL = 'archive/gor/Sources/gor/FileBrowser.swift'
PIN_SHA = '633b968dd7d4ecc5626b174b8a1744290e82cbd53ce28481e32d6ad18b914b67'
OLD_STATION = 'gor'
PLANNED_STATION = 'GorUI'
TYPES = ['FileBrowserPanel', 'FileEntry']
TOKENS = ['FileBrowserPanel', 'FileEntry', 'toggleSearchPanelFromKey', 'pressRandomFromKey', 'renderEntries', 'loadPath', 'nextSearchGeneration', 'isCurrentSearch', 'performSearch', 'goUp', 'goHome', 'clearSearchAndShowFolder']

DECL_RE = r'(?m)^[ \t]*(?:(?:public|private|internal|fileprivate|open|final|indirect)\s+)*(?:class|struct|enum|actor|protocol)\s+%s(?:\s*[:{]|\s|$)'
ROOT = Path(__file__).resolve().parents[5]


def decl_count(text, name):
    return len(re.findall(DECL_RE % re.escape(name), text))


def check_identity(content):
    h = hashlib.sha256(content).hexdigest()
    assert h == PIN_SHA, 'pinned source changed: rebase and review, never bless silently'


def check_declarations(content):
    s = content.decode('utf-8')
    for t in TOKENS:
        assert t in s, 'declaration boundary token missing: ' + t
    for ty in TYPES:
        n = decl_count(s, ty)
        assert n == 1, 'duplicate-type rejection (in-file): %s declared %d times' % (ty, n)


def locate(root):
    pkg = root / 'archive/gor'
    assert pkg.is_dir(), 'archive/gor package root missing'
    srcroot = pkg / 'Sources'
    base = REL.rsplit('/', 1)[1]
    matches = sorted(p for p in srcroot.rglob(base) if p.is_file()) if srcroot.is_dir() else []
    assert len(matches) == 1, 'station locator: expected exactly 1 %s under archive/gor/Sources, found %d: %s' % (
        base, len(matches), [str(m) for m in matches])
    p = matches[0]
    rel = p.relative_to(root).as_posix()
    assert rel == REL, 'station drift: %s is not the pinned row %s (planned future station %s); rebase and review, never bless silently' % (rel, REL, PLANNED_STATION)
    station = p.parent.name
    assert station == OLD_STATION and station != PLANNED_STATION, 'station locator: %s sits in target dir %s; expected old station %s (move to %s is future owner-held work)' % (base, station, OLD_STATION, PLANNED_STATION)
    return p, station


def tree_decl_files(root, name):
    hits = []
    for f in sorted((root / 'archive/gor/Sources').rglob('*.swift')):
        if f.is_file() and decl_count(f.read_bytes().decode('utf-8'), name):
            hits.append(f.relative_to(root).as_posix())
    return hits


def check_tree_duplicates(root):
    for ty in TYPES:
        hits = tree_decl_files(root, ty)
        assert hits == [REL], 'duplicate-type rejection (old/new): %s declarations at %s, expected only %s' % (ty, hits, REL)


def expect_reject(label, fn):
    try:
        fn()
    except AssertionError:
        return
    raise SystemExit('MUTANT_ACCEPTED %s: strengthened test failed to reject %s' % (label, label))


p, station = locate(ROOT)
content = p.read_bytes()
check_identity(content)
check_declarations(content)
check_tree_duplicates(ROOT)

# mutation coverage (in-memory and isolated tmp fixtures; production bytes never written)
nm = 0
expect_reject('append-bytes drift', lambda: check_identity(content + b'// mutant')); nm += 1
expect_reject('truncate drift', lambda: check_identity(content[:len(content) // 2])); nm += 1
mid = len(content) // 2
flip = content[:mid] + bytes([content[mid] ^ 0x01]) + content[mid + 1:]
expect_reject('single-byte flip drift', lambda: check_identity(flip)); nm += 1
typos = re.sub(DECL_RE % re.escape(TYPES[0]), lambda m: m.group(0).replace(TYPES[0], TYPES[0][:-1] + 'X'), content.decode('utf-8'), count=1).encode('utf-8')
assert typos != content, 'typo mutant setup failed'
expect_reject('declaration typo drift', lambda: check_declarations(typos)); nm += 1
dups = content + ('\nenum %s {}\n' % TYPES[0]).encode()
expect_reject('in-file duplicate declaration', lambda: check_declarations(dups)); nm += 1

def _fixture(kind):
    def go():
        with tempfile.TemporaryDirectory(prefix=PACKET + '-') as td:
            r = Path(td)
            old = r / 'archive/gor/Sources/gor'
            old.mkdir(parents=True)
            (old / REL.rsplit('/', 1)[1]).write_bytes(content)
            if kind == 'missing':
                (old / REL.rsplit('/', 1)[1]).unlink()
                locate(r)
            elif kind == 'new-station-dup':
                newd = r / ('archive/gor/Sources/' + PLANNED_STATION)
                newd.mkdir(parents=True)
                (newd / REL.rsplit('/', 1)[1]).write_bytes(content)
                try:
                    locate(r)
                except AssertionError:
                    raise
                else:
                    raise AssertionError('locate accepted new-station duplicate')
            elif kind == 'new-station-type-dup':
                newd = r / ('archive/gor/Sources/' + PLANNED_STATION)
                newd.mkdir(parents=True)
                (newd / 'Moved.swift').write_text('public enum %s {}\n' % TYPES[0])
                check_tree_duplicates(r)
            elif kind == 'old-station-type-dup':
                (old / 'Copy.swift').write_text('enum %s {}\n' % TYPES[0])
                check_tree_duplicates(r)
    return go

expect_reject('missing source', _fixture('missing')); nm += 1
expect_reject('new-station duplicate file', _fixture('new-station-dup')); nm += 1
expect_reject('new-station duplicate type', _fixture('new-station-type-dup')); nm += 1
expect_reject('old-station duplicate type', _fixture('old-station-type-dup')); nm += 1

print('CHARACTERIZATION_PASS %s: station %s located for %s (planned move to %s not yet applied), source identity pinned, %d boundary tokens, %d types duplicate-clean, %d mutation cases rejected; source-only, not runtime' % (
    PACKET, station, REL, PLANNED_STATION, len(TOKENS), len(TYPES), nm))
