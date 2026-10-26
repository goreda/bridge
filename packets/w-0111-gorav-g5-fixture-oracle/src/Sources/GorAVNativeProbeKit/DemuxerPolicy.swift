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
    /// Containers admitted for probe fixtures. Anything else is a rejection, not a guess.
    public static let admittedContainers: Set<String> = ["mov,mp4,m4a,3gp,3g2,mj2", "matroska,webm"]
    /// Software-decodable video codecs admitted for the first probe.
    public static let admittedVideoCodecs: Set<String> = ["h264", "hevc", "mpeg4", "mpeg2video", "mpeg1video", "vp9", "av1"]
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
                         audioCodecName: String? = nil) -> Decision {
        guard DemuxerPolicy.admittedContainers.contains(containerName) else {
            return .reject(reason: "container not admitted: \(containerName)")
        }
        guard otherStreamCount == 0 else {
            return .reject(reason: "unsupported stream types rejected before first decode read (other=\(otherStreamCount))")
        }
        // Card 465 bounded muxed profile: real owner media is one container with
        // sibling A/V streams, and the probe's original no-audio rule made every
        // such file inadmissible. Admitted muxed shape: exactly one admitted
        // video codec stream plus exactly one pcm_s16le audio stream in the mov
        // family (the audio sibling is decoded by FFmpegSoftwareAudioDecoder's
        // matching profile). Every other mixed shape keeps the rejection.
        if audioStreamCount == 1 {
            guard containerName == "mov,mp4,m4a,3gp,3g2,mj2", audioCodecName == "pcm_s16le" else {
                return .reject(reason: "mixed-media audio profile not admitted (container=\(containerName) audioCodec=\(audioCodecName ?? "none"))")
            }
        } else if audioStreamCount != 0 {
            return .reject(reason: "expected at most one audio stream, found \(audioStreamCount)")
        }
        guard videoStreamCount == 1 else {
            return .reject(reason: "expected exactly one video stream, found \(videoStreamCount)")
        }
        guard let codec = videoCodecName, DemuxerPolicy.admittedVideoCodecs.contains(codec) else {
            return .reject(reason: "video codec not admitted: \(videoCodecName ?? "none")")
        }
        return .admit(container: containerName, videoCodec: codec)
    }
}
