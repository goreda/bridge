// AUTHORED NEW (2026-10-17, review desk): audio probe adapter, K4 scope.
// Separate from the video adapter BY DESIGN: the video admission (one video,
// no audio, no other) is untouched. This class admits ONLY a single pcm_s16le
// audio stream in WAV, or MOV with exactly one video and no other streams.
// Probe class: bounded copies, typed refusals, explicit teardown. No clock,
// no playback pacing here - pacing belongs to the playback core (K6 core).
import Foundation
import CFFmpeg
import GorAVCore
import GorAVNativeProbeKit

public struct AudioPCMFrame: Equatable, Sendable {
    public let handle: UInt64
    public let samples: Int          // per channel
    public let channels: Int
    public let sampleRate: Int
    public let bytes: [UInt8]        // bounded visible PCM copy (packed s16le)
}

public enum AudioDecodeEvent: Equatable, Sendable {
    case opened(codec: String, sampleRate: Int, channels: Int)
    case pcm(AudioPCMFrame)
    case endOfStream
    case failed(code: Int, summary: String)
}

// Additive audio boundary. Native readiness is NOT decoded landing or core ACK.
public struct AudioSourceBinding: Equatable, Sendable {
    public let source: UUID
    public let session: UInt64
    public let revision: UInt64
}
public struct AudioSeekDescriptor: Equatable, Sendable {
    public let binding: AudioSourceBinding
    public let seekable: Bool
    public let audioStreamIndex: Int32
    public let audioTimebase: RationalTime
    public let audioStart: RationalTime?
    // MOV: video start on the effective post-edit demux presentation timeline.
    // WAV: explicitly the audio start, not an invented video reference.
    public let referenceOrigin: RationalTime?
    public let referenceIsVideo: Bool
}
public enum AudioSeekRefusal: Error, Equatable, Sendable {
    case closed, staleBinding, legacyMode, notSeekable, unknownOrigin
    case invalidTarget, overflow, exhausted, poisoned
}
public enum AudioSeekResult: Equatable, Sendable {
    case refused(AudioSeekRefusal)
    case nativeReady(binding: AudioSourceBinding, correlation: UInt64, commonTarget: RationalTime, seekTicks: Int64)
    // av_seek_frame can mutate even on failure. Close is required, never resume.
    case closeRequired(binding: AudioSourceBinding, correlation: UInt64, nativeCode: Int32)
}
public struct AudioPCMTiming: Equatable, Sendable {
    public let decodedPTS: Int64
    public let streamTimebase: RationalTime
    public let trimmedSamples: Int
    public let firstSample: RationalTime
    public let seekTarget: RationalTime?
    public let gapFromTarget: RationalTime?
}
public struct AudioEventEnvelope: Equatable, Sendable {
    public let binding: AudioSourceBinding
    public let correlation: UInt64? // nil for initial open
    public let event: AudioDecodeEvent
    public let timing: AudioPCMTiming? // present for every bound PCM event
}

// Exact signed arithmetic. Denominator/numerator overflow is a typed refusal;
// never silently quantize, switch to Double or raise the deployment floor.
public enum AudioMediaTime {
    private static func gcd(_ x: Int64, _ y: Int64) -> Int64 {
        var a = x, b = y
        while b != 0 { let r = a % b; a = b; b = r }
        return a
    }
    public static func add(_ a: RationalTime, _ b: RationalTime) throws -> RationalTime {
        let g = gcd(Int64(a.timescale), Int64(b.timescale))
        let am = Int64(b.timescale) / g, bm = Int64(a.timescale) / g
        let (den, od) = Int64(a.timescale).multipliedReportingOverflow(by: am)
        let (av, oa) = a.value.multipliedReportingOverflow(by: am)
        let (bv, ob) = b.value.multipliedReportingOverflow(by: bm)
        let (sum, os) = av.addingReportingOverflow(bv)
        guard !od, !oa, !ob, !os, den <= Int64(Int32.max) else { throw SeekTimeError.overflow }
        return try RationalTime(value: sum, timescale: Int32(den)).normalized
    }
    public static func subtract(_ a: RationalTime, _ b: RationalTime) throws -> RationalTime {
        guard b.value != Int64.min else { throw SeekTimeError.overflow }
        return try add(a, RationalTime(value: -b.value, timescale: b.timescale))
    }
    public static func timestamp(_ pts: Int64, timebase: RationalTime) throws -> RationalTime {
        let (v, overflow) = pts.multipliedReportingOverflow(by: timebase.value)
        guard !overflow else { throw SeekTimeError.overflow }
        return try RationalTime(value: v, timescale: timebase.timescale).normalized
    }
    public static func trimSamples(target: RationalTime, frameStart: RationalTime, rate: Int32) throws -> Int64 {
        guard rate > 0 else { throw SeekTimeError.invalidTimescale }
        let delta = try subtract(target, frameStart)
        if delta.value <= 0 { return 0 }
        let floor = try delta.floorTicks(toTimescale: rate)
        let exact = try RationalTime(value: floor, timescale: rate)
        if exact == delta { return floor }
        let (ceil, overflow) = floor.addingReportingOverflow(1)
        guard !overflow else { throw SeekTimeError.overflow }
        return ceil
    }
}

public final class FFmpegSoftwareAudioDecoder: @unchecked Sendable {
    public enum AudioOpenError: Error, Equatable { case sessionBusy, rejected(String) }
    public static let maxFrameBytes = 1 << 20

    private let nativeQueue = DispatchQueue(label: "gorav.audio.native")
    private var fmt: UnsafeMutablePointer<AVFormatContext>?
    private var codec: UnsafeMutablePointer<AVCodecContext>?
    private var audioIndex: Int32 = -1
    private var packet: UnsafeMutablePointer<AVPacket>?
    private var frame: UnsafeMutablePointer<AVFrame>?
    private var active = false
    // Queue-owned state. Terminal events are emitted once, then pulls return nil.
    private enum FeedState { case reading, draining, terminal }
    private var feedState: FeedState = .terminal
    private var packetPending = false
    private var activeSid: UInt64?
    private var pendingOpened: AudioDecodeEvent?
    private var nextHandle: UInt64 = 1
    private var pinnedRoots: [URL] = []

    private enum PullMode { case unset, legacy, bound }
    private var pullMode: PullMode = .unset
    private var sourceUUID: UUID?
    private var revision: UInt64 = 1
    private var correlation: UInt64?
    private var descriptor: AudioSeekDescriptor?
    private var landingTarget: RationalTime?
    private var lastTiming: AudioPCMTiming?
    private var poisoned = false

    public init() {}

    public func pinLocalRoots(_ roots: [String]) throws {
        try nativeQueue.sync {
            guard !active else { throw AudioOpenError.sessionBusy }
            for r in roots {
                guard r.hasPrefix("/") else { throw AudioOpenError.rejected("pinned root is not absolute") }
                // K13B (team2 candidate r1 F2, verified against code behavior):
                // the vacuous-root check runs POST-resolution - a raw-string
                // check misses "//", "/.", and symlinks to root.
                let u = URL(fileURLWithPath: r).resolvingSymlinksInPath().standardizedFileURL
                guard u.path != "/" else { throw AudioOpenError.rejected("pinned root resolves to '/': vacuous containment refused") }
                pinnedRoots.append(u)
            }
        }
    }

    public func open(source: SourceDescriptor, session: SessionID) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nativeQueue.sync {
                do {
                    guard !active else { throw AudioOpenError.sessionBusy }
                    guard session.epoch != 0 else { throw AudioOpenError.rejected("zero session") }
                    guard source.kind == .local else { throw AudioOpenError.rejected("local sources only") }
                    guard source.id.hasPrefix("/"), !source.id.contains("://") else {
                        throw AudioOpenError.rejected("absolute local path only")
                    }
                    let resolved = URL(fileURLWithPath: source.id).resolvingSymlinksInPath().standardizedFileURL
                    guard pinnedRoots.contains(where: { resolved.path == $0.path || resolved.path.hasPrefix($0.path + "/") }) else {
                        throw AudioOpenError.rejected("outside pinned roots")
                    }
                    var f: UnsafeMutablePointer<AVFormatContext>?
                    var rc = avformat_open_input(&f, resolved.path, nil, nil)
                    guard rc >= 0, let fc = f else { throw AudioOpenError.rejected("avformat_open_input failed \(rc)") }
                    rc = avformat_find_stream_info(fc, nil)
                    guard rc >= 0 else { avformat_close_input(&f); throw AudioOpenError.rejected("stream info failed \(rc)") }
                    let container = String(cString: fc.pointee.iformat.pointee.name)
                    var audioCount = 0, videoCount = 0, otherCount = 0, aIndex: Int32 = -1
                    for i in 0..<Int32(fc.pointee.nb_streams) {
                        switch fc.pointee.streams[Int(i)]?.pointee.codecpar?.pointee.codec_type ?? AVMEDIA_TYPE_UNKNOWN {
                        case AVMEDIA_TYPE_AUDIO: audioCount += 1; if aIndex < 0 { aIndex = i }
                        case AVMEDIA_TYPE_VIDEO: videoCount += 1
                        default: otherCount += 1
                        }
                    }
                    let codecID = aIndex >= 0 ? (fc.pointee.streams[Int(aIndex)]?.pointee.codecpar?.pointee.codec_id ?? AV_CODEC_ID_NONE) : AV_CODEC_ID_NONE
                    let codecName = String(cString: avcodec_get_name(codecID))
                    // Card 465 bounded muxed sibling profile: beside the original
                    // pure-wav fixture shape, admit the mov family with exactly one
                    // pcm_s16le audio stream next to exactly one video stream and
                    // nothing else (matches DemuxerPolicy's muxed admission). Every
                    // other shape keeps the rejection.
                    let wavProfile = container == "wav" && audioCount == 1 && videoCount == 0 && otherCount == 0 && codecName == "pcm_s16le"
                    let muxedMovProfile = container == "mov,mp4,m4a,3gp,3g2,mj2" && audioCount == 1 && videoCount == 1 && otherCount == 0 && codecName == "pcm_s16le"
                    guard wavProfile || muxedMovProfile else {
                        avformat_close_input(&f)
                        throw AudioOpenError.rejected("admission: container=\(container) audio=\(audioCount) video=\(videoCount) other=\(otherCount) codec=\(codecName)")
                    }
                    guard let dec = avcodec_find_decoder(codecID) else {
                        avformat_close_input(&f); throw AudioOpenError.rejected("no pcm_s16le decoder")
                    }
                    guard let cc = avcodec_alloc_context3(dec) else {
                        avformat_close_input(&f); throw AudioOpenError.rejected("codec ctx alloc")
                    }
                    let parametersRC = avcodec_parameters_to_context(cc, fc.pointee.streams[Int(aIndex)]?.pointee.codecpar)
                    guard parametersRC >= 0 else {
                        var tmp: UnsafeMutablePointer<AVCodecContext>? = cc; avcodec_free_context(&tmp)
                        avformat_close_input(&f); throw AudioOpenError.rejected("codec parameters failed \(parametersRC)")
                    }
                    // avcodec_receive_frame PTS is interpreted in this explicit
                    // packet/stream timebase, not AV_TIME_BASE or sample count.
                    cc.pointee.pkt_timebase = fc.pointee.streams[Int(aIndex)]!.pointee.time_base
                    guard avcodec_open2(cc, dec, nil) >= 0 else {
                        var tmp: UnsafeMutablePointer<AVCodecContext>? = cc; avcodec_free_context(&tmp)
                        avformat_close_input(&f); throw AudioOpenError.rejected("codec open")
                    }
                    var allocatedPacket = av_packet_alloc()
                    var allocatedFrame = av_frame_alloc()
                    guard allocatedPacket != nil, allocatedFrame != nil else {
                        av_packet_free(&allocatedPacket); av_frame_free(&allocatedFrame)
                        var tmp: UnsafeMutablePointer<AVCodecContext>? = cc; avcodec_free_context(&tmp)
                        avformat_close_input(&f); throw AudioOpenError.rejected("packet/frame allocation failed")
                    }
                    self.fmt = fc; self.codec = cc; self.audioIndex = aIndex
                    self.packet = allocatedPacket; self.frame = allocatedFrame
                    self.active = true; self.feedState = .reading; self.packetPending = false
                    self.activeSid = session.epoch
                    self.sourceUUID = UUID(); self.revision = 1; self.correlation = nil
                    self.pullMode = .unset; self.poisoned = false
                    self.landingTarget = nil; self.lastTiming = nil
                    let ast = fc.pointee.streams[Int(aIndex)]!.pointee
                    if ast.time_base.num > 0, ast.time_base.den > 0 {
                        let tb = try RationalTime(value: Int64(ast.time_base.num), timescale: ast.time_base.den)
                        let audioStart: RationalTime? = ast.start_time == gorav_av_nopts_value() ? nil : (try? AudioMediaTime.timestamp(ast.start_time, timebase: tb))
                        var reference = audioStart
                        if muxedMovProfile {
                            reference = nil
                            for i in 0..<Int(fc.pointee.nb_streams) {
                                guard let st = fc.pointee.streams[i], st.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_VIDEO else { continue }
                                let vt = st.pointee.time_base
                                if vt.num > 0, vt.den > 0, st.pointee.start_time != gorav_av_nopts_value() {
                                    reference = try? AudioMediaTime.timestamp(st.pointee.start_time, timebase: RationalTime(value: Int64(vt.num), timescale: vt.den))
                                }
                            }
                        }
                        self.descriptor = AudioSeekDescriptor(binding: self.bindingOnQueue(),
                            seekable: source.seekable && reference != nil, audioStreamIndex: aIndex,
                            audioTimebase: tb, audioStart: audioStart, referenceOrigin: reference,
                            referenceIsVideo: muxedMovProfile)
                    } else { self.descriptor = nil }
                    let rate = Int(cc.pointee.sample_rate)
                    let ch = Int(cc.pointee.ch_layout.nb_channels)
                    self.pendingOpened = .opened(codec: codecName, sampleRate: rate, channels: ch)
                    cont.resume()
                } catch { cont.resume(throwing: error) }
            }
        }
    }

    private func bindingOnQueue() -> AudioSourceBinding {
        AudioSourceBinding(source: sourceUUID!, session: activeSid!, revision: revision)
    }
    public func seekDescriptor(session: SessionID) async -> AudioSeekDescriptor? {
        nativeQueue.sync {
            guard active, activeSid == session.epoch, !poisoned, let d = descriptor else { return nil }
            return AudioSeekDescriptor(binding: bindingOnQueue(), seekable: d.seekable,
                audioStreamIndex: d.audioStreamIndex, audioTimebase: d.audioTimebase,
                audioStart: d.audioStart, referenceOrigin: d.referenceOrigin, referenceIsVideo: d.referenceIsVideo)
        }
    }
    public func seek(binding: AudioSourceBinding, videoRelativeTarget: RationalTime, correlation: UInt64) async -> AudioSeekResult {
        nativeQueue.sync {
            guard active, let fc = fmt, let cc = codec else { return .refused(.closed) }
            guard binding == bindingOnQueue() else { return .refused(.staleBinding) }
            guard !poisoned else { return .refused(.poisoned) }
            guard pullMode != .legacy else { return .refused(.legacyMode) }
            guard videoRelativeTarget.value >= 0, correlation != 0 else { return .refused(.invalidTarget) }
            guard let d = descriptor, let origin = d.referenceOrigin else { return .refused(.unknownOrigin) }
            guard d.seekable else { return .refused(.notSeekable) }
            guard revision < UInt64.max else { return .refused(.exhausted) }
            let common: RationalTime, ticks: Int64
            do {
                common = try AudioMediaTime.add(origin, videoRelativeTarget)
                ticks = try common.floorTicks(toTimebaseNumerator: d.audioTimebase.value, denominator: Int64(d.audioTimebase.timescale))
            } catch { return .refused(.overflow) }
            self.pullMode = .bound
            // Queue serialization fences all provider reads. It cannot revoke
            // bytes returned earlier; composition must stop/quarantine producer.
            let rc = av_seek_frame(fc, audioIndex, ticks, 1)
            avcodec_flush_buffers(cc)
            if let packet { av_packet_unref(packet) }
            if let frame { av_frame_unref(frame) }
            packetPending = false; pendingOpened = nil; lastTiming = nil
            revision += 1; self.correlation = correlation
            if rc < 0 {
                poisoned = true; feedState = .terminal; landingTarget = nil
                return .closeRequired(binding: bindingOnQueue(), correlation: correlation, nativeCode: rc)
            }
            feedState = .reading; landingTarget = common
            return .nativeReady(binding: bindingOnQueue(), correlation: correlation, commonTarget: common, seekTicks: ticks)
        }
    }
    public func nextEvent(session: SessionID) async -> AudioDecodeEvent? {
        nativeQueue.sync {
            guard pullMode != .bound else { return nil }
            guard active, activeSid == session.epoch else { return nil }
            pullMode = .legacy
            return pullOnQueue(epoch: session.epoch)
        }
    }
    public func nextBoundEvent(binding: AudioSourceBinding) async -> AudioEventEnvelope? {
        nativeQueue.sync {
            guard active, binding == bindingOnQueue(), !poisoned, pullMode != .legacy else { return nil }
            pullMode = .bound
            guard let event = pullOnQueue(epoch: binding.session) else { return nil }
            return AudioEventEnvelope(binding: bindingOnQueue(), correlation: correlation, event: event, timing: lastTiming)
        }
    }
    private func pullOnQueue(epoch: UInt64) -> AudioDecodeEvent? {
        guard active, epoch == activeSid, !poisoned,
              let fc = fmt, let cc = codec, let pkt = packet, let fr = frame else { return nil }
        self.lastTiming = nil
        if let opened = pendingOpened { pendingOpened = nil; return opened }
        if self.feedState == .terminal { return nil }
        func fail(_ code: Int32, _ summary: String) -> AudioDecodeEvent {
            av_frame_unref(fr); av_packet_unref(pkt)
            self.packetPending = false; self.feedState = .terminal
            return .failed(code: Int(code), summary: summary)
        }
        while true {
            let rc = avcodec_receive_frame(cc, fr)
            if rc == 0 {
                // Copy this exact receive result before the next receive,
                // including frames produced after the single nil-send.
                guard fr.pointee.format == AV_SAMPLE_FMT_S16.rawValue else {
                    return fail(-16, "non-s16 sample format \(fr.pointee.format); packed copy refused")
                }
                let ch = Int(fr.pointee.ch_layout.nb_channels)
                let rate = Int(fr.pointee.sample_rate)
                let samples = Int(fr.pointee.nb_samples)
                guard ch > 0, rate > 0, samples > 0,
                      ch <= Self.maxFrameBytes / 2,
                      samples <= Self.maxFrameBytes / (ch * 2),
                      let base = fr.pointee.data.0 else {
                    return fail(-15, "unbounded or absent PCM plane")
                }
                guard self.nextHandle < UInt64.max else {
                    return fail(-17, "PCM handle exhausted")
                }
                var trim = 0
                self.lastTiming = nil
                if self.pullMode == .bound {
                    guard let desc = self.descriptor, fr.pointee.pts != gorav_av_nopts_value() else {
                        return fail(-18, "bound PCM timestamp/timebase missing")
                    }
                    // Decoder-owned skip processing is normally applied
                    // before output. Unconsumed skip side data is not
                    // silently ignored or applied twice here.
                    guard av_frame_get_side_data(fr, AV_FRAME_DATA_SKIP_SAMPLES) == nil else {
                        return fail(-20, "unconsumed audio skip/discard side data unsupported")
                    }
                    do {
                        let pts = fr.pointee.pts
                        let start = try AudioMediaTime.timestamp(pts, timebase: desc.audioTimebase)
                        let target = self.landingTarget
                        if let target {
                            let count = try AudioMediaTime.trimSamples(target: target, frameStart: start, rate: Int32(rate))
                            if count >= Int64(samples) { av_frame_unref(fr); continue }
                            trim = Int(count)
                        }
                        let first = try AudioMediaTime.add(start, RationalTime(value: Int64(trim), timescale: Int32(rate)))
                        let gap = try target.map { try AudioMediaTime.subtract(first, $0) }
                        self.lastTiming = AudioPCMTiming(decodedPTS: pts, streamTimebase: desc.audioTimebase,
                            trimmedSamples: trim, firstSample: first, seekTarget: target, gapFromTarget: gap)
                        self.landingTarget = nil
                    } catch { return fail(-19, "bound PCM rational conversion overflow") }
                }
                let keptSamples = samples - trim
                let n = keptSamples * ch * 2
                let bytes = Array(UnsafeBufferPointer(start: base.advanced(by: trim * ch * 2), count: n))
                let h = self.nextHandle; self.nextHandle += 1
                av_frame_unref(fr)
                return .pcm(AudioPCMFrame(handle: h, samples: keptSamples, channels: ch, sampleRate: rate, bytes: bytes))
            }
            if rc == gorav_av_err_eof() {
                guard self.feedState == .draining else {
                    return fail(rc, "decoder EOF before drain admission")
                }
                self.feedState = .terminal
                return .endOfStream
            }
            guard rc == gorav_av_err_eagain() else { return fail(rc, "receive failed") }
            guard self.feedState == .reading else {
                // Accepted drain input must receive through EOF, not ask
                // for more packets or send a second nil packet.
                return fail(rc, "decoder requested input after accepted drain")
            }
            if !self.packetPending {
                while true {
                    let readRC = av_read_frame(fc, pkt)
                    if readRC == gorav_av_err_eof() {
                        av_packet_unref(pkt)
                        let flushRC = avcodec_send_packet(cc, nil)
                        guard flushRC >= 0 else { return fail(flushRC, "drain flush send failed") }
                        self.feedState = .draining
                        break
                    }
                    guard readRC >= 0 else { return fail(readRC, "av_read_frame failed") }
                    if pkt.pointee.stream_index == self.audioIndex {
                        self.packetPending = true
                        break
                    }
                    av_packet_unref(pkt)
                }
            }
            if self.packetPending {
                let sendRC = avcodec_send_packet(cc, pkt)
                // A send EAGAIN immediately following receive EAGAIN
                // violates the codec API progress guarantee. Do not drop
                // the packet and pretend decoding succeeded, or spin.
                guard sendRC >= 0 else { return fail(sendRC, "send failed after receive EAGAIN") }
                av_packet_unref(pkt); self.packetPending = false
            }
        }
    }

    public func close(session: SessionID) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            nativeQueue.sync {
                guard session.epoch == self.activeSid else { cont.resume(); return }
                self.activeSid = nil; self.pendingOpened = nil
                self.sourceUUID = nil; self.descriptor = nil; self.landingTarget = nil; self.lastTiming = nil
                self.feedState = .terminal; self.packetPending = false
                if let pkt = self.packet { var p: UnsafeMutablePointer<AVPacket>? = pkt; av_packet_free(&p); self.packet = nil }
                if let fr = self.frame { var f: UnsafeMutablePointer<AVFrame>? = fr; av_frame_free(&f); self.frame = nil }
                if let cc = self.codec { var c: UnsafeMutablePointer<AVCodecContext>? = cc; avcodec_free_context(&c); self.codec = nil }
                if let fc = self.fmt { var f: UnsafeMutablePointer<AVFormatContext>? = fc; avformat_close_input(&f); self.fmt = nil }
                self.active = false
                cont.resume()
            }
        }
    }
}
