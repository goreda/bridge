// AUTHORED NEW (2026-11-16, P30/W3, arch-197a item 2 + arch-197c).
// e1-vt-live-gate: the CI proof for the VT zero-copy lane. Drives the REAL
// live path over one fixture:
//   FFmpegSoftwareDecoder (armed GORAV_VT_ZEROCOPY=1, ffmpeg VT hwaccel)
//     -> ShellFrameSource (vtZeroCopyPayload first try, typed fallbacks)
//     -> MetalRenderer.upload(vtFrame:) (CVMetalTextureCache, offscreen)
// and asserts the gate the architect named: VTRECEIPT hwdec=videotoolbox,
// cpuCopies=0, cpuYUVtoRGB=0, iosurface>0, EVERY frame presented zero-copy,
// no fallback reason. Frame 1 round-trips readbackNative: the converted
// slot texture renders + reads back, so the GPU chain is proven EXECUTED,
// not merely encoded. The exact VTRECEIPT line is printed for ops.
// Any typed fallback is a gate FAILURE with the receipt's reason named.
// Off macOS (+Metal+CoreVideo) the binary is typed UNRUN (exit 77), the
// e1-headless convention.
import Foundation

#if os(macOS) && canImport(AppKit) && canImport(Metal) && canImport(CoreVideo)
import GorAVCore
import GorAVFFmpegAdapter
import GorAVMacShell
import GorAVMetalPresenter
import GorAVPlaybackCore

func fail(_ msg: String) -> Never {
    print("E1-VT-LIVE-GATE FAIL: \(msg)")
    Foundation.exit(1)
}

let args = CommandLine.arguments
guard args.count == 2, !args[1].isEmpty else {
    FileHandle.standardError.write(Data("usage: e1-vt-live-gate <fixture>\n".utf8))
    Foundation.exit(2)
}
let fixture = args[1]
// Arm the zero-copy receive path for THIS process only (AdmissionTable
// policy: GORAV_VT_ZEROCOPY=1, disable-hw unset).
setenv("GORAV_VT_ZEROCOPY", "1", 1)

let gateSem = DispatchSemaphore(value: 0)
Task {
    defer { gateSem.signal() }
    guard let issued = PlaybackIdentityAuthority.shared.issue() else { fail("identity issue refused") }
    let dec = FFmpegSoftwareDecoder()
    do {
        try await dec.open(source: SourceDescriptor(id: fixture, kind: .local, seekable: true), session: issued)
    } catch { fail("open \(fixture): \(error)") }
    let src = ShellFrameSource(decoder: dec, session: issued)
    let renderer: MetalRenderer
    do { renderer = try MetalRenderer(contract: .sdrDefault, outputTransform: .identity) } catch {
        fail("renderer init: \(error)")
    }
    guard renderer.beginSession(sessionID: "e1-vt-live-gate", generation: 1) else {
        fail("renderer beginSession refused")
    }
    var frames = 0
    var seq: UInt64 = 0
    var readbackChecked = false
    loop: while true {
        switch await src.nextEvent() {
        case .frame(let sf):
            frames += 1
            guard let vt = sf.vtPayload else {
                fail("frame \(frames) carried NO VT payload (digest=\(sf.digest)) - the zero-copy path was not taken")
            }
            seq += 1
            let fid = FrameIdentity(sessionID: "e1-vt-live-gate", sessionGeneration: 1,
                                    sequence: seq, surfaceRevision: 0,
                                    ptsSeconds: sf.ptsSeconds)
            let outcome = renderer.upload(vtFrame: vt, identity: fid)
            guard case .okZeroCopy = outcome else { fail("VT upload rejected frame \(frames): \(outcome)") }
            if !readbackChecked {
                readbackChecked = true
                // The conversion pass's output renders + reads back: the
                // whole GPU chain (cache -> textures -> shader -> slot)
                // executed for a real VT frame.
                guard renderer.readbackNative(identity: fid) != nil else {
                    fail("readback of the VT-uploaded frame failed")
                }
            }
        case .temporarilyUnavailable:
            continue
        case .ended:
            break loop
        case .failed(let code):
            fail("source failed code=\(code)")
        }
    }
    guard frames > 0 else { fail("zero frames decoded") }
    guard let report = await dec.l3RunReport(session: issued), let hw = report.hardware else {
        fail("no hardware receipt for an armed session")
    }
    print("E1-VT-LIVE-GATE \(hw.receiptLine())")
    var bad: [String] = []
    if !hw.activeCurrent { bad.append("hwdec!=videotoolbox") }
    if hw.cpuFrameCopies != 0 { bad.append("cpuCopies=\(hw.cpuFrameCopies)") }
    if hw.cpuYUVtoRGB != 0 { bad.append("cpuYUVtoRGB=\(hw.cpuYUVtoRGB)") }
    if hw.ioSurfaceBackedFrames <= 0 { bad.append("iosurface=0") }
    if hw.vtFramesZeroCopy != frames { bad.append("vtZeroCopy=\(hw.vtFramesZeroCopy) frames=\(frames)") }
    if let reason = hw.fallbackReason { bad.append("fallback=\(reason)") }
    if !bad.isEmpty { fail(bad.joined(separator: " ")) }
    print("E1-VT-LIVE-GATE PASS frames=\(frames) vtZeroCopy=\(hw.vtFramesZeroCopy) iosurface=\(hw.ioSurfaceBackedFrames)")
    Foundation.exit(0)
}
gateSem.wait()
Foundation.exit(3) // unreachable: the task always exits or signals-then-hangs is a gate failure
#else
print("E1-VT-LIVE-GATE UNRUN: macOS + Metal + CoreVideo required")
Foundation.exit(77)
#endif
