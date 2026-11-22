// DecodeHeartbeatTests - Linux venue: swift test --filter DecodeHeartbeatTests
import XCTest
@testable import GorAVPlaybackCore

final class DecodeHeartbeatTests: XCTestCase {
    private func tempPath(_ name: String) -> String {
        NSTemporaryDirectory() + "hb-\(name)-\(UUID().uuidString).txt"
    }
    private func readValue(_ path: String) -> UInt64? {
        guard let d = FileManager.default.contents(atPath: path),
              let s = String(data: d, encoding: .utf8) else { return nil }
        return UInt64(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func testDisabledWhenPathNilOrEmpty() {
        XCTAssertNil(DecodeHeartbeat(path: nil))
        XCTAssertNil(DecodeHeartbeat(path: ""))
    }

    func testCounterAdvancesAndFilePublishesEveryValue() {
        let p = tempPath("adv")
        defer { try? FileManager.default.removeItem(atPath: p) }
        let hb = DecodeHeartbeat(path: p)
        XCTAssertNotNil(hb)
        XCTAssertEqual(hb!.count, 0)              // fresh run starts at 0 (contract)
        hb!.noteDecodedFrame()
        XCTAssertEqual(readValue(p), 1)
        hb!.noteDecodedFrame(); hb!.noteDecodedFrame()
        XCTAssertEqual(hb!.count, 3)
        XCTAssertEqual(readValue(p), 3)           // value IS the decode counter
    }

    func testStallMeansUnchangedValue() {
        let p = tempPath("stall")
        defer { try? FileManager.default.removeItem(atPath: p) }
        let hb = DecodeHeartbeat(path: p)!
        hb.noteDecodedFrame(); hb.noteDecodedFrame()
        let first = readValue(p)
        // no decode progress -> no writes -> gate sees a non-advancing value
        XCTAssertEqual(readValue(p), first)
        XCTAssertEqual(first, 2)
    }

    func testFreshInstanceResetsCounterPerRun() {
        let p1 = tempPath("run1"); let p2 = tempPath("run2")
        defer { try? FileManager.default.removeItem(atPath: p1); try? FileManager.default.removeItem(atPath: p2) }
        let a = DecodeHeartbeat(path: p1)!
        a.noteDecodedFrame(); a.noteDecodedFrame()
        let b = DecodeHeartbeat(path: p2)!
        b.noteDecodedFrame()
        XCTAssertEqual(readValue(p2), 1)          // per-playback reset, never cumulative
        XCTAssertEqual(readValue(p1), 2)
    }

    func testUnwritablePathCountsFailureNeverThrows() {
        let hb = DecodeHeartbeat(path: "/nonexistent-dir-xyz/hb.txt")!
        hb.noteDecodedFrame()                     // must not crash playback
        XCTAssertEqual(hb.count, 1)               // in-memory counter still honest
        XCTAssertEqual(hb.writeFailures, 1)       // and the failure is visible
    }

    func testNoTmpLitterOnSuccess() {
        let p = tempPath("clean")
        defer { try? FileManager.default.removeItem(atPath: p) }
        let hb = DecodeHeartbeat(path: p)!
        hb.noteDecodedFrame()
        XCTAssertFalse(FileManager.default.fileExists(atPath: p + ".tmp-\(getpid())"))
    }
}
