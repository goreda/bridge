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
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/demux-goldens/README.md",
        "block": "rf1"
      },
      {
        "path": "kits/demux-goldens/check.py",
        "block": "rf2"
      },
      {
        "path": "kits/demux-goldens/digests.py",
        "block": "rf3"
      },
      {
        "path": "kits/demux-goldens/generate.py",
        "block": "rf4"
      },
      {
        "path": "kits/demux-goldens/goldens/synthetic-bframe-reorder.digest.txt",
        "block": "rf5"
      },
      {
        "path": "kits/demux-goldens/goldens/synthetic-corrupt-tail.digest.txt",
        "block": "rf6"
      },
      {
        "path": "kits/demux-goldens/goldens/synthetic-no-timestamps.digest.txt",
        "block": "rf7"
      },
      {
        "path": "kits/demux-goldens/streams/synthetic-bframe-reorder.json",
        "block": "rf8"
      },
      {
        "path": "kits/demux-goldens/streams/synthetic-corrupt-tail.json",
        "block": "rf9"
      },
      {
        "path": "kits/demux-goldens/streams/synthetic-no-timestamps.json",
        "block": "rf10"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/demux-goldens/check.py --replay",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:05:15.666926+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "demux-goldens: 3/3 golden digests byte-identical PASS",
    "inline_files": [
      {
        "path": "kits/demux-goldens/README.md",
        "block": "rf1",
        "sha256": "7d5ba2c37b2529fd03343c623a02142113818197ac8e54a2f8ee9b8db55c03f8"
      },
      {
        "path": "kits/demux-goldens/check.py",
        "block": "rf2",
        "sha256": "b4ae60dcf872def178e2df753661827757739f832a5e2ed357f3cd88308815f7"
      },
      {
        "path": "kits/demux-goldens/digests.py",
        "block": "rf3",
        "sha256": "46485d5dbbb0c2fa04ed31b60799ff5f6f26e6bb0d13a9bd09e1141bcc5a7062"
      },
      {
        "path": "kits/demux-goldens/generate.py",
        "block": "rf4",
        "sha256": "deee760c75db5525b14e549ddf8fa538cd8ab57d688c4063e84569cde2669359"
      },
      {
        "path": "kits/demux-goldens/goldens/synthetic-bframe-reorder.digest.txt",
        "block": "rf5",
        "sha256": "7716b9b84be1b7899bc909dbe5f4aba33d9386dec6438359b2e4ca5dc75333aa"
      },
      {
        "path": "kits/demux-goldens/goldens/synthetic-corrupt-tail.digest.txt",
        "block": "rf6",
        "sha256": "1df4ce99bbd36f660f952138d0d11c2cd45979f5542fc74a3308d8350e042ed9"
      },
      {
        "path": "kits/demux-goldens/goldens/synthetic-no-timestamps.digest.txt",
        "block": "rf7",
        "sha256": "8942c13359c59388c096d3e4a2c253ee18dbb6fcf236b7d6741a9334f9a34123"
      },
      {
        "path": "kits/demux-goldens/streams/synthetic-bframe-reorder.json",
        "block": "rf8",
        "sha256": "8c62bdafe0af068a9b3dcd35fa4faef87a0ba02f1afb3eef581f7c3e8df926fb"
      },
      {
        "path": "kits/demux-goldens/streams/synthetic-corrupt-tail.json",
        "block": "rf9",
        "sha256": "6bd3ca423fca10e439da1ef8ea4072a46e9c3e289814e7d9525d839d4a73884a"
      },
      {
        "path": "kits/demux-goldens/streams/synthetic-no-timestamps.json",
        "block": "rf10",
        "sha256": "c75effa4e3ab9312f899b1957ed3592ff2ab42c6f9253417e67a051e2615c170"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "711e96948ec7601156668fd797748717304622af3c3d591e4512d83d2afab614",
    "last_5_lines": [
      "negative-control permuted-order: expected FAIL, got FAIL (synthetic-bframe-reorder, 2 field mismatch(es), stream id asserted on every FAIL line)",
      "negative-control nil-tail-permutation: expected FAIL, got FAIL (synthetic-corrupt-tail, 1 field mismatch(es))",
      "negative-control tampered-golden: expected mismatch, got mismatch (goldens/synthetic-no-timestamps.digest.txt: bytes differ)",
      "negative-control corrupt-tail-repair: expected FAIL, got FAIL (synthetic-corrupt-tail, 4 field mismatch(es))",
      "demux-goldens: 3/3 golden digests byte-identical PASS"
    ],
    "receipt_sha256": "67e39f5976302c9f33bf3ca427da728e0b609d95d533eb9fe5949867f3cdb4e8"
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

```text id=rf1
# kits/demux-goldens — W-gdb-024 demux parity golden digest kit (v2.1)

Independent golden digest tables for synthetic interleaved streams, for the demux
parity runner (gorav lane, packet W-gdb-024 @ bridge pin 3eb39d3). Synthetic stream
descriptions only: no media bytes anywhere in this kit.

v2.1 corrects one documentation sentence (review F7); code and goldens are
identical to v2. v2 addressed independent review d713f22a (6 findings). Schema is
`demux-goldens/v2`; v1 goldens are not comparable (digest input changed).

## Layout

- `digests.py` — comparison vocabulary. `Rat`, `packet_line` and `fnv_add` mirror
  `Sources/demux-parity-tests/DemuxParity.swift` @ 2112af0 (sha256 8d64bede)
  (reduced rationals, `pts=.. dts=.. dur=..` lines, FNV-1a with the per-add 0xff
  terminator mix); the review verified this mirror — keep it intact.
  `digest_line` extends the packet line with `seq`, `track`, `frame_type` and
  `corrupt`, so the packet-sequence digest is sensitive to packet identity and
  position: permuting two packets with identical (nil) timestamps also changes
  the digest (review F3).
- `generate.py` — generator. Emits the synthetic stream descriptions
  (`streams/*.json`) and the golden digest tables (`goldens/*.digest.txt`).
  Deterministic: re-running regenerates byte-identical files.
- `check.py` — checker. `--replay` is the packet's acceptance test;
  `--candidate FILE` replays one candidate demuxer's emitted stream description
  against its golden. Every FAIL line starts `FAIL <stream_id>: ...`; exit 0/1.
- `streams/` — three synthetic stream descriptions (generated, committed).
- `goldens/` — three golden digest tables (generated, committed).

## Streams (the packet's three classes)

| stream_id | class | shape |
| --- | --- | --- |
| synthetic-bframe-reorder | bframe-reorder | h264-like GOP 24 / 2 B-frames @ 25 fps + aac-like audio (1024/48000 s frames + one final partial frame), packets emitted in interleaved dts order so pts reorders |
| synthetic-no-timestamps | no-timestamps | intra-only video, pts nil on every 7th frame, pts+dts nil on the final 3 packets |
| synthetic-corrupt-tail | corrupt-tail | the bframe-reorder stream with its last 4 emitted packets corrupt (timestamps stripped, corrupt flag); golden honestly reports pts_monotonic_after_reorder: false (pts hole) and duration_seconds: 99/25 (recoverable prefix), not 4/1 |

## Golden digest row

`{ packet sequence digest, pts/dts order, duration }`, as the packet names it:

- `seq_fnv` — FNV-1a over the emission-order `digest_line` of ALL packets
  (corrupt packets included, with `corrupt=true` and nil timestamps)
- `packets` / `corrupt_tail` — non-corrupt count / corrupt count
- `pts_monotonic_after_reorder` — an actual reorder check (review F2): per
  non-corrupt track, packets are reordered from emission (dts) order to
  presentation order by sorting on pts; the field is `true` iff pts are then
  strictly increasing with a constant cadence and dts is non-decreasing in
  emission order. A wrong-but-unique pts assignment fails the cadence check
  when its values no longer form an arithmetic progression, and fails the dts
  check when it breaks emission order, as does a hole in the pts sequence
  (this is why the corrupt-tail golden reports `false`: its corrupt video
  frame removes one pts). `n/a` when a track has missing pts. Scope limits,
  stated honestly: the check sorts, so it is permutation-invariant - rotating
  a track's exact same pts value set is still a valid reorder and passes;
  the packet sequence digest (seq_fnv) is what binds emission order, and
  timestamps alone cannot validate frame content.
- `pts_reorder_observed` — `true` when a track's emission pts order differs from
  its presentation order (distinguishes a real B-frame reorder from a stream
  that never reorders; review F2)
- `duration_seconds` — see Owner decisions below.

The packet's fixture block carries `"packetOrder": "<deliverable digest>"` — a
placeholder; the real digest values are generated by this kit and live in
`goldens/`, regenerated and verified by `--replay`.

## Owner decisions (packet pins no definition; review F1/F5)

These are kit-chosen definitions, not packet-pinned. The owner decides whether
they stand.

1. **duration_seconds** = max over tracks of the sum of non-corrupt packet
   durations, as a reduced rational. **Corrupt packets are excluded** — their
   durations are unrecoverable by definition — and this exclusion is stated
   here, in `generate.stream_duration`'s docstring, and visible in every golden
   via the `corrupt_tail` count (review F1). Aligned to the packet fixture's
   `durationSeconds: 4.0` semantics: the audio track carries one final partial
   frame so both tracks land exactly on 4.0 s, and the bframe-reorder and
   no-timestamps goldens report `duration_seconds: 4/1`. The corrupt-tail
   golden reports `99/25` — the recoverable duration after its corrupt tail,
   which is the honest value for that class.
2. **Aggregation scope** (`max` across tracks, per-track sum) is unpinned by the
   packet and chosen by this kit (review F5).
3. **Digest input extension** beyond the Swift `Pkt.description` triple (adding
   seq/track/frame_type/corrupt) is a kit choice made under review F3; the
   pinned FNV/Rat mirror itself is unchanged.

## Acceptance test (from the packet)

    python3 kits/demux-goldens/check.py --replay

Expected: exit 0; stdout `demux-goldens: K/K golden digests byte-identical PASS`;
one permuted packet order fails the checker with the stream id (negative control,
runs inside `--replay`; progress goes to stderr so stdout stays the acceptance line).

Negative controls in `--replay`:
1. permuted-order — two emitted packets of the bframe-reorder stream swapped;
   the checker must FAIL with every FAIL line starting `FAIL <stream_id>:`
   (asserted, review F4).
1b. nil-tail-permutation — the last two corrupt-tail packets swapped (all
   timestamps nil); the extended digest input must still catch it (review F3).
2. tampered-golden — one hex digit flipped in a golden; tree compare must detect.
3. corrupt-tail-repair — a candidate that fabricates timestamps for the corrupt
   tail must FAIL.

## Checking a candidate demuxer

Have the candidate emit a stream description in the `streams/*.json` shape
(pts/dts/dur as reduced rationals or null, emission order), then:

    python3 kits/demux-goldens/check.py --candidate candidate.json

Exit 0 and `PASS <stream_id>` iff the candidate reproduces the golden row exactly.

Python 3 stdlib only; no build step. Determinism: JSON with sorted keys, fixed
field order in goldens, exact-rational interleave sorting (fractions.Fraction).

```

```text id=rf2
#!/usr/bin/env python3
"""W-gdb-024 checker (v2): replay(candidateOutput, golden) -> PASS/FAIL, plus --replay.

Modes:
  --replay                 Regenerate everything from generate.py into a temp dir,
                           compare byte-identically against the committed goldens,
                           run the negative controls, print the acceptance line.
  --candidate FILE         Check one candidate stream description (same JSON shape
                           the generator emits) against goldens/<stream_id>.digest.txt.
                           Every FAIL line starts 'FAIL <stream_id>: ...'; exit 0/1.

Acceptance (from the packet): exit 0; stdout
  demux-goldens: K/K golden digests byte-identical PASS
and one permuted packet order fails the checker with the stream id.
python3 stdlib only.
"""
import argparse
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def _tree_files(root, sub):
    base = os.path.join(root, sub)
    out = {}
    for name in sorted(os.listdir(base)):
        path = os.path.join(base, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                out[name] = f.read()
    return out


def compare_trees(committed_root, candidate_root):
    """Byte-compare streams/ and goldens/ between two kit roots.

    Returns (mismatches, golden_count). A golden that regenerates to different
    bytes, or is missing on either side, is a mismatch.
    """
    mismatches = []
    golden_count = 0
    for sub in ("streams", "goldens"):
        a = _tree_files(committed_root, sub)
        b = _tree_files(candidate_root, sub)
        for name in sorted(set(a) | set(b)):
            if sub == "goldens":
                golden_count += 1
            if name not in a:
                mismatches.append("%s/%s: missing from committed kit" % (sub, name))
            elif name not in b:
                mismatches.append("%s/%s: generator did not reproduce" % (sub, name))
            elif a[name] != b[name]:
                mismatches.append("%s/%s: bytes differ" % (sub, name))
    return mismatches, golden_count


def check_stream(stream, golden_bytes):
    """replay(candidateOutput, golden): recompute the golden row from the
    candidate stream description and compare to the golden, line by line.
    Returns a list of failure strings (empty == PASS)."""
    got = generate.golden_text(stream)
    want = golden_bytes.decode("utf-8")
    failures = []
    got_lines, want_lines = got.splitlines(), want.splitlines()
    for i in range(max(len(got_lines), len(want_lines))):
        g = got_lines[i] if i < len(got_lines) else "<missing>"
        w = want_lines[i] if i < len(want_lines) else "<missing>"
        if g != w:
            failures.append("line %d: golden %r vs candidate %r" % (i + 1, w, g))
    return failures


def format_failures(stream_id, failures):
    """The checker's single FAIL-output contract: every line names the stream id.
    Used by run_candidate and asserted by the permuted-order negative control."""
    return ["FAIL %s: %s" % (stream_id, f) for f in failures]


def _load_stream(path):
    with open(path) as f:
        return json.load(f)


def _golden_path(root, stream_id):
    return os.path.join(root, "goldens", stream_id + ".digest.txt")


def negative_controls(log):
    """The packet's named negative control, plus three structural ones.

    Each must produce an expected failure; any unexpected pass aborts --replay.
    Returns a list of error strings (empty == all controls behaved).
    """
    errors = []

    # 1. Permuted packet order (the control the packet names): swap two emitted
    #    packets of the bframe-reorder stream; the checker must FAIL and every
    #    FAIL line must start with the stream id (review finding F4).
    stream = _load_stream(os.path.join(HERE, "streams", "synthetic-bframe-reorder.json"))
    stream["packets"][10], stream["packets"][11] = stream["packets"][11], stream["packets"][10]
    with open(_golden_path(HERE, stream["stream_id"]), "rb") as f:
        golden = f.read()
    fails = check_stream(stream, golden)
    lines = format_failures(stream["stream_id"], fails)
    if fails and all(l.startswith("FAIL %s:" % stream["stream_id"]) for l in lines):
        log("negative-control permuted-order: expected FAIL, got FAIL "
            "(%s, %d field mismatch(es), stream id asserted on every FAIL line)"
            % (stream["stream_id"], len(fails)))
    else:
        errors.append("negative-control permuted-order: permuted order was NOT rejected "
                      "with the stream id")

    # 1b. Identical-timestamp permutation (review finding F3): swap the last two
    #     corrupt-tail packets (all timestamps nil); the digest input carries
    #     seq/track/type/corrupt, so the swap must still FAIL.
    stream = _load_stream(os.path.join(HERE, "streams", "synthetic-corrupt-tail.json"))
    stream["packets"][-1], stream["packets"][-2] = stream["packets"][-2], stream["packets"][-1]
    with open(_golden_path(HERE, stream["stream_id"]), "rb") as f:
        golden = f.read()
    fails = check_stream(stream, golden)
    if fails:
        log("negative-control nil-tail-permutation: expected FAIL, got FAIL "
            "(%s, %d field mismatch(es))" % (stream["stream_id"], len(fails)))
    else:
        errors.append("negative-control nil-tail-permutation: identical-timestamp "
                      "swap was NOT rejected")

    # 2. Tampered golden: flip one hex digit in a golden; tree compare must
    #    detect the drift against a fresh regeneration.
    with tempfile.TemporaryDirectory() as tampered, tempfile.TemporaryDirectory() as regen:
        generate.write_all(tampered)
        generate.write_all(regen)
        gpath = _golden_path(tampered, "synthetic-no-timestamps")
        with open(gpath) as f:
            text = f.read()
        if "seq_fnv: 0" in text:
            text = text.replace("seq_fnv: 0", "seq_fnv: 1", 1)
        else:
            text = text.replace("seq_fnv: ", "seq_fnv: x", 1)
        with open(gpath, "w") as f:
            f.write(text)
        mism, _ = compare_trees(tampered, regen)
        if any("synthetic-no-timestamps" in m for m in mism):
            log("negative-control tampered-golden: expected mismatch, got mismatch (%s)" % mism[0])
        else:
            errors.append("negative-control tampered-golden: tamper was NOT detected")

    # 3. Corrupt-tail acceptance control: a candidate that 'repairs' the corrupt
    #    tail by fabricating timestamps must FAIL against the golden.
    stream = _load_stream(os.path.join(HERE, "streams", "synthetic-corrupt-tail.json"))
    for p in stream["packets"]:
        if p.get("corrupt"):
            p["pts"] = "9999/1"
            p["dts"] = "9999/1"
            p["dur"] = "1/25"
            p["corrupt"] = False
    with open(_golden_path(HERE, stream["stream_id"]), "rb") as f:
        golden = f.read()
    fails = check_stream(stream, golden)
    if fails:
        log("negative-control corrupt-tail-repair: expected FAIL, got FAIL "
            "(%s, %d field mismatch(es))" % (stream["stream_id"], len(fails)))
    else:
        errors.append("negative-control corrupt-tail-repair: fabricated tail was NOT rejected")

    return errors


def run_replay():
    def log(msg):
        print(msg, file=sys.stderr)

    with tempfile.TemporaryDirectory() as regen:
        generate.write_all(regen)
        mismatches, k = compare_trees(HERE, regen)

    control_errors = negative_controls(log)

    if not mismatches and not control_errors:
        print("demux-goldens: %d/%d golden digests byte-identical PASS" % (k, k))
        return 0
    for m in mismatches:
        log("replay mismatch: " + m)
    for e in control_errors:
        log("control error: " + e)
    print("demux-goldens: %d/%d golden digests byte-identical FAIL" % (k - len(mismatches), k))
    return 1


def run_candidate(path):
    stream = _load_stream(path)
    sid = stream.get("stream_id", "<unknown>")
    gpath = _golden_path(HERE, sid)
    if not os.path.isfile(gpath):
        print("FAIL %s: no golden digest table at %s" % (sid, gpath))
        return 1
    with open(gpath, "rb") as f:
        golden = f.read()
    fails = check_stream(stream, golden)
    if fails:
        for line in format_failures(sid, fails):
            print(line)
        return 1
    print("PASS %s" % sid)
    return 0


def main():
    ap = argparse.ArgumentParser(description="W-gdb-024 demux-goldens checker")
    ap.add_argument("--replay", action="store_true",
                    help="regenerate and verify byte-identical goldens + negative controls")
    ap.add_argument("--candidate", metavar="FILE",
                    help="check one candidate stream description against its golden")
    args = ap.parse_args()
    if args.replay:
        return run_replay()
    if args.candidate:
        return run_candidate(args.candidate)
    ap.error("one of --replay or --candidate is required")


if __name__ == "__main__":
    sys.exit(main())

```

```text id=rf3
"""Shared digest vocabulary for the W-gdb-024 demux-goldens kit (v2).

Rat, packet_line and fnv_add mirror the comparison vocabulary of
Sources/demux-parity-tests/DemuxParity.swift @ 2112af0d60df16c5473173b664903f76ce54173e
(sha256 8d64bede): reduced rationals (Rat), "pts=.. dts=.. dur=.." packet lines
(Pkt.description), FNV-1a with the per-add 0xff terminator mix (struct Fnv).
Independently reviewed and verified correct; keep this mirror intact.

digest_line extends Pkt.description with seq/track/frame_type/corrupt so that the
packet-sequence digest is sensitive to packet identity and position, not only to
the timestamp triple: permuting two packets with identical (nil) timestamps also
changes the digest (review finding F3).

python3 stdlib only. Deterministic: same input -> same digest on any platform.
"""

FNV_OFFSET = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
MASK64 = (1 << 64) - 1


def fnv_add(h, s):
    """One Fnv.add(s): FNV-1a over the utf8 bytes, then the 0xff terminator mix."""
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * FNV_PRIME) & MASK64
    h ^= 0xFF
    h = (h * FNV_PRIME) & MASK64
    return h


def _gcd(a, b):
    while b:
        a, b = b, a % b
    return a


class Rat:
    """Reduced rational, matching the Swift Rat init (0 -> 0/1, d > 0 assumed)."""

    __slots__ = ("n", "d")

    def __init__(self, n, d):
        if d == 0:
            raise ValueError("zero denominator")
        a = -n if n < 0 else n
        g = _gcd(a, d) if a else 0
        if a == 0 or n == 0:
            self.n, self.d = 0, 1
        else:
            self.n, self.d = n // g, d // g

    def __str__(self):
        return "%d/%d" % (self.n, self.d)


def packet_line(pkt):
    """Swift Pkt.description: 'pts=<rat|nil> dts=<rat|nil> dur=<rat|nil>'."""
    def f(v):
        return v if v is not None else "nil"
    return "pts=%s dts=%s dur=%s" % (f(pkt["pts"]), f(pkt["dts"]), f(pkt["dur"]))


def digest_line(pkt):
    """Full digest input for one packet: identity + position + timestamp triple."""
    return "seq=%d track=%d type=%s %s corrupt=%s" % (
        pkt["seq"], pkt["track"], pkt["frame_type"], packet_line(pkt),
        "true" if pkt.get("corrupt") else "false")


def seq_fnv(packets):
    """FNV over the emission-order digest lines of ALL packets, corrupt included
    (corrupt packets carry corrupt=true and nil timestamps in their line)."""
    h = FNV_OFFSET
    for p in packets:
        h = fnv_add(h, digest_line(p))
    return "%016x" % h

```

```text id=rf4
#!/usr/bin/env python3
"""W-gdb-024 generator (v2): synthetic interleaved stream descriptions + golden
digest tables.

Emits three synthetic streams covering the packet's three classes:
  synthetic-bframe-reorder   h264-like GOP (gop=24, bframes=2) + aac-like audio,
                             packets in interleaved decode (dts) order so pts reorders
  synthetic-no-timestamps    intra-only video, pts missing on every 7th frame,
                             pts+dts missing on the final 3 packets
  synthetic-corrupt-tail     the bframe-reorder stream with its last 4 emitted
                             packets corrupt (timestamps stripped, corrupt flag set)

No media bytes anywhere: descriptions are (pts, dts, dur) reduced rationals only.
Deterministic, python3 stdlib only; re-running regenerates byte-identical files.
That property is the kit's acceptance test (check.py --replay).

v2 changes (review d713f22a): audio lands exactly on the 4.0 s stream duration
(final partial frame), digest input includes seq/track/type/corrupt, and the
pts-order field performs an actual reorder check (see pts_order_check).
"""
import json
import os
import sys
from fractions import Fraction

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from digests import Rat, seq_fnv  # noqa: E402

SCHEMA = "demux-goldens/v2"
HERE = os.path.dirname(os.path.abspath(__file__))

FPS = 25
GOP = 24
BFRAMES = 2
DURATION_S = 4
AAC_NUM, AAC_DEN = 1024, 48000  # aac-like frame duration: 1024/48000 s


def gop_types(count):
    """Presentation-order frame types: I at GOP starts, anchors every bframes+1."""
    types = []
    for i in range(count):
        if i % GOP == 0:
            types.append("I")
        elif (i % GOP) % (BFRAMES + 1) == 0:
            types.append("P")
        else:
            types.append("B")
    return types


def decode_order(types):
    """Presentation -> decode order: emit each anchor, then its following B frames.

    I B B P B B P ... -> I P B B P B B ... (classic B-frame reorder).
    """
    order, buf = [], []
    for i, t in enumerate(types):
        if t == "B":
            buf.append(i)
        else:
            order.append(i)
            order.extend(buf)
            buf = []
    order.extend(buf)
    return order


def _rat_str(n, d):
    return str(Rat(n, d))


def video_packets(count, bframes):
    """Video track packets in decode (dts) order; pts/dts/dur in seconds."""
    types = gop_types(count)
    order = decode_order(types) if bframes else list(range(count))
    pkts = []
    for decode_pos, pres in enumerate(order):
        pkts.append({
            "track": 0,
            "frame_type": types[pres],
            "pts": _rat_str(pres, FPS),
            "dts": _rat_str(decode_pos, FPS),
            "dur": _rat_str(1, FPS),
            "corrupt": False,
        })
    return pkts


def audio_packets(duration_s):
    """Aac-like audio: pts == dts, constant 1024/48000 s frames, plus one final
    partial frame so the track lands exactly on duration_s (the packet fixture's
    4.0 s semantics)."""
    total = duration_s * AAC_DEN  # samples
    full, rem = divmod(total, AAC_NUM)
    count = full + (1 if rem else 0)
    pkts = []
    for i in range(count):
        dur = AAC_NUM if i < full else rem
        pkts.append({
            "track": 1,
            "frame_type": "A",
            "pts": _rat_str(i * AAC_NUM, AAC_DEN),
            "dts": _rat_str(i * AAC_NUM, AAC_DEN),
            "dur": _rat_str(dur, AAC_DEN),
            "corrupt": False,
        })
    return pkts


def interleave(track_lists):
    """Merge tracks into emission order by exact dts; ties -> lower track index.

    Packets without dts append after all timestamped packets, in creation order.
    """
    stamped, unstamped = [], []
    for tindex, pkts in enumerate(track_lists):
        for p in pkts:
            if p["dts"] is not None:
                n, d = p["dts"].split("/")
                stamped.append((Fraction(int(n), int(d)), tindex, p))
            else:
                unstamped.append(p)
    stamped.sort(key=lambda x: (x[0], x[1]))
    out = [p for _, _, p in stamped] + unstamped
    for i, p in enumerate(out):
        p["seq"] = i
    return out


def build_bframe_reorder(stream_id):
    nframes = FPS * DURATION_S
    packets = interleave([video_packets(nframes, True), audio_packets(DURATION_S)])
    return {
        "schema": SCHEMA,
        "stream_id": stream_id,
        "class": "bframe-reorder",
        "params": {"video": {"codec": "h264-like", "gop": GOP, "bframes": BFRAMES,
                             "fps": FPS, "timebase": "1/%d" % FPS},
                   "audio": {"codec": "aac-like", "frame": "%d/%d s" % (AAC_NUM, AAC_DEN),
                             "note": "final partial frame lands the track exactly on "
                                     "the stream duration"}},
        "tracks": [
            {"index": 0, "kind": "video", "frames": nframes},
            {"index": 1, "kind": "audio", "frames": len(audio_packets(DURATION_S))},
        ],
        "packets": packets,
    }


def build_no_timestamps(stream_id):
    nframes = FPS * DURATION_S
    pkts = video_packets(nframes, False)  # intra-only, pts == dts
    for i, p in enumerate(pkts):
        if i >= nframes - 3:
            p["pts"] = None
            p["dts"] = None
        elif i % 7 == 0 and i > 0:
            p["pts"] = None
    packets = interleave([pkts])
    return {
        "schema": SCHEMA,
        "stream_id": stream_id,
        "class": "no-timestamps",
        "params": {"video": {"codec": "h264-like intra", "gop": 1, "bframes": 0,
                             "fps": FPS, "timebase": "1/%d" % FPS},
                   "missing": "pts nil on every 7th frame; pts+dts nil on final 3"},
        "tracks": [{"index": 0, "kind": "video", "frames": nframes}],
        "packets": packets,
    }


def build_corrupt_tail(stream_id, tail=4):
    stream = build_bframe_reorder(stream_id)
    stream["class"] = "corrupt-tail"
    stream["params"]["corrupt_tail"] = ("last %d emitted packets truncated: "
                                        "timestamps stripped, corrupt flag set" % tail)
    for p in stream["packets"][-tail:]:
        p["pts"] = None
        p["dts"] = None
        p["dur"] = None
        p["corrupt"] = True
    return stream


def _parse_rat(s):
    n, d = s.split("/")
    return Fraction(int(n), int(d))


def pts_order_check(stream):
    """Actual reorder check (review finding F2), per non-corrupt track:

    reorder the track's packets from emission (dts) order to presentation order
    by sorting on pts, then require
      1. pts strictly increasing after the reorder, and
      2. constant pts cadence (all consecutive deltas equal), and
      3. dts non-decreasing in emission order.
    'n/a' when a track has any missing pts or fewer than 2 timestamped packets.
    A wrong-but-unique pts assignment fails (2) when its values no longer form
    an arithmetic progression, and fails (3) when it breaks dts emission order.
    The check sorts, so it is permutation-invariant: rotating a track's exact
    same pts value set is still a valid reorder and passes; seq_fnv is what
    binds emission order. Timestamps alone cannot validate frame content;
    see README.
    """
    by_track = {}
    for p in stream["packets"]:
        if not p.get("corrupt"):
            by_track.setdefault(p["track"], []).append(p)
    verdicts = []
    for pkts in by_track.values():
        pts = [p["pts"] for p in pkts]
        if any(x is None for x in pts) or len(pts) < 2:
            verdicts.append("n/a")
            continue
        vals = sorted(_parse_rat(x) for x in pts)
        increasing = all(a < b for a, b in zip(vals, vals[1:]))
        deltas = [b - a for a, b in zip(vals, vals[1:])]
        constant_cadence = len(set(deltas)) == 1
        dts = [_parse_rat(p["dts"]) for p in pkts if p["dts"] is not None]
        dts_ordered = all(a <= b for a, b in zip(dts, dts[1:]))
        verdicts.append("true" if (increasing and constant_cadence and dts_ordered)
                        else "false")
    if not verdicts:
        return "n/a"
    if all(v == "true" for v in verdicts):
        return "true"
    if any(v == "false" for v in verdicts):
        return "false"
    return "n/a"


def pts_reorder_observed(stream):
    """True when at least one non-corrupt track's emission pts order differs from
    its presentation (sorted pts) order, i.e. an actual B-frame-style reorder."""
    by_track = {}
    for p in stream["packets"]:
        if not p.get("corrupt"):
            by_track.setdefault(p["track"], []).append(p)
    for pkts in by_track.values():
        pts = [p["pts"] for p in pkts]
        if any(x is None for x in pts):
            continue
        vals = [_parse_rat(x) for x in pts]
        if vals != sorted(vals):
            return "true"
    return "false"


def stream_duration(stream):
    """Max per-track sum of packet durations over NON-CORRUPT packets (corrupt
    packets are excluded; their duration is unrecoverable by definition).
    Kit-chosen aggregation scope; the packet pins no definition (README, F1/F5)."""
    totals = {}
    for p in stream["packets"]:
        if p.get("corrupt") or p["dur"] is None:
            continue
        totals[p["track"]] = totals.get(p["track"], Fraction(0)) + _parse_rat(p["dur"])
    if not totals:
        return str(Rat(0, 1))
    m = max(totals.values())
    return str(Rat(m.numerator, m.denominator))


def golden_text(stream):
    """Golden digest row: packet sequence digest, pts/dts order, duration."""
    good = [p for p in stream["packets"] if not p.get("corrupt")]
    lines = [
        "schema: %s" % SCHEMA,
        "stream: %s" % stream["stream_id"],
        "class: %s" % stream["class"],
        "packets: %d" % len(good),
        "corrupt_tail: %d" % sum(1 for p in stream["packets"] if p.get("corrupt")),
        "seq_fnv: %s" % seq_fnv(stream["packets"]),
        "pts_monotonic_after_reorder: %s" % pts_order_check(stream),
        "pts_reorder_observed: %s" % pts_reorder_observed(stream),
        "duration_seconds: %s" % stream_duration(stream),
    ]
    return "\n".join(lines) + "\n"


def build_all():
    return [
        build_bframe_reorder("synthetic-bframe-reorder"),
        build_no_timestamps("synthetic-no-timestamps"),
        build_corrupt_tail("synthetic-corrupt-tail"),
    ]


def write_all(outdir):
    streams_dir = os.path.join(outdir, "streams")
    goldens_dir = os.path.join(outdir, "goldens")
    os.makedirs(streams_dir, exist_ok=True)
    os.makedirs(goldens_dir, exist_ok=True)
    for stream in build_all():
        sid = stream["stream_id"]
        with open(os.path.join(streams_dir, sid + ".json"), "w") as f:
            f.write(json.dumps(stream, indent=1, sort_keys=True) + "\n")
        with open(os.path.join(goldens_dir, sid + ".digest.txt"), "w") as f:
            f.write(golden_text(stream))


def main():
    write_all(HERE)
    print("demux-goldens: generated 3 stream descriptions + 3 golden digest tables (v2)")


if __name__ == "__main__":
    main()

```

```text id=rf5
schema: demux-goldens/v2
stream: synthetic-bframe-reorder
class: bframe-reorder
packets: 288
corrupt_tail: 0
seq_fnv: 1089c4dff6c1f8f2
pts_monotonic_after_reorder: true
pts_reorder_observed: true
duration_seconds: 4/1

```

```text id=rf6
schema: demux-goldens/v2
stream: synthetic-corrupt-tail
class: corrupt-tail
packets: 284
corrupt_tail: 4
seq_fnv: fe3b555418628054
pts_monotonic_after_reorder: false
pts_reorder_observed: true
duration_seconds: 99/25

```

```text id=rf7
schema: demux-goldens/v2
stream: synthetic-no-timestamps
class: no-timestamps
packets: 100
corrupt_tail: 0
seq_fnv: 233e15667c3515f3
pts_monotonic_after_reorder: n/a
pts_reorder_observed: false
duration_seconds: 4/1

```

```text id=rf8
{
 "class": "bframe-reorder",
 "packets": [
  {
   "corrupt": false,
   "dts": "0/1",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "0/1",
   "seq": 0,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "0/1",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "0/1",
   "seq": 1,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/375",
   "seq": 2,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "3/25",
   "seq": 3,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/375",
   "seq": 4,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/125",
   "seq": 5,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "2/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "1/25",
   "seq": 6,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "32/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/375",
   "seq": 7,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/75",
   "seq": 8,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "3/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "2/25",
   "seq": 9,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/125",
   "seq": 10,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "56/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/375",
   "seq": 11,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "4/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "6/25",
   "seq": 12,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "64/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "64/375",
   "seq": 13,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "24/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "24/125",
   "seq": 14,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "4/25",
   "seq": 15,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/75",
   "seq": 16,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "88/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "88/375",
   "seq": 17,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "6/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "1/5",
   "seq": 18,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "32/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/125",
   "seq": 19,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "104/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "104/375",
   "seq": 20,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "7/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "9/25",
   "seq": 21,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "112/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "112/375",
   "seq": 22,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "7/25",
   "seq": 23,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "8/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/25",
   "seq": 24,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "128/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "128/375",
   "seq": 25,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "9/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "8/25",
   "seq": 26,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "136/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "136/375",
   "seq": 27,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "48/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "48/125",
   "seq": 28,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "2/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "12/25",
   "seq": 29,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "152/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "152/375",
   "seq": 30,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "32/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/75",
   "seq": 31,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "11/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "2/5",
   "seq": 32,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "56/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/125",
   "seq": 33,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "176/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "176/375",
   "seq": 34,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "12/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "11/25",
   "seq": 35,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "184/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "184/375",
   "seq": 36,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "64/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "64/125",
   "seq": 37,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "13/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "3/5",
   "seq": 38,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "8/15",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/15",
   "seq": 39,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "208/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "208/375",
   "seq": 40,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "14/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "13/25",
   "seq": 41,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "72/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "72/125",
   "seq": 42,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "224/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "224/375",
   "seq": 43,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "3/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "14/25",
   "seq": 44,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "232/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "232/375",
   "seq": 45,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "16/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "18/25",
   "seq": 46,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/25",
   "seq": 47,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "248/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "248/375",
   "seq": 48,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "17/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "16/25",
   "seq": 49,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "256/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "256/375",
   "seq": 50,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "88/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "88/125",
   "seq": 51,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "18/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "17/25",
   "seq": 52,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "272/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "272/375",
   "seq": 53,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "56/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/75",
   "seq": 54,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "19/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "21/25",
   "seq": 55,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "96/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "96/125",
   "seq": 56,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "296/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "296/375",
   "seq": 57,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "4/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "19/25",
   "seq": 58,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "304/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "304/375",
   "seq": 59,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "104/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "104/125",
   "seq": 60,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "21/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "4/5",
   "seq": 61,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "64/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "64/75",
   "seq": 62,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "328/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "328/375",
   "seq": 63,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "22/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "24/25",
   "seq": 64,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "112/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "112/125",
   "seq": 65,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "344/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "344/375",
   "seq": 66,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "23/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "22/25",
   "seq": 67,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "352/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "352/375",
   "seq": 68,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "24/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "23/25",
   "seq": 69,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "24/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "24/25",
   "seq": 70,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "368/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "368/375",
   "seq": 71,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1/1",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "27/25",
   "seq": 72,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "376/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "376/375",
   "seq": 73,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "128/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "128/125",
   "seq": 74,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "26/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "1/1",
   "seq": 75,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "392/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "392/375",
   "seq": 76,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "16/15",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/15",
   "seq": 77,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "27/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "26/25",
   "seq": 78,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "136/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "136/125",
   "seq": 79,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "416/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "416/375",
   "seq": 80,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "28/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "6/5",
   "seq": 81,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "424/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "424/375",
   "seq": 82,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "144/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "144/125",
   "seq": 83,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "29/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "28/25",
   "seq": 84,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "88/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "88/75",
   "seq": 85,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "448/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "448/375",
   "seq": 86,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "6/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "29/25",
   "seq": 87,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "152/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "152/125",
   "seq": 88,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "464/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "464/375",
   "seq": 89,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "31/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "33/25",
   "seq": 90,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "472/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "472/375",
   "seq": 91,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "32/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "31/25",
   "seq": 92,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "32/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/25",
   "seq": 93,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "488/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "488/375",
   "seq": 94,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "33/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "32/25",
   "seq": 95,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "496/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "496/375",
   "seq": 96,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "168/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "168/125",
   "seq": 97,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "34/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "36/25",
   "seq": 98,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "512/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "512/375",
   "seq": 99,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "104/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "104/75",
   "seq": 100,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "7/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "34/25",
   "seq": 101,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "176/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "176/125",
   "seq": 102,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "536/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "536/375",
   "seq": 103,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "36/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "7/5",
   "seq": 104,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "544/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "544/375",
   "seq": 105,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "184/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "184/125",
   "seq": 106,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "37/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "39/25",
   "seq": 107,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "112/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "112/75",
   "seq": 108,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "568/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "568/375",
   "seq": 109,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "38/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "37/25",
   "seq": 110,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "192/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "192/125",
   "seq": 111,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "584/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "584/375",
   "seq": 112,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "39/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "38/25",
   "seq": 113,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "592/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "592/375",
   "seq": 114,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "42/25",
   "seq": 115,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "8/5",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/5",
   "seq": 116,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "608/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "608/375",
   "seq": 117,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "41/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "8/5",
   "seq": 118,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "616/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "616/375",
   "seq": 119,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "208/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "208/125",
   "seq": 120,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "42/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "41/25",
   "seq": 121,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "632/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "632/375",
   "seq": 122,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "128/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "128/75",
   "seq": 123,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "43/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "9/5",
   "seq": 124,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "216/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "216/125",
   "seq": 125,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "656/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "656/375",
   "seq": 126,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "44/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "43/25",
   "seq": 127,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "664/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "664/375",
   "seq": 128,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "224/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "224/125",
   "seq": 129,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "9/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "44/25",
   "seq": 130,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "136/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "136/75",
   "seq": 131,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "688/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "688/375",
   "seq": 132,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "46/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "48/25",
   "seq": 133,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "232/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "232/125",
   "seq": 134,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "704/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "704/375",
   "seq": 135,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "47/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "46/25",
   "seq": 136,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "712/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "712/375",
   "seq": 137,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "48/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "47/25",
   "seq": 138,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "48/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "48/25",
   "seq": 139,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "728/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "728/375",
   "seq": 140,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "49/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "51/25",
   "seq": 141,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "736/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "736/375",
   "seq": 142,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "248/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "248/125",
   "seq": 143,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "2/1",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "49/25",
   "seq": 144,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "752/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "752/375",
   "seq": 145,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "152/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "152/75",
   "seq": 146,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "51/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "2/1",
   "seq": 147,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "256/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "256/125",
   "seq": 148,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "776/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "776/375",
   "seq": 149,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "52/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "54/25",
   "seq": 150,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "784/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "784/375",
   "seq": 151,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "264/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "264/125",
   "seq": 152,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "53/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "52/25",
   "seq": 153,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "32/15",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/15",
   "seq": 154,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "808/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "808/375",
   "seq": 155,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "54/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "53/25",
   "seq": 156,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "272/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "272/125",
   "seq": 157,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "824/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "824/375",
   "seq": 158,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "11/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "57/25",
   "seq": 159,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "832/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "832/375",
   "seq": 160,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "56/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "11/5",
   "seq": 161,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "56/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/25",
   "seq": 162,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "848/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "848/375",
   "seq": 163,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "57/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "56/25",
   "seq": 164,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "856/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "856/375",
   "seq": 165,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "288/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "288/125",
   "seq": 166,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "58/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "12/5",
   "seq": 167,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "872/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "872/375",
   "seq": 168,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "176/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "176/75",
   "seq": 169,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "59/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "58/25",
   "seq": 170,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "296/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "296/125",
   "seq": 171,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "896/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "896/375",
   "seq": 172,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "12/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "59/25",
   "seq": 173,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "904/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "904/375",
   "seq": 174,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "304/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "304/125",
   "seq": 175,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "61/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "63/25",
   "seq": 176,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "184/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "184/75",
   "seq": 177,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "928/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "928/375",
   "seq": 178,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "62/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "61/25",
   "seq": 179,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "312/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "312/125",
   "seq": 180,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "944/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "944/375",
   "seq": 181,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "63/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "62/25",
   "seq": 182,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "952/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "952/375",
   "seq": 183,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "64/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "66/25",
   "seq": 184,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "64/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "64/25",
   "seq": 185,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "968/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "968/375",
   "seq": 186,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "13/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "64/25",
   "seq": 187,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "976/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "976/375",
   "seq": 188,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "328/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "328/125",
   "seq": 189,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "66/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "13/5",
   "seq": 190,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "992/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "992/375",
   "seq": 191,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/3",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/3",
   "seq": 192,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "67/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "69/25",
   "seq": 193,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "336/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "336/125",
   "seq": 194,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1016/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1016/375",
   "seq": 195,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "68/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "67/25",
   "seq": 196,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1024/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1024/375",
   "seq": 197,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "344/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "344/125",
   "seq": 198,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "69/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "68/25",
   "seq": 199,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "208/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "208/75",
   "seq": 200,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1048/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1048/375",
   "seq": 201,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "14/5",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "72/25",
   "seq": 202,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "352/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "352/125",
   "seq": 203,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1064/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1064/375",
   "seq": 204,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "71/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "14/5",
   "seq": 205,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1072/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1072/375",
   "seq": 206,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "72/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "71/25",
   "seq": 207,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "72/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "72/25",
   "seq": 208,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1088/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1088/375",
   "seq": 209,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "73/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "3/1",
   "seq": 210,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1096/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1096/375",
   "seq": 211,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "368/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "368/125",
   "seq": 212,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "74/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "73/25",
   "seq": 213,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1112/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1112/375",
   "seq": 214,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "224/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "224/75",
   "seq": 215,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "3/1",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "74/25",
   "seq": 216,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "376/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "376/125",
   "seq": 217,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1136/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1136/375",
   "seq": 218,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "76/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "78/25",
   "seq": 219,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1144/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1144/375",
   "seq": 220,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "384/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "384/125",
   "seq": 221,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "77/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "76/25",
   "seq": 222,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "232/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "232/75",
   "seq": 223,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1168/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1168/375",
   "seq": 224,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "78/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "77/25",
   "seq": 225,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "392/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "392/125",
   "seq": 226,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1184/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1184/375",
   "seq": 227,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "79/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "81/25",
   "seq": 228,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1192/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1192/375",
   "seq": 229,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "16/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "79/25",
   "seq": 230,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/5",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/5",
   "seq": 231,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1208/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1208/375",
   "seq": 232,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "81/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "16/5",
   "seq": 233,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1216/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1216/375",
   "seq": 234,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "408/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "408/125",
   "seq": 235,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "82/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "84/25",
   "seq": 236,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1232/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1232/375",
   "seq": 237,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "248/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "248/75",
   "seq": 238,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "83/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "82/25",
   "seq": 239,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "416/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "416/125",
   "seq": 240,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1256/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1256/375",
   "seq": 241,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "84/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "83/25",
   "seq": 242,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1264/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1264/375",
   "seq": 243,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "424/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "424/125",
   "seq": 244,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "17/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "87/25",
   "seq": 245,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "256/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "256/75",
   "seq": 246,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1288/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1288/375",
   "seq": 247,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "86/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "17/5",
   "seq": 248,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "432/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "432/125",
   "seq": 249,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1304/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1304/375",
   "seq": 250,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "87/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "86/25",
   "seq": 251,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1312/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1312/375",
   "seq": 252,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "88/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "18/5",
   "seq": 253,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "88/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "88/25",
   "seq": 254,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1328/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1328/375",
   "seq": 255,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "89/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "88/25",
   "seq": 256,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1336/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1336/375",
   "seq": 257,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "448/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "448/125",
   "seq": 258,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "18/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "89/25",
   "seq": 259,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1352/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1352/375",
   "seq": 260,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "272/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "272/75",
   "seq": 261,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "91/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "93/25",
   "seq": 262,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "456/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "456/125",
   "seq": 263,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1376/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1376/375",
   "seq": 264,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "92/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "91/25",
   "seq": 265,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1384/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1384/375",
   "seq": 266,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "464/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "464/125",
   "seq": 267,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "93/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "92/25",
   "seq": 268,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "56/15",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/15",
   "seq": 269,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1408/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1408/375",
   "seq": 270,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "94/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "96/25",
   "seq": 271,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "472/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "472/125",
   "seq": 272,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1424/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1424/375",
   "seq": 273,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "19/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "94/25",
   "seq": 274,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1432/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1432/375",
   "seq": 275,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "96/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "19/5",
   "seq": 276,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "96/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "96/25",
   "seq": 277,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1448/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1448/375",
   "seq": 278,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "97/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "99/25",
   "seq": 279,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1456/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1456/375",
   "seq": 280,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "488/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "488/125",
   "seq": 281,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "98/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "97/25",
   "seq": 282,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1472/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1472/375",
   "seq": 283,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "296/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "296/75",
   "seq": 284,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "99/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "98/25",
   "seq": 285,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "496/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "496/125",
   "seq": 286,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1496/375",
   "dur": "4/375",
   "frame_type": "A",
   "pts": "1496/375",
   "seq": 287,
   "track": 1
  }
 ],
 "params": {
  "audio": {
   "codec": "aac-like",
   "frame": "1024/48000 s",
   "note": "final partial frame lands the track exactly on the stream duration"
  },
  "video": {
   "bframes": 2,
   "codec": "h264-like",
   "fps": 25,
   "gop": 24,
   "timebase": "1/25"
  }
 },
 "schema": "demux-goldens/v2",
 "stream_id": "synthetic-bframe-reorder",
 "tracks": [
  {
   "frames": 100,
   "index": 0,
   "kind": "video"
  },
  {
   "frames": 188,
   "index": 1,
   "kind": "audio"
  }
 ]
}

```

```text id=rf9
{
 "class": "corrupt-tail",
 "packets": [
  {
   "corrupt": false,
   "dts": "0/1",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "0/1",
   "seq": 0,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "0/1",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "0/1",
   "seq": 1,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/375",
   "seq": 2,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "3/25",
   "seq": 3,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/375",
   "seq": 4,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/125",
   "seq": 5,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "2/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "1/25",
   "seq": 6,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "32/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/375",
   "seq": 7,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/75",
   "seq": 8,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "3/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "2/25",
   "seq": 9,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/125",
   "seq": 10,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "56/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/375",
   "seq": 11,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "4/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "6/25",
   "seq": 12,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "64/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "64/375",
   "seq": 13,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "24/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "24/125",
   "seq": 14,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "4/25",
   "seq": 15,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/75",
   "seq": 16,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "88/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "88/375",
   "seq": 17,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "6/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "1/5",
   "seq": 18,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "32/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/125",
   "seq": 19,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "104/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "104/375",
   "seq": 20,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "7/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "9/25",
   "seq": 21,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "112/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "112/375",
   "seq": 22,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "7/25",
   "seq": 23,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "8/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/25",
   "seq": 24,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "128/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "128/375",
   "seq": 25,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "9/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "8/25",
   "seq": 26,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "136/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "136/375",
   "seq": 27,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "48/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "48/125",
   "seq": 28,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "2/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "12/25",
   "seq": 29,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "152/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "152/375",
   "seq": 30,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "32/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/75",
   "seq": 31,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "11/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "2/5",
   "seq": 32,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "56/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/125",
   "seq": 33,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "176/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "176/375",
   "seq": 34,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "12/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "11/25",
   "seq": 35,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "184/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "184/375",
   "seq": 36,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "64/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "64/125",
   "seq": 37,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "13/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "3/5",
   "seq": 38,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "8/15",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/15",
   "seq": 39,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "208/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "208/375",
   "seq": 40,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "14/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "13/25",
   "seq": 41,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "72/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "72/125",
   "seq": 42,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "224/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "224/375",
   "seq": 43,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "3/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "14/25",
   "seq": 44,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "232/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "232/375",
   "seq": 45,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "16/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "18/25",
   "seq": 46,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/25",
   "seq": 47,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "248/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "248/375",
   "seq": 48,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "17/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "16/25",
   "seq": 49,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "256/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "256/375",
   "seq": 50,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "88/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "88/125",
   "seq": 51,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "18/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "17/25",
   "seq": 52,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "272/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "272/375",
   "seq": 53,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "56/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/75",
   "seq": 54,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "19/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "21/25",
   "seq": 55,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "96/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "96/125",
   "seq": 56,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "296/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "296/375",
   "seq": 57,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "4/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "19/25",
   "seq": 58,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "304/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "304/375",
   "seq": 59,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "104/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "104/125",
   "seq": 60,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "21/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "4/5",
   "seq": 61,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "64/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "64/75",
   "seq": 62,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "328/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "328/375",
   "seq": 63,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "22/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "24/25",
   "seq": 64,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "112/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "112/125",
   "seq": 65,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "344/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "344/375",
   "seq": 66,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "23/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "22/25",
   "seq": 67,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "352/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "352/375",
   "seq": 68,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "24/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "23/25",
   "seq": 69,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "24/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "24/25",
   "seq": 70,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "368/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "368/375",
   "seq": 71,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1/1",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "27/25",
   "seq": 72,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "376/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "376/375",
   "seq": 73,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "128/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "128/125",
   "seq": 74,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "26/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "1/1",
   "seq": 75,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "392/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "392/375",
   "seq": 76,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "16/15",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/15",
   "seq": 77,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "27/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "26/25",
   "seq": 78,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "136/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "136/125",
   "seq": 79,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "416/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "416/375",
   "seq": 80,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "28/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "6/5",
   "seq": 81,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "424/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "424/375",
   "seq": 82,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "144/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "144/125",
   "seq": 83,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "29/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "28/25",
   "seq": 84,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "88/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "88/75",
   "seq": 85,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "448/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "448/375",
   "seq": 86,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "6/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "29/25",
   "seq": 87,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "152/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "152/125",
   "seq": 88,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "464/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "464/375",
   "seq": 89,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "31/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "33/25",
   "seq": 90,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "472/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "472/375",
   "seq": 91,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "32/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "31/25",
   "seq": 92,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "32/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/25",
   "seq": 93,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "488/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "488/375",
   "seq": 94,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "33/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "32/25",
   "seq": 95,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "496/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "496/375",
   "seq": 96,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "168/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "168/125",
   "seq": 97,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "34/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "36/25",
   "seq": 98,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "512/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "512/375",
   "seq": 99,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "104/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "104/75",
   "seq": 100,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "7/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "34/25",
   "seq": 101,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "176/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "176/125",
   "seq": 102,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "536/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "536/375",
   "seq": 103,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "36/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "7/5",
   "seq": 104,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "544/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "544/375",
   "seq": 105,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "184/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "184/125",
   "seq": 106,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "37/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "39/25",
   "seq": 107,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "112/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "112/75",
   "seq": 108,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "568/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "568/375",
   "seq": 109,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "38/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "37/25",
   "seq": 110,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "192/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "192/125",
   "seq": 111,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "584/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "584/375",
   "seq": 112,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "39/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "38/25",
   "seq": 113,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "592/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "592/375",
   "seq": 114,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "42/25",
   "seq": 115,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "8/5",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/5",
   "seq": 116,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "608/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "608/375",
   "seq": 117,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "41/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "8/5",
   "seq": 118,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "616/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "616/375",
   "seq": 119,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "208/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "208/125",
   "seq": 120,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "42/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "41/25",
   "seq": 121,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "632/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "632/375",
   "seq": 122,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "128/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "128/75",
   "seq": 123,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "43/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "9/5",
   "seq": 124,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "216/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "216/125",
   "seq": 125,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "656/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "656/375",
   "seq": 126,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "44/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "43/25",
   "seq": 127,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "664/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "664/375",
   "seq": 128,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "224/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "224/125",
   "seq": 129,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "9/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "44/25",
   "seq": 130,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "136/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "136/75",
   "seq": 131,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "688/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "688/375",
   "seq": 132,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "46/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "48/25",
   "seq": 133,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "232/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "232/125",
   "seq": 134,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "704/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "704/375",
   "seq": 135,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "47/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "46/25",
   "seq": 136,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "712/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "712/375",
   "seq": 137,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "48/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "47/25",
   "seq": 138,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "48/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "48/25",
   "seq": 139,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "728/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "728/375",
   "seq": 140,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "49/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "51/25",
   "seq": 141,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "736/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "736/375",
   "seq": 142,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "248/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "248/125",
   "seq": 143,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "2/1",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "49/25",
   "seq": 144,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "752/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "752/375",
   "seq": 145,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "152/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "152/75",
   "seq": 146,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "51/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "2/1",
   "seq": 147,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "256/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "256/125",
   "seq": 148,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "776/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "776/375",
   "seq": 149,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "52/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "54/25",
   "seq": 150,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "784/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "784/375",
   "seq": 151,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "264/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "264/125",
   "seq": 152,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "53/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "52/25",
   "seq": 153,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "32/15",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "32/15",
   "seq": 154,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "808/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "808/375",
   "seq": 155,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "54/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "53/25",
   "seq": 156,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "272/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "272/125",
   "seq": 157,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "824/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "824/375",
   "seq": 158,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "11/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "57/25",
   "seq": 159,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "832/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "832/375",
   "seq": 160,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "56/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "11/5",
   "seq": 161,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "56/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/25",
   "seq": 162,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "848/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "848/375",
   "seq": 163,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "57/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "56/25",
   "seq": 164,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "856/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "856/375",
   "seq": 165,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "288/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "288/125",
   "seq": 166,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "58/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "12/5",
   "seq": 167,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "872/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "872/375",
   "seq": 168,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "176/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "176/75",
   "seq": 169,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "59/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "58/25",
   "seq": 170,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "296/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "296/125",
   "seq": 171,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "896/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "896/375",
   "seq": 172,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "12/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "59/25",
   "seq": 173,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "904/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "904/375",
   "seq": 174,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "304/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "304/125",
   "seq": 175,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "61/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "63/25",
   "seq": 176,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "184/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "184/75",
   "seq": 177,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "928/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "928/375",
   "seq": 178,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "62/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "61/25",
   "seq": 179,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "312/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "312/125",
   "seq": 180,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "944/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "944/375",
   "seq": 181,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "63/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "62/25",
   "seq": 182,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "952/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "952/375",
   "seq": 183,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "64/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "66/25",
   "seq": 184,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "64/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "64/25",
   "seq": 185,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "968/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "968/375",
   "seq": 186,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "13/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "64/25",
   "seq": 187,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "976/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "976/375",
   "seq": 188,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "328/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "328/125",
   "seq": 189,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "66/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "13/5",
   "seq": 190,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "992/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "992/375",
   "seq": 191,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "8/3",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "8/3",
   "seq": 192,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "67/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "69/25",
   "seq": 193,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "336/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "336/125",
   "seq": 194,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1016/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1016/375",
   "seq": 195,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "68/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "67/25",
   "seq": 196,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1024/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1024/375",
   "seq": 197,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "344/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "344/125",
   "seq": 198,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "69/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "68/25",
   "seq": 199,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "208/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "208/75",
   "seq": 200,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1048/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1048/375",
   "seq": 201,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "14/5",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "72/25",
   "seq": 202,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "352/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "352/125",
   "seq": 203,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1064/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1064/375",
   "seq": 204,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "71/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "14/5",
   "seq": 205,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1072/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1072/375",
   "seq": 206,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "72/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "71/25",
   "seq": 207,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "72/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "72/25",
   "seq": 208,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1088/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1088/375",
   "seq": 209,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "73/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "3/1",
   "seq": 210,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1096/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1096/375",
   "seq": 211,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "368/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "368/125",
   "seq": 212,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "74/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "73/25",
   "seq": 213,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1112/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1112/375",
   "seq": 214,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "224/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "224/75",
   "seq": 215,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "3/1",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "74/25",
   "seq": 216,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "376/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "376/125",
   "seq": 217,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1136/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1136/375",
   "seq": 218,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "76/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "78/25",
   "seq": 219,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1144/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1144/375",
   "seq": 220,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "384/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "384/125",
   "seq": 221,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "77/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "76/25",
   "seq": 222,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "232/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "232/75",
   "seq": 223,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1168/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1168/375",
   "seq": 224,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "78/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "77/25",
   "seq": 225,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "392/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "392/125",
   "seq": 226,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1184/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1184/375",
   "seq": 227,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "79/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "81/25",
   "seq": 228,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1192/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1192/375",
   "seq": 229,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "16/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "79/25",
   "seq": 230,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/5",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "16/5",
   "seq": 231,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1208/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1208/375",
   "seq": 232,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "81/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "16/5",
   "seq": 233,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1216/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1216/375",
   "seq": 234,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "408/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "408/125",
   "seq": 235,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "82/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "84/25",
   "seq": 236,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1232/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1232/375",
   "seq": 237,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "248/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "248/75",
   "seq": 238,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "83/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "82/25",
   "seq": 239,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "416/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "416/125",
   "seq": 240,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1256/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1256/375",
   "seq": 241,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "84/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "83/25",
   "seq": 242,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1264/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1264/375",
   "seq": 243,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "424/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "424/125",
   "seq": 244,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "17/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "87/25",
   "seq": 245,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "256/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "256/75",
   "seq": 246,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1288/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1288/375",
   "seq": 247,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "86/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "17/5",
   "seq": 248,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "432/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "432/125",
   "seq": 249,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1304/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1304/375",
   "seq": 250,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "87/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "86/25",
   "seq": 251,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1312/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1312/375",
   "seq": 252,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "88/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "18/5",
   "seq": 253,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "88/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "88/25",
   "seq": 254,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1328/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1328/375",
   "seq": 255,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "89/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "88/25",
   "seq": 256,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1336/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1336/375",
   "seq": 257,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "448/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "448/125",
   "seq": 258,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "18/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "89/25",
   "seq": 259,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1352/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1352/375",
   "seq": 260,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "272/75",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "272/75",
   "seq": 261,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "91/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "93/25",
   "seq": 262,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "456/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "456/125",
   "seq": 263,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1376/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1376/375",
   "seq": 264,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "92/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "91/25",
   "seq": 265,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1384/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1384/375",
   "seq": 266,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "464/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "464/125",
   "seq": 267,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "93/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "92/25",
   "seq": 268,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "56/15",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "56/15",
   "seq": 269,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1408/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1408/375",
   "seq": 270,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "94/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "96/25",
   "seq": 271,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "472/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "472/125",
   "seq": 272,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1424/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1424/375",
   "seq": 273,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "19/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "94/25",
   "seq": 274,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1432/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1432/375",
   "seq": 275,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "96/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "19/5",
   "seq": 276,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "96/25",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "96/25",
   "seq": 277,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "1448/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1448/375",
   "seq": 278,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "97/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "99/25",
   "seq": 279,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1456/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1456/375",
   "seq": 280,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "488/125",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "488/125",
   "seq": 281,
   "track": 1
  },
  {
   "corrupt": false,
   "dts": "98/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "97/25",
   "seq": 282,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1472/375",
   "dur": "8/375",
   "frame_type": "A",
   "pts": "1472/375",
   "seq": 283,
   "track": 1
  },
  {
   "corrupt": true,
   "dts": null,
   "dur": null,
   "frame_type": "A",
   "pts": null,
   "seq": 284,
   "track": 1
  },
  {
   "corrupt": true,
   "dts": null,
   "dur": null,
   "frame_type": "B",
   "pts": null,
   "seq": 285,
   "track": 0
  },
  {
   "corrupt": true,
   "dts": null,
   "dur": null,
   "frame_type": "A",
   "pts": null,
   "seq": 286,
   "track": 1
  },
  {
   "corrupt": true,
   "dts": null,
   "dur": null,
   "frame_type": "A",
   "pts": null,
   "seq": 287,
   "track": 1
  }
 ],
 "params": {
  "audio": {
   "codec": "aac-like",
   "frame": "1024/48000 s",
   "note": "final partial frame lands the track exactly on the stream duration"
  },
  "corrupt_tail": "last 4 emitted packets truncated: timestamps stripped, corrupt flag set",
  "video": {
   "bframes": 2,
   "codec": "h264-like",
   "fps": 25,
   "gop": 24,
   "timebase": "1/25"
  }
 },
 "schema": "demux-goldens/v2",
 "stream_id": "synthetic-corrupt-tail",
 "tracks": [
  {
   "frames": 100,
   "index": 0,
   "kind": "video"
  },
  {
   "frames": 188,
   "index": 1,
   "kind": "audio"
  }
 ]
}

```

```text id=rf10
{
 "class": "no-timestamps",
 "packets": [
  {
   "corrupt": false,
   "dts": "0/1",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "0/1",
   "seq": 0,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "1/25",
   "seq": 1,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "2/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "2/25",
   "seq": 2,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "3/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "3/25",
   "seq": 3,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "4/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "4/25",
   "seq": 4,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "1/5",
   "seq": 5,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "6/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "6/25",
   "seq": 6,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "7/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 7,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "8/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "8/25",
   "seq": 8,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "9/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "9/25",
   "seq": 9,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "2/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "2/5",
   "seq": 10,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "11/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "11/25",
   "seq": 11,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "12/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "12/25",
   "seq": 12,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "13/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "13/25",
   "seq": 13,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "14/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 14,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "3/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "3/5",
   "seq": 15,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "16/25",
   "seq": 16,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "17/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "17/25",
   "seq": 17,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "18/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "18/25",
   "seq": 18,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "19/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "19/25",
   "seq": 19,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "4/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "4/5",
   "seq": 20,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "21/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": null,
   "seq": 21,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "22/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "22/25",
   "seq": 22,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "23/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "23/25",
   "seq": 23,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "24/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "24/25",
   "seq": 24,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "1/1",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "1/1",
   "seq": 25,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "26/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "26/25",
   "seq": 26,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "27/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "27/25",
   "seq": 27,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "28/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 28,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "29/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "29/25",
   "seq": 29,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "6/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "6/5",
   "seq": 30,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "31/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "31/25",
   "seq": 31,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "32/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "32/25",
   "seq": 32,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "33/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "33/25",
   "seq": 33,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "34/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "34/25",
   "seq": 34,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "7/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 35,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "36/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "36/25",
   "seq": 36,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "37/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "37/25",
   "seq": 37,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "38/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "38/25",
   "seq": 38,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "39/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "39/25",
   "seq": 39,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "8/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "8/5",
   "seq": 40,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "41/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "41/25",
   "seq": 41,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "42/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": null,
   "seq": 42,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "43/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "43/25",
   "seq": 43,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "44/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "44/25",
   "seq": 44,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "9/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "9/5",
   "seq": 45,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "46/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "46/25",
   "seq": 46,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "47/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "47/25",
   "seq": 47,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "48/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "48/25",
   "seq": 48,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "49/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 49,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "2/1",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "2/1",
   "seq": 50,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "51/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "51/25",
   "seq": 51,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "52/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "52/25",
   "seq": 52,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "53/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "53/25",
   "seq": 53,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "54/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "54/25",
   "seq": 54,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "11/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "11/5",
   "seq": 55,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "56/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 56,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "57/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "57/25",
   "seq": 57,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "58/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "58/25",
   "seq": 58,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "59/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "59/25",
   "seq": 59,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "12/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "12/5",
   "seq": 60,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "61/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "61/25",
   "seq": 61,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "62/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "62/25",
   "seq": 62,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "63/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": null,
   "seq": 63,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "64/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "64/25",
   "seq": 64,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "13/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "13/5",
   "seq": 65,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "66/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "66/25",
   "seq": 66,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "67/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "67/25",
   "seq": 67,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "68/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "68/25",
   "seq": 68,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "69/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "69/25",
   "seq": 69,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "14/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 70,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "71/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "71/25",
   "seq": 71,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "72/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "72/25",
   "seq": 72,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "73/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "73/25",
   "seq": 73,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "74/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "74/25",
   "seq": 74,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "3/1",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "3/1",
   "seq": 75,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "76/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "76/25",
   "seq": 76,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "77/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 77,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "78/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "78/25",
   "seq": 78,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "79/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "79/25",
   "seq": 79,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "16/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "16/5",
   "seq": 80,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "81/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "81/25",
   "seq": 81,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "82/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "82/25",
   "seq": 82,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "83/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "83/25",
   "seq": 83,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "84/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": null,
   "seq": 84,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "17/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "17/5",
   "seq": 85,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "86/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "86/25",
   "seq": 86,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "87/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "87/25",
   "seq": 87,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "88/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "88/25",
   "seq": 88,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "89/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "89/25",
   "seq": 89,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "18/5",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "18/5",
   "seq": 90,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "91/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 91,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "92/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "92/25",
   "seq": 92,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "93/25",
   "dur": "1/25",
   "frame_type": "P",
   "pts": "93/25",
   "seq": 93,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "94/25",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "94/25",
   "seq": 94,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "19/5",
   "dur": "1/25",
   "frame_type": "B",
   "pts": "19/5",
   "seq": 95,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": "96/25",
   "dur": "1/25",
   "frame_type": "I",
   "pts": "96/25",
   "seq": 96,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": null,
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 97,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": null,
   "dur": "1/25",
   "frame_type": "B",
   "pts": null,
   "seq": 98,
   "track": 0
  },
  {
   "corrupt": false,
   "dts": null,
   "dur": "1/25",
   "frame_type": "P",
   "pts": null,
   "seq": 99,
   "track": 0
  }
 ],
 "params": {
  "missing": "pts nil on every 7th frame; pts+dts nil on final 3",
  "video": {
   "bframes": 0,
   "codec": "h264-like intra",
   "fps": 25,
   "gop": 1,
   "timebase": "1/25"
  }
 },
 "schema": "demux-goldens/v2",
 "stream_id": "synthetic-no-timestamps",
 "tracks": [
  {
   "frames": 100,
   "index": 0,
   "kind": "video"
  }
 ]
}

```

```text id=actual_run_log
negative-control permuted-order: expected FAIL, got FAIL (synthetic-bframe-reorder, 2 field mismatch(es), stream id asserted on every FAIL line)
negative-control nil-tail-permutation: expected FAIL, got FAIL (synthetic-corrupt-tail, 1 field mismatch(es))
negative-control tampered-golden: expected mismatch, got mismatch (goldens/synthetic-no-timestamps.digest.txt: bytes differ)
negative-control corrupt-tail-repair: expected FAIL, got FAIL (synthetic-corrupt-tail, 4 field mismatch(es))
demux-goldens: 3/3 golden digests byte-identical PASS
```
