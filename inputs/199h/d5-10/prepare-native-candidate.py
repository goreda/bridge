#!/usr/bin/env python3
"""On a native Mac, emit each candidate before its compile CI receipt.
Use the real product worktree, not the carrier's differently rooted payload.
Only the two generated manifests may change. Print the final exact candidate.
"""
import argparse,hashlib,json,platform,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--repo',type=Path,required=True);p.add_argument('--source',required=True);p.add_argument('--receipt',type=Path,required=True);a=p.parse_args()
def git(*args):return subprocess.check_output(['git','-C',str(a.repo),*args]).decode().strip()
assert platform.system()=='Darwin','Native manifest emission needs Darwin Swift; no Linux substitute'
source=git('rev-parse',a.source);assert git('rev-parse','HEAD')==source,'Wrong source checkout'
assert not git('status','--porcelain','--untracked-files=all'),'Candidate worktree must be clean'
r=a.repo/'archive/gor';allowed=['archive/gor/architecture/delivery.tsv','archive/gor/architecture/manifest.tsv']
# --emit also reports existing architecture debt. That report is not a new
# delivery gate:199h requires generated native manifests + real integrity.
emit=subprocess.run([sys.executable,str(r/'tools/architecture.py'),'--root',str(r),'--emit'])
changed=git('diff','--name-only').splitlines();assert set(changed)<=set(allowed),'Emitter changed non-manifest source'
if changed:
 subprocess.run(['git','-C',str(a.repo),'add','--',*allowed],check=True)
 subprocess.run(['git','-C',str(a.repo),'commit','-m','delivery: automatically emit native candidate manifests'],check=True)
candidate=git('rev-parse','HEAD')
for command in ([sys.executable,str(r/'tools/architecture.py'),'--root',str(r),'--integrity-only'],[sys.executable,str(r/'Tests/Architecture/manifest_tree_test.py')]):subprocess.run(command,check=True,cwd=r)
receipt=dict(candidate=candidate,source=source,result='PASS',platform=platform.platform(),manifest_tree_test='PASS',architecture_report_exit=emit.returncode,files={p.removeprefix('archive/gor/'):hashlib.sha256((a.repo/p).read_bytes()).hexdigest() for p in allowed})
a.receipt.write_text(json.dumps(receipt,indent=2)+'\n');print('NATIVE_CANDIDATE '+json.dumps(receipt))
