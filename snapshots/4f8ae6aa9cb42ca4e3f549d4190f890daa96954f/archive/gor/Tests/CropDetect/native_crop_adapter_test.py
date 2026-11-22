#!/usr/bin/env python3
"""Live native crop value/geometry and typed setter. GPU execution NOT_RUN.
FrameUniforms, ABI validation, host math, StageGeometry and renderer mutation are
extracted from their production sources; transport/token types are minimal doubles.
"""
from pathlib import Path
import os,shutil,subprocess,tempfile
root=Path(__file__).resolve().parents[2];core=root/'Packages/gorav/Sources/GorAVPlaybackCore'
def top_type(text,start):
 a=text.index(start);b=text.index('\n}',a)+2;return text[a:b]
render=(root/'Packages/gorav/Sources/GorAVMetalPresenter/core/MetalRenderer.swift').read_text()
a=render.index('    public func setSourceCrop(');setter=render[a:render.index('\n    }',a)+6]
uniforms=top_type((core/'RenderGraph.swift').read_text(),'@frozen public struct FrameUniforms')
abi=top_type((core/'FrameUniformABI.swift').read_text(),'public enum FrameUniformABI')
geometry=(core/'StageGeometry.swift').read_text();host=(core/'HostTransform.swift').read_text()
header='''import Foundation
public enum ToneMapCurve {case none,clip,mobius,hable,reinhard}
public enum GamutMode {case perceptual,other}
public struct ModeToken {let name:String}
'''
mutator='''
final class RendererMutation {
 let lock=NSLock();var sessionID="a";var sessionGeneration:UInt64=4
 var sourceCrop=SourceCrop.full;var blocked=false
 func admissionBlockedLocked()->Bool{blocked}
'''
cases='''
}
func near(_ a:Float,_ b:Float)->Bool{abs(a-b)<0.000001}
precondition(SourceCrop(x:0,y:0,width:1,height:1) == .full)
for v in [Double.nan,Double.infinity,-Double.infinity] {
 precondition(SourceCrop(x:v,y:0,width:1,height:1)==nil)
 precondition(SourceCrop(x:0,y:0,width:v,height:1)==nil)
}
precondition(SourceCrop(x:-0.01,y:0,width:1,height:1)==nil)
precondition(SourceCrop(x:0.1,y:0,width:1,height:1)==nil)
precondition(SourceCrop(x:0,y:0,width:0,height:1)==nil)
let crop=SourceCrop(x:0,y:0.125,width:1,height:0.75)!
var u=FrameUniforms();u.frameWidth=1920;u.frameHeight=1080;u.fitModeID=1;crop.apply(to:&u)
precondition(FrameUniformABI.valid(u))
let q=StageGeometry.quad(uniforms:u,drawableWidth:1920,drawableHeight:810)!
precondition(near(q[0],-1) && near(q[1],1) && near(q[2],0) && near(q[3],0.125) && near(q[7],0.875))
let r=RendererMutation()
precondition(r.setSourceCrop(crop,sessionID:"foreign",generation:4) == .refusedStaleSession && r.sourceCrop == .full)
precondition(r.setSourceCrop(crop,sessionID:"a",generation:3) == .refusedStaleSession && r.sourceCrop == .full)
r.blocked=true;precondition(r.setSourceCrop(crop,sessionID:"a",generation:4) == .refusedSealed && r.sourceCrop == .full)
r.blocked=false;precondition(r.setSourceCrop(crop,sessionID:"a",generation:4) == .applied && r.sourceCrop == crop)
// Snapshot remains immutable if a later crop changes; an old lease must not read live mutable geometry.
let snap=r.sourceCrop;_ = r.setSourceCrop(.full,sessionID:"a",generation:4);precondition(snap==crop && r.sourceCrop == .full)
print("PASS actual SourceCrop validation, uniform ABI, stage UV/aspect geometry and typed stale/sealed/applied mutation")
'''
variants={'green':(geometry,setter),
 'red-value-range':(geometry.replace('x+width <= 1','x+width <= 2'),setter),
 'red-missing-uv':(geometry.replace('u.cropX=Float(x);u.cropY=Float(y);u.cropW=Float(width);u.cropH=Float(height)',''),setter),
 'red-session-fence':(geometry,setter.replace('guard self.sessionID==sessionID,self.sessionGeneration==generation else{return .refusedStaleSession}','')),
 'red-sealed-fence':(geometry,setter.replace('guard !admissionBlockedLocked() else{return .refusedSealed}',''))}
swift=os.environ.get('SWIFTC') or shutil.which('swiftc') or '/tmp/swift-install/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as td:
 p=Path(td)/'main.swift'
 for name,(g,s) in variants.items():
  p.write_text('\n'.join([header,uniforms,abi,host,g,mutator,s,cases]));out=Path(td)/name
  v=subprocess.run([swift,'-swift-version','5',str(p),'-o',str(out)],capture_output=True,text=True)
  assert v.returncode==0,(name,v.stderr)
  v=subprocess.run([str(out)],capture_output=True,text=True,timeout=5)
  if name=='green':assert v.returncode==0,v.stderr;print(v.stdout.strip())
  else:assert v.returncode!=0,'survived: '+name;print('PASS runtime RED: '+name)
# Wiring checks supplement (not substitute for) the executable pure geometry test.
assert render.count('renderState: renderState, sourceCrop: sourceCrop))')==2
assert render.count('lease.sourceCrop.apply(to:&u)')==2
assert render.count('lease.sourceCrop != sourceCrop')==2
assert 'photon.sourceCrop.xy+((in.uv-photon.videoRect.xy)/photon.videoRect.zw)*photon.sourceCrop.zw' in render
assert 'all(in.uv >= photon.videoRect.xy)' in render
presenter=(root/'Packages/gorav/Sources/GorAVMetalPresenter/core/MetalPresenter.swift').read_text()
session=(root/'Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift').read_text()
host=(root/'Sources/gor/Engine/GorAVPlayerHost.swift').read_text()
assert 'renderer.setSourceCrop(crop,sessionID:sessionID,generation:sessionGeneration)' in presenter
assert 'if result == .applied {rerenderIfOpen()}' in presenter
assert 'return presenter.setSourceCrop(crop)' in session
assert 'self.sourceURL?.path==source,let session=self.session' in host
assert 'session.setSourceCrop(' in host and 'embeddedSourceCrop=nil' in host
print('PASS current-source native session->presenter->renderer wiring; both lease/encode/commit paths and Photon overlay source UV/clip. Metal pixels NOT_RUN')
