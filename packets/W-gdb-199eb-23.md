# W-gdb-199eb-23: transfer-preflight-ui
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/transfer-preflight-ui.
Source: archive/gor/Sources/gor/App/ExportAsSeenAction.swift, lines 14-41.

## Product change
Surface the exact refused source transfer tag in export preflight instead of a generic refusal.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

```text
14: 
15:     /// Photon menu entries from the ExportMenu model through its pure surface sync: exactly one "encode" item (tag 7414, one page: export row, dimmed settings heading, options) however often this runs,
16:     /// the old standalone action row (tag 7403) and duplicates removed, every other item untouched and in order. Ownership is the verified tag, never a title.
17:     /// The export row opens the panel (Start stays fail-closed until the capability legs are all present); the model's encode-route reason is its tooltip.
18:     static func installMenu(in photonMenu: NSMenu, target: AppDelegate) {
19:         let model = ExportMenu(profile: ExportSettings.profile(from: settingsBacking), sourceHDR: nil, encodeRoute: .unavailable(reason: "no accepted encode route"))
20:         let current = photonMenu.items.map { ExportMenu.SurfaceItem(tag: $0.tag, title: $0.title, isSeparator: $0.isSeparatorItem) }
21:         let desired = ExportMenu.sync(surface: current, with: model)
22:         let owned = Set(ExportMenu.ownedSurfaceTags)
23:         for old in photonMenu.items where owned.contains(old.tag) { photonMenu.removeItem(old) }
24:         for (position, item) in desired.enumerated() where item.tag == ExportMenuTags.settingsSubmenu {
25:             let entry = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
26:             entry.submenu = submenu(from: item.submenu ?? [], title: item.title, target: target)
27:             entry.tag = item.tag
28:             photonMenu.insertItem(entry, at: min(position, photonMenu.items.count))
29:         }
30:     }
31: 
32:     /// Lane E skeleton: the composition root installs the real Start provider through here. The provider runs
33:     /// outside every controller lock (ExportStartCoordinator); until the cached capability snapshot is
34:     /// start-capable (all four legs present, Lane A amendment) AND the root supplies the real builder (the
35:     /// lanes' parts), it answers nil and Start keeps its typed .noProvider: fail-closed, never a static ready.
36:     static func installStartProvider(on controller: PPController, capability: ExportCapabilitySource,
37:                                      build: ((ExportPreflightResult) -> ExportStartInputs?)? = nil) {
38:         controller.exportStartProvider = { result in
39:             guard capability.cachedSnapshot.startCapable, let build = build else { return nil }
40:             return build(result)
41:         }
```

## Mandatory test
PQ/HLG/missing tag tests show tag and no output file; bt709 path proceeds.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
