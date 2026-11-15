# W-gdb-041 195b-N6-adjacent RPU profile transform: consuming pin (narrowed scope; W-gdb-009 withdrawal stands)
state: candidate
solver lab: 1nstinct
reviewer lab: unclaimed
id: W-gdb-041

```packet-json
{
 "packet_id": "W-gdb-041",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/GorAVDolbyVision/DVRPUSideData.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "DVRPUSideData.syncRead<B: DVRPUFrameBorrow>(_: B) -> DVRPUReadResult; dvFnv1a64(_ bytes: [UInt8]) -> UInt64; additive module entry dvTransformRPUProfile(rpu: [UInt8], targetProfile: UInt32) -> Result<[UInt8], DVProfileTransformRefusal>; additive witness dvTransformWitness(rpu: [UInt8], targetProfile: UInt32) -> Result<DVProfileTransformWitness, DVProfileTransformRefusal>",
  "types": "DVRPUReadResult 5 cases; DVRPUObservation { bytes, byteCount, fnv1a64, context, headerStatus }; DVProfileTransformRefusal { unsupportedProfile, malformedInput, rejectedOversize } (additive); DVProfileTransformWitness { inputFnv1a64: UInt64, inputParsedProfile: UInt32, targetProfile: UInt32, outputFnv1a64: UInt64, outputHeaderParsed: Bool, outputFullParsedProfile: UInt32? } (additive)",
  "ownership_lifetime": "input RPU bytes consumed read-only; transform output is a fresh [UInt8]; observations own a bounded copy <= 1_048_576 bytes, oversize input yields nil, never a trap",
  "caller": "GorAVDolbyVision lane consuming DVRPUSideData.syncRead",
  "callee": "the lab transform module behind dvTransformRPUProfile; input admission decided solely by the pinned header parse"
 },
 "test": {
  "command": "python3 kits/n6-profile-transform-pin/check.py kits/n6-profile-transform-pin/fixtures.json",
  "expected": "exit 0; stdout 'n6-profile-transform-pin: 4/4 fixtures PASS'; valid fixture parses parsed(profileGuess: 8) with fnv1a64 d8135198627a78cb; badcrc/truncated inputs are refused malformedInput; a mutated output byte fails its row; the identity-trap row MUST fail its witness (output profileGuess 8 != claimed targetProfile 5)",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVDolbyVision/",
   "kits/n6-profile-transform-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
DV playback across profile variants needs a verified RPU METADATA profile transform (rewriting RPU metadata from one DV profile to another); without a pinned consuming seam and a transform-validity witness, labs cannot start even this metadata-level step.

## scope limit (narrowed target)
This packet is explicitly narrowed to RPU PROFILE TRANSFORM at the metadata level. DV PIXEL RESHAPING (applying the RPU mapping polynomial/MMR coefficients to decoded pixels) is OUT OF SCOPE: this packet's oracles parse and validate RPU metadata, they do not reshape pixels, and no pixel-reshape oracle is pinned here. The W-gdb-009 / W-0276 (195b-N6 DV reshaping) withdrawal STANDS UNCHANGED; reopening N6 is a separate owner decision requiring a real pixel reshape oracle plus source pin, and this packet is not that reopen. This narrowing is itself a separate decision from the N6 question.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for the narrowed RPU profile-transform target; the lab module implements against the pinned interface below.

## expected behaviour
a profile-transform module behind the additive entry dvTransformRPUProfile(rpu: [UInt8], targetProfile: UInt32) -> Result<[UInt8], DVProfileTransformRefusal>, consuming RPU bytes ONLY through the pinned DVRPUSideData read path: input validity is decided by the pinned header parse (parsed(profileGuess:) required; malformed/crcMismatch/semanticRejected/parseUnavailable inputs are refused typed, never transformed). The header parse is admission only (pinned SCOPE LIMIT: it is not reshaping/DM/config-record validation), so every transform additionally emits a DVProfileTransformWitness proving TRANSFORM validity at the metadata level: the output re-parses through the pinned header parse to .parsed (outputHeaderParsed true), its bytes+fnv1a64 are recomputed and reported, AND the output passes a FULL RPU parse (dependency pinned below) reporting outputFullParsedProfile == targetProfile. An identity transform (output bytes == input bytes while targetProfile differs from inputParsedProfile) is a witness mismatch and MUST fail. No full-FEL claim; no pixel-reshaping claim; supported-profile set is named by the module and enforced typed.

## pinned full-parse dependency (source pin)
The full RPU parse is FFmpeg 8.0.1 libavcodec dovi_rpu: source tree commit 894da5ca7d742e4429ffb2af534fcda0103ef593 (the lab static tree), file libavcodec/dovi_rpu.c sha256 prefix 29922596 with entry int ff_dovi_rpu_parse(DOVIContext*, const uint8_t*, size_t, ...) declared in libavcodec/dovi_rpu.h:117 (sha256 prefix cc91857f). The witness's outputFullParsedProfile comes from that parser over the exact output bytes; a parse failure or profile mismatch fails the row. This dependency pin is part of the packet contract.

## exact call site and interface
DVRPUSideData.syncRead/DVRPUObservation (pinned excerpt) is the only read seam; the transform module is additive new code under Sources/GorAVDolbyVision/ + kits/n6-profile-transform-pin/.

## behaviour that must not change
DVRPUSideData read-path semantics (bytes-preserving, fnv1a64, headerStatus taxonomy, bounded-copy nil-construction) are untouched; no public assemble/serialize entry is added (r4.3); no pixel-reshaping API is introduced under this packet.

## acceptance test (from the product repo)
python3 kits/n6-profile-transform-pin/check.py kits/n6-profile-transform-pin/fixtures.json exits 0; every fixture row matches its pinned parse/fnv golden (verified against the pinned DVRPUAnnexB.c compiled and run by the integrator); a mutated output byte fails its row; the identity-trap row (module returns the input bytes unchanged while claiming targetProfile 5) fails its DVProfileTransformWitness because the output still parses profileGuess 8 and the full RPU parse does not reach profile 5 - proving the witness checks a real transform, not byte delivery.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVDolbyVision/DVRPUSideData.swift (sha256 cffc14e1, lines 96-130 of 246)
```swift id=source1
public struct DVRPUObservation: Sendable, Equatable {
    public let bytes: [UInt8]
    public let byteCount: Int
    public let fnv1a64: UInt64
    public let context: DVRPUContext
    public let headerStatus: DVRPUHeaderStatus
    /// Typed construction: oversize input yields nil, never a trap.
    /// INTERNAL on purpose (r4.2 part 3): the header status is COMPUTED by
    /// the lane's own parse over these exact bytes; there is no public way
    /// to attach a "parsed" claim to arbitrary bytes. Consumers READ
    /// headerStatus - an .ok observation with a non-.parsed status is a
    /// degraded receipt and MUST be treated as such. A parsed RPU header is
    /// NOT reshaping/DM/config-record capability validation.
    init?(bytes: [UInt8], context: DVRPUContext) {
        guard bytes.count <= dvRPUMaxBytes else { return nil }
        self.bytes = bytes
        self.byteCount = bytes.count
        self.fnv1a64 = dvFnv1a64(bytes)
        self.context = context
        self.headerStatus = DVRPUSideData.parseStatus(of: bytes)
    }
    /// True iff the lane's reference-verified parse fully validated the
    /// fixed HEADER SUBSET of THESE bytes (framing + CRC + the reference's
    /// header validate arms). SCOPE LIMIT (architect r4.3): this is NOT
    /// full DV validity - rpu_data_mapping, NLQ and DM metadata are
    /// NOT_PARSED, reshaping is not validated, FEL is out of scope, and a
    /// parsed header is not a playback/config-record claim. False on any
    /// degraded receipt (malformed/crcMismatch/semanticRejected/
    /// parseUnavailable) - such an observation proves byte delivery, never
    /// DV content validity.
    public var isHeaderParsed: Bool {
        if case .parsed = headerStatus { return true }
        return false
    }
}
```


## roles and state
solver lab: 1nstinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"fixture": "dv-rpu-p8-valid", "bytesHex": "19080008404236c000ee8db12380", "expect": {"parse": "parsed(profileGuess: 8)", "fnv1a64": "d8135198627a78cb"}}, {"fixture": "dv-rpu-badcrc", "bytesHex": "19080008404236c000ef8db12380", "expect": {"parse": "crcMismatch", "transformRefusal": "malformedInput"}}, {"fixture": "dv-rpu-truncated", "bytesHex": "1908000840", "expect": {"parse": "malformed", "transformRefusal": "malformedInput"}}, {"fixture": "dv-rpu-p8-identity-trap", "moduleClaims": {"targetProfile": 5}, "moduleOutputHex": "19080008404236c000ee8db12380", "expect": {"witness": "FAIL", "reason": "output header parse still reports profileGuess 8 and the full RPU parse does not reach targetProfile 5; unchanged input bytes are not a transform"}}]
```
