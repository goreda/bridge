"""Offline IPTV source-bound parser/request models; no HTTP or AppKit."""
from pathlib import Path
import hashlib,json,re,itertools
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Media/IPTV.swift';s=p.read_text()
parser=s[s.index('private func parseM3U'):]
country=s[s.index('private func fetchCountryChannels'):s.index('// MARK: - List Rebuild')]
random=s[s.index('private func fetchRandomCountryChannel'):s.index('private func playRandomChannel')]
for t in ['line.hasPrefix("#EXTINF")','let comma = line.lastIndex(of: ",")','if candidate.hasPrefix("#") { break }','urlLine.hasPrefix("http") || urlLine.hasPrefix("rtsp") || urlLine.hasPrefix("rtmp")','ch.tvgID.firstIndex(of: "@")','existing.urls.append(ch.streamURL)','alternateURLs: Array(v.urls.dropFirst())']:assert t in parser,t
assert country.count('self.countryRequestGeneration == generation')==2
assert country.count('currentCode == code')==2
assert 'countryRequestGeneration += 1' in country
assert random.count('self.isRandomMode')==2
assert 'generation' not in random,'Random identity semantics changed; review model'
def cc(tid):
 tid=tid.lower().split('@',1)[0];parts=[p for p in tid.split('.') if p]
 return parts[-1] if parts and len(parts[-1])==2 else ''
def parse(text):
 lines=text.replace('\r\n','\n').replace('\r','\n').split('\n');rows=[];i=0
 def extract(line,key):
  m=re.search(key+'="([^"]*)"',line);return m.group(1).strip(' \t') if m else ''
 while i<len(lines):
  line=lines[i].strip(' \t')
  if not line.startswith('#EXTINF'):i+=1;continue
  name=extract(line,'tvg-name');tid=extract(line,'tvg-id');country=extract(line,'tvg-country').lower() or cc(tid)
  if not name and ',' in line:name=line.rsplit(',',1)[1].strip(' \t')
  j=i+1;url=''
  while j<len(lines):
   candidate=lines[j].strip(' \t')
   if not candidate:j+=1;continue
   if candidate.startswith('#'):break
   url=candidate;break
  if url and url.startswith(('http','rtsp','rtmp')) and name:
   rows.append({'name':name,'url':url,'tvgID':tid,'country':country});i=j+1
  else:i+=1
 groups={};ungrouped=[]
 for row in rows:
  if not row['tvgID']:ungrouped.append({**row,'alternates':[]});continue
  key=row['tvgID'].split('@',1)[0]
  if key in groups:groups[key]['alternates'].append(row['url'])
  else:groups[key]={**row,'alternates':[]}
 return list(groups.values())+ungrouped # Swift Dictionary iteration order unspecified
controls=[]
for eol in ['\n','\r\n','\r']:
 text=eol.join(['#EXTM3U','#EXTINF:-1 tvg-name="News" tvg-id="News.tr" tvg-country="TR",Fallback','',' https://example.invalid/live.m3u8 ','#EXTINF:-1,Radio','rtsp://example.invalid/radio'])
 got=parse(text);assert len(got)==2 and got[0]['name']=='News' and got[0]['country']=='tr';controls.append('EOL '+repr(eol)+' attributes/blank line/URL whitespace')
x=parse('#EXTINF:-1 tvg-id="News.us@HD",News\nhttps://example.invalid/hd\n#EXTINF:-1 tvg-id="News.us@SD",News SD\nhttps://example.invalid/sd\n')
assert len(x)==1 and x[0]['alternates']==['https://example.invalid/sd'] and x[0]['country']=='us';controls.append('tvg-ID quality suffix groups alternate URLs in encountered order')
x=parse('#EXTINF:-1,One\nhttps://example.invalid/1\n#EXTINF:-1,Two\nhttps://example.invalid/2\n');assert len(x)==2;controls.append('absent tvg-ID does not merge unrelated channels')
assert not parse('#EXTINF:-1,\nhttps://example.invalid/\n');assert not parse('#EXTINF:-1,News\nfile:///local\n');controls.append('missing name and local-file URL skipped')
assert cc('News.tr@HD')=='tr' and cc('News.US')=='us' and cc('News')=='';controls.append('country suffix fallback controls')
# Normal country fetch uses both request generation and visible country at
# completion and parser delivery. Keep stale-result suppression explicit.
class Country:
 def __init__(self):self.generation=0;self.screen=None;self.delivered=[]
 def start(self,code):self.generation+=1;self.screen=code;return self.generation
 def apply(self,gen,code):
  if self.generation==gen and self.screen==code:self.delivered.append(code)
x=Country();a=x.start('tr');b=x.start('us');x.apply(a,'tr');x.apply(b,'us');assert x.delivered==['us'];controls.append('old country completion rejected after replacement')
x=Country();a=x.start('tr');x.screen='favorites';x.apply(a,'tr');assert not x.delivered;controls.append('country result rejected after leaving country screen')
x=Country();a=x.start('tr');b=x.start('tr');x.apply(a,'tr');x.apply(b,'tr');assert x.delivered==['tr'];controls.append('same-country ABA guarded by generation')
reds=[]
x=parse('#EXTINF:-1,News\n#EXTVLCOPT:http-referrer=https://example.invalid\nhttps://example.invalid/live\n');assert not x;reds.append({'case':'intervening player directive','observed':'otherwise named HTTP channel dropped after comment/directive'})
x=parse('#EXTINF:-1,News\nhttp-not-a-url\n');assert x[0]['url']=='http-not-a-url';reds.append({'case':'prefix-only URL admission','observed':'malformed http-prefixed string enters channel list'})
x=parse('#EXTINF:-1,News\nHTTPS://example.invalid/live\n');assert not x;reds.append({'case':'uppercase scheme','observed':'uppercase HTTPS omitted by case-sensitive prefix gate'})
x=parse('#EXTINF:-1,News, International\nhttps://example.invalid/live\n');assert x[0]['name']=='International';reds.append({'case':'comma in display name','observed':'last-comma fallback loses leading display-name text'})
# Source's random path has only a boolean check at both stages.
mode=True;old_request='A';mode=False;mode=True
played=[]
if mode:played.append(old_request)
assert played==['A'];reds.append({'case':'random stop/restart ABA','observed':'A request remains eligible when boolean returns true in new random session','scope':'ownership model, native URLSession ordering unverified'})
print(json.dumps({'result':'PASS controls and expected known-red characterization','controls':controls,'known_red':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['Swift regex/String/Dictionary parity','random request cancellation/retry bounds','playlist HTTP status/charset/provider behavior','EPG, favorites persistence, quality switching and AppKit pixels not covered'],'scope':'Synthetic Python parser/state ports + current Swift source guards; no live playlist request or Swift/native execution'},indent=2))
