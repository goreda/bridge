import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter
import GorAVPlaybackCore

// r14 (from r13): decode the kit's pinned mpeg4 fixture through the gorav adapter and write
// every frame as a binary PPM (RGB), 1-based names, so a script can compare them
// with mpv's frames of the same file. Uses the same calls as playback-test and
// ShellFrameSource (both compiled on the owner's Mac per the r10 record).
@main
struct FrameDump {
    static func main() async {
        let KIT = ProcessInfo.processInfo.environment["GORAV_KIT"] ?? "."
        let env = ProcessInfo.processInfo.environment
        let clip = env["GORAV_CLIP"] ?? "k3"
        let wantFrames = Int(env["GORAV_NFRAMES"] ?? "47") ?? 47
        let fixture = "\(KIT)/fixtures/" + (clip == "k3" ? "fixture-k3.mp4" : "fixture-r14-\(clip).mp4")
        let useBil = (env["GORAV_CONV"] ?? "nearest") == "bilinear"
        let dumpYUV = (env["GORAV_DUMP"] ?? "") == "yuv"
        let outDir = "\(KIT)/r14-out/gorav-\(clip)" + (useBil ? "-bilinear" : "")
        let yuvDir = "\(KIT)/r14-out/yuv-\(clip)"
        if dumpYUV { do { try FileManager.default.createDirectory(atPath: yuvDir, withIntermediateDirectories: true) } catch { print("FRAME_DUMP FAIL: mkdir yuv \(error)"); exit(60) } }
        do { try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true) }
        catch { print("FRAME_DUMP FAIL: mkdir \(error)"); exit(60) }

        let decoder = FFmpegSoftwareDecoder()
        do { try decoder.pinLocalRoots([KIT]) }
        catch { print("FRAME_DUMP FAIL: pinLocalRoots \(error)"); exit(66) }
        let session = SessionID(uncheckedEpoch: 31)
        do {
            try await decoder.open(source: SourceDescriptor(id: fixture, kind: .local, seekable: true), session: session)
        } catch { print("FRAME_DUMP FAIL: open \(error)"); exit(67) }

        var written = 0
        var sawEOS = false
        while let event = await decoder.nextEvent(session: session) {
            switch event {
            case .opened(let codec, let w, let h):
                print("opened: codec=\(codec) \(w)x\(h)")
            case .frameDecoded(let frame):
                if let copy = await decoder.framePlaneCopy(handle: frame.handle, session: session),
                   copy.format == "yuv420p", copy.planes.count == 3 {
                    let rgba = copy.planes[0].withUnsafeBufferPointer { yb -> [UInt8] in
                        copy.planes[1].withUnsafeBufferPointer { ub in
                            copy.planes[2].withUnsafeBufferPointer { vb in
                                useBil
                                ? YUV420BilinearConverter.rgbaFromYUV420pBilinear(
                                    y: yb.baseAddress!, yStride: copy.width,
                                    u: ub.baseAddress!, uStride: (copy.width + 1) >> 1,
                                    v: vb.baseAddress!, vStride: (copy.width + 1) >> 1,
                                    width: copy.width, height: copy.height)
                                : YUV420Converter.rgbaFromYUV420p(
                                    y: yb.baseAddress!, yStride: copy.width,
                                    u: ub.baseAddress!, uStride: (copy.width + 1) >> 1,
                                    v: vb.baseAddress!, vStride: (copy.width + 1) >> 1,
                                    width: copy.width, height: copy.height)
                            }
                        }
                    }
                    if dumpYUV {
                        let base = yuvDir + "/frame-" + String(format: "%04d", written + 1)
                        let names = [".y", ".u", ".v"]
                        for pi in 0..<3 {
                            if !FileManager.default.createFile(atPath: base + names[pi], contents: Data(copy.planes[pi])) {
                                print("FRAME_DUMP FAIL: write yuv \(base)\(names[pi])"); exit(72)
                            }
                        }
                    }
                    var ppm = Data("P6\n\(copy.width) \(copy.height)\n255\n".utf8)
                    var rgb = [UInt8]()
                    rgb.reserveCapacity(copy.width * copy.height * 3)
                    var i = 0
                    while i < rgba.count {
                        rgb.append(rgba[i]); rgb.append(rgba[i + 1]); rgb.append(rgba[i + 2])
                        i += 4
                    }
                    ppm.append(contentsOf: rgb)
                    written += 1
                    let name = outDir + "/frame-" + String(format: "%04d", written) + ".ppm"
                    if !FileManager.default.createFile(atPath: name, contents: ppm) {
                        print("FRAME_DUMP FAIL: write \(name)"); exit(68)
                    }
                } else {
                    print("FRAME_DUMP FAIL: frame not yuv420p with 3 planes"); exit(69)
                }
                await decoder.releaseFrame(handle: frame.handle, session: session)
            case .endOfStream:
                sawEOS = true
            case .failed(let code, let summary):
                print("FRAME_DUMP FAIL: failed \(code) \(summary)"); exit(70)
            default: break
            }
        }
        let report = await decoder.closeAndReport(session: session)
        print("frames_written=\(written) eos=\(sawEOS) leaks=\(report?.leakedHandles.count ?? -1)")
        if written == wantFrames && sawEOS && (report?.leakedHandles.isEmpty ?? false) {
            print("FRAME_DUMP_PASS frames=\(written)")
        } else {
            print("FRAME_DUMP_FAIL frames=\(written)")
            exit(71)
        }
    }
}
