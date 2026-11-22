import XCTest
#if canImport(Metal) && canImport(QuartzCore)
import Metal
import QuartzCore
import GorAVPlaybackCore
@testable import GorAVMetalPresenter

final class PhotonPresenterPixelsNativeTests:XCTestCase {
    func testActualRendererOffscreenConsumesProducer() throws {
        let renderer=try MetalRenderer()
        XCTAssertTrue(renderer.beginSession(sessionID:"photon-native",generation:1))
        let identity=FrameIdentity(sessionID:"photon-native",sessionGeneration:1,sequence:1,
            surfaceRevision:renderer.currentSurfaceRevision,ptsSeconds:1)
        var bytes=[UInt8](repeating:0,count:64*48*4)
        for y in 0..<48 {for x in 0..<64 {
            let i=(y*64+x)*4,v=UInt8(80+(x*3+y*2)%100)
            bytes[i]=v;bytes[i+1]=v;bytes[i+2]=v;bytes[i+3]=255
        }}
        guard case .ok = renderer.upload(rgba:bytes,width:64,height:48,identity:identity) else {
            return XCTFail("actual source upload refused")
        }
        guard let original=renderer.readbackNative(identity:identity) else{return XCTFail("baseline readback")}
        // Each family routes independently through the real graph. Both off
        // must be an identity effect, not merely tiny nonzero parameters.
        for sharp in [false,true] {for grain in [false,true] {
            XCTAssertTrue(renderer.setPhotonProducerEnabled(true,sharp:sharp,grain:grain))
            guard let family=renderer.readbackNative(identity:identity) else {return XCTFail("family readback")}
            if !sharp && !grain {XCTAssertEqual(original.bytes,family.bytes)}
            else {XCTAssertNotEqual(original.bytes,family.bytes,"enabled family must affect actual pixels")}
        }}
        XCTAssertTrue(renderer.setPhotonProducerEnabled(true))
        XCTAssertNil(renderer.completedPhotonTelemetry(),"setter cannot fabricate presented telemetry")
        guard let processed=renderer.readbackNative(identity:identity) else{return XCTFail("processed readback")}
        XCTAssertNotEqual(original.bytes,processed.bytes,"real shared renderer graph must change output pixels")
        XCTAssertNil(renderer.completedPhotonTelemetry(),"offscreen is not onscreen completion")
        XCTAssertTrue(renderer.setPhotonProducerEnabled(false))
        guard let restored=renderer.readbackNative(identity:identity) else{return XCTFail("restored readback")}
        XCTAssertEqual(original.bytes,restored.bytes,"disabled output must retain original path")
    }
}
#endif
