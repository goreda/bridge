#!/usr/bin/env python3
"""Compile real owner probe + real transport. An owned delayed server observes command order."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,socket,subprocess,tempfile,threading,json,time
root=Path(__file__).resolve().parents[2]
s=(_pp_split().path(root,'PPController.swift')).read_text();start=s.index('    static func socketRoundtrip(');end=s.index('    // ── Convenience:',start)
primitive=s[start:end].replace('Darwin.','Glibc.').replace('SOCK_STREAM, 0','Int32(SOCK_STREAM.rawValue), 0').replace('SHUT_WR)','Int32(SHUT_WR))')
source=(root/'Sources/gor/Engine/MPVCommand.swift').read_text();command=source[source.index('enum MPVCommand {'):source.index('// Backend admission')];probe=source[source.index('enum OwnerActionPlayerProbe {'):source.rindex('#endif')]
assert 'client.send(' not in probe.split('static func restoreVariant',1)[0]
with tempfile.TemporaryDirectory() as d:
 p=Path(d);sock=socket.socket(socket.AF_UNIX);sock.bind(str(p/'sock'));sock.listen();got=[]
 def serve():
  for j in range(2):
   c,_=sock.accept()
   with c:
    buf=b''
    while True:
     v=c.recv(4096)
     if not v:break
     buf+=v
    lines=[json.loads(v)['command'] for v in buf.splitlines()];got.append(lines)
    time.sleep(.2)
    c.sendall(b'{"error":"success"}\n')
 t=threading.Thread(target=serve);t.start()
 swift='import Foundation\nimport Glibc\n'+command+'\nfinal class IPCClient {\nlet path:String\ninit(path:String){self.path=path}\nfunc send(_ s:String){fatalError("async send must not be used by setRoll")}\nfunc queryBatch(_ s:String,timeout:TimeInterval)->[String]{Self.socketRoundtrip(path:path,payload:s,timeout:timeout)}\n'+primitive+'}\n'+probe+'\nOwnerActionPlayerProbe.setRoll(socket:CommandLine.arguments[1],extended:false,roll:"0.174532925")\nOwnerActionPlayerProbe.setRoll(socket:CommandLine.arguments[1],extended:true,roll:"0")\n'
 (p/'main.swift').write_text(swift)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'probe')],check=True,capture_output=True,text=True)
 subprocess.run([str(p/'probe'),str(p/'sock')],check=True,timeout=10);t.join();sock.close()
 assert len(got)==2
 for commands,active,roll in zip(got,('false','true'),('0.174532925','0')):
  assert len(commands)==2 and commands[0][-1]==active and commands[1][2]=='vr180-look-set-orientation' and commands[1][6]==roll,commands
 print('PASS actual Swift owner probe delivers variant then pose on one ordered connection; delayed200ms replies cannot outrun receipt. Mac shader assertion unchanged.')
