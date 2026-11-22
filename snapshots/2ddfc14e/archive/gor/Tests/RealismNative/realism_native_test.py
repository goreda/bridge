#!/usr/bin/env python3
"""Native Metal compile + renderer on/off fixture; no owner media."""
import pathlib,subprocess,tempfile,sys
r=pathlib.Path(__file__).resolve().parents[2]
t=pathlib.Path(tempfile.mkdtemp()); s=r/'Sources/gor'
main=r'''import Foundation
import Metal
let mode=CommandLine.arguments[1], dest=CommandLine.arguments[2]
guard let renderer=Stereo3DRenderer.make() else { fatalError("Metal library compile failed") }
let d=renderer.queue.device, w=256, h=64
func tex(_ fmt:MTLPixelFormat,_ ww:Int,_ hh:Int)->MTLTexture {let x=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:fmt,width:ww,height:hh,mipmapped:false);x.storageMode = .shared;x.usage=[.shaderRead,.shaderWrite];return d.makeTexture(descriptor:x)!}
let frame=tex(.rgba8Unorm,w,h), depth=tex(.r32Float,w,h), out=tex(.rgba8Unorm,w*2,h)
var rgb=[UInt8](repeating:255,count:w*h*4), z=[Float](repeating:6,count:w*h)
for y in 0..<h {for x in 0..<w {let i=y*w+x;rgb[i*4]=UInt8((x*17+y*11)%256);rgb[i*4+1]=UInt8((x*3+y*23)%256);rgb[i*4+2]=UInt8((x*7+y*5)%256);z[i]=(x<128 ? 0.3:6)}}
rgb.withUnsafeBytes {frame.replace(region:MTLRegionMake2D(0,0,w,h),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:w*4)}
z.withUnsafeBytes {depth.replace(region:MTLRegionMake2D(0,0,w,h),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:w*4)}
OPTIONS
RENDER
renderer.lastCommandBuffer!.waitUntilCompleted()
guard renderer.lastCommandBuffer!.status == .completed else {fatalError("GPU command failed")}
var bytes=[UInt8](repeating:0,count:w*2*h*4)
bytes.withUnsafeMutableBytes {out.getBytes($0.baseAddress!,bytesPerRow:w*2*4,from:MTLRegionMake2D(0,0,w*2,h),mipmapLevel:0)}
try Data(bytes).write(to:URL(fileURLWithPath:dest))
'''
call='guard renderer.render(frame:frame,depth:depth,thetaH:1.3,ipd:0.063,convergence:3,zNear:0.1,outW:w,outH:h,sbsOut:out,output:.fullSBSOPTIONSARG) else {fatalError("render refused")}'
for label,kernel in [('new',s/'Stereo3DKernel.swift'),('baseline',r/'Tests/RealismNative/baseline.swift')]:
    text=main.replace('OPTIONS','let opts=ThreeDExperimentOptions(floatingWindow:mode == "fw",depthOfField:mode == "dof",holeFillGradient:mode == "hg")' if label=='new' else '')
    text=text.replace('RENDER',call.replace('OPTIONSARG',',options:opts' if label=='new' else ''))
    (t/'main.swift').write_text(text)
    args=['swiftc','-O',str(s/'OutputModes.swift'),str(s/'SurroundGeometry.swift'),str(kernel)]
    if label=='new':
        args.append(str(s/'ThreeDExperimentOptions.swift'))
        for owner,dep in [(s/'DepthGuards.swift','DepthTemporalEMA'),(s/'CoreMLDepthRunner.swift','DepthModelID'),(s/'ModelDepthEMA.swift',None)]:
            if dep is None:
                if owner.exists():args.append(str(owner))
            else:  # 195y G2: relocated span inside the owner file
                txt=owner.read_text();span=txt.split('// BEGIN relocated '+dep+'.swift (195y G2, behavior unchanged)')[1].split('// END relocated '+dep+'.swift')[0]
                (t/(dep+'.swift')).write_text('import Foundation\n'+span);args.append(str(t/(dep+'.swift')))
    subprocess.run(args+[str(t/'main.swift'),'-o',str(t/label)],check=True)
    for mode in (['off','fw','dof','hg'] if label=='new' else ['off']):subprocess.run([str(t/label),mode,str(t/(label+'-'+mode+'.raw'))],check=True)
base=(t/'baseline-off.raw').read_bytes(); off=(t/'new-off.raw').read_bytes()
assert base==off,'flag-off pixels changed'
print('REALISM-NATIVE off pixels baseline-identical',len(off))
for mode in ['fw','dof','hg']:
    b=(t/('new-'+mode+'.raw')).read_bytes(); changed=sum(x!=y for x,y in zip(off,b));print('REALISM-NATIVE',mode,'changed bytes',changed);assert changed>0,mode+' no effect'
print('REALISM-NATIVE PASS')
