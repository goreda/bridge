# W-gdb-199eb-02: crop-live-playhead
Team: 1nstinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-02, lane lane/1nstinct/crop-live-playhead; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Stereo/Source.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 34d9dc1d00550fc471fbf843d1a734824aa290aa
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Keep progressive source reads useful when playback moves while a crop scan runs.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
