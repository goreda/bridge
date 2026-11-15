# W-gdb-038 DV RPU side-data bytes-preserving fixtures
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-038

```packet-json
{
 "packet_id": "W-gdb-038",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/GorAVDolbyVision/DVRPUSideData.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "DVRPUSideData.syncRead<B: DVRPUFrameBorrow>(_: B) -> DVRPUReadResult; dvFnv1a64(_ bytes: [UInt8]) -> UInt64",
  "types": "DVRPUSideDataFetch 5 cases; DVRPUReadResult { absent, corrupt, rejectedOversize, unavailable, ok(DVRPUObservation) }; DVRPUObservation { bytes, byteCount, fnv1a64, context, headerStatus }; DVRPUHeaderStatus 5 cases",
  "ownership_lifetime": "observation owns a bounded copy (<= 1048576 bytes); oversize input yields nil, never a trap",
  "caller": "HDR round-trip checker",
  "callee": "DVRPUSideData.syncRead + dvFnv1a64 + DVRPUObservation typed construction (pinned below)"
 },
 "test": {
  "command": "python3 kits/hdr-roundtrip/check.py",
  "expected": "exit 0; stdout 'hdr-roundtrip: all fixtures bytes+fnv identical PASS'; truncated/CRC-broken fixtures yield .ok with degraded headerStatus (malformed/crcMismatch), never a trap; .corrupt only on producer-malformed/empty fetch",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/hdr-roundtrip/"
  ],
  "return_form": "full-files"
 }
}
```

## problem (what fails for the user)
Dolby Vision RPU side data must survive the DVRPUSideData read path byte-exact (bytes + fnv1a64) with a truthful headerStatus; a silent corruption ships as wrong colors or a fallen-back-to-SDR picture with no error.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVDolbyVision/DVRPUSideData.swift (sha256 cffc14e1; first 50 lines below).
- real test command: the returned fixtures run against the pinned parser on Linux.

## expected behaviour
concrete DV RPU byte fixtures (generator + oracle verified against the pinned DVRPUAnnexB.c, compiled and run locally) with bytes-preserving read goldens: fixture bytes -> syncRead -> .ok(observation), observation.bytes == fixture bytes, observation.fnv1a64 == dvFnv1a64(bytes), headerStatus golden per fixture. Degraded headers (truncated, bad CRC) still produce .ok with the typed degraded headerStatus; .corrupt is reserved for producer-malformed/empty fetches; absent fetches produce .absent. no pixel data, no licensed streams, no HDR10/HLG scope.

## exact call site and interface
DVRPUSideData's parse surface (pinned excerpt) plus the static-metadata types at the same pin are asserted.

## pinned ABI decisions (integrator, 2026-11-15; parse ABI pinned - round-trip claim corrected)
DVRPUSideData.swift at the pin (excerpt above + these declarations):
- dvRPUBufferSideDataKind: Int32 = 23; dvRPUMaxBytes = 1_048_576; public func dvFnv1a64(_ bytes: [UInt8]) -> UInt64
- public enum DVRPUSideDataFetch { absent, ok([UInt8]), refusedOversize(size: Int, limit: Int), malformed(reason: String), unavailable(reason: String) }, produced via protocol DVRPUFrameBorrow.dvFetchSideData(_ kind: Int32, maxBytes: Int)
- public enum DVRPUSideData { static syncFetch<B: DVRPUFrameBorrow>(_: B) -> (DVRPUSideDataFetch, DVRPUContext); syncRead -> DVRPUReadResult }; DVRPUReadResult { absent, corrupt(reason: String), rejectedOversize(size: Int, limit: Int), unavailable(reason: String), ok(DVRPUObservation) }
- public struct DVRPUObservation { bytes: [UInt8]; byteCount: Int; fnv1a64: UInt64; context: DVRPUContext; headerStatus: DVRPUHeaderStatus } - typed construction: oversize input yields nil, never a trap; DVRPUHeaderStatus { parsed(profileGuess: UInt32), malformed, crcMismatch, semanticRejected, parseUnavailable(reason: String) }
- there is NO public assemble/serialize entry (r4.3: assembly from raw parts is internal by design). the round-trip ABI is therefore BYTES-PRESERVING: fixture bytes -> syncRead -> .ok(observation) -> observation.bytes == fixture bytes AND observation.fnv1a64 == dvFnv1a64(fixture bytes), with headerStatus goldens per fixture (parsed(profileGuess:) / malformed / crcMismatch). the earlier parse->serialize wording is corrected.

## behaviour that must not change
existing color/DV checks stay green; unknown profile data is preserved, not dropped.

## acceptance test (from the product repo)
every fixture preserves bytes + fnv1a64 exactly and matches its headerStatus golden; a truncated or CRC-broken block yields .ok with the typed degraded headerStatus (never a trap); a producer-malformed or empty fetch yields .corrupt; an absent fetch yields .absent.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVDolbyVision/DVRPUSideData.swift (sha256 cffc14e1, lines 1-50 of 246)
```swift id=source1
// DVRPUSideData.swift - gorav block 78 L6: RPU via FFmpeg side data (primary path).
// Base: gorav trunk main c5f06bd (v1.4 exact base, FFmpeg n8.0.1 @ 894da5ca).
// STATUS r4.1: TYPECHECKED + LIVE-RUN on Linux Swift 6.0.3 against the real
// GorAVDVRPU C core and a fake borrow (dovi-selftest/swift, clearly marked).
// NOT YET RUN against the real L3 decoder: L3 v4 is UNCOMPILED upstream
// (R2Y compile + safety review pending; runtime hold stays). Mac build via
// swift build on the trunk is STILL UNRUN.
//
// r4 (architect review part 1/2 findings 1-2):
// - Typed producer fetch: a nil/absent conflation can no longer classify a
//   producer error or an oversize refusal as "non-DV content". .absent is
//   emitted ONLY when the producer proves absence; L3 v3.1's sideDataCopy
//   cannot prove it, so the v3.1 bridge maps nil -> .unavailable.
// - No precondition traps: a nonconforming producer returning more than the
//   bound gets a typed refusal, never a crash.
// - Kind binding: the RPU side-data kind is a pinned constant of this
//   module, not a caller-supplied Int32, so no caller can relabel non-RPU
//   bytes as an RPU receipt. The integration bridge checks the constant
//   against the real AVFrameSideDataType at startup.
// - Semantic receipt: the observation carries the C core's header-parse
//   outcome (not just bytes), so .ok is a parsed-RPU receipt, and parse
//   failure degrades the receipt instead of hiding it.
// Consumer scope (unchanged): never sees an AVFrame pointer, never wraps
// pointer+UInt64, hashes the OWNED copy after it leaves the lease, stores
// nothing borrowed. The borrow protocol does NOT prove producer
// enforcement - budget/scope/token/stream/PTS identity enforcement remains
// L3 v4 producer work.

import Foundation
import GorAVDVRPU

/// AV_FRAME_DATA_DOVI_RPU_BUFFER in the pinned FFmpeg n8.0.1 @ 894da5ca
/// (libavutil/frame.h enum position 23), VERIFIED by a compiled assert
/// against the pinned headers (dovi-selftest/swift/kindcheck.c output in
/// TESTLOG). The integration bridge MUST check this against the real
/// CFFmpeg constant at startup (see DVRPUL3Bridge.swift).
public let dvRPUBufferSideDataKind: Int32 = 23

/// Hard bound on one RPU side-data buffer. RPUs are typically 150-400 B
/// (dolby_vision crate comment); 1 MiB is deliberately generous and turns
/// anything larger into a typed refusal instead of an unbounded copy.
/// This is the LANE's consumer bound, independent of producer copy caps
/// (L3 v4.3: 32 MiB per copy, 128 MiB aggregate per borrow) - the tighter
/// bound wins on this path by design.
public let dvRPUMaxBytes: Int = 1_048_576

/// Standard FNV-1a 64. Receipt hash only, NOT a cryptographic integrity
/// claim. Matches DVRPUAnnexB.c exactly (pinned by standard vectors).
@inline(__always)
public func dvFnv1a64(_ bytes: [UInt8]) -> UInt64 {
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"fixtures":[{"fixture":"dv-rpu-p8-valid","bytesHex":"19080008404236c000ee8db12380","expect":{"readResult":"ok","bytesPreserved":true,"fnv1a64":"d8135198627a78cb","headerStatus":"parsed(profileGuess: 8)"}},{"fixture":"dv-rpu-badcrc","bytesHex":"19080008404236c000ef8db12380","expect":{"readResult":"ok","bytesPreserved":true,"fnv1a64":"3c6dc615a7b39ea4","headerStatus":"crcMismatch"}},{"fixture":"dv-rpu-truncated","bytesHex":"1908000840","expect":{"readResult":"ok","bytesPreserved":true,"fnv1a64":"082d28ed18e5b034","headerStatus":"malformed"}},{"fixture":"fetch-absent","expect":{"readResult":"absent"}},{"fixture":"fetch-malformed-zero-length","expect":{"readResult":"corrupt","trap":false}}],"oracle":"rows 1-3 verified against pinned Sources/GorAVDVRPU/src/DVRPUAnnexB.c compiled and run locally: gorav_dv_parse_rpu_header rc 0/-2/-1 maps to parsed(profileGuess: 8)/crcMismatch/malformed; fnv1a64 from gorav_dv_fnv1a64"}
```
