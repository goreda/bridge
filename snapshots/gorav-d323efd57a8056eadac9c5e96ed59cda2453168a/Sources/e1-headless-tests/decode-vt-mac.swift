import Foundation
#if os(macOS) && E1_WITH_VT
import CoreMedia
import CoreVideo
import VideoToolbox
import CFFmpeg

// E1Headless DECODE-VT leg (macOS, opt-in compile flag E1_WITH_VT):
// decode the same lab-demuxed h264 packets through a real VideoToolbox
// VTDecompressionSession and assert parity against a second software
// avcodec pass: frame count, pts set, geometry, and per-plane pixel
// identity (h264 decode is deterministic; Y/U/V bytes must match exactly,
// NV12 output deinterleaved into I420 order for the digest). Parity
// EVIDENCE only - no VT acceptance, no host-integration claim. The
// software avcodec path in main.swift is untouched; without the flag (or
// off macOS) the leg is typed UNRUN. Native first compile + run is
// goreda's mac CI.

private func fnv1a(_ base: UnsafePointer<UInt8>, count: Int, seed: UInt64) -> UInt64 {
    var h = seed
    for i in 0..<count { h ^= UInt64(base[i]); h &*= 1099511628211 }
    return h
}

private func swPlaneDigest(_ f: UnsafeMutablePointer<AVFrame>) -> UInt64 {
    let w = Int(f.pointee.width), h = Int(f.pointee.height)
    var d: UInt64 = 14695981039346656037
    // yuv420p: row-wise over meaningful bytes (stride padding excluded),
    // U plane fully before V plane.
    let planes: [(UnsafePointer<UInt8>, Int, Int, Int)] = [
        (UnsafePointer(f.pointee.data.0!), Int(f.pointee.linesize.0), w, h),
        (UnsafePointer(f.pointee.data.1!), Int(f.pointee.linesize.1), w / 2, h / 2),
        (UnsafePointer(f.pointee.data.2!), Int(f.pointee.linesize.2), w / 2, h / 2),
    ]
    for (base, stride, pw, ph) in planes {
        for row in 0..<ph { d = fnv1a(base + row * stride, count: pw, seed: d) }
    }
    return d
}

private func vtPlaneDigest(_ pb: CVPixelBuffer) -> UInt64? {
    CVPixelBufferLockBaseAddress(pb, CVPixelBufferLockFlags.readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, CVPixelBufferLockFlags.readOnly) }
    let fmt = CVPixelBufferGetPixelFormatType(pb)
    let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
    var d: UInt64 = 14695981039346656037
    guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
    let yStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
    let yPtr = yBase.assumingMemoryBound(to: UInt8.self)
    for row in 0..<h { d = fnv1a(yPtr + row * yStride, count: w, seed: d) }
    if fmt == kCVPixelFormatType_420YpCbCr8Planar || fmt == kCVPixelFormatType_420YpCbCr8PlanarFullRange {
        for plane in 1...2 {
            guard let b = CVPixelBufferGetBaseAddressOfPlane(pb, plane) else { return nil }
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, plane)
            let ptr = b.assumingMemoryBound(to: UInt8.self)
            for row in 0..<(h / 2) { d = fnv1a(ptr + row * stride, count: w / 2, seed: d) }
        }
        return d
    }
    if fmt == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange || fmt == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange {
        guard let uvBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1) else { return nil }
        let uvStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        let uvPtr = uvBase.assumingMemoryBound(to: UInt8.self)
        // Deinterleave NV12 into I420 order: the full U plane (rows in
        // order), then the full V plane, matching swPlaneDigest byte order.
        var uAll = [UInt8](); uAll.reserveCapacity(w * h / 4)
        var vAll = [UInt8](); vAll.reserveCapacity(w * h / 4)
        for row in 0..<(h / 2) {
            let rowPtr = uvPtr + row * uvStride
            for x in 0..<(w / 2) { uAll.append(rowPtr[2 * x]); vAll.append(rowPtr[2 * x + 1]) }
        }
        d = uAll.withUnsafeBufferPointer { fnv1a($0.baseAddress!, count: $0.count, seed: d) }
        d = vAll.withUnsafeBufferPointer { fnv1a($0.baseAddress!, count: $0.count, seed: d) }
        return d
    }
    return nil
}

private final class VTCollector: @unchecked Sendable {
    let lock = NSLock()
    var frames: [(ptsUs: Int64, pb: CVPixelBuffer)] = []
    var failed = false
    var status: OSStatus = noErr
}

private let vtOutputCallback: VTDecompressionOutputCallback = { refCon, _, status, _, imageBuffer, pts, _ in
    guard let refCon else { return }
    let c = Unmanaged<VTCollector>.fromOpaque(refCon).takeUnretainedValue()
    c.lock.lock(); defer { c.lock.unlock() }
    if status != noErr { c.failed = true; c.status = status; return }
    guard let pb = imageBuffer else { c.failed = true; return }
    // No manual CVBufferRetain: Swift ARC manages CF objects; appending
    // retains for the collection's lifetime.
    let ptsUs = pts.timescale != 0 ? pts.value * 1_000_000 / Int64(pts.timescale) : -1
    c.frames.append((ptsUs, pb))
}

private func parseAvcC(_ d: [UInt8]) -> (sps: [[UInt8]], pps: [[UInt8]], nalLen: Int)? {
    guard d.count >= 8, d[0] == 1 else { return nil }
    let nalLen = Int(d[4] & 0x03) + 1
    var off = 5
    let numSPS = Int(d[off] & 0x1F); off += 1
    var sps: [[UInt8]] = []
    for _ in 0..<numSPS {
        guard off + 2 <= d.count else { return nil }
        let n = (Int(d[off]) << 8) | Int(d[off + 1]); off += 2
        guard off + n <= d.count else { return nil }
        sps.append(Array(d[off..<off + n])); off += n
    }
    guard off < d.count else { return nil }
    let numPPS = Int(d[off]); off += 1
    var pps: [[UInt8]] = []
    for _ in 0..<numPPS {
        guard off + 2 <= d.count else { return nil }
        let n = (Int(d[off]) << 8) | Int(d[off + 1]); off += 2
        guard off + n <= d.count else { return nil }
        pps.append(Array(d[off..<off + n])); off += n
    }
    return (sps, pps, nalLen)
}

func vtDecodeParity(packets: [CompressedPacket], avcC: [UInt8], expectW: Int, expectH: Int) {
    guard let cfg = parseAvcC(avcC), !cfg.sps.isEmpty, !cfg.pps.isEmpty else {
        fail("vt: avcC parameter-set parse failed")
    }
    if cfg.nalLen != 4 { fail("vt: avcC NAL length size \(cfg.nalLen) != 4") }
    let sps = cfg.sps[0], pps = cfg.pps[0]
    var rc: OSStatus = noErr
    var fd: CMFormatDescription?
    sps.withUnsafeBufferPointer { spsBuf in
        pps.withUnsafeBufferPointer { ppsBuf in
            var ptrs: [UnsafePointer<UInt8>] = [spsBuf.baseAddress!, ppsBuf.baseAddress!]
            var sizes: [Int] = [sps.count, pps.count]
            rc = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: nil, parameterSetCount: 2,
                parameterSetPointers: &ptrs, parameterSetSizes: &sizes,
                nalUnitHeaderLength: 4, formatDescriptionOut: &fd)
        }
    }
    guard rc == noErr, let formatDescription = fd else { fail("vt: format description create rc=\(rc)") }
    let collector = VTCollector()
    var cbRec = VTDecompressionOutputCallbackRecord(
        decompressionOutputCallback: vtOutputCallback,
        decompressionOutputRefCon: Unmanaged.passUnretained(collector).toOpaque())
    var session: VTDecompressionSession?
    rc = VTDecompressionSessionCreate(
        allocator: nil, formatDescription: formatDescription,
        decoderSpecification: nil, imageBufferAttributes: nil,
        outputCallback: &cbRec, decompressionSessionOut: &session)
    guard rc == noErr, let session else { fail("vt: session create rc=\(rc)") }
    defer { VTDecompressionSessionInvalidate(session) }
    for p in packets {
        var bb: CMBlockBuffer?
        var brc = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: p.bytes.count,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
            dataLength: p.bytes.count, flags: CMBlockBufferFlags(kCMBlockBufferAssureMemoryNowFlag),
            blockBufferOut: &bb)
        guard brc == noErr, let block = bb else { fail("vt: block buffer rc=\(brc)") }
        brc = p.bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return noErr }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block,
                                                 offsetIntoDestination: 0, dataLength: p.bytes.count)
        }
        guard brc == noErr else { fail("vt: block replace rc=\(brc)") }
        var timing = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTimeMake(value: p.ptsUs, timescale: 1_000_000),
            decodeTimeStamp: CMTimeMake(value: p.dtsUs, timescale: 1_000_000))
        var size = p.bytes.count
        var sb: CMSampleBuffer?
        brc = CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: formatDescription,
            sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sb)
        guard brc == noErr, let sample = sb else { fail("vt: sample buffer rc=\(brc)") }
        brc = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample,
                                                flags: VTDecodeFrameFlags(),
                                                frameRefcon: nil, infoFlagsOut: nil)
        if brc != noErr { fail("vt: decode frame rc=\(brc)") }
    }
    VTDecompressionSessionFinishDelayedFrames(session)
    VTDecompressionSessionWaitForAsynchronousFrames(session)
    if collector.failed { fail("vt: output callback status=\(collector.status)") }

    // Reference: a second software avcodec pass over the same packets.
    guard let codec = avcodec_find_decoder(AV_CODEC_ID_H264) else { fail("vt-ref: avcodec_find_decoder -> nil") }
    var rctx = avcodec_alloc_context3(codec)
    guard rctx != nil else { fail("vt-ref: alloc -> nil") }
    rctx!.pointee.extradata = UnsafeMutablePointer<UInt8>(OpaquePointer(av_malloc(avcC.count)))
    memcpy(rctx!.pointee.extradata, avcC, avcC.count)
    rctx!.pointee.extradata_size = Int32(avcC.count)
    if avcodec_open2(rctx, codec, nil) < 0 { fail("vt-ref: open2 failed") }
    var rframe = av_frame_alloc()
    guard rframe != nil else { fail("vt-ref: frame alloc -> nil") }
    var refDigest: [Int64: UInt64] = [:]
    func drainRef() {
        while true {
            let rrc = avcodec_receive_frame(rctx, rframe!)
            if rrc == 0 {
                refDigest[rframe!.pointee.pts] = swPlaneDigest(rframe!)
            } else if rrc == gorav_av_err_eagain() || rrc == gorav_av_err_eof() { return }
            else { fail("vt-ref: receive rc=\(rrc)") }
        }
    }
    for p in packets {
        var pkt = av_packet_alloc()
        guard pkt != nil, av_new_packet(pkt, Int32(p.bytes.count)) == 0 else { fail("vt-ref: packet alloc failed") }
        p.bytes.withUnsafeBufferPointer { buf in
            if let dst = pkt!.pointee.data, let srcp = buf.baseAddress { memcpy(dst, srcp, buf.count) }
        }
        pkt!.pointee.pts = p.ptsUs
        pkt!.pointee.dts = p.dtsUs
        var src = avcodec_send_packet(rctx, pkt)
        if src == gorav_av_err_eagain() { drainRef(); src = avcodec_send_packet(rctx, pkt) }
        av_packet_free(&pkt)
        if src < 0 { fail("vt-ref: send rc=\(src)") }
        drainRef()
    }
    _ = avcodec_send_packet(rctx, nil)
    drainRef()
    av_frame_free(&rframe)
    avcodec_free_context(&rctx)

    let frames = collector.frames
    if frames.count != packets.count { fail("vt: decoded \(frames.count) frames != packets \(packets.count)") }
    var vtByPts: [Int64: CVPixelBuffer] = [:]
    for (pts, pb) in frames {
        if pts < 0 { fail("vt: frame with invalid pts") }
        if vtByPts[pts] != nil { fail("vt: duplicate pts \(pts)") }
        vtByPts[pts] = pb
    }
    if Set(vtByPts.keys) != Set(refDigest.keys) { fail("vt: presentation set != sw reference set") }
    if Set(vtByPts.keys) != Set(packets.map { $0.ptsUs }) { fail("vt: presentation set != demuxed set") }
    var parity = 0
    for (pts, pb) in vtByPts {
        let w = CVPixelBufferGetWidth(pb), hgt = CVPixelBufferGetHeight(pb)
        if w != expectW || hgt != expectH { fail("vt: geometry \(w)x\(hgt) != \(expectW)x\(expectH)") }
        guard let vd = vtPlaneDigest(pb), let rd = refDigest[pts] else {
            fail("vt: unsupported pixel format or missing reference at pts=\(pts)")
        }
        if vd != rd { fail("vt: plane digest mismatch at pts=\(pts)") }
        parity += 1
    }
    print("E1-HEADLESS decode_vt frames=\(frames.count) pts_set=demux_set plane_parity=\(parity)/\(frames.count) (VideoToolbox vs sw avcodec; parity evidence only, no VT acceptance)")
}
#endif
