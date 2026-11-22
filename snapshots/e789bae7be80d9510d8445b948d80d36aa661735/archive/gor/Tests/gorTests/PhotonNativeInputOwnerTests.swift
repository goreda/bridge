// Native candidate test of the existing same-module diagnostic surface.
// This calls the real owner's evaluateAppliedBase path, not VRDistanceModel.
// It is not end-to-end presentation/capture qualification.
#if canImport(AppKit)
import AppKit
import CoreGraphics
import GorAVPlaybackCore
import XCTest
@testable import gor

final class PhotonNativeInputOwnerTests: XCTestCase {
    @MainActor
    func testAcceptedConstantMMUsesPullDisplayNotOrientationScale() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let displayID = number.uint32Value
        let mm = CGDisplayScreenSize(displayID).width
        let pixels = CGDisplayPixelsWide(displayID)
        guard mm > 0, pixels > 0 else {
            throw XCTSkip("NOT_RUN: display physical scale unavailable")
        }
        let scale = mm / Double(pixels)
        let owner = StereoLookNativeInputOwner(clock: { 10 })
        let session = UUID()
        let origin = StereoLookCommandOrigin(session: session, source: "photon-native-test", generation: 1)
        XCTAssertNil(owner.install(session: session, source: origin.source, generation: 1,
            initial: StereoLookNativeInitial(poseYaw: 0, posePitch: 0, poseFov: 90,
                poseRoll: 0, calibration: 0)))
        XCTAssertNil(owner.accept(.setIpdMM(2), origin: origin))
        XCTAssertNil(owner.accept(.setOrientation(yaw: nil, pitch: nil, fov: nil, roll: nil,
            ipdNudge: nil, headX: nil, headY: nil, headZ: nil,
            distanceMM: nil, distanceReason: "fov-unavailable", mmPerPx: 999,
            fusionRoll: nil, nativeRawRoll: nil), origin: origin))
        let context = StereoLookPullContext(widthPx: 1000, heightPx: 700,
                                            displayID: displayID, mmPerPx: scale)
        let result = try XCTUnwrap(owner.diagnosticEvaluateBase(now: 10, context: context))
        XCTAssertEqual(result.reason, "fov-unavailable")
        XCTAssertNil(result.distanceMM)
        XCTAssertFalse(result.capped)
        XCTAssertEqual(result.mmPerPx, scale, accuracy: 1e-12)
        XCTAssertEqual(result.mmPerPxSource, "host-display-\(displayID)")
        XCTAssertEqual(result.orientationScaleSlot, 999)
        XCTAssertEqual(result.baseIpdRaw, 2 / (250 * scale), accuracy: 1e-12)
        XCTAssertEqual(result.appliedIpdBase, result.baseIpdRaw, accuracy: 1e-12)
        var unavailable = context
        unavailable.mmPerPx = nil
        let fallback = try XCTUnwrap(owner.diagnosticEvaluateBase(now: 10, context: unavailable))
        XCTAssertEqual(fallback.mmPerPxSource, "macbook-227ppi")
        XCTAssertEqual(fallback.mmPerPx, 25.4 / 227, accuracy: 1e-12)
        owner.uninstall()
        XCTAssertNil(owner.diagnosticEvaluateBase(now: 10, context: context))
    }
}
#endif
