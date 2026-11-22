# Lab UI-allocation metadata addendum (architect whole-file exceptions, 2026-11-22)

Metadata-only. No source bodies. Base inventory packets/199bv-in2tinct-stations/metadata-cd4
(bridge 18db9d4936475deca1fb8bc21f2cf673a8bb9ca8) stays byte-identical; this file adds rows.

## Exception 1: AdaptiveColor -> UI (whole file, no split)
- File: AdaptiveColor.swift, sha256 2fd63b55e52d7e97a5b21a21856583137373c4fa8bfa52f167133d08bb5be1d6 (content pin, path-independent)
- Interim path (publisher restore, until UI batch): Sources/gor/GorEffectsModel/AdaptiveColor.swift
- Final path at UI batch: Sources/gor/UI/AdaptiveColor.swift
- Supersedes allocation-map line 20 cell "GorEffectsModel/AdaptiveColor -> Picture" (owner order item 2, architect actual Picture-body resolution).
- UI allocation count for lab move scripts: 25-row published inventory + this 1 row = 26 when the UI batch runs. Not part of Media/UI/Modes carrier rows already published.

## Exception 2: LookToolsRoute -> Stereo (whole file, no split)
- File: LookToolsRoute.swift, sha256 3208c01f3c9831bc4b97b5221f20a48e4e9e063fa208bdb89bde19b52d91ca13 (content pin, path-independent)
- Path: Sources/gor/Picture/LookToolsRoute.swift (d765a) -> Sources/gor/Stereo/LookToolsRoute.swift (publisher-composed into pending Stereo integration; publisher-owned, do not duplicate)
- No lab Media/UI/Modes allocation impact; recorded here so lab allocation math stays consistent.

## Unchanged
- Picture final allocation: Viewport/Viewport, Viewport/CropDetector, Display/Brightness (no splits).
- All 25 published carrier rows (Media/UI/Modes at cd4c) stand as published.
