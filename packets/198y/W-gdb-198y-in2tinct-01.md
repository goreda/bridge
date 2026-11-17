# W-gdb-198y-in2tinct-01
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVPlaybackCore/AudioTrackPlan.swift in shipping-path engine station GorAVPlaybackCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-01.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-01",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/AudioTrackPlan.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVPlaybackCore/AudioTrackPlan.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: AudioTrackInfo, AudioTrackSelector, AudioTrackRefusal, AudioTrackPlan, select, AudioDelay",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-01.py",
    "callee": "Sources/GorAVPlaybackCore/AudioTrackPlan.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-01.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-01.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-01.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.619424+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/AudioTrackPlan.swift",
        "block": "source1",
        "sha256": "24d8e9f53b044811f39268299767fad5a2bf788982133439138f5269c5678c31"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-01.py",
        "block": "fixtures1",
        "sha256": "e78feef5510819e60092d91f225cea5576be8e6e6dd0d52453c6a74dc6084984"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "c89109cb3807c05365b37cc7c18b7434a8500ac6d61b7bbbe7d061511339c882",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-01: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "fb2a0b78565bec15bd16f22c1538bd24bfd81f7a901b6042c9155a7bca3a16dd"
  }
}
```

```swift id=source1
import Foundation

// R6 (arch-195l, dispatch L6): audio track selection policy + audio delay
// value semantics. Pure Swift, Linux-verifiable; the Mac wiring
// (FFmpegSoftwareAudioDecoder preferred stream, session commands) consumes
// these types. Selection is typed and loud: an explicit request that the
// container cannot honor is a typed refusal, never a silent fallback.

/// One audio track as the control layer needs it (mirrors the audio rows of
/// MediaInventory.Track without importing the FFmpeg adapter).
public struct AudioTrackInfo: Equatable, Sendable {
    /// Container stream index (avformat stream index, not an ordinal).
    public let index: Int
    public let language: String?
    public let title: String?
    public let isDefault: Bool
    public init?(index: Int, language: String?, title: String?, isDefault: Bool) {
        guard index >= 0 else { return nil }
        self.index = index; self.language = language
        self.title = title; self.isDefault = isDefault
    }
}

public enum AudioTrackSelector: Equatable, Sendable {
    /// Container default flag first, else the lowest stream index.
    case auto
    /// Exact container stream index.
    case index(Int)
    /// Exact language tag, case-insensitive (e.g. "eng", "tur").
    case language(String)
}

public enum AudioTrackRefusal: Error, Equatable, Sendable, CustomStringConvertible {
    case noAudioTracks
    case requestedIndexAbsent(Int)
    case requestedLanguageAbsent(String)
    public var description: String {
        switch self {
        case .noAudioTracks: return "noAudioTracks"
        case .requestedIndexAbsent(let i): return "requestedIndexAbsent(\(i))"
        case .requestedLanguageAbsent(let l): return "requestedLanguageAbsent(\(l))"
        }
    }
}

public enum AudioTrackPlan {
    public static func select(_ selector: AudioTrackSelector, from tracks: [AudioTrackInfo])
        -> Result<AudioTrackInfo, AudioTrackRefusal> {
        guard !tracks.isEmpty else { return .failure(.noAudioTracks) }
        switch selector {
        case .auto:
            if let d = tracks.first(where: { $0.isDefault }) { return .success(d) }
            return .success(tracks.min(by: { $0.index < $1.index })!)
        case .index(let i):
            guard i >= 0, let t = tracks.first(where: { $0.index == i }) else {
                return .failure(.requestedIndexAbsent(i))
            }
            return .success(t)
        case .language(let lang):
            let wanted = lang.lowercased()
            guard let t = tracks.first(where: { $0.language?.lowercased() == wanted }) else {
                return .failure(.requestedLanguageAbsent(lang))
            }
            return .success(t)
        }
    }
}

/// User audio delay, mpv audio-delay convention: POSITIVE delays the audio
/// relative to the video. Setting REPLACES the value; it never accumulates.
public struct AudioDelay: Equatable, Sendable {
    public static let limitSeconds = 600.0
    public let seconds: Double
    public init?(_ seconds: Double) {
        guard seconds.isFinite, abs(seconds) <= AudioDelay.limitSeconds else { return nil }
        self.seconds = seconds
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVPlaybackCore/AudioTrackPlan.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='24d8e9f53b044811f39268299767fad5a2bf788982133439138f5269c5678c31', 'pinned source changed: rebase and review, never bless silently'
for token in ['AudioTrackInfo', 'AudioTrackSelector', 'AudioTrackRefusal', 'AudioTrackPlan', 'select', 'AudioDelay']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='24d8e9f53b044811f39268299767fad5a2bf788982133439138f5269c5678c31'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-01: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-01: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
