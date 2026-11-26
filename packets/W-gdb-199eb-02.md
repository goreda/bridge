# W-gdb-199eb-02: crop-live-playhead
Team: 1nstinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/1nstinct/crop-live-playhead.
Source: archive/gor/Sources/gor/Stereo/Source.swift, lines 1144-1171.

## Product change
Keep progressive source reads useful when playback moves while a crop scan runs.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
1144:                y1:min(height,((b.y1 + 1) / 2) * 2))
1145:     }
1146: }
1147: 
1148: final class SourcePixelCropScanner {
1149:     private let lock = NSLock()
1150:     private var epoch = 0
1151:     private var freshnessFloor = 0 // only an explicit measurement boundary forbids cancelled carry reuse
1152:     private var active: Process?
1153:     /// Work already measured on a stream (wt) survives a cancel: bars are a static property of the file, so the union of
1154:     /// samples from an interrupted scan stays valid for the next scan of the same file, and a decisive rect that was
1155:     /// computed but dropped by a cancel is handed to the next scan of that file instead of being thrown away.
1156:     /// key = path|stereo|topBottom|rounded duration of the scan that wrote it; dims = "WxH pix range" once the stream was probed ("" if never).
1157:     private struct Carry { var key: String; var dims: String; var at: Double; var bounds: SourcePixelBounds.Bounds?; var members: [SourcePixelBounds.Bounds]; var sampled: Int; var undelivered: Bool; var rect: CGRect?; var done: [Double]; var ep: Int }   // ep = epoch of the scan that wrote it: an older scan never overwrites it
1158:     private var carry: Carry?
1159:     private var newestKey: String?   // key of the most recently started stream scan: a stale scan may not store under another key
1160:     private static let carryTTL: Double = 180   // seconds; older measurements are re-measured, never replayed
1161:     private(set) var decodedWidth=0
1162:     private(set) var decodedHeight=0
1163:     private(set) var perEyeAspect:Double?
1164:     private var lastDeliveredEpoch = -1   // epoch of the scan that last delivered a decisive result: an older scan may not store after it
1165:     /// Forget everything carried (explicit manual Detect re-measures from scratch).
1166:     /// Samples decoded so far by the scan now running (0 when none started or none decoded yet).
1167:     private(set) var liveSamples = 0
1168:     /// True when a scan for the file on screen is already producing samples: a manual Detect then lets it finish
1169:     /// instead of killing it (the capture showed repeated clicks cancelling every scan at 19-27 s of ~57 s).
1170:     private var scanStartedAt:Double=0, scanDeadlineAt:Double=0, lastProgressAt:Double=0
1171:     /// A single old sample is not proof that the worker is still making progress.
```

## Mandatory test
Replay sample timestamps and playhead advance; old scan cannot replace a newer decision.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
