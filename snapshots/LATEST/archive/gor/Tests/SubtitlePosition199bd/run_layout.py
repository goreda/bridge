from pathlib import Path
import subprocess,os
r=Path(__file__).resolve().parent
source=r/os.environ.get('SOURCE_DIR','post')/'Packages/gorav/Sources/GorAVMetalPresenter/core/MetalPresenter.swift'
s=source.read_text();a=s.index('    private func cueFrames(');b=s.index('    public override func viewDidChangeBackingProperties()',a)
methods=s[a:b].replace('private ','')
ca=s.index('    func displayCues(');cb=s.index('    public override init(',ca)
methods=s[ca:cb]+methods
# Last close brace before viewDidChange belongs to setSubtitlePosition, not view.
prefix='''import Foundation
final class Cell {
 var measured:Double
 init(_ h:Double){measured=h}
 func cellSize(forBounds:NSRect)->NSSize {NSSize(width:forBounds.width,height:measured)}
}
struct SubtitleCue {let text:String}
final class Label {var stringValue="";var isHidden=false;var cell:Cell?=Cell(40);var frame=NSRect.zero}
final class Layout {
 var bounds=NSRect(x:0,y:0,width:640,height:360)
 var cueLabel=Label(),secondaryCueLabel=Label()
 var subtitlePosition=100.0,needsLayout=false
 var subtitleVideoRect:(()->NSRect?)?={NSRect(x:0,y:0,width:640,height:360)}
'''
tests='''
@main struct Tests {
 static func main(){
 var n=0
 func check(_ b:Bool,_ name:String){n+=1;if !b{fatalError(name)}}
 let v=Layout();v.secondaryCueLabel.isHidden=true
 check(v.setSubtitlePosition(100),"bottom accepted")
 check(v.layoutCueLabels(position:100,apply:true),"layout applied")
 check(v.cueLabel.frame.minY==24 && v.cueLabel.frame.height==40,"measured bottom AppKit conversion")
 check(v.setSubtitlePosition(0),"top accepted")
 _=v.layoutCueLabels(position:0,apply:true)
 check(v.cueLabel.frame.maxY==336,"top safe inset")
 let old=v.subtitlePosition
 for p in [Double.nan,Double.infinity,-1,101] {check(!v.setSubtitlePosition(p) && v.subtitlePosition==old,"invalid refuses unchanged")}
 v.cueLabel.cell!.measured=120
 _=v.layoutCueLabels(position:50,apply:true)
 check(v.cueLabel.frame.height==120 && v.cueLabel.frame.midY==180,"multiline actual measured height")
 v.subtitleVideoRect={NSRect(x:80,y:45,width:480,height:270)}
 _=v.layoutCueLabels(position:100,apply:true)
 check(v.cueLabel.frame.minX==104 && v.cueLabel.frame.minY==69 && v.cueLabel.frame.width==432,"film safe rectangle")
 v.bounds=NSRect(x:0,y:0,width:320,height:180);v.subtitleVideoRect={NSRect(x:0,y:0,width:320,height:180)};v.cueLabel.cell!.measured=30
 _=v.layoutCueLabels(position:100,apply:true)
 check(v.cueLabel.frame.width==272 && v.cueLabel.frame.minY==24,"resize uses new measurement bounds")
 v.secondaryCueLabel.isHidden=false;v.secondaryCueLabel.cell!.measured=30
 check(v.layoutCueLabels(position:0,apply:true),"dual top primary")
 check(v.cueLabel.frame.minY>=v.secondaryCueLabel.frame.maxY+8,"secondary opposite edge no overlap")
 check(v.layoutCueLabels(position:100,apply:true),"dual bottom primary")
 check(v.secondaryCueLabel.frame.minY>=v.cueLabel.frame.maxY+8,"secondary established top")
 let retained=v.cueLabel.frame;v.cueLabel.cell!.measured=1000
 check(!v.layoutCueLabels(position:100,apply:true) && v.cueLabel.frame==retained,"oversize typed refusal retains frame")
 check(!v.setSubtitlePosition(50),"oversize command refuses")
 v.subtitleVideoRect={nil};check(!v.setSubtitlePosition(50),"no video geometry refuses")
 v.displayCues(primary:SubtitleCue(text:"new timed cue"),secondary:nil)
 check(v.cueLabel.stringValue=="new timed cue" && !v.cueLabel.isHidden && v.secondaryCueLabel.isHidden,"layout refusal cannot suppress new cue content")
 check(!v.layoutCueLabels(position:100,apply:true),"missing geometry still refuses layout")
 v.displayCues(primary:nil,secondary:nil)
 check(v.cueLabel.isHidden && v.secondaryCueLabel.isHidden && v.cueLabel.stringValue.isEmpty,"expired cue clears despite layout refusal")
 print("PASS \\(n) actual view method projection checks; real AppKit text measurement NOT_RUN")
 }
}
'''
p=r/'LayoutProjection.swift';p.write_text(prefix+methods+'}\n'+tests)
for opt in os.environ.get('OPTIONS','-Onone -O').split():
 c=subprocess.run([os.environ.get('SWIFTC','swiftc'),'-swift-version','5',opt,str(r/os.environ.get('SOURCE_DIR','post')/'Packages/gorav/Sources/GorAVSubtitles/SubtitleTypography.swift'),str(p),'-o',str(r/'layout-tests')],capture_output=True,text=True)
 if c.returncode:raise SystemExit(c.stderr)
 t=subprocess.run([str(r/'layout-tests')],capture_output=True,text=True);print(opt,t.stdout,t.stderr)
 if t.returncode:raise SystemExit(t.returncode)
