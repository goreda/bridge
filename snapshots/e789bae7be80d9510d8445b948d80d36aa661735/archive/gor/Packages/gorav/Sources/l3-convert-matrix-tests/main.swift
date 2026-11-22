import Foundation

// l3-convert-matrix-tests: golden conversion-matrix checker for packet
// W-gdb-013 (N9 format/rate conversion, rewrites W-0279).
//
// Replays matrix.json under the fixed packed s16le stereo 44.1 kHz output
// contract against every enabled lane:
//   - reference: portable ReferenceConverter (always built; no FFmpeg)
//   - provider:  the real pinned L3SampleConverter (only when the product
//                package defines L3_PROVIDER for this target)
// Usage: swift run l3-convert-matrix-tests [path-to-matrix.json]
// Final stdout line: "l3-convert-matrix-tests: <N> PASS, <M> FAIL".
// Exit 0 iff M == 0.

struct MatrixDoc: Decodable {
    struct Row: Decodable {
        var id: String
        var kind: String
        var layout: String?
        var inFormat: String?
        var inRate: Int?
        var inSamples: Int?
        var expect: Expect?
        var name: String?
        var steps: [Step]?
    }
    struct Step: Decodable {
        var op: String
        var layout: String?
        var inFormat: String?
        var inRate: Int?
        var inSamples: Int?
        var tone: Double?
        var expect: Expect?
        var maxFrameBytes: Int?
        var `repeat`: Int?
        var inputRate: Int?
        var rule: String?
        var convertedFrames: Int?
        var conversionFailures: Int?
        var seekCount: Int?
        var reinitCount: Int?
        var tolerance: Double?
        var freq: Double?
        var maxRatio: Double?
    }
    enum Expect: Decodable, Equatable {
        case converted, nilFailure, empty, bool(Bool)
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .bool(b); return }
            switch try c.decode(String.self) {
            case "converted": self = .converted
            case "nil-failure": self = .nilFailure
            case "empty": self = .empty
            default: throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad expect")
            }
        }
    }
    var rows: [Row]
}

protocol Conv {
    var convertedFrames: Int { get }
    var conversionFailures: Int { get }
    var outputSamples: Int64 { get }
    var inputSamplesByRate: [Int: Int64] { get }
    var seekCount: Int { get }
    var reinitCount: Int { get }
    func currentInputDelay(inputRate: Int64) -> Int64
    func resetForSeek() -> Bool
    func convert(frame: RefFrame, maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)?
    func drain(maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)?
}

final class RefConv: Conv {
    let inner = ReferenceConverter()
    var convertedFrames: Int { inner.convertedFrames }
    var conversionFailures: Int { inner.conversionFailures }
    var outputSamples: Int64 { inner.outputSamples }
    var inputSamplesByRate: [Int: Int64] { inner.inputSamplesByRate }
    var seekCount: Int { inner.seekCount }
    var reinitCount: Int { inner.reinitCount }
    func currentInputDelay(inputRate: Int64) -> Int64 { inner.currentInputDelay(inputRate: inputRate) }
    func resetForSeek() -> Bool { inner.resetForSeek() }
    func convert(frame: RefFrame, maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)? {
        inner.convert(frame: frame, maxFrameBytes: maxFrameBytes)
    }
    func drain(maxFrameBytes: Int) -> (bytes: [UInt8], samples: Int)? {
        inner.drain(maxFrameBytes: maxFrameBytes)
    }
}

func goertzel(_ s16: [Int16], rate: Double, freq: Double) -> Double {
    guard !s16.isEmpty else { return 0 }
    let w = 2.0 * Double.pi * freq / rate
    let coeff = 2.0 * cos(w)
    var s0 = 0.0, s1 = 0.0, s2 = 0.0
    for x in s16 { s0 = Double(x) + coeff * s1 - s2; s2 = s1; s1 = s0 }
    return (s1 * s1 + s2 * s2 - coeff * s1 * s2) / Double(s16.count * s16.count)
}

func leftChannel(_ bytes: [UInt8]) -> [Int16] {
    var out: [Int16] = []
    out.reserveCapacity(bytes.count / 4)
    var i = 0
    while i + 1 < bytes.count {
        out.append(Int16(bitPattern: UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8)))
        i += 4 // packed stereo: left sample only
    }
    return out
}

var passCount = 0
var failCount = 0
func record(_ ok: Bool, _ id: String, _ lane: String, _ detail: String) {
    if ok { passCount += 1 } else { failCount += 1; print("FAIL \(id) [\(lane)] \(detail)") }
}

func runConvertRow(_ row: MatrixDoc.Row, lane: String, make: () -> Conv) {
    let c = make()
    let d = RefFrame(layout: row.layout ?? "", inFormat: row.inFormat ?? "",
                     inRate: row.inRate ?? 0, inSamples: row.inSamples ?? 1024, tone: nil)
    let failsBefore = c.conversionFailures
    let r = c.convert(frame: d, maxFrameBytes: 1 << 22)
    switch row.expect {
    case .converted:
        record(r != nil && r!.samples > 0, row.id, lane,
               "expected converted, got \(r == nil ? "nil" : "samples=\(r!.samples)")")
        if r != nil { record(c.conversionFailures == failsBefore, row.id, lane, "converted but conversionFailures incremented") }
    case .nilFailure:
        record(r == nil, row.id, lane, "expected nil-failure, got samples=\(r?.samples ?? -1)")
        record(c.conversionFailures == failsBefore + 1, row.id, lane,
               "nil-return must be counted in conversionFailures (delta=\(c.conversionFailures - failsBefore))")
    default:
        record(false, row.id, lane, "bad convert-row expect")
    }
}

func runSequence(_ row: MatrixDoc.Row, lane: String, make: () -> Conv) {
    let c = make()
    var okAll = true
    var postResetTone: Double? = nil
    var preResetTone: Double? = nil
    var lastBytes: [UInt8] = []
    func check(_ ok: Bool, _ detail: String) { if !ok { okAll = false; print("FAIL \(row.id) [\(lane)] \(detail)") } }
    for step in row.steps ?? [] {
        switch step.op {
        case "convert":
            let d = RefFrame(layout: step.layout ?? "", inFormat: step.inFormat ?? "",
                             inRate: step.inRate ?? 0, inSamples: step.inSamples ?? 1024, tone: step.tone)
            for _ in 0..<(step.`repeat` ?? 1) {
                let failsBefore = c.conversionFailures
                let r = c.convert(frame: d, maxFrameBytes: step.maxFrameBytes ?? (1 << 22))
                switch step.expect {
                case .converted:
                    check(r != nil, "convert \(d.layout)/\(d.inFormat)/\(d.inRate) expected converted, got nil")
                    if let r = r { lastBytes = r.bytes }
                case .nilFailure:
                    check(r == nil, "convert expected nil-failure, got samples=\(r?.samples ?? -1)")
                    check(c.conversionFailures == failsBefore + 1, "nil-return not counted in conversionFailures")
                default: check(false, "convert step missing expect")
                }
            }
        case "drain":
            let r = c.drain(maxFrameBytes: step.maxFrameBytes ?? (1 << 22))
            switch step.expect {
            case .converted: check(r != nil && r!.samples > 0, "drain expected tail, got \(r?.samples ?? -1)")
            case .empty: check(r != nil && r!.samples == 0, "drain expected empty, got \(r?.samples ?? -1)")
            case .nilFailure: check(r == nil, "drain expected nil-failure")
            default: check(false, "drain step missing expect")
            }
        case "resetForSeek":
            preResetTone = postResetTone ?? preResetTone
            let ok = c.resetForSeek()
            check(ok == (step.expect == .bool(true)), "resetForSeek returned \(ok)")
        case "checkDelay":
            let dl = c.currentInputDelay(inputRate: Int64(step.inputRate ?? 44100))
            switch step.rule {
            case "==0": check(dl == 0, "delay \(dl) != 0")
            case ">=0": check(dl >= 0, "delay \(dl) < 0")
            default: check(false, "unknown delay rule")
            }
        case "checkCounters":
            if let v = step.convertedFrames { check(c.convertedFrames == v, "convertedFrames \(c.convertedFrames) != \(v)") }
            if let v = step.conversionFailures { check(c.conversionFailures == v, "conversionFailures \(c.conversionFailures) != \(v)") }
            if let v = step.seekCount { check(c.seekCount == v, "seekCount \(c.seekCount) != \(v)") }
            if let v = step.reinitCount { check(c.reinitCount == v, "reinitCount \(c.reinitCount) != \(v)") }
        case "checkDuration":
            var ideal = 0.0
            for (rate, n) in c.inputSamplesByRate { ideal += Double(n) * 44100.0 / Double(rate) }
            let tol = step.tolerance ?? 0.005
            let delta = abs(Double(c.outputSamples) - ideal)
            check(delta <= max(64.0, ideal * tol), "duration drift: out=\(c.outputSamples) ideal=\(ideal) delta=\(delta)")
        case "checkNoPreResetTone":
            // Witness: the post-reset output carries NO energy at the
            // pre-reset tone frequency relative to the post-reset tone.
            let s16 = leftChannel(lastBytes)
            let pre = step.freq ?? 440
            var best = 0.0, bestP = 0.0
            for f in stride(from: 220.0, through: 1760.0, by: 220.0) where abs(f - pre) > 1 {
                let p = goertzel(s16, rate: 44100, freq: f)
                if p > bestP { bestP = p; best = f }
            }
            let pPre = goertzel(s16, rate: 44100, freq: pre)
            let ratio = bestP > 0 ? pPre / bestP : Double.infinity
            check(bestP > 0 && ratio <= (step.maxRatio ?? 0.001),
                  "pre-reset tone \(pre)Hz not eliminated: power=\(pPre) vs \(best)Hz power=\(bestP) ratio=\(ratio)")
            postResetTone = best
        default:
            check(false, "unknown op \(step.op)")
        }
    }
    record(okAll, row.id, lane, "sequence \(row.name ?? "") failed")
}

// ---- entry ----
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "kits/l3-matrix/matrix.json"
guard let data = FileManager.default.contents(atPath: path) else {
    print("l3-convert-matrix-tests: cannot read matrix at \(path)")
    exit(2)
}
let doc: MatrixDoc
do { doc = try JSONDecoder().decode(MatrixDoc.self, from: data) } catch {
    print("l3-convert-matrix-tests: matrix parse error: \(error)")
    exit(2)
}

var lanes: [(String, () -> Conv)] = [("reference", { RefConv() })]
#if L3_PROVIDER
lanes.append(("provider", { ProviderConv() as Conv }))
#endif

for row in doc.rows {
    for (lane, make) in lanes {
        switch row.kind {
        case "convert": runConvertRow(row, lane: lane, make: make)
        case "sequence": runSequence(row, lane: lane, make: make)
        default: record(false, row.id, lane, "unknown row kind \(row.kind)")
        }
    }
}
print("l3-convert-matrix-tests: \(passCount) PASS, \(failCount) FAIL")
exit(failCount == 0 ? 0 : 1)
