# W-gdb-198y-in2tinct-12
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVSubtitles/SubtitleTrack.swift in shipping-path engine station GorAVSubtitles. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-12.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-12",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SubtitleTrack.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVSubtitles/SubtitleTrack.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: SubtitleTrack, LoadError, Track, load",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-12.py",
    "callee": "Sources/GorAVSubtitles/SubtitleTrack.swift owning station GorAVSubtitles"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-12.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-12.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-12.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.834742+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/SubtitleTrack.swift",
        "block": "source1",
        "sha256": "d0e635a1ec87e20d75cfdb59dd75fb4f9aec24f7c54a2f88f84dab154518b969"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-12.py",
        "block": "fixtures1",
        "sha256": "2cbeae0bf0410d1466ab3911cefcad836cd8759b48aa5de81a6eccc11d5c395c"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "e817b5fd7597b334d4b48024305f5c0858658ac19cb54373b8dd20db1860502b",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-12: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "ad1f72078235883910ad951cd8af481833957f7a727001bd1f0dc1117a29da24"
  }
}
```

```swift id=source1
import Foundation

/// Sidecar subtitle track loader (lanes L5/L6, unit u2): picks the parser by
/// file extension (.srt, .ass, .ssa) and returns cues plus the optional ASS
/// style table. Unknown extensions and unreadable files are typed refusals,
/// never silent fallbacks. Pure loader; no playback or rendering here.
public enum SubtitleTrack {

    public enum LoadError: Error, Equatable {
        case unknownFormat(path: String)
        case unreadable(path: String)
    }

    public struct Track: Equatable, Sendable {
        public let format: String // "srt" or "ass" (.ssa normalizes to "ass")
        public let cues: [SubtitleCue]
        public let styles: [ASSParser.Style]
        /// ASS override blocks detected during load: UNSUPPORTED rendering
        /// instructions, reported, never silently stripped. Empty for SRT.
        public let unsupportedOverrides: [ASSParser.OverrideReport]
        /// ASS Style rows that failed parsing during load: caller-visible at
        /// the loader entry point too, never dropped between parser and
        /// consumer. Empty for SRT.
        public let skippedStyles: [ASSParser.SkippedStyle]
        /// ASS PlayRes layout reference frame; nil for SRT or when absent.
        public let playResX: Int?
        public let playResY: Int?

        public init(format: String, cues: [SubtitleCue], styles: [ASSParser.Style],
                    unsupportedOverrides: [ASSParser.OverrideReport],
                    skippedStyles: [ASSParser.SkippedStyle], playResX: Int?, playResY: Int?) {
            self.format = format
            self.cues = cues
            self.styles = styles
            self.unsupportedOverrides = unsupportedOverrides
            self.skippedStyles = skippedStyles
            self.playResX = playResX
            self.playResY = playResY
        }
    }

    public static func load(path: String) throws -> Track {
        let ext = (path as NSString).pathExtension.lowercased()
        guard ext == "srt" || ext == "ass" || ext == "ssa" else { throw LoadError.unknownFormat(path: path) }
        guard let data = FileManager.default.contents(atPath: path), let text = String(data: data, encoding: .utf8) else {
            throw LoadError.unreadable(path: path)
        }
        if ext == "srt" {
            return Track(format: "srt", cues: try SRTParser.parse(text), styles: [],
                         unsupportedOverrides: [], skippedStyles: [], playResX: nil, playResY: nil)
        }
        let doc = try ASSParser.parse(text)
        return Track(format: "ass", cues: doc.cues, styles: doc.styles,
                     unsupportedOverrides: doc.unsupportedOverrides, skippedStyles: doc.skippedStyles,
                     playResX: doc.playResX, playResY: doc.playResY)
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVSubtitles/SubtitleTrack.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='d0e635a1ec87e20d75cfdb59dd75fb4f9aec24f7c54a2f88f84dab154518b969', 'pinned source changed: rebase and review, never bless silently'
for token in ['SubtitleTrack', 'LoadError', 'Track', 'load']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='d0e635a1ec87e20d75cfdb59dd75fb4f9aec24f7c54a2f88f84dab154518b969'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-12: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-12: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
