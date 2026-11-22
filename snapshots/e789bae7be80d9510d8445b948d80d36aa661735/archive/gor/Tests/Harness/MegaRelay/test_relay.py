"""Current-source relay framing/lifecycle port. No process, socket or MEGA call."""
from pathlib import Path
import hashlib,itertools,json
root=Path(__file__).resolve().parents[3]
source=root/'Sources/gor/Media/MegaStreamManager.swift';s=source.read_text()
a=(root/'Sources/gor/App/AppDelegate.swift').read_text()
r=(root/'Resources/vendor/mega_relay/mega_relay.mjs').read_text()
acc=s[s.index('final class ByteLineAccumulator'):s.index('final class RelayReadyOnce')]
stream=s[s.index('stdoutPipe.fileHandleForReading.readabilityHandler ='):s.index('stderrPipe.fileHandleForReading.readabilityHandler =')]
error=s[s.index('stderrPipe.fileHandleForReading.readabilityHandler ='):s.index('showMegaOSD("resolving mega link...")')]
stop=s[s.index('func stopMegaRelay()'):]
guards=['pending.append(data)','pending.lastIndex(of: 0x0A)','pending = Data(pending[pending.index(after: last)...])','String(decoding: complete, as: UTF8.self).components(separatedBy: "\\n").filter { !$0.isEmpty }']
for t in guards:assert t in acc,t
for block,prefix in [(stream,'STREAM:'),(error,'ERROR:')]:
 for t in ['handle.availableData','stdoutBuffer.append(data)' if prefix=='STREAM:' else 'stderrBuffer.append(data)',f'hasPrefix("{prefix}")','DispatchQueue.main.async']:assert t in block,t
for t in ['megaRelayProcess = p','stopMegaRelay()','let stdoutBuffer = ByteLineAccumulator()','let stderrBuffer = ByteLineAccumulator()','let ready = RelayReadyOnce()','try p.run()','failed to start mega relay']:assert t in s,t
for t in ['megaStdoutPipe?.fileHandleForReading.readabilityHandler = nil','megaStderrPipe?.fileHandleForReading.readabilityHandler = nil','proc.terminate()','proc.waitUntilExit()','megaRelayProcess = nil']:assert t in stop,t
for t in ['var megaRelayProcess: Process?','var megaStdoutPipe: Pipe?','var megaStderrPipe: Pipe?']:assert t in a,t
assert 'console.log(`STREAM:http://127.0.0.1:${PORT}/`)' in r
assert 'console.error(`ERROR:${msg}`)' in r
# Current source: ownership identity and ready-once are implemented; pin them.
for t in ['guard let self, let p, self.megaRelayProcess === p, !ready.fired else { return }','ready.fired = true']:
 assert t in stream,t
assert 'guard let self, let p, self.megaRelayProcess === p else { return }' in error
assert 'final class RelayReadyOnce { var fired = false }' in s
class Lines:
 def __init__(self):self.pending=b''
 def append(self,text):
  if isinstance(text,str):text=text.encode()
  self.pending+=text
  i=self.pending.rfind(b'\n')
  if i<0:return []
  complete=self.pending[:i+1];self.pending=self.pending[i+1:]
  return [l for l in complete.decode('utf-8',errors='replace').split('\n') if l]
controls=[]
# All two-cut partitions of one ready message, including empty boundaries.
message='STREAM:http://127.0.0.1:2223/\n'
for i in range(len(message)+1):
 for j in range(i,len(message)+1):
  b=Lines();got=[]
  for chunk in [message[:i],message[i:j],message[j:]]:got+=b.append(chunk)
  assert got==[message[:-1]]
controls.append({'case':'all ASCII ready-message three-chunk partitions','count':(len(message)+1)*(len(message)+2)//2})
b=Lines();assert b.append('note:x\n\nSTREAM:u\r\npartial')==['note:x','STREAM:u\r'];assert b.pending==b'partial';assert b.append('-tail\n')==['partial-tail'];controls.append({'case':'coalesced lines, blanks, CRLF and retained tail'})
b=Lines();assert b.append('STREAM:unterminated')==[];controls.append({'case':'unterminated tail waits for newline'})
out,err=Lines(),Lines();assert out.append('STREAM:u\n')==['STREAM:u'];assert err.append('ERROR:x\n')==['ERROR:x'];controls.append({'case':'separate stdout/stderr accumulation'})
# Port the callback as source implements it: identity check and ready-once on the main queue.
class Relay:
 def __init__(self):self.active=None;self.queue=[];self.played=[];self.status=[];self.fired={}
 def start(self,identity):self.active=identity;self.fired[identity]=False
 def ready(self,identity,url,title):
  def cb():
   if self.active!=identity or self.fired[identity]:return
   self.fired[identity]=True;self.status.append('stream ready');self.played.append((identity,url,title))
  self.queue.append(cb)
 def failure(self,identity,message):self.queue.append(lambda:self.active==identity and self.status.append((identity,message)))
 def stop(self):self.active=None
 def flush(self):
  for callback in self.queue:callback()
  self.queue=[]
x=Relay();x.start('A');x.ready('A','local-A','title-A');x.flush();assert x.played==[('A','local-A','title-A')];controls.append({'case':'current ready plays once'})
x=Relay();x.start('A');x.ready('A','u','t');x.stop();x.flush();assert x.played==[];controls.append({'case':'queued ready dropped after stop'})
x=Relay();x.start('A');x.ready('A','u','t');x.start('B');x.flush();assert x.played==[];controls.append({'case':'queued ready dropped after replacement'})
x=Relay();x.start('A');x.failure('A','old error');x.start('B');x.flush();assert x.status==[];controls.append({'case':'queued old error dropped after replacement'})
x=Relay();x.start('A');x.ready('A','u','t');x.ready('A','u','t');x.flush();assert len(x.played)==1;controls.append({'case':'duplicate ready plays once'})
# UTF-8 scalar split across reads: byte accumulator decodes only complete lines.
wire='ERROR:café\n'.encode();i=wire.index(b'\xc3')+1;buffer=Lines();delivered=[]
for chunk in [wire[:i],wire[i:]]:delivered+=buffer.append(chunk)
assert delivered==['ERROR:café'];controls.append({'case':'UTF-8 scalar split across reads keeps the line','scope':'byte-level model + source guard, not native Foundation'})
reds=[]
# EOF has no flush branch and memory has no line-size bound. Characterize,
# without claiming producer always emits these malformed streams.
assert 'terminationHandler' not in s
assert 'pending.count' not in acc and 'pending.utf8.count' not in acc
print(json.dumps({'result':'PASS controls (ownership, ready-once, byte framing now in source)','controls':controls,'known_red':reds,'other_open':['EOF/exit does not flush trailing line or report unexpected termination','no pending-line size bound','port reuse/process startup failure cleanup','native FileHandle/main-queue ordering and Foundation UTF-8 parity'],'source_sha256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [source,root/'Sources/gor/App/AppDelegate.swift',root/'Resources/vendor/mega_relay/mega_relay.mjs']},'scope':'Python source-bound models only; not Swift execution, real process scheduling, localhost relay integration, external MEGA or playback'},indent=2))
