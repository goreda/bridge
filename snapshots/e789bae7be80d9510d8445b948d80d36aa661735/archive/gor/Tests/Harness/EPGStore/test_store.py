"""Offline EPG cache/fallback source port; no provider or XML parse."""
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Media/IPTV.swift';s=p.read_text();a=s[s.index('private final class EPGStore'):s.index('// MARK: - XMLTV Parser')]
for t in ['cacheTTL: TimeInterval = 6 * 3600','waiters[code, default: []].append(completion)','if loading.contains(code) { return }','self.waiters.removeValue(forKey: code)','httpStatus == 200','if !parsed.isEmpty {','self.cacheTime[code] = Date()','self.failed[code] = Date()']:assert t in a,t
fetch=a[a.index('private func fetchFrom'):a.index('private func downloadEPG')];assert fetch.count('self.parseAndStore')==2
class Store:
 TTL=21600
 def __init__(self):self.cache={};self.times={};self.failed={};self.loading=set();self.waiters={};self.calls=[];self.requests=[]
 def fetch(self,code,who,now):
  if code in self.cache and now-self.times[code]<self.TTL:self.calls.append((who,self.cache[code]));return
  for d in [self.cache,self.times]:d.pop(code,None)
  if code in self.failed and now-self.failed[code]<self.TTL:self.calls.append((who,{}));return
  self.failed.pop(code,None);self.waiters.setdefault(code,[]).append(who)
  if code in self.loading:return
  self.loading.add(code);self.requests.append((code,'primary'))
 def done(self,code,parsed,now,network_failure=False):
  self.loading.discard(code)
  if network_failure:self.failed[code]=now
  elif parsed:self.cache[code]=parsed;self.times[code]=now
  for who in self.waiters.pop(code,[]):self.calls.append((who,parsed))
 def primary(self,code,http,body,parsed,now):
  if http==200 and body:self.done(code,parsed,now)
  else:self.requests.append((code,'fallback'))
controls=[]
x=Store();x.fetch('tr','A',0);x.fetch('tr','B',1);assert x.requests==[('tr','primary')];x.done('tr',{'news':1},2);assert x.calls==[('A',{'news':1}),('B',{'news':1})] and not x.waiters;controls.append('inflight waiters coalesce and all delivered once')
x.fetch('tr','C',3);assert len(x.requests)==1 and x.calls[-1][0]=='C';controls.append('fresh positive cache avoids request')
x.fetch('tr','D',21602);assert len(x.requests)==2 and 'tr' not in x.cache;controls.append('TTL boundary expires cache and starts request')
x=Store();x.fetch('tr','A',0);x.done('tr',{},1,True);x.fetch('tr','B',2);assert len(x.requests)==1;x.fetch('tr','C',21601);assert len(x.requests)==2;controls.append('network negative cache expires at same 6h boundary')
x=Store();x.fetch('tr','A',0);x.primary('tr',404,b'error',{},1);assert x.requests[-1]==('tr','fallback');controls.append('non200 primary goes to fallback')
x=Store();x.fetch('tr','A',0);x.primary('tr',200,b'',{},1);assert x.requests[-1]==('tr','fallback');controls.append('empty-body primary goes to fallback')
x=Store();x.fetch('tr','A',0);x.fetch('us','B',0);assert x.loading=={'tr','us'};controls.append('countries keep independent loading/waiters')
reds=[]
x=Store();x.fetch('tr','A',0);x.primary('tr',200,b'<html>not guide</html>',{},1);assert x.requests==[('tr','primary')] and x.calls==[('A',{})];reds.append({'case':'primary nonempty 200 parses empty','observed':'fallback not attempted; caller gets empty guide','scope':'synthetic provider reply, not current live outage'})
x.fetch('tr','B',2);assert len(x.requests)==2 and 'tr' not in x.failed;reds.append({'case':'empty parsed success repeats','observed':'no positive/negative cache, next request repeats primary','scope':'source policy characterization, actual frequency unmeasured'})
# Source's fallback fuzzy first(where:) can pick prefix sibling; keep order
# ambiguity explicit rather than pretending Python insertion order is Swift.
assert 'data.first(where:' in a and 'k.hasPrefix(norm) || norm.hasPrefix(k)' in a
reds.append({'case':'fuzzy prefix guide match','observed':'first matching prefix wins with Dictionary iteration, no exact identity assurance','scope':'caller-dependent channel ambiguity, actual wrong guide not proved'})
print(json.dumps({'result':'PASS cache/fallback controls and source policy characterizations','controls':controls,'characterizations':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['native URLSession/thread/cache time parity','real primary/fallback feed responses and XMLParser','normalization/channel identity preference','stale-cache preservation policy and failure TTL intent'],'scope':'Python state port + current Swift guards only; no EPG provider/network/XML/native/UI execution'},indent=2))
