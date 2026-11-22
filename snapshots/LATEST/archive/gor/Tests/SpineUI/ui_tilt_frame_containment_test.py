#!/usr/bin/env python3
"""Compile actual UI consumer and inverse against committed Lua film snapshots."""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import subprocess,tempfile,os,json,math
root=Path(__file__).resolve().parents[2]
pp=(_pp_split().path(root,'PPController.swift')).read_text();spine=(root/'Sources/gor/UI/SpineUI.swift').read_text()
def extract(src,sig):
 a=src.index(sig);brace=src.index('{',a);depth=0
 for b in range(brace,len(src)):
  depth+=(src[b]=='{')-(src[b]=='}')
  if depth==0:return src[a:b+1]
assert 'private func rotatedFitScale' not in pp,'normal2D/SBS UI-only fit survives'
assert 'let shared=subtitleView.trackedOverlayPlacement(in:self)' not in extract(pp,'private func applyTrackedUITilt()'),'ink safety still moves normal2D/SBS UI'
assert 'guard self?.vr180Controller?.usesLegacyPreviewChrome == true else{return}' in pp,'normal2D/SBS still applies pre-IPC pose callback'
assert 'user-data/vr180-look/film-frame' in pp
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)}
exec(compile(f.read_text().split('# Independent seeded',1)[0],str(f),'exec'),ns)
frames=[]
for size in ((320,180),(640,360),(960,540),(1280,720),(1920,1080),(600,800)):
 for mode in ('plain','sbs','tb','anaglyph'):
  plain=mode=='plain'
  for degrees in (0,25,-45,90):
   for fov in (130,135,140):
    r=ns['Replay'](flat=True);r.g.props['osd-width']=size[0];r.g.props['osd-height']=size[1]
    if plain:r.msg('vr180-look-set-enabled','false');r.msg('vr180-look-tools-active','true')
    else:r.msg('vr180-look-set-pack',{'sbs':3,'tb':1,'anaglyph':2}[mode],0,.5,1,0)
    r.msg('vr180-look-full-fit');r.pose(roll=math.radians(degrees),fov=fov,x=.1,y=-.08)
    frame=dict(r.g.props['user-data/vr180-look/film-frame']);frames.append({k:float(v) for k,v in frame.items() if isinstance(v,(int,float))})
program='import Foundation\n\ntypealias NSPoint = CGPoint\nstruct CGAffineTransform {\n    var a: CGFloat = 1, b: CGFloat = 0, c: CGFloat = 0, d: CGFloat = 1\n    var tx: CGFloat = 0, ty: CGFloat = 0\n}\nstruct Matrix {\n    var m11: CGFloat = 1, m12: CGFloat = 0\n    var m21: CGFloat = 0, m22: CGFloat = 1\n    var m41: CGFloat = 0, m42: CGFloat = 0\n}\nfunc CATransform3DMakeRotation(_ angle: CGFloat, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> Matrix {\n    let c = cos(angle), s = sin(angle)\n    return Matrix(m11: c, m12: s, m21: -s, m22: c)\n}\nfunc CATransform3DMakeTranslation(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> Matrix {\n    Matrix(m41: x, m42: y)\n}\nenum CATransaction {\n    static func begin() {}\n    static func setDisableActions(_ disabled: Bool) {}\n    static func commit() {}\n}\nfinal class CGMutablePath {\n    var rects: [CGRect] = []\n    func addRect(_ rect: CGRect) { rects.append(rect) }\n    var points:[CGPoint]=[]\n    func move(to p:CGPoint) {points=[p]}\n    func addLine(to p:CGPoint) {points.append(p)}\n    func closeSubpath() {}\n}\nclass Layer {\n    var anchorPoint = CGPoint(x: 0.5, y: 0.5)\n    var bounds = CGRect.zero\n    var frame = CGRect.zero\n    var position = CGPoint.zero\n    var affine = CGAffineTransform()\n    var sublayerTransform = Matrix()\n    var instanceTransform = Matrix()\n    var instanceCount = 1\n    var mask: Layer?\n    var masksToBounds = false\n    func setAffineTransform(_ transform: CGAffineTransform) { affine = transform }\n}\nfinal class CAShapeLayer: Layer {\n    var path: CGMutablePath?\n    var fillColor: Int = 0\n}\nstruct NSColor {\n    static let black = NSColor()\n    var cgColor: Int { 1 }\n}\ntypealias CALayer = Layer\n\nfinal class SubtitleProbe {\n    var frame=CGRect.zero\n    func setCommittedFilmFrame(_ f:[String:Double]?,origin:CGPoint,output:CGSize) {}\n    func trackedOverlayPlacement(in host: Any) -> (center: NSPoint, placement: (angle: Double, leftX: Double, leftY: Double, replicaX: Double, replicaY: Double))? {\n        nil\n    }\n}\nfinal class SourceView {\n    var wantsLayer = false\n    let layer: Layer? = Layer()\n    var bounds = CGRect.zero\n    var origin = CGPoint.zero\n    func convert(_ point: CGPoint, to host: Any) -> CGPoint {\n        CGPoint(x: point.x + origin.x, y: point.y + origin.y)\n    }\n    func convert(_ rect: CGRect, to host: Any) -> CGRect {\n        rect.offsetBy(dx: origin.x, dy: origin.y)\n    }\n}\nfinal class SpineRecorder {\n    func convert(_ point: CGPoint, from host: Any) -> CGPoint { point }\n    func convert(_ rect:CGRect,from host:Any)->CGRect {rect}\n    func setTrackedUIOutputClip(_ rect:CGRect?) {}\n    func setTrackedUITilt(_ angle: Double, center: CGPoint, translation: CGPoint, replica: CGPoint?) {}\n    func setTrackedUITilt(_ angle: Double, center: CGPoint, translation: CGPoint, replica: CGPoint?, fitScale: CGFloat, clipToBounds: Bool) {}\n}\nfinal class InputProbe {\n    var sources: [SourceView] = []\n    var fixedEyeBand:CGRect?\n    var eyeShift: CGFloat = 0\n    var eyeShiftY: CGFloat = 0\n    var tiltTranslation = CGPoint.zero\n    var roll = 0.0\n    var tiltCenter = CGPoint.zero\n    var tiltScale: CGFloat = 1\n    var stereo = false\n    var active = false\n    var inputEyeOverride: Bool?\n__ORIGINAL_POINT__\n}\nfinal class PPProbe {\n    func traceFilmUI(_ reason:String,receiptPath:String?=nil) {}\n    func missingFlatFilmBounds(in b:CGRect)->CGRect? {nil}\n    var trackedUIRoll = 0.0\n    var trackedUICenter = CGPoint.zero\n    var trackedUILeftOffset: CGFloat = 0\n    var trackedUITiltFitScale: CGFloat = 1\n    var controlChromeBounds = CGRect.zero\n    var bounds=CGRect(x:0,y:0,width:960,height:540)\n    var committedFilmFrame:[String:Double]?\n    var vr180Controller:LegacyProbe?=nil\n    func applyLegacyPreviewUITilt() {}\n    var filmBandMasks:[ObjectIdentifier:(CALayer,CALayer?,CAShapeLayer)]=[:]\n__BAND_METHODS__\n    var layer:Layer?=Layer()\n    let vrControlInput = InputProbe()\n    var vrControlMirrorLayers: [Layer] = []\n    var vrControlMirrorClip = CGRect.zero\n    var vrControlMirrorShift: CGFloat = 0\n    var vrControlMirrorOn = false\n    let subtitleView = SubtitleProbe()\n    let vrChromeReplicator = Layer()\n    let vrChromeMask = Layer()\n    let uiChromeMask = CAShapeLayer()\n    let vrControlMirrorRoot = Layer()\n    let vrChromeContainer = Layer()\n    let spineUI = SpineRecorder()\n\n\n__APPLY_TILT__\n}\nfinal class SpineProbe {\n    var trackedUITilt = 0.0\n    var trackedUITiltCenter = NSPoint.zero\n    var trackedUIOffset: CGFloat = 0\n    var trackedUIFitScale:CGFloat=1,trackedUIClip=true\n    var trackedUITranslation=NSPoint.zero,trackedUIReplica:NSPoint?\n    let vrChromeReplicator = Layer()\n    let vrChromeContainer = Layer()\n__SPINE_TILT__\n}\n\nvar failures: [String] = []\nfunc check(_ ok: Bool, _ message: String) {\n    if !ok { failures.append(message) }\n}\nfunc corners(_ rect: CGRect) -> [CGPoint] {\n    [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),\n     CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]\n}\nfunc apply(_ t: CGAffineTransform, to p: CGPoint) -> CGPoint {\n    CGPoint(x: t.a * p.x + t.c * p.y + t.tx,\n            y: t.b * p.x + t.d * p.y + t.ty)\n}\nfunc apply(_ t: Matrix, to p: CGPoint) -> CGPoint {\n    CGPoint(x: t.m11 * p.x + t.m21 * p.y + t.m41,\n            y: t.m12 * p.x + t.m22 * p.y + t.m42)\n}\nfunc add(_ a: CGPoint, _ b: CGPoint) -> CGPoint {\n    CGPoint(x: a.x + b.x, y: a.y + b.y)\n}\nfunc sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint {\n    CGPoint(x: a.x - b.x, y: a.y - b.y)\n}\nfunc inside(_ p: CGPoint, _ r: CGRect, tolerance: CGFloat = 0.0001) -> Bool {\n    p.x >= r.minX - tolerance && p.x <= r.maxX + tolerance &&\n    p.y >= r.minY - tolerance && p.y <= r.maxY + tolerance\n}\nfunc visualSourceCorners(_ source: SourceView) -> [CGPoint] {\n    let layer = source.layer!\n    let anchorLocal = CGPoint(x: source.bounds.width * layer.anchorPoint.x,\n                              y: source.bounds.height * layer.anchorPoint.y)\n    let anchorGlobal = source.convert(anchorLocal, to: "host")\n    return corners(source.bounds).map { add(anchorGlobal, apply(layer.affine, to: sub($0, anchorLocal))) }\n}\nfunc visualMirrorCorners(_ mirror: Layer, clip: CGRect) -> [CGPoint] {\n    let anchorLocal = CGPoint(x: mirror.bounds.width * mirror.anchorPoint.x,\n                              y: mirror.bounds.height * mirror.anchorPoint.y)\n    let anchorGlobal = CGPoint(x: clip.minX + mirror.position.x,\n                               y: clip.minY + mirror.position.y)\n    return corners(mirror.bounds).map { add(anchorGlobal, apply(mirror.affine, to: sub($0, anchorLocal))) }\n}\n\n'
program='class LegacyProbe {var usesLegacyPreviewChrome=false}\n'+program
program=program.replace('__APPLY_TILT__',extract(pp,'private func applyTrackedUITilt()').replace('private func','func'))
program=program.replace('__BAND_METHODS__',extract(pp,'private func restoreFilmBandMasks()').replace('private func','func')+'\n'+extract(pp,'private func clipFilmLayer(').replace('private func','func'))
program=program.replace('__ORIGINAL_POINT__',extract(pp,'private func originalPoint(_ point: NSPoint) -> NSPoint').replace('private func','func'))
program=program.replace('__SPINE_TILT__',extract(spine,'func setTrackedUITilt(_ angle:Double'))
program+='\nlet cases:[[String:Double]]=['+','.join('['+','.join('"'+k+'":'+repr(v) for k,v in f.items())+']' for f in frames)+']\n'
program+=r'''for frame in cases {
 let probe=PPProbe();probe.committedFilmFrame=frame
 let w=frame["width"]!,h=frame["height"]!;probe.bounds=CGRect(x:0,y:0,width:w,height:h)
 let stereo=frame["instances"]!>1
 let fw=frame["frameW"]!*w,fh=frame["frameH"]!*h
 let baseCX=frame["baseX"]!*w,baseCY=(1-frame["baseY"]!)*h
 let film=CGRect(x:baseCX-fw/2,y:baseCY-fh/2,width:fw,height:fh)
 probe.controlChromeBounds=film;probe.trackedUICenter=CGPoint(x:film.midX,y:film.midY)
 probe.vrControlMirrorOn=stereo;probe.vrControlMirrorShift=stereo ? 483:0
 probe.vrControlMirrorClip=film.offsetBy(dx:probe.vrControlMirrorShift,dy:0)
 let source=SourceView();source.origin=film.origin;source.bounds=CGRect(origin:.zero,size:film.size);source.layer!.bounds=source.bounds
 let mirror=Layer();mirror.bounds=source.bounds;mirror.position=CGPoint(x:fw/2,y:fh/2)
 probe.vrControlMirrorLayers=[mirror]
 let oldMask=Layer();source.layer!.mask=oldMask
 probe.vrControlInput.sources=[source];probe.applyTrackedUITilt()
 let scale=frame["scale"]!,angle=frame["angle"]!,c=cos(angle),s=sin(angle)
 check(abs(Double(probe.trackedUITiltFitScale)-scale)<1e-9,"UI did not use exact film scale")
 if frame["layout"] == 1 {
  check(source.layer!.mask?.mask === oldMask,"fixed-band clip discarded existing source mask")
  for (layer,origin,bandY) in [(source.layer!,source.origin,h*0.5),(mirror,probe.vrControlMirrorClip.origin,0.0)] {
   let path=(layer.mask as? CAShapeLayer)?.path
   check(path?.points.count==4,"TB fixed output band mask missing")
   for (index,q) in (path?.points ?? []).enumerated() {
    let a=CGPoint(x:layer.bounds.midX,y:layer.bounds.midY)
    let out=add(add(origin,a),apply(layer.affine,to:sub(q,a)))
    let expected=corners(CGRect(x:0,y:bandY,width:w,height:h*0.5))[index]
    check(hypot(out.x-expected.x,out.y-expected.y)<1e-6,"TB clip rotated with film instead of staying in fixed half-band")
   }
  }
 }
 let visual=visualSourceCorners(source)
 for (index,p) in visual.enumerated() {
  let q=corners(source.bounds)[index],dx=q.x-fw/2,dy=q.y-fh/2
  let expected=CGPoint(x:frame["leftX"]!*w+scale*(c*dx-s*dy),y:(1-frame["leftY"]!)*h+scale*(s*dx+c*dy))
  check(hypot(p.x-expected.x,p.y-expected.y)<1e-6,"UI polygon diverges from committed film transform")
  probe.vrControlInput.inputEyeOverride=false
  let original=probe.vrControlInput.originalPoint(p)
  check(hypot(original.x-(q.x+film.minX),original.y-(q.y+film.minY))<1e-6,"left inverse differs from visible film geometry")
  if stereo {
   probe.vrControlInput.inputEyeOverride=true
   let right=CGPoint(x:p.x+frame["replicaX"]!*w,y:p.y-frame["replicaY"]!*h)
   let inv=probe.vrControlInput.originalPoint(right)
   check(hypot(inv.x-original.x,inv.y-original.y)<1e-6,"right inverse differs from same film transform")
  }
 }
 probe.restoreFilmBandMasks()
 check(source.layer!.mask === oldMask,"TB exit did not restore original layer mask")
}
if !failures.isEmpty {for failure in failures {print("FAIL \(failure)")};exit(1)}
print("PASS actual UI consumer:\(cases.count)Lua film snapshots, exact same scale/pivot/polygon, left/right inverse; TB output-fixed masks compose and restore; no UI-only fit")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
