#!/usr/bin/env python3
"""Delivered98 depth-cache regression. Disposable Linux fixtures, never native PASS.
Extracts the full actual Budget + IO declarations. Only unrelated generation-name
recognition is a conservative false double. No production source embedded.
Use --source for another exact ThreeD.swift, --expect-legacy-gap for delivered98,
and --mutants for compiling discrimination controls. Default expects all green.
"""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile,sys
p=argparse.ArgumentParser();p.add_argument('--source',type=Path);p.add_argument('--expect-legacy-gap',action='store_true');p.add_argument('--mutants',action='store_true');p.add_argument('--out',type=Path);p.add_argument('--cache-only',action='store_true');a=p.parse_args()
r=Path(__file__).resolve().parents[2];src=a.source or _threed_split().path(r);s=src.read_text();sw=os.environ.get('SWIFTC','swiftc');out=a.out or Path(tempfile.mkdtemp(prefix='depth-cache-evidence-'));out.mkdir(parents=True,exist_ok=True)
def decl(text,marker):
 start=text.index(marker);opening=text.index('{',start);level=1;i=opening+1
 while level:
  if text[i]=='{':level+=1
  elif text[i]=='}':level-=1
  i+=1
 return text[start:i]
# Source structural assertions are not decoder/pixel proof.
assert 'let readableFilm=request.film' in s
assert s.count('FrameReader(url: readableFilm,')>=2   # 199h D2: the source-proxy second decode is deleted; two by-index original-film readers remain
assert 'func prepareReadableSource(' not in s
assert 'removeTransient(' not in s
for line in s.splitlines():
 if 'prepare-input' in line:
  assert 'let fixed:Set<String>' in line or 'for name in [' in line,('unexpected prepare-input path',line)
assert 'reapLegacyInputs(root:root,source:startupSource)' in s
budget=decl(s,'enum DepthCacheBudget {');io=decl(s,'enum DepthCacheIO {')
fixture=Path(__file__).with_name('depth_cache_fixtures.swift').read_text()
header='import Foundation\n#if canImport(Darwin)\nimport Darwin\n#else\nimport Glibc\n#endif\n// Unrelated generation-name recognition: conservative double, not under test.\nenum ShotGenerationStore {static func recognized(_ s:String)->Bool {false}}\n'
variants={'actual':budget+'\n'+io}
if a.mutants:
 mutations={
 'omit-owner-part':('for name in ["prepare-input.part","prepare-input.part.mp4","prepare-input.mp4"]','for name in ["prepare-input.part.mp4","prepare-input.mp4"]'),
 'omit-entry-pin':('if flock(pin,LOCK_EX|LOCK_NB) != 0 {','if false {'),
 'ignore-quota':('guard used<=q,bytes<=q-used else','guard true else'),
 'ignore-reserve':('guard free>=p.reserve,bytes<=free-p.reserve else','guard true else'),
 'append-zero-charge':('try transact(url:url,bytes:UInt64(data.count)) {','try transact(url:url,bytes:0) {'),
 'omit-worker-lock':('if flock(worker,LOCK_EX|LOCK_NB) != 0 {','if false {'),
 }
 for name,(old,new) in mutations.items():
  assert variants['actual'].count(old)>=1,(name,'marker absent')
  variants[name]=variants['actual'].replace(old,new,1)
rows=[]
for name,text in variants.items():
 for mode in ['-Onone','-O']:
  with tempfile.TemporaryDirectory(prefix='gor-depth-cache-') as td:
   q=Path(td);main=q/'main.swift';main.write_text(header+text+'\n'+fixture);binary=q/'test'
   c=subprocess.run([sw,'-swift-version','5',mode,str(main),'-o',str(binary)],capture_output=True,text=True,timeout=90)
   (out/(name+mode+'-compile.log')).write_text(c.stdout+c.stderr)
   if c.returncode:raise RuntimeError((name,mode,'COMPILE_ERROR',c.stderr))
   run=subprocess.run([str(binary),str(q/'cache')],capture_output=True,text=True,timeout=20)
   (out/(name+mode+'-run.log')).write_text(run.stdout+run.stderr)
   fail=[x for x in run.stdout.splitlines() if x.startswith('FAIL ')]
   if name=='actual' and a.expect_legacy_gap:
    assert run.returncode==1 and fail==['FAIL owned exact legacy prepare-input.part','FAIL owned residual entry stays deletable prepare-input.part'],(name,mode,fail,run.stderr)
   elif name=='actual':assert run.returncode==0,(mode,fail,run.stderr)
   else:assert run.returncode==1 and fail,(name,mode,'survivor or crash',run.returncode,fail,run.stderr)
   row=dict(variant=name,mode=mode,compile_exit=0,semantic_exit=run.returncode,failures=fail,summary=run.stdout.splitlines()[-1:] );rows.append(row);print(row,flush=True)
(out/'RESULTS.json').write_text(json.dumps(dict(source_sha256=hashlib.sha256(src.read_bytes()).hexdigest(),rows=rows,scope='Linux exact-source filesystem; native NOT_RUN'),indent=2)+'\n')
print('PASS source guards: original-film readers, no full-source remux constructor, startup cleanup call. Structural only.')
print('Bounded logger tests are outside this depth-cache entrypoint; use shared_diagnostics.py and remaining_writers.py separately.')
