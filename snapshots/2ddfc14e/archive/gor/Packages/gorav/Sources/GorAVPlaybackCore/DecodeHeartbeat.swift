// DecodeHeartbeat.swift - gorav block 168 L14 kit binding: the player's
// OWN decode-progress heartbeat for the L13 soak --heartbeat-file /
// --require-heartbeat gate and the L11 thermal PROGRESS_FILE binding.
//
// CONTRACT (L13 r4): $GORAV_HB_FILE names a per-run file; the value must
// be the player/decoder's OWN DECODE COUNTER - decoded frames produced by
// THIS player run. Never a wall tick, never a CPU proxy, never a liveness
// beacon: the gate treats a non-advancing value as SOAK_INCONCLUSIVE
// (liveness is not decode progress) and a stall as HANG.
//
// PLACEMENT: the writer lives in GorAVPlaybackCore (pure Foundation,
// Linux-venue testable); the decode-event ping lives in ShellFrameSource
// (MacShell), at the point the player's OWN decoder emits a decoded frame.
// Disabled unless the environment names a file: default runs are
// byte-identical to before (no file, no syscalls, no behavior change).
//
// FAILURE DISCIPLINE: a heartbeat write failure NEVER throws into
// playback. It is counted (writeFailures) and the counter keeps
// advancing in memory; the gate's honest outcome for a missing/stale
// file is INCONCLUSIVE, which is the correct signal - telemetry must
// not break playback, and playback must not fabricate telemetry.
import Foundation

public final class DecodeHeartbeat: @unchecked Sendable {
    /// The environment variable the L13 soak runner sets per run
    /// ({run_id}-substituted path; counters reset per playback).
    public static let environmentVariable = "GORAV_HB_FILE"

    private let path: String
    private let lock = NSLock()
    private var _count: UInt64 = 0
    private var _writeFailures: UInt64 = 0

    /// Decoded frames observed this run (starts at 0 per instance -
    /// a fresh playback run is a fresh counter, per the contract).
    public var count: UInt64 { lock.lock(); defer { lock.unlock() }; return _count }
    /// Write failures observed; diagnostic only, never fatal.
    public var writeFailures: UInt64 { lock.lock(); defer { lock.unlock() }; return _writeFailures }

    /// nil path (or empty) means DISABLED: init returns nil and the
    /// player carries no heartbeat at all (default unchanged behavior).
    public init?(path: String?) {
        guard let path, !path.isEmpty else { return nil }
        self.path = path
    }

    /// One decoded frame from the player's own decoder. Writes the new
    /// counter atomically (same-directory temp file + rename) so a
    /// concurrent reader never sees a torn value. Every call writes:
    /// no throttle, no timer - the value IS the decode counter, so the
    /// file advances exactly when decode advances.
    public func noteDecodedFrame() {
        lock.lock()
        _count &+= 1
        let v = _count
        lock.unlock()
        write(v)
    }

    private func write(_ v: UInt64) {
        let tmp = path + ".tmp-\(getpid())"
        do {
            try Data("\(v)\n".utf8).write(to: URL(fileURLWithPath: tmp))
            // POSIX rename(2) over the destination: the ONLY atomic
            // publish. (A remove+move pair would leave a window where
            // the path is absent, readable as a torn heartbeat.)
            if rename(tmp, path) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            lock.lock(); _writeFailures &+= 1; lock.unlock()
            try? FileManager.default.removeItem(atPath: tmp)
        }
    }
}
