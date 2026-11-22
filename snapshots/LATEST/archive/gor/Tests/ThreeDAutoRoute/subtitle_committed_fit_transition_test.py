#!/usr/bin/env python3
"""Real Lua transition receipts + actual compiled subtitle compositor. Not native presentation."""

# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile,json,math
root=Path(__file__).resolve().parents[2]
f=root/'Tests/ThreeDAutoRoute/cinema_pose_lua_test.py';ns={'__file__':str(f)};exec(compile(_sub_read(f).split('# Independent seeded',1)[0],str(f),'exec'),ns)
old=subprocess.check_output(['git','show','e7684e7f331ba895d1fdd07a9339396e87aabe04:archive/gor/Resources/vendor/mpv/scripts/vr180-look.lua'],text=True)
rows=[]
for label,w,h in [('window',960,640),('fullscreen',1920,1080)]:
 for pack in [3,1,2,4]:
  for crop in [(0,0,1,1),(.1,.2,.8,.6)]:
   for deg in [0,25,-45]:
    now=ns['Replay'](flat=True);before=ns['Replay'](flat=True,source=old)
    for replay in [now,before]:
     replay.g.props['osd-width']=w;replay.g.props['osd-height']=h;replay.g.props['video-params/aspect']=16/9
    # Off->On,3D->3D,3D->Off->On, each with accepted crop restored after route.
    for transition in ['2D->3D','3D->3D','3D->2D->3D']:
     for replay in [now,before]:
      if transition!='3D->3D':replay.msg('vr180-look-set-enabled','false');replay.msg('vr180-look-tools-active','true')
      replay.msg('vr180-look-set-projection','flat-2d3d',16/9);replay.msg('vr180-look-set-enabled','true')
      replay.msg('vr180-look-set-pack',pack,0,.5,1,0);replay.msg('vr180-look-bar-crop',*crop)
      replay.pose(roll=math.radians(deg),fov=140,x=.06,y=-.04)
     a=dict(now.g.props['user-data/vr180-look/film-frame']);b=dict(before.g.props['user-data/vr180-look/film-frame'])
     for k in ['fit','scale','angle','leftX','leftY','replicaX','replicaY','frameW','frameH','baseX','baseY','layout','instances']:
      assert abs(a[k]-b[k])<1e-10,('194p film/UI geometry changed',label,pack,transition,k,a[k],b[k])
     rows.append(dict(a,outputW=w,outputH=h,case=label+':'+str(pack)+':'+transition))
s=_sub_read(root/'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
if os.environ.get('SUBTITLE_SOURCE'):
 s=subprocess.check_output(['git','show',os.environ['SUBTITLE_SOURCE']+':archive/gor/Sources/gor/GorSubtitlesUI/SubtitleView.swift'],text=True)
assert 'private func applyCommittedSubtitleFrame(' in s,'subtitle has no committed film-fit consumer'
def method(sig):
 a=s.index(sig);i=s.index('{',a)+1;d=1
 while d:d+=(s[i]=='{')-(s[i]=='}');i+=1
 return s[a:i].replace('private func','func')
assert 'subtitleView.setCommittedFilmFrame(frame,origin:subtitleView.frame.origin,output:bounds.size)' in _sub_read(_pp_split().path(root,'PPController.swift'))
program=r'''import Foundation
struct Matrix {var m11:CGFloat=1,m12:CGFloat=0,m21:CGFloat=0,m22:CGFloat=1,m41:CGFloat=0,m42:CGFloat=0}
func CATransform3DMakeRotation(_ a:CGFloat,_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->Matrix {Matrix(m11:cos(a),m12:sin(a),m21:-sin(a),m22:cos(a))}
func CATransform3DMakeTranslation(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->Matrix {Matrix(m41:x,m42:y)}
enum CATransaction {static func begin(){};static func commit(){};static func setDisableActions(_ b:Bool){}}
struct Color {var cgColor=0};enum NSColor {static let black=Color()}
class Layer {var frame=CGRect.zero,sublayerTransform=Matrix(),instanceTransform=Matrix();var mask:Layer?;var masksToBounds=false,instanceCount=1;var backgroundColor:Int?}
class Probe {
var subtitleTiltReplica=(shift:CGFloat(0),left:CGFloat(0),offset:CGFloat(0))
var committedSubtitleFrame:[String:Double]?,committedSubtitleOrigin=CGPoint.zero,committedSubtitleOutput=CGSize.zero
let textLayer=Layer(),vrSubtitleContainer=Layer(),vrSubtitleReplicator=Layer(),vrSubtitleSafeMask=Layer()
'''+method('    private func applyCommittedSubtitleFrame(')+r'''
}
let data=try! Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
let rows=try! JSONSerialization.jsonObject(with:data) as! [[String:Any]]
var cases=0
for raw in rows {
var f:[String:Double]=[:];for (k,v) in raw {if let n=v as? NSNumber {f[k]=n.doubleValue}}
let p=Probe(),w=f["outputW"]!,h=f["outputH"]!,fw=f["frameW"]!*w,fh=f["frameH"]!*h
p.committedSubtitleFrame=f;p.committedSubtitleOutput=CGSize(width:w,height:h)
p.committedSubtitleOrigin=CGPoint(x:f["baseX"]!*w-fw/2,y:(1-f["baseY"]!)*h-fh/2)
let ink=CGRect(x:10,y:fh-48,width:min(220,fw-20),height:38);p.textLayer.frame=ink
precondition(p.applyCommittedSubtitleFrame())
let t=p.vrSubtitleContainer.sublayerTransform,rep=p.vrSubtitleReplicator.instanceTransform
precondition(abs(hypot(t.m11,t.m12)-f["scale"]!)<1e-9)
precondition(abs(rep.m41-f["replicaX"]!*w)<1e-9 && abs(rep.m42+f["replicaY"]!*h)<1e-9)
precondition(p.vrSubtitleReplicator.instanceCount==Int(f["instances"]!))
for x in [ink.minX,ink.maxX] {for y in [ink.minY,ink.maxY] {
let actual=CGPoint(x:p.committedSubtitleOrigin.x+t.m11*x+t.m21*y+t.m41,y:p.committedSubtitleOrigin.y+t.m12*x+t.m22*y+t.m42)
let dx=x-fw/2,dy=y-fh/2,c=cos(f["angle"]!),s=sin(f["angle"]!),scale=f["scale"]!
let expected=CGPoint(x:f["leftX"]!*w+scale*(c*dx-s*dy),y:(1-f["leftY"]!)*h+scale*(s*dx+c*dy))
precondition(hypot(actual.x-expected.x,actual.y-expected.y)<1e-8,"subtitle not in same film/UI fit")
}}
if f["layout"] == 1 {
precondition(p.vrSubtitleContainer.mask===p.vrSubtitleSafeMask)
precondition(abs(p.vrSubtitleSafeMask.frame.minY+p.committedSubtitleOrigin.y-(1-f["clipY"]!-f["clipH"]!)*h)<1e-9)
} else {precondition(p.vrSubtitleContainer.mask==nil)}
let row:[String:Any] = ["case":raw["case"]!,"w":w,"h":h,"fw":fw,"fh":fh,"ox":Double(p.committedSubtitleOrigin.x),"oy":Double(p.committedSubtitleOrigin.y),"ink":[Double(ink.minX),Double(ink.minY),Double(ink.width),Double(ink.height)],"m":[Double(t.m11),Double(t.m12),Double(t.m21),Double(t.m22),Double(t.m41),Double(t.m42)],"rep":[Double(rep.m41),Double(rep.m42)],"count":p.vrSubtitleReplicator.instanceCount]
print(String(data:try! JSONSerialization.data(withJSONObject:row),encoding:.utf8)!)
// Existing subtitle depth dial must stay live and keep the interocular axis.
if f["instances"]!>1 {
 let before=rep,baseline=hypot(f["replicaX"]!*w,f["replicaY"]!*h)
 p.subtitleTiltReplica=(0,1,-2);precondition(p.applyCommittedSubtitleFrame())
 let after=p.vrSubtitleReplicator.instanceTransform
 precondition(abs(hypot(after.m41-before.m41,after.m42-before.m42)-2)<1e-8)
 precondition(abs((after.m41-before.m41)*before.m42-(after.m42-before.m42)*before.m41)<1e-8)
 precondition(baseline>0)
}
cases+=1
}
print("PASS",cases,"actual compiled subtitle transforms consume exact film/UI fit; window/fullscreen separately, SBS/TB/anaglyph/VR180-preview-request, crop and3transition sequences;194p film/UI receipts unchanged")
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program);(p/'rows.json').write_text(json.dumps(rows))
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sub_compile_input(root/'Sources/gor/Subtitles/SubtitleTiltGeometry.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 result=subprocess.check_output([str(p/'test'),str(p/'rows.json')],text=True)
 print(result.splitlines()[-1])
 Path('/tmp/194r-compiled-subtitle-matrices.json').write_text(json.dumps([json.loads(x) for x in result.splitlines() if x.startswith('{')]))
Path('/tmp/194r-transition-frames.json').write_text(json.dumps(rows))
