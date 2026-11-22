# Ninth-move binding receipt: AdaptiveColor -> UI (structure-writer answer to H-0717)

Metadata only. No source body is included or published. The private body remains writer/publisher-held.

## Product binding
- Repository: goreda/instinct
- Branch (integration lane): lane-199bv-stereo
- Commit containing the interim restored source: 37a149bf376f55b6b6688c41036daad661a92d8f (parent 48e12ce4d713ced325816520505281489cfa5dd1)
- Interim restored path (repo-relative): archive/gor/Sources/gor/GorEffectsModel/AdaptiveColor.swift
- Git blob: b613c6639ab53a4fd72d9f8861be7e2fca364221
- Content SHA256: 2fd63b55e52d7e97a5b21a21856583137373c4fa8bfa52f167133d08bb5be1d6
- Size: 4826 bytes; Lines: 128
- Working-file mode: 0644, regular non-symlink non-executable (stat-verified on the applied actual tree)
- Stage-0 index mode 100644: asserted by publisher integration; index-state verification is checkout-side and remains owed on the composing checkout (typed unknown from this receipt)

## Evidence level upgrade
H-0717 recorded the content hash as issuer metadata. It is now verified against the actual integrated tree: the body supplied privately from actual37a and the independently applied publisher diff produce byte-identical content with the hash above.

## Current manifest / policy rows (actual37a, verbatim cells)
- manifest.tsv: Sources/gor/GorEffectsModel/AdaptiveColor.swift\tswift\tgor\t128
- policy.tsv: Sources/gor/GorEffectsModel/AdaptiveColor.swift\tAdaptiveColor\tGorEffectsModel\t\tM7\t\t-\t-
Both rows exist at the interim path; no absence to declare.

## Retirement identities (actual37a, 2 entries, both pins = content hash above)
- path Sources/gor/AdaptiveColor.swift -> replacement Sources/gor/GorEffectsModel/AdaptiveColor.swift
- path Sources/gor/Picture/AdaptiveColor.swift -> replacement Sources/gor/GorEffectsModel/AdaptiveColor.swift
At UI-batch integration these two replacement cells move to Sources/gor/UI/AdaptiveColor.swift and one new old-path entry (path = the GorEffectsModel interim, same pin) is appended, matching the established station template.

## Order relative to the eight UI moves
- Ninth and last, appended after the H-0715 eight in their existing ui-old-new.tsv order (SpineUI, SidebarUI, MenuActions, PhotonFont, VariationBroadcaster, IconBarFit, FlatControlRefreshGate, PhotonActiveEngineHeader).
- Destination: Sources/gor/UI/AdaptiveColor.swift (whole file, no body edits).
- Expected HEAD: the lane tip after the publisher's pending Modes composition (current tip 37a149bf376f55b6b6688c41036daad661a92d8f). The eight-file script's code-bound PIN (cd4c134e0c87009f92f0e37a6a5b0fcd6c0bda01) is stale relative to the integration lane; rebinding the pin constant is a single-writer composition step. All nine source contents are verified unchanged on the actual chain, so only the pin guard is affected.

## Counts once integrated
Nine UI moves / 26 combined carrier rows (25 published + this one). Not 26 UI.
