"""Execute only current scan/classify AST functions in synthetic temp folders."""
from pathlib import Path
import ast,os,re,json,tempfile,hashlib,types
root=Path(__file__).resolve().parents[3];source=root/'Resources/vendor/mus2/mus2.py';text=source.read_text();tree=ast.parse(text)
nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['scan_local_path','classify_contents'] or isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='AUDIO_EXTS' for t in n.targets)]
assert len(nodes)==3
scope={'os':os,'re':re,'log':lambda *args:None};exec(compile(ast.Module(body=nodes,type_ignores=[]),'current-mus2-scan','exec'),scope);scan=scope['scan_local_path'];classify=scope['classify_contents']
controls=[];findings=[]
with tempfile.TemporaryDirectory() as td:
 p=Path(td);album=p/'Album';album.mkdir();(album/'01 - Café.FLAC').touch();(album/'02_Song.mp3').touch();(album/'notes.txt').touch();(p/'.hidden').mkdir();(p/'.hidden'/'x.mp3').touch();(p/'empty').mkdir();nested=p/'Artist';nested.mkdir();(nested/'Subalbum').mkdir()
 rows=scan(td);assert [r['name'] for r in rows]==['Album','Artist'];assert rows[0]['type']=='album' and rows[1]['type']=='folder';assert [r['title'] for r in rows[0]['tracks']]==['Café','Song'];controls.append('album/folder/hidden/empty admission and title prefix cleanup')
 assert [r['n'] for r in rows[0]['tracks']]==[0,1] and all(r['local_path']==r['file'] for r in rows[0]['tracks']);controls.append('track indices and local path identity')
 assert scan(str(p/'missing'))==[];controls.append('missing root empty result')
 for ext in scope['AUDIO_EXTS']:(album/('test'+ext.upper())).touch()
 audio,_=classify(str(album));assert len(audio)==2+len(scope['AUDIO_EXTS']);controls.append('every current audio extension uppercase accepted')
 (p/'root-track.mp3').touch();assert all(r.get('path')!=str(p/'root-track.mp3') for r in scan(td));findings.append({'case':'audio directly in selected root','observed':'root tracks omitted, scanner lists child folders only','scope':'actual isolated current scan, root-entry contract may be intentional'})
 child=album/'Nested';child.mkdir();(child/'lost.mp3').touch();row=next(r for r in scan(td) if r['name']=='Album');assert row['type']=='album' and 'has_subdirs' not in row;findings.append({'case':'folder with direct audio and nested album','observed':'classified only as album; nested directory not represented in this result','scope':'actual scan output, UI access through other routes unverified'})
 (album/'.secret.mp3').touch();audio,_=classify(str(album));assert str(album/'.secret.mp3') in audio;findings.append({'case':'hidden audio inside visible album','observed':'included despite hidden child folders being skipped'})
 (p/'Alias').symlink_to(album,target_is_directory=True);rows=scan(td);assert {'Alias','Album'} <= {r['name'] for r in rows};findings.append({'case':'symlink album alias','observed':'both alias and target listed, no realpath dedupe','scope':'synthetic symlink behavior, may be intended'})
# Exercise permission-error handling deterministically without relying on UID.
fake=types.SimpleNamespace(path=os.path,listdir=lambda _:(_ for _ in ()).throw(PermissionError('fixture')))
ns={'os':fake,'re':re,'log':lambda *args:None};exec(compile(ast.Module(body=nodes,type_ignores=[]),'permission-fixture','exec'),ns)
with tempfile.TemporaryDirectory() as td:
 assert ns['scan_local_path'](td)==[] and ns['classify_contents'](td)==([],[])
controls.append('injected permission error returns empty without crash')
print(json.dumps({'result':'PASS actual isolated source functions on synthetic filesystem','controls':controls,'characterizations':findings,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'scope':'Actual current Python scan/classify functions, temp empty fixture files only. Not compiled mus2 binary, user library/music decoding/network/Swift/UI proof'},indent=2))
