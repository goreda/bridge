# W-gdb-199eb-22: transfer-mpv-mapping
Team: in2tinct. State: WAIT_STATION_REPIN. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-22, lane lane/in2tinct/transfer-mpv-mapping; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Picture/ExportEncoderConfig.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 894d712a3266c57ac2840ea8977e22e489f55dce
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Cite actual mpv mapping path and line before changing colour transfer admission.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Existing export target is being consolidated by the single station writer. Wait for its verified destination@SHA, then repin this same packet. No parallel satellite edit.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
