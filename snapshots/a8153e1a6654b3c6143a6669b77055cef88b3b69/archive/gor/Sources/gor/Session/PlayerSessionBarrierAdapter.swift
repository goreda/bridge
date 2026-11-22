import Foundation

/// Serialized bridge from real per-child evidence to the helper's one-bit drain.
/// Run on a lifecycle worker, never the AppKit main queue. This owns no child
/// termination policy and must be called before admitting or launching a child.
protocol PlayerSessionFileCommands:AnyObject {
    func begin(token:String,pid:Int32,producers:[String])throws
    func register(token:String,producer:String)throws
    func setClosing(token:String)throws
    func markDrained(token:String,producer:String)throws
    func publish(token:String,crash:Bool)throws->String
}
final class PlayerSessionBarrierAdapter {
    enum Failure:Error {case invalidRegistration,closed,barriersPending,invalidEvidence}
    private let lock=NSRecursiveLock()
    private let plan:PlayerSessionDrainPlan
    private let files:PlayerSessionFileCommands
    let token:String
    let diagnostic:PlayerSessionDrainPlan.Producer
    private var closing=false
    private var finalized=false
    private var sent:Set<UUID>=[]
    init(files:PlayerSessionFileCommands,pid:Int32)throws {
        let p=PlayerSessionDrainPlan()
        plan=p;self.files=files;token=p.session.uuidString.replacingOccurrences(of:"-",with:"").lowercased()
        diagnostic=p.register(kind:"diagnostic",barriers:["queue-drained"])!
        try files.begin(token:token,pid:pid,producers:[diagnostic.id.uuidString])
    }
    func register(kind:String,barriers:Set<String>)throws->PlayerSessionDrainPlan.Producer {
        lock.lock();defer{lock.unlock()}
        guard !closing,!finalized else{throw Failure.closed}
        guard !kind.isEmpty,!barriers.isEmpty,!barriers.contains("") else{throw Failure.invalidRegistration}
        let id=UUID()
        // Register externally before adding native pending state. A refused
        // registration cannot leave a phantom native producer behind.
        try files.register(token:token,producer:id.uuidString)
        guard let p=plan.register(kind:kind,barriers:barriers,id:id) else{throw Failure.invalidRegistration}
        return p
    }
    func observe(_ barrier:String,producer:PlayerSessionDrainPlan.Producer)throws {
        lock.lock();defer{lock.unlock()}
        guard !finalized,plan.observed(barrier,producer:producer) else{throw Failure.invalidEvidence}
        if closing {try flushReady()}
    }
    func close()throws {
        lock.lock();defer{lock.unlock()}
        guard !finalized else{throw Failure.closed}
        if !closing {
            try files.setClosing(token:token)
            precondition(plan.beginClose());closing=true
        }
        try flushReady()
    }
    private func flushReady()throws {
        for p in plan.satisfiedProducers() where !sent.contains(p.id) {
            try files.markDrained(token:token,producer:p.id.uuidString)
            sent.insert(p.id)
        }
    }
    func evidenceSatisfied(excludingKinds:Set<String> = [])->Bool {
        lock.lock();defer{lock.unlock()}
        return plan.allSatisfied(excludingKinds:excludingKinds)
    }
    func finish(crash:Bool=false)throws->String {
        lock.lock();defer{lock.unlock()}
        guard !finalized else{throw Failure.closed}
        if !crash {
            guard closing,plan.allSatisfied else{throw Failure.barriersPending}
            try flushReady()
        }
        // A failed publication is retryable. Do not retire native state first.
        let path=try files.publish(token:token,crash:crash)
        guard plan.finish(crash:crash) != nil else{throw Failure.barriersPending}
        finalized=true;return path
    }
}
