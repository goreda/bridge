from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5]
CFG=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:
 print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
version=subprocess.run([swift,'--version'],capture_output=True,text=True)
print(version.stdout,flush=True)
if version.returncode:sys.exit(2)
with tempfile.TemporaryDirectory() as directory:
 d=Path(directory); main=d/'main.swift'; main.write_text(CFG['test_source'])
 for mode,optimization in [('debug','-Onone'),('optimized','-O')]:
  exe=d/('test-'+mode)
  args=[swift,optimization]+[str(ROOT/p) for p in CFG['sources']]+[str(main),'-o',str(exe)]
  print('mode='+mode+' argv='+json.dumps(args),flush=True)
  c=subprocess.run(args,capture_output=True,text=True,timeout=90)
  print('compile_exit='+str(c.returncode));print(c.stdout);print(c.stderr)
  if c.returncode:sys.exit(2)
  c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15)
  print('semantic_exit='+str(c.returncode));print(c.stdout);print(c.stderr,flush=True)
  if c.returncode:sys.exit(1)
 print('PASS_EXCERPT_SWIFT_SEMANTICS debug+optimized clean_checkout:false native_runtime:NOT_RUN package_build:NOT_RUN')
