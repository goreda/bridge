"""Nonvisual cover callback/cache routing port, no image fetch/render/UI."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3];p=_pp_split().path(root,'PPController_Features.swift');s=p.read_text();a=s[s.index('func showCoverPreview'):s.index('func toggleMusicMode')]
for t in ['StableCacheKey.sha1(urlString)','if !FileManager.default.fileExists(atPath: fname.path)','Data(contentsOf: url)','try? data.write(to: fname)','NSImage(contentsOf: fname)','coverView.image = image','coverView.frame = hostView.bounds','ctx.duration = 0.8','coverView.animator().alphaValue = 1.0','ctx.duration = 0.6','coverView.animator().alphaValue = 0.0']:assert t in a,t
assert 'generation' not in a and 'isMusicMode' not in a,'ownership changed; port review needed'
class Cover:
 def __init__(self):self.cache=set();self.queue=[];self.image=None;self.alpha=0;self.fetches=[];self.mode=True
 def show(self,url,cached=False,valid=True):
  if cached:self.cache.add(url)
  if url not in self.cache:self.fetches.append(url);self.cache.add(url)
  if valid:self.queue.append(lambda:(setattr(self,'image',url),setattr(self,'alpha',1)))
 def hide(self):self.alpha=0
 def deliver(self,index=0):self.queue.pop(index)()
controls=[]
x=Cover();x.show('A');x.deliver();assert x.image=='A' and x.alpha==1 and x.fetches==['A'];controls.append('cache miss then successful callback installs selected cover')
x=Cover();x.show('A',cached=True);x.deliver();assert not x.fetches and x.image=='A';controls.append('cache hit skips fetch')
x=Cover();x.show('A',cached=True,valid=False);assert not x.queue and not x.fetches;controls.append('unreadable cached image does not install')
x=Cover();x.show('A');x.deliver();x.hide();assert x.alpha==0;controls.append('hide after completed preview remains hidden')
x=Cover();x.show('A');x.show('B');x.deliver();x.deliver();assert x.image=='B';controls.append('in-order selections finish with B')
reds=[]
x=Cover();x.show('A');x.show('B');x.deliver(1);x.deliver();assert x.image=='A';reds.append({'case':'A/B completion reversed','observed':'older cover A overwrites B'})
x=Cover();x.show('A');x.hide();x.deliver();assert x.alpha==1;reds.append({'case':'hide before completion','observed':'queued load unhides cover again'})
x=Cover();x.show('A');x.mode=False;x.deliver();assert x.alpha==1;reds.append({'case':'music mode exit before completion','observed':'captured coverView still receives image/alpha write without mode check'})
x=Cover();x.show('A',cached=True,valid=False);x.show('A',valid=False);assert not x.fetches;reds.append({'case':'corrupt cache entry','observed':'file-exists fast path skips refetch even if NSImage cannot decode','scope':'source routing model, corrupt actual bytes not inspected'})
print(json.dumps({'result':'PASS nonvisual controls and callback ownership characterizations','controls':controls,'characterizations':reds,'source_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'open':['actual SHA-1 implementation parity (only source call anchored)','NSImage/network/size/MIME/timeout/cache write errors','real AppKit animations/mode lifetime/pixels','concurrent same-key cache writes'],'scope':'Python nonvisual routing/ownership ports and Swift source anchors; no cover/network/image/Swift/UI execution'},indent=2))
