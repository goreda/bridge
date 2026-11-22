// ================================================================
//  GorAVLocalOffer.swift - per-file gorav offer for local media (arch-196t r3)
//  Owns: probing a local file with ffprobe and evaluating the exact same
//  DemuxerPolicy the gorav engine applies, so the owner's HUD reason is the
//  engine's own verdict ("gorav: <reason> -> mpv", never a refusal dialog).
//  A refusal or a probe failure never blocks playback: the caller plays the
//  same file on mpv in the same window at once.
//  The offer never decides from filename or container sniffing alone
//  (DemuxerPolicy contract); the ffprobe stream inventory mirrors the
//  engine's avformat_find_stream_info counting in FFmpegSoftwareDecoder.swift
//  (video/audio counted by codec type, first video/audio codec named, every
//  remaining stream type counted as other).
// ================================================================
import Foundation
import GorAVNativeProbeKit

enum GorAVLocalOffer {
    enum Outcome: Equatable {
        /// The engine's policy would take the file; the in-window gorav host
        /// rides the integrator's playback-path item, so today the caller
        /// still falls back to mpv with this detail in the HUD reason.
        case admitted(String)
        /// The engine's own DemuxerPolicy rejection reason, verbatim.
        case refused(String)
        /// ffprobe missing/failed; mpv plays, the offer never blocks it.
        case probeUnavailable(String)
    }

    struct ProbeFacts: Equatable {
        var containerName = ""
        var videoCodec: String? = nil
        var audioCodec: String? = nil
        var videoStreams = 0
        var audioStreams = 0
        var subtitleStreams = 0
        var otherStreams = 0
    }

    static func offer(path: String) -> Outcome {
        switch probe(path: path) {
        case .failure(let reason): return .probeUnavailable(reason)
        case .success(let facts): return decide(facts)
        }
    }

    static func decide(_ f: ProbeFacts) -> Outcome {
        switch DemuxerPolicy().evaluate(containerName: f.containerName,
                                        videoCodecName: f.videoCodec,
                                        videoStreamCount: f.videoStreams,
                                        audioStreamCount: f.audioStreams,
                                        otherStreamCount: f.otherStreams,
                                        subtitleStreamCount: f.subtitleStreams,
                                        audioCodecName: f.audioCodec) {
        case .admit(let container, let videoCodec):
            return .admitted("\(container)/\(videoCodec)")
        case .reject(let reason):
            return .refused(reason)
        }
    }

    /// Probe outcome; the failure carries the plain-language reason for the HUD
    /// and the diagnostics record. String is not an Error, so no Result<_, String>.
    enum ProbeResult {
        case success(ProbeFacts)
        case failure(String)
    }

    /// ffprobe JSON probe, same established binary locations as FileBrowser's
    /// aspect probe (ffmpeg/bin/ffprobe is the documented PENDING vendor gap).
    /// Hard-bounded (A-D successor reading, 2026-11-15): the read + reap run on
    /// a utility queue under a semaphore deadline; on expiry the child is
    /// SIGKILLed - which also ends the stuck read, and the background wait then
    /// reaps it - and the offer refuses with a reason, so a hung ffprobe can
    /// never wedge the open path.
    static func probe(path: String, timeoutSeconds: Double = 5) -> ProbeResult {
        guard let ffprobe = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return .failure("ffprobe unavailable")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffprobe)
        p.arguments = ["-v", "error", "-show_format", "-show_streams", "-of", "json", path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return .failure("ffprobe launch failed") }
        final class ProbeBox { var data = Data(); var status: Int32 = -1 }
        let box = ProbeBox(), done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            box.data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            box.status = p.terminationStatus
            done.signal()
        }
        guard done.wait(timeout: .now() + timeoutSeconds) == .success else {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            return .failure("ffprobe timed out")
        }
        guard box.status == 0,
              let obj = try? JSONSerialization.jsonObject(with: box.data) as? [String: Any] else {
            return .failure("ffprobe could not read the file")
        }
        var f = ProbeFacts()
        f.containerName = (obj["format"] as? [String: Any])?["format_name"] as? String ?? ""
        guard !f.containerName.isEmpty else { return .failure("ffprobe reported no container") }
        for case let s as [String: Any] in (obj["streams"] as? [Any]) ?? [] {
            switch s["codec_type"] as? String {
            case "video": f.videoStreams += 1; if f.videoCodec == nil { f.videoCodec = s["codec_name"] as? String }
            case "audio": f.audioStreams += 1; if f.audioCodec == nil { f.audioCodec = s["codec_name"] as? String }
            // arch-196t r2 item 4a: embedded subtitle streams (PGS, VobSub,
            // WebVTT) are admitted and counted separately, never as "other".
            case "subtitle": f.subtitleStreams += 1
            default: f.otherStreams += 1
            }
        }
        return .success(f)
    }
}
