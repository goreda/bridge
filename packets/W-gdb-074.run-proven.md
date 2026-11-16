# W-gdb-074 b5-hlsplay: HLS playlist model parity, run-proven at pin (M2 sources)
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-074

```packet-json
{
  "packet_id": "W-gdb-074",
  "writer": "gdb",
  "code_owner": "gdb gorav integrator (HLS playlist lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "8786bfe3e5482a891dda15248b107e50fab52463",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/LabHLSPlaylist.swift",
      "excerpt_block": "source1"
    },
    {
      "path": "kits/b5-hlsplay/run_parity.sh",
      "excerpt_block": "source2"
    }
  ],
  "interface": {
    "signatures": "LabHLSPlaylist.parseAttrs(_:) -> [String:String]; parseMaster(_:) throws -> [LabHLSVariant]; parseMedia(_:) throws -> LabHLSMedia; chooseVariant(_:bandwidthBps:...) ; liveEdge(_:behind:) throws -> (Int, Bool); LabHLSSession.update(_:) -> [LabHLSSegment]; consumed(_:); fetchFailed(retryDelayBase:) -> Double?; seek(_:_:) throws -> (Int, Double)",
    "types": "LabHLSVariant { uri, bandwidth, avgBandwidth, width, height, codecs, frameRate }; LabHLSSegment { uri, duration, seq, discontinuity, discSeq }; LabHLSMedia { target, mediaSeq, discSeq, ended, playlistType, segments, holdBack, version }; LabHLSSession state: nextSeq/discSeq/cache/window/seekable/live/ended/failures/state/events; LabHLSError typed errors",
    "ownership_lifetime": "pure value-type playlist model + one session object per scenario; no I/O, no shared state across scenarios",
    "caller": "kits/b5-hlsplay/main.swift (on-main integrator parity harness)",
    "callee": "Sources/GorAVPlaybackCore/LabHLSPlaylist.swift (product playlist model, GorAVPlaybackCore)"
  },
  "test": {
    "command": "cd kits/b5-hlsplay && set -o pipefail && python3 -m unittest test_hlslive 2>&1 | tail -2 && bash run_parity.sh | tee /tmp/b5-074-out.txt && grep -qx 'PARITY-MATCH (65 lines)' /tmp/b5-074-out.txt",
    "expected": "exit 0. The vendored python suite (test_hlslive.py, 22 cases) runs visible (pipefail; its OK line prints, any failure exits non-zero before the parity diff). run_parity.sh diffs the python carrier against the compiled product Swift model and prints the marker; tee surfaces it and grep -qx enforces the exact line 'PARITY-MATCH (65 lines)' - 65 attested from a run of the pinned tree 2026-11-16 04:17 +03 (swiftc 5.10.1, python3, Linux x86_64). A digest drift, a scenario-count drift, or a suite failure each exit non-zero.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "kits/b5-hlsplay/",
      "Sources/GorAVPlaybackCore/LabHLSPlaylist.swift"
    ],
    "return_form": "module"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "8786bfe3e5482a891dda15248b107e50fab52463",
    "command": "cd kits/b5-hlsplay && set -o pipefail && python3 -m unittest test_hlslive 2>&1 | tail -2 && bash run_parity.sh | tee /tmp/b5-074-out.txt && grep -qx 'PARITY-MATCH (65 lines)' /tmp/b5-074-out.txt",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-16T01:46:10.817498+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "PARITY-MATCH (65 lines)",
    "inline_files": [
      {
        "path": "kits/b5-hlsplay/run_parity.sh",
        "block": "source2",
        "sha256": "3b120d8c4bdbefdf7352a0e8d3c370c38dea79f01973f7e490ea6cb36a114e11"
      },
      {
        "path": "kits/b5-hlsplay/scenarios.json",
        "block": "fixtures1",
        "sha256": "d9fe1cf9c0e93b2b7b594de66ceef7595f4239f3645a6a5878d7ab95f5e609a8"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "84c910ded5d93a6f66bc3b4d518766435322616099c2592138818d2550dbe442",
    "last_5_lines": [
      "",
      "OK",
      "PARITY-MATCH (65 lines)"
    ],
    "receipt_sha256": "6b8ded715d419827e83557cbd21fa5765e12d90a46bbe683d1beb1f0cfe40752"
  }
}
```

## problem (what fails for the user)

HLS live/VOD playback stands on the playlist model in
Sources/GorAVPlaybackCore/LabHLSPlaylist.swift (G0744 / 195b-B5): master and
media playlist parsing, POLICY variant choice, live edge, session
window/gap/discontinuity/reconnect/seek state. A regression in that model
reaches the user as a stream that picks the wrong variant, loses the live
edge, or breaks on a discontinuity - with no run-pinned proof at the current
main that the model still matches its vendored lab carrier.

## reproducer

No new code: the on-main integrator parity harness (kits/b5-hlsplay:
scenarios.json, 41 scenarios at pin, sha256 d6a927f7; parity.py; main.swift;
run_parity.sh, source2) compiles the REAL product file
Sources/GorAVPlaybackCore/LabHLSPlaylist.swift (source1 excerpt; whole-file
sha256 69d32532 at pin) standalone with swiftc and diffs its scenario digests
against the vendored python carrier (hlslive.py). This packet pins and
run-proves that harness at 8786bfe3 (arch-196z item 3, M2 source-lane kits;
HLS/IPTV lane).

## expected behaviour

The compound test.command exits 0: the 22-case vendored python suite runs
visible (OK line printed; failure exits non-zero via pipefail), the parity
diff passes byte-exact, and grep -qx enforces the exact marker
`PARITY-MATCH (65 lines)` (v2, per lab G0832 review: suite no longer
stderr-suppressed in the gate path; the 65-line count asserted, not just
printed). The avformat transport driver is NOT part of this seam (stays in
the lab lane, RET-W0284-avformat-einval); the model consumes playlist TEXT
only.

## exact call site and interface

Sources/GorAVPlaybackCore/LabHLSPlaylist.swift at pin (parse/choose/liveEdge/
session API in interface above). Harness: kits/b5-hlsplay/main.swift (sha256
3b86d157) drives the scenarios; parity.py (sha256 5ddf534b) is the python
side; run_parity.sh (sha256 857731aa, source2) is the test command.

## pinned excerpts (gorav @ 8786bfe3e5482a891dda15248b107e50fab52463)

### Sources/GorAVPlaybackCore/LabHLSPlaylist.swift (sha256 69d32532, lines 242-262 of 347)

```swift id=source1
public final class LabHLSSession {
    public var nextSeq: Int? = nil
    public var discSeq: Int = 0
    public var cache: [Int: String] = [:]
    public var cacheLimit: Int
    public var seekable = false
    public var live = true
    public var ended = false
    public var failures = 0
    public var maxFailures: Int
    public var state = "init"           // init|playing|reconnecting|failed|ended
    public private(set) var events: [LabHLSEvent] = []
    public var window: (Int, Int) = (0, 0)
    public var eventsLimit: Int

    public init(maxFailures: Int = 5, cacheLimit: Int = 8, eventsLimit: Int = 64) {
        self.maxFailures = maxFailures
        self.cacheLimit = cacheLimit
        self.eventsLimit = eventsLimit
    }
```

### kits/b5-hlsplay/run_parity.sh (sha256 857731aa, whole file)

```sh id=source2
#!/bin/sh
set -e
cd "$(dirname "$0")"
SWIFTC="${SWIFTC:-swiftc}"
python3 -m unittest test_hlslive 2>/dev/null || { echo "lab python suite FAILED"; exit 1; }
python3 parity.py > /tmp/b5-parity-py.txt
"$SWIFTC" -O -o /tmp/b5-parity-swift main.swift ../../Sources/GorAVPlaybackCore/LabHLSPlaylist.swift
/tmp/b5-parity-swift > /tmp/b5-parity-sw.txt
diff /tmp/b5-parity-py.txt /tmp/b5-parity-sw.txt && echo "PARITY-MATCH ($(wc -l < /tmp/b5-parity-py.txt | tr -d ' ') lines)"
```

## roles and state

All packet-relevant files are on main at the pin; the packet adds no files.
The harness writes only /tmp/b5-parity-* artifacts. Fixture set:
scenarios.json (fixtures1, byte-exact at pin) plus kits/b5-hlsplay/fixtures/
playlist texts referenced by scenario file entries; no user data, no
licensed content.

## repair note (arch-196x item 4)

v2 (2026-11-16 04:4x, lab G0832 review): compound test.command surfaces
the python suite and enforces the exact marker; hlslive.py and fixtures/*
byte-bound in fixtures2. The v1 minted receipt stands unchanged.

Pin 8786bfe3 with prose bullets; on-main files excerpted byte-exact, never
edited. Marker attested from a real run of the pinned tree (2026-11-16
04:17 +03), not a build line. Mac/Metal NOT_TESTED (pure value-type model,
no Metal involvement - per the product file header).

## how to run

Clean checkout at the pin, then the packet's compound test.command (needs
python3 + swiftc on PATH; SWIFTC env overrides the compiler). The raw kit
entry point remains `bash kits/b5-hlsplay/run_parity.sh`; the packet's
command wraps it with the visible suite and the exact-marker assertion.

### fixtures2: byte-binding attestation (whole-file sha256 at pin 8786bfe3)

```text id=fixtures2
Sources/GorAVPlaybackCore/LabHLSPlaylist.swift  69d3253200aa3a241193fffec4134abfa1c7b80c41d24aa245f3789b41a090a0
kits/b5-hlsplay/main.swift  3b86d157fb9805f4d3a75b019849ebcf96c1bf3c9f9c7ecb9264935a734ba6e1
kits/b5-hlsplay/parity.py  5ddf534b713b2d0d3e4b37409cb7c8a765eb7ec7b192e6ebce4db52a0141b5ec
kits/b5-hlsplay/run_parity.sh  857731aaa0961564be7970c06874a7486fcf33bd9f34de02dfe5c6fdcaf787b3
kits/b5-hlsplay/scenarios.json  d6a927f7b063189bece157a07ec3fc8ab2131092e782d23ee27144b2fcc0d389
kits/b5-hlsplay/hlslive.py  72c0912ab5a890c2fe88bef13aee52ccefeac3688de51bfc644f06035adb6f2f
kits/b5-hlsplay/test_hlslive.py  f0003dce9dc5fb9e3fbdedc6de19df9966b8a666fa38318291698529e29ba1b0
kits/b5-hlsplay/gen_fixtures.py  cdffdef44eda1afb07a7bc3e2bde08b6c3882eecdcd082f177fbc720c45e3907
kits/b5-hlsplay/fixtures/live_100.m3u8  135c07d354e222766a7bb6c8251c7836f0589e60aa5fafa466fe157ec5990ba8
kits/b5-hlsplay/fixtures/live_104.m3u8  f73b1362509fcfbdf96a6475febc53fa9b0559120c55382e2e81480c1a0b7c35
kits/b5-hlsplay/fixtures/master.m3u8  9702e4544b75252c40e57f330d8e52624c29e164fe5127c6145099f436875cf3
kits/b5-hlsplay/fixtures/vod.m3u8  c4b4ec11020e31c3e2b646a6b4d6668111e10277c93199663c506a6d8064002f
```

## lab-review note (G0832), bridge-ready

(1) Python suite visibility: run_parity.sh:5 `python3 -m unittest
test_hlslive 2>/dev/null || { echo "lab python suite FAILED"; exit 1; }` -
stderr (unittest's result channel) was suppressed, so the 22-case detail was
invisible, but the suite was always enforced: any failure exits 1 before the
parity diff (set -e, line 2). v2's gate path runs the suite visibly with
pipefail. (2) Line count: run_parity.sh:9 computes the count (`$(wc -l ...)`)
from the run and only prints it; a scenario-set drift on both sides would
still print PARITY-MATCH. v2 enforces the exact marker line with grep -qx.
(3) Counts: scenarios.json at pin holds 41 scenario entries across 15 ops;
the kit README's "40 scenarios" is stale documentation (named follow-up,
kit edit is an architect call). 65 is output lines, not scenarios -
multi-line ops emit M+S lines per segment (parity.py fmt_media). (4) Oracle
scope: parity binds the Swift product model to its vendored python carrier
(same lab lineage; the product file header states the line-faithful port)
over the scenario set; it is not an RFC-8216-independent oracle. v2 binds
every harness/fixture byte by sha256 (fixtures2), including hlslive.py and
fixtures/* that v1 covered only behaviorally.

### fixtures1: scenario set (`kits/b5-hlsplay/scenarios.json` at pin)

```json id=fixtures1
[
 {"op":"parse_master","file":"master.m3u8"},
 {"op":"choose","file":"master.m3u8","bw":4000000},
 {"op":"choose","file":"master.m3u8","bw":100000},
 {"op":"choose","file":"master.m3u8","bw":20000000,"max_height":720},
 {"op":"choose","file":"master.m3u8","bw":20000000,"codecs":["avc1","mp4a"]},
 {"op":"choose","file":"master.m3u8","bw":10000000,"codecs":["vp09"]},
 {"op":"choose","file":"master.m3u8","bw":3000000,"current":0},
 {"op":"choose","file":"master.m3u8","bw":4000000,"current":0},
 {"op":"parse_media","file":"live_100.m3u8"},
 {"op":"parse_media","file":"live_104.m3u8"},
 {"op":"parse_media","file":"vod.m3u8"},
 {"op":"live_edge","file":"live_100.m3u8"},
 {"op":"live_edge","file":"vod.m3u8"},
 {"op":"session_basic","file":"live_100.m3u8"},
 {"op":"session_gap"},
 {"op":"backoff","max":3,"n":4},
 {"op":"recover"},
 {"op":"seek","file":"vod.m3u8","target":13},
 {"op":"seek","file":"vod.m3u8","target":31},
 {"op":"seek","file":"live_100.m3u8","target":1},
 {"op":"seek","file":"vod.m3u8","target":"-1"},
 {"op":"seek","file":"vod.m3u8","target":"nan"},
 {"op":"seek","file":"vod.m3u8","target":"inf"},
 {"op":"bad_media","text":"#EXTM3U\n#EXTINF:1,\na.ts\n"},
 {"op":"bad_media","text":"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:9,\na.ts\n"},
 {"op":"bad_media","text":"#EXTM3U\n#EXT-X-TARGETDURATION:2\na.ts\n"},
 {"op":"bad_media","text":"#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:nan,\na.ts\n"},
 {"op":"bad_media","text":"#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:inf,\na.ts\n"},
 {"op":"bad_media","text":"#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:-1,\na.ts\n"},
 {"op":"bad_media","text":"#EXTM3U\n#EXT-X-TARGETDURATION:x\n"},
 {"op":"bad_media","text":"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:q\n#EXTINF:1,\na.ts\n"},
 {"op":"bad_media","text":"#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:1,\na.ts\n#EXTINF:1,\n"},
 {"op":"bad_master","text":"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=abc\na.m3u8\n"},
 {"op":"bad_master","text":"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=axb\na.m3u8\n"},
 {"op":"choose","text":"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000,CODECS=\"avc1.4d401f, mp4a.40.2\"\na.m3u8\n","bw":10000000,"codecs":["avc1","mp4a"]},
 {"op":"choose","text":"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=160x90\nbig.m3u8\n","bw":10000000,"max_height":180,"probed":{"big.m3u8":360}},
 {"op":"choose","text":"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\na.m3u8\n","bw":10000000,"max_height":180},
 {"op":"choose","text":"#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\na.m3u8\n","bw":10000000},
 {"op":"cache_bound","limit":3},
 {"op":"empty_update"},
 {"op":"events_bounded","limit":5,"n":50}
]
```

```text id=actual_run_log

OK
PARITY-MATCH (65 lines)
```
