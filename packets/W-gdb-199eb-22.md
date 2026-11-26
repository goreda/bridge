# W-gdb-199eb-22: transfer-mpv-mapping
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/transfer-mpv-mapping.
Source: archive/gor/Sources/gor/Picture/ExportEncoderConfig.swift, lines 3-30.

## Product change
Cite actual mpv mapping path and line before changing colour transfer admission.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
3: // Uses: ExportEncoderSettings, ExportJob
4: // Engine: none
5: import Foundation
6: 
7: public enum ExportEncoderConfigError: Error, Equatable {
8:     case unknownArgument(String)
9:     case missingValue(String)
10:     case badValue(flag: String, value: String)
11:     case missing(String)
12:     case hdrWithX264
13:     case pixelFormatMismatch(String)
14: }
15: 
16: public struct ExportMasterDisplayText: Equatable { public var text: String }
17: 
18: public struct ExportEncoderConfig: Equatable {
19:     public var codec: ExportCodec
20:     public var width: Int, height: Int
21:     public var bitDepth: Int
22:     public var pixelFormat: String
23:     public var crf: Int
24:     public var preset: String
25:     public var tune: String?
26:     public var h264Profile: String?
27:     public var vbvMaxrateKbps: Int64
28:     public var vbvBufsizeKbps: Int64
29:     public var transfer: ExportTransfer
30:     public var colorPrimaries: String?
```

## Mandatory test
Pinned mpv mapping regression proves bt709 to bt.1886 relation; contradictions are returned with evidence.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
