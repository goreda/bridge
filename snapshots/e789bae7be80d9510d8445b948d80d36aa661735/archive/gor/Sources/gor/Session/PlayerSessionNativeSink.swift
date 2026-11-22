import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One admitted file owner. Raw records are written synchronously on a serial
/// queue, never queued in an unbounded RAM spool. Caller must not use this sink
/// as a second independent owner of another producer's admitted file. A held
/// file flock rejects a second native sink; Python/raw descriptor writers must
/// still be excluded by composer. File flock is acquired only at admission,
/// never waited on under the helper lock.
final class PlayerSessionNativeSink {
    typealias Admission = PlayerSessionFileTransport.NativeAdmission
    struct DrainStatus {
        let admission: Admission
        let capReached: Bool
        let writeFailed: Bool
    }
    enum Failure: Error { case invalidAdmission, unsafeRoot, staleSession, replacedFile, closed, io, metadata }
    enum AppendResult: Equatable { case accepted, capReached }
    private let queue = DispatchQueue(label: "gor.player-session.native-sink", qos: .utility)
    private let admission: Admission
    private let parent: URL
    private let stateRoot: URL
    private var fd: Int32 = -1
    private var closing = false
    private var drained = false
    private var capped = false
    private var writeFailed = false
    private var droppedBytes:UInt64=0
    private let reserve: UInt64 = 160
    /// This is metadata handoff only, called once at drain, not per raw record.
    /// Composer MUST commit cap/io status to helper before acknowledging drain.
    private let commitStatus: (DrainStatus) throws -> Void
    /// Composer maps this to adapter.observe("queue-drained",producer:...).
    private let acknowledgeDrain: () throws -> Void

    init(parent: URL, admission: Admission,
         commitStatus: @escaping (DrainStatus) throws -> Void,
         acknowledgeDrain: @escaping () throws -> Void) throws {
        let tokenOK = admission.token.count == 32 && admission.token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        let expected: UInt64 = admission.name == "gor_diag.log" ? 20 * 1024 * 1024 : 10 * 1024 * 1024
        guard tokenOK, !admission.producer.isEmpty, admission.name == URL(fileURLWithPath: admission.name).lastPathComponent,
              !admission.name.hasPrefix("."), admission.cap >= 256, admission.cap == expected else { throw Failure.invalidAdmission }
        self.parent = parent; self.stateRoot = URL(fileURLWithPath: admission.stateRoot, isDirectory: true); self.admission = admission
        self.commitStatus = commitStatus; self.acknowledgeDrain = acknowledgeDrain
        try withSessionLock {
            try validateReceipt()
            let opened = open(parent.appendingPathComponent(admission.name).path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
            guard opened >= 0 else { throw Failure.replacedFile }
            fd = opened
            do {
                _ = try validateFile()
                guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw Failure.replacedFile }
            } catch { close(opened); fd = -1; throw error }
        }
    }
    deinit { if fd >= 0 { close(fd) } } // no invented drain acknowledgment

    /// Serialized, bounded-by-caller backpressure; no per-record Process or async Data capture.
    @discardableResult func append(_ record: Data) throws -> AppendResult {
        try queue.sync {
            guard !closing, !drained, !writeFailed else { throw Failure.closed }
            return try withSessionLock {
                try validateReceipt()
                let size = try validateFile()
                let count=UInt64(record.count)
                if !capped,size+count<=admission.cap {
                    do {try writeAll(record)}catch {writeFailed=true;throw error}
                    return .accepted
                }
                // Bounded disk head+tail. Only half a raw-file cap is read;
                // no session-sized in-memory spool and no unbounded queue.
                let reserve=UInt64(160),bodyCap=admission.cap-reserve
                let head=bodyCap/2,tailCap=bodyCap-head
                if !capped,size<head {
                    // A first oversized append still contributes its beginning
                    // to the retained head, not a sparse zero-filled gap.
                    try writeAll(Data(record.prefix(Int(min(head-size,count)))))
                }
                let reader=open(parent.appendingPathComponent(admission.name).path,O_RDONLY|O_NOFOLLOW|O_CLOEXEC)
                guard reader>=0 else{writeFailed=true;throw Failure.io}
                let handle=FileHandle(fileDescriptor:reader,closeOnDealloc:true)
                let oldTailCount=min(size>head ? size-head:0,tailCap)
                try handle.seek(toOffset:size-oldTailCount)
                let oldTail=try handle.read(upToCount:Int(oldTailCount)) ?? Data()
                var tail=Data()
                if record.count>=Int(tailCap) {tail=record.suffix(Int(tailCap))}
                else {
                    tail.append(oldTail.suffix(max(0,Int(tailCap)-record.count)));tail.append(record)
                }
                let priorPayload=capped ? bodyCap:size
                droppedBytes += priorPayload+count>bodyCap ? priorPayload+count-bodyCap:0
                var note=Data(("\nTRUNCATED \(droppedBytes) bytes\n").utf8)
                if note.count<Int(reserve) {note.append(Data(repeating:32,count:Int(reserve)-note.count))}
                guard lseek(fd,off_t(head),SEEK_SET)>=0 else{writeFailed=true;throw Failure.io}
                // O_APPEND must be cleared for compaction under the owner lock.
                let flags=fcntl(fd,F_GETFL)
                guard flags>=0,fcntl(fd,F_SETFL,flags & ~O_APPEND)==0 else{writeFailed=true;throw Failure.io}
                defer {_ = fcntl(fd,F_SETFL,flags)}
                try writeAll(note);try writeAll(tail)
                guard ftruncate(fd,off_t(head+UInt64(note.count)+UInt64(tail.count)))==0 else{writeFailed=true;throw Failure.io}
                capped=true;return .capReached
            }
        }
    }

    /// Serial queue barrier runs after every prior synchronous append. No queue
    /// drain success until fd sync/close AND helper status commit have succeeded.
    /// A failed metadata callback may be retried; no further appends are admitted.
    func drain() throws {
        try queue.sync {
            if drained { return }
            closing = true
            if fd >= 0 {
                try withSessionLock {
                    try validateReceipt()
                    _ = try validateFile()
                    if fsync(fd) != 0 { writeFailed = true }
                    let old = fd; fd = -1
                    if close(old) != 0 { writeFailed = true }
                }
            }
            try withSessionLock { try validateReceipt() }
            try commitStatus(DrainStatus(admission: admission, capReached: capped, writeFailed: writeFailed))
            guard !writeFailed else { throw Failure.io }
            try acknowledgeDrain()
            drained = true
        }
    }

    private func withSessionLock<T>(_ body: () throws -> T) throws -> T {
        var root = stat(), parentInfo = stat()
        guard lstat(stateRoot.path, &root) == 0, (root.st_mode & S_IFMT) == S_IFDIR,
              lstat(parent.path, &parentInfo) == 0, (parentInfo.st_mode & S_IFMT) == S_IFDIR else { throw Failure.unsafeRoot }
        guard root.st_uid == geteuid(), (root.st_mode & 0o077) == 0 else { throw Failure.unsafeRoot }
        let ownerFD = open(stateRoot.appendingPathComponent(".owner").path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard ownerFD >= 0 else { throw Failure.unsafeRoot }
        defer { close(ownerFD) }
        var ownerInfo = stat(), ownerBytes = [UInt8](repeating: 0, count: 64)
        guard fstat(ownerFD, &ownerInfo) == 0, (ownerInfo.st_mode & S_IFMT) == S_IFREG,
              ownerInfo.st_nlink == 1, ownerInfo.st_size == 19 else { throw Failure.unsafeRoot }
        let ownerCount = read(ownerFD, &ownerBytes, ownerBytes.count)
        guard ownerCount == 19, String(bytes: ownerBytes.prefix(19), encoding: .utf8) == "gor-log-archives-v2" else { throw Failure.unsafeRoot }
        // Must exist from helper begin; sink does not create/adopt state paths.
        let lockFD = open(stateRoot.appendingPathComponent(".lock").path, O_RDWR | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard lockFD >= 0 else { throw Failure.unsafeRoot }
        defer { _ = flock(lockFD, LOCK_UN); close(lockFD) }
        var lockInfo = stat()
        guard fstat(lockFD, &lockInfo) == 0, (lockInfo.st_mode & S_IFMT) == S_IFREG, lockInfo.st_nlink == 1,
              flock(lockFD, LOCK_EX) == 0 else { throw Failure.unsafeRoot }
        return try body()
    }
    private func validateReceipt() throws {
        let receipt = stateRoot.appendingPathComponent("player-session.json")
        let input = open(receipt.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard input >= 0 else { throw Failure.metadata }
        let handle = FileHandle(fileDescriptor: input, closeOnDealloc: true)
        var info = stat()
        guard fstat(input, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_nlink == 1 else { throw Failure.metadata }
        guard info.st_size >= 0, info.st_size <= 1024 * 1024 else { throw Failure.metadata }
        let data = try handle.read(upToCount: 1024 * 1024 + 1) ?? Data()
        guard data.count <= 1024 * 1024 else { throw Failure.metadata }
        guard let r = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              r["token"] as? String == admission.token,
              ["open", "closing"].contains(r["state"] as? String ?? ""),
              let producers = r["producers"] as? [String: Bool], producers[admission.producer] == false,
              let files = r["files"] as? [String: [String: Any]], let m = files[admission.name],
              m["producer"] as? String == admission.producer,
              (m["dev"] as? NSNumber)?.uint64Value == admission.dev,
              (m["ino"] as? NSNumber)?.uint64Value == admission.ino,
              (m["cap"] as? NSNumber)?.uint64Value == admission.cap else { throw Failure.staleSession }
        if (r["caps"] as? [String] ?? []).contains(admission.name) { capped = true }
    }
    private func validateFile() throws -> UInt64 {
        var descriptor = stat(), path = stat()
        guard fd >= 0, fstat(fd, &descriptor) == 0,
              lstat(parent.appendingPathComponent(admission.name).path, &path) == 0,
              (descriptor.st_mode & S_IFMT) == S_IFREG, descriptor.st_nlink == 1,
              (path.st_mode & S_IFMT) == S_IFREG, path.st_nlink == 1,
              UInt64(descriptor.st_dev) == admission.dev, UInt64(descriptor.st_ino) == admission.ino,
              descriptor.st_dev == path.st_dev, descriptor.st_ino == path.st_ino,
              descriptor.st_size >= 0, UInt64(descriptor.st_size) <= admission.cap else { throw Failure.replacedFile }
        return UInt64(descriptor.st_size)
    }
    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var at = 0
            while at < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: at), raw.count - at)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Failure.io }
                at += n
            }
        }
    }
}
