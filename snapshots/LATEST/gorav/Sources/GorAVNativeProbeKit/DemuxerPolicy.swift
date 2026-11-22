// AUTHORED_R2 replacement (2026-10-16, ZDYM provider/build lane).
// NOT the pinned r1 member (pin 1747B/0650f2b8...); byte identity is not claimed.
// Role per DECODER-ONLY-TARGET-WIRING-r1: explicit demux admission.
import Foundation
import GorAVCore

/// Explicit demux admission for the decoder-only probe. An input is either
/// admitted with a recorded reason or rejected with a recorded reason; there is
/// no implicit fallback. Mixed-media sources are rejected pre-open (Stage 3 P-14).
public struct DemuxerPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case admit(container: String, videoCodec: String)
        case reject(reason: String)
    }
    /// d4 close-out (queue 36): the forwarding aliases are retired. Every
    /// admission set is read directly from GorAVCore AdmissionTable, the single
    /// source of truth; this type keeps only evaluate() and its decisions.
    public init() {}

    /// Admission check from probe facts. Runs post-open/post-stream-inventory and
    /// pre-decode (r4 D12: it cannot run before avformat_find_stream_info; the
    /// pre-open stage is the source-id allowlist in the adapter). streamCounts
    /// must come from actual demuxed
    /// stream inventory, never from filename or container sniffing alone.
    /// audioCodecName (card 465, 2026-10-25): actual demuxed audio codec for the
    /// bounded muxed profile below; nil preserves the original no-audio rule.
    public func evaluate(containerName: String,
                         videoCodecName: String?,
                         videoStreamCount: Int,
                         audioStreamCount: Int,
                         otherStreamCount: Int,
                         subtitleStreamCount: Int = 0,
                         audioCodecName: String? = nil,
                         sourceKind: SourceDescriptor.Kind? = nil,
                         sourceURL: String? = nil) -> Decision {
        // Queue 30: when the caller supplies the source class, a non-admitted
        // class is a loud rejection naming the kind (P14).
        if let kind = sourceKind, !AdmissionTable.isAdmittedSource(kind: kind) {
            return .reject(reason: "source kind not admitted: \(kind)")
        }
        // Queue 31/32: a remote or iptv source needs an admitted scheme; rejection names it.
        if let kind = sourceKind, AdmissionTable.schemeGatedKinds.contains(kind) {
            guard let url = sourceURL else { return .reject(reason: "\(kind) source without a URL") }
            guard AdmissionTable.isAdmittedRemoteURL(url) else {
                return .reject(reason: "\(kind) scheme not admitted: \(AdmissionTable.remoteScheme(of: url) ?? "(none)")")
            }
        }
        guard AdmissionTable.probeContainers.contains(containerName) else {
            return .reject(reason: "container not admitted: \(containerName)")
        }
        // arch-196t r2 item 4a: embedded subtitle streams (PGS, VobSub,
        // WebVTT) are admitted and counted separately by the caller; routing
        // them into the subtitle seams is a playback-path wiring step, not an
        // admission rejection. Truly unknown stream types still refuse.
        guard otherStreamCount == 0 else {
            return .reject(reason: "unsupported stream types rejected before first decode read (other=\(otherStreamCount), subtitles=\(subtitleStreamCount))")
        }
        // Card 465 bounded muxed profile: real owner media is one container with
        // sibling A/V streams, and the probe's original no-audio rule made every
        // such file inadmissible. Admitted muxed shape: exactly one admitted
        // video codec stream plus exactly one admitted audio stream in MOV or Matroska
        // containers (the audio sibling is decoded by FFmpegSoftwareAudioDecoder's
        // matching profile). Every other mixed shape keeps the rejection.
        if audioStreamCount == 1 {
            // L3 (2026-10-25): muxed audio widened from pcm_s16le-in-mov to the
            // L3 audio set across the mov family and matroska. Conversion to
            // the sink contract is owned by FFmpegSoftwareAudioDecoder.
            guard AdmissionTable.muxedContainers.contains(containerName),
                  let audio = audioCodecName, AdmissionTable.audioCodecs.contains(audio) else {
                return .reject(reason: "mixed-media audio profile not admitted (container=\(containerName) audioCodec=\(audioCodecName ?? "none"))")
            }
        } else if audioStreamCount != 0 {
            return .reject(reason: "expected at most one audio stream, found \(audioStreamCount)")
        }
        guard videoStreamCount == 1 else {
            return .reject(reason: "expected exactly one video stream, found \(videoStreamCount)")
        }
        guard let codec = videoCodecName, AdmissionTable.videoCodecs.contains(codec) else {
            return .reject(reason: "video codec not admitted: \(videoCodecName ?? "none")")
        }
        return .admit(container: containerName, videoCodec: codec)
    }
}
