#!/usr/bin/env python3
"""Compile and run actual prepared-caption Swift math on Linux. Not AppKit/GPU."""

# Subtitles source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _sub_iu
from pathlib import Path as _SubPath
_sub_root=next(p for p in _SubPath(__file__).resolve().parents if (p/'Tests/Structure/subtitles_source.py').is_file())
_sub_spec=_sub_iu.spec_from_file_location('subtitles_source_view',_sub_root/'Tests/Structure/subtitles_source.py')
_sub_view=_sub_iu.module_from_spec(_sub_spec);_sub_spec.loader.exec_module(_sub_view)
_sub_read=_sub_view.read_source
_sub_bytes=_sub_view.read_bytes
_sub_compile_input=_sub_view.compile_input
def _threed_split():
    import importlib.util as _iu, pathlib as _pl
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/threed_split.py').exists():
        assert _d != _d.parent, 'Tests/Structure/threed_split.py not found'
        _d = _d.parent
    _s = _iu.spec_from_file_location('threed_split', _d / 'Tests/Structure/threed_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile,shutil
def _sec_file(root,name):
    import tempfile,pathlib
    b=_sub_read(_threed_split().path(root))
    p=pathlib.Path(tempfile.mkdtemp())/name
    p.write_text(b[b.index('// BEGIN relocated '+name+' '):b.index('// END relocated '+name+'\n')])
    return p

r=Path(__file__).resolve().parents[2]
swift=os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
src=_sec_file(r,'ThreeDSubtitleDepth.swift')
main='''import Foundation
struct ShotComfort { var depthScale:Double=1; var convergenceM:Double=2; var zNear:Double=0.3 }
func check(_ ok:Bool,_ name:String) { if !ok { fatalError(name) }; print("PASS",name) }
let width=1000.0
check(ThreeDSubtitleDepth.captionTarget(nearest:0.003,width:width,previous:nil,dt:0)==4.5,"nearest scene plus exactly1.5physical pixels")
check(ThreeDSubtitleDepth.captionTarget(nearest:1,width:width,previous:nil,dt:0)==10,"near cap1pct")
check(ThreeDSubtitleDepth.captionTarget(nearest:0.003,width:width,previous:0,dt:0)==0,"repeated geometry cannot advance smoothing")
let step=ThreeDSubtitleDepth.captionTarget(nearest:0.009,width:width,previous:0,dt:1.0/24)
check(abs(step-0.5)<1e-9,"max slew0.5px per24fps frame")
let ema=ThreeDSubtitleDepth.captionTarget(nearest:0.001,width:width,previous:2,dt:1.0/24)
check(abs(ema-2.075)<1e-9,"EMA k0.15 at24fps")
check(ThreeDSubtitleDepth.subtitleFraction(base:0.004,width:1000,event:"caption",now:1)==0.004,"off output equals existing fraction")
print("Prepared sampling/native AppKit compiler path NOT_RUN on Linux")
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(main)
 # Stage1 is the same portable math unit on every host. Darwin otherwise
 # activates the prepared/container branch that stage2 tests explicitly below.
 math_source=_sub_read(src)
 assert '#if canImport(AVFoundation)' in math_source, 'prepared boundary changed'
 (p/'Math.swift').write_text(math_source.replace('#if canImport(AVFoundation)','#if false'))
 subprocess.run([swift,str(p/'Math.swift'),str(p/'main.swift'),'-o',str(p/'check')],check=True)
 env=dict(os.environ);env.pop('GOR3D_SUBDEPTH',None)
 subprocess.run([str(p/'check')],env=env,check=True)
# Include the real prepared branch on Linux with only its container boundary fake.
# This does NOT qualify platform imports or AppKit typechecking.
prepared=_sub_read(src).replace('import AVFoundation','').replace('import CoreVideo','').replace('#if canImport(AVFoundation)','#if true')
prep_main="""import Foundation
struct ShotComfort { var depthScale:Double=1; var convergenceM:Double=2; var zNear:Double=0.3 }
struct DZCFile {
 static var value=128
 let meta=(width:32,height:16)
 init?(url:URL) {}
 func index(atOrAfter pts:Double)->Int {0}
 func plane(_ index:Int)->[Int]? {Array(repeating:Self.value,count:512)}
}
func check(_ ok:Bool,_ name:String) { if !ok {fatalError(name)};print("PASS",name) }
let sd=ThreeDSubtitleDepth.shared
ThreeDSubtitleDepth.setExperimental(true)
let url=URL(fileURLWithPath:"/fixture.dzc")
check(ThreeDSubtitleDepth.sampleBand(url,at:0,rows:4).count==64,"actual prepared16x4 sampler")
sd.begin(depth:url,pts:0,thetaH:1.3) {.init(ipd:0.063,convergence:2,zNear:0.3)}
RunLoop.main.run(until:Date().addingTimeInterval(0.05))
let a=ThreeDSubtitleDepth.subtitleFraction(base:0.004,width:1000,event:"caption1",now:1)
check(a != 0.004 && a>=0 && a<=0.01,"actual begin to visible-caption consumer")
DZCFile.value=512;sd.refreshPrepared(pts:1)
RunLoop.main.run(until:Date().addingTimeInterval(0.05))
let b=ThreeDSubtitleDepth.subtitleFraction(base:0.004,width:1000,event:"caption1",now:1+1.0/24)
check(abs(b-a)<=0.000500001,"actual refreshed sample obeys slew")
let c=ThreeDSubtitleDepth.subtitleFraction(base:0.004,width:1000,event:"caption2",now:1+1.0/24)
check(c>=b,"new caption snaps without old-caption smoothing")
sd.end()
check(ThreeDSubtitleDepth.subtitleFraction(base:0.004,width:1000,event:"caption2",now:2)==0.004,"end clears prepared override")
print("AVFoundation/CoreVideo/AppKit platform types NOT_RUN; prepared code ran with DZC boundary fixture")
"""
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'Prepared.swift').write_text(prepared);(p/'main.swift').write_text(prep_main)
 subprocess.run([swift,str(_sec_file(r,'SubtitleDepth.swift')),str(p/'Prepared.swift'),str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],env=dict(os.environ,GOR3D_SUBDEPTH='1'),check=True)
s=_sub_read(src);pp=_sub_read(_pp_split().path(r,'PPController.swift'));co=(lambda _b: _b[_b.index('// BEGIN relocated '+'ThreeDRenderCoordinator.swift'+' '):_b.index('// END relocated '+'ThreeDRenderCoordinator.swift'+'\n')])(_sub_read(_threed_split().path(r)));sv=_sub_read(r/'Sources/gor/GorSubtitlesUI/SubtitleView.swift')
assert 'private var experimental = false' in s and 'static func setExperimental' in s
assert 'rows:4' in s and 'sampleBusy' in s and 'token==t' in s
assert 'min().map' in s and 'Self.seenZ($0,zNear:r.zNear)' in s
assert 'shared.refreshPrepared(pts:pts)' in co
assert 'event:subtitleView.depthEvent' in pp and ': legacyDepth' in pp and 'let uiDepth=legacyDepth' in pp
assert 'depthEventEpoch &+= 1' in sv
print('PASS actual prepared producer -> bounded utility sample -> fenced nearest disparity -> visible subtitle consumer, UI unchanged')
