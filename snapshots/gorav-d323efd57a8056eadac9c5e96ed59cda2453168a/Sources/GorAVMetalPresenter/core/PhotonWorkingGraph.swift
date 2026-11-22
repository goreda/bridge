#if canImport(Metal)
import Foundation
import Metal
import GorAVPlaybackCore

struct PhotonWorkingFrame: @unchecked Sendable {
    let texture:MTLTexture
    let snapshot:PhotonProducerSnapshot?
    let videoRect:SIMD4<Float>
}
struct PhotonCompositeUniforms {
    var videoRect=SIMD4<Float>(0,0,1,1)
    var enabled=SIMD4<UInt32>(repeating:0)
}

final class PhotonGraphReservation: @unchecked Sendable {
    let release:@Sendable ()->Void
    init(_ release:@escaping @Sendable ()->Void){self.release=release}
    deinit{release()}
}

/// Flat geometry only. No projection, stereo conversion or extra output transform.
final class PhotonWorkingGraph: @unchecked Sendable {
    private let device:MTLDevice
    private let effects:PhotonMetalEffects
    private let geometry:MTLRenderPipelineState
    private let sampler:MTLSamplerState
    private let lock=NSLock()
    private var bytesInFlight=0
    init(device:MTLDevice)throws {
        self.device=device;effects=try PhotonMetalEffects(device:device)
        let code="""
        #include <metal_stdlib>
        using namespace metal;
        struct V {float4 p [[position]];float2 uv;};
        vertex V photonFlat(uint i [[vertex_id]],constant float4* q [[buffer(0)]]) {
            V o;o.p=float4(q[i].xy,0,1);o.uv=q[i].zw;return o;
        }
        fragment float4 photonCopy(V i [[stage_in]],texture2d<float> t [[texture(0)]],sampler s [[sampler(0)]]) {return t.sample(s,i.uv);}
        """
        let lib=try device.makeLibrary(source:code,options:nil)
        let pd=MTLRenderPipelineDescriptor();pd.vertexFunction=lib.makeFunction(name:"photonFlat")
        pd.fragmentFunction=lib.makeFunction(name:"photonCopy");pd.colorAttachments[0].pixelFormat = .rgba32Float
        geometry=try device.makeRenderPipelineState(descriptor:pd)
        let sd=MTLSamplerDescriptor();sd.minFilter = .nearest;sd.magFilter = .nearest
        sd.sAddressMode = .clampToEdge;sd.tAddressMode = .clampToEdge
        guard let s=device.makeSamplerState(descriptor:sd) else {throw PhotonMetalError.allocation};sampler=s
    }
    private final class Reservation: @unchecked Sendable {
        let release:@Sendable ()->Void
        init(_ release:@escaping @Sendable ()->Void){self.release=release}
        deinit{release()}
    }
    func encode(on cb:MTLCommandBuffer,source:MTLTexture,snapshot:PhotonProducerSnapshot,
                quad:[Float])throws->PhotonWorkingFrame {
        let w=snapshot.outputWidth,h=snapshot.outputHeight
        guard quad.count==16,quad.allSatisfy(\.isFinite) else {throw PhotonMetalError.textureSize}
        // Combined sharp + geometry + grain scratch, including reduction textures.
        let bytes=(source.width*source.height+2*w*h+2*w+2*h)*16
        lock.lock()
        guard bytes<=128*1024*1024,bytesInFlight<=256*1024*1024-bytes else {lock.unlock();throw PhotonMetalError.byteBudget}
        bytesInFlight+=bytes;lock.unlock()
        let reservation=Reservation{[self] in lock.lock();bytesInFlight-=bytes;lock.unlock()}
        cb.addCompletedHandler{_ in withExtendedLifetime(reservation){}}
        func block(_ family:PhotonMetalParameters.Family,_ values:[String:Double])throws->PhotonMetalParameters {
            var result=PhotonMetalParameters(family)
            let names=family == .sharp ? PhotonMetalParameters.sharpNames:PhotonMetalParameters.grainNames
            guard Set(values.keys)==Set(names) else {throw PhotonMetalError.invalidParameter("incomplete snapshot")}
            for (name,value) in values {try result.set(name,Float(value))}
            return result
        }
        let sharp=try effects.encodeSharp(commandBuffer:cb,source:source,parameters:block(.sharp,snapshot.sharp))
        let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba32Float,width:w,height:h,mipmapped:false)
        td.storageMode = .private;td.usage=[.shaderRead,.renderTarget]
        guard let flat=device.makeTexture(descriptor:td) else {throw PhotonMetalError.allocation}
        let rp=MTLRenderPassDescriptor();rp.colorAttachments[0].texture=flat
        rp.colorAttachments[0].loadAction = .clear;rp.colorAttachments[0].storeAction = .store
        rp.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,1)
        guard let e=cb.makeRenderCommandEncoder(descriptor:rp) else {throw PhotonMetalError.encoder}
        e.setRenderPipelineState(geometry);e.setFragmentTexture(sharp,index:0);e.setFragmentSamplerState(sampler,index:0)
        quad.withUnsafeBytes{e.setVertexBytes($0.baseAddress!,length:$0.count,index:0)}
        e.drawPrimitives(type:.triangleStrip,vertexStart:0,vertexCount:4);e.endEncoding()
        let output=try effects.encodeGrain(commandBuffer:cb,source:flat,sourceWidth:source.width,sourceHeight:source.height,parameters:block(.grain,snapshot.grain))
        let rect=SIMD4<Float>((quad[0]+1)*0.5,(1-quad[1])*0.5,(quad[8]-quad[0])*0.5,(quad[1]-quad[5])*0.5)
        return PhotonWorkingFrame(texture:output,snapshot:snapshot,videoRect:rect)
    }
}
#endif
