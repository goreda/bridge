// d4 rung 1 (architect gorav night queue item 7, owner block 190): single
// admission table. ONE source of truth for container/codec admission sets;
// DemuxerPolicy (GorAVNativeProbeKit) and the adapters read it directly
// (forwarding aliases retired at queue 36). No mirrored copies, no KEEP IN SYNC.
import Foundation

/// Container/codec admission sets for the M1/L3 profile, shared by the probe
/// and the adapter. Set names carry their role; anything outside a set is a
/// refusal, never a guess.
public enum AdmissionTable {
    /// Containers the L3 profile admits at all (adapter side; wav is the
    /// PCM WAV profile the adapter decodes directly).
    public static let containers: Set<String> = ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts", "wav"]
    /// Containers admitted for the muxed (video + audio sibling) shape.
    public static let muxedContainers: Set<String> = ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts"]
    /// Containers the decoder-only probe admits. Stricter than the adapter
    /// set: no wav (the probe is a video probe; wav carries no video stream).
    public static let probeContainers: Set<String> = ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm", "mpegts"]
    /// M1 software video codecs; unbuilt codecs are refused. HEVC 10-bit
    /// originals remain preserved; no HDR tone mapping claim. arch-196t
    /// item 4: + av1, vp9 for the real-media matrix.
    public static let videoCodecs: Set<String> = ["mpeg4", "h264", "hevc", "av1", "vp9"]
    /// Audio codecs admitted as the muxed sibling or the wav profile.
    /// arch-196t item 4 (2026-11-15): real-media matrix - DTS, AC3, EAC3,
    /// AAC, Opus, FLAC, TrueHD, MP3, PCM. Admission requires the pinned
    /// FFmpeg to carry the matching decoder; a missing decoder is a typed
    /// "no decoder for admitted codec" refusal at open, never a guess.
    /// Non-pcm codecs decode through FFmpegSoftwareAudioDecoder's L3 path and
    /// are converted to the sink contract (packed s16le stereo 44.1 kHz).
    public static let audioCodecs: Set<String> = ["pcm_s16le", "aac", "dts", "ac3", "eac3", "opus", "flac", "truehd", "mp3"]
    /// Codecs that attempt VideoToolbox with the measured software fallback
    /// (L4, block 168 m2). mpeg4 has no VT hwaccel and av1 stays
    /// software-by-policy. Off-Darwin the shim refuses and decode proceeds in
    /// software - receipt-recorded.
    public static let hardwareAttemptCodecs: Set<String> = ["h264", "hevc"]

    /// d4 rungs 2-7 (queue 30-35, ladder complete): source classes admitted: local,
    /// remote, iptv, webTorrent, ytdl and archiveOrg (all but local only behind the
    /// http/https scheme allowlist below; a webTorrent id is an HTTP(S) URL served
    /// by the wt_server bridge, a ytdl id is an HTTP(S) URL resolved by the ytdl
    /// step, an archiveOrg id is an HTTP(S) URL into the archive).
    /// HLS/.m3u8 and torrent-protocol handling are out of scope: this is a
    /// source-class admission decision only.
    public static let admittedSourceKinds: Set<SourceDescriptor.Kind> = [.local, .remote, .iptv, .webTorrent, .ytdl, .archiveOrg]
    /// Kinds that must also carry an admitted URL scheme.
    public static let schemeGatedKinds: Set<SourceDescriptor.Kind> = [.remote, .iptv, .webTorrent, .ytdl, .archiveOrg]

    /// d4 rung 3 (queue 31): remote schemes admitted. Scheme-prefix parse only.
    public static let admittedRemoteSchemes: [String] = ["http", "https"]

    /// The scheme of a source id ("http" for "HTTP://x"), lowercased; nil when
    /// the id carries no "scheme://" prefix.
    public static func remoteScheme(of url: String) -> String? {
        guard let r = url.range(of: "://") else { return nil }
        let scheme = url[url.startIndex ..< r.lowerBound]
        guard !scheme.isEmpty else { return nil }
        return scheme.lowercased()
    }

    /// Remote URL admission: case-insensitive scheme match against the
    /// allowlist; nothing else is consulted.
    public static func isAdmittedRemoteURL(_ url: String) -> Bool {
        guard let scheme = remoteScheme(of: url) else { return false }
        return admittedRemoteSchemes.contains(scheme)
    }

    /// Source-class admission: the single source of truth for the kind axis.
    public static func isAdmittedSource(kind: SourceDescriptor.Kind) -> Bool {
        admittedSourceKinds.contains(kind)
    }

    /// Muxed audio admission from demuxed facts.
    public static func isAdmittedMuxedAudio(container: String, audioCodec: String) -> Bool {
        muxedContainers.contains(container) && audioCodecs.contains(audioCodec)
    }

    /// Whether a session should try to attach VideoToolbox for the codec.
    /// GORAV_L3_DISABLE_HW=1 forces the software path: the deterministic,
    /// reproducible arm of the clean-fallback acceptance evidence.
    public static func shouldAttemptHardware(videoCodec: String,
                                             environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard hardwareAttemptCodecs.contains(videoCodec) else { return false }
        if environment["GORAV_L3_DISABLE_HW"] == "1" { return false }
        return true
    }

    /// P30/W2 (arch-196z E1, arch-197a item 2, arch-197b): whether an attached
    /// VideoToolbox session keeps VT frames GPU-resident for the zero-copy
    /// present path (CVPixelBuffer -> CVMetalTextureCache, YUV->RGB in the
    /// shader BEFORE the colour stage) instead of transferring every frame to
    /// software (a CPU copy). GORAV_VT_ZEROCOPY=1 arms it; the transfer path
    /// stays the DEFAULT until the native E1 gate (VTRECEIPT cpuCopies=0
    /// cpuYUVtoRGB=0 on h264/hevc/hevc10) has passed on the armed tree.
    /// Inert off-Darwin: no VT-format frame exists there, so an armed
    /// session's zero-copy receive passes software frames through untouched
    /// (l4-hwdecode-tests prove the invariance on Linux).
    public static func shouldArmVTZeroCopy(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment["GORAV_L3_DISABLE_HW"] == "1" { return false }
        return environment["GORAV_VT_ZEROCOPY"] == "1"
    }
}
