"""Current provider route classifier source port; no provider/network action."""
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Media/CDPSession.swift';s=p.read_text();a=s[s.index('static func classifyURL'):s.index('// MARK: - State')]
for t in ['url.hasPrefix("mega-folder::")','link.host(is: "mega.nz")','link.pathAfter("/folder/")','link.host(is: "transfer.it")','link.firstSegment(after: "/d/")','link.firstSegment(after: "/file/d/")','link.pathAfter("/u/")','link.pathAfter("/download/")']:assert t in a,t
assert 'URLComponents' in s[s.index('private static func parsedLink'):s.index('static func classifyURL')] and 'url.contains(' not in a,'classifier admission is host-parsed; substring routing must not return'
from urllib.parse import urlsplit,unquote,parse_qs
def parsed(u):
 try:c=urlsplit(u)
 except ValueError:return None
 if c.scheme.lower() not in('http','https') or not c.hostname:return None
 return c.hostname.lower(),unquote(c.path),c.query
def host_is(h,n):return h==n or h.endswith('.'+n)
def after(path,prefix):return path[len(prefix):] if path.startswith(prefix) else None
def seg(path,prefix):
 r=after(path,prefix);return None if r is None else (r.split('/')[0] if r else '')
def classify(u):
 for prefix,kind in [('mega-folder::','megaFolder'),('transferit-folder::','transferFolder')]:
  if u.startswith(prefix):
   parts=u.split('::');return kind,parts[1] if len(parts)>1 else '',parts[2] if len(parts)>2 else ''
 if u.startswith('gofile-folder::'):return 'gofileFolder',u.split('::')[1] if u.count('::')>=1 else ''
 if u.startswith('gofile-direct::'):return 'gofileDirect',u
 pl=parsed(u)
 if pl is None:return None
 h,path,query=pl;frag=u.split('#',1)[1] if '#' in u else ''
 if host_is(h,'mega.nz'):
  r=after(path,'/folder/')
  if r is not None:return 'mega',r.split('/')[0],frag
  r=after(path,'/file/')
  if r is not None:return 'megaFile',r.split('/')[0],frag
 if host_is(h,'transfer.it'):return ('transfer',)
 if host_is(h,'gofile.io'):
  if path.startswith('/download/') or h!='gofile.io':return 'gofile',''
  r=seg(path,'/d/')
  if r is not None:return 'gofile',r
 if h=='drive.google.com':
  r=seg(path,'/file/d/')
  if r is not None:return 'driveFile',r
  r=seg(path,'/drive/folders/')
  if r is not None:return 'driveFolder',r
  if path=='/uc' and 'export=download' in query:return 'driveFile',''
 if h=='drive.usercontent.google.com' and path=='/download':
  q=parse_qs(query);return 'driveFile',(q.get('id') or [''])[0]
 if host_is(h,'pixeldrain.com'):
  for m in ['/u/','/api/file/']:
   r=seg(path,m)
   if r is not None:return 'pixeldrain',r
 if host_is(h,'archive.org'):
  r=seg(path,'/details/@')
  if r is not None:return ('archiveProfile',r) if r else None
  r=seg(path,'/download/')
  if r is not None:return ('archiveItem',r) if r else None
 return None
controls=[]
fixtures=[('https://mega.nz/folder/abc#key',('mega','abc','key')),('https://mega.nz/file/abc#key',('megaFile','abc','key')),('mega-folder::https://mega.nz/folder/abc#key::handle',('megaFolder','https://mega.nz/folder/abc#key','handle')),('https://transfer.it/share',('transfer',)),('https://gofile.io/d/content',('gofile','content')),('https://drive.google.com/file/d/abc/view',('driveFile','abc')),('https://drive.google.com/drive/folders/abc',('driveFolder','abc')),('https://pixeldrain.com/u/abc?download',('pixeldrain','abc')),('https://archive.org/details/@name/lists/1',('archiveProfile','name')),('https://archive.org/download/item/movie.mp4',('archiveItem','item')),('https://example.invalid/x',None)]
for url,want in fixtures:assert classify(url)==want;controls.append(url)
findings=[]
for url in ['https://unrelated.invalid/?next=https://transfer.it/share','https://unrelated.invalid/archive.org/download/item/movie.mp4','https://unrelated.invalid/mega.nz/folder/abc#key']:
 assert classify(url) is None;controls.append('off-host route rejected: '+url)
assert classify('HTTPS://ARCHIVE.ORG/download/item/file')==('archiveItem','item');controls.append('uppercase scheme/host admitted (host lowercased)')
assert classify('mega-folder::')==('megaFolder','','');findings.append({'case':'empty internal pseudo-link','observed':'empty handle/share admitted','scope':'internal provenance/input validity unverified'})
print(json.dumps({'result':'PASS provider route controls (host-parsed admission) and characterizations','controls':controls,'characterizations':findings,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'scope':'Python classifier port/current Swift guards, no Swift/Foundation/browser/network/provider execution'},indent=2))
