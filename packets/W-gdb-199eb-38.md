# W-gdb-199eb-38: magnet-row-stability
Team: in2tinct. State: READY_UNCLAIMED. Priority: product regression.
Pin: goreda/instinct 168af857fedfeb06956891e11580b1a28f3aeadf. Target: lane/in2tinct/magnet-row-stability.
Source: archive/gor/Sources/gor/Media/MagnetBrowser.swift, lines 639-666.

## Product change
Keep row identity stable when seed counts update and tie-breaks are equal.

## Interface and ownership
Preserve the existing public signatures shown below, source/load/player token ownership and provider behavior. No placeholder return, default-off stub, disabled delivered feature or copied mock substitutes for the real path. Own only the narrow function/helper under this task; claim the exact symbol before writing. If another writer already owns that symbol, implement a separate extracted helper/test and return integration points rather than overwriting it.

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

## Mandatory test
Same seed/title variations and hash duplicates never shift selection onto another magnet.
Run the regression against the pinned baseline first and show the failing assertion, then the patch and raw passing output. If baseline passes, return the exact source finding and a narrower actual failing case, not a speculative change. Swift/C edits require compile-only free native CI started at lane push, separate from test suites. Native runtime remains NOT_RUN without a real execution receipt.

## Return
Return a unified patch or complete edited file plus exact base SHA, changed symbols, commands, raw test output, known limitations and lane commit URL. Include no credentials, private endpoints, owner messages/IDs, personal paths or licensed fixture bytes. Self-claim here with timestamp and branch before work. Existing earliest claim wins. Any receiver ingests by apply/test/merge or exact failure response within two hours. Assembly merges landed lanes hourly; no main-agent hand-apply dependency. Record source acceptance separately from installed/runtime/owner acceptance.
