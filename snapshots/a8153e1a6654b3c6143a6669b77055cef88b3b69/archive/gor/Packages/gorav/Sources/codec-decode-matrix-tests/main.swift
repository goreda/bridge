import Foundation
import GorAVCore
import GorAVPlaybackCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
import GorAVSeekComposition

// W-gdb-073: per-codec decode-to-checksum fixtures for the full-codec
// provider (arch-196y item 4(d)). v2: rows run through shapes the product
// admission guard accepts (lane b run 1 RED on bare-file admission); codecs
// admission refuses run as expected-refusal rows asserting the typed
// AudioOpenError.rejected("admission: ...") - findings, not dropped rows.
// v3: negative control flips flac (D3-clean); the five priming-codec rows
// fail D3 by real product behaviour (architect-held finding, not weakened).
// v4 (G0834): per-row lines print d1/d2/d3 digests so D1==D2 is positively
// visible; the packet command runs the control unconditionally in the same
// receipt (base; rc1; control; rc2; test rc1==1 && rc2==0). Every row opens its fixture through the
// REAL FFmpegSoftwareAudioDecoder, pumps the whole stream through the REAL
// BoundAudioPump (packed s16le via the product L3SampleConverter path) and
// FNV-1a digests the PCM. Lane-only: needs the full-codec FFmpeg provider.
//
// Legs per row:
//   D1: full decode -> digest
//   D2: second decoder, same fixture -> digest must equal D1 (determinism)
//   D3: seek(0) on the first decoder, pump again -> digest must equal D1
//       (seek-reset cleanliness of the decoder/converter state)
// Digests are NOT in matrix.json: they exist only on the lane's pinned 7.1
// provider and are attested in the run receipt (attested-marker pattern).
// Negative control: --negative-control flips the FIRST row's D3 expectation
// (D3 must equal D1^1); the control passes iff exactly that row fails with
// its codec id printed.

struct MatrixRow: Decodable {
    let id: String
    let file: String
    let codec: String
    let sha256: String
    let channels: Int
    let minBytes: Int
    let kind: String // "decode" | "expectedRefusal" (v2: admission shapes)
}

struct MatrixFile: Decodable {
    let schema: String
    let rows: [MatrixRow]
}

final class CollectingSink: AudioSinkControlling, @unchecked Sendable {
    private(set) var bytes: [UInt8] = []
    private(set) var fence: UInt64 = 0
    var currentFenceGeneration: UInt64 { fence }
    var available: Int { 0 }
    func push(_ pcm: [UInt8]) { bytes.append(contentsOf: pcm) }
    func resetRingForSeek() async -> UInt64? {
        fence += 1
        return fence
    }
    func reset() { bytes.removeAll(keepingCapacity: true) }
}

func fnv1a64(_ bytes: [UInt8]) -> UInt64 {
    var h: UInt64 = 14695981039346656037
    for b in bytes { h = (h ^ UInt64(b)) &* 1099511628211 }
    return h
}

struct DecodeResult {
    let digest: UInt64
    let pushedFrames: Int
    let bytes: Int
    let terminal: String
}

func decodeAll(root: String, file: String, epoch: UInt64) async -> (FFmpegSoftwareAudioDecoder, SessionID, AudioSeekDescriptor, CollectingSink, DecodeResult) {
    let dec = FFmpegSoftwareAudioDecoder()
    try! dec.pinLocalRoots([root])
    let sid = SessionID(uncheckedEpoch: epoch)
    try! await dec.open(source: SourceDescriptor(id: root + "/fixtures/" + file, kind: .local, seekable: true), session: sid)
    guard let desc = await dec.seekDescriptor(session: sid) else {
        fatalError("no seek descriptor for \(file)")
    }
    let sink = CollectingSink()
    let out = await BoundAudioPump.run(decoder: dec, session: sid, binding: desc.binding, correlation: nil, sink: sink)
    let r = DecodeResult(digest: fnv1a64(sink.bytes), pushedFrames: out.pushed, bytes: sink.bytes.count, terminal: String(describing: out.terminal))
    return (dec, sid, desc, sink, r)
}

func decodeFresh(root: String, file: String, epoch: UInt64) async -> DecodeResult {
    let (_, _, _, _, r) = await decodeAll(root: root, file: file, epoch: epoch)
    return r
}

/// Expected-refusal leg (v2): the open must fail with the typed admission
/// refusal AudioOpenError.rejected("admission: ..."); the reason is printed
/// for the receipt. A successful open is a finding, not a pass.
func probeOpen(root: String, file: String, epoch: UInt64) async -> (Bool, String) {
    let dec = FFmpegSoftwareAudioDecoder()
    try! dec.pinLocalRoots([root])
    let sid = SessionID(uncheckedEpoch: epoch)
    do {
        try await dec.open(source: SourceDescriptor(id: root + "/fixtures/" + file, kind: .local, seekable: true), session: sid)
        return (false, "open succeeded (unexpected)")
    } catch {
        return (true, String(describing: error).replacingOccurrences(of: "\n", with: " "))
    }
}

@main
struct CodecDecodeMatrixMain {
    static func main() async {
        var args = CommandLine.arguments
        args.removeFirst()
        var matrixPath: String?
        var negativeControl = false
        var i = 0
        while i < args.count {
            if args[i] == "--negative-control" { negativeControl = true; i += 1 }
            else { matrixPath = args[i]; i += 1 }
        }
        guard let matrixPath else {
            FileHandle.standardError.write(Data("usage: codec-decode-matrix-tests <matrix.json> [--negative-control]\n".utf8))
            exit(2)
        }
        let root = FileManager.default.currentDirectoryPath
        let matrix: MatrixFile
        do {
            matrix = try JSONDecoder().decode(MatrixFile.self, from: Data(contentsOf: URL(fileURLWithPath: matrixPath)))
        } catch {
            FileHandle.standardError.write(Data("matrix load failed: \(error)\n".utf8))
            exit(2)
        }
        guard matrix.schema == "codec-decode-matrix/v2" else {
            FileHandle.standardError.write(Data("matrix schema mismatch: \(matrix.schema)\n".utf8))
            exit(2)
        }

        var failures: [(String, String)] = []
        for (n, row) in matrix.rows.enumerated() {
            let epoch = UInt64(9100 + n)
            if row.kind == "expectedRefusal" {
                let (refused, reason) = await probeOpen(root: root, file: row.file, epoch: epoch)
                let passed = refused && reason.contains("admission:")
                if !passed { failures.append((row.id, "expected typed admission refusal, got: \(reason)")) }
                print("\(row.id)\t\(row.codec)\trefusal=\(reason)\t\(passed ? "PASS" : "FAIL")")
                continue
            }
            let (dec, sid, desc, sink, d1) = await decodeAll(root: root, file: row.file, epoch: epoch)
            let d2 = await decodeFresh(root: root, file: row.file, epoch: epoch + 500)

            // D3: seek back to 0 on the first decoder and pump again.
            var d3: DecodeResult? = nil
            let seekResult = await dec.seek(binding: desc.binding,
                                            videoRelativeTarget: try! RationalTime(value: 0, timescale: 1),
                                            correlation: 1)
            if case .nativeReady(let nb, let ncorr, _, _) = seekResult {
                sink.reset()
                let out = await BoundAudioPump.run(decoder: dec, session: sid, binding: nb, correlation: ncorr, sink: sink)
                d3 = DecodeResult(digest: fnv1a64(sink.bytes), pushedFrames: out.pushed, bytes: sink.bytes.count, terminal: String(describing: out.terminal))
            }

            var rowFail: [String] = []
            if d1.bytes < row.minBytes { rowFail.append("D1 bytes \(d1.bytes) < minBytes \(row.minBytes)") }
            if d1.digest != d2.digest { rowFail.append("D2 digest \(String(d2.digest, radix: 16)) != D1 \(String(d1.digest, radix: 16))") }
            let expectD3 = negativeControl && row.id == "flac" ? d1.digest ^ 1 : d1.digest
            guard let d3 else {
                rowFail.append("D3 seek(0) did not return nativeReady: \(seekResult)")
                if !rowFail.isEmpty { failures.append((row.id, rowFail.joined(separator: "; "))) }
                print("\(row.id)\t\(row.codec)\td1=\(String(d1.digest, radix: 16))\td2=\(String(d2.digest, radix: 16))\td3=n/a\tframes=\(d1.pushedFrames)\tbytes=\(d1.bytes)\tFAIL")
                continue
            }
            if d3.digest != expectD3 { rowFail.append("D3 digest \(String(d3.digest, radix: 16)) != expected \(String(expectD3, radix: 16))") }

            let passed = rowFail.isEmpty
            if !passed { failures.append((row.id, rowFail.joined(separator: "; "))) }
            print("\(row.id)\t\(row.codec)\td1=\(String(d1.digest, radix: 16))\td2=\(String(d2.digest, radix: 16))\td3=\(String(d3.digest, radix: 16))\tframes=\(d1.pushedFrames)\tbytes=\(d1.bytes)\t\(passed ? "PASS" : "FAIL")")
            for f in rowFail { print("  FAIL \(row.id): \(f)") }
        }

        if negativeControl {
            // v3: the flipped row is flac (D3-clean); the priming-codec rows
            // (aac/mp3/opus/ac3/eac3) fail D3 by real product behaviour, so
            // the control asserts flac fails, not that it fails alone.
            let ok = failures.contains { $0.0 == "flac" }
            print("negative-control: flipped D3 expectation for flac -> " +
                  (ok ? "correctly FAILED with codec id" : "UNEXPECTED RESULT"))
            exit(ok ? 0 : 1)
        }
        print("codec-matrix: \(matrix.rows.count) codecs, \(matrix.rows.count - failures.count) pass, \(failures.count) fail")
        exit(failures.isEmpty ? 0 : 1)
    }
}

