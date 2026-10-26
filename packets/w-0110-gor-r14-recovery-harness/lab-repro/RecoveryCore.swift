import Foundation

// ============================================================================
// W-0110 gor r14 recovery-state regression harness - extracted production core
// Source pin: goreda/bridge @ 91da2e7f2433e712a8b9341b404ffa6ce1fd9964
//   packets/w-0110-gor-r14-recovery-harness/AppDelegate.swift
//   sha256 3ce05563098bc930d96315f657aa2a71676e6a73a66493278ced6dd9af380a55
// Extraction policy: recovery fields, classifier, invalidate and
// handleYoutubeOpenFailure bodies are the actual production source. Every
// deviation is a disclosed mechanical injection, listed in TRANSFORMATIONS.md.
// ============================================================================

/// Minimal slice of Foundation.Process used by the production -U update block.
/// Production news a `Process()`; the harness injects a LABELED FAKE.
protocol UpdateProcess: AnyObject {
    var executableURL: URL? { get set }
    var arguments: [String]? { get set }
    var standardOutput: Any? { get set }
    var standardError: Any? { get set }
    var terminationStatus: Int32 { get }
    func run() throws
    func waitUntilExit()
}

/// Deterministic executor: queued blocks run only on explicit harness ACK.
/// Replaces DispatchQueue.global/.main so async ordering is gates/ACK, never
/// sleeps. LABELED FAKE (Dispatch executor).
protocol RecoveryExecutor {
    func async(_ work: @escaping () -> Void)
}

final class RecoveryCore {
    // ================================================================
    // EXTRACTED VERBATIM - recovery state fields
    // (source lines 117-124 of pinned AppDelegate.swift)
    // ================================================================
    var lastPlayedURL: String? = nil
    var lastPlayedTitle: String = ""
    var lastPlayedStartPos: Double? = nil
    var youtubePlaybackGeneration: UInt64 = 0
    var lastPlayedSubtitleURLs: [String] = []
    var youtubeRetryAttempted = false
    var ytdlpUpdateInProgress = false
    var ytdlpUpdateCheckedThisSession = false

    // ---------------------------------------------------------------
    // INJECTION POINTS (disclosed transformations, see TRANSFORMATIONS.md)
    // ---------------------------------------------------------------
    /// Production: AppDelegate.stagedYtDlpPath() reads Bundle.main and the
    /// Application Support staging dir. Harness injects a fixture path.
    var stagedYtDlpPathProvider: () -> String = { "" }
    /// Production: controller?.currentTime (PPController is AppKit-side).
    var currentTimeProvider: () -> Double? = { nil }
    /// Production: mpvProcess: Process?. Harness keeps identity semantics via
    /// an AnyObject token; `===` guards are unchanged.
    var mpvProcessToken: AnyObject? = nil
    /// Production: Process(). Harness injects a labeled fake UpdateProcess.
    var updateProcessFactory: () -> UpdateProcess = {
        fatalError("harness must inject updateProcessFactory")
    }
    /// Production: DispatchQueue.global(qos: .userInitiated) / .main.
    var backgroundExecutor: RecoveryExecutor = GatedExecutor(label: "background")
    var mainExecutor: RecoveryExecutor = GatedExecutor(label: "main")

    // ---------------------------------------------------------------
    // RECORDING STUB (labeled): playMedia is product code outside the pinned
    // source file; the harness records calls for assertion.
    // ---------------------------------------------------------------
    struct PlayMediaCall {
        let url: String
        let title: String
        let startPos: Double
        let subtitleURLs: [String]
    }
    private(set) var playMediaCalls: [PlayMediaCall] = []
    func playMedia(url: String, title: String, startPos: Double, subtitleURLs: [String]) {
        playMediaCalls.append(.init(url: url, title: title, startPos: startPos, subtitleURLs: subtitleURLs))
    }

    // ================================================================
    // EXTRACTED VERBATIM - classifier
    // (MARK: - YouTube auto-recovery, source lines 1233-1244)
    // ================================================================
    static func isYoutubeURL(_ value: String) -> Bool {
        guard let host = URLComponents(string: value)?.host?.lowercased() else { return false }
        return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
    }

    static func isYoutubeOpenFailureDiagnostic(_ line: String) -> Bool {
        // Opening URLs and nested script probes are NOT player failures.
        // For example slices=38455247-40324801 triggered the former contains(403).
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("Failed to open ") || text.hasPrefix("[cplayer] Failed to open ") { return true }
        let pattern = #"^(?:\[(?:https?|tls|ffmpeg(?:/https?)?|ytdl_hook)(?: @ 0x[0-9a-fA-F]+)?\]\s*)?(?:HTTP error 403(?:\s|:|$)|Server returned 403(?:\s|:|$)|ERROR:.*(?:HTTP Error 403:|403 Forbidden))"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // ================================================================
    // EXTRACTED VERBATIM - invalidate
    // (source lines 1247-1253; dispatchPrecondition line removed,
    //  disclosed in TRANSFORMATIONS.md)
    // ================================================================
    // Called at load intent, not after the asynchronous path poll catches up.
    func invalidateYoutubeRecovery() {
        youtubePlaybackGeneration &+= 1
        lastPlayedURL = nil
        lastPlayedSubtitleURLs = []
        youtubeRetryAttempted = false
    }

    // ================================================================
    // EXTRACTED with disclosed mechanical injections - recovery handler
    // (source lines 1255-1317). Body text is production; only the marked
    // injection tokens differ (stagedYtDlpPathProvider, currentTimeProvider,
    // mpvProcessToken, updateProcessFactory, backgroundExecutor, mainExecutor,
    // playMedia stub, dispatchPrecondition removed).
    // ================================================================
    func handleYoutubeOpenFailure() {
        guard !youtubeRetryAttempted, !ytdlpUpdateInProgress,
              let url = lastPlayedURL, Self.isYoutubeURL(url) else { return }
        youtubeRetryAttempted = true
        ytdlpUpdateInProgress = true
        let generation = youtubePlaybackGeneration
        let playbackProcess = mpvProcessToken
        let title = lastPlayedTitle
        let subtitles = lastPlayedSubtitleURLs
        let observed = currentTimeProvider() ?? 0
        let failurePosition = observed.isFinite && observed > 0 ? observed : (lastPlayedStartPos ?? 0)
        let ytdlpPath = stagedYtDlpPathProvider()
        guard FileManager.default.fileExists(atPath: ytdlpPath) else {
            print("[yt-dlp-recovery] staged binary missing; no reload")
            ytdlpUpdateInProgress = false
            return
        }
        if ytdlpPath.contains("/yt-dlp-standalone/") {
            // One bounded fresh URL resolution per load intent, WITHOUT -U.
            // This is a retry, not proof the CDN403 root cause is cured.
            ytdlpUpdateInProgress = false
            guard youtubePlaybackGeneration == generation, lastPlayedURL == url,
                  mpvProcessToken === playbackProcess else { return }
            print("[yt-dlp-recovery] standalone extractor: one fresh resolution, no updater")
            playMedia(url: url, title: title, startPos: failurePosition, subtitleURLs: subtitles)
            youtubeRetryAttempted = true
            return
        }
        guard !ytdlpUpdateCheckedThisSession else { ytdlpUpdateInProgress = false; return }
        ytdlpUpdateCheckedThisSession = true
        print("[yt-dlp-recovery] verified player failure; checking extractor update once this session")
        let updateProcessFactory = self.updateProcessFactory
        let mainExecutor = self.mainExecutor
        backgroundExecutor.async { [weak self] in
            let update = updateProcessFactory()
            update.executableURL = URL(fileURLWithPath: ytdlpPath)
            update.arguments = ["-U"]
            update.standardOutput = FileHandle.nullDevice
            update.standardError = FileHandle.nullDevice
            let before = try? Data(contentsOf: URL(fileURLWithPath: ytdlpPath))
            var succeeded = false
            do {
                try update.run()
                update.waitUntilExit()
                let after = try? Data(contentsOf: URL(fileURLWithPath: ytdlpPath))
                succeeded = update.terminationStatus == 0 && before != nil && after != nil && before != after
                print("[yt-dlp-recovery] update status=\(update.terminationStatus) extractorChanged=\(succeeded)")
            } catch {
                print("[yt-dlp-recovery] update launch failed: \(error)")
            }
            let updateSucceeded = succeeded
            mainExecutor.async {
                guard let self else { return }
                self.ytdlpUpdateInProgress = false
                guard updateSucceeded, self.youtubePlaybackGeneration == generation,
                      self.lastPlayedURL == url, self.mpvProcessToken === playbackProcess else { return }
                let current = self.currentTimeProvider() ?? 0
                let resume = current.isFinite && current > 0 ? current : failurePosition
                print("[yt-dlp-recovery] retry current source at \(resume)s")
                self.playMedia(url: url, title: title, startPos: resume, subtitleURLs: subtitles)
                self.youtubeRetryAttempted = true
            }
        }
    }
}
