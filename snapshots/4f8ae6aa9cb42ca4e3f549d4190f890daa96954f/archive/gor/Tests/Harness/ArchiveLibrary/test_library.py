"""Offline current ArchiveLibrary CSV/cache state port, not Swift/disk execution."""
from pathlib import Path
import json,hashlib,itertools
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Media/ArchiveLibrary.swift';s=p.read_text()
for t in ['if next < raw.endIndex && raw[next] == "\\\""','currentField.append("\\\"")','case "\\r":','case "\\n":','try? data.write(to: url, options: .atomic)','let changed = Set(result) != Set(self.titles)','return fetchFailed ? nil : result','if let cached = loadCacheFromDisk(), !cached.isEmpty','initial fetch failed; retry available on next load']:assert t in s,t
load=s[s.index('func load()'):s.index('func refreshInBackground()')]
refresh=s[s.index('func refreshInBackground()'):s.index('func reload()')]
assert load.index('guard self.isLoaded else')<load.index('self.pendingCallbacks = []')
assert refresh.index('self.isFetching = false')<refresh.index('self.writeCacheToDisk(result)')
assert 'DispatchQueue.global(qos: .utility).async {' in refresh
assert 'generation' not in refresh,'cache write identity changed; review ordering model'
def csv(raw):
 rows=[];row=[];field='';quotes=False;i=0
 while i<len(raw):
  char=raw[i]
  if quotes:
   if char=='"':
    if i+1<len(raw) and raw[i+1]=='"':field+='"';i+=2;continue
    quotes=False
   else:field+=char
  elif char=='"':quotes=True
  elif char==',':row.append(field);field=''
  elif char in ['\r','\n']:
   row.append(field);field='';rows.append(row);row=[]
   if char=='\r' and i+1<len(raw) and raw[i+1]=='\n':i+=1
  else:field+=char
  i+=1
 if field or row:row.append(field);rows.append(row)
 if rows and rows[-1]==['']:rows.pop()
 return rows
controls=[]
for eol in ['\n','\r','\r\n']:
 assert csv('a,b'+eol+'c,d'+eol)==[['a','b'],['c','d']]
 controls.append('CSV '+repr(eol)+' row boundaries/trailing terminator')
assert csv('"a,b","c""d",x\n')==[['a,b','c"d','x']];controls.append('quoted comma/escaped quote')
assert csv('"a\r\nb",c')==[['a\r\nb','c']];controls.append('embedded quoted newline retained')
assert csv('a,,')==[['a','','']];assert csv('')==[];controls.append('empty input/trailing empty fields')
assert csv('"café 😀",世界')==[['café 😀','世界']];controls.append('Unicode fields without byte splitting')
class Library:
 def __init__(self):self.titles=[];self.loaded=False;self.fetching=False;self.pending=[];self.calls=[];self.writes=[];self.disk=None
 def load(self,callback,cache=None):
  if self.loaded:self.calls.append(callback);return
  if self.fetching:self.pending.append(callback);return
  self.current=callback
  if cache:self.titles=cache;self.loaded=True;self.calls.append(callback);self.fetching=True;return
  self.fetching=True
 def initial(self,result):
  if result:self.titles=result;self.loaded=True;self.disk=result
  self.fetching=False
  if not self.loaded:return
  self.calls+=[self.current]+self.pending;self.pending=[]
 def refresh(self,result):
  self.fetching=False
  if result and set(result)!=set(self.titles):self.titles=result;self.calls.append('updated');self.writes.append(result)
  self.calls+=self.pending;self.pending=[]
x=Library();x.load('loaded',cache=['old']);assert x.titles==['old'] and x.calls==['loaded'];x.refresh(None);assert x.titles==['old'];controls.append('instant disk cache + failed refresh never blanks titles')
x=Library();x.load('A');x.load('B');x.initial(['first']);assert x.calls==['A','B'];controls.append('successful initial fetch delivers owner + queued callback')
x=Library();x.load('A');x.initial(None);assert not x.loaded and not x.fetching;x.load('B');x.initial(['retry']);assert x.loaded and x.calls==['B'];controls.append('first failure permits successful next load retry')
x=Library();x.titles=['a','b'];x.loaded=True;x.refresh(['b','a']);assert not x.writes and not x.calls;controls.append('reorder-only refresh causes no update/write')
x.refresh(['a','c']);assert x.titles==['a','c'] and x.calls==['updated'] and x.writes==[['a','c']];controls.append('changed refresh updates UI and schedules persistence')
reds=[]
x=Library();x.titles=['old'];x.loaded=True;x.refresh(['A']);x.fetching=True;x.refresh(['B']);assert x.titles==['B']
for write in reversed(x.writes):x.disk=write
assert x.disk==['A'];reds.append({'case':'off-main cache writes complete out of order','observed':'memory B, disk older A even though each write is atomic','scope':'adversarial completion model, actual filesystem queue ordering unverified'})
x=Library();x.load('A');x.load('queued-A');x.initial(None);x.load('retry-B');x.initial(['ok']);assert x.calls==['retry-B','queued-A'];reds.append({'case':'failed first-fetch queued callback retained','observed':'old queued callback delivered on later success','scope':'lifetime characterization, may be intended waiting-client behavior'})
assert csv('""')==[];reds.append({'case':'single quoted empty field at EOF','observed':'empty row omitted, identical to empty input','scope':'parser characterization, impact on Sheets rows unverified'})
assert csv('"unterminated')==[['unterminated']];reds.append({'case':'unterminated quote','observed':'accepted field without syntax error','scope':'malformed-input permissiveness, not current Sheets failure'})
print(json.dumps({'result':'PASS controls and expected cache/parser characterizations','controls':controls,'known_red_or_characterization':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['Swift Character/regex/link extraction parity','real Sheets HTTP/source merge/provider availability','actual atomic-write ordering and disk errors','callback owner replacement/thread discipline','title deduplication/manual-source/empty-library semantics'],'scope':'Python ports/current Swift source guards only; no Swift/Foundation/network/disk/AppKit execution'},indent=2))
