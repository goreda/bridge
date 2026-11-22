// main.swift - L6 r4 consumer live run on Linux Swift 6.0.3 + the real
// GorAVDVRPU C core (header parse runs on the received copy). Fake borrow
// models the producer contract; no AVFrame, no CFFmpeg, no stubs.
import Foundation
import GorAVDVRPU

final class FakeBorrow: DVRPUFrameBorrow {
    let sessionEpoch: UInt64 = 0x1e45
    let presentationEpoch: UInt64 = 7
    let streamIndex: Int = 0
    let handle: UInt64 = 0xF1A4E
    let pts: Int64 = 42
    var fetch: DVRPUSideDataFetch
    private(set) var sawKind = -1 as Int32
    private(set) var sawMaxBytes = 0
    init(_ fetch: DVRPUSideDataFetch) { self.fetch = fetch }
    func dvFetchSideData(_ kind: Int32, maxBytes: Int) -> DVRPUSideDataFetch {
        sawKind = kind; sawMaxBytes = maxBytes
        return fetch
    }
}

struct FakeLeaseError: Error {}

let payload = [UInt8](try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let wantFnv: UInt64 = 0x5747adb14a63d5dd

func run(_ fb: FakeBorrow) -> DVRPUReadResult { DVRPUSideData.syncRead(fb) }

// case 1: real RPU -> .ok, exact owned bytes, fnv over owned copy,
// producer-reported identity, kind + bound pinned, header PARSED profile 8
let fb1 = FakeBorrow(.ok(payload))
switch run(fb1) {
case .ok(let o):
    precondition(o.bytes == payload && o.byteCount == 148, "FAIL c1 bytes")
    precondition(o.fnv1a64 == wantFnv, "FAIL c1 fnv")
    precondition(o.context.sessionEpoch == 0x1e45 && o.context.presentationEpoch == 7 && o.context.handle == 0xF1A4E
                 && o.context.streamIndex == 0 && o.context.pts == 42, "FAIL c1 identity")
    precondition(o.headerStatus == .parsed(profileGuess: 8), "FAIL c1 headerStatus \(o.headerStatus)")
    precondition(fb1.sawKind == dvRPUBufferSideDataKind && fb1.sawMaxBytes == dvRPUMaxBytes, "FAIL c1 binding")
    print("case1 ok: parsed receipt, profile guess 8, kind=\(fb1.sawKind) bound=\(fb1.sawMaxBytes)")
default: fatalError("FAIL case1 not ok")
}

// case 2: producer-PROVEN absence -> .absent (only path that may say non-DV)
switch run(FakeBorrow(.absent)) { case .absent: print("case2 ok: proven absent"); default: fatalError("FAIL case2") }

// case 3: lease-invalidated/error -> .unavailable, NEVER .absent
switch run(FakeBorrow(.unavailable(reason: "producer: borrow invalidated (post-turn access)"))) {
case .unavailable(let r): print("case3 ok: unavailable(\(r))")
default: fatalError("FAIL case3: unproven absence must not classify as absent")
}

// case 4: zero-length buffer -> .corrupt
switch run(FakeBorrow(.ok([]))) { case .corrupt(let r): print("case4 ok: corrupt(\(r))"); default: fatalError("FAIL case4") }

// case 5a: producer policy refusal -> typed oversize
switch run(FakeBorrow(.refusedOversize(size: dvRPUMaxBytes + 1, limit: dvRPUMaxBytes))) {
case .rejectedOversize(let s, let l): print("case5a ok: refused \(s)>\(l)")
default: fatalError("FAIL case5a")
}
// case 5b: NONCONFORMING producer returning > bound -> typed refusal, NO TRAP
switch run(FakeBorrow(.ok([UInt8](repeating: 0xAB, count: dvRPUMaxBytes + 1)))) {
case .rejectedOversize(let s, let l): print("case5b ok: nonconforming oversize refused \(s)>\(l), no trap")
default: fatalError("FAIL case5b: oversize must refuse typed, not trap")
}

// case 3b: producer-detected zero-length -> .corrupt, not .absent
switch run(FakeBorrow(.malformed(reason: "producer: zero-length side-data buffer"))) {
case .corrupt(let r): print("case3b ok: corrupt(\(r))")
default: fatalError("FAIL case3b: malformed must not classify as absent")
}

// case 6: corrupt bytes (valid copy, bad RPU) -> .ok receipt DEGRADED to crcMismatch
switch run(FakeBorrow(.ok([UInt8](repeating: 7, count: 64)))) {
case .ok(let o): precondition(o.headerStatus == .crcMismatch || o.headerStatus == .malformed, "FAIL c6 \(o.headerStatus)")
    print("case6 ok: receipt degraded to \(o.headerStatus)")
default: fatalError("FAIL case6")
}

// case 7: owned-copy independence - mutate producer source after scope
var src = payload
let fb7 = FakeBorrow(.ok(src))
guard case .ok(let o7) = run(fb7) else { fatalError("FAIL case7 read") }
src.withUnsafeMutableBytes { $0.baseAddress!.assumingMemoryBound(to: UInt8.self).update(repeating: 0, count: src.count) }
precondition(o7.bytes == payload && o7.fnv1a64 == wantFnv, "FAIL case7 TOCTOU")
print("case7 ok: owned copy independent of post-scope mutation")

// case 8: fnv standard vectors
precondition(dvFnv1a64([]) == 0xcbf29ce484222325, "FAIL fnv empty")
precondition(dvFnv1a64(Array("a".utf8)) == 0xaf63dc4c8601ec8c, "FAIL fnv a")
precondition(dvFnv1a64(Array("foobar".utf8)) == 0x85944171f73967e8, "FAIL fnv foobar")
print("case8 ok: fnv vectors")

// case 9: pinned kind constant is exactly 23 (verified vs pinned headers by kindcheck)
precondition(dvRPUBufferSideDataKind == 23, "FAIL kind")
print("case9 ok: kind pinned at 23 (kindcheck verifies vs FFmpeg 8.0.1 headers)")

print("SWIFTBINDING_PASS 11/11")
