from pathlib import Path

def source_path(name):
    # Cell lives at gor/Tests/Harness/AudioFont; current tree wins.
    live = Path(__file__).resolve().parents[3] / 'Sources' / 'gor' / name
    assert live.is_file(), f'Missing current repository source: {live}'
    return live

import json,hashlib
s=source_path('VariationBroadcaster.swift').read_text()
a=s[s.index('func addListener('):s.index('func removeListener(')]
assert 'listeners.append' in a and 'block()' not in a and 'lastNotified' not in a
assert 'guard mouseMoved || audioBucketChanged else { return }' in s
assert 'let audioBucketChanged = self.audioFanoutCoalescer.hasBucketChange(self.smoothAudio)' in s
class Fanout:
 def __init__(self):self.entries=[];self.n=0;self.mouse=0;self.audio=.3;self.counter=0
 def add(self,weak=None):
  self.n+=1;self.entries.append({'id':self.n,'alive':weak,'calls':0});return self.n
 def remove(self,n):self.entries=[e for e in self.entries if e['id']!=n]
 def tick(self,mouse=0,audio=.3):
  if (mouse-self.mouse)**2<=.5**2 and abs(audio-self.audio)<=.008:return
  self.mouse,self.audio=mouse,audio
  for e in self.entries:
   if e['alive'] is not False:e['calls']+=1
  self.counter+=1
  if self.counter>=300:self.counter=0;self.entries=[e for e in self.entries if e['alive'] is not False]
x=Fanout();n=x.add()
for _ in range(10000):x.tick()
assert x.entries[0]['calls']==0
idle_result='New listener gets zero callbacks across 10,000 stable ticks; addListener does not deliver current state or invalidate suppression. Visible consequence depends on caller initialization/layout.'
x.tick(mouse=.6);assert x.entries[0]['calls']==1;x.remove(n);x.tick(mouse=1.2);assert not x.entries
x=Fanout();x.add(False)
for i in range(299):x.tick(mouse=i+1)
assert len(x.entries)==1;x.tick(mouse=300);assert not x.entries
x=Fanout();x.add()
for i in range(300):x.tick(mouse=i+1)
assert len(x.entries)==1
print(json.dumps({'normal_result':'PASS','normal_cases':['movement resumes fanout','explicit remove prevents later delivery','dead weak lifetime pruned at 300 qualifying ticks','tokenless entry retained at cleanup'],'idle_characterization':idle_result,'scope':'Python state port and source anchors, no Swift listener mutation/queue or visual proof','source_sha256':hashlib.sha256(s.encode()).hexdigest()},indent=2))
