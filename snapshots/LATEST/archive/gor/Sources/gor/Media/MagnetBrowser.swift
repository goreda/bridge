// Magnet metadata browser. No torrent content is fetched here.
import AppKit
import Foundation
import CoreFoundation
import Darwin
import WebKit

fileprivate struct MagnetResult: Decodable {
    let title: String
    let sizeBytes: Int64?
    let seeds: Int?
    let magnetUri: String?
    let uploadedAt: String?
    let uploadedLabel: String?
    let infoHash: String?
    let source: String
    let detailUrl: String
    // `seeds` is the source's own claim. Never shown as health (see MagnetVerdict).
    var claims: [String: Int] = [:]
    var verdict: MagnetVerdict? = nil

    var hasExecutableTitle: Bool {
        title.range(of: #"(?i)\.exe(?![a-z0-9])"#, options: .regularExpression) != nil
    }
}
// Health model, candidate "hoax-filter-1" (prereg 9b5daafc + two-window 26daa3f3).
// Claimed counts are source text; only verified fields describe a swarm.
fileprivate enum MagnetState: String, Decodable {
    case verified, unverifiedTimeout, unverifiedDisagreement, contradicted, dead
}
fileprivate struct MagnetVerdict: Decodable {
    let state: MagnetState
    let verifiedSeeds: Int?
    let verifiedPeers: Int
    var label: String {
        switch state {
        case .verified: return verifiedSeeds.map(String.init) ?? "seed ?"
        case .contradicted: return "x0"
        case .dead: return "dead"
        case .unverifiedDisagreement: return "unverified"
        case .unverifiedTimeout: return "no reply"
        }
    }
}
fileprivate struct MagnetProbe {
    enum Layer: Hashable { case udp, http, dht }
    let layer: Layer
    let seeders: Int?
    let peers: Int
}
fileprivate enum MagnetWindow { case positive, zero, inconclusive }
fileprivate struct MagnetProbeResult { let window: MagnetWindow; let seeds: Int?; let peers: Int }

fileprivate struct ProviderStatus: Decodable {
    let status: String
    let reason: String?
    let pending: [String]?
}
fileprivate struct SearchResponse: Decodable {
    let results: [MagnetResult]
    let pendingRows: [MagnetResult]
    let providers: [String: ProviderStatus]
}

// Direct JSON only. Refuse cross-host redirects before sending a query elsewhere.
private final class MagnetJSONRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

// Keep the first result at the top of the scroll view even when the list is short.
private final class MagnetResultStack: NSView {
    override var isFlipped: Bool { true }
}

// Diagnostic-only: never print dn, trackers, detail URL, title, or arbitrary xt text.
private enum MagnetSelectionTrace {
    static func log(_ reason: String, _ magnet: String?, trace: String = "handoff") {
        let raw = magnet.flatMap { URLComponents(string: $0)?.queryItems?.first(where: { $0.name == "xt" })?.value }
        let safe: String
        if let raw, raw.range(of: "^urn:btih:([0-9a-f]{40}|[a-z2-7]{32})$", options: [.regularExpression, .caseInsensitive]) != nil {
            safe = raw
        } else {
            safe = raw == nil ? "absent" : "redacted-invalid"
        }
        print("[magnet-select-diag] trace=\(trace) reason=\(reason) xt=\(safe)")
    }
}

// A separate full-height floating field follows gor's existing archive search
// style. The results panel remains in the video frame while the field is key.
//
// Scroll-wheel events aimed at this layer-backed list never reach the app-wide
// local monitor in PPController.setupAutoHide, so the idle timer faded the
// panel mid-scroll while plain mouse movement (which the monitor does see)
// kept it awake. Wake the same idle path from the scroll view itself.
final class GORActivityScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        (NSApp.delegate as? AppDelegate)?.controller?.wakeUI()
        super.scrollWheel(with: event)
    }
}

// Series tags written as s + 2 season digits + e + 2 episode digits
// ("s03e03", "S03E03"): after a picked episode plays to its end, the reopened
// search bar offers the next episode with the same tag spelling. Import-free
// pure value logic so the same source compiles into the swiftc test harness.
enum MagnetSeriesQuery {
    private static func isDigit(_ c: Character) -> Bool { c >= "0" && c <= "9" }
    private static func isWord(_ c: Character) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || isDigit(c) || c == "_"
    }
    /// First tag with token boundaries wins. The episode keeps its zero
    /// padding and the season never rolls; 99 has no next within the width.
    static func nextEpisode(_ query: String) -> String? {
        let c = Array(query)
        var i = 0
        while i + 6 <= c.count {
            if (c[i] == "s" || c[i] == "S"), isDigit(c[i + 1]), isDigit(c[i + 2]),
               (c[i + 3] == "e" || c[i + 3] == "E"), isDigit(c[i + 4]), isDigit(c[i + 5]),
               (i == 0 || !isWord(c[i - 1])), (i + 6 == c.count || !isWord(c[i + 6])) {
                guard let tens = c[i + 4].wholeNumberValue, let ones = c[i + 5].wholeNumberValue else { return nil }
                let n = tens * 10 + ones
                guard n < 99 else { return nil }
                var out = c
                out[i + 4] = Character(String((n + 1) / 10))
                out[i + 5] = Character(String((n + 1) % 10))
                return String(out)
            }
            i += 1
        }
        return nil
    }
}

// Owns the next-episode advance across the magnet panel's lifecycle. The
// panel and its controller are discarded on every pick (close -> stop ->
// nil) and rebuilt on the next Cmd+M, so the armed advance lives on
// AppDelegate and every new panel reads its prefill from here.
struct MagnetEpisodeTracker {
    struct Armed { let query: String; let source: String; var adopted = false }
    private(set) var armed: Armed?
    private(set) var advanceQuery: String?
    /// The picked query snapshot and source, taken before the panel closes.
    mutating func pick(query: String, source: String) { armed = Armed(query: query, source: source) }
    /// Every media start. Only the picked source's own torrent stream (port
    /// 2222, the same predicate wtPlaybackToken uses) may adopt the arm; any
    /// other media first, or a second stream after adoption, invalidates it.
    /// An empty path is the gap between media and keeps the arm.
    mutating func noteMediaStarted(path: String?, startedSource: String?) {
        guard var a = armed, let path else { return }
        guard MagnetEpisodeTracker.isTorrentStream(path), startedSource == a.source, !a.adopted
        else { armed = nil; return }
        a.adopted = true; armed = a
    }
    /// A playback EOF edge. Only the adopted picked media reaching its own
    /// end arms the advance.
    mutating func notePlaybackFinished(path: String?) {
        guard let a = armed, a.adopted, let path, MagnetEpisodeTracker.isTorrentStream(path) else { return }
        advanceQuery = a.query; armed = nil
    }
    /// A committed query replaces the remembered one and drops any advance.
    mutating func noteQueryCommitted() { advanceQuery = nil; armed = nil }
    /// The next search bar's text: the finished pick's next episode, else the
    /// caller's fallback (the panel's own restored query, "" on a fresh one).
    func prefill(fallback: String) -> String {
        advanceQuery.flatMap(MagnetSeriesQuery.nextEpisode) ?? fallback
    }
    static func isTorrentStream(_ path: String) -> Bool {
        PlayerTorrentEndpoint.isCurrent(path)
    }
}
final class MagnetResultsPanel: NSView, NSTextFieldDelegate {
    var onClose: (() -> Void)?
    var onQuery: ((String) -> Void)?
    // Empty-query Enter lists popular torrents (owner 2026-11-20); nil falls back to dismiss.
    var onPopular: (() -> Void)?
    var onSelect: ((String) -> Void)?
    var onPendingSelect: ((String) -> Void)?
    var onSort: ((String, Bool) -> Void)?
    private var fieldPanel: NSPanel?
    private var searchMinimumWidth: CGFloat = 280
    private var searchMaximumWidth: CGFloat = 960
    private var rows: [MagnetResult] = []
    // Rebuilt controls cannot select a different row through a reused numeric index.
    private var rowRevision: UInt64 = 0
    private var lastContentSignature = ""
    private var lastVerdictSignature = ""
    private var windowPages = 1
    private static let windowPageSize = 1000
    private var lastShownResponse: SearchResponse?
    // Virtualization (v22.17): a fixed pool of row views is reassigned to the
    // visible range on scroll; view count stays ~poolSize at any row count.
    private var rowPool: [NSView] = []
    private var visibleRowRange: Range<Int> = 0..<0
    private var scrollWired = false
    private var poolDirty = false
    private let loadMore = NSButton(title: "load more", target: nil, action: nil)
    private var selectionInProgress = false
    fileprivate func invalidateSelection() {
        rowRevision &+= 1
    }
    private var queryText = ""
    private let scroll = GORActivityScrollView()
    private let stack = MagnetResultStack()
    private let statusLayer = CATextLayer()
    private let time = NSButton(title: "time", target: nil, action: nil)
    private let size = NSButton(title: "size", target: nil, action: nil)
    private let seed = NSButton(title: "seed", target: nil, action: nil)
    private let source = NSButton(title: "source", target: nil, action: nil)
    private let titleSort = NSButton(title: "title", target: nil, action: nil)
    private let close = MusicBtn("×", hover: "close")
    private var sortKey = "priority"
    private var descending = true
    private var currentSort = "priority"
    private var descendingSort = true
    // The header and rows share these exact column starts; widths scale
    // with the loaded variable font, rather than fixed pixels.
    private var rowHeight: CGFloat { PhotonFont.chromeLineH + 3 }
    private var sourceWidth: CGFloat { max(88, PhotonFont.chromeCharW * 7 + 12) }
    // Fit the date actually drawn (yy.MM.dd HH:mm), not a fixed 176pt slot.
    // A right-aligned value in an oversized slot made source and time look far apart.
    private var timeWidth: CGFloat { textWidth("26.09.29 13:00", font: PhotonFont.chromeNs()) + 8 }
    private var seedWidth: CGFloat { max(78, textWidth("unverified", font: PhotonFont.chromeNs()) + 12) }
    private var sizeWidth: CGFloat { max(88, PhotonFont.chromeCharW * 8 + 12) }
    private var columnGap: CGFloat { max(14, PhotonFont.chromePad) }
    private let displayDate = DateFormatter()
    private let isoDate = ISO8601DateFormatter()
    private var variationToken: UUID?
    private var fieldVariationToken: UUID?
    private var variationActive = true

    // A detached results panel may still be retained by AppKit event handling.
    // Retire its fanout explicitly before selection starts another source.
    fileprivate func retireVariation() {
        variationActive = false
        if let token = variationToken { VariationBroadcaster.shared.removeListener(token) }
        variationToken = nil
        closeSearch()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true; layer?.backgroundColor = NSColor.clear.cgColor
        displayDate.dateFormat = "yy.MM.dd HH:mm"
        displayDate.timeZone = .current
        isoDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        scroll.documentView = stack; scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        addSubview(scroll)
        [source,time,seed,size,titleSort,close].forEach { addSubview($0) }
        statusLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        statusLayer.foregroundColor = NSColor(white:0.31,alpha:1).cgColor
        statusLayer.font = PhotonFont.chromeCt()
        if statusLayer.fontSize != PhotonFont.chromeSize { statusLayer.fontSize = PhotonFont.chromeSize }
        statusLayer.truncationMode = .end
        layer?.addSublayer(statusLayer)
        for (button, key) in [(source,"source"),(time,"uploadedAt"),(seed,"seeds"),(size,"sizeBytes"),(titleSort,"title")] {
            button.isBordered = false; button.font = PhotonFont.chromeNs()
            button.contentTintColor = .white
            button.cell?.lineBreakMode = .byTruncatingTail
            button.alignment = key == "title" ? .left : .right
            button.target = self; button.action = #selector(sortTapped(_:))
            button.identifier = NSUserInterfaceItemIdentifier(key)
        }
        close.tap = { [weak self] in self?.closeTapped() }
        // Use the same point size and driven face as the rest of the UI.
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
        variationToken = VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self, self.variationActive, self.window != nil, !self.isHidden else { return }
            let headerFont = PhotonFont.chromeCtDriven(view: self, profile: .panel)
            PhotonFont.setIfChanged(headerFont, on: self.statusLayer)
            for button in [self.source, self.time, self.seed, self.size, self.titleSort] {
                let driven = PhotonFont.chromeNsDriven(view: button, profile: .button)
                if button.font != driven { button.font = driven }
            }
            // Pool overscan slots are empty and hidden by design. Never read
            // attribute index 0 of their empty mutable attributed titles:
            // NSRangeException here escapes the shared variation timer.
            for row in self.rowPool where !row.isHidden {
                if let button = row.subviews.compactMap({ $0 as? NSButton }).first,
                   let attributed = button.attributedTitle.mutableCopy() as? NSMutableAttributedString,
                   attributed.length > 0 {
                    let driven = PhotonFont.chromeNsDriven(view: row, profile: .row)
                    if attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont != driven {
                        attributed.addAttribute(.font, value: driven, range: NSRange(location: 0, length: attributed.length))
                        button.attributedTitle = attributed
                    }
                }
                for cell in row.subviews.compactMap({ $0 as? NSTextField }) {
                    let driven = PhotonFont.chromeNsDriven(view: row, profile: .row)
                    if cell.font != driven { cell.font = driven }
                }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit {
        if let variationToken { VariationBroadcaster.shared.removeListener(variationToken) }
        if let fieldVariationToken { VariationBroadcaster.shared.removeListener(fieldVariationToken) }
    }
    override func mouseMoved(with event: NSEvent) {
        if let pt = window?.contentView?.convert(event.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: pt)
        }
        super.mouseMoved(with: event)
    }
    // Header and rows share these starts. The sort block packs from the
    // right edge and the title keeps a usable share of the panel; the
    // secondary columns contract before the title is allowed to collapse.
    private func columns(_ width: CGFloat) -> (source: CGFloat, time: CGFloat, seed: CGFloat, size: CGFloat, titleWidth: CGFloat, widths: [CGFloat]) {
        let gap = columnGap
        let titleMin: CGFloat = max(75, PhotonFont.chromeCharW * 5)
        let reserve = max(titleMin, width * 0.28)
        let available = max(0, width - 56 - reserve - gap * 4)
        let ideal = [sourceWidth,timeWidth,seedWidth,sizeWidth]
        let sum = ideal.reduce(0,+)
        let scale = min(1, available / sum)
        let ws = ideal.map { floor($0 * scale) }
        let sizeX = width - 42 - ws[3]
        let seedX = sizeX - gap - ws[2]
        let timeX = seedX - gap - ws[1]
        let sourceX = timeX - gap - ws[0]
        // The title button begins at x=14; leave only a 6pt gutter to source.
        return (sourceX,timeX,seedX,sizeX,max(0,sourceX - 14 - 6),ws)
    }
    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes:[.font:font]).width) + 3
    }
    override func layout() {
        super.layout()
        // The panel is always inset inside the window (applyVideoFrame fits
        // the video frame, and any crop target, to the window bounds), so
        // layout uses the panel bounds directly - there is no off-screen
        // region to clamp against.
        let w = bounds.width, h = bounds.height
        GeomTrace.log("magnet.layout", "bounds=\(Int(w))x\(Int(h))")
        let c = columns(w)
        // The panel is inset inside the video frame. Derive Quit's real
        // frame through the shared overlay coordinates, not from panel h.
        let headerY: CGFloat
        if let spine = (NSApp.delegate as? AppDelegate)?.controller?.spineUI,
           spine.superview != nil, spine.btnQ.superview != nil {
            headerY = spine.convert(spine.btnQ.frame, to: self).minY
        } else {
            headerY = h - PhotonFont.chromePad + 5 - PhotonFont.chromeLineH
        }
        let lineH = PhotonFont.chromeLineH + 4
        // Title stays left. Each sort label hugs its column's right edge so
        // it sits directly over the right-aligned row values; the size label
        // ends immediately left of the close button. Hit targets stay the
        // label glyphs (plus a small slack), never the inter-column gaps.
        let titleMeasure = textWidth(titleSort.title,font:titleSort.font ?? PhotonFont.chromeNs())
        titleSort.frame = CGRect(x:14,y:headerY-4,
                                 width:max(0,min(titleMeasure,c.titleWidth)),height:lineH)
        // MusicBtn grows leftwards on hover (typewriter title); header labels yield to it.
        let closeLeft = w - 4 - close.frame.width
        let sortStarts = [c.source,c.time,c.seed,c.size]
        for (index,button) in [source,time,seed,size].enumerated() {
            let measure = textWidth(button.title,font:button.font ?? PhotonFont.chromeNs()) + 6
            let rightEdge = min(sortStarts[index] + c.widths[index], closeLeft - 6)
            button.frame = CGRect(x:rightEdge - measure,y:headerY-4,
                                  width:max(0,measure),height:lineH)
        }
        close.frame = CGRect(x:max(0,w - 4 - close.frame.width),y:headerY-4,width:close.frame.width,height:lineH)
        let statusX = titleSort.frame.maxX + 7
        statusLayer.frame = CGRect(x:statusX,y:headerY,
                                   width:max(0,c.source - columnGap - statusX),height:PhotonFont.chromeCharH + 3)
        let footerH: CGFloat = loadMore.isHidden ? 0 : (PhotonFont.chromeLineH + 10)
        loadMore.frame = CGRect(x:10, y:2, width:max(0,w-20), height:PhotonFont.chromeLineH + 6)
        scroll.frame = CGRect(x:10,y:8+footerH,width:max(0,w-20),height:max(0,headerY-12-footerH))
        layoutResultRows()
    }
    private func layoutResultRows() {
        let contentWidth = max(0, scroll.contentSize.width)
        stack.frame = CGRect(x:0,y:0,width:contentWidth,height:CGFloat(rows.count)*rowHeight)
        poolDirty = true // column widths may have changed on resize
        // A taller viewport (window -> fullscreen) needs more pooled rows. The pool was only
        // grown in show(), so after the switch the extra area stayed empty (looked like the
        // window-mode height). Grow it on every layout; it never shrinks.
        if !rows.isEmpty { ensureRowPool() }
        reassignVisibleRows()
    }
    // Build one reusable row view skeleton (title button + 4 cells).
    private func makeRowView() -> NSView {
        let view = NSView(frame: .zero)
        let title = NSButton(title: "", target: self, action: #selector(rowTapped(_:)))
        title.isBordered = false; title.alignment = .left; title.font = PhotonFont.chromeNs()
        title.cell?.lineBreakMode = .byTruncatingTail
        title.contentTintColor = .white
        view.addSubview(title)
        for _ in 0..<4 {
            let label = NSTextField(labelWithString: "")
            label.font = PhotonFont.chromeNs()
            label.alignment = .right
            label.lineBreakMode = .byTruncatingTail
            view.addSubview(label)
        }
        return view
    }
    private func ensureRowPool() {
        let need = MagnetNative.poolSize(viewportHeight: Double(scroll.contentSize.height), rowHeight: Double(rowHeight))
        while rowPool.count < need { let v = makeRowView(); rowPool.append(v); stack.addSubview(v) }
        if !scrollWired {
            scrollWired = true
            scroll.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: nil) { [weak self] _ in
                self?.reassignVisibleRows()
            }
        }
    }
    // Fill each pool slot with its assigned row; hide slots beyond the range.
    private func reassignVisibleRows() {
        guard !rowPool.isEmpty else { return }
        let range = MagnetNative.visibleRange(offsetY: Double(scroll.contentView.bounds.origin.y),
                                              viewportHeight: Double(scroll.contentView.bounds.height),
                                              rowCount: rows.count, rowHeight: Double(rowHeight))
        guard poolDirty || range != visibleRowRange else { return }
        poolDirty = false
        visibleRowRange = range
        let assignments = MagnetNative.slotAssignments(poolSize: rowPool.count, range: range, rowCount: rows.count)
        let c = columns(bounds.width)
        let starts = [c.source,c.time,c.seed,c.size].map { $0 - scroll.frame.minX }
        var assigned = Set<Int>()
        for (slot, rowIndex) in assignments {
            assigned.insert(slot)
            let view = rowPool[slot]
            let row = rows[rowIndex]
            view.isHidden = false
            view.frame = CGRect(x:0,y:CGFloat(rowIndex)*rowHeight,width:stack.frame.width,height:rowHeight)
            guard let title = view.subviews.compactMap({ $0 as? NSButton }).first else { continue }
            title.title = row.title
            title.toolTip = row.infoHash == nil ? "Verify magnet before playback" : row.title
            title.identifier = NSUserInterfaceItemIdentifier("\(rowRevision):\(rowIndex)")
            title.frame = CGRect(x:4,y:0,width:max(0,c.titleWidth),height:rowHeight)
            let timestamp = row.uploadedAt ?? ""
            let parsedDate = isoDate.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
            let timeText = parsedDate.map { displayDate.string(from: $0) } ?? "-"
            let sizeText = row.sizeBytes.map { ByteCountFormatter.string(fromByteCount:$0, countStyle:.file) } ?? "-"
            // Provisional "~claim" at t=0 while verification runs; the verdict
            // replaces it. Claims stay marked as claims (tooltip), never health.
            let seedText = row.verdict?.label ?? (row.claims.values.max().map { "~\($0)" } ?? "pending")
            let cells = [row.source,timeText,seedText,sizeText]
            for (index, label) in view.subviews.compactMap({ $0 as? NSTextField }).enumerated() where index < 4 {
                label.stringValue = cells[index]
                if index == 2, let verdict = row.verdict {
                    label.toolTip = verdict.verifiedSeeds.map { "Tracker-reported seeders: \($0); verified peers: \(verdict.verifiedPeers)" }
                        ?? "Seeder count unknown; verified peers: \(verdict.verifiedPeers)"
                } else if index == 2, row.verdict == nil, row.claims.values.max() != nil {
                    label.toolTip = "Provider-reported claim (unverified); tracker/DHT verification in flight"
                } else { label.toolTip = nil }
                label.textColor = index == 0 ? NSColor(white:0.24,alpha:1) : NSColor.white.withAlphaComponent(0.5)
                label.frame = CGRect(x:starts[index],y:0,width:max(0,c.widths[index]),height:rowHeight)
            }
        }
        for (slot, view) in rowPool.enumerated() where !assigned.contains(slot) { view.isHidden = true }
    }
    var visibleResultCount: Int { rows.count }
    func setStatus(_ value: String) { statusLayer.string = "· " + value + (rows.isEmpty ? "" : " / checks cover the first 60 results") }
    func setQuery(_ value: String) { queryText = value; windowPages = 1; lastContentSignature = ""; lastVerdictSignature = ""; setStatus("searching providers") }
    // Keep the panel safe even if a different caller bypasses the controller.
    fileprivate func show(_ response: SearchResponse, keepScroll: Bool = false) {
        // Windowing (owner 2026-10-17): the first window is the top-1000 by
        // seeds (verified when present, else the claim); "load more" appends
        // the next 1000. Rendering thousands of rows at once stalls the panel.
        lastShownResponse = response
        let filtered = (response.results + response.pendingRows).filter { !$0.hasExecutableTitle }
        let pool = MagnetNative.topBySeeds(filtered, limit: MagnetResultsPanel.windowPageSize * windowPages)
        let hiddenCount = filtered.count - pool.count
        rows = MagnetNative.sortRows(pool, key: currentSort, descending: descendingSort)
        // Verdict scrapes refresh every 0.5s. Two signatures split the work:
        // same row set -> only the verdict cells update in place (no rebuild,
        // no re-order while the user reads); new/removed rows -> full rebuild.
        // Sort taps and provider landings (keepScroll=false) always rebuild.
        let contentSignature = rows.map { "\($0.infoHash ?? $0.title)|\($0.source)|\($0.title)" }.joined(separator: "\n") + "|\(hiddenCount)"
        let verdictSignature = rows.map { "\($0.infoHash ?? $0.title):\($0.verdict?.label ?? "pending")" }.sorted().joined(separator: "\n")
        if keepScroll, contentSignature == lastContentSignature {
            if verdictSignature != lastVerdictSignature {
                updateVerdictLabelsInPlace()
                lastVerdictSignature = verdictSignature
            }
            setStatus(hiddenCount > 0 ? "\(rows.count) results + \(hiddenCount) more below" : "\(rows.count) results")
            return
        }
        lastContentSignature = contentSignature
        lastVerdictSignature = verdictSignature
        rowRevision &+= 1
        let savedY = scroll.contentView.bounds.origin.y
        // Virtualized render: the stack only carries the fixed pool; the
        // document height is what makes the scrollbar honest. A row-count
        // change resets the visible range so every slot gets reassigned.
        poolDirty = true
        ensureRowPool()
        if loadMore.superview == nil {
            loadMore.target = self; loadMore.action = #selector(loadMoreTapped(_:))
            loadMore.isBordered = false; loadMore.alignment = .left; loadMore.font = PhotonFont.chromeNs()
            loadMore.contentTintColor = NSColor.white.withAlphaComponent(0.8)
            addSubview(loadMore)
        }
        loadMore.isHidden = hiddenCount == 0
        loadMore.title = "load more (\(hiddenCount) more results)"
        setStatus(hiddenCount > 0 ? "\(rows.count) results + \(hiddenCount) more below" : "\(rows.count) results")
        // Adding document subviews does not guarantee this panel gets a layout
        // pass when its frame stays fixed. Size each row now, not just on resize.
        needsLayout = true
        layoutSubtreeIfNeeded()
        layoutResultRows()
        // A background refresh (tracker seeds arriving) must not throw the user back to the top.
        let maxY = MagnetNative.maxOffsetY(rowCount: rows.count, rowHeight: Double(rowHeight), viewportHeight: Double(scroll.contentView.bounds.height))
        scroll.contentView.scroll(to:NSPoint(x:0,y: keepScroll ? min(savedY, maxY) : 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        reassignVisibleRows() // bounds notification may not fire when y is unchanged
    }
    @objc private func loadMoreTapped(_ sender: NSButton) {
        windowPages += 1
        if let response = lastShownResponse { show(response, keepScroll: true) }
    }
    // Verdict ticks rewrite only the seed-cell text of the rows that already
    // exist - no view rebuild, no re-order while the user reads. The next
    // explicit sort tap re-orders instantly from cached rows.
    private func updateVerdictLabelsInPlace() {
        for (slot, rowIndex) in MagnetNative.slotAssignments(poolSize: rowPool.count, range: visibleRowRange, rowCount: rows.count) {
            let row = rows[rowIndex]
            let rowView = rowPool[slot]
            guard rowView.subviews.count >= 4, let label = rowView.subviews[3] as? NSTextField else { continue }
            label.stringValue = row.verdict?.label ?? (row.claims.values.max().map { "~\($0)" } ?? "pending")
            if let verdict = row.verdict {
                label.toolTip = verdict.verifiedSeeds.map { "Tracker-reported seeders: \($0); verified peers: \(verdict.verifiedPeers)" }
                    ?? "Seeder count unknown; verified peers: \(verdict.verifiedPeers)"
            }
        }
    }
    @objc private func rowTapped(_ sender: NSButton) {
        let trace = UUID().uuidString
        func log(_ reason: String, _ magnet: String? = nil) {
            MagnetSelectionTrace.log(reason, magnet, trace: trace)
        }
        log("CLICK")
        guard !selectionInProgress else { log("SELECTION_IN_PROGRESS"); return }
        guard let id = sender.identifier?.rawValue else { log("MISSING_ROW_ID"); return }
        let identity = id.split(separator: ":", omittingEmptySubsequences: false)
        guard identity.count == 2, let revision = UInt64(identity[0]),
              let index = Int(identity[1]) else { log("INVALID_ROW_ID"); return }
        guard revision == rowRevision else { log("STALE_ROW_REVISION"); return }
        selectionInProgress = true
        defer { selectionInProgress = false }
        guard rows.indices.contains(index) else { log("STALE_ROW_INDEX"); return }
        let row = rows[index]
        log("ROW_RESOLVED", row.magnetUri)
        guard !row.hasExecutableTitle else { log("EXECUTABLE_TITLE_REJECT", row.magnetUri); return }
        // The parsed hash must still match the selected magnet before WT.
        guard let hash = row.infoHash, let magnet = row.magnetUri else {
            log(onPendingSelect == nil ? "PENDING_CALLBACK_MISSING" : "PENDING_SELECT", row.magnetUri)
            onPendingSelect?(row.detailUrl)
            log("PENDING_RETURN", row.magnetUri); return
        }
        guard hash.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil else {
            log("INVALID_INFOHASH", magnet); return
        }
        guard let components = URLComponents(string: magnet) else { log("URI_PARSE_REJECT", magnet); return }
        guard let xt = components.queryItems?.first(where: { $0.name == "xt" })?.value else {
            log("MISSING_XT", magnet); return
        }
        guard xt.lowercased() == "urn:btih:\(hash)" else { log("XT_MISMATCH", magnet); return }
        // A contradicted swarm may still be alive: never stream it silently.
        if row.verdict?.state == .contradicted {
            log("CONTRADICTED_PROMPT", magnet)
            let alert = NSAlert()
            alert.messageText = "Source claims seeds, none were found"
            alert.informativeText = "Two independent checks found no peers for this magnet. Start it anyway?"
            alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Start anyway")
            guard alert.runModal() == .alertSecondButtonReturn else { log("USER_CANCEL", magnet); return }
            log("USER_START_ANYWAY", magnet)
        }
        // A modal alert runs a nested loop: search/stop/refresh may invalidate this row.
        guard revision == rowRevision else { log("STALE_ROW_AFTER_PROMPT", magnet); return }
        // Playback intent: the advance outlives this panel (close -> stop ->
        // nil on every pick), so it arms on the AppDelegate-owned tracker.
        if let app = NSApp.delegate as? AppDelegate {
            app.magnetEpisodeTracker.pick(query: queryText, source: magnet)
        }
        // Preserve callback capture and close-before-selection order.
        // onClose may stop the controller, so validate before calling it, not after.
        let select = onSelect
        log(onClose == nil ? "CLOSE_CALLBACK_MISSING" : "CLOSE_CALL", magnet)
        onClose?()
        log("CLOSE_RETURN", magnet)
        log(select == nil ? "SELECT_CALLBACK_MISSING" : "SELECT_CALL", magnet)
        select?(magnet)
        log("SELECT_RETURN", magnet)
    }
    @objc private func sortTapped(_ sender: NSButton) {
        let key = sender.identifier?.rawValue ?? "seeds"
        descending = key == sortKey ? !descending : (key == "seeds" || key == "sizeBytes" || key == "uploadedAt")
        sortKey = key
        currentSort = key; descendingSort = descending
        onSort?(sortKey, descending)
    }
    // Same state write as a header tap, for flows that pick the sort themselves
    // (the empty-query popular listing sorts by seeds, highest first).
    func applySort(_ key: String, descending value: Bool) {
        sortKey = key; descending = value; currentSort = key; descendingSort = value
    }
    @objc private func closeTapped() { onClose?() }
    var isSearchOpen: Bool { fieldPanel?.isVisible == true }
    func setChromeAlpha(_ alpha: CGFloat, animated: Bool = false) {
        if animated {
            animator().alphaValue = alpha
            if fieldPanel?.isVisible != true { fieldPanel?.animator().alphaValue = alpha }
        } else {
            alphaValue = alpha
            if fieldPanel?.isVisible != true { fieldPanel?.alphaValue = alpha }
        }
    }
    func dismissSearch() {
        guard fieldPanel != nil else { return }
        closeSearch()
        if isHidden { onClose?() }
    }
    /// Cmd+F toggle (owner 2026-11-15): an open search closes; otherwise it
    /// opens (openSearch reuses and refocuses an existing bar).
    func toggleSearchFromKey() {
        if fieldPanel != nil { closeSearch() } else { openSearch() }
    }
    func closeSearch() {
        guard let panel = fieldPanel else { return }
        fieldPanel = nil
        if let fieldVariationToken { VariationBroadcaster.shared.removeListener(fieldVariationToken) }
        fieldVariationToken = nil
        let parent = window
        panel.close()
        parent?.makeKeyAndOrderFront(nil)
        (NSApp.delegate as? AppDelegate)?.overlayWin?.ignoresMouseEvents = false
    }
    func openSearch() {
        // One-instance rule: any existing search bar is reused (never a second one),
        // visible or not, and key + first responder are re-asserted with the same retry
        // the first open uses (the app can activate a beat late after a click in mpv).
        if let panel = fieldPanel {
            if !NoActivate.active {NSApp.activate(ignoringOtherApps: true)}
            panel.makeKeyAndOrderFront(nil)
            if let field = (panel.stereoSession?.original ?? panel.contentView)?.subviews.first(where: { $0 is NSTextField }) {
                panel.makeFirstResponder(field)
                panel.assertKeyAndFocus(field)
            }
            print("[magnet-panel] reopen: refocused search field, key=\(panel.isKeyWindow)")
            return
        }
        // Safety net: a stale bar from an earlier controller must not stack under a new one.
        if let stale = MagnetFieldPanel.current, stale.isVisible { stale.close() }
        guard let parent = window else { return }
        // FileBrowserTopBar.openSearchPanel is the literal panel pattern.
        // The only geometry difference requested here is player centering.
        let ph: CGFloat = 54
        let frame = SearchBarFit.initialFrame(host: parent, height: ph)
        let pw = frame.width
        searchMaximumWidth = SearchBarFit.maxWidth(host: parent)
        searchMinimumWidth = pw
        let panel = MagnetFieldPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.onEscape = { [weak self] in self?.dismissSearch() }
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
        NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification, object:panel, queue:.main) { [weak self, weak parent] _ in
            if self?.fieldPanel === panel {
                self?.fieldPanel = nil
                if let token = self?.fieldVariationToken { VariationBroadcaster.shared.removeListener(token) }
                self?.fieldVariationToken = nil
            }
            parent?.ignoresMouseEvents = false
        }
        let bg = NSView(frame: CGRect(x: 0, y: 0, width: pw, height: ph))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.black.cgColor
        let field = NSTextField(frame: CGRect(x: 20, y: 14, width: pw - 40, height: 28))
        // A series query whose picked episode played to its end advances to
        // the next episode; any other query is restored unchanged.
        field.stringValue = (NSApp.delegate as? AppDelegate)?.magnetEpisodeTracker.prefill(fallback: queryText) ?? queryText
        field.font = PhotonFont.chromeNs(); field.textColor = .white
        field.backgroundColor = .clear; field.drawsBackground = false
        field.isBordered = false; field.focusRingType = .none
        field.isEditable = true; field.isSelectable = true
        field.refusesFirstResponder = false
        field.placeholderString = "search"
        field.target = self; field.action = #selector(commitSearch(_:))
        field.delegate = self
        fieldVariationToken = VariationBroadcaster.shared.addListener(weakLifetime: field) { [weak self, weak field] in
            guard self?.variationActive == true, let field, field.window != nil else { return }
            // The search field is in its own NSPanel, not the player window.
            // Measure the pointer in screen space rather than reusing the
            // broadcaster's player-window point or a fixed proximity.
            guard let window = field.window else { return }
            let rect = window.convertToScreen(field.convert(field.bounds, to: nil))
            let pointer = NSEvent.mouseLocation
            let dx = max(rect.minX - pointer.x, 0, pointer.x - rect.maxX)
            let dy = max(rect.minY - pointer.y, 0, pointer.y - rect.maxY)
            let p = max(0, min(1, 1 - hypot(dx, dy) / DriveProfile.panel.radius))
            let vb = VariationBroadcaster.shared
            let curve = vb.curve(p, power: DriveProfile.panel.power)
            let driven = PhotonFont.chromeNsDriven(p: p, t_audio: Double(vb.audioBlend(curve)))
            if field.font != driven { field.font = driven }
        }
        field.usesSingleLineMode = false
        field.cell?.wraps = true; field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping; field.maximumNumberOfLines = SearchBarFit.maxLines
        bg.addSubview(field)
        panel.onReturn = { [weak self, weak field] in if let field { self?.commitSearch(field) } }
        panel.contentView = bg
        fieldPanel = panel
        MagnetFieldPanel.current = panel
        // The floating key window is independent of the idle mouse-hide timer.
        // Do not inherit the hidden spine alpha while the user is typing.
        panel.alphaValue = 1
        parent.ignoresMouseEvents = true
        panel.installStereoIfNeeded(parent: parent)
        panel.makeKeyAndOrderFront(nil); panel.assertKeyAndFocus(field)
        resizeSearch(field)
        SearchBarFit.observeHost(panel: panel, host: parent) { [weak self, weak field] in
            if let field { self?.resizeSearch(field) }
        }
    }
    private func resizeSearch(_ field: NSTextField) {
        guard let panel = fieldPanel, field.window === panel else { return }
        if let host = window {
            searchMaximumWidth = SearchBarFit.maxWidth(host: host)
            searchMinimumWidth = SearchBarFit.openWidth(host: host)
        }
        SearchBarFit.fit(panel: panel, field: field, minWidth: searchMinimumWidth,
                         maxWidth: searchMaximumWidth, anchor: .center)
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        resizeSearch(field)
    }
    @objc private func commitSearch(_ sender: NSTextField) {
        guard let search = fieldPanel, sender.window === search else { return }
        let query = sender.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        // Owner 2026-11-20: Enter on an empty query lists popular torrents
        // instead of dismissing; unwired falls back to the old dismiss.
        if query.isEmpty {
            guard let onPopular else { dismissSearch(); return }
            closeSearch(); onPopular(); return
        }
        closeSearch()
        if let app = NSApp.delegate as? AppDelegate { app.magnetEpisodeTracker.noteQueryCommitted() }
        queryText = query; onQuery?(query)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { dismissSearch(); return true }
        if selector == #selector(NSResponder.insertNewline(_:)), let field = control as? NSTextField {
            commitSearch(field); return true
        }
        return false
    }
}

/// One place that turns provider outcomes into the panel status line.
/// A provider that did not answer is always named with a readable reason, and an empty list
/// never reads as a plain "0 results" while a provider is down or still searching.
enum MagnetProviderStatusLine {
    static let reasonLabels: [String:String] = [
        "cloudflare_unresolved": "Cloudflare check not solved",
        "rate_limited": "rate limited",
        "http_or_network": "network error",
        "request_format": "bad request",
        "layout_changed": "page layout changed"
    ]
    static func label(_ provider: String, _ reason: String?) -> String {
        guard let reason, !reason.isEmpty else { return provider }
        return provider + " (" + (reasonLabels[reason] ?? "unavailable") + ")"
    }
    static func line(rows: Int, pending: Bool, unavailable: [(String, String?)]) -> String {
        let down = unavailable.sorted { $0.0 < $1.0 }.map { label($0.0, $0.1) }
        var parts = [rows == 0 && !pending ? (down.isEmpty ? "no results" : "no results from available providers") : "\(rows) rows"]
        if pending { parts.append("searching") }
        if !down.isEmpty { parts.append("unavailable: " + down.joined(separator: ", ")) }
        return parts.joined(separator: " / ")
    }
}


// ================================================================
//  SearchBarFit - shared growth rule for the single-line search/input bars
//  Width grows with the text up to a ceiling (2/3 of the player window, 2/4 of the
//  screen in fullscreen); past that the field wraps and the bar grows in height, one line per wrapped line. Installed once per bar; it only
//  observes text changes, so each bar keeps its own delegate/commit logic.
// ================================================================
enum SearchBarFit {
    enum Anchor { case center, top }
    /// The bar grows one line of height per wrapped line up to this cap; past it the
    /// panel stays at this height and the field clips. 0 would mean no line limit.
    static let maxLines = 4
    /// Every search bar opens like Cmd+M: centred on the player window.
    /// Open width: one third of the player window; one quarter of the screen in fullscreen.
    /// Growth: the bar widens as you type up to two thirds of the player window (two quarters of the screen in
    /// fullscreen). Past that the text wraps and the bar grows in height, one line per wrapped line (up to maxLines).
    /// Fullscreen state of the PLAYER (mpv's own report via AppDelegate), not the overlay window's styleMask:
    /// the overlay is a borderless window that never carries .fullScreen. Until mpv has reported, fall back to the
    /// overlay frame covering its whole screen.
    static func isFullscreen(_ host: NSWindow) -> Bool {
        if let state = (NSApp.delegate as? AppDelegate)?.playerFullscreenState { return state }
        guard let s = host.screen else { return false }
        return host.frame.width >= s.frame.width - 2 && host.frame.height >= s.frame.height - 2
    }
    private static func screenWidth(_ host: NSWindow) -> CGFloat {
        host.screen?.frame.width ?? NSScreen.main?.frame.width ?? host.frame.width
    }
    /// Read live, so the next fit after a window resize or a fullscreen switch uses the new limits.
    static func maxWidth(host: NSWindow) -> CGFloat {
        isFullscreen(host) ? screenWidth(host) / 2 : host.frame.width * 2 / 3
    }
    static func openWidth(host: NSWindow) -> CGFloat {
        isFullscreen(host) ? screenWidth(host) / 4 : host.frame.width / 3
    }
    static func initialFrame(host: NSWindow, height: CGFloat) -> CGRect {
        let w = openWidth(host: host)
        return CGRect(x: host.frame.midX - w / 2, y: host.frame.midY - height / 2, width: w, height: height)
    }
    static func recenter(panel: NSPanel, host: NSWindow) {
        if panel.stereoSession != nil { return }
        var f = panel.frame
        f.origin.x = host.frame.midX - f.width / 2
        f.origin.y = host.frame.midY - f.height / 2
        panel.setFrame(f, display: true)
    }
    /// Re-fit when the player window resizes or the player enters/leaves fullscreen (mpv's report, posted by
    /// AppDelegate). The overlay frame follows mpv a beat later, so every host resize also recentres the bar.
    static func observeHost(panel: NSPanel, host: NSWindow, refit: @escaping () -> Void) {
        let nc = NotificationCenter.default
        var tokens: [NSObjectProtocol] = []
        tokens.append(nc.addObserver(forName: AppDelegate.playerFullscreenChanged, object: nil, queue: .main) { [weak panel, weak host] _ in
            guard let panel, let host, panel.isVisible else { return }
            refit(); recenter(panel: panel, host: host)
        })
        tokens.append(nc.addObserver(forName: NSWindow.didResizeNotification, object: host, queue: .main) { [weak panel, weak host] _ in
            guard let panel, let host, panel.isVisible else { return }
            refit(); recenter(panel: panel, host: host)
        })
        var closeToken: NSObjectProtocol?
        closeToken = nc.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
            tokens.forEach { nc.removeObserver($0) }
            if let closeToken { nc.removeObserver(closeToken) }
        }
    }

    static func install(panel: NSPanel, field: NSTextField, minWidth: CGFloat? = nil,
                        maxWidth: CGFloat? = nil, anchor: Anchor, trailing: NSView? = nil,
                        host: NSWindow? = nil) {
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = maxLines
        let minW = minWidth ?? panel.frame.width
        let insetR = max(0, panel.frame.width - 40 - field.frame.width)
        let trailGap = trailing.map { panel.frame.width - $0.frame.maxX } ?? 0
        let screenW = panel.screen?.visibleFrame.width ?? NSScreen.main?.visibleFrame.width ?? 1200
        let maxW0 = max(minW, maxWidth ?? min(960, screenW * 0.60))
        // With a host window the limits are read live on every fit (window vs fullscreen).
        func limits() -> (CGFloat, CGFloat) {
            guard let host else { return (minW, maxW0) }
            return (openWidth(host: host), SearchBarFit.maxWidth(host: host))
        }
        let token = NotificationCenter.default.addObserver(
            forName: NSControl.textDidChangeNotification, object: field, queue: .main
        ) { [weak panel, weak field] _ in
            guard let panel, let field, panel.isVisible else { return }
            let l = limits()
            fit(panel: panel, field: field, minWidth: l.0, maxWidth: l.1, anchor: anchor,
                insetR: insetR, trailing: trailing, trailGap: trailGap)
        }
        // Prefilled text (e.g. a restored query) gets sized once the panel is on screen.
        DispatchQueue.main.async { [weak panel, weak field] in
            guard let panel, let field, panel.isVisible, !field.stringValue.isEmpty else { return }
            let l = limits()
            fit(panel: panel, field: field, minWidth: l.0, maxWidth: l.1, anchor: anchor,
                insetR: insetR, trailing: trailing, trailGap: trailGap)
        }
        if let host {
            observeHost(panel: panel, host: host) { [weak panel, weak field] in
                guard let panel, let field else { return }
                let l = limits()
                fit(panel: panel, field: field, minWidth: l.0, maxWidth: l.1, anchor: anchor,
                    insetR: insetR, trailing: trailing, trailGap: trailGap)
            }
        }
        var closeToken: NSObjectProtocol?
        closeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { _ in
            NotificationCenter.default.removeObserver(token)
            if let closeToken { NotificationCenter.default.removeObserver(closeToken) }
        }
    }

    static func fit(panel: NSPanel, field: NSTextField, minWidth: CGFloat, maxWidth: CGFloat, anchor: Anchor,
                    insetR: CGFloat = 0, trailing: NSView? = nil, trailGap: CGFloat = 0) {
        // Text wraps in the actual eye-local panel, not the original full-window limit.
        // Measure using that same width or a long query can silently clip its final lines.
        let maxWidth = min(maxWidth,panel.stereoSession?.maximumContentWidth ?? maxWidth)
        let minWidth = min(minWidth,maxWidth)
        let font = field.font ?? PhotonFont.chromeNs()
        let text = field.stringValue
        let single = ceil((text as NSString).size(withAttributes: [.font: font]).width) + 56 + insetR
        let width = min(maxWidth, max(minWidth, single))
        let fieldW = max(0, width - 40 - insetR)
        let lineH = ceil(NSLayoutManager().defaultLineHeight(for: font))
        var lines = 1
        if single > maxWidth {
            let rect = NSAttributedString(string: text, attributes: [.font: font]).boundingRect(
                with: NSSize(width: max(1, fieldW - 12), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading])
            let wrapped = max(1, Int(ceil(rect.height / lineH)))
            lines = maxLines > 0 ? min(maxLines, wrapped) : wrapped
        }
        let fieldH = max(28, 28 + CGFloat(lines - 1) * lineH)
        let panelH = 54 + (fieldH - 28)
        if let stereo = panel.stereoSession {
            stereo.fit(width: width, height: panelH)
            let available = stereo.original?.bounds.width ?? width
            field.frame = CGRect(x:20,y:14,width:max(0,available-40-insetR),height:fieldH)
            if let trailing { trailing.frame.origin.x = available-trailGap-trailing.frame.width }
            return
        }
        var frame = panel.frame
        guard abs(frame.width - width) >= 1 || abs(frame.height - panelH) >= 1 else { return }
        let oldH = frame.height
        frame.origin.x += (frame.width - width) / 2
        frame.size.width = width
        frame.size.height = panelH
        switch anchor {
        case .center: frame.origin.y -= (panelH - oldH) / 2
        case .top: frame.origin.y -= (panelH - oldH)
        }
        panel.setFrame(frame, display: true)
        field.frame = CGRect(x: 20, y: 14, width: fieldW, height: fieldH)
        if let trailing {
            trailing.frame = CGRect(x: width - trailGap - trailing.frame.width, y: 0,
                                    width: trailing.frame.width, height: panelH)
        }
        if let editor = field.currentEditor() as? NSTextView {
            editor.scrollRangeToVisible(NSRange(location: editor.string.utf16.count, length: 0))
        }
    }
}

/// Search field panel. Esc and Return must work even when the text field has lost first responder.
final class MagnetFieldPanel: GORInputPanel {
    var onEscape: (() -> Void)?
    var onReturn: (() -> Void)?
    /// The one live search bar (weak): a second open closes a stale one instead of stacking.
    static weak var current: MagnetFieldPanel?
    override var canBecomeKey: Bool { !NoActivate.active }
    override func close() {
        if MagnetFieldPanel.current === self { MagnetFieldPanel.current = nil }
        super.close()
    }
    override func cancelOperation(_ sender: Any?) { print("[magnet-panel] esc via panel"); onEscape?() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: print("[magnet-panel] esc keyDown first=\(String(describing: firstResponder))"); onEscape?()
        case 36, 76: print("[magnet-panel] return keyDown first=\(String(describing: firstResponder))"); onReturn?()
        default: super.keyDown(with: event)
        }
    }
}

/// uindex.org sits behind a Cloudflare managed challenge (live probe 2026-10-17:
/// HTTP 403, header cf-mitigated: challenge, body "Just a moment..."). A plain
/// URLSession can never pass it; a real WebKit engine runs the challenge JS and
/// keeps cf_clearance in the shared data store, so later searches reuse it.
/// The collector is layout-tolerant on purpose: rows are anchored on magnet:
/// links — the one element any results layout must carry — and title/seeds/size
/// are recovered from the anchor's row context with tolerant patterns.
private enum MagnetUIndexFailure: Error {
    case cloudflareUnresolved, httpOrNetwork, requestFormat
    var reason: String {
        switch self {
        case .cloudflareUnresolved: return "cloudflare_unresolved"
        case .httpOrNetwork: return "http_or_network"
        case .requestFormat: return "request_format"
        }
    }
}

private final class MagnetUIndexProvider: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((Result<[[String: Any]], MagnetUIndexFailure>) -> Void)?
    private var deadlineWork: DispatchWorkItem?
    private var probeWork: DispatchWorkItem?
    private var probes = 0
    private var query = ""
    private var page = 1
    private var popularMode = false
    private var aggregated: [[String: Any]] = []
    private static let maxPages = 20           // abuse bound; most queries end on page 1-3
    // Live measurement 2026-10-17 (cloud Chrome on a datacenter IP, worst case):
    // the managed challenge reloaded 3 times and cleared after ~90s; a residential
    // IP typically clears far faster. Budgets carry margin past that observation.
    private static let maxProbes = 80            // 80 x 1.5s = 120s challenge budget
    private static let overallTimeout: TimeInterval = 300   // challenge + up to 20 pages

    // DOM-side collector: every magnet: anchor plus its row context. No layout
    // assumption beyond "a results row wraps the magnet link".
    static let collectJS = #"JSON.stringify([...document.querySelectorAll('a[href^="magnet:"]')].slice(0,100).map(a=>{const tr=a.closest('tr');const q=s=>tr?tr.querySelector(s):null;const t=s=>{const e=q(s);return (e?e.textContent:'').trim()};const t2=a=>{for(const s of a){const v=t(s);if(v)return v}return ''};const dt=q('a[href*="details.php"]');const row=(tr?tr.innerText:(a.parentElement?a.parentElement.innerText:a.textContent))||'';return {magnet:a.href,title:((dt?dt.textContent:a.textContent)||'').trim(),detail:dt?dt.href:'',size:t2(['td.sr-col-size','td.hp-td-size']),seeds:t2(['td.sr-col-seeders','td.hp-td-seed']).replace(/[,\u00a0 ]/g,''),uploaded:t2(['td.sr-col-uploaded']),row:row.trim().slice(0,500)};}))"#
    // Challenge sniff: title + the first 2000 chars of visible text.
    static let probeJS = #"((document.title||'')+' '+(document.body?document.body.innerText.slice(0,2000):''))"#

    private static func looksChallenged(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("just a moment") || t.contains("cf-chl") || t.contains("challenge-platform") || t.contains("verify you are human")
    }

    func search(query: String, completion: @escaping (Result<[[String: Any]], MagnetUIndexFailure>) -> Void) {
        begin(query: query, popular: false, completion: completion)
    }
    // Query-less popular listing (owner 2026-11-20): the uindex front page
    // carries Trending tables (live 2026-11-20: 120 magnet rows over 8
    // sections). Same WebKit challenge flow and row collector as a search;
    // one page, no pagination.
    func popular(completion: @escaping (Result<[[String: Any]], MagnetUIndexFailure>) -> Void) {
        begin(query: "", popular: true, completion: completion)
    }
    private func begin(query: String, popular: Bool, completion: @escaping (Result<[[String: Any]], MagnetUIndexFailure>) -> Void) {
        cancel()
        self.completion = completion
        self.query = query
        self.popularMode = popular
        self.page = 1
        self.aggregated = []
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // cf_clearance persists across searches and launches
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768), configuration: config)
        view.navigationDelegate = self
        webView = view
        loadPage()
        let work = DispatchWorkItem(block: { [weak self] in self?.finish(.failure(.cloudflareUnresolved)) })
        deadlineWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + MagnetUIndexProvider.overallTimeout, execute: work)
    }

    // Pages carry 100 rows each; a full page means another page may follow
    // (pagination parameter verified live: search.php?search=X&p=2, &p=3).
    // Post-clearance page loads take ~1-2s.
    private func loadPage() {
        if popularMode {
            guard let url = URL(string: "https://uindex.org/") else { finish(.failure(.requestFormat)); return }
            probes = 0
            webView?.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
            return
        }
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://uindex.org/search.php?search=\(encoded)&p=\(page)") else {
            finish(.failure(.requestFormat)); return
        }
        probes = 0
        webView?.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20))
    }

    func cancel() {
        deadlineWork?.cancel(); deadlineWork = nil
        probeWork?.cancel(); probeWork = nil
        completion = nil
        probes = 0
        aggregated = []
        if let view = webView { view.navigationDelegate = nil; view.stopLoading(); webView = nil }
    }

    private func finish(_ result: Result<[[String: Any]], MagnetUIndexFailure>) {
        guard let done = completion else { return }
        cancel()
        done(result)
    }

    private func probeAndCollect() {
        guard let view = webView else { return }
        view.evaluateJavaScript(MagnetUIndexProvider.probeJS) { [weak self] value, _ in
            guard let self, let view = self.webView else { return }
            if MagnetUIndexProvider.looksChallenged((value as? String) ?? "") {
                self.probes += 1
                if self.probes >= MagnetUIndexProvider.maxProbes { self.finish(.failure(.cloudflareUnresolved)); return }
                let work = DispatchWorkItem(block: { [weak self] in self?.probeAndCollect() })
                self.probeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
                return
            }
            view.evaluateJavaScript(MagnetUIndexProvider.collectJS) { [weak self] raw, _ in
                guard let self else { return }
                guard let json = raw as? String, let data = json.data(using: .utf8),
                      let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                    self.finish(.failure(.requestFormat)); return
                }
                self.aggregated += items
                if !self.popularMode, items.count == 100, self.page < MagnetUIndexProvider.maxPages {
                    self.page += 1
                    self.loadPage()
                } else {
                    self.finish(.success(self.aggregated))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { probeAndCollect() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(.httpOrNetwork))
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(.httpOrNetwork))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish(.failure(.httpOrNetwork)) }
}

final class MagnetBrowserController {
    let panel: MagnetResultsPanel
    private var generation = 0
    private var throttledUntil = Date.distantPast
    private var query = ""
    private var sort = "seeds"
    private var descending = true
    private var parsedProviders: [String:Any] = [:]
    private var failures: [String:String] = [:]
    private var pendingProviders: Set<String> = []
    private let uindexProvider = MagnetUIndexProvider()
    private var tasks: [URLSessionDataTask] = []
    private var sessions: [URLSession] = []
    private var parseSerial = 0
    private var lastResponse: SearchResponse?
    private var verdicts: [String:MagnetVerdict] = [:]
    private var scrapedHashes = Set<String>()
    private let trackerQueue: OperationQueue = {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 8
        queue.qualityOfService = .utility; return queue
    }()
    init(app: AppDelegate, panel: MagnetResultsPanel) {
        self.panel = panel
        panel.onQuery = { [weak self] in self?.search($0) }
        panel.onPopular = { [weak self] in self?.popular() }
        panel.onSort = { [weak self] key, desc in
            guard let self else { return }
            self.sort = key; self.descending = desc
            if let response = self.lastResponse { self.panel.show(response) }
        }
        panel.onSelect = { [weak app] magnet in
            MagnetSelectionTrace.log(app == nil ? "APP_MISSING" : "STREAM_TORRENT_CALL", magnet)
            app?.streamTorrent(magnet)
            MagnetSelectionTrace.log("STREAM_TORRENT_RETURN", magnet)
        }
    }
    func stop() {
        generation += 1; parseSerial += 1
        refreshRevision &+= 1; reparsePending = false
        panel.invalidateSelection()
        pendingProviders.removeAll()
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        sessions.forEach { $0.invalidateAndCancel() }; sessions.removeAll()
        uindexProvider.cancel()
        trackerQueue.cancelAllOperations()
        panel.retireVariation()
    }
    func openSearch() { panel.openSearch() }
    private func search(_ value: String) {
        let q = value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !q.isEmpty, q.count <= 120 else { panel.setStatus("enter a shorter search"); return }
        // A new search always replaces the one in flight: the generation bump
        // below cancels its tasks and sessions, and every callback is ignored
        // unless it still carries the current generation, so no stale rows leak.
        generation += 1; parseSerial += 1; let token = generation
        refreshRevision &+= 1; reparsePending = false
        panel.invalidateSelection()
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        sessions.forEach { $0.invalidateAndCancel() }; sessions.removeAll()
        query = q; parsedProviders = [:]; failures = [:]
        pendingProviders = ["apibay", "bitsearch", "magnetz", "bt4g", "bt4gRecent", "nyaa", "knaben", "eztv", "uindex"]
        lastResponse = nil
        trackerQueue.cancelAllOperations(); verdicts = [:]; scrapedHashes = []
        panel.isHidden = false
        (NSApp.delegate as? AppDelegate)?.controller?.wakeUI()
        panel.setQuery(q)
        let encoded = q.addingPercentEncoding(withAllowedCharacters:.alphanumerics) ?? ""
        guard let primary = URL(string:"https://apibay.org/q.php?q=\(encoded)"),
              let secondary = URL(string:"https://bitsearch.eu/api/v1/search?q=\(encoded)"),
              let tertiary = URL(string:"https://magnetz.eu/api/magnets/search?query=\(encoded)&page=1"),
              let bt4g = URL(string:"https://bt4gprx.com/search?q=\(encoded)&orderby=seeders&p=1&page=rss"),
              let bt4gRecent = URL(string:"https://bt4gprx.com/search?q=\(encoded)&orderby=time&p=1&page=rss"),
              let nyaa = URL(string:"https://nyaa.si/?page=rss&q=\(encoded)"),
              let knaben = URL(string:"https://api.knaben.org/v1"),
              let eztv = URL(string:"https://eztvx.to/api/get-torrents?limit=100&page=1") else {
            panel.setStatus("invalid search"); return
        }
        // Independent providers must not wait on one another's 15s timeout.
        // Every completed source refreshes the same generation's merged rows.
        let body: [String:Any] = ["search_type":"100%", "search_field":"title",
                                 "query":q, "order_by":"seeders",
                                 "order_direction":"desc", "size":300]
        let knabenBody = try? JSONSerialization.data(withJSONObject:body)
        fetch(primary, provider:"apibay", token:token) { [weak self] in self?.parse() }
        fetch(secondary, provider:"bitsearch", token:token) { [weak self] in self?.parse() }
        fetch(tertiary, provider:"magnetz", token:token) { [weak self] in self?.parse() }
        fetch(bt4g, provider:"bt4g", token:token, mime:"application/xml") { [weak self] in self?.parse() }
        fetch(bt4gRecent, provider:"bt4gRecent", token:token, mime:"application/xml") { [weak self] in self?.parse() }
        fetch(nyaa, provider:"nyaa", token:token, mime:"application/xml") { [weak self] in self?.parse() }
        if let knabenBody {
            fetch(knaben, provider:"knaben", token:token, body:knabenBody) { [weak self] in self?.parse() }
        } else { failures["knaben"] = "request_format"; pendingProviders.remove("knaben"); parse() }
        // TV-only: one latest page. A match here does not imply whole-catalogue coverage.
        fetch(eztv, provider:"eztv", token:token) { [weak self] in self?.parse() }
        // uindex.org: Cloudflare managed challenge — routed through a real WebKit
        // engine, never URLSession (see MagnetUIndexProvider).
        uindexProvider.search(query: q) { [weak self] (result: Result<[[String: Any]], MagnetUIndexFailure>) in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.pendingProviders.remove("uindex")
                switch result {
                case .success(let rows): self.parsedProviders["uindex"] = rows
                case .failure(let failure): self.failures["uindex"] = failure.reason
                }
                self.parse()
            }
        }
    }
    // Empty-query Enter (owner 2026-11-20): popular listing. Popular scope
    // (owner-pasted gdb note 2026-11-19, owner instruction 2026-11-20): only
    // providers with a real popular list may be shown as popular;
    // magnetz/bt4g/nyaa/eztv must not. Live endpoint audits this lane ran:
    // 2026-11-20 apibay precompiled top100 endpoints all 404, bitsearch
    // /trending and /popular 500, knaben /popular and /trending 404 and its
    // empty-query search returns zero hits. Re-audit 2026-11-21: apibay
    // data_top100_all.json is live again (200, 100 rows, same field shape as
    // q.php, handled by the existing apibay parse arm), bitsearch and knaben
    // unchanged. uindex.org's front page carries Trending tables, so the
    // popular sources are uindex (WebKit route, same as search) and apibay
    // below. If gdb's package lands with working endpoints for the rest, add
    // them here.
    private func popular() {
        guard Date() >= throttledUntil else { panel.setStatus("wait before searching again"); return }
        throttledUntil = Date().addingTimeInterval(20)
        generation += 1; parseSerial += 1; let token = generation
        refreshRevision &+= 1; reparsePending = false
        panel.invalidateSelection()
        tasks.forEach { $0.cancel() }; tasks.removeAll()
        sessions.forEach { $0.invalidateAndCancel() }; sessions.removeAll()
        query = ""; parsedProviders = [:]; failures = [:]
        pendingProviders = ["uindex", "apibay"]
        lastResponse = nil
        trackerQueue.cancelAllOperations(); verdicts = [:]; scrapedHashes = []
        panel.isHidden = false
        (NSApp.delegate as? AppDelegate)?.controller?.wakeUI()
        panel.setQuery("")
        panel.applySort("seeds", descending: true)
        // apibay precompiled top100 (all-time): plain JSON on the same fetch
        // path as search, same response checks, existing apibay parse arm.
        if let apibayTop = URL(string:"https://apibay.org/precompiled/data_top100_all.json") {
            fetch(apibayTop, provider:"apibay", token:token) { [weak self] in self?.parse() }
        } else { failures["apibay"] = "request_format"; pendingProviders.remove("apibay"); parse() }
        uindexProvider.popular { [weak self] (result: Result<[[String: Any]], MagnetUIndexFailure>) in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.pendingProviders.remove("uindex")
                switch result {
                case .success(let rows): self.parsedProviders["uindex"] = rows
                case .failure(let failure): self.failures["uindex"] = failure.reason
                }
                self.parse()
            }
        }
    }
    private func fetch(_ url: URL, provider: String, token: Int, mime: String = "application/json", body: Data? = nil, done: @escaping () -> Void) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 18
        let session = URLSession(configuration:config, delegate:MagnetJSONRedirectGuard(), delegateQueue:nil)
        var request = URLRequest(url:url, cachePolicy:.reloadIgnoringLocalCacheData, timeoutInterval:15)
        request.setValue(mime, forHTTPHeaderField:"Accept")
        if let body { request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField:"Content-Type"); request.httpBody = body }
        let task = session.dataTask(with:request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { session.invalidateAndCancel(); return }
                self.pendingProviders.remove(provider)
                session.finishTasksAndInvalidate()
                guard error == nil, let http = response as? HTTPURLResponse,
                      http.statusCode == 200, http.url?.scheme == "https", http.url?.host == url.host,
                      http.url?.path == url.path,
                      (http.mimeType?.lowercased() == mime || (mime == "application/xml" && http.mimeType?.lowercased() == "text/xml")),
                      let data, data.count <= 1_000_000,
                      let object: Any = (mime == "application/json" ? (try? JSONSerialization.jsonObject(with:data)) : String(data:data,encoding:.utf8)) else {
                    self.failures[provider] = (response as? HTTPURLResponse)?.statusCode == 429 ? "rate_limited" : "http_or_network"
                    done(); return
                }
                self.parsedProviders[provider] = object
                done()
            }
        }
        sessions.append(session); tasks.append(task); task.resume()
    }
    private var reparsePending = false
    private var refreshRevision: UInt64 = 0
    // Tracker scrapes arrive one by one (up to 25 hashes x trackers). Each used to re-merge,
    // re-sort and rebuild every row at once; coalesce them into one refresh per 0.5 s.
    private func scheduleRefresh() {
        guard !reparsePending else { return }
        reparsePending = true
        let token = generation
        refreshRevision &+= 1
        let refresh = refreshRevision
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.generation == token, self.refreshRevision == refresh else { return }
            self.reparsePending = false
            self.parse(refresh: true)
        }
    }
    private func parse(refresh: Bool = false) {
        MagnetNative.skippedRows = [:]
        var statuses: [String: ProviderStatus] = [:]
        var groups: [[MagnetResult]] = []
        for provider in parsedProviders.keys.sorted() {
            do {
                let rows = try MagnetNative.parse(provider, parsedProviders[provider]!)
                groups.append(rows)
                statuses[provider] = ProviderStatus(status: "ok", reason: nil, pending: nil)
            } catch {
                statuses[provider] = ProviderStatus(status: "unavailable", reason: String(describing:error), pending:nil)
            }
        }
        for (provider, reason) in failures {
            statuses[provider] = ProviderStatus(status:"unavailable", reason:reason, pending:nil)
        }
        for provider in pendingProviders {
            statuses[provider] = ProviderStatus(status:"pending", reason:nil, pending:nil)
        }
        let merged = MagnetNative.merge(groups,query:query)
        let enriched = merged.map { row -> MagnetResult in
            var out = row
            if let hash = row.infoHash { out.verdict = verdicts[hash] }
            return out
        }
        let response = SearchResponse(results:enriched, pendingRows:[], providers:statuses)
        verifyRows(merged)
        lastResponse = response
        panel.show(response, keepScroll: refresh)
        let down = statuses.filter { $0.value.status == "unavailable" }.map { ($0.key, $0.value.reason) }
        let skipped = MagnetNative.skippedRows.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
        panel.setStatus(MagnetProviderStatusLine.line(rows: panel.visibleResultCount, pending: !pendingProviders.isEmpty, unavailable: down)
            + (skipped.isEmpty ? "" : " / skipped rows: " + skipped.joined(separator:", ")))
    }
    // Window A for every row (highest claims first), then one independent window B
    // for rows that look contradicted or dead. Only both windows agreeing may
    // produce those states.
    private static let recheckDelay: TimeInterval = 600
    // Rows verified per search (highest claims first). 25 left most rows on
    // "pending" forever on a full result page (owner log 2026-10-17).
    private static let scrapeCap = 60
    private func verifyRows(_ rows: [MagnetResult]) {
        let token = generation
        let ordered = rows.sorted { ($0.claims.values.max() ?? -1) > ($1.claims.values.max() ?? -1) }
        for row in ordered {
            guard scrapedHashes.count < MagnetBrowserController.scrapeCap, let hash = row.infoHash, !scrapedHashes.contains(hash),
                  let uri = row.magnetUri else { continue }
            scrapedHashes.insert(hash)
            let claim = row.claims.values.max()
            trackerQueue.addOperation { [weak self] in
                let diagnosticOldThreadName = Thread.current.name
                Thread.current.name = "magnet.verify"
                defer { Thread.current.name = diagnosticOldThreadName }
                let a = MagnetVerify.probe(uri: uri, hash: hash, onPositive: { partial in
                    DispatchQueue.main.async {
                        guard let self, self.generation == token else { return }
                        self.verdicts[hash] = MagnetVerify.verdict(claim: claim, a: partial, b: nil)
                        self.scheduleRefresh()
                    }
                })
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.verdicts[hash] = MagnetVerify.verdict(claim: claim, a: a, b: nil)
                    print("[magnet-verdict] \(hash.prefix(8)) src=\(row.source) claim=\(claim.map(String.init) ?? "-") label=\(self.verdicts[hash]?.label ?? "?") rowsChecked=\(self.scrapedHashes.count)/\(MagnetBrowserController.scrapeCap)")
                    self.scheduleRefresh()
                    guard a.window == .zero else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + MagnetBrowserController.recheckDelay) { [weak self] in
                        guard let self, self.generation == token else { return }
                        self.trackerQueue.addOperation { [weak self] in
                            let diagnosticOldThreadName = Thread.current.name
                            Thread.current.name = "magnet.verify"
                            defer { Thread.current.name = diagnosticOldThreadName }
                            let b = MagnetVerify.probe(uri: uri, hash: hash)
                            DispatchQueue.main.async {
                                guard let self, self.generation == token else { return }
                                self.verdicts[hash] = MagnetVerify.verdict(claim: claim, a: a, b: b)
                                self.scheduleRefresh()
                            }
                        }
                    }
                }
            }
        }
    }
}

// All magnet metadata normalization lives with the panel. Reject a provider
// batch on schema drift rather than silently presenting a partial, wrong list.
private enum MagnetFormatError: Error { case layout(String) }
private enum MagnetNative {
    // Rows dropped by row-level tolerance, per provider, for the current parse() pass.
    // Main-thread only (parse() runs on main). Shown in the status line, never silent.
    static var skippedRows: [String: Int] = [:]
    static func fail(_ reason: String) -> MagnetFormatError { .layout(reason) }
    static func text(_ value: Any?, _ label: String) throws -> String {
        guard let s = value as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.count <= 300 else { throw fail(label) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func num(_ value: Any?, _ label: String) throws -> Int64 {
        let number: Int64?
        if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { number = Int64(exactly: n) }
        else if let s = value as? String, s.range(of: #"^(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil { number = Int64(s) }
        else { number = nil }
        guard let n = number, n >= 0 else { throw fail(label) }; return n
    }
    static func hash(_ value: Any?, _ label: String) throws -> String {
        guard let s = value as? String, s.range(of: #"^[0-9a-fA-F]{40}$"#, options: .regularExpression) != nil else { throw fail(label) }
        return s.lowercased()
    }
    static func iso(_ value: Any?, _ label: String) throws -> String {
        guard let s = value as? String, s.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T"#, options: .regularExpression) != nil else { throw fail(label) }
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: s) ?? ISO8601DateFormatter().date(from: s) else { throw fail(label) }
        return fmt.string(from: date)
    }
    static func magnet(_ name: String, _ hash: String) -> String {
        "magnet:?xt=urn:btih:\(hash)&dn=\(name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
    }
    static func row(_ source: String, _ name: String, _ hash: String, _ size: Int64?, _ seeds: Int?, _ date: String?, _ detail: String = "", uri: String? = nil) -> MagnetResult {
        MagnetResult(title: name, sizeBytes: size, seeds: seeds, magnetUri: uri ?? magnet(name,hash), uploadedAt: date, uploadedLabel: nil, infoHash: hash, source: source, detailUrl: detail)
    }
    static func dict(_ value: Any?, _ label: String) throws -> [String: Any] {
        guard let d = value as? [String: Any] else { throw fail(label) }; return d
    }
    static func array(_ value: Any?, _ max: Int, _ label: String) throws -> [[String:Any]] {
        guard let a = value as? [[String:Any]], a.count <= max else { throw fail(label) }; return a
    }
    static func matches(_ pattern: String, _ input: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        let ns = input as NSString
        return re.matches(in: input, range: NSRange(location:0,length:ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at:$0).location == NSNotFound ? "" : ns.substring(with:m.range(at:$0)) }
        }
    }
    static func first(_ pattern: String, _ input: String) -> String? { matches(pattern,input).first?.dropFirst().first }
    static func unescape(_ s: String) -> String {
        var result=s
        for (a,b) in [("&amp;","&"),("&quot;","\""),("&apos;","'"),("&lt;","<"),("&gt;",">")] { result=result.replacingOccurrences(of:a,with:b) }
        return result
    }
    static func field(_ tag: String, _ xml: String) -> String {
        unescape(first("<\(NSRegularExpression.escapedPattern(for:tag))(?:\\s+[^>]*)?>([\\s\\S]*?)</\(NSRegularExpression.escapedPattern(for:tag))>",xml) ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
    }
    static func date(_ value: Any?, _ label: String) throws -> String {
        guard let s=value as? String, let d=DateFormatter.rfc2822.date(from:s) else { throw fail(label) }
        return ISO8601DateFormatter().string(from:d)
    }
    static func size(_ s:String, binary:Bool=false, _ label:String) throws -> Int64 {
        guard let m=matches(#"^([0-9]+(?:\.[0-9]+)?)\s*(B|KiB|MiB|GiB|TiB|KB|MB|GB|TB)$"#,s).first,
              let n=Double(m[1]), n >= 0 else {throw fail(label)}
        let unit=m[2].lowercased(), power=["b":0,"kb":1,"mb":2,"gb":3,"tb":4,"kib":1,"mib":2,"gib":3,"tib":4][unit] ?? 0
        let result=n*pow((binary || unit.contains("i")) ? 1024.0 : 1000.0,Double(power))
        guard result.isFinite, result <= Double(Int64.max) else {throw fail(label)}
        return Int64(result.rounded())
    }
    static func normalized(_ s:String) -> [String] {
        s.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:Locale(identifier:"en_US_POSIX"))
         .lowercased().components(separatedBy:CharacterSet.alphanumerics.inverted).filter{ !$0.isEmpty }
    }
    static func merge(_ groups:[[MagnetResult]], query:String) -> [MagnetResult] {
        let terms=normalized(query)
        var rows:[String:MagnetResult]=[:]
        var claims:[String:[String:Int]]=[:]
        // An empty term list (popular listing, no typed query) keeps every row;
        // a typed query still requires all terms, unchanged.
        for r in groups.flatMap({$0}) where !r.hasExecutableTitle && (terms.isEmpty || terms.allSatisfy({normalized(r.title).joined(separator:" ").contains($0)})) {
            // Regex, not URLComponents: the two Foundation implementations parse
            // long magnet URIs differently, and a silent mismatch here drops rows.
            // Drops are counted so the status line names them ("_merge N").
            guard let h=r.infoHash, h.range(of:#"^[0-9a-f]{40}$"#,options:.regularExpression) != nil,
                  let u=r.magnetUri, first(#"[?&]xt=urn:btih:([0-9a-fA-F]{40})"#,u)?.lowercased()==h else { skippedRows["_merge",default:0]+=1; continue }
            if let seeds=r.seeds {claims[h,default:[:]][r.source]=max(claims[h]?[r.source] ?? 0,seeds)}
            // One row per (hash, source): cross-provider duplicates stay visible
            // under their own source label (owner 2026-10-17: "eksik olmayacak").
            // Within a source, keep the row that carries its own trackers.
            let key="\(h)|\(r.source)"
            if rows[key] == nil || (rows[key]?.magnetUri?.contains("tr=") != true && r.magnetUri?.contains("tr=") == true) {rows[key]=r}
        }
        return rows.map { var r=$0.value; r.claims=claims[String($0.key.prefix(40))] ?? [:]; return r }
    }
    // Sort model (owner 2026-10-17): default = uindex first, then bt4g, then the
    // rest; inside every sort the tiebreak is seeds high-to-low (verified when
    // present, else the source's own claim), then title.
    static func sourceRank(_ source: String) -> Int {
        source == "uindex" ? 0 : (source == "bt4g" || source == "bt4gRecent") ? 1 : 2
    }
    static func sortSeeds(_ r: MagnetResult) -> Int64 {
        if let v = r.verdict, v.state == .verified, let vs = v.verifiedSeeds { return Int64(vs) }
        return Int64(r.claims.values.max() ?? r.seeds ?? -1)
    }
    // "1.6 years ago" (uindex) -> an absolute ISO date, computed against now.
    // Unknown formats return nil (undated) rather than a wrong date.
    static func relativeDateISO(_ s: String) -> String? {
        guard let m = matches(#"^([0-9]+(?:\.[0-9]+)?)\s*(second|minute|hour|day|week|month|year)s?\s*ago$"#, s.lowercased()).first,
              let v = Double(m[1]) else { return nil }
        let seconds: [String: Double] = ["second": 1, "minute": 60, "hour": 3600, "day": 86400,
                                         "week": 604800, "month": 2629800, "year": 31557600]
        guard let unit = seconds[m[2]] else { return nil }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -v * unit))
    }
    static func sortRows(_ input: [MagnetResult], key: String, descending: Bool) -> [MagnetResult] {
        let isoDate = DateFormatter(); isoDate.locale = Locale(identifier: "en_US_POSIX"); isoDate.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        return input.sorted { a, b in
            let tie: () -> Bool = {
                let x = sortSeeds(a), y = sortSeeds(b)
                if x != y { return x > y }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
            switch key {
            case "priority":
                let ra = sourceRank(a.source), rb = sourceRank(b.source)
                if ra != rb { return ra < rb }
                return tie()
            case "title":
                let c = a.title.localizedStandardCompare(b.title)
                if c != .orderedSame { return descending ? c == .orderedDescending : c == .orderedAscending }
                return tie()
            case "source":
                if a.source != b.source { return descending ? a.source > b.source : a.source < b.source }
                return tie()
            case "sizeBytes":
                let x = a.sizeBytes, y = b.sizeBytes
                if x == nil || y == nil { return x != nil && y == nil }
                if x != y { return descending ? x! > y! : x! < y! }
                return tie()
            case "seeds":
                let x = a.verdict.flatMap { $0.state == .verified ? $0.verifiedSeeds.map(Int64.init) : nil }
                let y = b.verdict.flatMap { $0.state == .verified ? $0.verifiedSeeds.map(Int64.init) : nil }
                if x == nil || y == nil { return x != nil && y == nil }
                if x != y { return descending ? x! > y! : x! < y! }
                return tie()
            default: // uploadedAt
                let x = a.uploadedAt.flatMap { isoDate.date(from:$0) ?? ISO8601DateFormatter().date(from:$0) }
                let y = b.uploadedAt.flatMap { isoDate.date(from:$0) ?? ISO8601DateFormatter().date(from:$0) }
                if x == nil || y == nil { return x != nil && y == nil }
                if x != y { return descending ? x! > y! : x! < y! }
                return tie()
            }
        }
    }
    // ===== Panel virtualization (v22.17) - pure math, Linux-tested =====
    // The panel renders only the rows intersecting the viewport (plus an
    // overscan buffer) into a fixed pool of row views; scrolling reassigns
    // pool slots. View count stays ~poolSize regardless of row count.
    static let virtualOverscan = 3
    static func poolSize(viewportHeight: Double, rowHeight: Double, overscan: Int = virtualOverscan) -> Int {
        guard rowHeight > 0, viewportHeight > 0 else { return 2 * overscan + 1 }
        return Int((viewportHeight / rowHeight).rounded(.up)) + 2 * overscan + 1
    }
    // Row indices intersecting [offsetY, offsetY+viewportHeight], widened by
    // overscan rows on both sides, clamped to 0..<rowCount.
    static func visibleRange(offsetY: Double, viewportHeight: Double, rowCount: Int, rowHeight: Double, overscan: Int = virtualOverscan) -> Range<Int> {
        guard rowCount > 0, rowHeight > 0 else { return 0..<0 }
        // Clamp to the last page: a stale saved offset (list shrank since)
        // must show the tail, never an empty range.
        let maxY = Swift.max(0, Double(rowCount) * rowHeight - viewportHeight)
        let y = min(Swift.max(0, offsetY), maxY)
        let first = max(0, Int(y / rowHeight) - overscan)
        let lastVisible = Int(((y + viewportHeight) / rowHeight).rounded(.up)) - 1
        let end = min(rowCount, max(first, lastVisible + 1 + overscan))
        return first..<max(first, end)
    }
    static func maxOffsetY(rowCount: Int, rowHeight: Double, viewportHeight: Double) -> Double {
        max(0, Double(rowCount) * rowHeight - viewportHeight)
    }
    // Positional mapping: pool slot i renders row range.lowerBound + i.
    // Returns only valid (slot, row) pairs; slots beyond the range stay hidden.
    static func slotAssignments(poolSize: Int, range: Range<Int>, rowCount: Int) -> [(slot: Int, row: Int)] {
        var out: [(Int, Int)] = []
        let n = min(poolSize, range.count)
        for i in 0..<n { out.append((i, range.lowerBound + i)) }
        return out
    }
    static func topBySeeds(_ input: [MagnetResult], limit: Int) -> [MagnetResult] {
        if input.count <= limit { return input }
        return Array(input.sorted { sortSeeds($0) > sortSeeds($1) }.prefix(limit))
    }
    static func parse(_ provider:String, _ payload:Any) throws -> [MagnetResult] {
        switch provider {
        case "apibay":
            let a=try array(payload,100,"apibay:envelope")
            if a.count==1, (a[0]["id"] as? String)=="0", (a[0]["name"] as? String)=="No results returned", (a[0]["info_hash"] as? String)==String(repeating:"0",count:40) {return []}
            return try a.map { x in
                let id=try num(x["id"],"apibay:id"); if id==0 {throw fail("apibay:id")}
                let ts=try num(x["added"],"apibay:date"); if ts > 4102444800 {throw fail("apibay:date")}
                return try row("apibay",text(x["name"],"apibay:title"),hash(x["info_hash"],"apibay:hash"),num(x["size"],"apibay:size"),Int(num(x["seeders"],"apibay:seeds")),ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:Double(ts))))
            }
        case "bitsearch":
            let root=try dict(payload,"bitsearch:envelope")
            guard (root["success"] as? Bool)==true, root["pagination"] is [String:Any] else {throw fail("bitsearch:envelope")}
            return try array(root["results"],20,"bitsearch:results").map {x in
                guard let id=x["id"] as? String,id.range(of:#"^[a-fA-F0-9]{24}$"#,options:.regularExpression) != nil else {throw fail("bitsearch:id")}
                return try row("bitsearch",text(x["title"],"bitsearch:title"),hash(x["infohash"],"bitsearch:hash"),num(x["size"],"bitsearch:size"),Int(num(x["seeders"],"bitsearch:seeds")),iso(x["updatedAt"],"bitsearch:date"))
            }
        case "magnetz":
            let root=try dict(payload,"magnetz:envelope")
            guard root["meta"] is [String:Any] else {throw fail("magnetz:meta")}
            return try array(root["data"],25,"magnetz:data").map {x in
                guard let id=x["sqid"] as? String,id.range(of:#"^[a-zA-Z0-9]{4,24}$"#,options:.regularExpression) != nil else {throw fail("magnetz:id")}
                let h=try hash(x["info_hash"],"magnetz:hash")
                guard let uri=x["magnet_link"] as? String, first(#"[?&]xt=urn:btih:([0-9a-fA-F]{40})"#,uri)?.lowercased()==h else {throw fail("magnetz:magnet")}
                return try row("magnetz",text(x["name"],"magnetz:title"),h,num(x["size"],"magnetz:size"),Int(num(x["seeders"],"magnetz:seeds")),iso(x["created_at"],"magnetz:date"))
            }
        case "knaben":
            let root=try dict(payload,"knaben:envelope")
            guard root["total"] is [String:Any] else {throw fail("knaben:total")}
            // Row-level drift drops that row only (counted); envelope drift above still fails the provider.
            return try array(root["hits"],300,"knaben:hits").compactMap {x -> MagnetResult? in
              do {
                // The API documents non-magnet indexer hits with both fields null.
                // They are not magnets; do not let them invalidate valid neighbours.
                if (x["hash"] == nil || x["hash"] is NSNull) && (x["magnetUrl"] == nil || x["magnetUrl"] is NSNull) { return nil }
                let h=try hash(x["hash"],"knaben:hash")
                guard let uri=x["magnetUrl"] as? String, uri.hasPrefix("magnet:?"),first(#"[?&]xt=urn:btih:([0-9a-fA-F]{40})"#,uri)?.lowercased()==h else {throw fail("knaben:magnet")}
                return try row("knaben",text(x["title"],"knaben:title"),h,num(x["bytes"],"knaben:bytes"),Int(num(x["seeders"],"knaben:seeds")),iso(x["date"],"knaben:date"),x["details"] as? String ?? "")
              } catch { skippedRows["knaben", default: 0] += 1; return nil }
            }
        case "eztv":
            let root=try dict(payload,"eztv:envelope")
            _=try num(root["torrents_count"],"eztv:count"); _=try num(root["limit"],"eztv:limit"); _=try num(root["page"],"eztv:page")
            return try array(root["torrents"],100,"eztv:torrents").map {x in
                _=try num(x["id"],"eztv:id"); let h=try hash(x["hash"],"eztv:hash")
                guard let uri=x["magnet_url"] as? String,uri.hasPrefix("magnet:?"),first(#"[?&]xt=urn:btih:([0-9a-fA-F]{40})"#,uri)?.lowercased()==h else {throw fail("eztv:magnet")}
                let ts=try num(x["date_released_unix"],"eztv:date");if ts>4102444800 {throw fail("eztv:date")}
                return try row("eztv",text(x["title"],"eztv:title"),h,num(x["size_bytes"],"eztv:size"),Int(num(x["seeds"],"eztv:seeds")),ISO8601DateFormatter().string(from:Date(timeIntervalSince1970:Double(ts))))
            }
        case "bt4g","bt4gRecent":
            guard let xml=payload as? String,xml.count <= 1_000_000,xml.range(of:#"^\s*<rss\s+version="2\.0""#,options:.regularExpression) != nil else {throw fail("bt4g:rss")}
            let items=matches(#"<item>[\s\S]*?</item>"#,xml).map{$0[0]};if items.count>100 {throw fail("bt4g:items")}
            return try items.map { item in
                let name=try text(field("title",item),"bt4g:title")
                let uri=field("link",item)
                guard uri.hasPrefix("magnet:?"),let h=first(#"[?&]xt=urn:btih:([0-9a-fA-F]{40})"#,uri)?.lowercased() else {throw fail("bt4g:magnet")}
                let validHash=try hash(h,"bt4g:hash")
                let detail=field("guid",item)
                guard let url=URL(string:detail),url.scheme=="https",url.host=="bt4gprx.com",url.path.range(of:#"^/magnet/[a-zA-Z0-9]+$"#,options:.regularExpression) != nil else {throw fail("bt4g:guid")}
                guard let desc=first(#"<description><!\[CDATA\[([\s\S]*?)\]\]></description>"#,item) else {throw fail("bt4g:description")}
                let pieces=desc.replacingOccurrences(of:#"(?i)<br\s*/?>"#,with:"\u{0001}",options:.regularExpression).components(separatedBy:"\u{0001}").map{$0.trimmingCharacters(in:.whitespacesAndNewlines)}
                guard pieces.count==4,pieces[3].lowercased()==validHash else {throw fail("bt4g:description")}
                return try row("bt4g",name,validHash,size(pieces[1],"bt4g:size"),nil,date(field("pubDate",item),"bt4g:date"),detail,uri:uri)
            }
        case "nyaa":
            guard let xml=payload as? String,xml.count<=1_000_000,xml.contains("<rss") else {throw fail("nyaa:rss")}
            let items=matches(#"<item>[\s\S]*?</item>"#,xml).map{$0[0]};if items.count>100 {throw fail("nyaa:items")}
            return try items.map {item in
                let name=try text(field("title",item),"nyaa:title")
                let h=try hash(field("nyaa:infoHash",item),"nyaa:hash")
                let link=field("link",item)
                guard link.range(of:#"^https://nyaa\.si/(view|download)/[0-9]+(?:\.torrent)?$"#,options:.regularExpression) != nil else {throw fail("nyaa:link")}
                return try row("nyaa",name,h,size(field("nyaa:size",item),binary:true,"nyaa:size"),Int(num(field("nyaa:seeders",item),"nyaa:seeds")),date(field("pubDate",item),"nyaa:date"))
            }
        case "uindex":
            // Collector output: magnet-anchored rows from a real WebKit page.
            // Live layout (verified 2026-10-17 on the real results DOM):
            // td.sr-col-name holds the magnet anchor plus the details.php title
            // anchor; td.sr-col-size / td.sr-col-seeders / td.sr-col-uploaded
            // carry claims. Every field falls back to row-text / dn= so a
            // layout change degrades instead of breaking. Malformed rows drop
            // and count, never fail the provider. seeds/size stay claims -
            // the verdict verifies truth.
            return try array(payload,2000,"uindex:rows").compactMap { x -> MagnetResult? in
              do {
                // text() caps at 300 chars; real uindex magnets carry 8 trackers
                // and run 400-700 chars (measured on the live DOM 2026-10-17), so
                // the magnet gets its own extraction with a 4096 abuse cap.
                guard let uri=(x["magnet"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines),
                      !uri.isEmpty, uri.count<=4096 else { throw fail("uindex:magnet") }
                guard uri.hasPrefix("magnet:?"),
                      let h=first(#"[?&]xt=urn:btih:([0-9a-fA-F]{40})"#,uri)?.lowercased() else {throw fail("uindex:magnet")}
                let validHash=try hash(h,"uindex:hash")
                var name=(x["title"] as? String ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
                if name.isEmpty, let dn=first(#"[?&]dn=([^&]{1,300})"#,uri) { name=dn.removingPercentEncoding ?? dn }
                guard !name.isEmpty else { throw fail("uindex:title") }
                let rowText=(x["row"] as? String) ?? ""
                var sizeBytes:Int64?=nil
                if let fs=(x["size"] as? String), !fs.isEmpty { sizeBytes=try? size(fs,"uindex:size") }
                if sizeBytes==nil, let sm=matches(#"([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB|KB|MB|GB|TB))"#,rowText).first {
                    sizeBytes=try? size(sm[1],"uindex:size")
                }
                var seeds:Int?=nil
                if let ss=(x["seeds"] as? String), let n=Int(ss.trimmingCharacters(in:.whitespaces)), n>=0, n<=100000 { seeds=n }
                if seeds==nil, let sm=matches(#"([0-9]+(?:\.[0-9]+)?\s*(?:B|KiB|MiB|GiB|TiB|KB|MB|GB|TB))"#,rowText).first {
                    let tail=rowText.components(separatedBy:sm[1]).dropFirst().joined(separator:" ")
                    if let n=matches(#"(?<![0-9.])([0-9]{1,6})(?![0-9.])"#,tail).first.flatMap({Int($0[1])}), n<=100000 { seeds=n }
                }
                let uploaded=(x["uploaded"] as? String)?.trimmingCharacters(in:.whitespacesAndNewlines)
                let uploadedISO=uploaded.flatMap { $0.isEmpty ? nil : relativeDateISO($0) }
                let detail=((x["detail"] as? String) ?? "").hasPrefix("https://uindex.org/") ? (x["detail"] as! String) : "https://uindex.org/"
                return row("uindex",name,validHash,sizeBytes,seeds,uploadedISO,detail,uri:uri)
              } catch { skippedRows["uindex",default:0]+=1; return nil }
            }
        default: throw fail("unknown provider")
        }
    }
}
private extension DateFormatter {
    static var rfc2822: DateFormatter {
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(secondsFromGMT:0)
        f.dateFormat="EEE,dd MMM yyyy HH:mm:ss Z";return f
    }
}

// BEP 15 swarm metadata only. No torrent payload is downloaded.
private enum MagnetTracker {
    static func scrape(_ tracker: String, hash: String, timeoutMS: Int32 = 4000) -> (seeders: Int, peers: Int)? {
        guard let url = URL(string:tracker), url.scheme == "udp", let host = url.host,
              let port = url.port, (1...65535).contains(port),
              hash.range(of:#"^[0-9a-f]{40}$"#,options:.regularExpression) != nil else { return nil }
        var hints = addrinfo()
        hints.ai_family = AF_INET
        #if os(Linux)
        hints.ai_socktype = Int32(SOCK_DGRAM.rawValue)
        #else
        hints.ai_socktype = SOCK_DGRAM
        #endif
        hints.ai_protocol = Int32(IPPROTO_UDP)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let address = info else { return nil }
        defer { freeaddrinfo(info) }
        let fd = socket(address.pointee.ai_family, address.pointee.ai_socktype, address.pointee.ai_protocol)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard connect(fd, address.pointee.ai_addr, address.pointee.ai_addrlen) == 0 else { return nil }
        let deadline = Date().addingTimeInterval(Double(timeoutMS)/1000)
        func word(_ value: UInt32) -> [UInt8] {
            [UInt8(truncatingIfNeeded:value >> 24), UInt8(truncatingIfNeeded:value >> 16),
             UInt8(truncatingIfNeeded:value >> 8), UInt8(truncatingIfNeeded:value)]
        }
        func number(_ bytes: [UInt8], _ at: Int) -> UInt32 {
            (UInt32(bytes[at]) << 24) | (UInt32(bytes[at+1]) << 16) | (UInt32(bytes[at+2]) << 8) | UInt32(bytes[at+3])
        }
        func exchange(_ packet: [UInt8], action: UInt32, transaction: UInt32, minimum: Int) -> [UInt8]? {
            let sent = packet.withUnsafeBytes { send(fd,$0.baseAddress,packet.count,0) }
            guard sent == packet.count else { return nil }
            while Date() < deadline {
                var waiter = pollfd(fd:fd,events:Int16(POLLIN),revents:0)
                let remaining = Int32(max(1,deadline.timeIntervalSinceNow*1000))
                guard poll(&waiter,1,remaining) > 0 else { return nil }
                var bytes = [UInt8](repeating:0,count:2048)
                let length = bytes.withUnsafeMutableBytes { recv(fd,$0.baseAddress,2048,0) }
                guard length >= 8 else { continue }
                if number(bytes,4) != transaction { continue }
                guard number(bytes,0) == action, length >= minimum else { return nil }
                return Array(bytes.prefix(length))
            }
            return nil
        }
        let connectID = UInt32.random(in:UInt32.min...UInt32.max)
        let request:[UInt8] = [0,0,4,23,39,16,25,128] + word(0) + word(connectID)
        guard let response = exchange(request,action:0,transaction:connectID,minimum:16) else { return nil }
        let scrapeID = UInt32.random(in:UInt32.min...UInt32.max)
        var hashBytes:[UInt8] = []
        var index = hash.startIndex
        for _ in 0..<20 {
            let end = hash.index(index,offsetBy:2)
            guard let byte = UInt8(hash[index..<end],radix:16) else { return nil }
            hashBytes.append(byte); index = end
        }
        let scrapePacket = Array(response[8..<16]) + word(2) + word(scrapeID) + hashBytes
        guard let answer = exchange(scrapePacket,action:2,transaction:scrapeID,minimum:20) else { return nil }
        let seeders = Int(number(answer,8))
        return (seeders, seeders + Int(number(answer,16)))
    }
    // The magnet's own trackers (first 4 valid) plus a fixed public fallback set.
    static let fallback = ["udp://tracker.opentrackr.org:1337/announce", "udp://open.stealth.si:80/announce",
                           "udp://tracker.torrent.eu.org:451/announce"]
    static func trackers(_ uri: String) -> [String] {
        var own: [String] = []
        for item in (URLComponents(string:uri)?.queryItems ?? []) where item.name == "tr" {
            guard let value = item.value, let url = URL(string:value), url.host != nil,
                  ["udp","http","https"].contains(url.scheme ?? ""), !own.contains(value) else { continue }
            own.append(value)
        }
        let first = Array(own.prefix(4))
        return first + fallback.filter { !first.contains($0) }
    }
    static func hashBytes(_ hash: String) -> [UInt8] {
        stride(from:0, to:hash.count - 1, by:2).compactMap {
            UInt8(hash[hash.index(hash.startIndex,offsetBy:$0)..<hash.index(hash.startIndex,offsetBy:$0+2)], radix:16)
        }
    }
    // BEP 48 HTTP(S) scrape: announce URL -> scrape URL, bencoded files[hash].
    static func httpScrape(_ tracker: String, hash: String, timeout: TimeInterval = 4) -> (seeders: Int, peers: Int)? {
        guard var parts = URLComponents(string:tracker), ["http","https"].contains(parts.scheme ?? ""),
              parts.path.hasSuffix("/announce"),
              hash.range(of:#"^[0-9a-f]{40}$"#,options:.regularExpression) != nil else { return nil }
        let raw = hashBytes(hash)
        parts.path = String(parts.path.dropLast("announce".count)) + "scrape"
        parts.percentEncodedQuery = "info_hash=" + raw.map { String(format:"%%%02x", $0) }.joined()
        guard let url = parts.url else { return nil }
        final class Box { var data: Data? }
        let box = Box(); let done = DispatchSemaphore(value:0)
        let task = URLSession.shared.dataTask(with: URLRequest(url:url, timeoutInterval:timeout)) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { box.data = data }
            done.signal()
        }
        task.resume()
        guard done.wait(timeout:.now()+timeout+1) == .success, let data = box.data, data.count <= 65536 else { task.cancel(); return nil }
        let bytes = [UInt8](data); var at = 0
        guard case .dict(let root)? = Bencode.parse(bytes,&at), case .dict(let files)? = root[Array("files".utf8)],
              case .dict(let entry)? = files[raw],
              case .int(let seeders)? = entry[Array("complete".utf8)],
              case .int(let leechers)? = entry[Array("incomplete".utf8)] else { return nil }
        return (seeders, seeders + leechers)
    }
}

// Minimal bencode reader for tracker and DHT replies. Rejects anything malformed.
private indirect enum Bencode {
    case int(Int), bytes([UInt8]), list([Bencode]), dict([[UInt8]: Bencode])
    static func parse(_ b: [UInt8], _ i: inout Int, depth: Int = 0) -> Bencode? {
        guard i < b.count, depth < 8 else { return nil }
        switch b[i] {
        case UInt8(ascii:"i"):
            guard let end = b[i...].firstIndex(of:UInt8(ascii:"e")),
                  let n = Int(String(decoding:b[(i+1)..<end],as:UTF8.self)) else { return nil }
            i = end + 1; return .int(n)
        case UInt8(ascii:"l"):
            i += 1; var items: [Bencode] = []
            while i < b.count, b[i] != UInt8(ascii:"e") { guard let v = parse(b,&i,depth:depth+1) else { return nil }; items.append(v) }
            guard i < b.count else { return nil }; i += 1; return .list(items)
        case UInt8(ascii:"d"):
            i += 1; var map: [[UInt8]: Bencode] = [:]
            while i < b.count, b[i] != UInt8(ascii:"e") {
                guard case .bytes(let k)? = parse(b,&i,depth:depth+1), let v = parse(b,&i,depth:depth+1) else { return nil }
                map[k] = v
            }
            guard i < b.count else { return nil }; i += 1; return .dict(map)
        default:
            guard let colon = b[i...].firstIndex(of:UInt8(ascii:":")),
                  let n = Int(String(decoding:b[i..<colon],as:UTF8.self)), n >= 0, colon + 1 + n <= b.count else { return nil }
            i = colon + 1 + n; return .bytes(Array(b[(colon+1)..<(colon+1+n)]))
        }
    }
}

// Verification layers and classification. window/verdict are pure and carry the
// frozen rules: claim floor 50, >=2 independent layers, two agreeing windows.
private enum MagnetVerify {
    static let claimFloor = 50
    static func window(_ probes: [MagnetProbe]) -> MagnetWindow {
        if probes.contains(where:{ ($0.seeders ?? 0) >= 1 || $0.peers >= 1 }) { return .positive }
        let zero = Set(probes.filter{ ($0.seeders ?? 0) == 0 && $0.peers == 0 }.map(\.layer))
        return zero.count >= 2 ? .zero : .inconclusive
    }
    static func verdict(claim: Int?, a: MagnetProbeResult, b: MagnetProbeResult?) -> MagnetVerdict {
        func make(_ state: MagnetState) -> MagnetVerdict {
            MagnetVerdict(state:state, verifiedSeeds:[a.seeds, b?.seeds].compactMap { $0 }.max(), verifiedPeers:max(a.peers,b?.peers ?? 0))
        }
        switch a.window {
        case .positive: return make(.verified)
        case .inconclusive: return make(.unverifiedTimeout)
        case .zero:
            guard let b else { return make(.unverifiedTimeout) }
            switch b.window {
            case .positive: return make(.unverifiedDisagreement)
            case .inconclusive: return make(.unverifiedTimeout)
            case .zero: return make((claim ?? 0) >= claimFloor ? .contradicted : .dead)
            }
        }
    }
    // One window: UDP/HTTP scrape per tracker plus a bounded DHT lookup, run together.
    static func probe(uri: String, hash: String,
                      onPositive: ((MagnetProbeResult) -> Void)? = nil) -> MagnetProbeResult {
        let lock = NSLock(); var probes: [MagnetProbe] = []
        var publishedPositive = false
        let group = DispatchGroup()
        func add(_ p: MagnetProbe?) {
            guard let p else { return }
            var partial: MagnetProbeResult?
            lock.lock()
            probes.append(p)
            if !publishedPositive, (p.seeders ?? 0) > 0 || p.peers > 0 {
                publishedPositive = true
                partial = MagnetProbeResult(window: .positive,
                    seeds: probes.compactMap(\.seeders).max(),
                    peers: probes.map(\.peers).max() ?? 0)
            }
            // This private callback only enqueues to main. Enqueue before unlocking
            // so the worker's final publication cannot overtake the partial one.
            if let partial { onPositive?(partial) }
            lock.unlock()
        }
        for tracker in MagnetTracker.trackers(uri) {
            group.enter()
            DispatchQueue.global(qos:.utility).async {
                let diagnosticOldThreadName = Thread.current.name
                Thread.current.name = tracker.hasPrefix("udp://") ? "magnet.udp" : "magnet.http"
                defer { Thread.current.name = diagnosticOldThreadName }
                if tracker.hasPrefix("udp://") {
                    add(MagnetTracker.scrape(tracker,hash:hash).map { MagnetProbe(layer:.udp, seeders:$0.seeders, peers:$0.peers) })
                } else {
                    add(MagnetTracker.httpScrape(tracker,hash:hash).map { MagnetProbe(layer:.http, seeders:$0.seeders, peers:$0.peers) })
                }
                group.leave()
            }
        }
        group.enter()
        DispatchQueue.global(qos:.utility).async {
            let diagnosticOldThreadName = Thread.current.name
            Thread.current.name = "magnet.dht"
            defer { Thread.current.name = diagnosticOldThreadName }
            // Release the queue slot's wait as soon as any layer published a
            // positive: the DHT tail (seconds) must not stall the other rows.
            add(MagnetDHT.lookup(hash:hash, shouldStop: {
                lock.lock(); defer { lock.unlock() }; return publishedPositive
            })); group.leave()
        }
        group.wait()
        lock.lock(); defer { lock.unlock() }
        let result = MagnetProbeResult(window:window(probes), seeds:probes.compactMap(\.seeders).max(),
                                       peers:probes.map(\.peers).max() ?? 0)
        // Diagnostic: which layers answered. Without this a "?" cannot be told apart from a blocked tracker.
        let layers = probes.map { "\($0.layer):\($0.seeders.map(String.init) ?? "-")/\($0.peers)" }.joined(separator:",")
        print("[magnet-verify] \(hash.prefix(8)) window=\(result.window) answered=\(probes.count)/\(MagnetTracker.trackers(uri).count + 1) layers=[\(layers)]")
        return result
    }
}

// BEP 5 get_peers lookup, 4 s budget. A zero needs >=3 distinct replying nodes;
// fewer replies is silence, not evidence. The 600 s recheck window supplies the
// second opinion, so the first window does not need 8 s of queue-slot patience.
private enum MagnetDHT {
    static let routers = [("router.bittorrent.com","6881"),("dht.transmissionbt.com","6881"),("router.utorrent.com","6881")]
    private struct Node: Hashable { let ip: UInt32; let port: UInt16 }
    static func lookup(hash: String, budgetMS: Int = 4000, shouldStop: (() -> Bool)? = nil) -> MagnetProbe? {
        let target = MagnetTracker.hashBytes(hash)
        guard target.count == 20 else { return nil }
        let fd = socket(AF_INET, SOCK_DGRAM, 0); guard fd >= 0 else { return nil }
        defer { close(fd) }
        let ownID = (0..<20).map { _ in UInt8.random(in:0...255) }
        let query: [UInt8] = Array("d1:ad2:id20:".utf8) + ownID + Array("9:info_hash20:".utf8) + target
            + Array("e1:q9:get_peers1:t2:aa1:y1:qe".utf8)
        var ids: [Node: [UInt8]] = [:], asked = Set<Node>(), responders = Set<Node>(), values = Set<[UInt8]>()
        for (host, port) in routers {
            var hints = addrinfo(); hints.ai_family = AF_INET; hints.ai_socktype = SOCK_DGRAM
            var info: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(host, port, &hints, &info) == 0, let found = info else { continue }
            defer { freeaddrinfo(info) }
            found.pointee.ai_addr.withMemoryRebound(to:sockaddr_in.self, capacity:1) {
                ids[Node(ip:$0.pointee.sin_addr.s_addr, port:UInt16(bigEndian:$0.pointee.sin_port))] = [UInt8](repeating:0xff,count:20)
            }
        }
        func distance(_ id: [UInt8]) -> [UInt8] { zip(id, target).map { $0 ^ $1 } }
        let deadline = Date().addingTimeInterval(Double(budgetMS)/1000)
        while Date() < deadline && shouldStop?() != true {
            let next = ids.keys.filter { !asked.contains($0) }
                .sorted { distance(ids[$0]!).lexicographicallyPrecedes(distance(ids[$1]!)) }.prefix(8)
            for node in next {
                asked.insert(node)
                var sin = sockaddr_in(); sin.sin_family = sa_family_t(AF_INET)
                sin.sin_port = node.port.bigEndian; sin.sin_addr.s_addr = node.ip
                _ = withUnsafePointer(to:&sin) { $0.withMemoryRebound(to:sockaddr.self, capacity:1) {
                    sendto(fd, query, query.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            }
            var waiter = pollfd(fd:fd, events:Int16(POLLIN), revents:0)
            while Date() < deadline {
                let remainingMS = Int32(max(1, min(300, deadline.timeIntervalSinceNow * 1000)))
                guard poll(&waiter, 1, remainingMS) > 0, Date() < deadline else { break }
                var buffer = [UInt8](repeating:0, count:4096)
                var from = sockaddr_in(); var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let got = withUnsafeMutablePointer(to:&from) { $0.withMemoryRebound(to:sockaddr.self, capacity:1) {
                    recvfrom(fd, &buffer, buffer.count, 0, $0, &length) } }
                guard got > 0 else { break }
                var at = 0
                guard case .dict(let top)? = Bencode.parse(Array(buffer.prefix(got)), &at),
                      case .dict(let reply)? = top[Array("r".utf8)] else { continue }
                responders.insert(Node(ip:from.sin_addr.s_addr, port:UInt16(bigEndian:from.sin_port)))
                if case .list(let list)? = reply[Array("values".utf8)] {
                    for case .bytes(let peer) in list where peer.count == 6 { values.insert(peer) }
                }
                if case .bytes(let nodes)? = reply[Array("nodes".utf8)] {
                    var k = 0
                    while k + 26 <= nodes.count {
                        var raw: UInt32 = 0
                        withUnsafeMutableBytes(of:&raw) { $0.copyBytes(from:nodes[(k+20)..<(k+24)]) }
                        let port = UInt16(nodes[k+24]) << 8 | UInt16(nodes[k+25])
                        let node = Node(ip:raw, port:port)
                        if port != 0, ids[node] == nil { ids[node] = Array(nodes[k..<(k+20)]) }
                        k += 26
                    }
                }
            }
            if !values.isEmpty && responders.count >= 3 { break }
        }
        if !values.isEmpty { return MagnetProbe(layer:.dht, seeders:nil, peers:values.count) }
        return responders.count >= 3 ? MagnetProbe(layer:.dht, seeders:0, peers:0) : nil
    }
}


// ================================================================
//  MagnetFallbackSearch - automatic background fallback (wt v22.6)
// ================================================================
// wt_server emits REQ:magnet-fallback {json} when a stream is starved for
// good (no-holder / all-choked / no-peers / no-metadata / stalled). This
// searches the same providers as the panel, headless, by media name
// (+sXXeYY or year, +resolution), then swaps silently to the best eligible
// candidate that is not the current or an already-tried magnet.
// Lives in this file because MagnetResult / MagnetNative are fileprivate.
// Guards: one search at a time, 45s cooldown after a swap, max 3 swaps per
// origin title, and the result is dropped if the user started or stopped a
// stream while the search ran.
final class MagnetFallbackSearch {
    static let shared = MagnetFallbackSearch()
    private var inFlight = false
    private var originKey = ""
    private var tried = Set<String>()
    private var swaps = 0
    private var lastSwapAt = Date.distantPast
    private let maxSwaps = 3
    private let cooldown: TimeInterval = 45
    private let minSeeds = 2

    func handle(requestLine: String, app: AppDelegate) {
        guard !inFlight, Date().timeIntervalSince(lastSwapAt) >= cooldown else { return }
        guard let data = requestLine.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let title = obj["title"] as? String, title.count >= 3,
              let query = obj["query"] as? String, !query.isEmpty else { return }
        let episode = obj["episode"] as? String
        let year = obj["year"] as? String
        let resolution = obj["resolution"] as? String
        let reason = obj["reason"] as? String ?? "unknown"
        let key = [title.lowercased(), episode ?? year ?? ""].joined(separator: "|")
        if key != originKey { originKey = key; tried = []; swaps = 0 }
        guard swaps < maxSwaps else { return }
        if let current = (obj["infoHash"] as? String)?.lowercased() { tried.insert(current) }
        let origin = app.lastMagnetURL
        guard !origin.isEmpty, app.torrentProcess != nil else { return }
        inFlight = true
        var queries = [query]
        let relaxed = [title, episode ?? year].compactMap { $0 }.joined(separator: " ")
        if resolution != nil, relaxed != query { queries.append(relaxed) }
        print("[wt-fallback] request reason=\(reason) query=\"\(query)\" swaps=\(swaps)/\(maxSwaps)")
        run(queries: queries, resolution: resolution) { [weak self, weak app] picked in
            guard let self else { return }
            self.inFlight = false
            // The user started, replaced or stopped a stream meanwhile: do nothing.
            guard let app, app.lastMagnetURL == origin, app.torrentProcess != nil else {
                print("[wt-fallback] dropped: stream changed during search"); return
            }
            guard let picked else { print("[wt-fallback] no eligible candidate"); return }
            self.tried.insert(picked.hash)
            self.swaps += 1
            self.lastSwapAt = Date()
            if let c = app.controller, c.currentTime > 5 { c.pendingStreamStartPos = max(0, c.currentTime - 3) }
            print("[wt-fallback] swap -> \(picked.hash) seeds=\(picked.seeds) \"\(picked.title)\"")
            app.streamTorrent(picked.magnet)
        }
    }

    private func run(queries: [String], resolution: String?,
                     done: @escaping ((hash: String, magnet: String, seeds: Int, title: String)?) -> Void) {
        guard let q = queries.first else { done(nil); return }
        fetchAll(query: q) { [weak self] rows in
            guard let self else { done(nil); return }
            if let best = self.pick(rows, resolution: resolution) { done(best); return }
            self.run(queries: Array(queries.dropFirst()), resolution: resolution, done: done)
        }
    }

    private func pick(_ rows: [MagnetResult], resolution: String?) -> (hash: String, magnet: String, seeds: Int, title: String)? {
        let eligible = rows.filter { r in
            guard let h = r.infoHash, !tried.contains(h), r.magnetUri != nil, (r.seeds ?? 0) >= minSeeds else { return false }
            return true
        }
        func resMatch(_ r: MagnetResult) -> Int {
            guard let res = resolution else { return 0 }
            return r.title.lowercased().contains(res) ? 1 : 0
        }
        let sorted = eligible.sorted { (resMatch($0), $0.seeds ?? 0) > (resMatch($1), $1.seeds ?? 0) }
        guard let r = sorted.first, let h = r.infoHash, let m = r.magnetUri else { return nil }
        return (h, m, r.seeds ?? 0, r.title)
    }

    private struct Job { let provider: String; let url: URL; let mime: String; let body: Data? }

    private func fetchAll(query: String, done: @escaping ([MagnetResult]) -> Void) {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        var jobs: [Job] = []
        func add(_ provider: String, _ urlString: String, mime: String = "application/json", body: Data? = nil) {
            if let url = URL(string: urlString) { jobs.append(Job(provider: provider, url: url, mime: mime, body: body)) }
        }
        add("apibay", "https://apibay.org/q.php?q=\(encoded)")
        add("bitsearch", "https://bitsearch.eu/api/v1/search?q=\(encoded)")
        add("magnetz", "https://magnetz.eu/api/magnets/search?query=\(encoded)&page=1")
        add("bt4g", "https://bt4gprx.com/search?q=\(encoded)&orderby=seeders&p=1&page=rss", mime: "application/xml")
        add("nyaa", "https://nyaa.si/?page=rss&q=\(encoded)", mime: "application/xml")
        let knabenBody: [String: Any] = ["search_type": "100%", "search_field": "title", "query": query,
                                         "order_by": "seeders", "order_direction": "desc", "size": 50]
        add("knaben", "https://api.knaben.org/v1", body: try? JSONSerialization.data(withJSONObject: knabenBody))
        add("eztv", "https://eztvx.to/api/get-torrents?limit=100&page=1")

        var groups: [[MagnetResult]] = []
        let group = DispatchGroup()
        for job in jobs {
            group.enter()
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 18
            let session = URLSession(configuration: config, delegate: MagnetJSONRedirectGuard(), delegateQueue: nil)
            var request = URLRequest(url: job.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue(job.mime, forHTTPHeaderField: "Accept")
            if let body = job.body {
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            session.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    defer { session.finishTasksAndInvalidate(); group.leave() }
                    // Same response checks as the panel's fetch(): https, same host and path, expected mime, 1 MB cap.
                    guard error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200,
                          http.url?.scheme == "https", http.url?.host == job.url.host, http.url?.path == job.url.path,
                          (http.mimeType?.lowercased() == job.mime
                           || (job.mime == "application/xml" && http.mimeType?.lowercased() == "text/xml")),
                          let data, data.count <= 1_000_000,
                          let object: Any = (job.mime == "application/json"
                                             ? (try? JSONSerialization.jsonObject(with: data))
                                             : String(data: data, encoding: .utf8)),
                          let rows = try? MagnetNative.parse(job.provider, object) else { return }
                    groups.append(rows)
                }
            }.resume()
        }
        group.notify(queue: .main) { done(MagnetNative.merge(groups, query: query)) }
    }
}
