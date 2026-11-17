# W-gdb-198z-1nstinct-03 - Subtitle presentation settings/readback
state: OPEN / unclaimed
lab: 1nstinct

Clamped font scale, vertical position, delay, reset/readback and stale-source rejection. Stereo depth stays a named refusal.

Required acceptance: Sources/subtitle-tests/SubtitleControllerTests.swift: sampled cue/style before/after seek and reset.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-1nstinct-03",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SubtitleController.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Subtitle presentation settings/readback; Clamped font scale, vertical position, delay, reset/readback and stale-source rejection. Stereo depth stays a named refusal.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Sources/subtitle-tests/SubtitleControllerTests.swift: sampled cue/style before/after seek and reset.",
    "callee": "Sources/GorAVSubtitles/SubtitleController.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-03.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Sources/subtitle-tests/SubtitleControllerTests.swift: sampled cue/style before/after seek and reset.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-198z-1nstinct-03",
    "paths": [
      "Sources/GorAVSubtitles/SubtitleController.swift",
      "Tests/Architecture/198z/W-gdb-198z-1nstinct-03.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-1nstinct-03.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.366106+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/SubtitleController.swift",
        "block": "source1",
        "sha256": "7695cee46f59b071b8f315019ad42f15dec6ceab6975a0ddc3bd1e81f2db1897"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-1nstinct-03.py",
        "block": "fixtures1",
        "sha256": "1ab874d66359c3d73021087a212bdf66079ae2a8a3c01e00085cf014b0dbae63"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "948305dad8e143ad28b126bf862f02606e839fa8023c5ddc415162cbf6813561",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-03; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "0d53bbb3011c1cdddd142fbdf46ec1aa7d32fcb6add0717971cdd4e304460b7a"
  }
}
```

```swift id=source1
import Foundation

/// R7 (arch-195b): primary/secondary text cue selection with per-slot delay,
/// across seeks and reset. The schedule lookup is stateless, so a seek needs
/// no reload: cue identity (trackContentID, cue.index) survives any number of
/// seeks because the track content never changes under the controller.
public struct SubtitleController: Equatable, Sendable {

    public enum Slot: Equatable, Sendable { case primary, secondary }

    /// Identity of the currently displayed cue: stable across seeks, changes
    /// only when track content changes (a different file or a reload).
    public struct CueIdentity: Equatable, Sendable {
        public let trackContentID: UInt64
        public let cueIndex: Int
        public init(trackContentID: UInt64, cueIndex: Int) {
            self.trackContentID = trackContentID
            self.cueIndex = cueIndex
        }
    }

    public private(set) var primary: SubtitleTrack.Track?
    public private(set) var secondary: SubtitleTrack.Track?
    /// Seconds added to the cue timeline per slot: a positive delay shows cues
    /// later (query time minus delay). Default 0.
    public private(set) var primaryDelay: Double = 0
    public private(set) var secondaryDelay: Double = 0
    /// Set false to hide a slot without unloading it (mpv sub-visibility).
    public private(set) var primaryVisible = true
    public private(set) var secondaryVisible = true

    private var primaryContentID: UInt64 = 0
    private var secondaryContentID: UInt64 = 0
    private var primarySchedule: SubtitleSchedule?
    private var secondarySchedule: SubtitleSchedule?

    public init() {}

    public mutating func selectPrimary(_ track: SubtitleTrack.Track) {
        primary = track
        primarySchedule = SubtitleSchedule(cues: track.cues)
        primaryContentID = SubtitlePlanContentID.compute(cues: track.cues, styles: track.styles, playResX: track.playResX, playResY: track.playResY, unsupportedOverrides: track.unsupportedOverrides, skippedStyles: track.skippedStyles)
        primaryVisible = true
    }

    public mutating func selectSecondary(_ track: SubtitleTrack.Track) {
        secondary = track
        secondarySchedule = SubtitleSchedule(cues: track.cues)
        secondaryContentID = SubtitlePlanContentID.compute(cues: track.cues, styles: track.styles, playResX: track.playResX, playResY: track.playResY, unsupportedOverrides: track.unsupportedOverrides, skippedStyles: track.skippedStyles)
        secondaryVisible = true
    }

    public mutating func setDelay(_ seconds: Double, slot: Slot) {
        guard seconds.isFinite else { return }
        switch slot {
        case .primary: primaryDelay = seconds
        case .secondary: secondaryDelay = seconds
        }
    }

    public mutating func setVisible(_ visible: Bool, slot: Slot) {
        switch slot {
        case .primary: primaryVisible = visible
        case .secondary: secondaryVisible = visible
        }
    }

    /// Reset selection state: secondary unloaded, delays zeroed, both slots
    /// visible. The primary track stays loaded (mpv sub-reset semantics: the
    /// current external file remains the selected one).
    public mutating func reset() {
        secondary = nil
        secondarySchedule = nil
        secondaryContentID = 0
        primaryDelay = 0
        secondaryDelay = 0
        primaryVisible = true
        secondaryVisible = true
    }

    /// Active cue for one slot at film time `t` (delay applied). nil when the
    /// slot is empty, hidden, or no cue covers the shifted time.
    public func activeCue(at t: Double, slot: Slot) -> SubtitleCue? {
        switch slot {
        case .primary:
            guard primaryVisible, let s = primarySchedule else { return nil }
            return s.activeCue(at: t - primaryDelay)
        case .secondary:
            guard secondaryVisible, let s = secondarySchedule else { return nil }
            return s.activeCue(at: t - secondaryDelay)
        }
    }

    /// Identity of the active cue for one slot at film time `t`.
    public func activeCueIdentity(at t: Double, slot: Slot) -> CueIdentity? {
        guard let cue = activeCue(at: t, slot: slot) else { return nil }
        let tid = slot == .primary ? primaryContentID : secondaryContentID
        return CueIdentity(trackContentID: tid, cueIndex: cue.index)
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/GorAVSubtitles/SubtitleController.swift').read_bytes()).hexdigest()=='7695cee46f59b071b8f315019ad42f15dec6ceab6975a0ddc3bd1e81f2db1897'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-03; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-1nstinct-03; baseline only, product change and semantic test still required
```

secret scan: clean
