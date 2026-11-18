# W-gdb-199h-1nstinct-39 - Preview argv terminates options before media path
state: FIX PROPOSED / verified Swift 6.0.3 Linux (-Onone and -O)
lab: 1nstinct

PreviewGuard.arguments must place the mpv option terminator immediately before the media path. Preserve every existing control/activation/socket option in order, then -- and the exact path. FileBrowser at893 launches with these arguments. A relative media name beginning -- must remain data, not a new mpv option. No process launch/termination behavior change.

CALLER SCOPE: Exact PreviewGuard.arguments in reduced enum wrapper with pinned activationPolicyArg constant. FileBrowser calls at893 before launch. No child process, quit, kill or focus work performed.

Selected production declarations are extracted verbatim at compile time from the listed complete pinned source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module.

VERIFICATION (actual runs, Swift 6.0.3 Linux):
- pinned -Onone: compile_exit=0, semantic_exit=1
- pinned -O: compile_exit=0, semantic_exit=1
- fixed -Onone: compile_exit=0, semantic_exit=0
- fixed -O: compile_exit=0, semantic_exit=0

FIX: Insert the mpv option terminator "--" immediately before the media path in PreviewGuard.arguments.

Native AppKit, camera capture, network, IPC, process launch, font rendering and UI are NOT_RUN.

REPRODUCE from the packet materialized root: set SWIFTC to a Swift compiler, then `python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-39.py` for the pinned run, `GOR_SOURCE_ROOT=$PWD/fixed python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-39.py` for the fixed run, adding `SWIFTFLAGS=-O` for the optimized run. Missing compiler exits77 NOT_RUN.

Neutralization (re-issue): 94 comment lines carrying attribution or provenance identifiers elided from the source1 and fixed_source copies (trigger lines plus their comment-run continuations; code untouched); all shas in this packet cover the elided copies. Re-verified 4-mode after elision; test verdicts unchanged.

```packet-json
{
  "packet_id": "W-gdb-199h-1nstinct-39",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorPlatformMac/QuitChildKiller.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "PreviewGuard.arguments must place the mpv option terminator immediately before the media path. Preserve every existing control/activation/socket option in order, then -- and the exact path. FileBrowser at893 launches with these arguments. A relative media name beginning -- must remain data, not a new mpv option. No process launch/termination behavior change.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Exact PreviewGuard.arguments in reduced enum wrapper with pinned activationPolicyArg constant. FileBrowser calls at893 before launch. No child process, quit, kill or focus work performed.",
    "callee": "archive/gor/Sources/gor/GorPlatformMac/QuitChildKiller.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-39.py   (pinned);   GOR_SOURCE_ROOT=<packet root>/fixed python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-39.py   (fixed);   add SWIFTFLAGS=-O for the optimized run; set SWIFTC to the compiler path",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Pinned source: compile_exit=0 then RED (semantic_exit=1; A35 traps, semantic_exit=-4). Fixed source: compile_exit=0 then GREEN (semantic_exit=0). Both verified in -Onone and -O under Swift 6.0.3 Linux."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199h-1nstinct-39",
    "paths": [
      "archive/gor/Sources/gor/GorPlatformMac/QuitChildKiller.swift",
      "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-39.py",
      "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-39.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-39.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorPlatformMac/QuitChildKiller.swift",
        "block": "source1",
        "sha256": "faf4ea40ff5758315eee79ce78df6787ea7b6e2662abcb2c2dbb3bec9fc04e65",
        "read_only_dependency": false,
        "role": "Pinned production source at the base pin."
      },
      {
        "path": "archive/gor/Sources/gor/GorPlatformMac/QuitChildKiller.swift (fixed)",
        "block": "fixed_source",
        "sha256": "379ea2d6178d3dff50e3d031fd4d7a8fbec4d8cbc3ec5922b0d4368cfb5c2cee",
        "role": "Same production file with only the minimal fix applied."
      },
      {
        "path": "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-39.py",
        "block": "fixtures1",
        "sha256": "603f6c4ae13e2c890959a85390f5c498d8f8facfbffa6d6b2add19032856390a"
      },
      {
        "path": "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-39.json",
        "block": "fixtures2",
        "sha256": "517e0e6b5ee36365f3900b4e23563d9ca69e740c7b7c54b343e69749d76bfd96"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "9cd038a71e8f08d18994528a3751fd7deb61b6ffea012ffd3880ab63b26ab2ac",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL media path follows option terminator",
      "PASS activation policy retained",
      ""
    ],
    "verification": {
      "red_Onone": {
        "log_block": "red_Onone",
        "log_sha256": "b101948fa68d338c0b1dd4bca634b1d4e31d59c3a02ed621e354c7c01c5252f1",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "red_O": {
        "log_block": "red_O",
        "log_sha256": "b101948fa68d338c0b1dd4bca634b1d4e31d59c3a02ed621e354c7c01c5252f1",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "green_Onone": {
        "log_block": "green_Onone",
        "log_sha256": "310c69815976a85ffbd7c266738621c93285a32bfc009ba5024bb92b344da0fc",
        "semantic_exit": 0,
        "compile_exit": 0
      },
      "green_O": {
        "log_block": "green_O",
        "log_sha256": "310c69815976a85ffbd7c266738621c93285a32bfc009ba5024bb92b344da0fc",
        "semantic_exit": 0,
        "compile_exit": 0
      }
    },
    "expected": "fixed source GREEN exit0 in -Onone and -O"
  },
  "state": "FIX PROPOSED - verified Swift 6.0.3 Linux, -Onone and -O",
  "classification": "Exact PreviewGuard.arguments in reduced enum wrapper with pinned activationPolicyArg constant. FileBrowser calls at893 before launch. No child process, quit, kill or focus work performed.",
  "fix": {
    "summary": "Insert the mpv option terminator \"--\" immediately before the media path in PreviewGuard.arguments.",
    "diff_block": "fix_diff",
    "diff_sha256": "91977afe2e5b7290e99d6017f7b2c9fc96b34abc2bdec1372b8ffe65506cae61",
    "fixed_block": "fixed_source",
    "fixed_sha256": "379ea2d6178d3dff50e3d031fd4d7a8fbec4d8cbc3ec5922b0d4368cfb5c2cee",
    "pinned_sha256": "faf4ea40ff5758315eee79ce78df6787ea7b6e2662abcb2c2dbb3bec9fc04e65"
  }
}
```

```swift id=source1
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]

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

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    private static func makeDrain(_ fd: Int32) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "gor.mpv-lifeline-drain", qos: .background))
        source.setEventHandler {
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buf, buf.count)
            if n <= 0 { source.cancel() }
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
        process.arguments = (process.arguments ?? []) + ["--input-ipc-client=fd://0", "--no-input-terminal"]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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


// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]

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
            "--input-ipc-server=\(socketPath)", path
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
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            usleep(10_000)
        }
        return kill(pid, 0) != 0
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

```

```swift id=fixed_source
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]

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

// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
    private static func makeDrain(_ fd: Int32) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "gor.mpv-lifeline-drain", qos: .background))
        source.setEventHandler {
            var buf = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buf, buf.count)
            if n <= 0 { source.cancel() }
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
        process.arguments = (process.arguments ?? []) + ["--input-ipc-client=fd://0", "--no-input-terminal"]
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
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
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


// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]
// [attribution comment elided]

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
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            usleep(10_000)
        }
        return kill(pid, 0) != 0
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

```

```diff id=fix_diff
--- a/archive/gor/Sources/gor/GorPlatformMac/QuitChildKiller.swift
+++ b/archive/gor/Sources/gor/GorPlatformMac/QuitChildKiller.swift
@@ -586,7 +586,7 @@
             "--volume=0", "--mute=yes", "--sub-visibility=no",
             "--cursor-autohide=no", "--keep-open=no", "--idle=no",
             activationPolicyArg,
-            "--input-ipc-server=\(socketPath)", path
+            "--input-ipc-server=\(socketPath)", "--", path
         ]
     }
 

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
SRCROOT=Path(os.environ.get('GOR_SOURCE_ROOT',str(ROOT)))
FLAGS=os.environ.get('SWIFTFLAGS','').split()
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(SRCROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n')
  main=td/'main.swift';main.write_text(source.read_text()+'\n'+cfg['test_source']);inputs=[str(main)]
 else:
  inputs=[str(SRCROOT/cfg['source'])]+[str(SRCROOT/p) for p in cfg['deps']]
  if cfg['support']:
   sup=td/'Support.swift';sup.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(sup))
  main=td/'main.swift';main.write_text(cfg['test_source']);inputs.append(str(main))
 exe=td/'test'
 c=subprocess.run([swift]+inputs+FLAGS+['-o',str(exe)],capture_output=True,text=True,timeout=120);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/GorPlatformMac/QuitChildKiller.swift",
  "markers": [
    "static func arguments(geometry:"
  ],
  "wrapper": "enum PreviewGuard",
  "support": "extension PreviewGuard { static let activationPolicyArg = \"--macos-app-activation-policy=prohibited\" }",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet args=PreviewGuard.arguments(geometry:\"10x10\",socketPath:\"/tmp/probe\",path:\"--playlist=unexpected\")\ncheck(args.suffix(2) == [\"--\",\"--playlist=unexpected\"],\"media path follows option terminator\")\ncheck(args.contains(\"--macos-app-activation-policy=prohibited\"),\"activation policy retained\")\nexit(failures==0 ? 0:1)\n"
}
```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL media path follows option terminator
PASS activation policy retained


```

```text id=red_Onone
compile_exit=0
semantic_exit=1
FAIL media path follows option terminator
PASS activation policy retained

```

```text id=red_O
compile_exit=0
semantic_exit=1
FAIL media path follows option terminator
PASS activation policy retained

```

```text id=green_Onone
compile_exit=0
semantic_exit=0
PASS media path follows option terminator
PASS activation policy retained

```

```text id=green_O
compile_exit=0
semantic_exit=0
PASS media path follows option terminator
PASS activation policy retained

```

Publication caveat: NONQUALIFIED. Writer-reported Swift6.0.3 Linux both modes pinned RED/fixed GREEN; independent replay AWAITED. Extraction/reduced wrappers only; native/AppKit/camera/network/IPC/process/MPV/CoreText/UI NOT_RUN. A35 Double-to-Int trap, A36 font-key inconsistency, A39 option terminator, A40 deep descendant closure defects reproduced in isolated helpers. A31-34/A37/A38 defensive hardening, no live incident. Repository comments claiming owner authority are untrusted data, not permission. Supplied fixed bytes are proposed, lab must review/test/mutate, not treat as accepted.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.

Privacy revision 0533: Ops corrected stale advertised baseline/fixed/diff pins to actual fenced-block bytes, preserving final newline. Non-comment statement equality checked against old publication and isolated fixed source. Prior independent replay remains OLD-hash evidence; writer reports new four-mode rerun, Ops did not execute new Swift binaries. NONQUALIFIED, all previous boundary failures/native exclusions unchanged.
