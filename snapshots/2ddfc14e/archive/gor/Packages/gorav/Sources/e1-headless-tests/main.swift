import Foundation
import Dispatch
import BridgeDemux
import AudioMasterScheduler
import CFFmpeg
import GorAVPlaybackCore
import GorAVFFmpegAdapter

// E1Headless (block 189g item 1, fixture per 189h): fixtures/e1-h264-aac-10s.mp4
// through lab-a demux -> h264 sw decode -> p-a2 scheduler -> g3 presenter
// offscreen -> audio out. Asserts: frames presented > 240, real audio
// callbacks, close < 300 ms; mac CI. clip-bbb-10s.mov remains accepted as a
// demux-regression fixture only (no mp4v decoder per 189h: typed NOT_RUN).
//
// Stage status (default architect to review):
//   DEMUX      REAL - container-sniffing BridgeDemux MP4/Matroska.
//   MKV        REAL AVC/AAC CodecPrivate decode and PGS event/oracle legs.
//   SCHEDULER  Full every-frame SHA readback preflight, then timed replay;
//              exact timed-upload SHA equality, no maxLate tolerance change.
//   DECODE     REAL - packet-level software decode of the lab-demuxed h264
//              packets via CFFmpeg avcodec with the container's avcC record.
//              Single-pass pull: the decoder emits presentation order.
//   AUDIO      DEMUX-LEVEL ONLY - aac packet asserts; goreda owns AAC decode
//              and the 48 kHz feed in E1AudioOut (contract pending, Main 01:13).
//   SCHEDULER  REAL - vendored p-a2 AudioMasterScheduler; paced on goreda's
//              real audio clock under E1_WITH_AUDIO_OUT, perfect-clock
//              simulation otherwise.
//   PRESENTER  REAL on macOS (presenter-mac.swift), TYPED-UNRUN elsewhere.
//   AUDIO-OUT  REAL on mac CI with -Xswiftc -DE1_WITH_AUDIO_OUT against
//              goreda's landed E1AudioOut (cherry-pick of 88a46e7, verified
//              byte-identical): start(pcm:, sampleRate: 48000, channels: 2),
//              real AudioUnit render callbacks anchor the scheduler.
// Exit codes: 0 pass, 1 fail, 2 NOT_RUN, 77 UNRUN (typed-unlanded legs).
//
// 189k PERMANENT ENGINE RULE (owner block 189k via Main): the readiness
// ordering below is owned by ReadinessAnchorSession in GorAVPlaybackCore,
// not by this harness. The harness performs the real decode/present/clock
// work but moves through the engine's typed gates: the audio clock starts
// only after frame 0 is decoded AND presented (anchorPresentedNow ->
// requestClockStart), frame 0 takes no scheduler decision, and a pre-anchor
// clock start is a typed engine refusal (E1_SKIP_WARMUP witness). Seek
// ordering (flush, new anchor, clock restart) is engine state too; the
// POST-SEEK witness below exercises it. maxLate and all asserts unchanged.

let UNRUN: Int32 = 77
let NOT_RUN: Int32 = 2

func fail(_ msg: String) -> Never { print("E1-HEADLESS BAD: \(msg)"); Foundation.exit(1) }

let fixturePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/e1-h264-aac-10s.mp4"
guard FileManager.default.fileExists(atPath: fixturePath) else {
    print("E1-HEADLESS NOT_RUN: missing fixture \(fixturePath)")
    Foundation.exit(NOT_RUN)
}
let bytes = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: fixturePath)))
print("E1-HEADLESS fixture=\(fixturePath) bytes=\(bytes.count)")

// MARK: Container box walkers (config records the lab-a track API does not surface)
func be32(_ b: [UInt8], _ o: Int) -> Int { (Int(b[o]) << 24) | (Int(b[o+1]) << 16) | (Int(b[o+2]) << 8) | Int(b[o+3]) }
func boxType(_ b: [UInt8], _ o: Int) -> String { String(bytes: b[(o+4)..<(o+8)], encoding: .ascii) ?? "" }

func childBoxes(_ b: [UInt8], _ lo: Int, _ hi: Int) -> [(type: String, lo: Int, hi: Int)] {
    var out: [(String, Int, Int)] = []
    var pos = lo
    while pos + 8 <= hi {
        var size = be32(b, pos)
        var head = 8
        if size == 1 { size = (be32(b, pos + 8) << 32) | be32(b, pos + 12); head = 16 }
        if size < head || pos + size > hi { break }
        out.append((boxType(b, pos), pos + head, pos + size))
        pos += size
    }
    return out
}

func esdsExtradata(_ b: [UInt8], _ lo: Int, _ hi: Int) -> [UInt8]? {
    // esds body: 4 bytes version/flags, then expandable-length descriptor TLVs.
    var pos = lo + 4
    func tlv(_ at: Int) -> (tag: Int, body: Int, end: Int)? {
        guard at + 2 <= hi else { return nil }
        var p = at + 1, len = 0
        for _ in 0..<4 {
            let c = Int(b[p]); p += 1
            len = (len << 7) | (c & 0x7F)
            if c & 0x80 == 0 { break }
        }
        guard p + len <= hi else { return nil }
        return (Int(b[at]), p, p + len)
    }
    guard let es = tlv(pos) else { return nil }
    pos = es.body + 3 // ES_ID(2) + flags(1)
    guard let dc = tlv(pos) else { return nil }
    pos = dc.body + 13 // objectType(1)+streamType(1)+bufferSize(3)+maxBR(4)+avgBR(4)
    guard let ds = tlv(pos), ds.tag == 0x05 else { return nil }
    return Array(b[ds.body..<ds.end])
}

// Walk moov/trak/mdia/minf/stbl/stsd for a sample entry of `entryType`;
// VisualSampleEntry children at entry+78, AudioSampleEntry children at entry+28.
func sampleEntryChild(_ b: [UInt8], entryType: String, childType: String, audio: Bool) -> (child: (lo: Int, hi: Int), w: Int, h: Int)? {
    for top in childBoxes(b, 0, b.count) where top.type == "moov" {
        for trak in childBoxes(b, top.lo, top.hi) where trak.type == "trak" {
            for mdia in childBoxes(b, trak.lo, trak.hi) where mdia.type == "mdia" {
                for minf in childBoxes(b, mdia.lo, mdia.hi) where minf.type == "minf" {
                    for stbl in childBoxes(b, minf.lo, minf.hi) where stbl.type == "stbl" {
                        for stsd in childBoxes(b, stbl.lo, stbl.hi) where stsd.type == "stsd" {
                            var pos = stsd.lo + 8 // version/flags(4) + entry_count(4)
                            while pos + 8 <= stsd.hi {
                                let size = be32(b, pos)
                                guard size >= 8, pos + size <= stsd.hi else { return nil }
                                if boxType(b, pos) == entryType {
                                    let entry = pos + 8
                                    let w = audio ? 0 : (Int(b[entry+24]) << 8) | Int(b[entry+25])
                                    let h = audio ? 0 : (Int(b[entry+26]) << 8) | Int(b[entry+27])
                                    let childStart = entry + (audio ? 28 : 78)
                                    for child in childBoxes(b, childStart, pos + size) where child.type == childType {
                                        return ((child.lo, child.hi), w, h)
                                    }
                                    return nil
                                }
                                pos += size
                            }
                        }
                    }
                }
            }
        }
    }
    return nil
}

// MARK: Stage DEMUX (real)
// Container-sniffing (arch-197c lane c PGS seam): the MP4 shapes resolve to
// the same MP4Demuxer with identical packets; Matroska resolves to
// MKVDemuxer so the corpus PGS shape demuxes for real.
var demuxer = Demuxer()
let isMP4 = MP4Demuxer.looksLikeMP4(bytes)
let tracks: [DemuxTrack]
do { tracks = try demuxer.open(bytes) } catch { fail("demux open threw: \(error)") }
guard let videoTrack = tracks.first(where: { $0.kind == "video" }) else { fail("no video track") }
guard let audioTrack = tracks.first(where: { $0.kind == "audio" }) else { fail("no audio track") }
let subtitleTrack = tracks.first(where: { $0.kind == "subtitle" })
print("E1-HEADLESS demux tracks=\(tracks.map { "\($0.kind):\($0.codec)" }.joined(separator: ","))")

struct CompressedPacket { let bytes: [UInt8]; let ptsUs: Int64; let dtsUs: Int64 }
func us(_ t: RationalTime) -> Int64 { t.value * 1_000_000 / t.scale }
var packets: [CompressedPacket] = []
var audioPacketsList: [CompressedPacket] = []
var subtitlePackets: [(bytes: [UInt8], ptsUs: Int64)] = []
while let packet = try! demuxer.next() {
    if packet.trackID == videoTrack.id {
        guard let pts = packet.pts, let dts = packet.dts else { fail("video packet missing pts/dts") }
        packets.append(CompressedPacket(bytes: packet.bytes, ptsUs: us(pts), dtsUs: us(dts)))
    } else if packet.trackID == audioTrack.id {
        guard let pts = packet.pts, let dts = packet.dts else { fail("audio packet missing pts/dts") }
        audioPacketsList.append(CompressedPacket(bytes: packet.bytes, ptsUs: us(pts), dtsUs: us(dts)))
    } else if packet.trackID == subtitleTrack?.id {
        guard let pts = packet.pts else { fail("subtitle packet missing pts") }
        subtitlePackets.append((bytes: packet.bytes, ptsUs: us(pts)))
    }
}
if packets.count < 240 { fail("demuxed video packets \(packets.count) < 240") }
// DTS monotonicity is an invariant of the lab MP4Demuxer's decode-order
// emission. Matroska emits container order with dts=pts (B-frame shapes are
// non-monotonic); the MKV video legs are typed UNRUN below, so the check is
// MP4-only.
if isMP4 {
    for i in 1..<packets.count where packets[i].dtsUs < packets[i - 1].dtsUs {
        fail("video DTS non-monotonic at \(i): \(packets[i - 1].dtsUs) -> \(packets[i].dtsUs)")
    }
}
print("E1-HEADLESS demux video_packets=\(packets.count) audio_packets=\(audioPacketsList.count) subtitle_packets=\(subtitlePackets.count) dts_monotonic=OK")

// MARK: Stage SUBTITLE-PGS (real when a PGS track is present): LANDED
// LabPGSDecoder seam (arch-197c lane c second seam). REAL on every host -
// the decoder is pure Swift. Proof: event digests are byte-identical to the
// vendored C carrier (kits/b1-pgs parity recipe) on the same extracted
// stream; the e1-mkv-pgs.mkv values are pinned below.
if let subTrack = subtitleTrack {
    if subTrack.codec == "s_hdmv/pgs" {
        // Matroska stores PGS segments WITHOUT the .sup header: each stored
        // segment is type(1)+len(2)+body, the "PG"+pts+dts header is the
        // block's, reconstituted by ffmpeg's matroskadec on extraction
        // (verified: ffmpeg -c copy of this fixture yields the headed .sup).
        // The seam does the same reconstitution before feeding the
        // .sup-format decoder; the block pts (90 kHz) heads every segment.
        func reheadPGS(_ bytes: [UInt8], pts90k: UInt32) -> [UInt8]? {
            var out = [UInt8]()
            out.reserveCapacity(bytes.count + 16)
            var i = 0
            while i + 3 <= bytes.count {
                let segLen = Int(bytes[i + 1]) << 8 | Int(bytes[i + 2])
                guard i + 3 + segLen <= bytes.count else { return nil }
                out.append(0x50); out.append(0x47)
                for shift in [24, 16, 8, 0] { out.append(UInt8(truncatingIfNeeded: pts90k >> shift)) }
                for shift in [24, 16, 8, 0] { out.append(UInt8(truncatingIfNeeded: pts90k >> shift)) }
                out.append(bytes[i]); out.append(bytes[i + 1]); out.append(bytes[i + 2])
                out.append(contentsOf: bytes[(i + 3)..<(i + 3 + segLen)])
                i += 3 + segLen
            }
            return i == bytes.count ? out : nil
        }
        // Frame geometry comes from the stream's own first PCS declaration,
        // never hardcoded.
        guard let firstSub = subtitlePackets.first, firstSub.bytes.count >= 7,
              firstSub.bytes[0] == 0x16 else {
            fail("PGS: first subtitle packet does not start with a PCS segment")
        }
        let pgsW = Int(firstSub.bytes[3]) << 8 | Int(firstSub.bytes[4])
        let pgsH = Int(firstSub.bytes[5]) << 8 | Int(firstSub.bytes[6])
        guard let pgs = LabPGSDecoder(frameW: UInt16(pgsW), frameH: UInt16(pgsH)) else {
            fail("PGS: LabPGSDecoder refused frame \(pgsW)x\(pgsH)")
        }
        var pgsDrops = 0
        var pgsEvents: [LabPGSEvent] = []
        var lastEvtPts: UInt64 = 0
        for sp in subtitlePackets {
            guard let headed = reheadPGS(sp.bytes, pts90k: UInt32(clamping: sp.ptsUs * 9 / 100)) else {
                fail("PGS: malformed stored segment stream in subtitle packet")
            }
            if !pgs.feed(headed) { pgsDrops += 1 }
            while let ev = pgs.nextEvent() {
                if !pgsEvents.isEmpty && ev.pts90k < lastEvtPts { fail("PGS: event pts non-monotonic") }
                lastEvtPts = ev.pts90k
                pgsEvents.append(ev)
            }
        }
        if pgsDrops != 0 { fail("PGS: seam dropped \(pgsDrops) of \(subtitlePackets.count) packets") }
        if pgsEvents.isEmpty { fail("PGS: seam decoded zero events from \(subtitlePackets.count) packets") }
        var pgsDisplayCount = 0, pgsClearCount = 0
        var pgsIsum: UInt = 0, pgsPsum: UInt = 0
        for ev in pgsEvents {
            var isum: UInt = 0
            if let idx = ev.indices { for b in idx { isum = isum &* 31 &+ UInt(b) } }
            var psum: UInt = 0
            if let pal = ev.palette { for e in pal { psum = psum &* 31 &+ UInt(e) } }
            print("E1-HEADLESS pgs evt type=\(ev.type == .display ? 1 : 2) pts90k=\(ev.pts90k) ptsms=\(ev.ptsMs) rects=\(ev.rects.count) isum=\(isum) psum=\(psum)")
            for r in ev.rects {
                print("E1-HEADLESS pgs   rect \(r.x) \(r.y) \(r.w) \(r.h)")
                if Int(r.x) + Int(r.w) > pgsW || Int(r.y) + Int(r.h) > pgsH { fail("PGS: rect outside frame") }
            }
            if ev.type == .display { pgsDisplayCount += 1; pgsIsum = isum; pgsPsum = psum } else { pgsClearCount += 1 }
        }
        print("E1-HEADLESS subtitle leg=SUBTITLE-PGS seam=LabPGSDecoder packets=\(subtitlePackets.count) displays=\(pgsDisplayCount) clears=\(pgsClearCount) frame=\(pgsW)x\(pgsH)")
        if (fixturePath as NSString).lastPathComponent == "e1-mkv-pgs.mkv" {
            if pgsDisplayCount != 1 || pgsClearCount != 0 || pgsEvents.count != 1
                || pgsEvents[0].pts90k != 2070 || pgsEvents[0].ptsMs != 23
                || pgsIsum != 11703373549476155392 || pgsPsum != 3354854972892648383
                || pgsEvents[0].rects != [LabPGSRect(x: 100, y: 100, w: 64, h: 36)] {
                fail("PGS: e1-mkv-pgs pinned expectation mismatch")
            }
            print("E1-HEADLESS subtitle pinned=e1-mkv-pgs OK (byte-identical to the C carrier)")
        }
    } else {
        print("E1-HEADLESS UNRUN leg=SUBTITLE codec=\(subTrack.codec) (only hdmv_pgs_subtitle wired)")
    }
} else {
    print("E1-HEADLESS subtitle: no subtitle track (leg N/A)")
}

// clip-bbb-10s.mov: demux regression only, no mp4v decoder (block 189h).
if videoTrack.codec == "mp4v" {
    print("E1-HEADLESS NOT_RUN: codec mp4v has no decoder per block 189h; demux regression only")
    Foundation.exit(NOT_RUN)
}
guard videoTrack.codec == "h264" else { fail("unexpected video codec \(videoTrack.codec)") }

// MARK: Stage AUDIO-PCM (real): aac decode -> LANDED LabSwrConverter seam
// -> s16 interleaved at the 48 kHz contract rate, fed to goreda's landed
// E1AudioOut (start(pcm:, sampleRate: 48000, channels: 2)).
// Lane (c) playback-path wiring (arch-196y r1 item 3c / 196t r2 item 4b):
// conversion on this live path runs through the landed G0740/195b-N9 seam
// (LabSwrConverter state machine: generation/flush, bounded pts math,
// zero-input contract) bound to the product GorAVSwrBackend over the pinned
// provider's libswresample. The previous inline raw-swr block is kept only
// as a byte-exact ORACLE and the two streams are diffed. A source-native
// rate != 48000 (fixtures/e1-h264-aac44k1-10s.mp4) exercises REAL resampling
// through the seam on the live path; the 48 kHz shape stays 1:1 same-rate
// format conversion (no resampling, old contract unchanged).
if audioPacketsList.count < 400 { fail("demuxed aac packets \(audioPacketsList.count) < 400") }
for i in 1..<audioPacketsList.count where audioPacketsList[i].dtsUs < audioPacketsList[i - 1].dtsUs {
    fail("audio DTS non-monotonic at \(i)")
}
let asc: [UInt8]
if isMP4 {
    guard let entry = sampleEntryChild(bytes, entryType: "mp4a", childType: "esds", audio: true),
          let config = esdsExtradata(bytes, entry.child.lo, entry.child.hi) else { fail("no MP4 AAC config") }
    asc = config
} else {
    guard audioTrack.codec == "aac", !audioTrack.codecPrivate.isEmpty else { fail("MKV AAC CodecPrivate missing") }
    asc = audioTrack.codecPrivate
}
guard let acodec = avcodec_find_decoder(AV_CODEC_ID_AAC) else { fail("avcodec_find_decoder aac -> nil") }
var actx = avcodec_alloc_context3(acodec)
guard actx != nil else { fail("avcodec_alloc_context3 aac -> nil") }
actx!.pointee.extradata = UnsafeMutablePointer<UInt8>(OpaquePointer(av_mallocz(asc.count + 64)))
memcpy(actx!.pointee.extradata, asc, asc.count)
actx!.pointee.extradata_size = Int32(asc.count)
if avcodec_open2(actx, acodec, nil) < 0 { fail("avcodec_open2 aac failed") }
var aframe = av_frame_alloc()
guard aframe != nil else { fail("av_frame_alloc aac -> nil") }

var pcmBytes = [UInt8]() // s16 interleaved stereo at 48000 Hz (seam output)
pcmBytes.reserveCapacity(2_000_000)
var oracleBytes = [UInt8]() // pre-seam inline raw-swr path, byte-diff oracle
oracleBytes.reserveCapacity(2_000_000)
var decodedSamplesIn = 0 // decoded samples at the SOURCE-native rate
var nativeRate = 0
var seam: LabSwrConverter? = nil
var oracleSwr: OpaquePointer? = nil
var seamOutSamples = 0
var seamFlushTail = 0
var seamNextOutPts: Int64 = LabSwrConverter.nopts // expected next contiguous outPts
var seamDiscontinuities = 0
func drainAudio() {
    while true {
        let rrc = avcodec_receive_frame(actx, aframe!)
        if rrc == 0 {
            let n = Int(aframe!.pointee.nb_samples)
            let fmt = AVSampleFormat(rawValue: aframe!.pointee.format)
            if seam == nil {
                nativeRate = Int(aframe!.pointee.sample_rate)
                let ch = Int(aframe!.pointee.ch_layout.nb_channels)
                let layouts: [Int: LabSwrLayout] = [1: .mono, 2: .stereo, 6: .fiveOne]
                guard let inFmt = LabSwrFmt(rawValue: Int(fmt.rawValue)) else { fail("seam: unmapped sample fmt \(fmt.rawValue)") }
                guard let inLayout = layouts[ch] else { fail("seam: unsupported channel count \(ch)") }
                let inSpec = LabSwrSpec(rate: nativeRate, fmt: inFmt, layout: inLayout)
                let outSpec = LabSwrSpec(rate: 48000, fmt: .s16, layout: .stereo)
                let (conv, code) = LabSwrConverter.create(in: inSpec, out: outSpec, backend: GorAVSwrBackend.self)
                guard code == .ok, let conv = conv else { fail("seam create failed code=\(code)") }
                seam = conv
                // Oracle: the previous inline raw-swr path on the identical spec.
                var inL = AVChannelLayout()
                inL.order = AV_CHANNEL_ORDER_NATIVE
                inL.nb_channels = Int32(ch)
                inL.u.mask = inLayout.mask
                var outL = AVChannelLayout(); av_channel_layout_default(&outL, 2)
                var sp: OpaquePointer? = nil
                if swr_alloc_set_opts2(&sp, &outL, AV_SAMPLE_FMT_S16, 48000, &inL, fmt, Int32(nativeRate), 0, nil) < 0 || swr_init(sp) < 0 {
                    fail("oracle swr init failed fmt=\(fmt.rawValue)")
                }
                oracleSwr = sp
                print("E1-HEADLESS audio decode aac fmt=\(String(cString: av_get_sample_fmt_name(fmt)))@\(nativeRate)ch=\(ch) -> seam=LabSwrConverter backend=GorAVSwrBackend(\(GorAVSwrBackend.depVersions())) out=s16 interleaved @48000 stereo" + (nativeRate == 48000 ? " (same-rate format conversion, no resampling)" : " RESAMPLE-REAL"))
            }
            guard let seam = seam else { fail("seam missing") }
            let inPts = Int64(decodedSamplesIn)
            decodedSamplesIn += n
            let chNow = Int(aframe!.pointee.ch_layout.nb_channels)
            let inPlanes = av_sample_fmt_is_planar(fmt) != 0 ? chNow : 1
            var srcSlice: [UnsafePointer<UInt8>?] = (0..<inPlanes).map { i in
                UnsafeRawPointer(aframe!.pointee.extended_data[i])?.assumingMemoryBound(to: UInt8.self)
            }
            // Oracle convert (pre-seam path, identical libswresample spec).
            let oracleCap = Int(swr_get_out_samples(oracleSwr, Int32(n)))
            if oracleCap < 0 { fail("oracle swr_get_out_samples rc=\(oracleCap)") }
            var oracleBuf = [UInt8](repeating: 0, count: oracleCap * 4)
            oracleBuf.withUnsafeMutableBytes { ob in
                var dstSlice: [UnsafeMutablePointer<UInt8>?] = [db_base(ob), nil]
                let got = swr_convert(oracleSwr, &dstSlice, Int32(oracleCap), &srcSlice, Int32(n))
                if got < 0 { fail("oracle swr_convert rc=\(got)") }
                oracleBytes.append(contentsOf: ob.prefix(Int(got) * 4))
            }
            // Live-path convert through the landed seam.
            let cap = seam.maxOut(Int64(n))
            if cap < 0 { fail("seam maxOut rc=\(cap)") }
            var outBuf = [UInt8](repeating: 0, count: Int(cap) * 4)
            var convOut = LabSwrConverter.ConvertOut()
            outBuf.withUnsafeMutableBytes { ob in
                var dstSlice: [UnsafeMutablePointer<UInt8>?] = [db_base(ob), nil]
                let rc = seam.convert(gen: 0, inPlanes: srcSlice, n: Int64(n), inPts: inPts, out: dstSlice, cap: cap, result: &convOut)
                if rc != .ok { fail("seam convert rc=\(rc) at in_samples=\(decodedSamplesIn - n)") }
                pcmBytes.append(contentsOf: ob.prefix(Int(convOut.outN) * 4))
            }
            if convOut.flags & LabSwrConverter.fDiscont != 0 { seamDiscontinuities += 1 }
            if convOut.outN > 0 {
                if seamNextOutPts != LabSwrConverter.nopts, convOut.outPts != seamNextOutPts {
                    fail("seam outPts not contiguous: got \(convOut.outPts), want \(seamNextOutPts)")
                }
                seamNextOutPts = convOut.outPts + convOut.outN
                seamOutSamples += Int(convOut.outN)
            }
            av_frame_unref(aframe)
        } else if rrc == gorav_av_err_eagain() || rrc == gorav_av_err_eof() { return }
        else { fail("aac receive rc=\(rrc)") }
    }
}
func db_base(_ ob: UnsafeMutableRawBufferPointer) -> UnsafeMutablePointer<UInt8>? {
    ob.baseAddress?.assumingMemoryBound(to: UInt8.self)
}
for p in audioPacketsList {
    var pkt = av_packet_alloc()
    guard pkt != nil, av_new_packet(pkt, Int32(p.bytes.count)) == 0 else { fail("aac packet alloc failed") }
    p.bytes.withUnsafeBufferPointer { buf in
        if let dst = pkt!.pointee.data, let srcp = buf.baseAddress { memcpy(dst, srcp, buf.count) }
    }
    pkt!.pointee.pts = p.ptsUs
    var src = avcodec_send_packet(actx, pkt)
    if src == gorav_av_err_eagain() { drainAudio(); src = avcodec_send_packet(actx, pkt) }
    av_packet_free(&pkt)
    if src < 0 { fail("aac send rc=\(src)") }
    drainAudio()
}
_ = avcodec_send_packet(actx, nil)
drainAudio()
av_frame_free(&aframe)
avcodec_free_context(&actx)
guard let seam = seam, oracleSwr != nil else { fail("aac decode produced no frames") }
// EOF: drain the seam (its only flushing path) and the oracle identically.
do {
    let flushCap = seam.maxFlush()
    var flushBuf = [UInt8](repeating: 0, count: Int(flushCap) * 4)
    var fr = LabSwrConverter.ConvertOut()
    flushBuf.withUnsafeMutableBytes { ob in
        var dstSlice: [UnsafeMutablePointer<UInt8>?] = [db_base(ob), nil]
        let rc = seam.flush(out: dstSlice, cap: flushCap, result: &fr)
        if rc != .ok { fail("seam flush rc=\(rc)") }
        pcmBytes.append(contentsOf: ob.prefix(Int(fr.outN) * 4))
    }
    if fr.outN > 0 {
        if seamNextOutPts != LabSwrConverter.nopts, fr.outPts != seamNextOutPts {
            fail("seam flush outPts not contiguous: got \(fr.outPts), want \(seamNextOutPts)")
        }
        seamNextOutPts = fr.outPts + fr.outN
    }
    seamFlushTail = Int(fr.outN)
    seamOutSamples += Int(fr.outN)
    let oCap = Int(swr_get_out_samples(oracleSwr, 0))
    var oBuf = [UInt8](repeating: 0, count: max(oCap, 0) * 4)
    oBuf.withUnsafeMutableBytes { ob in
        var dstSlice: [UnsafeMutablePointer<UInt8>?] = [db_base(ob), nil]
        let got = swr_convert(oracleSwr, &dstSlice, Int32(oCap), nil, 0)
        if got < 0 { fail("oracle drain rc=\(got)") }
        oracleBytes.append(contentsOf: ob.prefix(Int(got) * 4))
    }
}
var os = oracleSwr
swr_free(&os)
// The seam's live-path output must be byte-identical to the pre-seam path
// (same libswresample, same spec, same feed pattern).
if pcmBytes != oracleBytes { fail("seam output diverges from the pre-seam path: \(pcmBytes.count)B vs \(oracleBytes.count)B") }
// Duration-agnostic expectation (arch-197e item 5 decision, STATUS.md):
// decode completeness = every demuxed AAC frame decoded, 1024 samples each
// (this decode path does not trim priming). Replaces the hardcoded ~10s of
// the original 10s-only fixtures, which wrongly failed the 12s E1 corpus.
let expectIn = audioPacketsList.count * 1024
if abs(decodedSamplesIn - expectIn) > 1024 { fail("aac decoded \(decodedSamplesIn) samples @\(nativeRate), want ~\(expectIn) (\(audioPacketsList.count) packets x 1024)") }
let pcmFrames = pcmBytes.count / 4
if seamOutSamples != pcmFrames { fail("seam counters \(seamOutSamples) != emitted frames \(pcmFrames)") }
if nativeRate == 48000, pcmFrames != decodedSamplesIn { fail("pcm frames \(pcmFrames) != decoded samples \(decodedSamplesIn) (1:1, no resampling)") }
let pcmSeconds = Double(pcmFrames) / 48000.0
// Duration-agnostic: the emitted stream must match the demuxed audio span
// and agree with the video span (no wholesale truncation), not a fixed 10s.
let audioSpanSeconds = audioPacketsList.count > 1
    ? Double(audioPacketsList.last!.ptsUs - audioPacketsList.first!.ptsUs) / 1_000_000.0 + 1024.0 / Double(nativeRate)
    : Double(expectIn) / Double(nativeRate)
if abs(pcmSeconds - audioSpanSeconds) > 0.2 { fail("pcm seconds \(pcmSeconds) != demuxed audio span \(audioSpanSeconds)") }
if packets.count > 1 {
    let videoSpanSeconds = Double(packets.last!.ptsUs - packets.first!.ptsUs) / 1_000_000.0
    if abs(pcmSeconds - videoSpanSeconds) > 1.0 { fail("audio seconds \(pcmSeconds) vs video span \(videoSpanSeconds) disagree by >1s") }
}
let inSeconds = Double(decodedSamplesIn) / Double(nativeRate)
if abs(pcmSeconds - inSeconds) > 0.01 { fail("seam duration not conserved: in \(inSeconds)s out \(pcmSeconds)s") }
if seamDiscontinuities != 0 { fail("seam flagged \(seamDiscontinuities) pts discontinuities on a clean fixture") }
print("E1-HEADLESS audio_pcm aac_packets=\(audioPacketsList.count) in_samples=\(decodedSamplesIn)@\(nativeRate) out_samples=\(pcmFrames)@48k s16_interleaved_bytes=\(pcmBytes.count) seconds=\(String(format: "%.3f", pcmSeconds)) seam_out=\(seamOutSamples) flush_tail=\(seamFlushTail) discontinuities=\(seamDiscontinuities) oracle_bytediff=IDENTICAL")

// MARK: Stage VIDEO PIPELINE (real): h264 decode -> scheduler -> presenter, single pass
let avcC: [UInt8]
var configuredW = 0, configuredH = 0
if isMP4 {
    guard let entry = sampleEntryChild(bytes, entryType: "avc1", childType: "avcC", audio: false) else { fail("no MP4 AVC config") }
    avcC = Array(bytes[entry.child.lo..<entry.child.hi])
    configuredW = entry.w; configuredH = entry.h
} else {
    guard !videoTrack.codecPrivate.isEmpty else { fail("MKV AVC CodecPrivate missing") }
    avcC = videoTrack.codecPrivate // avcC carries the stream's SPS geometry
}
print("E1-HEADLESS decode config avcC=\(avcC.count)B container=\(isMP4 ? "mp4" : "matroska")")
guard let codec = avcodec_find_decoder(AV_CODEC_ID_H264) else { fail("avcodec_find_decoder h264 -> nil") }
var ctx = avcodec_alloc_context3(codec)
guard ctx != nil else { fail("avcodec_alloc_context3 -> nil") }
ctx!.pointee.extradata = UnsafeMutablePointer<UInt8>(OpaquePointer(av_mallocz(avcC.count + 64)))
memcpy(ctx!.pointee.extradata, avcC, avcC.count)
ctx!.pointee.extradata_size = Int32(avcC.count)
ctx!.pointee.width = Int32(configuredW)
ctx!.pointee.height = Int32(configuredH)
if avcodec_open2(ctx, codec, nil) < 0 { fail("avcodec_open2 h264 failed") }
var frame = av_frame_alloc()
guard frame != nil else { fail("av_frame_alloc -> nil") }

var packetIndex = 0
var flushed = false
func sendPacket(_ p: CompressedPacket) {
    var pkt = av_packet_alloc()
    guard pkt != nil, av_new_packet(pkt, Int32(p.bytes.count)) == 0 else { fail("packet alloc failed") }
    p.bytes.withUnsafeBufferPointer { buf in
        if let dst = pkt!.pointee.data, let srcp = buf.baseAddress { memcpy(dst, srcp, buf.count) }
    }
    pkt!.pointee.pts = p.ptsUs
    pkt!.pointee.dts = p.dtsUs
    let src = avcodec_send_packet(ctx, pkt)
    av_packet_free(&pkt)
    if src < 0 && src != gorav_av_err_eagain() { fail("avcodec_send_packet rc=\(src)") }
}
// Pull one decoded frame (presentation order); false at end of stream.
func pumpNextFrame() -> Bool {
    while true {
        let rrc = avcodec_receive_frame(ctx, frame!)
        if rrc == 0 { return true }
        if rrc == gorav_av_err_eof() { return false }
        if rrc != gorav_av_err_eagain() { fail("avcodec_receive_frame rc=\(rrc)") }
        if packetIndex < packets.count {
            sendPacket(packets[packetIndex]); packetIndex += 1
        } else if !flushed {
            flushed = true
            _ = avcodec_send_packet(ctx, nil)
        }
    }
}

#if os(macOS)
presenterBegin()
// The full 1:1 GPU readback/SHA oracle is not a real-time display operation.
// Verify EVERY decoded frame before starting audio, then replay the decoder
// for the actual timed upload/embed run. No scheduler tolerance is changed.
var verifiedFrames = 0
while pumpNextFrame() {
    let f = frame!
    _ = presenterPresentFrame(f, ptsSeconds: Double(f.pointee.pts) / 1_000_000)
    verifiedFrames += 1
    av_frame_unref(frame)
}
presenterFinishVerification(expectedFrames: verifiedFrames)
avcodec_flush_buffers(ctx)
packetIndex = 0
flushed = false
#if E1_WITH_EMBED
presenterEmbedBegin()
#endif
#endif
// Test hooks (typed, test-only): E1_SIM_AUDIO_CLOCK=1 replaces the perfect
// clock with a real running wall clock anchored where the audio clock
// starts; E1_SKIP_WARMUP=1 starts the clock BEFORE video readiness
// (ordering witness); E1_SIM_FIRST_FRAME_DELAY_MS=N injects N ms of
// first-frame decode latency; E1_SIM_CLOCK_JUMP_MS=N models a device whose
// first render callback pulls N ms of PCM into pre-buffering instantly
// (consumed clock jumps, stays ahead); E1_SIM_CLOCK_NOCLAMP=1 disables the
// audible-time clamp (witness); E1_SIM_SLOW_FRAME_MS=N with
// E1_SIM_SLOW_FRAME_IDX=K injects N ms of pipeline latency at frame K after
// the clock is running (witness that a genuinely slow frame still drops).
let simRunningClock = ProcessInfo.processInfo.environment["E1_SIM_AUDIO_CLOCK"] == "1"
let skipWarmup = ProcessInfo.processInfo.environment["E1_SKIP_WARMUP"] == "1"
let simFirstDelayMs = Int(ProcessInfo.processInfo.environment["E1_SIM_FIRST_FRAME_DELAY_MS"] ?? "0") ?? 0
let simClockJumpSec = Double(Int(ProcessInfo.processInfo.environment["E1_SIM_CLOCK_JUMP_MS"] ?? "0") ?? 0) / 1000
let simNoClamp = ProcessInfo.processInfo.environment["E1_SIM_CLOCK_NOCLAMP"] == "1"
let simSlowFrameMs = Int(ProcessInfo.processInfo.environment["E1_SIM_SLOW_FRAME_MS"] ?? "0") ?? 0
let simSlowFrameIdx = Int(ProcessInfo.processInfo.environment["E1_SIM_SLOW_FRAME_IDX"] ?? "10") ?? 10
// The media and presentation timelines share a zero at REAL READINESS: the
// audio clock starts only after the video pipeline has decoded AND
// presented its first frame through the full presenter path (Metal
// pipeline/shader/readback warm-up included). Mac run 42305745797
// telemetry: frame pts=0.04 decided at hostSinceAudioStart=0.111s,
// rawMediaTime=0.096s - the first present cost ~110 ms AFTER the clock
// started. Real lateness, fixed at the root by ordering, not tolerance:
// maxLate and every assert unchanged, and E1_SIM_SLOW_FRAME_* below keeps a
// witness that a genuinely slow frame after readiness still drops.
// E1_SKIP_WARMUP=1 inverts the order as the ordering witness.
var clockZero = 0.0
func markClockZero() { clockZero = ProcessInfo.processInfo.systemUptime }
#if E1_WITH_AUDIO_OUT
let audioOut: E1AudioOut
do { audioOut = try E1AudioOut() } catch { fail("audio out init threw: \(error)") }
func startAudio(_ label: String) {
    do { try audioOut.start(pcm: pcmBytes, sampleRate: 48000, channels: 2) } catch { fail("audio start threw: \(error)") }
    print("E1-HEADLESS audio_out started pcm_bytes=\(pcmBytes.count) rate=48000 ch=2\(label)")
    markClockZero()
}
#else
func startAudio(_ label: String) { markClockZero() }
#endif
// Engine-owned readiness state (189k): the harness no longer implements
// the start ordering itself; it calls the engine's typed gates.
var readiness = ReadinessAnchorSession()
readiness.begin()
if skipWarmup {
    // E1_SKIP_WARMUP witness, engine level: the pre-readiness clock start
    // the flag asks for must be a typed REFUSAL, never silently permitted.
    // A permission here is the bug the rule exists to kill.
    if readiness.requestClockStart() {
        fail("engine permitted pre-anchor clock start (E1_SKIP_WARMUP)")
    }
    print("E1-HEADLESS witness E1_SKIP_WARMUP: engine refused pre-anchor clock start (typed refusal); continuing under engine ordering")
}
// Decode frame 0 (timed; per-stage timings print for every frame).
if simFirstDelayMs > 0 { usleep(UInt32(simFirstDelayMs) * 1000) }
var stageT = ProcessInfo.processInfo.systemUptime
var haveFrame = pumpNextFrame()
var decodeMs = (ProcessInfo.processInfo.systemUptime - stageT) * 1000
if !haveFrame { fail("decoder produced no frames") }
var clock = AudioMasterClock()
clock.reset(audioTime: 0, hostTime: 0)
var decodedCount = 0
var presented = 0
var lastPTS: Int64 = Int64.min
var firstFormat = ""
var frameW = 0, frameH = 0
var pulledPTS: [Int64] = []
// Frame 0 readiness present: no scheduler decision (frame 0 defines the
// timeline zero); the clock starts after it is really presented.
do {
    let pts = frame!.pointee.pts
    lastPTS = pts
    pulledPTS.append(pts)
    decodedCount += 1
    firstFormat = String(cString: av_get_pix_fmt_name(AVPixelFormat(rawValue: frame!.pointee.format)))
    frameW = Int(frame!.pointee.width); frameH = Int(frame!.pointee.height)
    let ptsSec = Double(pts) / 1_000_000
    stageT = ProcessInfo.processInfo.systemUptime
    var convMs = 0.0, upMs = 0.0, rbMs = 0.0
    #if os(macOS)
    #if E1_WITH_EMBED
    // Convert ONCE per present decision; both presenter legs share it.
    let cT0 = ProcessInfo.processInfo.systemUptime
    let rgbaShared0 = yuvToRGBA8(frame!, Int(frame!.pointee.width), Int(frame!.pointee.height))
    convMs = (ProcessInfo.processInfo.systemUptime - cT0) * 1000
    (upMs, rbMs) = presenterPresentConverted(rgba: rgbaShared0, w: Int(frame!.pointee.width), h: Int(frame!.pointee.height), ptsSeconds: ptsSec)
    presenterEmbedPresent(rgba: rgbaShared0, w: Int(frame!.pointee.width), h: Int(frame!.pointee.height), ptsSeconds: ptsSec)
    #else
    (convMs, upMs, rbMs) = presenterPresentFrame(frame!, ptsSeconds: ptsSec)
    #endif
    #endif
    presented += 1
    #if os(macOS)
    print("E1-HEADLESS frame 0 pts=\(ptsSec) decode_ms=\(decodeMs) convert_ms=\(convMs) upload_ms=\(upMs) readback_ms=\(rbMs)")
    #else
    print("E1-HEADLESS frame 0 pts=\(ptsSec) decode_ms=\(decodeMs)")
    #endif
}
// Frame 0 was decoded AND presented: it IS the readiness anchor (no
// scheduler decision was taken on it). The clock start goes through the
// engine gate; a refusal here means the anchor bookkeeping is broken.
readiness.anchorPresentedNow()
if !readiness.requestClockStart() { fail("engine refused clock start after readiness anchor present") }
startAudio("")
av_frame_unref(frame)
stageT = ProcessInfo.processInfo.systemUptime
haveFrame = pumpNextFrame()
decodeMs = (ProcessInfo.processInfo.systemUptime - stageT) * 1000
while haveFrame {
    let pts = frame!.pointee.pts
    if pts <= lastPTS { fail("decoded PTS not strictly increasing at frame \(decodedCount)") }
    lastPTS = pts
    pulledPTS.append(pts)
    decodedCount += 1
    if firstFormat.isEmpty {
        firstFormat = String(cString: av_get_pix_fmt_name(AVPixelFormat(rawValue: frame!.pointee.format)))
        frameW = Int(frame!.pointee.width); frameH = Int(frame!.pointee.height)
    }
    let ptsSec = Double(pts) / 1_000_000
    let frameIdx = decodedCount - 1
    if simSlowFrameMs > 0 && frameIdx == simSlowFrameIdx { usleep(UInt32(simSlowFrameMs) * 1000) }
    // Decide against the clock, re-deciding on .wait: a frame ahead of the
    // real audio clock WAITS for it (never counts as presented early); a
    // drop past maxLate is a typed failure. Peer finding 01:15 verified in
    // code: the previous spin released at pts - maxLate and treated the
    // resulting .wait as fatal - both wrong.
    if readiness.anchorPending { fail("engine anchor still pending inside scheduler loop at pts=\(ptsSec)") }
    var spins = 0
    var decisionOffsetMs: Double? = nil
    decideLoop: while true {
        #if E1_WITH_AUDIO_OUT
        // Audible media time can never exceed wall time since the unit
        // started. E1AudioOut.mediaTime is a consumed-POSITION clock
        // (consumedBytes / (rate*ch*2)): the device may pull a whole buffer
        // of PCM into pre-buffering in one instant first callback, which a
        // raw consumed clock reads as audible progress. Mac run 42304632850:
        // frame pts=0.04 dropped 32 us after audio start, i.e. mediaTime
        // read > 0.08 s within 32 us. Clamp at the call site to the wall
        // upper bound; real lateness (video behind real time) still drops.
        let rawMedia = audioOut.mediaTime
        let hostElapsed = ProcessInfo.processInfo.systemUptime - clockZero
        let clampedMedia = min(rawMedia, hostElapsed)
        decisionOffsetMs = (clampedMedia - ptsSec) * 1000 // diagnostics: decision-time lateness
        clock.updateAudio(mediaTime: clampedMedia, hostTime: ptsSec)
        #else
        if simRunningClock {
            let hostElapsed = ProcessInfo.processInfo.systemUptime - clockZero
            // The jump models the first render callback's instant pre-buffer
            // pull, which lands after the primed first frame (Mac signature:
            // pts=0.00 passes, pts=0.04 drops).
            let raw = hostElapsed + (presented > 0 ? simClockJumpSec : 0.0)
            clock.updateAudio(mediaTime: simNoClamp ? raw : min(raw, hostElapsed), hostTime: ptsSec)
        } else {
            clock.updateAudio(mediaTime: ptsSec, hostTime: ptsSec) // perfect-clock simulation
        }
        #endif
        switch clock.decide(videoPTS: ptsSec, hostTime: ptsSec) {
        case .present:
            stageT = ProcessInfo.processInfo.systemUptime
            var convMs = 0.0, upMs = 0.0, rbMs = 0.0
            #if os(macOS)
            #if E1_WITH_EMBED
            // Convert ONCE per present decision; both presenter legs share it.
            let cT0 = ProcessInfo.processInfo.systemUptime
            let rgbaShared = yuvToRGBA8(frame!, Int(frame!.pointee.width), Int(frame!.pointee.height))
            convMs = (ProcessInfo.processInfo.systemUptime - cT0) * 1000
            (upMs, rbMs) = presenterPresentConverted(rgba: rgbaShared, w: Int(frame!.pointee.width), h: Int(frame!.pointee.height), ptsSeconds: ptsSec)
            presenterEmbedPresent(rgba: rgbaShared, w: Int(frame!.pointee.width), h: Int(frame!.pointee.height), ptsSeconds: ptsSec)
            #else
            (convMs, upMs, rbMs) = presenterPresentFrame(frame!, ptsSeconds: ptsSec)
            #endif
            #endif
            let presentMs = (ProcessInfo.processInfo.systemUptime - stageT) * 1000
            presented += 1
            #if os(macOS)
            print("E1-HEADLESS frame \(frameIdx) pts=\(ptsSec) decode_ms=\(decodeMs) convert_ms=\(convMs) upload_ms=\(upMs) readback_ms=\(rbMs) present_ms=\(presentMs)" + (decisionOffsetMs.map { String(format: " offset_ms=%.1f", $0) } ?? ""))
            #else
            print("E1-HEADLESS frame \(frameIdx) pts=\(ptsSec) decode_ms=\(decodeMs) present_ms=\(presentMs)")
            #endif
            break decideLoop
        case .wait:
            #if E1_WITH_AUDIO_OUT
            usleep(1000)
            spins += 1
            if spins > 30_000 { fail("audio clock stalled at pts=\(ptsSec)s clock=\(min(audioOut.mediaTime, ProcessInfo.processInfo.systemUptime - clockZero))s rawMediaTime=\(audioOut.mediaTime)s maxLate=\(AudioMasterClock.maxLate)s") }
            continue decideLoop
            #else
            if simRunningClock {
                usleep(1000)
                spins += 1
                if spins > 30_000 { fail("sim clock stalled at pts=\(ptsSec)") }
                continue decideLoop
            }
            fail("scheduler waited on synced frame pts=\(ptsSec)")
            #endif
        case .drop:
            #if E1_WITH_AUDIO_OUT
            let rawMedia = audioOut.mediaTime
            let hostElapsed = ProcessInfo.processInfo.systemUptime - clockZero
            fail("scheduler dropped frame pts=\(ptsSec)s clock=\(min(rawMedia, hostElapsed))s rawMediaTime=\(rawMedia)s hostSinceAudioStart=\(hostElapsed)s consumedBytes=\(audioOut.consumedBytes)B queuedBytes=\(audioOut.queuedBytes)B maxLate=\(AudioMasterClock.maxLate)s spins=\(spins) (late past maxLate)")
            #else
            fail("scheduler dropped frame pts=\(ptsSec) (late past maxLate)")
            #endif
        }
    }
    av_frame_unref(frame)
    stageT = ProcessInfo.processInfo.systemUptime
    haveFrame = pumpNextFrame()
    decodeMs = (ProcessInfo.processInfo.systemUptime - stageT) * 1000
}
av_frame_free(&frame)
avcodec_free_context(&ctx)

if decodedCount <= 240 { fail("decoded frames \(decodedCount) <= 240") }
if frameW <= 0 || frameH <= 0 { fail("decoded frame has no geometry") }
if Set(pulledPTS) != Set(packets.map { $0.ptsUs }) { fail("decoded presentation set != demuxed presentation set") }
if presented <= 240 { fail("scheduler presented \(presented) <= 240") }
print("E1-HEADLESS decode frames=\(decodedCount) format=\(firstFormat) \(frameW)x\(frameH) pts_set=demux_set OK")
#if E1_WITH_AUDIO_OUT
print("E1-HEADLESS scheduler presented=\(presented)/\(decodedCount) (real audio-clock anchor)")
#else
print("E1-HEADLESS scheduler presented=\(presented)/\(decodedCount) (\(simRunningClock ? "sim running wall clock" : "perfect-clock simulation"))")
#endif

// MARK: POST-SEEK witness (engine level, 189k): a seek fences the
// generation, stops the clock, and demands a NEW readiness anchor before
// any clock restart. Engine-state witness only; the media pipeline is
// done above and untouched here.
do {
    let g = readiness.seek()
    if readiness.clockRunning { fail("engine clock still running across seek") }
    if readiness.requestClockStart() { fail("engine permitted post-seek clock restart before new readiness anchor") }
    readiness.anchorPresentedNow() // first post-seek frame decoded AND presented
    if !readiness.requestClockStart() { fail("engine refused clock restart after post-seek readiness anchor") }
    print("E1-HEADLESS witness POST-SEEK: generation=\(g) fenced, clock restart gated by new readiness anchor OK")
}

// MARK: Stage DECODE-VT (opt-in E1_WITH_VT on macOS; typed-unrun elsewhere)
#if os(macOS)
#if E1_WITH_VT
vtDecodeParity(packets: packets, avcC: avcC, expectW: frameW, expectH: frameH)
#else
print("E1-HEADLESS UNRUN leg=DECODE-VT seam=VideoToolbox (E1_WITH_VT not enabled)")
#endif
#else
print("E1-HEADLESS UNRUN leg=DECODE-VT seam=VideoToolbox (macOS, E1_WITH_VT)")
#endif

// MARK: Stage AUDIO-OUT DRAIN (flag runs only; outside the close measurement)
#if E1_WITH_AUDIO_OUT
let wSem = DispatchSemaphore(value: 0)
var audioFullyConsumed = false
Task { audioFullyConsumed = await audioOut.waitUntilConsumed(); wSem.signal() }
wSem.wait()
if !audioFullyConsumed { fail("audio consumption deadline hit: consumed \(audioOut.consumedBytes)B of \(pcmBytes.count)B") }
if audioOut.consumedBytes != pcmBytes.count { fail("audio consumed \(audioOut.consumedBytes)B != pcm \(pcmBytes.count)B") }
print("E1-HEADLESS audio_out consumed=\(audioOut.consumedBytes)B waitUntilConsumed=OK")
#endif

// MARK: Stage PRESENTER report (real on macOS, typed-unrun elsewhere)
#if os(macOS)
presenterAssertAndReport()
#if E1_WITH_EMBED
presenterEmbedAssertAndReport()
#else
print("E1-HEADLESS UNRUN leg=PRESENTER-EMBED seam=MetalPresenter(embedIn:) (E1_WITH_EMBED not enabled)")
#endif
#else
print("E1-HEADLESS UNRUN leg=PRESENTER seam=GorAVMetalPresenter-offscreen (macOS)")
print("E1-HEADLESS UNRUN leg=PRESENTER-EMBED seam=MetalPresenter(embedIn:) (macOS, E1_WITH_EMBED)")
#endif

// MARK: Stage CLOSE (combined presenter+audio close on mac, < 300 ms)
let closeStart = Date()
#if os(macOS)
presenterClose()
#if E1_WITH_EMBED
presenterEmbedClose()
#endif
#endif
#if E1_WITH_AUDIO_OUT
let audioSem = DispatchSemaphore(value: 0)
Task {
    let receipt = await audioOut.close()
    if receipt.producerFailed { fail("audio close: output-unit stop/dispose failed") }
    if receipt.callbacks <= 0 { fail("audio close: zero real render callbacks") }
    if receipt.sampleRate != 48000 || receipt.channels != 2 { fail("audio receipt rate \(receipt.sampleRate) ch \(receipt.channels) != 48000/2") }
    if receipt.residualBytes != 0 { fail("audio residual \(receipt.residualBytes)B after full consumption") }
    if receipt.consumedBytes != receipt.suppliedBytes { fail("audio consumed \(receipt.consumedBytes)B != supplied \(receipt.suppliedBytes)B") }
    print("E1-HEADLESS audio_out closed callbacks=\(receipt.callbacks) consumed=\(receipt.consumedBytes)B close_ms=\(receipt.closeMs)")
    audioSem.signal()
}
audioSem.wait()
#endif
demuxer = Demuxer()
clock.reset(audioTime: 0, hostTime: 0)
let closeMs = Date().timeIntervalSince(closeStart) * 1000
if closeMs >= 300 { fail("close \(closeMs) ms >= 300 ms") }
print(String(format: "E1-HEADLESS close_ms=%.3f < 300", closeMs))

#if os(macOS) && E1_WITH_AUDIO_OUT
var extraLegs = ""
#if E1_WITH_EMBED
extraLegs += " + host-embed (AppKit embed, submit-path, not scanout proof)"
#endif
#if E1_WITH_VT
extraLegs += " + decode-vt (plane parity vs sw, no VT acceptance)"
#endif
print("E1-HEADLESS PASS: all six legs real (demux decode audio-pcm scheduler presenter audio-out)\(extraLegs)")
Foundation.exit(0)
#else
print("E1-HEADLESS UNRUN leg=AUDIO-OUT seam=E1AudioOut (macOS, E1_WITH_AUDIO_OUT)")
print("E1-HEADLESS UNRUN: typed legs unlanded on this host (see leg lines above)")
Foundation.exit(UNRUN)
#endif
