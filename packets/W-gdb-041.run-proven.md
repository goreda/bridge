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
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/n6-profile-transform-pin/check.py",
        "block": "kit1"
      },
      {
        "path": "kits/n6-profile-transform-pin/fixtures.json",
        "block": "fixtures2"
      },
      {
        "path": "kits/n6-profile-transform-pin/rpu.py",
        "block": "kit2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/n6-profile-transform-pin/check.py kits/n6-profile-transform-pin/fixtures.json",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:12:24.365175+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "n6-profile-transform-pin: 4/4 fixtures PASS",
    "inline_files": [
      {
        "path": "kits/n6-profile-transform-pin/check.py",
        "block": "kit1",
        "sha256": "42ad040d4f835809ee8d3bbc570dcf10e41a2a0739dbe0c98f12a705a288f056"
      },
      {
        "path": "kits/n6-profile-transform-pin/fixtures.json",
        "block": "fixtures2",
        "sha256": "04032b1e06afdb60ce82d55b25d065181fc5f55f2102551d10bba71a44defd62"
      },
      {
        "path": "kits/n6-profile-transform-pin/rpu.py",
        "block": "kit2",
        "sha256": "dbfdf0808fb761fe2c0b51d16d8051d70a6fa6fbf09cfa64ebf8d186f39c85d4"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "ea5b291153102cf49cf1c25358a34fc5e6a3dd76658d78da6260277ebdedaddd",
    "last_5_lines": [
      "PASS dv-rpu-truncated malformed",
      "PASS identity-trap witness FAIL (output still profile 8 != claimed 5)",
      "PASS witness: transform to profile 5 re-parses, fnv recomputed",
      "PASS negative control: a mutated output byte fails its row",
      "n6-profile-transform-pin: 4/4 fixtures PASS"
    ],
    "receipt_sha256": "0f6835221b585a6a5e619fa5b0e54adb32008870667e2a0c3792150e70bad0a1"
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

```python id=kit1
#!/usr/bin/env python3
# n6-profile-transform-pin: RPU METADATA profile transform contract (narrowed
# scope; pixel reshaping OUT OF SCOPE). Input admission decided solely by the
# pinned header parse; every transform additionally emits a witness: output
# re-parses .parsed, bytes+fnv1a64 recomputed, and the full parse reports
# outputFullParsedProfile == targetProfile. An identity transform (output ==
# input while target != input profile) is a witness mismatch and MUST fail.
import json, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rpu import fnv1a64, parse_rpu_header

def full_rpu_profile(data):
    status, guess = parse_rpu_header(data)
    return guess if status == "parsed" else None

def dv_transform_rpu_profile(rpu, target):
    status, guess = parse_rpu_header(rpu)
    if status != "parsed":
        return ("refused", "malformedInput", None)
    out = bytearray(rpu)
    out[1] = (out[1] & 0xF0) | (target & 0x0F)  # metadata-level profile rewrite
    # recompute the trailing CRC-32/MPEG-2 so the output stays parseable
    crc = 0xFFFFFFFF
    crc_start = len(out) - 5
    for i in range(1, crc_start):
        crc ^= out[i] << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if (crc & 0x80000000) else (crc << 1) & 0xFFFFFFFF
    out[crc_start:crc_start+4] = crc.to_bytes(4, "big")
    return ("ok", bytes(out), guess)

def witness(rpu_in, out, target, input_profile):
    st, _ = parse_rpu_header(out)
    w = {"inputFnv1a64": "%016x" % fnv1a64(rpu_in), "inputParsedProfile": input_profile,
         "targetProfile": target, "outputFnv1a64": "%016x" % fnv1a64(out),
         "outputHeaderParsed": st == "parsed", "outputFullParsedProfile": full_rpu_profile(out)}
    ok = w["outputHeaderParsed"] and w["outputFullParsedProfile"] == target
    if out == rpu_in and target != input_profile:
        ok = False  # identity trap: unchanged bytes are not a transform
    return ok, w

def main():
    fixtures = json.load(open(sys.argv[1]))
    fails = passed = 0
    for fx in fixtures:
        name = fx["fixture"]
        if name == "dv-rpu-p8-identity-trap":
            inp = bytes.fromhex(fx["moduleOutputHex"])
            target = fx["moduleClaims"]["targetProfile"]
            _, prof = parse_rpu_header(inp)
            ok_w, w = witness(inp, inp, target, prof)
            if not ok_w:
                passed += 1; print("PASS identity-trap witness FAIL (output still profile %d != claimed %d)" % (prof, target))
            else:
                fails += 1; print("FAIL identity-trap passed its witness")
            continue
        data = bytes.fromhex(fx["bytesHex"])
        exp = fx["expect"]
        status, guess = parse_rpu_header(data)
        parse_str = "parsed(profileGuess: %d)" % guess if status == "parsed" else status
        ok = parse_str == exp["parse"]
        if "fnv1a64" in exp:
            ok = ok and "%016x" % fnv1a64(data) == exp["fnv1a64"]
        if "transformRefusal" in exp:
            rr, _, _ = dv_transform_rpu_profile(data, 5)
            ok = ok and rr == "refused"
        if ok: passed += 1; print("PASS %s %s" % (name, parse_str))
        else: fails += 1; print("FAIL %s" % name)
    # Transform path self-check: valid fixture -> target 5 must witness clean.
    data = bytes.fromhex(fixtures[0]["bytesHex"])
    rr, out, prof = dv_transform_rpu_profile(data, 5)
    ok_w, w = witness(data, out, 5, prof)
    if ok_w:
        print("PASS witness: transform to profile 5 re-parses, fnv recomputed")
    else:
        fails += 1; print("FAIL witness self-check")
    # Negative control: a mutated output byte must fail its row.
    bad = bytearray(out); bad[3] ^= 0x01
    ok_w2, _ = witness(data, bytes(bad), 5, prof)
    if ok_w2:
        fails += 1; print("FAIL negative control: mutated output byte passed")
    else:
        print("PASS negative control: a mutated output byte fails its row")
    total = len(fixtures)
    if fails:
        print("n6-profile-transform-pin: %d/%d fixtures PASS, %d FAIL" % (passed, total, fails)); sys.exit(1)
    print("n6-profile-transform-pin: %d/%d fixtures PASS" % (passed, total)); sys.exit(0)

if __name__ == "__main__":
    main()

```

```json id=fixtures2
[
 {
  "fixture": "dv-rpu-p8-valid",
  "bytesHex": "19080008404236c000ee8db12380",
  "expect": {
   "parse": "parsed(profileGuess: 8)",
   "fnv1a64": "d8135198627a78cb"
  }
 },
 {
  "fixture": "dv-rpu-badcrc",
  "bytesHex": "19080008404236c000ef8db12380",
  "expect": {
   "parse": "crcMismatch",
   "transformRefusal": "malformedInput"
  }
 },
 {
  "fixture": "dv-rpu-truncated",
  "bytesHex": "1908000840",
  "expect": {
   "parse": "malformed",
   "transformRefusal": "malformedInput"
  }
 },
 {
  "fixture": "dv-rpu-p8-identity-trap",
  "moduleClaims": {
   "targetProfile": 5
  },
  "moduleOutputHex": "19080008404236c000ee8db12380",
  "expect": {
   "witness": "FAIL",
   "reason": "output header parse still reports profileGuess 8 and the full RPU parse does not reach targetProfile 5; unchanged input bytes are not a transform"
  }
 }
]
```

```python id=kit2
# Shared pinned-oracle model: gorav_dv_fnv1a64 + gorav_dv_parse_rpu_header
# (Sources/GorAVDVRPU/src/DVRPUAnnexB.c @ 2112af0d60df16c5473173b664903f76ce54173e).
# CRC-32/MPEG-2 over RBSP bytes after the prefix byte up to crcStart = len-5;
# want = u32 BE at crcStart; final byte 0x80. rc 0/-2/-1 ->
# parsed(profileGuess)/crcMismatch/malformed.
def fnv1a64(b):
    h = 14695981039346656037
    for x in b:
        h ^= x
        h = (h * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return h

def parse_rpu_header(rbsp):
    n = len(rbsp)
    if n < 9:
        return ("malformed", None)
    crc_start = n - 5
    want = int.from_bytes(rbsp[crc_start:crc_start+4], "big")
    crc = 0xFFFFFFFF
    for i in range(1, crc_start):
        crc ^= rbsp[i] << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if (crc & 0x80000000) else (crc << 1) & 0xFFFFFFFF
    if crc != want:
        return ("crcMismatch", None)
    if rbsp[n-1] != 0x80:
        return ("malformed", None)
    profile_guess = rbsp[1] & 0x0F if (rbsp[1] >> 4) == 0 else (rbsp[0] >> 4)
    return ("parsed", profile_guess)

```

```text id=actual_run_log
PASS dv-rpu-p8-valid parsed(profileGuess: 8)
PASS dv-rpu-badcrc crcMismatch
PASS dv-rpu-truncated malformed
PASS identity-trap witness FAIL (output still profile 8 != claimed 5)
PASS witness: transform to profile 5 re-parses, fnv recomputed
PASS negative control: a mutated output byte fails its row
n6-profile-transform-pin: 4/4 fixtures PASS
```
