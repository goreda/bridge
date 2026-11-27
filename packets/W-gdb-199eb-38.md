# W-gdb-199eb-38: magnet-row-stability
Team: in2tinct. State: REISSUED_CUSTODY_UNVERIFIED. Priority: product regression.
Packet identity and occupancy: original W-gdb-199eb-38, lane lane/in2tinct/magnet-row-stability; earliest existing symbol claim still wins.
Legacy extracted-helper/new-file fallback and full-file return are RETIRED by199ee. This is the same packet reissued as an existing-file patch, not a new dispatch.

## Target file@SHA
Repository: goreda/instinct
Target: archive/gor/Sources/gor/Media/MagnetBrowser.swift@37ccb29b7403bbc35b276ab5600947979de42f7d
Blob: 60d81bd64f18c8ca371fbee7466f634272ca1575
The target existed at this exact pin. Historical168af857 excerpts below are not the current pin.

## Change
Keep row identity stable when seed counts update and tie-breaks are equal.

## Return as patch to that file
Unified patch against the exact target above. Modify its existing owning concept; no new source/test/helper file, full-file replacement or new Gate/Guard/Receipt/Proof/Admission/Stub type. A genuinely new file requires an explicit block line naming it first. Preserve source/load/player identity, existing interfaces and product behavior outside this change. On collision report it and preserve earliest custody instead of extracting a helper.

## Current reconciliation
No current claim/return proof found in the queue snapshot. Preserve any earlier claim; reconcile actual source and later returns before taking work. This is not a fresh unclaimed assignment.
A queue label alone does not prove the original defect is outstanding. Report already-fixed evidence before proposing a duplicate change. Tests and compile/runtime limitations are reported honestly; this packet adds no CI gate between code and owner delivery.

## Historical source context
```text
639:         onSort?(sortKey, descending)
640:     }
641:     // Same state write as a header tap, for flows that pick the sort themselves
642:     // (the empty-query popular listing sorts by seeds, highest first).
643:     func applySort(_ key: String, descending value: Bool) {
644:         sortKey = key; descending = value; currentSort = key; descendingSort = value
645:     }
646:     @objc private func closeTapped() { onClose?() }
647:     var isSearchOpen: Bool { inlineEditing }
648:     func setChromeAlpha(_ alpha: CGFloat, animated: Bool = false) {
649:         let value: CGFloat = inlineEditing ? 1 : alpha
650:         if animated { animator().alphaValue = value } else { alphaValue = value }
651:     }
652:     func dismissSearch() { closeSearch() }
653:     func toggleSearchFromKey() {
654:         if inlineEditing { closeSearch() } else { openSearch() }
655:     }
656:     func closeSearch() {
657:         guard inlineEditing else { return }
658:         cancelLiveSearch()
659:         inlineEditing = false
660:         titleSort.isHidden = false
661:         statusLayer.isHidden = false
662:         let host = window
663:         if searchField.currentEditor() != nil { _ = host?.makeFirstResponder(nil) }
664:         searchField.isHidden = true
665:         PanelKeyOwnership.shared.unregister(ObjectIdentifier(self))
666:         if let view = priorResponder as? NSView, view.window === host { _ = host?.makeFirstResponder(view) }
```

Secret scan: clean.
