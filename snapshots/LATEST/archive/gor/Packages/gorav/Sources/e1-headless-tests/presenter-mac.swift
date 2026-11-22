import Foundation
import Dispatch
#if os(macOS)
import CFFmpeg
import GorAVMetalPresenter

// E1Headless P-E1A presenter leg (macOS only; owned by the E1 lane, not by
// goreda's audio branch). Renderer-level offscreen sink, single pass with
// the decode/scheduler loop: each .present decision converts the decoded
// frame yuv420p -> RGBA8 (swscale), MetalRenderer upload + readbackNative
// with per-frame sha256 identity at 1:1 - the MetalCheck section-A/J
// offscreen pattern driven by real E1 decode output. Offscreen evidence
// only, never scanout proof. First compile + run is goreda's mac CI (the
// code is os(macOS)-guarded; Linux keeps typed UNRUN).

private var presenterConfirmed = 0
private var presenterTimedUploads = 0
private var presenterVerifying = true
private var verificationDigests: [String] = []
private var presenterSeq: UInt64 = 0
private var presenterRenderer: MetalRenderer?

// SWS_BILINEAR is a C macro (1 << 1 = 2); C macros do not import into Swift.
// The sws context is cached across frames (fixed geometry in this harness;
// recreated if w/h ever change) and the output buffer skips the wasted
// zero-init (sws_scale overwrites every pixel) - output bytes are identical
// to the previous per-call create/free + zeroed-buffer version.
// SwsContext is a bare forward declaration in FFmpeg 7.1 headers (opaque);
// Swift imports it as OpaquePointer, matching main.swift's swr pattern.
private var cachedSWS: OpaquePointer?
private var cachedSWSW = 0
private var cachedSWSH = 0

func yuvToRGBA8(_ f: UnsafeMutablePointer<AVFrame>, _ w: Int, _ h: Int) -> [UInt8] {
    if cachedSWS == nil || cachedSWSW != w || cachedSWSH != h {
        if let old = cachedSWS { sws_freeContext(old) }
        guard let c = sws_getContext(Int32(w), Int32(h), AV_PIX_FMT_YUV420P,
                                     Int32(w), Int32(h), AV_PIX_FMT_RGBA,
                                     2, nil, nil, nil) else { fail("sws_getContext -> nil") }
        cachedSWS = c; cachedSWSW = w; cachedSWSH = h
    }
    let sws = cachedSWS!
    return [UInt8](unsafeUninitializedCapacity: w * h * 4) { db, initializedCount in
        var dstSlice: [UnsafeMutablePointer<UInt8>?] = [db.baseAddress]
        var dstStride: [Int32] = [Int32(w * 4)]
        var srcSlice: [UnsafePointer<UInt8>?] = [
            UnsafeRawPointer(f.pointee.data.0)?.assumingMemoryBound(to: UInt8.self),
            UnsafeRawPointer(f.pointee.data.1)?.assumingMemoryBound(to: UInt8.self),
            UnsafeRawPointer(f.pointee.data.2)?.assumingMemoryBound(to: UInt8.self)]
        var srcStride: [Int32] = [f.pointee.linesize.0, f.pointee.linesize.1, f.pointee.linesize.2]
        _ = sws_scale(sws, &srcSlice, &srcStride, 0, Int32(h), &dstSlice, &dstStride)
        initializedCount = w * h * 4
    }
}

func presenterBegin() {
    do {
        let r = try MetalRenderer() // .sdrDefault contract + .identity output transform
        guard r.beginSession(sessionID: "e1-headless", generation: 1) else { fail("presenter beginSession refused") }
        presenterRenderer = r
    } catch { fail("presenter init threw: \(error)") }
}

// Upload+verify half of the offscreen present, given an already-converted
// RGBA buffer (shared with the embed leg when both run: the frame is
// converted ONCE per present decision).
@discardableResult
func presenterPresentConverted(rgba: [UInt8], w: Int, h: Int, ptsSeconds: Double) -> (uploadMs: Double, readbackMs: Double) {
    guard let r = presenterRenderer else { return (0, 0) }
    let t1 = ProcessInfo.processInfo.systemUptime
    presenterSeq += 1
    let fid = FrameIdentity(sessionID: "e1-headless", sessionGeneration: 1,
                            sequence: presenterSeq, surfaceRevision: 0,
                            ptsSeconds: ptsSeconds)
    switch r.upload(rgba: rgba, width: w, height: h, identity: fid) {
    case .ok(let sha):
        let t2 = ProcessInfo.processInfo.systemUptime
        if presenterVerifying {
            guard let rb = r.readbackNative(identity: fid) else { fail("presenter readback unavailable frame \(presenterSeq)") }
            let t3 = ProcessInfo.processInfo.systemUptime
            guard rb.sha256 == sha else { fail("presenter readback sha != upload sha frame \(presenterSeq)") }
            presenterConfirmed += 1
            verificationDigests.append(sha)
            return ((t2 - t1) * 1000, (t3 - t2) * 1000)
        }
        guard presenterTimedUploads < verificationDigests.count,
              verificationDigests[presenterTimedUploads] == sha else {
            fail("presenter timed upload differs from verified frame \(presenterTimedUploads)")
        }
        presenterTimedUploads += 1
        return ((t2 - t1) * 1000, 0)
    default:
        fail("presenter upload rejected frame \(presenterSeq)")
    }
}

// Called at the scheduler's .present decision point, frame still owned by
// the decode loop (unref happens there after this returns).
@discardableResult
func presenterPresentFrame(_ frame: UnsafeMutablePointer<AVFrame>, ptsSeconds: Double) -> (convertMs: Double, uploadMs: Double, readbackMs: Double) {
    let w = Int(frame.pointee.width), h = Int(frame.pointee.height)
    let t0 = ProcessInfo.processInfo.systemUptime
    let rgba = yuvToRGBA8(frame, w, h)
    let convMs = (ProcessInfo.processInfo.systemUptime - t0) * 1000
    let (upMs, rbMs) = presenterPresentConverted(rgba: rgba, w: w, h: h, ptsSeconds: ptsSeconds)
    return (convMs, upMs, rbMs)
}

func presenterFinishVerification(expectedFrames: Int) {
    guard presenterVerifying, presenterConfirmed == expectedFrames, expectedFrames > 240 else {
        fail("presenter verification count \(presenterConfirmed) != decoded \(expectedFrames)")
    }
    presenterVerifying = false
    print("E1-HEADLESS presenter verification preflight=\(presenterConfirmed) upload+readback 1:1 (untimed oracle, no audio clock)")
}

func presenterAssertAndReport() {
    guard !presenterVerifying, presenterTimedUploads == presenterConfirmed else {
        fail("presenter timed uploads \(presenterTimedUploads) != verified frames \(presenterConfirmed)")
    }
    if presenterConfirmed <= 240 { fail("presenter confirmed \(presenterConfirmed) <= 240") }
    print("E1-HEADLESS presenter confirmed=\(presenterConfirmed) upload+readback 1:1 offscreen")
}

// Seal + close only; the combined <300 ms close measurement (with audio on
// E1_WITH_AUDIO_OUT runs) is owned by main.swift's CLOSE stage.
func presenterClose() {
    if let r = presenterRenderer {
        _ = r.seal(maxBarrierSeconds: 2.0)
        let sem = DispatchSemaphore(value: 0)
        Task { _ = await r.close(maxWaitSeconds: 2.0); sem.signal() }
        sem.wait()
    }
}
#endif
