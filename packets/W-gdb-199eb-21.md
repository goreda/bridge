# W-gdb-199eb-21: transfer-tag-authority
Team: in2tinct. State: WAIT_STATION_REPIN. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-21, lane lane/in2tinct/transfer-tag-authority; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Picture/ExportColourEvidence.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 42af9343d86a52abda93e69dcb10e528387d4de0
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Admit ffprobe bt709 with mpv bt.1886 consistency and refuse other source transfer tags with tag shown.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Existing export target is being consolidated by the single station writer. Wait for its verified destination@SHA, then repin this same packet. No parallel satellite edit.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
11: // Uses: ExportSnapshotAdapter
12: // Engine: none
13: import Foundation
14: 
15: public struct ExportDecodedSignal: Equatable {
16:     /// mpv video-dec-params colour fields as read for THIS load generation; nil = not read. Raw
17:     /// strings: mapping to the typed vocabulary happens in one place and an unrecognised value is
18:     /// a typed unknown, never a nearest match.
19:     public var primaries: String?
20:     public var transfer: String?
21:     public var matrix: String?
22:     public var range: String?
23:     public init(primaries: String? = nil, transfer: String? = nil, matrix: String? = nil, range: String? = nil) {
24:         self.primaries = primaries; self.transfer = transfer; self.matrix = matrix; self.range = range
25:     }
26: }
27: 
28: extension ExportDecodedSignal {
29:     /// The four mpv property names of the decoded source colour probe, in a stable order so a
30:     /// batch query maps request_id -> key with no table drift.
31:     public static let videoDecParamsKeys = ["video-dec-params/primaries", "video-dec-params/trc",
32:                                             "video-dec-params/colormatrix", "video-dec-params/colorlevels"]
33: 
34:     /// Parses one mpv IPC batch reply (one JSON object per line, request_id = base + key index)
35:     /// into a keyed dict. Unsuccessful replies, unknown request ids, null and non-string or empty
36:     /// data are skipped: whatever is not positively read stays absent, never invented. A repeated
37:     /// reply for the same key with the SAME value is harmless; a repeated reply with a DIFFERENT
38:     /// value is a conflict: the key is dropped and stays dropped (never last-wins).
```

Secret scan: clean.
