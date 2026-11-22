// Engine-owned metadata process boundary. No shell, URL logging or downloader
// playback wrapper. Linux backend first; other platforms are typed-unavailable.
import Foundation
#if os(Linux)
import Glibc
#endif

public final class YtdlpProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    public init() {}
    public func cancel() { lock.lock(); flag = true; lock.unlock() }
    fileprivate var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

public enum YtdlpProcessSource {
    /// Blocking worker entry. Run off the UI/native decode queue. Process group,
    /// pipes and waitpid are owned by this call; returned URLs/headers are secret.
    public static func resolve(url: String, executable: String,
                               cookiesFile: String? = nil, maxHeight: Int = 1080,
                               timeout: Double = 25,
                               cancellation: YtdlpProcessCancellation = .init()) throws -> LabYtdlp.Resolved {
        guard executable.hasPrefix("/"), timeout.isFinite, timeout > 0, timeout <= 300 else {
            throw LabYtdlpError.kind("process_config", "")
        }
        let argv = try LabYtdlp.buildArgv(url, exe: executable, cookiesFile: cookiesFile, maxH: maxHeight)
        #if os(Linux)
        let output = try run(argv, timeout: timeout, cancellation: cancellation)
        guard let value = try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            throw LabYtdlpError.kind("bad_json", "")
        }
        return try LabYtdlp.resolveFormats(value, maxH: maxHeight)
        #else
        throw LabYtdlpError.kind("process_platform_unavailable", "")
        #endif
    }
    #if os(Linux)
    private static func run(_ argv: [String], timeout: Double,
                            cancellation: YtdlpProcessCancellation) throws -> Data {
        if cancellation.cancelled { throw LabYtdlpError.kind("cancelled", "") }
        var outputFD: [Int32] = [0, 0], errorFD: [Int32] = [0, 0]
        guard pipe(&outputFD) == 0 else { throw LabYtdlpError.kind("pipe_failed", "") }
        guard pipe(&errorFD) == 0 else {
            close(outputFD[0]); close(outputFD[1]); throw LabYtdlpError.kind("pipe_failed", "")
        }
        defer { for fd in outputFD + errorFD where fd >= 0 { close(fd) } }
        var actions = posix_spawn_file_actions_t(), attributes = posix_spawnattr_t()
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw LabYtdlpError.kind("spawn_actions", "") }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw LabYtdlpError.kind("spawn_attributes", "") }
        defer { posix_spawnattr_destroy(&attributes) }
        var setup = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        setup |= posix_spawnattr_setpgroup(&attributes, 0)
        setup |= posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        setup |= posix_spawn_file_actions_adddup2(&actions, outputFD[1], STDOUT_FILENO)
        setup |= posix_spawn_file_actions_adddup2(&actions, errorFD[1], STDERR_FILENO)
        for fd in outputFD + errorFD { setup |= posix_spawn_file_actions_addclose(&actions, fd) }
        guard setup == 0 else { throw LabYtdlpError.kind("spawn_setup", "") }
        let pointers: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        defer { for pointer in pointers { free(pointer) } }
        guard pointers.dropLast().allSatisfy({ $0 != nil }) else { throw LabYtdlpError.kind("allocation", "") }
        var pid: pid_t = 0
        let rc = pointers.withUnsafeBufferPointer { args in
            posix_spawn(&pid, args[0]!, &actions, &attributes, args.baseAddress!, environ)
        }
        guard rc == 0 else { throw LabYtdlpError.kind("spawn_failed", "") }
        close(outputFD[1]); outputFD[1] = -1; close(errorFD[1]); errorFD[1] = -1
        _ = fcntl(outputFD[0], F_SETFL, O_NONBLOCK); _ = fcntl(errorFD[0], F_SETFL, O_NONBLOCK)
        let began = DispatchTime.now().uptimeNanoseconds
        var stoppedAt: UInt64?, failure: String?, status: Int32 = 0
        var reaped = false, sentKill = false
        var data = Data(), errors = Data(), outEOF = false, errEOF = false
        var buffer = [UInt8](repeating: 0, count: 16384)
        func elapsed(_ stamp: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - stamp) / 1e9 }
        while true {
            if failure == nil {
                if cancellation.cancelled { failure = "cancelled" }
                else if elapsed(began) >= timeout { failure = "timeout" }
            }
            if failure != nil && stoppedAt == nil { stoppedAt = DispatchTime.now().uptimeNanoseconds; _ = kill(-pid, SIGTERM) }
            if let stop = stoppedAt, !sentKill, elapsed(stop) >= 0.3 { _ = kill(-pid, SIGKILL); sentKill = true }
            for stream in 0...1 {
                let fd = stream == 0 ? outputFD[0] : errorFD[0]
                if (stream == 0 && outEOF) || (stream == 1 && errEOF) { continue }
                // Bound work per stream per cycle so a noisy producer cannot
                // starve stderr draining, cancellation, or the deadline.
                for _ in 0..<8 {
                    let count = read(fd, &buffer, buffer.count)
                    if count > 0 {
                        let cap = stream == 0 ? LabYtdlp.maxStdout : LabYtdlp.maxStderr
                        let existing = stream == 0 ? data.count : errors.count
                        if count > cap - existing { failure = stream == 0 ? "stdout_limit" : "stderr_limit" }
                        else if stream == 0 { data.append(contentsOf: buffer.prefix(count)) }
                        else { errors.append(contentsOf: buffer.prefix(count)) }
                    } else if count == 0 {
                        if stream == 0 { outEOF = true } else { errEOF = true }; break
                    } else if errno == EAGAIN || errno == EINTR { break }
                    else { failure = "pipe_read"; break }
                }
            }
            // Do not reap the group leader until teardown is complete, so its
            // PID/group identity cannot be recycled before our final kill.
            if outEOF && errEOF && failure == nil {
                let waited = waitpid(pid, &status, WNOHANG)
                if waited == pid { reaped = true; break }
            }
            if let stop = stoppedAt, elapsed(stop) >= 0.6 {
                _ = kill(-pid, SIGKILL)
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
                reaped = true; break
            }
            usleep(10_000)
        }
        if !reaped { _ = kill(-pid, SIGKILL); while waitpid(pid, &status, 0) < 0 && errno == EINTR {} }
        if let kind = failure { throw LabYtdlpError.kind(kind, "") }
        // Linux wait status: normal exit is low7 bits zero and high8 exit code.
        guard status & 0x7f == 0, (status >> 8) & 0xff == 0 else {
            throw LabYtdlpError.kind(LabYtdlp.classify(String(decoding: errors, as: UTF8.self)), "")
        }
        return data
    }
    #endif
}
