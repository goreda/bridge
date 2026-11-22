import Foundation

///199bh: per-player immutable producer barriers. This file owns no UI or child
///termination policy. Callers must report actual exit/EOF/queue-barrier evidence.
final class PlayerSessionDrainPlan {
    struct Producer: Hashable {
        let session: UUID
        let id: UUID
        let kind: String
    }
    struct Finish {
        let session: UUID
        let complete: Bool
        let missing: [String]
    }
    private let lock=NSLock()
    let session: UUID
    private var closing=false
    private var finished=false
    private var producers:[Producer:Set<String>]=[:]
    private var required:[Producer:Set<String>]=[:]
    init(session:UUID=UUID()) {self.session=session}
    func register(kind:String,barriers:Set<String>,id:UUID=UUID())->Producer? {
        lock.lock();defer{lock.unlock()}
        guard !closing,!finished,!kind.isEmpty,!barriers.isEmpty else{return nil}
        let p=Producer(session:session,id:id,kind:kind)
        producers[p]=[];required[p]=barriers
        return p
    }
    func observed(_ barrier:String,producer:Producer)->Bool {
        lock.lock();defer{lock.unlock()}
        guard !finished,producer.session==session,
              required[producer]?.contains(barrier)==true else{return false}
        producers[producer,default:[]].insert(barrier)
        return true
    }
    func satisfiedProducers()->[Producer] {
        lock.lock();defer{lock.unlock()}
        return required.compactMap { p,wanted in wanted.isSubset(of:producers[p] ?? []) ? p:nil }
    }
    var allSatisfied:Bool {
        lock.lock();defer{lock.unlock()}
        return required.allSatisfy { p,wanted in wanted.isSubset(of:producers[p] ?? []) }
    }
    func allSatisfied(excludingKinds:Set<String>)->Bool {
        lock.lock();defer{lock.unlock()}
        return required.allSatisfy { p,wanted in
            excludingKinds.contains(p.kind) || wanted.isSubset(of:producers[p] ?? [])
        }
    }
    func beginClose()->Bool {
        lock.lock();defer{lock.unlock()}
        guard !closing,!finished else{return false}
        closing=true;return true
    }
    func finish(crash:Bool=false)->Finish? {
        lock.lock();defer{lock.unlock()}
        guard !finished,(closing || crash) else{return nil}
        let missing=required.flatMap {p,wanted in
            wanted.subtracting(producers[p] ?? []).map{p.kind+":"+p.id.uuidString+":"+$0}
        }.sorted()
        guard crash || missing.isEmpty else{return nil}
        finished=true
        return Finish(session:session,complete:!crash && missing.isEmpty,missing:missing)
    }
}
