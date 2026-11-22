#!/usr/bin/env python3
"""Compile actual fade implementation and compare Float bit patterns to prior formula."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import tempfile,subprocess,shutil
root=Path(__file__).resolve().parents[2]
s=(_threed_split().path(root)).read_text();body=s[s.index('    static func fadeAmounts'):s.index('    // MARK: 3. static overlay')]
program='import Foundation\nenum Actual {\n'+body+'\n}\n'+r'''
func prior(_ inv:[[Float]],_ luma:[Double])->[[Float]] {
 let a=Actual.fadeAmounts(meanLuma:luma);guard a.contains(where:{$0>0}),let n=inv.first?.count else{return inv}
 var med=[Float](repeating:0,count:n),col=[Float](repeating:0,count:inv.count)
 for p in 0..<n {for t in 0..<inv.count {col[t]=inv[t][p]};col.sort();let c=col.count;med[p]=c%2==1 ? col[c/2]:Float((Double(col[c/2-1])+Double(col[c/2]))/2.0)}
 return inv.enumerated().map { (t:Int,f:[Float])->[Float] in
  if a[t]<=0{return f}
  return (0..<n).map { (i:Int)->Float in Float((1.0-a[t])*Double(f[i])+a[t]*Double(med[i])) }
 }
}
var seed:UInt64=73
func sampleValue()->Double {seed=seed&*6364136223846793005&+1;return Double(seed>>32)/Double(UInt32.max)}
for frames in 1...12 {for count in [0,1,2,17,65] {for _ in 0..<20 {
 let inv=(0..<frames).map{_ in (0..<count).map{_ in Float(sampleValue()*20-10)}}
 let luma=(0..<frames).map{_ in sampleValue()*2}
 let a=Actual.fadeFlatten(inv:inv,meanLuma:luma),b=prior(inv,luma)
 precondition(a.map{$0.map{$0.bitPattern}}==b.map{$0.map{$0.bitPattern}})
}}}
precondition(Actual.fadeFlatten(inv:[],meanLuma:[]).isEmpty)
print("PASS actual fadeFlatten explicit-loop equivalence1200fixtures Float bit patterns unchanged")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program);swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
