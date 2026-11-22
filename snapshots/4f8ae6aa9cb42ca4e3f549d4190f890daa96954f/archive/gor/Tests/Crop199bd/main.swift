import Foundation
import Glibc
let mode=CommandLine.arguments[1]
let root="/tmp/crop-local-early-tests/"
try? FileManager.default.removeItem(atPath:root+"release")
try? FileManager.default.removeItem(atPath:root+"decodes.log")
let scanner=SourcePixelCropScanner();var early:[CGRect]=[];var done=false;var final:CGRect?;let began=ProcessInfo.processInfo.systemUptime
scanner.scan(path:mode,duration:400,stereo:false,interim:{r,c in early.append(r)}) {r,d,c in final=r;done=true}
func pump(_ until:()->Bool,_ timeout:Double) {let end=Date().addingTimeInterval(timeout);while !until() && Date()<end {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}}
func decoded()->[String] {(try? String(contentsOfFile:root+"decodes.log"))?.split(separator:"\n").map(String.init) ?? []}
pump({decoded().count>=4},5)
precondition(decoded().count>=4,"first3 must complete without waiting for global scans")
precondition(!done,"global completion held independently")
precondition(decoded()[0].split(separator:" ")[1]=="0.0","frame0 attempt first")
precondition(ProcessInfo.processInfo.systemUptime-began<5,"no scheduled startup delay")
if mode=="agree" || mode=="change" || mode=="cancel" || mode=="switch" {precondition(early.count==1 && early[0].height<1,"three agreeing separated source frames publish before global completion")}
else {precondition(early.isEmpty,"black/disagreement/RGB may not early crop")}
if mode=="cancel" {scanner.cancel()}
if mode=="switch" {scanner.scan(path:"black",duration:400,stereo:false,interim:{_,_ in preconditionFailure("new black opening has no crop")}){_,_,_ in done=true}}
FileManager.default.createFile(atPath:root+"release",contents:Data())
if mode=="cancel" {pump({false},0.3);precondition(!done && early.count==1)}
else {pump({done},8);precondition(done)}
if mode=="change" {precondition(early.count>=2 && early.last?.height==1 && final==nil,"new wider content restores immediately before global final")}
if mode=="agree" {precondition(final?.height==early[0].height)}
print("PASS actual scanner \(mode): opening source decode admission, early callback before global completion, pixel veto and epoch fences")
