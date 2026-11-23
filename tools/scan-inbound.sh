#!/bin/sh
# scan-inbound.sh v3.2 — 199da item 5 inbound scanner (agent/model-addressed instruction text).
# Blocks text addressed to agents/models: system/assistant-style warnings, instructions to
# delete, skip checks, or hide/suppress/avoid-raising output. Deps: sh + python3 stdlib only.
#
# Modes (both require explicit --policy and --repo-id; there is no implicit HEAD):
#   scan-inbound.sh --push-gate OLD NEW --policy REF|NO_EXEMPTIONS --repo-id instinct|gorav|bridge [--repo-root R]
#       Enumerate complete path+status+mode+blob metadata for OLD..NEW FROM GIT
#       (never from patch text) and scan the full resulting blob of every changed
#       regular file. Symlinks, gitlinks, binary, invalid-UTF-8 and oversize results
#       are HELD. Receipts bind full resolved OLD/NEW/policy commit IDs and the full
#       scanner sha256.
#   scan-inbound.sh --pre-apply MANIFEST PAYLOAD_ROOT --policy REF|NO_EXEMPTIONS --repo-id instinct|gorav|bridge [--repo-root R]
#       Scan a safely materialized payload against the caller's complete operation
#       manifest (op<TAB>path<TAB>mode<TAB>sha256 per line; op in ADD/MODIFY/DELETE;
#       renames are DELETE+ADD pairs; DELETE rows use '-' for mode/sha256; a declared
#       symlink is mode 120000 with '-'). The scanner independently hashes every
#       payload file and refuses content not listed in the manifest. Payload root
#       must be a real directory (never a symlink); .git components are rejected at
#       any depth; FIFOs are refused before read; devices/sockets are HELD; manifest
#       and paths must be strict UTF-8 with no control characters. Runs BEFORE
#       overlay/index construction.
#
# --repo-id selects the pinned per-repo canonical protected entry points and policy
# path from the map in these bytes (instinct: archive/gor/tools/..., gorav/bridge:
# tools/...). The caller cannot name paths; exact canonical matches only, no suffix
# or alias matching.
#
# Policy: --policy REF reads the repo's canonical scan-inbound-allowlist.tsv committed
# at REF (trusted base, e.g. the remote default-branch merge-base); REF must resolve
# and the lookup must succeed, else FAILURE. NO_EXEMPTIONS disables the allowlist
# entirely — the right choice for new refs with no trusted base. No policy is ever
# read from the worktree, the payload, or the candidate.
#
# Allowlist format: relpath<TAB>P<id><TAB>sha256-of-exact-reviewed-line<TAB>reason.
# The digest binds the exemption to the reviewed occurrence; different later content
# at the same path/pattern still blocks.
#
# P0: any operation touching the repo's canonical scanner entry point or allowlist —
# add, modify, delete, rename, or mode-only — blocks unconditionally in this gate.
# Policy changes land only through the separately reviewed install path
# (identity-pinned tool installation, same channel as the other pinned tools); this
# scanner has no self-authorizing override.
#
# Exit: 0 clean, 1 hits or HELD input (prints path:line: P<id> / path: HELD reason),
# 2 scanner failure. ANY non-zero blocks. HELD is never clean: receipts must not claim
# held content was scanned.
set -eu
tmp=$(mktemp "${TMPDIR:-/tmp}/scan-inbound.XXXXXX")
trap 'rm -f "$tmp"' EXIT HUP INT TERM
sed '1,/^# --- scan-inbound python ---$/d' "$0" > "$tmp"
rc=0
SCANNER_SELF="$0" python3 "$tmp" "$@" || rc=$?
exit $rc
# --- scan-inbound python ---
import hashlib, os, pathlib, re, subprocess, sys

VERSION = 'scan-inbound-v3.2'

# Pinned per-repo canonical protected entry points and policy paths. The map lives in
# the pinned installed scanner bytes; --repo-id only SELECTS the row, it cannot name
# paths. No suffix or alias matching: exact canonical relative paths only.
REPO_MAP = {
    'instinct': {'scanner': 'archive/gor/tools/scan-inbound.sh',
                 'allowlist': 'archive/gor/tools/scan-inbound-allowlist.tsv'},
    'gorav': {'scanner': 'tools/scan-inbound.sh',
              'allowlist': 'tools/scan-inbound-allowlist.tsv'},
    'bridge': {'scanner': 'tools/scan-inbound.sh',
               'allowlist': 'tools/scan-inbound-allowlist.tsv'},
}


def policy_paths(args):
    row = REPO_MAP[args['repo_id']]
    return (row['scanner'], row['allowlist'])
SIZE_CAP = 20 * 1024 * 1024

PATTERNS = [
    ('P1', re.compile(r'(?i)\bignore\s+(all\s+|any\s+|the\s+|every\s+)?(previous|prior|above|preceding|earlier)\s+(instructions?|messages?|prompts?|rules?|directions?)\b'),
     'ignore/discard prior instructions'),
    ('P2', re.compile(r'(?i)^\s*(?://+|#|/\*+|\*+|;|--|--)?\s*(system|assistant|developer)\s+(message|prompt|notice|instruction|override|warning)\s*:'),
     'role/system-style message header (comment prefixes allowed)'),
    ('P3', re.compile(r'(?i)\b(suppress|silence|conceal|hide|omit)\b[^.\n]{0,40}\b(security\s+)?(warnings?|alerts?|findings?|errors?|checks?|scans?|reports?|output)\b'),
     'suppress/hide warnings or output'),
    ('P4', re.compile(r'(?i)\b(?:do\s+not|don\'?t|never|avoid|stop)\s+(?:\w+\s+)?(report|reporting|warn|warning|alert|alerting|tell|inform|notify|mention|show|showing|log|logging|flag|raise|raising|emit|emitting|repeat|repeating)\b[^.\n]{0,60}\b(user|owner|warnings?|security|findings?|errors?|this|these|anyone|alerts?)\b'),
     'do-not-report / avoid-raising instruction'),
    ('P5', re.compile(r'(?i)\b(delete|remove|erase|destroy|wipe)\s+(this|these|the|all|any|every)\s+(files?|directories|folders?|repos?|repositories|evidence|logs?|backups?|records?)\b'),
     'delete/destroy instruction'),
    ('P6', re.compile(r'(?i)\b(skip|bypass|disable|turn\s+off|do\s+not\s+run|don\'?t\s+run)\b[^.\n]{0,30}\b(checks?|tests?|scans?|scanner|guards?|hooks?|lint|verification|gate)\b'),
     'skip/bypass checks instruction'),
    ('P7', re.compile(r'(?i)\b(agent|assistant|model|llm|copilot|chatbot)s?\b[^.\n]{0,60}\b(must|should|shall|needs?\s+to|is\s+to|are\s+to)\b[^.\n]{0,60}\b(ignore|skip|delete|remove|hide|suppress|disable|bypass|conceal|avoid\s+reporting)\b'),
     'agent-addressed instruction'),
]


def fail(msg):
    print('scan-inbound: FAILURE: %s' % msg, file=sys.stderr)
    sys.exit(2)


def valid_relpath(path):
    pure = pathlib.PurePosixPath(path)
    if (not path or path != str(pure) or path.startswith('/') or path.startswith('./')
            or '..' in pure.parts or '.' in pure.parts or path.endswith('/')):
        fail('unsafe/uncanonical path from input: %r' % path[:100])
    if '.git' in pure.parts:
        fail('repository metadata path not allowed in input: %r' % path[:100])
    if any(ord(c) < 0x20 or ord(c) == 0x7f for c in path):
        fail('control character in path from input: %r' % path[:100])
    return path


def line_digest(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()


def scan_text(path, lineno, text, prev, allow, hits):
    for pid, rx, _desc in PATTERNS:
        if rx.search(text) and line_digest(text) not in allow.get((path, pid), set()):
            hits.append((path, lineno, pid))
    if prev is not None:
        joined = prev.rstrip() + ' ' + text.lstrip()
        for pid, rx, _desc in PATTERNS:
            if rx.search(joined) and not rx.search(prev) and not rx.search(text):
                hits.append((path, lineno - 1, pid))


def scan_content(path, data, allow, hits, held):
    if b'\x00' in data:
        held.append((path, 'binary/NUL content'))
        return
    if len(data) > SIZE_CAP:
        held.append((path, 'over %d bytes' % SIZE_CAP))
        return
    try:
        text = data.decode('utf-8')
    except UnicodeDecodeError:
        held.append((path, 'invalid UTF-8 content; not inspectable as text'))
        return
    prev = None
    for n, line in enumerate(text.splitlines(), 1):
        scan_text(path, n, line, prev, allow, hits)
        prev = line


def git(repo_root, *args, binary=False):
    return subprocess.run(['git', '-C', repo_root] + list(args), capture_output=True)


def resolve_ref(repo_root, ref, label):
    proc = git(repo_root, 'rev-parse', '--verify', '--quiet', ref + '^{commit}')
    if proc.returncode != 0:
        fail('%s does not resolve to a commit: %s' % (label, ref))
    return proc.stdout.decode().strip()


def load_policy(args):
    policy = args['policy']
    if policy == 'NO_EXEMPTIONS':
        return {}, 'NO_EXEMPTIONS'
    allowlist_rel = REPO_MAP[args['repo_id']]['allowlist']
    ref = resolve_ref(args['repo_root'], policy, '--policy ref')
    lst = git(args['repo_root'], 'ls-tree', ref, '--', allowlist_rel)
    if lst.returncode != 0:
        fail('cannot inspect policy path at %s (git/object failure, not absent policy)' % policy)
    if not lst.stdout.strip():
        print('scan-inbound: no committed allowlist at %s (%s); zero exemptions' % (policy, allowlist_rel), file=sys.stderr)
        return {}, ref
    show = git(args['repo_root'], 'show', '%s:%s' % (ref, allowlist_rel))
    if show.returncode != 0:
        fail('cannot read committed allowlist at %s' % policy)
    try:
        text = show.stdout.decode('utf-8')
    except UnicodeDecodeError:
        fail('committed allowlist at %s is not valid UTF-8; policy not trustworthy' % policy)
    entries = {}
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.startswith('#'):
            continue
        fields = line.split('\t')
        if len(fields) != 4 or not re.fullmatch(r'P[0-9]', fields[1]) or not re.fullmatch(r'[0-9a-f]{64}', fields[2]):
            fail('malformed allowlist line %d (need relpath<TAB>P<id><TAB>sha256-of-reviewed-line<TAB>reason)' % n)
        valid_relpath(fields[0])
        entries.setdefault((fields[0], fields[1]), set()).add(fields[2])
    return entries, ref


def decode_git_path(raw, held):
    try:
        return valid_relpath(raw.decode('utf-8'))
    except UnicodeDecodeError:
        held.append(('<bytes %s>' % raw.hex()[:80], 'path not valid UTF-8; not inspectable'))
        return None


def run_push_gate(args, allow, hits, held, notices):
    old = resolve_ref(args['repo_root'], args['old'], 'OLD')
    new = resolve_ref(args['repo_root'], args['new'], 'NEW')
    args['old_resolved'], args['new_resolved'] = old, new
    protected = policy_paths(args)
    proc = git(args['repo_root'], 'diff-tree', '-r', '-z', '--no-commit-id', old, new)
    if proc.returncode != 0:
        fail('git diff-tree failed for %s..%s: %s' % (args['old'], args['new'], proc.stderr.decode(errors='replace')[:120]))
    tokens = proc.stdout.split(b'\x00')
    if tokens and tokens[-1] == b'':
        tokens.pop()
    changed = 0
    i = 0
    while i < len(tokens):
        raw_entry = tokens[i]; i += 1
        try:
            entry = raw_entry.decode('ascii')
        except UnicodeDecodeError:
            fail('undecodable diff-tree entry bytes; metadata not trustworthy')
        m = re.match(r'^:(\d+) (\d+) ([0-9a-f]+) ([0-9a-f]+) ([A-Z])(\d*)$', entry)
        if not m:
            fail('unparseable diff-tree entry: %r' % entry[:80])
        old_mode, new_mode, old_blob, new_blob, status, _score = m.groups()
        if i >= len(tokens):
            fail('truncated diff-tree output: entry without path')
        path = decode_git_path(tokens[i], held); i += 1
        extra_path = None
        if status in ('R', 'C'):
            if i >= len(tokens):
                fail('truncated diff-tree output: %s entry without second path' % status)
            extra_path = decode_git_path(tokens[i], held); i += 1
        changed += 1
        paths = [p for p in (path, extra_path) if p]
        if not paths:
            continue
        if any(p in protected for p in paths):
            hits.append((paths[-1], 1, 'P0'))
            continue
        if status == 'D':
            continue
        if new_mode in ('120000', '160000'):
            held.append((paths[-1], 'type %s (symlink/gitlink) not inspectable' % new_mode))
            continue
        if new_mode not in ('100644', '100755'):
            held.append((paths[-1], 'unsupported mode %s' % new_mode))
            continue
        if status == 'T':
            held.append((paths[-1], 'type change; result not inspectable'))
            continue
        size_proc = git(args['repo_root'], 'cat-file', '-s', new_blob)
        if size_proc.returncode != 0:
            fail('cannot stat new blob %s for %s' % (new_blob[:12], paths[-1]))
        try:
            blob_size = int(size_proc.stdout.decode('ascii').strip())
        except ValueError:
            fail('unparseable blob size for %s' % new_blob[:12])
        if blob_size > SIZE_CAP:
            held.append((paths[-1], 'over %d bytes' % SIZE_CAP))
            continue
        blob = git(args['repo_root'], 'cat-file', 'blob', new_blob)
        if blob.returncode != 0:
            fail('cannot read new blob %s for %s' % (new_blob[:12], paths[-1]))
        if len(blob.stdout) != blob_size:
            fail('blob %s size changed between stat and read; object not stable' % new_blob[:12])
        scan_content(paths[-1], blob.stdout, allow, hits, held)
    if changed == 0:
        notices.append('OLD..NEW contains no changed paths; caller proved this is a metadata-only push and records it')


def payload_entry_kind(real):
    st = os.lstat(real)
    import stat as statmod
    if statmod.S_ISREG(st.st_mode):
        return 'file'
    if statmod.S_ISLNK(st.st_mode):
        return 'symlink'
    if statmod.S_ISDIR(st.st_mode):
        return 'dir'
    if statmod.S_ISFIFO(st.st_mode):
        return 'fifo'
    if statmod.S_ISSOCK(st.st_mode):
        return 'socket'
    if statmod.S_ISBLK(st.st_mode) or statmod.S_ISCHR(st.st_mode):
        return 'device'
    return 'other'


def run_pre_apply(args, allow, hits, held):
    root_arg = pathlib.Path(args['root'])
    if not root_arg.exists():
        fail('payload root does not exist: %s' % args['root'])
    if root_arg.is_symlink():
        fail('payload root must not be a symlink: %s' % args['root'])
    if not root_arg.is_dir():
        fail('payload root is not a directory: %s' % args['root'])
    root = root_arg.resolve()
    try:
        raw = pathlib.Path(args['manifest']).read_bytes()
    except OSError as e:
        fail('manifest unreadable: %s' % e)
    manifest_sha = hashlib.sha256(raw).hexdigest()
    print('scan-inbound: receipt: manifest sha256=%s' % manifest_sha)
    try:
        manifest_text = raw.decode('utf-8')
    except UnicodeDecodeError:
        fail('manifest is not valid UTF-8; caller-supplied operations not trustworthy')
    protected = policy_paths(args)
    ops = []
    for n, line in enumerate(manifest_text.splitlines(), 1):
        if not line.strip():
            continue
        fields = line.split('\t')
        if len(fields) != 4 or fields[0] not in ('ADD', 'MODIFY', 'DELETE'):
            fail('malformed manifest line %d (need ADD|MODIFY|DELETE<TAB>path<TAB>mode<TAB>sha256)' % n)
        op, path, mode, sha = fields
        valid_relpath(path)
        if op == 'DELETE':
            if mode != '-' or sha != '-':
                fail('malformed DELETE line %d (mode and sha256 must be -)' % n)
        elif mode == '120000':
            if sha != '-':
                fail('malformed %s line %d (symlink row: mode 120000, sha256 must be -)' % (op, n))
        else:
            if mode not in ('100644', '100755') or not re.fullmatch(r'[0-9a-f]{64}', sha):
                fail('malformed %s line %d (mode 100644/100755 sha256 hex, or 120000 with -)' % (op, n))
        ops.append((op, path, mode, sha))
    listed = set()
    for op, path, mode, sha in ops:
        if path in listed:
            fail('duplicate manifest path: %s' % path)
        listed.add(path)
        if path in protected:
            hits.append((path, 1, 'P0'))
            continue
        target = (root / path).resolve()
        if not str(target).startswith(str(root) + '/') and target != root:
            fail('manifest path escapes payload root: %s' % path)
        real = root / path
        if op == 'DELETE':
            if real.exists() or real.is_symlink():
                fail('DELETE row but payload still carries %s' % path)
            continue
        kind = payload_entry_kind(real) if os.path.lexists(real) else 'missing'
        if mode == '120000':
            if kind != 'symlink':
                fail('manifest declares symlink but payload path is not one: %s' % path)
            held.append((path, 'declared symlink (mode 120000)'))
            continue
        if kind == 'missing':
            fail('manifest file missing in payload: %s' % path)
        if kind == 'fifo':
            fail('FIFO in payload refused before read (would block): %s' % path)
        if kind in ('socket', 'device'):
            held.append((path, kind + ' in payload; not inspectable'))
            continue
        if kind != 'file':
            fail('unsupported payload entry type %s: %s' % (kind, path))
        if real.is_symlink() or any(q.is_symlink() for q in real.parents if q != root.parent and str(q).startswith(str(root))):
            held.append((path, 'symlink in payload'))
            continue
        st = os.lstat(real)
        if st.st_size > SIZE_CAP:
            held.append((path, 'over %d bytes' % SIZE_CAP))
            continue
        with open(real, 'rb') as fh:
            data = fh.read(SIZE_CAP + 1)
        if len(data) > SIZE_CAP:
            held.append((path, 'over %d bytes' % SIZE_CAP))
            continue
        if len(data) != st.st_size:
            fail('payload file changed size during scan (mutable source refused): %s' % path)
        if hashlib.sha256(data).hexdigest() != sha:
            fail('payload hash mismatch for %s (manifest not caller-verified)' % path)
        actual_mode = '100755' if (real.stat().st_mode & 0o111) else '100644'
        if actual_mode != mode:
            fail('payload mode mismatch for %s (manifest %s, actual %s)' % (path, mode, actual_mode))
        scan_content(path, data, allow, hits, held)
    if not ops:
        fail('empty operations manifest is not proof of a no-op apply; caller must state the operations explicitly')

    def walk_error(err):
        fail('payload traversal failed: %s' % err)

    for dirpath, dirnames, filenames in os.walk(root, followlinks=False, onerror=walk_error):
        for d in list(dirnames):
            p = pathlib.Path(dirpath) / d
            rel = str(p.relative_to(root))
            if d == '.git' or '.git' in pathlib.PurePosixPath(rel).parts:
                fail('repository metadata present in payload: %s' % rel)
            if p.is_symlink():
                held.append((rel, 'symlinked directory'))
                dirnames.remove(d)
        for f in filenames:
            p = pathlib.Path(dirpath) / f
            rel = str(p.relative_to(root))
            if f == '.git' or '.git' in pathlib.PurePosixPath(rel).parts:
                fail('repository metadata present in payload: %s' % rel)
            kind = payload_entry_kind(p)
            if kind == 'fifo':
                fail('FIFO in payload refused before read (would block): %s' % rel)
            if kind in ('socket', 'device'):
                held.append((rel, kind + ' in payload; not inspectable'))
                continue
            if rel not in listed:
                if kind == 'symlink':
                    held.append((rel, 'unlisted symlink'))
                elif kind == 'file':
                    fail('payload contains path not in manifest: %s' % rel)
                else:
                    fail('unsupported payload entry type %s: %s' % (kind, rel))


def main():
    argv = sys.argv[1:]
    args = {'mode': None, 'manifest': None, 'root': None, 'old': None, 'new': None,
            'repo_root': '.', 'policy': None, 'repo_id': None,
            'old_resolved': None, 'new_resolved': None}
    positional = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--push-gate':
            args['mode'] = 'push'; args['old'] = argv[i + 1]; args['new'] = argv[i + 2]; i += 3
        elif a == '--pre-apply':
            args['mode'] = 'apply'; args['manifest'] = argv[i + 1]; i += 2
        elif a == '--policy':
            args['policy'] = argv[i + 1]; i += 2
        elif a == '--repo-root':
            args['repo_root'] = argv[i + 1]; i += 2
        elif a == '--repo-id':
            args['repo_id'] = argv[i + 1]; i += 2
        else:
            positional.append(a); i += 1
    if args['mode'] == 'apply' and len(positional) == 1:
        args['root'] = positional[0]
    elif positional:
        fail('unrecognized argument(s): %s (no override flags exist; unknown input fails closed)' % ' '.join(positional[:5]))
    for a in argv:
        if a.startswith('--') and a not in ('--push-gate', '--pre-apply', '--policy', '--repo-root', '--repo-id'):
            fail('unknown flag: %s (no override flags exist; unknown input fails closed)' % a)
    if args['mode'] not in ('push', 'apply'):
        fail('usage: scan-inbound.sh --push-gate OLD NEW --policy REF|NO_EXEMPTIONS --repo-id ID | --pre-apply MANIFEST ROOT --policy REF|NO_EXEMPTIONS --repo-id ID [--repo-root R]')
    if args['mode'] == 'apply' and not args['root']:
        fail('--pre-apply requires PAYLOAD_ROOT')
    if not args['policy']:
        fail('explicit policy required: --policy REF or --policy NO_EXEMPTIONS (no implicit HEAD, no worktree policy)')
    if args['repo_id'] not in REPO_MAP:
        fail('explicit --repo-id required: one of %s (pinned canonical protected paths per repo)' % ', '.join(sorted(REPO_MAP)))

    allow, policy_desc = load_policy(args)
    hits, held, notices = [], [], []
    if args['mode'] == 'push':
        run_push_gate(args, allow, hits, held, notices)
    else:
        run_pre_apply(args, allow, hits, held)

    try:
        self_sha = hashlib.sha256(pathlib.Path(os.environ.get('SCANNER_SELF', '/dev/null')).read_bytes()).hexdigest()
    except OSError:
        self_sha = 'unavailable'
    for path, lineno, pid in sorted(set(hits)):
        print('%s:%d: %s' % (path, lineno, pid))
    for path, why in sorted(set(held)):
        print('%s: HELD (%s); needs explicit review, not an apply' % (path, why))
    for note in notices:
        print('scan-inbound: NOTICE: %s' % note, file=sys.stderr)
    bounds = ''
    if args['mode'] == 'push':
        bounds = ' old=%s new=%s' % (args['old_resolved'], args['new_resolved'])
    print('scan-inbound: receipt: scanner=%s repo=%s policy=%s%s hits=%d held=%d' % (
        self_sha, args['repo_id'], policy_desc, bounds, len(set(hits)), len(set(held))), file=sys.stderr)
    if hits or held:
        print('scan-inbound: %s: block. Exemptions need a reviewed digest-bound %s entry at the trusted policy ref, never an in-payload directive.' % (
            VERSION, REPO_MAP[args['repo_id']]['allowlist']), file=sys.stderr)
        sys.exit(1)
    print('scan-inbound: %s clean' % VERSION)
    sys.exit(0)


try:
    main()
except SystemExit:
    raise
except Exception as e:
    fail('unexpected scanner error (failing closed): %s: %s' % (type(e).__name__, str(e)[:200]))
