from pathlib import Path

def source_path(name):
    # Cell lives at gor/Tests/Harness/AudioFont; current tree wins.
    live = Path(__file__).resolve().parents[3] / 'Sources' / 'gor' / name
    assert live.is_file(), f'Missing current repository source: {live}'
    return live

import random,json,math,hashlib
p=Path(__file__).parent;s=source_path('PhotonFont.swift').read_text();b=source_path('VariationBroadcaster.swift').read_text()
for t in ['CacheMaxEntries = 1024','CacheQuantizationSteps: Double = { let v = UserDefaults.standard.double(forKey: "gor.heat.axisSteps"); return v >= 16 && v <= 128 ? v.rounded() : 128 }()','vars.keys.sorted()','normalized = (v - r.min) / (r.max - r.min)','_nsCache.removeValue(forKey: evict)','_cache.removeValue(forKey: evict)','if _cacheIndex[key] != nil { return }','_cacheIndex[key] = _cacheClock'] :assert t in s,t
for t in ['guard mouseMoved || audioBucketChanged else { return }','guard updateTimer == nil else { return }','entry.block()','skippedHidden.insert(entry.token)','CleanupIntervalTicks = 300']: assert t in b,t
class Cache:
 def __init__(self):self.order=[];self.idx={};self.ct={};self.ns={}
 def touch(self,k):
  i=self.idx[k];self.order.pop(i);self.order.append(k)
  for j in range(i,len(self.order)):self.idx[self.order[j]]=j
 def get(self,k,kind):
  d=self.ct if kind=='ct' else self.ns
  if k in d:self.touch(k);return
  d[k]=k
  if k in self.idx:return
  self.order.append(k);self.idx[k]=len(self.order)-1
  while len(self.order)>256:
   e=self.order.pop(0)
   for k,i in list(self.idx.items()):self.idx[k]=i-1
   self.idx.pop(e);self.ct.pop(e,None);self.ns.pop(e,None)
 def check(self):
  assert self.idx=={k:i for i,k in enumerate(self.order)}
  assert len(self.order)<=256 and len(self.ct)<=256 and len(self.ns)<=256
  assert set(self.ct)|set(self.ns)==set(self.order)
x=Cache();rng=random.Random(2601001)
for _ in range(20000):x.get(rng.randrange(400),rng.choice(['ct','ns']));x.check()
x=Cache()
for k in range(256):x.get(k,'ct')
x.get(0,'ct');x.get(256,'ns');assert 0 in x.ct and 1 not in x.idx
# quantization equivalence, sorted axes, same normalized weight for wide ranges
round_swift=lambda v: math.floor(v+.5) if v>=0 else math.ceil(v-.5)
def key(vars,size,ranges):
 return tuple((tag,round_swift(((v-ranges[tag][0])/(ranges[tag][1]-ranges[tag][0]) if tag in ranges and ranges[tag][1]>ranges[tag][0] else v)*128)/128) for tag,v in sorted(vars.items())),round_swift(size*4)
assert key({1:450,2:.5},24,{1:(100,800),2:(0,1)})==key({2:.5,1:450},24,{1:(100,800),2:(0,1)})
assert key({1:450},24,{1:(100,800)})[0][0][1]==.5
# fanout threshold compares against last notified value, so tiny cumulative moves count
last=0;notifications=0
for pos in [.1,.2,.3,.4,.5,.6]:
 if (pos-last)**2>.5**2:last=pos;notifications+=1
assert notifications==1
# Characterize new opposite-kind insertion sharing existing LRU key.
x=Cache()
for k in range(256):x.get(k,'ct')
x.get(0,'ns');x.get(256,'ct');assert 0 not in x.ns
print(json.dumps({'result':'PASS','random_cache_operations':20000,'source_guards':12,'checks':['shared CT/NS bounds and index integrity','cache hit protects hot key','normalized sorted quantization','cumulative subthreshold mouse movement eventually fans out'],'characterizations':['First construction in opposite CT/NS cache does not refresh existing shared LRU key, so just-created instance can be next eviction. Performance-only model result, no incorrect font proved.','Listener cleanup counter advances only on qualifying notifications; 300 is not a guaranteed 5-second wall-clock cadence.','CATextLayer.applyVariation in broadcaster assigns self.font directly, unlike setIfChanged helper. Actual typesetter cost not measured.'],'source_sha256':{'font':hashlib.sha256(s.encode()).hexdigest(),'broadcast':hashlib.sha256(b.encode()).hexdigest()},'scope':'Python port and source checks; no Swift CoreText/AppKit execution or thermal/pixel claim'},indent=2))

# Compile the production fanout method against typed view/transaction adapters.
# This checks identical listener order/final font-state values and one outer
# transaction, not macOS pixel output or thermal acceptance.
import subprocess,tempfile,shutil
method=b[b.index('    private func notifyListeners() {'):b.index('    /// weakLifetime defaults',b.index('    private func notifyListeners() {'))]
method=method.replace('private func notifyListeners','func notifyListeners')
assert 'CATransaction.begin(); CATransaction.setDisableActions(true)' in method
baseline=method.replace('        CATransaction.begin(); CATransaction.setDisableActions(true)\n        defer { CATransaction.commit() }\n','')
pre=r'''import Foundation
func CACurrentMediaTime()->Double {0}
class NSView {var isEffectivelyVisible=true}
final class WeakBox {weak var value:AnyObject?;init(_ v:AnyObject){value=v};var isAlive:Bool{value != nil}}
enum CATransaction {
 static var depth=0,flushes=0,actions=[Bool](),pending=false
 static func begin(){depth+=1;actions.append(false)}
 static func setDisableActions(_ v:Bool){actions[actions.count-1]=v}
 static func write(){pending=true}
 static func commit(){precondition(depth>0);depth-=1;actions.removeLast();if depth==0 && pending{flushes+=1;pending=false}}
 static func reset(){precondition(depth==0);flushes=0;pending=false}
}
'''
fields=r'''
 var diagnosticFanouts:UInt64=0
 var callbackPhase="idle",listenerSite="none"
 var listenerInFlight:UUID?;var listenerEnteredAt=0.0;var notifyDepth=0
 var skippedHidden=Set<UUID>(),siteRuns=[String:Int](),hiddenSkips=0,cleanupCounter=0
 static let CleanupIntervalTicks=300
 var listeners:[(token:UUID,block:()->Void,liveness:WeakBox?,site:String)]=[]
'''
program=pre+'final class Baseline {\n'+fields+baseline+'}\nfinal class Batched {\n'+fields+method+r'''}
func run(_ batched:Bool)->([Int],[Int],Int,Int,Int){
 let old=Baseline(),new=Batched();let hidden=NSView();hidden.isEffectivelyVisible=false
 var state=Array(repeating:0,count:12),order=[Int]()
 for i in 0..<12 {
  let entry=(token:UUID(),block:{CATransaction.begin();CATransaction.setDisableActions(true);state[i]=i*31+7;order.append(i);CATransaction.write();CATransaction.commit()},liveness:i==4 ? WeakBox(hidden):nil,site:"site\(i)")
  old.listeners.append(entry);new.listeners.append(entry)
 }
 CATransaction.reset()
 for _ in 0..<301 {if batched {new.notifyListeners()} else {old.notifyListeners()}}
 return (state,order,CATransaction.flushes,batched ? new.hiddenSkips:old.hiddenSkips,batched ? new.listeners.count:old.listeners.count)
}
let a=run(false),z=run(true)
precondition(a.0==z.0 && a.1==z.1 && a.3==z.3 && a.4==z.4)
precondition(a.2==3311 && z.2==301 && CATransaction.depth==0)
print("PASS actual production fanout typed equivalence301ticks: listener order/final font-state/hidden skips/cleanup unchanged;3311->301 outer transaction flushes; not native rendering or heat proof")
'''
with tempfile.TemporaryDirectory() as td:
 q=Path(td);(q/'main.swift').write_text(program)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(q/'main.swift'),'-o',str(q/'test')],check=True)
 subprocess.run([str(q/'test')],check=True)
