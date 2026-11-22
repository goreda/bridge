import Foundation
import GorAVPlaybackCore

// Witness for row 195b-55: register/deregister, typed snapshots, duplicate
// refusal with receipt, lifecycle marking, session invalidation fencing,
// ordering by registration sequence.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

var inv = DecoderInventory()
let v7 = DecoderIdentity(session: 7, handle: 1)
let a7 = DecoderIdentity(session: 7, handle: 2)
let v8 = DecoderIdentity(session: 8, handle: 1)

// T1: register + snapshot
check("T1-register", inv.register(v7, kind: .videoSoftware, codec: "h264") == .registered)
let s1 = inv.snapshot(v7)
check("T1-snapshot", s1?.kind == .videoSoftware && s1?.codec == "h264"
      && s1?.lifecycle == .open && s1?.registrationSeq == 1)

// T2: duplicate refused, receipted, original wins
check("T2-dup", inv.register(v7, kind: .audioSoftware, codec: "aac") == .duplicateRefused
      && inv.duplicateRegistrations == 1)
check("T2-original-wins", inv.snapshot(v7)?.kind == .videoSoftware)

// T3: ordering across registrations
_ = inv.register(a7, kind: .audioSoftware, codec: "aac")
_ = inv.register(v8, kind: .videoSoftware, codec: "hevc")
let act7 = inv.activeSnapshots(session: 7)
check("T3-order", act7.map { $0.identity.handle } == [1, 2])

// T4: lifecycle marking
inv.mark(a7, .draining)
check("T4-lifecycle", inv.snapshot(a7)?.lifecycle == .draining)
inv.mark(DecoderIdentity(session: 9, handle: 9), .failed) // unknown: no crash, no entry
check("T4-unknown-mark", inv.snapshot(DecoderIdentity(session: 9, handle: 9)) == nil)

// T5: activeSnapshots excludes closed, includes failed (it happened)
inv.mark(a7, .closed)
check("T5-closed-excluded", inv.activeSnapshots(session: 7).map { $0.identity.handle } == [1])
inv.mark(a7, .failed) // re-mark after closed is caller error but must not corrupt
check("T5b-snapshot-survives", inv.snapshot(a7)?.lifecycle == .failed)

// T6: deregister
check("T6-dereg", inv.deregister(a7) && inv.deregistrations == 1)
check("T6-gone", inv.snapshot(a7) == nil && !inv.deregister(a7))

// T7: session invalidation fences everything for that session
inv.invalidateSession(7)
check("T7-fenced", inv.snapshot(v7) == nil && inv.activeSnapshots(session: 7).isEmpty)
check("T7-other-session-live", inv.activeSnapshots(session: 8).count == 1)

// T8: invalidated generations are terminal; stale registrations cannot revive them.
check("T8-stale-register-refused", inv.register(v7, kind: .videoSoftware, codec: "h264") == .refusedInvalidatedSession)
check("T8-remains-fenced", inv.snapshot(v7) == nil && inv.activeSnapshots(session: 7).isEmpty)
let v9 = DecoderIdentity(session: 9, handle: 1)
check("T8-new-generation-registers", inv.register(v9, kind: .videoSoftware, codec: "h264") == .registered)
check("T8-seq-monotonic", inv.snapshot(v9)!.registrationSeq > inv.snapshot(v8)!.registrationSeq)

// 195b-59: serialized multi-decoder metadata store, not container inventory.
let store=DecoderInventoryStore()
let live=store.register(session:100,kind:.videoSoftware,codec:"h264",sourceID:"opaque-video-1",revisionAtOpen:1)!
let liveAudio=store.register(session:100,kind:.audioSoftware,codec:"aac",sourceID:"opaque-audio-1",revisionAtOpen:1)!
check("store-composite-handles",live != liveAudio)
check("store-open-identity",store.snapshot(live)?.sourceID == "opaque-video-1" && store.snapshot(live)?.revisionAtOpen == 1)
store.deregister(live)
check("store-close-drops-only-owner",store.snapshot(live) == nil && store.snapshot(liveAudio) != nil)
store.deregister(live)
let replacement=store.register(session:100,kind:.videoSoftware,codec:"hevc",sourceID:"opaque-video-2",revisionAtOpen:1)!
check("store-replacement-not-stale",replacement != live && store.snapshot(live) == nil)
store.invalidateSession(100)
check("store-invalidate-all",store.activeSnapshots(session:100).isEmpty)
check("store-stale-reregister-refused",store.register(session:100,kind:.videoSoftware,codec:"h264",sourceID:"old",revisionAtOpen:1) == nil)
check("store-zero-session-refused",store.register(session:0,kind:.videoSoftware,codec:"h264",sourceID:"x",revisionAtOpen:1) == nil)
check("store-zero-revision-refused",store.register(session:101,kind:.videoSoftware,codec:"h264",sourceID:"x",revisionAtOpen:0) == nil)
let lock=NSLock()
var ids:[DecoderIdentity]=[]
DispatchQueue.concurrentPerform(iterations:100) { n in
    if let id=store.register(session:101,kind:.videoSoftware,codec:"h264",sourceID:"opaque-\(n)",revisionAtOpen:1) {
        lock.lock(); ids.append(id); lock.unlock()
    }
}
check("store-concurrent-identities",Set(ids).count == 100 && store.activeSnapshots(session:101).count == 100)
for id in ids { store.deregister(id) }
check("store-concurrent-clean",store.activeSnapshots(session:101).isEmpty)

print("decoder-inventory-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
