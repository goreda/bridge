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
    "command": "bash kits/b5-hlsplay/run_parity.sh",
    "expected": "exit 0. The vendored python suite (test_hlslive.py, 22 cases) runs first; any failure prints 'lab python suite FAILED' and exits 1. Then the harness diffs the python carrier against the product Swift model over the scenario set; on success the last line is 'PARITY-MATCH (65 lines)' - 65 attested from a run of the pinned tree 2026-11-16 04:17 +03 (swiftc 5.10.1, python3, Linux x86_64). A digest drift prints the diff and exits 1.",
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
    "command": "bash kits/b5-hlsplay/run_parity.sh",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-16T01:25:46.863773+00:00",
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
    "log_sha256": "7aebba075b8f0d328508e534172377649cc9e10bf161880f8a1ce6cb07c3f470",
    "last_5_lines": [
      "PARITY-MATCH (65 lines)"
    ],
    "receipt_sha256": "a6e86232e25a9bd5e9c62436471ba6925af4c72698a7436fac764298d9885317"
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

`bash kits/b5-hlsplay/run_parity.sh` exits 0 with last line
`PARITY-MATCH (65 lines)`; the 22-case vendored python suite runs first and
any failure exits 1 before the parity diff. The avformat transport driver is
NOT part of this seam (stays in the lab lane, RET-W0284-avformat-einval);
the model consumes playlist TEXT only.

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

Pin 8786bfe3 with prose bullets; on-main files excerpted byte-exact, never
edited. Marker attested from a real run of the pinned tree (2026-11-16
04:17 +03), not a build line. Mac/Metal NOT_TESTED (pure value-type model,
no Metal involvement - per the product file header).

## how to run

Clean checkout at the pin, then `bash kits/b5-hlsplay/run_parity.sh`
(needs python3 + swiftc on PATH; SWIFTC env overrides the compiler).

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
PARITY-MATCH (65 lines)
```
