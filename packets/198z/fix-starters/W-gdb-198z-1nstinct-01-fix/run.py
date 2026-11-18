from pathlib import Path
import os,subprocess,tempfile,sys,json,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
HERE=Path(__file__).resolve().parent
cfg=json.loads((HERE/'binding.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift: print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
root=Path(os.environ.get('PRODUCT_ROOT',str(HERE/'exact-source')))
def declaration(text,marker):
 start=text.index(marker); brace=text.index('{',start); depth=1; i=brace+1
 while depth:
  if text[i]=='{': depth+=1
  elif text[i]=='}': depth-=1
  i+=1
 return text[start:i]
source=(root/cfg['source']).read_text()
kind=declaration(source,'public enum TrackKind:')
method=declaration(source,'public static func stableStreamID(')
# Verbatim declarations only, no rewritten algorithm and no provider mocks.
with tempfile.TemporaryDirectory() as td:
 td=Path(td); extracted=td/'Identity.swift'; extracted.write_text('import Foundation\npublic enum MediaInventory {\n'+kind+'\n'+method+'\n}\n')
 main=td/'main.swift'; main.write_text((HERE/'Regression.swift').read_text()); exe=td/'test'
 args=[swift,str(extracted),str(main),'-o',str(exe)]
 c=subprocess.run(args,capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(c.returncode)
