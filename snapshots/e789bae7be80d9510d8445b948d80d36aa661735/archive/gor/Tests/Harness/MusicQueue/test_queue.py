"""Actual AST-isolated queue functions, effect dependencies stubbed."""
from pathlib import Path
import ast,json,hashlib
root=Path(__file__).resolve().parents[3];p=root/'Resources/vendor/mus2/mus2.py';s=p.read_text();names={'q_emit','q_clear_all','q_play_pos','build_queue_from_album'};nodes=[n for n in ast.parse(s).body if isinstance(n,ast.FunctionDef) and n.name in names];assert len(nodes)==4;code=compile(ast.Module(body=nodes,type_ignores=[]),'actual-current-queue','exec')
def setup():
 effects=[];ns={'_queue':[],'_queue_pos':-1,'emit':lambda obj:effects.append(('emit',obj)),'mpv_cmd':lambda cmd:effects.append(('mpv_cmd',cmd)),'download_cover':lambda url:'cover-fixture' if url else None,'mpv_play':lambda url,cover:effects.append(('play',url,cover)),'archive_url':lambda a:'archive-fixture:'+a['title'],'fetch_bc_tracks':lambda a:([{'n':1,'title':'fetched','stream_url':'fake:fetched'}],None)};exec(code,ns);return ns,effects
controls=[];findings=[]
ns,e=setup();ns['q_play_pos'](-1);ns['q_play_pos'](0);assert not e and ns['_queue_pos']==-1;controls.append('invalid/empty bounds have no playback effect')
ns['build_queue_from_album']({'source':'archive','title':'Album','cover':'cover'},3);assert len(ns['_queue'])==1 and ns['_queue'][0]['cache_idx']==3 and e[-1][1]['cmd']=='queue';controls.append('archive queues one album and emits list')
ns['q_play_pos'](0);assert ns['_queue_pos']==0 and e[-2][0]=='play' and e[-1][1]['title']=='Album';controls.append('valid queue entry plays and emits now-playing')
ns['q_clear_all']();assert ns['_queue']==[] and ns['_queue_pos']==-1 and json.loads(e[-2][1])['command']==['playlist-clear'];controls.append('clear resets queue/position and sends playlist-clear')
ns,e=setup();ns['build_queue_from_album']({'source':'bandcamp','title':'Album','tracks':[{'n':2,'title':'Song','stream_url':'fake:song'},{'n':3,'title':'NoURL'}]},4);assert len(ns['_queue'])==1 and ns['_queue'][0]['track_n']==2;controls.append('bandcamp only playable tracks retain source cache/track identity')
ns,e=setup();ns['build_queue_from_album']({'source':'bandcamp','title':'Album'},4);assert ns['_queue'][0]['url']=='fake:fetched';controls.append('empty bandcamp tracks use stubbed provider result')
ns,e=setup();ns['_queue']=[{'title':'Song','url':'fake:Song'}]
def fail(*args):raise OSError('synthetic playback failure')
ns['mpv_play']=fail
try:ns['q_play_pos'](0)
except OSError:pass
assert ns['_queue_pos']==0 and not e;findings.append({'case':'playback dependency raises','observed':'position already advanced, no rollback/now-playing event','scope':'actual helper with injected failure; real mpv_play error contract unverified'})
ns,e=setup();ns['_queue']=[{'title':'MissingURL'}]
try:ns['q_play_pos'](0);raised=False
except KeyError:raised=True
assert raised and ns['_queue_pos']==0;findings.append({'case':'malformed entry URL missing','observed':'KeyError after position mutation','scope':'synthetic queue state, normal producer validity not disproved'})
ns,e=setup();ns['build_queue_from_album']({'source':'unknown','title':'Album'},4);assert ns['_queue']==[] and e[-1][1]['cmd']=='queue';findings.append({'case':'unknown album source','observed':'no queued item, still emits list','scope':'admission characterization, may be intended'})
print(json.dumps({'result':'PASS actual isolated queue controls and failure characterizations','controls':controls,'characterizations':findings,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'scope':'Actual Python queue helpers with synthetic effects/stubs; no mpv/cover/provider/user state/compiled helper/Swift/UI execution'},indent=2))
