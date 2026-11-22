#if canImport(AppKit) && canImport(CoreAudio)
import XCTest
import Foundation
import CoreAudio
import GorAVMacShell
import GorAVPlaybackCore

/// Opt-in hardware acceptance only. Never runs a device switch on a CI host
/// without an explicit output UID and explicit test enable environment.
final class AudioOutputDeviceNativeTests:XCTestCase, @unchecked Sendable {
    func testExplicitDeviceHandoffReadbackAndRollbackToOriginal() async throws {
        guard ProcessInfo.processInfo.environment["GORAV_AUDIO_DEVICE_TEST"]=="1",
              let requested=ProcessInfo.processInfo.environment["GORAV_AUDIO_DEVICE_UID"] else {
            throw XCTSkip("NOT_RUN: explicit hardware output-device test and UID required")
        }
        guard let sink=AudioUnitSink() else {XCTFail("sink allocation refused");return}
        try sink.start()
        sink.producerNotExpected(generation:sink.currentGeneration)
        defer {_=sink.stop()}
        let before=try sink.outputDeviceInventory().get()
        let old=try XCTUnwrap(before.currentUID)
        XCTAssertTrue(before.devices.contains{$0.uid==requested && $0.isAlive})
        XCTAssertEqual(sink.selectOutputDevice(uid:requested),.accepted(currentUID:requested))
        XCTAssertEqual(try sink.outputDeviceInventory().get().currentUID,requested)
        XCTAssertEqual(sink.selectOutputDevice(uid:old),.accepted(currentUID:old))
        XCTAssertEqual(try sink.outputDeviceInventory().get().currentUID,old)
        // No PCM/pixel/subjective-audio quality acceptance is implied.
    }
}
#endif
