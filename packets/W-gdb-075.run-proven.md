# W-gdb-075 n4-ptsdur: container PTS/duration exact-rational oracle parity, run-proven at pin (M2 sources)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-075

```packet-json
{
  "packet_id": "W-gdb-075",
  "writer": "gdb",
  "code_owner": "gdb gorav integrator (PTS/duration lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "8786bfe3e5482a891dda15248b107e50fab52463",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/LabPTSDuration.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "kits/n4-ptsdur/run_parity.sh",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "LabRational init(_:_:) throws; LabRational.parse(_:) throws; LabPTS.rational(_:) throws -> LabRational?; tick(_:_:) throws -> LabRational?; pyFloat(_:) -> String; boxes(_:loIn:hiIn:) throws -> [Atom]; times(_:) throws -> TimeHeader?; BMFF movie/track/edit inventory (mvhd/mdhd/tkhd/elst v0/v1)",
    "types": "LabRational { n, d, seconds, Comparable/Equatable exact rational }; LabPTSError typed errors; Atom { kind, payload }; TimeHeader { timescale, durationTicks, duration }; Edit { durationMovieTicks, duration, mediaTimeTicks, mediaTime, movieSegmentStart, emptyEdit, mediaRate, unitRateOffset }; Track { trackId, mediaHeader, edits }; BMFF { movieHeader, tracks }",
    "ownership_lifetime": "pure value-type oracle over saved probe JSON; read-only, no player verdict, no demuxer/decoder, no best-effort substitution for missing PTS",
    "caller": "kits/n4-ptsdur/main.swift (on-main integrator parity harness)",
    "callee": "Sources/GorAVPlaybackCore/LabPTSDuration.swift (product PTS/duration model, GorAVPlaybackCore)"
  },
  "test": {
    "command": "cd kits/n4-ptsdur && set -o pipefail && export SWIFTC=${SWIFTC:-swiftc} && \"$SWIFTC\" --version && bash run_parity.sh | tee /tmp/n4-075-out.txt && grep -qx 'PARITY OK: 16 scenarios, 273 lines byte-identical' /tmp/n4-075-out.txt",
    "expected": "exit 0. The selected compiler prints its version before compiling the REAL product LabPTSDuration.swift standalone. run_parity.sh diffs the compiled model's scenario output against the vendored python oracle; tee surfaces the output and grep -qx enforces the unchanged exact marker 'PARITY OK: 16 scenarios, 273 lines byte-identical'. The original local run was reported with Swift 5.10.1; lane b reports its v1 run used Swift 6.1.2, but the v1 log did not print a compiler version. v2 records the selected compiler version in its own fresh run log rather than inferring it. A digest drift, output-count drift, compiler-version command failure or compile failure exits non-zero.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "kits/n4-ptsdur/",
      "Sources/GorAVPlaybackCore/LabPTSDuration.swift"
    ],
    "return_form": "module"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "8786bfe3e5482a891dda15248b107e50fab52463",
    "command": "cd kits/n4-ptsdur && set -o pipefail && export SWIFTC=${SWIFTC:-swiftc} && \"$SWIFTC\" --version && bash run_parity.sh | tee /tmp/n4-075-out.txt && grep -qx 'PARITY OK: 16 scenarios, 273 lines byte-identical' /tmp/n4-075-out.txt",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-16T02:17:33.946516+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "PARITY OK: 16 scenarios, 273 lines byte-identical",
    "inline_files": [
      {
        "path": "kits/n4-ptsdur/run_parity.sh",
        "block": "source2",
        "sha256": "b9a1825567728d0bda15008bc25c4205ebb563af715d69e4de33a00c2a3e3e9d"
      },
      {
        "path": "kits/n4-ptsdur/scenarios.json",
        "block": "fixtures1",
        "sha256": "d1cc82a99bc4c7ed7daddcbac1661d6a4a2773fd7ad19ffae28fe5a18216e0b5"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "0e407252c973a1efd23fa7ce2028e0ba2b3c80b7f61f6e3f96d7598fab1a6dff",
    "last_5_lines": [
      "Swift version 6.1.2 (swift-6.1.2-RELEASE)",
      "Target: x86_64-unknown-linux-gnu",
      "PARITY OK: 16 scenarios, 273 lines byte-identical"
    ],
    "receipt_sha256": "fc9382549d390d847eb6c492e716832602c2528d49f366e174af4b026e8c893a"
  }
}
```

## problem (what fails for the user)

Seek accuracy, A/V sync and duration display all stand on exact container
timestamps. Sources/GorAVPlaybackCore/LabPTSDuration.swift (G0730 / 195a-N04)
is the product's exact-rational PTS/duration inventory - separate
container/stream/decoded-end/span values, an independent BMFF
mvhd/mdhd/tkhd/elst v0/v1 parser, and no best-effort substitution for a
missing PTS. A regression reaches the user as wrong durations, drifted
seeks, or end-timestamp-as-duration on nonzero-origin files - with no
run-pinned proof at current main that the model still matches its vendored
lab oracle.

## reproducer

No new code: the on-main integrator parity harness (kits/n4-ptsdur:
scenarios.json, 16 scenarios at pin, sha256 efea9752; parity.py; main.swift;
run_parity.sh, source2) compiles the REAL product file
Sources/GorAVPlaybackCore/LabPTSDuration.swift (source1 excerpt; whole-file
sha256 40f58920 at pin) standalone with swiftc and diffs its scenario digest
lines against the vendored python oracle (src/oracle.py). The scenarios cover
all 8 saved probe sets (BMFF edit lists, skip/discard side data, alignment
deltas), the unit edge cases (missing PTS/end, negative PTS, zero timebase,
invalid rational, truncated atom, elst v1 64-bit) and the naive-RED contrast.
The harness consumes saved probes - no FFmpeg run at proof time. This packet
pins and run-proves the harness at 8786bfe3 (arch-196z item 3, M2
source-lane kits).

## expected behaviour

The compound test.command exits 0 with the exact marker
`PARITY OK: 16 scenarios, 273 lines byte-identical` enforced by grep -qx
(074 v2 style: output surfaced via tee, count asserted, not just printed) -
attested from a run of the pinned tree 2026-11-16 04:55 +03. The oracle is
read-only reference: no player verdict, no demuxer/decoder claims. Mac/Metal
NOT_TESTED (per the product file header).

## exact call site and interface

Sources/GorAVPlaybackCore/LabPTSDuration.swift at pin (API in interface
above). Harness: kits/n4-ptsdur/main.swift (sha256 71b44695) drives the
scenarios; parity.py (sha256 981f95b5) is the python side; run_parity.sh
(sha256 8acff1c1, source2) is the test entry point.

## pinned excerpts (gorav @ 8786bfe3e5482a891dda15248b107e50fab52463)

### Sources/GorAVPlaybackCore/LabPTSDuration.swift (sha256 40f58920, lines 161-183 of 404; 22 excerpt lines, trailing blank omitted)

```swift id=source1
    public struct TimeHeader {
        public let timescale: Int
        public let durationTicks: Int
        public let duration: LabRational
    }

    public static func times(_ b: Data?) throws -> TimeHeader? {
        guard let b = b else { return nil }
        let ver = b[b.startIndex]
        let scale: Int, duration: Int
        if ver == 0 {
            scale = try u32(b, 12)
            duration = try u32(b, 16)
        } else if ver == 1 {
            scale = try u32(b, 20)
            duration = try u64(b, 24)
        } else {
            throw LabPTSError.invalid("unsupported time header version")
        }
        if scale <= 0 { throw LabPTSError.invalid("zero timescale") }
        return TimeHeader(timescale: scale, durationTicks: duration, duration: try LabRational(duration, scale))
    }
```

### kits/n4-ptsdur/run_parity.sh (sha256 8acff1c1, whole file)

```sh id=source2
#!/bin/bash
# n4-ptsdur parity: python lab oracle vs Swift port, scenario digest diff.
set -e
cd "$(dirname "$0")"
SWIFTC="${SWIFTC:-$HOME/swift/usr/bin/swiftc}"
"$SWIFTC" -O -o /tmp/n4_parity main.swift ../../Sources/GorAVPlaybackCore/LabPTSDuration.swift
python3 parity.py > /tmp/n4_py.out
/tmp/n4_parity > /tmp/n4_sw.out
diff /tmp/n4_py.out /tmp/n4_sw.out && echo "PARITY OK: $(grep -c '^== ' /tmp/n4_py.out) scenarios, $(wc -l < /tmp/n4_py.out) lines byte-identical"
```

## roles and state

All packet-relevant files are on main at the pin; the packet adds no files.
The harness writes only /tmp/n4_* artifacts and refreshes the kit's tracked
__pycache__ byte (bound below). Every kit byte is sha256-bound in fixtures2
(64 files incl. fixtures/, probes/, results/, docs/, SHA256SUMS, and the
tracked src/__pycache__/oracle.cpython-310.pyc). Fixture media is generated
per the kit's commands.json record (FFmpeg 4.4.2, N04 needs no source
rebuild); no user data, no licensed content.

## repair note (arch-196x item 4)

v2 (G0836): print the selected compiler version before the parity run.
Lane b reports Swift 6.1.2 for its v1 run; the v1 receipt log did not
record a version. The original local 5.10.1 report does not describe the
lane compiler. Product digest now uses HASH  PATH order like the kit
manifest. Excerpt count is 22 lines, excluding the trailing blank.
The parity assertion and marker are unchanged. v1 receipt is preserved;
v2 requires a fresh run and receipt.

Pin 8786bfe3 with prose bullets; on-main files excerpted byte-exact, never
edited. Marker attested from a real run of the pinned tree (2026-11-16
04:55 +03), not a build line. n2-margin stays out (HDR/colour hold,
arch-197a item 2); n10-cropdetect/b10-musicmode need new Swift parity
harnesses - deferred per coordinator 2026-11-16 04:5x.

## how to run

Clean checkout at the pin, then the packet's compound test.command (needs
python3 + swiftc; SWIFTC env overrides the compiler, run_parity.sh defaults
it to $HOME/swift/usr/bin/swiftc, the command overrides to PATH swiftc).

### fixtures1: scenario set (`kits/n4-ptsdur/scenarios.json` at pin)

```json id=fixtures1
[
 {"op":"probe","name":"h264-unequal.mp4"},
 {"op":"probe","name":"hevc-unequal.mp4"},
 {"op":"probe","name":"h264-unequal.mkv"},
 {"op":"probe","name":"hevc-unequal.mkv"},
 {"op":"probe","name":"h264-unequal.mov"},
 {"op":"probe","name":"hevc-unequal.mov"},
 {"op":"probe","name":"h264-nonzero.mp4"},
 {"op":"probe","name":"hevc-nonzero.mkv"},
 {"op":"inline","probe":{"streams":[{"index":0,"time_base":"1/1000","codec_type":"video"}],"packets":[{"stream_index":0}]},"frames":{"frames":[{"stream_index":0,"best_effort_timestamp":8,"pkt_duration":40}]}},
 {"op":"inline","probe":{"streams":[{"index":0,"time_base":"1/1000","codec_type":"video"}]},"frames":{"frames":[{"stream_index":0,"pts":0,"pkt_duration":40},{"stream_index":0,"pts":40}]}},
 {"op":"inline","probe":{"streams":[{"index":0,"time_base":"1/48000","codec_type":"audio","sample_rate":"48000"}]},"frames":{"frames":[{"stream_index":0,"pts":-1024,"nb_samples":1024}]}},
 {"op":"inline","probe":{"streams":[{"index":0,"time_base":"0/1"}]},"frames":{}},
 {"op":"rational","value":"1/0"},
 {"op":"boxes_trunc"},
 {"op":"times_v1"},
 {"op":"naive"}
]
```

### fixtures2: byte-binding attestation (whole-file sha256 at pin 8786bfe3)

```text id=fixtures2
40f589209ab29070e8d3ded2f8ca2deea87fd0070697d81456bd1be84a7cd690  Sources/GorAVPlaybackCore/LabPTSDuration.swift
c6f5ec513b8bc98881156571e6c2d887921b51fce96d6c95bc993495864b6d8a  kits/n4-ptsdur/README-LAB.md
fb51f573791f36e0058fa92b857ed25e0e67519c028b49958c6190cc776d69c3  kits/n4-ptsdur/README.md
8f33f87dfcec9a6ab6a158a625cc9c6bdfd05b5fa90a91dae5d324efda4aa666  kits/n4-ptsdur/SHA256SUMS
d755db453c8befe161d1dd6ce8bd85028e873d9af8e07ee5c8f2a7c93aeec54f  kits/n4-ptsdur/commands.json
3e821a11411d09fa9e1cb690e656b80a742c23766a0d3d0b0ead45ed011962d7  kits/n4-ptsdur/docs/sources.md
0220b22e1e528797790412f0a04f447a905d040d8a3d9e7ae205dc797affd944  kits/n4-ptsdur/environment.txt
b39e2084f18a58a97f01e378f2e167740701fceae671298334d6c9c8d94c52ca  kits/n4-ptsdur/fixtures/h264-nonzero.mp4
4200c44e48065d615d30acf57fd1d9d50dffbf1f1b888e448400b3b45684f7ec  kits/n4-ptsdur/fixtures/h264-unequal.mkv
2806f6ffaa0cf8dcc0908b291ab13d3a247907452b791dcca3edf116b69bf555  kits/n4-ptsdur/fixtures/h264-unequal.mov
2105fedd560c3ee0c59e550a199ed6555502a27e8e45ec05dda22a3a1533453a  kits/n4-ptsdur/fixtures/h264-unequal.mp4
318d6f72f874660a1a915b43663e3e6e700651135ed2166b8deb4d246e5ab6a0  kits/n4-ptsdur/fixtures/hevc-nonzero.mkv
500cd8878d7ca0dd3425db9862ee0ced2e09121044dc5815064e4110a72e8533  kits/n4-ptsdur/fixtures/hevc-unequal.mkv
f4ee883d0d30a79332de2890c05922bf22732b2eb1a5f5183e3bf4357bbb8105  kits/n4-ptsdur/fixtures/hevc-unequal.mov
f95aab789d17c80c69b853d7864a9e86f2234b4dac2e1e400c145459f9050131  kits/n4-ptsdur/fixtures/hevc-unequal.mp4
71b446950da277bcb957a4e854f7f03fd9153ebb31fae64d90c7478c70b607f1  kits/n4-ptsdur/main.swift
981f95b53c2daa8a420712e44e4a9ccac7dbc8d29cf2bcb57a50048d98297490  kits/n4-ptsdur/parity.py
76190e31900f6c880d475d1672509f75778c5e9dcd3da55a46b1af4840f4dbd6  kits/n4-ptsdur/probes/h264-nonzero.mp4.audio.framemd5
a040d3348188e1a1edad7ddf7f84bf61a8cb2c3bb078c77a5139b1f96f07247d  kits/n4-ptsdur/probes/h264-nonzero.mp4.frames.json
a589d8bee7dedcd1777693dc0f9f3d3eafb2173bd151e6b29d17304eaa9b732e  kits/n4-ptsdur/probes/h264-nonzero.mp4.packets.json
f567e1ac93af58ef60cf5799fe415a46707c93344e145dd4dafed49abd8633aa  kits/n4-ptsdur/probes/h264-nonzero.mp4.video.framemd5
67f400085c16f8d8cb774f5d8c862aa6cd804fd976cf90155e82b0c39048d672  kits/n4-ptsdur/probes/h264-unequal.mkv.audio.framemd5
dd8140d4693f4dff547c0bd3b0cd89d81be044d8be6276b5d56df391c32876e7  kits/n4-ptsdur/probes/h264-unequal.mkv.frames.json
7525c25b0c644fb41e9a0a0fe078e5528556161df7d500b0ce72976d11d5830e  kits/n4-ptsdur/probes/h264-unequal.mkv.packets.json
031832d15bc1d76c1a496ad13657b86b5b01edbdd74cc42fd3a5344b0143af37  kits/n4-ptsdur/probes/h264-unequal.mkv.video.framemd5
7ba597b84813f0165fb21336db839207fd77be2323f21a38886d9b72af7af329  kits/n4-ptsdur/probes/h264-unequal.mov.audio.framemd5
9eeb8b570c1f5e6cc0161c73168ae2b7b374ef30e99c086b0e9b38b41bef7984  kits/n4-ptsdur/probes/h264-unequal.mov.frames.json
44186e30dd9d3b1c348b84eb96c42cd366d26ef7442d4f0f845d151c82f60677  kits/n4-ptsdur/probes/h264-unequal.mov.packets.json
3d5bc0945d447bfacb5ac85f509066584d934ab2b3ec2ecc5a8d53bf0fb4023a  kits/n4-ptsdur/probes/h264-unequal.mov.video.framemd5
7ba597b84813f0165fb21336db839207fd77be2323f21a38886d9b72af7af329  kits/n4-ptsdur/probes/h264-unequal.mp4.audio.framemd5
9c6746d5d2bfb6df38989bae4530c181a1989f9c92c32060a25f8c11d0db1c9b  kits/n4-ptsdur/probes/h264-unequal.mp4.frames.json
6abecb89eeeb89956a9ac93a131ccb3375807f11b0427897a0676f00c462c410  kits/n4-ptsdur/probes/h264-unequal.mp4.packets.json
3d5bc0945d447bfacb5ac85f509066584d934ab2b3ec2ecc5a8d53bf0fb4023a  kits/n4-ptsdur/probes/h264-unequal.mp4.video.framemd5
67f400085c16f8d8cb774f5d8c862aa6cd804fd976cf90155e82b0c39048d672  kits/n4-ptsdur/probes/hevc-nonzero.mkv.audio.framemd5
5a8ae381aaa96d071de8277fa3365dbf8e5c5c17d1638562fd83b6ee66b7229a  kits/n4-ptsdur/probes/hevc-nonzero.mkv.frames.json
f5fdd7dfb52852df9d5562d573bd1b3dfdb3543a517697aebf192da1b7c0d07e  kits/n4-ptsdur/probes/hevc-nonzero.mkv.packets.json
bf21f39cf33b65c3e53fc79b312534565e2447f4ca550b37e8dd5a2c8b948225  kits/n4-ptsdur/probes/hevc-nonzero.mkv.video.framemd5
67f400085c16f8d8cb774f5d8c862aa6cd804fd976cf90155e82b0c39048d672  kits/n4-ptsdur/probes/hevc-unequal.mkv.audio.framemd5
62c944c49733ea8b4e6b1e43c43bd39b48c269a13fffe393ea18c8dd81635027  kits/n4-ptsdur/probes/hevc-unequal.mkv.frames.json
dda455fe7032f6963532363dace31cb1530920127ef45e5a79b0df951b94514b  kits/n4-ptsdur/probes/hevc-unequal.mkv.packets.json
4d4608a8d2a450752f33465a12c6601f5bc319de22a174525521f8aef0f9d2b0  kits/n4-ptsdur/probes/hevc-unequal.mkv.video.framemd5
7ba597b84813f0165fb21336db839207fd77be2323f21a38886d9b72af7af329  kits/n4-ptsdur/probes/hevc-unequal.mov.audio.framemd5
60e319169639dde70d7a9365bfb216f59fa18c2e963d60b03ee9a7db307a8fa3  kits/n4-ptsdur/probes/hevc-unequal.mov.frames.json
21136209a067f8a9b4b115a305318d45d1c6776fbafef1311304a7fbf97690c7  kits/n4-ptsdur/probes/hevc-unequal.mov.packets.json
d5eb40eb41f173d62a986de962483bc9bb04d22819ab7765d19a459fbc6190c4  kits/n4-ptsdur/probes/hevc-unequal.mov.video.framemd5
7ba597b84813f0165fb21336db839207fd77be2323f21a38886d9b72af7af329  kits/n4-ptsdur/probes/hevc-unequal.mp4.audio.framemd5
0e382c96196440c9e15eb4966aeb15d49c310e142626a1ff3d27dd9c65f5c77f  kits/n4-ptsdur/probes/hevc-unequal.mp4.frames.json
d13a437b9447c745176b99df87d945522b0d2e8e076ef11005d6b81b3cf58909  kits/n4-ptsdur/probes/hevc-unequal.mp4.packets.json
d5eb40eb41f173d62a986de962483bc9bb04d22819ab7765d19a459fbc6190c4  kits/n4-ptsdur/probes/hevc-unequal.mp4.video.framemd5
78f55317d338204338968cb4a2a606934899564d5b828c2554324dd32854e642  kits/n4-ptsdur/results/h264-nonzero.mp4.report.json
582d8bf6adef420f81aa54db9c08be6e0afbe040a63d56ca36df0729a0efaac3  kits/n4-ptsdur/results/h264-unequal.mkv.report.json
45787e0a128743abdc5a0faffdf8f1ecf825c2fc192ca12565c7e49337254556  kits/n4-ptsdur/results/h264-unequal.mov.report.json
45787e0a128743abdc5a0faffdf8f1ecf825c2fc192ca12565c7e49337254556  kits/n4-ptsdur/results/h264-unequal.mp4.report.json
dbccdfef1b362df860cf7e02fc342ab18e5a5373c3e929eed8fd55ece9d97faf  kits/n4-ptsdur/results/hevc-nonzero.mkv.report.json
a482b5489d47cf85b720c5377cb8d3d3970426177116686212b496228d0870d3  kits/n4-ptsdur/results/hevc-unequal.mkv.report.json
acdd18987e0ec584244c07abaa4674a571f56f050542ad510987087b0b343f74  kits/n4-ptsdur/results/hevc-unequal.mov.report.json
acdd18987e0ec584244c07abaa4674a571f56f050542ad510987087b0b343f74  kits/n4-ptsdur/results/hevc-unequal.mp4.report.json
2c055bc0b487b81f2912b28cb846331deb6d1aa836aadc51d5b401b5490ad0ce  kits/n4-ptsdur/results/summary.tsv
8acff1c1bd0555f91d951e9f3c7135e2b39349775e380cdeae339974ff28f26a  kits/n4-ptsdur/run_parity.sh
efea9752261ff87c999a7a2d81393c756d1864077758b199b193cf532f1aaf2f  kits/n4-ptsdur/scenarios.json
086e09645eb0ddb4f54f62f34635b91f36d6dc19856d715a437604def3163251  kits/n4-ptsdur/src/__pycache__/oracle.cpython-310.pyc
1010a10b26c14cb356974a604974fa413ad2bed5c3a6685c70dd5dc0191de436  kits/n4-ptsdur/src/generate.py
7e6b30900b32b4e32f27977672d5d866fe8a6eeac3a2632081981cbc8b14a8af  kits/n4-ptsdur/src/naive_red.py
cf54c61278971ba1c4bddcf6cf9daf3158c61258b761347cf0aaf8dbe4787241  kits/n4-ptsdur/src/oracle.py
1b995c70bcdec67c26362643f89fd923af7a264e385f9fde1cdff5e708ab2e8a  kits/n4-ptsdur/src/test_oracle.py
```


```text id=actual_run_log
Swift version 6.1.2 (swift-6.1.2-RELEASE)
Target: x86_64-unknown-linux-gnu
PARITY OK: 16 scenarios, 273 lines byte-identical
```
