# W-gdb-199eb-32: pip-menu-state
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/pip-menu-state.
Source: archive/gor/Sources/gor/UI/ExportMenu.swift, lines 31-58.

## Product change
Audit PiP-related menu availability versus actual provider capability; remove no delivered entry.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Available means real handler/capability; refusal is explicit and state refresh reflects provider switches.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
