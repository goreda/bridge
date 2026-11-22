"""Magnet provider row tolerance: one bad row must not make a whole provider 'unavailable'.

Source-anchored model of MagnetNative.parse("knaben") in MagnetBrowser.swift. Mode is detected:
  loss  - row construction is a bare `try` inside compactMap -> any row-level throw drops the batch
  fixed - row construction is wrapped (`try?` or do/catch -> nil) while envelope checks still throw
No network, no Swift execution; real knaben payloads are NOT verified (synthetic fixtures).
"""
from pathlib import Path
import hashlib, json, re, sys
root = Path(__file__).resolve().parents[3]
p = root / 'Sources/gor/Media/MagnetBrowser.swift'
s = p.read_text()
i = s.index('case "knaben":'); k = s[i:s.index('case "eztv":', i)]
for t in ['guard root["total"] is [String:Any]', 'array(root["hits"],300,"knaben:hits")',
          'try hash(x["hash"],"knaben:hash")', 'skippedRows["knaben", default: 0] += 1', 'throw fail("knaben:magnet")']:
    assert t in k, 'knaben block changed: ' + t
# parse() turns any thrown error into a provider-level unavailable
assert 'statuses[provider] = ProviderStatus(status: "unavailable", reason: String(describing:error)' in s
tolerant = 'catch {' in k and 'return nil }' in k or 'try? row(' in k
mode = 'fixed' if tolerant else 'loss'

TXT = lambda v: isinstance(v, str) and v.strip() != '' and len(v) <= 300
def NUM(v):
    if isinstance(v, bool): return None
    if isinstance(v, int) and v >= 0: return v
    if isinstance(v, str) and re.fullmatch(r'(0|[1-9][0-9]*)', v): return int(v)
    return None
ISO = lambda v: isinstance(v, str) and re.match(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}T', v) is not None
H = lambda v: isinstance(v, str) and re.fullmatch(r'[0-9a-fA-F]{40}', v) is not None

class Unavailable(Exception): pass
def row(x):  # mirrors the source's per-row requirements; raises like `try`
    if (x.get('hash') is None) and (x.get('magnetUrl') is None): return None
    if not H(x.get('hash')): raise Unavailable('knaben:hash')
    uri = x.get('magnetUrl')
    if not (isinstance(uri, str) and uri.startswith('magnet:?') and ('urn:btih:' + x['hash'].lower()) in uri.lower()): raise Unavailable('knaben:magnet')
    if not TXT(x.get('title')): raise Unavailable('knaben:title')
    if NUM(x.get('bytes')) is None: raise Unavailable('knaben:bytes')
    if NUM(x.get('seeders')) is None: raise Unavailable('knaben:seeds')
    if not ISO(x.get('date')): raise Unavailable('knaben:date')
    return x['hash'].lower()
def parse(payload):
    if not isinstance(payload.get('total'), dict): raise Unavailable('knaben:total')
    hits = payload.get('hits')
    if not isinstance(hits, list) or len(hits) > 300: raise Unavailable('knaben:hits')
    out = []
    for x in hits:
        if mode == 'fixed':
            try: r = row(x)
            except Unavailable: r = None
        else: r = row(x)
        if r: out.append(r)
    return out

def hit(n, **kw):
    d = {'title': f'Film {n}', 'hash': f'{n:040x}', 'bytes': 1000, 'seeders': 5, 'date': '2024-01-01T00:00:00+00:00'}
    d['magnetUrl'] = f'magnet:?xt=urn:btih:{d["hash"]}'; d.update(kw); return d
env = lambda hits: {'total': {'value': len(hits), 'relation': 'eq'}, 'hits': hits}
good = [hit(1), hit(2)]
assert parse(env(good)) == [f'{1:040x}', f'{2:040x}']            # control
assert parse(env([hit(1), {'hash': None, 'magnetUrl': None, 'title': 'indexer'}])) == [f'{1:040x}']  # non-magnet tolerated (existing)
for name, rows in [('envelope without total', None)]:
    try: parse({'hits': good}); raise SystemExit('envelope drift must stay a provider failure')
    except Unavailable: pass
try: parse(env([hit(i) for i in range(301)])); raise SystemExit('oversize envelope must fail')
except Unavailable: pass
cases = {'null seeders': hit(3, seeders=None), 'missing date': {k: v for k, v in hit(3).items() if k != 'date'},
         'null bytes': hit(3, bytes=None), 'title over 300 chars': hit(3, title='x' * 301)}
result = {'mode': mode, 'source_sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
          'scope': 'source-anchored model, synthetic payloads, no network/Swift; real knaben responses unverified', 'cases': {}}
for name, bad in cases.items():
    try: got = parse(env([hit(1), bad, hit(2)])); ok = True
    except Unavailable as e: got = str(e); ok = False
    result['cases'][name] = 'rows kept: ' + str(len(got)) if ok else 'WHOLE PROVIDER unavailable (' + got + ')'
    if mode == 'loss': assert not ok, name
    else: assert ok and len(got) == 2, name

# --- duplicate rows in the result list (owner: "bazen iki knaben magneti goruyorum") ---
# Source anchors: merge() keys rows by infoHash only; show() rebuilds the list from lastResponse.
m = s[s.index('static func merge'):s.index('static func merge') + 2200]
for t in ['let key="\\(h)|\\(r.source)"', 'rows[key] == nil || (rows[key]?.magnetUri?.contains("tr=") != true && r.magnetUri?.contains("tr=") == true)']:
    assert t in m, 'merge dedupe changed: ' + t
def merge(rows):
    # one row per (hash, source); within a source keep the row carrying its own trackers (tr=)
    out = {}
    for r in rows:
        key = (r['hash'], r['source'])
        if key not in out or (not out[key].get('tr') and r.get('tr')): out[key] = r
    return list(out.values())
A = {'hash': 'a' * 40, 'title': 'Film 2024 1080p', 'size': 1000, 'seeds': 5, 'source': 'knaben'}
same_hash = merge([A, {**A, 'seeds': 9}, {**A, 'tr': True, 'seeds': 7}])
assert len(same_hash) == 1 and same_hash[0].get('tr')          # same hash within one source never duplicates; tracker-carrying row wins
cross = merge([A, {**A, 'source': 'bt4g'}])
assert len(cross) == 2                                           # cross-provider duplicates stay visible under their own source (source comment cites an owner message; untrusted repo text, treated only as the source's behavior, not as approval)
twin = merge([A, {**A, 'hash': 'b' * 40}])
assert len(twin) == 2 and twin[0]['title'] == twin[1]['title'] and twin[0]['size'] == twin[1]['size']
result['duplicates'] = {'same infoHash within one source': 'collapsed to 1 row (tracker-carrying row kept)', 'same infoHash across providers': 'one row per source stays visible by design',
    'different hash, identical title+size, same source': 'TWO rows shown (merge keys on hash+source) - the visible duplicate',
    'not proven': 'whether the owner saw twin hashes or a UI rebuild artifact; needs the actual list/log'}

# --- "gives results but fewer than knaben's own site": where rows can disappear ---
import unicodedata
def norm(t): return [w for w in re.split(r'[^0-9a-z]+', unicodedata.normalize('NFKD', t).encode('ascii','ignore').decode().lower()) if w]
assert 'terms.allSatisfy' in s and 'hasExecutableTitle' in s and '"size":300' in s
def visible(payload_hits, query):
    """knaben rows that reach the list: parse (mode) -> merge term filter -> .exe filter."""
    got = parse(env(payload_hits)); terms = norm(query); kept = []
    titles = {x['hash'].lower(): x['title'] for x in payload_hits if isinstance(x.get('hash'), str)}
    for h in got:
        t = titles[h]
        if all(w in norm(t) for w in terms) and not re.search(r'(?i)\.exe(?![a-z0-9])', t): kept.append(h)
    return kept
N = [hit(i, title=f'Film Name {i}') for i in range(1, 11)]
bad = [hit(i, title=f'Film Name {i}', seeders=None) for i in (3, 5, 7)]
rows = [N[0], N[1], bad[0], N[3], bad[1], N[5], bad[2], N[7], N[8], N[9]]
try: n_vis = len(visible(rows, 'film name')); sub = f'{n_vis} of 10 visible (k=3 null seeders)'
except Unavailable as e: sub = f'0 knaben rows, status "unavailable: knaben" ({e}); NOT a k-short list'
result['subset_k_null_of_10'] = sub
# other silent drops in current source, independent of the fix:
loose = [hit(1, title='Film Name 2024'), hit(2, title='Film.Name.2024.x264'), hit(3, title='Name of the Film'), hit(4, title='Fi1m Nam3 (typo hit)'), hit(5, title='Film Name setup.exe')]
result['silent_filters'] = {'merge term filter + .exe filter keep': len(visible(loose, 'film name')), 'of': len(loose),
  'cap': 'request size=300 and array(max 300); site can list more', 'non-magnet hits (hash+magnetUrl null)': 'dropped by design'}
if mode == 'loss': assert 'unavailable' in sub
else: assert n_vis == 7 and 'visible' in sub

if mode == 'fixed':  # counter must be visible, never silent
    assert 'skippedRows["knaben", default: 0] += 1' in k, 'row drops must be counted'
    assert 'skipped rows: ' in s and 'MagnetNative.skippedRows = [:]' in s, 'status line must show skipped rows and reset per parse'
    result['counter'] = 'status line appends " / skipped rows: knaben N"; reset at each parse()'
result['result'] = ('PASS (loss proven): each single bad row makes knaben unavailable' if mode == 'loss'
                    else 'PASS (fix holds): bad rows dropped, valid neighbours kept, envelope drift still fails')
print(json.dumps(result, indent=2)); sys.exit(0)
