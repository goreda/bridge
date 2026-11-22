// Photon candidate native coverage: constant-mm distance path on a real Mac.
// On macOS AVCaptureDevice videoFieldOfView is unavailable, so the contract
// behavior is the constant-mm base with distance-clamp machinery dormant.
// These pins use the REAL display scale (CGDisplayScreenSize) and the real
// model source (production VRLookDistanceModel), not a retyped mirror.
#if canImport(AppKit)
import AppKit
import CoreGraphics
import XCTest
@testable import gor

final class PhotonDistanceModelNativeTests: XCTestCase {

    private func evaluate(_ model: VRLookDistanceModel, width: Double = 1_000,
                          offset: Double? = 0, now: Double = 10) -> VRLookDistanceModel.Outcome {
        model.evaluate(osdWidth: width, vrFov: 90, manualFov: 0,
                       fovMinDeg: 45, fovMaxDeg: 120, ipdNudge: 0.2,
                       ipdOffsetMM: offset, parallaxEnabled: false,
                       parallaxDisparity: -0.4, parallaxStrength: 0.4, now: now)
    }

    // No distance input at all: model reports no-input and applies no base.
    func testNoDistanceInputAppliesNothing() {
        let out = evaluate(VRLookDistanceModel(), offset: nil)
        XCTAssertNil(out.appliedBase)
        XCTAssertEqual(out.reason, "no-input")
    }

    // osd-width <= 0: typed no-osd-size refusal, no applied base.
    func testNoOsdSizeRefusal() {
        let out = evaluate(VRLookDistanceModel(), width: 0)
        XCTAssertNil(out.appliedBase)
        XCTAssertEqual(out.reason, "no-osd-size")
    }

    // Real host display scale: the model consumes the supplied display-bound
    // mm/px (label CGDisplayScreenSize); the macbook constant is the fallback
    // only. Verifies the real screen actually yields a usable scale on Mac.
    @MainActor
    func testRealDisplayMillimetrePerPixelSource() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main, "native screen required")
        let number = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
        let displayID = CGDirectDisplayID(number.uint32Value)
        let size = CGDisplayScreenSize(displayID)
        let pxWidth = Double(CGDisplayPixelsWide(displayID))
        guard size.width > 0, pxWidth > 0 else {
            throw XCTSkip("NOT_RUN: display does not report a physical width")
        }
        let mmPerPx = size.width / pxWidth
        var model = VRLookDistanceModel()
        model.acceptDistance(dMM: nil, reason: "fov-unavailable", mmPerPx: mmPerPx, now: 10)
        let out = evaluate(model)
        XCTAssertEqual(out.reason, "fov-unavailable")
        XCTAssertNil(out.dMM)
        XCTAssertEqual(out.mmPerPxSource, "CGDisplayScreenSize")
        XCTAssertEqual(out.mmPerPx, mmPerPx, accuracy: 1e-12)
        XCTAssertEqual(VRLookDistanceModel.macbookMMPerPx, 25.4 / 227.0, accuracy: 1e-9)
    }

    // Hold contract on exact boundaries: a held distance is authoritative at
    // the 0.5s ok boundary; once the 2.0s hold lapses without new input the
    // model leaves the held-distance reason for the constant-mm fallback.
    func testHoldBoundaries() {
        var model = VRLookDistanceModel()
        model.acceptDistance(dMM: 400, reason: "ok", mmPerPx: 0.2, now: 10)
        let atBoundary = evaluate(model, now: 10.5)
        XCTAssertEqual(atBoundary.reason, "ok")
        let afterHold = evaluate(model, now: 10.5 + 2.0 + 0.001)
        XCTAssertEqual(afterHold.reason, "no-face-hold-expired")
        XCTAssertNil(afterHold.dMM)
    }
}
#endif
