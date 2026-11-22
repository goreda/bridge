// W-gdb-005 cue-batch fixture rows for cue-output-tests.
// Replays kits/cue-batch-fixtures/expected/*.json (100 ms sampling grid)
// against the pinned batch transport types (product pin
// 2112af0d60df16c5473173b664903f76ce54173e):
//   SubtitleCue, SubtitleController.CueIdentity / .Slot,
//   CueOutputEvent, SubtitleCueBatch, SubtitleCueConsumer
// Consumer-side rows (active sets, generation fencing, stale disappears,
// reset clears) replay against the REAL SubtitleCueConsumer. Producer-side
// event lists are validated for shape/ordering/identity stability here;
// full producer replay needs a SubtitleController populated with the track
// cues - that API is not pinned in the packet, see the SEAM note in
// INTEGRATION.md.
import Foundation
import GorAVSubtitles
import GorAVPlaybackCore

struct CueRowLog {
    var pass = 0
    var fail = 0
    mutating func check(_ id: String, _ ok: Bool, _ detail: String = "") {
        if ok { pass += 1 } else { fail += 1; print("ROW \(id) FAIL \(detail)") }
    }
}

enum CueBatchFixtureRows {
    private static func slot(_ s: String) -> SubtitleController.Slot { s == "primary" ? .primary : .secondary }
    private static func ident(_ a: [Int]) -> SubtitleController.CueIdentity {
        SubtitleController.CueIdentity(trackContentID: UInt64(a[0]), cueIndex: a[1])
    }

    /// Slot-aware cue resolution: indices are only unique per track, so an
    /// event's cue is looked up in ITS slot's track list (a secondary index-0
    /// must not resolve to the primary track). Script rows may carry inline
    /// "cueLines" instead of a track table.
    private static func cueFor(_ id: SubtitleController.CueIdentity, slot: String,
                               tracks: [String: [[String: Any]]], inlineLines: [String]?) -> SubtitleCue {
        if let lines = inlineLines {
            return SubtitleCue(index: id.cueIndex, startSeconds: 0, endSeconds: 0, lines: lines)
        }
        for c in tracks[slot] ?? [] where c["index"] as? Int == id.cueIndex {
            return SubtitleCue(index: id.cueIndex,
                               startSeconds: c["start"] as? Double ?? 0,
                               endSeconds: c["end"] as? Double ?? 0,
                               lines: c["lines"] as? [String] ?? [],
                               styleName: c["styleName"] as? String)
        }
        return SubtitleCue(index: id.cueIndex, startSeconds: 0, endSeconds: 0, lines: [])
    }

    /// Build the real CueOutputEvent list from a table row, resolving
    /// appeared cues slot-aware from the case's track table.
    private static func events(_ list: [[String: Any]], tracks: [String: [[String: Any]]]) -> [CueOutputEvent] {
        var out: [CueOutputEvent] = []
        for e in list {
            if let a = e["appeared"] as? [String: Any], let id = a["identity"] as? [Int] {
                let cid = ident(id)
                let slotName = a["slot"] as? String ?? "primary"
                out.append(.appeared(slot: slot(slotName), identity: cid,
                                     cue: cueFor(cid, slot: slotName, tracks: tracks,
                                                 inlineLines: a["cueLines"] as? [String])))
            } else if let d = e["disappeared"] as? [String: Any], let id = d["identity"] as? [Int] {
                out.append(.disappeared(slot: slot(d["slot"] as? String ?? "primary"), identity: ident(id)))
            }
        }
        return out
    }

    /// Payload text check: the cue carried in a constructed appeared event
    /// must equal a fresh SubtitleCue built from the same table entry. This
    /// proves the harness moves table text (incl. decomposed vs precomposed
    /// unicode) into the real payload byte-exact; the end-to-end guarantee
    /// through SubtitleCueProducer additionally needs the controller seam
    /// (INTEGRATION.md seam 2).
    private static func payloadTextOK(_ evs: [CueOutputEvent], tracks: [String: [[String: Any]]]) -> Bool {
        for e in evs {
            if case .appeared(let s, let id, let cue) = e {
                let name = s == .primary ? "primary" : "secondary"
                let fresh = cueFor(id, slot: name, tracks: tracks, inlineLines: nil)
                if tracks[name] != nil, !(fresh.lines.isEmpty && !cue.lines.isEmpty), cue != fresh { return false }
            }
        }
        return true
    }

    private static func activeMap(_ consumer: SubtitleCueConsumer) -> [String: [Int]?] {
        func pack(_ a: SubtitleCueConsumer.Active?) -> [Int]? {
            a.map { [Int($0.identity.trackContentID), $0.identity.cueIndex] }
        }
        return ["primary": pack(consumer.primary), "secondary": pack(consumer.secondary)]
    }

    /// JSON null comes through as NSNull, which fails a direct [Int]? cast;
    /// normalize explicitly so expected nulls compare equal to nil.
    private static func activeWant(_ any: Any?) -> [String: [Int]?] {
        guard let d = any as? [String: Any] else { return [:] }
        var out: [String: [Int]?] = [:]
        for (k, v) in d { out[k] = (v as? [Int]) }
        return out
    }

    static func run(packPath: String) -> (pass: Int, fail: Int) {
        var log = CueRowLog()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: packPath) else {
            print("ROW cue-batch-fixtures/pack FAIL cannot list \(packPath)")
            return (0, 1)
        }
        for file in entries.sorted() where file.hasSuffix(".json") {
            guard let data = fm.contents(atPath: (packPath as NSString).appendingPathComponent(file)),
                  let table = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = table["case"] as? String,
                  let session = (table["session"] as? Int).map(UInt64.init) else { continue }
            let tracks = table["tracks"] as? [String: [[String: Any]]] ?? [:]

            // script rows: drive the real consumer directly
            if let script = table["script"] as? [[String: Any]] {
                var consumer = SubtitleCueConsumer(session: session)
                var sequence: UInt64 = 0
                for (i, step) in script.enumerated() {
                    guard let b = step["batch"] as? [String: Any],
                          let gen = (b["generation"] as? Int).map(UInt64.init) else { continue }
                    sequence += 1
                    let batch = SubtitleCueBatch(session: session, generation: gen, sequence: sequence,
                                                 reset: b["reset"] as? Bool ?? false,
                                                 closed: b["closed"] as? Bool ?? false,
                                                 events: events(b["events"] as? [[String: Any]] ?? [], tracks: tracks))
                    let got = consumer.consume(batch)
                    log.check("\(name)/script[\(i)]/consume", got == (step["expectConsume"] as? Bool ?? false),
                              "consume -> \(got)")
                    let want = activeWant(step["expectActive"])
                    log.check("\(name)/script[\(i)]/active", activeMap(consumer) == want,
                              "active -> \(activeMap(consumer)) want \(want)")
                }
            }

            // per-sample rows: validate event shape/ordering, then fold the
            // emitted batches through the real consumer and compare the
            // active-set table (this is what MetalPresenter would render).
            if let samples = table["samples"] as? [[String: Any]] {
                var consumer = SubtitleCueConsumer(session: session)
                var sequence: UInt64 = 0
                for (i, srow) in samples.enumerated() {
                    let rid = "\(name)/sample[\(i)]@\(srow["tMs"] ?? -1)ms"
                    let ev = srow["events"] as? [[String: Any]] ?? []
                    // ordering invariant: per slot, disappeared precedes its replacement
                    var appearedSlots = Set<String>()
                    var orderOK = true
                    for e in ev {
                        if let a = e["appeared"] as? [String: Any] { appearedSlots.insert(a["slot"] as? String ?? "") }
                        if let d = e["disappeared"] as? [String: Any], appearedSlots.contains(d["slot"] as? String ?? "") { orderOK = false }
                    }
                    log.check(rid + "/order", orderOK, "disappeared after appeared for same slot")
                    if !ev.isEmpty {
                        sequence += 1
                        let evs = events(ev, tracks: tracks)
                        log.check(rid + "/cueText", payloadTextOK(evs, tracks: tracks),
                                  "appeared payload text diverges from track table")
                        let batch = SubtitleCueBatch(session: session, generation: 0, sequence: sequence,
                                                     reset: false, events: evs)
                        log.check(rid + "/consume", consumer.consume(batch), "consumer refused in-generation batch")
                    }
                    let want = activeWant(srow["active"])
                    log.check(rid + "/active", activeMap(consumer) == want,
                              "active -> \(activeMap(consumer)) want \(want)")
                }
            }
            // SEAM (INTEGRATION.md): producer-side replay of `samples`
            // against SubtitleCueProducer.sample(session:generation:filmTime:controller:)
            // needs a SubtitleController carrying each slot's track; that
            // construction API is not pinned in the packet excerpts.
        }
        print("cue-batch-fixture-rows: \(log.pass) PASS, \(log.fail) FAIL")
        return (log.pass, log.fail)
    }
}
