#!/usr/bin/env python3
"""Deterministic source-only gorav refresh. Never builds or changes app defaults.
Uses a local Git source; refuses unrecorded drift and unapproved local overlays.
All validation precedes writes. Upstream/local conflicts require a reviewed merge,
not an implicit preference. Does not remove files from the installed snapshot.
"""
import argparse,hashlib,json,subprocess
from pathlib import Path

def sha(data):return hashlib.sha256(data).hexdigest()
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args],stderr=subprocess.DEVNULL)
def eligible(name):
 return (name=='Package.swift' or (name.startswith(('Sources/','Tests/','Shaders/')) and Path(name).suffix in {'.swift','.c','.h','.metal','.modulemap','.lua'}) or name=='tools/p27-frame-tap-test.py')
def tree(repo,rev):
 rows={}
 for row in git(repo,'ls-tree','-rz',rev).split(b'\0'):
  if not row:continue
  meta,raw=row.split(b'\t');mode,kind,oid=meta.decode().split();name=raw.decode()
  if not eligible(name):continue
  if kind!='blob' or mode not in ('100644','100755'):raise ValueError('unsupported source mode: '+name)
  rows[name]=git(repo,'cat-file','blob',oid)
 return rows

def refresh(repo,revision,dest,preserve=(),write=False):
 dest=Path(dest);lock=json.loads((dest/'source-lock.json').read_text())
 revision=git(repo,'rev-parse',revision+'^{commit}').decode().strip()
 actual={p.relative_to(dest).as_posix():p.read_bytes() for p in dest.rglob('*') if p.is_file() and p.name!='source-lock.json'}
 if any(p.is_symlink() for p in dest.rglob('*')):raise ValueError('vendor symlink refused')
 if {p:sha(b) for p,b in actual.items()}!=lock['files']:raise ValueError('unrecorded vendor drift')
 base=tree(repo,lock['revision']);upstream=tree(repo,revision);preserve=set(preserve)
 if not preserve.issubset(actual):raise ValueError('preserved path does not exist')
 overlays={p for p,b in actual.items() if base.get(p)!=b}
 if overlays-preserve:raise ValueError('unapproved local overlay: '+','.join(sorted(overlays-preserve)))
 output=dict(upstream);kept={}
 for p in sorted(overlays):
  if upstream.get(p) not in (None,base.get(p),actual[p]):raise ValueError('upstream/local conflict: '+p)
  output[p]=actual[p];kept[p]=sha(actual[p])
 missing=set(actual)-set(output)
 if missing:raise ValueError('upstream removal needs separate review: '+','.join(sorted(missing)))
 protected=['Sources/GorAVMacShell/FrameTap.swift','Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift','Sources/GorAVMacShell/ShellFrameSource.swift']
 result={'repository':lock['repository'],'revision':revision,'files':{p:sha(b) for p,b in sorted(output.items())}}
 if kept:result['preserved_local']={'base_revision':lock.get('preserved_local',{}).get('base_revision',lock['revision']),'files':kept}
 receipt={'source_revision':revision,'prior_revision':lock['revision'],'file_count':len(output),'changed':sorted(p for p in output if actual.get(p)!=output[p]),'preserved_local':kept,'p27_unchanged':{p:actual[p]==output.get(p) for p in protected if p in actual}}
 if write:
  for p,b in sorted(output.items()):
   target=dest/p;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(b)
  (dest/'source-lock.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
 return receipt
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source-repo',required=True);p.add_argument('--revision',required=True);p.add_argument('--dest',type=Path,default=Path(__file__).resolve().parents[1]/'Packages/gorav');p.add_argument('--preserve',action='append',default=[]);p.add_argument('--write',action='store_true');a=p.parse_args()
 try:print(json.dumps(refresh(a.source_repo,a.revision,a.dest,a.preserve,a.write),indent=2,sort_keys=True))
 except (ValueError,subprocess.CalledProcessError) as e:p.exit(1,'REFUSED: '+str(e)+'\n')
