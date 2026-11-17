# W-gdb-198y-1nstinct-09
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/IPTV.swift -> GorSources. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-09.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-09",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/IPTV.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/IPTV.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: IPTVChannel, IPTVCountry, IPTVContinent, IPTVScreen, iconFor, randomIPTVIcon, countryName, playbackCountryCode, channelInCountry, playbackTitle, ClickableTextRow, IPTVPanel",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-09.py",
    "callee": "archive/gor/Sources/gor/IPTV.swift owning station GorSources"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-09.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-09.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-09.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.353267+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/IPTV.swift",
        "block": "source1",
        "sha256": "d3c1ed6bf012926e74425437d2b62270c39f1e209f293960a4909719ebc0e0e8"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-09.py",
        "block": "fixtures1",
        "sha256": "2909ec63234afdaaacb56c12a4529b57decb21cc773f044a1c1bc3e77737cd56"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "81974d9ac3f642a6b2f6b003652790b7fe6694fb734bf81de9cd0ea52fb3bc12",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-09: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "e59cea69609b8997f49417fac9999068e53ba64ef44fa144c1239d2a08ab3d5e"
  }
}
```

```swift id=source1
// ================================================================
//  IPTV.swift - IPTV channel browser and guide
//  Owns: channel navigation, favorites, EPG and quality selection
//  Answers: I30 I32 I33 · TRAP-06
//  Contract: onPlayURL passes stream URL and the chosen channel playback label
// ================================================================
import AppKit
import Foundation

// MARK: - Models

// ================================================================
//  IPTVChannel - channel identity and stream links
// ================================================================
private struct IPTVChannel {
    let name: String
    let streamURL: String
    let alternateURLs: [String]
    let tvgID: String
    let countryCode: String
    let routeCountryCode: String
    let searchKey: String
    init(name: String, streamURL: String, alternateURLs: [String] = [], tvgID: String = "", countryCode: String = "", routeCountryCode: String = "") {
        self.name          = name
        self.streamURL     = streamURL
        self.alternateURLs = alternateURLs
        self.tvgID         = tvgID.lowercased()
        self.countryCode   = countryCode.lowercased()
        self.routeCountryCode = routeCountryCode.lowercased()
        self.searchKey     = name.lowercased()
    }
}

// ================================================================
//  IPTVCountry - IPTVCountry
// ================================================================
private struct IPTVCountry {
    let code: String
    let name: String
    let icon: String
}

// ================================================================
//  IPTVContinent - IPTVContinent
// ================================================================
private struct IPTVContinent {
    let name: String
    let icon: String
    var countries: [IPTVCountry]
}

// ================================================================
//  IPTVScreen - IPTVScreen
// ================================================================
private enum IPTVScreen {
    case allChannels
    case countryTree
    case countryChannels(code: String)
    case favorites
}

// MARK: - Static helpers

private let iptvIcons = ["","","","","","","","","","",""]

private func iconFor(_ seed: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
    return iptvIcons[Int(hash % UInt64(iptvIcons.count))]
}
private func randomIPTVIcon() -> String {
    iptvIcons.randomElement() ?? iptvIcons[0]
}

private func countryName(for code: String) -> String {
    Locale(identifier: "en_US").localizedString(forRegionCode: code.uppercased()) ?? code.uppercased()
}

private let continentDefs: [(name: String, icon: String, codes: [String])] = [
    ("Europe",       "", ["al","ad","at","by","be","ba","bg","hr","cy","cz","dk","ee","fi","fr","de","gr","hu","is","ie","it","xk","lv","lt","lu","mt","md","mc","me","nl","mk","no","pl","pt","ro","ru","sm","rs","sk","si","es","se","ch","ua","uk","gb"]),
    ("Americas",     "", ["ar","br","ca","cl","co","cr","cu","do","ec","gt","hn","jm","mx","ni","pa","pe","py","sv","tt","us","uy","ve","bo"]),
    ("Asia Pacific", "", ["am","au","az","bd","cn","fo","ge","gl","hk","id","in","jp","kp","kr","mo","my","nz","ph","pk","sg","th","tw","uz","vn"]),
    ("Middle East",  "", ["ae","iq","ir","il","jo","kw","lb","om","qa","sa","sy","tr","ye"]),
    ("Africa",       "", ["dz","ao","bj","bw","cd","cf","cg","ci","cm","cv","dj","eg","er","et","ga","gh","gm","gn","gq","ke","ly","ma","mg","ml","mr","mw","mz","na","ne","ng","rw","sn","so","ss","sd","sz","td","tg","tn","tz","ug","zm","zw"])
]

// Playback label is a property of the chosen channel, not the current browser screen.
private func playbackCountryCode(_ raw: String) -> String? {
    let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard code.count == 2, code.utf8.allSatisfy({ (97...122).contains($0) }),
          Locale.isoRegionCodes.contains(code.uppercased()) || code == "xk" || code == "uk" else { return nil }
    return code
}
private func channelInCountry(_ channel: IPTVChannel, code: String) -> IPTVChannel {
    IPTVChannel(name: channel.name, streamURL: channel.streamURL, alternateURLs: channel.alternateURLs,
                tvgID: channel.tvgID, countryCode: channel.countryCode, routeCountryCode: playbackCountryCode(code) ?? "")
}
private func playbackTitle(_ channel: IPTVChannel) -> String {
    guard let code = playbackCountryCode(channel.routeCountryCode) ?? playbackCountryCode(channel.countryCode) else { return channel.name }
    let country = countryName(for: code == "uk" ? "gb" : code)
    guard let continent = continentDefs.first(where: { $0.codes.contains(code) })?.name else {
        return country + " → " + channel.name
    }
    return continent + " → " + country + " → " + channel.name
}

// MARK: - ClickableTextRow

fileprivate protocol ClickableTextRow: NSView {
    var clickableRects: [CGRect] { get }
}

// MARK: - IPTVPanel

// ================================================================
//  IPTVPanel - channel browser
// ================================================================
final class IPTVPanel: NSView {

    var onPlayURL:   ((String, String) -> Void)?
    var onSwitchURL: ((String) -> Void)?
    var onClose:     (() -> Void)?
    
    private var currentChannel: IPTVChannel?
    private var currentAlternateIndex: Int = 0

    var isRandomMode = false
    private var randomScreen: IPTVScreen?
    /// Owns the random pick in flight. Bumped on every new pick and on stop; a late reply
    /// from an older pick is ignored (a Bool alone lets two picks run in parallel).
    private var randomGeneration = 0
    private var randomTask: URLSessionDataTask?
    private var randomRetries = 0
    private let randomRetryLimit = 12

    private let topBar     = IPTVTopBar()
    private let listScroll = IPTVRowStepScrollView()
    private let statusLayer = CATextLayer()
    private let playbackLine = IPTVMarqueeLine()
    private var programTimer: Timer?
    private var escapeMonitor: Any?
    private var chromeAlpha: CGFloat = 1
    private var listView: IPTVVirtualListView?

    private var _isVisible = true
    private var variationToken: UUID?

    private var screen: IPTVScreen = .allChannels

    private var allChannels:      [IPTVChannel] = []
    private var filteredChannels: [IPTVChannel] = []

    private var continents:   [IPTVContinent] = []
    private var expandedSet:  Set<String>     = [""]

    private var countryChannels:         [IPTVChannel] = []
    private var filteredCountryChannels: [IPTVChannel] = []

    private var favorites: [IPTVChannel] = []
    private let favKey = "iptv.favorites.v1"

    private var searchQuery: String = ""

    private var isLoadingAll     = false
    private var isLoadingCountry = false
    private var countryRequestGeneration = 0
    private var isLoadingTree    = false

    private var blackScreenTimer: DispatchWorkItem?
    private static let blackScreenDelay: TimeInterval = 8

    private let qualityLabel = CATextLayer()

    private var hlsVariants:   [PPController.HLSVariant] = []
    private var currentHLSURL: String = ""
    private var qualityOverlay: HLSQualityOverlay?

    private let epgStore = EPGStore()
    private var loadedEPGCodes: Set<String> = []

    private var epgSearchResults: [(channel: IPTVChannel, program: EPGProgram, countryCode: String)] = []

    private var epgPrefetchQueue:   [String] = []
    private var epgPrefetchActive   = 0
    private var epgIndexedCount     = 0
    private static let epgPrefetchConcurrency = 12

    private var epgRefreshWorkItem: DispatchWorkItem?

    private var epgSearchGeneration = 0

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        statusLayer.contentsScale   = NSScreen.main?.backingScaleFactor ?? 2
        statusLayer.isWrapped       = false
        statusLayer.truncationMode  = .end
        statusLayer.foregroundColor = NSColor.white.cgColor
        statusLayer.font            = PhotonFont.chromeCt()
        statusLayer.fontSize        = PhotonFont.chromeSize
        statusLayer.shadowColor     = NSColor.black.cgColor
        statusLayer.shadowRadius    = PPController.shadowRadius
        statusLayer.shadowOpacity   = PPController.shadowOpacity
        statusLayer.shadowOffset    = .zero
        layer?.addSublayer(statusLayer)

        listScroll.drawsBackground     = false
        listScroll.hasVerticalScroller = false
        listScroll.autohidesScrollers  = true
        listScroll.rowHeight           = PhotonFont.chromeLineH + 4

        addSubview(listScroll)
        addSubview(topBar)
        addSubview(playbackLine)
        programTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, let channel = self.currentChannel else { return }
            self.updateEPGStatus(for: channel)
        }


        topBar.onClose     = { [weak self] in
            (NSApp.delegate as? AppDelegate)?.restoreDefaultProfile()
            self?.onClose?()
        }
        topBar.onSearch    = { [weak self] q, epg in self?.applySearch(q, epgEnabled: epg) }
        topBar.onTreeToggle = { [weak self] in self?.toggleTree() }
        topBar.onBack      = { [weak self] in self?.goBack() }
        topBar.onHome      = { [weak self] in self?.showAllChannels() }
        topBar.onFavorites = { [weak self] in self?.showFavorites() }
        topBar.onAddFav    = { [weak self] in self?.addCurrentToFavorites() }
        topBar.onRandom    = { [weak self] in self?.pickRandomChannel() }
        topBar.onQuality   = { [weak self] in self?.toggleQualityPanel() }

        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            self?.statusLayer.font     = PhotonFont.chromeCt()
            if let l = self?.statusLayer, l.fontSize != PhotonFont.chromeSize { l.fontSize = PhotonFont.chromeSize }
            self?.playbackLine.invalidateFont()
            self?.needsLayout = true
        }

        variationToken = VariationBroadcaster.shared.addListener { [weak self] in
            guard let self, self.window != nil, self.isEffectivelyVisible else { return }
            let newFont = PhotonFont.chromeCtDriven(view: self, profile: .panel)
            PhotonFont.setIfChanged(newFont, on: self.statusLayer)
        }

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.window != nil, !self.isHidden,
                  (NSApp.delegate as? AppDelegate)?.isShowingInputPanel != true,
                  event.window === self.window else { return event }
            self.dismissQualityOverlay()
            self.topBar.clearSearchText()
            self.onClose?() // close panel only, no stream stop or forwarded mpv ESC
            return nil
        }
        loadFavorites()
        fetchAllChannels()
        fetchCountryTree()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        programTimer?.invalidate()
        if let monitor = escapeMonitor { NSEvent.removeMonitor(monitor) }
        if let t = variationToken { VariationBroadcaster.shared.removeListener(t) }
    }

    override func viewDidHide() {
        super.viewDidHide()
        topBar.resetButtonHover()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { topBar.resetButtonHover() }
    }

    // MARK: - Visibility

    func setVisible(_ visible: Bool, animated: Bool = true) {
        guard visible != _isVisible else { return }
        _isVisible = visible
        if animated {
            if visible { isHidden = false; alphaValue = 0 }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().alphaValue = visible ? 1 : 0
            }, completionHandler: {
                if !visible { self.isHidden = true }
            })
        } else {
            alphaValue = visible ? 1 : 0
            isHidden   = !visible
        }
    }

    // Global chrome fades do not close the TV panel or stop its stream.
    func setChromeAlpha(_ alpha: CGFloat, animated: Bool = false) {
        chromeAlpha = alpha
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = alpha > 0 ? 0.2 : 0.5
                self.animator().alphaValue = alpha
                self.qualityOverlay?.animator().alphaValue = alpha
            }
        } else { alphaValue = alpha; qualityOverlay?.alphaValue = alpha }
        qualityOverlay?.isHidden = alpha <= 0.01
    }

    var isIPTVVisible: Bool { _isVisible }

    // MARK: - Layout

    private var barH:    CGFloat { PhotonFont.chromeLineH + 4 }
    private var statusH: CGFloat { PhotonFont.chromeLineH }

    override func layout() {
        super.layout()
        guard bounds.width > 10 else { return }
        let w = bounds.width; let h = bounds.height
        topBar.frame = CGRect(x: 0, y: h - barH, width: w, height: barH)

        let metric = PhotonFont.chromeLineH + 4
        listScroll.rowHeight = metric
        listView?.updateRowMetric(metric)
        let lh   = PhotonFont.chromeLineH
        let pad: CGFloat = 12
        let playing = currentChannel != nil
        playbackLine.isHidden = !playing; statusLayer.isHidden = playing
        playbackLine.frame = CGRect(x: pad, y: 2, width: max(0, w-pad*2), height: lh)
        statusLayer.frame = CGRect(x: pad, y: 2, width: max(0,w-pad*2), height: lh)
        // A whole-row viewport and row-aligned offset keep both edges free of cut lines.
        let available = max(0, h - barH - statusH - 6)
        let viewport = floor(available / listScroll.rowHeight) * listScroll.rowHeight
        listScroll.frame = CGRect(x: 0, y: statusH + 4, width: w, height: viewport)
        if let overlay = qualityOverlay, let cv = window?.contentView {
            overlay.frame = overlayFrameInContentView(cv, overlay: overlay)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard chromeAlpha > 0.01 else { return nil }
        let hit = super.hitTest(point)
        if hit === self {
            return nil
        }

        guard let lv = listView, isDescendant(hit, of: listScroll) else {
            return hit
        }

        guard let panelSuperview = superview else {
            return hit
        }
        let pointInList = lv.convert(point, from: panelSuperview)
        if pointInList.y >= lv.contentHeight {
            return nil
        }

        guard let rowHit = hit else {
            return hit
        }
        if let row = rowHit as? ClickableTextRow {
            let rects = row.clickableRects
            let pointInRow = row.convert(point, from: panelSuperview)
            let result = rects.contains { $0.contains(pointInRow) }
            return result ? hit : nil
        }
        return hit
    }

    private func isDescendant(_ candidate: NSView?, of ancestor: NSView) -> Bool {
        var v = candidate
        while let cur = v {
            if cur === ancestor { return true }
            v = cur.superview
        }
        return false
    }

    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }
    override func mouseEntered(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        (NSApp.delegate as? AppDelegate)?.moveMpv(dx: event.deltaX, dy: event.deltaY)
    }
    override func mouseUp(with event: NSEvent) {
        (NSApp.delegate as? AppDelegate)?.resetMpvPositionCache()
        super.mouseUp(with: event)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, !isHidden {
            dismissQualityOverlay(); topBar.clearSearchText(); onClose?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Status

    private func setStatus(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusLayer.string = msg
            if let channel = self.currentChannel { self.updateEPGStatus(for: channel) }
        }
    }
    
    // MARK: - Cryptographically Secure Randomness

    private func secureRandomIndex(count: Int) -> Int? {
        ArchiveRandom.shared.addTiming(ProcessInfo.processInfo.systemUptime * 1000)
        return ArchiveRandom.shared.drawIndex(count: count, session: "iptv")
    }

    // MARK: - Random Channel Picker

    func pickRandomChannel() {
        isRandomMode  = true
        randomScreen  = screen
        randomGeneration += 1
        randomTask?.cancel(); randomTask = nil
        randomRetries = 0
        switch screen {
        case .allChannels:
            pickRandomFromAll()
        case .countryTree:
            pickRandomFromTree()
        default:
            pickRandomFromAll()
        }
    }

    private func pickRandomFromAll() {
        guard !allChannels.isEmpty else {
            setStatus("⚠ no channels loaded yet")
            isRandomMode = false
            return
        }
        guard let idx = secureRandomIndex(count: allChannels.count) else { setStatus("random unavailable"); stopRandomMode(); return }
        let ch  = allChannels[idx]
        playRandomChannel(ch)
    }

    private func pickRandomFromTree() {
        guard !continents.isEmpty else {
            setStatus("⚠ no country tree loaded yet")
            isRandomMode = false
            return
        }
        guard let cIdx = secureRandomIndex(count: continents.count) else { setStatus("random unavailable"); stopRandomMode(); return }
        let continent = continents[cIdx]
        guard !continent.countries.isEmpty else { retryRandomTree(); return }

        guard let coIdx = secureRandomIndex(count: continent.countries.count) else { setStatus("random unavailable"); stopRandomMode(); return }
        let country = continent.countries[coIdx]

        setStatus("∞ \(continent.name) → \(country.name)…")
        fetchRandomCountryChannel(country.code)
    }

    /// Bounded retry: every country failing must end in a status, not an endless request loop.
    private func retryRandomTree() {
        randomRetries += 1
        guard randomRetries <= randomRetryLimit else {
            setStatus("⚠ random: no working country found")
            stopRandomMode()
            return
        }
        pickRandomFromTree()
    }

    private func fetchRandomCountryChannel(_ code: String) {
        guard let url = URL(string: "https://iptv-org.github.io/iptv/countries/\(code).m3u") else {
            if isRandomMode { retryRandomTree() }
            return
        }
        let gen = randomGeneration
        let session = URLSession(configuration: .ephemeral)
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.cachePolicy     = .reloadIgnoringLocalAndRemoteCacheData

        let task = session.dataTask(with: req) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self, self.isRandomMode, self.randomGeneration == gen else { return }
                guard error == nil, let data, !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                      !text.isEmpty else {
                    self.retryRandomTree()
                    return
                }
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let channels = parseM3U(text).map { channelInCountry($0, code: code) }
                    DispatchQueue.main.async {
                        guard let self, self.isRandomMode, self.randomGeneration == gen else { return }
                        guard !channels.isEmpty else { self.retryRandomTree(); return }
                        guard let idx = self.secureRandomIndex(count: channels.count) else { self.setStatus("random unavailable"); self.stopRandomMode(); return }
                        self.playRandomChannel(channels[idx])
                    }
                }
            }
        }
        randomTask = task
        task.resume()
    }

    private func playRandomChannel(_ ch: IPTVChannel) {
        guard isRandomMode else { return }
        lastPlayedChannel      = ch
        currentChannel         = ch
        currentAlternateIndex  = 0
        setStatus("∞ \(ch.name)")
        scheduleBlackScreenWarning()
        onPlayURL?(ch.streamURL, ch.name)
        (NSApp.delegate as? AppDelegate)?.applyIPTVProfile()
        updateEPGStatus(for: ch)
    }

    func handleRandomFailure() {
        guard isRandomMode else { return }
        NSLog("[RANDOM] stream failed — picking next…")
        switch randomScreen {
        case .countryTree:
            pickRandomFromTree()
        default:
            pickRandomFromAll()
        }
    }

    private func stopRandomMode() {
        isRandomMode = false
        randomScreen = nil
        randomGeneration += 1
        randomTask?.cancel(); randomTask = nil
    }

    func tryNextAlternateURL() {
        guard let ch = currentChannel else { return }
        guard currentAlternateIndex < ch.alternateURLs.count else {
            currentAlternateIndex = 0
            setStatus("⚠ no signal — all URLs failed")
            return
        }
        let nextURL = ch.alternateURLs[currentAlternateIndex]
        currentAlternateIndex += 1
        setStatus("⚠ trying mirror \(currentAlternateIndex)/\(ch.alternateURLs.count)…")
        onPlayURL?(nextURL, ch.name)
        (NSApp.delegate as? AppDelegate)?.applyIPTVProfile()
    }

    // MARK: - Navigation

    private func toggleTree() {
        switch screen {
        case .allChannels:
            screen = .countryTree
            searchQuery = ""
            topBar.clearSearchText()
            topBar.setMode(back: true, treeActive: true, title: "Countries")
            rebuildList()
        case .countryTree:
            screen = .allChannels
            searchQuery = ""
            topBar.clearSearchText()
            topBar.setMode(back: false, treeActive: false, title: "gor tv")
            rebuildList()
            if allChannels.isEmpty && !isLoadingAll { fetchAllChannels() }
        case .countryChannels:
            screen = .countryTree
            searchQuery = ""
            countryChannels = []
            filteredCountryChannels = []
            topBar.clearSearchText()
            topBar.setMode(back: true, treeActive: true, title: "Countries")
            rebuildList()
        case .favorites:
            screen = .countryTree
            searchQuery = ""
            topBar.clearSearchText()
            topBar.setMode(back: true, treeActive: true, title: "Countries")
            rebuildList()
        }
    }

    private func goBack() {
        switch screen {
        case .countryChannels:
            screen = .countryTree
            searchQuery = ""
            countryChannels = []
            filteredCountryChannels = []
            topBar.clearSearchText()
            topBar.setMode(back: true, treeActive: true, title: "Countries")
            setStatus("select a country")
            rebuildList()
        case .countryTree:
            screen = .allChannels
            searchQuery = ""
            topBar.clearSearchText()
            topBar.setMode(back: false, treeActive: false, title: "gor tv")
            let n = allChannels.count
            setStatus(n > 0 ? "\(n) channels" : isLoadingAll ? "loading…" : "")
            rebuildList()
        case .favorites:
            screen = .allChannels
            searchQuery = ""
            topBar.clearSearchText()
            topBar.setMode(back: false, treeActive: false, title: "gor tv")
            let n = allChannels.count
            setStatus(n > 0 ? "\(n) channels" : isLoadingAll ? "loading…" : "")
            rebuildList()
        default:
            break
        }
    }

    // MARK: - Favorites Navigation

    private func showAllChannels() {
        screen = .allChannels
        searchQuery = ""
        topBar.clearSearchText()
        topBar.setMode(back: false, treeActive: false, title: "gor tv")
        let n = allChannels.count
        setStatus(n > 0 ? "\(n) channels" : isLoadingAll ? "loading…" : "")
        rebuildList()
        if allChannels.isEmpty && !isLoadingAll { fetchAllChannels() }
    }

    private func showFavorites() {
        screen = .favorites
        searchQuery = ""
        topBar.clearSearchText()
        topBar.setMode(back: false, treeActive: false, title: "Favorites")
        let n = favorites.count
        setStatus(n == 0 ? "no favorites yet" : "\(n) favorite\(n == 1 ? "" : "s")")
        rebuildList()
    }

    private var lastPlayedChannel: IPTVChannel?

    private func addCurrentToFavorites() {
        guard let ch = lastPlayedChannel else {
            setStatus("play a channel first")
            return
        }
        if favorites.contains(where: { $0.streamURL == ch.streamURL }) {
            setStatus("already in favorites")
            return
        }
        favorites.append(ch)
        saveFavorites()
        setStatus("♥ added: \(ch.name)")
    }

    func removeFavorite(url: String) {
        favorites.removeAll { $0.streamURL == url }
        saveFavorites()
        if case .favorites = screen {
            let n = favorites.count
            setStatus(n == 0 ? "no favorites yet" : "\(n) favorite\(n == 1 ? "" : "s")")
            rebuildList()
        }
    }

    // MARK: - Favorites Persistence

    private func loadFavorites() {
        guard let arr = UserDefaults.standard.array(forKey: favKey) as? [[String: String]] else { return }
        favorites = arr.compactMap { d -> IPTVChannel? in
            guard let name = d["name"], let url = d["url"] else { return nil }
            var seen = Set<String>([url])
            let mirrors = (d["alts"] ?? "")
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            return IPTVChannel(name: name, streamURL: url, alternateURLs: mirrors,
                               tvgID: d["tvgID"] ?? "", countryCode: d["country"] ?? "", routeCountryCode: d["routeCountry"] ?? "")
        }
    }

    private func saveFavorites() {
        let arr = favorites.map { [
            "name":    $0.name,
            "url":     $0.streamURL,
            "tvgID":   $0.tvgID,
            "country": $0.countryCode,
            "routeCountry": $0.routeCountryCode,
            // Mirrors as ONE newline-joined string: the [[String: String]] cast in
            // loadFavorites must keep holding, and old builds ignore the extra key.
            "alts":    $0.alternateURLs.joined(separator: "\n")
        ] }
        UserDefaults.standard.set(arr, forKey: favKey)
    }

    // MARK: - HLS Quality

    private var qualitySelectedLabel: String = ""

    var qualityLabelLayer: CATextLayer { qualityLabel }

    func clearQualityVariants() {
        dismissQualityOverlay()
        hlsVariants   = []
        currentHLSURL = ""
        DispatchQueue.main.async { [weak self] in
            self?.topBar.setQualityVisible(false)
        }
    }

    func showQualityVariants(_ variants: [PPController.HLSVariant], currentURL: String) {
        dismissQualityOverlay()
        hlsVariants   = variants
        currentHLSURL = currentURL
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasVariants = !variants.isEmpty
            if hasVariants {
                let selected = variants.first { $0.url == currentURL } ?? variants[0]
                self.qualitySelectedLabel = selected.label
            }
            self.topBar.setQualityVisible(hasVariants)
        }
    }

    private func updateQualityLabelHover(_ inside: Bool) {
        topBar.setQualityHover(inside, label: qualitySelectedLabel)
    }
    
    private func toggleQualityPanel() {
        if let overlay = qualityOverlay {
            overlay.removeFromSuperview()
            qualityOverlay = nil
            return
        }
        guard !hlsVariants.isEmpty, let contentView = window?.contentView else { return }

        let variants      = hlsVariants
        let snapshotURL   = currentHLSURL

        let overlay = HLSQualityOverlay(variants: variants, selectedURL: snapshotURL)
        overlay.onSelect = { [weak self] url in
            guard let self else { return }
            guard url != snapshotURL else { self.dismissQualityOverlay(); return }
            guard self.currentHLSURL == snapshotURL else {
                NSLog("[HLS-QUALITY] Channel changed, selection canceled: snapshot=%@ current=%@", snapshotURL, self.currentHLSURL)
                self.dismissQualityOverlay()
                return
            }
            self.currentHLSURL = url
            self.dismissQualityOverlay()
            if let selected = variants.first(where: { $0.url == url }) {
                self.qualitySelectedLabel = selected.label
                self.topBar.setQualityHover(false, label: selected.label)
            }
            self.onSwitchURL?(url)
            NSLog("[HLS-QUALITY] Selected: %@", url)
        }
        overlay.onDismiss = { [weak self] in self?.dismissQualityOverlay() }

        overlay.frame = self.overlayFrameInContentView(contentView, overlay: overlay)
        contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        qualityOverlay = overlay
        overlay.alphaValue = chromeAlpha; overlay.isHidden = chromeAlpha <= 0.01
    }

    private func dismissQualityOverlay() {
        qualityOverlay?.removeMonitor()
        qualityOverlay?.removeFromSuperview()
        qualityOverlay = nil
    }

    private func overlayFrameInContentView(_ cv: NSView, overlay: HLSQualityOverlay) -> CGRect {
        let ow = overlay.preferredWidth
        let oh = overlay.preferredHeight
        let topBarBottomInPanel = CGPoint(x: bounds.width, y: bounds.height - barH)
        let topBarBottomInCV    = convert(topBarBottomInPanel, to: cv)
        return CGRect(x: topBarBottomInCV.x - ow, y: topBarBottomInCV.y - oh, width: ow, height: oh)
    }

    // MARK: - Black Screen Warning

    private func scheduleBlackScreenWarning() {
        blackScreenTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.setStatus("⚠ no signal — try another channel")
        }
        blackScreenTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + IPTVPanel.blackScreenDelay, execute: item)
    }

    func cancelBlackScreenWarning() {
        blackScreenTimer?.cancel()
        blackScreenTimer = nil
    }

    // MARK: - EPG Status

    private func updateEPGStatus(for channel: IPTVChannel) {
        guard let current = currentChannel, current.streamURL == channel.streamURL,
              current.tvgID == channel.tvgID, current.routeCountryCode == channel.routeCountryCode,
              current.name == channel.name else { return }
        let label = playbackTitle(channel).replacingOccurrences(of: " → ", with: " · ")
        topBar.setNowPlaying(channel.name)
        needsLayout = true
        let code = playbackCountryCode(channel.routeCountryCode) ?? playbackCountryCode(channel.countryCode) ?? ""
        guard !code.isEmpty else { playbackLine.setText(label); return }
        func render() {
            guard let current = self.currentChannel, current.streamURL == channel.streamURL,
                  current.tvgID == channel.tvgID, current.routeCountryCode == channel.routeCountryCode,
                  current.name == channel.name else { return }
            let program = self.epgStore.currentProgram(for: channel, countryCode: code)
            self.playbackLine.setText(label + (program.map { " · " + $0.title + " · " + $0.timeRange } ?? ""))
        }
        render()
        // Store owns six-hour success/failure cache and in-flight coalescing, not 30s network polling.
        epgStore.fetch(countryCode: code) { _ in render() }
    }

    private func resolveCountryCode(for channel: IPTVChannel) -> String {
        if !channel.countryCode.isEmpty { return channel.countryCode }

        let tid = channel.tvgID
        if let atRange = tid.range(of: "@") {
            let before = String(tid[tid.startIndex..<atRange.lowerBound])
            let parts  = before.split(separator: ".")
            if let last = parts.last, last.count == 2 {
                return String(last)
            }
        }
        let parts = tid.split(separator: ".")
        if let last = parts.last, last.count == 2 {
            return String(last)
        }
        return ""
    }

    private func selectCountry(_ code: String) {
        screen = .countryChannels(code: code)
        countryChannels = []
        filteredCountryChannels = []
        searchQuery = ""
        topBar.clearSearchText()
        topBar.setMode(back: true, treeActive: true, title: countryName(for: code))
        rebuildList()
        setStatus("loading \(countryName(for: code))…")
        fetchCountryChannels(code: code)

        if !loadedEPGCodes.contains(code) {
            loadedEPGCodes.insert(code)
            epgStore.fetch(countryCode: code) { [weak self] _ in
                guard let self, let ch = self.lastPlayedChannel else { return }
                self.updateEPGStatus(for: ch)
            }
        }
    }

    private func toggleContinent(_ name: String) {
        if expandedSet.contains(name) { expandedSet.remove(name) }
        else { expandedSet.insert(name) }
        rebuildList()
    }

    // MARK: - Search

    private func applySearch(_ q: String, epgEnabled: Bool = false) {
        searchQuery = q

        epgRefreshWorkItem?.cancel()
        epgRefreshWorkItem = nil
        epgSearchGeneration += 1
        epgSearchResults = []

        if !q.isEmpty && epgEnabled {
            scheduleEPGPrefetchIfNeeded()
            refreshEPGResults()
        }

        switch screen {
        case .allChannels:
            filteredChannels = filter(allChannels, q)
            let n = filteredChannels.count
            if q.isEmpty {
                setStatus("\(allChannels.count) channels")
            } else if epgEnabled {
                let queueN = epgPrefetchQueue.count + epgPrefetchActive
                setStatus(queueN > 0
                    ? "\(n) channel\(n == 1 ? "" : "s") — indexing EPG…"
                    : "\(n) channel\(n == 1 ? "" : "s")")
            } else {
                setStatus("\(n) channel\(n == 1 ? "" : "s")")
            }
        case .countryTree:
            if !q.isEmpty {
                let n = filter(allChannels, q).count
                if epgEnabled {
                    let queueN = epgPrefetchQueue.count + epgPrefetchActive
                    setStatus(queueN > 0
                        ? (n > 0 ? "\(n) channel\(n == 1 ? "" : "s") — indexing EPG…" : "indexing EPG…")
                        : (n > 0 ? "\(n) channel\(n == 1 ? "" : "s")" : "searching…"))
                } else {
                    setStatus(n > 0 ? "\(n) channel\(n == 1 ? "" : "s")" : "searching…")
                }
            }
        case .countryChannels(let code):
            filteredCountryChannels = filter(countryChannels, q)
            let n = filteredCountryChannels.count
            if q.isEmpty {
                setStatus("\(countryChannels.count) channels — \(countryName(for: code))")
            } else {
                setStatus("\(n) result\(n == 1 ? "" : "s") for \"\(q)\"")
            }
        case .favorites:
            break
        }
        rebuildList()
    }

    // MARK: - EPG Broad Prefetch

    private func scheduleEPGPrefetchIfNeeded() {
        let allCodes = continentDefs.flatMap { $0.codes }
        let cached   = epgStore.cachedCodes
        let queued   = Set(epgPrefetchQueue)
        for code in allCodes where !loadedEPGCodes.contains(code)
                                && !cached.contains(code)
                                && !queued.contains(code) {
            epgPrefetchQueue.append(code)
        }
        drainEPGPrefetchQueue()
    }

    private func drainEPGPrefetchQueue() {
        while epgPrefetchActive < IPTVPanel.epgPrefetchConcurrency,
              !epgPrefetchQueue.isEmpty {
            let code = epgPrefetchQueue.removeFirst()
            guard !loadedEPGCodes.contains(code) else { continue }
            loadedEPGCodes.insert(code)
            epgPrefetchActive += 1
            epgStore.fetch(countryCode: code) { [weak self] result in
                guard let self else { return }
                self.epgPrefetchActive -= 1
                if !result.isEmpty { self.epgIndexedCount += 1 }
                self.drainEPGPrefetchQueue()
                if !self.searchQuery.isEmpty {
                    self.scheduleEPGRefresh()
                    if self.epgPrefetchQueue.isEmpty && self.epgPrefetchActive == 0 {
                        let total = self.epgStore.cachedCodes.count
                        self.setStatus("\(self.epgSearchResults.count) EPG hit\(self.epgSearchResults.count == 1 ? "" : "s") — \(total) countries indexed")
                    }
                }
            }
        }
    }

    private func scheduleEPGRefresh() {
        epgRefreshWorkItem?.cancel()
        let gen   = epgSearchGeneration
        let delay = (epgPrefetchActive > 0 || !epgPrefetchQueue.isEmpty) ? 3.0 : 0.4
        let item  = DispatchWorkItem { [weak self] in
            self?.runEPGSearch(generation: gen)
        }
        epgRefreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func runEPGSearch(generation: Int) {
        let q = searchQuery
        guard !q.isEmpty, generation == epgSearchGeneration else { return }

        let cacheSnapshot = epgStore.cacheSnapshot()
        let channelList   = allChannels

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let lq  = q.lowercased()
            let now = Date()

            var hits: [(channelID: String, countryCode: String, program: EPGProgram, isLive: Bool)] = []
            for (code, channels) in cacheSnapshot {
                for (chID, programs) in channels {
                    for prog in programs {
                        guard prog.title.lowercased().contains(lq) else { continue }
                        let live      = prog.start <= now && now < prog.stop
                        let soonStart = prog.start > now && prog.start <= now.addingTimeInterval(7200)
                        guard live || soonStart else { continue }
                        hits.append((channelID: chID, countryCode: code, program: prog, isLive: live))
                    }
                }
            }
            hits.sort {
                if $0.isLive != $1.isLive { return $0.isLive }
                return $0.program.start < $1.program.start
            }

            let channelMap = Dictionary(
                channelList.map { ch -> (String, IPTVChannel) in
                    let key = ch.tvgID.split(separator: "@").first.map(String.init) ?? ch.tvgID
                    return (key, ch)
                },
                uniquingKeysWith: { first, _ in first }
            )
            let results: [(channel: IPTVChannel, program: EPGProgram, countryCode: String)] = hits.compactMap { hit in
                let base = hit.channelID.split(separator: ".").dropLast().joined(separator: ".")
                let ch   = channelMap[hit.channelID]
                    ?? channelMap[base]
                    ?? channelList.first { c in
                        var tid = c.tvgID
                        if let r = tid.range(of: "@") { tid = String(tid[tid.startIndex..<r.lowerBound]) }
                        return tid == hit.channelID || tid == base
                    }
                guard let channel = ch else { return nil }
                return (channel: channel, program: hit.program, countryCode: hit.countryCode)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.epgSearchGeneration else { return }
                self.epgSearchResults = results
                let total  = self.epgStore.cachedCodes.count
                let queueN = self.epgPrefetchQueue.count + self.epgPrefetchActive

                if queueN > 0 {
                    self.setStatus("indexing \(total)/\(total + queueN)…  \(results.count) EPG hit\(results.count == 1 ? "" : "s")")
                } else {
                    self.setStatus("\(results.count) EPG hit\(results.count == 1 ? "" : "s") — \(total) countries indexed")
                }

                if let lv = self.listView {
                    lv.updateEPGSection { [weak self] lv in
                        self?.buildEPGSearchSection(lv)
                    }
                }
            }
        }
    }

    private func refreshEPGResults() {
        epgSearchGeneration += 1
        runEPGSearch(generation: epgSearchGeneration)
    }

    private func filter(_ list: [IPTVChannel], _ q: String) -> [IPTVChannel] {
        guard !q.isEmpty else { return list }
        let lq = q.lowercased()
        return list.filter { $0.searchKey.contains(lq) }
    }

    // MARK: - Network

    private func fetchAllChannels() {
        guard !isLoadingAll else { return }
        isLoadingAll = true
        setStatus("loading all channels…")
        topBar.setMode(back: false, treeActive: false, title: "gor tv")

        let session = URLSession(configuration: .ephemeral)
        var req = URLRequest(url: URL(string: "https://iptv-org.github.io/iptv/index.m3u")!)
        req.timeoutInterval = 30
        req.cachePolicy     = .reloadIgnoringLocalAndRemoteCacheData

        session.dataTask(with: req) { [weak self] data, response, error in
            let httpCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let dataLen  = data?.count ?? 0
            NSLog("[IPTV] index.m3u → HTTP %d  data=%d bytes  error=%@",
                  httpCode, dataLen, error?.localizedDescription ?? "none")
            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoadingAll = false
                if let error {
                    self.setStatus("error: \(error.localizedDescription)")
                    return
                }
                guard let data, !data.isEmpty else {
                    self.setStatus("error: empty data (HTTP \(httpCode))")
                    return
                }
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                if text.isEmpty {
                    self.setStatus("error: decode failed")
                    return
                }
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let channels = parseM3U(text)
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.allChannels = channels
                        self.filteredChannels = self.filter(channels, self.searchQuery)
                        if case .allChannels = self.screen { self.rebuildList() }
                        self.setStatus("\(channels.count) channels")
                    }
                }
            }
        }.resume()
    }

    private func fetchCountryTree() {
        guard !isLoadingTree else { return }
        isLoadingTree = true

        let session = URLSession(configuration: .ephemeral)
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/iptv-org/iptv/contents/countries")!)
        req.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        session.dataTask(with: req) { [weak self] data, _, _ in
            guard let self else { return }
            var available = Set<String>()
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in json {
                    guard let fname = item["name"] as? String, fname.hasSuffix(".m3u") else { continue }
                    available.insert(String(fname.dropLast(4)).lowercased())
                }
            }
            if available.isEmpty {
                for def in continentDefs { def.codes.forEach { available.insert($0) } }
            }
            var used = Set<String>()
            var built: [IPTVContinent] = []
            for def in continentDefs {
                let countries = def.codes
                    .filter { available.contains($0) }
                    .map { code -> IPTVCountry in
                        used.insert(code)
                        return IPTVCountry(code: code, name: countryName(for: code), icon: iconFor(code))
                    }
                    .sorted { $0.name < $1.name }
                if !countries.isEmpty {
                    built.append(IPTVContinent(name: def.name, icon: def.icon, countries: countries))
                }
            }
            let leftover = available.subtracting(used).sorted()
            if !leftover.isEmpty {
                let others = leftover.map {
                    IPTVCountry(code: $0, name: countryName(for: $0), icon: iconFor($0))
                }.sorted { $0.name < $1.name }
                built.append(IPTVContinent(name: "Other", icon: "", countries: others))
            }
            DispatchQueue.main.async {
                self.isLoadingTree = false
                self.continents    = built
                if case .countryTree = self.screen { self.rebuildList() }
            }
        }.resume()
    }

    private func fetchCountryChannels(code: String) {
        countryRequestGeneration += 1
        let generation = countryRequestGeneration
        isLoadingCountry = true

        guard let url = URL(string: "https://iptv-org.github.io/iptv/countries/\(code).m3u") else {
            setStatus("error: invalid URL"); isLoadingCountry = false; return
        }
        let session = URLSession(configuration: .ephemeral)
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.cachePolicy     = .reloadIgnoringLocalAndRemoteCacheData

        session.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.countryRequestGeneration == generation,
                      case .countryChannels(let currentCode) = self.screen,
                      currentCode == code else { return }
                self.isLoadingCountry = false
                if let error {
                    self.setStatus("error: \(error.localizedDescription)")
                    return
                }
                guard let data, !data.isEmpty else {
                    self.setStatus("error: empty data")
                    return
                }
                let text = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                if text.isEmpty {
                    self.setStatus("error: decode failed")
                    return
                }
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let channels = parseM3U(text).map { channelInCountry($0, code: code) }
                    DispatchQueue.main.async {
                        guard let self, self.countryRequestGeneration == generation,
                              case .countryChannels(let currentCode) = self.screen,
                              currentCode == code else { return }
                        self.countryChannels = channels
                        self.filteredCountryChannels = self.filter(channels, self.searchQuery)
                        if case .countryChannels = self.screen {
                            self.rebuildList()
                            self.setStatus(channels.isEmpty
                                ? "no channels"
                                : "\(channels.count) channels — \(countryName(for: code))")
                        }
                    }
                }
            }
        }.resume()
    }

    // MARK: - List Rebuild

    private func rebuildList() {
        listView?.removeFromSuperview()
        listScroll.documentView = nil
        listView = nil

        let w = listScroll.bounds.width > 10 ? listScroll.bounds.width : bounds.width
        let lv = IPTVVirtualListView(width: w)

        switch screen {
        case .allChannels:
            let list = searchQuery.isEmpty ? allChannels : filteredChannels
            if isLoadingAll && list.isEmpty {
                lv.placeholder("loading…")
            } else if list.isEmpty && epgSearchResults.isEmpty {
                lv.placeholder("no channels")
            } else {
                buildChannelRows(lv, channels: list)
            }

        case .countryTree:
            if continents.isEmpty {
                lv.placeholder(isLoadingTree ? "loading countries…" : "no countries")
            } else {
                let q = searchQuery.lowercased()
                var treeMatchCount = 0
                for continent in continents {
                    let filtered = q.isEmpty ? continent.countries
                                             : continent.countries.filter { $0.name.lowercased().contains(q) }
                    if !q.isEmpty && filtered.isEmpty { continue }
                    treeMatchCount += filtered.count

                    let expanded = expandedSet.contains(continent.name) || !q.isEmpty
                    let arrow = (expanded && q.isEmpty) ? "" : (q.isEmpty ? "" : "")
                    lv.continentRow(
                        title: arrow + "" + continent.icon + "" + continent.name
                    ) { [weak self] in
                        if q.isEmpty { self?.toggleContinent(continent.name) }
                    }

                    if expanded {
                        for country in filtered {
                            lv.countryRow(title: "" + country.icon + " " + country.name) { [weak self] in
                                self?.selectCountry(country.code)
                            }
                        }
                    }
                }

                if !q.isEmpty {
                    let channelMatches = filter(allChannels, searchQuery)
                    if channelMatches.isEmpty && treeMatchCount == 0 && epgSearchResults.isEmpty {
                        lv.placeholder("no results for \"\(searchQuery)\"")
                    } else if !channelMatches.isEmpty {
                        lv.placeholder("")
                        lv.continentRow(title: "  \(channelMatches.count) channel\(channelMatches.count == 1 ? "" : "s") matching \"\(searchQuery)\"") { }
                        buildChannelRows(lv, channels: channelMatches)
                    }
                }
            }

        case .countryChannels:
            let list = searchQuery.isEmpty ? countryChannels : filteredCountryChannels
            if isLoadingCountry && list.isEmpty {
                lv.placeholder("loading…")
            } else if list.isEmpty && epgSearchResults.isEmpty {
                lv.placeholder("no channels")
            } else {
                buildChannelRows(lv, channels: list)
            }

        case .favorites:
            if favorites.isEmpty {
                lv.placeholder("no favorites yet — press + to add after playing a channel")
            } else {
                buildFavChannelRows(lv, channels: favorites)
            }
        }

        buildEPGSearchSection(lv)

        lv.finish(scrollView: listScroll)
        listView = lv
    }

    private func buildEPGSearchSection(_ lv: IPTVVirtualListView) {
        guard !epgSearchResults.isEmpty else { return }
        let now = Date()
        for hit in epgSearchResults {
            let isLive  = hit.program.start <= now && now < hit.program.stop
            let icon    = iconFor(hit.channel.searchKey)
            let title   = icon + "  " + hit.channel.name + "   " + hit.program.timeRange
            let channel = channelInCountry(hit.channel, code: hit.countryCode)
            lv.epgRow(title: title, subtitle: hit.program.title, isLive: isLive) { [weak self] in
                guard let self else { return }
                self.stopRandomMode()
                self.lastPlayedChannel = channel
                self.scheduleBlackScreenWarning()
                self.currentChannel = channel
                self.currentAlternateIndex = 0
                self.onPlayURL?(channel.streamURL, channel.name)
                (NSApp.delegate as? AppDelegate)?.applyIPTVProfile()
                self.updateEPGStatus(for: channel)
            }
        }
    }

    private func buildChannelRows(_ lv: IPTVVirtualListView, channels: [IPTVChannel]) {
        for ch in channels {
            let icon  = iconFor(ch.searchKey)
            let title = icon + "  " + ch.name
            let channel = ch
            lv.channelRow(title: title) { [weak self] in
                guard let self else { return }
                self.stopRandomMode()
                self.lastPlayedChannel = channel
                self.scheduleBlackScreenWarning()
                self.currentChannel = channel
                self.currentAlternateIndex = 0
                self.onPlayURL?(channel.streamURL, channel.name)
                (NSApp.delegate as? AppDelegate)?.applyIPTVProfile()
                self.updateEPGStatus(for: channel)
            }
        }
    }

    private func buildFavChannelRows(_ lv: IPTVVirtualListView, channels: [IPTVChannel]) {
        for ch in channels {
            let icon  = iconFor(ch.searchKey)
            let title = icon + "  " + ch.name
            let channel = ch
            lv.favChannelRow(title: title, onPlay: { [weak self] in
                guard let self else { return }
                self.stopRandomMode()
                self.lastPlayedChannel = channel
                self.scheduleBlackScreenWarning()
                self.currentChannel = channel
                self.currentAlternateIndex = 0
                self.onPlayURL?(channel.streamURL, channel.name)
                (NSApp.delegate as? AppDelegate)?.applyIPTVProfile()
                self.updateEPGStatus(for: channel)
            }, onRemove: { [weak self] in
                self?.removeFavorite(url: channel.streamURL)
            })
        }
    }
}

// MARK: - IPTVTopBar

// ================================================================
//  IPTVTopBar - browser navigation
// ================================================================
final class IPTVTopBar: NSView {

    var onClose:      (() -> Void)?
    var onSearch:     ((String, Bool) -> Void)?
    var onTreeToggle: (() -> Void)?
    var onBack:       (() -> Void)?
    var onHome:       (() -> Void)?
    var onFavorites:  (() -> Void)?
    var onAddFav:     (() -> Void)?
    var onRandom:     (() -> Void)?
    var onQuality:    (() -> Void)?

    private let closeBtn   = MusicBtn("×", hover: "close")
    private let searchBtn  = MusicBtn("◌", hover: "search")
    private let treeBtn    = MusicBtn(randomIPTVIcon(), hover: "countries")
    private let backBtn    = MusicBtn("↰", hover: "back")
    private let homeBtn    = MusicBtn("Δ",  hover: "all")
    private let favBtn     = MusicBtn("♥",  hover: "faves")
    private let addFavBtn  = MusicBtn("+",  hover: "add")
    private let randomBtn  = MusicBtn("∞",  hover: "random")
    private let qualityBtn = MusicBtn("♦",  hover: "quality")

    private let titleLayer     = CATextLayer()
    private let nowPlayLayer   = CATextLayer()
    private var showBack = false

    private var searchPanel: NSPanel?
    private var searchField: NSTextField?
    private var epgEnabled: Bool = false
    private weak var epgToggleView: EPGToggleView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        backBtn.expandsLeftToRight = true
        homeBtn.expandsLeftToRight = true
        closeBtn.tap  = { [weak self] in self?.onClose?() }
        searchBtn.tap = { [weak self] in self?.openSearchPanel() }
        treeBtn.tap   = { [weak self] in
            self?.treeBtn.updateLabel(randomIPTVIcon())
            self?.onTreeToggle?()
        }
        backBtn.tap   = { [weak self] in self?.onBack?() }
        backBtn.isHidden = true

        homeBtn.tap    = { [weak self] in self?.onHome?() }
        favBtn.tap     = { [weak self] in self?.onFavorites?() }
        addFavBtn.tap  = { [weak self] in self?.onAddFav?() }
        randomBtn.tap  = { [weak self] in self?.onRandom?() }
        qualityBtn.tap = { [weak self] in self?.onQuality?() }
        qualityBtn.isHidden = true

        titleLayer.contentsScale   = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped       = false
        titleLayer.truncationMode  = .end
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
        titleLayer.font     = PhotonFont.chromeCt()
        if titleLayer.fontSize != PhotonFont.chromeSize { titleLayer.fontSize = PhotonFont.chromeSize }
        titleLayer.string   = "gor tv"
        titleLayer.shadowColor   = NSColor.black.cgColor
        titleLayer.shadowRadius  = PPController.shadowRadius
        titleLayer.shadowOpacity = PPController.shadowOpacity
        titleLayer.shadowOffset  = .zero
        layer?.addSublayer(titleLayer)

        nowPlayLayer.contentsScale   = NSScreen.main?.backingScaleFactor ?? 2
        nowPlayLayer.isWrapped       = false
        nowPlayLayer.truncationMode  = .end
        nowPlayLayer.foregroundColor = NSColor.white.withAlphaComponent(0.42).cgColor
        nowPlayLayer.font            = PhotonFont.chromeCt(wght: 200)
        nowPlayLayer.fontSize        = PhotonFont.chromeSize
        nowPlayLayer.shadowColor     = NSColor.black.cgColor
        nowPlayLayer.shadowRadius    = PPController.shadowRadius
        nowPlayLayer.shadowOpacity   = PPController.shadowOpacity
        nowPlayLayer.shadowOffset    = .zero
        layer?.addSublayer(nowPlayLayer)

        [backBtn, homeBtn, favBtn, addFavBtn, closeBtn, treeBtn, searchBtn, randomBtn, qualityBtn].forEach { $0.externalHover = true; addSubview($0) }

        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.titleLayer.font      = PhotonFont.chromeCt()
            self.titleLayer.fontSize  = PhotonFont.chromeSize
            self.nowPlayLayer.font    = PhotonFont.chromeCt(wght: 200)
            if self.nowPlayLayer.fontSize != PhotonFont.chromeSize { self.nowPlayLayer.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true
        }

        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self, self.window != nil else { return }
            let titleFont = PhotonFont.chromeCtDriven(view: self, profile: .panel)
            PhotonFont.setIfChanged(titleFont, on: self.titleLayer)
            PhotonFont.setIfChanged(titleFont, on: self.nowPlayLayer)
        }

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height

        let gap: CGFloat = PhotonFont.chromePad / 2

        // Leading group expands left to right from the row-title inset (IPTVRow titles sit at pad/2), equal ink gaps.
        let lead = (backBtn.isHidden ? [] : [backBtn]) + [homeBtn]
        let leadFrames = IconBarFit.leadingFrames(left: gap, height: h, gap: IconBarFit.standardGap,
            buttons: lead.map { IconBarFit.Slot(width: $0.frame.width, ink: $0.inkWidth) })
        for (btn, f) in zip(lead, leadFrames) { btn.frame = f }
        let lx = (leadFrames.last?.maxX ?? gap) + gap

        // I32: live widths; IconBarFit keeps equal gaps between glyph ink edges from each button's live string.
        let rightButtons: [MusicBtn] = [closeBtn, qualityBtn, treeBtn, randomBtn, searchBtn, addFavBtn, favBtn]
        let visibleRight = rightButtons.filter { !$0.isHidden }
        let rightFrames = IconBarFit.trailingFrames(right: bounds.width - gap, height: h, gap: IconBarFit.standardGap,
            buttons: visibleRight.map { IconBarFit.Slot(width: $0.frame.width, ink: $0.inkWidth) })
        for (btn, f) in zip(visibleRight, rightFrames) { btn.frame = f }
        let rx = rightFrames.last?.minX ?? (bounds.width - gap)

        let lineH = PhotonFont.chromeLineH
        let midY  = (h - lineH) / 2

        let titleStr  = (titleLayer.string as? String) ?? ""
        let titleFont = (titleLayer.font as! CTFont)
        let measured  = titleStr.isEmpty ? 0 : ceil((titleStr as NSString)
            .size(withAttributes: [.font: titleFont as Any]).width)
        let titleW    = min(measured + 2, rx - lx - PhotonFont.chromeSize)
        titleLayer.frame = CGRect(x: lx + PhotonFont.chromePad / 2, y: midY, width: max(0, titleW), height: lineH)

        let npX = lx + titleW + PhotonFont.chromeSize * 0.6
        nowPlayLayer.frame = CGRect(x: npX, y: midY, width: max(0, rx - npX - gap), height: lineH)
    }

    func setMode(back: Bool, treeActive: Bool, title: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.backBtn.isHidden = !back
            if !back { self.backBtn.endHover() }
            let alpha: CGFloat = treeActive ? 0.9 : 0.5
            self.treeBtn.setAlpha(alpha)
            self.titleLayer.string = title
            self.needsLayout = true
        }
    }

    func setNowPlaying(_ text: String?) {
        DispatchQueue.main.async { [weak self] in
            self?.nowPlayLayer.string = text ?? ""
        }
    }

    func setQualityVisible(_ visible: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.qualityBtn.isHidden = !visible
            if !visible { self.qualityBtn.endHover() }
            if !visible { self.qualityBtn.updateLabel("♦") }
            self.needsLayout = true
        }
    }

    func setQualityHover(_ inside: Bool, label: String) {
        let text = inside ? "♦ \(label)" : "♦"
        qualityBtn.updateLabel(text)
        needsLayout = true
    }

    func clearSearchText() {
        searchField?.stringValue = ""
        searchPanel?.close()
        searchPanel    = nil
        searchField    = nil
        epgToggleView  = nil
    }



    @objc func openSearchPanel() {
        if let existing = searchPanel, existing.isVisible {
            existing.close(); searchPanel = nil; return
        }
        guard let parentWin = window else { return }

        let appDelegate = NSApp.delegate as? AppDelegate
        let ph: CGFloat = 54
        let startFrame = SearchBarFit.initialFrame(host: parentWin, height: ph)
        let pw = startFrame.width
        let px = startFrame.minX
        let py = startFrame.minY

        let panel = GORInputPanel(
            contentRect: CGRect(x: px, y: py, width: pw, height: ph),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.title  = ""
        panel.level  = .modalPanel
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor.black
        panel.isOpaque = true
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.standardWindowButton(.closeButton)?.isHidden     = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden      = true

        let bg = NSView(frame: CGRect(x: 0, y: 0, width: pw, height: ph))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.cgColor

        let toggleW: CGFloat = 28 * 4
        let toggleX = pw - toggleW - 8
        let toggle = EPGToggleView(frame: CGRect(x: toggleX, y: 0, width: toggleW, height: ph),
                                   isOn: epgEnabled)
        toggle.onToggle = { [weak self] isOn in
            self?.epgEnabled = isOn
        }
        bg.addSubview(toggle)
        epgToggleView = toggle

        let tfX: CGFloat = 20
        let tfW = toggleX - tfX - 6
        let tf = NSTextField(frame: CGRect(x: tfX, y: 14, width: tfW, height: 28))
        tf.font             = PhotonFont.chromeNs()
        tf.textColor        = .white
        tf.backgroundColor  = .clear
        tf.drawsBackground  = false
        tf.isBordered       = false
        tf.focusRingType    = .none
        tf.isEditable       = true
        tf.isSelectable     = true
        tf.refusesFirstResponder = false
        tf.placeholderString = "search channels or countries…"
        tf.target = self; tf.action = #selector(commitSearch)

        bg.addSubview(tf)
        panel.contentView = bg
        searchField = tf; searchPanel = panel
        SearchBarFit.install(panel: panel, field: tf, anchor: .center, trailing: toggle, host: parentWin)

        appDelegate?.isShowingInputPanel = true
        appDelegate?.setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = true

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel, queue: .main
        ) { [weak parentWin] _ in
            appDelegate?.isShowingInputPanel = false
            appDelegate?.setEventTapEnabled(true)
            parentWin?.ignoresMouseEvents = false
        }

        panel.installStereoIfNeeded(parent: parentWin)
        panel.makeKeyAndOrderFront(nil)
        panel.assertKeyAndFocus(tf)
    }

    @objc private func commitSearch() {
        let q    = searchField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        let epg  = epgEnabled
        searchPanel?.close(); searchPanel = nil; searchField = nil
        onSearch?(q, epg)
    }

    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        syncButtonHover(at: convert(e.locationInWindow, from: nil))
    }

    // A stationary pointer that first enters the bar sends only mouseEntered, so handle it too.
    override func mouseEntered(with e: NSEvent) {
        syncButtonHover(at: convert(e.locationInWindow, from: nil))
    }

    override func mouseExited(with e: NSEvent) {
        syncButtonHover(at: nil)
    }

    private weak var hoverWindow: NSWindow?
    private var priorAcceptsMouseMoved = false

    // Bar-owned hover needs mouse-moved delivery and the overlay window never sets it itself.
    // Set it only while this bar is visible in a window, then restore the previous value.
    private func adoptWindow() {
        guard let w = window, !isHiddenOrHasHiddenAncestor else { return }
        if hoverWindow !== w {
            releaseWindow()
            priorAcceptsMouseMoved = w.acceptsMouseMovedEvents
            hoverWindow = w
        }
        w.acceptsMouseMovedEvents = true
    }

    private func releaseWindow() {
        if let w = hoverWindow { w.acceptsMouseMovedEvents = priorAcceptsMouseMoved }
        hoverWindow = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { releaseWindow(); resetButtonHover() } else { adoptWindow() }
    }

    override func viewDidHide() {
        super.viewDidHide()
        releaseWindow()
        resetButtonHover()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        adoptWindow()
    }

    /// Clears any retained hover (reopen must not start from a stale isHovered).
    func resetButtonHover() { syncButtonHover(at: nil) }

    // The bar is the only hover owner for its buttons (externalHover set in init), so geometry-
    // triggered button exits cannot race bar tracking. The first typewriter tick shrinks a button
    // from 32 to 30 pt (left edge moves right 2 pt), so the hit rect gets 2 pt of slack to keep a
    // pointer on that edge from ending the hover it just started. Hidden buttons and a left or
    // detached bar reset to idle. This uses the existing animation; it does not prove runtime delivery.
    private func syncButtonHover(at p: NSPoint?) {
        for btn in allButtons {
            if let p, !btn.isHidden, btn.frame.insetBy(dx: -2, dy: 0).contains(p) { btn.beginHover() } else { btn.endHover() }
        }
    }

    private var allButtons: [MusicBtn] {
        [backBtn, homeBtn, favBtn, addFavBtn, closeBtn, treeBtn, searchBtn, randomBtn, qualityBtn]
    }
}

// MARK: - EPGToggleView

// ================================================================
//  EPGToggleView - EPGToggleView
// ================================================================
private final class EPGToggleView: NSView {

    var onToggle: ((Bool) -> Void)?

    private(set) var isOn: Bool
    private let dotLayer = CATextLayer()
    private var variationToken: UUID?
    private var isHovered = false

    init(frame: NSRect, isOn: Bool) {
        self.isOn = isOn
        super.init(frame: frame)
        wantsLayer = true

        dotLayer.contentsScale  = NSScreen.main?.backingScaleFactor ?? 2
        dotLayer.isWrapped      = false
        dotLayer.alignmentMode  = .center
        dotLayer.font           = PhotonFont.chromeCt(wght: 300)
        dotLayer.fontSize       = PhotonFont.chromeSize
        dotLayer.string         = isOn ? "• epg" : "· epg"
        dotLayer.foregroundColor = currentColor()
        dotLayer.shadowColor    = NSColor.black.cgColor
        dotLayer.shadowRadius   = PPController.shadowRadius
        dotLayer.shadowOpacity  = PPController.shadowOpacity
        dotLayer.shadowOffset   = .zero
        layer?.addSublayer(dotLayer)

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self, userInfo: nil))

        variationToken = VariationBroadcaster.shared.addListener { [weak self] in
            self?.updateVariation()
        }

        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.dotLayer.font     = PhotonFont.chromeCt(wght: 300)
            if self.dotLayer.fontSize != PhotonFont.chromeSize { self.dotLayer.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        dotLayer.frame = CGRect(x: 0, y: (bounds.height - PhotonFont.chromeLineH) / 2,
                                width: bounds.width, height: PhotonFont.chromeLineH)
    }

    private func currentColor() -> CGColor {
        if isOn  { return NSColor.white.cgColor }
        return NSColor.white.withAlphaComponent(isHovered ? 0.75 : 0.5).cgColor
    }

    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        updateVariation()
    }
    override func mouseEntered(with e: NSEvent) { isHovered = true;  updateVariation() }
    override func mouseExited(with e: NSEvent)  { isHovered = false; updateVariation() }

    private func updateVariation() {
        guard let win = window else { return }
        let center = convert(NSPoint(x: bounds.midX, y: bounds.midY), to: win.contentView)
        let dy = abs(VariationBroadcaster.shared.mouseWindowPt.y - center.y)
        let dx = abs(VariationBroadcaster.shared.mouseWindowPt.x - center.x)
        let dist = sqrt(dx*dx + dy*dy)
        let p = max(0, min(1, 1.0 - dist / 120))

        let audio = CGFloat(VariationBroadcaster.shared.audioBlend(0))
        let driven = max(p, audio * 0.4)

        if isOn {
            let a = 0.70 + 0.30 * driven
            dotLayer.font           = PhotonFont.chromeCtDriven(view: self, profile: .row)
            dotLayer.foregroundColor = NSColor.white.withAlphaComponent(a).cgColor
        } else {
            let a = 0.20 + 0.50 * driven
            dotLayer.font           = PhotonFont.chromeCt(wght: 100.0 + 250.0 * driven)
            dotLayer.foregroundColor = NSColor.white.withAlphaComponent(a).cgColor
        }
    }

    override func mouseDown(with e: NSEvent) {
        dotLayer.foregroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
    }

    override func mouseUp(with e: NSEvent) {
        isOn = !isOn
        dotLayer.string = isOn ? "• epg" : "· epg"
        dotLayer.foregroundColor = currentColor()
        updateVariation()
        onToggle?(isOn)
    }

    deinit {
        if let t = variationToken { VariationBroadcaster.shared.removeListener(t) }
    }
}

// MARK: - MusicBtn alpha helper

// ================================================================
//  MusicBtn - MusicBtn
// ================================================================
extension MusicBtn {
    func setAlpha(_ a: CGFloat) {
        alphaValue = a
    }
    func updateLabel(_ label: String) {
        // MusicBtn has no setTitle:, so the old selector path always fell through to a raw
        // layer write that the hover exit then overwrote. setLabel updates the resting label.
        setLabel(label)
    }
}

// MARK: - IPTVVirtualListView

// ================================================================
//  IPTVRowData - IPTVRowData
// ================================================================
private struct IPTVRowData {
    let title:    String
    let subtitle: String?
    let isLive:   Bool
    let rowSpan:  Int
    let style:    IPTVRowStyle
    let action:   (() -> Void)?
    let onRemove: (() -> Void)?
    init(title: String, subtitle: String? = nil, isLive: Bool = false, rowSpan: Int = 1, style: IPTVRowStyle, action: (() -> Void)?, onRemove: (() -> Void)? = nil) {
        self.title = title; self.subtitle = subtitle; self.isLive = isLive; self.rowSpan = rowSpan; self.style = style; self.action = action; self.onRemove = onRemove
    }
}

// ================================================================
//  IPTVVirtualListView - virtualized channel rows
// ================================================================
final class IPTVVirtualListView: NSView {
    private var rowH: CGFloat = PhotonFont.chromeLineH + 4
    private var rows:    [IPTVRowData] = []
    private var yOffset: [CGFloat]    = []
    private var stopViewport: CGFloat = -1
    private var cachedStops: [CGFloat] = []

    // I33: favorites and channel rows share this map; keep the value type NSView.
    private var visibleRows: [Int: NSView] = [:]

    private weak var boundScroll: NSScrollView?

    private(set) var epgSectionStart: Int = -1

    private(set) var contentHeight: CGFloat = 0

    init(width: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: max(width, 100), height: 100))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func updateRowMetric(_ value: CGFloat) {
        guard value > 0, value != rowH else { return }
        rowH = value
        invalidateStops()
        var y: CGFloat = 0
        yOffset = rows.map { row in let top = y; y += rowH*CGFloat(row.rowSpan); return top }
        contentHeight = y+8
        if let scroll = boundScroll { frame.size.height = max(contentHeight,scroll.contentView.bounds.height) }
        for (_,view) in visibleRows { view.removeFromSuperview() }; visibleRows.removeAll()
        if let scroll = boundScroll { tileVisible(in:scroll.contentView.bounds) }
    }
    private func invalidateStops() { stopViewport = -1; cachedStops = [] }
    func scrollStops(viewport: CGFloat) -> [CGFloat] {
        if viewport == stopViewport { return cachedStops }
        stopViewport = viewport
        let threshold = max(0,contentHeight-8-viewport)
        // Tiny viewport may not fit the last two-line item. Keep every earlier
        // item reachable; that item remains hidden until the viewport can fit it.
        let limit = yOffset.first(where: { $0 >= threshold }) ?? yOffset.last ?? 0
        cachedStops = yOffset.filter { $0 <= limit }
        if cachedStops.isEmpty { cachedStops = [0] }
        return cachedStops
    }
    func nearestStop(to value: CGFloat, stops: [CGFloat]) -> Int {
        var low = 0, high = stops.count
        while low < high { let mid = (low+high)/2; if stops[mid] < value { low = mid+1 } else { high = mid } }
        guard low > 0 else { return 0 }; guard low < stops.count else { return stops.count-1 }
        return value-stops[low-1] <= stops[low]-value ? low-1 : low
    }

    // MARK: - Row builders
    func continentRow(title: String, action: @escaping () -> Void) {
        rows.append(IPTVRowData(title: title, style: .continent, action: action))
    }
    func countryRow(title: String, action: @escaping () -> Void) {
        rows.append(IPTVRowData(title: title, style: .country, action: action))
    }
    func channelRow(title: String, action: @escaping () -> Void) {
        rows.append(IPTVRowData(title: title, style: .channel, action: action))
    }
    func favChannelRow(title: String, onPlay: @escaping () -> Void, onRemove: @escaping () -> Void) {
        rows.append(IPTVRowData(title: title, style: .channel, action: onPlay, onRemove: onRemove))
    }
    func epgRow(title: String, subtitle: String, isLive: Bool, action: @escaping () -> Void) {
        if epgSectionStart == -1 { epgSectionStart = rows.count }
        rows.append(IPTVRowData(title: title, subtitle: subtitle, isLive: isLive, rowSpan: 2, style: .channel, action: action))
    }
    func placeholder(_ text: String) {
        rows.append(IPTVRowData(title: text, style: .placeholder, action: nil))
    }

    func finish(scrollView: NSScrollView) {
        var y: CGFloat = 0
        yOffset = rows.map { row in
            let top = y
            y += rowH * CGFloat(row.rowSpan)
            return top
        }
        let totalH = y + 8
        contentHeight = totalH
        invalidateStops()

        let savedOrigin = scrollView.contentView.bounds.origin

        frame.size.height = max(totalH, scrollView.bounds.height + 1)
        scrollView.documentView = self

        let stops = scrollStops(viewport: scrollView.contentView.bounds.height)
        let restoredY = stops[nearestStop(to: savedOrigin.y, stops: stops)]
        frame.size.height = max(frame.height,(stops.last ?? 0)+scrollView.contentView.bounds.height)
        scrollView.contentView.setBoundsOrigin(CGPoint(x: 0, y: restoredY))

        boundScroll = scrollView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView)

        tileVisible(in: scrollView.contentView.bounds)
    }

    @objc private func scrolled(_ n: Notification) {
        guard let cv = boundScroll?.contentView else { return }
        tileVisible(in: cv.bounds)
    }

    func updateEPGSection(newRows builder: (IPTVVirtualListView) -> Void) {
        guard let sv = boundScroll else { return }

        let cutFrom = (epgSectionStart >= 0) ? epgSectionStart : rows.count
        for idx in cutFrom..<rows.count {
            if let v = visibleRows.removeValue(forKey: idx) { v.removeFromSuperview() }
        }
        rows.removeSubrange(cutFrom...)
        epgSectionStart = -1

        builder(self)

        let baseY = cutFrom > 0 ? (yOffset[cutFrom - 1] + rowH * CGFloat(rows[cutFrom - 1].rowSpan)) : 0
        var y = baseY
        let newOffsets = rows[cutFrom...].map { row -> CGFloat in
            let top = y; y += rowH * CGFloat(row.rowSpan); return top
        }
        yOffset.replaceSubrange(cutFrom..., with: newOffsets)

        let totalH = y + 8
        contentHeight = totalH
        invalidateStops()
        let stops = scrollStops(viewport: sv.contentView.bounds.height)
        let newH = max(totalH,(stops.last ?? 0)+sv.contentView.bounds.height)
        if abs(frame.height - newH) > 0.5 {
            frame.size.height = newH
        }

        let cv = sv.contentView
        let origin = stops[nearestStop(to: cv.bounds.origin.y, stops: stops)]
        cv.setBoundsOrigin(NSPoint(x:0,y:origin))
        tileVisible(in: cv.bounds)
    }

    private func tileVisible(in visibleRect: CGRect) {
        guard !rows.isEmpty, rows.count == yOffset.count else { return }
        let w = bounds.width

        let minY = visibleRect.minY - rowH * 2
        let maxY = visibleRect.maxY + rowH * 2
        var needed = Set<Int>()
        var lo = 0, hi = rows.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            let bottom = yOffset[mid] + rowH * CGFloat(rows[mid].rowSpan)
            if bottom < minY { lo = mid + 1 } else { hi = mid }
        }
        var idx = lo
        while idx < rows.count && yOffset[idx] <= maxY { needed.insert(idx); idx += 1 }

        for (idx, view) in visibleRows where !needed.contains(idx) {
            view.removeFromSuperview()
            visibleRows.removeValue(forKey: idx)
        }

        for idx in needed where visibleRows[idx] == nil {
            let data = rows[idx]
            let y    = yOffset[idx]
            let h    = rowH * CGFloat(data.rowSpan)
            if let onRemove = data.onRemove {
                let row = IPTVFavRow(frame: CGRect(x: 0, y: y, width: w, height: h),
                                     title: data.title)
                row.onPlay   = data.action
                row.onRemove = onRemove
                addSubview(row)
                visibleRows[idx] = row
            } else if let subtitle = data.subtitle {
                let row = IPTVEPGRow(frame: CGRect(x: 0, y: y, width: w, height: h),
                                     title: data.title, subtitle: subtitle, isLive: data.isLive)
                row.action = data.action
                addSubview(row)
                visibleRows[idx] = row
            } else {
                let row = IPTVRow(frame: CGRect(x: 0, y: y, width: w, height: h),
                                  title: data.title, style: data.style)
                row.action = data.action
                addSubview(row)
                visibleRows[idx] = row
            }
        }
        // Variable-height EPG items are visible only as a complete item. The
        // next wheel step starts at their real boundary, never their second line.
        for (_,view) in visibleRows {
            view.isHidden = view.frame.minY < visibleRect.minY-0.5 || view.frame.maxY > visibleRect.maxY+0.5
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - IPTVRow

fileprivate enum IPTVRowStyle { case continent, country, channel, placeholder }

fileprivate final class IPTVRow: NSView, ClickableTextRow {
    var action: (() -> Void)?
    private let titleLayer = CATextLayer()
    private var variationToken: UUID?
    private let style: IPTVRowStyle

    init(frame: NSRect, title: String, style: IPTVRowStyle) {
        self.style = style
        super.init(frame: frame)
        wantsLayer = true

        titleLayer.contentsScale  = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped      = false
        titleLayer.truncationMode = .end
        titleLayer.font     = baseFont(style)
        if titleLayer.fontSize != PhotonFont.chromeSize { titleLayer.fontSize = PhotonFont.chromeSize }
        titleLayer.string   = title
        titleLayer.foregroundColor = baseColor(style)
        titleLayer.shadowColor   = NSColor.black.cgColor
        titleLayer.shadowRadius  = PPController.shadowRadius
        titleLayer.shadowOpacity = PPController.shadowOpacity
        titleLayer.shadowOffset  = .zero
        layer?.addSublayer(titleLayer)

        if style != .placeholder {
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                owner: self, userInfo: nil))

            variationToken = VariationBroadcaster.shared.addListener { [weak self] in
                self?.updateVariation()
            }
        }

        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.titleLayer.font     = self.baseFont(self.style)
            if self.titleLayer.fontSize != PhotonFont.chromeSize { self.titleLayer.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func baseFont(_ s: IPTVRowStyle) -> CTFont {
        switch s {
        case .continent:   return PhotonFont.chromeCt(wght: 500)
        case .country:     return PhotonFont.chromeCt(wght: 400)
        case .channel:     return PhotonFont.chromeCt(wght: 400)
        case .placeholder: return PhotonFont.chromeCt(wght: 400)
        }
    }

    private func baseColor(_ s: IPTVRowStyle) -> CGColor {
        switch s {
        case .continent:   return NSColor.white.withAlphaComponent(0.60).cgColor
        case .country:     return NSColor.white.withAlphaComponent(0.38).cgColor
        case .channel:     return NSColor.white.withAlphaComponent(0.28).cgColor
        case .placeholder: return NSColor.white.withAlphaComponent(0.18).cgColor
        }
    }

    private func baseAlpha(_ s: IPTVRowStyle) -> CGFloat {
        switch s {
        case .continent:   return 0.60
        case .country:     return 0.38
        case .channel:     return 0.28
        case .placeholder: return 0.18
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height; let pad: CGFloat = PhotonFont.chromePad / 2
        titleLayer.frame = CGRect(x: pad, y: (h - PhotonFont.chromeLineH) / 2,
                                  width: bounds.width - pad * 2, height: PhotonFont.chromeLineH)
    }

    var clickableRects: [CGRect] {
        guard style != .placeholder else { return [] }
        let str  = (titleLayer.string as? String) ?? ""
        guard !str.isEmpty, let font = titleLayer.font else { return [] }
        let w = ceil((str as NSString).size(withAttributes: [.font: font as Any]).width)
        let tolerance: CGFloat = PhotonFont.chromeSize * 0.6
        return [CGRect(x: titleLayer.frame.minX,
                       y: 0,
                       width: min(w + tolerance, titleLayer.frame.width),
                       height: bounds.height)]
    }

    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        updateVariation()
    }
    override func mouseEntered(with e: NSEvent) { updateVariation() }
    override func mouseExited(with e: NSEvent)  { updateVariation() }

    private func updateVariation() {
        guard isEffectivelyVisible else { return }; let p = verticalProximity(radius: 180)
        if p <= 0 {
            let wght = 100.0 + 200.0 * Double(VariationBroadcaster.shared.audioBlend(0))
            let newFont = PhotonFont.chromeCt(wght: wght, SIZE: PhotonFont.chromeSize * 0.85)
            PhotonFont.setIfChanged(newFont, on: titleLayer)
            titleLayer.setForegroundIfChanged(baseColor(style))
            return
        }
        let curv  = CGFloat(VariationBroadcaster.shared.curve(p, power: 2.0))
        let base  = baseAlpha(style)
        let alpha = base + (1.0 - base) * curv * 0.85
        let newFont = PhotonFont.chromeCtDriven(view: self, profile: .row)
        PhotonFont.setIfChanged(newFont, on: titleLayer)
        titleLayer.setForegroundIfChanged(NSColor.white.withAlphaComponent(alpha).cgColor)
    }

    private func verticalProximity(radius: CGFloat) -> CGFloat {
        guard let win = window else { return 0 }
        let center = convert(NSPoint(x: 0, y: bounds.midY), to: win.contentView)
        let dy = abs(VariationBroadcaster.shared.mouseWindowPt.y - center.y)
        return max(0, min(1, 1.0 - dy / radius))
    }

    override func mouseDown(with e: NSEvent) {
        guard style != .placeholder else { return }
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
    }
    override func mouseUp(with e: NSEvent) {
        guard style != .placeholder else { return }
        titleLayer.foregroundColor = baseColor(style)
        action?()
    }

    deinit {
        if let token = variationToken {
            VariationBroadcaster.shared.removeListener(token)
        }
    }
}

// MARK: - IPTVFavRow

fileprivate final class IPTVFavRow: NSView, ClickableTextRow {
    var onPlay:   (() -> Void)?
    var onRemove: (() -> Void)?

    private let titleLayer  = CATextLayer()
    private let removeLayer = CATextLayer()
    private var variationToken: UUID?
    private let removeW: CGFloat = 24

    init(frame: NSRect, title: String) {
        super.init(frame: frame)
        wantsLayer = true

        titleLayer.contentsScale  = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped      = false
        titleLayer.truncationMode = .end
        titleLayer.font           = PhotonFont.chromeCt(wght: 200)
        titleLayer.fontSize       = PhotonFont.chromeSize
        titleLayer.string         = title
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
        titleLayer.shadowColor    = NSColor.black.cgColor
        titleLayer.shadowRadius   = PPController.shadowRadius
        titleLayer.shadowOpacity  = PPController.shadowOpacity
        titleLayer.shadowOffset   = .zero
        layer?.addSublayer(titleLayer)

        removeLayer.contentsScale  = NSScreen.main?.backingScaleFactor ?? 2
        removeLayer.isWrapped      = false
        removeLayer.alignmentMode  = .center
        removeLayer.font           = PhotonFont.chromeCt(wght: 200)
        removeLayer.fontSize       = PhotonFont.chromeSize
        removeLayer.string         = "×"
        removeLayer.foregroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        removeLayer.shadowColor    = NSColor.black.cgColor
        removeLayer.shadowRadius   = PPController.shadowRadius
        removeLayer.shadowOpacity  = PPController.shadowOpacity
        removeLayer.shadowOffset   = .zero
        layer?.addSublayer(removeLayer)

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self, userInfo: nil))

        variationToken = VariationBroadcaster.shared.addListener { [weak self] in
            self?.updateVariation()
        }

        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.titleLayer.font  = PhotonFont.chromeCt(wght: 200)
            self.removeLayer.font = PhotonFont.chromeCt(wght: 200)
            self.titleLayer.fontSize  = PhotonFont.chromeSize
            if self.removeLayer.fontSize != PhotonFont.chromeSize { self.removeLayer.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height; let pad: CGFloat = PhotonFont.chromePad / 2
        let rw = removeW
        titleLayer.frame  = CGRect(x: pad, y: (h - PhotonFont.chromeLineH) / 2,
                                   width: bounds.width - pad - rw - 4, height: PhotonFont.chromeLineH)
        removeLayer.frame = CGRect(x: bounds.width - rw - 4, y: (h - PhotonFont.chromeLineH) / 2,
                                   width: rw, height: PhotonFont.chromeLineH)
    }

    private func removeRect() -> CGRect {
        CGRect(x: bounds.width - removeW - 4, y: 0, width: removeW + 4, height: bounds.height)
    }

    var clickableRects: [CGRect] {
        let str = (titleLayer.string as? String) ?? ""
        let rr  = removeRect()
        guard !str.isEmpty, let font = titleLayer.font else { return [rr] }
        let w = ceil((str as NSString).size(withAttributes: [.font: font as Any]).width)
        let tolerance: CGFloat = PhotonFont.chromeSize * 0.6
        let titleRect = CGRect(x: titleLayer.frame.minX,
                               y: 0,
                               width: min(w + tolerance, titleLayer.frame.width),
                               height: bounds.height)
        return [titleRect, rr]
    }

    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        updateVariation()
    }
    override func mouseEntered(with e: NSEvent) { updateVariation() }
    override func mouseExited(with e: NSEvent)  { updateVariation() }

    private func updateVariation() {
        let mouseLocal = convert(VariationBroadcaster.shared.mouseWindowPt, from: window?.contentView)
        let inRemove = removeRect().contains(mouseLocal)
        if inRemove {
            removeLayer.setForegroundIfChanged(NSColor.white.withAlphaComponent(0.7).cgColor)
            titleLayer.setForegroundIfChanged(NSColor.white.withAlphaComponent(0.28).cgColor)
        } else {
            removeLayer.setForegroundIfChanged(NSColor.white.withAlphaComponent(0.18).cgColor)
            let center = convert(NSPoint(x: 0, y: bounds.midY), to: window?.contentView)
            let dy = abs(VariationBroadcaster.shared.mouseWindowPt.y - center.y)
            let p  = max(0, min(1, 1.0 - dy / 180))
            let a  = 0.28 + (1.0 - 0.28) * p * 0.85
            titleLayer.setForegroundIfChanged(NSColor.white.withAlphaComponent(a).cgColor)
        }
    }

    override func mouseDown(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        if removeRect().contains(pt) {
            removeLayer.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        } else {
            titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        }
    }

    override func mouseUp(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        titleLayer.foregroundColor  = NSColor.white.withAlphaComponent(0.28).cgColor
        removeLayer.foregroundColor = NSColor.white.withAlphaComponent(0.18).cgColor
        if removeRect().contains(pt) {
            onRemove?()
        } else {
            onPlay?()
        }
    }

    deinit {
        if let token = variationToken {
            VariationBroadcaster.shared.removeListener(token)
        }
    }
}

// MARK: - IPTVEPGRow

fileprivate final class IPTVEPGRow: NSView, ClickableTextRow {
    var action: (() -> Void)?

    private let bulletLayer   = CATextLayer()
    private let titleLayer    = CATextLayer()
    private let subtitleLayer = CATextLayer()
    private var variationToken: UUID?
    private let isLive: Bool

    private let bulletW:   CGFloat = 16
    private let bulletGap: CGFloat = PhotonFont.chromeSize * 0.6

    init(frame: NSRect, title: String, subtitle: String, isLive: Bool) {
        self.isLive = isLive
        super.init(frame: frame)
        wantsLayer = true

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let crimson = NSColor.systemRed.withAlphaComponent(0.80).cgColor
        let dimWhite = NSColor.white.withAlphaComponent(0.18).cgColor

        bulletLayer.contentsScale  = scale
        bulletLayer.isWrapped      = false
        bulletLayer.font           = PhotonFont.chromeCt(wght: 300)
        bulletLayer.fontSize       = PhotonFont.chromeSize
        bulletLayer.string         = isLive ? "•" : "·"
        bulletLayer.foregroundColor = isLive ? crimson : dimWhite
        bulletLayer.shadowColor    = NSColor.black.cgColor
        bulletLayer.shadowRadius   = PPController.shadowRadius
        bulletLayer.shadowOpacity  = PPController.shadowOpacity
        bulletLayer.shadowOffset   = .zero
        layer?.addSublayer(bulletLayer)

        titleLayer.contentsScale  = scale
        titleLayer.isWrapped      = false
        titleLayer.truncationMode = .end
        titleLayer.font           = PhotonFont.chromeCt(wght: 250)
        titleLayer.fontSize       = PhotonFont.chromeSize
        titleLayer.string         = title
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.34).cgColor
        titleLayer.shadowColor    = NSColor.black.cgColor
        titleLayer.shadowRadius   = PPController.shadowRadius
        titleLayer.shadowOpacity  = PPController.shadowOpacity
        titleLayer.shadowOffset   = .zero
        layer?.addSublayer(titleLayer)

        subtitleLayer.contentsScale  = scale
        subtitleLayer.isWrapped      = false
        subtitleLayer.truncationMode = .end
        subtitleLayer.font           = PhotonFont.chromeCt(wght: 200)
        subtitleLayer.fontSize       = PhotonFont.chromeSize
        subtitleLayer.string         = subtitle
        subtitleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.20).cgColor
        subtitleLayer.shadowColor    = NSColor.black.cgColor
        subtitleLayer.shadowRadius   = PPController.shadowRadius
        subtitleLayer.shadowOpacity  = PPController.shadowOpacity
        subtitleLayer.shadowOffset   = .zero
        layer?.addSublayer(subtitleLayer)

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self, userInfo: nil))

        variationToken = VariationBroadcaster.shared.addListener { [weak self] in
            self?.updateVariation()
        }

        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.bulletLayer.font    = PhotonFont.chromeCt(wght: 300)
            if self.bulletLayer.fontSize != PhotonFont.chromeSize { self.bulletLayer.fontSize = PhotonFont.chromeSize }
            self.titleLayer.font     = PhotonFont.chromeCt(wght: 250)
            if self.titleLayer.fontSize != PhotonFont.chromeSize { self.titleLayer.fontSize = PhotonFont.chromeSize }
            self.subtitleLayer.font  = PhotonFont.chromeCt(wght: 200)
            if self.subtitleLayer.fontSize != PhotonFont.chromeSize { self.subtitleLayer.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h   = bounds.height
        let pad: CGFloat = 12
        let lh  = PhotonFont.chromeLineH
        let half = h / 2

        bulletLayer.frame = CGRect(x: pad, y: half - lh / 2,
                                   width: bulletW, height: lh)

        let textX = pad + bulletW + bulletGap
        let textW = bounds.width - textX - pad
        let gap: CGFloat = 3
        titleLayer.frame = CGRect(x: textX, y: half - lh - gap / 2,
                                  width: textW, height: lh)

        subtitleLayer.frame = CGRect(x: textX, y: half + gap / 2,
                                     width: textW, height: lh)
    }

    var clickableRects: [CGRect] {
        let tolerance: CGFloat = PhotonFont.chromeSize * 0.6
        func measuredRect(_ layer: CATextLayer) -> CGRect? {
            let str = (layer.string as? String) ?? ""
            guard !str.isEmpty, let font = layer.font else { return nil }
            let w = ceil((str as NSString).size(withAttributes: [.font: font as Any]).width)
            return CGRect(x: layer.frame.minX, y: layer.frame.minY,
                          width: min(w + tolerance, layer.frame.width),
                          height: layer.frame.height)
        }
        return [measuredRect(titleLayer), measuredRect(subtitleLayer)].compactMap { $0 }
    }

    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        updateVariation()
    }
    override func mouseEntered(with e: NSEvent) { updateVariation() }
    override func mouseExited(with e: NSEvent)  { updateVariation() }

    private func updateVariation() {
        guard let win = window else { return }
        let center = convert(NSPoint(x: 0, y: bounds.midY), to: win.contentView)
        let dy = abs(VariationBroadcaster.shared.mouseWindowPt.y - center.y)
        let p  = max(0, min(1, 1.0 - dy / 180))
        let audioBlend = CGFloat(VariationBroadcaster.shared.audioBlend(0))
        let driven     = max(p, audioBlend * 0.5)
        let a  = CGFloat(0.34 + (1.0 - 0.34) * driven * 0.80)
        let newFont = PhotonFont.chromeCtDriven(view: self, profile: .row)
        PhotonFont.setIfChanged(newFont, on: titleLayer)
        titleLayer.setForegroundIfChanged(NSColor.white.withAlphaComponent(a).cgColor)
        subtitleLayer.setForegroundIfChanged(NSColor.white.withAlphaComponent(a * 0.65).cgColor)
        if isLive {
            let crimsonA = 0.55 + 0.45 * driven
            bulletLayer.foregroundColor = NSColor.systemRed.withAlphaComponent(crimsonA).cgColor
        } else {
            bulletLayer.foregroundColor = NSColor.white.withAlphaComponent(a * 0.55).cgColor
        }
    }

    override func mouseDown(with e: NSEvent) {
        titleLayer.foregroundColor    = NSColor.white.withAlphaComponent(0.90).cgColor
        subtitleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.60).cgColor
    }
    override func mouseUp(with e: NSEvent) {
        titleLayer.foregroundColor    = NSColor.white.withAlphaComponent(0.34).cgColor
        subtitleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.20).cgColor
        action?()
    }

    deinit {
        if let token = variationToken {
            VariationBroadcaster.shared.removeListener(token)
        }
    }
}


// Immediate whole-row movement, not repeated 120ms animations from stale current origins.
private final class IPTVRowStepScrollView: RowSnapScrollView {
    private var remainder: CGFloat = 0
    override func scrollWheel(with event: NSEvent) {
        // The app-wide idle monitor does not see scroll events over this
        // layer-backed list; wake the same idle path the mouse route uses.
        (NSApp.delegate as? AppDelegate)?.controller?.wakeUI()
        guard rowHeight > 0, let document = documentView as? IPTVVirtualListView else { return }
        if event.phase == .began { remainder = 0 }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * rowHeight
        remainder += delta
        let steps = Int((remainder / rowHeight).rounded(.towardZero))
        guard steps != 0 else { return }
        remainder -= CGFloat(steps)*rowHeight
        let stops = document.scrollStops(viewport: contentView.bounds.height)
        let index = document.nearestStop(to: contentView.bounds.origin.y, stops: stops)
        let next = min(max(0,index-steps),stops.count-1)
        if next == 0 || next == stops.count-1 { remainder = 0 }
        document.frame.size.height = max(document.frame.height,(stops.last ?? 0)+contentView.bounds.height)
        contentView.layer?.removeAllAnimations()
        contentView.setBoundsOrigin(NSPoint(x: 0, y: stops[next]))
        reflectScrolledClipView(contentView)
    }
    override func layout() {
        super.layout()
        guard let document = documentView as? IPTVVirtualListView else { return }
        let stops = document.scrollStops(viewport: contentView.bounds.height)
        let y = stops[document.nearestStop(to: contentView.bounds.origin.y, stops: stops)]
        document.frame.size.height = max(document.contentHeight,(stops.last ?? 0)+contentView.bounds.height)
        if y != contentView.bounds.origin.y { contentView.setBoundsOrigin(NSPoint(x:0,y:y)) }
    }
}

// Two clipped copies make long bottom-bar text loop without drawing over the list.
private final class IPTVMarqueeLine: NSView {
    private let first = CATextLayer(), second = CATextLayer()
    private var text = "", lastWidth: CGFloat = -1, lastFontSize: CGFloat = -1
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.masksToBounds = true
        for label in [first,second] {
            label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            label.foregroundColor = NSColor.white.cgColor; label.isWrapped = false
            label.truncationMode = .none; layer?.addSublayer(label)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func invalidateFont() { lastWidth = -1; needsLayout = true }
    func setText(_ value: String) {
        guard text != value else { return }; text = value; lastWidth = -1; needsLayout = true
    }
    override func layout() {
        super.layout()
        guard lastWidth != bounds.width || lastFontSize != PhotonFont.chromeSize else { return }
        lastWidth = bounds.width; lastFontSize = PhotonFont.chromeSize
        let font = PhotonFont.chromeCt()
        let width = ceil((text as NSString).size(withAttributes: [.font: PhotonFont.chromeNs()]).width)
        let overflow = width > bounds.width && bounds.width > 0, travel = width + 40
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (index,label) in [first,second].enumerated() {
            label.removeAllAnimations(); label.font = font; if label.fontSize != PhotonFont.chromeSize { label.fontSize = PhotonFont.chromeSize }; label.string = text
            label.frame = CGRect(x: index == 0 ? 0 : travel, y: 0, width: max(bounds.width,width), height: bounds.height)
            label.isHidden = index == 1 && !overflow
            if overflow {
                let animation = CABasicAnimation(keyPath: "transform.translation.x")
                animation.fromValue = 0; animation.toValue = -travel
                animation.duration = Double(travel / 28); animation.repeatCount = .infinity
                animation.timingFunction = CAMediaTimingFunction(name: .linear)
                label.add(animation, forKey: "marquee")
            }
        }
        CATransaction.commit()
    }
}

// MARK: - EPG

// ================================================================
//  EPGProgram - EPGProgram
// ================================================================
private struct EPGProgram {
    let channelID: String
    let title:     String
    let start:     Date
    let stop:      Date

    var timeRange: String {
        "\(epgTimeFormatter.string(from: start))–\(epgTimeFormatter.string(from: stop))"
    }
}

private let epgTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "HH:mm"
    return f
}()

// ================================================================
//  EPGStore - EPGStore
// ================================================================
private final class EPGStore {

    private var cache:   [String: [String: [EPGProgram]]] = [:]
    private var cacheTime: [String: Date] = [:]
    private var idIndex: [String: [String: [EPGProgram]]] = [:]
    private var nameIndex: [String: [String: [EPGProgram]]] = [:]
    private let cacheTTL: TimeInterval = 6 * 3600
    private var loading: Set<String> = []
    private var waiters: [String: [([String: [EPGProgram]]) -> Void]] = [:]
    private var failed: [String: Date] = [:]

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.timeoutIntervalForRequest     = 20
        cfg.timeoutIntervalForResource    = 30
        cfg.requestCachePolicy            = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: cfg)
    }()

    // MARK: - Public API

    func fetch(countryCode code: String, completion: @escaping ([String: [EPGProgram]]) -> Void) {
        assert(Thread.isMainThread)

        if let cached = cache[code], let stored = cacheTime[code],
           Date().timeIntervalSince(stored) < cacheTTL { completion(cached); return }
        cache.removeValue(forKey: code)
        cacheTime.removeValue(forKey: code)
        idIndex.removeValue(forKey: code)
        nameIndex.removeValue(forKey: code)
        if let failedAt = failed[code], Date().timeIntervalSince(failedAt) < cacheTTL {
            completion([:]); return
        }
        failed.removeValue(forKey: code)
        waiters[code, default: []].append(completion)
        if loading.contains(code) { return }

        loading.insert(code)
        fetchFrom(primary: code) { [weak self] programs in
            guard let self else { return }
            let callbacks = self.waiters.removeValue(forKey: code) ?? []
            callbacks.forEach { $0(programs) }
        }
    }

    private func fetchFrom(primary code: String, completion: @escaping ([String: [EPGProgram]]) -> Void) {
        let urlString = "https://iptv-epg.org/files/epg-\(code).xml"
        guard let url = URL(string: urlString) else {
            loading.remove(code); failed[code] = Date(); completion([:]); return
        }
        downloadEPG(url: url, code: code) { [weak self] data in
            guard let self else { return }
            if let data {
                self.parseAndStore(data: data, code: code, completion: completion)
            } else {
                let fallback = "https://epg.pw/xmltv/epg_\(code.uppercased()).xml"
                guard let fallURL = URL(string: fallback) else {
                    DispatchQueue.main.async {
                        self.loading.remove(code); self.failed[code] = Date(); completion([:])
                    }
                    return
                }
                NSLog("[EPG] %@ → 404/fail, trying fallback %@", urlString, fallback)
                self.downloadEPG(url: fallURL, code: code) { [weak self] data2 in
                    guard let self else { return }
                    if let data2 {
                        self.parseAndStore(data: data2, code: code, completion: completion)
                    } else {
                        DispatchQueue.main.async {
                            self.loading.remove(code); self.failed[code] = Date(); completion([:])
                        }
                    }
                }
            }
        }
    }

    private func downloadEPG(url: URL, code: String, completion: @escaping (Data?) -> Void) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("keep-alive",        forHTTPHeaderField: "Connection")

        session.dataTask(with: req) { data, response, error in
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[EPG] %@ → HTTP %d  bytes=%d  err=%@",
                  url.absoluteString, httpStatus, data?.count ?? 0,
                  error?.localizedDescription ?? "none")
            if let data, !data.isEmpty, httpStatus == 200 {
                completion(data)
            } else {
                completion(nil)
            }
        }.resume()
    }

    private func parseAndStore(data: Data, code: String, completion: @escaping ([String: [EPGProgram]]) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let parsed = EPGXMLParser().parse(data)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(code)
                if !parsed.isEmpty {
                    self.cache[code] = parsed
                    self.cacheTime[code] = Date()
                    var ids: [String: [EPGProgram]] = [:]
                    var names: [String: [EPGProgram]] = [:]
                    for (key, programs) in parsed {
                        ids[key.lowercased()] = programs
                        let normalized = epgNormalize(key)
                        if !normalized.isEmpty, names[normalized] == nil { names[normalized] = programs }
                    }
                    self.idIndex[code] = ids
                    self.nameIndex[code] = names
                }
                NSLog("[EPG] %@ parsed — %d channel entries", code, parsed.count)
                completion(parsed)
            }
        }
    }

    func currentProgram(for channel: IPTVChannel, countryCode code: String) -> EPGProgram? {
        assert(Thread.isMainThread)
        guard let data = cache[code], !data.isEmpty,
              let stored = cacheTime[code], Date().timeIntervalSince(stored) < cacheTTL else { return nil }

        let now = Date()

        if !channel.tvgID.isEmpty {
            var tid = channel.tvgID
            if let atIdx = tid.range(of: "@") { tid = String(tid[tid.startIndex..<atIdx.lowerBound]) }

            if let p = findCurrent(in: data[tid], now: now) { return p }
            if let p = findCurrent(in: idIndex[code]?[tid.lowercased()], now: now) { return p }

            let tidBase = tid.split(separator: ".").dropLast().joined(separator: ".")
            if !tidBase.isEmpty {
                if let p = findCurrent(in: data[tidBase], now: now) { return p }
                if let p = findCurrent(in: idIndex[code]?[tidBase.lowercased()], now: now) { return p }
                if let entry = data.first(where: { $0.key.lowercased().hasPrefix(tidBase) || tidBase.hasPrefix($0.key.lowercased()) }),
                   let p = findCurrent(in: entry.value, now: now) { return p }
            }
        }

        let norm = epgNormalize(channel.name)
        if norm.isEmpty { return nil }

        if let p = findCurrent(in: nameIndex[code]?[norm], now: now) { return p }

        if let entry = data.first(where: {
            let k = epgNormalize($0.key)
            return k.hasPrefix(norm) || norm.hasPrefix(k)
        }), let p = findCurrent(in: entry.value, now: now) { return p }

        return nil
    }

    private func findCurrent(in programs: [EPGProgram]?, now: Date) -> EPGProgram? {
        guard let progs = programs else { return nil }
        return progs.first { $0.start <= now && now < $0.stop }
    }

    func isLoading(countryCode code: String) -> Bool { loading.contains(code) }
    func hasFailed(countryCode code: String) -> Bool {
        guard let date = failed[code] else { return false }
        return Date().timeIntervalSince(date) < cacheTTL
    }

    // MARK: - EPG Program Search

    func searchPrograms(keyword: String) -> [(channelID: String, countryCode: String, program: EPGProgram)] {
        assert(Thread.isMainThread)
        guard !keyword.isEmpty else { return [] }
        let lq  = keyword.lowercased()
        let now = Date()
        var results: [(channelID: String, countryCode: String, program: EPGProgram, isLive: Bool)] = []

        for (code, channels) in cache {
            for (chID, programs) in channels {
                for prog in programs {
                    guard prog.title.lowercased().contains(lq) else { continue }
                    let live = prog.start <= now && now < prog.stop
                    let soonStart = prog.start <= now.addingTimeInterval(7200)
                    guard live || soonStart else { continue }
                    results.append((channelID: chID, countryCode: code, program: prog, isLive: live))
                }
            }
        }

        results.sort {
            if $0.isLive != $1.isLive { return $0.isLive }
            return $0.program.start < $1.program.start
        }
        return results.map { ($0.channelID, $0.countryCode, $0.program) }
    }

    var cachedCodes: Set<String> { Set(cache.keys) }

    func cacheSnapshot() -> [String: [String: [EPGProgram]]] { cache }

}

// MARK: - EPG Normalize

private func epgNormalize(_ s: String) -> String {
    s.lowercased()
        .replacingOccurrences(of: " hd",  with: "")
        .replacingOccurrences(of: "(hd)", with: "")
        .replacingOccurrences(of: " sd",  with: "")
        .replacingOccurrences(of: "(sd)", with: "")
        .replacingOccurrences(of: "tr - ", with: "")
        .replacingOccurrences(of: ".",    with: "")
        .replacingOccurrences(of: "-",    with: "")
        .filter { !$0.isWhitespace }
}

// MARK: - XMLTV Parser

// ================================================================
//  EPGXMLParser - EPGXMLParser
// ================================================================
private final class EPGXMLParser: NSObject, XMLParserDelegate {

    private var result:  [String: [EPGProgram]] = [:]

    private var inProgramme = false
    private var curChannel:  String = ""
    private var curStart:    Date?
    private var curStop:     Date?
    private var curTitle:    String = ""
    private var captureText  = false
    private var textBuf:     String = ""

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMddHHmmss Z"
        return f
    }()

    func parse(_ data: Data) -> [String: [EPGProgram]] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces    = false
        parser.shouldReportNamespacePrefixes = false
        parser.parse()
        for key in result.keys {
            result[key]?.sort { $0.start < $1.start }
        }
        return result
    }

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement el: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes attrs: [String: String]) {
        switch el {
        case "programme":
            inProgramme = true
            curChannel  = (attrs["channel"] ?? "").lowercased()
            curStart    = attrs["start"].flatMap { df.date(from: $0) }
            curStop     = attrs["stop"].flatMap  { df.date(from: $0) }
            curTitle    = ""
            captureText = false
            textBuf     = ""
        case "title" where inProgramme:
            captureText = true
            textBuf     = ""
        default:
            captureText = false
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard captureText else { return }
        textBuf += string
    }

    func parser(_ parser: XMLParser,
                didEndElement el: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        switch el {
        case "title" where inProgramme && captureText:
            let t = textBuf.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { curTitle = t }
            captureText = false
        case "programme":
            if inProgramme,
               !curChannel.isEmpty,
               let start = curStart, let stop = curStop {
                let prog = EPGProgram(
                    channelID: curChannel,
                    title:     curTitle.isEmpty ? "—" : curTitle,
                    start:     start,
                    stop:      stop
                )
                result[curChannel, default: []].append(prog)
            }
            inProgramme = false
            captureText = false
        default:
            captureText = false
        }
    }
}

// MARK: - QualityHitView

// ================================================================
//  QualityHitView - QualityHitView
// ================================================================
final class QualityHitView: NSView {
    var onTap:   (() -> Void)?
    var onHover: ((Bool) -> Void)?

    weak var panel: IPTVPanel?

    private var variationToken: UUID?
    private var isHovered = false
    private var mouseDownInside = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self, userInfo: nil))

        variationToken = VariationBroadcaster.shared.addListener { [weak self] in
            self?.applyVariation()
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let t = variationToken { VariationBroadcaster.shared.removeListener(t) }
    }

    // MARK: - Proximity / variation

    private func applyVariation() {
        guard window != nil, let ql = panel?.qualityLabelLayer else { return }
        
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window?.contentView)
        let dy = abs(VariationBroadcaster.shared.mouseWindowPt.y - center.y)
        let dx = abs(VariationBroadcaster.shared.mouseWindowPt.x - center.x)
        let prox = max(0, min(1, 1 - hypot(dx, dy) / 160))
        let audio = CGFloat(VariationBroadcaster.shared.audioBlend(0))
        let driven = max(prox, audio * 0.4)
        let alpha = 0.28 + 0.72 * driven
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ql.font = PhotonFont.chromeCtDriven(view: self, profile: .row)
        ql.foregroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
        CATransaction.commit()
    }

    // MARK: - Hover

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        onHover?(true)
        if let winPt = window?.contentView?.convert(event.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        onHover?(false)
        if let winPt = window?.contentView?.convert(event.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        if let winPt = window?.contentView?.convert(event.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        applyVariation()
    }

    // MARK: - Click

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        mouseDownInside = bounds.contains(pt)
    }
    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if mouseDownInside && bounds.contains(pt) {
            onTap?()
        }
        mouseDownInside = false
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { false }
}

// MARK: - HLSQualityOverlay

// ================================================================
//  HLSQualityOverlay - HLSQualityOverlay
// ================================================================
final class HLSQualityOverlay: NSView {

    var onSelect:  ((String) -> Void)?
    var onDismiss: (() -> Void)?

    private let variants:    [PPController.HLSVariant]
    private let selectedURL: String
    private var rowLayers:   [(title: CATextLayer, url: String)] = []
    private var variationToken: UUID?
    private var mouseMonitor:   Any?

    private let rowH: CGFloat = PhotonFont.chromeLineH + 4
    private let pad:  CGFloat = 12

    var preferredWidth: CGFloat {
        let maxLabel = variants.map { ($0.label as NSString)
            .size(withAttributes: [.font: PhotonFont.chromeNs()]).width }.max() ?? 80
        return ceil(maxLabel) + pad * 2 + 20
    }
    var preferredHeight: CGFloat { rowH * CGFloat(variants.count) }

    init(variants: [PPController.HLSVariant], selectedURL: String) {
        self.variants    = variants
        self.selectedURL = selectedURL
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear

        buildLayers()

        variationToken = VariationBroadcaster.shared.addListener { [weak self] in
            self?.updateVariations()
        }

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            if let hit = event.window?.contentView?.hitTest(event.locationInWindow) {
                if hit === self || hit.isDescendant(of: self) { return event }
            }
            self.onDismiss?()
            return nil
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let t = variationToken { VariationBroadcaster.shared.removeListener(t) }
        if let m = mouseMonitor   { NSEvent.removeMonitor(m) }
    }

    private func buildLayers() {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        for (i, variant) in variants.enumerated() {
            let isCurrent = (variant.url == selectedURL)

            let dotL = CATextLayer()
            dotL.contentsScale  = scale
            dotL.isWrapped      = false
            dotL.alignmentMode  = .right
            dotL.font           = PhotonFont.chromeCt(wght: 300)
            dotL.fontSize       = PhotonFont.chromeSize
            dotL.string         = isCurrent ? "•" : "·"
            dotL.foregroundColor = isCurrent
                ? NSColor.white.withAlphaComponent(0.80).cgColor
                : NSColor.white.withAlphaComponent(0.22).cgColor
            dotL.shadowColor    = NSColor.black.cgColor
            dotL.shadowRadius   = PPController.shadowRadius
            dotL.shadowOpacity  = PPController.shadowOpacity
            dotL.shadowOffset   = .zero
            layer?.addSublayer(dotL)

            let titleL = CATextLayer()
            titleL.contentsScale  = scale
            titleL.isWrapped      = false
            titleL.truncationMode = .end
            titleL.alignmentMode  = .right
            titleL.font           = PhotonFont.chromeCt(wght: isCurrent ? 350 : 200)
            titleL.fontSize       = PhotonFont.chromeSize
            titleL.string         = variant.label
            titleL.foregroundColor = isCurrent
                ? NSColor.white.withAlphaComponent(0.80).cgColor
                : NSColor.white.withAlphaComponent(0.30).cgColor
            titleL.shadowColor    = NSColor.black.cgColor
            titleL.shadowRadius   = PPController.shadowRadius
            titleL.shadowOpacity  = PPController.shadowOpacity
            titleL.shadowOffset   = .zero
            layer?.addSublayer(titleL)

            rowLayers.append((title: titleL, url: variant.url))
            _ = (i, dotL)
        }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let dotW: CGFloat = 14
        let gap:  CGFloat = 6
        let lh    = PhotonFont.chromeLineH

        for (i, variant) in variants.enumerated() {
            let isCurrent = (variant.url == selectedURL)
            let y = bounds.height - rowH * CGFloat(i + 1)
            let midY = y + (rowH - lh) / 2

            let dotX = w - pad - dotW
            let labelW = dotX - pad - gap
            let labelX = pad

            if let dotLayer = layer?.sublayers?[i * 2] as? CATextLayer {
                dotLayer.frame = CGRect(x: dotX, y: midY, width: dotW, height: lh)
                dotLayer.string = isCurrent ? "•" : "·"
            }
            if let titleLayer = layer?.sublayers?[i * 2 + 1] as? CATextLayer {
                titleLayer.frame = CGRect(x: labelX, y: midY, width: labelW, height: lh)
            }
        }
    }

    // MARK: - Row hit test

    private func rowIndex(at point: NSPoint) -> Int? {
        for i in 0..<variants.count {
            let y = bounds.height - rowH * CGFloat(i + 1)
            if point.y >= y && point.y < y + rowH { return i }
        }
        return nil
    }

    // MARK: - Mouse

    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        updateVariations()
    }
    override func mouseEntered(with e: NSEvent) { updateVariations() }
    override func mouseExited(with e: NSEvent)  { updateVariations() }

    private func updateVariations() {
        guard let win = window else { return }
        let mouseLocal = convert(win.mouseLocationOutsideOfEventStream, from: nil)

        for (i, info) in rowLayers.enumerated() {
            let isCurrent = (info.url == selectedURL)
            let y = bounds.height - rowH * CGFloat(i + 1)
            let midY = y + rowH / 2
            let center = NSPoint(x: bounds.midX, y: midY)
            let centerWin = convert(center, to: win.contentView)
            let dy = abs(VariationBroadcaster.shared.mouseWindowPt.y - centerWin.y)
            let p  = max(0, min(1, 1.0 - dy / 60))

            let baseA: CGFloat = isCurrent ? 0.80 : 0.30
            let a = baseA + (1.0 - baseA) * p * 0.75

            let newFont = PhotonFont.chromeCtDriven(view: self, profile: .row)
            PhotonFont.setIfChanged(newFont, on: info.title)
            info.title.foregroundColor = NSColor.white.withAlphaComponent(a).cgColor

            if let dotLayer = layer?.sublayers?[i * 2] as? CATextLayer {
                let dotBase: CGFloat = isCurrent ? 0.80 : 0.22
                let dotA = dotBase + (1.0 - dotBase) * p * 0.65
                dotLayer.foregroundColor = NSColor.white.withAlphaComponent(dotA).cgColor
            }

            _ = mouseLocal
        }
    }

    override func mouseDown(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        if let idx = rowIndex(at: pt) {
            rowLayers[idx].title.foregroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        }
    }

    override func mouseUp(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        if let idx = rowIndex(at: pt) {
            onSelect?(variants[idx].url)
        }
    }

    // MARK: - ESC key

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
        } else {
            super.keyDown(with: event)
        }
    }
    
    func removeMonitor() {
        if let m = mouseMonitor {
            NSEvent.removeMonitor(m)
            mouseMonitor = nil
        }
    }
}

// MARK: - IPTVQualityRow

fileprivate final class IPTVQualityRow: NSView {
    var action: (() -> Void)?

    private let titleLayer  = CATextLayer()
    private let checkLayer  = CATextLayer()
    private let isSelected: Bool
    private var variationToken: UUID?

    init(frame: NSRect, label: String, isSelected: Bool) {
        self.isSelected = isSelected
        super.init(frame: frame)
        wantsLayer = true

        let scale = NSScreen.main?.backingScaleFactor ?? 2

        checkLayer.contentsScale  = scale
        checkLayer.isWrapped      = false
        checkLayer.alignmentMode  = .center
        checkLayer.font           = PhotonFont.chromeCt(wght: 300)
        checkLayer.fontSize       = PhotonFont.chromeSize
        checkLayer.string         = isSelected ? "•" : "·"
        checkLayer.foregroundColor = isSelected
            ? NSColor.white.cgColor
            : NSColor.white.withAlphaComponent(0.28).cgColor
        checkLayer.shadowColor    = NSColor.black.cgColor
        checkLayer.shadowRadius   = PPController.shadowRadius
        checkLayer.shadowOpacity  = PPController.shadowOpacity
        checkLayer.shadowOffset   = .zero
        layer?.addSublayer(checkLayer)

        titleLayer.contentsScale  = scale
        titleLayer.isWrapped      = false
        titleLayer.truncationMode = .end
        titleLayer.font           = PhotonFont.chromeCt(wght: isSelected ? 350 : 200)
        titleLayer.fontSize       = PhotonFont.chromeSize
        titleLayer.string         = label
        titleLayer.foregroundColor = isSelected
            ? NSColor.white.withAlphaComponent(0.85).cgColor
            : NSColor.white.withAlphaComponent(0.35).cgColor
        titleLayer.shadowColor    = NSColor.black.cgColor
        titleLayer.shadowRadius   = PPController.shadowRadius
        titleLayer.shadowOpacity  = PPController.shadowOpacity
        titleLayer.shadowOffset   = .zero
        layer?.addSublayer(titleLayer)

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self, userInfo: nil))

        variationToken = VariationBroadcaster.shared.addListener { [weak self] in
            self?.updateVariation()
        }

        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.titleLayer.font     = PhotonFont.chromeCt(wght: self.isSelected ? 350 : 200)
            self.checkLayer.font     = PhotonFont.chromeCt(wght: 300)
            if self.titleLayer.fontSize != PhotonFont.chromeSize { self.titleLayer.fontSize = PhotonFont.chromeSize }
            if self.checkLayer.fontSize != PhotonFont.chromeSize { self.checkLayer.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h   = bounds.height
        let pad: CGFloat = 12
        let dotW: CGFloat = 16
        let lh  = PhotonFont.chromeLineH
        checkLayer.frame = CGRect(x: pad, y: (h - lh) / 2, width: dotW, height: lh)
        titleLayer.frame = CGRect(x: pad + dotW + 6, y: (h - lh) / 2,
                                  width: bounds.width - pad - dotW - 6 - pad, height: lh)
    }

    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        updateVariation()
    }
    override func mouseEntered(with e: NSEvent) { updateVariation() }
    override func mouseExited(with e: NSEvent)  { updateVariation() }

    private func updateVariation() {
        guard let win = window else { return }
        let center = convert(NSPoint(x: 0, y: bounds.midY), to: win.contentView)
        let dy     = abs(VariationBroadcaster.shared.mouseWindowPt.y - center.y)
        let p      = max(0, min(1, 1.0 - dy / 80))
        let base: CGFloat = isSelected ? 0.85 : 0.35
        let a = base + (1.0 - base) * p * 0.80
        let newFont = PhotonFont.chromeCtDriven(view: self, profile: .row)
        PhotonFont.setIfChanged(newFont, on: titleLayer)
        titleLayer.setForegroundIfChanged(NSColor.white.withAlphaComponent(a).cgColor)
        checkLayer.foregroundColor = isSelected
            ? NSColor.white.withAlphaComponent(0.60 + 0.40 * p).cgColor
            : NSColor.white.withAlphaComponent(0.18 + 0.50 * p).cgColor
    }

    override func mouseDown(with e: NSEvent) {
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
    }
    override func mouseUp(with e: NSEvent) {
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(isSelected ? 0.85 : 0.35).cgColor
        action?()
    }

    deinit {
        if let t = variationToken { VariationBroadcaster.shared.removeListener(t) }
    }
}

// MARK: - M3U Parser

private func countryCodeFromTvgID(_ tvgID: String) -> String {
    let tid = tvgID.lowercased()
    if let atRange = tid.range(of: "@") {
        let before = String(tid[tid.startIndex..<atRange.lowerBound])
        let parts  = before.split(separator: ".")
        if let last = parts.last, last.count == 2 { return String(last) }
    }
    let parts = tid.split(separator: ".")
    if let last = parts.last, last.count == 2 { return String(last) }
    return ""
}

private func parseM3U(_ text: String) -> [IPTVChannel] {
    var channels: [IPTVChannel] = []

    let normalized = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r",   with: "\n")
    let lines = normalized.components(separatedBy: "\n")

    let tvgNameRx    = try? NSRegularExpression(pattern: #"tvg-name="([^"]*)""#)
    let tvgIDRx      = try? NSRegularExpression(pattern: #"tvg-id="([^"]*)""#)
    let tvgCountryRx = try? NSRegularExpression(pattern: #"tvg-country="([^"]*)""#)

    func extract(_ rx: NSRegularExpression?, from line: String) -> String {
        guard let rx else { return "" }
        let range = NSRange(line.startIndex..., in: line)
        guard let m = rx.firstMatch(in: line, range: range),
              let r = Range(m.range(at: 1), in: line) else { return "" }
        return String(line[r]).trimmingCharacters(in: .whitespaces)
    }

    var i = 0
    while i < lines.count {
        let line = lines[i].trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("#EXTINF") else { i += 1; continue }

        var name        = extract(tvgNameRx,    from: line)
        let tvgID       = extract(tvgIDRx,      from: line)
        var countryCode = extract(tvgCountryRx, from: line).lowercased()

        if countryCode.isEmpty { countryCode = countryCodeFromTvgID(tvgID) }

        if name.isEmpty, let comma = line.lastIndex(of: ",") {
            name = String(line[line.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces)
        }

        var urlLine = ""
        var j = i + 1
        while j < lines.count {
            let candidate = lines[j].trimmingCharacters(in: .whitespaces)
            if candidate.isEmpty      { j += 1; continue }
            if candidate.hasPrefix("#") { break }
            urlLine = candidate
            break
        }

        if !urlLine.isEmpty,
           urlLine.hasPrefix("http") || urlLine.hasPrefix("rtsp") || urlLine.hasPrefix("rtmp"),
           !name.isEmpty {
            channels.append(IPTVChannel(name: name, streamURL: urlLine,
                                        tvgID: tvgID, countryCode: countryCode))
            i = j + 1
            continue
        }
        i += 1
    }

    var grouped: [String: (name: String, urls: [String], tvgID: String, country: String)] = [:]
    var ungrouped: [IPTVChannel] = []

    for ch in channels {
        guard !ch.tvgID.isEmpty else {
            ungrouped.append(ch)
            continue
        }
        let key: String
        if let atIdx = ch.tvgID.firstIndex(of: "@") {
            key = String(ch.tvgID[ch.tvgID.startIndex..<atIdx])
        } else {
            key = ch.tvgID
        }
        if var existing = grouped[key] {
            existing.urls.append(ch.streamURL)
            if existing.country != ch.countryCode { existing.country = "multiple" }
            grouped[key] = existing
        } else {
            grouped[key] = (name: ch.name, urls: [ch.streamURL], tvgID: ch.tvgID, country: ch.countryCode)
        }
    }

    var result = grouped.map { _, v in
        IPTVChannel(name: v.name, streamURL: v.urls[0],
                     alternateURLs: Array(v.urls.dropFirst()),
                     tvgID: v.tvgID, countryCode: v.country)
    }
    result.append(contentsOf: ungrouped)
    return result
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/IPTV.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='d3c1ed6bf012926e74425437d2b62270c39f1e209f293960a4909719ebc0e0e8', 'pinned source changed: rebase and review, never bless silently'
for token in ['IPTVChannel', 'IPTVCountry', 'IPTVContinent', 'IPTVScreen', 'iconFor', 'randomIPTVIcon', 'countryName', 'playbackCountryCode', 'channelInCountry', 'playbackTitle', 'ClickableTextRow', 'IPTVPanel']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='d3c1ed6bf012926e74425437d2b62270c39f1e209f293960a4909719ebc0e0e8'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-09: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-09: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
