import Foundation
let m=PhotonV4Model.self
for src in [480.0,720,1080,2160] { for out in [1080.0,1440,2160] { for cell in [0.4,0.8,1.2,2,5] {
 print(String(format:"cell %.12f",try m.cell(sourceHeight:src,outputHeight:out,sourceCell:cell,confidence:1,lookFraction:0.8/1080,trim:1)))
}}}
for t in [0.0015,0.003,0.01,0.02] { for s in [0.0,0.001,0.01,0.04] { for c in [1.0,1.5,2] {
 let v=try m.sigma(target:t,source:s,compression:c); precondition(v>0 && v>=0.35*t*c-1e-16)
 print(String(format:"sigma %.12f",v))
}}}
for y in [-1.0,0,0.1,0.5,1,2] { print(String(format:"pwl %.12f",try m.pwl(y,xs:[0,0.5,1],ys:[0.001,0.01,0.002]))) }
precondition(try! m.sigma(target:0.01,source:0,amount:0)==0)
precondition(try! m.sigma(target:0.01,source:0,enabled:false)==0)
precondition((try? m.pwl(0.5,xs:[0,0],ys:[1,2]))==nil)
precondition((try? m.cell(sourceHeight:0,outputHeight:1080,sourceCell:1,confidence:1,lookFraction:0.001,trim:1))==nil)
precondition((try? m.cell(sourceHeight:480,outputHeight:.infinity,sourceCell:1,confidence:1,lookFraction:0.001,trim:1))==nil)
