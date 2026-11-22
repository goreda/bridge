// L4 (block 168 m2): VideoToolbox decode with measured software fallback -
// Linux-host decision/receipt checks. Off-Darwin the C shim returns -2 and
// decode proceeds in software; these tests pin THAT contract plus the
// admission matrix (168: h264/hevc attempt VT, mpeg4/av1 stay software).
// Native VT execution is the owner-kit leg (m2 kit 11-06) and is NEVER
// claimed from this host.
import Foundation
import CFFmpeg
import GorAVCore
import GorAVFFmpegAdapter

@main struct L4HWDecodeTests {
    static func main() async throws {
        var failures = 0
        func check(_ cond: Bool, _ name: String) {
            print("\(cond ? "PASS" : "FAIL") \(name)")
            if !cond { failures += 1 }
        }

        // 1. Admission matrix.
        check(AdmissionTable.shouldAttemptHardware(videoCodec: "h264", environment: [:]),
              "admit h264 -> VT attempt")
        check(AdmissionTable.shouldAttemptHardware(videoCodec: "hevc", environment: [:]),
              "admit hevc -> VT attempt")
        check(!AdmissionTable.shouldAttemptHardware(videoCodec: "mpeg4", environment: [:]),
              "mpeg4 stays software (VT has no mpeg4 hwaccel)")
        check(!AdmissionTable.shouldAttemptHardware(videoCodec: "av1", environment: [:]),
              "av1 stays software-by-policy")
        check(!AdmissionTable.shouldAttemptHardware(videoCodec: "h264", environment: ["GORAV_L3_DISABLE_HW": "1"]),
              "GORAV_L3_DISABLE_HW=1 forces software")

        #if os(Linux)
        // 2. Off-Darwin attach receipt: attempted, attachResult -2, no hw
        // negotiation claimed.
        guard let codec = avcodec_find_decoder(AV_CODEC_ID_H264),
              let ctx = avcodec_alloc_context3(codec) else {
            print("FAIL h264 decoder context alloc")
            Foundation.exit(1)
        }
        let hw = L3HardwareSession()
        let attempted = hw.attachIfAdmitted(codecContext: ctx, videoCodecName: "h264", environment: [:])
        check(!attempted, "off-Darwin attach returns false")
        check(hw.receipt.attempted, "receipt.attempted recorded")
        check(hw.receipt.attachResult == -2, "receipt.attachResult == -2 (off-Darwin)")
        check(!hw.receipt.activeEver && !hw.receipt.activeCurrent, "no hw negotiation claimed off-Darwin")
        do { var c: UnsafeMutablePointer<AVCodecContext>? = ctx; avcodec_free_context(&c) }

        // 3. Integration: admitted h264 fixture decodes fully in software
        // with the VT policy live - the admission change never breaks the
        // software path, and the run report carries the off-Darwin attempt.
        let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        let path = root + "/fixtures/m1/synthetic-h264-aac.mp4"
        let sid = SessionID(uncheckedEpoch: 900)
        let v = FFmpegSoftwareDecoder()
        try v.pinLocalRoots([root])
        try await v.open(source: SourceDescriptor(id: path, kind: .local, seekable: true), session: sid)
        var count = 0, eos = false, decodeFailed = false
        while let ev = await v.nextEvent(session: sid) {
            switch ev {
            case .frameDecoded(let f):
                count += 1
                await v.releaseFrame(handle: f.handle, session: sid)
            case .endOfStream:
                eos = true
            case .failed(let c, let m):
                print("FAIL decode failed \(c) \(m)")
                failures += 1
                decodeFailed = true
                eos = true
            default:
                break
            }
            if decodeFailed { break }
        }
        check(count == 75 && eos && !decodeFailed, "h264 fixture decodes 75 frames to EOS with VT policy live")
        _ = await v.closeAndReport(session: sid)
        if let rep = await v.l3RunReport(session: sid), let hwrep = rep.hardware {
            check(hwrep.attempted, "run report: VT attempted on admitted h264")
            check(hwrep.attachResult == -2, "run report: attachResult -2 off-Darwin")
            check(hwrep.hardwareFrames == 0 && hwrep.softwareFallbacks == 0,
                  "run report: zero hw frames, zero fallbacks (clean software decode)")
        } else {
            check(false, "run report hardware receipt present post-close")
        }
        #endif

        // 4. W1 (arch-196z E1 / P30): zero-copy receipt schema + counters.
        // A synthetic VT-format AVFrame exercises processReceivedFrameZeroCopy
        // off-Darwin (the format constant is platform-independent); no VT
        // execution is claimed from this host.
        do {
            let hw = L3HardwareSession()
            // defaults keep old producers valid
            check(hw.receipt.vtFramesZeroCopy == 0 && hw.receipt.cpuFrameCopies == 0
                  && hw.receipt.cpuYUVtoRGB == 0 && hw.receipt.ioSurfaceBackedFrames == 0
                  && hw.receipt.fallbackReason == nil, "W1 schema defaults zero/nil")
            var vtFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
            check(vtFrame != nil, "W1 synthetic frame alloc")
            vtFrame!.pointee.format = gorav_l3_pixfmt_videotoolbox()
            switch hw.processReceivedFrameZeroCopy(&vtFrame) {
            case .ok: break
            default: check(false, "W1 zero-copy VT frame passes through")
            }
            check(hw.receipt.vtFramesZeroCopy == 1, "W1 vtFramesZeroCopy counted")
            check(vtFrame != nil, "W1 zero-copy does NOT free/replace the frame")
            if vtFrame != nil { av_frame_free(&vtFrame) }
            var swFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
            swFrame!.pointee.format = 0 // AV_PIX_FMT_YUV420P
            switch hw.processReceivedFrameZeroCopy(&swFrame) {
            case .ok: break
            default: check(false, "W1 software frame passes through zero-copy path")
            }
            check(hw.receipt.vtFramesZeroCopy == 1, "W1 software frame not counted as VT")
            if swFrame != nil { av_frame_free(&swFrame) }
            var nilFrame: UnsafeMutablePointer<AVFrame>? = nil
            if case .refused = hw.processReceivedFrameZeroCopy(&nilFrame) {} else {
                check(false, "W1 nil frame typed refusal")
            }
            hw.noteCPUYUVtoRGB()
            hw.noteCPUYUVtoRGB(2)
            hw.noteIOSurfaceBackedFrames()
            hw.noteFallbackReason("vt-decode-failed")
            hw.noteFallbackReason("second-reason")
            check(hw.receipt.cpuYUVtoRGB == 3 && hw.receipt.ioSurfaceBackedFrames == 1,
                  "W1 present-path counters accumulate")
            check(hw.receipt.fallbackReason == "vt-decode-failed",
                  "W1 first fallback reason sticks")
            check(hw.receiptLine() == "VTRECEIPT hwdec=no vtZeroCopy=1 cpuCopies=0 cpuYUVtoRGB=3 iosurface=1 fallback=vt-decode-failed hwFrames=0 transferErrors=0 swFallbacks=0",
                  "W1 receipt line exact field order: \(hw.receiptLine())")
        }

        // 5. W2 (arch-197b): zero-copy arm policy + transfer-on-demand.
        do {
            // Policy matrix (AdmissionTable.shouldArmVTZeroCopy).
            check(!AdmissionTable.shouldArmVTZeroCopy(environment: [:]), "W2 default is unarmed")
            check(AdmissionTable.shouldArmVTZeroCopy(environment: ["GORAV_VT_ZEROCOPY": "1"]), "W2 env arms")
            check(!AdmissionTable.shouldArmVTZeroCopy(environment: ["GORAV_VT_ZEROCOPY": "0"]), "W2 explicit 0 does not arm")
            check(!AdmissionTable.shouldArmVTZeroCopy(environment: ["GORAV_VT_ZEROCOPY": "1", "GORAV_L3_DISABLE_HW": "1"]), "W2 disable-hw wins over arm")
            let hw = L3HardwareSession()
            check(!hw.zeroCopyArmed, "W2 session starts unarmed")
            hw.armZeroCopy(environment: ["GORAV_VT_ZEROCOPY": "1"])
            check(hw.zeroCopyArmed, "W2 armZeroCopy arms under env")
            let hwNo = L3HardwareSession()
            hwNo.armZeroCopy(environment: [:])
            check(!hwNo.zeroCopyArmed, "W2 armZeroCopy inert without env")
            // Armed session: software frames pass the zero-copy receive
            // untouched and uncounted (arming is inert for software decode).
            var swFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
            swFrame!.pointee.format = 0 // AV_PIX_FMT_YUV420P
            switch hw.processReceivedFrameZeroCopy(&swFrame) {
            case .ok: break
            default: check(false, "W2 armed session passes software frame")
            }
            check(hw.receipt.vtFramesZeroCopy == 0 && hw.receipt.cpuFrameCopies == 0,
                  "W2 armed software frame: no VT count, no CPU copy")
            if swFrame != nil { av_frame_free(&swFrame) }
            // transferToSoftwareCopy off-Darwin: the REAL
            // av_hwframe_transfer_data fails on a synthetic frame (no
            // hw_frames_ctx) - typed nil, cpuFrameCopies NOT counted, the
            // shim's transfer error is visible in the receipt.
            var vtFrame: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
            vtFrame!.pointee.format = gorav_l3_pixfmt_videotoolbox()
            let transferred = hw.transferToSoftwareCopy(vtFrame!)
            check(transferred == nil, "W2 off-Darwin transfer fails typed, no fake software frame")
            check(hw.receipt.cpuFrameCopies == 0, "W2 failed transfer is not counted as a CPU copy")
            check(hw.receipt.transferErrors == 1, "W2 failed transfer is counted as a transfer error")
            if vtFrame != nil { av_frame_free(&vtFrame) }
            if transferred != nil { var t = transferred; av_frame_free(&t) }
            hw.noteCPUFrameCopies()
            check(hw.receipt.cpuFrameCopies == 1, "W2 noteCPUFrameCopies accumulates")
        }

        if failures > 0 {
            print("L4_HWDECODE_TESTS FAIL failures=\(failures)")
            Foundation.exit(1)
        }
        print("L4_HWDECODE_TESTS_PASS")
    }
}
