"""Actual isolated pure music metadata helpers with invented inputs."""
from pathlib import Path
import ast,json,re,urllib.parse,hashlib
root=Path(__file__).resolve().parents[3];p=root/'Resources/vendor/mus2/mus2.py';s=p.read_text();nodes=[n for n in ast.parse(s).body if isinstance(n,ast.FunctionDef) and n.name in ['is_music','fmt_duration','archive_url'] or isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='AUDIO_TAGS' for t in n.targets)];assert len(nodes)==4
ns={'re':re,'urllib':urllib,'_url_cache':{}};exec(compile(ast.Module(body=nodes,type_ignores=[]),'actual-current-metadata','exec'),ns)
controls=[];findings=[]
for tag in ns['AUDIO_TAGS']:assert ns['is_music']('Album ('+tag.upper()+')')
controls.append('all current audio tags case-insensitive admission')
assert not ns['is_music']('Album (pdf)');assert not ns['is_music']('Plain Album');assert ns['is_music']('Album (flac+pdf)');controls.append('nonmusic exclusion and mixed audio tag current precedence')
for secs,want in [(0,'0:00'),(59,'0:59'),(60,'1:00'),(3600,'60:00'),('90.9','1:30')]:assert ns['fmt_duration'](secs)==want
for secs in [None,'bad',float('nan'),float('inf')]:assert ns['fmt_duration'](secs)==''
controls.append('duration boundaries/float string/invalid input')
for title in ['Café 😀','a/b?x=1&z=#q','a"b\\c','line\nnext']:
 url=ns['archive_url']({'collection':'fixture','title':title});tail=url.split('/fixture/',1)[1];assert urllib.parse.unquote(tail[:-4])==title and '?' not in tail and '#' not in tail
controls.append('title URL escaping roundtrips delimiters and Unicode')
a=ns['archive_url']({'collection':'fixture','title':'Album'});b=ns['archive_url']({'collection':'fixture','title':'Album','ext':'.rar'});assert a.endswith('.zip') and b.endswith('.rar') and a!=b;controls.append('cache identity includes extension/default ZIP')
assert ns['is_music']('flaccid (book)');findings.append({'case':'tag substring in ordinary word','observed':'flac substring admits flaccid','scope':'synthetic metadata, real collection false positive not observed'})
assert ns['fmt_duration'](-1)=='-1:59';findings.append({'case':'negative duration','observed':'negative minute plus modulo seconds emitted, no nonnegative gate'})
url=ns['archive_url']({'collection':'fixture/child','title':'Album','ext':'?query'});assert '/fixture/child/' in url and url.endswith('?query');findings.append({'case':'collection/extension unsanitized','observed':'only title quoted; synthetic collection/ext can alter path/query','scope':'normal trusted source collection/ext producer contract unverified; not exploit claim'})
print(json.dumps({'result':'PASS actual metadata helper controls and input characterizations','controls':controls,'characterizations':findings,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'scope':'Actual isolated Python pure helpers/invented inputs only; no provider/backend module/compiled helper/user cache/network/Swift/UI execution'},indent=2))
