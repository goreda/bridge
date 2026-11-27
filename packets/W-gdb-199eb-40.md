# W-gdb-199eb-40: export-terminal-visibility
Team: in2tinct. State: WAIT_STATION_REPIN. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-40, lane lane/in2tinct/export-terminal-visibility; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/App/ExportAsSeenAction.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 0ec7e2fbbda985277d502420ac49679966812adc
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Keep the export panel terminal error/output state visible after asynchronous runner completion.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
Existing export target is being consolidated by the single station writer. Wait for its verified destination@SHA, then repin this same packet. No parallel satellite edit.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
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

Secret scan: clean.
