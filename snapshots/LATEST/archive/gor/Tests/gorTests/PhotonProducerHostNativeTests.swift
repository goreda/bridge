// PHOTON remote fixture contract: OpenURLRouter admits a seekable direct remote.
// A tail-moov MP4 fixture must serve byte Range/206 for the FFmpeg seek path.
// This test does not add a non-seekable HTTP200 download/spooling transport.
#if canImport(AppKit)
import AppKit
import Foundation
import XCTest
import GorAVPlaybackCore
@testable import gor
final class PhotonProducerHostNativeTests:XCTestCase {
    @MainActor func testOrdinaryHostStartsSharpGrainWithRuntimeDefaults() async throws {
        guard let path=ProcessInfo.processInfo.environment["GORAV_PHOTON_FIXTURE"],FileManager.default.fileExists(atPath:path) else {
            throw XCTSkip("NOT_RUN: real local media fixture required")
        }
        _=NSApplication.shared
        let host=GorAVPlayerHost(inWindowChrome:true)
        host.open(file:path)
        host.window?.setContentSize(NSSize(width:1001,height:701))
        do {
            // No qualification activation: ordinary host open must supply
            // the producer, upload its params and complete actual GPU work.
            var rows:[String]?
            for _ in 0..<500 {
                rows=host.gatePhotonTelemetryRows()
                if rows != nil {break}
                try await Task.sleep(nanoseconds:20_000_000)
            }
            XCTAssertTrue(rows?.first?.hasPrefix("photon\t") == true)
            XCTAssertTrue(rows?.first?.contains("GPU completed") == true)
            XCTAssertTrue(rows?.first?.contains("no scene feed") == true)
            let completed=try XCTUnwrap(host.gatePhotonSnapshot())
            var reference=PhotonPresenterProducer()
            let families=(NSApp.delegate as? AppDelegate)?.goravPhotonFamilyTargets ?? (sharp:true,grain:true)
            reference.setTargets(sharp:families.sharp,grain:families.grain)
            XCTAssertEqual(completed.sharpEnabled,families.sharp)
            XCTAssertEqual(completed.grainEnabled,families.grain)
            let expected=try reference.snapshot(epoch:completed.epoch,
                sourceWidth:completed.sourceWidth,sourceHeight:completed.sourceHeight,
                outputWidth:completed.outputWidth,outputHeight:completed.outputHeight,
                position:host.currentTime ?? 0,now:ProcessInfo.processInfo.systemUptime,
                pictureWidth:completed.pictureWidth,pictureHeight:completed.pictureHeight)
            XCTAssertEqual(completed.sharp.count,19)
            XCTAssertEqual(completed.grain.count,29)
            XCTAssertEqual(completed.sharp,expected.sharp,"actual completed parameter upload must use the same runtime defaults")
            // Animation bucket is tied to actual presentation PTS. Compare all
            // other parameters, not a wall-clock approximation of that bucket.
            XCTAssertEqual(completed.grain.filter{$0.key != "GR_ANIM_BUCKET"},expected.grain.filter{$0.key != "GR_ANIM_BUCKET"})
            XCTAssertNotEqual(completed.outputWidth,completed.outputHeight,"non-square drawable case")
            // Actual Float quad-derived picture dimensions are captured with
            // the encoded snapshot, never re-created using ideal Double fit.
            XCTAssertGreaterThan(completed.pictureWidth,0)
            XCTAssertGreaterThan(completed.pictureHeight,0)
            let oldToken=completed.token
            await host.gateSeekAction(seconds:2)
            var afterSeek:PhotonProducerSnapshot?
            for _ in 0..<500 {
                if let next=host.gatePhotonSnapshot(),next.token != oldToken {afterSeek=next;break}
                try await Task.sleep(nanoseconds:20_000_000)
            }
            XCTAssertNotNil(afterSeek,"committed seek must rebind and upload a new owner")
            XCTAssertEqual(afterSeek?.sharpEnabled,families.sharp)
            XCTAssertEqual(afterSeek?.grainEnabled,families.grain)
            await host.gatePauseAction()
            try await Task.sleep(nanoseconds:100_000_000)
            XCTAssertNotNil(host.gatePhotonSnapshot(),"paused retained picture preserves the completed producer")
            await host.gateCloseAction()
            XCTAssertNil(host.gatePhotonTelemetryRows())
        } catch {await host.gateCloseAction();throw error}
    }
    @MainActor func testOrdinaryMasterOffNeverPublishesPhoton() async throws {
        guard let path=ProcessInfo.processInfo.environment["GORAV_PHOTON_FIXTURE"],FileManager.default.fileExists(atPath:path) else {throw XCTSkip("NOT_RUN: local fixture required")}
        _=NSApplication.shared
        let previous=NSApp.delegate
        let owner=AppDelegate();owner.photonEnabled=false;NSApp.delegate=owner
        defer {NSApp.delegate=previous}
        let host=GorAVPlayerHost(inWindowChrome:true);host.open(file:path)
        do {
            for _ in 0..<500 {
                if host.currentTime != nil {break}
                try await Task.sleep(nanoseconds:20_000_000)
            }
            XCTAssertNotNil(host.currentTime,"must actually open, not pass on missing source")
            try await Task.sleep(nanoseconds:100_000_000)
            XCTAssertNil(host.gatePhotonSnapshot())
            await host.gateSeekAction(seconds:2)
            try await Task.sleep(nanoseconds:100_000_000)
            XCTAssertNil(host.gatePhotonSnapshot())
            await host.gateCloseAction()
        } catch {await host.gateCloseAction();throw error}
    }
    @MainActor func testOrdinaryRemoteOpenUploadsPhoton() async throws {
        guard let url=ProcessInfo.processInfo.environment["GORAV_PHOTON_REMOTE_FIXTURE"],let parsed=URL(string:url),["http","https"].contains(parsed.scheme ?? "") else {throw XCTSkip("NOT_RUN: direct HTTP fixture required")}
        _=NSApplication.shared
        let previous=NSApp.delegate
        let owner=AppDelegate();owner.photonEnabled=true;NSApp.delegate=owner
        defer {NSApp.delegate=previous}
        let host=GorAVPlayerHost(inWindowChrome:true);host.open(url:url)
        do {
            for _ in 0..<500 {
                if host.gatePhotonSnapshot() != nil {break}
                try await Task.sleep(nanoseconds:20_000_000)
            }
            XCTAssertNotNil(host.gatePhotonSnapshot(),"remote ordinary opened hook must upload and complete")
            await host.gateCloseAction();XCTAssertNil(host.gatePhotonSnapshot())
        } catch {await host.gateCloseAction();throw error}
    }
}
#endif
