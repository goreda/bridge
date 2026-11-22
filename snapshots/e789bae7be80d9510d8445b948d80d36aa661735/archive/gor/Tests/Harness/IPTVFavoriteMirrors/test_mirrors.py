"""IPTV favorite mirror persistence: source-derived save/load model, no real UserDefaults/playback.

The persisted key set is read from the live saveFavorites()/loadFavorites() text in IPTV.swift,
so the model follows whatever the source stores. Mode is detected from source:
  loss  - current main: mirrors are not persisted -> proves the loss (PASS = loss proven)
  fixed - patched source persists mirrors under key "alts" -> proves invariants (PASS = fix holds)
"""
from pathlib import Path
import hashlib, json, re, sys

root = Path(__file__).resolve().parents[3]
p = root / 'Sources/gor/Media/IPTV.swift'
s = p.read_text()

def block(start, end):
    i = s.index(start); return s[i:s.index(end, i)]

save_src = block('private func saveFavorites', '// MARK: - HLS Quality')
load_src = block('private func loadFavorites', 'private func saveFavorites')
assert 'private let favKey = "iptv.favorites.v1"' in s, 'favKey changed'
assert 'guard currentAlternateIndex < ch.alternateURLs.count' in s, 'failover guard changed'

# swift dict key -> IPTVChannel attribute, as the source writes it
attr = {'name': 'name', 'url': 'streamURL', 'tvgID': 'tvgID', 'country': 'countryCode', 'routeCountry': 'routeCountryCode', 'alts': 'alternateURLs'}
saved_keys = re.findall(r'"(\w+)"\s*:\s*\$0\.(\w+)', save_src)
assert saved_keys, 'save dictionary not found'
for k, a in saved_keys:
    assert attr.get(k) == a, f'unexpected save mapping {k}->{a}: review model'
saved_attrs = {a for _, a in saved_keys}
mode = 'fixed' if 'alternateURLs' in saved_attrs else 'loss'

SEP = '\n'  # design: alts is ONE string value so the [[String:String]] cast still holds

def save(rows):
    out = []
    for r in rows:
        d = {}
        for k, a in saved_keys:
            v = r[a]
            d[k] = SEP.join(v) if isinstance(v, list) else v
        out.append(d)
    return out

def load(rows):
    # Swift: whole-array cast to [[String:String]]; required keys name+url; optionals default ""
    if not isinstance(rows, list) or any(not isinstance(x, dict) or any(not isinstance(v, str) for v in x.values()) for x in rows):
        return []
    res = []
    for d in rows:
        if 'name' not in d or 'url' not in d: continue
        alts = []
        if mode == 'fixed':
            for u in d.get('alts', '').split(SEP):
                u = u.strip()
                if u and u != d['url'] and u not in alts: alts.append(u)
        res.append({'name': d['name'], 'streamURL': d['url'], 'alternateURLs': alts,
                    'tvgID': d.get('tvgID', '').lower(), 'countryCode': d.get('country', '').lower(),
                    'routeCountryCode': d.get('routeCountry', '').lower()})
    return res

def failover(ch):
    """Candidates tryNextAlternateURL would play, in order, then the 'all URLs failed' stop."""
    seq, i = [], 0
    while i < len(ch['alternateURLs']):
        seq.append(ch['alternateURLs'][i]); i += 1
    seq.append('ALL_FAILED'); return seq

M, A1, A2 = 'https://example.invalid/main', 'https://example.invalid/mirror1', 'https://example.invalid/mirror2'
ch = {'name': 'Café News', 'streamURL': M, 'alternateURLs': [A1, A2], 'tvgID': 'news.tr', 'countryCode': 'tr', 'routeCountryCode': 'de'}
got = load(save([ch]))[0]

# controls (hold in both modes): identity and defaults survive
assert got['name'] == ch['name'] and got['streamURL'] == M and got['tvgID'] == 'news.tr' and got['countryCode'] == 'tr' and got['routeCountryCode'] == 'de'
assert failover(ch) == [A1, A2, 'ALL_FAILED']
legacy = load([{'name': 'a', 'url': 'u'}, {'name': 'bad'}])
assert len(legacy) == 1 and legacy[0]['alternateURLs'] == [] and legacy[0]['tvgID'] == '' and failover(legacy[0]) == ['ALL_FAILED']
legacy2 = load([{'name': 'a', 'url': 'u', 'tvgID': 'X', 'country': 'TR'}])[0]  # old 4-field record
assert legacy2['alternateURLs'] == [] and legacy2['tvgID'] == 'x' and legacy2['routeCountryCode'] == ''  # record without routeCountry loads with an empty route country

result = {'mode': mode, 'source_sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
          'scope': 'source-derived schema model; no UserDefaults/restart/playback/Swift execution'}
if mode == 'loss':
    assert got['alternateURLs'] == [], 'loss expected'
    assert failover(got) == ['ALL_FAILED'] and failover(ch) != failover(got)
    result['result'] = 'PASS (loss proven): main URL/identity kept, both mirrors dropped on roundtrip'
    result['observed'] = {'before': failover(ch), 'after_reload': failover(got)}
    code = 0
else:
    assert 'alts' in load_src, 'loadFavorites must read alts'
    assert got['alternateURLs'] == [A1, A2], 'mirror order lost'
    assert failover(got) == failover(ch)
    # dedupe/normalisation invariants
    d = load([{'name': 'n', 'url': M, 'alts': SEP.join([A1, '', A1, M, ' ' + A2 + ' '])}])[0]
    assert d['alternateURLs'] == [A1, A2]
    # old record (no alts) loads; new record read by old schema = extra key ignored, cast still valid
    assert all(isinstance(v, str) for r in save([ch]) for v in r.values())
    # favorite identity unchanged: add/remove still keyed on streamURL only
    assert 'favorites.contains(where: { $0.streamURL == ch.streamURL })' in s
    assert 'favorites.removeAll { $0.streamURL == url }' in s
    # empty mirror list roundtrips to empty
    assert load(save([{**ch, 'alternateURLs': []}]))[0]['alternateURLs'] == []
    result['result'] = 'PASS (fix holds): mirrors roundtrip in order, failover identical, old records load'
    code = 0
print(json.dumps(result, indent=2, ensure_ascii=False))
sys.exit(code)
