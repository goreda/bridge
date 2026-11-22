import Foundation
import Dispatch
#if os(macOS)
import AppKit
import GorAVEmbeddedShell
import GorAVPlaybackCore
#endif

// SESSION VENUE (e1 gor-seam, 189k item 3 follow-up): the exact call
// sequence gor's host-view adapter will drive at the PlayerBackend seam
// (contract note, LANE-NOTES.md item 4: open / setPaused / seek /
// stop+fence), asserted against the publicly observable surface of
// GorAVEmbeddedSession: the typed EmbeddedEvent stream, snapshot(), and
// typed EmbeddedRefusal throws. No internals are poked; nothing silent
// counts as pass.
//
// Exit codes: 0 pass, 1 fail (BAD line), 2 NOT_RUN (missing fixture /
// no Metal), 77 UNRUN (typed-unlanded on this host, e.g. Linux).

let UNRUN: Int32 = 77
let NOT_RUN: Int32 = 2
func fail(_ msg: String) -> Never { print("SESSION-VENUE BAD: \(msg)"); Foundation.exit(1) }

#if os(macOS)
let fixturePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures/e1-h264-aac-10s.mp4"
guard FileManager.default.fileExists(atPath: fixturePath) else {
    print("SESSION-VENUE NOT_RUN: missing fixture \(fixturePath)")
    Foundation.exit(NOT_RUN)
}

// GorAVEmbeddedSession is @MainActor (verified at its declaration); the
// whole venue body runs on the main actor, and the main thread pumps
// RunLoop.main instead of blocking on a semaphore - a blocked main thread
// would starve the MainActor task (same structure as
// rollback-acceptance-tests). Every path inside the task exits explicitly.
Task { @MainActor in
    guard GorAVEmbeddedSession.probeAvailable() else {
        print("SESSION-VENUE NOT_RUN: no Metal device on this host (probeAvailable=false)")
        Foundation.exit(NOT_RUN)
    }

    final class EventLog {
        var events: [EmbeddedEvent] = []
        var sequence = 0
        var seekCommittedWall: Double?
        var endedWall: Double?
        func seen(_ needle: String) -> Bool { events.contains { "\($0)".hasPrefix(needle) } }
        /// Payload-carrying lookup: the committed seconds of the first
        /// .seekCommitted, or nil if none arrived. Prefix matching alone
        /// never proves the payload.
        func seekCommittedPayload() -> Double? {
            for ev in events { if case .seekCommitted(let secs) = ev { return secs } }
            return nil
        }
    }

    // LIVE-PROGRESS CONTRACT (diagnosed against PlaybackCore.swift:537-551,
    // run 42313544473 V1 BAD): the pace anchor is a FIXED reference per
    // presentation generation - the first frame's pts + its wall arrival -
    // and never advances within a generation; later frames pace by pts
    // deltas off it. So anchorMediaSeconds is NOT a progress signal: it is
    // nil before the first decision, ~0 for the initial generation, and the
    // seek target after a seek generation. The honest live signals at the
    // public surface are the typed events (firstFrame / ended) and, at pump
    // end, the terminal stats. Progress is therefore proven by arrival of
    // .ended across real content plus terminal shown >= 1 - stronger than
    // watching any counter tick.

    // Venue-only drawable hosting, never product geometry.
    func venueWindow(_ x: CGFloat) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: x, y: 100, width: 64, height: 64),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
        return w
    }
    let window = venueWindow(100)
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
    window.contentView = host
    let log = EventLog()
    let s = GorAVEmbeddedSession(hostView: host, runID: "session-venue")
    // The session fires onEvent on the main actor (class is @MainActor;
    // tools-5.9 language mode). Append directly: re-queueing into another
    // Task could delay a synchronous event past the check that needs it.
    // Auditable event trace: every typed event printed with monotonic
    // elapsed seconds (ProcessInfo.systemUptime), so hold/wait accounting
    // survives buffered CI logs. Any .failed event is unexpected in this
    // venue and is an immediate BAD naming the typed token - a typed
    // failure must never pass as a silent hang (run 42314208050: a
    // seek-time audio outcome != .nativeReady cancels the commit via
    // prohibitResumeAfterSeekFailure -> the pipeline halts and .ended
    // never arrives; the .failed event was the only witness).
    let venueStart = ProcessInfo.processInfo.systemUptime
    s.onEvent = { ev in
        log.events.append(ev)
        if case .seekCommitted = ev { log.seekCommittedWall = ProcessInfo.processInfo.systemUptime }
        if case .ended = ev { log.endedWall = ProcessInfo.processInfo.systemUptime }
        let dt = ProcessInfo.processInfo.systemUptime - venueStart
        log.sequence += 1
        print(String(format: "SESSION-VENUE event[seq=%d t=+%.2fs] \(ev)", log.sequence, dt))
        if case .failed(let token) = ev { fail("typed failure event during venue: \(token)") }
    }

    #if GORAV_D8_PROBES
    func dumpD8(_ variant: String) {
        let rows = D8Probes.shared.snapshot()
        var csv = "id,pts,t0,t_upload_end,t_encode_end,t_present_issued,t_commit_end,wait_seconds\n"
        var stages: [String: [Double]] = [:]
        var complete = 0
        for row in rows {
            func field(_ value: Double?) -> String { value.map { String($0) } ?? "" }
            csv += "\(row.id),\(row.pts),\(row.t0),\(field(row.uploadEnd)),\(field(row.encodeEnd)),\(field(row.presentIssued)),\(field(row.commitEnd)),\(row.wait)\n"
            guard let upload = row.uploadEnd, let encode = row.encodeEnd,
                  let present = row.presentIssued, let commit = row.commitEnd else { continue }
            guard upload >= row.t0, encode >= upload, present >= encode, commit >= present else {
                fail("D8 non-monotonic CPU boundaries")
            }
            complete += 1
            stages["upload", default: []].append((upload - row.t0) * 1000)
            stages["encode", default: []].append((encode - upload) * 1000)
            stages["submission_tail", default: []].append((commit - encode) * 1000)
            stages["present_issued_delta", default: []].append((present - encode) * 1000)
            stages["wait", default: []].append(row.wait * 1000)
            stages["total_submission", default: []].append((commit - row.t0) * 1000)
        }
        let base = ProcessInfo.processInfo.environment["GORAV_D8_CSV_DIR"] ?? NSTemporaryDirectory()
        let path = URL(fileURLWithPath: base).appendingPathComponent("d8-\(variant).csv")
        do { try csv.write(to: path, atomically: true, encoding: .utf8) }
        catch { fail("D8 CSV write failed: \(error)") }
        print("D8 variant=\(variant) rows=\(rows.count) complete=\(complete) incomplete=\(rows.count-complete) csv=\(path.path)")
        for name in stages.keys.sorted() {
            let values = stages[name]!.sorted()
            func percentile(_ p: Double) -> Double { values[max(0, Int(ceil(Double(values.count) * p)) - 1)] }
            print("D8 stage=\(name) count=\(values.count) mean_ms=\(values.reduce(0,+)/Double(values.count)) p50_ms=\(percentile(0.5)) p95_ms=\(percentile(0.95)) max_ms=\(values.last!)")
        }
        if variant == "V4" || variant == "V5" {
            guard let total = stages["total_submission"], !total.isEmpty else { fail("D8 no complete submission samples") }
            let sorted = total.sorted()
            let p95 = sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
            let over80 = total.filter { $0 > 80 }.count
            print("D8 gate p95_ms=\(p95) over80ms=\(over80) incomplete=\(rows.count-complete)")
            print("D8 read_only=true threshold_enforcement=false observed_p95_ms=\(p95) observed_over80ms=\(over80)")
        }
    }
    #endif

    func dump(_ session: GorAVEmbeddedSession, variant: String) async {
        let snapshot = await session.snapshot()
        print("SESSION-VENUE \(variant) terminalStats shown=\(String(describing: snapshot.shown)) dropped=\(String(describing: snapshot.dropped)) waits=\(String(describing: snapshot.waits)) lifecycle=\(snapshot.lifecycle)")
        for entry in snapshot.seekTrace { print("SESSION-VENUE \(variant) seekTrace \(entry)") }
        print("SESSION-VENUE \(variant) firstPCM=\(snapshot.audioLandingFirstSampleSeconds)")
        #if GORAV_D8_PROBES
        dumpD8(variant)
        #endif
    }

    // V1: open -> .opened + async .firstFrame + the generation anchor
    // published at the first frame's pts (~0 for this fixture).
    do { try await s.open(path: fixturePath) } catch { fail("open threw: \(error)") }
    if !log.seen("opened") { fail("open returned without .opened event") }
    let t0 = Date()
    while !log.seen("firstFrame") {
        if Date().timeIntervalSince(t0) > 10 { fail("no .firstFrame within 10s of open") }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    guard let a1 = await s.snapshot().anchorMediaSeconds else {
        fail("firstFrame seen but no pace anchor published")
    }
    if abs(a1) > 1.5 { fail("initial generation anchor \(a1)s not near content start") }
    print("SESSION-VENUE V1 open: .opened + .firstFrame, generation anchor=\(a1)s")

    await dump(s, variant: "V1")

    // V2: pause -> .paused, and playback truly holds: across a wait LONGER
    // than the remaining content, no .ended may arrive. (The anchor is
    // fixed per generation, so an anchor-equality check would prove
    // nothing; absence of EOS across the full remainder is the real
    // freeze witness - a fake pause hits EOS within ~8s of this point.)
    guard await s.snapshot().lifecycle == .playing else {
        fail("expected .playing after firstFrame, got \(await s.snapshot().lifecycle)")
    }
    do { try await s.setPaused(true) } catch { fail("setPaused(true) threw: \(error)") }
    if !log.seen("paused") { fail("setPaused(true) returned without .paused event") }
    try? await Task.sleep(nanoseconds: 12_000_000_000)
    if log.seen("ended") { fail(".ended arrived while paused (pause did not hold playback)") }
    print("SESSION-VENUE V2 pause: .paused, no EOS across a 12s hold exceeding remaining content")

    await dump(s, variant: "V2")

    // V3: resume -> .resumed.
    do { try await s.setPaused(false) } catch { fail("setPaused(false) threw: \(error)") }
    if !log.seen("resumed") { fail("setPaused(false) returned without .resumed event") }
    print("SESSION-VENUE V3 resume: .resumed")

    await dump(s, variant: "V3")

    func assertD1(_ snapshot: EmbeddedSnapshot, _ events: EventLog, _ variant: String) {
        let tokens = ["seekBegin", "seekVideoCommitted", "frame0Presented", "audioRingReset", "audioSeekDone", "audioProducerRearmed", "seekCommitted"]
        var previous = -1
        for token in tokens {
            guard let index = snapshot.seekTrace.firstIndex(where: { $0.contains(" " + token) }), index > previous else { fail("\(variant) D1 order missing/out-of-order \(token)") }
            previous = index
        }
        guard let sample = snapshot.audioFirstAdmissionWallSeconds.last,
              let committed = events.seekCommittedWall, let ended = events.endedWall,
              committed < sample, sample < ended else { fail("\(variant) D1 actual audio admission order") }
    }

    // V4 deadline includes the seek call itself, not only its return.
    #if GORAV_D8_PROBES
    D8Probes.shared.clear()
    #endif
    let beforeSeekEvents = log.events.count
    let t4 = ContinuousClock.now
    do { try await s.seek(toSeconds: 8.0) } catch { fail("seek(8.0) threw: \(error)") }
    guard let committed = log.seekCommittedPayload(), abs(committed - 8.0) < 1e-6 else {
        fail("V4 missing exact .seekCommitted(8.0)")
    }
    guard log.events.dropFirst(beforeSeekEvents).contains(.firstFrame) else {
        fail("V4 no post-seek accepted frame0 event")
    }
    while !log.seen("ended") {
        if t4.duration(to: .now) > .seconds(4) { await dump(s, variant: "V4"); fail("V4 no EOF within 4s of seek") }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    guard log.events.contains(.ended(reason: "eof")) else { fail("V4 terminal was not eof") }
    await dump(s, variant: "V4")
    let v4Snapshot = await s.snapshot()
    guard let landing = v4Snapshot.audioLandingFirstSampleSeconds.last else { fail("V4 missing audio landing") }
    if !(7.9...8.1).contains(landing) {
        fail("V4 PCM landing \(landing)s outside [7.9,8.1]")
    }
    assertD1(v4Snapshot, log, "V4")
    #if GORAV_D8_PROBES
    D8Probes.shared.clear()
    #endif
    print("SESSION-VENUE V4 PASS: committed, accepted frame0, eof within 4s")

    // V5 uses a fresh single-use session because V4 intentionally reaches EOF.
    let pausedLog = EventLog()
    let pausedWindow = venueWindow(200)
    let pausedHost = NSView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
    pausedWindow.contentView = pausedHost
    let p = GorAVEmbeddedSession(hostView: pausedHost, runID: "session-venue-paused-seek")
    p.onEvent = { event in
        pausedLog.events.append(event)
        if case .seekCommitted = event { pausedLog.seekCommittedWall = ProcessInfo.processInfo.systemUptime }
        if case .ended = event { pausedLog.endedWall = ProcessInfo.processInfo.systemUptime }
        pausedLog.sequence += 1
        print("SESSION-VENUE V5 event[seq=\(pausedLog.sequence)] \(event)")
        if case .failed(let token) = event { fail("V5 typed failure: \(token)") }
    }
    do { try await p.open(path: fixturePath) } catch { fail("V5 open threw: \(error)") }
    let openDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !pausedLog.seen("firstFrame") {
        if ContinuousClock.now > openDeadline { fail("V5 open frame0 timeout") }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    do { try await p.setPaused(true) } catch { fail("V5 pause threw: \(error)") }
    let v5SamplesBeforeSeek = await p.snapshot().audioLandingFirstSampleSeconds.count
    let v5Begin = pausedLog.events.count
    do { try await p.seek(toSeconds: 8) } catch { fail("V5 seek threw: \(error)") }
    guard pausedLog.events.dropFirst(v5Begin).contains(.firstFrame),
          pausedLog.seekCommittedPayload() == 8 else { fail("V5 missing committed seek/frame0") }
    let beforeHoldSamples = await p.snapshot().audioLandingFirstSampleSeconds.count
    guard await p.snapshot().lifecycle == .paused else { fail("V5 seek lost paused state") }
    try? await Task.sleep(nanoseconds: 12_000_000_000)
    guard !pausedLog.seen("ended") else { fail("V5 ended during paused hold") }
    guard await p.snapshot().audioLandingFirstSampleSeconds.count == beforeHoldSamples, beforeHoldSamples == v5SamplesBeforeSeek else { fail("V5 post-seek audio admitted while paused") }
    await dump(p, variant: "V5-paused")
    let resumeTime = ContinuousClock.now
    do { try await p.setPaused(false) } catch { fail("V5 resume threw: \(error)") }
    while !pausedLog.seen("ended") {
        if resumeTime.duration(to: .now) > .seconds(4) { await dump(p, variant: "V5"); fail("V5 no EOF within 4s of resume") }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    guard pausedLog.events.contains(.ended(reason: "eof")) else { fail("V5 terminal was not eof") }
    await dump(p, variant: "V5")
    let v5Snapshot = await p.snapshot()
    assertD1(v5Snapshot, pausedLog, "V5")
    guard let v5Landing = v5Snapshot.audioLandingFirstSampleSeconds.last, (7.9...8.1).contains(v5Landing) else { fail("V5 PCM landing outside [7.9,8.1]") }
    await p.stop()
    pausedWindow.close()
    print("SESSION-VENUE V5 PASS: paused seek frame0, 12s hold, resume to EOF")

    // EOS publishes the terminal stats - the frame-count assertion
    // lives where the contract publishes it. Then stop + single-use:
    // every later call refuses typed.
    let t5 = Date()
    var terminalShown: Int?
    while Date().timeIntervalSince(t5) < 5 {
        if let sh = await s.snapshot().shown { terminalShown = sh; break }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    guard let terminalShown, terminalShown >= 1 else {
        fail("terminal snapshot.shown not published after EOS (or zero frames shown)")
    }
    print("SESSION-VENUE terminal stats: shown=\(terminalShown) at EOS")
    await s.stop()
    do { try await s.open(path: fixturePath); fail("re-open after stop did not throw") }
    catch let e as EmbeddedRefusal { print("SESSION-VENUE single-use: re-open refused typed (\(e))") }
    catch { fail("re-open after stop threw non-typed error: \(error)") }
    do { try await s.setPaused(true); fail("setPaused after stop did not throw") }
    catch let e as EmbeddedRefusal { print("SESSION-VENUE single-use: setPaused after stop refused typed (\(e))") }
    catch { fail("setPaused after stop threw non-typed error: \(error)") }

    window.close()
    print("SESSION-VENUE PASS: open firstFrame pause-holds-EOS resume seek-to-EOS terminal-shown single-use-teardown (seam call sequence)")
    Foundation.exit(0)
}
while true { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1)) }
#else
print("SESSION-VENUE UNRUN leg=SESSION seam=GorAVEmbeddedSession (macOS-only venue)")
Foundation.exit(UNRUN)
#endif
