import Foundation

/// P29-ADMISSION (DR-0018): typed Swift re-expression of photon-admission.lua
/// (instinct main archive/gor/Resources/vendor/mpv/scripts/photon-admission.lua,
/// SHA256 c485661b006fbc1aa7e6bbcc144cd3cbe358785179e72eecbb2f38e08f7c6943).
/// Protocol semantics mirror the source exactly: same limits, fences, receipt
/// fields, rejection reasons, HOLD behaviour and persistence codec. No Lua
/// runtime is introduced. The player's sole open authority is preserved: this
/// type never opens media and never writes a parameter itself - the host binds
/// `apply`, and receipts assert host parameter acceptance, never GPU or
/// physical user identity.
public enum PhotonAdmission {
    public static let version = 1

    /// Source ranges/count and selected admission floor, not newly calibrated
    /// adaptive values. learningSamples/lookMin/lookMax are preserved source
    /// values, not calibration.
    public enum Limits {
        public static let multFloor = 0.5
        public static let multCeiling = 8.0
        public static let manualMin = 0.0
        public static let manualMax = 30.0
        public static let lookMin = 0.0
        public static let lookMax = 100.0
        public static let learningSamples = 3
    }

    public static func finite(_ v: Double) -> Bool { v.isFinite }
    static func isInteger(_ v: Double) -> Bool { v.isFinite && v >= 0 && v.truncatingRemainder(dividingBy: 1) == 0 }

    /// A bound document identity. gen is a non-negative integer in the source.
    public struct Document: Equatable, Sendable {
        public let gen: Int
        public let name: String
        public init(gen: Int, name: String) { self.gen = gen; self.name = name }
        public var valid: Bool { gen >= 0 && !name.isEmpty }
    }

    /// One auto command (source version 2).
    public struct Command: Equatable, Sendable {
        public let doc: Document
        public let id: Int
        public let revision: Int
        public let serialFloor: Int
        public let mult: Double
        public let expectedStrength: Double
        public init(doc: Document, id: Int, revision: Int, serialFloor: Int, mult: Double, expectedStrength: Double) {
            self.doc = doc; self.id = id; self.revision = revision; self.serialFloor = serialFloor
            self.mult = mult; self.expectedStrength = expectedStrength
        }
        /// The duplicate-detection signature: exact identity of every field,
        /// mult/expected as %.17g like the source's string.format.
        var signature: String {
            [String(doc.gen), doc.name, String(id), String(revision), String(serialFloor),
             String(format: "%.17g", mult), String(format: "%.17g", expectedStrength)].joined(separator: "\0")
        }
    }

    public enum Status: String, Equatable, Sendable { case applied = "APPLIED", noop = "NOOP", rejected = "REJECTED" }

    /// The receipt (source version 2). docGen/docName/commandId are nil only on
    /// the malformed path where no valid command/document was decoded.
    public struct Receipt: Equatable, Sendable {
        public let docGen: Int?
        public let docName: String?
        public let commandId: Int?
        public let revision: Int
        public let serial: Int
        public let status: Status
        public let reason: String?
        public let origin: String?
        public let acceptedStrength: Double
        public let base: Double
        public init(docGen: Int?, docName: String?, commandId: Int?, revision: Int, serial: Int,
                    status: Status, reason: String?, origin: String?, acceptedStrength: Double, base: Double) {
            self.docGen = docGen; self.docName = docName; self.commandId = commandId
            self.revision = revision; self.serial = serial; self.status = status
            self.reason = reason; self.origin = origin
            self.acceptedStrength = acceptedStrength; self.base = base
        }
    }

    public struct TraceEvent: Equatable, Sendable {
        public let kind: String
        public let clock: String
        public let t: Double
        public let fields: [String: String]
    }

    /// Bounded, in-memory diagnostics. No frame bytes, names, URLs or blocking IO.
    public final class Ring {
        public let capacity: Int
        public private(set) var count = 0
        public private(set) var dropped = 0
        private var head = 0
        private var data: [Int: [String: String]] = [:]
        public init(capacity: Int) {
            precondition(capacity > 0, "explicit positive ring capacity required")
            self.capacity = capacity
        }
        public func record(_ event: [String: String]) {
            head = head % capacity + 1
            if count == capacity { dropped += 1 } else { count += 1 }
            data[head] = event
        }
        public func snapshot() -> (events: [[String: String]], dropped: Int) {
            var out: [[String: String]] = []
            var i = 1
            while i <= count {
                let index = (head - count + i - 1 + capacity * 2) % capacity + 1
                if let e = data[index] { out.append(e) }
                i += 1
            }
            return (out, dropped)
        }
    }

    // MARK: - Receiver

    public final class Receiver {
        public let base: Double
        public private(set) var revision = 0
        public private(set) var serial = 0
        public private(set) var actionSeq = 0
        public private(set) var commandHigh = 0
        public private(set) var doc: Document?
        public private(set) var enabled = false
        public private(set) var suppressed = false
        public private(set) var acceptedStrength: Double

        public struct ManualAction: Equatable, Sendable {
            public let doc: Document
            public let actionId: Int
            public let revision: Int
            public let strength: Double
            public let kind: String   // "strength"
            public let origin: String // "MANUAL_STRENGTH"
            public fileprivate(set) var resumed: Bool
            public init(doc: Document, actionId: Int, revision: Int, strength: Double, kind: String, origin: String, resumed: Bool) {
                self.doc = doc; self.actionId = actionId; self.revision = revision
                self.strength = strength; self.kind = kind; self.origin = origin; self.resumed = resumed
            }
        }
        public private(set) var manual: ManualAction?

        private let cacheCapacity: Int
        private let apply: (Double) -> Bool
        private let clock: () -> Double
        private let trace: ((TraceEvent) -> Void)?
        private var cache: [Int: (signature: String, receipt: Receipt)] = [:]
        private var order: [Int] = []

        public init(base: Double, cacheCapacity: Int,
                    apply: @escaping (Double) -> Bool, clock: @escaping () -> Double,
                    trace: ((TraceEvent) -> Void)? = nil) {
            precondition(PhotonAdmission.finite(base) && base > 0)
            precondition(cacheCapacity > 0)
            self.base = base; self.cacheCapacity = cacheCapacity
            self.apply = apply; self.clock = clock; self.trace = trace
            self.acceptedStrength = base
        }

        private func log(_ kind: String, _ fields: [String: String] = [:]) {
            trace?(TraceEvent(kind: kind, clock: "receiver", t: clock(), fields: fields))
        }
        private func receipt(_ c: Command?, status: Status, reason: String?, origin: String?) -> Receipt {
            Receipt(docGen: doc?.gen, docName: doc?.name, commandId: c?.id, revision: revision,
                    serial: serial, status: status, reason: reason, origin: origin,
                    acceptedStrength: acceptedStrength, base: base)
        }
        private func emit(_ v: Receipt) -> Receipt {
            log("ACK_SEND", ["command_id": v.commandId.map(String.init) ?? "", "revision": String(v.revision),
                             "status": v.status.rawValue, "reason": v.reason ?? ""])
            return v
        }

        /// Bind a document. Same identity cannot reset high-water fences or
        /// revision; returns false then. A different document resets fully.
        @discardableResult
        public func bind(_ newDoc: Document, enabled: Bool) -> Bool {
            precondition(newDoc.valid)
            if let d = doc, d == newDoc { return false }
            doc = newDoc; revision = 0; serial = 0; actionSeq = 0; commandHigh = 0
            cache = [:]; order = []; manual = nil; suppressed = false; self.enabled = enabled
            log("RESET", ["doc_gen": String(newDoc.gen)])
            return true
        }

        /// Same-document invalidation: revision advances, manual/suppression
        /// clear. High-water and cached receipts survive.
        public func invalidate(reason: String, enabled: Bool? = nil) {
            revision += 1; manual = nil; suppressed = false
            if let enabled { self.enabled = enabled }
            log("RESET", ["doc_gen": doc.map { String($0.gen) } ?? "", "revision": String(revision), "reason": reason])
        }

        public func publish() -> Int { serial += 1; return serial }

        public func auto(_ command: Command?) -> Receipt {
            log("RECEIVE", ["command_id": command.map { String($0.id) } ?? ""])
            guard let c = command, c.doc.valid, c.id >= 1, c.revision >= 0, c.serialFloor >= 0,
                  PhotonAdmission.finite(c.mult),
                  c.mult >= Limits.multFloor, c.mult <= Limits.multCeiling,
                  PhotonAdmission.finite(c.expectedStrength) else {
                return emit(receipt(command, status: .rejected, reason: "malformed", origin: nil))
            }
            guard c.doc == doc else { return emit(receipt(c, status: .rejected, reason: "document", origin: nil)) }
            let sig = c.signature
            if let old = cache[c.id] {
                if old.signature != sig { return emit(receipt(c, status: .rejected, reason: "duplicate-conflict", origin: nil)) }
                return emit(old.receipt)
            }
            if c.id <= commandHigh { return emit(receipt(c, status: .rejected, reason: "stale-evicted", origin: nil)) }
            commandHigh = c.id
            var reason: String?
            if c.revision != revision { reason = "revision" }
            else if c.serialFloor > serial { reason = "serial" }
            else if !enabled { reason = "disabled" }
            else if suppressed { reason = "manual-override" }
            else if c.expectedStrength != base * c.mult { reason = "base-mismatch" }
            else if c.expectedStrength < Limits.manualMin || c.expectedStrength > Limits.manualMax { reason = "host-range" }
            let v: Receipt
            if let reason {
                v = receipt(c, status: .rejected, reason: reason, origin: nil)
            } else {
                let accepted = base * c.mult
                if accepted == acceptedStrength {
                    v = receipt(c, status: .noop, reason: nil, origin: "AUTO_COMMAND")
                } else if apply(accepted) != true {
                    // Adapter must apply the exact value without clamping and
                    // return true only after host acceptance.
                    v = receipt(c, status: .rejected, reason: "apply-failed", origin: nil)
                } else {
                    acceptedStrength = accepted; revision += 1
                    v = receipt(c, status: .applied, reason: nil, origin: "AUTO_COMMAND")
                }
            }
            cache[c.id] = (sig, v)
            order.append(c.id)
            if order.count > cacheCapacity { cache[order.removeFirst()] = nil }
            log(v.status.rawValue, ["command_id": String(c.id), "revision": String(revision),
                                    "accepted_strength": String(acceptedStrength)])
            return emit(v)
        }

        /// Only the actual validated manual handler may invoke this method.
        public func manualStrength(_ value: Double) -> (action: ManualAction?, error: String?) {
            guard doc != nil, enabled, PhotonAdmission.finite(value) else { return (nil, "invalid-manual") }
            let clamped = max(Limits.manualMin, min(Limits.manualMax, value)) // Existing manual range, not adaptive tuning.
            guard apply(clamped) == true else { return (nil, "apply-failed") }
            acceptedStrength = clamped; revision += 1; actionSeq += 1
            suppressed = true
            let action = ManualAction(doc: doc!, actionId: actionSeq, revision: revision,
                                      strength: clamped, kind: "strength", origin: "MANUAL_STRENGTH", resumed: false)
            manual = action
            log("MANUAL_ACCEPT", ["action_id": String(actionSeq), "revision": String(revision),
                                  "accepted_strength": String(clamped)])
            return (action, nil)
        }

        public func resume(doc resumeDoc: Document, actionId: Int, revision resumeRevision: Int) -> (ok: Bool, error: String?) {
            guard enabled, let m = manual, resumeDoc == doc,
                  actionId == m.actionId, resumeRevision == revision else { return (false, "stale-resume") }
            if m.resumed { return (true, "duplicate") }
            suppressed = false; manual?.resumed = true
            log("RESUME", ["action_id": String(actionId), "revision": String(resumeRevision)])
            return (true, nil)
        }
    }

    // MARK: - Sender

    public final class Sender {
        public enum State: String, Equatable, Sendable {
            case unbound = "UNBOUND", ready = "READY", holdUnresolved = "HOLD_UNRESOLVED",
                 autoPending = "AUTO_PENDING", manual = "MANUAL"
        }
        public private(set) var state: State = .unbound
        public private(set) var seq = 0
        public private(set) var serial = 0
        public private(set) var revision = 0
        public private(set) var reason: String?
        public private(set) var doc: Document?
        public private(set) var lookR: Double?
        public private(set) var rejected: Receipt?
        public private(set) var receiverSuppressionUnresolved = false

        private let clock: () -> Double
        private let timeout: Double?
        private let manualIdentityBound: Bool
        private let save: ((Double, Receiver.ManualAction) -> Bool)?
        private let resumeFn: ((Document, Int, Int) -> Bool)?
        private let trace: ((TraceEvent) -> Void)?
        private var base = 0.0
        private var pending: (command: Command, sentAt: Double)?
        private var learner: (action: Receiver.ManualAction, values: [Double], scene: Int?)?

        public init(clock: @escaping () -> Double, timeout: Double? = nil,
                    manualIdentityBound: Bool = false,
                    save: ((Double, Receiver.ManualAction) -> Bool)? = nil,
                    resume: ((Document, Int, Int) -> Bool)? = nil,
                    trace: ((TraceEvent) -> Void)? = nil) {
            self.clock = clock; self.timeout = timeout; self.manualIdentityBound = manualIdentityBound
            self.save = save; self.resumeFn = resume; self.trace = trace
        }

        private func log(_ kind: String, _ fields: [String: String] = [:]) {
            trace?(TraceEvent(kind: kind, clock: "sender", t: clock(), fields: fields))
        }

        @discardableResult
        public func bind(_ newDoc: Document, revision: Int, serial: Int, base: Double) -> Bool {
            guard newDoc.valid, revision >= 0, serial >= 0, PhotonAdmission.finite(base), base > 0 else { return false }
            if let d = doc, d == newDoc { return false }
            doc = newDoc; self.revision = revision; self.serial = serial; self.base = base; seq = 0
            pending = nil; learner = nil; state = .ready
            return true
        }

        public func hold(reason newReason: String) {
            state = .holdUnresolved; pending = nil; learner = nil; reason = newReason
            receiverSuppressionUnresolved = true
            log("HOLD", ["reason": newReason, "doc_gen": doc.map { String($0.gen) } ?? ""])
        }

        public func send(_ mult: Double) -> (command: Command?, error: String?) {
            guard state == .ready, PhotonAdmission.finite(mult),
                  mult >= Limits.multFloor, mult <= Limits.multCeiling, let d = doc else { return (nil, nil) }
            let expected = base * mult
            if expected < Limits.manualMin || expected > Limits.manualMax {
                log("SEND_SKIPPED", ["reason": "host-range", "mult": String(mult), "expected_strength": String(expected)])
                return (nil, "host-range")
            }
            seq += 1
            let c = Command(doc: d, id: seq, revision: revision, serialFloor: serial,
                            mult: mult, expectedStrength: expected)
            pending = (c, clock()); state = .autoPending
            log("SEND", ["command_id": String(c.id), "revision": String(c.revision), "mult": String(mult)])
            return (c, nil)
        }

        @discardableResult
        public func ack(_ a: Receipt) -> Bool {
            guard let p = pending else { log("ACK_IGNORED"); return false }
            let c = p.command
            if a.commandId == c.id, a.docGen == doc?.gen, a.docName == doc?.name, a.status == .rejected {
                // Rejection is not application. Keep explicit HOLD until separately
                // source-bound reconciliation; never retry over a new manual action.
                rejected = a; hold(reason: "rejected:" + (a.reason ?? "")); return false
            }
            guard a.commandId == c.id, a.docGen == doc?.gen, a.docName == doc?.name,
                  a.revision >= 0, a.serial >= 0, a.serial >= c.serialFloor,
                  a.origin == "AUTO_COMMAND", a.base == base,
                  a.acceptedStrength == c.expectedStrength,
                  (a.status == .applied && a.revision == c.revision + 1) || (a.status == .noop && a.revision == c.revision)
            else { hold(reason: "invalid-ack"); return false }
            revision = a.revision; serial = a.serial
            pending = nil; state = .ready; reason = nil
            log("ACK_RECEIVE", ["command_id": String(a.commandId ?? -1), "revision": String(a.revision),
                                "latency": String(clock() - p.sentAt)])
            return true
        }

        public func timeoutTick() {
            // No invented production T. Unqualified timeout remains pending/HOLD.
            guard let p = pending else { return }
            guard let t = timeout, t > 0 else {
                log("STALL", ["command_id": String(p.command.id), "age": String(clock() - p.sentAt), "unqualified": "true"])
                return
            }
            if clock() - p.sentAt >= t { hold(reason: "timeout") }
        }

        public func diagnostics() -> (state: State, reason: String?, receiverSuppressionUnresolved: Bool, rejectedReason: String?) {
            (state, reason, receiverSuppressionUnresolved, rejected?.reason)
        }

        /// Caller must pass a source-bound receiver receipt, not numeric
        /// disagreement. No automatic reconcile: a new source-bound lifecycle
        /// decision must establish READY; same-document rebind cannot bypass HOLD.
        @discardableResult
        public func manual(_ a: Receiver.ManualAction) -> Bool {
            guard manualIdentityBound else { hold(reason: "manual-identity-unbound"); return false }
            guard let d = doc, a.doc == d, a.origin == "MANUAL_STRENGTH", a.kind == "strength",
                  a.actionId >= 1, a.revision > revision, PhotonAdmission.finite(a.strength)
            else { hold(reason: "invalid-manual"); return false }
            pending = nil; revision = a.revision; state = .manual
            learner = (a, [], nil)
            return true
        }

        @discardableResult
        public func sample(_ value: Double, scene: Int?, revisionAfter: Int) -> Bool {
            guard state == .manual, var l = learner, PhotonAdmission.finite(value),
                  value > Limits.lookMin, value < Limits.lookMax,
                  let scene, revisionAfter == l.action.revision else { hold(reason: "learning-fence"); return false }
            if let s = l.scene, s != scene { hold(reason: "scene-change"); return false }
            l.scene = scene; l.values.append(value); learner = l
            guard l.values.count >= Limits.learningSamples else { return false } // Preserved existing count.
            let learned = l.values.sorted()[1] // median of 3 (source index 2, 1-based)
            guard save?(learned, l.action) == true else { hold(reason: "save-failed"); return false }
            guard resumeFn?(l.action.doc, l.action.actionId, l.action.revision) == true else { hold(reason: "resume-failed"); return false }
            lookR = learned; learner = nil; state = .ready; reason = nil
            receiverSuppressionUnresolved = false
            log("LOOK_LEARNED", ["action_id": String(l.action.actionId)])
            return true
        }
    }

    // MARK: - Persistence codec

    /// New namespace only. The IO adapter must atomically persist and report
    /// failures; atomic rename is not fsync, and there is a single writer.
    public static let namespace = "~~state/gor_look_manual_v2.txt"
    public static let schema = "manual-action-v2"

    public static func decodeLook(_ text: String) -> Double? {
        let prefix = schema + "\n"
        guard text.hasPrefix(prefix), text.hasSuffix("\n") else { return nil }
        let body = text.dropFirst(prefix.count).dropLast()
        guard !body.isEmpty, !body.contains("\n") else { return nil }
        var end = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 1)
        defer { end.deallocate() }
        let value = String(body).withCString { strtod($0, end) }
        guard end.pointee != nil && end.pointee!.pointee == 0 else { return nil }
        guard finite(value), value > Limits.lookMin, value < Limits.lookMax else { return nil }
        return value
    }

    public static func encodeLook(_ value: Double) -> String? {
        guard finite(value), value > Limits.lookMin, value < Limits.lookMax else { return nil }
        return schema + "\n" + String(format: "%.17g", value) + "\n"
    }
}
