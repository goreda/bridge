"""Current production IPCClient + real owned Unix socket; Linux ABI adaptation only."""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import os,subprocess,tempfile,socket,threading,json,time
r=Path(__file__).resolve().parents[2]
s=_s3read(_pp_split().path(r,'PPController.swift'));s=s[s.index('final class IPCClient {'):s.index('// ================================================================',s.index('final class IPCClient {'))]
s=s.replace('Darwin.','Glibc.').replace('socket(AF_UNIX, SOCK_STREAM, 0)','socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)').replace('tv_sec: sec','tv_sec: sec').replace('SHUT_WR)','Int32(SHUT_WR))')
with tempfile.TemporaryDirectory() as d:
 p=Path(d);sock=socket.socket(socket.AF_UNIX);sock.bind(d+'/s');sock.listen();sock.settimeout(.1);rows=[];arrivals=[];threads=[];stop=False
 def handle(c):
  with c:
   data=b''
   while b'\n' not in data:
    part=c.recv(4096)
    if not part:return
    data+=part
   rows.append(json.loads(data.split(b'\n')[0])['command']);arrivals.append(time.monotonic())
   time.sleep(.45) # deliberate slow/nonclosing reply, like a long-lived mpv IPC connection
   try:c.sendall(b'{"error":"success"}\n')
   except BrokenPipeError:pass
 def serve():
  while not stop:
   try:c,_=sock.accept()
   except socket.timeout:continue
   t=threading.Thread(target=handle,args=(c,));t.start();threads.append(t)
 worker=threading.Thread(target=serve);worker.start()
 stub='''import Foundation
import Glibc
enum GeomTrace {static func logBlink(_ value:String){}}
'''
 main='''
let client=IPCClient(path:CommandLine.arguments[1])
for i in 0..<1000 {client.sendLatestLids("{\\"command\\":[\\"lid\\",\\(i)]}")}
let began=ProcessInfo.processInfo.systemUptime
client.send("{\\"command\\":[\\"pause\\"]}")
Thread.sleep(forTimeInterval:0.7)
client.closeLatestPose()
for i in 1000..<2000 {client.sendLatestLids("{\\"command\\":[\\"lid\\",\\(i)]}")}
Thread.sleep(forTimeInterval:0.65)
'''
 trace=_s3read(r/'Sources/gor/GorCore/Diag.swift').split('// MARK: - Session traces\n',1)[1]
 (p/'main.swift').write_text(stub+s+main+'\n'+trace)
 try:
  subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),str(r/'Sources/gor/Camera/HeadPose.swift'),'-o',d+'/run'],check=True)
  began=time.monotonic();subprocess.run([d+'/run',d+'/s'],check=True,timeout=4)
 finally:stop=True;worker.join();sock.close();[t.join() for t in threads]
 assert ['lid',999] in rows,rows
 assert ['pause'] in rows and rows.index(['pause'])<=2,rows
 assert len(rows)<12 and not any(v[0]=='lid' and v[1]>=1000 for v in rows),rows
 print('PASS actual IPCClient + LatestPoseSlot: 1000 lids coalesce, pause not behind a lid FIFO, quit closes lid slot:',rows)
 # Independent exact send-only primitive latency with a delayed response is established by
 # pause reaching server before its first 450ms lid reply can finish.
 assert arrivals[rows.index(['pause'])]-arrivals[0]<.25,(rows,arrivals)
 print('PASS production send-only lid path does not wait for socket EOF/450ms reply; discrete path unchanged')
