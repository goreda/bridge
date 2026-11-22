import Foundation
#if canImport(Darwin)
import Darwin
#elseif os(Linux)
import Glibc
#endif

/// Launches the bundled disk-session helper directly, never through a shell.
/// All operations are serialized; begin must finish before any producer starts.
final class PlayerSessionFileTransport {
    enum Failure:Error {case missingHelper,helperFailed(Int32,String),outputTooLarge}
    private let helper:URL
    private(set) var rawRoot=URL(fileURLWithPath:"/dev/null",isDirectory:false)
    private var allocated=false
    private let queue=DispatchQueue(label:"gor.player-session.files",qos:.utility)
    init(resources:URL)throws {
        helper=resources.appendingPathComponent("player_session_log_cli.py")
        guard FileManager.default.isReadableFile(atPath:helper.path) else{throw Failure.missingHelper}
    }
    private func perform(_ arguments:[String],input:Data?=nil)throws->String {
        let p=Process(),output=Pipe(),stdin=Pipe()
        p.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
        p.arguments=[helper.path]+(allocated ? ["--root",rawRoot.path]:[])+arguments
        p.standardInput=input==nil ? FileHandle.nullDevice:stdin
        #if canImport(Darwin)
        if input != nil {_ = fcntl(stdin.fileHandleForWriting.fileDescriptor,F_SETNOSIGPIPE,1)}
        // Darwin-only: F_SETNOSIGPIPE existence/behavior is NOT proven by Linux runs.
        #endif
        p.standardOutput=output;p.standardError=output
        try p.run()
        var rowWriteFailed=false
        if let input {
            // Raw rows never ride on argv (visible to other local users). Exact
            // length framing (LEN\nPAYLOAD): the helper validates the full
            // length before fanout, so a short write commits NO prefix.
            var framed=Data(String(input.count).utf8);framed.append(0x0a);framed.append(input)
            #if os(Linux)
            // Thread-scoped SIGPIPE guard: no global ignore. Block SIGPIPE on
            // THIS thread around the write, consume a pending one, restore.
            do{try writeAllGuarded(stdin.fileHandleForWriting.fileDescriptor,framed)}
            catch{rowWriteFailed=true}
            #else
            // Darwin: F_SETNOSIGPIPE (set above) + FileHandle.write. NOT
            // certified by Linux runs; Mac verification pending at Ops.
            do{try stdin.fileHandleForWriting.write(contentsOf:framed)}catch{rowWriteFailed=true}
            #endif
            try? stdin.fileHandleForWriting.close()
        }
        // Only bounded helper status, never a raw log stream. Drain while child
        // runs so a failure cannot deadlock waiting on a full pipe.
        var result=Data()
        while true {
            let data=output.fileHandleForReading.availableData
            if data.isEmpty {break}
            guard result.count+data.count<=65536 else {
                p.terminate();_=reapExitCode(p);throw Failure.outputTooLarge
            }
            result.append(data)
        }
        let code=reapExitCode(p)
        let text=String(data:result,encoding:.utf8) ?? "invalid helper output"
        if rowWriteFailed {throw Failure.helperFailed(-1,"row write incomplete")}
        guard code==0 else{throw Failure.helperFailed(code,text)}
        return text
    }

    #if os(Linux)
    /// Linux-only: write all bytes to the helper's stdin without SIGPIPE
    /// killing the process when the child closed its end early. SIGPIPE is
    /// blocked on the CALLING thread for the write's duration only (never a
    /// global ignore); a signal raised by this write is consumed before the
    /// previous mask is restored. EINTR retries; EPIPE/other -> typed throw.
    private func writeAllGuarded(_ fd:Int32,_ data:Data)throws {
        var block=sigset_t();sigemptyset(&block);sigaddset(&block,SIGPIPE)
        var before=sigset_t();_=sigpending(&before)
        let preExisting=sigismember(&before,SIGPIPE)==1
        var old=sigset_t()
        guard pthread_sigmask(SIG_BLOCK,&block,&old)==0 else {
            // Without the block a short write can kill the process: refuse.
            throw Failure.helperFailed(-1,"sigmask block failed; write refused")
        }
        var thrown:Error?=nil
        do { try data.withUnsafeBytes { raw in
            guard let base=raw.baseAddress else{return}
            var off=0
            while off<raw.count {
                let n=write(fd,base.advanced(by:off),raw.count-off)
                if n>0 {off+=n;continue}
                if n == -1 && errno==EINTR {continue}
                if n == -1 && errno==EPIPE {throw Failure.helperFailed(-1,"helper stdin closed early")}
                throw Failure.helperFailed(-1,"row write failed errno=\(errno)")
            }
        } } catch { thrown=error }
        // Consume ONLY a signal this write raised: a SIGPIPE already pending
        // on entry belongs to its owner and is preserved (standard signals
        // coalesce to one pending bit, so leaving it is the safe choice).
        if !preExisting {
            var after=sigset_t();_=sigpending(&after)
            if sigismember(&after,SIGPIPE)==1 {
                var info=siginfo_t();var ts=timespec(tv_sec:0,tv_nsec:0)
                while sigtimedwait(&block,&info,&ts) == -1 && errno==EINTR {}
            }
        }
        let restoreErr=pthread_sigmask(SIG_SETMASK,&old,nil)
        if let thrown {throw thrown}
        guard restoreErr==0 else {throw Failure.helperFailed(-1,"sigmask restore failed")}
    }
    #endif
    /// Linux: corelibs waitUntilExit can miss a helper that exited while its
    /// pipe was draining (observed with the 'watch' helper forking its
    /// detached watcher: output EOFs, waitUntilExit never returns). Reap
    /// directly with blocking waitpid + EINTR retry. ECHILD means corelibs
    /// already reaped the child; fall back to Process state. Darwin keeps
    /// waitUntilExit; the Darwin path is NOT proven by Linux runs.
    private func reapExitCode(_ p:Process)->Int32 {
        #if os(Linux)
        var st:Int32=0
        while true {
            let r=waitpid(p.processIdentifier,&st,0)
            if r==p.processIdentifier {
                if (st & 0x7f)==0 {return (st>>8)&0xff} // WIFEXITED: WEXITSTATUS
                return 128+(st & 0x7f) // signaled
            }
            if r == -1 && errno==EINTR {continue}
            if r == -1 && errno==ECHILD {
                var spins=0
                while p.isRunning && spins<1000 {usleep(1000);spins+=1}
                return p.terminationStatus
            }
            break
        }
        #endif
        p.waitUntilExit()
        return p.terminationStatus
    }
    func begin(token:String,pid:Int32,producers:[String])throws {
        try queue.sync {
            let text=try perform(["allocate",token,String(pid)]+producers)
            struct Allocation:Decodable {let root:String;let token:String}
            let a=try JSONDecoder().decode(Allocation.self,from:Data(text.utf8))
            guard a.token==token,a.root.hasPrefix("/"),a.root != "/tmp" else{throw Failure.helperFailed(2,"invalid allocation")}
            rawRoot=URL(fileURLWithPath:a.root,isDirectory:true);allocated=true
            _ = try perform(["watch",token,String(pid)])
        }
    }
    func appendAppRow(_ data:Data)throws {
        guard data.count<=65536 else{throw Failure.outputTooLarge}
        try queue.sync {_ = try perform(["app-row"],input:data)}
    }
    func register(token:String,producer:String)throws {
        try queue.sync {_ = try perform(["register",token,producer])}
    }
    func admit(token:String,name:String,producer:String)throws {
        try queue.sync {_ = try perform(["admit",token,name,producer])}
    }
    struct NativeAdmission:Decodable {
        let token:String
        let name:String
        let producer:String
        let dev:UInt64
        let ino:UInt64
        let cap:UInt64
        let stateRoot:String
    }
    func admitNative(token:String,name:String,producer:String)throws->NativeAdmission {
        try queue.sync {
            let text=try perform(["admit-native",token,name,producer])
            let a=try JSONDecoder().decode(NativeAdmission.self,from:Data(text.utf8))
            guard a.token==token,a.name==name,a.producer==producer,a.cap>=256 else{throw Failure.helperFailed(2,"invalid admission descriptor")}
            return a
        }
    }
    func nativeCapReached(token:String,name:String,producer:String)throws {
        try queue.sync {_ = try perform(["cap-native",token,name,producer])}
    }
    func close(token:String,completion:@escaping(Result<Void,Error>)->Void) {
        queue.async {
            do {_ = try self.perform(["closing",token]);completion(.success(()))}
            catch {completion(.failure(error))}
        }
    }
    func drained(token:String,producer:String,completion:@escaping(Result<Void,Error>)->Void) {
        queue.async {
            do {_ = try self.perform(["drained",token,producer]);completion(.success(()))}
            catch {completion(.failure(error))}
        }
    }
    func finish(token:String,crash:Bool=false,completion:@escaping(Result<String,Error>)->Void) {
        queue.async {
            do {completion(.success(try self.perform([crash ? "crash":"finish",token])))}
            catch {completion(.failure(error))}
        }
    }
}

extension PlayerSessionFileTransport:PlayerSessionFileCommands {
    func setClosing(token:String)throws {
        try queue.sync {_ = try perform(["closing",token])}
    }
    func markDrained(token:String,producer:String)throws {
        try queue.sync {_ = try perform(["drained",token,producer])}
    }
    func publish(token:String,crash:Bool)throws->String {
        try queue.sync {try perform([crash ? "crash":"finish",token])}
    }
}
