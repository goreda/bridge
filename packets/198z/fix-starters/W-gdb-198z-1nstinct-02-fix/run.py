from pathlib import Path
import os,subprocess,tempfile,sys,json,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
HERE=Path(__file__).resolve().parent
cfg=json.loads((HERE/'binding.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift: print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
root=Path(os.environ.get('PRODUCT_ROOT',str(HERE/'exact-source')))
with tempfile.TemporaryDirectory() as td:
 td=Path(td); main=td/'main.swift';main.write_text((HERE/'Regression.swift').read_text())
 sources=[str(root/p) for p in cfg['compile_inputs']]
 ids=[]
 for mode in ['normal','diagnostic']:
  extra=[]
  if mode=='diagnostic':
   probe=td/'Description.swift';probe.write_text('extension SubtitleCue: CustomStringConvertible { public var description: String { "diagnostic-only" } }\n');extra=[str(probe)]
  exe=td/mode
  c=subprocess.run([swift]+sources+extra+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90)
  print(mode+'_compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
  if c.returncode:sys.exit(2)
  c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15)
  if c.returncode:print(c.stdout+c.stderr);sys.exit(2)
  ids.append(c.stdout.strip());print(mode+'_id='+ids[-1])
 print(('PASS' if ids[0]==ids[1] else 'FAIL')+' identity must not depend on diagnostic description')
 sys.exit(0 if ids[0]==ids[1] else 1)
