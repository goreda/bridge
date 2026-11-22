"""Current HLS resolver source-bound port; no fetch/playback/native URL execution."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
from urllib.parse import urlsplit,urlunsplit,urljoin
import json,hashlib
root=Path(__file__).resolve().parents[3];p=_pp_split().path(root,'PPController_Features.swift');s=p.read_text()
a=s[s.index('static func resolveHLSVariant'):s.index('// MARK: - InputController')]
play=s[s.index('panel.onPlayURL ='):s.index('panel.onClose =')]
for t in ['masterURL.lowercased().contains(".m3u8")','line.hasPrefix("#EXT-X-STREAM-INF:")','line.dropFirst(18).components(separatedBy: ",")','bw = max(bw, v)','base.deleteLastPathComponent()','variantURLStr = base.absoluteString + variantURLStr','variants.sorted { $0.bandwidth > $1.bandwidth }','completion(masterURL, [])']:assert t in a,t
assert 'MPVCommand.make(["loadfile", resolvedURL])' in play
for t in ['self.iptvLoadGeneration &+= 1','let generation = self.iptvLoadGeneration','guard let self, self.iptvLoadGeneration == generation else { return }']:assert t in play,'playback ownership changed, review port: '+t
assert play.index('guard let self, self.iptvLoadGeneration == generation else { return }')<play.index('MPVCommand.make(["loadfile", resolvedURL])'),'owner check must precede loadfile'
def resolve(master,text):
 if '.m3u8' not in master.lower():return master,[]
 lines=text.replace('\r','\n').split('\n');variants=[];i=0
 while i<len(lines):
  line=lines[i]
  if line.startswith('#EXT-X-STREAM-INF:'):
   bw=0;res=''
   for part in line[18:].split(','):
    part=part.strip(' \t')
    if part.startswith('BANDWIDTH='):
     try:bw=max(bw,int(part[10:]))
     except ValueError:pass
    if part.startswith('RESOLUTION='):res=part[11:]
   i+=1
   if i<len(lines):
    uri=lines[i].strip(' \t')
    if uri and not uri.startswith('#'):
     if not uri.startswith('http'):
      v=urlsplit(master);base=urlunsplit((v.scheme,v.netloc,v.path.rsplit('/',1)[0]+'/',v.query,v.fragment));uri=base+uri
     variants.append({'bandwidth':bw,'resolution':res,'url':uri})
  i+=1
 variants.sort(key=lambda row:-row['bandwidth'])
 return (variants[0]['url'],variants) if variants else (master,[])
master='https://example.invalid/live/master.m3u8';controls=[]
text='#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=640x360\nlow.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\nhttps://cdn.invalid/high.m3u8\n'
best,rows=resolve(master,text);assert best=='https://cdn.invalid/high.m3u8' and rows[1]['url']=='https://example.invalid/live/low.m3u8';controls.append('highest bandwidth sort, absolute and simple relative path')
assert resolve(master,'#EXTM3U\n#EXTINF:1\nsegment.ts\n')==(master,[]);controls.append('media/no-variant playlist fallback')
assert resolve('https://example.invalid/video.mp4',text)==('https://example.invalid/video.mp4',[]);controls.append('non-m3u8 URL pass-through')
best,rows=resolve(master,'#EXT-X-STREAM-INF:BANDWIDTH=bad,RESOLUTION=1280x720\na.m3u8\n');assert rows[0]['bandwidth']==0;controls.append('invalid bandwidth currently zero, still admitted')
assert resolve(master,'#EXT-X-STREAM-INF:BANDWIDTH=1\n#comment\n')==(master,[]);controls.append('comment as immediate variant URI omitted')
reds=[]
for uri in ['/high.m3u8','//cdn.invalid/high.m3u8','../high.m3u8']:
 best,rows=resolve(master,'#EXT-X-STREAM-INF:BANDWIDTH=1\n'+uri+'\n');expected=urljoin(master,uri);assert best!=expected
 reds.append({'case':'URI '+uri,'observed':best,'reference_resolution':expected,'scope':'Python URI-reference comparison, no Foundation/native playback'})
assert resolve(master,'#EXT-X-STREAM-INF:BANDWIDTH=1\n\nhigh.m3u8\n')==(master,[]);reds.append({'case':'blank before variant URI','observed':'variant lost; only immediate next line inspected'})
assert resolve(master,' #EXT-X-STREAM-INF:BANDWIDTH=1\nhigh.m3u8\n')==(master,[]);reds.append({'case':'leading tag whitespace','observed':'variant lost; parser does not trim tag line','scope':'permissiveness characterization, not valid-HLS compliance claim'})
# Port of the iptvLoadGeneration owner check: a completion whose generation is stale plays nothing and lists nothing.
generation=0;played=[]
def select():
 global generation
 generation+=1;return generation
def completion(gen,url):
 if gen!=generation:return
 played.append(url)
a=select();b=select();completion(b,'url-B');completion(a,'url-A')
assert played==['url-B'];controls.append('selection A/B: a late A resolve completion is dropped by the iptvLoadGeneration owner check (source guard precedes loadfile)')
print(json.dumps({'result':'PASS controls and expected HLS characterizations','controls':controls,'known_red_or_characterization':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['Foundation deleteLastPathComponent/URL query-fragment parity','HLS audio-group/codec/redirect/HTTP handling','equal bandwidth order and quoted attributes','native selected-channel switching/quality UI/mpv playback'],'scope':'Python port + current Swift source guards; no HLS/network/Swift/UI execution'},indent=2))
