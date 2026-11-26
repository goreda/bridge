# W-gdb-199eb-21: transfer-tag-authority
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/transfer-tag-authority.
Source: archive/gor/Sources/gor/Picture/ExportColourEvidence.swift, lines 11-38.

## Product change
Admit ffprobe bt709 with mpv bt.1886 consistency and refuse other source transfer tags with tag shown.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Matrix bt709/bt.1886 accepted; PQ/HLG/unknown/refused tag visible, no silent coercion.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
