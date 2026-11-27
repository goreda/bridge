# W-gdb-199eb-24: transfer-frame-source
Team: in2tinct. State: WAIT_STATION_REPIN. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-24, lane lane/in2tinct/transfer-frame-source; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Picture/ExportFrameSource.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 0bac076d481b7ff6ca2d6269de0eace826459536
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Bind source color evidence to each export frame source identity and reject mismatched source.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Existing export target is being consolidated by the single station writer. Wait for its verified destination@SHA, then repin this same packet. No parallel satellite edit.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
3: // Uses: none
4: // Engine: mpv
5: import Foundation
6: 
7: public enum ExportFramePath: String, CaseIterable, Codable, Equatable { case libmpvRenderAPI = "libmpv-render-api", screenshotRawFrameStep = "screenshot-raw-frame-step" }
8: 
9: /// What the Codemagic measurement records per path. The winner is chosen from these numbers, not from this code.
10: public struct ExportFramePathMeasurement: Codable, Equatable {
11:     public var path: ExportFramePath
12:     public var frames: Int
13:     public var seconds: Double
14:     public var exactPTSMatches: Int
15:     public var bytesPerFrame: Int
16:     public init(path: ExportFramePath, frames: Int, seconds: Double, exactPTSMatches: Int, bytesPerFrame: Int) {
17:         self.path = path; self.frames = frames; self.seconds = seconds; self.exactPTSMatches = exactPTSMatches; self.bytesPerFrame = bytesPerFrame
18:     }
19:     public var framesPerSecond: Double { seconds > 0 ? Double(frames) / seconds : 0 }
20:     public var ptsExact: Bool { frames > 0 && exactPTSMatches == frames }
21: }
```

Secret scan: clean.
