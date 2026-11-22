#!/usr/bin/env python3
from pathlib import Path
import subprocess,os,argparse,tempfile,json
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--baseline',action='store_true');p.add_argument('--allow-failure',action='store_true');p.add_argument('--compat-baseline',action='store_true');a=p.parse_args();s=a.source.read_text();a.out.mkdir(parents=True,exist_ok=True)
def decl(marker):
 b=s.index(marker);i=s.index('{',b)+1;depth=1
 while depth:
  depth+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[b:i]
markers=['struct ShotComfort:','struct ShotComfortSpan:','enum ShotComfortShot {','struct ThreeDExperimentOptions:','struct RenderPrefsValue:']
if 'enum ShotDeepGeometry {' in s:markers.insert(2,'enum ShotDeepGeometry {')
# Real pure declarations, only unavailable container/host surfaces are doubled.
head='''import Foundation
struct DZCFile {static var planes:[[UInt16]]=[];init?(url:URL){};var count:Int{Self.planes.count};func plane(_ i:Int)->[UInt16]?{Self.planes[i]}}
enum RenderPrefs {static let modes:Set<String>=["off","sbs","over_under","anaglyph","vr180"]}
enum ThreeDSubtitleDepth {
 struct RenderParams:Equatable {var ipd:Double,convergence:Double?,zNear:Double?}
'''
start=s.index('    static func params(ipdM:');i=s.index('{',start)+1;depth=1
while depth:depth+=(s[i]=='{')-(s[i]=='}');i+=1
head+=s[start:i]+'\n}\n'
compat='''
extension ShotComfort {var todayFallback:Bool {false}}
extension ShotComfort.Measurement {var mode:String {"deep"}}
extension RenderPrefsValue {func deepComfort(_ raw:ShotComfort?)->ShotComfort? {raw}}
''' if a.compat_baseline else ''
text=head+'\n'.join(decl(m) for m in markers)+'\n'+compat+Path(__file__).with_name('tests.swift').read_text().replace('import Foundation\n','')
rows=[]
for mode in ['-Onone','-O']:
 with tempfile.TemporaryDirectory() as td:
  root=Path(td);(root/'main.swift').write_text(text);c=subprocess.run([os.environ['SWIFTC'],'-swift-version','5',mode,str(root/'main.swift'),'-o',str(root/'test')],capture_output=True,text=True);(a.out/('compile'+mode+'.log')).write_text(c.stdout+c.stderr)
  if a.baseline:
   assert c.returncode!=0 and 'deepVolume' in c.stderr;print(mode,'baseline API absent RED (compile, not semantic)');continue
  assert c.returncode==0,c.stderr
  q=subprocess.run([str(root/'test')],capture_output=True,text=True,timeout=15);(a.out/('run'+mode+'.log')).write_text(q.stdout+q.stderr);print(mode,q.returncode,q.stdout)
  if not a.allow_failure:assert q.returncode==0
  rows.append(dict(mode=mode,compile_exit=0,semantic_exit=q.returncode,summary=q.stdout))
(a.out/'RESULTS.json').write_text(json.dumps(rows,indent=2)+'\n')
