# W-gdb-198y-1nstinct-27
state: OPEN / unclaimed
lab: 1nstinct

Build a new independent scope-aware source/move characterization test for this exact file. Parse lexical nominal ownership including nesting, ignore comments/strings, and compare fully qualified declaration owners across the entire pinned Sources tree. Do not confuse nested names in unrelated owners with duplicates. Preserve pinned bytes. Check old and mapped station, renamed copies, valid overload/nested-name controls, and real duplicate mutants. Use explicit failure paths that remain active under python3 -O. Run normal and optimized positive plus on-disk external negative/restore controls. The existing 01..20 returns are evidence only and may not be copied unchanged.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-27.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-27",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/FileBrowser.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-27.py checks archive/gor/Sources/gor/FileBrowser.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: FileBrowserPanel, FileEntry, toggleSearchPanelFromKey, pressRandomFromKey, renderEntries, loadPath, nextSearchGeneration, isCurrentSearch, performSearch, goUp, goHome, clearSearchAndShowFolder",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-27.py",
    "callee": "archive/gor/Sources/gor/FileBrowser.swift owning station GorUI"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-27.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-27.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-27.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:15.911329+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/FileBrowser.swift",
        "block": "source1",
        "sha256": "633b968dd7d4ecc5626b174b8a1744290e82cbd53ce28481e32d6ad18b914b67"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-27.py",
        "block": "fixtures1",
        "sha256": "38fd55448afbda1d5c0d17a5ec2a305958d1ae8738ae9f21d909739956afadea"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "94834e6205dcee9afd70dc2cd2236b51e40782c427d1e3fc76aed5df6ae712bb",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-27: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "391e188b432ab750848f00534f0cb3b4a579aa64d3ad56a150e96d467f4698df"
  }
}
```

```swift id=source1
// ================================================================
//  FileBrowser.swift - file system browser: panel, top bar, rows,
//  hover mpv preview, row-snapping scroll view
//  Owns: FileBrowserPanel, FileBrowserTopBar, FileListRow,
//  FileListView, RowSnapScrollView
//  Answers: I43
//  Contract: empty space falls through (hitTest nil), never swallows
//  clicks; preview hovers obey I43 (125ms delay, 10Hz seek cap,
//  cached aspect)
// ================================================================
import AppKit

// ================================================================
//  FileBrowserPanel - picker panel: top bar + scrollable list
// ================================================================

final class FileBrowserPanel: NSView {
    var onSelect: ((String) -> Void)?
    var onClose: (() -> Void)?
    
    private var currentPath: String = NSHomeDirectory() + "/Movies"
    private var entries: [FileEntry] = []
    private let listScroll = RowSnapScrollView()
    private var listView: FileListView?
    private let topBar = FileBrowserTopBar()
    // non-nil while showing recursive search results; goUp/goHome then
    // fall back to the plain folder view first
    private var searchQuery: String?
    
    private struct FileEntry {
        let name: String; let path: String; let isDir: Bool; let isPlayable: Bool
    }
    
    var onSelectFolder: ((String) -> Void)?
    
    // forwards to topBar so MenuActions' Esc monitor can check/close
    // the search field without touching the private topBar
    var isSearchPanelOpen: Bool { topBar.isSearchPanelOpen }
    @discardableResult func closeSearchPanelIfOpen() -> Bool { topBar.closeSearchPanelIfOpen() }
    // Source commentary elided for privacy; historical proof hashes are not rebound.
    func toggleSearchPanelFromKey() { topBar.toggleSearchPanelFromKey() }

    // Source commentary elided for privacy; historical proof hashes are not rebound.
    func pressRandomFromKey() { topBar.onRandom?() }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = false
        addSubview(listScroll)
        addSubview(topBar)
        topBar.onClose = { [weak self] in self?.onClose?() }
        topBar.onGoUp = { [weak self] in self?.goUp() }
        topBar.onHome = { [weak self] in self?.goHome() }
        topBar.onSelectCurrent = { [weak self] in
            guard let self else { return }
            self.onSelectFolder?(self.currentPath)
            // The owner of a folder-selection action closes the panel. A
            // second close here can call the same cleanup after it is gone.
        }
        topBar.onRandom = { [weak self] in
            guard let self else { return }
            let choices = self.entries.filter { $0.isDir || ($0.isPlayable && !["srt", "ass", "ssa", "vtt", "sub"].contains(($0.path as NSString).pathExtension.lowercased())) }
            guard let index = ArchiveRandom.shared.drawIndex(count: choices.count, session: "file-browser") else { return }
            ArchiveRandom.shared.addTiming(ProcessInfo.processInfo.systemUptime * 1000)
            let entry = choices[index]
            if entry.isDir { self.searchQuery = nil; self.loadPath(entry.path) }
            else { self.onSelect?(entry.path) }
        }
        topBar.onSearch = { [weak self] q in self?.performSearch(q) }
        topBar.onClearSearch = { [weak self] in self?.clearSearchAndShowFolder() }
        loadPath(currentPath)
        
        listScroll.rowHeight = PhotonFont.chromeLineH + 4
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func layout() {
        super.layout()
        let barH: CGFloat = PhotonFont.chromeLineH + 4
        topBar.frame = CGRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)
        listScroll.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - barH)
    }

    // WHY: bounds cover the whole padded video area but only topBar,
    // listScroll and row text are interactive - return nil for self so
    // empty-background clicks fall through instead of being swallowed,
    // so a double-click reaches PPController.mouseDown and toggles
    // fullscreen like anywhere else on the video.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
    
    private func renderEntries(_ newEntries: [FileEntry]) {
        entries = newEntries
        listView?.removeFromSuperview()
        listScroll.documentView = nil
        let lv = FileListView(width: listScroll.bounds.width > 10 ? listScroll.bounds.width : bounds.width)
        let icons: [String] = ["\u{e004}","\u{e005}","\u{e006}","\u{e007}","\u{e008}","\u{e009}","\u{e010}","\u{e011}","\u{e012}","\u{e013}","\u{e014}"]
        for (i, entry) in entries.enumerated() {
            let icon = icons[i % icons.count]
            // search results mix folders, so append the parent folder -
            // same-named hits would be indistinguishable otherwise
            let label: String
            if searchQuery != nil {
                let parent = (entry.path as NSString).deletingLastPathComponent
                let parentName = (parent as NSString).lastPathComponent
                label = icon + " " + entry.name + "  \u{b7}  " + parentName
            } else {
                label = icon + " " + entry.name
            }
            // A .torrent opens through MenuActions.streamTorrent; mpv hover
            // preview cannot decode the metadata file itself.
            let previewPath = entry.isDir || entry.path.lowercased().hasSuffix(".torrent") ? nil : entry.path
            lv.row(idx: i, title: label, isPlayable: true, previewPath: previewPath) { [weak self] in
                guard let self else { return }
                if entry.isDir {
                    self.searchQuery = nil
                    self.loadPath(entry.path)
                } else if entry.isPlayable {
                    self.onSelect?(entry.path)
                }
            }
        }
        lv.finish(scrollView: listScroll)
        listView = lv
    }
    
    func loadPath(_ path: String) {
        let generation = nextSearchGeneration()
        entries = [] // no old random target while new directory is loading
        currentPath = path
        topBar.setPath(path)
        // Enumeration and sorting can be substantial on network/large folders.
        // Only the latest navigation may install rows on the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let playableExts: Set<String> = ["torrent","mkv","mp4","avi","mov","m4v","webm","ts","vob","flv","crdownload","part","mp3","flac","wav","aac","ogg","opus","m4a","aiff","wma","srt","ass","ssa","vtt","sub"]
            var dirs: [FileEntry] = []
            var files: [FileEntry] = []
            if let contents = try? fm.contentsOfDirectory(atPath: path) {
                for name in contents.sorted() {
                    guard let self, self.isCurrentSearch(generation) else { return }
                    if name.hasPrefix(".") { continue }
                    let full = path + "/" + name
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: full, isDirectory: &isDir)
                    if isDir.boolValue {
                        dirs.append(FileEntry(name: name, path: full, isDir: true, isPlayable: true))
                    } else {
                        let ext = name.components(separatedBy: ".").last?.lowercased() ?? ""
                        if playableExts.contains(ext) {
                            files.append(FileEntry(name: name, path: full, isDir: false, isPlayable: true))
                        }
                    }
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrentSearch(generation) else { return }
                self.renderEntries(dirs + files)
            }
        }
    }

    // Recursive case-insensitive name search under currentPath (local
    // equivalent of Archive's search), capped against unbounded trees.
    // WHY: the enumerator's stat() calls block, so the walk runs on a
    // background queue; searchGeneration is bumped per call so a
    // superseded search discards its result instead of clobbering a
    // newer one.
    private var searchGeneration = 0
    private let searchGenerationLock = NSLock()
    private func nextSearchGeneration() -> Int {
        searchGenerationLock.lock(); defer { searchGenerationLock.unlock() }
        searchGeneration += 1
        return searchGeneration
    }
    private func isCurrentSearch(_ generation: Int) -> Bool {
        searchGenerationLock.lock(); defer { searchGenerationLock.unlock() }
        return searchGeneration == generation
    }
    
    private func performSearch(_ query: String) {
        searchQuery = query
        entries = [] // stale pre-search random targets are not selectable
        topBar.setPath("search: \"\(query)\" in " + (currentPath as NSString).abbreviatingWithTildeInPath)
        let myGeneration = nextSearchGeneration()
        let path = currentPath
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            let playableExts: Set<String> = ["torrent","mkv","mp4","avi","mov","m4v","webm","ts","vob","flv","crdownload","part","mp3","flac","wav","aac","ogg","opus","m4a","aiff","wma","srt","ass","ssa","vtt","sub"]
            let needle = query.lowercased()
            var dirs: [FileEntry] = []
            var files: [FileEntry] = []
            let maxResults = 500
            
            if let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) {
                for case let url as URL in enumerator {
                    // bail before the next stat() once superseded, so a
                    // stale query stops burning disk I/O
                    guard let self, self.isCurrentSearch(myGeneration) else { return }
                    if dirs.count + files.count >= maxResults { break }
                    let name = url.lastPathComponent
                    guard name.lowercased().contains(needle) else { continue }
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if isDir {
                        dirs.append(FileEntry(name: name, path: url.path, isDir: true, isPlayable: true))
                    } else {
                        let ext = name.components(separatedBy: ".").last?.lowercased() ?? ""
                        if playableExts.contains(ext) {
                            files.append(FileEntry(name: name, path: url.path, isDir: false, isPlayable: true))
                        }
                    }
                }
            }
            dirs.sort { $0.name.lowercased() < $1.name.lowercased() }
            files.sort { $0.name.lowercased() < $1.name.lowercased() }
            let results = dirs + files
            
            DispatchQueue.main.async {
                guard let self, self.isCurrentSearch(myGeneration) else { return }
                self.renderEntries(results)
            }
        }
    }
    
    private func goUp() {
        if searchQuery != nil { searchQuery = nil; loadPath(currentPath); return }
        loadPath((currentPath as NSString).deletingLastPathComponent)
    }
    private func goHome() {
        searchQuery = nil
        loadPath("/Volumes")
    }
    
    // emptying the search field returns to the plain folder view
    // immediately (not debounced), same as Esc or re-tapping search
    fileprivate func clearSearchAndShowFolder() {
        _ = nextSearchGeneration()  // invalidate any in-flight background search
        searchQuery = nil
        loadPath(currentPath)
    }
}

// ================================================================
//  FileBrowserTopBar - navigation bar: back, home, select, close,
//  floating search panel
// ================================================================
final class FileBrowserTopBar: NSView, NSTextFieldDelegate {
    var onClose: (() -> Void)?; var onGoUp: (() -> Void)?; var onHome: (() -> Void)?
    var onSelectCurrent: (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onClearSearch: (() -> Void)?
    var onRandom: (() -> Void)?
    
    private let closeBtn = MusicBtn("×", hover: "close")
    private let upBtn = MusicBtn("↰", hover: "back")
    private let homeBtn = MusicBtn("Δ", hover: "home")
    private let selectBtn = MusicBtn("+", hover: "select")
    private let randomBtn = MusicBtn("∞", hover: "random")
    private let searchBtn = MusicBtn("◌", hover: "search")
    private let pathLbl = NSTextField()

    // Floating search panel (separate key window) — same pattern as
    // MusicPanel.swift's MusicTopBar.openSearchPanel/commitSearch.
    private var searchPanel: NSPanel?
    private var searchField: NSTextField?
    private var isSearchActive = false
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        upBtn.expandsLeftToRight = true
        closeBtn.tap = { [weak self] in self?.onClose?() }
        upBtn.tap = { [weak self] in self?.onGoUp?() }
        homeBtn.tap = { [weak self] in self?.onHome?() }
        selectBtn.tap = { [weak self] in self?.onSelectCurrent?() }
        randomBtn.tap = { [weak self] in self?.onRandom?() }
        searchBtn.tap = { [weak self] in self?.handleSearchTap() }
        pathLbl.isEditable = false; pathLbl.isBordered = false
        pathLbl.drawsBackground = false
        pathLbl.textColor = NSColor.white.withAlphaComponent(0.5)
        pathLbl.font = PhotonFont.chromeNs()
        pathLbl.lineBreakMode = .byTruncatingHead
        [closeBtn, selectBtn, homeBtn, searchBtn, randomBtn, upBtn, pathLbl].forEach { addSubview($0) }
        
        addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self, userInfo: nil))
        
        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self, self.window != nil else { return }
            let p = VariationBroadcaster.shared.proximity(to: self, radius: 300)
            let curv = VariationBroadcaster.shared.curve(p, power: 2.0)
            let color = ScreenCaptureEngine.shared.currentColor(for: "subtitle") ?? .white
            self.pathLbl.textColor = color.withAlphaComponent(0.3 + 0.4 * CGFloat(curv))
            self.pathLbl.font = PhotonFont.chromeNsDriven(view: self, profile: .panel)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    
    // WHY: MusicBtn grows its frame during hover. upBtn expands left to
    // right from a pinned origin (no glyph shift); IconBarFit lays the
    // right row out with a constant gap between glyph ink edges, whatever
    // widths the variable font gives each glyph.

    // WHY: the bar is mostly empty space; return nil for self so clicks
    // fall through (double-click reaches fullscreen toggle), same rule
    // as FileBrowserPanel.hitTest.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }

    override func layout() {
        super.layout()
        let h = bounds.height; let pad: CGFloat = 4
        
        // Owner 13:35: the back glyph starts exactly where the rows' folder icons start, no hover shift.
        upBtn.frame = CGRect(x: FileListRow.rowLeading, y: 0, width: upBtn.frame.width, height: h)
        let upbtnRight = upBtn.frame.maxX + pad
        
        // Right: equal gaps between glyph ink edges, measured from each button's live string.
        let rightBtns = [closeBtn, homeBtn, selectBtn, searchBtn, randomBtn] as [MusicBtn]
        let frames = IconBarFit.trailingFrames(right: bounds.width - pad, height: h, gap: IconBarFit.standardGap,
            buttons: rightBtns.map { IconBarFit.Slot(width: $0.frame.width, ink: $0.inkWidth) })
        for (btn, f) in zip(rightBtns, frames) { btn.frame = f }
        let rx = frames.last?.minX ?? (bounds.width - pad)
        
        // path label sits between the two live cursors, so hover
        // growth on either side pushes it instead of overlapping
        pathLbl.frame = CGRect(x: upbtnRight, y: 0, width: max(0, rx - upbtnRight - pad), height: h)
    }
    
    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }
    
    func setPath(_ path: String) { pathLbl.stringValue = (path as NSString).abbreviatingWithTildeInPath }
    
    // WHY: orderOut(nil) posts no willCloseNotification, so every
    // dismissal path funnels through here - otherwise isShowingInputPanel
    // / eventTap / ignoresMouseEvents stay stuck in "panel open" state.
    private func teardownSearchPanel() {
        liveSearchTimer?.invalidate()
        liveSearchTimer = nil
        let appDelegate = NSApp.delegate as? AppDelegate
        appDelegate?.isShowingInputPanel = false
        appDelegate?.setEventTapEnabled(true)
        window?.ignoresMouseEvents = false
        searchPanel = nil
        searchField = nil
    }
    
    // lets MenuActions' Esc monitor tell "close the search panel" from
    // "close the file browser"
    var isSearchPanelOpen: Bool { searchPanel?.isVisible ?? false }
    
    // closes only the floating search field; browser and committed
    // search results stay
    func closeSearchPanelIfOpen() -> Bool {
        guard let existing = searchPanel, existing.isVisible else { return false }
        existing.close()
        teardownSearchPanel()
        return true
    }
    
    // Floating-NSPanel search, same pattern as MusicTopBar: 4+ chars
    // fire a debounced live search, Enter commits immediately, re-tapping
    // an active search clears it.
    private static let liveSearchMinLength = 4
    private static let liveSearchDebounce: TimeInterval = 0.25
    private var liveSearchTimer: Timer?
    
    // Cmd+F toggle: a visible floating field closes; otherwise the search
    // button path runs (open, or clear an active committed search).
    func toggleSearchPanelFromKey() {
        if closeSearchPanelIfOpen() { return }
        handleSearchTap()
    }
    
    private func handleSearchTap() {
        if isSearchActive {
            isSearchActive = false
            searchBtn.setLabel("◌")
            onClearSearch?()
            return
        }
        openSearchPanel()
    }
    
    private func openSearchPanel() {
        if searchPanel?.isVisible == true {
            _ = closeSearchPanelIfOpen()
            return
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
        panel.title = ""
        panel.level = .modalPanel
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = NSColor.black
        panel.isOpaque = true
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let bg = NSView(frame: CGRect(x: 0, y: 0, width: pw, height: ph))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.cgColor

        let tf = NSTextField(frame: CGRect(x: 20, y: 14, width: pw - 40, height: 28))
        tf.font = PhotonFont.chromeNs()
        tf.textColor = .white
        tf.backgroundColor = .clear; tf.drawsBackground = false
        tf.isBordered = false; tf.focusRingType = .none
        tf.isEditable = true
        tf.isSelectable = true
        tf.refusesFirstResponder = false
        tf.placeholderString = "search files, folders..."
        tf.target = self; tf.action = #selector(commitSearch)
        tf.delegate = self

        bg.addSubview(tf)
        panel.contentView = bg
        searchField = tf; searchPanel = panel
        SearchBarFit.install(panel: panel, field: tf, anchor: .center, host: parentWin)

        appDelegate?.isShowingInputPanel = true
        appDelegate?.setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = true

        // safety net for a real window-close only; normal dismissal
        // paths call teardownSearchPanel() directly (orderOut posts no
        // notification)
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            self?.teardownSearchPanel()
        }

        panel.installStereoIfNeeded(parent: parentWin)
        panel.makeKeyAndOrderFront(nil)
        panel.assertKeyAndFocus(tf)
    }

    @objc private func commitSearch() {
        let q = searchField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        searchPanel?.close()
        teardownSearchPanel()
        guard !q.isEmpty else { return }
        isSearchActive = true
        searchBtn.setLabel("●")
        onSearch?(q)
    }
    
    // live search while the panel stays open; debounced so a keystroke
    // burst doesn't walk the filesystem per character
    func controlTextDidChange(_ obj: Notification) {
        liveSearchTimer?.invalidate()
        let q = searchField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        // empty field returns to the folder view; only clears when a
        // search was actually active, so stray backspaces don't reload
        guard !q.isEmpty else {
            if isSearchActive {
                isSearchActive = false
                searchBtn.setLabel("◌")
                onClearSearch?()
            }
            return
        }
        guard q.count >= Self.liveSearchMinLength else { return }
        liveSearchTimer = Timer.scheduledTimer(withTimeInterval: Self.liveSearchDebounce, repeats: false) { [weak self] _ in
            guard let self, let current = self.searchField?.stringValue.trimmingCharacters(in: .whitespaces),
                  current == q else { return }
            self.isSearchActive = true
            self.searchBtn.setLabel("●")
            self.onSearch?(q)
        }
    }
}

// ================================================================
//  FileListRow - single row: title + size layers, hover mpv preview
// ================================================================
// One small hover button at the right end of a row (archive: favorite / delete / recover),
// drawn with the same MusicBtn as the top bars. Hidden until the pointer rests on the row.
struct FileRowAccessory {
    let glyph: String
    let hover: String
    var alwaysVisible: Bool = false
    let action: () -> Void
}

final class FileListRow: NSView {
    /// Leading inset of every row's title (icon + name); the top bar pins its back glyph to this x (owner 13:35).
    static let rowLeading: CGFloat = 0
    var action: (() -> Void)?
    private var accessoryButtons: [MusicBtn] = []
    private var accessoryReveal: DispatchWorkItem?
    // Same right inset and slot width the top bar uses for its close button, so the right-most
    // accessory sits in the close button's column.
    private static let accessoryPad: CGFloat = 4
    private static let accessorySlot: CGFloat = 32
    private static let accessoryDwell: TimeInterval = 0.45
    private var accessoryReserve: CGFloat {
        accessoryButtons.isEmpty ? 0 : Self.accessoryPad + CGFloat(accessoryButtons.count) * Self.accessorySlot + CGFloat(accessoryButtons.count - 1) * IconBarFit.standardGap
    }

    func setAccessories(_ specs: [FileRowAccessory]) {
        accessoryReveal?.cancel(); accessoryReveal = nil
        accessoryButtons.forEach { $0.removeFromSuperview() }
        accessoryButtons = specs.map { spec in
            let b = MusicBtn(spec.glyph, hover: spec.hover)
            b.tap = spec.action
            b.isHidden = !spec.alwaysVisible
            addSubview(b)
            return b
        }
        accessorySpecsAlways = specs.map { $0.alwaysVisible }
        needsLayout = true
    }
    private var accessorySpecsAlways: [Bool] = []

    private func scheduleAccessoryReveal() {
        guard !accessoryButtons.isEmpty, accessoryReveal == nil,
              accessoryButtons.contains(where: { $0.isHidden }) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.accessoryReveal = nil
            self.accessoryButtons.forEach { $0.isHidden = false }
            self.needsLayout = true
        }
        accessoryReveal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.accessoryDwell, execute: work)
    }

    private func hideAccessories() {
        accessoryReveal?.cancel(); accessoryReveal = nil
        for (i, b) in accessoryButtons.enumerated() where i < accessorySpecsAlways.count && !accessorySpecsAlways[i] {
            b.isHidden = true
        }
    }
    var previewPath: String?
    private var previewWork: PreviewWork?
    private var previewProcess: Process?
    private var previewSocketPath: String?
    private var previewPollToken: UUID?
    private var previewStart: DispatchWorkItem?
    private var lastPreviewSeek: TimeInterval = 0
    private static var aspectCache: [String: Double] = [:]
    private static var probedPaths = Set<String>()
    private let titleLayer = CATextLayer()
    // WHY: size text gets its own right-aligned fixed-width layer -
    // baked into the title it would be the first thing .end truncation
    // clips, which defeats showing it.
    private let sizeLayer: CATextLayer?
    private var isPlayable: Bool = false
    private var variationToken: UUID?
    // untruncated title; applyTruncatedTitle(width:) cuts the middle
    // and keeps the extension (the mkv/mp4 distinction), re-run from
    // layout() since the real width is unknown at init
    private let fullTitle: String

    init(frame: NSRect, title: String, isPlayable: Bool, sizeText: String? = nil) {
        if let sizeText, !sizeText.isEmpty {
            sizeLayer = CATextLayer()
            sizeLayer!.string = sizeText
        } else {
            sizeLayer = nil
        }
        fullTitle = title
        super.init(frame: frame)
        self.isPlayable = isPlayable
        wantsLayer = true
        
        titleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped = false
        // fallback only; applyTruncatedTitle pre-shortens, and .end is
        // safer than middle if it ever cuts before layout runs
        titleLayer.truncationMode = .end
        titleLayer.foregroundColor = isPlayable ? NSColor.white.cgColor : NSColor.white.withAlphaComponent(0.28).cgColor
        titleLayer.font = PhotonFont.chromeCt()
        if titleLayer.fontSize != PhotonFont.chromeSize { titleLayer.fontSize = PhotonFont.chromeSize }
        titleLayer.string = title
        titleLayer.shadowColor = NSColor.black.cgColor
        titleLayer.shadowRadius = PPController.shadowRadius
        titleLayer.shadowOpacity = PPController.shadowOpacity
        titleLayer.shadowOffset = .zero
        layer?.addSublayer(titleLayer)
        
        if let sizeLayer {
            sizeLayer.contentsScale = titleLayer.contentsScale
            sizeLayer.isWrapped = false
            sizeLayer.alignmentMode = .right
            sizeLayer.truncationMode = .end
            // dimmer than the title (metadata, not the selection) and
            // excluded from updateFontVariation()'s hover weight
            sizeLayer.foregroundColor = NSColor.white.withAlphaComponent(isPlayable ? 0.45 : 0.22).cgColor
            sizeLayer.font = PhotonFont.chromeCt()
            if sizeLayer.fontSize != PhotonFont.chromeSize { sizeLayer.fontSize = PhotonFont.chromeSize }
            sizeLayer.shadowColor = NSColor.black.cgColor
            sizeLayer.shadowRadius = PPController.shadowRadius
            sizeLayer.shadowOpacity = PPController.shadowOpacity
            sizeLayer.shadowOffset = .zero
            layer?.addSublayer(sizeLayer)
        }
        
        if isPlayable {
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect], owner: self, userInfo: nil))
        }
        
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            self?.titleLayer.font = PhotonFont.chromeCt()
            if let l = self?.titleLayer, l.fontSize != PhotonFont.chromeSize { l.fontSize = PhotonFont.chromeSize }
            self?.sizeLayer?.font = PhotonFont.chromeCt()
            if let l = self?.sizeLayer, l.fontSize != PhotonFont.chromeSize { l.fontSize = PhotonFont.chromeSize }
            self?.needsLayout = true
        }
        
        variationToken = VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            DispatchQueue.main.async { self?.updateFontVariation() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    
    // A width change (window <-> fullscreen) must always re-fit the title; relying on AppKit to
    // call layout() after a frame change left names cut to the previous (window) width.
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.size.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { needsLayout = true }
    }

    override func layout() {
        super.layout()
        let h = bounds.height; let padLeft: CGFloat = Self.rowLeading; let padRight: CGFloat = 12 + accessoryReserve
        // Accessories: equal ink gaps (IconBarFit), same system as the top bar.
        let aFrames = IconBarFit.trailingFrames(right: bounds.width - Self.accessoryPad,
            height: PhotonFont.chromeLineH, gap: IconBarFit.standardGap,
            buttons: accessoryButtons.reversed().map { IconBarFit.Slot(width: $0.frame.width, ink: $0.inkWidth) })
        for (b, f) in zip(accessoryButtons.reversed(), aFrames) {
            b.frame = f.offsetBy(dx: 0, dy: (h - PhotonFont.chromeLineH) / 2)
        }
        if let sizeLayer {
            // fixed-width slot pinned to the right edge, sized to the
            // current string with a floor/ceiling so it never clips or
            // jumps between rows
            let sizeText = (sizeLayer.string as? String) ?? ""
            let sizeWidth = min(140, max(56, sizeText.size(withAttributes: [.font: PhotonFont.chromeNs()]).width + 4))
            sizeLayer.frame = CGRect(x: bounds.width - padRight - sizeWidth, y: (h - PhotonFont.chromeLineH) / 2,
                                      width: sizeWidth, height: PhotonFont.chromeLineH)
            let gap: CGFloat = 10
            let titleWidth = max(0, bounds.width - padLeft - padRight - sizeWidth - gap)
            titleLayer.frame = CGRect(x: padLeft, y: (h - PhotonFont.chromeLineH) / 2, width: titleWidth, height: PhotonFont.chromeLineH)
        } else {
            titleLayer.frame = CGRect(x: padLeft, y: (h - PhotonFont.chromeLineH) / 2, width: bounds.width - padLeft - padRight, height: PhotonFont.chromeLineH)
        }
        applyTruncatedTitle(width: titleLayer.frame.width)
    }

    // Shortens fullTitle to fit `width`, cutting only the middle so the
    // file extension (the mkv/mp4 distinction) always survives at the end
    // — "Satantango (1994) USA Arbelos Blu...mkv" instead of .end
    // truncation's "Satantango (1994) USA Arbelos Blu..." with no
    // extension at all. No-ops (leaves fullTitle as-is) when it already
    // fits, so short names are never touched.
    private func applyTruncatedTitle(width: CGFloat) {
        guard width > 0 else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: PhotonFont.chromeNs()]
        guard fullTitle.size(withAttributes: attrs).width > width else {
            titleLayer.string = fullTitle
            return
        }

        // Extension = substring after the last '.', kept whole and always
        // shown; everything before it is the part that gives up characters.
        // No '.' at all (rare — an extensionless name) just falls back to
        // shortening the whole string with no suffix carve-out.
        let ext: String
        let stem: String
        if let dot = fullTitle.range(of: ".", options: .backwards) {
            ext = String(fullTitle[dot.lowerBound...])   // includes the "."
            stem = String(fullTitle[..<dot.lowerBound])
        } else {
            ext = ""
            stem = fullTitle
        }

        let ellipsis = "…"
        let ellipsisWidth = ellipsis.size(withAttributes: attrs).width
        let extWidth = ext.size(withAttributes: attrs).width
        let headBudget = width - ellipsisWidth - extWidth
        guard headBudget > 0 else {
            // Pathologically narrow row — extension alone barely fits.
            // Fall back to plain .end truncation rather than producing an
            // empty/negative-width head.
            titleLayer.string = fullTitle
            return
        }

        // Binary search the longest stem prefix (in characters) that fits
        // headBudget — cheaper than measuring one character at a time for
        // long titles, and titles here are short enough (a few hundred
        // chars at most) that correctness matters more than micro-cost.
        let stemChars = Array(stem)
        var lo = 0, hi = stemChars.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = String(stemChars[..<mid])
            if candidate.size(withAttributes: attrs).width <= headBudget {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        // WHY: trim only trailing whitespace before the ellipsis - the
        // leading "  " prefix every row title carries must survive, or
        // truncated rows render flush against the row edge while short
        // rows stay padded.
        var head = String(stemChars[..<lo])
        while head.hasSuffix(" ") { head.removeLast() }
        titleLayer.string = head.isEmpty ? fullTitle : "\(head)\(ellipsis)\(ext)"
    }
    
    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        updateFontVariation()
        // I43: preview seeks capped at 10Hz, geometry in the same IPC command
        guard let socketPath = previewSocketPath,
              FileManager.default.fileExists(atPath: socketPath) else { return }
        guard bounds.width > 0 else { return }
        let x = convert(e.locationInWindow, from: nil).x
        let progress = max(0, min(1, Double(x / bounds.width))) * 100
        let now = Date().timeIntervalSince1970
        guard now - lastPreviewSeek >= 0.1 else { return }
        lastPreviewSeek = now
        let seekCmd = "{\"command\":[\"seek\",\(progress),\"absolute-percent\",\"keyframes\"]}\n"
        updatePreviewPosition(mouse: NSEvent.mouseLocation, extraCommand: seekCmd)
    }
    
    // One teardown for every path that ends a hover (exit, click, deinit,
    // re-entry). PreviewGuard.terminate asks mpv to quit over its IPC
    // socket, closes the EOF lifeline, then escalates SIGTERM -> SIGKILL
    // off the main thread: a preview never outlives its hover.
    private func stopPreview() {
        previewStart?.cancel()
        previewStart = nil
        lastPreviewSeek = 0
        previewPollToken = nil
        previewWork?.cancel(); previewWork = nil
        if let process = previewProcess {
            let socketPath = previewSocketPath
            PreviewGuard.terminate(process, gracefulQuit: socketPath.map { path in
                { _ = IPCClient.socketRoundtrip(path: path, payload: "{\"command\":[\"quit\"]}\n", timeout: 0.25, sendOnly: true) }
            })
        }
        previewProcess = nil
        previewSocketPath = nil
    }

    override func mouseExited(with e: NSEvent) {
        hideAccessories()
        updateFontVariation()
        stopPreview()
    }
    
    private func updateFontVariation() {
        let p = verticalProximity(to: self, radius: 180)
        if p <= 0 {
            // mouse far: audio still drives wght (audioBlend(0) = smoothAudio*0.85)
            let wght = 100.0 + 200.0 * Double(VariationBroadcaster.shared.audioBlend(0))
            let font = PhotonFont.chromeCt(wght: wght, SIZE: PhotonFont.chromeSize * 0.85)
            if (titleLayer.font as AnyObject?) !== (font as AnyObject) {
                PhotonFont.setIfChanged(font, on: titleLayer)
            }
            let color = NSColor.white.withAlphaComponent(0.28).cgColor
            if titleLayer.foregroundColor != color { titleLayer.foregroundColor = color }
            return
        }
        let curv = VariationBroadcaster.shared.curve(p, power: 2.0)
        let alpha: CGFloat = 0.28 + 0.72 * CGFloat(curv)
        let font = PhotonFont.chromeCtDriven(view: self, profile: .row)
        if (titleLayer.font as AnyObject?) !== (font as AnyObject) {
            PhotonFont.setIfChanged(font, on: titleLayer)
        }
        let color = NSColor.white.withAlphaComponent(alpha).cgColor
        if titleLayer.foregroundColor != color { titleLayer.foregroundColor = color }
    }

    private func verticalProximity(to view: NSView, radius: CGFloat) -> CGFloat {
        guard let win = view.window else { return 0 }
        let center = view.convert(NSPoint(x: 0, y: view.bounds.midY), to: win.contentView)
        let dy = abs(VariationBroadcaster.shared.mouseWindowPt.y - center.y)
        return max(0, min(1, 1.0 - dy / radius))
    }
    
    // WHY: mirror mouseDown's clickable-width test so a point on the
    // blank space past the title returns nil and falls through (e.g.
    // double-click reaches RowSnapScrollView) instead of being consumed
    // and silently dropped.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        for b in accessoryButtons where !b.isHidden && b.frame.contains(local) { return b }
        let pad: CGFloat = 12
        let titleText = (titleLayer.string as? String) ?? ""
        let textWidth = titleText.size(withAttributes: [.font: PhotonFont.chromeNs()]).width
        let clickableWidth = min(textWidth, titleLayer.frame.width)
        guard local.x >= pad, local.x <= pad + clickableWidth else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with e: NSEvent) {
        // activation only on the title's rendered width (capped at the
        // slot), same left pad as layout() - blank space does nothing
        let clickX = convert(e.locationInWindow, from: nil).x
        let pad: CGFloat = 12
        let titleText = (titleLayer.string as? String) ?? ""
        let textWidth = titleText.size(withAttributes: [.font: PhotonFont.chromeNs()]).width
        let clickableWidth = min(textWidth, titleLayer.frame.width)
        guard clickX >= pad, clickX <= pad + clickableWidth else { return }
        stopPreview()
        action?()
    }
    
    // One background serial channel for preview commands. No shell or nc
    // subprocesses on cursor movement; keep UI events off socket I/O.
    private static let previewIPCQueue = DispatchQueue(label: "gor.preview.ipc", qos: .utility)
    private var previewAspect: Double = 16.0/9.0
    
    // I43: preview mpv launches only after a 125ms hover delay
    override func mouseEntered(with e: NSEvent) {
        scheduleAccessoryReveal()
        updateFontVariation()
        stopPreview() // idempotent; clears any stale or cap-evicted preview state
        let work = DispatchWorkItem { [weak self] in self?.startPreview() }
        previewStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(125), execute: work)
    }

    private func startPreview() {
        previewStart = nil
        guard previewProcess == nil, let path = previewPath,
              let appDelegate = NSApp.delegate as? AppDelegate,
              let screen = NSScreen.main,
              let overlayWin = appDelegate.overlayWin else { return }

        let socketPath = "/tmp/preview_mpv_\(UUID().uuidString).sock"
        previewSocketPath = socketPath
        previewAspect = Self.aspectCache[path] ?? 16.0 / 9.0
        let geo = calcPreviewGeometry(mouse: NSEvent.mouseLocation,
                                      screen: screen, overlayWin: overlayWin)

        let previewMpv = Process()
        // vendorPath: resolved vendored path, or the conventional sibling
        // path on a miss (logged); the do/catch run() below degrades preview.
        previewMpv.executableURL = URL(fileURLWithPath: GORResources.vendorPath("mpv/bin/mpv"))
        // PreviewGuard owns the one argument list: it carries
        // --macos-app-activation-policy=prohibited, so a preview helper
        // never takes a Dock icon (the main playback spawn already does).
        previewMpv.arguments = PreviewGuard.arguments(geometry: geo, socketPath: socketPath, path: path)
        let work = PreviewWork(); previewWork = work
        let token = UUID(); previewPollToken = token
        PreviewGuard.log = Self.appendPreviewDiag
        PreviewGuard.launch(previewMpv, work: work) { [weak self] success in
            DispatchQueue.main.async {
                guard let self, self.previewPollToken == token, !work.isCancelled else {
                    if success { PreviewGuard.terminate(previewMpv) }; return
                }
                guard success else { self.previewSocketPath = nil; self.previewWork = nil; return }
                self.previewProcess = previewMpv
            }
        }
        guard !Self.probedPaths.contains(path) else { return }
        Self.probedPaths.insert(path)
        // I43: one ffprobe attempt per path, aspect cached; never a
        // process per IPC retry or mouse move.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard !work.isCancelled else { return }
            let probe = Process()
            guard work.attach(probe) else { return }
            let probePath = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            guard let probePath else { return }
            probe.executableURL = URL(fileURLWithPath: probePath)
            probe.arguments = ["-v", "error", "-select_streams", "v:0",
                               "-show_entries", "stream=width,height", "-of", "csv=p=0", path]
            let out = Pipe()
            probe.standardOutput = out
            probe.standardError = FileHandle.nullDevice
            guard !work.isCancelled else { return }
            do { try probe.run() } catch { return }
            if work.isCancelled { PreviewGuard.terminate(probe); return }
            // Deadline closes a blocked read as well as an unresponsive child.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) {
                if probe.isRunning { PreviewGuard.terminate(probe) }
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            probe.waitUntilExit()
            let values = String(data: data, encoding: .utf8)?
                .split(separator: "\n").first?.split(separator: ",") ?? []
            guard probe.terminationStatus == 0, values.count >= 2,
                  let width = Double(values[0]), let height = Double(values[1]),
                  width > 0, height > 0 else { return }
            DispatchQueue.main.async {
                guard let self, self.previewPollToken == token else { return }
                self.previewAspect = width / height
                Self.aspectCache[path] = self.previewAspect
                self.updatePreviewPosition(mouse: NSEvent.mouseLocation)
            }
        }
    }

    private func calcPreviewGeometry(mouse: NSPoint, screen: NSScreen, overlayWin: NSWindow) -> String {
        let scale = screen.backingScaleFactor
        let scrH = screen.frame.height
        let previewW = Int(320 * scale)
        let previewH = Int(Double(previewW) / previewAspect)
        
        let winMinX = Int(overlayWin.frame.minX * scale)
        let winMaxX = Int(overlayWin.frame.maxX * scale)
        let winMinY = Int((scrH - overlayWin.frame.maxY) * scale)
        let winMaxY = Int((scrH - overlayWin.frame.minY) * scale)
        
        let mousePixX = Int(mouse.x * scale)
        let mousePixY = Int((scrH - mouse.y) * scale)
        
        var pxX = mousePixX - previewW
        var pxY = mousePixY
        
        if pxX < winMinX { pxX = mousePixX }
        if pxX + previewW > winMaxX { pxX = winMaxX - previewW }
        if pxY + previewH > winMaxY { pxY = mousePixY - previewH }
        if pxY < winMinY { pxY = winMinY }
        
        return "\(previewW)x\(previewH)+\(pxX)+\(pxY)"
    }
    
    private func updatePreviewPosition(mouse: NSPoint, extraCommand: String = "") {
        guard let socketPath = previewSocketPath,
              FileManager.default.fileExists(atPath: socketPath),
              let screen = NSScreen.main,
              let overlayWin = (NSApp.delegate as? AppDelegate)?.overlayWin else { return }
        
        let geo = calcPreviewGeometry(mouse: mouse, screen: screen, overlayWin: overlayWin)
        let cmd = "{\"command\":[\"set\",\"geometry\",\"\(geo)\"]}\n"
        let payload = extraCommand + cmd
        previewWork?.sendLatest {
            _ = IPCClient.socketRoundtrip(path: socketPath, payload: payload, timeout: 0.05, sendOnly: true)
        }
    }
    
    deinit {
        stopPreview()
        if let token = variationToken {
            VariationBroadcaster.shared.removeListener(token)
        }
    }

    // Preview spawn/exit counts land in the existing bounded gor_diag.log;
    // no new file, same cap as every other diagnostic record.
    private static func appendPreviewDiag(_ line: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let text = line.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let data = Data((f.string(from: Date()) + " " + text + "\n").utf8)
        _ = BoundedDiskWriter.append(data, to: URL(fileURLWithPath: StagedRunPaths.tmp("/tmp/gor_diag.log")), cap: SharedDiagnosticRecord.cap)
    }
}

// ================================================================
//  FileListView - scroll content: batched row construction
// ================================================================
final class FileListView: NSView {
    private let rowH: CGFloat = PhotonFont.chromeLineH + 4
    private struct RowData {
        let title: String, isPlayable: Bool
        let previewPath: String?, sizeText: String?
        let accessories: [FileRowAccessory]
        let action: () -> Void
    }
    private var rowData: [RowData] = []
    private var visibleRows: [Int: FileListRow] = [:]
    private weak var scrollView: NSScrollView?

    init(width: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: max(width, 100), height: 800))
        autoresizingMask = [.width]
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    
    func row(idx: Int, title: String, isPlayable: Bool, previewPath: String? = nil,
             sizeText: String? = nil, accessories: [FileRowAccessory] = [],
             action: @escaping () -> Void) {
        rowData.append(RowData(title: title, isPlayable: isPlayable,
                               previewPath: previewPath, sizeText: sizeText,
                               accessories: accessories, action: action))
    }

    @objc private func scrollChanged() {
        guard let scrollView else { return }
        tileVisible(in: scrollView.contentView.bounds)
    }

    private func tileVisible(in visibleRect: CGRect) {
        let start = max(0, Int(floor(visibleRect.minY / rowH)) - 2)
        let end = min(rowData.count, Int(ceil(visibleRect.maxY / rowH)) + 3)
        let wanted = start..<max(start, end)
        for index in Array(visibleRows.keys) where !wanted.contains(index) {
            visibleRows.removeValue(forKey: index)?.removeFromSuperview()
        }
        for index in wanted where visibleRows[index] == nil {
            let data = rowData[index]
            let row = FileListRow(frame: CGRect(x: 0, y: CGFloat(index) * rowH,
                                                width: bounds.width, height: rowH),
                                  title: data.title, isPlayable: data.isPlayable,
                                  sizeText: data.sizeText)
            row.previewPath = data.previewPath
            if !data.accessories.isEmpty { row.setAccessories(data.accessories) }
            if data.isPlayable { row.action = data.action }
            row.autoresizingMask = [.width]
            addSubview(row)
            visibleRows[index] = row
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Re-stretch the visible rows right away; do not wait for a later layout pass.
        for row in visibleRows.values where abs(row.frame.width - newSize.width) > 0.5 {
            row.frame.size.width = newSize.width
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        for row in visibleRows.values where row.frame.width != bounds.width {
            row.frame.size.width = bounds.width
        }
        if let scrollView { tileVisible(in: scrollView.contentView.bounds) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }

    func finish(scrollView: NSScrollView) {
        frame.size.height = max(CGFloat(rowData.count) * rowH + 8, scrollView.bounds.height + 1)
        frame.size.width = scrollView.contentView.bounds.width
        self.scrollView = scrollView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrollChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.documentView = self
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: 0))
        tileVisible(in: scrollView.contentView.bounds)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

}

// ================================================================
//  RowSnapScrollView - scroll view with row-height snap + click-through
// ================================================================
class RowSnapScrollView: NSScrollView {
    var rowHeight: CGFloat = 44
    private var scrollAccum: CGFloat = 0
    
    // WHY: NSScrollView never resizes documentView's width on its own -
    // pin it to the clip width every pass, which drives the row
    // re-stretch chain in FileListView/FileListRow layout().
    override func layout() {
        super.layout()
        if let doc = documentView, doc.frame.width != contentView.bounds.width {
            doc.frame.size.width = contentView.bounds.width
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard rowHeight > 0 else {
            super.scrollWheel(with: event)
            return
        }
        
        if event.phase == .began {
            scrollAccum = 0
        }
        
        if event.phase == .changed || event.momentumPhase == .changed {
            scrollAccum += event.scrollingDeltaY
            
            if abs(scrollAccum) >= rowHeight {
                let steps = round(scrollAccum / rowHeight)
                let moveY = steps * rowHeight
                scrollAccum = scrollAccum - moveY
                
                var newOrigin = contentView.bounds.origin
                newOrigin.y -= moveY
                
                if let docView = documentView {
                    let maxY = max(0, docView.frame.height - contentSize.height)
                    newOrigin.y = min(maxY, max(0, newOrigin.y))
                }
                
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    contentView.animator().setBoundsOrigin(newOrigin)
                }
            }
        } else if event.phase == .ended || event.phase == .cancelled {
            scrollAccum = 0
            if let docView = documentView {
                let offsetY = contentView.bounds.origin.y
                let snappedY = round(offsetY / rowHeight) * rowHeight
                let maxY = max(0, docView.frame.height - contentSize.height)
                let clampedY = min(maxY, max(0, snappedY))
                
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: clampedY))
                }
            }
        } else {
            super.scrollWheel(with: event)
        }
    }
    
    // WHY: empty list background should behave like empty video space -
    // a genuine double-click toggles fullscreen via the same mpv IPC
    // command (see MenuActions.menuFullscreen); single clicks pass to
    // super for the drag-to-move gesture.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            (NSApp.delegate as? AppDelegate)?.controller?.ipcCommand(#"{"command":["cycle","fullscreen"]}"#)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        (NSApp.delegate as? AppDelegate)?.moveMpv(dx: event.deltaX, dy: event.deltaY)
    }
    
    override func mouseUp(with event: NSEvent) {
        (NSApp.delegate as? AppDelegate)?.resetMpvPositionCache()
        super.mouseUp(with: event)
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/FileBrowser.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='633b968dd7d4ecc5626b174b8a1744290e82cbd53ce28481e32d6ad18b914b67', 'pinned source changed: rebase and review, never bless silently'
for token in ['FileBrowserPanel', 'FileEntry', 'toggleSearchPanelFromKey', 'pressRandomFromKey', 'renderEntries', 'loadPath', 'nextSearchGeneration', 'isCurrentSearch', 'performSearch', 'goUp', 'goHome', 'clearSearchAndShowFolder']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='633b968dd7d4ecc5626b174b8a1744290e82cbd53ce28481e32d6ad18b914b67'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-27: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-27: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
