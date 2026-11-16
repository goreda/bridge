# M2-TLS-VERIFIED-PCM-01: authenticated encrypted source into product PCM
state: candidate

```packet-json
{
  "packet_id": "M2-TLS-VERIFIED-PCM-01",
  "writer": "gdb",
  "code_owner": "M2-source product lane",
  "product_repo": "goreda/gorav",
  "product_sha": "a34e2cd96b6825932a196424a17cc62962e910a7",
  "touched_files": [
    {
      "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift",
      "excerpt_block": "audio"
    },
    {
      "path": "Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift",
      "excerpt_block": "options"
    },
    {
      "path": "Sources/CFFmpeg/shim.h",
      "excerpt_block": "shim"
    }
  ],
  "interface": {
    "signatures": "SourceOpenOptions(... tlsCAFile: String? = nil); gorav_r3_open_input_verified(...ca_file); FFmpegSoftwareAudioDecoder.close(session:)/deinit ordering repair",
    "types": "optional absolute PEM trust-root path; existing typed source-open refusals; no verification-disable field",
    "ownership_lifetime": "attempt storage survives failed native open; successful session slot survives avformat_close_input and copied protocol callbacks; caller owns trust-root file; dictionaries freed on all branches",
    "caller": "Packet HTTPS integration witness into product decoder",
    "callee": "Engine SourceOpenOptions + C dictionary bridge + measured GnuTLS provider"
  },
  "test": {
    "command": "bash kits/m2-source-packets/tls-verified-canonical.sh",
    "expected": "exit0 inventory0/product0; trusted encrypted PCM equals local toEOF; 403 retained; trustedCA/wronghostname, wrongCA, default-selfsigned all rejected; m2-tls-verified-pcm: all pass. ASAN leak not covered and remains separate RED.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift",
      "Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift",
      "Sources/CFFmpeg/shim.h",
      "kits/m2-source-packets/tls-verified-canonical.sh",
      "kits/m2-source-packets/tls-verified-main.swift",
      "kits/m2-source-packets/protocol-inventory.c"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/GorAVFFmpegAdapter/FFmpegSoftwareAudioDecoder.swift",
        "block": "audio"
      },
      {
        "path": "Sources/GorAVFFmpegAdapter/SourceOpenOptions.swift",
        "block": "options"
      },
      {
        "path": "Sources/CFFmpeg/shim.h",
        "block": "shim"
      },
      {
        "path": "kits/m2-source-packets/tls-verified-canonical.sh",
        "block": "runner"
      },
      {
        "path": "kits/m2-source-packets/tls-verified-main.swift",
        "block": "harness"
      },
      {
        "path": "kits/m2-source-packets/protocol-inventory.c",
        "block": "inventory"
      }
    ]
  }
}
```

## Scope and remaining RED
Supplied lane execution GREEN; fresh ingest replay still required. Loopback encrypted source, CA and hostname negatives, realPCM equality only. No external-service, Darwin/Metal or leak-free claim. Separate ASAN lifecycle run passes assertions but retains32byte product-closure leak pending attribution/repair. Provider must be the exact measured FFmpeg7.1+dav1d+GnuTLS candidate, never arbitrary systemFFmpeg.

## Decision
DR-M2-TLS-01 chooses provider verification over a newTLSAVIO stack; tls_verify=1 always, optional caller trust roots, no bypass. Close-order repair retains storage through nested protocol teardown.

```swift id=audio
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
    public init(decoderInventory: DecoderInventoryStore = .shared) {
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
                        interruptSlot.install(session: session.epoch) { [weak self] in self?.interruptBox.set() }
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
                    } else { self.descriptor = nil }
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
                    do {
                        let actual = try AudioMediaTime.timestamp(fr.pointee.pts, timebase: inputDescriptor.audioTimebase)
                        if let expected = m1InputCursor {
                            let difference = try AudioMediaTime.subtract(actual, expected)
                            let tick = inputDescriptor.audioTimebase
                            let negativeTick = try RationalTime(value: -tick.value, timescale: tick.timescale)
                            // Matroska timebases may quantize an AAC sample boundary
                            // by one stream tick. Anything beyond this is a real
                            // discontinuity, not a continuous output timeline.
                            guard difference >= negativeTick && difference <= tick else {
                                return fail(-35, "converted-audio input PTS discontinuity exceeds one stream tick: actual=\(actual) expected=\(expected)")
                            }
                        }
                        let inputStart = m1InputCursor ?? actual
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
                    guard let chunk = converter.convert(frame: fr, maxFrameBytes: Self.maxFrameBytes) else {
                        return fail(-33, "converted-audio conversion failed")
                    }
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
```

```swift id=options
import Foundation
import GorAVCore
import CFFmpeg

// R3 (arch-195b): production open options for admitted remote source classes
// (http/https per AdmissionTable) plus URL redaction for every string that can
// reach a log or an error. Credentials and query values never leave this file
// in plaintext form.

/// Per-open transport options for remote (scheme-gated) sources. Local opens
/// ignore this value entirely.
public struct SourceOpenOptions: Equatable, Sendable {
    /// Extra HTTP request headers (e.g. Authorization). Keys and values are
    /// emitted verbatim into the request; they are SECRETS-ADJACENT and are
    /// never included in redactedSummary.
    public var headers: [String: String]
    /// HTTP cookies as name=value pairs.
    public var cookies: [String: String]
    /// 195b-54: optional per-open deadline in seconds, bounding the remote
    /// open + stream-info phase only (streaming reads answer cancellation
    /// instead). nil means no deadline. Must be finite, > 0 and <= 86400.
    /// Optional absolute PEM trust-root path, owned by caller. nil uses system
    /// trust. Verification and hostname matching are always enabled.
    public var tlsCAFile: String?
    public var openDeadlineSeconds: Double?
    public init(headers: [String: String] = [:], cookies: [String: String] = [:], openDeadlineSeconds: Double? = nil, tlsCAFile: String? = nil) {
        self.headers = headers
        self.cookies = cookies
        self.tlsCAFile = tlsCAFile
        self.openDeadlineSeconds = openDeadlineSeconds
    }
    /// Log-safe description: counts and presence only, never keys or values.
    public var redactedSummary: String {
        "headers=\(headers.count) cookies=\(cookies.count) deadline=\(openDeadlineSeconds == nil ? "none" : "armed")"
    }
    /// Monotonic-nanosecond deadline for the interrupt box, from `now`.
    /// Validation bounds the value at 86400 s, so the addition cannot wrap.
    func openDeadlineNanos(from now: DispatchTime = .now()) -> UInt64? {
        guard let seconds = openDeadlineSeconds else { return nil }
        return now.uptimeNanoseconds + UInt64(seconds * 1e9)
    }
}

/// Typed validation failures for remote open options (195b-54).
public enum SourceOpenOptionsError: Error, Equatable, Sendable {
    case headerInjection
    case cookieInjection
    case cookieHeaderConflict
    case deadlineInvalid
    case tlsTrustInvalid
}

extension SourceOpenOptions {
    /// 195b-54: validate a per-open copy BEFORE any network access, mirroring
    /// the transport backstop's rules in goravR3OpenInput so the caller gets
    /// a typed refusal instead of a bare -22 from the C boundary. The
    /// returned value is intended to be captured and held immutable for the
    /// whole open attempt.
    public func validatedForOpen() throws -> SourceOpenOptions {
        let forbidden = CharacterSet(charactersIn: "\r\n\0")
        guard headers.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(":") && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }) else {
            throw SourceOpenOptionsError.headerInjection
        }
        guard cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }) else {
            throw SourceOpenOptionsError.cookieInjection
        }
        if !cookies.isEmpty {
            guard !headers.keys.contains(where: { $0.lowercased() == "cookie" }) else {
                throw SourceOpenOptionsError.cookieHeaderConflict
            }
        }
        if let path = tlsCAFile {
            guard path.hasPrefix("/"), !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SourceOpenOptionsError.tlsTrustInvalid
            }
        }
        if let deadline = openDeadlineSeconds {
            guard deadline.isFinite, deadline > 0, deadline <= 86400 else {
                throw SourceOpenOptionsError.deadlineInvalid
            }
        }
        return self
    }
}

/// Error-safe source label. Never retain URL components: paths and even query
/// keys can contain credentials, including malformed or percent-encoded ones.
public enum URLRedaction {
    public static func redact(_ raw: String) -> String {
        "REDACTED"
    }
}

/// Opens a remote source with the transport options applied. The option
/// dictionary is built, consumed and freed on the C side (AVDictionary is
/// not Swift-importable); this wrapper only joins and passes the strings.
/// Local opens never reach here - callers keep the plain open path.
func goravR3OpenInput(_ ctx: UnsafeMutablePointer<UnsafeMutablePointer<AVFormatContext>?>, url: String, options: SourceOpenOptions) -> Int32 {
    // Refuse CR/LF/NUL injection before C string transport; never log secret values.
    let forbidden = CharacterSet(charactersIn: "\r\n\0")
    guard options.headers.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(":") && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }),
          options.cookies.allSatisfy({ !$0.key.isEmpty && !$0.key.contains(where: { "=;".contains($0) }) && $0.key.rangeOfCharacter(from: forbidden) == nil && $0.value.rangeOfCharacter(from: forbidden) == nil }) else { return -22 }
    var lines = options.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
    // FFmpeg's cookies option expects Set-Cookie response syntax, not a Cookie
    // request field. Serialize the request explicitly, retaining every pair.
    if !options.cookies.isEmpty {
        guard !options.headers.keys.contains(where: { $0.lowercased() == "cookie" }) else { return -22 }
        lines.append("Cookie: " + options.cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "))
    }
    let headers: String? = lines.isEmpty ? nil : lines.joined(separator: "\r\n") + "\r\n"
    let cookies: String? = nil
    func withOpt(_ s: String?, _ body: (UnsafePointer<CChar>?) -> Int32) -> Int32 {
        guard let s else { return body(nil) }
        return s.withCString { body($0) }
    }
    return url.withCString { urlC in
        withOpt(headers) { hC in
            withOpt(cookies) { cC in
                withOpt(options.tlsCAFile) { caC in
                    gorav_r3_open_input_verified(ctx, urlC, hC, cC, caC)
                }
            }
        }
    }
}
```

```c id=shim
/* AUTHORED_R2 replacement (2026-10-16, ZDYM provider/build lane).
 * NOT the pinned r1 member (pin 3114B/562aa5ad...); byte identity is not claimed.
 * Role per DECODER-ONLY-TARGET-WIRING-r1: avformat/avcodec/avutil/frame/pixdesc/imgutils/buffer/mem
 * imports, error constants, frame classification, interrupt callback bridge.
 * Provider lock (P1): FFmpeg 8.0.1 @ 894da5ca7d742e4429ffb2af534fcda0103ef593,
 * private-prefix headers only. No system/Homebrew FFmpeg.
 *
 * AUTHORED_L3 extension (2026-10-25, L3 formats/hardware-decode lane):
 * the AUTHORED_R2 body below is preserved verbatim; the L3 section after the
 * marker adds swscale/swresample imports, VideoToolbox hwcontext (Darwin),
 * measured-fallback hardware state, yuv420p conversion and s16le-stereo
 * resample helpers. Static inline only; no new translation unit. */
#ifndef GORAV_CFFMPEG_SHIM_H
#define GORAV_CFFMPEG_SHIM_H

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/frame.h>
#include <libavutil/pixdesc.h>
#include <libavutil/imgutils.h>
#include <libavutil/buffer.h>
#include <libavutil/mem.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <stdint.h>

/* Current AVIO input buffer occupancy, not decoded cache or playable time.
 * No read, refill, seek or I/O side effect. -1 means unavailable/inconsistent. */
static inline int64_t gorav_avio_buffer_available(const AVIOContext *io) {
    if (!io || io->write_flag || !io->buffer || !io->buf_ptr || !io->buf_end || io->buffer_size < 0) return -1;
    uintptr_t base = (uintptr_t)io->buffer, p = (uintptr_t)io->buf_ptr, end = (uintptr_t)io->buf_end;
    if (p < base || end < p || end - base > (uint64_t)io->buffer_size) return -1;
    return (int64_t)(end - p);
}

/* Error constants: stable negative AVERROR values surfaced to Swift as ints. */
static inline int gorav_av_error_open(int code) { return code; } /* identity, keeps call site explicit */
static inline int gorav_av_errbuf(int code, char *dst, int dst_size) {
    if (dst == NULL || dst_size <= 0) { return -1; }
    if (av_strerror(code, dst, (size_t)dst_size) < 0) { dst[0] = '\0'; return -1; }
    return 0;
}
static inline int gorav_av_err_eof(void) { return AVERROR_EOF; }
static inline int gorav_av_err_exit(void) { return AVERROR_EXIT; }
static inline int gorav_av_err_eagain(void) { return AVERROR(EAGAIN); }

/* Frame classification for the decoder-only probe. UNKNOWN is a real value;
 * classification is reported, never inferred beyond codec/frame facts. */
enum GorAVFrameClass {
    GORAV_FRAME_CLASS_UNKNOWN = 0,
    GORAV_FRAME_CLASS_VIDEO_KEY = 1,
    GORAV_FRAME_CLASS_VIDEO_DELTA = 2,
    GORAV_FRAME_CLASS_OTHER = 3
};
static inline enum GorAVFrameClass gorav_classify_frame(const AVFrame *f) {
    if (f == NULL) { return GORAV_FRAME_CLASS_UNKNOWN; }
    if (f->flags & AV_FRAME_FLAG_KEY) { return GORAV_FRAME_CLASS_VIDEO_KEY; }
    if (f->width > 0 && f->height > 0) { return GORAV_FRAME_CLASS_VIDEO_DELTA; }
    return GORAV_FRAME_CLASS_OTHER;
}

/* Interrupt callback bridge: ioOnly capability. Aborts blocking demux/AVIO calls
 * that poll this callback; does NOT interrupt a stuck decode. */
typedef int (*GorAVInterruptPoll)(void *opaque);
struct GorAVInterruptSlot {
    GorAVInterruptPoll poll; /* returns nonzero to request abort */
    void *opaque;
};
static inline int gorav_avio_interrupt_thunk(void *opaque) {
    struct GorAVInterruptSlot *slot = (struct GorAVInterruptSlot *)opaque;
    if (slot == NULL || slot->poll == NULL) { return 0; }
    return slot->poll(slot->opaque);
}

/* Version labels are diagnostics only, never byte identity or ABI proof. */
static inline unsigned gorav_avformat_version(void) { return avformat_version(); }
static inline unsigned gorav_avcodec_version(void) { return avcodec_version(); }
static inline unsigned gorav_avutil_version(void) { return avutil_version(); }

/* Authored successor: pinned-source custom IO ownership, NOT importer-tested. */
static inline int gorav_av_err_einval(void) { return AVERROR(EINVAL); }
/* AV_NOPTS_VALUE macro is not importable by Swift; expose it as a function. */
static inline int64_t gorav_av_nopts_value(void) { return AV_NOPTS_VALUE; }
static inline void gorav_free_custom_avio(AVIOContext **io) {
    if (!io || !*io) return;
    av_freep(&(*io)->buffer); /* CURRENT buffer, never original stale pointer */
    avio_context_free(io);
}
static inline void gorav_bind_custom_avio(AVFormatContext *format, AVIOContext *io) {
    format->pb = io;
    format->flags |= AVFMT_FLAG_CUSTOM_IO;
}

/* =================== AUTHORED_L3 section begins ===================
 * L3 formats/hardware-decode lane. Everything in this section is new. */

#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavutil/hwcontext.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
#include <libavutil/opt.h>
#include <libavutil/mastering_display_metadata.h>
#if defined(__APPLE__)
#include <libavutil/hwcontext_videotoolbox.h>
#endif

static inline unsigned gorav_l3_swscale_version(void) { return swscale_version(); }
static inline unsigned gorav_l3_swresample_version(void) { return swresample_version(); }

/* Decoder-presence probe: lets tests assert the built binary actually contains
 * a decoder instead of trusting the configure line. Returns 1 if present. */
static inline int gorav_l3_has_decoder(const char *name) {
    return avcodec_find_decoder_by_name(name) != NULL ? 1 : 0;
}

/* --- Hardware decode (VideoToolbox, Darwin) with measured fallback --- */

/* Mutable receipt slot. Lives on the Swift side (heap-allocated, stable address);
 * the get_format callback reads/writes it through AVCodecContext.opaque. */
struct GorAVL3HWState {
    int hw_attempted;        /* 1 once VT attach was requested */
    int hw_active;           /* 1 if the decoder negotiated a VT format */
    int hw_frames;           /* frames received carrying AV_PIX_FMT_VIDEOTOOLBOX */
    int hw_transfer_errors;  /* failed av_hwframe_transfer_data calls */
    int hw_disabled;         /* 1 once this session fell back to software */
};

static enum AVPixelFormat gorav_l3_get_format_vt(struct AVCodecContext *s,
                                                 const enum AVPixelFormat *fmt) {
    struct GorAVL3HWState *st = (struct GorAVL3HWState *)s->opaque;
    const enum AVPixelFormat *p;
    enum AVPixelFormat first_sw = AV_PIX_FMT_NONE;
    for (p = fmt; *p != AV_PIX_FMT_NONE; p++) {
        const AVPixFmtDescriptor *d;
        if (*p == AV_PIX_FMT_VIDEOTOOLBOX) {
            if (st != NULL && !st->hw_disabled) {
                st->hw_active = 1;
                return AV_PIX_FMT_VIDEOTOOLBOX;
            }
            continue;
        }
        /* Software candidate must be a REAL software format: skip any other
         * hwaccel pixel format the list may carry. */
        d = av_pix_fmt_desc_get(*p);
        if (d != NULL && (d->flags & AV_PIX_FMT_FLAG_HWACCEL)) { continue; }
        if (first_sw == AV_PIX_FMT_NONE) { first_sw = *p; }
    }
    if (st != NULL) { st->hw_active = 0; }
    return first_sw != AV_PIX_FMT_NONE ? first_sw : AV_PIX_FMT_NONE;
}

/* Attaches a VideoToolbox device context and the get_format bridge.
 * Returns 0 on attach, -1 if VT device creation failed, -2 off-Darwin. */
static inline int gorav_l3_attach_videotoolbox(AVCodecContext *ctx, struct GorAVL3HWState *st) {
#if defined(__APPLE__)
    AVBufferRef *dev = NULL;
    if (av_hwdevice_ctx_create(&dev, AV_HWDEVICE_TYPE_VIDEOTOOLBOX, NULL, NULL, 0) < 0) {
        return -1;
    }
    ctx->hw_device_ctx = dev; /* ownership transferred; freed with ctx */
    ctx->get_format = gorav_l3_get_format_vt;
    ctx->opaque = st;
    if (st != NULL) { st->hw_attempted = 1; }
    return 0;
#else
    (void)ctx; (void)st;
    return -2;
#endif
}

/* Detach: disarm the callback and drop the device ref so a software-only
 * retry of the same codec context is honest. */
static inline void gorav_l3_detach_hardware(AVCodecContext *ctx, struct GorAVL3HWState *st) {
    if (st != NULL) { st->hw_disabled = 1; st->hw_active = 0; }
    if (ctx != NULL) {
        ctx->get_format = NULL;
        ctx->opaque = NULL;
        av_buffer_unref(&ctx->hw_device_ctx);
    }
}

/* Transfers one hardware frame to a software frame, copying metadata. */
static inline int gorav_l3_hw_transfer(AVFrame *dst_sw, const AVFrame *src_hw,
                                       struct GorAVL3HWState *st) {
    int ret = av_hwframe_transfer_data(dst_sw, src_hw, 0);
    if (ret < 0) { if (st != NULL) { st->hw_transfer_errors++; } return ret; }
    /* v4: props copy is checked - a silent failure here was a side-data
     * LOSS on the transferred frame (HDR metadata gone with no record). */
    ret = av_frame_copy_props(dst_sw, src_hw);
    if (ret < 0) { if (st != NULL) { st->hw_transfer_errors++; } return ret; }
    if (st != NULL) { st->hw_frames++; }
    return 0;
}

static inline int gorav_l3_pixfmt_videotoolbox(void) { return (int)AV_PIX_FMT_VIDEOTOOLBOX; }

/* --- Pixel conversion: any admitted software frame -> YUV420P 8-bit --- */

struct GorAVL3PixConv {
    struct SwsContext *ctx;
    enum AVPixelFormat src_fmt;
    int src_w;
    int src_h;
    /* v4: colorspace/range join the cache key - a color-only change on the
     * same geometry previously kept a STALE conversion matrix. */
    int src_range;
    int src_csp;
};

/* v4: aggregate byte budget for one derived frame (bounds the 16k alloc). */
#define GORAV_L3_MAX_CONVERT_BYTES (64 << 20)

static inline struct GorAVL3PixConv *gorav_l3_pixconv_open(void) {
    return (struct GorAVL3PixConv *)calloc(1, sizeof(struct GorAVL3PixConv));
}

static inline void gorav_l3_pixconv_close(struct GorAVL3PixConv **pc) {
    if (pc == NULL || *pc == NULL) { return; }
    if ((*pc)->ctx != NULL) { sws_freeContext((*pc)->ctx); }
    free(*pc);
    *pc = NULL;
}

/* v4.4 repair (r6 g6): EXACT av_frame_get_buffer(align 32) allocation
 * model for a yuv420p destination of w x h - ceil chroma widths, the
 * linesize alignment loop, 32-row padded height, plane sizes, and the
 * per-buffer alignment overhead measured once against the REAL allocator
 * (so the value tracks the running build's ALIGN/plane-padding exactly).
 * Returns -1 when the geometry is not computable. The old floor(width/2)
 * estimate was not a bound: odd widths understate the chroma planes and
 * no padding was modeled (65x1: estimate 160 B vs actual 5376 B
 * allocation - geometry-check.c). */
static inline int64_t gorav_l3_yuv420p_alloc_estimate(int32_t w, int32_t h) {
    int ls[4] = {0, 0, 0, 0};
    ptrdiff_t pls[4];
    size_t sizes[4] = {0, 0, 0, 0};
    int i, ph;
    int64_t payload;
    static int64_t overhead = -1;
    if (w <= 0 || h <= 0 || w > 16384 || h > 16384) { return -1; }
    /* libavutil/frame.c get_video_buffer: smallest power-of-two width
     * alignment whose y linesize is a multiple of 32, then 32-align. */
    for (i = 1; i <= 32; i += i) {
        if (av_image_fill_linesizes(ls, AV_PIX_FMT_YUV420P, (w + i - 1) & ~(i - 1)) < 0) { return -1; }
        if (!(ls[0] & 31)) { break; }
    }
    for (i = 0; i < 4 && ls[i]; i++) { ls[i] = (ls[i] + 31) & ~31; }
    ph = (h + 31) & ~31;
    for (i = 0; i < 4; i++) { pls[i] = ls[i]; }
    if (av_image_fill_plane_sizes(sizes, AV_PIX_FMT_YUV420P, ph, pls) < 0) { return -1; }
    payload = (int64_t)sizes[0] + (int64_t)sizes[1] + (int64_t)sizes[2] + (int64_t)sizes[3];
    if (overhead < 0) {
        /* per-buffer overhead (4*plane_padding + 4*align) is
         * geometry-independent: measure once with a 1x1 frame whose
         * modeled payload is 32*32 + 2*(32*16) = 2048. */
        AVFrame *t = av_frame_alloc();
        if (t == NULL) { return -1; }
        t->format = AV_PIX_FMT_YUV420P; t->width = 1; t->height = 1;
        if (av_frame_get_buffer(t, 32) < 0 || t->buf[0] == NULL) { av_frame_free(&t); return -1; }
        overhead = (int64_t)t->buf[0]->size - 2048;
        av_frame_free(&t);
        if (overhead < 0) { return -1; }
    }
    return payload + overhead;
}

/* Converts src into dst as YUV420P 8-bit at source size, EXPLICIT bt709
 * coefficients and range handling (no ambient defaults). ALL bounds are
 * validated BEFORE any allocation or read: geometry, software-only format,
 * positive strides. sws_scale must return the FULL output row count; a
 * partial scale is an error, not a quiet short frame. dst metadata copy is
 * checked. src must already be a software frame (transfer hw frames first). */
static inline int gorav_l3_to_yuv420p(struct GorAVL3PixConv *pc, AVFrame *dst, const AVFrame *src) {
    int ret, i;
    const int *coeffs;
    int src_range;
    const AVPixFmtDescriptor *d;
    if (pc == NULL || dst == NULL || src == NULL) { return AVERROR(EINVAL); }
    if (src->width <= 0 || src->height <= 0 || src->width > 16384 || src->height > 16384) {
        return AVERROR(EINVAL);
    }
    d = av_pix_fmt_desc_get((enum AVPixelFormat)src->format);
    if (d == NULL || (d->flags & AV_PIX_FMT_FLAG_HWACCEL)) { return AVERROR(EINVAL); }
    for (i = 0; i < 8; i++) {
        if (src->data[i] != NULL && src->linesize[i] <= 0) { return AVERROR(EINVAL); }
    }
    /* v4: per-plane minimum strides + refcounted-buffer coverage BEFORE any
     * read (the Swift-side lease check covers the retained frame; the C side
     * verifies again at the conversion boundary - no trust across modules). */
    {
        int min_ls[4] = {0, 0, 0, 0};
        if (av_image_fill_linesizes(min_ls, (enum AVPixelFormat)src->format, src->width) < 0) {
            return AVERROR(EINVAL);
        }
        for (i = 0; i < 4; i++) {
            int plane_h;
            int64_t need;
            if (src->data[i] == NULL) { continue; }
            if (src->linesize[i] < min_ls[i]) { return AVERROR(EINVAL); }
            plane_h = (i == 1 || i == 2) ? AV_CEIL_RSHIFT(src->height, d->log2_chroma_h) : src->height;
            need = (int64_t)src->linesize[i] * (plane_h > 1 ? (int64_t)plane_h - 1 : 0) + min_ls[i];
            if (src->buf[i] != NULL) {
                if ((int64_t)src->buf[i]->size < need) { return AVERROR(EINVAL); }
            } else if (src->buf[0] != NULL && src->data[0] != NULL) {
                int64_t off = (int64_t)(src->data[i] - src->buf[0]->data);
                if (off < 0 || off + need > (int64_t)src->buf[0]->size) { return AVERROR(EINVAL); }
            } else {
                return AVERROR(EINVAL); /* no refcounted backing to verify against */
            }
        }
    }
    /* v4: aggregate byte budget BEFORE the destination allocation - a 16k
     * frame otherwise allocates ~400 MiB on a single call. */
    /* v4.4 (r6 g5): bt2020 CONSTANT-LUMINANCE cannot be reduced with the
     * NCL matrix - refuse at the C boundary too, not only via the Swift
     * caller. */
    if (src->colorspace == AVCOL_SPC_BT2020_CL) { return AVERROR(EINVAL); }
    /* v4.4 repair (r6 g5): only the matrices actually mapped below
     * (601/709/2020 NCL) or UNSPECIFIED (documented 709 default) may proceed;
     * any other KNOWN matrix is refused at the boundary, never silently
     * converted through 709. */
    if (src->colorspace != AVCOL_SPC_UNSPECIFIED &&
        src->colorspace != AVCOL_SPC_BT709 &&
        src->colorspace != AVCOL_SPC_BT470BG &&
        src->colorspace != AVCOL_SPC_SMPTE170M &&
        src->colorspace != AVCOL_SPC_BT2020_NCL) { return AVERROR(EINVAL); }
    {
        /* v4.4 repair (r6 g6): the budget is checked against the EXACT
         * allocation model - the floor-chroma estimate was not a bound. */
        int64_t est = gorav_l3_yuv420p_alloc_estimate(src->width, src->height);
        if (est < 0) { return AVERROR(EINVAL); }
        if (est > GORAV_L3_MAX_CONVERT_BYTES) { return AVERROR(ENOSPC); }
    }
    src_range = src->color_range == AVCOL_RANGE_JPEG;
    if (pc->ctx == NULL || pc->src_fmt != src->format ||
        pc->src_w != src->width || pc->src_h != src->height ||
        pc->src_range != src_range || pc->src_csp != (int)src->colorspace) {
        if (pc->ctx != NULL) { sws_freeContext(pc->ctx); pc->ctx = NULL; }
        pc->ctx = sws_getContext(src->width, src->height, (enum AVPixelFormat)src->format,
                                 src->width, src->height, AV_PIX_FMT_YUV420P,
                                 SWS_BILINEAR | SWS_ACCURATE_RND | SWS_BITEXACT,
                                 NULL, NULL, NULL);
        if (pc->ctx == NULL) { return AVERROR(EINVAL); }
        /* v4.3 (architect r5): coefficient set by the SOURCE's ACTUAL matrix
         * - 601 sources (bt470bg/smpte170m) get 601, bt709 gets 709,
         * bt2020 NCL gets 2020 NCL, unspecified gets 709 and the Swift side
         * says so in provenance. bt2020-CL never reaches here (refused by
         * the caller - the NCL matrix would be a WRONG transform for CL).
         * v4 forced 709 onto every source; v4.2 split only 709/2020 and let
         * 601 sources convert through the wrong matrix. */
        int coeffSet = SWS_CS_ITU709;
        if (src->colorspace == AVCOL_SPC_BT470BG || src->colorspace == AVCOL_SPC_SMPTE170M) {
            coeffSet = SWS_CS_ITU601;
        } else if (src->colorspace == AVCOL_SPC_BT2020_NCL) {
            coeffSet = SWS_CS_BT2020; /* actual constant name in n8.0.1 swscale.h (first compile caught SWS_CS_ITU2020 undeclared) */
        } else if (src->colorspace == AVCOL_SPC_UNSPECIFIED) {
            /* arch-196x item 2 (v4.4 amendment, mpv parity): untagged ->
             * bt709 at width>=1280 or height>576, else bt601 - the guess the
             * default mpv path makes, and what the Swift provenance names.
             * (For this yuv->yuv bit-depth reduction the coefficient set is
             * pixel-neutral; the guess governs the downstream RGB stage.) */
            coeffSet = (src->width >= 1280 || src->height > 576) ? SWS_CS_ITU709 : SWS_CS_ITU601;
        }
        coeffs = sws_getCoefficients(coeffSet);
        ret = sws_setColorspaceDetails(pc->ctx, coeffs, src_range, coeffs, 0, 0, 1 << 16, 1 << 16);
        if (ret < 0) { sws_freeContext(pc->ctx); pc->ctx = NULL; return ret; }
        pc->src_fmt = (enum AVPixelFormat)src->format;
        pc->src_w = src->width;
        pc->src_h = src->height;
        pc->src_range = src_range;
        pc->src_csp = (int)src->colorspace;
    }
    av_frame_unref(dst);
    dst->format = AV_PIX_FMT_YUV420P;
    dst->width = src->width;
    dst->height = src->height;
    ret = av_frame_get_buffer(dst, 32);
    if (ret < 0) { return ret; }
    ret = sws_scale(pc->ctx, (const uint8_t *const *)src->data, src->linesize,
                    0, src->height, dst->data, dst->linesize);
    if (ret != src->height) { av_frame_unref(dst); return AVERROR_EXTERNAL; }
    ret = av_frame_copy_props(dst, src);
    if (ret < 0) { av_frame_unref(dst); return ret; }
    /* v4.3 (architect r5): the derived frame is a bit-depth reduction of
     * the source, NOT an SDR render - no EOTF mapping ran. Transfer,
     * primaries and matrix tags stay the SOURCE's (via copy_props): the
     * encoded values keep the source signal. But the RANGE was actually
     * converted (sws dst_range = limited above), so the copy is TAGGED
     * limited - inheriting a source FULL tag would be false provenance.
     * v4 stripped all tags and forced bt709 (mislabeled render); v4.2 kept
     * tags including a possibly-full range (false provenance). Both fixed. */
    dst->color_range = AVCOL_RANGE_MPEG;
    return 0;
}

/* --- Audio conversion: any admitted audio frame -> packed s16le stereo --- */

#define GORAV_L3_MAX_OUT_SAMPLES 262144 /* 1 MiB s16le stereo bound, pre-allocation */

struct GorAVL3Swr {
    struct SwrContext *ctx;
    enum AVSampleFormat in_fmt;
    int in_rate;
    AVChannelLayout in_layout;
    int out_rate;
    int reinits; /* reinit drops buffered delay: counted, never silent */
};

static inline struct GorAVL3Swr *gorav_l3_swr_open(void) {
    struct GorAVL3Swr *s = (struct GorAVL3Swr *)calloc(1, sizeof(struct GorAVL3Swr));
    return s;
}

static inline void gorav_l3_swr_close(struct GorAVL3Swr **s) {
    if (s == NULL || *s == NULL) { return; }
    if ((*s)->ctx != NULL) { swr_free(&(*s)->ctx); }
    av_channel_layout_uninit(&(*s)->in_layout);
    free(*s);
    *s = NULL;
}

/* Converts one decoded audio frame to packed s16le stereo at out_rate.
 * On success *out_data is an av_malloc'd buffer of *out_samples * 4 bytes,
 * ownership to the caller (free with gorav_l3_av_freep).
 * Returns 0, or negative AVERROR. Re-inits on format/rate/layout change. */
static inline int gorav_l3_swr_convert(struct GorAVL3Swr *s, const AVFrame *src,
                                       int out_rate, uint8_t **out_data, int *out_samples) {
    int ret;
    AVChannelLayout out_layout;
    int out_count;
    uint8_t *outp[1];
    uint8_t *tail = NULL;
    int tail_samples = 0;
    int64_t need64;
    if (s == NULL || src == NULL || out_data == NULL || out_samples == NULL) { return AVERROR(EINVAL); }
    *out_data = NULL;
    *out_samples = 0;
    if (src->nb_samples <= 0) { return 0; }
    if (src->sample_rate <= 0 || src->ch_layout.nb_channels <= 0 || out_rate <= 0) { return AVERROR(EINVAL); }
    if (s->ctx == NULL || s->in_fmt != src->format || s->in_rate != src->sample_rate ||
        s->out_rate != out_rate || av_channel_layout_compare(&s->in_layout, &src->ch_layout) != 0) {
        /* v4 (architect): a reinit used to DROP the old context's buffered
         * delay silently. Drain the old configuration's tail first and
         * prepend it to this call's output, so sample totals stay conserved
         * across the reinit. reinits counts ONLY actual re-inits (an old
         * context existed), never the first init, and is reported. */
        if (s->ctx != NULL) {
            int64_t old_delay = swr_get_delay(s->ctx, s->in_rate);
            if (old_delay > 0) {
                int64_t t64 = av_rescale_rnd(old_delay, s->out_rate, s->in_rate, AV_ROUND_UP);
                if (t64 > 0 && t64 <= GORAV_L3_MAX_OUT_SAMPLES) {
                    tail = (uint8_t *)av_malloc((size_t)t64 * 4);
                    if (tail != NULL) {
                        uint8_t *tp[1];
                        int t;
                        tp[0] = tail;
                        t = swr_convert(s->ctx, tp, (int)t64, NULL, 0);
                        if (t > 0) { tail_samples = t; } else { av_freep(&tail); }
                    }
                }
            }
            s->reinits++;
            swr_free(&s->ctx); s->ctx = NULL;
        }
        av_channel_layout_uninit(&s->in_layout);
        av_channel_layout_default(&out_layout, 2); /* stereo, matches the sink contract */
        ret = swr_alloc_set_opts2(&s->ctx, &out_layout, AV_SAMPLE_FMT_S16, out_rate,
                                  &src->ch_layout, (enum AVSampleFormat)src->format,
                                  src->sample_rate, 0, NULL);
        av_channel_layout_uninit(&out_layout);
        if (ret < 0 || s->ctx == NULL) { av_freep(&tail); return ret < 0 ? ret : AVERROR(EINVAL); }
        ret = swr_init(s->ctx);
        if (ret < 0) { av_freep(&tail); swr_free(&s->ctx); return ret; }
        s->in_fmt = (enum AVSampleFormat)src->format;
        s->in_rate = src->sample_rate;
        s->out_rate = out_rate;
        ret = av_channel_layout_copy(&s->in_layout, &src->ch_layout);
        if (ret < 0) { av_freep(&tail); swr_free(&s->ctx); return ret; }
    }
    /* v4: the rescale is bounded in int64 BEFORE the int conversion - the
     * old code truncated a >INT32_MAX rescale through (int) and only then
     * compared against the cap. delay+nb_samples is an int64 sum. */
    need64 = av_rescale_rnd(swr_get_delay(s->ctx, src->sample_rate) + (int64_t)src->nb_samples,
                            out_rate, src->sample_rate, AV_ROUND_UP);
    if (need64 < 0) { av_freep(&tail); return AVERROR(EINVAL); }
    if (need64 + tail_samples > GORAV_L3_MAX_OUT_SAMPLES) { av_freep(&tail); return AVERROR(ENOSPC); }
    out_count = (int)need64;
    if (out_count == 0 && tail_samples == 0) { return 0; }
    *out_data = (uint8_t *)av_malloc(((size_t)out_count + (size_t)tail_samples) * 4);
    if (*out_data == NULL) { av_freep(&tail); return AVERROR(ENOMEM); }
    if (tail_samples > 0) {
        memcpy(*out_data, tail, (size_t)tail_samples * 4);
        av_freep(&tail);
    }
    outp[0] = *out_data + (size_t)tail_samples * 4;
    ret = out_count > 0
        ? swr_convert(s->ctx, outp, out_count,
                      (const uint8_t **)src->extended_data, src->nb_samples)
        : 0;
    if (ret < 0) { av_freep(out_data); return ret; }
    *out_samples = tail_samples + ret;
    if (*out_samples == 0) { av_freep(out_data); }
    return 0;
}

/* v4: actual re-init count (first init excluded) for the run receipt. */
static inline int gorav_l3_swr_reinits(const struct GorAVL3Swr *s) {
    return s != NULL ? s->reinits : 0;
}

/* Drains the resampler's delay buffer at EOS (blocker 4: tail samples are
 * real audio; losing them shortens duration and drifts the clock). */
static inline int gorav_l3_swr_drain(struct GorAVL3Swr *s, uint8_t **out_data, int *out_samples) {
    int out_count;
    uint8_t *outp[1];
    int ret;
    if (s == NULL || out_data == NULL || out_samples == NULL) { return AVERROR(EINVAL); }
    *out_data = NULL;
    *out_samples = 0;
    if (s->ctx == NULL || s->out_rate <= 0) { return 0; }
    /* v4: int64 bound BEFORE the int conversion (same truncation fix). */
    {
        int64_t need64 = av_rescale_rnd(swr_get_delay(s->ctx, s->in_rate), s->out_rate, s->in_rate, AV_ROUND_UP);
        if (need64 < 0) { return AVERROR(EINVAL); }
        if (need64 > GORAV_L3_MAX_OUT_SAMPLES) { return AVERROR(ENOSPC); }
        out_count = (int)need64;
    }
    if (out_count == 0) { return 0; }
    *out_data = (uint8_t *)av_malloc((size_t)out_count * 4);
    if (*out_data == NULL) { return AVERROR(ENOMEM); }
    outp[0] = *out_data;
    ret = swr_convert(s->ctx, outp, out_count, NULL, 0);
    if (ret < 0) { av_freep(out_data); return ret; }
    *out_samples = ret;
    if (ret == 0) { av_freep(out_data); }
    return 0;
}

/* HDR signal descriptor values (blocker 1): mastering display + content
 * light level side data, presence distinguished from zero values. Color
 * enums (primaries/trc/space/range) live on AVFrame fields and are read
 * directly from Swift with the av_color_*_name() public API. */
struct GorAVL3HDRValues {
    int has_mastering;           /* side data present */
    int mastering_has_lum;       /* AVMasteringDisplayMetadata.has_luminance */
    int mastering_has_prim;      /* has_primaries */
    int max_lum_num, max_lum_den;
    int min_lum_num, min_lum_den;
    /* v4 (L5): display primaries + white point as rational xy pairs, valid
     * only when mastering_has_prim != 0. GBR order, matching
     * AVMasteringDisplayMetadata.display_primaries. */
    int prim_num[6], prim_den[6];  /* G(x,y), B(x,y), R(x,y) */
    int wp_num[2], wp_den[2];      /* white point x, y */
    int has_cll;                 /* side data present */
    unsigned max_cll, max_fall;
    /* v4 (L5): AVFrame.chroma_location verbatim (AVChromaLocation as int;
     * 0 = unspecified). Typed mapping is the Swift side's, no assumption here. */
    int chroma_location;
};
static inline struct GorAVL3HDRValues gorav_l3_hdr_values(const AVFrame *f) {
    struct GorAVL3HDRValues v;
    AVFrameSideData *sd;
    memset(&v, 0, sizeof(v));
    if (f == NULL) { return v; }
    sd = av_frame_get_side_data(f, AV_FRAME_DATA_MASTERING_DISPLAY_METADATA);
    if (sd != NULL && sd->data != NULL && sd->size >= sizeof(AVMasteringDisplayMetadata)) {
        const AVMasteringDisplayMetadata *md = (const AVMasteringDisplayMetadata *)sd->data;
        int i, j;
        v.has_mastering = 1;
        v.mastering_has_lum = md->has_luminance;
        v.mastering_has_prim = md->has_primaries;
        v.max_lum_num = md->max_luminance.num;
        v.max_lum_den = md->max_luminance.den;
        v.min_lum_num = md->min_luminance.num;
        v.min_lum_den = md->min_luminance.den;
        if (md->has_primaries) {
            for (i = 0; i < 3; i++) {
                for (j = 0; j < 2; j++) {
                    v.prim_num[i*2+j] = md->display_primaries[i][j].num;
                    v.prim_den[i*2+j] = md->display_primaries[i][j].den;
                }
            }
            for (j = 0; j < 2; j++) {
                v.wp_num[j] = md->white_point[j].num;
                v.wp_den[j] = md->white_point[j].den;
            }
        }
    }
    v.chroma_location = (int)f->chroma_location;
    sd = av_frame_get_side_data(f, AV_FRAME_DATA_CONTENT_LIGHT_LEVEL);
    if (sd != NULL && sd->data != NULL && sd->size >= sizeof(AVContentLightMetadata)) {
        const AVContentLightMetadata *cl = (const AVContentLightMetadata *)sd->data;
        v.has_cll = 1;
        v.max_cll = cl->MaxCLL;
        v.max_fall = cl->MaxFALL;
    }
    return v;
}

static inline void gorav_l3_av_freep(void *p) {
    void **pp = (void **)p;
    av_freep(pp);
}

/* v4.2: full swr state reset for seek - drops converter-internal delay and
 * any source-format leftovers so post-seek conversion starts clean. */
static inline int gorav_l3_swr_reset(SwrContext *swr) {
    return swr_init(swr);
}

/* v4.4 (r6 g3): the resampler's current delay in INPUT samples at the given
 * input rate - the output-side timing correction the audio lane applies
 * when it computes an emitted chunk's first-sample time. Negative = error. */
static inline int64_t gorav_l3_swr_delay(const struct GorAVL3Swr *s, int64_t input_rate) {
    if (!s || !s->ctx) { return -1; }
    return swr_get_delay(s->ctx, input_rate);
}

/* =================== AUTHORED_R3 section begins ===================
 * R3 (arch-195b): remote open with transport options. AVDictionary is not
 * importable by Swift, so the dictionary is built, passed and freed entirely
 * on the C side; Swift only supplies the already-joined strings (or NULL).
 * Returns the avformat_open_input result code. */
static inline int gorav_r3_open_input_verified(AVFormatContext **ctx, const char *url,
                                      const char *headers, const char *cookies,
                                      const char *ca_file) {
    AVDictionary *d = NULL;
    int rc = av_dict_set(&d, "tls_verify", "1", 0);
    if (rc < 0) goto cleanup;
    if (ca_file && ca_file[0]) {
        rc = av_dict_set(&d, "ca_file", ca_file, 0);
        if (rc < 0) goto cleanup;
    }
    if (headers && headers[0]) {
        rc = av_dict_set(&d, "headers", headers, 0);
        if (rc < 0) goto cleanup;
    }
    if (cookies && cookies[0]) {
        rc = av_dict_set(&d, "cookies", cookies, 0);
        if (rc < 0) goto cleanup;
    }
    rc = avformat_open_input(ctx, url, NULL, &d);
cleanup:
    av_dict_free(&d);
    return rc;
}
/* Existing C callers also use authenticated transport with system trust. */
static inline int gorav_r3_open_input(AVFormatContext **ctx, const char *url,
                                      const char *headers, const char *cookies) {
    return gorav_r3_open_input_verified(ctx, url, headers, cookies, NULL);
}

/* =================== AUTHORED_R10 section begins ===================
 * R10 (arch-195b): media inventory accessors. AVDictionary and the
 * AV_DISPOSITION_* macros are not Swift-importable, so stream/format/chapter
 * facts cross through these wrappers only. No mutation; reads only. */
static inline int gorav_r10_stream_count(const AVFormatContext *f) {
    return f != NULL ? (int)f->nb_streams : 0;
}
/* codec_type as int: 0 video, 1 audio, 2 data, 3 subtitle, -1 unknown/other. */
static inline int gorav_r10_stream_kind(const AVFormatContext *f, int idx) {
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return -1; }
    switch (f->streams[idx]->codecpar->codec_type) {
        case AVMEDIA_TYPE_VIDEO: return 0;
        case AVMEDIA_TYPE_AUDIO: return 1;
        case AVMEDIA_TYPE_DATA: return 2;
        case AVMEDIA_TYPE_SUBTITLE: return 3;
        default: return -1;
    }
}
static inline const char *gorav_r10_stream_codec_name(const AVFormatContext *f, int idx) {
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return NULL; }
    return avcodec_get_name(f->streams[idx]->codecpar->codec_id);
}
static inline int gorav_r10_stream_disposition(const AVFormatContext *f, int idx) {
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return 0; }
    return f->streams[idx]->disposition;
}
static inline int gorav_r10_disposition_default(void) { return AV_DISPOSITION_DEFAULT; }
static inline int gorav_r10_disposition_attached_pic(void) { return AV_DISPOSITION_ATTACHED_PIC; }
static inline int64_t gorav_r10_stream_duration_ts(const AVFormatContext *f, int idx) {
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return AV_NOPTS_VALUE; }
    return f->streams[idx]->duration;
}
static inline void gorav_r10_stream_timebase(const AVFormatContext *f, int idx, int *num, int *den) {
    if (num != NULL) { *num = 0; }
    if (den != NULL) { *den = 0; }
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams) { return; }
    if (num != NULL) { *num = f->streams[idx]->time_base.num; }
    if (den != NULL) { *den = f->streams[idx]->time_base.den; }
}
static inline const char *gorav_r10_stream_meta(const AVFormatContext *f, int idx, const char *key) {
    const AVDictionaryEntry *e;
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_streams || key == NULL) { return NULL; }
    e = av_dict_get(f->streams[idx]->metadata, key, NULL, 0);
    return e != NULL ? e->value : NULL;
}
static inline const char *gorav_r10_format_meta(const AVFormatContext *f, const char *key) {
    const AVDictionaryEntry *e;
    if (f == NULL || key == NULL) { return NULL; }
    e = av_dict_get(f->metadata, key, NULL, 0);
    return e != NULL ? e->value : NULL;
}
static inline int64_t gorav_r10_duration_us(const AVFormatContext *f) {
    return f != NULL ? f->duration : AV_NOPTS_VALUE;
}
static inline int gorav_r10_chapter_count(const AVFormatContext *f) {
    return f != NULL ? (int)f->nb_chapters : 0;
}
static inline void gorav_r10_chapter_times(const AVFormatContext *f, int idx,
                                           int64_t *start, int64_t *end, int *num, int *den) {
    if (start != NULL) { *start = 0; }
    if (end != NULL) { *end = 0; }
    if (num != NULL) { *num = 0; }
    if (den != NULL) { *den = 1; }
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_chapters) { return; }
    if (start != NULL) { *start = f->chapters[idx]->start; }
    if (end != NULL) { *end = f->chapters[idx]->end; }
    if (num != NULL) { *num = f->chapters[idx]->time_base.num; }
    if (den != NULL) { *den = f->chapters[idx]->time_base.den; }
}
static inline const char *gorav_r10_chapter_title(const AVFormatContext *f, int idx) {
    const AVDictionaryEntry *e;
    if (f == NULL || idx < 0 || (unsigned)idx >= f->nb_chapters) { return NULL; }
    e = av_dict_get(f->chapters[idx]->metadata, "title", NULL, 0);
    return e != NULL ? e->value : NULL;
}

#endif /* GORAV_CFFMPEG_SHIM_H */
```

```sh id=runner
#!/usr/bin/env bash
set -u -o pipefail
: "${M2_FF_PREFIX:?exact candidate provider prefix required}"
ff=$(realpath "$M2_FF_PREFIX")
here=kits/m2-source-packets
work=$(mktemp -d)
trap 'rm -f "$work/key.pem" "$work/cert.pem" "$work/wrong-key.pem" "$work/wrong-cert.pem"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/key.pem" -out "$work/cert.pem" -days 1 -subj /CN=fixture.invalid -addext 'subjectAltName=IP:127.0.0.1' >/dev/null 2>&1 || exit 2
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$work/wrong-key.pem" -out "$work/wrong-cert.pem" -days 1 -subj /CN=wrong.invalid -addext 'subjectAltName=DNS:wrong.invalid' >/dev/null 2>&1 || exit 2
export M2_TLS_CERT="$work/cert.pem" M2_TLS_KEY="$work/key.pem" M2_TLS_WRONG_CERT="$work/wrong-cert.pem" M2_TLS_WRONG_KEY="$work/wrong-key.pem"
export PKG_CONFIG_PATH="$ff/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="$ff/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cp "$here/tls-verified-main.swift" Sources/remote-source-tests/main.swift
cc "$here/protocol-inventory.c" -I"$ff/include" -L"$ff/lib" $(pkg-config --static --cflags --libs libavformat libavcodec libavutil) -o "$work/inventory" || exit 2
"$work/inventory"; inventory_rc=$?
mapfile -t flags < <(pkg-config --static --libs libavformat libavcodec libavutil libswscale libswresample | python3 -c 'import shlex,sys; print("\n".join(shlex.split(sys.stdin.read())))')
args=(-Xcc "-I$ff/include")
for flag in "${flags[@]}"; do args+=(-Xlinker "$flag"); done
timeout 300 swift run "${args[@]}" remote-source-tests; product_rc=$?
printf 'M2_TLS_VERIFIED_PCM_RESULT inventory_exit=%s product_open_exit=%s\n' "$inventory_rc" "$product_rc"
[ "$inventory_rc" -eq 0 ] && [ "$product_rc" -eq 0 ]
```

```swift id=harness
// Encrypted local TLS+PCM witness, no certificate-authentication conclusion.
import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
setbuf(stdout, nil)
import GorAVCore
import GorAVFFmpegAdapter

// R3 (arch-195b) witness: remote (http) source open with headers/cookies,
// redaction, and refusal without credentials. Local python http server
// requires a header AND a cookie; serves a PCM wav (stream-friendly probe).

var failures = 0
func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " \(info)"))
    if !ok { failures += 1 }
}

// U-series: redaction and option summary (pure)
check("U1 userinfo redacted", URLRedaction.redact("http://user:secret@example.com/a.wav") == "REDACTED")
check("U2 query values and keys redacted", URLRedaction.redact("https://h/p?token=abc&x=1") == "REDACTED")
check("U3 fragment and path redacted", URLRedaction.redact("http://h/secret#frag") == "REDACTED")
check("U4 local path not exposed", URLRedaction.redact("/plain/path.wav") == "REDACTED")
check("U6 malformed credential redacted", URLRedaction.redact("http://user:slash/secret@host/p?bareSecret") == "REDACTED")
check("U7 encoded credential redacted", URLRedaction.redact("http://%73ecret@host/%74oken?%73ecret") == "REDACTED")
check("U5 summary counts only", SourceOpenOptions(headers: ["Authorization": "s3cr3t"], cookies: ["k": "v"]).redactedSummary == "headers=1 cookies=1 deadline=none")

// S-series: live http open through the admitted remote path
let root = ProcessInfo.processInfo.environment["GORAV_REPO"] ?? FileManager.default.currentDirectoryPath
let fixture = root + "/fixtures/tone-48k.wav"
let tmp = NSTemporaryDirectory() + "r3srv-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
let serverPy = tmp + "/server.py"
let portFile = tmp + "/port"
let script = """
import http.server, sys, threading, ssl
fixture = sys.argv[1]
portfile = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/share', '/hop'):
            self.send_response(302)
            self.send_header('Location', '/hop' if self.path == '/share' else '/tone-48k.wav')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.headers.get('X-GorAV-Test') != 'yes' or ('session=abc' not in (self.headers.get('Cookie') or '') or 'other=def' not in (self.headers.get('Cookie') or '')):
            self.send_response(403); self.end_headers(); return
        with open(fixture, 'rb') as fh: data = fh.read()
        self.send_response(200)
        self.send_header('Content-Type', 'audio/wav')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(sys.argv[3], sys.argv[4])
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
with open(portfile, 'w') as fh: fh.write(str(srv.server_address[1]))
srv.serve_forever()
"""
try! script.write(toFile: serverPy, atomically: true, encoding: .utf8)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
guard let cert = ProcessInfo.processInfo.environment["M2_TLS_CERT"], let key = ProcessInfo.processInfo.environment["M2_TLS_KEY"] else { fatalError("TLS fixture paths required") }
proc.arguments = [serverPy, fixture, portFile, cert, key]
try! proc.run()
var port: String? = nil
for _ in 0..<200 {
    if let p = try? String(contentsOfFile: portFile, encoding: .utf8), !p.isEmpty { port = p.trimmingCharacters(in: .whitespacesAndNewlines); break }
    try? await Task.sleep(nanoseconds: 50_000_000)
}
guard let port else {
    check("S0 server started", false)
    print("remote-source-tests: \(failures) FAIL"); exit(1)
}
check("S0 server started on 127.0.0.1:\(port)", true)
let url = "https://127.0.0.1:\(port)/share"

func probeOpen(withOptions opts: SourceOpenOptions?, epoch: UInt64, input: String? = nil) async -> String {
    let d = FFmpegSoftwareAudioDecoder()
    do { try d.pinLocalRoots([root]) } catch { return "pin \(error)" }
    if let opts { d.remoteOpenOptions = opts }
    let selected = input ?? url
    let src = SourceDescriptor(id: selected, kind: selected.hasPrefix("http") ? .remote : .local, seekable: true)
    do {
        try await d.open(source: src, session: SessionID(uncheckedEpoch: epoch))
    } catch { return "open-error: \(error)" }
    // drain the .opened event
    var seen = "no-event"
    if let ev = await d.nextEvent(session: SessionID(uncheckedEpoch: epoch)), case .opened(let c, let r, let ch, _, _) = ev {
        seen = "\(c) \(r)Hz x\(ch)"
    }
    var bytes = 0, chunks = 0, eof = false
    var digest: UInt64 = 14695981039346656037
    for _ in 0..<10000 {
        guard let event = await d.nextEvent(session: SessionID(uncheckedEpoch: epoch)) else { break }
        switch event {
        case .pcm(let frame):
            bytes += frame.bytes.count; chunks += 1
            for b in frame.bytes { digest = (digest ^ UInt64(b)) &* 1099511628211 }
        case .endOfStream: eof = true
        case .failed(let code, _): seen = "decode-failed: \(code)"
        default: break
        }
        if eof { break }
    }
    await d.close(session: SessionID(uncheckedEpoch: epoch))
    return "\(seen) bytes=\(bytes) chunks=\(chunks) eof=\(eof) fnv=\(String(digest, radix:16))"
}

let noCred = await probeOpen(withOptions: SourceOpenOptions(tlsCAFile: cert), epoch: 91)
check("S1 remote open without credentials is refused by the server", noCred.hasPrefix("open-error"), noCred)
let withCred = await probeOpen(withOptions: SourceOpenOptions(headers: ["X-GorAV-Test": "yes"], cookies: ["session": "abc", "other": "def"], tlsCAFile: cert), epoch: 92)
let local = await probeOpen(withOptions: nil, epoch: 96, input: fixture)
print("redirect-remote: \(withCred)")
print("reference-local: \(local)")
check("redirect chain actual decoded PCM equals local product decode", withCred == local && withCred.contains("eof=true") && !withCred.contains("bytes=0 "), withCred)

let injected = await probeOpen(withOptions: SourceOpenOptions(headers: ["X-GorAV-Test": "yes\r\nX-Injected: true"]), epoch: 95)
check("S2b header newline injection refused", injected.hasPrefix("open-error"), injected)

// S3: transport failure errors carry the redacted URL, never the secret
let d2 = FFmpegSoftwareAudioDecoder()
try! d2.pinLocalRoots([root])
let secretURL = "http://user:s3cr3t@127.0.0.1:1/x.wav?token=abc123"
do {
    try await d2.open(source: SourceDescriptor(id: secretURL, kind: .remote, seekable: true), session: SessionID(uncheckedEpoch: 93))
    check("S3 dead-endpoint open throws", false, "opened")
} catch {
    let msg = "\(error)"
    check("S3 error redacts userinfo and query", msg.contains("REDACTED") && !msg.contains("s3cr3t") && !msg.contains("abc123"), msg)
}

// S4: scheme admission still enforced for the audio path
do {
    try await d2.open(source: SourceDescriptor(id: "ftp://127.0.0.1/x.wav", kind: .remote, seekable: true), session: SessionID(uncheckedEpoch: 94))
    check("S4 non-admitted scheme refused", false, "opened")
} catch {
    check("S4 non-admitted scheme refused", "\(error)".contains("scheme not admitted"), "\(error)")
}

// Second server has a trusted certificate for wrong.invalid, not 127.0.0.1.
let wrongCert = ProcessInfo.processInfo.environment["M2_TLS_WRONG_CERT"]!
let wrongKey = ProcessInfo.processInfo.environment["M2_TLS_WRONG_KEY"]!
let wrongPortFile = tmp + "/wrong-port"
let wrongServer = Process()
wrongServer.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
wrongServer.arguments = [serverPy, fixture, wrongPortFile, wrongCert, wrongKey]
try! wrongServer.run()
var wrongPort: String?
for _ in 0..<200 {
    if let value = try? String(contentsOfFile: wrongPortFile, encoding: .utf8), !value.isEmpty {
        wrongPort = value.trimmingCharacters(in: .whitespacesAndNewlines); break
    }
    try? await Task.sleep(nanoseconds: 50_000_000)
}
if let wrongPort {
    let wrongHost = await probeOpen(withOptions: SourceOpenOptions(headers: ["X-GorAV-Test": "yes"], cookies: ["session": "abc", "other": "def"], tlsCAFile: wrongCert), epoch: 110, input: "https://127.0.0.1:\(wrongPort)/share")
    check("TLS trusted chain but wrong hostname rejected", wrongHost.hasPrefix("open-error"), wrongHost)
} else { check("TLS wrong-host fixture starts", false) }
wrongServer.terminate()
let untrusted = await probeOpen(withOptions: SourceOpenOptions(headers: ["X-GorAV-Test": "yes"], cookies: ["session": "abc", "other": "def"], tlsCAFile: wrongCert), epoch: 111)
check("TLS wrong CA rejects encrypted source", untrusted.hasPrefix("open-error"), untrusted)
let systemTrust = await probeOpen(withOptions: SourceOpenOptions(headers: ["X-GorAV-Test": "yes"], cookies: ["session": "abc", "other": "def"]), epoch: 112)
check("TLS default trust rejects self-signed fixture", systemTrust.hasPrefix("open-error"), systemTrust)

proc.terminate()
print(failures == 0 ? "m2-tls-verified-pcm: all pass" : "remote-source-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
```

```c id=inventory
#include <stdio.h>
#include <string.h>
#include <libavformat/avio.h>
#include <libavformat/avformat.h>
int main(void) {
    void *opaque = NULL; const char *p; int h=0,t=0,s=0;
    printf("avformat_version=%u\nconfiguration=%s\n",avformat_version(),avformat_configuration());
    while ((p=avio_enum_protocols(&opaque,0))) {
        printf("input_protocol=%s\n",p);
        h |= !strcmp(p,"http"); t |= !strcmp(p,"tcp"); s |= !strcmp(p,"https");
    }
    printf("provider-required: http=%d tcp=%d https=%d\n",h,t,s);
    return h&&t&&s ? 0 : 1;
}
```

```text id=fixtures1
Pinned fixtures/tone-48k.wav; ephemeral loopback HTTPS servers with exact fixtureCA and deliberately wrong-host certificate. No external service request. Keys generated per run, removed on exit. Supplied measurement176400B/13chunks/FNV94de25bf8548e55d EOFtrue from both encrypted and local paths.
```

