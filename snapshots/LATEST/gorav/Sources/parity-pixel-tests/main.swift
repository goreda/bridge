import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
import GorAVPlaybackCore

// parity-pixel-tests (arch-196x item 2): proves the untagged mpv-parity rule
// END TO END at the pixel level, on the real product path:
//   FFmpegSoftwareDecoder.open -> frameDecoded -> framePlaneCopyDerived
//   (v4.4 amendment: untagged + no HDR side data -> .sdrCompatible;
//   matrix guess bt709 at w>=1280 or h>576 else bt601, named in provenance)
//   -> YUV420Converter with the provenance-named matrix -> per-channel
//   FNV-1a-64 vs the kit golden (kits/e1-corpus/*.golden.json).
// The golden's reference chain mirrors the CFFmpeg shim's sws flags and the
// converter's fixed-point formula exactly, so a match is byte-exact; a
// wrong-matrix product path (e.g. 601 applied to 1080p) CANNOT match.
// Usage: swift run parity-pixel-tests <fixture> <golden.json> [sampleFrame]
// Exit 0 PASS, 1 FAIL, 2 NOT_RUN (typed decoder/admission refusal).

struct Golden: Decodable {
    let sampleFrame: Int
    let width: Int
    let height: Int
    let digests: Digests
    struct Digests: Decodable { let R: String; let G: String; let B: String; let A: String }
}

func fnv(_ h: UInt64, _ b: UInt8) -> UInt64 { return (h ^ UInt64(b)) &* 1099511628211 }

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("PARITY NOT_RUN: usage parity-pixel-tests <fixture> <golden.json> [sampleFrame]")
    exit(2)
}
let fixture = args[1]
let goldenURL = URL(fileURLWithPath: args[2])
guard let golden = try? JSONDecoder().decode(Golden.self, from: Data(contentsOf: goldenURL)) else {
    print("PARITY FAIL: golden unreadable \(args[2])")
    exit(1)
}
let sample = args.count >= 4 ? (Int(args[3]) ?? golden.sampleFrame) : golden.sampleFrame
let shapeName = (fixture as NSString).lastPathComponent

let decoder = FFmpegSoftwareDecoder()
do { try decoder.pinLocalRoots([(fixture as NSString).deletingLastPathComponent]) }
catch { print("PARITY FAIL \(shapeName): pinLocalRoots \(error)"); exit(1) }
let session = SessionID(uncheckedEpoch: 77)
do {
    try await decoder.open(source: SourceDescriptor(id: fixture, kind: .local, seekable: true), session: session)
} catch {
    print("PARITY NOT_RUN \(shapeName): open refused typed: \(error)")
    exit(2)
}

var index = -1
var fail: String? = nil
var done = false
while !done, let event = await decoder.nextEvent(session: session) {
    switch event {
    case .frameDecoded(let frame):
        index += 1
        if index == sample {
            do {
                let d = try await decoder.framePlaneCopyDerived(handle: frame.handle, session: session)
                guard d.format == "yuv420p", d.planes.count == 3 else {
                    fail = "derived format=\(d.format) planes=\(d.planes.count)"; break
                }
                guard d.width == golden.width, d.height == golden.height else {
                    fail = "geometry \(d.width)x\(d.height) != golden \(golden.width)x\(golden.height)"; break
                }
                var matrix: YUV420Converter.Matrix = .bt601
                switch d.presentation {
                case .direct8bit(let prov):
                    // 8-bit copy-through names no applied matrix ("none"):
                    // resolve via the same mpv-parity policy the shell's
                    // direct lease path applies (arch-196x item 2, lane b).
                    guard let m = UntaggedColorPolicy.resolveDirectMatrix(
                        // Provenance vocabulary: av_color_*_name() spells the
                        // UNSPECIFIED enum "unknown" and unclassifiable raws
                        // collapse to "unspecified" - both mean "no tag" here.
                        colorSpace: ["unspecified", "unknown"].contains(prov.sourceMatrix) ? nil : prov.sourceMatrix,
                        transfer: ["unspecified", "unknown"].contains(prov.sourceTransfer) ? nil : prov.sourceTransfer,
                        anyTagUnknown: false, hasHDRSideData: false,
                        width: d.width, height: d.height) else {
                        fail = "direct8bit matrix unresolved srcMatrix=\(prov.sourceMatrix)"; break
                    }
                    matrix = m
                    print("PARITY DIAG presentation=direct8bit policy=\(m) srcTags=\(prov.sourceTransfer)/\(prov.sourcePrimaries)/\(prov.sourceMatrix)")
                case .sdrCompatible(let prov):
                    matrix = prov.matrixApplied.hasPrefix("itu709") ? .bt709 : .bt601
                    print("PARITY DIAG presentation=\(prov.matrixApplied) srcTags=\(prov.sourceTransfer)/\(prov.sourcePrimaries)/\(prov.sourceMatrix)")
                case .notRenderablePreview(let prov):
                    fail = "typed notRenderablePreview matrixApplied=\(prov.matrixApplied) - parity rule did not type this SDR"
                    break
                }
                if fail == nil {
                    let rgba = d.planes[0].withUnsafeBufferPointer { yb -> [UInt8] in
                        d.planes[1].withUnsafeBufferPointer { ub in
                            d.planes[2].withUnsafeBufferPointer { vb in
                                YUV420Converter.rgbaFromYUV420p(
                                    y: yb.baseAddress!, yStride: d.width,
                                    u: ub.baseAddress!, uStride: (d.width + 1) >> 1,
                                    v: vb.baseAddress!, vStride: (d.width + 1) >> 1,
                                    width: d.width, height: d.height, matrix: matrix)
                            }
                        }
                    }
                    var dr: UInt64 = 0xcbf29ce484222325, dg = dr, db = dr, da = dr
                    var i = 0
                    while i < rgba.count {
                        dr = fnv(dr, rgba[i]); dg = fnv(dg, rgba[i + 1]); db = fnv(db, rgba[i + 2]); da = fnv(da, rgba[i + 3])
                        i += 4
                    }
                    let got = [String(format: "%016llx", dr), String(format: "%016llx", dg),
                               String(format: "%016llx", db), String(format: "%016llx", da)]
                    let want = [golden.digests.R, golden.digests.G, golden.digests.B, golden.digests.A]
                    if got != want {
                        fail = "pixel digest mismatch got=\(got) want=\(want)"
                    }
                }
            } catch {
                fail = "derived typed refusal: \(error)"
            }
            done = true
        }
        await decoder.releaseFrame(handle: frame.handle, session: session)
    case .endOfStream: done = true
    case .failed(let code, let summary):
        fail = "decoder failed \(code) \(summary)"; done = true
    default: break
    }
    if fail != nil { done = true }
}
_ = await decoder.closeAndReport(session: session)

if index < sample && fail == nil { fail = "stream ended at frame \(index + 1), sample \(sample) never reached" }
if let f = fail {
    print("PARITY FAIL \(shapeName): \(f)")
    exit(1)
}
print("PARITY PASS \(shapeName) frame=\(sample) digests=golden")
exit(0)
