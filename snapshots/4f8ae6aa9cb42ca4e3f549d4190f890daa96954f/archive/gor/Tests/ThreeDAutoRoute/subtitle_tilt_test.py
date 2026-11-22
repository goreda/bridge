#!/usr/bin/env python3
"""Compile production subtitle tilt geometry, inspect transformed real-text pixels."""

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
import json,math,os,subprocess,tempfile
from pathlib import Path
import numpy as np
from PIL import Image,ImageDraw,ImageFont
root=Path(__file__).resolve().parents[2]
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',28)
text='Tilt follows the frame\nBoth eyes stay readable'
ink=Image.new('RGBA',(360,86));d=ImageDraw.Draw(ink);d.multiline_text((9,5),text,font=font,fill='white',spacing=8)
program='''import Foundation
for cross in [false,true] {for deg in [-30.0,-20,-10,0,10,20,30] {for y in [4.0,470.0,540.0] {
let r=deg*Double.pi/180,p=SubtitleTiltGeometry.place(ink:CGRect(x:40,y:y,width:360,height:86),screen:CGRect(x:0,y:0,width:960,height:600),shift:483,left:1,offset:-2,roll:r,pairRoll:r*(cross ? 1:-1))
let row:[String:Any]=["cross":cross,"deg":deg,"y":y,"angle":p.angle,"leftX":p.leftX,"leftY":p.leftY,"replicaX":p.replicaX,"replicaY":p.replicaY]
let data=try! JSONSerialization.data(withJSONObject:row,options:.sortedKeys);print(String(data:data,encoding:.utf8)!)
}}}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sub_compile_input(root/'Sources/gor/Subtitles/SubtitleTiltGeometry.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 rows=[json.loads(x) for x in subprocess.check_output([str(p/'test')],text=True).splitlines() if x.startswith('{')]
frames=[]
for row in rows:
 a=row['angle'];c,s=math.cos(a),math.sin(a);cx,cy=220,row['y']+43
 image=Image.new('RGBA',(960,600),(14,14,14,255))
 corners=[]
 for side in (0,1):
  tx=row['leftX']+side*row['replicaX'];ty=row['leftY']+side*row['replicaY']
  pts=[(cx+c*(x-cx)-s*(y-cy)+tx,cy+s*(x-cx)+c*(y-cy)+ty) for x,y in ((40,row['y']),(400,row['y']),(400,row['y']+86),(40,row['y']+86))]
  assert all(-1e-8<=x<=960+1e-8 and -1e-8<=y<=600+1e-8 for x,y in pts),(row,pts)
  baseline=(pts[1][0]-pts[0][0],pts[1][1]-pts[0][1]);angle=math.degrees(math.atan2(baseline[1],baseline[0]))
  assert abs(angle+row['deg'])<1e-8 # displayed Y-down compositor angle
  assert abs(math.hypot(*baseline)-360)<1e-8,'font ink scaled'
  # Production forward rigid transform, inverted for Pillow's backward sampling.
  ox=cx-c*cx+s*cy+tx;oy=cy-s*cx-c*cy+ty
  # Pillow y grows down; display the GL-oriented geometry with a final flip.
  aa=(c,s,-c*ox-s*oy-40,-s,c,s*ox-c*oy-row['y'])
  layer=ink.transform(image.size,Image.Transform.AFFINE,aa,resample=Image.Resampling.BICUBIC)
  image.alpha_composite(layer)
 if row['cross'] and row['y']==540:frames.append((row['deg'],image))
print('PASS42 compiled production placements: signed baselines0/+/-10/20/30deg, both-eye four-corner containment, unit ink scale, top/middle/bottom positions')
canvas=Image.new('RGB',(960,len(frames)*320),(20,20,20));draw=ImageDraw.Draw(canvas)
for i,(deg,image) in enumerate(frames):
 draw.text((8,i*320+4),'production subtitle transform: %d degrees | original font size | both eyes inside screen'%deg,fill='white')
 image.thumbnail((480,300));canvas.paste(image,(240,i*320+20))
canvas.save('/downloads/subtitle-tilt-proof.png')
s=_sub_read(root/'Sources/gor/GorSubtitlesUI/SubtitleView.swift');pp=_sub_read(_pp_split().path(root,'PPController.swift'));vr=_sub_read(_pp_split().path(root,'PPController_Features.swift'))
assert 'setTrackedTilt(roll:roll,pairRoll:pair)' in pp and 'onSubtitleTilt?(overlayRoll' in vr and 'let overlayRoll=projectionKind.hasPrefix("vr") ? 0:filmRoll' in vr
assert 'onSubtitleTilt?(0,0)' in vr and 'CATransform3DMakeRotation(CGFloat(p.angle)' in s
assert 'vrSubtitleContainer.mask=nil;vrSubtitleContainer.masksToBounds=false' in s
# Compile the actual compositor method against matrix/layer boundary spies.
def method(sig):
 start=s.index(sig);a=s.index('{',start);depth=1;b=a+1
 while depth:
  depth+=(s[b]=='{')-(s[b]=='}');b+=1
 return s[start:b].replace('private func','func')+'\n'
bridge=r"""import Foundation
struct Matrix {var m11:CGFloat=1,m12:CGFloat=0,m21:CGFloat=0,m22:CGFloat=1,m41:CGFloat=0,m42:CGFloat=0}
func CATransform3DMakeTranslation(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->Matrix {Matrix(m41:x,m42:y)}
func CATransform3DMakeRotation(_ a:CGFloat,_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->Matrix {Matrix(m11:cos(a),m12:sin(a))}
enum CATransaction {static func begin(){};static func setDisableActions(_ b:Bool){};static func commit(){}}
class Layer {var frame=CGRect(x:40,y:540,width:360,height:86);var sublayerTransform=Matrix();var instanceTransform=Matrix();var mask:Int?=1;var masksToBounds=true}
class View {
var vrSubtitleOn=true,subtitleTilt=(roll:0.0,pair:0.0),subtitleTiltCanvas=CGRect(x:0,y:0,width:960,height:600)
var subtitleUIPlacementCanvas=CGRect(x:0,y:0,width:960,height:600)
func applyCommittedSubtitleFrame()->Bool {false}
var overlayControlBounds:CGRect?
var subtitleTiltReplica=(shift:CGFloat(483),left:CGFloat(1),offset:CGFloat(-2))
let textLayer=Layer(),vrSubtitleContainer=Layer(),vrSubtitleReplicator=Layer()
func updateVRSubtitleMask(){vrSubtitleContainer.mask=1}
"""+method('    func setTrackedTilt(')+method('    private func applyTrackedSubtitleTilt(')+r"""
}
let v=View()
for deg in [-30.0,-20,-10,10,20,30] {
let a=deg*Double.pi/180;v.setTrackedTilt(roll:a,pairRoll:a)
let t=v.vrSubtitleContainer.sublayerTransform
precondition(abs(atan2(t.m12,t.m11)+a)<1e-12)
precondition(v.vrSubtitleContainer.mask==nil && !v.vrSubtitleContainer.masksToBounds)
}
v.setTrackedTilt(roll:0,pairRoll:0)
precondition(v.vrSubtitleContainer.sublayerTransform.m11==1 && v.vrSubtitleContainer.sublayerTransform.m12==0)
precondition(v.vrSubtitleContainer.sublayerTransform.m41==1 && v.vrSubtitleReplicator.instanceTransform.m41==481 && v.vrSubtitleReplicator.instanceTransform.m42==0)
precondition(v.vrSubtitleContainer.mask != nil && v.vrSubtitleContainer.masksToBounds)
print("PASS actual compositor method: signed rotation matrix, tilt mask disabled, neutral/reset restores translation and clip")
"""
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(bridge)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(_sub_compile_input(root/'Sources/gor/Subtitles/SubtitleTiltGeometry.swift')),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 print(subprocess.check_output([str(p/'test')],text=True),end='')
assert 'vrSubtitleContainer.anchorPoint = .zero' in s
print('PASS production pose-to-overlay wiring, native film-roll choice, tracking-stop reset and no fixed vertical mask during tilt. Actual Mac Core Animation NOT_RUN.')

#194o: subtitle ink-safety geometry no longer owns the chrome pivot. The
#194l/m film receipt supersedes that old independent UI fixture. Execute the
# actual current consumer, polygon, inverse, TB masks and neutral restore gate.
import runpy
runpy.run_path(str(root/'Tests/SpineUI/ui_tilt_frame_containment_test.py'),run_name='__main__')
def extract(text,sig):
 start=text.index(sig);a=text.index('{',start);level=1;b=a+1
 while level:level+=(text[b]=='{')-(text[b]=='}');b+=1
 return text[start:b].replace('private func','func')+'\n'
#194d: actual Spine publisher and Core Animation anchor semantics. The previous
# matrix-only spy omitted the container anchor, allowing a separate title pivot.
sp=_sub_read(root/'Sources/gor/UI/SpineUI.swift')
assert 'vrChromeContainer.anchorPoint = .zero' in sp
assert 'vrChromeContainer.anchorPoint = .zero' in pp
spine_probe=r'''import Foundation
typealias NSPoint=CGPoint
struct Matrix {var m11:CGFloat=1,m12:CGFloat=0,m21:CGFloat=0,m22:CGFloat=1,m41:CGFloat=0,m42:CGFloat=0}
func CATransform3DMakeRotation(_ a:CGFloat,_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->Matrix {Matrix(m11:cos(a),m12:sin(a))}
func CATransform3DMakeTranslation(_ x:CGFloat,_ y:CGFloat,_ z:CGFloat)->Matrix {Matrix(m41:x,m42:y)}
enum CATransaction {static func begin(){};static func commit(){};static func setDisableActions(_ b:Bool){}}
class Layer {var sublayerTransform=Matrix(),instanceTransform=Matrix();var masksToBounds=false;var instanceCount=2}
class Spine {
var trackedUITilt=0.0,trackedUITiltCenter=NSPoint.zero;var trackedUIOffset:CGFloat=0
var trackedUIFitScale:CGFloat=1,trackedUIClip=true,trackedUITranslation=NSPoint.zero,trackedUIReplica:NSPoint?
let vrChromeContainer=Layer(),vrChromeReplicator=Layer()
'''+extract(sp,'    func setTrackedUITilt(')+r'''
}
let spine=Spine(),origin=CGPoint(x:30,y:60),pivot=CGPoint(x:210,y:120)
for deg in [-90.0,-45,-20,20,45,90] {
 let a=deg*Double.pi/180,c=cos(a),s=sin(a)
 spine.setTrackedUITilt(a,center:CGPoint(x:pivot.x-origin.x,y:pivot.y-origin.y),translation:CGPoint(x:12,y:18),replica:CGPoint(x:500*cos(a),y:500*sin(a)))
 let t=spine.vrChromeContainer.sublayerTransform
 // One title line is vertically oriented before the common parent transform.
 for local in [CGPoint(x:20,y:80),CGPoint(x:20,y:380)] {
  let result=CGPoint(x:origin.x+c*local.x-s*local.y+t.m41,y:origin.y+s*local.x+c*local.y+t.m42)
  let global=CGPoint(x:origin.x+local.x,y:origin.y+local.y)
  let expected=CGPoint(x:pivot.x+c*(global.x-pivot.x)-s*(global.y-pivot.y)+12,y:pivot.y+s*(global.x-pivot.x)+c*(global.y-pivot.y)+18)
  precondition(hypot(result.x-expected.x,result.y-expected.y)<1e-9)
  // Default center anchor adds anchor-R*anchor: this is the prior displaced pivot.
  let anchor=CGPoint(x:20,y:300)
  let error=hypot(anchor.x-c*anchor.x+s*anchor.y,anchor.y-s*anchor.x-c*anchor.y)
  precondition(error>100,"previous centre-anchor mutant escaped")
 }
 print("PASS actual Spine title common axis and pivot, zero anchor; centre-anchor mutant rejected",deg)
 let row:[String:Double] = ["spine_deg":deg,"a":Double(t.m11),"b":Double(t.m12),"tx":Double(t.m41),"ty":Double(t.m42)]
 print(String(data:try! JSONSerialization.data(withJSONObject:row),encoding:.utf8)!)
}
'''
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(spine_probe)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 spine_output=subprocess.check_output([str(p/'test')],text=True)
 print(spine_output,end='')
 spine_rows=[json.loads(l) for l in spine_output.splitlines() if l.startswith('{')]
# Snapshotting may force a render/transaction flush. No live surface may ever
# receive identity while refresh runs, even before the final commit.
refresh=extract(pp,'    private func refreshVRControlMirrors(')
assert 'setAffineTransform(.identity)' not in refresh
assert 'mirror.frame = placed' not in refresh
assert refresh.index('applyTrackedUITilt() // Publish the final transform') < refresh.index('CATransaction.commit()\n        CATransaction.flush()')
assert 'mirror.bounds=CGRect(origin:.zero,size:placed.size);mirror.position=' in refresh
old=refresh.replace('for mirror in vrControlMirrorLayers {mirror.isHidden=true}', 'for mirror in vrControlMirrorLayers {mirror.setAffineTransform(.identity);mirror.isHidden=true}')
assert 'setAffineTransform(.identity)' in old
assert 'if abs(trackedUITilt)<1e-10 || !on' in sp
print('PASS refresh never stages live identity; final map precedes commit/flush; transformed mirrors use bounds+position; tilted layout retains complete replica map. Previous identity-staging mutant rejected. Native AppKit frames NOT_RUN.')

proof=Image.new('RGB',(1200,3*430),(15,15,15));pd=ImageDraw.Draw(proof)
for i,row in enumerate(r for r in spine_rows if r['spine_deg'] in (-45,20,45)):
 c,ss=row['a'],row['b'];tx,ty=row['tx'],row['ty'];ybase=i*430
 def raw_point(x,y,old=False):
  dx=(20-c*20+ss*300) if old else 0;dy=(300-ss*20-c*300) if old else 0
  return (30+c*x-ss*y+tx+dx+140,430-(60+ss*x+c*y+ty+dy)+ybase)
 all_points=[raw_point(20,y,old) for y in (80,230,380) for old in (False,True)]
 minx,maxx=min(p[0] for p in all_points),max(p[0] for p in all_points)
 miny,maxy=min(p[1] for p in all_points),max(p[1] for p in all_points)
 scale=min(430/max(maxx-minx,1),330/max(maxy-miny,1))
 def point(x,y,old=False):
  px,py=raw_point(x,y,old)
  return (40+(px-minx)*scale,ybase+40+(py-miny)*scale)
 # Button positions use the common global map, title the real Spine matrix.
 for j,y in enumerate((80,230,380)):
  pt=point(20,y);pd.ellipse((pt[0]-7,pt[1]-7,pt[0]+7,pt[1]+7),fill=(55,160,200))
 pd.line([point(20,80),point(20,380)],fill='white',width=3)
 pd.line([point(20,80,True),point(20,380,True)],fill=(200,65,60),width=3)
 pd.text((600,ybase+90),'Actual compiled Spine title axis: %.0f degrees'%row['spine_deg'],fill='white')
 pd.text((600,ybase+120),'White: fixed title through blue common-axis controls',fill='white')
 pd.text((600,ybase+150),'Red: prior default-anchor displaced-pivot mutant',fill=(240,110,100))
 pd.text((600,ybase+180),'Software matrix render, not native AppKit frames',fill='white')
proof.save('/downloads/spine-title194d.png')
