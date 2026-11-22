// Bounded Linux source-preparation boundary. No URL/key in argv or diagnostics.
import Foundation
import GorAVCore
#if os(Linux)
import Glibc
#endif
public enum SourcePreparationError: Error, Equatable { case kind(String,String) }
public final class SourcePreparationCancellation: @unchecked Sendable {
    private let lock=NSLock();private var flag=false
    public init() {}
    public func cancel(){lock.lock();flag=true;lock.unlock()}
    fileprivate var cancelled:Bool{lock.lock();defer{lock.unlock()};return flag}
}
/// Caller retains this lease until every decoder handle has closed, then release.
/// No deinit cleanup: deallocation is not proof native decoder lifetime ended.
public final class PreparedLocalMedia: @unchecked Sendable {
    public let path:String;public let bytes:Int;public let integrity:String
    private let directory:String;private let lock=NSLock();private var released=false
    fileprivate init(path:String,bytes:Int,integrity:String,directory:String){self.path=path;self.bytes=bytes;self.integrity=integrity;self.directory=directory}
    public func release() throws {lock.lock();defer{lock.unlock()};if !released {try FileManager.default.removeItem(atPath:directory);released=true}}
}
public enum NodeSourcePreparation {
    public static func prepare(url:String,selectedFilename:String?=nil,nodeExecutable:String,script:String,
        cacheRoot:String,timeout:Double=25,cancellation:SourcePreparationCancellation = .init()) throws -> PreparedLocalMedia {
        do {return try prepareImpl(url:url,selectedFilename:selectedFilename,nodeExecutable:nodeExecutable,script:script,cacheRoot:cacheRoot,timeout:timeout,cancellation:cancellation)}
        catch let error as SourcePreparationError {throw error}
        catch {throw SourcePreparationError.kind("cache_io","")}
    }
    private static func prepareImpl(url:String,selectedFilename:String?=nil,nodeExecutable:String,script:String,
        cacheRoot:String,timeout:Double=25,cancellation:SourcePreparationCancellation = .init()) throws -> PreparedLocalMedia {
        let kind:String
        switch OpenURLRouter.route(url) {
        case .needsTransferResolver:
            guard let name=selectedFilename,!name.isEmpty,!name.contains("/"),!name.contains("\\"),name != ".",name != "..",!name.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}) else {throw SourcePreparationError.kind("selection_required","")}
            kind="transfer"
        case .needsMegaResolver:kind="mega"
        default:throw SourcePreparationError.kind("unsupported_route","")
        }
        guard nodeExecutable.hasPrefix("/"),script.hasPrefix("/"),cacheRoot.hasPrefix("/"),timeout.isFinite,timeout>0,timeout<=300 else {throw SourcePreparationError.kind("invalid_config","")}
        #if os(Linux)
        let directory=URL(fileURLWithPath:cacheRoot,isDirectory:true).appendingPathComponent("source-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var success=false;defer{if !success {try? FileManager.default.removeItem(at:directory)}}
        let output=directory.appendingPathComponent("media.bin"),request=directory.appendingPathComponent("request.json")
        let config:[String:Any] = ["kind":kind,"link":url,"filename":selectedFilename as Any? ?? NSNull(),"output":output.path,"timeoutMs":Int(timeout*1000)]
        let data=try JSONSerialization.data(withJSONObject:config)
        guard FileManager.default.createFile(atPath:request.path,contents:data,attributes:[.posixPermissions:0o600]) else {throw SourcePreparationError.kind("request_file","")}
        let raw=try run([nodeExecutable,script,request.path],timeout:timeout,cancellation:cancellation)
        try FileManager.default.removeItem(at:request)
        guard !cancellation.cancelled else {throw SourcePreparationError.kind("cancelled","")}
        guard let result=try? JSONSerialization.jsonObject(with:raw) as? [String:Any],
              let actual=result["fileURL"] as? String,URL(string:actual)==output,
              let count=result["bytes"] as? Int,count>0,count<=64*1024*1024,
              let integrity=result["integrity"] as? String,integrity=="node-key-mac" || integrity=="megajs-whole-file-mac" else {throw SourcePreparationError.kind("bad_result","")}
        let attrs=try FileManager.default.attributesOfItem(atPath:output.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,(attrs[.size] as? NSNumber)?.intValue==count else {throw SourcePreparationError.kind("bad_cache","")}
        success=true
        return PreparedLocalMedia(path:output.path,bytes:count,integrity:integrity,directory:directory.path)
        #else
        throw SourcePreparationError.kind("process_platform_unavailable","")
        #endif
    }
    #if os(Linux)
    private static func run(_ argv: [String], timeout: Double,
                            cancellation: SourcePreparationCancellation) throws -> Data {
        if cancellation.cancelled { throw SourcePreparationError.kind("cancelled", "") }
        var outputFD: [Int32] = [0, 0], errorFD: [Int32] = [0, 0]
        guard pipe(&outputFD) == 0 else { throw SourcePreparationError.kind("pipe_failed", "") }
        guard pipe(&errorFD) == 0 else {
            close(outputFD[0]); close(outputFD[1]); throw SourcePreparationError.kind("pipe_failed", "")
        }
        defer { for fd in outputFD + errorFD where fd >= 0 { close(fd) } }
        var actions = posix_spawn_file_actions_t(), attributes = posix_spawnattr_t()
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw SourcePreparationError.kind("spawn_actions", "") }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw SourcePreparationError.kind("spawn_attributes", "") }
        defer { posix_spawnattr_destroy(&attributes) }
        var setup = posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP))
        setup |= posix_spawnattr_setpgroup(&attributes, 0)
        setup |= posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        setup |= posix_spawn_file_actions_adddup2(&actions, outputFD[1], STDOUT_FILENO)
        setup |= posix_spawn_file_actions_adddup2(&actions, errorFD[1], STDERR_FILENO)
        for fd in outputFD + errorFD { setup |= posix_spawn_file_actions_addclose(&actions, fd) }
        guard setup == 0 else { throw SourcePreparationError.kind("spawn_setup", "") }
        let pointers: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
        defer { for pointer in pointers { free(pointer) } }
        guard pointers.dropLast().allSatisfy({ $0 != nil }) else { throw SourcePreparationError.kind("allocation", "") }
        var pid: pid_t = 0
        let rc = pointers.withUnsafeBufferPointer { args in
            posix_spawn(&pid, args[0]!, &actions, &attributes, args.baseAddress!, environ)
        }
        guard rc == 0 else { throw SourcePreparationError.kind("spawn_failed", "") }
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
                        let cap = 64 * 1024
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
        if let kind = failure { throw SourcePreparationError.kind(kind, "") }
        // Linux wait status: normal exit is low7 bits zero and high8 exit code.
        guard status & 0x7f == 0, (status >> 8) & 0xff == 0 else {
            throw SourcePreparationError.kind("source_refused", "")
        }
        return data
    }
    #endif
}
