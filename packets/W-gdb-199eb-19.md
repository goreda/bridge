# W-gdb-199eb-19: encode-menu-location
Team: 1nstinct. State: WAIT_STATION_REPIN. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-19, lane lane/1nstinct/encode-menu-location; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/UI/ExportMenu.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: aa8d862130658e06ba849230cf09e3b7935092fd
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Place encode as a top-level menu entry outside photon; keep existing entry behavior and refresh.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Existing export target is being consolidated by the single station writer. Wait for its verified destination@SHA, then repin this same packet. No parallel satellite edit.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
31:     public let disabledReason: String?
32:     /// The option value this row selects, when kind == .option.
33:     public let representedValue: String?
34: 
35:     public static func separator(tag: Int) -> ExportMenuRow {
36:         ExportMenuRow(kind: .separator, title: "", tag: tag,
37:                       isChecked: false, isEnabled: false,
38:                       disabledReason: nil, representedValue: nil)
39:     }
40: }
41: 
42: /// Whether a coordinator/render/encode route exists for Export As Seen.
43: /// Invariant: the action may enable only when a route is present.
44: public enum ExportEncodeRoute: Equatable {
45:     case unavailable(reason: String)
46:     // An accepted route adds: case available(routeID: String)
47: }
48: 
49: /// Tags reserved by this model. Rebuild hygiene depends on every dynamic row
50: /// and separator carrying one of these tags.
51: public enum ExportMenuTags {
52:     public static let action = 7403              // "Export As Seen" action item
53:     public static let separatorCodec = 7411      // between the export row and the settings heading
54:     public static let settingsHeading = 7415     // dimmed "settings" section heading
55:     public static let separatorResolution = 7412 // before the resolution group
56:     public static let separatorQuality = 7413    // before the quality group
57:     public static let settingsSubmenu = 7414     // the "encode" menu row
58: }
```

Secret scan: clean.
