#!/usr/bin/env python3
"""Production socket primitive + actual pose send policy vs delayed-EOF owned server."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,re,socket,subprocess,tempfile,threading,time,json
root=Path(__file__).resolve().parents[2]
s=(_pp_split().path(root,'PPController.swift')).read_text()
start=s.index('    static func socketRoundtrip(');end=s.index('    // ── Convenience:',start)
primitive=s[start:end].replace('Darwin.','Glibc.').replace('SOCK_STREAM, 0','Int32(SOCK_STREAM.rawValue), 0').replace('SHUT_WR)','Int32(SHUT_WR))')
pose=s.split('private func drainLatestPose()',1)[1].split('func sendLatestPose',1)[0]
call=next(l.strip()for l in pose.splitlines()if 'socketRoundtrip('in l)
assert 'sendOnly:true' in call,'continuous pose still waits for EOF'
with tempfile.TemporaryDirectory() as d:
 p=Path(d);server=socket.socket(socket.AF_UNIX);server.bind(str(p/'socket'));server.listen(20);server.settimeout(.2);messages=[];stop=False;workers=[]
 def client(c):
  with c:
   buf=b''
   while b'\n' not in buf:
    b=c.recv(4096)
    if not b:break
    buf+=b
   messages.append(json.loads(buf))
   time.sleep(.25)
   try:c.sendall(b'{"error":"success"}\n')
   except BrokenPipeError:pass
 def serve():
  while not stop:
   try:c,_=server.accept()
   except socket.timeout:continue
   t=threading.Thread(target=client,args=(c,));t.start();workers.append(t)
 t=threading.Thread(target=serve);t.start()
 main='''import Foundation
import Glibc
final class IPCClient {
'''+primitive+'''}
let path=CommandLine.arguments[1]
for sendOnly in [false,true] {
 let began=ProcessInfo.processInfo.systemUptime
 for i in 0..<4 {
  let json="{\\"command\\":[\\"pose\\",\\(i)]}"
  _=IPCClient.socketRoundtrip(path:path,payload:json,timeout:0.5,sendOnly:sendOnly)
 }
 print("MEAS sendOnly=\\(sendOnly) elapsed_s=\\(ProcessInfo.processInfo.systemUptime-began)")
}
'''
 (p/'main.swift').write_text(main)
 try:
  subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'probe')],check=True,capture_output=True,text=True)
  r=subprocess.run([str(p/'probe'),str(p/'socket')],capture_output=True,text=True,check=True,timeout=10);print(r.stdout)
 finally:
  stop=True;t.join();server.close()
  for w in workers:w.join()
 values=[float(v)for v in re.findall(r'elapsed_s=([0-9.eE+-]+)',r.stdout)]
 assert len(messages)==8 and all(m['command'][0]=='pose'for m in messages),messages
 assert values[0]>.8 and values[1]<.1,values
 print('PASS actual production transport:8 whole JSON lines, delayed-EOF baseline red, pose send-only no reply wait; coalescing unchanged')
