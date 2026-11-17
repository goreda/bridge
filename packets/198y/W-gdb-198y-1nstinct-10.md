# W-gdb-198y-1nstinct-10
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/LiveCaptionController.swift -> GorSubtitles. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-10.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-10",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/LiveCaptionController.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/LiveCaptionController.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: LiveCaptionRenderMode, LiveCaptionController, resolvedRenderMode, Config, discoveredModels, rankedCandidates, installedModels, start, stop, teardown, writePCM, handleStdout",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-10.py",
    "callee": "archive/gor/Sources/gor/LiveCaptionController.swift owning station GorSubtitles"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-10.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-10.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-10.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.380717+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/LiveCaptionController.swift",
        "block": "source1",
        "sha256": "d749b6d29a80423faa9e66d8b274b7103b4ce477c57ee3c54c7ed861c4c04da3"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-10.py",
        "block": "fixtures1",
        "sha256": "e049a10b248fd4707c19242820d265403728430a46f8597caf78c44c10fa87bd"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "3935919cd522893c593b731dc7dd62b2f085c3a20d61d4e3df29a4fed9ab5b3c",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-10: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "8dc97e275e194c13a6e0f5b0bf072fe184f22a828987a8a6c4580c09fb5cfb76"
  }
}
```

```swift id=source1
// ================================================================
//  LiveCaptionController.swift - whisper-live subprocess + caption renderer
//  Owns: whisper-live process lifecycle, PCM feed from ScreenCaptureEngine,
//  partial/final re-timing state
//  Contract: isActive guards PPController's sub-text path so live captions
//  and mpv cues never both call subtitleView.show() in one tick; also read
//  by SubtitleView.Config.liveCaptionActive for bottom-center placement
// ================================================================
import Foundation

// ================================================================
//  LiveCaptionRenderMode - caption reveal pacing
//  segmentCut updates partials in place; wordByWord reveals paced inside
//  a fixed trailing window; hybrid = wordByWord partials + hard-clear on final.
// ================================================================
enum LiveCaptionRenderMode {
    case segmentCut
    case wordByWord
    case hybrid
}

final class LiveCaptionController {

    static let shared = LiveCaptionController()
    private init() {}

    // MARK: - Public state

    private(set) var isActive = false

    /// "tiny" trades accuracy for headroom on older/slower Apple Silicon.
    var modelName: String = "small"
    /// Explicit parser-supported worker count. Default matches whisper-live's existing4.
    var inferenceThreads: Int = 4

    /// Manual language override. nil/"auto" keeps whisper-live's own
    /// auto-detect + language-lock smoothing; a whisper language code is
    /// passed straight through as -l. Wired from SpineUI's language picker.
    var preferredLanguage: String? = nil

    /// nil (default) picks per message from whisper-live's measured
    /// pace_ms (see resolvedRenderMode(for:)); a concrete mode pins
    /// behavior regardless of model speed.
    /// WHY automatic: a fast model supports live word-by-word reveal, a
    /// slow one reads better as segmentCut; pace_ms adapts with no code
    /// change on either side when the loaded model changes.
    var renderMode: LiveCaptionRenderMode? = nil

    // ms - pace below this picks word-by-word reveal, at/above picks
    // segmentCut; midway between tiny (~200-400ms) and medium (~1.3-2.5s)
    private static let paceAdaptiveThresholdMs = 800.0

    // s - minimum wall-clock between automatic mode switches, so one
    // pace_ms sample near the threshold can't flip modes back and forth
    private static let autoModeSwitchDebounceSeconds = 5.0
    private var lastAutoModeSwitchWall: Date = .distantPast
    private var currentAutoMode: LiveCaptionRenderMode = .hybrid

    /// Pinned renderMode if set, else the debounced automatic choice from pace_ms.
    private func resolvedRenderMode(for paceMs: Double?) -> LiveCaptionRenderMode {
        if let pinned = renderMode {
            return pinned
        }
        guard let paceMs = paceMs, paceMs >= 0 else {
            // No pace data yet (first message, before whisper_full()
            // completes) - hold the last resolution rather than guess.
            return currentAutoMode
        }
        let wantsSegmentCut = paceMs >= Self.paceAdaptiveThresholdMs
        // WHY: .hybrid, not .wordByWord, is the fast-model choice - same
        // live reveal, but wordByWord never hard-clears on final (see
        // handleIncomingFinal), which let old text sit behind new text.
        let wanted: LiveCaptionRenderMode = wantsSegmentCut ? .segmentCut : .hybrid
        if wanted != currentAutoMode {
            let now = Date()
            if now.timeIntervalSince(lastAutoModeSwitchWall) >= Self.autoModeSwitchDebounceSeconds {
                currentAutoMode = wanted
                lastAutoModeSwitchWall = now
                print("[LiveCaption] auto render mode -> \(wanted) (pace_ms=\(Int(paceMs)))")
            }
        }
        return currentAutoMode
    }

    // MARK: - Config

    private struct Config {
        static let vadModelFile   = "ggml-silero-v6.2.0.bin"
        static let sampleRate     = 16000  // must match whisper-live's expected input rate
        static let windowSeconds  = 6.0
        // s - floor only: whisper-live stretches its own cadence upward
        // when a pass takes longer than this (see main.cpp "Adaptive step")
        static let stepSeconds    = 1.0
        // Reading-duration model for final captions: ~3 words/sec, clamped.
        static let wordsPerSecond = 3.0
        static let minFinalDuration = 1.2
        static let maxFinalDuration = 8.0
        static let partialDuration  = 2.5

        // Higher-quality families first; file discovery supplies available variants.
        // Unknown models remain visible, but are excluded from automatic ranking
        // until their quality and language support have been vetted.
        static let modelFamilies = ["large-v3-turbo", "large-v3", "large-v2", "large", "medium", "small", "base", "tiny"]

        // s/word - reveal pacing tuned for reading comfort, slightly
        // slower than speech (~2.5-3 words/sec): faster reads as flicker,
        // slower reads as lagging the speaker
        static let wordRevealBaseInterval = 0.28
        static let wordRevealMinInterval  = 0.12  // floor when catching up on a backlog
        static let wordRevealMaxInterval  = 0.45  // ceiling when only 1 new word arrived
        // words - past this backlog, reveal speeds up so captions don't
        // fall further behind a burst (a whole clause in one tick)
        static let backlogSpeedupThreshold = 4
        // words - fixed trailing window for wordByWord/hybrid partials;
        // never grows, so no reflow to a second line
        static let trailingWordWindow = 8
    }

    // MARK: - Process plumbing

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = Data()
    // Main-queue caption callbacks from a stopped subprocess must never
    // render into a replacement session.
    private var captionGeneration: UInt64 = 0

    // MARK: - Wiring points (set by PPController.setupLiveCaption())

    /// Called whenever a partial or final caption should be shown.
    /// PPController wires this inline, closing over self.currentTime and
    /// self.subtitleView, and calls subtitleView.show(text:duration:at:).
    var onCaption: ((_ text: String, _ duration: Double, _ isFinal: Bool) -> Void)?

    /// Called on any subprocess failure (missing binary, crash, EOF) so
    /// PPController can surface it and flip the dropdown row back off.
    var onFailure: ((String) -> Void)?

    // MARK: - Lifecycle

    /// Discover installed ggml binaries, not a frozen list of filenames.
    /// Silero is a VAD model, never a transcription candidate.
    private func discoveredModels(in modelsDir: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: modelsDir) else { return [] }
        return names.compactMap { name -> String? in
            guard name.hasPrefix("ggml-"), name.hasSuffix(".bin"),
                  !name.hasPrefix("ggml-silero"), !name.hasPrefix("ggml-vad") else { return nil }
            let path = modelsDir + "/" + name
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return nil }
            return String(name.dropFirst(5).dropLast(4))
        }.sorted()
    }

    /// Auto mode uses known multilingual families in quality order. Unknown
    /// files and .en models stay manually selectable, not guessed as equal-quality.
    private func rankedCandidates(in modelsDir: String) -> [String] {
        let installed = Set(discoveredModels(in: modelsDir))
        return Config.modelFamilies.flatMap { family in
            [family, family + "-q5_0"].filter { installed.contains($0) }
        }
    }

    func installedModels() -> [String] {
        guard let vendor = GORResources.vendor() else { return [] }
        return discoveredModels(in: vendor.appendingPathComponent("whisper/models").path)
    }

    func start() {
        guard !isActive else { return }
        guard let vendor = GORResources.vendor() else {
            onFailure?("vendor assets unavailable - no real bundled or sibling Resources/vendor")
            return
        }

        let binPath   = vendor.appendingPathComponent("whisper/whisper-live").path
        let modelsDir = vendor.appendingPathComponent("whisper/models").path
        let vadPath   = vendor.appendingPathComponent("whisper/models/\(Config.vadModelFile)").path

        guard FileManager.default.fileExists(atPath: binPath) else {
            onFailure?("whisper-live binary not found at \(binPath) — see BUILD_AND_INSTALL.md")
            return
        }

        // "auto" resolves to --auto-candidates plus -m auto. WHY largest-
        // first: whisper-live picks the first candidate under its pace
        // threshold, so a near-tie favors quality over raw speed. Candidate
        // discovery stays here, not in whisper-live (see select_best_model
        // in main.cpp).
        let isAutoModel = (modelName == "auto")
        var modelPath = ""
        var autoCandidatePaths: [String] = []

        if isAutoModel {
            autoCandidatePaths = rankedCandidates(in: modelsDir)
                .map { modelsDir + "/ggml-\($0).bin" }

            guard !autoCandidatePaths.isEmpty else {
                onFailure?("No whisper models found in \(modelsDir) for auto-select")
                return
            }
            modelPath = "auto"
        } else {
            guard discoveredModels(in: modelsDir).contains(modelName) else {
                onFailure?("Model not installed: \(modelName)")
                return
            }
            modelPath = modelsDir + "/ggml-\(modelName).bin"
            guard FileManager.default.fileExists(atPath: modelPath) else {
                onFailure?("Model not found at \(modelPath)")
                return
            }
        }

        let hasVAD = FileManager.default.fileExists(atPath: vadPath)
        if !hasVAD {
            print("[LiveCaption] ⚠️ VAD model not found at \(vadPath) — proceeding without VAD. " +
                  "Movie/show audio with music will produce noisy partials.")
        }

        let p   = Process()
        let inP = Pipe()
        let outP = Pipe()
        let errP = Pipe()

        p.executableURL = URL(fileURLWithPath: binPath)
        let threads=max(1,min(32,inferenceThreads))
        let diagnostics=LiveCaptionDiagnostics()
        diagnostics.begin(model:modelName,threads:threads,window:Config.windowSeconds,step:Config.stepSeconds,language:preferredLanguage ?? "auto",vad:hasVAD)
        var args = [
            "-m", modelPath,
            "--threads", String(threads),
            "-l", preferredLanguage ?? "auto",
            "--sample-rate", String(Config.sampleRate),
            "--window-seconds", String(Config.windowSeconds),
            "--step-seconds", String(Config.stepSeconds),
        ]
        if isAutoModel {
            args += ["--auto-candidates", autoCandidatePaths.joined(separator: ",")]
        }
        if hasVAD {
            args += ["-vm", vadPath]
        }
        p.arguments = args
        p.standardInput  = inP
        p.standardOutput = outP
        p.standardError  = errP

        // WHY: below mpv's audio thread priority so a burst of PCM writes
        // or JSON parsing never contends with playback (see SCEWorkerThread
        // in ScreenCaptureEngine).
        p.qualityOfService = .utility

        outP.fileHandleForReading.readabilityHandler = { [weak self, weak outP] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // Teardown, parser state, and caption rendering all run on main.
            // A callback already reading from an old pipe cannot append to
            // the replacement session's stdout buffer after stop/start.
            DispatchQueue.main.async { [weak self, weak outP] in
                guard let self = self, let oldPipe = outP,
                      self.isActive, self.stdoutPipe === oldPipe else { return }
                self.handleStdout(data)
            }
        }

        errP.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            diagnostics.ingest(data)
            if let s=String(data:data,encoding:.utf8) {print("[whisper-live stderr] \(s)")}
        }

        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                // A stopped process may exit after a replacement has started.
                // Its callback must not tear down the new process and PCM tap.
                guard let self = self, self.process === proc else { return }
                let wasActive = self.isActive
                self.teardown()
                if wasActive {
                    self.onFailure?("whisper-live exited unexpectedly (status \(proc.terminationStatus))")
                }
            }
        }

        do {
            try p.run()
        } catch {
            onFailure?("Failed to launch whisper-live: \(error)")
            return
        }

        process    = p
        stdinPipe  = inP
        stdoutPipe = outP
        stderrPipe = errP
        captionGeneration &+= 1
        isActive   = true

        // Enable the PCM tap only now — zero cost when live captions are off.
        ScreenCaptureEngine.shared.pcmTapEnabled = true
        ScreenCaptureEngine.shared.pcmHandler = { [weak self] buffer in
            self?.writePCM(buffer)
        }

        print("[LiveCaption] whisper-live started (model: \(modelName), vad: \(hasVAD)).")
    }

    func stop() {
        guard isActive else { return }
        teardown()
    }

    private func teardown() {
        ScreenCaptureEngine.shared.pcmTapEnabled = false
        ScreenCaptureEngine.shared.pcmHandler = nil

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        // Closing stdin's write end signals EOF to whisper-live's reader
        // thread (see main.cpp's stdin_reader_thread), which triggers a
        // clean shutdown rather than a kill.
        try? stdinPipe?.fileHandleForWriting.close()

        if let p = process, p.isRunning {
            // Give it a moment to exit cleanly on EOF before forcing.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) {
                if p.isRunning { p.terminate() }
            }
        }

        process    = nil
        stdinPipe  = nil
        stdoutPipe = nil
        stderrPipe = nil
        stdoutBuffer.removeAll()
        captionGeneration &+= 1
        isActive = false

        // WHY: renderer state must not leak into the next session - a fresh
        // start() would diff its first partial against stale words.
        cancelWordReveal()
        transcriptGapTimer?.invalidate(); transcriptGapTimer=nil
        subtitleBlocks = LiveCaptionBlocks()
        rendererLastPartialWords.removeAll()
    }

    // MARK: - PCM feed (called from ScreenCaptureEngine's SCStream callback queue)

    private func writePCM(_ buffer: UnsafeBufferPointer<Float>) {
        guard let handle = stdinPipe?.fileHandleForWriting, buffer.count > 0 else { return }
        let data = Data(bytes: buffer.baseAddress!, count: buffer.count * MemoryLayout<Float>.size)
        // WHY: FileHandle.write raises NSException on a broken pipe
        // (subprocess died mid-write) and has no throwing variant, so
        // guard the process is alive instead of try/catch.
        guard process?.isRunning == true else { return }
        handle.write(data)
    }

    // MARK: - stdout parsing (line-delimited JSON)

    private func handleStdout(_ data: Data) {
        stdoutBuffer.append(data)

        while let newlineRange = stdoutBuffer.range(of: Data([0x0A])) { // "\n"
            let lineData = stdoutBuffer.subdata(in: stdoutBuffer.startIndex..<newlineRange.lowerBound)
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex..<newlineRange.upperBound)
            guard !lineData.isEmpty else { continue }
            parseLine(lineData)
        }
    }

    private func parseLine(_ lineData: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              let type = json["type"] as? String else { return }

        // pace_ms is -1 (or absent on older binaries) before the first
        // whisper_full() call completes - treated as "no data yet", not a pace.
        let paceMs: Double? = {
            guard let raw = json["pace_ms"] as? Double, raw >= 0 else { return nil }
            return raw
        }()

        switch type {
        case "partial":
            guard let text = json["text"] as? String, !text.isEmpty else { return }
            handleIncomingPartial(text, paceMs: paceMs)

        case "final":
            guard let text = json["text"] as? String, !text.isEmpty else { return }
            handleIncomingFinal(text, paceMs: paceMs)

        case "status":
            if let msg = json["text"] as? String {
                Diag.log("[whisper-live status] \(msg)")
            }

        default:
            break
        }
    }

    // MARK: - Caption rendering (mode docs on LiveCaptionRenderMode)

    // Renderer state - main queue only (reveal timer and incoming JSON
    // both hop to .main before touching any of this).
    private var rendererLastPartialWords: [String] = []   // words already surfaced for the in-progress segment
    private var pendingWords: [String] = []                // confirmed-new words not yet revealed on screen
    private var revealedWindow: [String] = []              // trailing window currently on screen (wordByWord/hybrid)
    private var revealTimer: Timer?

    private var subtitleBlocks = LiveCaptionBlocks()
    private var transcriptGapTimer: Timer?
    private static let transcriptGapSeconds = 1.2

    private func renderSubtitleBlock(_ text: String, isFinal: Bool) {
        cancelWordReveal()
        transcriptGapTimer?.invalidate()
        if let block = subtitleBlocks.ingest(text, isFinal: isFinal) {
            showSegmentCut(text:block, isFinal:isFinal)
        }
        guard !isFinal else { return }
        let generation = captionGeneration
        transcriptGapTimer = Timer.scheduledTimer(withTimeInterval: Self.transcriptGapSeconds, repeats:false) { [weak self] _ in
            guard let self, self.isActive, self.captionGeneration == generation else { return }
            // No new transcript for a full window: close the current cue. Keep the
            // decoder's cumulative prefix as a fence so the old ring cannot replay it.
            self.subtitleBlocks.endUtterance()
            self.rendererLastPartialWords.removeAll()
            self.transcriptGapTimer = nil
        }
    }

    private func handleIncomingPartial(_ text: String, paceMs: Double?) {
        let generation = captionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, self.captionGeneration == generation else { return }
            self.renderSubtitleBlock(text, isFinal:false)
        }
    }

    private func handleIncomingFinal(_ text: String, paceMs: Double?) {
        let generation = captionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActive, self.captionGeneration == generation else { return }
            self.renderSubtitleBlock(text, isFinal:true)
        }
    }

    /// .segmentCut behavior and .hybrid's final tail: push text straight
    /// to subtitleView via onCaption, no reveal pacing. Duration: ~3
    /// words/sec for finals, fixed for partials.
    private func showSegmentCut(text: String, isFinal: Bool) {
        let duration: Double
        if isFinal {
            let wordCount = text.split(separator: " ").count
            let raw = Double(wordCount) / Config.wordsPerSecond
            duration = max(Config.minFinalDuration, min(raw, Config.maxFinalDuration))
        } else {
            duration = Config.partialDuration
        }
        onCaption?(text, duration, isFinal)
    }

    /// Diffs the incoming cumulative partial/final text against the words
    /// already surfaced for this segment and queues only newly-confirmed
    /// words. Contract: whisper-live's partials grow append-only within a
    /// segment, so a common-prefix diff is correct (not a general text diff).
    private func ingestPartialForWordReveal(_ text: String) {
        let words = text.split(separator: " ").map(String.init)

        // Common-prefix length against what we've already surfaced.
        var commonPrefix = 0
        while commonPrefix < words.count,
              commonPrefix < rendererLastPartialWords.count,
              words[commonPrefix] == rendererLastPartialWords[commonPrefix] {
            commonPrefix += 1
        }

        if commonPrefix == rendererLastPartialWords.count {
            // The common case mid-utterance: whisper's new read extends
            // what we already showed - queue only the new words.
            let newWords = Array(words[commonPrefix...])
            rendererLastPartialWords = words
            guard !newWords.isEmpty else { return }
            pendingWords.append(contentsOf: newWords)
            if revealTimer == nil {
                scheduleNextReveal()
            }
            return
        }

        // WHY: whisper revised its read mid-utterance (sliding window
        // re-reads the same audio with more context). Show its current
        // best guess immediately - waiting for multi-tick agreement adds
        // seconds of lag without guaranteeing stability. Cancel the
        // pending queue and jump the window straight to the new read.
        cancelWordReveal()
        rendererLastPartialWords = words
        let windowWords = words.suffix(Config.trailingWordWindow)
        revealedWindow = Array(windowWords)
        onCaption?(revealedWindow.joined(separator: " "), Config.partialDuration, false)
    }

    /// Interval shortens as the backlog grows so a burst of confirmed
    /// words catches up to real time instead of falling behind the speaker.
    private func nextRevealInterval() -> TimeInterval {
        guard pendingWords.count > Config.backlogSpeedupThreshold else {
            return pendingWords.count <= 1 ? Config.wordRevealMaxInterval : Config.wordRevealBaseInterval
        }
        let overflow = pendingWords.count - Config.backlogSpeedupThreshold
        let sped = Config.wordRevealBaseInterval - (Double(overflow) * 0.03)
        return max(Config.wordRevealMinInterval, sped)
    }

    private func scheduleNextReveal() {
        revealTimer?.invalidate()
        revealTimer = Timer.scheduledTimer(withTimeInterval: nextRevealInterval(), repeats: false) { [weak self] _ in
            self?.revealNextWord()
        }
    }

    private func revealNextWord() {
        revealTimer = nil
        guard !pendingWords.isEmpty else { return }
        let word = pendingWords.removeFirst()

        revealedWindow.append(word)
        if revealedWindow.count > Config.trailingWordWindow {
            revealedWindow.removeFirst(revealedWindow.count - Config.trailingWordWindow)
        }

        onCaption?(revealedWindow.joined(separator: " "), Config.partialDuration, false)

        if !pendingWords.isEmpty {
            scheduleNextReveal()
        }
    }

    private func cancelWordReveal() {
        revealTimer?.invalidate()
        revealTimer = nil
        pendingWords.removeAll()
        revealedWindow.removeAll()
    }
}

/// Subtitle-sized pages from a cumulative decoder transcript. Never slides a tail.
/// A gap fences the already-seen prefix, even when an older decoder retains audio.
struct LiveCaptionBlocks {
    static let maxWords = 12
    static let maxCharacters = 84
    private var previous: [String] = []
    private var start = 0
    private var shown = ""

    mutating func endUtterance() {
        start = previous.count
        shown = ""
    }

    mutating func ingest(_ text:String, isFinal:Bool) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return nil }
        var common = 0
        while common < min(words.count,previous.count), words[common] == previous[common] { common += 1 }
        // The decoder starts a new window or corrects text before our page boundary.
        // Keep a silence fence for an unchanged old prefix; a genuinely new read starts fresh.
        if common < min(start,previous.count) { start = 0; shown = "" }
        if start > words.count { start = 0 }
        previous = words
        guard start < words.count else { if isFinal { endUtterance() }; return nil }
        var end = start
        var chars = 0
        while end < words.count {
            let added = words[end].count + (end == start ? 0:1)
            if end > start && (end-start >= Self.maxWords || chars+added > Self.maxCharacters) { break }
            chars += added; end += 1
        }
        // Finish a full page atomically instead of dropping one leading word at a time.
        // The next decoder update begins the following page; no paced scrolling queue.
        let block = String(words[start..<end].joined(separator:" ").prefix(Self.maxCharacters))
        let output = block == shown ? nil:block
        shown = block
        if end < words.count || end-start >= Self.maxWords || chars >= Self.maxCharacters {
            start = end; shown = ""
        }
        if isFinal { endUtterance() }
        return output
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/LiveCaptionController.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='d749b6d29a80423faa9e66d8b274b7103b4ce477c57ee3c54c7ed861c4c04da3', 'pinned source changed: rebase and review, never bless silently'
for token in ['LiveCaptionRenderMode', 'LiveCaptionController', 'resolvedRenderMode', 'Config', 'discoveredModels', 'rankedCandidates', 'installedModels', 'start', 'stop', 'teardown', 'writePCM', 'handleStdout']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='d749b6d29a80423faa9e66d8b274b7103b4ce477c57ee3c54c7ed861c4c04da3'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-10: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-10: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
