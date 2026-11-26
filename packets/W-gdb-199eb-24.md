# W-gdb-199eb-24: transfer-frame-source
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/transfer-frame-source.
Source: archive/gor/Sources/gor/Picture/ExportFrameSource.swift, lines 3-21.

## Product change
Bind source color evidence to each export frame source identity and reject mismatched source.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Swap two sources/evidence objects; mismatch refused without consuming a frame.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
