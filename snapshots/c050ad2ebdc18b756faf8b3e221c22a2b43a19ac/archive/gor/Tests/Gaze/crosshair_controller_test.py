#!/usr/bin/env python3
"""Compile actual overlay controller with boundary-only AppKit/camera spies."""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import tempfile,subprocess,os
root=Path(__file__).resolve().parents[2]
stubs=r'''
import Foundation
var clock=1.0
func CACurrentMediaTime()->Double {clock}
class CALayer {weak var superlayer:CALayer?;var sublayers:[CALayer]=[];func addSublayer(_ l:CALayer){l.superlayer=self;sublayers.append(l)};func removeFromSuperlayer(){superlayer=nil}}
class CATextLayer:CALayer {var font:String?,fontSize:CGFloat=0,foregroundColor:String?,alignmentMode:String="",contentsScale:CGFloat=0,string:String?,frame=CGRect.zero,isHidden=false}
extension String {static let center="center"}
class NSWindow {var backingScaleFactor:CGFloat=2;var origin=CGPoint.zero;func convertToScreen(_ r:CGRect)->CGRect {r.offsetBy(dx:origin.x,dy:origin.y)}}
class NSView {var layer:CALayer?=CALayer(),bounds=CGRect(x:0,y:0,width:960,height:540),window:NSWindow?=NSWindow();func convert(_ r:CGRect,to:NSView?)->CGRect {r}}
enum PhotonFont {static let chromeSize:CGFloat=14,chromeCharW:CGFloat=12,chromeLineH:CGFloat=18;static func ctFace()->String {"font"}}
class NSColor {static let white=NSColor();var cgColor:String {"white"}}
enum CATransaction {static func begin(){};static func setDisableActions(_ v:Bool){};static func commit(){}}
class HeadTracker {static let shared=HeadTracker();var onGazeUpdate:((BinocularGazeSample?)->Void)?,onPoseUpdate:(()->Void)?;var isRunning=true;var consumers=7;func start(){consumers+=1};func stop(){consumers-=1}}
'''
main=r'''import Foundation
let view=NSView(),marker=CATextLayer(),controller=GazeCrosshairController()
HeadTracker.shared.onPoseUpdate={}
controller.bind(view:view,marker:marker)
precondition(!marker.isHidden && abs(marker.frame.midX-480)<1e-9)
controller.toggle();precondition(HeadTracker.shared.consumers==8)
for (i,target) in BinocularGazeCalibration.targets.enumerated() {
 precondition(abs(marker.frame.midX-Double(target.x)*960)<1e-6)
 print("target \(i+1) \(marker.frame.midX) \(marker.frame.midY)")
 for _ in 0..<48 {
  clock += 1.0/30
  HeadTracker.shared.onGazeUpdate?(BinocularGazeSample(t:clock,x:(Double(target.x)-0.5)*0.3,y:(Double(target.y)-0.5)*0.2,yaw:0,pitch:0))
  if abs(marker.frame.midX-Double(target.x)*960)>1e-6 || abs(marker.frame.midY-Double(target.y)*540)>1e-6 || marker.isHidden {break}
 }
}
clock += 0.1
HeadTracker.shared.onGazeUpdate?(BinocularGazeSample(t:clock,x:0.06,y:-0.04,yaw:0,pitch:0))
precondition(!marker.isHidden && abs(marker.frame.midX-672)<1e-5 && abs(marker.frame.midY-162)<1e-5)
print("gaze \(marker.frame.midX) \(marker.frame.midY)")
HeadTracker.shared.onGazeUpdate?(nil);precondition(marker.isHidden)
// Window move invalidates learned screen coordinates and returns to target1.
view.window!.origin.x=20;controller.bind(view:view,marker:marker)
precondition(!marker.isHidden && marker.frame.midX==480)
// SmallSBS rails: actual status layer cell width must fit, even at80px.
for width:CGFloat in [80,160,320] {
 view.bounds.size=CGSize(width:width,height:180)
 controller.bind(view:view,marker:marker)
 let label=view.layer!.sublayers.compactMap{$0 as? CATextLayer}.last!
 let text=label.string ?? ""
 let measuredWidth=CGFloat(text.count)*PhotonFont.chromeCharW*label.fontSize/PhotonFont.chromeSize
 precondition(measuredWidth<=width-8 && label.frame.height<=PhotonFont.chromeLineH)
 print("status rail \(width) text=\(text) measuredCellWidth=\(measuredWidth)")
}
controller.stop();controller.stop()
precondition(HeadTracker.shared.consumers==7 && HeadTracker.shared.onGazeUpdate==nil && HeadTracker.shared.onPoseUpdate != nil)
precondition(!marker.isHidden && marker.frame.midX==view.bounds.midX)
print("PASS actual controller: centered/off,5 targets,tracking frame,loss hides,window move restarts,stop idempotent,camera count and existing head callback retained. AppKit boundaries stubbed; physical camera NOT_RUN")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td)
 actual=_s3read(root/'Sources/gor/Stereo/GazeCrosshairController.swift').replace('import AppKit','import Foundation')
 (p/'controller.swift').write_text(actual)
 (p/'stubs.swift').write_text(stubs)
 (p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(root/'Sources/gor/Camera/BinocularGaze.swift'),str(p/'stubs.swift'),str(p/'controller.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 result=subprocess.check_output([str(p/'test')],text=True);print(result)
 Path('/tmp/gaze-controller-geometry.txt').write_text(result)
