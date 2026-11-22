import XCTest
@testable import BridgeDemux

/// P-A1-R1: malformed-container safety and reopen-state regression.
///
/// Two layers for every crafted fixture:
///  1. In-process: open()/next() throw a *named* DemuxError (never a trap).
///  2. Subprocess: the BridgeDemuxProbe executable is fed the same bytes in a
///     disposable process; exit status must be 0 with an "ERROR ..." line -
///     a fatal-error trap or OOM kill would surface as a nonzero status.
///     Probe runs are wrapped in `ulimit -v` so an allocation explosion is
///     contained and shows up as a kill instead of destabilizing the host.
///
/// The reopen tests open a good stream, drain packets, then attempt to open
/// a malformed one: the reopen must throw the named error, and next() must
/// afterwards throw (no packets from the previous stream may leak through).
final class MalformedSafetyTests: XCTestCase {

    private struct Case {
        let file: String
        let expectedErrorPrefix: String   // named-error prefix for open()
    }

    private let cases: [Case] = [
        // Matroska SimpleBlock with Xiph lace flag but no lace-count byte:
        // the block body ends exactly after the flags byte.
        Case(file: "bad-lace-no-count.mkv", expectedErrorPrefix: "truncated: xiph lace count"),
        // Cluster Timecode = 0xFFFFFFFFFFFFFFFF (Int64 conversion overflow).
        Case(file: "huge-cluster-timecode.mkv", expectedErrorPrefix: "unsupported: cluster Timecode"),
        // TimestampScale = 0xFFFFFFFFFFFFFFFF (Int64 conversion overflow).
        Case(file: "huge-timestamp-scale.mkv", expectedErrorPrefix: "unsupported: TimestampScale"),
        // ftyp box with an absurd largesize (size arithmetic must not overflow).
        Case(file: "huge-box-largesize.mp4", expectedErrorPrefix: "truncated: box ftyp"),
        // stsz sample_count far larger than the file.
        Case(file: "huge-stsz-count.mp4", expectedErrorPrefix: "malformed: stsz count"),
        // ctts run-length count that would explode the expansion.
        Case(file: "huge-ctts-count.mp4", expectedErrorPrefix: "malformed: ctts entry count"),
        // stts run-length sum beyond any plausible sample count.
        Case(file: "huge-stts-count.mp4", expectedErrorPrefix: "malformed: stts sample count"),
    ]

    // MARK: - Path resolution

    private func fixtureURL(_ name: String) -> URL {
        let url = Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures/malformed")
            .appendingPathComponent(name)
        return url
    }

    private func goodFixtureURL(_ name: String) -> URL {
        Bundle.module.resourceURL!
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    /// The probe executable is built by `swift test` next to the test bundle.
    private func probeURL() -> URL {
        let testBundle = Bundle(for: MalformedSafetyTests.self).bundleURL
        // .build/debug/BridgeDemuxTests.xctest -> .build/debug/BridgeDemuxProbe
        let sibling = testBundle.deletingLastPathComponent()
            .appendingPathComponent("BridgeDemuxProbe")
        if FileManager.default.fileExists(atPath: sibling.path) { return sibling }
        // Fallback: package-root .build/debug (derived from this file).
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // BridgeDemuxTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        return root.appendingPathComponent(".build/debug/BridgeDemuxProbe")
    }

    private func runProbe(_ args: [String], memoryLimitKB: Int = 2_097_152) throws -> (status: Int32, output: String) {
        let probe = probeURL()
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: probe.path),
                      "probe executable missing at \(probe.path); run `swift build` first")
        let p = Process()
        let quoted = ([probe.path] + args).map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "ulimit -v \(memoryLimitKB) 2>/dev/null; exec \(quoted.joined(separator: " "))"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    // MARK: - In-process named-error assertions

    func testMalformedFixturesThrowNamedErrorsInProcess() throws {
        for c in cases {
            let bytes = [UInt8](try Data(contentsOf: fixtureURL(c.file)))
            var d = Demuxer()
            do {
                _ = try d.open(bytes)
                XCTFail("\(c.file): open succeeded on malformed input")
            } catch let e as DemuxError {
                XCTAssertTrue(e.description.hasPrefix(c.expectedErrorPrefix),
                              "\(c.file): unexpected error: \(e)")
            } catch {
                XCTFail("\(c.file): non-DemuxError thrown: \(error)")
            }
        }
    }

    // MARK: - Subprocess crash regressions (named error, no process trap)

    func testMalformedFixturesNoProcessTrap() throws {
        for c in cases {
            let r = try runProbe(["demux", fixtureURL(c.file).path])
            XCTAssertEqual(r.status, 0,
                           "\(c.file): probe terminated abnormally (status \(r.status)):\n\(r.output)")
            XCTAssertTrue(r.output.hasPrefix("ERROR "),
                          "\(c.file): expected a named error line, got:\n\(r.output)")
            XCTAssertTrue(r.output.hasPrefix("ERROR \(c.expectedErrorPrefix)"),
                          "\(c.file): unexpected error line:\n\(r.output)")
        }
    }

    func testProbeControlOnGoodFixtures() throws {
        for name in ["a1-v24.mp4", "a1-audio.mkv", "a1-bframes.mp4", "f1-av24.mp4"] {
            let r = try runProbe(["demux", goodFixtureURL(name).path])
            XCTAssertEqual(r.status, 0, "\(name): probe failed:\n\(r.output)")
            XCTAssertTrue(r.output.hasPrefix("OK tracks="), "\(name): \(r.output)")
        }
    }

    // MARK: - Reopen-state regression

    /// Subprocess: good open, drain 3 packets, failed reopen, then next().
    /// The probe must report REOPEN-ERROR, and the post-reopen next() must
    /// throw (no stale packet from the first stream may leak through).
    func testFailedReopenNoStalePacketLeakSubprocess() throws {
        for good in ["a1-v24.mp4", "a1-audio.mkv"] {
            for c in cases where c.file.hasSuffix(good.hasSuffix("mp4") ? ".mp4" : ".mkv") {
                let r = try runProbe(["reopen", goodFixtureURL(good).path, fixtureURL(c.file).path, "3"])
                XCTAssertEqual(r.status, 0, "\(good)->\(c.file): abnormal status:\n\(r.output)")
                XCTAssertTrue(r.output.contains("OPEN1 tracks="), "\(good)->\(c.file): \(r.output)")
                XCTAssertTrue(r.output.contains("REOPEN-ERROR \(c.expectedErrorPrefix)"),
                              "\(good)->\(c.file): \(r.output)")
                XCTAssertFalse(r.output.contains("REOPEN-UNEXPECTED-OK"),
                               "\(good)->\(c.file): malformed reopen succeeded: \(r.output)")
                XCTAssertFalse(r.output.contains("AFTER packet"),
                               "\(good)->\(c.file): stale packet leaked after failed reopen: \(r.output)")
                XCTAssertTrue(r.output.contains("AFTER error malformed: next() before open()"),
                              "\(good)->\(c.file): expected named error after failed reopen: \(r.output)")
            }
        }
    }

    /// In-process equivalent of the reopen regression.
    func testFailedReopenInProcess() throws {
        let good = [UInt8](try Data(contentsOf: goodFixtureURL("a1-v24.mp4")))
        let bad = [UInt8](try Data(contentsOf: fixtureURL("huge-stsz-count.mp4")))
        var d = Demuxer()
        let tracks = try d.open(good)
        XCTAssertEqual(tracks.count, 1)
        // Drain a few packets from the good stream.
        for _ in 0 ..< 3 { XCTAssertNotNil(try d.next()) }
        // Failed reopen: named error.
        do {
            _ = try d.open(bad)
            XCTFail("malformed reopen succeeded")
        } catch let e as DemuxError {
            XCTAssertTrue(e.description.hasPrefix("malformed: stsz count"), "unexpected: \(e)")
        }
        // No stale packets from the first stream may leak through.
        do {
            _ = try d.next()
            XCTFail("next() after failed reopen did not throw")
        } catch let e as DemuxError {
            XCTAssertEqual(e, .malformed("next() before open()"))
        }
    }

    /// A failed reopen must not poison later opens: reopening a valid file
    /// afterwards yields exactly the same packets as a fresh demuxer.
    func testSuccessfulOpenAfterFailedReopenMatchesFreshOpen() throws {
        let good = [UInt8](try Data(contentsOf: goodFixtureURL("a1-av24.mp4")))
        let bad = [UInt8](try Data(contentsOf: fixtureURL("huge-ctts-count.mp4")))
        var d = Demuxer()
        _ = try d.open(good)
        _ = try d.next()
        XCTAssertThrowsError(try d.open(bad))
        let tracks = try d.open(good)
        XCTAssertEqual(tracks.count, 2)
        var reopened: [DemuxPacket] = []
        while let p = try d.next() { reopened.append(p) }

        var fresh = Demuxer()
        _ = try fresh.open(good)
        var expected: [DemuxPacket] = []
        while let p = try fresh.next() { expected.append(p) }

        XCTAssertEqual(reopened.count, expected.count)
        XCTAssertFalse(reopened.isEmpty)
        for (a, b) in zip(reopened, expected) {
            XCTAssertEqual(a.trackID, b.trackID)
            XCTAssertEqual(a.pts, b.pts)
            XCTAssertEqual(a.dts, b.dts)
            XCTAssertEqual(a.duration, b.duration)
            XCTAssertEqual(a.bytes, b.bytes)
        }
    }
}
