import Foundation
#if os(Linux)
import Glibc
#endif

// ============================================================================
// W-0110 gor r14 recovery-state regression harness - test runner
// Foundation-only, no XCTest. Every scenario prints [PASS]/[FAIL]; exit code
// is nonzero on any failure. Async ordering uses GatedExecutor ACKs only.
// ============================================================================

var failures = 0
var passes = 0
func check(_ condition: Bool, _ name: String, _ detail: String = "") {
    if condition {
        passes += 1
        print("[PASS] \(name)")
    } else {
        failures += 1
        print("[FAIL] \(name) \(detail)")
    }
}

// --- fixtures ---------------------------------------------------------------
let fm = FileManager.default
let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("w0110-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? fm.removeItem(at: root)
try! fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }

let legacyDir = root.appendingPathComponent("legacy", isDirectory: true)
let standaloneDir = root.appendingPathComponent("yt-dlp-standalone", isDirectory: true)
try! fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)
try! fm.createDirectory(at: standaloneDir, withIntermediateDirectories: true)
let legacyBin = legacyDir.appendingPathComponent("yt-dlp")
let standaloneBin = standaloneDir.appendingPathComponent("yt-dlp_macos")
try! Data("OLD-EXTRACTOR-BYTES".utf8).write(to: legacyBin)
try! Data("STANDALONE-BYTES".utf8).write(to: standaloneBin)

let ytURL = "https://www.youtube.com/watch?v=abc123"
let ytTitle = "Some Title"
let ytSubs = ["https://www.youtube.com/api/timedtext?v=abc123&lang=en"]

/// Fresh core pointed at a PRISTINE per-scenario legacy staged binary
/// (each scenario gets its own file so fake -U rewrites never leak across tests).
var fixtureCounter = 0
func makeCore(status: Int32, replacement: [UInt8]?, token: AnyObject, currentTime: Double? = nil) -> (RecoveryCore, FakeUpdateFactory, GatedExecutor, GatedExecutor) {
    fixtureCounter += 1
    let bin = legacyDir.appendingPathComponent("yt-dlp-\(fixtureCounter)")
    try! Data("OLD-EXTRACTOR-BYTES".utf8).write(to: bin)
    let core = RecoveryCore()
    let bg = GatedExecutor(label: "bg")
    let mq = GatedExecutor(label: "main")
    core.backgroundExecutor = bg
    core.mainExecutor = mq
    core.stagedYtDlpPathProvider = { bin.path }
    core.currentTimeProvider = { currentTime }
    core.mpvProcessToken = token
    let factory = FakeUpdateFactory { FakeUpdateProcess(status: status, replacementBytes: replacement) }
    core.updateProcessFactory = { factory.make() }
    core.lastPlayedURL = ytURL
    core.lastPlayedTitle = ytTitle
    core.lastPlayedStartPos = 12.0
    core.lastPlayedSubtitleURLs = ytSubs
    return (core, factory, bg, mq)
}

// --- T1: normal URLs / arbitrary 403 digits never classify as failure --------
let negativeLines = [
    "Opening URL https://rr2---sn-abc.googlevideo.com/videoplayback?slices=38455247-40324801",
    "[https @ 0x7f8dead] Opening 'https://example.com/v?id=403403'",
    "https://www.youtube.com/watch?v=403",
    "AV: 403.2  403 / 403",
    "[mpv] buffer contains 403 bytes",
    "nested script probe https://example.com/403403",
]
for line in negativeLines {
    check(!RecoveryCore.isYoutubeOpenFailureDiagnostic(line), "classifier negative: \(line.prefix(48))")
}

// --- T2: actual 403 / "Failed to open" diagnostics classify ------------------
let positiveLines = [
    "Failed to open https://www.youtube.com/watch?v=abc123.",
    "[cplayer] Failed to open https://youtu.be/abc123.",
    "[ffmpeg] HTTP error 403: Forbidden",
    "[https @ 0x7f00beef] HTTP error 403: Forbidden",
    "HTTP error 403",
    "[tls] Server returned 403 Forbidden",
    "Server returned 403",
    "ERROR: unable to download video data: HTTP Error 403: Forbidden",
    "[ytdl_hook] ERROR: HTTP Error 403: Forbidden",
]
for line in positiveLines {
    check(RecoveryCore.isYoutubeOpenFailureDiagnostic(line), "classifier positive: \(line.prefix(48))")
}

// --- T3: isYoutubeURL host matching ------------------------------------------
check(RecoveryCore.isYoutubeURL("https://www.youtube.com/watch?v=x"), "isYoutubeURL www.youtube.com")
check(RecoveryCore.isYoutubeURL("https://youtu.be/x"), "isYoutubeURL youtu.be")
check(!RecoveryCore.isYoutubeURL("https://notyoutube.com/x"), "isYoutubeURL rejects notyoutube.com")
check(!RecoveryCore.isYoutubeURL("https://example.com/watch"), "isYoutubeURL rejects example.com")

// --- T4: standalone extractor - exactly one fresh resolution, no -U ----------
do {
    let token = NSObject()
    let core = RecoveryCore()
    let factory = FakeUpdateFactory { FakeUpdateProcess(status: 0, replacementBytes: Array("NEW".utf8)) }
    core.updateProcessFactory = { factory.make() }
    core.stagedYtDlpPathProvider = { standaloneBin.path }
    core.currentTimeProvider = { 0 }
    core.mpvProcessToken = token
    core.lastPlayedURL = ytURL
    core.lastPlayedTitle = ytTitle
    core.lastPlayedStartPos = 33.0
    core.lastPlayedSubtitleURLs = ytSubs

    core.handleYoutubeOpenFailure()
    check(core.playMediaCalls.count == 1, "standalone: exactly one fresh resolution")
    if let call = core.playMediaCalls.first {
        check(call.url == ytURL && call.title == ytTitle && call.startPos == 33.0 && call.subtitleURLs == ytSubs,
              "standalone: no-U preserves URL/title/startPos/subtitles")
    }
    check(factory.created.isEmpty, "standalone: updater never launched (no -U)")
    check(core.youtubeRetryAttempted, "standalone: retry marked attempted")
}

// --- T5: repeated failure is bounded -----------------------------------------
do {
    let token = NSObject()
    let core = RecoveryCore()
    core.stagedYtDlpPathProvider = { standaloneBin.path }
    core.mpvProcessToken = token
    core.lastPlayedURL = ytURL
    core.handleYoutubeOpenFailure()
    core.handleYoutubeOpenFailure()
    core.handleYoutubeOpenFailure()
    check(core.playMediaCalls.count == 1, "repeated failure bounded at one reload")
}

// --- T6: non-YouTube URL never triggers recovery ------------------------------
do {
    let token = NSObject()
    let (core, factory, _, _) = makeCore(status: 0, replacement: Array("NEW".utf8), token: token)
    core.lastPlayedURL = "https://example.com/video.mp4"
    core.handleYoutubeOpenFailure()
    check(core.playMediaCalls.isEmpty && factory.created.isEmpty && !core.ytdlpUpdateInProgress,
          "non-YouTube URL: no recovery")
}

// --- T7: staged binary missing -> no reload, flags reset ---------------------
do {
    let token = NSObject()
    let core = RecoveryCore()
    core.stagedYtDlpPathProvider = { legacyDir.appendingPathComponent("absent").path }
    core.mpvProcessToken = token
    core.lastPlayedURL = ytURL
    core.handleYoutubeOpenFailure()
    check(core.playMediaCalls.isEmpty, "missing staged binary: no reload")
    check(!core.ytdlpUpdateInProgress, "missing staged binary: update flag reset")
    check(core.youtubeRetryAttempted, "missing staged binary: retry still consumed (bounded)")
}

// --- T8: legacy update, unchanged bytes, status 0 -> must NOT reload ---------
do {
    let token = NSObject()
    let (core, factory, bg, mq) = makeCore(status: 0, replacement: nil, token: token)
    core.handleYoutubeOpenFailure()
    bg.runAll()
    mq.runAll()
    check(factory.created.count == 1, "legacy: one update process")
    check(core.playMediaCalls.isEmpty, "unchanged bytes + status 0: no reload")
    check(!core.ytdlpUpdateInProgress, "unchanged bytes: update flag reset")
}

// --- T9: legacy update, changed bytes but nonzero status -> must NOT reload --
do {
    let token = NSObject()
    let (core, _, bg, mq) = makeCore(status: 1, replacement: Array("NEW".utf8), token: token)
    core.handleYoutubeOpenFailure()
    bg.runAll()
    mq.runAll()
    check(core.playMediaCalls.isEmpty, "changed bytes + status 1: no reload")
}

// --- T10: launch failure -> must NOT reload ----------------------------------
do {
    struct Boom: Error {}
    let token = NSObject()
    let core = RecoveryCore()
    let bg = GatedExecutor(label: "bg"); let mq = GatedExecutor(label: "main")
    core.backgroundExecutor = bg; core.mainExecutor = mq
    core.stagedYtDlpPathProvider = { legacyBin.path }
    core.mpvProcessToken = token
    core.lastPlayedURL = ytURL
    let factory = FakeUpdateFactory { FakeUpdateProcess(status: 0, launchError: Boom()) }
    core.updateProcessFactory = { factory.make() }
    core.handleYoutubeOpenFailure()
    bg.runAll(); mq.runAll()
    check(core.playMediaCalls.isEmpty, "update launch failure: no reload")
    check(!core.ytdlpUpdateInProgress, "update launch failure: flag reset")
}

// --- T11: changed bytes + status 0 + current generation -> reload ------------
do {
    let token = NSObject()
    let (core, _, bg, mq) = makeCore(status: 0, replacement: Array("NEW-EXTRACTOR".utf8), token: token, currentTime: 42.5)
    core.handleYoutubeOpenFailure()
    bg.runAll()
    mq.runAll()
    check(core.playMediaCalls.count == 1, "changed bytes + success + current generation: reload")
    if let call = core.playMediaCalls.first {
        check(call.url == ytURL && call.title == ytTitle && call.subtitleURLs == ytSubs,
              "reload preserves URL/title/subtitles")
        check(call.startPos == 42.5, "reload resumes at live controller position")
    }
}

// --- T12: resume falls back to failure position when no live time ------------
do {
    let token = NSObject()
    let (core, _, bg, mq) = makeCore(status: 0, replacement: Array("NEW".utf8), token: token, currentTime: nil)
    core.handleYoutubeOpenFailure()
    bg.runAll(); mq.runAll()
    check(core.playMediaCalls.first?.startPos == 12.0, "resume falls back to lastPlayedStartPos")
}

// --- T13: async ordering proven by gates/ACK, not sleeps ---------------------
do {
    let token = NSObject()
    let (core, _, bg, mq) = makeCore(status: 0, replacement: Array("NEW".utf8), token: token)
    core.handleYoutubeOpenFailure()
    check(core.playMediaCalls.isEmpty && core.ytdlpUpdateInProgress, "gate held: continuation has not run before ACK")
    bg.runAll()
    check(core.playMediaCalls.isEmpty, "after background ACK only: main continuation still gated")
    mq.runAll()
    check(core.playMediaCalls.count == 1, "after main ACK: reload delivered exactly once")
}

// --- T14: stale generation drops the pending reload --------------------------
do {
    let token = NSObject()
    let (core, _, bg, mq) = makeCore(status: 0, replacement: Array("NEW".utf8), token: token)
    core.handleYoutubeOpenFailure()
    bg.runAll()
    core.invalidateYoutubeRecovery() // new manual load intent before continuation lands
    mq.runAll()
    check(core.playMediaCalls.isEmpty, "stale generation: reload dropped")
}

// --- T15: stale process identity drops the pending reload --------------------
do {
    let token = NSObject()
    let (core, _, bg, mq) = makeCore(status: 0, replacement: Array("NEW".utf8), token: token)
    core.handleYoutubeOpenFailure()
    bg.runAll()
    core.mpvProcessToken = NSObject() // process swapped before continuation lands
    mq.runAll()
    check(core.playMediaCalls.isEmpty, "stale process: reload dropped")
}

// --- T16: -U checked at most once per session --------------------------------
do {
    let token = NSObject()
    let (core, factory, bg, mq) = makeCore(status: 0, replacement: nil, token: token)
    core.handleYoutubeOpenFailure()
    bg.runAll(); mq.runAll()
    // new manual intent clears the retry flag...
    core.invalidateYoutubeRecovery()
    core.lastPlayedURL = ytURL
    core.handleYoutubeOpenFailure()
    bg.runAll(); mq.runAll()
    check(factory.created.count == 1, "second failure same session: no second -U (once/session)")
    check(core.playMediaCalls.isEmpty, "second failure same session: no reload")
}

// --- T17: new manual intent allows its own retry (standalone path) -----------
do {
    let token = NSObject()
    let core = RecoveryCore()
    core.stagedYtDlpPathProvider = { standaloneBin.path }
    core.mpvProcessToken = token
    core.lastPlayedURL = ytURL
    core.handleYoutubeOpenFailure()
    check(core.playMediaCalls.count == 1, "first failure: one reload")
    core.invalidateYoutubeRecovery()
    core.lastPlayedURL = ytURL
    core.handleYoutubeOpenFailure()
    check(core.playMediaCalls.count == 2, "new manual intent allows its own retry")
}

// --- T18: invalidate resets recovery state ------------------------------------
do {
    let core = RecoveryCore()
    let g0 = core.youtubePlaybackGeneration
    core.lastPlayedURL = ytURL
    core.lastPlayedSubtitleURLs = ytSubs
    core.youtubeRetryAttempted = true
    core.invalidateYoutubeRecovery()
    check(core.youtubePlaybackGeneration == g0 &+ 1, "invalidate: generation bumped")
    check(core.lastPlayedURL == nil && core.lastPlayedSubtitleURLs.isEmpty && !core.youtubeRetryAttempted,
          "invalidate: URL/subtitles cleared, retry reset")
}

print("==== \(passes) passed, \(failures) failed ====")
exit(failures == 0 ? 0 : 1)
