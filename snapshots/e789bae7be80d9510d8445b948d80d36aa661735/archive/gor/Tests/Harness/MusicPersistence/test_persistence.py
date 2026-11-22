"""Actual isolated JSON persistence functions on temporary fixture paths (current mus2: atomic write + corrupt quarantine)."""
from pathlib import Path
import json,ast,tempfile,hashlib,builtins,os,time
root=Path(__file__).resolve().parents[3];p=root/'Resources/vendor/mus2/mus2.py';s=p.read_text();tree=ast.parse(s)
names={'_atomic_write_json','_load_json_list','_save_json','load_playlists','save_playlists','load_local_libraries','save_local_libraries'}
nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in names];assert len(nodes)==len(names)
code=compile(ast.Module(body=nodes,type_ignores=[]),'current-mus2-json-persistence','exec')
controls=[];findings=[];logs=[]
with tempfile.TemporaryDirectory() as td:
 pl=Path(td)/'playlists.json';local=Path(td)/'local.json'
 ns={'json':json,'os':os,'time':time,'log':lambda *a:logs.append(a),'PL_FILE':str(pl),'LOCAL_LIBRARIES_FILE':str(local)};exec(code,ns)
 for kind,path in [('playlists',pl),('local_libraries',local)]:
  load,save=ns['load_'+kind],ns['save_'+kind];assert load()==[];controls.append(kind+' missing file defaults empty')
  data=[{'id':'1','name':'Café 😀','items':['a','b']}] if kind=='playlists' else [{'path':'/synthetic/café','name':'Music'}]
  assert save(data) is True and load()==data;controls.append(kind+' Unicode JSON roundtrip, save returns True')
  path.write_text('{bad');assert load()==[];q=[f for f in os.listdir(td) if f.startswith(path.name+'.corrupt-')];assert len(q)==1 and not path.exists();controls.append(kind+' malformed JSON defaults empty and is quarantined, not overwritten')
  for f in q:os.unlink(Path(td)/f)
  save(data)
 # Failure injection after the temp file is opened: the previous file must stay byte-identical, no temp left.
 class Broken:
  def __init__(self,path,mode,**kw):self.real=builtins.open(path,mode,**kw)
  def __enter__(self):return self
  def __exit__(self,*args):self.real.close()
  def write(self,text):self.real.write(text[:1]);self.real.flush();raise OSError('synthetic write failure')
  def flush(self):self.real.flush()
  def fileno(self):return self.real.fileno()
 ns['open']=lambda path,mode='r',**kw:Broken(path,mode,**kw) if mode=='w' else builtins.open(path,mode,**kw)
 for kind,path in [('playlists',pl),('local_libraries',local)]:
  before=path.read_bytes();n=len(logs)
  assert ns['save_'+kind]([{'new':'replacement'}]) is False and len(logs)>n
  assert path.read_bytes()==before and ns['load_'+kind]()!=[] and not [f for f in os.listdir(td) if '.tmp-' in f]
  controls.append(kind+' write failure: previous file byte-identical, no temp left, save returns False and logs')
 del ns['open']
 pl.write_text('{}');assert ns['load_playlists']()==[];assert [f for f in os.listdir(td) if f.startswith('playlists.json.corrupt-')];controls.append('wrong JSON root shape is quarantined and loads as empty list')
print(json.dumps({'result':'PASS actual JSON persistence controls/fault injection (atomic write, quarantine)','controls':controls,'characterizations':findings,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['compiled mus2 parity','real disk permissions/concurrent writes/recovery','playlist/library schema/migration and user-visible error handling'],'scope':'Actual isolated current Python JSON load/save on temporary fixture files only; no user state/backend imports/pickle/network/Swift/UI execution'},indent=2))
