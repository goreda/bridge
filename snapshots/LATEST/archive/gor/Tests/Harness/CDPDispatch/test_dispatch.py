"""Current CDP pending/dispatch port; no browser/WebSocket execution."""
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3];p=root/'Sources/gor/Media/CDPSession.swift';s=p.read_text();a=s[s.index('private func dispatch'):s.index('// MARK: - Public API',s.index('private func dispatch'))]
for t in ['pending.removeValue(forKey: id)','eventHandlers[method]?(params)','let id = nextId','nextId += 1','pending[id] = cb','JSONSerialization.data(withJSONObject: obj)','wsTask?.send(.string(str))']:assert t in a,t
assert a.index('pending[id] = cb')<a.index('JSONSerialization.data(withJSONObject: obj)')
assert 'pending.removeValue' not in a[a.index('private func sendCommand'):],'send failure cleanup changed; review model'
class Dispatch:
 def __init__(self):self.next=1;self.pending={};self.calls=[];self.events=[]
 def send(self,serialize=True,connected=True,error=False):
  rid=self.next;self.next+=1;self.pending[rid]=True
  return rid
 def receive(self,obj):
  if isinstance(obj.get('id'),int):
   rid=obj['id']
   if rid in self.pending:self.pending.pop(rid);self.calls.append(obj)
   return
  if isinstance(obj.get('method'),str) and isinstance(obj.get('params'),dict):self.events.append((obj['method'],obj['params']))
x=Dispatch();a1=x.send();b=x.send();assert [a1,b]==[1,2];x.receive({'id':b,'result':{}});x.receive({'id':a1,'result':{}});assert [r['id'] for r in x.calls]==[2,1];x.receive({'id':a1});assert len(x.calls)==2
controls=['monotonic IDs, reverse response correlation and duplicate exactly-once dispatch']
x.receive({'id':999});assert not x.pending and len(x.calls)==2;controls.append('unknown reply ignored')
x.receive({'method':'Network.responseReceived','params':{'x':1}});assert len(x.events)==1;x.receive({'method':'bad','params':[]});assert len(x.events)==1;controls.append('method/dictionary event dispatch shape')
rid=x.send();x.receive({'id':rid,'error':{'code':-1}});assert x.calls[-1]['error']['code']==-1;controls.append('CDP error response still resolves callback once')
findings=[]
for scenario,args in [('serialization failure',{'serialize':False}),('nil wsTask',{'connected':False}),('send error',{'error':True})]:
 x=Dispatch();rid=x.send(**args);assert rid in x.pending and not x.calls;findings.append({'case':scenario,'observed':'pending retained without callback in command send path','scope':'source-bound failure model; outer operation deadline may compensate'})
print(json.dumps({'result':'PASS dispatch controls and failure-retention characterizations','controls':controls,'characterizations':findings,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'scope':'Python bookkeeping model/current Swift guards; no Swift/URLSession/WebSocket/browser/provider execution'},indent=2))
