#!/usr/bin/env python3
import argparse,re,subprocess,os,tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--baseline',type=Path,required=True);p.add_argument('--out',type=Path,required=True);a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
def decl(s,m):
 b=s.index(m);i=s.index('{',b)+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[b:i]
base=a.baseline.read_text();s=a.source.read_text();text='''import Foundation
struct DZCFile {static var planes:[[UInt16]]=[];init?(url:URL){};var count:Int{Self.planes.count};func plane(_ i:Int)->[UInt16]?{Self.planes[i]}}
'''
old='\n'.join(decl(base,m) for m in ['struct ShotComfort:','struct ShotComfortSpan:','enum ShotDeepGeometry {','enum ShotComfortShot {']);old=re.sub(r'\b(ShotComfort|ShotComfortSpan|ShotComfortShot|ShotDeepGeometry)\b',lambda m:'Legacy'+m[0],old)
text+=old+'\n'+'\n'.join(decl(s,m) for m in ['struct ShotComfort:','struct ShotComfortSpan:','enum ShotDeepGeometry {','enum ShotComfortShot {','struct ThreeDExperimentOptions:'])
text+='''
var failures=0,checks=0,state:UInt64=193
func random()->UInt16{state=state &* 6364136223846793005 &+ 1442695040888963407;return UInt16((state >> 32) & 1023)}
for shot in 0..<256 {DZCFile.planes=(0..<3).map{_ in (0..<64).map{_ in shot==0 ? UInt16(0):random()}}
 for ipd in [0.04,0.063,0.08] {
  let u=URL(fileURLWithPath:"/synthetic")
  let a=LegacyShotComfortShot.compute(depth:u,ipd:ipd),b=ShotComfortShot.compute(depth:u,ipd:ipd,options:ThreeDExperimentOptions(),screenDepth:3,strength:2,overBudget:true)
  checks+=1
  if let a,let b {let av=[a.convergenceM,a.ipdEff,a.depthScale,a.zNear,a.farOverflowDeg],bv=[b.convergenceM,b.ipdEff,b.depthScale,b.zNear,b.farOverflowDeg];if zip(av,bv).contains(where:{$0 != $1}){failures+=1;print("FAIL differential shot=\\(shot) ipd=\\(ipd) \\(av) \\(bv)")}}
  else if (a == nil) != (b == nil) {failures+=1;print("FAIL nil differential")}
 }
}
print("SUMMARY \\(checks) exact field differential checks \\(failures) failures; off compute vs supplied baseline, DZC transport double")
exit(failures==0 ? 0:1)
'''
for mode in ['-Onone','-O']:
 with tempfile.TemporaryDirectory() as td:
  r=Path(td);(r/'main.swift').write_text(text);c=subprocess.run([os.environ['SWIFTC'],'-swift-version','5',mode,str(r/'main.swift'),'-o',str(r/'test')],capture_output=True,text=True);(a.out/('compile'+mode+'.log')).write_text(c.stdout+c.stderr);assert c.returncode==0,c.stderr
  q=subprocess.run([str(r/'test')],capture_output=True,text=True,timeout=20);(a.out/('run'+mode+'.log')).write_text(q.stdout+q.stderr);print(mode,q.stdout);assert q.returncode==0
