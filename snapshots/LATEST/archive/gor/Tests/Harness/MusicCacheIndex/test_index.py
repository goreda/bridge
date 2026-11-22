"""Actual isolated cache-index/admission helpers, provider/save stubbed."""
from pathlib import Path
import ast,json,hashlib
root=Path(__file__).resolve().parents[3];p=root/'Resources/vendor/mus2/mus2.py';s=p.read_text();names={'build_cache_index','ensure_archive_cache','items_with_idx'};nodes=[n for n in ast.parse(s).body if isinstance(n,ast.FunctionDef) and n.name in names];assert len(nodes)==3
code=compile(ast.Module(body=nodes,type_ignores=[]),'actual-current-cache-index','exec')
def setup():
 effects=[];ns={'_cache_index':{},'ARCHIVE_COLLECTIONS':['fixture'],'fetch_archive_parallel':lambda sources:effects.append('fetch') or [{'source':'archive','title':'Z'},{'source':'archive','title':'A'}]};exec(code,ns)
 def save(data):effects.append('save');ns['build_cache_index'](data)
 ns['save_cache']=save;return ns,effects
controls=[];findings=[]
ns,e=setup();rows=[{'title':'A','source':'archive'},{'title':'B','source':'bandcamp'}];ns['build_cache_index'](rows);got=ns['items_with_idx'](list(reversed(rows)),rows);assert [r['cache_idx'] for r in got]==[1,0];controls.append('original object subsets/reordering preserve indexed positions')
assert ns['ensure_archive_cache'](rows) is rows and not e;controls.append('populated indexed cache avoids provider fetch')
ns,e=setup();rows=[{'source':'archive','title':'A'}];assert ns['ensure_archive_cache'](rows) is rows and ns['_cache_index'] and not e;controls.append('unindexed existing archive rebuilds without fetch')
ns,e=setup();rows=[];assert ns['ensure_archive_cache'](rows) is rows and [r['title'] for r in rows]==['A','Z'] and e==['fetch','save'];controls.append('empty cache stub fetch sorted/extended/saved/indexed')
ns['build_cache_index']([]);assert ns['_cache_index']=={};controls.append('empty rebuild clears index')
ns,e=setup();item={'title':'A'};ns['build_cache_index']([item]);assert ns['items_with_idx']([dict(item)],[item])[0]['cache_idx']==-1;findings.append({'case':'equal copied item','observed':'content-equal copy gets -1 because object identity differs','scope':'intentional identity contract may require original references'})
ns['build_cache_index']([item,item]);assert ns['items_with_idx']([item],[item,item])[0]['cache_idx']==1;findings.append({'case':'duplicate same object in cache','observed':'last duplicate position wins','scope':'synthetic duplicate input, normal producer reachability unverified'})
ns,e=setup();rows=[{'source':'bandcamp','title':'Bandcamp'}];ns['build_cache_index'](rows);ns['ensure_archive_cache'](rows);assert not e and not any(r['source']=='archive' for r in rows);findings.append({'case':'indexed bandcamp-only cache','observed':'nonempty index bypasses archive content check/fetch','scope':'actual helper synthetic state, search/main normal reachability not validated'})
ns,e=setup();old={'title':'Old'};ns['build_cache_index']([old]);new={'title':'New','source':'archive'};assert ns['items_with_idx']([new],[new])[0]['cache_idx']==-1;findings.append({'case':'cache replaced without rebuild','observed':'cache parameter unused by items_with_idx; stale global index returns -1','scope':'synthetic caller misuse, actual mutation sites not proved'})
print(json.dumps({'result':'PASS actual cache-index controls and synthetic state characterizations','controls':controls,'characterizations':findings,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'scope':'Actual isolated current Python helpers with provider/save stubs, no pickle/user cache/backend module/compiled helper/network/Swift/UI execution'},indent=2))
