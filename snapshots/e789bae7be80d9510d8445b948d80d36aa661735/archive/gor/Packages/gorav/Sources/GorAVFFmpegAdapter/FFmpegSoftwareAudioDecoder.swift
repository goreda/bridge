// AUTHORED NEW (2026-10-17, review desk): audio probe adapter, K4 scope.
// Separate from the video adapter. M1 admits PCM WAV, or exactly one
// AAC/PCM audio stream beside one video stream in MOV or Matroska.
// Probe class: bounded copies, typed refusals, explicit teardown. No clock,
// no playback pacing here - pacing belongs to the playback core (K6 core).
import Foundation
import CFFmpeg
import GorAVCore
import GorAVNativeProbeKit
import GorAVPlaybackCore

public struct AudioPCMFrame: Equatable, Sendable {
    public let handle: UInt64
    public let samples: Int          // per channel
    public let channels: Int
    public let sampleRate: Int
    public let bytes: [UInt8]        // bounded visible PCM copy (packed s16le)
}

/// d13 (queue 8): the device-facing audio format is an explicit open-time input.
/// Output frames always carry this format. The only value the sink currently
/// accepts is the existing sink contract (packed s16le stereo 44.1 kHz); any
/// other request is refused at open, never silently coerced. Mismatching
/// sources are converted sink-side by the existing swresample-backed
/// L3SampleConverter (no new resampler).
public struct AudioOutFormat: Equatable, Sendable {
    public let rate: Int
    public let channels: Int
    public init(rate: Int, channels: Int) { self.rate = rate; self.channels = channels }
    public static let sinkContract = AudioOutFormat(rate: Int(L3SampleConverter.outputRate), channels: L3SampleConverter.outputChannels)
}

public enum AudioDecodeEvent: Equatable, Sendable {
    /// sampleRate/channels are the SOURCE-native values read from the codec
    /// context; contractRate/contractChannels are the open-time device format
    /// every pcm event will carry (d13: detected vs contracted).
    case opened(codec: String, sampleRate: Int, channels: Int, contractRate: Int, contractChannels: Int)
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
    case decoderResetUnavailable
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
    /// Converted-audio input continuity tolerance for one stream: the COARSER
    /// of one container-timebase tick and one audio sample period. A 90 kHz
    /// (mpegts) container tick (11.1 us) is finer than one sample at 44.1 kHz
    /// (22.7 us); measured live (2026-11-16 mux segment leg): the container PTS
    /// ladder is not sample-aligned and per-frame offsets from a sample-exact
    /// cursor oscillate within +/-0.61 samples without accumulating, so a
    /// one-container-tick gate kills continuous audio. Sub-sample differences
    /// cannot be gap-filled (silence fill works in whole samples) and signal
    /// no missing audio. The Matroska case below keeps its 1 ms container tick,
    /// which is coarser than one sample.
    public static func continuityTick(containerTimebase: RationalTime, audioRate: Int32) throws -> RationalTime {
        guard audioRate > 0 else { throw SeekTimeError.invalidTimescale }
        let sampleTick = try RationalTime(value: 1, timescale: audioRate)
        return containerTimebase < sampleTick ? sampleTick : containerTimebase
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
    /// R3 (arch-195b): transport options consumed by the next remote open.
    /// Read on the native queue at open time; never logged (see redactedSummary).
    private let remoteOptionsLock = NSLock()
    private var storedRemoteOptions = SourceOpenOptions()
    public var remoteOpenOptions: SourceOpenOptions {
        get { remoteOptionsLock.lock(); defer { remoteOptionsLock.unlock() }; return storedRemoteOptions }
        set { remoteOptionsLock.lock(); storedRemoteOptions = newValue; remoteOptionsLock.unlock() }
    }

    private enum PullMode { case unset, legacy, bound }
    private var pullMode: PullMode = .unset
    private var sourceUUID: UUID?
    private var revision: UInt64 = 1
    private var correlation: UInt64?
    private var descriptor: AudioSeekDescriptor?
    private var landingTarget: RationalTime?
    private var lastTiming: AudioPCMTiming?
    private var poisoned = false

    private let decoderInventory: DecoderInventoryStore
    private var decoderInventoryID: DecoderIdentity?
    private var cachedMediaInventory: MediaInventory?
    private let decoderQueueKey = DispatchSpecificKey<UInt8>()
    private func deregisterDecoderOnQueue() {
        cachedMediaInventory=nil
        if let id=decoderInventoryID { decoderInventory.deregister(id) }
        decoderInventoryID=nil
    }
    /// Queue-owned cache from the actual active context; no remote re-open.
    public func activeMediaInventory(session:SessionID,
                                    expected:ActiveMediaInventoryIdentity? = nil) -> ActiveMediaInventorySnapshot? {
        guard DispatchQueue.getSpecific(key:decoderQueueKey) == nil else { return nil }
        return nativeQueue.sync {
            guard self.active, !self.poisoned, self.activeSid == session.epoch,
                  let source=self.sourceUUID, let inventory=self.cachedMediaInventory else { return nil }
            let identity=ActiveMediaInventoryIdentity(sourceID:source.uuidString,
                session:session.epoch,revision:self.revision)
            guard expected == nil || expected == identity else { return nil }
            return ActiveMediaInventorySnapshot(identity:identity,inventory:inventory)
        }
    }
    /// Explicit source policy, never a timestamp-guard bypass. Default rejects
    /// discontinuities. Positive gaps at most this many SOURCE samples may be
    /// filled with real digital silence. Overlap/fractional/large gaps refuse.
    private let positiveGapLimitSamples: Int
    public private(set) var filledGapInputSamples: Int64 = 0
    public init(decoderInventory: DecoderInventoryStore = .shared, positiveGapLimitSamples: Int = 0) {
        self.positiveGapLimitSamples = positiveGapLimitSamples
        self.decoderInventory=decoderInventory
        nativeQueue.setSpecific(key:decoderQueueKey,value:1)
    }
    // 195b-54: bounded cancellation/deadline for remote open + stream-info.
    // Mirrors the video adapter's interrupt fence (attempt-local slot,
    // session fence, ioOnly capability) and adds a monotonic open deadline.
    // The slot pointer is nil until a remote open commits it to the session.
    private let interruptSlot = SessionInterruptSlot()
    private final class AudioInterruptBox {
        private let lock = NSLock()
        private var flag = false
        private var deadlineNanos: UInt64?
        func set() { lock.lock(); flag = true; lock.unlock() }
        func reset(deadlineNanos: UInt64?) { lock.lock(); flag = false; self.deadlineNanos = deadlineNanos; lock.unlock() }
        func clearDeadline() { lock.lock(); deadlineNanos = nil; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flag }
        var deadlineExceeded: Bool {
            lock.lock(); defer { lock.unlock() }
            guard !flag, let d = deadlineNanos else { return false }
            return DispatchTime.now().uptimeNanoseconds >= d
        }
        var shouldAbort: Bool {
            lock.lock(); defer { lock.unlock() }
            if flag { return true }
            guard let d = deadlineNanos else { return false }
            return DispatchTime.now().uptimeNanoseconds >= d
        }
    }
    private let interruptBox = AudioInterruptBox()
    private var interruptSlotPtr: UnsafeMutablePointer<GorAVInterruptSlot>?

    /// ioOnly at best: aborts blocking demux/AVIO calls that poll the
    /// callback; never interrupts a stuck decode.
    public var interruptCapability: InterruptCapability { .ioOnly }

    /// Ask the provider to abort the current session's blocking open/read.
    /// A request for any other (stale) session is a fenced no-op.
    public func requestInterrupt(session: SessionID) {
        interruptSlot.request(session: session.epoch)
    }

    private func teardownInterruptLocked() {
        interruptSlot.clear()
        if let slot = interruptSlotPtr {
            slot.deinitialize(count: 1)
            slot.deallocate()
            interruptSlotPtr = nil
        }
    }

    /// Credential-free failure classification: interrupted and deadline
    /// exceeded are named plainly; provider failures carry the redacted URL
    /// only. No header, cookie or URL component ever appears.
    private func remoteOpenFailure(_ phase: String, _ rc: Int32, _ openPath: String) -> AudioOpenError {
        if interruptBox.isSet { return .rejected("\(phase) interrupted") }
        if interruptBox.deadlineExceeded { return .rejected("\(phase) deadline exceeded") }
        return .rejected("\(phase) failed \(rc) for \(URLRedaction.redact(openPath))")
    }


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

    /// R6 (arch-195l): when preferredAudioStreamIndex is set, the open binds
    /// THAT container stream instead of the first audio stream; a missing or
    /// non-audio index is a typed refusal. nil keeps the historical behavior.
    public func open(source: SourceDescriptor, session: SessionID, format: AudioOutFormat = .sinkContract, preferredAudioStreamIndex: Int32? = nil) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            nativeQueue.sync {
                // 195b-54 (attempt-local pattern from the video adapter): the
                // slot is visible to failure teardown, and the fence clear in
                // catch may only run if THIS attempt installed it.
                var attemptSlotForTeardown: UnsafeMutablePointer<GorAVInterruptSlot>?
                var attemptFenceInstalled = false
                do {
                    guard !active else { throw AudioOpenError.sessionBusy }
                    guard (0...96000).contains(positiveGapLimitSamples) else { throw AudioOpenError.rejected("invalid positive gap limit") }
                    filledGapInputSamples = 0
                    guard session.epoch != 0 else { throw AudioOpenError.rejected("zero session") }
                    guard format == .sinkContract else {
                        throw AudioOpenError.rejected("device format \(format.rate) Hz x\(format.channels) not supported: sink contract is \(AudioOutFormat.sinkContract.rate) Hz x\(AudioOutFormat.sinkContract.channels) packed s16le")
                    }
                    guard source.kind == .local || AdmissionTable.schemeGatedKinds.contains(source.kind) else { throw AudioOpenError.rejected("local sources only") }
                    let openPath: String
                    if AdmissionTable.schemeGatedKinds.contains(source.kind) {
                        // R3 (arch-195b): remote admission mirrors the video decoder - decided
                        // HERE, before any network access. Scheme allowlist only (http, https).
                        // Error strings carry the redacted URL only, never userinfo or query values.
                        guard AdmissionTable.isAdmittedRemoteURL(source.id) else {
                            throw AudioOpenError.rejected("scheme not admitted: \(AdmissionTable.remoteScheme(of: source.id) ?? "(none)")")
                        }
                        openPath = source.id
                    } else {
                        guard source.id.hasPrefix("/"), !source.id.contains("://") else {
                            throw AudioOpenError.rejected("absolute local path only")
                        }
                        let resolved = URL(fileURLWithPath: source.id).resolvingSymlinksInPath().standardizedFileURL
                        guard pinnedRoots.contains(where: { resolved.path == $0.path || resolved.path.hasPrefix($0.path + "/") }) else {
                            throw AudioOpenError.rejected("outside pinned roots")
                        }
                        openPath = resolved.path
                    }
                    var f: UnsafeMutablePointer<AVFormatContext>?
                    var rc: Int32
                    let fc: UnsafeMutablePointer<AVFormatContext>
                    if AdmissionTable.schemeGatedKinds.contains(source.kind) {
                        // 195b-54: per-open immutable validated options. The
                        // dictionary is copied and validated HERE, before any
                        // network access; a later remoteOpenOptions write
                        // cannot mutate this attempt, and injected CR/LF/NUL
                        // or an invalid deadline is a typed refusal instead
                        // of the transport's bare -22.
                        let options: SourceOpenOptions
                        do { options = try remoteOpenOptions.validatedForOpen() }
                        catch { throw AudioOpenError.rejected("invalid remote open options") }
                        // Interrupt plumbing BEFORE any blocking provider
                        // call: the slot is OPEN-ATTEMPT-LOCAL until commit.
                        // The sessionBusy rejection above throws before this
                        // point, so this fence install cannot shadow a live
                        // session.
                        interruptBox.reset(deadlineNanos: options.openDeadlineNanos())
                        interruptSlot.install(session: session.epoch) { [interruptBox] in interruptBox.set() }
                        attemptFenceInstalled = true
                        let attemptSlot = UnsafeMutablePointer<GorAVInterruptSlot>.allocate(capacity: 1)
                        attemptSlotForTeardown = attemptSlot
                        attemptSlot.initialize(to: GorAVInterruptSlot(
                            poll: { opaque in
                                guard let opaque = opaque else { return 0 }
                                return Unmanaged<AudioInterruptBox>.fromOpaque(opaque).takeUnretainedValue().shouldAbort ? 1 : 0
                            },
                            opaque: Unmanaged.passUnretained(interruptBox).toOpaque()))
                        // Pre-allocated context: the interrupt callback is
                        // armed BEFORE the URL open itself, so remote open
                        // AND stream info are both interruptible. The video
                        // adapter's remote path installs the callback after
                        // open and only covers later reads; audio closes
                        // that gap.
                        guard let allocated = avformat_alloc_context() else {
                            throw AudioOpenError.rejected("format context allocation failed")
                        }
                        allocated.pointee.interrupt_callback = AVIOInterruptCB(
                            callback: gorav_avio_interrupt_thunk,
                            opaque: UnsafeMutableRawPointer(attemptSlot))
                        f = allocated
                        rc = goravR3OpenInput(&f, url: openPath, options: options)
                        guard rc >= 0, let opened = f else {
                            // Open failure frees the context and NULLs the
                            // pointer; defensive cleanup for any remainder.
                            if let remaining = f { avformat_free_context(remaining); f = nil }
                            throw remoteOpenFailure("open", rc, openPath)
                        }
                        rc = avformat_find_stream_info(opened, nil)
                        guard rc >= 0 else {
                            var closing: UnsafeMutablePointer<AVFormatContext>? = opened
                            avformat_close_input(&closing); f = nil
                            throw remoteOpenFailure("stream info", rc, openPath)
                        }
                        fc = opened
                    } else {
                        rc = avformat_open_input(&f, openPath, nil, nil)
                        guard rc >= 0, let opened = f else { throw AudioOpenError.rejected("avformat_open_input failed \(rc) for local") }
                        rc = avformat_find_stream_info(opened, nil)
                        guard rc >= 0 else { avformat_close_input(&f); throw AudioOpenError.rejected("stream info failed \(rc)") }
                        fc = opened
                    }
                    let container = String(cString: fc.pointee.iformat.pointee.name)
                    var audioCount = 0, videoCount = 0, otherCount = 0, subtitleCount = 0, aIndex: Int32 = -1
                    var videoCodecName: String?
                    // R6: validate the explicit index against this container's
                    // own streams; out of range or non-audio is a typed refusal,
                    // never a silent fallback to first-audio.
                    if let preferred = preferredAudioStreamIndex {
                        guard preferred >= 0, preferred < Int32(fc.pointee.nb_streams) else {
                            var closing: UnsafeMutablePointer<AVFormatContext>? = fc
                            avformat_close_input(&closing)
                            throw AudioOpenError.rejected("audio track index \(preferred) out of range")
                        }
                        let pt = fc.pointee.streams[Int(preferred)]?.pointee.codecpar?.pointee.codec_type ?? AVMEDIA_TYPE_UNKNOWN
                        guard pt == AVMEDIA_TYPE_AUDIO else {
                            var closing: UnsafeMutablePointer<AVFormatContext>? = fc
                            avformat_close_input(&closing)
                            throw AudioOpenError.rejected("audio track index \(preferred) is not audio")
                        }
                        aIndex = preferred
                    }
                    for i in 0..<Int32(fc.pointee.nb_streams) {
                        switch fc.pointee.streams[Int(i)]?.pointee.codecpar?.pointee.codec_type ?? AVMEDIA_TYPE_UNKNOWN {
                        case AVMEDIA_TYPE_AUDIO: audioCount += 1; if aIndex < 0 { aIndex = i }
                        case AVMEDIA_TYPE_VIDEO:
                            videoCount += 1
                            if let videoID = fc.pointee.streams[Int(i)]?.pointee.codecpar?.pointee.codec_id {
                                videoCodecName = String(cString: avcodec_get_name(videoID))
                            }
                        default:
                            if fc.pointee.streams[Int(i)]?.pointee.codecpar?.pointee.codec_type == AVMEDIA_TYPE_SUBTITLE { subtitleCount += 1 } else { otherCount += 1 }
                        }
                    }
                    let codecID = aIndex >= 0 ? (fc.pointee.streams[Int(aIndex)]?.pointee.codecpar?.pointee.codec_id ?? AV_CODEC_ID_NONE) : AV_CODEC_ID_NONE
                    let codecName = String(cString: avcodec_get_name(codecID))
                    // Card 465 bounded muxed sibling profile, widened per
                    // arch-196t r2 item 4a: beside the pure-wav fixture shape,
                    // admit the real-media muxed profile (admitted container +
                    // admitted audio codec, exactly one audio next to exactly one
                    // video, no unknown stream types). Embedded subtitle streams
                    // are admitted and counted separately; routing them to the
                    // subtitle seams is a playback-path wiring step.
                    let wavProfile = container == "wav" && audioCount == 1 && videoCount == 0 && otherCount == 0 && codecName == "pcm_s16le"
                    let muxedMovProfile = AdmissionTable.isAdmittedMuxedAudio(container: container, audioCodec: codecName) && audioCount == 1 && videoCount == 1 && otherCount == 0
                        && videoCodecName.map(AdmissionTable.videoCodecs.contains) == true
                    _ = subtitleCount
                    guard wavProfile || muxedMovProfile else {
                        avformat_close_input(&f)
                        throw AudioOpenError.rejected("admission: container=\(container) audio=\(audioCount) video=\(videoCount) other=\(otherCount) subtitles=\(subtitleCount) codec=\(codecName) videoCodec=\(videoCodecName ?? "none")")
                    }
                    guard let dec = avcodec_find_decoder(codecID) else {
                        avformat_close_input(&f); throw AudioOpenError.rejected("no decoder for admitted codec \(codecName)")
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
                    // d13: aac always converts (existing M1 path); a source whose
                    // native rate/layout differs from the open-time contract is
                    // routed through the same sink-side converter.
                    // arch-196t item 4 (real-media audio matrix): every non-PCM
                    // codec converts - decoded DTS/AC3/EAC3/Opus/FLAC/TrueHD/MP3
                    // frames are typically fltp planar; without the converter a
                    // native-44.1k-stereo compressed stream would feed planar
                    // floats to the packed-s16 sink unreadably.
                    let nativeRate = Int(cc.pointee.sample_rate)
                    let nativeChannels = Int(cc.pointee.ch_layout.nb_channels)
                    let mismatch = nativeRate != format.rate || nativeChannels != format.channels
                    self.m1Converter = (codecName != "pcm_s16le" || mismatch) ? L3SampleConverter() : nil
                    self.m1TailDrained = false; self.m1OutputCursor = nil; self.m1InputCursor = nil
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
                        // R6 (arch-195b): raw PCM in a seekable audio-only container has an
                        // exact zero origin - the first byte is the first sample. A missing
                        // start_time there invents nothing, so fall back to t=0 in the audio
                        // stream timebase instead of refusing every seek with unknownOrigin.
                        // Compressed streams keep the refusal: their first PTS is not derivable.
                        if reference == nil, !muxedMovProfile, source.seekable, codecName.hasPrefix("pcm_") {
                            reference = try? AudioMediaTime.timestamp(0, timebase: tb)
                        }
                        self.descriptor = AudioSeekDescriptor(binding: self.bindingOnQueue(),
                            seekable: source.seekable && reference != nil, audioStreamIndex: aIndex,
                            audioTimebase: tb, audioStart: audioStart, referenceOrigin: reference,
                            referenceIsVideo: muxedMovProfile)
                        // W073 D3 priming-codec fix: pre-origin audio packets
                        // (first audio PTS precedes the video reference origin,
                        // e.g. AAC-in-matroska: audio pts 0, video start 21 ms)
                        // are encoder-delay priming, not content. Fresh open and
                        // seek(0) must deliver the same byte sequence, so they
                        // are dropped on EVERY read (see the read loop).
                        self.headFloorTicks = reference.flatMap {
                            try? $0.floorTicks(toTimebaseNumerator: tb.value, denominator: Int64(tb.timescale))
                        }
                    } else { self.descriptor = nil; self.headFloorTicks = nil }
                    self.pendingOpened = .opened(codec: codecName, sampleRate: nativeRate, channels: nativeChannels,
                                                 contractRate: format.rate, contractChannels: format.channels)
                    cachedMediaInventory=MediaInventory.extract(fromOpenedContext:fc)
                    self.decoderInventoryID=self.decoderInventory.register(session:session.epoch,
                        kind:.audioSoftware,codec:codecName,
                        sourceID:self.sourceUUID!.uuidString,revisionAtOpen:self.revision)
                    // 195b-54 commit: the attempt-local slot becomes
                    // session-owned so requestInterrupt reaches streaming
                    // reads. The deadline bounds open + stream-info only;
                    // later reads answer cancellation, not a stale clock.
                    if attemptFenceInstalled {
                        self.interruptSlotPtr = attemptSlotForTeardown
                        attemptSlotForTeardown = nil
                    }
                    interruptBox.clearDeadline()
                    cont.resume()
                } catch {
                    // 195b-54: a failed attempt tears down ONLY its own fence
                    // and slot storage; a rejection before install (e.g.
                    // sessionBusy) must not touch another session's live
                    // interrupt route.
                    if attemptFenceInstalled { interruptSlot.clear() }
                    if let slot = attemptSlotForTeardown {
                        slot.deinitialize(count: 1)
                        slot.deallocate()
                    }
                    interruptBox.clearDeadline()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // M1 consumes the existing bounded L3 converter without replacing NH6's
    // rational, request-bound packet state machine. Converted-audio seeking
    // is explicitly refused until resampler phase is bound to that contract.
    private var m1Converter: L3SampleConverter?
    private var m1TailDrained = false
    private var m1OutputCursor: RationalTime?
    private var m1InputCursor: RationalTime?
    private var headFloorTicks: Int64?

    private func bindingOnQueue() -> AudioSourceBinding {
        AudioSourceBinding(source: sourceUUID!, session: activeSid!, revision: revision)
    }
    /// Queue-serialized live identity check for a video-only prepared handoff.
    /// This does not seek, flush, restart or consume PCM.
    public func preparedShotBinding(session: SessionID) -> AudioSourceBinding? {
        nativeQueue.sync {
            guard active, activeSid == session.epoch, !poisoned,
                  feedState != .terminal, sourceUUID != nil else { return nil }
            return bindingOnQueue()
        }
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
            // Prepare AAC decoder replacement BEFORE any demux mutation.
            // FFmpeg AAC flush clears overlap but intentionally retains its
            // noise-generator state. A new codec gives repeat seeks the same
            // initial decoder state and cannot carry old-generation samples.
            var replacement: UnsafeMutablePointer<AVCodecContext>?
            if m1Converter != nil {
                guard let parameters = fc.pointee.streams[Int(audioIndex)]?.pointee.codecpar,
                      let decoder = avcodec_find_decoder(parameters.pointee.codec_id),
                      let fresh = avcodec_alloc_context3(decoder) else {
                    return .refused(.decoderResetUnavailable)
                }
                replacement = fresh
                let copied = avcodec_parameters_to_context(fresh, parameters)
                fresh.pointee.pkt_timebase = fc.pointee.streams[Int(audioIndex)]!.pointee.time_base
                guard copied >= 0, avcodec_open2(fresh, decoder, nil) >= 0 else {
                    avcodec_free_context(&replacement)
                    return .refused(.decoderResetUnavailable)
                }
            }
            self.pullMode = .bound
            // Queue serialization fences all provider reads. It cannot revoke
            // bytes returned earlier; composition must stop/quarantine producer.
            let rc = av_seek_frame(fc, audioIndex, ticks, 1)
            avcodec_flush_buffers(cc)
            if let fresh = replacement {
                var old: UnsafeMutablePointer<AVCodecContext>? = cc
                avcodec_free_context(&old)
                self.codec = fresh
            }
            if let packet { av_packet_unref(packet) }
            if let frame { av_frame_unref(frame) }
            packetPending = false; pendingOpened = nil; lastTiming = nil
            // Fresh converter drops all pre-seek delay/configuration. No stale
            // resampler bytes cross the binding revision. Initialization is
            // lazy on the first post-seek frame, whose exact PTS anchors it.
            if m1Converter != nil { m1Converter = L3SampleConverter() }
            m1TailDrained = false; m1OutputCursor = nil; self.m1InputCursor = nil
            revision += 1; self.correlation = correlation
            if rc < 0 {
                deregisterDecoderOnQueue()
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
    private func emitConvertedChunk(_ chunk: (bytes: [UInt8], samples: Int), decodedPTS: Int64) throws -> AudioDecodeEvent? {
        guard let start = m1OutputCursor else { throw SeekTimeError.invalidTimescale }
        m1OutputCursor = try AudioMediaTime.add(start, RationalTime(value: Int64(chunk.samples), timescale: 44100))
        var trim = 0
        if pullMode == .bound {
            guard let desc = descriptor else { throw SeekTimeError.invalidTimescale }
            if let target = landingTarget {
                let count = try AudioMediaTime.trimSamples(target: target, frameStart: start, rate: 44100)
                if count >= Int64(chunk.samples) { return nil }
                trim = Int(count)
            }
            let first = try AudioMediaTime.add(start, RationalTime(value: Int64(trim), timescale: 44100))
            lastTiming = AudioPCMTiming(decodedPTS: decodedPTS, streamTimebase: desc.audioTimebase,
                trimmedSamples: trim, firstSample: first, seekTarget: landingTarget,
                gapFromTarget: try landingTarget.map { try AudioMediaTime.subtract(first, $0) })
            landingTarget = nil
        }
        guard nextHandle < UInt64.max else { throw AudioSeekRefusal.exhausted }
        let h = nextHandle; nextHandle += 1
        return .pcm(AudioPCMFrame(handle: h, samples: chunk.samples-trim, channels: 2, sampleRate: 44100,
            bytes: Array(chunk.bytes.dropFirst(trim*4))))
    }

    private func pullOnQueue(epoch: UInt64) -> AudioDecodeEvent? {
        guard active, epoch == activeSid, !poisoned,
              let fc = fmt, let cc = codec, let pkt = packet, let fr = frame else { return nil }
        self.lastTiming = nil
        if let opened = pendingOpened { pendingOpened = nil; return opened }
        if self.feedState == .terminal { return nil }
        func fail(_ code: Int32, _ summary: String) -> AudioDecodeEvent {
            deregisterDecoderOnQueue()
            av_frame_unref(fr); av_packet_unref(pkt)
            self.packetPending = false; self.feedState = .terminal
            return .failed(code: Int(code), summary: summary)
        }
        while true {
            let rc = avcodec_receive_frame(cc, fr)
            if rc == 0 {
                if let converter = m1Converter {
                    // Emission timeline uses an exact rational origin plus
                    // the number of output samples, never rounded seconds.
                    // Read provider delay BEFORE convert consumes this frame.
                    let inputRate = fr.pointee.sample_rate
                    guard inputRate > 0 else { return fail(-34, "converted-audio input rate invalid") }
                    guard let inputDescriptor = descriptor, fr.pointee.pts != gorav_av_nopts_value() else {
                        return fail(-34, "converted-audio input timeline missing")
                    }
                    var gapPrefix: (bytes: [UInt8], samples: Int) = ([], 0)
                    var filledInputGap = false
                    do {
                        let actual = try AudioMediaTime.timestamp(fr.pointee.pts, timebase: inputDescriptor.audioTimebase)
                        if let expected = m1InputCursor {
                            let difference = try AudioMediaTime.subtract(actual, expected)
                            let tick = try AudioMediaTime.continuityTick(containerTimebase: inputDescriptor.audioTimebase, audioRate: inputRate)
                            let negativeTick = try RationalTime(value: -tick.value, timescale: tick.timescale)
                            // Matroska timebases may quantize an AAC sample boundary
                            // by one stream tick. Anything beyond this is a real
                            // discontinuity, not a continuous output timeline.
                            // The tolerance is the coarser of one stream tick and
                            // one audio sample (AudioMediaTime.continuityTick):
                            // on a 90 kHz mpegts clock one stream tick is finer
                            // than one sample, and measured sub-sample ladder
                            // noise (+/-0.61 samples, non-accumulating) is not a
                            // discontinuity and cannot be gap-filled.
                            if difference < negativeTick || difference > tick {
                                let gap = try difference.floorTicks(toTimebaseNumerator: 1, denominator: Int64(inputRate))
                                guard positiveGapLimitSamples > 0, gap > 0, gap <= Int64(positiveGapLimitSamples),
                                      try RationalTime(value: gap, timescale: inputRate) == difference else {
                                    return fail(-35, "converted-audio input PTS discontinuity exceeds one stream tick: actual=\(actual) expected=\(expected)")
                                }
                                guard let silentFrame = gorav_audio_gap_silence(fr, Int32(gap)) else {
                                    return fail(-36, "converted-audio silence allocation failed")
                                }
                                var releasing: UnsafeMutablePointer<AVFrame>? = silentFrame
                                let filled = converter.convert(frame: silentFrame, maxFrameBytes: Self.maxFrameBytes)
                                av_frame_free(&releasing)
                                guard let filled else { return fail(-36, "converted-audio gap conversion failed") }
                                filledInputGap = true
                                gapPrefix = filled
                                filledGapInputSamples += gap
                            }
                        }
                        let inputStart = filledInputGap ? actual : (m1InputCursor ?? actual)
                        m1InputCursor = try AudioMediaTime.add(inputStart, RationalTime(value: Int64(fr.pointee.nb_samples), timescale: inputRate))
                    } catch { return fail(-19, "converted-audio input timeline arithmetic overflow") }
                    if m1OutputCursor == nil {
                        guard let desc = descriptor, fr.pointee.pts != gorav_av_nopts_value() else {
                            return fail(-34, "converted-audio output origin missing")
                        }
                        let delay = converter.currentInputDelay(inputRate: Int64(inputRate))
                        guard delay >= 0 else { return fail(-34, "converted-audio input delay unavailable") }
                        do {
                            let inputStart = try AudioMediaTime.timestamp(fr.pointee.pts, timebase: desc.audioTimebase)
                            m1OutputCursor = try AudioMediaTime.subtract(inputStart, RationalTime(value: delay, timescale: inputRate))
                        } catch { return fail(-19, "converted-audio origin arithmetic overflow") }
                    }
                    let decodedPTS = fr.pointee.pts
                    guard let converted = converter.convert(frame: fr, maxFrameBytes: Self.maxFrameBytes),
                          converted.bytes.count <= Self.maxFrameBytes - gapPrefix.bytes.count else {
                        return fail(-33, "converted-audio conversion failed")
                    }
                    let chunk = (bytes: gapPrefix.bytes + converted.bytes, samples: gapPrefix.samples + converted.samples)
                    av_frame_unref(fr)
                    if chunk.samples == 0 { continue }
                    do {
                        if let event = try emitConvertedChunk(chunk, decodedPTS: decodedPTS) { return event }
                    } catch { return fail(-19, "converted-audio emitted sample arithmetic overflow") }
                    continue
                }
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
                while let converter = m1Converter, !m1TailDrained {
                    guard let chunk = converter.drain(maxFrameBytes: Self.maxFrameBytes) else {
                        return fail(-33, "converted-audio resampler drain failed")
                    }
                    if chunk.samples > 0 {
                        do {
                            if let event = try emitConvertedChunk(chunk, decodedPTS: gorav_av_nopts_value()) { return event }
                        } catch { return fail(-19, "converted-audio drain timing overflow") }
                    } else { m1TailDrained = true }
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
                        // Pre-origin head packet: before the video reference
                        // origin, never delivered. seek(0) BACKWARD landing
                        // skips exactly these demuxer-side, so open must too
                        // (D3 == D1); mid-stream BACKWARD landings can also
                        // deliver them, and skipping keeps the trim target and
                        // codec state consistent with the head seek.
                        if let floorTicks = self.headFloorTicks,
                           pkt.pointee.pts != gorav_av_nopts_value(),
                           pkt.pointee.pts < floorTicks {
                            av_packet_unref(pkt)
                            continue
                        }
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
                self.deregisterDecoderOnQueue()
                // Fence new requests now, but keep callback storage alive until
                // provider teardown completes. Nested protocol contexts may
                // hold copies of AVIOInterruptCB, including TLS shutdown.
                if let ctx = self.fmt {
                    ctx.pointee.interrupt_callback = AVIOInterruptCB(callback: nil, opaque: nil)
                }
                self.interruptSlot.clear()
                self.activeSid = nil; self.pendingOpened = nil
                self.sourceUUID = nil; self.descriptor = nil; self.landingTarget = nil; self.lastTiming = nil
                self.feedState = .terminal; self.packetPending = false
                if let pkt = self.packet { var p: UnsafeMutablePointer<AVPacket>? = pkt; av_packet_free(&p); self.packet = nil }
                if let fr = self.frame { var f: UnsafeMutablePointer<AVFrame>? = fr; av_frame_free(&f); self.frame = nil }
                if let cc = self.codec { var c: UnsafeMutablePointer<AVCodecContext>? = cc; avcodec_free_context(&c); self.codec = nil }
                if let fc = self.fmt { var f: UnsafeMutablePointer<AVFormatContext>? = fc; avformat_close_input(&f); self.fmt = nil }
                self.teardownInterruptLocked()
                self.m1Converter = nil; self.m1TailDrained = false; self.m1OutputCursor = nil; self.m1InputCursor = nil
                self.active = false
                cont.resume()
            }
        }
    }
    deinit {
        // No queued native operation can outlive the reference it retains.
        // Mirror explicit-close resource teardown for abandoned instances.
        func cleanup() {
            self.deregisterDecoderOnQueue()
            if let ctx = self.fmt { ctx.pointee.interrupt_callback = AVIOInterruptCB(callback: nil, opaque: nil) }
            self.interruptSlot.clear()
            if let pkt=self.packet { var p:UnsafeMutablePointer<AVPacket>?=pkt; av_packet_free(&p) }
            if let fr=self.frame { var f:UnsafeMutablePointer<AVFrame>?=fr; av_frame_free(&f) }
            if let cc=self.codec { var c:UnsafeMutablePointer<AVCodecContext>?=cc; avcodec_free_context(&c) }
            if let fc=self.fmt { var f:UnsafeMutablePointer<AVFormatContext>?=fc; avformat_close_input(&f) }
            self.teardownInterruptLocked()
        }
        if DispatchQueue.getSpecific(key:decoderQueueKey) != nil { cleanup() }
        else { nativeQueue.sync(execute:cleanup) }
    }

}
