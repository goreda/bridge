"""Source-bound property-store and cadence port, not Swift queue execution."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import re,json,hashlib
root=Path(__file__).resolve().parents[3];p=_pp_split().path(root,'PPController.swift');s=p.read_text();c=(root/'Sources/gor/Engine/MPVCommand.swift').read_text();body=c[c.index('final class PollEngine'):c.index('// END relocated PollEngine')]  # 195y G3
for t in ['fastIntervalMs = 200','slowEveryTicks: UInt64 = 5','if rid == 4 || rid == 19 || rid == 21 { flush() }','guard enabled else { return }','guard connection.isConnected else { return }','guard slowDue || pendingKicks > 0 else { return }','if pendingKicks > 0 { pendingKicks -= 1 }','if let value, !(value is NSNull)','connection.onConnected = { [weak self] in self?.subscribeObservations() }','let snapshot = store']:assert t in body,t
assert 'if event == "start-file" { self?.pollEngine.purgeFileStateOnQueue() }' in s
for t in ['arrivalSeq &+= 1','keySeq[key] = arrivalSeq','keySeq.removeValue(forKey: key)','let meta = Meta(keySeq: keySeq, connGen: connGen)','connGen &+= 1','// Flush after complete fast, video-identity slow and cache batches; never in fire().']:assert t in body,t
assert body.count('keySeq.removeValue(forKey: key)')==1,'only the file purge drops an arrival seq; setStore stamps every change including removal'
def table(name):
 a=body[body.index('let '+name+':'):];a=a[:a.index('\n    ]')];return {int(k):v for k,v in re.findall(r'(\d+): "([^"]+)"',a)}
fast,slow,cache,observed=[table(n) for n in ['fastProps','slowProps','cacheProps','observedProps']];props={**fast,**slow,**cache}
assert len(props)==len(fast)+len(slow)+len(cache);assert 'time-pos' not in observed.values()
a=body[body.index('let fileScopedKeys:'):];a=a[:a.index('\n    ]')];scoped=re.findall(r'"([^"]+)"',a)
class Poll:
 def __init__(self):self.store={};self.state='paused';self.enabled=True;self.connected=True;self.ticks=0;self.kicks=0;self.batches=[];self.queue=[];self.metas=[];self.seq=0;self.keyseq={};self.conngen=0
 def set(self,key,value):
  self.seq+=1
  self.keyseq[key]=self.seq
  if value is None:self.store.pop(key,None)
  else:self.store[key]=value
 def flush(self):
  if self.store:self.queue.append(dict(self.store));self.metas.append((dict(self.keyseq),self.conngen))
 def line(self,rid,value,error='success'):
  if rid not in props:return
  self.set(props[rid],value if error=='success' else None)
  if rid in [4,19,21]:self.flush()
 def change(self,key,value):
  self.set(key,value);self.state='idle' if self.store.get('idle-active') is True else 'paused' if self.store.get('pause',True) else 'playing';self.flush()
 def purge(self):
  for key in scoped:self.store.pop(key,None);self.keyseq.pop(key,None)
 def fire(self):
  if not self.enabled or not self.connected:return
  self.ticks+=1;due=self.ticks%5==0
  if self.state=='idle':return
  if self.state=='paused' and not due and not self.kicks:return
  self.batches.append('fast')
  if due:self.batches+=['slow','cache']
  if self.kicks:self.kicks-=1
controls=[]
x=Poll();x.state='playing'
for _ in range(10):x.fire()
assert x.batches.count('fast')==10 and x.batches.count('slow')==2 and x.batches.count('cache')==2;controls.append('playing 5Hz model, slow/cache each fifth tick')
x=Poll()
for _ in range(10):x.fire()
assert x.batches==['fast','slow','cache']*2;controls.append('paused normal fast/slow/cache only each fifth tick')
x=Poll();x.kicks=2
for _ in range(3):x.fire()
assert x.batches==['fast','fast'] and x.kicks==0;controls.append('paused two pending kicks, then suppress')
for attr in ['enabled','connected']:
 x=Poll();setattr(x,attr,False);x.fire();assert x.ticks==0 and not x.batches
controls.append('disabled/disconnected do not advance tick')
x=Poll();x.state='idle';x.fire();assert not x.batches;controls.append('idle no batch; production parks timer')
x=Poll();x.line(1,3);assert not x.queue;x.line(4,7);assert x.queue[-1]['time-pos']==3;x.line(1,None);assert 'time-pos' not in x.store;x.line(4,1,'failure');assert 'sub-end' not in x.store;controls.append('reply IDs, terminal flush, null/error removal')
x=Poll();x.line(999,4);assert not x.store;controls.append('unknown response ID ignored')
x.change('pause',False);assert x.state=='playing';x.change('idle-active',True);assert x.state=='idle';x.change('idle-active',False);assert x.state=='playing';controls.append('property changes update state and flush')
x=Poll();x.store={k:1 for k in scoped};x.store.update({'volume':50,'pause':True});assert 'path' in scoped;x.purge();assert x.store=={'volume':50,'pause':True};controls.append('file-scoped purge preserves global fields')
x=Poll();x.line(1,1);x.line(2,'a');x.line(4,3);ks,cg=x.metas[-1];assert ks['time-pos']<ks['sub-text']<ks['sub-end'] and cg==0;controls.append('flush snapshot carries per-key arrival order and connGen')
x=Poll();x.line(1,1);x.line(4,3);x.purge();x.line(4,3);assert 'time-pos' not in x.metas[-1][0] and 'time-pos' not in x.queue[-1];controls.append('file purge drops arrival seq with the value')
x=Poll();x.line(14,1);x.line(15,2);assert not x.queue;x.line(19,1);assert x.queue[-1]['dheight']==2;controls.append('slow batch flushes at id 19 (last video-identity key), not mid-batch at dheight')
reds=[]
x=Poll();x.line(1,99);x.line(4,3);x.purge();assert 'time-pos' not in x.store and x.queue[0]['time-pos']==99;reds.append({'case':'queued snapshot outlives file purge','observed':'purge removes live store, not already copied main-queue result','limit':'queue ordering relative to start-file main handler unverified'})
x=Poll();x.purge();x.line(1,99);assert x.store['time-pos']==99;reds.append({'case':'late prior-file reply after purge','observed':'fixed request ID can repopulate purged old time-pos','limit':'requires this event/reply ordering; not observed mpv trace'})
x=Poll();x.store={'duration':100,'time-pos':1};x.line(1,2);x.line(4,3);assert x.queue[-1]['duration']==100;reds.append({'case':'mixed-age tier snapshot','observed':'fast response flush includes earlier slow/event values','limit':'expected tiered cache behavior, not inherently a bug'})
print(json.dumps({'result':'PASS controls and scoped interleaving characterizations','controls':controls,'characterizations':reds,'tables':{'fast':fast,'slow':slow,'cache':cache,'observed':observed},'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'scope':'Python port/current source guards, not Swift timers/Dispatch queues/mpv response ordering or UI execution'},indent=2))
