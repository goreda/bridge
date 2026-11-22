import XCTest
@testable import HDRReference
#if canImport(Metal)
import Metal
#endif

// P-B3 test suite. Fixtures are generated artifacts from
// tools/generate_fixtures.py (hashes in MANIFEST.sha256); tests consume the
// saved oracle, never call the generator as implementation.
final class HDRReferenceTests: XCTestCase {

    let ref = ScalarHDRReference()
    let sourcePeak = 1000.0
    let targetPeak = 100.0

    static var packageRoot: URL {
        // Tests/HDRReferenceTests/HDRReferenceTests.swift -> package root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    struct RampRow { let nits: Double; let code: Double; let out: RGB }
    struct PatchRow { let name: String; let lin: RGB; let code: RGB; let out: RGB }

    func loadCSV(_ name: String) throws -> [[String]] {
        let url = Self.packageRoot.appendingPathComponent("fixtures/" + name)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst() // header
            .map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
    }

    func loadRamp() throws -> [RampRow] {
        try loadCSV("pq-gray-ramp.csv").map { c in
            RampRow(nits: Double(c[0])!, code: Double(c[1])!,
                    out: RGB(r: Double(c[2])!, g: Double(c[3])!, b: Double(c[4])!))
        }
    }

    func loadPatches() throws -> [PatchRow] {
        try loadCSV("hdr-primary-patches.csv").map { c in
            PatchRow(name: c[0],
                     lin: RGB(r: Double(c[1])!, g: Double(c[2])!, b: Double(c[3])!),
                     code: RGB(r: Double(c[4])!, g: Double(c[5])!, b: Double(c[6])!),
                     out: RGB(r: Double(c[7])!, g: Double(c[8])!, b: Double(c[9])!))
        }
    }

    // Assert: PQ reference round-trip, relative error <= 1e-6 where positive.
    func testPQRoundTripKnownSamples() {
        for l in [0.1, 1.0, 10.0, 100.0, 400.0, 1000.0] {
            let l2 = ScalarHDRReference.pqEOTF(ScalarHDRReference.pqOETFInverse(l))
            XCTAssertLessThanOrEqual(abs(l2 - l) / l, 1e-6, "round-trip at \(l) nits")
        }
    }

    func testPQRoundTripDense() {
        var maxRel = 0.0
        for i in 0...1000 {
            let l = 0.001 * pow(10.0, 7.0 * Double(i) / 1000.0)
            let l2 = ScalarHDRReference.pqEOTF(ScalarHDRReference.pqOETFInverse(l))
            maxRel = max(maxRel, abs(l2 - l) / l)
        }
        XCTAssertLessThanOrEqual(maxRel, 1e-6, "dense round-trip maxRel=\(maxRel)")
    }

    // Assert: black maps black, exactly.
    func testBlackMapsBlack() throws {
        let out = try ref.map(pq2020: RGB(r: 0, g: 0, b: 0),
                              sourcePeakNits: sourcePeak, targetPeakNits: targetPeak)
        XCTAssertEqual(out, RGB(r: 0, g: 0, b: 0))
    }

    // Assert: gray ramp fixture rows recompute within 1e-9 of the saved oracle;
    // neutral outputs neutral within 1e-6, finite, monotonic.
    func testGrayRampFixture() throws {
        let rows = try loadRamp()
        XCTAssertEqual(rows.count, 7)
        var prev = -1.0
        for row in rows {
            XCTAssertEqual(ScalarHDRReference.pqOETFInverse(row.nits), row.code,
                           accuracy: 1e-12, "pq_code column")
            let got = try ref.map(pq2020: RGB(r: row.code, g: row.code, b: row.code),
                                  sourcePeakNits: sourcePeak, targetPeakNits: targetPeak)
            for (a, b) in [(got.r, row.out.r), (got.g, row.out.g), (got.b, row.out.b)] {
                XCTAssertEqual(a, b, accuracy: 1e-9, "oracle match at \(row.nits) nits")
            }
            let spread = max(got.r, got.g, got.b) - min(got.r, got.g, got.b)
            XCTAssertLessThanOrEqual(spread, 1e-6, "neutrality at \(row.nits) nits")
            XCTAssertTrue(got.r.isFinite && got.g.isFinite && got.b.isFinite)
            XCTAssertGreaterThanOrEqual(got.r, prev, "monotonic at \(row.nits) nits")
            prev = got.r
        }
    }

    // Assert: primary patches recompute within 1e-9 of the saved oracle.
    func testPrimaryPatchesFixture() throws {
        let rows = try loadPatches()
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.map(\.name), ["red", "green", "blue", "white"])
        for row in rows {
            let got = try ref.map(pq2020: row.code,
                                  sourcePeakNits: sourcePeak, targetPeakNits: targetPeak)
            XCTAssertEqual(got.r, row.out.r, accuracy: 1e-9, "\(row.name) r")
            XCTAssertEqual(got.g, row.out.g, accuracy: 1e-9, "\(row.name) g")
            XCTAssertEqual(got.b, row.out.b, accuracy: 1e-9, "\(row.name) b")
        }
    }

    // Assert: specified SDR output stays within [0,1] for every fixture row.
    func testOutputRange() throws {
        for row in try loadRamp() + [] {
            for v in [row.out.r, row.out.g, row.out.b] {
                XCTAssertTrue((0.0...1.0).contains(v))
            }
        }
        for row in try loadPatches() {
            for v in [row.out.r, row.out.g, row.out.b] {
                XCTAssertTrue((0.0...1.0).contains(v))
            }
        }
    }

    // Assert: invalid inputs throw named errors, no silent success.
    func testErrorCases() {
        XCTAssertThrowsError(try ref.map(pq2020: RGB(r: -0.1, g: 0, b: 0),
                                         sourcePeakNits: sourcePeak,
                                         targetPeakNits: targetPeak)) {
            XCTAssertEqual($0 as? HDRReferenceError, .inputOutOfRange)
        }
        XCTAssertThrowsError(try ref.map(pq2020: RGB(r: .nan, g: 0, b: 0),
                                         sourcePeakNits: sourcePeak,
                                         targetPeakNits: targetPeak)) {
            XCTAssertEqual($0 as? HDRReferenceError, .nonFiniteInput)
        }
        XCTAssertThrowsError(try ref.map(pq2020: RGB(r: 0, g: 0, b: 0),
                                         sourcePeakNits: 0, targetPeakNits: targetPeak)) {
            XCTAssertEqual($0 as? HDRReferenceError, .invalidPeak)
        }
    }

    // Assert: reference PPM images are the 8-bit quantization of the oracle.
    func testPPMConsistency() throws {
        func parsePPM(_ name: String) throws -> (Int, Int, [UInt8]) {
            let url = Self.packageRoot.appendingPathComponent("fixtures/" + name)
            let data = try Data(contentsOf: url)
            // Header: "P6\n<w> <h>\n255\n"
            var idx = 0
            func token() -> String {
                while idx < data.count && (data[idx] == UInt8(ascii: " ") || data[idx] == UInt8(ascii: "\n")) {
                    idx += 1
                }
                var s = ""
                while idx < data.count && data[idx] != UInt8(ascii: " ") && data[idx] != UInt8(ascii: "\n") {
                    s.append(Character(UnicodeScalar(data[idx]))); idx += 1
                }
                return s
            }
            XCTAssertEqual(token(), "P6")
            let w = Int(token())!, h = Int(token())!
            XCTAssertEqual(Int(token())!, 255)
            idx += 1 // single LF after maxval
            return (w, h, [UInt8](data[idx...]))
        }
        func to8(_ v: Double) -> UInt8 {
            UInt8(min(255, max(0, Int((min(1.0, max(0.0, v)) * 255.0).rounded()))))
        }
        let ramp = try loadRamp()
        let (w, h, px) = try parsePPM("gray-ramp-reference.ppm")
        XCTAssertEqual(w, 448); XCTAssertEqual(h, 64)
        XCTAssertEqual(px.count, 448 * 64 * 3)
        for (c, row) in ramp.enumerated() {
            let x = c * 64 + 32, y = 32, base = (y * 448 + x) * 3
            XCTAssertEqual(px[base], to8(row.out.r), "ramp cell \(c) r")
            XCTAssertEqual(px[base + 1], to8(row.out.g), "ramp cell \(c) g")
            XCTAssertEqual(px[base + 2], to8(row.out.b), "ramp cell \(c) b")
        }
        let patches = try loadPatches()
        let (w2, h2, px2) = try parsePPM("color-patches-reference.ppm")
        XCTAssertEqual(w2, 256); XCTAssertEqual(h2, 64)
        for (c, row) in patches.enumerated() {
            let x = c * 64 + 32, y = 32, base = (y * 256 + x) * 3
            XCTAssertEqual(px2[base], to8(row.out.r), "patch \(row.name) r")
            XCTAssertEqual(px2[base + 1], to8(row.out.g), "patch \(row.name) g")
            XCTAssertEqual(px2[base + 2], to8(row.out.b), "patch \(row.name) b")
        }
    }

    // Assert (conditional): Metal output vs CPU reference, max absolute channel
    // error <= 1e-4. Skipped with XCTSkip when no Metal device is available;
    // an XCTSkip is Metal execution UNRUN, not a pass.
    #if canImport(Metal)
    func testMetalParity() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("no Metal device: Metal execution unrun")
        }
        let shaderURL = Self.packageRoot.appendingPathComponent("Shaders/tone_map.metal")
        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        guard let fn = library.makeFunction(name: "toneMapKernel"),
              let queue = device.makeCommandQueue() else {
            return XCTFail("Metal pipeline setup failed")
        }
        let pipeline = try device.makeComputePipelineState(function: fn)

        var inputs: [SIMD3<Float>] = []
        var expected: [RGB] = []
        for row in try loadRamp() {
            inputs.append(SIMD3(Float(row.code), Float(row.code), Float(row.code)))
            expected.append(row.out)
        }
        for row in try loadPatches() {
            inputs.append(SIMD3(Float(row.code.r), Float(row.code.g), Float(row.code.b)))
            expected.append(row.out)
        }
        for i in 0...1000 {
            let l = 0.001 * pow(10.0, 7.0 * Double(i) / 1000.0)
            let code = ScalarHDRReference.pqOETFInverse(l)
            inputs.append(SIMD3(Float(code), Float(code), Float(code)))
            expected.append(try ref.map(pq2020: RGB(r: code, g: code, b: code),
                                        sourcePeakNits: sourcePeak, targetPeakNits: targetPeak))
        }
        let n = inputs.count
        guard let inBuf = device.makeBuffer(bytes: inputs, length: n * MemoryLayout<SIMD3<Float>>.stride),
              let outBuf = device.makeBuffer(length: n * MemoryLayout<SIMD3<Float>>.stride),
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else {
            return XCTFail("Metal buffer/encoder setup failed")
        }
        var sp = Float(sourcePeak), tp = Float(targetPeak)
        enc.setComputePipelineState(pipeline)
        enc.setBuffer(inBuf, offset: 0, index: 0)
        enc.setBuffer(outBuf, offset: 0, index: 1)
        enc.setBytes(&sp, length: MemoryLayout<Float>.size, index: 2)
        enc.setBytes(&tp, length: MemoryLayout<Float>.size, index: 3)
        enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: min(64, n), height: 1, depth: 1))
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        let outPtr = outBuf.contents().bindMemory(to: SIMD3<Float>.self, capacity: n)
        var maxErr = 0.0
        for i in 0..<n {
            let o = outPtr[i], e = expected[i]
            maxErr = max(maxErr, abs(Double(o.x) - e.r),
                         abs(Double(o.y) - e.g), abs(Double(o.z) - e.b))
        }
        XCTAssertLessThanOrEqual(maxErr, 1e-4, "Metal vs CPU maxErr=\(maxErr)")
    }
    #endif
}
