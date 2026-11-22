"""Current favorites schema/admission port; no real UserDefaults or playback."""
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Media/IPTV.swift';s=p.read_text();a=s[s.index('private func addCurrentToFavorites'):s.index('// MARK: - HLS Quality')]
for t in ['favorites.contains(where: { $0.streamURL == ch.streamURL })','favorites.removeAll { $0.streamURL == url }','as? [[String: String]]','guard let name = d["name"], let url = d["url"]','UserDefaults.standard.set(arr, forKey: favKey)']:assert t in a,t
for t in ['"routeCountry": $0.routeCountryCode','"alts":    $0.alternateURLs.joined(separator: "\\n")','(d["alts"] ?? "")','routeCountryCode: d["routeCountry"] ?? ""']:assert t in a,'schema changed: review mirror persistence model: '+t
assert 'private let favKey = "iptv.favorites.v1"' in s
assert 'guard currentAlternateIndex < ch.alternateURLs.count' in s
fields={'name':'name','url':'url','tvgID':'tvgID','country':'country','routeCountry':'routeCountry'}
def save(rows):return [{**{k:row.get(v,'') for k,v in fields.items()},'alts':'\n'.join(row.get('alternates',[]))} for row in rows]
def load(rows):
 # Swift's whole-array cast rejects if any value is not a String.
 if not isinstance(rows,list) or any(not isinstance(r,dict) or any(not isinstance(v,str) for v in r.values()) for r in rows):return []
 out=[]
 for r in rows:
  if 'name' not in r or 'url' not in r:continue
  seen={r['url']};alts=[]
  for u in r.get('alts','').split('\n'):
   u=u.strip()
   if u and u not in seen:seen.add(u);alts.append(u)
  out.append({**{k:r.get(v,'') for k,v in fields.items()},'alternates':alts})
 return out
def add(rows,ch):
 if ch is not None and not any(r['url']==ch['url'] for r in rows):rows.append(ch)
controls=[]
channel={'name':'Café News','url':'https://example.invalid/main','tvgID':'news.tr','country':'tr','routeCountry':'de','alternates':[]}
assert load(save([channel]))==[channel];controls.append('five persisted fields (name,url,tvgID,country,routeCountry) Unicode roundtrip')
x=[];add(x,None);assert not x;controls.append('no played channel does not add')
add(x,channel);add(x,channel.copy());assert len(x)==1;controls.append('same streamURL dedupe')
add(x,{**channel,'url':'https://example.invalid/other'});assert len(x)==2;controls.append('distinct URL preserved even same name/ID')
x=[r for r in x if r['url']!=channel['url']];assert len(x)==1;controls.append('remove matches exact streamURL')
assert load([{'name':'a','url':'u'},{'name':'bad'}])==[{'name':'a','url':'u','tvgID':'','country':'','routeCountry':'','alternates':[]}];controls.append('legacy missing optional fields default; missing required row omitted')
reds=[]
ch={**channel,'alternates':['https://example.invalid/mirror1','https://example.invalid/mirror2']};got=load(save([ch]))[0];assert got['alternates']==ch['alternates'];controls.append('favorite mirrors roundtrip in order as one newline-joined alts string (source persists them; see IPTVFavoriteMirrors for the full schema model)')
assert load([{'name':'ok','url':'u'},{'name':'bad','url':42}])==[];reds.append({'case':'one nonstring value in persisted array','observed':'whole typed-array cast fails; otherwise valid rows not recovered','scope':'Swift cast behavior source model, native bridging not executed'})
assert load([{'name':'','url':''}]);reds.append({'case':'empty name/URL strings','observed':'required key presence accepted without nonempty/URL validation','scope':'synthetic stored state; no real corrupt preference read'})
print(json.dumps({'result':'PASS favorites schema controls and loss/admission characterizations','controls':controls,'characterizations':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['native UserDefaults bridging/persistence/restart parity','favorite identity/migration/quality-selection intent','real mirror failure/playback and UI'],'scope':'Python schema/state port + current Swift source guards, no actual preferences/stream/network/Swift/UI action'},indent=2))
