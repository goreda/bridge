"""Source-anchored lifecycle model. Does NOT execute Swift or prove queue ordering."""

# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
from pathlib import Path
import hashlib,itertools,json
s=_sub_read(Path(__file__).resolve().parents[3]/'Sources/gor/GorSubtitles/LiveCaptionController.swift')
required=['self.isActive, self.stdoutPipe === oldPipe','self.process === proc','self.captionGeneration == generation','stdoutBuffer.removeAll()','captionGeneration &+= 1','ScreenCaptureEngine.shared.pcmTapEnabled = false','ScreenCaptureEngine.shared.pcmHandler = nil','cancelWordReveal()','rendererLastPartialWords.removeAll()']
for token in required: assert token in s, token
assert s.count('self.captionGeneration == generation') == 3  # partial hop, final hop, and the transcript-gap timer (renderSubtitleBlock) all carry the generation fence
assert 'guard let self, self.isActive, self.captionGeneration == generation else { return }' in s[s.index('transcriptGapTimer = Timer.scheduledTimer'):s.index('transcriptGapTimer = Timer.scheduledTimer')+300],'gap timer lost its generation fence'
class Session:
 def __init__(self): self.gen=0;self.proc=None;self.pipe=None;self.active=False;self.buffer=b'';self.render=[];self.failures=[];self.tap=False
 def start(self,n):self.gen+=1;self.proc=n;self.pipe=n;self.active=True;self.tap=True
 def stop(self):self.gen+=1;self.proc=self.pipe=None;self.active=self.tap=False;self.buffer=b''
 def data(self,pipe,data):
  if self.active and self.pipe==pipe:self.buffer+=data
 def caption(self,gen,text):
  if self.active and self.gen==gen:self.render.append(text)
 def exit(self,proc):
  if self.proc==proc:
   was=self.active;self.stop()
   if was:self.failures.append(proc)
checks=0
# All old callback orders after replacement, with both partial/final queued.
for order in itertools.permutations(['data','partial','final','exit']):
 x=Session();x.start('A');g=x.gen;x.stop();x.start('B')
 for event in order:
  if event=='data':x.data('A',b'old')
  elif event=='exit':x.exit('A')
  else:x.caption(g,event)
 assert x.active and x.tap and x.proc=='B' and not x.buffer and not x.render and not x.failures
 checks+=1
# Old callbacks while stopped.
x=Session();x.start('A');g=x.gen;x.stop();x.data('A',b'old');x.caption(g,'old');x.exit('A')
assert not x.active and not x.tap and not x.buffer and not x.render and not x.failures;checks+=1
# Live callbacks must still work, not simply be suppressed globally.
x=Session();x.start('B');x.data('B',b'new');x.caption(x.gen,'new');assert x.buffer==b'new' and x.render==['new'];checks+=1
# Current unexpected exit disables tap and reports once; duplicate exit ignored.
x.exit('B');x.exit('B');assert not x.active and not x.tap and x.failures==['B'];checks+=1
# Partial line bytes cannot leak between sessions.
x=Session();x.start('A');x.data('A',b'{"partial":');x.stop();x.start('B');x.data('B',b'{"final":"new"}\n');assert x.buffer==b'{"final":"new"}\n';checks+=1
print(json.dumps({'source_sha256':hashlib.sha256(s.encode()).hexdigest(),'source_guard_checks':len(required)+1,'model_cases':checks,'result':'PASS','scope':'Python lifecycle model and Swift token guards only; no native lifecycle, PCM threading or UI proof'},indent=2))
