#!/usr/bin/env python3
"""195f typed-expression compile repair preserves the signed ratio predicate."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
s=_s3read(root/'Sources/gor/Camera/Pose192d.swift')
a=s.index('        let bounds: [Double] = ratios.flatMap')
b=s.index('        samples.append(bounds)',a)
actual=s[a:b].replace('        if let centres, let bands {','        do {')
program='''import Foundation
func fixed(_ ratios:[Double],_ foreshortening:Double,_ centres:[Double],_ bands:[Double])->Bool {
'''+actual+'''}
func reference(_ r:[Double],_ f:Double,_ c:[Double],_ b:[Double])->Bool {
 let x=r.flatMap {[$0*f,$0/f]}
 for j in 0..<2 { if !(x[j*2+1]>=c[j*2]-b[j*2] && x[j*2]<=c[j*2+1]+b[j*2+1]) {return false} }
 return true
}
var count=0
let values:[Double]=[-Double.infinity,-1,-0.0,0,Double.ulpOfOne,0.1,1,10,Double.greatestFiniteMagnitude,Double.infinity,Double.nan]
for x in values {for y in values {for f in values {
 let r=[x,y],c=[y,x,x,y],b=[x,y,y,x]
 precondition(fixed(r,f,c,b)==reference(r,f,c,b));count+=1
}}}
for i in 1...100000 {
 let r=[Double(i%123)/13,Double(i%371)/31],f=Double(i%997+1)/998
 let c=[0.1,1,0.5,2],b=[0.01,0.03,0.04,0.07]
 precondition(fixed(r,f,c,b)==reference(r,f,c,b));count+=1
}
print("PASS typed signed ratio predicate equivalence \\(count) cases")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
