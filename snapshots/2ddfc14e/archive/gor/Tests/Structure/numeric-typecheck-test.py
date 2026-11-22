#!/usr/bin/env python3
"""Compile exact numeric closures and compare old/new output bits."""
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,shutil
root=Path(__file__).resolve().parents[2];s=(_threed_split().path(root)).read_text()
def span(start,end):return s[s.index(start):s.index(end,s.index(start))]
parts=['import Foundation','struct Tensor {var d:[Float]}','struct Fit {var scale:Double;var shift:Double}']
parts+=['func hole(_ values:[Float],_ threshold:Float)->[Bool] {let m=Tensor(d:values);'+span('var b = m.d.map','        if innerDilation')+';return b}']
parts+=['func gauss(_ k:Int)->[Double] {let sigma=Double(k)*0.15+0.35,half=Double(k-1)*0.5;'+span('let v: [Double] = (0..<k).map','        let s = v.reduce')+';return v}']
parts+=['func deviation(_ m:[Double],_ m2:[Double])->[Float] {let w=m.count,h=1;'+span('return (0..<(w * h)).map { (index: Int) -> Float','    /// numpy.percentile').rsplit('    }',1)[0]+'}']
parts+=['enum Fade { '+span('    static func fadeAmounts','    static func fadeFlatten')+'}']
parts+=['func mask(_ m2:[Double],_ n:Int,_ staticThresh:Double)->[Bool] {let w=m2.count,h=1;'+span('let m: [Bool] = (0..<(w * h)).map','            let frac')+';return m}']
parts+=['func inverse(_ z:[Float])->[Float] {'+span('let inv: [Float] = z.map','            var d = [Double]()')+';return inv}']
parts+=['func scaled(_ vda:[Float],_ q:Fit)->[Float] {'+span('return vda.map { (value: Float) -> Float','// END relocated',).rsplit('    }',1)[0]+'}'] if False else []
# scale closure ends at its own four-line boundary.
start=s.index('return vda.map { (value: Float) -> Float');end=s.index('\n        }',start)+10
parts+=['func scaled(_ vda:[Float],_ q:Fit)->[Float] {'+s[start:end]+'}']
parts+=[r'''
var seed:UInt64=191
func sample()->Double{seed=seed&*6364136223846793005&+1;return Double(seed>>32)/Double(UInt32.max)}
for _ in 0..<1000 {
 let x:[Float]=(0..<33).map{_ in Float(sample()*20-10)},a:[Double]=x.map{Double($0)},b=a.map{$0*$0+sample()}
 let th:Float=Float(sample());precondition(hole(x,th)==x.map{1.0/(1.0+Float(exp(Double(-$0))))>th})
 let k=15,sigma=Double(k)*0.15+0.35,half=Double(k-1)*0.5
 let g:[Double]=(0..<k).map{exp(-0.5*pow((-half+Double($0)*(2*half)/Double(k-1))/sigma,2))}
 precondition(gauss(k).map{$0.bitPattern}==g.map{$0.bitPattern})
 let dev:[Float]=(0..<a.count).map{Float(max(b[$0]-a[$0]*a[$0],0).squareRoot())};precondition(deviation(a,b).map{$0.bitPattern}==dev.map{$0.bitPattern})
 var peak=1e-6;let fade:[Double]=a.map{v in peak=max(peak,max(v,1e-6));let q=1.0-v/peak;return q>=0.5 ? q:0.0};precondition(Fade.fadeAmounts(meanLuma:a).map{$0.bitPattern}==fade.map{$0.bitPattern})
 precondition(mask(b,9,2.0)==b.map{($0/Double(9)).squareRoot()<2.0})
 let inv:[Float]=x.map{($0.isFinite && $0>1e-3) ? 1.0/$0:0};precondition(inverse(x).map{$0.bitPattern}==inv.map{$0.bitPattern})
 let fit=Fit(scale:sample(),shift:sample());let mapped:[Float]=x.map{Float(Double($0)*fit.scale+fit.shift)};precondition(scaled(x,fit).map{$0.bitPattern}==mapped.map{$0.bitPattern})
}
print("PASS7 actual numeric closure rewrites1000fixtures each: exact Bool and Float/Double bit patterns")
''']
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text('\n'.join(parts));swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
