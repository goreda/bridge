# W-gdb-051 195b-B7 HTTP range transport: consuming pin
state: candidate
solver lab: 1nstinct
reviewer lab: unclaimed
id: W-gdb-051

```packet-json
{
 "packet_id": "W-gdb-051",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/GorAVFFmpegAdapter/ActiveTransportSnapshot.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "ActiveTransportSnapshot producer fields bytesRead: Int64? / bufferAvailableBytes: Int? / eofObserved: Bool? (pinned excerpt); transport read(offset:count:) -> bytes, seek, cancel",
  "types": "snapshot optionality rules pinned; range requests exact-half-open byte ranges",
  "ownership_lifetime": "snapshot values immutable; transport owns its sockets; cancel completes bounded",
  "caller": "avformat provider / remote open path",
  "callee": "the lab transport module feeding the pinned snapshot fields"
 },
 "test": {
  "command": "python3 kits/b7-transport-pin/check.py kits/b7-transport-pin/fixtures.json",
  "expected": "exit 0; stdout 'b7-transport-pin: 3/3 rows PASS'; cumulative bytesRead exact; unreported fields stay nil",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVFFmpegAdapter/",
   "kits/b7-transport-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
the range transport (195b-B7) feeds the player's progress/buffer display; without the pinned snapshot semantics it can lie about bytes read, buffering and EOF.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0286/B7; the lab module implements against the pinned interface below.

## expected behaviour
a transport module feeding ActiveTransportSnapshot truthfully per the pinned producer: bytesRead Int64? is the AVIO bytes_read counter, cumulative across reads INCLUDING probe reads and rereads (pinned source comment) - never network-only unique bytes, never body-only, never file position; bufferAvailableBytes Int? only when the source reports it, else nil; eofObserved Bool? true only when observed, nil otherwise (never false-as-default); range requests carry exact byte ranges; cancel interrupts in bounded time; the pinned W-gdb-027 snapshot-truthfulness rules apply as the acceptance vocabulary.

## exact call site and interface
ActiveTransportSnapshot.swift (pinned excerpt) is the snapshot producer contract; the transport module slots behind the avformat provider seam (W-gdb-049 option set); delivery as transport code + kits/b7-transport-pin/ synthetic-server fixtures.

## behaviour that must not change
snapshot nil-semantics (absence stays nil, never inferred) and the AVIO bridge read/seek fence are untouched.

## acceptance test (from the product repo)
python3 kits/b7-transport-pin/check.py kits/b7-transport-pin/fixtures.json exits 0 against its synthetic server; snapshot rows match goldens; a guessed non-nil field fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVFFmpegAdapter/ActiveTransportSnapshot.swift (sha256 5f0ea2a1, lines 1-42 of 42)
```swift id=source1
import Foundation
import GorAVNativeProbeKit
import CFFmpeg

/// A queue-time observation of the active AVIOContext, not a cache model.
/// nil means unavailable/not observed, never zero. No paths, URLs or headers.
public struct ActiveTransportSnapshot: Equatable, Sendable {
    public let source: SourceToken
    public let session: SeekSessionID
    public let revision: SeekRevision
    /// FFmpeg AVIO bytes_read counter, cumulative for this open. Includes probe
    /// reads and rereads; not network-only unique bytes or file position.
    public let bytesRead: Int64?
    /// Bytes remaining in AVIO's current user-space input buffer only.
    public let bufferAvailableBytes: Int?
    /// true when AVIO has observed EOF; nil before that or without an AVIOContext.
    /// A seek can clear this observation. No prediction that the remote is finished.
    public let eofObserved: Bool?
    /// Negative FFmpeg AVIO error when present; nil means no error observed,
    /// not an assertion that transport is healthy or unable to stall.
    public let errorCode: Int32?

    // Called only inside the format owner's native queue, never retains pb.
    static func capture(_ pb: UnsafePointer<AVIOContext>?, source: SourceToken,
                        session: SeekSessionID, revision: SeekRevision) -> Self {
        guard let pb else {
            return Self(source: source, session: session, revision: revision,
                        bytesRead: nil, bufferAvailableBytes: nil, eofObserved: nil, errorCode: nil)
        }
        let count = pb.pointee.bytes_read
        let available = gorav_avio_buffer_available(pb)
        return Self(source: source, session: session, revision: revision,
                    bytesRead: count >= 0 ? count : nil,
                    bufferAvailableBytes: available >= 0 ? Int(available) : nil,
                    eofObserved: pb.pointee.eof_reached != 0 ? true : nil,
                    errorCode: pb.pointee.error < 0 ? pb.pointee.error : nil)
    }
}

public enum ActiveTransportRefusal: Error, Equatable, Sendable {
    case notOpen, staleBinding
}
```


## roles and state
solver lab: 1nstinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"transfer": "1000B range GET, 3 reads 400+400+200", "expect": {"bytesRead": "cumulative 1000", "eofObserved": true}}, {"transfer": "unsized loopback", "expect": {"bufferAvailableBytes": null, "eofObserved": null}, "rule": "nil until reported, never inferred"}, {"transfer": "16384-byte probe read, then range 50000-99999 (50000 body bytes)", "expect": "single Range request with exact byte range; bytesRead = cumulative AVIO counter = probe bytes + range body bytes + any rereads (e.g. 66384 with no rereads), never body-only"}]
```
