#!/usr/bin/env python3
"""195w W4: restored raw paths and retained ZIP safety.
Supersedes per-session path/live-periodic requirements by owner arch-195w.
Native60s /tmp listing and owner camera outcome are explicitly not simulated here.
"""

# Core pure-move source view; existing assertions and compiler bodies are unchanged.
import importlib.util as _core_iu
from pathlib import Path as _CorePath
_core_root=next(p for p in _CorePath(__file__).resolve().parents if (p/'Tests/Structure/core_source.py').is_file())
_core_spec=_core_iu.spec_from_file_location('core_source_view',_core_root/'Tests/Structure/core_source.py')
_core_view=_core_iu.module_from_spec(_core_spec);_core_spec.loader.exec_module(_core_view)
_core_read=_core_view.read_source
_core_bytes=_core_view.read_bytes
_core_materialize=_core_view.materialize
from pathlib import Path
import tempfile,sys,subprocess,zipfile,os,shutil,json,hashlib
r=Path(__file__).resolve().parents[2];sys.path.insert(0,str(r/'tools'))
import session_log_paths as paths
import bounded_log_archives as bounded
build=_core_read(r/'build.sh');app=_core_read(r/'Sources/gor/App/AppDelegate.swift')
helper=build.split("<<'GOR_SESSION_HELPER'",1)[1].split('\nGOR_SESSION_HELPER',1)[0]
namespace={};exec(compile(helper.split("if sys.argv[1]=='arm':",1)[0],'helper','exec'),namespace)
assert paths.create()==Path('/tmp') and paths.active()==Path('/tmp')
os.environ['GOR_LOG_SESSION_DIR']='/tmp/gor-log-session-stale'
for n in paths.NAMES:assert paths.resolve('/tmp/'+n)==Path('/tmp')/n
# Shared raw files survive archive/cleanup, even if a caller asks to retire them.
paths.cleanup('/tmp',{'gor_diag.log':(0,0,0,0)})
assert "archive(record,'playback-snapshot',final=False)" not in helper
assert "elif sys.argv[1]=='snapshot':" in helper and "'on-demand',final=False" in helper
assert "while identity(record['pid'])==record['identity']:\n        time.sleep(1);tick+=1" in helper and "finish(pending,'owner-process-exited')" in helper
assert 'destination+".prev"' not in build
assert 'M.rotate_log(path, #line, cap)' not in _core_read(r/'Resources/vendor/mpv/scripts/photon-common.lua')
assert 'p.environment?.removeValue(forKey:"GOR_LOG_SESSION_DIR")' in app
assert 'GOR_LOG_SESSION_DIR' not in _core_read(r/'Resources/vendor/mpv/scripts/photon.lua')
assert 'directory.appendingPathComponent("quit-debug.log").path' in app
assert 'SharedDiagnosticRecord.cap' in _core_read(r/'Sources/gor/GorCore/Diag.swift')
with tempfile.TemporaryDirectory() as td:
 t=Path(td);bundle=t/'app';res=bundle/'Contents/Resources';res.mkdir(parents=True)
 (res/'build-id.txt').write_text('build=fixture');config=t/'config';(config/'scripts').mkdir(parents=True)
 (config/'scripts/fixture.lua').write_text('return {}');(config/'photon-grain-doc.log').write_text('2026-11-13T17:19:43+0300 baseline-config\n')
 root=paths.create(t);MK=b'[GOR-SESSION] pid=123 launch_epoch=1 launch_id='+b'a'*32+b' build=unknown tree=unknown\n';(root/'gor_diag.log').write_bytes(MK+b'12:00:00.000 SEED OK lua=1\nbounded-raw\n')
 original=bounded.publish;bounded.publish=lambda entries,**kw:original(entries,t/'archive',**kw)
 record=dict(id='fixture',pid=123,bundle=str(bundle),config=str(config),log_root=str(root),started=1)
 output=namespace['archive'](record,'on-demand',final=False)
 with zipfile.ZipFile(output) as z:
  assert z.testzip() is None and z.read('gor_diag.log').startswith(b'[GOR-IDENTITY] v1 ') and z.read('gor_diag.log').split(b'\n',1)[1]==MK+b'12:00:00.000 SEED OK lua=1\nbounded-raw\n'
  assert z.read('photon-grain-doc.log')==b'2026-11-13T17:19:43+0300 baseline-config\n' and b'CUT-START gor-launch=' in z.read('collection-status.txt')
 assert _core_bytes(root/'gor_diag.log')==MK+b'12:00:00.000 SEED OK lua=1\nbounded-raw\n'
 def fail(*a,**kw):raise OSError('injected full store')
 bounded.publish=fail
 try:namespace['archive'](record,'on-demand',final=False);raise AssertionError('must fail')
 except OSError:pass
 assert _core_bytes(root/'gor_diag.log')==MK+b'12:00:00.000 SEED OK lua=1\nbounded-raw\n'
 bounded.publish=original
 # Session cut (owner order 2026-11-15): every log cut to the current gor session.
 import time as _t
 now=_t.time();launched=now-3600;pid=424242
 root2=t/'session2';root2.mkdir();logs=paths.create(root2)
 (logs/'wt_full.log').write_text('[2026-11-13T09:00:00.000Z] INIT:v1\n[2026-11-13T09:00:01.000Z] STATS:{"session":11111}\nstale\n[2026-11-15T08:38:36.851Z] INIT:v2\n[2026-11-15T08:38:37.000Z] STATS:{"session":%d}\ncurrent\n'%pid)
 seed_stamp=_t.strftime('%H:%M:%S',_t.localtime(now-60))+'.233'
 (logs/'gor_diag.log').write_bytes(b'[GOR-SESSION] pid=1 launch_epoch=1 launch_id='+b'b'*32+b' build=unknown tree=unknown\n10:00:00.000 SEED OK lua=1\nold\n'+('[GOR-SESSION] pid=%d launch_epoch=%d launch_id='%(pid,int(launched)+1)).encode()+b'c'*32+b' build=unknown tree=unknown\n'+(seed_stamp+' SEED OK lua=16\nnew\n').encode())
 (logs/'gor-quit-debug.log').write_text('ts=%d pid=1 old\nts=%d pid=%d new\n'%(int(launched-7200),int(now),pid))
 (logs/'photon-grain-doc.log').write_text('2026-11-13T17:19:43+0300 old\n%s new\n'%_t.strftime('%Y-%m-%dT%H:%M:%S+0300',_t.localtime(now-60)))
 stale=logs/'gor-wt-lag-11111-1.txt';stale.write_text('stale');os.utime(stale,(now-3*86400,now-3*86400))
 (logs/('gor-wt-lag-%d-1.txt'%pid)).write_text('current lag')
 (logs/'gor_sample.txt').write_text('Analysis of sampling gor (pid 999)\n');os.utime(logs/'gor_sample.txt',(now-3*86400,now-3*86400))
 rec2=dict(id='cut',pid=pid,bundle=str(bundle),config=str(config),log_root=str(logs),started=launched)
 out2=namespace['archive'](rec2,'on-demand',final=False)
 with zipfile.ZipFile(out2) as z:
  names=set(z.namelist());st=z.read('collection-status.txt').decode()
  assert z.read('wt_full.log').startswith(b'[2026-11-15T08:38:36.851Z] INIT:v2')
  assert z.read('gor_diag.log').split(b'\n',2)[2]==(seed_stamp+' SEED OK lua=16\nnew\n').encode() and z.read('gor_diag.log').startswith(b'[GOR-IDENTITY] v1 ')
  assert z.read('gor-quit-debug.log')==('ts=%d pid=%d new\n'%(int(now),pid)).encode()
  assert z.read('photon-grain-doc.log').endswith(b' new\n') and b'2026-11-13' not in z.read('photon-grain-doc.log')
  assert 'gor-wt-lag-11111-1.txt' not in names and 'gor_sample.txt' not in names and ('gor-wt-lag-%d-1.txt'%pid) in names
  assert 'CUT-START gor-launch=' in st and 'EXCLUDED gor_sample.txt' in st
  assert z.testzip() is None
 # Real production Swift, no CoreML adapters or fabricated launcher decisions.
 main=t/'main.swift';main.write_text('''import Foundation
precondition(SessionLogPaths.root.path=="/tmp")
for name in SessionLogPaths.names {precondition(SessionLogPaths.path("/tmp/"+name)=="/tmp/"+name)}
print("PASS195w W4 actual Swift original/tmp paths; no native60s listing claim")
''')
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 relocated=t/'SessionLogPaths.swift';relocated.write_text(_core_read(r/'Sources/gor/GorCore/Diag.swift').split('// BEGIN relocated SessionLogPaths.swift (195w 2a, behavior unchanged)\n',1)[1].split('// END relocated SessionLogPaths.swift',1)[0])
 subprocess.run([swift,str(relocated),str(main),'-o',str(t/'test')],check=True)
 subprocess.run([str(t/'test')],check=True)
print('PASS195w W4 original raw routing/caps, ZIP CRC/failure/retention/on-demand; periodic ZIP off; native60s tmp-name comparison NOT_RUN')
