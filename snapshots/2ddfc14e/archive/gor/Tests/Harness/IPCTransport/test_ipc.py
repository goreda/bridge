"""Current Swift IPC source-bound Python ports. No mpv/socket/native execution."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import json,hashlib
root=Path(__file__).resolve().parents[3]
p=_pp_split().path(root,'PPController.swift');s=p.read_text();c=(root/'Sources/gor/Engine/MPVCommand.swift').read_text()
persistent=c[c.index('final class PersistentEventConnection'):c.index('// END relocated PersistentEventConnection')]  # 195y G3
one=c[c.index('final class IPCClient'):c.index('// END relocated IPCClient')]  # 195y G3: IPCClient relocated to MPVCommand.swift
for t in ['JSONSerialization.data(withJSONObject: ["command": args])','else { return "" }']:assert t in c,t
for t in ['while offset < byteCount','if n > 0 { offset += n; continue }','if n < 0 && errno == EINTR { continue }','guard sentAll else { return [] }','Darwin.shutdown(fd, SHUT_WR)','raw.append(contentsOf: buf.prefix(n))','String(data: raw, encoding: .utf8)','obj["data"] != nil']:assert t in one,t
for t in ['lineBuffer.append(contentsOf: buf.prefix(n))','lineBuffer.firstIndex(of: 0x0A)','JSONSerialization.jsonObject(with: lineData)','src.setCancelHandler { Darwin.close(newFd) }','reconnectDelay = min(reconnectDelay * 2, Self.maxReconnectDelay)','private static let maxReconnectDelay: TimeInterval = 5.0']:assert t in persistent,t
write=persistent[persistent.index('func write(_ payload'):persistent.index('// MARK: - Connection lifecycle')]
assert 'toSend.withCString { Darwin.write(self.fd, $0, strlen($0)) }' in write
assert 'if sent < 0 || sent < toSend.utf8.count' in write
assert 'while' not in write and 'EINTR' not in write,'persistent writer changed; review loss model'
controls=[]
# JSON escaping preserves one newline-delimited frame even for control bytes.
strings=['plain','quote"slash\\','new\nline\r\ttab','nul\0byte','café 日本','emoji 😀','https://example.invalid/a?x="q"&v=\\','a\x01b\x1fc']
for text in strings:
 frame=json.dumps({'command':['loadfile',text]},ensure_ascii=False,separators=(',',':'))+'\n'
 assert frame.count('\n')==1
 assert json.loads(frame)['command'][1]==text
controls.append({'case':'JSON string roundtrip and single-line batch boundary','count':len(strings),'scope':'Python JSON equivalence class, not Foundation serialization'})
def full_write(payload,steps):
 offset=0;sent=b'';calls=0
 for step in steps:
  calls+=1
  if step=='EINTR':continue
  if step<=0:return False,sent,calls
  n=min(step,len(payload)-offset);sent+=payload[offset:offset+n];offset+=n
  if offset==len(payload):return True,sent,calls
 return False,sent,calls
payload='{"command":["loadfile","café"]}\n'.encode()
for step in range(1,len(payload)+1):
 ok,sent,_=full_write(payload,[step]*len(payload));assert ok and sent==payload
ok,sent,_=full_write(payload,['EINTR',1,'EINTR',1000]);assert ok and sent==payload
for steps in [[0],[-1],[2,0],[2,-1]]:
 ok,sent,_=full_write(payload,steps);assert not ok
controls.append({'case':'one-shot complete-write/short-write/EINTR/failure controls','positive_step_sizes':len(payload)})
class Events:
 def __init__(self):self.pending=b'';self.rows=[]
 def append(self,chunk):
  self.pending+=chunk
  while b'\n' in self.pending:
   line,self.pending=self.pending.split(b'\n',1)
   try:obj=json.loads(line)
   except (ValueError,UnicodeDecodeError):continue
   if isinstance(obj,dict):self.rows.append(obj)
wire='{"event":"property-change","data":"café 😀"}\n'.encode()
for i in range(len(wire)+1):
 e=Events();e.append(wire[:i]);e.append(wire[i:]);assert e.rows==[{'event':'property-change','data':'café 😀'}]
e=Events();e.append(b'bad\n\n[]\n{"data":1}\n{"data":');assert e.rows==[{'data':1}];assert e.pending==b'{"data":';e.append(b'2}\n');assert e.rows[-1]=={'data':2}
controls.append({'case':'persistent byte framing, all split points incl UTF-8, malformed/non-object isolation','splits':len(wire)+1})
delay=.25;trace=[]
for _ in range(12):trace.append(delay);delay=min(delay*2,5)
assert trace==[.25,.5,1,2,4,5,5,5,5,5,5,5]
controls.append({'case':'reconnect exponential bound/reset source guards','delay_trace':trace})
def parse_first(lines):
 for line in lines:
  try:obj=json.loads(line)
  except ValueError:continue
  if isinstance(obj,dict) and 'data' in obj:return obj
 return {}
assert parse_first(['bad','{"error":"success","data":null}'])['data'] is None
assert parse_first(['{"error":"failure"}'])=={}
controls.append({'case':'first data-bearing response including null; malformed/error-only skipped'})
reds=[]
for n in [1,len(payload)-1]:
 observed=payload[:n];assert observed!=payload
 reds.append({'case':'persistent short write '+str(n),'observed':'prefix sent, transport torn down, original frame not completed/replayed by writer'})
reds.append({'case':'persistent EINTR','observed':'single negative write causes teardown rather than retry'})
lines=['{"event":"property-change","data":"unrelated"}','{"request_id":4,"error":"success","data":"wanted"}'];assert parse_first(lines)['data']=='unrelated'
reds.append({'case':'first-data response selection','observed':'data-bearing event before reply wins; no request-id correlation','scope':'caller-dependent protocol risk, not observed incorrect playback'})
assert 'lineBuffer.count' not in persistent and 'raw.count' not in one
print(json.dumps({'result':'PASS controls and expected transport characterizations','controls':controls,'known_red_or_protocol_risk':reds,'open':['persistent disconnected writes silently dropped','newline-free event buffer and one-shot response memory unbounded','read EINTR/timeout partial reply behavior','AF_UNIX path truncation, SIGPIPE and reconnect/start-stop scheduling','Darwin/Foundation/socket/mpv native integration'],'source_sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in [p,root/'Sources/gor/Engine/MPVCommand.swift']},'scope':'Python models + current source guards only; no socket/mpv/Swift execution, performance or runtime-proof claim'},indent=2))
