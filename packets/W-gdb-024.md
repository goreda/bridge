# W-gdb-024 demux parity golden digest kit
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-024

```packet-json
{
 "packet_id": "W-gdb-024",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/demux-parity-tests/DemuxParity.swift",
   "excerpt_block": "source1"
  },
  {
   "path": "Sources/demux-parity-tests/DemuxParity.swift",
   "excerpt_block": "source1_1"
  }
 ],
 "interface": {
  "signatures": "generator -> stream description + golden digest; checker replay(candidateOutput, golden) -> PASS/FAIL",
  "types": "golden digest row { packet sequence digest, pts/dts order, duration }",
  "ownership_lifetime": "synthetic stream descriptions only; no media bytes",
  "caller": "demux parity runner",
  "callee": "golden digest checker: packet sequence + pts/dts order + duration per synthetic stream"
 },
 "test": {
  "command": "python3 kits/demux-goldens/check.py --replay",
  "expected": "exit 0; stdout 'demux-goldens: K/K golden digests byte-identical PASS'; one permuted packet order fails the checker with the stream id",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/demux-goldens/"
  ],
  "return_form": "full-files"
 }
}
```

## problem (what fails for the user)
demux parity is asserted by a runner, but there are no independent golden digest tables for synthetic interleaved streams (B-frame reorder, no-timestamp packets, corrupt tail), so a packet-order regression can ship as A/V desync.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/demux-parity-tests/DemuxParity.swift (sha256 8d64bede; first 60 lines below) - the parity surface.
- real test command: swift run demux-parity-tests <fixture> (existing; args per suite README/STATUS).

## expected behaviour
a generator emitting synthetic stream descriptions plus golden digest tables (packet sequence, pts/dts order, duration) and a checker replaying a candidate demuxer's emitted stream against the golden table; covers the three classes above.

## exact call site and interface
DemuxParity's comparison vocabulary (pinned excerpt); kit = generator + goldens + checker.

## behaviour that must not change
the existing parity suite stays green; synthetic streams only - no media bytes.

## acceptance test (from the product repo)
goldens reproduce byte-identically from the generator; one permuted packet order fails the checker.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/demux-parity-tests/DemuxParity.swift (sha256 8d64bede, lines 1-34 of 91)
```swift id=source1
// queue 26: demux PTS-semantics parity witness. Compares the lab BridgeDemux (MP4Demuxer/MKVDemuxer via Demuxer)
// against production avformat, per track, on the packet sequence (pts/dts/duration as reduced rationals).
// Output: DIGEST lab fnv=<x>, DIGEST av fnv=<x>, PARITY pass=N fail=M. Exit 0 only when fail=0.
// Linux only / native NOT_RUN. Usage: demux-parity-tests <file>
import Foundation
import BridgeDemux
import CFFmpeg

struct Rat: Equatable, CustomStringConvertible {
    let n: Int64, d: Int64
    init(_ n: Int64, _ d: Int64) {
        var a = n < 0 ? -n : n, b = d
        while b != 0 { (a, b) = (b, a % b) }
        if a == 0 || n == 0 { self.n = 0; self.d = 1 } else { self.n = n / a; self.d = d / a }
    }
    var description: String { "\(n)/\(d)" }
}
struct Pkt: Equatable, CustomStringConvertible {
    var pts: Rat?, dts: Rat?, dur: Rat?
    var description: String { "pts=\(pts?.description ?? "nil") dts=\(dts?.description ?? "nil") dur=\(dur?.description ?? "nil")" }
}
struct Fnv {
    var h: UInt64 = 0xcbf29ce484222325
    mutating func add(_ s: String) { for b in s.utf8 { h ^= UInt64(b); h &*= 0x100000001b3 } ; h ^= 0xff; h &*= 0x100000001b3 }
}

func labSide(_ bytes: [UInt8]) throws -> [[Pkt]] {
    var dx = Demuxer()
    let tracks = try dx.open(bytes)
    var index: [Int: Int] = [:]
    for (i, t) in tracks.enumerated() { index[t.id] = i }
    var out = Array(repeating: [Pkt](), count: tracks.count)
    func r(_ x: RationalTime?) -> Rat? { x.map { Rat($0.value, $0.scale) } }
    while let p = try dx.next() {
```

### Sources/demux-parity-tests/DemuxParity.swift (sha256 8d64bede, lines 36-60 of 91)
```swift id=source1_1
        out[i].append(Pkt(pts: r(p.pts), dts: r(p.dts), dur: r(p.duration)))
    }
    return out
}

func avSide(_ path: String) -> [[Pkt]]? {
    var fc: UnsafeMutablePointer<AVFormatContext>? = nil
    guard avformat_open_input(&fc, path, nil, nil) == 0, let ctx = fc else { return nil }
    defer { var c: UnsafeMutablePointer<AVFormatContext>? = ctx; avformat_close_input(&c) }
    guard avformat_find_stream_info(ctx, nil) >= 0 else { return nil }
    let n = Int(ctx.pointee.nb_streams)
    var out = Array(repeating: [Pkt](), count: n)
    guard let pkt = av_packet_alloc() else { return nil }
    defer { var pp: UnsafeMutablePointer<AVPacket>? = pkt; av_packet_free(&pp) }
    while av_read_frame(ctx, pkt) >= 0 {
        let si = Int(pkt.pointee.stream_index)
        if si >= 0 && si < n, let st = ctx.pointee.streams[si] {
            let tb = st.pointee.time_base
            func r(_ v: Int64) -> Rat? { v == Int64.min ? nil : Rat(v * Int64(tb.num), Int64(tb.den)) }
            let dur: Rat? = pkt.pointee.duration > 0 ? r(pkt.pointee.duration) : (pkt.pointee.duration == 0 ? Rat(0, 1) : nil)
            out[si].append(Pkt(pts: r(pkt.pointee.pts), dts: r(pkt.pointee.dts), dur: dur))
        }
        av_packet_unref(pkt)
    }
    return out
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"stream":{"video":{"codec":"h264","gop":24,"bframes":2},"audio":{"codec":"aac","frameMs":21.33}},"golden":{"packetOrder":"<deliverable digest>","ptsMonotonicAfterReorder":true,"durationSeconds":4.0}}
```
