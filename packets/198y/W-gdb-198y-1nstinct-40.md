# W-gdb-198y-1nstinct-40
state: OPEN / unclaimed
lab: 1nstinct

Build a new independent scope-aware source/move characterization test for this exact file. Parse lexical nominal ownership including nesting, ignore comments/strings, and compare fully qualified declaration owners across the entire pinned Sources tree. Do not confuse nested names in unrelated owners with duplicates. Preserve pinned bytes. Check old and mapped station, renamed copies, valid overload/nested-name controls, and real duplicate mutants. Use explicit failure paths that remain active under python3 -O. Run normal and optimized positive plus on-disk external negative/restore controls. The existing 01..20 returns are evidence only and may not be copied unchanged.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-40.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-40",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/PhotonFont.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-40.py checks archive/gor/Sources/gor/PhotonFont.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: PhotonFont, capH100, chromeLayoutScale, setChromeLayoutScale, chromeValue, isInReversedFontSubdir, loadFromURL, invalidateCache, promotePendingMapping, applyAxisMapping, buildAutoMapping, clearAxisMapping",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-40.py",
    "callee": "archive/gor/Sources/gor/PhotonFont.swift owning station GorUI"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-40.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-40.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-40.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.180173+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/PhotonFont.swift",
        "block": "source1",
        "sha256": "bfacd0486b28217d6399a507c4d8f0273e1b70c1e0e13392801f532d3d77aeb7"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-40.py",
        "block": "fixtures1",
        "sha256": "0c3a4fbb107ba8ce4a60af4ba6cc0ffd54cb6d5f95d1604c27955a6fa199cec8"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "5b8fa9e6666005663b8b99516b023ef73d587ca623266828d8e7e8e354999a04",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-40: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "e949a2cc43e3a4c81c5298f0f7fec271102adbb583167e73d9214272219ec3ac"
  }
}
```

```swift id=source1
// ================================================================
//  PhotonFont.swift - measurement-driven font metrics, single source
//  Owns: all font metrics (charW/capH/charH/lineH/pad/gap), axis
//  discovery/mapping/reverse, driven-font caches, LayoutEngine
//  Answers: I18 I19 I20 I21 I22 I23 I39
//  Contract: every layout px derives from these metrics (I23)
// ================================================================
import AppKit
import CoreText

enum PhotonFont {

    // MARK: - User-tunable constants

    static var pointSize: CGFloat {
        // screenH is read live on every access (a display change must be
        // reflected immediately); only the expensive part — building the
        // 100pt probe font and measuring its cap height — is cached,
        // keyed by font name (_capH100).
        let screenH = NSScreen.main?.frame.height ?? 1440
        guard let name = _fontName else { return screenH / 42 }

        let capH = capH100(for: name)

        // capH at 100pt → target capH at screenH, scaled proportionally
        let targetCapH = screenH * 0.015
        let result = targetCapH * (100 / capH)

        return max(12, min(62, result))
    }  // pt

    /// Cap height of the current font at 100pt, cached per font name.
    /// pointSize is read per redraw (SeekBar derives its whole geometry
    /// from it), and CTFontCreateWithName + CTFontGetCapHeight on every
    /// access was the dominant cost of those reads. Cleared by
    /// invalidateCache() (loadFromURL calls it).
    private static var _capH100: (name: String, capH: CGFloat)?
    private static func capH100(for name: String) -> CGFloat {
        if let c = _capH100, c.name == name { return c.capH }
        let probeFont = CTFontCreateWithName(name as CFString, 100, nil)
        let capH = CTFontGetCapHeight(probeFont)
        _capH100 = (name, capH)
        return capH
    }
    static var tracking:   Double  = 0.0  // em - letter spacing (0 none, 0.1 wide)
    static var leading:    Double  = 0.0  // pt - extra inter-line spacing (negative overlaps; lineH floor = charH)
    static var padRatio:   Double  = 0.8  // x capH - edge padding
    static var gapRatio:   Double  = 0.0  // x capH - inter-element spacing

    /// Canonical 2D design canvas for chrome. The owner's measured 3D mockup
    /// content is 817x461; with the 960x540 canvas' scaled spine/sidebar and
    /// pads, its clear content matches that design surface. This is not a
    /// minimum window size and not the film tilt/zoom scale.
    static let chromeDesignCanvasSize = CGSize(width: 960, height: 540)
    static private(set) var chromeScale: CGFloat = 1

    // Source commentary elided for privacy; historical proof hashes are not rebound.
    static let chromeSmallRailUplift: CGFloat = 1.25
    static func chromeLayoutScale(for rail: CGRect) -> CGFloat {
        guard rail.width > 1, rail.height > 1 else { return 1 }
        return min(1, min(rail.width / chromeDesignCanvasSize.width,
                          rail.height / chromeDesignCanvasSize.height) * chromeSmallRailUplift)
    }

    static func setChromeLayoutScale(_ scale: CGFloat) {
        let safe = scale.isFinite ? scale : 1
        let next = max(0.000001, min(1, safe))
        guard abs(next - chromeScale) > 0.0001 else { return }
        chromeScale = next
        // Geometry and fonts land on this same physical-window receipt.
        LayoutEngine.shared.notifyFontChanged(immediate:true)
        VariationBroadcaster.shared.poke()
    }

    /// Scale a design-space offset that is not itself a named font metric.
    static func chromeValue(_ value: CGFloat) -> CGFloat { value * chromeScale }

    /// Fonts loaded from fontsDirName/"sixa"/ get their axes auto-reversed;
    /// fonts anywhere else (fonts/ root or any other subfolder) are isolated
    /// from this behavior. Checked in loadFromURL against loadURL's path.
    static let reversedFontSubdir: String = "sixa"

    /// True if `url` sits under fontsDirName/reversedFontSubdir/ (path-prefix
    /// check, includes nested subfolders of it).
    private static func isInReversedFontSubdir(_ url: URL) -> Bool {
        guard let fontsBase = GORResources.fonts() else { return false }
        let sixaDir = fontsBase
            .appendingPathComponent(reversedFontSubdir)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let candidate = url.resolvingSymlinksInPath().standardizedFileURL
        let sixaComponents = sixaDir.pathComponents
        let candidateComponents = candidate.pathComponents
        guard candidateComponents.count > sixaComponents.count else { return false }
        return Array(candidateComponents.prefix(sixaComponents.count)) == sixaComponents
    }

    /// When true, the first access to fontName (effectively app launch) picks
    /// a random supported file from fonts/ and loads it with isDefault: true.
    /// When false, defaultFontFile always loads. See header for the full flow.
    static let randomFontOnStartup: Bool = true

    // MARK: - Font directories

    // Single source of truth for the path both fontName (default load) and
    // pickRandomFontURL (randomFontOnStartup) read from.
    static let fontsDirName:    String = "fonts"
    static let defaultFontFile: String = "Exposure-VAR.ttf"

    // MARK: - Font loader

    /// Supported formats: ttf, otf, woff, woff2. Falls back to system
    /// monospace on failure. isDefault: true auto-promotes the variable-font
    /// mapping without opening the panel; isDefault: false (drag-drop) stages
    /// it in _pendingAutoMapping and lets PPController open the panel.
    @discardableResult
    static func loadFromURL(_ url: URL, isDefault: Bool = false) -> Bool {
        let ext = url.pathExtension.lowercased()
        let loadURL: URL
        if ext == "woff" || ext == "woff2" {
            guard let converted = convertWOFF(url) else { return false }
            loadURL = converted
        } else {
            loadURL = url
        }

        if let prev = _registeredFontURL {
            CTFontManagerUnregisterFontsForURL(prev as CFURL, .process, nil)
        }

        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(loadURL as CFURL, .process, &error) else {
            if let e = error?.takeRetainedValue() {
                print("[PhotonFont] Registration error: \(e)")
            }
            return false
        }

        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(loadURL as CFURL) as? [CTFontDescriptor],
              let name  = CTFontDescriptorCopyAttribute(descs[0], kCTFontNameAttribute) as? String
        else { return false }

        _fontName = name
        _registeredFontURL = loadURL

        _axisRanges = discoverAxes(url: loadURL)
        clearAxisMapping()

        if !_axisRanges.isEmpty {
            let auto = buildAutoMapping()
            if isDefault {
                applyAxisMapping(auto)
                let reversed = isInReversedFontSubdir(loadURL)
                if reversed {
                    for tag in _axisRanges.keys {
                        reversedAxes.insert(tag)
                    }
                }
                print("[PhotonFont] Default font - auto-mapping applied (panel not opened), reversed=\(reversed) (\(reversedFontSubdir)/ isolation)")
            } else {
                _pendingAutoMapping = auto
            }
        }

        invalidateCache()
        LayoutEngine.shared.notifyFontChanged()
        // Driven listeners fan out only on mouse/audio motion; poke once so
        // every surface re-applies the new face immediately, mouse still or
        // not. Hopped to main because listeners touch views.
        DispatchQueue.main.async { VariationBroadcaster.shared.poke() }
        let tagNames = _axisRanges.keys.map { fourCC($0) }
        let mappingDesc = axisMapping.isEmpty ? "(empty)" : axisMapping.map { "signal\($0.key)→[\($0.value.map { fourCC($0) }.joined(separator: ","))]" }.joined(separator: ", ")
        let pendingDesc = _pendingAutoMapping.isEmpty ? "(empty)" : _pendingAutoMapping.map { "\($0.key)→[\($0.value.map { fourCC($0) }.joined(separator: ","))]" }.joined(separator: ", ")
        print("[PhotonFont] Loaded: \(name) - axes: \(tagNames), mapping: \(mappingDesc), pending: \(pendingDesc)")
        return true
    }

    /// Drops all cached metrics and driven-font instances; call after any
    /// font-affecting change so subsequent lookups rebuild against the new state.
    static func invalidateCache() {
        _metrics = nil
        _cache = [:]
        _nsCache = [:]
        _cacheClock = 0
        _cacheIndex = [:]
        _capH100 = nil
        _faceFont = nil
        _faceFontName = nil
        _plainCache = [:]
        _plainCacheName = nil
        _twoDigitW = nil
    }

    // MARK: - Axis system
    //
    //  Signal-index system: axisMapping is [signalIndex: tagSet]; the key
    //  is the signal index, the value the axis tags that signal drives
    //  (a weight set - multiple tags can share one signal).
    //  I18: no AxisRole enum, no drivenAxisOrder, no TAG_* constants -
    //  each font writes its own axis universe into _axisRanges.

    /// Signal index → axis tag set. Keys: 0 = audio+prox, 1 = soft-prox,
    /// 2 = inv-prox, 3 = hard-prox, 4 = audio, 5+ ... . Multiple tags may
    /// share one signal index (weight-set behavior).
    static private(set) var axisMapping: [Int: Set<Int>] = [:]

    /// Computed by loadFromURL but not yet committed to axisMapping.
    /// Panel Esc     → promoted via promotePendingMapping().
    /// Panel confirm → user's choice is written via applyAxisMapping(), which resets this to empty.
    static private(set) var _pendingAutoMapping: [Int: Set<Int>] = [:]

    /// True when a variable font is loaded but has no mapping yet.
    /// PPController watches this flag to open the panel.
    /// Drag-drop (custom) leaves _pendingAutoMapping set and axisMapping empty → true.
    /// Default load (isDefault: true) fills axisMapping immediately → false, panel stays closed.
    static var needsAxisMapping: Bool {
        !_axisRanges.isEmpty && axisMapping.isEmpty
    }

    /// Promotes the auto-mapping when the user dismisses the panel (Esc).
    /// Called from SpineUI.showAxisMapping's onDismiss callback.
    static func promotePendingMapping() {
        guard !_pendingAutoMapping.isEmpty else { return }
        applyAxisMapping(_pendingAutoMapping)
        _pendingAutoMapping = [:]
        print("[PhotonFont] Pending auto-mapping promoted -> variation active")
    }

    /// Commits a user- or auto-generated mapping to axisMapping.
    static func applyAxisMapping(_ mapping: [Int: Set<Int>]) {
        axisMapping = mapping
        _pendingAutoMapping = [:]
        let desc = mapping
            .sorted { $0.key < $1.key }
            .map { "signal\($0.key)→[\($0.value.map { fourCC($0) }.joined(separator: ","))]" }
            .joined(separator: ", ")
        invalidateCache()
        LayoutEngine.shared.notifyFontChanged()
        DispatchQueue.main.async { VariationBroadcaster.shared.poke() }
        print("[PhotonFont] Axis mapping applied: \(desc)")
    }

    /// I22: wght->0, SIZE->1, ROTA->2 when present. Remaining axes are
    /// sorted by range size descending (widest ~ most important) and take
    /// the lowest free signal index scanning from 0 - so with no known
    /// tags the most important axis lands on signal 0 (the audio+proximity
    /// blend) and a single-axis font needs no special case.
    static func buildAutoMapping() -> [Int: Set<Int>] {
        let wghtTag: Int = 0x77676874
        let sizeTag: Int = 0x53495A45
        let rotaTag: Int = 0x524F5441

        var mapping: [Int: Set<Int>] = [:]
        var used: Set<Int> = []

        // 1) Known tags take their canonical signal index
        if _axisRanges[wghtTag] != nil { mapping[0] = [wghtTag]; used.insert(wghtTag) }
        if _axisRanges[sizeTag] != nil { mapping[1] = [sizeTag]; used.insert(sizeTag) }
        if _axisRanges[rotaTag] != nil { mapping[2] = [rotaTag]; used.insert(rotaTag) }

        // 2) Remaining axes: lowest free signal index scanning from 0,
        //    so with 0-2 filled this starts at 3, with none matched at 0.
        var nextIndex = 0
        let remaining = _axisRanges.keys
            .filter { !used.contains($0) }
            .sorted { abs(_axisRanges[$0]!.max - _axisRanges[$0]!.min) >
                      abs(_axisRanges[$1]!.max - _axisRanges[$1]!.min) }
        for tag in remaining {
            while mapping[nextIndex] != nil { nextIndex += 1 }
            mapping[nextIndex] = [tag]
            nextIndex += 1
        }

        return mapping
    }

    /// Clears the user mapping (e.g. when reverting to the default font).
    static func clearAxisMapping() {
        axisMapping = [:]
        _pendingAutoMapping = [:]
    }

    /// All axis ranges for the current font: [tag: (min, max, default)]
    static private(set) var _axisRanges: [Int: (min: Double, max: Double, def: Double)] = [:]

    /// Whether the current font exposes this axis.
    static func hasAxis(_ tag: Int) -> Bool { _axisRanges[tag] != nil }

    /// Clamps a value to the axis's range; passes through unchanged if the range is unknown.
    static func clamp(tag: Int, value: Double) -> Double {
        guard let r = _axisRanges[tag] else { return value }
        return Swift.max(r.min, Swift.min(r.max, value))
    }

    // MARK: - Axis direction (reverse)
    //
    //  reversedAxes is keyed by axis tag, not signal index - one signal can
    //  drive multiple tags (weight-set) and each axis gets its own reverse
    //  toggle in the panel. loadFromURL/clearAxisMapping never touch this
    //  set: reverse state is tied to tag identity and carries over when the
    //  same tag reappears in a reloaded font.

    /// Set of reversed axis tags. Read when the panel opens, written on
    /// commit via applyReversedAxes(_:).
    static private(set) var reversedAxes: Set<Int> = []

    /// Whether this axis is reversed.
    static func isReversed(_ tag: Int) -> Bool { reversedAxes.contains(tag) }

    /// Toggles a single axis's reverse state.
    static func toggleReversed(_ tag: Int) {
        if reversedAxes.contains(tag) { reversedAxes.remove(tag) }
        else { reversedAxes.insert(tag) }
    }

    /// Called on panel commit — writes all of the user's reverse-toggle
    /// choices at once, mirroring applyAxisMapping(_:)'s stage → confirm →
    /// commit flow for signal mapping.
    static func applyReversedAxes(_ tags: Set<Int>) {
        reversedAxes = tags
    }

    /// Called from PPController; shows the mapping UI via SpineUI.showAxisMapping.
    static func presentAxisMapping() {
        guard let spineUI = (NSApp.delegate as? AppDelegate)?.controller?.spineUI else { return }
        let axes = axesForMapping()
        guard !axes.isEmpty else { return }
        let auto = _pendingAutoMapping.isEmpty ? buildAutoMapping() : _pendingAutoMapping

        spineUI.showAxisMapping(
            axes: axes,
            autoMapping: auto,
            reversedAxes: reversedAxes,
            onComplete: { mapping, reversed in
                applyAxisMapping(mapping)
                applyReversedAxes(reversed)
                let desc = mapping
                    .sorted { $0.key < $1.key }
                    .map { "signal\($0.key)→[\($0.value.map { fourCC($0) }.joined(separator: ","))]" }
                    .joined(separator: ", ")
                let reversedDesc = reversed.isEmpty ? "(empty)" : reversed.map { fourCC($0) }.joined(separator: ", ")
                print("[PhotonFont] Mapping complete: \(desc), reversed: \(reversedDesc)")
            },
            onDismiss: {
                promotePendingMapping()
            }
        )
    }

    /// Axis list to present to the user — (tag, display label) pairs.
    static func axesForMapping() -> [(tag: Int, name: String)] {
        guard let url = _registeredFontURL,
              let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let desc  = descs.first else { return [] }
        let font = CTFontCreateWithFontDescriptor(desc, 12, nil)
        guard let rawAxes = CTFontCopyVariationAxes(font) as? [[String: Any]] else { return [] }

        return rawAxes.compactMap { dict -> (tag: Int, name: String)? in
            guard let tag = dict[kCTFontVariationAxisIdentifierKey as String] as? Int else { return nil }
            let rawName = (dict[kCTFontVariationAxisNameKey as String] as? String) ?? fourCC(tag)
            return (tag: tag, name: axisLabel(tag: tag, name: rawName))
        }
    }

    /// Dropdown label — currently just the raw CT axis name.
    static func axisLabel(tag: Int, name: String) -> String { name }

    // MARK: - Derived dimensions (do not edit)
    // I23: all layout px derive from these; no hardcoded px in any layout path.

    static var charW:      CGFloat { metrics.charW }
    /// Cap height — pure uppercase height (no leading, no ascender/descender).
    /// Drives padding and gap calculations.
    static var capH:       CGFloat { metrics.capH }
    /// Full typographic height = ascent + descent. A CATextLayer frame at this
    /// height never clips. Unaffected by leading.
    static var charH:      CGFloat { metrics.charH }
    /// Line step = charH + leading (pt). Negative leading overlaps; floor = charH.
    /// CATextLayer frame height is always charH — only the layout step changes.
    static var lineH:      CGFloat { max(metrics.charH, metrics.charH + CGFloat(leading)) }
    static var pad:        CGFloat { metrics.capH * CGFloat(padRatio) }
    static var gap:        CGFloat { metrics.capH * CGFloat(gapRatio) }
    static var trackingPx: CGFloat { metrics.charW * CGFloat(tracking) }
    /// SeekBar dot radius — capH × 0.07. "." advance width varies too much
    /// across fonts to use directly; the capH ratio scales consistently with
    /// sidebar font size instead. ~1.7px radius / 3.4px diameter at
    /// pointSize=25. SeekBar.solidW = capH × 0.035 (half of this).
    static var dotRadius:  CGFloat { metrics.dotRadius }

    static var size:       CGFloat { pointSize }
    static var charWidth:  CGFloat { charW }

    /// Collapsed (single-char) button width — font charW + gap.
    /// Used by TrafficTextBtn / VolumeSliderBtn idle state.
    static var collapsedBtnW: CGFloat { charW + gap }

    /// Expanded (full-text) button width — measured pixel width of the text
    /// plus two pads. Re-measures automatically on font change; replaces a
    /// hardcoded 220.
    static func expandedBtnW(for text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: ns(), .kern: trackingPx]
        let measured = (text as NSString).size(withAttributes: attrs).width
        return max(measured + pad * 2, collapsedBtnW)
    }

    // MARK: - Chrome-scoped typography
    //
    // Subtitles keep the canonical metrics above. Every chrome surface uses
    // this same locally scaled family, so layout measurements and glyph sizes
    // cannot diverge inside a panel, button, or CATextLayer.
    static var chromeCharW:      CGFloat { charW * chromeScale }
    static var chromeCapH:       CGFloat { capH * chromeScale }
    static var chromeCharH:      CGFloat { charH * chromeScale }
    static var chromeLineH:      CGFloat { lineH * chromeScale }
    static var chromePad:        CGFloat { pad * chromeScale }
    static var chromeGap:        CGFloat { gap * chromeScale }
    static var chromeTrackingPx: CGFloat { trackingPx * chromeScale }
    static var chromeDotRadius:  CGFloat { dotRadius * chromeScale }
    static var chromeSize:       CGFloat { pointSize * chromeScale }
    static var chromeCharWidth:  CGFloat { chromeCharW }
    static var chromeTwoDigitW:  CGFloat { twoDigitW * chromeScale }
    static var chromeCollapsedBtnW: CGFloat { chromeCharW + chromeGap }

    /// Design-space inputs for PPController.reflowVideoFramePanel; it applies
    /// chromeValue once. Callers must not pre-scale these aliases.
    static var designPad:       CGFloat { pad }
    static var designTwoDigitW: CGFloat { twoDigitW }

    static func chromeExpandedBtnW(for text: String) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: chromeNs(), .kern: chromeTrackingPx]
        let measured = (text as NSString).size(withAttributes: attrs).width
        return max(measured + chromePad * 2, chromeCollapsedBtnW)
    }

    // MARK: - Font construction

    /// Base CTFont, no variation. The wght/SIZE/ROTA parameters are a
    /// temporary bridge (I20 - do not remove yet) that maps through
    /// axisMapping, kept for legacy callers (MusicPanel, SidebarUI, SpineUI).
    static func ct(size s: CGFloat? = nil,
                   wght: Double? = nil,
                   SIZE: Double? = nil,
                   ROTA: Double? = nil) -> CTFont {
        let sz = s ?? pointSize
        let hasVars = wght != nil || SIZE != nil || ROTA != nil

        if !hasVars {
            return ctPlain(size: sz)
        }

        let vars = buildVarsBridge(wght: wght, SIZE: SIZE, ROTA: ROTA)
        let key = cacheKey(vars: vars, size: sz)
        if let cached = _cache[key] { touchCacheEntry(key); return cached }

        let desc = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: fontName as CFString,
            kCTFontVariationAttribute: vars as CFDictionary
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(desc, sz, nil)
        _cache[key] = font
        noteCacheInsertion(key)
        return font
    }

    // Source commentary elided for privacy; historical proof hashes are not rebound.
    private static func nsBase(size sz: CGFloat) -> NSFont {
        if let f = NSFont(name: fontName, size: sz) { return f }
        return CTFontCreateWithName(fontName as CFString, sz, nil) as NSFont
    }

    static func ns(size s: CGFloat? = nil,
                   wght: Double? = nil,
                   SIZE: Double? = nil,
                   ROTA: Double? = nil) -> NSFont {
        let sz = s ?? pointSize
        let hasVars = wght != nil || SIZE != nil || ROTA != nil
        let base = nsBase(size: sz)
        guard hasVars else { return base }
        let vars = buildVarsBridge(wght: wght, SIZE: SIZE, ROTA: ROTA)
        let key = cacheKey(vars: vars, size: sz)
        if let cached = _nsCache[key] { touchCacheEntry(key); return cached }

        let desc = base.fontDescriptor.addingAttributes([
            .variation: vars
        ])
        let font = NSFont(descriptor: desc, size: sz) ?? base
        _nsCache[key] = font
        noteCacheInsertion(key)
        return font
    }

    static func chromeCt(size s: CGFloat? = nil,
                         wght: Double? = nil,
                         SIZE: Double? = nil,
                         ROTA: Double? = nil) -> CTFont {
        ct(size: s ?? chromeSize, wght: wght, SIZE: SIZE, ROTA: ROTA)
    }

    static func chromeNs(size s: CGFloat? = nil,
                         wght: Double? = nil,
                         SIZE: Double? = nil,
                         ROTA: Double? = nil) -> NSFont {
        ns(size: s ?? chromeSize, wght: wght, SIZE: SIZE, ROTA: ROTA)
    }

    static func chromeNsBase(size sz: CGFloat) -> NSFont { nsBase(size: sz) }

    static func chromeCt(vars: [Int: Double], size sz: CGFloat? = nil) -> CTFont {
        ct(vars: vars, size: sz ?? chromeSize)
    }

    static func chromeCtDriven(p: CGFloat, t_audio: Double, size sz: CGFloat? = nil) -> CTFont {
        ctDriven(p: p, t_audio: t_audio, size: sz ?? chromeSize)
    }

    static func chromeNsDriven(p: CGFloat, t_audio: Double, size sz: CGFloat? = nil) -> NSFont {
        nsDriven(p: p, t_audio: t_audio, size: sz ?? chromeSize)
    }

    /// Face-only CTFont - no variation axes, one cached instance per font
    /// name, for CATextLayer sites that render the same face at many sizes
    /// through the layer's own fontSize.
    /// I39: render-only, never for measurement (ct()/ctPlain(size:)/ns()
    /// own that). Reads `fontName` (not _fontName) so the lazy first-load
    /// side effect is preserved; cleared by invalidateCache().
    static func ctFace() -> CTFont {
        let name = fontName
        if let f = _faceFont, _faceFontName == name { return f }
        let f = CTFontCreateWithName(name as CFString, pointSize, nil)
        _faceFont = f
        _faceFontName = name
        return f
    }

    /// Exact-size plain (no variation) CTFont from a small bounded cache.
    /// Keyed by the size's bit pattern; on overflow the whole map is dropped
    /// (cap PlainCacheMaxEntries) - tiny, rebuilds are one CoreText call.
    /// Reads `fontName` (not _fontName) so the lazy first-load side effect
    /// is preserved.
    static func ctPlain(size sz: CGFloat) -> CTFont {
        let name = fontName
        if _plainCacheName != name {
            _plainCache.removeAll()
            _plainCacheName = name
        }
        let key = UInt64(sz.bitPattern)
        if let cached = _plainCache[key] { return cached }
        let font = CTFontCreateWithName(name as CFString, sz, nil)
        if _plainCache.count >= PlainCacheMaxEntries { _plainCache.removeAll() }
        _plainCache[key] = font
        return font
    }

    // MARK: - Display-property assignment guard
    //
    //  WHY: CATextLayer.font / NSTextField.font rebuild CoreText's
    //  typesetter on every assignment, even a same-instance reassignment,
    //  so 60fps listeners must not re-assign an unchanged font. Separate
    //  overloads per receiver type: CTFont/NSFont are only bridged, and a
    //  single common-type overload does not compile.

    /// Skips the assignment when the current layer font is CFEqual to font.
    /// Equal CoreText fonts need no typesetter rebuild, even when distinct objects.
    static func setIfChanged(_ font: CTFont, on layer: CATextLayer, file: StaticString = #fileID, line: Int = #line) {
        let same = layer.font.map { CFEqual($0 as! CTFont, font) } ?? false
        HeatTelemetry.noteFont(changed: !same, file, line)
        if !same { layer.font = font }
    }

    /// NSFont overload, for CATextLayer sites driven by nsDriven/ns.
    /// TRAP: layer.font holds a CTFont or an NSFont toll-free bridged to
    /// CTFont, so `as! CTFont` is a bridging cast - comparing via
    /// `as? NSFont` + `===` misses across the two representations of the
    /// same font and the guard passes through every tick.
    static func setIfChanged(_ font: NSFont, on layer: CATextLayer, file: StaticString = #fileID, line: Int = #line) {
        let same = layer.font.map { CFEqual($0 as! CTFont, font as CTFont) } ?? false
        HeatTelemetry.noteFont(changed: !same, file, line)
        if !same { layer.font = font }
    }


    /// NSTextField overload (PLabel and friends).
    static func setIfChanged(_ font: NSFont, on field: NSTextField) {
        guard field.font !== font else { return }
        field.font = font
    }

    // MARK: - Seek bar alignment

    static var twoDigitW: CGFloat {
        // Memoized on (fontName, pointSize, trackingPx): this re-measured the
        // same "00" string on every access, and it sits on hot paths
        // (barX(), sidebarWidth) that run once per redraw. pointSize is part
        // of the key, so a screen change (which pointSize reads live) still
        // recomputes. Cleared by invalidateCache().
        let name = fontName
        let ps   = pointSize
        let tk   = trackingPx
        if let c = _twoDigitW,
           c.fontName == name, c.pointSize == ps, c.trackingPx == tk {
            return c.width
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: ns(),
            .kern: trackingPx,
        ]
        let w = ("00" as NSString).size(withAttributes: attrs).width
        _twoDigitW = (fontName: name, pointSize: ps, trackingPx: tk, width: w)
        return w
    }

    static var seekBarX: CGFloat {
        return twoDigitW - pad
    }

    // MARK: - Private state

    private static var _fontName: String?
    private static var _registeredFontURL: URL?
    private static var _metrics: Metrics?
    private static var _faceFont: CTFont?
    private static var _faceFontName: String?
    private static var _plainCache: [UInt64: CTFont] = [:]
    private static var _plainCacheName: String?
    private static let PlainCacheMaxEntries = 64
    private static var _twoDigitW: (fontName: String, pointSize: CGFloat, trackingPx: CGFloat, width: CGFloat)?

    // MARK: - Font cache
    //
    //  WHY: CTFontCreateWithFontDescriptor walks CoreText's TInstanceFont
    //  path and is too expensive to call every 60fps tick per listener.
    //  _cache maps a quantized variation-state key to the built font;
    //  LRU eviction (CacheMaxEntries) keeps the hot idle state pinned
    //  where FIFO would age it out. invalidateCache() clears all of this
    //  so a reloaded font never serves stale instances.
    private static var _cache: [String: CTFont] = [:]
    private static var _nsCache: [String: NSFont] = [:]
    private static var _cacheClock = 0
    /// key → last-use stamp (_cacheClock), so an LRU hit is O(1) (was an O(n) array shift + reindex per hit)
    /// and only a miss past the cap scans for the oldest stamp.
    private static var _cacheIndex: [String: Int] = [:]
    private static let CacheMaxEntries = 1024   // same key -> same font (identical output); only retention grows, ~75 listeners x audio states no longer thrash 256
    static let CacheQuantizationSteps: Double = { let v = UserDefaults.standard.double(forKey: "gor.heat.axisSteps"); return v >= 16 && v <= 128 ? v.rounded() : 128 }()  // default 128 (~0.008 per axis, identical to before); gor.heat.axisSteps 16...127 = coarser, fewer re-typesets (owner opt-in)

    /// Quantizes a driven-axis vars dict + size into a stable, coarse cache
    /// key. Sorted by tag so key construction is order-independent; each
    /// value is rounded to CacheQuantizationSteps buckets so near-identical
    /// continuous input (sub-pixel mouse motion, audio jitter) collapses onto
    /// the same key.
    private static func cacheKey(vars: [Int: Double], size: CGFloat) -> String {
        guard !vars.isEmpty else { return "novars|\(Int(size.rounded()))" }
        var parts: [String] = []
        parts.reserveCapacity(vars.count)
        for tag in vars.keys.sorted() {
            let v = vars[tag]!
            // WHY: normalize to [0,1] against the axis's own range so
            // CacheQuantizationSteps means the same granularity on every
            // axis (a fixed raw step barely quantizes a wide-range axis
            // like wght). Coupled: VariationBroadcaster.NoOpAudioThreshold
            // assumes this [0,1]-space quantization.
            let normalized: Double
            if let r = _axisRanges[tag], r.max > r.min {
                normalized = (v - r.min) / (r.max - r.min)
            } else {
                normalized = v
            }
            let q = (normalized * CacheQuantizationSteps).rounded() / CacheQuantizationSteps
            parts.append("\(tag):\(q)")
        }
        return parts.joined(separator: ",") + "|\(Int((size * 4).rounded()))"
    }

    /// Records a cache insertion for LRU eviction; evicts the least-recently-
    /// used entries once past CacheMaxEntries. Shared between the CTFont and
    /// NSFont caches — key collisions across the two dictionaries don't
    /// matter since they're stored separately; only the ordering list is shared.
    private static func noteCacheInsertion(_ key: String) {
        if _cacheIndex[key] != nil { return }
        _cacheClock += 1
        _cacheIndex[key] = _cacheClock
        while _cacheIndex.count > CacheMaxEntries {
            guard let evict = _cacheIndex.min(by: { $0.value < $1.value })?.key else { break }
            _cacheIndex.removeValue(forKey: evict)
            _cache.removeValue(forKey: evict)
            _nsCache.removeValue(forKey: evict)
        }
    }

    /// Marks `key` as most-recently-used; called on every cache HIT, not
    /// just insertion - that is what makes this LRU instead of FIFO (the
    /// idle state is inserted once but hit constantly). O(1): one stamp write.
    private static func touchCacheEntry(_ key: String) {
        guard _cacheIndex[key] != nil else { return }
        _cacheClock += 1
        _cacheIndex[key] = _cacheClock
    }

    private struct Metrics {
        let charW:     CGFloat  // "M" width (measured)
        let capH:      CGFloat  // CTFontGetCapHeight — pure uppercase height
        let charH:     CGFloat  // ascent + descent — clip-free typographic height
        let dotRadius: CGFloat  // "." glyph radius
    }

    static var fontName: String {
        if let n = _fontName { return n }
        // randomFontOnStartup: pick randomly from fonts/, falling back to
        // defaultFontURL if the folder is empty or unreadable. Otherwise, default directly.
        let url = (randomFontOnStartup ? pickRandomFontURL() : nil) ?? defaultFontURL
        // isDefault: true auto-maps variable-font axes without opening the panel.
        _ = loadFromURL(url, isDefault: true)
        return _fontName ?? "Menlo-Regular"
    }

    /// Fixed default font URL, built from fontsDirName/defaultFontFile.
    static var defaultFontURL: URL {
        URL(fileURLWithPath: GORResources.fontsPath(defaultFontFile))
    }

    /// Picks a random supported font file (ttf/otf/woff/woff2) from fonts/.
    /// Returns nil if the folder is unreadable or has no supported files —
    /// the caller (fontName) falls back to defaultFontURL.
    static func pickRandomFontURL() -> URL? {
        guard let dirURL = GORResources.fonts() else { return nil }
        // fonts/ resolves through GORResources (a real directory in both
        // layouts) - enumerate it directly.
        let supportedExts: Set<String> = ["ttf", "otf", "woff", "woff2"]

        // Recursive: scans fonts/ root plus every child folder (e.g. fonts/sixa/).
        // sixa/ fonts get reversed-axis isolation but stay in the random pool —
        // see isInReversedFontSubdir.
        guard let enumerator = FileManager.default.enumerator(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[PhotonFont] randomFontOnStartup: fonts/ folder unreadable (enumerator could not be created) - \(dirURL.path)")
            return nil
        }

        var candidates: [URL] = []
        for case let fileURL as URL in enumerator {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            if supportedExts.contains(fileURL.pathExtension.lowercased()) {
                candidates.append(fileURL)
            }
        }

        guard let pick = candidates.randomElement() else {
            print("[PhotonFont] randomFontOnStartup: no suitable font in fonts/ (including subfolders) - \(dirURL.path)")
            return nil
        }
        print("[PhotonFont] randomFontOnStartup: picked font - \(pick.path.replacingOccurrences(of: dirURL.path + "/", with: "")) (\(candidates.count) candidates, including subfolders)")
        return pick
    }


    private static var metrics: Metrics {
        if let m = _metrics { return m }
        let ct  = CTFontCreateWithName(fontName as CFString, pointSize, nil)
        // charW: measured via NSString "M" — most stable across variable-font weight changes
        let nsf = ns()
        let mW  = ("M" as NSString).size(withAttributes: [.font: nsf]).width
        // capH: the CTFont's actual cap height — font-specific, can differ from "M".height
        let capH = CTFontGetCapHeight(ct)
        // charH: ascent + |descent| — minimum frame height that contains all text
        let charH = CTFontGetAscent(ct) + abs(CTFontGetDescent(ct))
        // dotRadius: capH × 7% — see dotRadius property doc for why (advance
        // width varies too much across fonts to use directly).
        let dotR  = capH * 0.07
        let m = Metrics(charW: mW + 5, capH: capH, charH: charH, dotRadius: dotR)
        _metrics = m
        return m
    }

    // MARK: - Driven axis system
    //
    //  I19: fixed signal palette - 0=audio+prox, 1=soft-prox, 2=inv-prox,
    //  3=hard-prox, 4=audio, 5+ continues curve(p, power: 1.5 + i*0.5).
    //  axisMapping[signalIndex] is the tag set that signal drives.

    /// Maps t ∈ [0,1] to the axis tag's real range. t=0 → default (the font
    /// designer's intent), t=1 → max. If the axis is reversed
    /// (reversedAxes.contains(tag)), t is flipped (1-t) before the mapping —
    /// t=0 now lands on max, t=1 on default. All callers (buildVars,
    /// buildSVVars, and by extension ctDriven/nsDriven) pass through this one
    /// function, so reverse logic lives only here and in
    /// scaledValue(tag:tFull:). NOTE: buildVarsBridge does not call this — it
    /// clamps already-scaled literal values directly (e.g. wght: 900 for a
    /// static style), so it's unaffected by reverse. This is intentional
    /// (I22 — reverse applies only to the driven-signal pipeline).
    static func scaledValue(tag: Int, t: Double) -> Double {
        guard let r = _axisRanges[tag] else { return t }
        var tc = t.clamped(0, 1)
        if reversedAxes.contains(tag) { tc = 1.0 - tc }
        return r.def + tc * (r.max - r.def)
    }

    /// I21: full-range variant - t in [0,1] maps to [axisMin, axisMax],
    /// used by SubtitleView's signal-0 tag set (tFull). Reverse flips t
    /// here, so it applies automatically through buildVars/ctDriven/nsDriven.
    static func scaledValue(tag: Int, tFull t: Double) -> Double {
        guard let r = _axisRanges[tag] else { return t }
        var tc = t.clamped(0, 1)
        if reversedAxes.contains(tag) { tc = 1.0 - tc }
        return r.min + tc * (r.max - r.min)
    }

    /// Signal-index based variable builder.
    /// signalProvider: (signalIndex) → t [0,1]
    /// For each (signalIndex, tagSet) pair, gets t and writes scaledValue to every tag.
    static func buildVars(for mapping: [Int: Set<Int>],
                          signalProvider: (Int) -> Double) -> [Int: Double] {
        var vars: [Int: Double] = [:]
        for (signalIndex, tags) in mapping {
            let t = signalProvider(signalIndex)
            for tag in tags {
                vars[tag] = clamp(tag: tag, value: scaledValue(tag: tag, tFull: t))
            }
        }
        return vars
    }

    /// SubtitleView-specific helper.
    /// signal0T: tFull [0,1] — full-range (wght equivalent, signal index 0)
    /// signal1T: t [0,1]     — default-anchored (SIZE equivalent, signal index 1)
    /// signal2T: t [0,1]     — default-anchored (ROTA equivalent, signal index 2)
    ///
    /// Reads the tag sets from axisMapping[0/1/2]. Signal 0 uses
    /// scaledValue(tag:tFull:), signals 1/2 use scaledValue(tag:t:). Handles
    /// SV's tFull/t split directly — does not use ctDriven (I2).
    static func buildSVVars(signal0T: Double,
                            signal1T: Double,
                            signal2T: Double) -> [Int: Double] {
        var vars: [Int: Double] = [:]
        if let tags = axisMapping[0] {
            for tag in tags {
                vars[tag] = clamp(tag: tag, value: scaledValue(tag: tag, tFull: signal0T))
            }
        }
        if let tags = axisMapping[1] {
            for tag in tags {
                vars[tag] = clamp(tag: tag, value: scaledValue(tag: tag, t: signal1T))
            }
        }
        if let tags = axisMapping[2] {
            for tag in tags {
                vars[tag] = clamp(tag: tag, value: scaledValue(tag: tag, t: signal2T))
            }
        }
        return vars
    }

    /// Builds a CTFont from a vars dict (the result of buildSVVars or buildVars).
    /// Cache-first: quantized (vars, size) key checked before any CoreText call.
    /// See the "── FONT CACHE ──" block above for rationale.
    static func ct(vars: [Int: Double], size sz: CGFloat? = nil) -> CTFont {
        let s = sz ?? pointSize
        guard !vars.isEmpty else {
            return ctPlain(size: s)
        }
        let key = cacheKey(vars: vars, size: s)
        if let cached = _cache[key] { touchCacheEntry(key); return cached }

        let desc = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: fontName as CFString,
            kCTFontVariationAttribute: vars as CFDictionary
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(desc, s, nil)
        _cache[key] = font
        noteCacheInsertion(key)
        return font
    }

    /// Produces the drive signal for a given signal index, t ∈ [0,1].
    /// Fixed, font-agnostic signal palette (I20).
    static func driveSignal(axisIndex i: Int, p: CGFloat, t_audio: Double) -> Double {
        let vb = VariationBroadcaster.shared
        switch i {
        case 0: return t_audio                                          // audio + proximity
        case 1: return Double(vb.curve(p, power: 2.5))                 // soft proximity
        case 2: return 1.0 - Double(vb.curve(p, power: 1.0))          // inverse proximity
        case 3: return Double(vb.curve(p, power: 3.0))                 // hard proximity
        case 4: return vb.smoothAudio                                   // raw audio
        default: return Double(vb.curve(p, power: 1.5 + Double(i) * 0.5))
        }
    }

    /// Builds a CTFont by driving every axis in axisMapping.
    /// Cache-first: the quantized key check runs before any CoreText call.
    static func ctDriven(p: CGFloat, t_audio: Double, size sz: CGFloat? = nil) -> CTFont {
        let s = sz ?? pointSize
        guard !_axisRanges.isEmpty, !axisMapping.isEmpty else {
            return ctPlain(size: s)
        }
        let vars = buildVars(for: axisMapping) { signalIndex in
            driveSignal(axisIndex: signalIndex, p: p, t_audio: t_audio)
        }
        let key = cacheKey(vars: vars, size: s)
        if let cached = _cache[key] { touchCacheEntry(key); return cached }

        let desc = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: fontName as CFString,
            kCTFontVariationAttribute: vars as CFDictionary
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(desc, s, nil)
        _cache[key] = font
        noteCacheInsertion(key)
        return font
    }

    /// Builds an NSFont by driving every axis.
    /// Cache-first — see ctDriven above for the same treatment on the CTFont side.
    static func nsDriven(p: CGFloat, t_audio: Double, size sz: CGFloat? = nil) -> NSFont {
        let s = sz ?? pointSize
        guard !_axisRanges.isEmpty, !axisMapping.isEmpty else {
            return nsBase(size: s)
        }
        let vars = buildVars(for: axisMapping) { signalIndex in
            driveSignal(axisIndex: signalIndex, p: p, t_audio: t_audio)
        }
        let key = cacheKey(vars: vars, size: s)
        if let cached = _nsCache[key] { touchCacheEntry(key); return cached }

        let base = nsBase(size: s)
        let desc = base.fontDescriptor.addingAttributes([
            .variation: vars
        ])
        let font = NSFont(descriptor: desc, size: s) ?? base
        _nsCache[key] = font
        noteCacheInsertion(key)
        return font
    }

    // MARK: - Private helpers

    /// I20: writes wght/SIZE/ROTA values to axisMapping[0/1/2]'s tag sets;
    /// temporary bridge for ct(wght:SIZE:ROTA:)/ns(wght:SIZE:ROTA:), values
    /// arrive pre-scaled so reverse does not apply here.
    private static func buildVarsBridge(wght: Double?, SIZE: Double?, ROTA: Double?) -> [Int: Double] {
        var vars: [Int: Double] = [:]
        if let w = wght {
            for tag in axisMapping[0] ?? [] {
                vars[tag] = clamp(tag: tag, value: w)
            }
        }
        if let s = SIZE {
            for tag in axisMapping[1] ?? [] {
                vars[tag] = clamp(tag: tag, value: s)
            }
        }
        if let r = ROTA {
            for tag in axisMapping[2] ?? [] {
                vars[tag] = clamp(tag: tag, value: r)
            }
        }
        return vars
    }

    /// Discovers a variable font's axes via CTFontDescriptor.
    private static func discoverAxes(url: URL) -> [Int: (min: Double, max: Double, def: Double)] {
        guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let desc  = descs.first else {
            print("[PhotonFont] discoverAxes: descriptor unavailable - \(url.lastPathComponent)")
            return [:]
        }
        let font = CTFontCreateWithFontDescriptor(desc, 12, nil)
        guard let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] else {
            return [:]
        }
        var result: [Int: (Double, Double, Double)] = [:]
        for axis in axes {
            guard let tag = axis[kCTFontVariationAxisIdentifierKey as String] as? Int,
                  let min = axis[kCTFontVariationAxisMinimumValueKey as String] as? Double,
                  let max = axis[kCTFontVariationAxisMaximumValueKey as String] as? Double,
                  let def = axis[kCTFontVariationAxisDefaultValueKey as String] as? Double
            else { continue }
            result[tag] = (min, max, def)
            print("[PhotonFont] Axis: \(fourCC(tag)) tag=\(tag) min=\(min) max=\(max) def=\(def) range=\(max-min)")
        }
        return result
    }

    /// Temporary woff/woff2 → OTF/TTF conversion.
    private static func convertWOFF(_ url: URL) -> URL? {
        let ext = url.pathExtension.lowercased()
        _ = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".otf")

        if ext == "woff2" {
            var err: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
            if ok {
                CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
                return url
            }
            print("[PhotonFont] woff2 conversion needed - macOS does not support it natively")
            return nil
        }

        guard let data = try? Data(contentsOf: url), data.count > 48 else { return nil }
        var err2: Unmanaged<CFError>?
        let ok2 = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err2)
        if ok2 {
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
            return url
        }
        print("[PhotonFont] woff conversion failed")
        return nil
    }

    static func fourCC(_ tag: Int) -> String {
        let b0 = Character(UnicodeScalar((tag >> 24) & 0xFF)!)
        let b1 = Character(UnicodeScalar((tag >> 16) & 0xFF)!)
        let b2 = Character(UnicodeScalar((tag >>  8) & 0xFF)!)
        let b3 = Character(UnicodeScalar( tag        & 0xFF)!)
        return String([b0, b1, b2, b3])
    }
}

// ================================================================
//  LayoutEngine — forces a full UI re-layout whenever the font changes
// ================================================================
final class LayoutEngine {
    static let shared = LayoutEngine()
    private init() {}

    private var observers: [(liveness: WeakBox?, block: () -> Void)] = []

    func addObserver(weakLifetime: AnyObject? = nil, _ block: @escaping () -> Void) {
        observers.append((weakLifetime.map(WeakBox.init), block))
    }

    private var notifying=false
    func notifyFontChanged(immediate:Bool=false) {
        if immediate {
            dispatchPrecondition(condition:.onQueue(.main))
            guard !notifying else {return}
            notifying=true;defer {notifying=false}
            observers.removeAll {$0.liveness?.isAlive == false}
            let callbacks=observers.map {$0.block}
            callbacks.forEach {$0()}
        } else {
            DispatchQueue.main.async { [weak self] in self?.notifyFontChanged(immediate:true) }
        }
    }
}

// ================================================================
//  Double / CGFloat helpers
// ================================================================
extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.max(lo, Swift.min(hi, self)) }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

// BEGIN station-move TextLayerColor.swift
import QuartzCore

extension CATextLayer {
    /// Assigns foregroundColor only when it differs. CATextLayer redisplays on every assignment, even an equal
    /// colour, and the broadcaster tick assigns the same colour per row. Output is identical; only the no-op redisplay is skipped.
    func setForegroundIfChanged(_ color: CGColor) {
        if let cur = foregroundColor, CFEqual(cur, color) { return }
        foregroundColor = color
    }
}
// END station-move TextLayerColor.swift

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/PhotonFont.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='bfacd0486b28217d6399a507c4d8f0273e1b70c1e0e13392801f532d3d77aeb7', 'pinned source changed: rebase and review, never bless silently'
for token in ['PhotonFont', 'capH100', 'chromeLayoutScale', 'setChromeLayoutScale', 'chromeValue', 'isInReversedFontSubdir', 'loadFromURL', 'invalidateCache', 'promotePendingMapping', 'applyAxisMapping', 'buildAutoMapping', 'clearAxisMapping']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='bfacd0486b28217d6399a507c4d8f0273e1b70c1e0e13392801f532d3d77aeb7'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-40: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-40: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
