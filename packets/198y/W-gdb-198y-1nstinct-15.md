# W-gdb-198y-1nstinct-15
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/MusicPanel.swift -> GorUI. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-15.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-15",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/MusicPanel.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/MusicPanel.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: DraggableScrollView, MusicPanel, Screen, bind, updateScrollProgress, push, replaceTop, goBack, render, addLocalLibrary, previewCover, clearPreviewCover",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-15.py",
    "callee": "archive/gor/Sources/gor/MusicPanel.swift owning station GorUI"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-15.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-15.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-15.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:15.555151+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/MusicPanel.swift",
        "block": "source1",
        "sha256": "c671112da430988b090b17e1b9565d181c73993d60e7113365f05cfd4d2ab27f"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-15.py",
        "block": "fixtures1",
        "sha256": "7df5b093afb223b853bc142119f0c0de038118d898f74b289c2974a501a5509e"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "636cf6fdc3954baa8f81b76d1e9615952ea29495f29c14c8d170f4c00d084686",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-15: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "4aaec3d7818072849f454ac202de1a8b40661bf0c5d775720969f6b2da05b3c3"
  }
}
```

```swift id=source1
// ================================================================
//  MusicPanel.swift - music panel: menu/library/tracks/queue/playlist
//  screens, row list, top/bottom bars, MusicBtn
//  Owns: the screen stack, list row pool, multi-select state,
//  MusicBtn hover expansion
//  Contract: all text PhotonFont.chromeNs() at one size; rowH =
//  PhotonFont.chromeLineH + 8 everywhere; transparent top/bot bars
// ================================================================
import AppKit
import Foundation

// ================================================================
//  DraggableScrollView - scroll view that drag-moves the window
// ================================================================

private class DraggableScrollView: NSScrollView {
    override func mouseDragged(with event: NSEvent) {
        (NSApp.delegate as? AppDelegate)?.moveMpv(dx: event.deltaX, dy: event.deltaY)
    }
    override func mouseUp(with event: NSEvent) {
        (NSApp.delegate as? AppDelegate)?.resetMpvPositionCache()
        super.mouseUp(with: event)
    }
}

// ================================================================
//  MusicPanel - panel root: screen stack, list, bars
// ================================================================

final class MusicPanel: NSView {

    weak var controller: MusicController?
    var onClose: (() -> Void)?
    
    weak var sidebarRef: SidebarUI?
    var onScreenChange: ((Bool) -> Void)?

    enum Screen {
        case menu
        case library([MusicItem])
        case results(String, [MusicItem])
        case tracks(Int, String, String?, [TrackItem], String)
        case info(Int, String, String)
        case queue([QueueItem], Int)
        case playlist(Playlist)
        case localItems(String, String, [[String: Any]])  // path, name, items
        case localAlbum(String, String, [[String: Any]], String?)  // path, name, tracks, cover
    }

    private var stack: [Screen] = [.menu]
    private var currentScreen: Screen { stack.last ?? .menu }

    private let topBar     = MusicTopBar()
    private let listScroll = RowSnapScrollView()
    private let botBar     = MusicBotBar()
    private var listView: MusicListView?

    private var allLibrary: [MusicItem] = []
    private var playlists:  [Playlist]  = []
    private var localLibraries: [[String: Any]] = []

    // Multi-select
    private var selectedIndices: Set<Int> = []
    
    private var searchQuery: String = ""
    private var lastNowPlayingTitle: String = ""
    
    private var hoverCoverTimer: Timer?
    
    var onHoverCover: ((String) -> Void)?
    var onHoverCoverEnd: (() -> Void)?
    

    // ── init ─────────────────────────────────────────────────────

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Transparent — album art shows through
        
        registerForDraggedTypes([.fileURL])

        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = false
        listScroll.autohidesScrollers = true
        listScroll.verticalScroller?.alphaValue = 0.2

        addSubview(listScroll)
        addSubview(botBar)
        addSubview(topBar)

        topBar.onBack   = { [weak self] in self?.goBack() }
        topBar.onClose  = { [weak self] in self?.onClose?() }
        topBar.onSearch = { [weak self] q in self?.doSearch(q) }
        topBar.onAdd    = { [weak self] in self?.actionAdd() }
        topBar.onInfo   = { [weak self] in self?.actionInfo() }
        topBar.onNewPl  = { [weak self] in self?.actionNewPlaylist() }

        botBar.onPrev      = { [weak self] in self?.controller?.prev() }
        botBar.onPlayPause = { [weak self] in self?.playOrPauseSelection() }
        botBar.onNext      = { [weak self] in self?.controller?.next() }
        botBar.onQueue     = { [weak self] in self?.showQueue() }
        botBar.onQueueSel  = { [weak self] in self?.queueSelection() }
        botBar.onDataMode = { [weak self] in self?.toggleDataMode() }
        
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            self?.needsLayout = true
            self?.render()
        }
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    // ── layout ────────────────────────────────────────────────────

    private let barH = PhotonFont.chromeLineH

    override func layout() {
        super.layout()
        guard bounds.width > 10 else { return }
        let w = bounds.width; let h = bounds.height
        topBar.frame     = CGRect(x: 0, y: h - barH, width: w, height: barH)
        botBar.frame     = CGRect(x: 0, y: 0,        width: w, height: barH)
        listScroll.frame = CGRect(x: 0, y: barH,     width: w, height: h - barH * 1.985)
        if listView == nil, controller != nil { render() }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if !botBar.frame.contains(loc) {
            (NSApp.delegate as? AppDelegate)?.moveMpv(dx: event.deltaX, dy: event.deltaY)
        }
    }

    override func mouseUp(with event: NSEvent) {
        (NSApp.delegate as? AppDelegate)?.resetMpvPositionCache()
        super.mouseUp(with: event)
    }
    
    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.pasteboardItems else { return false }
        for item in items {
            guard let str = item.string(forType: .fileURL),
                  let url = URL(string: str) else { continue }
            let ext = url.pathExtension.lowercased()
            let subExts: Set<String> = ["srt","ass","ssa","vtt","sub"]
            let videoExts: Set<String> = ["mkv","mp4","avi","mov","m4v","webm","ts","flv"]
            if subExts.contains(ext) {
                // subtitle - send to mpv
                if let ctrl = self.superview as? PPController {
                    ctrl.ipcCommand(MPVCommand.make(["sub-add", url.path]))
                }
                return true
            } else if videoExts.contains(ext) {
                // video - leave music mode, open the file
                if let ctrl = self.superview as? PPController {
                    ctrl.iptvChannelTitle = ""
                    ctrl.ipcCommand(MPVCommand.make(["loadfile", url.path]))
                }
                return true
            }
        }
        return false
    }

    // ── bind ──────────────────────────────────────────────────────

    func bind(controller: MusicController) {
        self.controller = controller

        controller.onMenu = { [weak self] pls, libCount, _ in
            guard let self else { return }
            self.playlists = pls
            if case .menu = self.currentScreen {
                self.render()
            }
            self.botBar.setDataMode(self.controller?.currentDataMode ?? "")
        }

        controller.onResults = { [weak self] items in
            guard let self else { return }
            self.allLibrary = items
            
            switch self.currentScreen {
            case .library:
                self.replaceTop(.library(items))
            case .results:
                self.replaceTop(.results(self.searchQuery, items))
            case .menu:
                self.render()  // only update the count, don't auto-advance
            default:
                break
            }
        }

        controller.onTracks = { [weak self] idx, title, cover, tracks, source in
            self?.push(.tracks(idx, title, cover, tracks, source))
        }

        controller.onInfo = { [weak self] idx, title, text in
            self?.push(.info(idx, title, text))
        }

        controller.onQueue = { [weak self] items, cur in
            guard let self else { return }
            if case .queue = self.currentScreen { self.replaceTop(.queue(items, cur)) }
            self.botBar.setQueueCount(items.count)
        }

        controller.onNowPlaying = { [weak self] title, source, trackN in
            guard let self else { return }
            self.lastNowPlayingTitle = title
            self.botBar.setTitle(title)
            self.botBar.setPlaying(true)
            // update the selected track and re-render
            self.selectedIndices = [trackN]
            if case .tracks = self.currentScreen {
                self.render()
            }
            if case .localAlbum = self.currentScreen {
                self.render()
            }
        }

        // onStatus: use the mpv title only while lastNowPlayingTitle is empty
        controller.onStatus = { [weak self] title, _, _, paused, _ in
            guard let self else { return }
            if self.lastNowPlayingTitle.isEmpty && !title.isEmpty {
                self.botBar.setTitle(title)
            } else if !self.lastNowPlayingTitle.isEmpty {
                self.botBar.setTitle(self.lastNowPlayingTitle)
            }
            self.botBar.setPlaying(!paused)
        }

        controller.onPlaylists = { [weak self] pls in
            guard let self else { return }
            self.playlists = pls
            // re-render when the current screen is menu or playlist
            if case .menu = self.currentScreen {
                self.render()
            }
        }
        
        controller.onLocalLibraries = { [weak self] libs in
            guard let self else { return }
            self.localLibraries = libs
            if case .menu = self.currentScreen {
                self.render()
            }
        }
        
        controller.onLocalItems = { [weak self] path, name, items in
            self?.push(.localItems(path, name, items))
        }
        
        botBar.setDataMode(controller.currentDataMode)
        
        controller.localList()

        controller.requestMenu()
        
        // bind scrollTarget - the seekBar drives scrolling
        sidebarRef?.scrollTarget = listScroll
        
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didLiveScrollNotification,
            object: listScroll,
            queue: .main
        ) { [weak self] _ in
            self?.updateScrollProgress()
        }
        
        listScroll.rowHeight = PhotonFont.chromeLineH + 4 + 1

    }

    private func updateScrollProgress() {
        guard let docView = listScroll.documentView else { return }
        let contentH  = docView.frame.height
        let visibleH  = listScroll.contentSize.height
        let scrollable = contentH - visibleH
        guard scrollable > 0 else {
            sidebarRef?.setScrollProgress(0)
            return
        }
        let offsetY  = listScroll.contentView.bounds.origin.y
        let progress = Double(offsetY / scrollable)   // 0=start, 1=end
        sidebarRef?.setScrollProgress(progress)
    }

    // ── navigation ────────────────────────────────────────────────

    private func push(_ s: Screen) {
        selectedIndices.removeAll()
        stack.append(s); render()
    }
    private func replaceTop(_ s: Screen) {
        if stack.isEmpty { stack.append(s) } else { stack[stack.count-1] = s }
        render()
    }
    private func goBack() {
        selectedIndices.removeAll()
        if stack.count > 1 { stack.removeLast(); render() }
    }

    // ── render ────────────────────────────────────────────────────

    private func render() {
        let isListMode: Bool
        switch currentScreen {
        case .info: isListMode = false
        case .tracks, .localAlbum: isListMode = false
        default: isListMode = true
        }
        if !isHidden {
            onScreenChange?(isListMode)
        }
        
        sidebarRef?.scrollTarget = isListMode ? listScroll : nil
        if isListMode { sidebarRef?.setScrollProgress(0) }
        
        // clear the old rows' font references - prevents a crash
        listView?.subviews.compactMap { $0 as? MusicRowView }.forEach { row in
            row.subviews.compactMap { $0 as? NSTextField }.forEach { label in
                label.font = NSFont.systemFont(ofSize: 12)
                label.stringValue = ""
            }
        }
        listView?.removeFromSuperview()
        
        listScroll.documentView = nil
        listView = nil
        
        let lv = MusicListView(
            width: listScroll.bounds.width > 10 ? listScroll.bounds.width : bounds.width,
            onSelect: { [weak self] idx, cmd, shift in self?.handleSelect(idx, cmd: cmd, shift: shift) }
        )
        listView = lv

        switch currentScreen {

        case .menu:
            topBar.setTitle("· ·"); topBar.showBack(false)
            let libCount = allLibrary.filter { $0.source == "archive" }.count
            lv.section("library")
            lv.row(idx: 0, title: "jillem full archive",
                   sub: libCount > 0 ? "\(libCount) albums" : "loading...",
                   action: libCount > 0 ? { [weak self] in
                       guard let self else { return }
                       if self.allLibrary.isEmpty {
                           self.controller?.refresh()
                       } else {
                           let lib = self.allLibrary.filter { $0.source == "archive" }
                           self.push(.library(lib))
                       }
                   } : nil)
            
            lv.sectionButton("local") { [weak self] in
                self?.addLocalLibrary()
            }
            if localLibraries.isEmpty {
                lv.row(idx: 1, title: "no local folders", sub: "add a folder to get started", action: nil)
            } else {
                for (i, lib) in localLibraries.enumerated() {
                    let path = lib["path"] as? String ?? ""
                    let name = lib["name"] as? String ?? path
                    lv.row(idx: 100 + i, title: name, sub: path) { [weak self] in
                        self?.controller?.localBrowse(path: path)
                    }
                }
            }
            
            lv.section("playlists")
            if playlists.isEmpty {
                lv.row(idx: 2, title: "no playlists yet", sub: "use + to create one", action: nil)
            } else {
                for (i, pl) in playlists.enumerated() {
                    let p = pl
                    lv.row(idx: i + 3, title: pl.name, sub: "\(pl.items.count) albums") { [weak self] in
                        self?.push(.playlist(p))
                    }
                }
            }
            lv.section("queue")
            lv.row(idx: 99, title: "q", sub: "view queue") { [weak self] in self?.showQueue() }

        case .library(let items):
            topBar.setTitle("jillem full archive"); topBar.showBack(true)
            for (i, item) in items.enumerated() {
                let it = item; let sel = selectedIndices.contains(i)
                lv.row(idx: i, title: item.title, sub: nil, selected: sel,
                    action: nil,
                    doubleAction: { [weak self] in self?.controller?.browse(cacheIdx: it.cacheIdx) },
                    onHover: { [weak self] _ in self?.previewCover(for: it) },
                    onHoverEnd: { [weak self] in self?.clearPreviewCover() })
            }

        case .results(let q, let items):
            topBar.setTitle("\"\(q)\" — \(items.count) results"); topBar.showBack(true)
            if items.isEmpty { lv.row(idx: 0, title: "searching...", sub: nil, action: nil) }
            for (i, item) in items.enumerated() {
                let it = item; let sel = selectedIndices.contains(i)
                lv.row(idx: i, title: item.title, sub: item.source, selected: sel,
                    action: nil,
                    doubleAction: { [weak self] in self?.controller?.browse(cacheIdx: it.cacheIdx) },
                    onHover: { [weak self] _ in self?.previewCover(for: it) },
                    onHoverEnd: { [weak self] in self?.clearPreviewCover() })
            }
            
        case .tracks(let albumIdx, let title, _, let items, let source):
            topBar.setTitle(title); topBar.showBack(true)
            if items.isEmpty {
                lv.row(idx: 0, title: "loading tracks...", sub: nil, action: nil)
            } else {
                for item in items {
                    let n = item.n; let ai = albumIdx
                    let numTitle = "\(n + 1).  \(item.title)"
                    let sub = item.duration.isEmpty ? nil : item.duration
                    lv.row(idx: n, title: numTitle, sub: sub,
                           selected: selectedIndices.contains(n),
                           action: nil,
                           doubleAction: { [weak self] in
                               self?.controller?.playTrackWithContext(
                                   cacheIdx: ai, n: n, tracks: items, source: source)
                           })
                }
            }

        case .info(_, let title, let text):
            topBar.setTitle(title); topBar.showBack(true)
            lv.infoText(text)

        case .queue(let items, let cur):
            topBar.setTitle("queue · \(items.count)"); topBar.showBack(true)
            if items.isEmpty {
                lv.row(idx: 0, title: "queue is empty", sub: "use + to add albums", action: nil)
            }
            for (i, item) in items.enumerated() {
                let marker = i == cur ? "> " : "   "
                lv.row(idx: i, title: marker + item.title, sub: item.source, action: nil)
            }

        case .playlist(let pl):
            topBar.setTitle(pl.name); topBar.showBack(true)
            if pl.items.isEmpty {
                lv.row(idx: 0, title: "playlist is empty", sub: nil, action: nil)
            }
            for (i, entry) in pl.items.enumerated() {
                let idx = entry.cacheIdx
                lv.row(idx: i, title: entry.title, sub: entry.source) { [weak self] in
                    self?.controller?.play(cacheIdx: idx)
                }
            }
            lv.section("")
            let plId = pl.id
            lv.row(idx: 99, title: "play all", sub: nil) { [weak self] in
                self?.controller?.playPlaylist(id: plId)
            }
            lv.row(idx: 100, title: "delete", sub: nil) { [weak self] in
                self?.deletePlaylist(pl.id)
            }

        case .localItems(let path, let name, let items):
            topBar.setTitle(name); topBar.showBack(true)
            if items.isEmpty {
                lv.row(idx: 0, title: "empty folder", sub: nil, action: nil)
            }
            for (i, item) in items.enumerated() {
                let type = item["type"] as? String ?? ""
                let itemName = item["name"] as? String ?? ""
                let itemPath = item["path"] as? String ?? ""
                
                if type == "album" {
                    let tracks = item["tracks"] as? [[String: Any]] ?? []
                    lv.row(idx: i, title: itemName, sub: "\(tracks.count) tracks") { [weak self] in
                        self?.push(.localAlbum(itemPath, itemName, tracks, item["cover"] as? String))
                    }
                } else {
                    lv.row(idx: i, title: itemName + "/", sub: nil) { [weak self] in
                        self?.controller?.localBrowse(path: itemPath)
                    }
                }
            }
            lv.section("")
            lv.row(idx: 998, title: "play all", sub: nil) { [weak self] in
                var allTracks: [[String: Any]] = []
                for item in items {
                    if let tracks = item["tracks"] as? [[String: Any]] {
                        allTracks.append(contentsOf: tracks)
                    }
                }
                guard !allTracks.isEmpty else { return }
                if let first = allTracks.first, let firstPath = first["local_path"] as? String {
                    self?.controller?.playLocalWithContext(path: firstPath, tracks: allTracks, trackN: 0)
                }
            }
            lv.row(idx: 999, title: "remove from library", sub: nil) { [weak self] in
                self?.controller?.localRemove(path: path)
                self?.localLibraries.removeAll { ($0["path"] as? String) == path }
                self?.goBack()
            }

        case .localAlbum(let albumPath, let name, let tracks, _):
            topBar.setTitle(name); topBar.showBack(true)
            if tracks.isEmpty {
                lv.row(idx: 0, title: "no tracks", sub: nil, action: nil)
            }
            for (i, t) in tracks.enumerated() {
                let title = t["title"] as? String ?? "Track \(i+1)"
                let numTitle = "\(i + 1).  \(title)"
                let localPath = t["local_path"] as? String ?? ""
                lv.row(idx: i, title: numTitle, sub: nil,
                    selected: selectedIndices.contains(i),
                    action: nil,
                    doubleAction: { [weak self] in
                        self?.controller?.playLocalWithContext(path: localPath, tracks: tracks, trackN: i)
                    })
            }
            lv.section("")
            lv.row(idx: 99, title: "play all", sub: nil) { [weak self] in
                if let first = tracks.first, let firstPath = first["local_path"] as? String {
                    self?.controller?.playLocalWithContext(path: firstPath, tracks: tracks, trackN: 0)
                }
            }
            lv.row(idx: 100, title: "remove from library", sub: nil) { [weak self] in
                self?.controller?.localRemove(path: albumPath)
                self?.goBack()
            }
        }
        lv.finish(scrollView: listScroll)
        lv.refreshFonts()
    }
    
    private func addLocalLibrary() {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let overlayWin = appDelegate.overlayWin,
              let contentView = overlayWin.contentView else { return }
        
        if contentView.subviews.contains(where: { $0 is FileBrowserPanel }) { return }
        
        // Hide the music panel
        self.isHidden = true
        
        let padL: CGFloat = PhotonFont.chromeValue(40)
        let padR: CGFloat = IconBarFit.panelPadR(padL: 40)
        let padT: CGFloat = PhotonFont.chromeValue(9)
        let base = contentView.bounds
        let frame = CGRect(
            x: base.minX + padL,
            y: base.minY + padT,
            width: base.width - padL - padR,
            height: base.height - padT * 2
        )
        
        let browser = FileBrowserPanel(frame: frame)
        browser.wantsLayer = true
        browser.layer?.backgroundColor = NSColor.clear.cgColor
        browser.autoresizingMask = [.width, .height]
        
        browser.onClose = { [weak self, weak browser] in
            browser?.removeFromSuperview()
            appDelegate.isShowingInputPanel = false
            overlayWin.ignoresMouseEvents = false
            appDelegate.setEventTapEnabled(true)
            self?.isHidden = false
        }

        browser.onSelect = { [weak self, weak browser] path in
            browser?.onClose?()
            self?.controller?.localAdd(path: path)
        }
        
        browser.onSelectFolder = { [weak self, weak browser] path in
            browser?.onClose?()
            self?.controller?.localAdd(path: path)
        }
        
        contentView.addSubview(browser)
        
        appDelegate.isShowingInputPanel = true
        appDelegate.setEventTapEnabled(false)
        overlayWin.ignoresMouseEvents = false
        
        browser.loadPath(NSHomeDirectory() + "/Music")
        
        // capture the token and remove it on close - a discarded
        // token leaks one permanent app-wide keyDown listener per open
        var escMonitor: Any?
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak browser] event in
            if event.keyCode == 53, browser?.superview != nil, event.window === browser?.window {
                browser?.onClose?()
                return nil
            }
            return event
        }
        let previousOnClose = browser.onClose
        browser.onClose = {
            if let monitor = escMonitor {
                NSEvent.removeMonitor(monitor)
                escMonitor = nil
            }
            previousOnClose?()
        }
    }
    
    private func previewCover(for item: MusicItem) {
        guard let coverURL = item.cover else { return }
        hoverCoverTimer?.invalidate()
        hoverCoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.onHoverCover?(coverURL)
        }
    }

    private func clearPreviewCover() {
        hoverCoverTimer?.invalidate()
        onHoverCoverEnd?()
    }

    // ── multi-select ──────────────────────────────────────────────

    private func handleSelect(_ idx: Int, cmd: Bool, shift: Bool) {
        if cmd {
            if selectedIndices.contains(idx) { selectedIndices.remove(idx) }
            else { selectedIndices.insert(idx) }
        } else if shift, let last = selectedIndices.max() {
            let lo = min(last, idx); let hi = max(last, idx)
            (lo...hi).forEach { selectedIndices.insert($0) }
        } else {
            if selectedIndices == [idx] { selectedIndices.removeAll() }
            else { selectedIndices = [idx] }
        }
        botBar.setSelectionCount(selectedIndices.count)
        
        // Save the scroll position
        let savedScroll = listScroll.contentView.bounds.origin
        
        render()
        
        // restore the scroll position
        listScroll.contentView.setBoundsOrigin(savedScroll)
    }

    // ── actions ───────────────────────────────────────────────────

    private func playOrPauseSelection() {
        if selectedIndices.isEmpty {
            controller?.pause(); return
        }
        playSelection()
    }

    private func playSelection() {
        let sorted = selectedIndices.sorted()
        switch currentScreen {
        case .tracks(let albumIdx, _, _, let items, let source):
            if let first = sorted.first {
                controller?.playTrackWithContext(
                    cacheIdx: albumIdx, n: first, tracks: items, source: source)
            }
        case .library(let items), .results(_, let items):
            if let first = sorted.first, first < items.count {
                controller?.play(cacheIdx: items[first].cacheIdx)
            }
        default: controller?.pause()
        }
    }

    private func queueSelection() {
        let sorted = selectedIndices.sorted()
        switch currentScreen {
        case .tracks(let albumIdx, _, _, let tracks, _):
            for n in sorted where n < tracks.count {
                controller?.queueTrack(cacheIdx: albumIdx, trackN: n)
            }
        case .library(let items), .results(_, let items):
            for i in sorted where i < items.count {
                controller?.queueAlbum(cacheIdx: items[i].cacheIdx)
            }
        default: break
        }
    }

    private func doSearch(_ q: String) {
        searchQuery = q
        selectedIndices.removeAll()
        push(.results(q, []))
        controller?.search(q)
    }

    private func showQueue() {
        controller?.queueList()
        push(.queue([], -1))
    }

    private func actionAdd() {
        guard case .tracks(let albumIdx, _, _, _, _) = currentScreen else {
            // outside tracks, still show the menu; just add to queue/playlist
            showAddMenu(cacheIdx: nil)
            return
        }
        showAddMenu(cacheIdx: albumIdx)
    }

    private func showAddMenu(cacheIdx: Int?) {
        subviews.first(where: { $0 is AddMenuView })?.removeFromSuperview()
        
        let menuW: CGFloat = PhotonFont.chromeCharW * 20
        let origin = topBar.addButtonOriginInPanel
        var menuX = origin.x
        if menuX + menuW > bounds.width - 10 { menuX = bounds.width - menuW - 10 }
        
        let menu = AddMenuView(playlists: playlists,
                               frame: CGRect(x: menuX, y: 0, width: menuW, height: 400))
        menu.frame.origin.y = origin.y - menu.totalHeight - 4
        
        menu.alphaValue = 0
        menu.onSelect = { [weak self] action in
            switch action {
            case .queue:
                if let idx = cacheIdx {
                    self?.controller?.queueAlbum(cacheIdx: idx)
                } else {
                    self?.addAllToQueue()
                }
            case .playlist(let id):
                if let idx = cacheIdx {
                    self?.controller?.addToPlaylist(id: id, cacheIdx: idx)
                } else {
                    self?.addAllToPlaylist(id)
                }
            case .newPlaylist:
                self?.actionNewPlaylist()
            case .dismiss:
                break
            }
        }
        menu.onDismiss = { [weak self] in
            self?.subviews.first(where: { $0 is AddMenuView })?.removeFromSuperview()
        }
        addSubview(menu)
        
        // same discarded-token leak as the other monitors - remove on
        // dismiss (dismiss() funnels through onDismiss)
        var escMonitor: Any?
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak menu] event in
            if event.keyCode == 53, event.window === menu?.window {
                menu?.dismiss()
                return nil
            }
            return event
        }
        let previousOnDismiss = menu.onDismiss
        menu.onDismiss = {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            previousOnDismiss?()
        }
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            menu.animator().alphaValue = 1
        }
    }
    
    private func addAllToQueue() {
        switch currentScreen {
        case .tracks(let albumIdx, _, _, let tracks, _):
            for t in tracks { controller?.queueTrack(cacheIdx: albumIdx, trackN: t.n) }
        case .library(let items), .results(_, let items):
            for item in items { controller?.queueAlbum(cacheIdx: item.cacheIdx) }
        default: break
        }
    }

    private func addAllToPlaylist(_ plId: String) {
        switch currentScreen {
        case .tracks(let albumIdx, _, _, _, _):
            controller?.addToPlaylist(id: plId, cacheIdx: albumIdx)
        case .library(let items), .results(_, let items):
            for item in items { controller?.addToPlaylist(id: plId, cacheIdx: item.cacheIdx) }
        default: break
        }
    }
    
    private func actionInfo() {
        if case .tracks(let albumIdx, _, _, _, _) = currentScreen {
            controller?.info(cacheIdx: albumIdx)
        }
    }
    
    private func toggleDataMode() {
        guard let mc = controller else { return }
        let newMode = mc.currentDataMode == "" ? "∂" : ""
        mc.currentDataMode = newMode
        mc.setDataMode(newMode)
        botBar.setDataMode(newMode)
    }

    private func actionNewPlaylist() {
        guard let appDelegate = NSApp.delegate as? AppDelegate, !appDelegate.isShowingInputPanel else { return }
        
        guard let parentWin = window else { return }
        
        let pw: CGFloat = 420; let ph: CGFloat = 54
        let parentFrame = parentWin.frame
        let px = parentFrame.midX - pw / 2
        let py = parentFrame.maxY - 100
        
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
        tf.placeholderString = "playlist title"
        tf.target = self
        tf.action = #selector(commitPlaylist(_:))
        
        bg.addSubview(tf)
        panel.contentView = bg
        
        // eventTap off
        appDelegate.isShowingInputPanel = true
        appDelegate.setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = true
        
        // re-enable eventTap when the panel closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel, queue: .main
        ) { [weak parentWin] _ in
            appDelegate.isShowingInputPanel = false
            appDelegate.setEventTapEnabled(true)
            parentWin?.ignoresMouseEvents = false
        }
        
        tf.delegate = self
        panel.installStereoIfNeeded(parent: parentWin)
        panel.makeKeyAndOrderFront(nil)
        panel.assertKeyAndFocus(tf)
    }
    
    @objc private func commitPlaylist(_ sender: NSTextField) {
        let name = sender.stringValue.trimmingCharacters(in: .whitespaces)
        sender.window?.close()
        guard !name.isEmpty else { return }
        controller?.newPlaylist(name: name)
    }
    
    private func deletePlaylist(_ plId: String) {
        playlists.removeAll { $0.id == plId }
        controller?.deletePlaylist(id: plId)
        goBack()
    }
}

// ================================================================
//  MusicTopBar - back/title/search bar
// ================================================================

final class MusicTopBar: NSView {

    var onBack:   (() -> Void)?
    var onClose:  (() -> Void)?
    var onSearch: ((String) -> Void)?
    var onAdd:    (() -> Void)?
    var onInfo:   (() -> Void)?
    var onNewPl:  (() -> Void)?
    var onAddLocal: (() -> Void)?
    var addButtonOriginInPanel: CGPoint {
        let frameInTopBar = addBtn.frame
        let pointInPanel = convert(CGPoint(x: frameInTopBar.maxX, y: frameInTopBar.minY), to: superview)
        return pointInPanel
    }

    private let backBtn   = MusicBtn("↰",      hover: "back")
    private let addBtn    = MusicBtn("♥",      hover: "+add")
    private let infoBtn   = MusicBtn("◊",      hover: "info")
    private let plBtn     = MusicBtn("",    hover: "playlist")
    private let closeBtn  = MusicBtn("×",      hover: "close")
    private let searchBtn = MusicBtn("◌", hover: "search")
    private let titleLayer = CATextLayer()

    // Floating search panel (separate key window)
    private var searchPanel: NSPanel?
    private var searchField: NSTextField?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        backBtn.expandsLeftToRight = true
        backBtn.tap   = { [weak self] in self?.onBack?() }
        closeBtn.tap  = { [weak self] in self?.onClose?() }
        addBtn.tap    = { [weak self] in self?.onAdd?() }
        infoBtn.tap   = { [weak self] in self?.onInfo?() }
        plBtn.tap     = { [weak self] in self?.onNewPl?() }
        searchBtn.tap = { [weak self] in self?.openSearchPanel() }

        titleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped = false
        titleLayer.truncationMode = .end
        titleLayer.foregroundColor = NSColor.white.cgColor
        titleLayer.font = PhotonFont.chromeCt()
        if titleLayer.fontSize != PhotonFont.chromeSize { titleLayer.fontSize = PhotonFont.chromeSize }
        titleLayer.shadowColor = NSColor.black.cgColor
        titleLayer.shadowRadius = PPController.shadowRadius
        titleLayer.shadowOpacity = PPController.shadowOpacity
        titleLayer.shadowOffset = .zero
        layer?.addSublayer(titleLayer)

        for v in [backBtn, titleLayer, searchBtn, addBtn, infoBtn, plBtn, closeBtn] {
            if let btn = v as? NSView { addSubview(btn) }
        }
        
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.titleLayer.font = PhotonFont.chromeCt()
            if self.titleLayer.fontSize != PhotonFont.chromeSize { self.titleLayer.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true
        }
        
        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self, self.window != nil else { return }
            let newFont = PhotonFont.chromeCtDriven(view: self, profile: .title)
            PhotonFont.setIfChanged(newFont, on: self.titleLayer)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let h = bounds.height; let pad: CGFloat = 4
        // Back expands left to right from a pinned origin; IconBarFit keeps equal gaps between glyph ink edges, live widths, so a hover title only pushes the slots left of it.
        backBtn.frame = CGRect(x: pad, y: 0, width: backBtn.frame.width, height: h)
        let rightBtns = [closeBtn, plBtn, infoBtn, addBtn, searchBtn] as [MusicBtn]
        let frames = IconBarFit.trailingFrames(right: bounds.width - pad, height: h, gap: IconBarFit.standardGap, buttons: rightBtns.map { IconBarFit.Slot(width: $0.frame.width, ink: $0.inkWidth) })
        for (btn, f) in zip(rightBtns, frames) { btn.frame = f }
        let lineH = PhotonFont.chromeLineH
        titleLayer.frame = CGRect(x: backBtn.frame.maxX + pad, y: (h - lineH) / 2, width: (frames.last?.minX ?? (bounds.width - pad)) - backBtn.frame.maxX - pad - pad, height: lineH)
    }

    func setTitle(_ t: String) { titleLayer.string = t }
    func showBack(_ b: Bool)   { backBtn.isHidden = !b }

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
        tf.placeholderString = "search albums, artists..."
        tf.target = self; tf.action = #selector(commitSearch)

        bg.addSubview(tf)
        panel.contentView = bg
        searchField = tf; searchPanel = panel
        SearchBarFit.install(panel: panel, field: tf, anchor: .center, host: parentWin)

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
        let q = searchField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        searchPanel?.close(); searchPanel = nil; searchField = nil
        guard !q.isEmpty else { return }
        titleLayer.string = "\"\(q)\""
        onSearch?(q)
    }
    
    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }
}

// ================================================================
//  MusicBotBar - now-playing bar
// ================================================================

final class MusicBotBar: NSView {

    var onPrev:     (() -> Void)?
    var onPlayPause:(() -> Void)?
    var onNext:     (() -> Void)?
    var onQueue:    (() -> Void)?
    var onQueueSel: (() -> Void)?
    var onDataMode: (() -> Void)?

    private let prevBtn  = MusicBtn("←",  hover: "prev")
    private let playBtn  = MusicBtn("∆",  hover: "play")
    private let nextBtn  = MusicBtn("→",  hover: "next")
    private let qBtn     = MusicBtn("",  hover: "queue")
    private let dataModeBtn = MusicBtn("", hover: "wi-fi mode")
    private let titleLayer = CATextLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        prevBtn.tap  = { [weak self] in self?.onPrev?() }
        playBtn.tap  = { [weak self] in self?.onPlayPause?() }
        nextBtn.tap  = { [weak self] in self?.onNext?() }
        qBtn.tap     = { [weak self] in self?.onQueue?() }
        dataModeBtn.tap = { [weak self] in self?.onDataMode?() }

        titleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped = false
        titleLayer.truncationMode = .end
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(1.0).cgColor
        titleLayer.font = PhotonFont.chromeCt()
        if titleLayer.fontSize != PhotonFont.chromeSize { titleLayer.fontSize = PhotonFont.chromeSize }
        titleLayer.string = " …"
        titleLayer.shadowColor = NSColor.black.cgColor
        titleLayer.shadowRadius = PPController.shadowRadius
        titleLayer.shadowOpacity = PPController.shadowOpacity
        titleLayer.shadowOffset = .zero
        layer?.addSublayer(titleLayer)

        for v in [prevBtn, playBtn, nextBtn, titleLayer, dataModeBtn, qBtn] {
            if let btn = v as? NSView { addSubview(btn) }
        }
        
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.titleLayer.font = PhotonFont.chromeCt()
            if self.titleLayer.fontSize != PhotonFont.chromeSize { self.titleLayer.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true
        }
        
        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self, self.window != nil else { return }
            let newFont = PhotonFont.chromeCtDriven(view: self, profile: .title)
            PhotonFont.setIfChanged(newFont, on: self.titleLayer)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height; let pad: CGFloat = 4
        let lineH = PhotonFont.chromeLineH
        
        prevBtn.frame = CGRect(x: pad, y: 0, width: prevBtn.frame.width, height: h)
        playBtn.frame = CGRect(x: prevBtn.frame.maxX + pad, y: 0, width: playBtn.frame.width, height: h)
        nextBtn.frame = CGRect(x: playBtn.frame.maxX + pad, y: 0, width: nextBtn.frame.width, height: h)
        
        qBtn.frame = CGRect(x: bounds.width - qBtn.frame.width - pad, y: 0, width: qBtn.frame.width, height: h)
        dataModeBtn.frame = CGRect(x: qBtn.frame.minX - dataModeBtn.frame.width - pad, y: 0, width: dataModeBtn.frame.width, height: h)
        
        let tx = nextBtn.frame.maxX + pad
        titleLayer.frame = CGRect(x: tx, y: (h - lineH) / 2,
                                   width: dataModeBtn.frame.minX - tx - pad, height: lineH)
    }

    func setTitle(_ t: String)     { titleLayer.string = t.isEmpty ? "—" : t }
    func setPlaying(_ p: Bool)     { playBtn.setShortLabel(p ? "∆" : "∆", hover: p ? "pause" : "play") }
    func setQueueCount(_ n: Int)   { qBtn.setShortLabel(n > 0 ? "q\(n)" : "q", hover: "queue · \(n)") }
    func setSelectionCount(_ n: Int) {
        playBtn.setShortLabel("∆", hover: n > 0 ? "play \(n) selected" : "play")
    }
    func setDataMode(_ mode: String) {
        dataModeBtn.setShortLabel(mode, hover: mode == "" ? "wi-fi mode" : "data mode")
    }
    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }
}

// ================================================================
//  MusicListView - scroll content, row pool
// ================================================================

final class MusicListView: NSView {

    private let rowH: CGFloat = PhotonFont.chromeLineH
    private let secH: CGFloat = PhotonFont.chromeLineH
    private var nextY: CGFloat = 0
    private var onSelect: ((Int, Bool, Bool) -> Void)?
    private var addedLayers: [CALayer] = []
    
    // Virtual scrolling
    private struct RowDef {
        let idx: Int
        let title: String
        let sub: String?
        var selected: Bool
        let action: (() -> Void)?
        let doubleAction: (() -> Void)?
        let onHover: ((Int) -> Void)?
        let onHoverEnd: (() -> Void)?
        let y: CGFloat
    }
    private var rowDefs: [RowDef] = []
    private var rowPool: [MusicRowView] = []
    private var visibleStart: Int = 0
    private var visibleEnd: Int = 0
    private var lastKnownOffset: CGFloat = 0
    private weak var scrollView: NSScrollView?

    init(width: CGFloat, onSelect: ((Int, Bool, Bool) -> Void)?) {
        self.onSelect = onSelect
        super.init(frame: CGRect(x: 0, y: 0, width: max(width, 100), height: 800))
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    func section(_ title: String) {
        let layer = CATextLayer()
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.isWrapped = false
        layer.foregroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
        layer.font = PhotonFont.chromeCt()
        if layer.fontSize != PhotonFont.chromeSize { layer.fontSize = PhotonFont.chromeSize }
        layer.string = title.uppercased()
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowRadius = PPController.shadowRadius
        layer.shadowOpacity = PPController.shadowOpacity
        layer.shadowOffset = .zero
        self.layer?.addSublayer(layer)
        addedLayers.append(layer)
        layer.frame = CGRect(x: 12, y: nextY, width: bounds.width - 24, height: secH)
        nextY += secH + 2
    }

    func sectionButton(_ title: String, action: @escaping () -> Void) {
        let btn = MusicSectionButton(title: title, action: action)
        addSubview(btn)
        btn.frame = CGRect(x: 0, y: nextY, width: bounds.width, height: secH)
        nextY += secH + 2
    }

    func row(idx: Int, title: String, sub: String?, selected: Bool = false,
             action: (() -> Void)?, doubleAction: (() -> Void)? = nil,
             onHover: ((Int) -> Void)? = nil, onHoverEnd: (() -> Void)? = nil) {
        rowDefs.append(RowDef(idx: idx, title: title, sub: sub, selected: selected,
                              action: action, doubleAction: doubleAction,
                              onHover: onHover, onHoverEnd: onHoverEnd,
                              y: nextY))
        nextY += rowH + 1
    }

    func infoText(_ text: String) {
        let layer = CATextLayer()
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.isWrapped = true
        layer.foregroundColor = NSColor.white.withAlphaComponent(1.0).cgColor
        layer.font = PhotonFont.chromeCt()
        if layer.fontSize != PhotonFont.chromeSize { layer.fontSize = PhotonFont.chromeSize }
        layer.string = text
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowRadius = PPController.shadowRadius
        layer.shadowOpacity = PPController.shadowOpacity
        layer.shadowOffset = .zero
        let w = bounds.width - 24
        let nsFont = PhotonFont.chromeNs()
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: w, height: 9999),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: nsFont]
        )
        let h = rect.height + 16
        self.layer?.addSublayer(layer)
        addedLayers.append(layer)
        layer.frame = CGRect(x: 12, y: nextY, width: w, height: h)
        nextY += h + 8
    }

    func refreshFonts() {
        addedLayers.forEach { layer in
            if let textLayer = layer as? CATextLayer {
                textLayer.font = PhotonFont.chromeCt()
                if textLayer.fontSize != PhotonFont.chromeSize { textLayer.fontSize = PhotonFont.chromeSize }
            }
        }
        // update the pooled rows too
        rowPool.forEach { $0.needsLayout = true }
    }

    func finish(scrollView: NSScrollView) {
        self.scrollView = scrollView
        let totalH = max(nextY + 8, scrollView.bounds.height + 1)
        frame = CGRect(x: 0, y: 0, width: bounds.width, height: totalH)
        scrollView.documentView = self
        
        // Scroll observer
        NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        
        layoutVisibleRows()
    }
    
    func clearLayers() {
        addedLayers.forEach { $0.removeFromSuperlayer() }
        addedLayers.removeAll()
    }

    // MARK: - Virtual Scrolling
    
    override func layout() {
        super.layout()
        if scrollView != nil { layoutVisibleRows() }
    }
    
    @objc private func scrollChanged() {
        guard let sv = scrollView else { return }
        let offset = sv.contentView.bounds.origin.y
        guard abs(offset - lastKnownOffset) > rowH else { return }
        lastKnownOffset = offset
        layoutVisibleRows()
    }
    
    private var visibleRowViews: [Int: MusicRowView] = [:]
    private func layoutVisibleRows() {
        guard let sv = scrollView, !rowDefs.isEmpty else { return }
        
        let visibleRect = sv.contentView.bounds
        let buffer = 3
        let start = max(0, Int(visibleRect.minY / (rowH + 1)) - buffer)
        let end = min(rowDefs.count, Int(visibleRect.maxY / (rowH + 1)) + buffer + 1)
        
        guard start != visibleStart || end != visibleEnd else { return }
        
        // Preserve overlap; only rows leaving the viewport return to the pool.
        for index in Array(visibleRowViews.keys) where index < start || index >= end {
            if let row = visibleRowViews.removeValue(forKey: index) {
                row.removeFromSuperview()
                rowPool.append(row)
            }
        }

        // Create/pool rows
        for i in start..<end where visibleRowViews[i] == nil {
            let d = rowDefs[i]
            let y = d.y
            
            let row: MusicRowView
            if let pooled = rowPool.popLast() {
                row = pooled
                row.reconfigure(
                    idx: d.idx, title: d.title, sub: d.sub, selected: d.selected,
                    action: d.action, doubleAction: d.doubleAction,
                    onSelect: onSelect,
                    onHover: d.onHover, onHoverEnd: d.onHoverEnd
                )
            } else {
                row = MusicRowView(
                    idx: d.idx, title: d.title, sub: d.sub, height: rowH,
                    selected: d.selected, action: d.action, doubleAction: d.doubleAction,
                    onSelect: onSelect,
                    onHover: d.onHover, onHoverEnd: d.onHoverEnd
                )
            }
            row.frame = CGRect(x: 0, y: y, width: bounds.width, height: rowH)
            addSubview(row)
            visibleRowViews[i] = row
        }
        
        visibleStart = start
        visibleEnd = end
    }
}

final class MusicSectionButton: NSView {
    private let titleLayer = CATextLayer()
    private let action: () -> Void
    
    init(title: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        
        titleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped = false
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.5).cgColor
        titleLayer.font = PhotonFont.chromeCt()
        if titleLayer.fontSize != PhotonFont.chromeSize { titleLayer.fontSize = PhotonFont.chromeSize }
        titleLayer.string = title.uppercased()
        layer?.addSublayer(titleLayer)
        
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func layout() {
        super.layout()
        titleLayer.frame = CGRect(x: 12, y: 0, width: bounds.width - 24, height: bounds.height)
    }
    
    override func mouseEntered(with e: NSEvent) {
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.6).cgColor
    }
    override func mouseExited(with e: NSEvent) {
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.28).cgColor
    }
    override func mouseUp(with e: NSEvent) {
        action()
    }
}

// ================================================================
//  MusicRowView - single list row
// ================================================================

final class MusicRowView: NSView {

    private var action: (() -> Void)?
    private var doubleAction: (() -> Void)?
    private var onSelect: ((Int, Bool, Bool) -> Void)?
    var rowIdx: Int
    private var hovered = false
    private var selected: Bool
    
    private var onHover: ((Int) -> Void)?
    private var onHoverEnd: (() -> Void)?

    private let titleLayer = CATextLayer()
    private let subLayer = CATextLayer()
    private var hasSub = false
    private var variationToken: UUID?

    init(idx: Int, title: String, sub: String?, height: CGFloat,
         selected: Bool, action: (() -> Void)?, doubleAction: (() -> Void)? = nil,
         onSelect: ((Int, Bool, Bool) -> Void)?,
         onHover: ((Int) -> Void)? = nil, onHoverEnd: (() -> Void)? = nil) {
        self.rowIdx = idx
        self.action = action
        self.doubleAction = doubleAction
        self.onSelect = onSelect
        self.onHover = onHover
        self.onHoverEnd = onHoverEnd
        self.selected = selected
        super.init(frame: .zero)
        wantsLayer = true

        // Title layer
        titleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped = false
        titleLayer.truncationMode = .end
        titleLayer.foregroundColor = NSColor.white.cgColor
        titleLayer.font = selected ? PhotonFont.chromeCt(wght: 700) : PhotonFont.chromeCt()
        if titleLayer.fontSize != PhotonFont.chromeSize { titleLayer.fontSize = PhotonFont.chromeSize }
        titleLayer.string = title
        titleLayer.shadowColor = NSColor.black.cgColor
        titleLayer.shadowRadius = PPController.shadowRadius
        titleLayer.shadowOpacity = PPController.shadowOpacity
        titleLayer.shadowOffset = .zero
        layer?.addSublayer(titleLayer)

        // Sub layer
        if let sub, !sub.isEmpty {
            hasSub = true
            subLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            subLayer.isWrapped = false
            subLayer.truncationMode = .end
            subLayer.foregroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            subLayer.font = PhotonFont.chromeCt()
            if subLayer.fontSize != PhotonFont.chromeSize { subLayer.fontSize = PhotonFont.chromeSize }
            subLayer.string = sub
            subLayer.alignmentMode = .right
            subLayer.shadowColor = NSColor.black.cgColor
            subLayer.shadowRadius = PPController.shadowRadius
            subLayer.shadowOpacity = PPController.shadowOpacity
            subLayer.shadowOffset = .zero
            layer?.addSublayer(subLayer)
        }

        if action != nil || doubleAction != nil || onSelect != nil || onHover != nil {
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                owner: self, userInfo: nil))
        }
        
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            self?.needsLayout = true
            DispatchQueue.main.async { self?.updateFontVariation() }
        }
        
        // single listener - tracked by token, removed in deinit
        variationToken = VariationBroadcaster.shared.addListener { [weak self] in
            DispatchQueue.main.async { self?.updateFontVariation() }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let h = bounds.height; let pad: CGFloat = 12
        let subW: CGFloat = hasSub ? 190 : 0
        
        titleLayer.frame = CGRect(x: pad, y: (h - PhotonFont.chromeLineH) / 2,
                                   width: bounds.width - subW - pad*2 - 4,
                                   height: PhotonFont.chromeLineH)
        if hasSub {
            subLayer.frame = CGRect(x: bounds.width - subW - pad, y: (h - PhotonFont.chromeLineH) / 2,
                                     width: subW, height: PhotonFont.chromeLineH)
        }
    }

    override func mouseEntered(with e: NSEvent) {
        hovered = true
        updateFontVariation()
        onHover?(rowIdx)
    }
    
    override func mouseMoved(with e: NSEvent) {
        if let winPt = window?.contentView?.convert(e.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        updateFontVariation()
    }

    override func mouseExited(with e: NSEvent) {
        hovered = false
        updateFontVariation()
        onHoverEnd?()
    }
    
    func reconfigure(idx: Int, title: String, sub: String?, selected: Bool,
                     action: (() -> Void)?, doubleAction: (() -> Void)? = nil,
                     onSelect: ((Int, Bool, Bool) -> Void)?,
                     onHover: ((Int) -> Void)? = nil, onHoverEnd: (() -> Void)? = nil) {
        self.rowIdx = idx
        self.selected = selected
        self.action = action
        self.doubleAction = doubleAction
        self.onSelect = onSelect
        self.onHover = onHover
        self.onHoverEnd = onHoverEnd
        
        titleLayer.string = title
        titleLayer.font = selected ? PhotonFont.chromeCt(wght: 700) : PhotonFont.chromeCt()
        titleLayer.foregroundColor = NSColor.white.cgColor
        
        if let sub, !sub.isEmpty {
            hasSub = true
            subLayer.string = sub
            subLayer.isHidden = false
        } else {
            hasSub = false
            subLayer.isHidden = true
        }
        
        updateFontVariation()
    }
    
    private func updateFontVariation() {
        guard isEffectivelyVisible else { return }; if selected {
            PhotonFont.setIfChanged(PhotonFont.chromeCt(wght: 700), on: titleLayer)
            titleLayer.setForegroundIfChanged(NSColor.white.cgColor)
            return
        }
        
        let p = verticalProximity(to: self, radius: 180)
        
        if p <= 0 && !hovered {
            PhotonFont.setIfChanged(PhotonFont.chromeCt(wght: 200, SIZE: PhotonFont.chromeSize * 0.85), on: titleLayer)
            titleLayer.setForegroundIfChanged((ScreenCaptureEngine.shared.currentColor(for: "subtitle") ?? .white).withAlphaComponent(0.45).cgColor)
            return
        }
        
        let curv = VariationBroadcaster.shared.curve(p, power: 2.0)
        let alpha: CGFloat = 0.45 + 0.55 * CGFloat(curv)
        
        let newFont = PhotonFont.chromeCtDriven(view: self, profile: .row)
        PhotonFont.setIfChanged(newFont, on: titleLayer)
        titleLayer.setForegroundIfChanged((ScreenCaptureEngine.shared.currentColor(for: "subtitle") ?? .white).withAlphaComponent(alpha).cgColor)
    }

    private func verticalProximity(to view: NSView, radius: CGFloat) -> CGFloat {
        guard let win = view.window else { return 0 }
        let center = view.convert(NSPoint(x: 0, y: view.bounds.midY), to: win.contentView)
        let dy = abs(VariationBroadcaster.shared.mouseWindowPt.y - center.y)
        return max(0, min(1, 1.0 - dy / radius))
    }

    override func mouseDown(with e: NSEvent) {
        titleLayer.font = PhotonFont.chromeCt(wght: 700)
    }
    override func mouseUp(with e: NSEvent) {
        let cmd   = e.modifierFlags.contains(.command)
        let shift = e.modifierFlags.contains(.shift)
        titleLayer.font = selected ? PhotonFont.chromeCt(wght: 700) : PhotonFont.chromeCt()
        if cmd || shift {
            onSelect?(rowIdx, cmd, shift)
        } else if e.clickCount == 2 {
            doubleAction?()
        } else {
           onSelect?(rowIdx, false, false)
           action?()
       }
    }
    
    deinit {
        if let token = variationToken {
            VariationBroadcaster.shared.removeListener(token)
        }
    }
}

// ================================================================
//  MusicBtn - label + hover tooltip expansion via variable font
// ================================================================

final class MusicBtn: NSView {
    var tap: (() -> Void)?

    private let textLayer = CATextLayer()
    private var shortLabel: String
    private var hoverLabel: String
    private var isHovered = false
    private var typeTimer: Timer?
    private var fadeTimer: Timer?

    /// WHY: back-style buttons expand the hover title left to right with the origin pinned, so the glyph never shifts.
    var expandsLeftToRight = false { didSet { textLayer.alignmentMode = expandsLeftToRight ? .left : .right } }

    init(_ short: String, hover: String) {
        self.shortLabel = short
        self.hoverLabel = hover
        super.init(frame: CGRect(x: 0, y: 0, width: PhotonFont.chromeValue(32), height: PhotonFont.chromeLineH))
        wantsLayer = true
        
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.isWrapped = false
        textLayer.foregroundColor = NSColor.white.withAlphaComponent(1.0).cgColor
        textLayer.font = PhotonFont.chromeCt()
        if textLayer.fontSize != PhotonFont.chromeSize { textLayer.fontSize = PhotonFont.chromeSize }
        textLayer.alignmentMode = .right
        textLayer.string = short
        textLayer.shadowColor = NSColor.black.cgColor
        textLayer.shadowRadius = PPController.shadowRadius
        textLayer.shadowOpacity = PPController.shadowOpacity
        textLayer.shadowOffset = .zero
        
        layer?.addSublayer(textLayer)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
        
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.textLayer.font = PhotonFont.chromeCt()
            if self.textLayer.fontSize != PhotonFont.chromeSize { self.textLayer.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true; self.superview?.needsLayout = true
        }
        
        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self, self.window != nil else { return }
            if !self.isHovered {
                // WHY: the driven face changes glyph widths with proximity; on a width change the bar must re-lay or ink overlaps.
                let widthBefore = self.inkWidth
                PhotonFont.setIfChanged(PhotonFont.chromeCtDriven(view: self, profile: .button), on: self.textLayer)
                if self.inkWidth != widthBefore { self.superview?.needsLayout = true }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// WHY: gaps must measure the font the layer renders (driven face swaps with proximity), not a parallel NSFont guess.
    private func measureInk(_ s: String) -> CGFloat {
        guard !s.isEmpty, let rawFont = textLayer.font else { return 0 }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: rawFont as! CTFont]))
        return max(CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).maxX)
    }
    var inkWidth: CGFloat { measureInk((textLayer.string as? String) ?? shortLabel) }

    func setLabel(_ s: String)  { shortLabel = s; if !isHovered { textLayer.string = s } }
    func setShortLabel(_ s: String, hover h: String) {
        shortLabel = s; hoverLabel = h
        if !isHovered { textLayer.string = s }
    }

    override func layout() {
        super.layout()
        textLayer.frame = bounds
    }

    /// When a container owns hover for its buttons (IPTVTopBar), the button's own tracking events
    /// are ignored so exactly one owner calls beginHover/endHover and they cannot fight.
    var externalHover = false
    override func mouseEntered(with e: NSEvent) { if !externalHover { beginHover() } }

    // Hover entry points are separate from NSEvent so a container can drive them from its own
    // mouse-moved tracking when a button's own tracking area does not deliver (IPTVTopBar).
    func beginHover() {
        if isHovered { return }
        isHovered = true
        fadeTimer?.invalidate()
        textLayer.foregroundColor = NSColor.white.cgColor
        
        typeTimer?.invalidate()
        let chars = Array(hoverLabel)
        var idx = 0
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            idx += 1
            let partial = String(chars.prefix(idx))
            self.textLayer.string = partial
            
            self.frame = IconBarFit.hoverFrame(current: self.frame, ink: self.measureInk(partial), minWidth: PhotonFont.chromeValue(32), textPad: PhotonFont.chromeValue(8), expandsLeftToRight: self.expandsLeftToRight)
            self.superview?.needsLayout = true
            
            if idx >= chars.count {
                t.invalidate()
                self.typeTimer = nil
            }
        }
    }

    override func mouseExited(with e: NSEvent) { if !externalHover { endHover() } }

    func endHover() {
        if !isHovered { return }
        isHovered = false
        typeTimer?.invalidate()
        
        let currentText = textLayer.string as? String ?? ""
        let chars = Array(currentText)
        guard !chars.isEmpty else { return }
        
        var idx = chars.count
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            idx -= 1
            if idx <= 0 {
                self.textLayer.string = self.shortLabel
                self.textLayer.foregroundColor = NSColor.white.withAlphaComponent(1.0).cgColor
                self.textLayer.font = PhotonFont.chromeCt()
                self.frame = IconBarFit.hoverFrame(current: self.frame, ink: 0, minWidth: PhotonFont.chromeValue(32), textPad: 0, expandsLeftToRight: self.expandsLeftToRight)
                self.superview?.needsLayout = true
                t.invalidate()
                self.fadeTimer = nil
            } else {
                let partial = String(chars.prefix(idx))
                self.textLayer.string = partial
                self.frame = IconBarFit.hoverFrame(current: self.frame, ink: self.measureInk(partial), minWidth: PhotonFont.chromeValue(32), textPad: PhotonFont.chromeValue(8), expandsLeftToRight: self.expandsLeftToRight)
                self.superview?.needsLayout = true
            }
        }
    }
    
    override func mouseDown(with e: NSEvent) {
        textLayer.foregroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
    }
    override func mouseUp(with e: NSEvent) {
        textLayer.foregroundColor = NSColor.white.cgColor
        tap?()
    }
}

//  +AddMenuView

final class AddMenuView: NSView {
    var onSelect: ((AddMenuAction) -> Void)?
    var onDismiss: (() -> Void)?
    var totalHeight: CGFloat { frame.height }
    enum AddMenuAction {
        case queue
        case playlist(String)
        case newPlaylist
        case dismiss
    }
    
    private let playlists: [Playlist]
    private var rows: [AddMenuRow] = []
    private var selectedIndex: Int = -1
    private let rowH: CGFloat = PhotonFont.chromeLineH + 2
    
    init(playlists: [Playlist], frame: CGRect) {
        self.playlists = playlists
        super.init(frame: frame)
        wantsLayer = true
        build()
    }
    required init?(coder: NSCoder) { fatalError() }
    
    private func build() {
        var y: CGFloat = 0
        
        // Close
        let closeRow = AddMenuRow(title: "close", indent: 0, action: .dismiss)
        closeRow.frame = CGRect(x: 0, y: y, width: bounds.width, height: rowH)
        closeRow.onTap = { [weak self] in self?.dismiss() }
        addSubview(closeRow)
        rows.append(closeRow)
        y += rowH
        
        // Add to Queue
        let qRow = AddMenuRow(title: "queue", indent: 0, action: .queue)
        qRow.frame = CGRect(x: 0, y: y, width: bounds.width, height: rowH)
        qRow.onTap = { [weak self] in self?.select(.queue) }
        addSubview(qRow)
        rows.append(qRow)
        y += rowH
        
        // Playlists
        if !playlists.isEmpty {
            for pl in playlists {
                let plRow = AddMenuRow(title: pl.name, indent: 2, action: .playlist(pl.id))
                plRow.frame = CGRect(x: 0, y: y, width: bounds.width, height: rowH)
                plRow.onTap = { [weak self] in self?.select(.playlist(pl.id)) }
                addSubview(plRow)
                rows.append(plRow)
                y += rowH
            }
        }
        
        // New playlist
        let newRow = AddMenuRow(title: "new playlist...", indent: 0, action: .newPlaylist)
        newRow.frame = CGRect(x: 0, y: y, width: bounds.width, height: rowH)
        newRow.onTap = { [weak self] in self?.select(.newPlaylist) }
        addSubview(newRow)
        rows.append(newRow)
        y += rowH
        
        frame.size.height = y
        
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    
    private func select(_ action: AddMenuAction) {
        onSelect?(action)
        dismiss()
    }
    
    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }) { [weak self] in
            self?.onDismiss?()
            self?.removeFromSuperview()
        }
    }
    
    override func mouseMoved(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        for (i, row) in rows.enumerated() {
            if row.frame.contains(pt) && row.isSelectable {
                selectedIndex = i
                row.highlight()
            } else {
                row.unhighlight()
            }
        }
    }
    
    override func mouseUp(with e: NSEvent) {
        if bounds.contains(convert(e.locationInWindow, from: nil)) { return }
        dismiss()
    }
}

// Add menu row
final class AddMenuRow: NSView {
    var onTap: (() -> Void)?
    var isSelectable = true
    
    private let titleLayer = CATextLayer()
    private let action: AddMenuView.AddMenuAction?
    private let indent: Int
    
    init(title: String, indent: Int, action: AddMenuView.AddMenuAction?) {
        self.indent = indent
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        
        titleLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped = false
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
        titleLayer.font = PhotonFont.chromeCt()
        if titleLayer.fontSize != PhotonFont.chromeSize { titleLayer.fontSize = PhotonFont.chromeSize }
        titleLayer.string = String(repeating: "  ", count: indent) + title
        titleLayer.alignmentMode = .right
        titleLayer.shadowColor = NSColor.black.cgColor
        titleLayer.shadowRadius = PPController.shadowRadius
        titleLayer.shadowOpacity = PPController.shadowOpacity
        titleLayer.shadowOffset = .zero
        layer?.addSublayer(titleLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func layout() {
        super.layout()
        titleLayer.frame = bounds
    }
    
    func highlight() {
        guard isSelectable else { return }
        titleLayer.foregroundColor = NSColor.white.cgColor
        titleLayer.font = PhotonFont.chromeCt(wght: 700)
    }
    
    func unhighlight() {
        titleLayer.foregroundColor = NSColor.white.withAlphaComponent(0.7).cgColor
        titleLayer.font = PhotonFont.chromeCt()
    }
    
    override func mouseUp(with e: NSEvent) {
        guard isSelectable else { return }
        onTap?()
    }
}

// ================================================================
//  MusicPanel - NSTextFieldDelegate extension
// ================================================================

extension MusicPanel: NSTextFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let tf = control as? NSTextField {
                commitPlaylist(tf)
            }
            return true
        }
        return false
    }
}


```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/MusicPanel.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='c671112da430988b090b17e1b9565d181c73993d60e7113365f05cfd4d2ab27f', 'pinned source changed: rebase and review, never bless silently'
for token in ['DraggableScrollView', 'MusicPanel', 'Screen', 'bind', 'updateScrollProgress', 'push', 'replaceTop', 'goBack', 'render', 'addLocalLibrary', 'previewCover', 'clearPreviewCover']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='c671112da430988b090b17e1b9565d181c73993d60e7113365f05cfd4d2ab27f'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-15: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-15: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
