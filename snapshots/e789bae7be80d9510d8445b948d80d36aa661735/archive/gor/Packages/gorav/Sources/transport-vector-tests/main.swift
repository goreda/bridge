import Foundation

// W-gdb-027 transport truthfulness vectors, Swift side.
// NOT_RUN: authored without a Swift toolchain, against the pinned excerpt only
// (product repo private). This file does NOT import GorAVFFmpegAdapter, so it
// models capture() over raw AVIO observations. Integration step for the owner:
// replace `Candidate.reference` with a call that builds an AVIOContext fixture
// and calls ActiveTransportSnapshot.capture (needs @testable import).

struct RawObs { let bytesRead: Int64; let bufAvail: Int64; let eofReached: Int32; let error: Int32 }
struct Fields: Equatable {
    var bytesRead: Int64?; var bufferAvailableBytes: Int?; var eofObserved: Bool?; var errorCode: Int32?
}
struct Row { let id: String; let obs: RawObs?; let expect: Fields }

typealias Candidate = (RawObs?) -> Fields

// Mirrors the pinned excerpt: nil means unavailable, never zero or false.
let reference: Candidate = { o in
    guard let o = o else { return Fields(bytesRead: nil, bufferAvailableBytes: nil, eofObserved: nil, errorCode: nil) }
    return Fields(bytesRead: o.bytesRead >= 0 ? o.bytesRead : nil,
                  bufferAvailableBytes: o.bufAvail >= 0 ? Int(o.bufAvail) : nil,
                  eofObserved: o.eofReached != 0 ? true : nil,
                  errorCode: o.error < 0 ? o.error : nil)
}
// Mutants (behavioural negative controls), one per targeted rule.
let mutErrZero: Candidate = { o in var f = reference(o); if o != nil, f.errorCode == nil { f.errorCode = 0 }; return f }
let mutErrPositive: Candidate = { o in var f = reference(o); if let o = o, o.error != 0 { f.errorCode = o.error }; return f }
let mutErrDropped: Candidate = { o in var f = reference(o); f.errorCode = nil; return f }
let mutEofEq1: Candidate = { o in var f = reference(o); if let o = o { f.eofObserved = o.eofReached == 1 ? true : nil }; return f }
let mutNilPbZero: Candidate = { o in o == nil ? Fields(bytesRead: 0, bufferAvailableBytes: 0, eofObserved: nil, errorCode: nil) : reference(o) }
let mutNegCounterZero: Candidate = { o in var f = reference(o); if let o = o, o.bytesRead < 0 { f.bytesRead = 0 }; return f }
// Seeded inferred-value candidate: guesses eof=false when not reported.
let seededEofFalse: Candidate = { o in
    var f = reference(o)
    if let o = o, o.eofReached == 0 { f.eofObserved = false }
    return f
}

func F(_ b: Int64?, _ a: Int?, _ e: Bool?, _ c: Int32? = nil) -> Fields {
    Fields(bytesRead: b, bufferAvailableBytes: a, eofObserved: e, errorCode: c)
}
let rows: [Row] = [
    Row(id: "F1-file-1000-read1", obs: RawObs(bytesRead: 400, bufAvail: 600, eofReached: 0, error: 0), expect: F(400, 600, nil)),
    Row(id: "F2-file-1000-read2", obs: RawObs(bytesRead: 800, bufAvail: 200, eofReached: 0, error: 0), expect: F(800, 200, nil)),
    Row(id: "F3-file-1000-read3-eof", obs: RawObs(bytesRead: 1000, bufAvail: 0, eofReached: 1, error: 0), expect: F(1000, 0, true)),
    Row(id: "F4-file-tiny-read", obs: RawObs(bytesRead: 1, bufAvail: 999, eofReached: 0, error: 0), expect: F(1, 999, nil)),
    Row(id: "F5-file-reread-counts", obs: RawObs(bytesRead: 1200, bufAvail: 0, eofReached: 0, error: 0), expect: F(1200, 0, nil)),
    Row(id: "F6-file-seek-clears-eof", obs: RawObs(bytesRead: 1100, bufAvail: 900, eofReached: 0, error: 0), expect: F(1100, 900, nil)),
    Row(id: "F7-file-no-reads-yet", obs: RawObs(bytesRead: 0, bufAvail: 0, eofReached: 0, error: 0), expect: F(0, 0, nil)),
    Row(id: "H1-http-nolen-partial", obs: RawObs(bytesRead: 300, bufAvail: -1, eofReached: 0, error: 0), expect: F(300, nil, nil)),
    Row(id: "H2-http-nolen-drained", obs: RawObs(bytesRead: 1000, bufAvail: -1, eofReached: 0, error: 0), expect: F(1000, nil, nil)),
    Row(id: "H3-http-nolen-buffer-reported", obs: RawObs(bytesRead: 500, bufAvail: 128, eofReached: 0, error: 0), expect: F(500, 128, nil)),
    Row(id: "H4-http-length-eof", obs: RawObs(bytesRead: 1000, bufAvail: 0, eofReached: 1, error: 0), expect: F(1000, 0, true)),
    Row(id: "H5-http-no-percent-inferred", obs: RawObs(bytesRead: 250, bufAvail: -1, eofReached: 0, error: 0), expect: F(250, nil, nil)),
    Row(id: "E1-http-error", obs: RawObs(bytesRead: 200, bufAvail: -1, eofReached: 0, error: -5), expect: F(200, nil, nil, -5)),
    Row(id: "E2-error-zero-is-nil", obs: RawObs(bytesRead: 100, bufAvail: 900, eofReached: 0, error: 0), expect: F(100, 900, nil)),
    Row(id: "E3-error-positive-is-nil", obs: RawObs(bytesRead: 100, bufAvail: 900, eofReached: 0, error: 1), expect: F(100, 900, nil)),
    Row(id: "N1-no-avio-context", obs: nil, expect: F(nil, nil, nil)),
    Row(id: "N2-negative-counter", obs: RawObs(bytesRead: -1, bufAvail: -1, eofReached: 0, error: 0), expect: F(nil, nil, nil)),
    Row(id: "N3-eof-nonzero-any", obs: RawObs(bytesRead: 1000, bufAvail: 0, eofReached: 2, error: 0), expect: F(1000, 0, true)),
]

// Sequence row S1: eof true, then a seek clears it: second snapshot nil, never false.
// packet-rule-modeled rows (integrator must confirm against real AVIO): F1,F2,F3,H4,S1.
func runSeq(_ cand: Candidate) -> Bool {
    let a = cand(RawObs(bytesRead: 1000, bufAvail: 0, eofReached: 1, error: 0))
    let b = cand(RawObs(bytesRead: 1000, bufAvail: 0, eofReached: 0, error: 0))
    let ok = a == F(1000, 0, true) && b == F(1000, 0, nil)
    if !ok { print("FAIL row S1-seq-eof-then-seek: step0 \(a) step1 \(b)") }
    return ok
}

func run(_ cand: Candidate) -> (pass: Int, fail: Int) {
    var p = 0, f = 0
    for r in rows {
        let got = cand(r.obs)
        if got == r.expect { p += 1 } else { f += 1; print("FAIL row \(r.id): expected \(r.expect) got \(got)") }
    }
    if runSeq(cand) { p += 1 } else { f += 1 }
    return (p, f)
}

// Negative control: the seeded candidate must fail, and must name a row id.
let mutants: [(String, Candidate)] = [("eofFalse", seededEofFalse), ("errZero", mutErrZero), ("errDropped", mutErrDropped), ("errPositive", mutErrPositive),
    ("eofEq1", mutEofEq1), ("nilPbZero", mutNilPbZero), ("negCounterZero", mutNegCounterZero)]
for (name, m) in mutants {
    if run(m).fail == 0 { print("active-transport-tests: negative control \(name) did not fail"); exit(1) }
}

print("--- reference candidate ---")
let result = run(reference)
print("active-transport-tests: \(result.pass) PASS, \(result.fail) FAIL")
exit(result.fail == 0 && result.pass >= 16 ? 0 : 1)
