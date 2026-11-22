from pathlib import Path

def source_path(name):
    # Cell lives at gor/Tests/Harness/AudioFont; current tree wins.
    live = Path(__file__).resolve().parents[3] / 'Sources' / 'gor' / name
    assert live.is_file(), f'Missing current repository source: {live}'
    return live

import math,re
s=source_path('VariationBroadcaster.swift').read_text()
font=source_path('PhotonFont.swift').read_text()
assert 'let dt  = smoothAudioLastTime > 0 ? min(now - smoothAudioLastTime, 0.1) : (1.0 / 60.0)' in s
assert 'guard mouseMoved || audioBucketChanged else { return }' in s
assert 'let audioBucketChanged = self.audioFanoutCoalescer.hasBucketChange(self.smoothAudio)' in s
assert 'guard updateTimer == nil else { return }' in s
assert 'private static let CacheMaxEntries = 1024' in font
assert 'touchCacheEntry(key); return cached' in font
class Audio:
 def __init__(self):self.mean=.5;self.peak=.01;self.var=.04;self.sm=0;self.last=-1;self.notices=0
 def tick(self,level,dt=1/60):
  self.mean+=(-math.expm1(-dt/4))*(level-self.mean);self.mean=max(.01,self.mean)
  tau=.005 if level>self.peak else 3
  self.peak+=(-math.expm1(-dt/tau))*(max(level,.01)-self.peak);self.peak=max(self.peak,.01)
  diff=level-self.mean
  self.var+=(-math.expm1(-dt/2))*(diff*diff-self.var)
  norm=min(1,max(0,.5+diff/(max(math.sqrt(self.var),.01)*3)))
  blend=.8*norm+.2*level
  percept=blend**.7 if blend>0 else 0
  tau=.018 if percept>self.sm else .14
  self.sm+=(-math.expm1(-dt/tau))*(percept-self.sm)
  if abs(self.sm-self.last)>.008:self.notices+=1;self.last=self.sm
  assert 0<=self.sm<=1 and math.isfinite(self.sm)
for name,trace in [('silence',[0]*1200),('constant',[.35]*1200),('pulse',[.02 if (i//30)%2 else .7 for i in range(1200)])]:
 x=Audio()
 for value in trace:x.tick(value)
 print(name,'qualifying ticks',x.notices,'of',len(trace),'last audio',round(x.sm,4))
print('All audio traces bounded; this is a math model, not thermal or AppKit benchmark')
