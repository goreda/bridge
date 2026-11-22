import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// One player-process capture. Internal roots are not the output: every close
/// publishes this player's own timecoded ZIP under the archive parent.
final class PlayerSessionContext {
    static let shared:PlayerSessionContext? = {
        guard let resources=Bundle.main.resourceURL else{return nil}
        do {return try PlayerSessionContext(resources:resources,pid:ProcessInfo.processInfo.processIdentifier)}
        catch {NSLog("[GOR] player log capture unavailable: %@",String(describing:error));return nil}
    }()
    private let directReader=DispatchQueue(label:"gor.player-session.direct",qos:.utility)
    private let directDone=DispatchSemaphore(value:0)
    private var directSink:PlayerSessionNativeSink?
    private var directPipe:Pipe?
    private var directProducer:PlayerSessionDrainPlan.Producer?
    private var directFailure:Error?
    private let sinkLock=NSRecursiveLock()
    private var sharedRawSinks:[String:PlayerSessionNativeSink]=[:]
    private let closeQueue=DispatchQueue(label:"gor.player-session.close",qos:.utility)
    let transport:PlayerSessionFileTransport
    let adapter:PlayerSessionBarrierAdapter
    var token:String {adapter.token}
    var rawRoot:URL {transport.rawRoot}
    /// All temporary resources of this player map here. Never allocates a new
    /// context or id; shared is constructed before startup cleanup/producer run.
    func path(_ original:String)->String {
        rawRoot.appendingPathComponent(URL(fileURLWithPath:original).lastPathComponent).path
    }
    init(resources:URL,pid:Int32)throws {
        let files=try PlayerSessionFileTransport(resources:resources)
        let barriers=try PlayerSessionBarrierAdapter(files:files,pid:pid)
        transport=files;adapter=barriers
    }
    @discardableResult static func appendAppRow(_ data:Data)->Bool {
        guard let context=shared else{return false}
        do {try context.transport.appendAppRow(data);return true}catch {return false}
    }
    @discardableResult func writeAux(name:String,data:Data)->Bool {
        guard ["av-session.jsonl","input-session.jsonl"].contains(name) else{return false}
        do {_ = try sharedSink(name:name).append(data);return true}catch {return false}
    }
    /// One immutable raw-file owner for the entire player lifetime, independent
    /// of WT child generations. Each child still owns its own exit/EOF proof.
    /// Callers append synchronously but MUST NOT drain this shared sink.
    func sharedSink(name:String)throws->PlayerSessionNativeSink {
        sinkLock.lock();defer{sinkLock.unlock()}
        if let sink=sharedRawSinks[name] {return sink}
        let p=try register(kind:"raw-file",barriers:["queue-drained"])
        let sink=try makeSink(name:name,producer:p,acknowledgeDrain:{ [self] in
            try observe("queue-drained",producer:p)
        })
        sharedRawSinks[name]=sink;return sink
    }
    /// Called once before any stdout/stderr producer starts. No second writer
    /// process, no shared file fallback, no unbounded queued Data.
    func startDirectCapture()throws {
        let producer=try register(kind:"direct",barriers:["pipe-eof-tail"])
        let sink=try makeSink(name:"gor_direct.log",producer:producer,acknowledgeDrain:{ [self] in
            try observe("pipe-eof-tail",producer:producer)
        })
        let pipe=Pipe()
        directSink=sink;directPipe=pipe;directProducer=producer
        directReader.async { [self] in
            defer {directDone.signal()}
            var failed=false
            do {
                while true {
                    let bytes=try PlayerSessionPipeDrain.readAvailableChunk(pipe.fileHandleForReading)
                    if bytes.isEmpty {break}
                    if !failed {
                        do {_ = try sink.append(bytes)}catch {directFailure=error;failed=true}
                    }
                }
                // All chunks, including the final non-newline bytes, have been
                // consumed synchronously before the EOF/queue acknowledgment.
                if !failed {try sink.drain()}
            }catch {directFailure=error}
        }
        fflush(stdout);fflush(stderr)
        guard dup2(pipe.fileHandleForWriting.fileDescriptor,STDOUT_FILENO)>=0,
              dup2(pipe.fileHandleForWriting.fileDescriptor,STDERR_FILENO)>=0 else {throw PlayerSessionNativeSink.Failure.io}
        try pipe.fileHandleForWriting.close()
    }
    /// Lifecycle worker only. Missing producer evidence never becomes success.
    /// Failure leaves raw owned and lets the external death watcher publish an
    /// explicitly incomplete crash ZIP after the app can no longer write.
    func finishAfterProducerShutdown(drainDiagnostics:@escaping ()throws->Void,
                                     completion:@escaping(Result<String,Error>)->Void) {
        closeQueue.async { [self] in
            do {
                try adapter.close()
                // Child parsers still print their final rows into direct/diag.
                // Prove every child exit+EOF+tail BEFORE closing those sinks.
                let childrenDeadline=Date().addingTimeInterval(2)
                while !adapter.evidenceSatisfied(excludingKinds:["diagnostic","direct","raw-file"]),Date()<childrenDeadline {Thread.sleep(forTimeInterval:0.01)}
                guard adapter.evidenceSatisfied(excludingKinds:["diagnostic","direct","raw-file"]) else{throw PlayerSessionBarrierAdapter.Failure.barriersPending}
                fflush(stdout);fflush(stderr)
                let null=open("/dev/null",O_WRONLY)
                guard null>=0 else{throw PlayerSessionNativeSink.Failure.io}
                _ = dup2(null,STDOUT_FILENO);_ = dup2(null,STDERR_FILENO);close(null)
                if directPipe != nil {
                    directDone.wait()
                    if let directFailure {throw directFailure}
                }
                try drainDiagnostics()
                // Metadata is cheap; real pipe and queue owners deliver their
                // own evidence. No sleep is accepted as an EOF acknowledgment.
                let deadline=Date().addingTimeInterval(2)
                while Date()<deadline {
                    if adapter.evidenceSatisfied(excludingKinds:["raw-file"]) {
                        sinkLock.lock()
                        let sinks=Array(sharedRawSinks.values)
                        sinkLock.unlock()
                        for sink in sinks {try sink.drain()}
                    }
                    do {completion(.success(try adapter.finish()));return}
                    catch PlayerSessionBarrierAdapter.Failure.barriersPending {Thread.sleep(forTimeInterval:0.01)}
                }
                throw PlayerSessionBarrierAdapter.Failure.barriersPending
            }catch {completion(.failure(error))}
        }
    }
    func makeSink(name:String,producer:PlayerSessionDrainPlan.Producer,
                  acknowledgeDrain:@escaping ()throws->Void)throws->PlayerSessionNativeSink {
        let admission=try transport.admitNative(token:token,name:name,producer:producer.id.uuidString)
        return try PlayerSessionNativeSink(parent:rawRoot,admission:admission,commitStatus:{ [self] status in
            if status.capReached {try transport.nativeCapReached(token:token,name:name,producer:producer.id.uuidString)}
            if status.writeFailed {throw PlayerSessionNativeSink.Failure.io}
        },acknowledgeDrain:acknowledgeDrain)
    }
    /// For Node/child configuration only. No effect on another process's env.
    var childEnvironment:[String:String] {
        var env=ProcessInfo.processInfo.environment
        env["GOR_PLAYER_LOG_ROOT"]=rawRoot.path
        env["GOR_PLAYER_LOG_TOKEN"]=token
        return env
    }
    func register(kind:String,barriers:Set<String>)throws->PlayerSessionDrainPlan.Producer {
        try adapter.register(kind:kind,barriers:barriers)
    }
    func observe(_ barrier:String,producer:PlayerSessionDrainPlan.Producer)throws {
        try adapter.observe(barrier,producer:producer)
    }
    /// Admit only used files, before the raw producer is started.
    func admit(name:String,producer:PlayerSessionDrainPlan.Producer)throws {
        try transport.admit(token:token,name:name,producer:producer.id.uuidString)
    }
}
