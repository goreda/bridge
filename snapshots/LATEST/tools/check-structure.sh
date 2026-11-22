#!/bin/sh
# check-structure.sh v5 — gor/gorav code structure checker (199ci + 199ck S4 ruling).
# Checks: header form (4 lines), S2 engine boundary, S4 wiring (reference scan),
# F1 namesake presence (partial: manual concept audit still required), F2 names,
# STATIONS.tsv membership, gorav Tests/ placement. Deps: sh + python3 stdlib only.
exec python3 - "$@" <<'PYEOF'
import pathlib, re, sys

args = sys.argv[1:]
warn_only = '--warn-only' in args
roots = [pathlib.Path(a).resolve() for a in args if a != '--warn-only'] or [pathlib.Path.cwd()]
violations = []
def viol(m): violations.append(m)

TYPE_RE  = re.compile(r'(?<![\w.])(?:struct|class|enum|actor|protocol|typealias)\s+([A-Za-z_]\w*)')
EXT_RE   = re.compile(r'(?<![\w.])extension\s+([A-Za-z_]\w*)')
MPV_RE   = re.compile(r'(?<![\w])(MPVClient|MPVCommand|mpv_core|ipcCommand)(?![\w])')
GORAV_IMP= re.compile(r'(?<![\w.])import\s+(?:\w+\s+)*GorAV\w*')
IMPORT_RE= re.compile(r'^\s*(?:@?\w+\s+)*import\s')
COND_RE  = re.compile(r'^\s*#(?:if|elseif|else|endif)\b')
HISTORY_RE = re.compile(r'\bhistory\b|\b\d{3}[a-z]{1,2}\b|arch-\d|\b20\d\d-\d\d-\d\d\b|\breceipt\b|\bagent\b', re.I)
F2_TOKEN = re.compile(r'(Stub|Temp|Test|New|Old|(?<=[a-z0-9])V\d+(?![a-z0-9])|(?<=[a-z0-9])R\d+(?![a-z0-9])|\d{3,4}[a-z]{1,2}(?![A-Za-z0-9]))')
ENTRY_RE = re.compile(r'@main\b')

def strip_swift(text):
    """Code-only copy: line/nested-block comments, plain/raw/multiline strings removed.
    Newlines preserved so line numbers stay aligned."""
    out = []
    i, n = 0, len(text)
    block = 0
    while i < n:
        c = text[i]
        if block:
            if text.startswith('/*', i): block += 1; i += 2
            elif text.startswith('*/', i): block -= 1; i += 2
            else:
                if c == '\n': out.append('\n')
                i += 1
            continue
        if text.startswith('//', i):
            while i < n and text[i] != '\n': i += 1
            continue
        if text.startswith('/*', i): block = 1; i += 2; continue
        # raw strings: #"..."#, ##"..."##, #"""..."""#
        m = re.match(r'(#+)"', text[i:])
        if m:
            hashes = m.group(1)
            j = i + len(hashes) + 1
            if text.startswith('"""', j):
                end = '"""' + hashes
                k = text.find(end, j + 3)
                seg = text[i:(k + len(end)) if k != -1 else n]
                out.append('\n' * seg.count('\n')); i += len(seg); continue
            else:
                k = i + len(hashes) + 1
                while True:
                    k = text.find('"' + hashes, k)
                    if k == -1: k = n; break
                    k += 1 + len(hashes); break
                seg = text[i:k]; out.append('\n' * seg.count('\n')); i = k; continue
        if text.startswith('"""', i):
            k = text.find('"""', i + 3)
            seg = text[i:(k + 3) if k != -1 else n]
            out.append('\n' * seg.count('\n')); i += len(seg); continue
        if c == '"':
            j = i + 1
            while j < n:
                if text.startswith('\\(', j):
                    depth = 1; k = j + 2
                    while k < n and depth:
                        if text[k] == '(': depth += 1
                        elif text[k] == ')': depth -= 1
                        k += 1
                    out.append(' ' + text[j + 2:k - 1])
                    j = k; continue
                if text[j] == '\\': j += 2; continue
                if text[j] == '"' or text[j] == '\n': break
                j += 1
            seg = text[i:j + 1]; out.append(' ' * (len(seg) - seg.count('\n')) + '\n' * seg.count('\n')); i = j + 1; continue
        out.append(c); i += 1
    return ''.join(out)

def parse_manifest(manifest):
    text = manifest.read_text(encoding='utf-8')
    base = manifest.parent
    res = []
    for m in re.finditer(r'\.(target|executableTarget|testTarget)\s*\(([^)]*)\)', text, re.S):
        kind, body = m.group(1), m.group(2)
        nm = re.search(r'name\s*:\s*"([^"]+)"', body)
        if not nm: continue
        name = nm.group(1)
        pm = re.search(r'path\s*:\s*"([^"]+)"', body)
        if re.search(r'path\s*:\s*[A-Za-z_]', body) and not pm:
            viol(f'gorav manifest: unresolved path expression for target "{name}" in {manifest}')
            continue
        rel = pm.group(1) if pm else ('Tests/' + name if kind == 'testTarget' else 'Sources/' + name)
        p = pathlib.PurePosixPath(rel)
        if p.is_absolute() or '..' in p.parts:
            viol(f'gorav manifest: unsafe target path {rel!r} for target "{name}" in {manifest}')
            continue
        tdir = (base / rel).resolve()
        try: tdir.relative_to(base.resolve())
        except ValueError:
            viol(f'gorav manifest: target path escapes repo: {rel!r} for target "{name}" in {manifest}')
            continue
        res.append((name, tdir, kind, rel))
    return res

for root in roots:
    st = root/'docs'/'STATIONS.tsv'
    if not st.exists() and (root/'STATIONS.tsv').exists(): st = root/'STATIONS.tsv'
    tsv = set()
    if not st.exists():
        viol(f'missing docs/STATIONS.tsv in {root}')
    else:
        rows = [ln for ln in st.read_text().splitlines() if ln.strip()]
        if rows and rows[0].split('\t')[0].strip() in ('station', 'name'): rows = rows[1:]
        tsv = {ln.split('\t')[0].strip() for ln in rows}
        # membership: the TSV is the registry; checker cannot authenticate A3 approval (reported limit)

    is_gor = (root/'Sources'/'gor').is_dir()
    is_gorav = not is_gor and (root/'Sources').is_dir()

    all_swift = sorted(p for p in root.rglob('*.swift')
                       if '.build' not in p.parts and '.git' not in p.parts and p.name != 'Package.swift')
    src_swift = [p for p in all_swift if p.relative_to(root).parts[0] == 'Sources']

    # gorav manifest placement
    if is_gorav:
        mans = ([root/'Package.swift'] if (root/'Package.swift').exists() else []) + \
               sorted((root/'Packages').glob('*/Package.swift')) if (root/'Packages').is_dir() else \
               ([root/'Package.swift'] if (root/'Package.swift').exists() else [])
        for pm in mans:
            for (name, tdir, kind, rel) in parse_manifest(pm):
                if not tdir.is_dir():
                    viol(f'gorav manifest: target dir missing: {tdir}')
                    continue
                relroot = pathlib.PurePosixPath(rel).parts[0] if pathlib.PurePosixPath(rel).parts else ''
                if relroot == 'Tests':
                    continue  # every test/probe target lives under Tests/
                if relroot == 'Sources':
                    if kind != 'target' or not name.startswith('GorAV'):
                        viol(f'gorav Sources/ product modules only (GorAV<Station> .target): "{name}" ({kind}) at {rel} in {pm}')
                else:
                    viol(f'gorav manifest: target path outside Sources/Tests: {rel} in {pm}')

    # gor placement + stray root files
    if is_gor:
        for f in root.glob('*.swift'):
            if f.name != 'Package.swift':
                viol(f'root-level Swift must live under Sources/gor/<Station>: {f}')

    checked = 0
    decl_map = {}   # file -> declared type names (code only)
    code_map = {}
    for f in all_swift:
        text = f.read_text(encoding='utf-8')
        code = strip_swift(text)
        code_map[f] = code
        decl_map[f] = TYPE_RE.findall(code)

    for f in all_swift:
        rel = f.relative_to(root)
        parts = rel.parts
        text = f.read_text(encoding='utf-8')
        code = code_map[f]
        lines = text.split('\n')
        clines = code.split('\n')

        # placement (gor)
        if is_gor and parts[:2] == ('Sources', 'gor'):
            if len(parts) != 4:
                viol(f'gor placement must be one level: {rel}')
            elif tsv and parts[2] not in tsv:
                viol(f'unknown station {parts[2]}: {rel}')

        # header form
        hdr_ok = len(lines) >= 4
        m1 = m2 = m3 = m4 = None
        if hdr_ok:
            m1 = re.match(r'^// ([A-Za-z][A-Za-z0-9]*)/([A-Za-z0-9_.+]+)\.swift\s*$', lines[0])
            m2 = re.match(r'^// \S.*$', lines[1])
            m3 = re.match(r'^// Uses: .+$', lines[2])
            m4 = re.match(r'^// Engine: (mpv|gorav|both|none)\s*$', lines[3])
            hdr_ok = bool(m1 and m2 and m3 and m4)
        if not hdr_ok:
            viol(f'header: missing/inexact 4-line header: {f}')
            continue
        checked += 1
        topic, stem = m1.group(1), m1.group(2)
        if f.stem != stem:
            viol(f'header name mismatch: {f} header names {stem}.swift')
        # header topic = actual location
        if is_gor and parts[:2] == ('Sources', 'gor') and len(parts) == 4 and topic != parts[2]:
            viol(f'header station mismatch: {f} header topic {topic}, actual {parts[2]}')
        elif 'Tests' in parts:
            tdir = parts[parts.index('Tests') + 1] if parts.index('Tests') + 1 < len(parts) - 1 else None
            if tdir and topic != tdir:
                viol(f'header topic mismatch: {f} header topic {topic}, actual Tests/{tdir}')
        elif is_gorav and parts[0] == 'Sources':
            if topic != parts[1]:
                viol(f'header topic mismatch: {f} header topic {topic}, actual {parts[1]}')

        # above-imports region: only blank + conditional lines; history-pattern comments always banned
        first_imp = next((i for i, ln in enumerate(clines[4:], 4) if IMPORT_RE.match(ln)), None)
        if first_imp is not None:
            for raw in lines[4:first_imp]:
                s = raw.strip()
                if not s: continue
                if COND_RE.match(s): continue
                viol(f'header: extra content above imports: {f}: {raw.strip()[:60]}')
                break
        else:
            # header region ends at the first ACTUAL code line (type, free func, let/var, entry code);
            # non-doc comments and other content before it violate
            stop_i = next((i for i, stripped in enumerate(clines[4:], 4)
                           if stripped.strip() and not COND_RE.match(stripped.strip())), len(lines))
            for raw in lines[4:stop_i]:
                rs = raw.strip()
                if not rs: continue
                if COND_RE.match(rs): continue
                if rs.startswith('///'): continue
                viol(f'header: extra content in no-import header region: {f}: {rs[:60]}')
                break

        # F1: namesake type declared in real code (partial automation; concept audit manual)
        decls = decl_map[f]
        exts = EXT_RE.findall(code)
        base = stem.split('+')[0]
        if f.name == 'main.swift':
            decls = decls or [base]  # explicit owner entry-point allowance: no namesake type required
        if decls:
            if base not in decls:
                viol(f'F1: {f} does not declare its namesake type {base}')
        elif exts:
            if base not in exts:
                viol(f'F1: {f} extension does not target {base}')
        else:
            viol(f'F1: no type or extension found in {f}')

        # F2: forbidden name tokens (file + declared types)
        names = [f.stem] + decls
        for nm in names:
            hit = F2_TOKEN.search(nm)
            if hit and not ('Tests' in parts and hit.group(1) in ('Test',)):
                viol(f'F2: forbidden name token {hit.group(1)!r} in {nm} ({f})')
                break

        # S2: only Engine talks to an engine (gor repos)
        if is_gor and parts[:2] == ('Sources', 'gor') and len(parts) == 4 and parts[2] != 'Engine':
            if MPV_RE.search(code):
                viol(f'S2: mpv reference outside Engine: {f}')
            if GORAV_IMP.search(code):
                viol(f'S2: GorAV import outside Engine: {f}')

    # S4 wiring (199ck): each Sources file wired or entry point; linear token index
    DECL_MASK = re.compile(r'(?<![\w.])(?:struct|class|enum|actor|protocol|typealias)\s+[A-Za-z_]\w*')
    use_index = {}
    for g in src_swift:
        masked = DECL_MASK.sub(lambda m: m.group(0).split()[0], code_map[g])
        for tok in set(re.findall(r'[A-Za-z_]\w*', masked)):
            use_index.setdefault(tok, set()).add(g)
    for f in src_swift:
        decls = decl_map.get(f, [])
        if f.name == 'main.swift' or ENTRY_RE.search(code_map[f]) or 'AppDelegate' in decls:
            continue
        wired = any(len(use_index.get(t, set()) - {f}) > 0 for t in decls)
        if not wired:
            viol(f'S4: unwired file (no type used from another Sources file, not an entry point): {f}')

    # 199cm: vendored gorav drift read-only report (lock varsa bayt eşleşmesi; yoksa MISSING bulgusu)
    vend = root/'Packages'/'gorav'
    if vend.is_dir():
        lockp = vend/'source-lock.json'
        vsrc = [q for q in vend.rglob('*') if q.is_file() and q.name not in ('Package.swift', 'source-lock.json')]
        if not lockp.exists():
            if not vsrc:
                viol(f'vendor-drift: Packages/gorav manifest-only, source-lock.json MISSING: drift unmeasurable, no vendored sources recorded')
            else:
                viol(f'vendor-drift: source-lock.json MISSING with {len(vsrc)} unrecorded vendored files: drift unmeasurable')
        else:
            import hashlib, json as _json
            try:
                lock = _json.loads(lockp.read_text())
                lf = lock.get('files', {})
                bad = miss = 0
                actual = {q.relative_to(vend).as_posix(): q for q in vsrc}
                for path, exp in lf.items():
                    ap = actual.pop(path, None)
                    if ap is None: miss += 1
                    elif hashlib.sha256(ap.read_bytes()).hexdigest() != exp: bad += 1
                if bad or miss or actual:
                    viol(f'vendor-drift: Packages/gorav drifted vs lock rev {lock.get("revision","?")[:12]}: {bad} modified, {miss} missing, {len(actual)} unrecorded')
            except Exception as e:
                viol(f'vendor-drift: source-lock.json unreadable: {type(e).__name__}')

    if checked == 0:
        viol(f'nothing checked in {root}: no Swift sources with valid 4-line headers (refuse to PASS)')

if violations:
    for v in violations: print(f'check-structure: VIOLATION {v}')
    if warn_only:
        print(f'check-structure: WARN-ONLY {len(violations)} violation(s)'); sys.exit(0)
    print('check-structure: FAIL'); sys.exit(1)
print('check-structure: PASS')
PYEOF
