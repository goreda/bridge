// ================================================================
//  QuitChildKiller.swift - quit-time owned-child cleanup (176a/176c)
//  Target: macOS (Foundation). Dual-compiles on Linux for host tests.
//
//  Contract (176a, amended by 176c):
//  - ONE shared function for applicationWillTerminate, the approved
//    chain and the quit watchdog. Own registered PIDs only.
//    No pkill/pgrep/orphan sweeps, no exit(), no quit-machinery state
//    writes, no restart logic in here. Exit ownership is unchanged:
//    only the watchdog _exit()s; AppKit exits after willTerminate
//    returns.
//  - PID REGISTRY (176c): lock-protected set of owned child pids,
//    registered on the main thread AFTER run() succeeds. A handle
//    assigned before run() (peerflix) simply has no pid yet - a child
//    that was never started cannot be orphaned, so nothing is skipped
//    and nothing needs a pid<=0 special case at kill time.
//  - PROVEN-GONE removal: an entry is dropped only when the child is
//    proven reaped-and-gone (kill(pid,0) == ESRCH), discovered either
//    by the chained terminationHandler (registry removal on
//    termination) or by the capture-time probe. Clearing the owning
//    property (nil/detach) removes a handle only when already gone;
//    a nil-ed but LIVE child stays registered so it cannot escape the
//    quit-time kill set. An unreaped zombie stays registered by
//    design: its pid cannot be reused while unreaped, and a SIGKILL
//    on it is a harmless no-op. IDENTITY-RACE HONESTY: the residual
//    TOCTOU between the kill(pid,0) probe and the SIGKILL is named,
//    not eliminated; the registry design shrinks it to pids that were
//    ours and unreaped at probe time.
//  - ONE-SHOT + COMPLETED (176c): the graceful sequence (SIGTERM to
//    all owned pids, ONE shared 300ms poll budget via kill(pid,0)
//    liveness, then SIGKILL for survivors) runs at most once; the
//    completion flag is set only when the sequence FINISHES. A caller
//    arriving mid-sequence WAITS - bounded by the same absolute
//    deadline plus a 100ms margin - and returns the observed outcome
//    (completed / timeout). It never restarts or extends the grace.
//  - EMERGENCY ESCALATION IS EXEMPT FROM RUN-ONCE (documented
//    deviation from the literal "runs once" wording): a watchdog
//    caller ALWAYS finishes with an idempotent SIGKILL-only floor
//    pass inside this same function, so no watchdog exit can land
//    after an incomplete sequence without the watchdog's own kill
//    attempt. Escalation may repeat (signals are idempotent); the
//    300ms grace never does.
//  - All signaling uses kill(2) directly (SIGTERM / SIGKILL / the
//    signal-0 liveness probe), not Process.terminate()/isRunning:
//    no Foundation termination semantics in the body, no main-thread
//    dependency, matches the watchdog's pre-existing kill(2) idiom.
//    Every attempt logs pid, signal name, rc and errno.
// ================================================================

import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

final class QuitChildKiller {
    static let shared = QuitChildKiller()

    init() {}

    enum Reason: String {
        case willTerminate
        case approvedChain
        case watchdog
    }

    enum Outcome {
        case ranToCompletion(tracked: Int, sigkillSent: Int)
        case alreadyDone
        case joinedCompleted
        case joinedTimeoutFloorApplied   // watchdog only: floor pass ran after a timed-out join
        case joinedTimeout               // non-watchdog joiner observed an incomplete sequence

        var summary: String {
            switch self {
            case .ranToCompletion(let t, let k): return "completed tracked=\(t) sigkill-sent=\(k)"
            case .alreadyDone: return "already-done"
            case .joinedCompleted: return "joined-completed"
            case .joinedTimeoutFloorApplied: return "joined-timeout-floor-applied"
            case .joinedTimeout: return "joined-timeout"
            }
        }
    }

    private enum Phase { case idle, running, done }

    // Fixed budgets. The grace deadline is anchored once at sequence start
    // and is never restarted or extended by any caller.
    private let graceSeconds: TimeInterval = 0.300
    private let joinMarginSeconds: TimeInterval = 0.100
    private let pollStepSeconds: TimeInterval = 0.010

    /// AppDelegate wires this to quitDebug at arm time. Off-main safe by
    /// contract of the sink (quitDebug opens/writes/closes the file per call,
    /// already called from quitWatchdogQueue today).
    var log: (String) -> Void = { _ in }

    // One NSCondition is the only synchronization primitive: it guards the
    // registry, the phase machine and the completion signal. The sequence
    // body below runs holding NO lock, so no caller can be blocked inside a
    // critical section and no thread ever waits on the main run loop.
    private let cond = NSCondition()
    private var phase: Phase = .idle
    private var deadline: TimeInterval = 0
    private var entries: [pid_t: Process] = [:]  // owned children by pid; strong ref keeps the Process alive for its handler
    private var armPIDs: Set<pid_t> = []          // arm-time history snapshot

    // MARK: - Registry (main thread)

    /// Register after run() succeeds. Chains the existing terminationHandler
    /// so a termination (Foundation-reaped) removes the entry - proven
    /// stopped - while the site's own handler keeps its behavior.
    func register(_ p: Process) {
        let pid = p.processIdentifier
        guard pid > 0 else {
            log("killOwnedChildren register skipped never-launched")
            return
        }
        cond.lock()
        guard p.isRunning else {
            cond.unlock()
            return
        }
        if kill(pid, 0) != 0, errno == ESRCH {
            cond.unlock()
            log("killOwnedChildren register skipped already-gone pid=\(pid)")
            return
        }
        entries[pid] = p
        let prior = p.terminationHandler
        p.terminationHandler = { [weak self, weak p] finished in
            // Foundation completion retires this exact registration even if
            // the numeric PID has already been reused. Never signal here.
            if let p = p { self?.retireCompleted(p, pid: pid) }
            prior?(finished)
        }
        cond.unlock()
    }

    /// Call where the owning property is cleared (nil/detach). Removes the
    /// entry ONLY when the child is proven gone; a cleared but live child
    /// stays registered so it cannot escape the quit-time kill set.
    func unregisterIfStopped(_ p: Process) {
        let pid = p.processIdentifier
        guard pid > 0 else { return }
        cond.lock(); defer { cond.unlock() }
        guard entries[pid] === p else { return }
        if kill(pid, 0) != 0, errno == ESRCH {
            entries.removeValue(forKey: pid)
            armPIDs.remove(pid)
        }
    }

    /// Arm-time history snapshot, from armQuitWatchdog on the main thread.
    /// The watchdog never reads AppDelegate handle properties off-main; it
    /// reads only this lock-protected state.
    func snapshotArmSet() {
        cond.lock(); armPIDs = Set(entries.keys); cond.unlock()
    }

    private func retireCompleted(_ p: Process, pid: pid_t) {
        cond.lock(); defer { cond.unlock() }
        guard entries[pid] === p else { return } // stale callback: newer entry wins
        entries.removeValue(forKey: pid)
        armPIDs.remove(pid)
    }

    private func removeIfGone(_ pid: pid_t) {
        guard pid > 0 else { return }
        cond.lock(); defer { cond.unlock() }
        if kill(pid, 0) != 0, errno == ESRCH {
            entries.removeValue(forKey: pid)
            armPIDs.remove(pid)
        }
    }

    // MARK: - Shared kill function

    @discardableResult
    func killOwnedChildren(reason: Reason) -> Outcome {
        cond.lock()
        switch phase {
        case .done:
            cond.unlock()
            log("killOwnedChildren already-done reason=\(reason.rawValue)")
            return finishForWatchdog(reason, base: .alreadyDone)
        case .running:
            // Join the in-flight sequence. Bounded by the SHARED deadline
            // plus margin; NSCondition.wait releases cond while waiting, so
            // the runner is never blocked by joiners. On timeout the caller
            // returns with the sequence incomplete: a watchdog caller then
            // applies its floor pass before its exit (finishForWatchdog).
            let remaining = max(0, deadline - uptime()) + joinMarginSeconds
            let waitUntil = Date(timeIntervalSinceNow: remaining)
            while phase == .running && Date() < waitUntil {
                _ = cond.wait(until: waitUntil)
            }
            let completed = (phase == .done)
            cond.unlock()
            log("killOwnedChildren join reason=\(reason.rawValue) outcome=\(completed ? "completed" : "timeout")")
            if completed { return finishForWatchdog(reason, base: .joinedCompleted) }
            return finishForWatchdog(reason, base: reason == .watchdog ? .joinedTimeoutFloorApplied : .joinedTimeout)
        case .idle:
            phase = .running
            deadline = uptime() + graceSeconds
            let set = captureLocked()
            cond.unlock()
            let sigkillSent = runSequence(set: set, reason: reason)
            cond.lock()
            phase = .done
            cond.broadcast()
            cond.unlock()
            log("killOwnedChildren completed reason=\(reason.rawValue) tracked=\(set.count) sigkill-sent=\(sigkillSent)")
            return finishForWatchdog(reason, base: .ranToCompletion(tracked: set.count, sigkillSent: sigkillSent))
        }
    }

    // MARK: - Internals

    private func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Called with cond held. Prunes proven-gone entries (ESRCH only; any
    /// other probe error keeps the entry and the kill attempt is logged)
    /// and returns the immutable kill set: registry UNION arm history.
    private func captureLocked() -> [pid_t] {
        for pid in entries.keys where kill(pid, 0) != 0 && errno == ESRCH { entries.removeValue(forKey: pid) }
        armPIDs = armPIDs.filter { !(kill($0, 0) != 0 && errno == ESRCH) }
        return Array(Set(entries.keys).union(armPIDs)).sorted()
    }

    /// The graceful sequence; runs at most once (guarded by phase). Holds
    /// no lock and needs nothing from the main thread: kill(2) only,
    /// signal-0 liveness polling; logging via the per-call append sink above.
    private func runSequence(set: [pid_t], reason: Reason) -> Int {
        for pid in set {
            let rc = kill(pid, SIGTERM)
            log("killOwnedChildren term pid=\(pid) rc=\(rc) errno=\(rc == 0 ? 0 : errno) reason=\(reason.rawValue)")
        }
        var pending = Set(set)
        while !pending.isEmpty && uptime() < deadline {
            Thread.sleep(forTimeInterval: pollStepSeconds)
            pending = pending.filter { kill($0, 0) == 0 || errno == EPERM }
        }
        var sigkillSent = 0
        for pid in pending.sorted() {
            let rc = kill(pid, SIGKILL)
            log("killOwnedChildren kill pid=\(pid) rc=\(rc) errno=\(rc == 0 ? 0 : errno) reason=\(reason.rawValue)")
            if rc == 0 { sigkillSent += 1 }
        }
        return sigkillSent
    }

    /// Watchdog exit-safety floor, INSIDE the shared function: idempotent
    /// SIGKILL-only pass, at-least-once. Preserves the pre-176a guarantee
    /// that the watchdog never exits without its own kill attempt, even
    /// when it joined a sequence that never completed.
    private func emergencyFloor(reason: Reason) {
        cond.lock()
        let set = captureLocked()
        cond.unlock()
        for pid in set {
            let rc = kill(pid, SIGKILL)
            log("killOwnedChildren floor pid=\(pid) rc=\(rc) errno=\(rc == 0 ? 0 : errno) reason=\(reason.rawValue)")
        }
    }

    private func finishForWatchdog(_ reason: Reason, base: Outcome) -> Outcome {
        guard reason == .watchdog else { return base }
        emergencyFloor(reason: reason)
        return base
    }
}

// mpv's native input-ipc-client EOF lifetime. No watcher or extra process.
final class MPVLifeline {
    private static let lock = NSLock()
    private struct Entry {
        let process: Process
        let parentEnd: FileHandle
        let drain: DispatchSourceRead
    }

    // mpv treats --input-ipc-client as a full IPC client and writes its event stream to it. With no
    // reader the socket buffer fills and mpv's ipc/ipc thread spins in ipc_write_str -> sendto
    // (owner sample 02:56: 1502 of 1527 samples, mpv 100% CPU with no video loaded). The parent end
    // is read and discarded; EOF-on-close stays mpv's lifeline. Close only after the source is cancelled.
    private static func makeDrain(_ fd: Int32) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "gor.mpv-lifeline-drain", qos: .background))
        source.setEventHandler {
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buf, buf.count)
            if n == 0 || (n < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) { source.cancel() }
        }
        return source
    }

    private static func release(_ entry: Entry) {
        let parent = entry.parentEnd
        entry.drain.setCancelHandler { try? parent.close() }
        entry.drain.cancel()
    }
    private static var entries: [ObjectIdentifier: Entry] = [:]
    private static var signalTerminationRequested = false

    static func closeForTerminationSignal() {
        lock.lock()
        signalTerminationRequested = true
        let held = Array(entries.values)
        entries.removeAll()
        lock.unlock()
        for entry in held { release(entry) }
    }

    // Only for mpv launch sites whose stdin was unused. Existing IPC server
    // argument/socket, Process PID, stdout/stderr, renderer and audio unchanged.
    static func run(_ process: Process) throws {
        var fds: [Int32] = [-1, -1]
        #if os(Linux)
        let socketType = Int32(SOCK_STREAM.rawValue)
        #else
        let socketType = SOCK_STREAM
        #endif
        guard socketpair(AF_UNIX, socketType, 0, &fds) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        for fd in fds {
            guard fcntl(fd, F_SETFD, FD_CLOEXEC) != -1 else {
                let saved = errno
                #if os(Linux)
                _ = Glibc.close(fds[0]); _ = Glibc.close(fds[1])
                #else
                _ = Darwin.close(fds[0]); _ = Darwin.close(fds[1])
                #endif
                throw POSIXError(POSIXErrorCode(rawValue: saved) ?? .EIO)
            }
        }
        let parent = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true)
        let child = FileHandle(fileDescriptor: fds[1], closeOnDealloc: true)
        let key = ObjectIdentifier(process)
        let prior = process.terminationHandler
        process.standardInput = child // Process maps this endpoint to child fd0.
        var args = process.arguments ?? []
        let boundary = args.firstIndex(of: "--") ?? args.count
        args.insert(contentsOf: ["--input-ipc-client=fd://0", "--no-input-terminal"], at: boundary)
        process.arguments = args
        // Publish before run so a very short child cannot finish before insert.
        lock.lock()
        guard !signalTerminationRequested else {
            lock.unlock()
            try? child.close(); try? parent.close()
            throw POSIXError(.ECANCELED)
        }
        let drain = makeDrain(fds[0])
        entries[key] = Entry(process: process, parentEnd: parent, drain: drain)
        lock.unlock()
        drain.resume()
        process.terminationHandler = { finished in
            close(for: finished)
            prior?(finished)
        }
        do {
            try process.run()
            try? child.close() // gor must retain ONLY the parent endpoint.
            QuitChildKiller.shared.register(process)
        } catch {
            try? child.close()
            close(for: process)
            throw error
        }
    }

    // Intentional stop: EOF is mpv's own quit request. No unrelated PID signal.
    static func close(for process: Process) {
        lock.lock()
        let entry = entries.removeValue(forKey: ObjectIdentifier(process))
        lock.unlock()
        if let entry { release(entry) }
    }
}

#if !os(Linux)
/// Owner block 176e: at launch, before the first mpv spawn, end leftover
/// vendor mpv/node processes from an earlier gor run. A process is a target
/// only if ALL three hold: its executable path resolved through symlinks is
/// one of this gor's vendor executables (proc_pidpath, never the process
/// name), its parent is gone (ppid == 1), and it belongs to the current
/// user. Each target gets SIGTERM, then SIGKILL after 300 ms only if the
/// SAME identity is still alive (path + start time + ppid + uid re-checked,
/// so a reused pid is never signaled). One log line per target pid.
enum OrphanSweep {

    private struct Target {
        let pid: pid_t
        let canonicalPath: String
        let startSec: UInt64
        let startUsec: UInt64
    }

    private struct Info {
        let canonicalPath: String
        let ppid: pid_t
        let uid: uid_t
        let startSec: UInt64
        let startUsec: UInt64
    }

    /// Runs synchronously on the caller's thread. The 300 ms wait happens
    /// only when at least one orphan was found; with none the cost is one
    /// proc_listpids pass. Call once at launch before the first mpv spawn.
    ///
    /// vendorExecutables: pass GORResources.vendorPath("mpv/bin/mpv") and
    /// GORResources.vendorPath("node/node"). A path that does not resolve on
    /// disk is silently excluded (vendor node absent -> mpv-only sweep).
    static func sweep(vendorExecutables: [String], nodeExecutable: String, nodeScripts: [String], log: (String) -> Void) {
        let owned = Set(vendorExecutables.compactMap(canonicalize))
        guard !owned.isEmpty else { return }
        let scripts = Set(nodeScripts.compactMap(canonicalize))
        let node = canonicalize(nodeExecutable)
        let targets = findTargets(owned: owned, node: node, scripts: scripts)
        var signaled: [Target] = []
        for t in targets {
            guard matches(t, node: node, scripts: scripts) else {
                log("orphan-sweep pid=\(t.pid) action=skip-identity-changed")
                continue
            }
            if kill(t.pid, SIGTERM) == 0 { signaled.append(t) }
            else { log("orphan-sweep pid=\(t.pid) action=term-failed errno=\(errno)") }
        }
        guard !signaled.isEmpty else { return }
        usleep(300_000) // 176e: SIGKILL after 300 ms if still alive
        for t in signaled {
            var action = "term"
            // Full identity re-check before SIGKILL: the pid may have exited
            // and been reused inside the 300 ms window.
            if matches(t, node: node, scripts: scripts), kill(t.pid, SIGKILL) == 0 {
                action = "term+kill"
            }
            log("orphan-sweep pid=\(t.pid) path=\(t.canonicalPath) action=\(action)")
        }
    }

    private static func findTargets(owned: Set<String>, node: String?, scripts: Set<String>) -> [Target] {
        let uid = getuid()
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 64)
        let capacityBytes = Int32(pids.count * MemoryLayout<pid_t>.size)
        let n = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, capacityBytes)
        guard n > 0 else { return [] }
        let count = min(Int(n) / MemoryLayout<pid_t>.size, pids.count)
        var out: [Target] = []
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 1, let info = describe(pid: pid) else { continue }
            guard info.ppid == 1, info.uid == uid, owned.contains(info.canonicalPath) else { continue }
            if info.canonicalPath == node && !isOwnedNodeScript(pid: pid, scripts: scripts) { continue }
            out.append(Target(pid: pid, canonicalPath: info.canonicalPath,
                              startSec: info.startSec, startUsec: info.startUsec))
        }
        return out
    }

    private static func matches(_ t: Target, node: String?, scripts: Set<String>) -> Bool {
        guard let cur = describe(pid: t.pid), cur.canonicalPath == t.canonicalPath,
              cur.startSec == t.startSec, cur.startUsec == t.startUsec,
              cur.ppid == 1, cur.uid == getuid() else { return false }
        return cur.canonicalPath != node || isOwnedNodeScript(pid: t.pid, scripts: scripts)
    }

    // KERN_PROCARGS2 gives NUL-delimited argv, not a name/substr match.
    // Node's first non-option argv is its script. Require the exact own path.
    private static func isOwnedNodeScript(pid: pid_t, scripts: Set<String>) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size, size <= 1_048_576 else { return false }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &bytes, &size, nil, 0) == 0 else { return false }
        var argc: Int32 = 0
        _ = withUnsafeMutableBytes(of: &argc) { bytes.prefix(MemoryLayout<Int32>.size).copyBytes(to: $0) }
        guard argc > 1, argc < 65_536 else { return false }
        var i = MemoryLayout<Int32>.size
        while i < size && bytes[i] != 0 { i += 1 } // executable path
        while i < size && bytes[i] == 0 { i += 1 }
        var argv: [String] = []
        for _ in 0..<Int(argc) {
            guard i < size else { return false }
            let start = i
            while i < size && bytes[i] != 0 { i += 1 }
            guard i < size else { return false }
            argv.append(String(decoding: bytes[start..<i], as: UTF8.self)); i += 1
        }
        guard let script = argv.dropFirst().first(where: { !$0.hasPrefix("-") }),
              let canonical = canonicalize(script) else { return false }
        return scripts.contains(canonical)
    }

    private static func describe(pid: pid_t) -> Info? {
        guard pid > 1 else { return nil }
        var bsd = proc_bsdinfo()
        let got = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd,
                               Int32(MemoryLayout<proc_bsdinfo>.size))
        guard got == Int32(MemoryLayout<proc_bsdinfo>.size) else { return nil }
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathCapacity = UInt32(buf.count)
        guard proc_pidpath(pid, &buf, pathCapacity) > 0 else { return nil }
        guard let canon = canonicalize(String(cString: buf)) else { return nil }
        return Info(canonicalPath: canon,
                    ppid: pid_t(bsd.pbi_ppid),
                    uid: bsd.pbi_uid,
                    startSec: bsd.pbi_start_tvsec,
                    startUsec: bsd.pbi_start_tvusec)
    }

    private static func canonicalize(_ path: String) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard realpath(path, &buf) != nil else { return nil }
        return String(cString: buf)
    }
}

#endif


// BEGIN station-move PreviewGuard.swift
// ================================================================
//  PreviewGuard.swift - file-browser hover preview mpv lifecycle
//  Target: macOS (Foundation). Dual-compiles on Linux for host tests.
//
//  Contract (owner order 2026-11-17: hover preview mpv processes piled
//  up as Dock icons, never closed, kept eating CPU):
//  - ONE argument list for the hover-preview mpv, and it carries
//    --macos-app-activation-policy=prohibited. The main playback spawn
//    already passes exactly this (AppDelegate.swift); the preview spawn
//    did not, and every preview mpv runs cocoa_main -> NSApplication,
//    so every preview took a Dock icon by construction.
//  - HARD CAP: at most maxLive preview processes owned by this gor at
//    any moment. Launch admission waits for older children to exit; registration also terminates every other live
//    one. The cursor hovers one row at a time, so the cap costs no
//    feature: it only reaps the previews a missed exit event would
//    have leaked.
//  - TERMINATE, NOT HOPE: teardown runs the caller's graceful quit
//    (mpv IPC "quit" over the preview socket), then closes the
//    MPVLifeline EOF lifeline (mpv's native quit_on_close for
//    --input-ipc-client), then escalates SIGTERM -> SIGKILL behind
//    kill(2) liveness probes, all off the main thread. IDENTITY-RACE
//    HONESTY: as in QuitChildKiller, the residual TOCTOU between the
//    kill(pid,0) probe and the signal is named, not eliminated; only
//    pids this gor spawned and registered are ever signaled.
//  - DIAGNOSTIC: every spawn and every observed exit logs one line
//    with pid and running counts to the injected sink (wired to the
//    existing bounded gor_diag.log by the caller), so the next owner
//    log bundle proves live previews return to zero.
//  - Safety nets unchanged: MPVLifeline.run registers every preview
//    into QuitChildKiller (killed at quit, 176a/176c) and OrphanSweep
//    reaps ppid==1 vendor mpv at launch (176e). This file adds the
//    missing during-session teardown and the Dock policy.
// ================================================================

import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum PreviewGuard {

    /// Singleton hover: one live preview at a time.
    static let maxLive = 1

    /// The Dock-icon fix: a preview helper never activates in the Dock.
    static let activationPolicyArg = "--macos-app-activation-policy=prohibited"

    /// Injected by the caller (FileBrowser wires the existing bounded
    /// gor_diag.log appender). Off-main safe by the sink's contract,
    /// same shape as QuitChildKiller.log.
    static var log: (String) -> Void = { _ in }

    /// The one hover-preview mpv argument list. Byte-identical to the
    /// previous inline list plus activationPolicyArg; MPVLifeline.run
    /// still appends --input-ipc-client=fd://0 --no-input-terminal.
    static func arguments(geometry: String, socketPath: String, path: String) -> [String] {
        return [
            "--no-config", "--no-osc", "--no-input-default-bindings",
            "--geometry=\(geometry)",
            "--no-border", "--ontop", "--no-native-fs",
            "--volume=0", "--mute=yes", "--sub-visibility=no",
            "--cursor-autohide=no", "--keep-open=no", "--idle=no",
            activationPolicyArg,
            "--input-ipc-server=\(socketPath)", "--", path
        ]
    }

    // MARK: - Live registry (hard cap)

    private static let lock = NSLock()
    private static var live: [ObjectIdentifier: Process] = [:]
    private static var spawnedCount = 0
    private static var exitedCount = 0
    private static let guardQueue = DispatchQueue(label: "gor.preview.guard", qos: .utility, attributes: .concurrent)
    private static let launchQueue = DispatchQueue(label: "gor.preview.launch", qos: .utility)
    private static var terminating = Set<ObjectIdentifier>()

    // Launch admission is serialized off main. Never spawn while an older preview
    // is still alive: a stuck teardown drops this request rather than overlapping.
    static func launch(_ process: Process, work: PreviewWork, completion: @escaping (Bool) -> Void) {
        launchQueue.async {
            guard !work.isCancelled else { completion(false); return }
            lock.lock(); let older = Array(live.values); lock.unlock()
            for old in older { terminate(old) }
            for old in older {
                guard waitGone(old.processIdentifier, seconds: 0.8) else { completion(false); return }
            }
            guard work.attach(process), !work.isCancelled else { completion(false); return }
            do { try MPVLifeline.run(process) } catch { completion(false); return }
            register(process)
            if work.isCancelled { terminate(process); completion(false); return }
            completion(true)
        }
    }

    /// Grace before SIGTERM, then before SIGKILL. Same 300 ms budget the
    /// quit sequence uses; never restarted, never extended.
    private static let graceSeconds: TimeInterval = 0.300

    static var liveCount: Int {
        lock.lock(); defer { lock.unlock() }
        return live.count
    }

    /// Call right after MPVLifeline.run succeeds. Chains the existing
    /// terminationHandler (MPVLifeline close + QuitChildKiller registry
    /// removal keep their behavior) so every actual exit is counted.
    static func register(_ process: Process) {
        let key = ObjectIdentifier(process)
        lock.lock()
        spawnedCount += 1
        live[key] = process
        let spawned = spawnedCount
        let liveN = live.count
        let others = live.count > maxLive ? live.filter { $0.key != key }.map { $0.value } : []
        lock.unlock()
        log("preview mpv spawn pid=\(process.processIdentifier) live=\(liveN) spawned=\(spawned)")
        let prior = process.terminationHandler
        process.terminationHandler = { finished in
            prior?(finished)
            noteExit(finished)
        }
        if !process.isRunning { noteExit(process) }
        for other in others { terminate(other) }
    }

    private static func noteExit(_ process: Process) {
        lock.lock()
        let wasLive = live.removeValue(forKey: ObjectIdentifier(process)) != nil
        if wasLive { exitedCount += 1 }
        let exited = exitedCount
        let liveN = live.count
        lock.unlock()
        if wasLive {
            log("preview mpv exit pid=\(process.processIdentifier) live=\(liveN) exited=\(exited)")
        }
    }

    static func isLive(_ process: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return live[ObjectIdentifier(process)] != nil
    }

    // MARK: - Terminate (graceful -> EOF lifeline -> SIGTERM -> SIGKILL)

    /// Intentional stop. Safe from any thread, idempotent per process:
    /// every step probes first, a dead pid gets no signal.
    static func terminate(_ process: Process, gracefulQuit: (() -> Void)? = nil) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        guard pid > 0 else { return }
        let key = ObjectIdentifier(process)
        lock.lock()
        guard !terminating.contains(key) else { lock.unlock(); return }
        terminating.insert(key); lock.unlock()
        guardQueue.async {
            defer { lock.lock(); terminating.remove(key); lock.unlock() }
            guard process.isRunning else { return }
            MPVLifeline.close(for: process) // EOF is mpv's native quit_on_close
            gracefulQuit?()
            if waitGone(pid, seconds: graceSeconds) { return }
            let rcT = kill(pid, SIGTERM)
            log("preview mpv sigterm pid=\(pid) rc=\(rcT) errno=\(rcT == 0 ? 0 : errno)")
            if waitGone(pid, seconds: graceSeconds) { return }
            let rcK = kill(pid, SIGKILL)
            log("preview mpv sigkill pid=\(pid) rc=\(rcK) errno=\(rcK == 0 ? 0 : errno)")
        }
    }

    /// true when the pid is gone (kill(pid,0) -> ESRCH) within the
    /// budget. An unreaped zombie still reads alive until Foundation
    /// reaps it; the SIGKILL that may follow is a documented no-op.
    private static func waitGone(_ pid: pid_t, seconds: TimeInterval) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            usleep(10_000)
        }
        return kill(pid, 0) != 0 && errno == ESRCH
    }
}

// One hover's cancellable work. No AppKit state is read from worker queues.
final class PreviewWork {
    private let lock = NSLock()
    private var stopped = false
    private var processes: [Process] = []
    private var pendingIPC: (() -> Void)?
    private var ipcRunning = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func attach(_ process: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { return false }
        processes.append(process); return true
    }
    func cancel() {
        lock.lock(); stopped = true; pendingIPC = nil; let owned = processes; lock.unlock()
        for process in owned { PreviewGuard.terminate(process) }
    }
    func sendLatest(_ block: @escaping () -> Void) {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        pendingIPC = block
        guard !ipcRunning else { lock.unlock(); return }
        ipcRunning = true; lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            while true {
                lock.lock()
                guard !stopped, let next = pendingIPC else { pendingIPC = nil; ipcRunning = false; lock.unlock(); return }
                pendingIPC = nil; lock.unlock()
                next()
            }
        }
    }
}
// END station-move PreviewGuard.swift
