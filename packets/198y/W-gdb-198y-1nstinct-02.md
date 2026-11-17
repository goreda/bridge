# W-gdb-198y-1nstinct-02
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/ArchiveBrowser.swift -> GorUI. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-02.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-02",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/ArchiveBrowser.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/ArchiveBrowser.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: ArchiveConfig, Sheet, cacheFileName, ArchiveTitle, ArchiveOrgItem, archiveOrgDisplayName, ArchiveFile, ArchiveFavorite, ArchiveDeletedEntry, ArchiveUserLists, Stored, save",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-02.py",
    "callee": "archive/gor/Sources/gor/ArchiveBrowser.swift owning station GorUI"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-02.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-02.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-02.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.195472+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/ArchiveBrowser.swift",
        "block": "source1",
        "sha256": "25472e0eb5da384cda6b5823dc851c8471e002c9223e1949937055b9e98608bb"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-02.py",
        "block": "fixtures1",
        "sha256": "478ff8b07ecd43cc4dd136cb0957a420cbedb39c3ef3295a5ccaff3f6f77f327"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "eb433820988c9423beed2cb6ba218bee4d78b63674f34eb3bdaf03a6bc6929fb",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-02: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "427716e669bd4f89c9389c446e9455c68c7b78e0b2719a577d6db216b4cf549f"
  }
}
```

```swift id=source1
// ================================================================
//  ArchiveBrowser.swift - archive panel: spreadsheet/manual link
//  library, transfer-link file browsing, archive.org profile/list
//  browser with filter tree
//  Owns: ArchiveConfig, the archive models, ArchiveBrowserPanel and
//  ArchiveTopBar UI, the nav stack
//  Contract: navStack drives goBack one level at a time; catalogue
//  data comes from ArchiveOrgCatalogue, never re-fetched
//  Not here: CDP session lifecycle, catalogue worker
//  (TransferResolver.swift)
// ================================================================
import AppKit
import Foundation
import CommonCrypto

// ================================================================
//  ArchiveConfig - sheet sources, link patterns, timeouts
// ================================================================

enum ArchiveConfig {
    struct Sheet {
        let name: String
        let csvURL: String
        let titleCol: Int
        let linkCol: Int
    }
    /// Cache file name for a source list: FNV-1a over "id:gid" pairs. A changed source list can never read a snapshot
    /// built from another one (the removed spreadsheet 1vne06... was merged into 1-O2aje...).
    static func cacheFileName(for sources: [(id: String, gid: String, label: String)]) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in sources.map({ "\($0.id):\($0.gid)" }).joined(separator: "|").utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return "archive_cache-" + String(h, radix: 16) + ".json"
    }
    static let spreadsheetSources: [(id: String, gid: String, label: String)] = [
        ("1-O2ajewvMSrs6L8N3uMjDp53jcHz5klLvOSv9wndRaA", "576490957", ""),
    ]
    
    static let manualLinks: [(title: String, links: [String])] = [
        ("Wang Bing Arsivi", ["https://transfer.it/t/rWGXy65xETjD/C6o1lJQR"]),
        ("google drive folder", ["https://drive.google.com/drive/folders/1Fea7EuyjcsyomxN2Uhp4o1oPxCfUjjW5"]),
        ("google drive file", ["https://drive.google.com/file/d/1NsTehvICrC_g5qTjRglcrfm77jNlHxjj/view"]),
        ("gofile", ["https://gofile.io/d/Q0MS47"]),
    ]

    static let chromiumResource = "chrome-headless-shell"
    static let chromiumDirectory = "vendor/chromium/chrome-headless-shell-mac-arm64"

    /// Browser binary path relative to the vendor root (external layout),
    /// derived from the two constants above - single source of truth.
    static let chromiumPathUnderVendor =
        String(chromiumDirectory.dropFirst("vendor/".count)) + "/" + chromiumResource

    static let videoExtensions: Set<String> = ["mkv", "mp4", "avi", "webm", "mov", "ts", "m2ts", "mpg", "mpeg", "wmv", "flv", "ogv", "divx", "vob"]
    
    // gofile.io API
    static let gofileAPIBase = "https://api.gofile.io"
    // WHY: the real wt_obf.js salt, verified via Node vm - see the
    // matching note in CDPSession.resolveGofileFilesAPI.
    static let gofileWT = "9844d94d963d30"
    // must match fetchGofileContent's request User-Agent byte-for-byte -
    // see the same note
    static let gofileUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"
    
    // Google Drive download pattern
    static let driveDownloadTemplate = "https://drive.usercontent.google.com/download?export=download&confirm=t&id="
    static let driveFilePattern = "/file/d/"
    static let driveFolderPattern = "/drive/folders/"
    
    static let pageSettleDelay: TimeInterval  = 5.0
    static let urlCaptureTimeout: TimeInterval = 8.0   // Python: 16 × 0.5s
    static let fileListTimeout: TimeInterval   = 20.0
}

// ================================================================
//  ArchiveTitle / ArchiveOrgItem / ArchiveFile - models
// ================================================================

struct ArchiveTitle: Codable, Equatable, Hashable {
    let title: String
    let section: String
    let links: [String]
}

// One archive.org item as listed under a profile — carries just enough
// facet metadata (year/creator/language/subject) to build the filter tree
// and label rows, without a per-item /metadata fetch. Files are resolved
// lazily, only once the user actually taps into this item.
struct ArchiveOrgItem: Equatable, Codable, Hashable {
    let identifier: String
    let title: String
    let year: String?
    let creator: String?
    let language: String?
    let subject: String?
}

// Readable form of an archive.org handle for on-screen titles — no leading
// "@", underscores opened into spaces ("cinematic_footprint" → "cinematic
// footprint"). Used everywhere a username reaches the topBar or a row.
private func archiveOrgDisplayName(_ username: String) -> String {
    username.replacingOccurrences(of: "_", with: " ")
}

struct ArchiveFile {
    let name: String
    let size: String
    let elementId: String
    let transferURL: String
    let isFolder: Bool
    // MEGA-only: the node's own encrypted key (format "<handle>:<encrypted_key_b64>"
    // for files, just the b64 for folders), needed to derive the AES-CTR key/nonce
    // for decrypting the CDN body — the "g" cs action returns a signed URL to
    // CIPHERTEXT, not a playable stream (see handoff / chat history). Optional
    // with a default so every existing ArchiveFile(...) call site (transfer.it,
    // gofile, drive, pixeldrain — 10 of them, none MEGA) keeps compiling
    // unchanged; only fetchMegaNodes in CDPSession.swift sets it.
    let nodeKey: String?
    let gofileFolderID: String?

    // Gofile companions belong to the containing folder, not a matching stem.
    var isGofileSubtitle: Bool {
        guard !isFolder, transferURL.hasPrefix("gofile-direct::") ||
                transferURL.hasPrefix("https://gofile.io/d/") else { return false }
        return ["srt", "ass", "ssa", "vtt"].contains((name as NSString).pathExtension.lowercased())
    }

    // WHY: a stored property with a default is silently dropped from the
    // memberwise init, so the init is written by hand - nodeKey is a real
    // parameter defaulting to nil; existing call sites skip it, MEGA passes it.
    init(name: String,
         size: String,
         elementId: String,
         transferURL: String,
         isFolder: Bool,
         nodeKey: String? = nil,
         gofileFolderID: String? = nil) {
        self.name = name
        self.size = size
        self.elementId = elementId
        self.transferURL = transferURL
        self.isFolder = isFolder
        self.gofileFolderID = gofileFolderID
        self.nodeKey = nodeKey
    }
}

// ================================================================
//  ArchiveUserLists - per-page "deleted" buckets + one global favorites bucket
//  Deleting only hides a row from its own page; nothing at the source is touched and
//  every hidden row can be recovered from that page's bucket.
// ================================================================

// A stable way to find a row again, never a stored (possibly signed or expiring) file URL:
// opening replays the path from a catalogue entry and re-fetches the page, then picks the
// row by name/id. Every kind of row in the tree has one.
indirect enum ArchiveTarget: Codable, Equatable, Hashable {
    case section(String)
    case title(ArchiveTitle)
    case aoList(user: String, id: Int, name: String)
    case aoItem(ArchiveOrgItem, user: String, listID: Int?)
    // category: "year"/"creator"/"language"/"subject"; value nil = the category row itself
    case aoFacet(user: String, listID: Int?, category: String, value: String?)
    case file(parent: ArchiveTarget, name: String, elementId: String, isFolder: Bool)
}

struct ArchiveFavorite: Codable, Equatable, Hashable {
    let key: String
    let label: String
    let target: ArchiveTarget
}

// Recovery puts the row back on its own page; index and parent are kept so the bucket can show
// where each one came from and in its original order.
struct ArchiveDeletedEntry: Codable, Equatable, Hashable {
    let key: String
    let label: String
    var parent: String = ""
    var index: Int = 0
    // Lets the row be opened (browsed, played) from the deleted list without recovering it.
    var target: ArchiveTarget? = nil
}

final class ArchiveUserLists {
    static let shared = ArchiveUserLists()

    private struct Stored: Codable {
        var deleted: [String: [ArchiveDeletedEntry]] = [:]
        var favorites: [ArchiveFavorite] = []
    }
    private var stored = Stored()
    private let fileURL: URL?
    private let writeQueue = DispatchQueue(label: "archive.userlists.write", qos: .utility)

    private init() {
        if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDir = dir.appendingPathComponent("gor", isDirectory: true)
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
            fileURL = appDir.appendingPathComponent("archive_user_lists.json")
        } else {
            fileURL = nil
        }
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else { return }
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = decoded
        } else {
            // Unreadable file: keep it aside instead of overwriting the user's lists.
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("archive_user_lists.unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    private func save() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(stored) else { return }
        writeQueue.async { try? data.write(to: url, options: .atomic) }
    }

    func deletedKeys(page: String) -> Set<String> { Set((stored.deleted[page] ?? []).map { $0.key }) }
    func deletedEntries(page: String) -> [ArchiveDeletedEntry] { stored.deleted[page] ?? [] }

    func delete(page: String, key: String, label: String, parent: String = "", index: Int = 0, target: ArchiveTarget? = nil) {
        var list = stored.deleted[page] ?? []
        guard !list.contains(where: { $0.key == key }) else { return }
        list.append(ArchiveDeletedEntry(key: key, label: label, parent: parent, index: index, target: target))
        stored.deleted[page] = list
        save()
    }

    // Entries saved before a path was stored have none; the first time their page is built the
    // hidden row is seen again with its path, which is filled in here (nothing else changes).
    func backfillTarget(page: String, key: String, target: ArchiveTarget) {
        guard var list = stored.deleted[page],
              let i = list.firstIndex(where: { $0.key == key }), list[i].target == nil else { return }
        list[i].target = target
        stored.deleted[page] = list
        save()
    }

    func recover(page: String, key: String) {
        guard var list = stored.deleted[page] else { return }
        list.removeAll { $0.key == key }
        stored.deleted[page] = list.isEmpty ? nil : list
        save()
    }

    var favorites: [ArchiveFavorite] { stored.favorites }
    func isFavorite(key: String) -> Bool { stored.favorites.contains { $0.key == key } }

    func toggleFavorite(_ fav: ArchiveFavorite) {
        if let i = stored.favorites.firstIndex(where: { $0.key == fav.key }) {
            stored.favorites.remove(at: i)
        } else {
            stored.favorites.append(fav)
        }
        save()
    }
}

// What a list row stands for, so the row can be hidden (per page) or favorited (global).
private struct ArchiveRowMeta {
    let key: String
    let label: String
    let page: String          // the page that owns the row (its deleted bucket)
    let parent: String        // that page's on-screen title
    let index: Int            // position in the list when it was built
    let target: ArchiveTarget?
}

// ================================================================
//  ArchiveError
// ================================================================

enum ArchiveError: LocalizedError {
    case chromiumNotFound
    case chromiumTimeout
    case cdpNoTarget
    case csvFetchFailed(String)
    case noFilesFound
    case urlCaptureFailed

    var errorDescription: String? {
        switch self {
        case .chromiumNotFound: return "chrome-headless-shell not found in bundle"
        case .chromiumTimeout:  return "Chromium CDP port did not become ready"
        case .cdpNoTarget:      return "No CDP WebSocket target available"
        case .csvFetchFailed(let name): return "Failed to fetch sheet: \(name)"
        case .noFilesFound:     return "No video files found"
        case .urlCaptureFailed: return "Failed to capture signed URL"
        }
    }
}

// ================================================================
//  ArchiveBrowserPanel - panel root: screens, nav, list
// ================================================================

final class ArchiveBrowserPanel: NSView {
    var onClose: (() -> Void)?
    // Exposes the topBar's floating search panel state to the app-wide ESC
    // monitor (MenuActions.swift) so ESC can close search first and the
    // browser itself only on a subsequent press — see closeActiveSearchPanel.
    @discardableResult
    func closeActiveSearchPanel() -> Bool { topBar.closeActiveSearchPanel() }
    // nodeKey/folderKeyFragment are nil for every non-MEGA source
    // (transfer.it, gofile, drive, pixeldrain) — only set when
    // file.nodeKey is present. See MegaStreamManager.swift: MEGA's "g"
    // action returns a signed URL to CIPHERTEXT, not a playable stream,
    // so whoever handles onPlay needs both to decrypt it before mpv can
    // play it.
    var onPlay: ((_ cdnURL: String, _ title: String, _ nodeKey: String?, _ folderKeyFragment: String?, _ subtitleURLs: [String]) -> Void)?
    
    private enum Screen {
        case loading
        case library
        case files
        case fetching
    }

    // WHY: each entry captures exactly what's needed to redraw the screen
    // the user came from; navigating forward pushes one, goBack() pops and
    // redraws - never a hardcoded destination.
    private enum NavEntry {
        case library
        case section(name: String, titles: [ArchiveTitle])
        case files(title: String, files: [ArchiveFile], parent: ArchiveTarget?)
        // archive.org profile/list screen: the full unfiltered item set,
        // the drilled-in filter (nil = all films), and which category's
        // value list was on screen; source carries uploads vs list so
        // going back lands on the right one.
        case archiveOrgProfile(source: ArchiveOrgSource, items: [ArchiveOrgItem], filter: ArchiveOrgFilter?, category: ArchiveOrgFilterCategory?)
        // The "all lists" picker for a user with more than one curated
        // list (archive.org/details/@user/lists/, id-less) — a flat list
        // of that user's lists by name, each tapping straight into its
        // own archiveOrgProfile screen. Only ever pushed when there's
        // more than one list; a single-list account skips this screen
        // entirely (see selectArchiveOrgAllLists).
        case archiveOrgListPicker(username: String, lists: [ArchiveOrgListSummary])
        // The global favorites list, and one page's deleted-items bucket.
        case favorites
        case deleted(page: String, label: String)
    }
    private enum ListMode: Equatable {
        case normal
        case favorites
        case deleted(page: String, label: String)
    }
    // Reset by every rebuildList; the favorites/deleted renderers set it right after their rebuild.
    private var listMode: ListMode = .normal
    // Key of the page the current list belongs to (nil on loading/transient/special screens).
    private var currentPageKey: String? = nil
    // How the on-screen files list was reached (for favoriting its rows), and what a favorite is
    // still waiting for while its pages load.
    private var currentFilesParent: ArchiveTarget? = nil
    private var nextFilesParent: ArchiveTarget? = nil
    private var pendingFilePath: [(String, String)] = []
    private var pendingFacet: (user: String, listID: Int?, category: String, value: String?)? = nil
    private var navStack: [NavEntry] = []
    // Mirrors currentSectionTitles/currentArchiveOrgProfile for the "all
    // lists" picker screen — non-nil only while that exact screen is on
    // display, so currentNavEntry() can capture it and applySortToCurrentScreen
    // can redraw it in place on a sort-button tap, the same way the other
    // screen-local state vars work.
    private var currentArchiveOrgListPicker: (username: String, lists: [ArchiveOrgListSummary])? = nil

    // One active facet selection on the archive.org profile screen — e.g.
    // .year("1979") narrows the item list to items whose year is "1979".
    // Only one filter is active at a time (picking a new one replaces it),
    // which is what keeps the "tree" one level deep: category → value → films.
    private enum ArchiveOrgFilter: Equatable {
        case year(String)
        case creator(String)
        case language(String)
        case subject(String)

        var label: String {
            switch self {
            case .year(let v): return "year: \(v)"
            case .creator(let v): return "creator: \(v)"
            case .language(let v): return "language: \(v)"
            case .subject(let v): return "subject: \(v)"
            }
        }

        func matches(_ item: ArchiveOrgItem) -> Bool {
            switch self {
            case .year(let v): return item.year == v
            case .creator(let v): return item.creator == v
            case .language(let v): return item.language == v
            case .subject(let v): return item.subject == v
            }
        }
    }
    // Non-nil only while screen == .files AND we're showing an archive.org
    // profile or list screen (as opposed to a section's title list or a
    // real file listing) — mirrors how currentSectionTitles distinguishes
    // its own case. currentArchiveOrgFilter is the active drill-down, if
    // any. `source` says whether this is a user's own uploads or a
    // curated Lists list, which the fetch/refresh calls below need to
    // route to the right TransferResolver entry point — a profile's own
    // uploads and any Lists list of theirs are always fetched, cached, and
    // refreshed completely independently (see ArchiveOrgCatalogue.
    // keyForList in TransferResolver.swift), so this determines which one
    // any given screen action is talking to.
    private enum ArchiveOrgSource: Equatable {
        case profile(username: String)
        case list(username: String, listID: Int)

        // Lets every existing `.username` call site (there are many: the
        // title bar, the "@handle" display name, the "which profile is
        // this film's file-cache keyed under" lookup) keep working
        // unchanged for both cases — a list still displays under its
        // owner's handle, it just also carries a listID that the
        // fetch/refresh calls below switch on separately.
        var username: String {
            switch self {
            case .profile(let username): return username
            case .list(let username, _): return username
            }
        }
    }

    // Same URL parsing as selectTitle's routing (specific-list vs plain
    // profile), factored out for global search below — which needs to
    // know a row's ArchiveOrgSource up front, before any navigation
    // happens, purely to look up that profile/list's already-cached
    // items on disk. Returns nil for a non-archive.org link and for the
    // id-less "all lists" form (archive.org/details/@user/lists/), which
    // has no single cached item set of its own to search — its member
    // lists, once opened at least once, are each searchable individually
    // as their own .list rows already are.
    private func archiveOrgSource(fromLink link: String) -> ArchiveOrgSource? {
        guard let range = link.range(of: "archive.org/details/@") else { return nil }
        let afterAt = link[range.upperBound...]
        let segments = afterAt.components(separatedBy: "/")
        guard let username = segments.first, !username.isEmpty else { return nil }
        if segments.count >= 3, segments[1] == "lists", let listID = Int(segments[2]) {
            return .list(username: username, listID: listID)
        }
        if segments.count >= 2, segments[1] == "lists" {
            return nil  // id-less "all lists" row — nothing of its own to search
        }
        let cleanUsername = username.components(separatedBy: "?").first ?? username
        guard !cleanUsername.isEmpty else { return nil }
        return .profile(username: cleanUsername)
    }

    // A sheet row of the id-less form archive.org/details/@user/lists/
    // (no numeric id) doesn't resolve to a single ArchiveOrgSource the way
    // every other row does — it names all of that user's lists at once,
    // and how many of those exist isn't known until fetchAllLists
    // actually returns. selectArchiveOrgAllLists resolves such a row to
    // either a single .list source (one list found — skip straight past
    // the picker) or a picker screen (NavEntry.archiveOrgListPicker above)
    // offering each list by its own name; from there on every navigation
    // is an ordinary ArchiveOrgSource exactly as if that one list's row
    // had been added to the sheet directly. This summary — just enough to
    // label and open one row of that picker (id to open it, name and
    // member count to label it) — is kept separate from ArchiveOrgSource
    // itself so every existing `switch source` in this file (title bar,
    // file cache keying, etc.) stays exhaustive without a case that would
    // never actually reach any of them.
    private struct ArchiveOrgListSummary: Equatable {
        let id: Int
        let name: String
        let memberCount: Int
    }
    private var currentArchiveOrgProfile: (source: ArchiveOrgSource, items: [ArchiveOrgItem])? = nil
    private var currentArchiveOrgFilter: ArchiveOrgFilter? = nil

    // WHY: a global search hit sets this before calling the normal
    // select entry point; once that profile/list loads, it is consumed to
    // auto-select the matched film. nil the rest of the time - never
    // triggers on ordinary navigation.
    private var pendingArchiveOrgIdentifier: String? = nil

    // WHY: a Lists screen shows the list's own name once known - archive.org
    // returns it only with the member fetch (see fetchListMembers) - and
    // falls back to the bare username until then.
    private func archiveOrgTitle(for source: ArchiveOrgSource) -> String {
        switch source {
        case .profile(let username):
            return archiveOrgDisplayName(username)
        case .list(let username, let listID):
            let key = ArchiveOrgCatalogue.keyForList(username: username, listID: listID)
            if let listName = ArchiveOrgCatalogue.shared.displayName(for: key) {
                return listName
            }
            return archiveOrgDisplayName(username)
        }
    }
    // Which filter category's value list is currently on screen (e.g. user
    // tapped "Year" and is now looking at "1971 / 1979 / 1982…"), distinct
    // from currentArchiveOrgFilter which is an already-applied value. Reset
    // whenever the user picks a value or backs out.
    private enum ArchiveOrgFilterCategory { case year, creator, language, subject }
    private var currentArchiveOrgFilterCategory: ArchiveOrgFilterCategory? = nil

    // Sort order applied to whatever list is currently on screen (library
    // sections, a section's title list, or a file listing). Cycles on each
    // tap of the topBar sort button: newest → oldest → A-Z → Z-A → newest…
    // "Newest/oldest" has no real timestamp to go on (ArchiveTitle/ArchiveFile
    // carry none) — it's the spreadsheet's own row order, which is append-only
    // in practice, so last-row-first reads as "most recently added."
    private enum SortMode: CaseIterable {
        case newestFirst
        case oldestFirst
        case az
        case za

        var next: SortMode {
            let all = SortMode.allCases
            let i = all.firstIndex(of: self)!
            return all[(i + 1) % all.count]
        }
        // Each mode gets its own arrow so the button's face alone tells you
        // which of the 4 is active — plain down/up for newest/oldest
        // (append order), double down/up for A-Z/Z-A (alphabetical) so the
        // two pairs read as distinct at a glance, not just up-vs-down.
        var icon: String {
            switch self {
            case .newestFirst: return "↓"
            case .oldestFirst: return "↑"
            case .az: return "⇊"
            case .za: return "⇈"
            }
        }
    }
    private var sortMode: SortMode = .az

    private func sortedTitles(_ titles: [ArchiveTitle]) -> [ArchiveTitle] {
        switch sortMode {
        case .newestFirst: return titles.reversed()
        case .oldestFirst: return titles
        case .az: return titles.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .za: return titles.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
    }

    // Keeps folders before files regardless of sort direction (matches
    // showFiles' existing convention of listing folders first via source
    // order) — only the within-group order changes with sortMode.
    private func sortedFiles(_ files: [ArchiveFile]) -> [ArchiveFile] {
        let folders = files.filter { $0.isFolder }
        let plain = files.filter { !$0.isFolder }
        func apply(_ list: [ArchiveFile]) -> [ArchiveFile] {
            switch sortMode {
            case .newestFirst: return list.reversed()
            case .oldestFirst: return list
            case .az: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            case .za: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
            }
        }
        return apply(folders) + apply(plain)
    }

    private var screen: Screen = .loading
    private let topBar = ArchiveTopBar()
    private let listScroll = RowSnapScrollView()
    private var listView: FileListView?
    private var randomActions: [() -> Void] = []
    private var libraryRandomActions: [() -> Void] = []
    
    private var currentTitle: String = ""
    private var currentFiles: [ArchiveFile] = []
    // Non-nil while the on-screen ".files" list is actually a section's
    // title list (ArchiveTitle rows from showSection), as opposed to a real
    // ArchiveFile listing (from selectTitle/showFiles). Both reuse the same
    // `.files` Screen case for the topBar/back-button chrome, but they hold
    // different row data — currentNavEntry() needs this to snapshot the
    // right one instead of assuming currentFiles is always current.
    private var currentSectionTitles: [ArchiveTitle]? = nil
    private let resolver = TransferResolver()
    // Bumped whenever the user leaves the current file (goBack, close, or
    // picks a different file). In-flight captureURL/retry closures snapshot
    // this at entry and check it before acting, so a stale retry chain for a
    // file the user stopped caring about discards itself instead of running
    // forever. See handoff: infinite "URL capture failed, retrying with
    // fresh session" loop.
    private var selectionGeneration = 0
    
    private var libraryListView: FileListView?
    
    private var searchQuery = ""
    private var isFiltered = false
    // WHY: rebuilding a few-hundred-row list per keystroke is the real
    // cost, not filtering - debounce the rebuild; the query itself is
    // still stored immediately.
    private var searchDebounceItem: DispatchWorkItem?
    
    private var isTorrentMode = false
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setup(torrentMode: false)
    }

    init(frame: NSRect, torrentMode: Bool) {
        self.isTorrentMode = torrentMode
        super.init(frame: frame)
        setup(torrentMode: torrentMode)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        let barH: CGFloat = PhotonFont.chromeLineH + 4
        topBar.frame = CGRect(x: 0, y: bounds.height - barH,
                              width: bounds.width, height: barH)
        listScroll.frame = CGRect(x: 0, y: 0,
                                  width: bounds.width,
                                  height: bounds.height - barH)
        // The list rows are built once; make every panel resize (window <-> fullscreen) re-stretch them.
        listScroll.layoutSubtreeIfNeeded()
        if let doc = listScroll.documentView {
            let w = listScroll.contentView.bounds.width
            GeomTrace.log("archive.layout", "bounds=\(Int(bounds.width))x\(Int(bounds.height)) doc=\(Int(doc.frame.width)) content=\(Int(w))")
            if doc.frame.width != w { doc.frame.size.width = w }
            doc.needsLayout = true
        }
    }
    
    private func setup(torrentMode: Bool) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        listScroll.drawsBackground = false
        listScroll.hasVerticalScroller = false
        listScroll.rowHeight = PhotonFont.chromeLineH + 4
        addSubview(listScroll)
        addSubview(topBar)
        
        topBar.onClose = { [weak self] in self?.close() }
        topBar.onSearch = { [weak self] query in
            self?.filterContent(query)
        }
        topBar.onBack  = { [weak self] in self?.goBack() }
        topBar.onFavorites = { [weak self] in
            guard let self, self.listMode != .favorites else { return }
            self.showFavorites(pushingCurrent: true)
        }
        topBar.onDeleted = { [weak self] in
            guard let self, self.listMode == .normal, let page = self.currentPageKey else { return }
            self.showDeleted(page: page, label: page == "library" ? "archive" : self.currentTitle, pushingCurrent: true)
        }
        topBar.onRandom = { [weak self] in
            guard let self, !self.randomActions.isEmpty else { return }
            ArchiveRandom.shared.addTiming(ProcessInfo.processInfo.systemUptime * 1000)
            guard let index = ArchiveRandom.shared.drawIndex(count: self.randomActions.count, session: "archive-browser") else {
                self.topBar.setTitle("random unavailable - local entropy failed"); return
            }
            self.randomActions[index]()
        }
        topBar.randomVisible = !torrentMode
        topBar.onRefresh = { [weak self] in self?.refreshLibrary() }
        topBar.onSortToggle = { [weak self] in
            guard let self else { return }
            self.sortMode = self.sortMode.next
            self.topBar.setSortIcon(self.sortMode.icon)
            self.applySortToCurrentScreen()
        }
        topBar.setSortIcon(sortMode.icon)
        
        if torrentMode {
            topBar.setTitle("torrent files")
            topBar.backVisible = false
            topBar.refreshVisible = false  // no spreadsheet library in torrent mode
        } else {
            topBar.setTitle("archive")
            // onUpdated fires whenever a background refresh (automatic,
            // right after a cached load, or from the refresh button) finds
            // the library actually changed. Wired once, for the panel's
            // whole lifetime, independent of onLoaded below — it can fire
            // any number of times while this panel is open. Only touches
            // the screen if the user is sitting on the top-level library
            // list; if they've navigated into a section or a file listing,
            // ArchiveLibrary.shared.titles is already updated underneath
            // them and they'll see it next time they land back on the
            // library screen (goBack()/showLibrary()) without this having
            // to reach into whatever they're currently doing.
            ArchiveLibrary.shared.onUpdated = { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.screen == .library else { return }
                    self.libraryListView = nil  // stale rows — rebuild from the updated titles
                    if self.isFiltered {
                        // Don't blow away an active search — re-run it
                        // against the refreshed titles so the query stays
                        // in place and just picks up any new matches.
                        self.filterContent(self.searchQuery)
                    } else {
                        self.showLibrary()
                    }
                }
            }
            if ArchiveLibrary.shared.isLoaded {
                showLibrary()
            } else {
                showLoading()
                ArchiveLibrary.shared.onLoaded = { [weak self] in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        // WHY: the background load can finish after the
                        // user has moved on - redraw only if still on the
                        // loading placeholder; an unconditional redraw
                        // would reset their screen and re-trigger a load.
                        guard self.screen == .loading else { return }
                        self.showLibrary()
                    }
                }
                ArchiveLibrary.shared.load()
            }
        }
    }

    // Source commentary elided for privacy; historical proof hashes are not rebound.
    func toggleSearchFromKey() { topBar.toggleSearchFromKey() }

    // Source commentary elided for privacy; historical proof hashes are not rebound.
    func pressRandomFromKey() { topBar.onRandom?() }

    private func refreshLibrary() {
        if let profile = currentArchiveOrgProfile {
            let source = profile.source
            let handleRefresh: ([ArchiveOrgItem], String?) -> Void = { [weak self] items, _ in
                DispatchQueue.main.async {
                    guard let self,
                          self.screen == .files,
                          self.currentArchiveOrgProfile?.source == source else { return }
                    self.showArchiveOrgProfile(source: source, items: items, filter: self.currentArchiveOrgFilter, pushingCurrent: false)
                }
            }
            switch source {
            case .profile(let username):
                resolver.forceRefreshArchiveOrgProfile(username: username, completion: handleRefresh)
            case .list(let username, let listID):
                resolver.forceRefreshArchiveOrgList(username: username, listID: listID, completion: handleRefresh)
            }
            return
        }
        ArchiveLibrary.shared.reload()
    }
    

    func showTorrentFiles(json: String, onSelect: @escaping (Int) -> Void) {
        guard let data = json.data(using: .utf8),
              let files = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        
        currentTitle = "torrent"
        screen = .files
        
        let rows: [(String, Bool, String?, () -> Void)] = files.enumerated().map { (i, file) in
            let name = file["name"] as? String ?? "File \(i+1)"
            let size = file["length"] as? Int64 ?? 0
            let sizeStr = size > 0 ? ByteCountFormatter.string(fromByteCount: size, countStyle: .file) : nil
            return ("  \(name)", true, sizeStr, { onSelect(i) })
        }
        
        rebuildList(rows: rows, contentActions: rows.filter { $0.1 }.map { $0.3 })
        topBar.setTitle("torrent files")
    }
    
    // MARK: - Screens
    
    private func showLoading() {
        screen = .loading
        topBar.setTitle("archive · loading...")
        topBar.backVisible = false
        rebuildList(rows: [("  loading sheets...", false, nil, {})])
    }
    
    // `pushingCurrent: true` records where we're navigating from onto
    // navStack before drawing the new screen, so goBack() can return to it.
    // Root-level calls (initial load, search reset) pass false since there's
    // nothing meaningful above the library to come back to.
    private func showLibrary(pushingCurrent: Bool = false) {
        if pushingCurrent {
            navStack.append(currentNavEntry())
        } else {
            navStack.removeAll()
        }
        selectionGeneration += 1  // leaving file view — invalidate stale retries
        screen = .library
        currentArchiveOrgProfile = nil
        currentArchiveOrgListPicker = nil
        currentArchiveOrgFilter = nil
        currentArchiveOrgFilterCategory = nil
        topBar.setTitle("archive")
        topBar.backVisible = false
        
        // skip if already created
        if libraryListView != nil {
            listView?.removeFromSuperview()
            listScroll.documentView = libraryListView
            listView = libraryListView
            randomActions = libraryRandomActions
            listMode = .normal
            currentPageKey = "library"
            updateChrome()
            return
        }
        
        let lib = ArchiveLibrary.shared.titles
        guard !lib.isEmpty else {
            rebuildList(rows: [("  no titles — check config", false, nil, {})])
            return
        }
        
        var sectionOrder: [String] = []
        var bySection: [String: [ArchiveTitle]] = [:]

        for title in lib {
            if bySection[title.section] == nil {
                sectionOrder.append(title.section)
            }
            bySection[title.section, default: []].append(title)
        }

        let orderedSections: [String]
        switch sortMode {
        case .newestFirst: orderedSections = sectionOrder.reversed()
        case .oldestFirst: orderedSections = sectionOrder
        case .az: orderedSections = sectionOrder.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        case .za: orderedSections = sectionOrder.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedDescending }
        }

        var rows: [(String, Bool, String?, () -> Void)] = []
        var acc: [[FileRowAccessory]] = []
        let deletedSections = ArchiveUserLists.shared.deletedKeys(page: "library")
        for section in orderedSections {
            guard let sectionTitles = bySection[section], !sectionTitles.isEmpty else { continue }
            guard !deletedSections.contains("s:" + section) else {
                ArchiveUserLists.shared.backfillTarget(page: "library", key: "s:" + section, target: .section(section))
                continue
            }
            rows.append(("  · \(section)  (\(sectionTitles.count))", true, nil, {
                self.showSection(section, titles: sectionTitles, pushingCurrent: true)
            }))
            acc.append(accessories(for: rowMeta("s:" + section, section, page: "library", parent: "archive",
                                                index: acc.count, target: .section(section))))
        }
        
        rebuildList(rows: rows, accessories: acc, page: "library", contentActions: rows.filter { $0.1 }.map { $0.3 })
        libraryListView = listView
        libraryRandomActions = randomActions
    }

    // Re-draws whatever's currently on screen with the current sortMode
    // applied, without touching navStack (this isn't a navigation — the
    // user is still looking at the same screen, just reordered). Called by
    // the topBar sort button.
    private func applySortToCurrentScreen() {
        switch listMode {
        case .favorites: showFavorites(pushingCurrent: false); return
        case .deleted(let page, let label): showDeleted(page: page, label: label, pushingCurrent: false); return
        case .normal: break
        }
        switch screen {
        case .loading:
            return
        case .library:
            libraryListView = nil  // force rebuild — cached view has the old order baked in
            showLibrary(pushingCurrent: false)
        case .fetching:
            return  // mid-fetch; nothing stable to resort yet
        case .files:
            if let picker = currentArchiveOrgListPicker {
                showArchiveOrgListPicker(username: picker.username, lists: picker.lists, pushingCurrent: false)
            } else if let profile = currentArchiveOrgProfile {
                showArchiveOrgProfile(source: profile.source, items: profile.items, filter: currentArchiveOrgFilter, pushingCurrent: false)
            } else if let sectionTitles = currentSectionTitles {
                showSection(currentTitle, titles: sectionTitles, pushingCurrent: false)
            } else {
                showFiles(currentFiles)
            }
        }
    }

    // Snapshots what's on screen right now as a NavEntry so goBack() can
    // restore it later. Call just before navigating forward.
    private func currentNavEntry() -> NavEntry {
        switch listMode {
        case .favorites: return .favorites
        case .deleted(let page, let label): return .deleted(page: page, label: label)
        case .normal: break
        }
        switch screen {
        case .library, .loading:
            return .library
        case .files, .fetching:
            if let picker = currentArchiveOrgListPicker {
                return .archiveOrgListPicker(username: picker.username, lists: picker.lists)
            }
            if let profile = currentArchiveOrgProfile {
                return .archiveOrgProfile(source: profile.source, items: profile.items, filter: currentArchiveOrgFilter, category: currentArchiveOrgFilterCategory)
            }
            if let sectionTitles = currentSectionTitles {
                return .section(name: currentTitle, titles: sectionTitles)
            }
            return .files(title: currentTitle, files: currentFiles, parent: currentFilesParent)
        }
    }
    
    // What to print for one sheet row: the catalogue's real list_name
    // when known, else ArchiveLibrary's placeholder. WHY: the " · list"
    // tag is appended either way, so a visited list never reads like a
    // plain profile row.
    private func sheetRowTitle(_ title: ArchiveTitle) -> String {
        guard let link = title.links.first,
              let range = link.range(of: "archive.org/details/@") else {
            return title.title
        }
        let afterAt = link[range.upperBound...]
        let segments = afterAt.components(separatedBy: "/")
        guard segments.count >= 3, segments[1] == "lists", let listID = Int(segments[2]) else {
            return title.title
        }
        let username = segments[0]
        guard !username.isEmpty else { return title.title }
        let key = ArchiveOrgCatalogue.keyForList(username: username, listID: listID)
        guard let realName = ArchiveOrgCatalogue.shared.displayName(for: key) else {
            return title.title
        }
        return "\(realName) · list"
    }

    private func showSection(_ section: String, titles: [ArchiveTitle], pushingCurrent: Bool = false) {
        if pushingCurrent { navStack.append(currentNavEntry()) }
        currentTitle = section
        currentSectionTitles = titles
        currentArchiveOrgProfile = nil
        currentArchiveOrgListPicker = nil
        currentArchiveOrgFilter = nil
        currentArchiveOrgFilterCategory = nil
        screen = .fetching  // show loading
        topBar.setTitle(section)
        topBar.backVisible = true
        
        var rows: [(String, Bool, String?, () -> Void)] = []
        let folderIcons = ["","","","","","","","","","",""]
        var acc: [[FileRowAccessory]] = []
        let page = "section:" + section
        let deletedHere = ArchiveUserLists.shared.deletedKeys(page: page)
        for (i, title) in sortedTitles(titles).enumerated() {
            let key = "t:" + title.title + "|" + (title.links.first ?? "")
            guard !deletedHere.contains(key) else {
                ArchiveUserLists.shared.backfillTarget(page: page, key: key, target: .title(title))
                continue
            }
            let icon = folderIcons[i % folderIcons.count]
            rows.append(("  \(icon) \(sheetRowTitle(title))", true, nil, {
                self.selectTitle(title.title, links: title.links)
            }))
            acc.append(accessories(for: rowMeta(key, sheetRowTitle(title), page: page, parent: section,
                                                index: acc.count, target: .title(title))))
        }
        rebuildList(rows: rows, accessories: acc, page: page, contentActions: rows.filter { $0.1 }.map { $0.3 })
        
        screen = .files
    }
    
    func selectTitle(_ title: String, links: [String], pushingCurrent: Bool = true) {
        // How this files page was reached, kept for favoriting its rows (folders pass their own chain).
        let destinationParent = nextFilesParent ?? .title(ArchiveTitle(title: title, section: "", links: links))
        nextFilesParent = nil
        // archive.org "Lists" link — archive.org/details/@user/lists/<id>/
        // <name> — checked BEFORE the plain profile check below, since a
        // list link also contains "archive.org/details/@" as a substring
        // and would otherwise be misread as a profile link with the
        // /lists/<id>/<name> tail silently dropped (the old
        // components(separatedBy:).first parsing stops at the first "/"
        // after the username regardless of what follows it).
        if let listLink = links.first,
           let range = listLink.range(of: "archive.org/details/@") {
            let afterAt = listLink[range.upperBound...]
            let segments = afterAt.components(separatedBy: "/")
            // segments[0] = username, segments[1] = "lists" (if present),
            // segments[2] = the numeric list id.
            if segments.count >= 3, segments[1] == "lists", let listID = Int(segments[2]) {
                let username = segments[0]
                if !username.isEmpty {
                    selectArchiveOrgList(username: username, listID: listID, pushingCurrent: pushingCurrent)
                    return
                }
            }
            // Id-less form — archive.org/details/@user/lists/ or
            // .../lists with nothing (or just a trailing slash) after it —
            // names every list this user has rather than one specific
            // one. segments.count == 2 covers "lists" with no trailing
            // slash; == 3 with segments[2] empty covers a trailing slash
            // ("lists/"). Checked only after the specific-id case above
            // fails to match, so a real numeric id always wins this branch.
            let isAllLists = segments.count == 2 && segments[1] == "lists"
                || segments.count == 3 && segments[1] == "lists" && segments[2].isEmpty
            if isAllLists {
                let username = segments[0]
                if !username.isEmpty {
                    selectArchiveOrgAllLists(username: username, pushingCurrent: pushingCurrent)
                    return
                }
            }
        }
        // archive.org profile link — separate flow with its own filter-tree
        // screen instead of the flat fetchFiles→showFiles path every other
        // source uses. A row's links array holds exactly one link for a
        // single-column sheet source (see ArchiveLibrary), which is how
        // archive.org rows always arrive, so checking the first is enough.
        if let profileLink = links.first, profileLink.contains("archive.org/details/@"),
           let username = profileLink.components(separatedBy: "archive.org/details/@").last?
                .components(separatedBy: "/").first?.components(separatedBy: "?").first, !username.isEmpty {
            selectArchiveOrgProfile(username: username, pushingCurrent: pushingCurrent)
            return
        }

        selectionGeneration += 1  // new ordinary title supersedes older fetches
        if pushingCurrent { navStack.append(currentNavEntry()) }
        currentFilesParent = destinationParent // snapshot previous parent BEFORE adopting child ancestry
        currentTitle = title
        currentSectionTitles = nil  // leaving section-title-list state, if we were in it
        currentArchiveOrgProfile = nil
        currentArchiveOrgListPicker = nil
        currentArchiveOrgFilter = nil
        screen = .fetching
        topBar.setTitle("\(title) · fetching...")
        topBar.backVisible = true
        rebuildList(rows: [("  opening...", false, nil, {})])
        
        let openingGeneration = selectionGeneration
        var allFiles: [ArchiveFile] = []
        var lastErrorMessage: String? = nil
        
        func fetchNext(_ index: Int) {
            guard selectionGeneration == openingGeneration else { return }
            guard index < links.count else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.selectionGeneration == openingGeneration else { return }
                    if allFiles.isEmpty {
                        // show the resolver's real error (e.g. gofile API
                        // down) when one came back; generic text only as
                        // fallback
                        let emptyMessage = lastErrorMessage ?? "no video files found"
                        self.rebuildList(rows: [
                            ("  \(emptyMessage)", false, nil, {}),
                            ("  ← back", true, nil, { [weak self] in self?.goBack() }),
                        ])
                    } else {
                        self.currentFiles = allFiles
                        self.screen = .files
                        self.topBar.setTitle(title)
                        self.showFiles(allFiles)
                    }
                }
                return
            }
            
            resolver.fetchFiles(url: links[index]) { [weak self] files, errorMessage in
                DispatchQueue.main.async {
                    guard let self, self.selectionGeneration == openingGeneration else { return }
                    allFiles.append(contentsOf: files)
                    if let errorMessage { lastErrorMessage = errorMessage }
                    fetchNext(index + 1)
                }
            }
        }
        
        fetchNext(0)
    }

    // MARK: - archive.org profile

    // Entry point for an archive.org profile row. Fetches the uploader's
    // items (with year/creator/language/subject facets, no per-item file
    // resolution yet) and lands on the filter-tree screen. Files are only
    // resolved once the user taps an actual film.
    private func selectArchiveOrgProfile(username: String, pushingCurrent: Bool) {
        selectionGeneration += 1  // a new async destination supersedes older fetches
        if pushingCurrent { navStack.append(currentNavEntry()) }
        let source = ArchiveOrgSource.profile(username: username)
        currentTitle = archiveOrgDisplayName(username)
        currentSectionTitles = nil
        currentArchiveOrgProfile = nil
        currentArchiveOrgListPicker = nil
        currentArchiveOrgFilter = nil
        currentArchiveOrgFilterCategory = nil
        screen = .fetching
        topBar.setTitle("\(archiveOrgDisplayName(username)) · fetching...")
        topBar.backVisible = true
        rebuildList(rows: [("  opening...", false, nil, {})])
        let openingGeneration = selectionGeneration

        resolver.fetchArchiveOrgProfileItems(username: username, onUpdated: { [weak self] freshItems in
            // Fires as the catalogue's background worker learns more items
            // (or, for a brand-new profile, as the very first ones arrive)
            // — redraws only if the user is still looking at this exact
            // profile, otherwise the catalogue just keeps filling quietly
            // for next time.
            DispatchQueue.main.async {
                guard let self, self.selectionGeneration == openingGeneration, self.screen == .files,
                      self.currentArchiveOrgProfile?.source == source else { return }
                self.showArchiveOrgProfile(source: source, items: freshItems, filter: self.currentArchiveOrgFilter, pushingCurrent: false)
            }
        }, completion: { [weak self] items, errorMessage in
            DispatchQueue.main.async {
                guard let self, self.selectionGeneration == openingGeneration else { return }
                guard !items.isEmpty else {
                    self.rebuildList(rows: [
                        ("  \(errorMessage ?? "no items found")", false, nil, {}),
                        ("  ← back", true, nil, { [weak self] in self?.goBack() }),
                    ])
                    return
                }
                self.showArchiveOrgProfile(source: source, items: items, filter: nil, pushingCurrent: false)
                self.openPendingArchiveOrgItemIfNeeded(items: items)
            }
        })
    }

    // Entry point for a curated "Lists" row — archive.org/details/@user
    // /lists/<id>/<name>. Identical flow to selectArchiveOrgProfile above,
    // against a different TransferResolver entry point and its own
    // ArchiveOrgSource.list case, which keeps the fetch/refresh/cache
    // completely separate from that same user's own uploads catalogue.
    private func selectArchiveOrgList(username: String, listID: Int, pushingCurrent: Bool) {
        selectionGeneration += 1  // a new async destination supersedes older fetches
        if pushingCurrent { navStack.append(currentNavEntry()) }
        let source = ArchiveOrgSource.list(username: username, listID: listID)
        currentTitle = archiveOrgTitle(for: source)
        currentSectionTitles = nil
        currentArchiveOrgProfile = nil
        currentArchiveOrgListPicker = nil
        currentArchiveOrgFilter = nil
        currentArchiveOrgFilterCategory = nil
        screen = .fetching
        topBar.setTitle("\(archiveOrgTitle(for: source)) · fetching...")
        topBar.backVisible = true
        rebuildList(rows: [("  opening...", false, nil, {})])
        let openingGeneration = selectionGeneration

        resolver.fetchArchiveOrgListItems(username: username, listID: listID, onUpdated: { [weak self] freshItems in
            DispatchQueue.main.async {
                guard let self, self.selectionGeneration == openingGeneration, self.screen == .files,
                      self.currentArchiveOrgProfile?.source == source else { return }
                self.showArchiveOrgProfile(source: source, items: freshItems, filter: self.currentArchiveOrgFilter, pushingCurrent: false)
            }
        }, completion: { [weak self] items, errorMessage in
            DispatchQueue.main.async {
                guard let self, self.selectionGeneration == openingGeneration else { return }
                guard !items.isEmpty else {
                    self.rebuildList(rows: [
                        ("  \(errorMessage ?? "no items found")", false, nil, {}),
                        ("  ← back", true, nil, { [weak self] in self?.goBack() }),
                    ])
                    return
                }
                self.showArchiveOrgProfile(source: source, items: items, filter: nil, pushingCurrent: false)
                self.openPendingArchiveOrgItemIfNeeded(items: items)
            }
        })
    }

    // Consumes pendingArchiveOrgIdentifier (set by a global search hit —
    // see runFilter) once the profile/list it points into has finished
    // loading and matches the just-shown items. Cleared unconditionally
    // right after reading it, whether or not a match was actually found,
    // so it never lingers and fires again on some later, unrelated
    // profile open. If the identifier isn't in `items` — the cached
    // catalogue used for the search hit was stale, or the item is no
    // longer present — this just leaves the user on the profile/list
    // screen itself rather than failing silently or showing an error;
    // that's still a reasonable landing spot for the search.
    private func openPendingArchiveOrgItemIfNeeded(items: [ArchiveOrgItem]) {
        guard let identifier = pendingArchiveOrgIdentifier else { return }
        pendingArchiveOrgIdentifier = nil
        guard let item = items.first(where: { $0.identifier == identifier }) else { return }
        selectArchiveOrgItem(item)
    }

    // Entry point for the id-less "all lists" row. Fetches every list in
    // one request; a single list opens directly, more than one lands on a
    // picker naming each by its own list_name.
    private func selectArchiveOrgAllLists(username: String, pushingCurrent: Bool) {
        selectionGeneration += 1  // a new async destination supersedes older fetches
        if pushingCurrent { navStack.append(currentNavEntry()) }
        currentTitle = "\(archiveOrgDisplayName(username)) · lists"
        currentSectionTitles = nil
        currentArchiveOrgProfile = nil
        currentArchiveOrgFilter = nil
        currentArchiveOrgFilterCategory = nil
        currentArchiveOrgListPicker = nil
        screen = .fetching
        topBar.setTitle("\(archiveOrgDisplayName(username)) · fetching lists...")
        topBar.backVisible = true
        rebuildList(rows: [("  opening...", false, nil, {})])
        let openingGeneration = selectionGeneration

        resolver.fetchArchiveOrgAllLists(username: username) { [weak self] lists, errorMessage in
            DispatchQueue.main.async {
                guard let self, self.selectionGeneration == openingGeneration else { return }
                guard let lists, !lists.isEmpty else {
                    self.rebuildList(rows: [
                        ("  \(errorMessage ?? "no lists found for @\(username)")", false, nil, {}),
                        ("  ← back", true, nil, { [weak self] in self?.goBack() }),
                    ])
                    return
                }
                if lists.count == 1, let only = lists.first {
                    // Single list — skip the picker, go straight in. Not
                    // pushed onto navStack a second time: selectArchiveOrgList
                    // does that itself, and we already pushed (if asked to)
                    // above before this fetch started.
                    self.selectArchiveOrgList(username: username, listID: only.id, pushingCurrent: false)
                    return
                }
                let summaries = lists.map { ArchiveOrgListSummary(id: $0.id, name: $0.name, memberCount: $0.count) }
                self.showArchiveOrgListPicker(username: username, lists: summaries, pushingCurrent: false)
            }
        }
    }

    // Renders the "all lists" picker — one row per list, named by its own
    // list_name, tapping straight into that list's ordinary
    // archiveOrgProfile screen exactly as if its row had been added to the
    // sheet directly. sortMode applies the same way it does to a section's
    // title list (A-Z/Z-A/insertion order/reversed).
    private func showArchiveOrgListPicker(username: String, lists: [ArchiveOrgListSummary], pushingCurrent: Bool) {
        if pushingCurrent { navStack.append(currentNavEntry()) }
        currentTitle = "\(archiveOrgDisplayName(username)) · lists"
        currentSectionTitles = nil
        currentArchiveOrgProfile = nil
        currentArchiveOrgFilter = nil
        currentArchiveOrgFilterCategory = nil
        currentArchiveOrgListPicker = (username, lists)
        screen = .fetching
        topBar.setTitle(currentTitle)
        topBar.backVisible = true

        let ordered: [ArchiveOrgListSummary]
        switch sortMode {
        case .newestFirst: ordered = lists.reversed()
        case .oldestFirst: ordered = lists
        case .az: ordered = lists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .za: ordered = lists.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        }

        var rows: [(String, Bool, String?, () -> Void)] = []
        var acc: [[FileRowAccessory]] = []
        let pickerPage = "aolists:" + username
        let deletedLists = ArchiveUserLists.shared.deletedKeys(page: pickerPage)
        for list in ordered {
            guard !deletedLists.contains("l:\(list.id)") else {
                ArchiveUserLists.shared.backfillTarget(page: pickerPage, key: "l:\(list.id)",
                                                       target: .aoList(user: username, id: list.id, name: list.name))
                continue
            }
            rows.append(("  · \(list.name)  (\(list.memberCount))", true, nil, { [weak self] in
                self?.selectArchiveOrgList(username: username, listID: list.id, pushingCurrent: true)
            }))
            acc.append(accessories(for: rowMeta("l:\(list.id)", list.name, page: pickerPage, parent: currentTitle,
                index: acc.count, target: .aoList(user: username, id: list.id, name: list.name))))
        }
        rebuildList(rows: rows, accessories: acc, page: pickerPage, contentActions: rows.filter { $0.1 }.map { $0.3 })
        screen = .files
    }

    // Distinct facet values for one category, ordered by the topBar's
    // sortMode (most-common-first default, A-Z/Z-A via the sort button).
    private func archiveOrgFacetValues(_ items: [ArchiveOrgItem], _ pick: (ArchiveOrgItem) -> String?) -> [(value: String, count: Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            guard let v = pick(item) else { continue }
            counts[v, default: 0] += 1
        }
        let pairs = counts.map { (value: $0.key, count: $0.value) }
        switch sortMode {
        case .newestFirst:
            return pairs.sorted {
                $0.count != $1.count ? $0.count > $1.count : $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending
            }
        case .oldestFirst:
            return pairs.sorted {
                $0.count != $1.count ? $0.count < $1.count : $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending
            }
        case .az:
            return pairs.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        case .za:
            return pairs.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedDescending }
        }
    }

    // Renders the archive.org profile screen: filter categories (or, one
    // level deeper, that category's values) at the top, then the — possibly
    // filtered — film list below. `filter`, when set, narrows the film list
    // to items matching it; `currentArchiveOrgFilterCategory`, when set,
    // shows that category's value list instead of the category row itself.
    private func showArchiveOrgProfile(source: ArchiveOrgSource, items: [ArchiveOrgItem], filter initialFilter: ArchiveOrgFilter?, pushingCurrent: Bool) {
        var filter = initialFilter
        let displayTitle = archiveOrgTitle(for: source)
        var sourceListID: Int? = nil
        if case .list(_, let id) = source { sourceListID = id }
        let aoPageKey: String
        switch source {
        case .profile(let username): aoPageKey = "ao:" + username
        case .list(let username, let listID): aoPageKey = "ao:" + ArchiveOrgCatalogue.keyForList(username: username, listID: listID)
        }
        if pushingCurrent { navStack.append(currentNavEntry()) }
        // A favorite for a facet category/value is waiting for this profile/list to load.
        if let p = pendingFacet, p.user == source.username, p.listID == sourceListID {
            pendingFacet = nil
            if let cat = facetCategory(p.category) {
                if let v = p.value {
                    currentArchiveOrgFilterCategory = nil
                    filter = facetFilter(category: p.category, value: v)
                } else {
                    currentArchiveOrgFilterCategory = cat
                }
            }
        }
        currentTitle = displayTitle
        currentSectionTitles = nil
        currentArchiveOrgProfile = (source, items)
        currentArchiveOrgFilter = filter
        screen = .fetching
        topBar.backVisible = true

        var rows: [(String, Bool, String?, () -> Void)] = []

        if let category = currentArchiveOrgFilterCategory {
            // no extra "← filters" row - the category name in the title
            // is enough context; the real back button goes up via goBack()
            let categoryLabel: String
            switch category {
            case .year: categoryLabel = "Year"
            case .creator: categoryLabel = "Creator"
            case .language: categoryLabel = "Language"
            case .subject: categoryLabel = "Subject"
            }
            topBar.setTitle("\(displayTitle) · \(categoryLabel)")
            func pick(_ item: ArchiveOrgItem) -> String? {
                switch category {
                case .year: return item.year
                case .creator: return item.creator
                case .language: return item.language
                case .subject: return item.subject
                }
            }
            func makeFilter(_ value: String) -> ArchiveOrgFilter {
                switch category {
                case .year: return .year(value)
                case .creator: return .creator(value)
                case .language: return .language(value)
                case .subject: return .subject(value)
                }
            }
            var valueAcc: [[FileRowAccessory]] = []
            let deletedHere = ArchiveUserLists.shared.deletedKeys(page: aoPageKey)
            for (value, count) in archiveOrgFacetValues(items, pick) {
                let vkey = "v:" + facetName(category) + ":" + value
                guard !deletedHere.contains(vkey) else {
                    ArchiveUserLists.shared.backfillTarget(page: aoPageKey, key: vkey,
                        target: .aoFacet(user: source.username, listID: sourceListID, category: facetName(category), value: value))
                    continue
                }
                rows.append(("  · \(value)  (\(count))", true, nil, { [weak self] in
                    guard let self else { return }
                    self.currentArchiveOrgFilterCategory = nil
                    self.showArchiveOrgProfile(source: source, items: items, filter: makeFilter(value), pushingCurrent: true)
                }))
                valueAcc.append(accessories(for: rowMeta(vkey, "\(categoryLabel): \(value)", page: aoPageKey,
                    parent: "\(displayTitle) · \(categoryLabel)", index: valueAcc.count,
                    target: .aoFacet(user: source.username, listID: sourceListID, category: facetName(category), value: value))))
            }
            rebuildList(rows: rows, accessories: valueAcc, page: aoPageKey, contentActions: [])
            screen = .files
            return
        }

        topBar.setTitle(filter != nil ? "\(displayTitle) · \(filter!.label)" : displayTitle)


        // WHY: category rows go into categoryRows so placement depends on
        // whether a filter is active - they lead an unfiltered list, but
        // never sit above the filtered films.
        let categories: [(String, ArchiveOrgFilterCategory, (ArchiveOrgItem) -> String?)] = [
            ("Year", .year, { $0.year }), ("Creator", .creator, { $0.creator }),
            ("Language", .language, { $0.language }), ("Subject", .subject, { $0.subject }),
        ]
        var categoryRows: [(String, Bool, String?, () -> Void)] = []
        var categoryAcc: [[FileRowAccessory]] = []
        let deletedCats = ArchiveUserLists.shared.deletedKeys(page: aoPageKey)
        for (label, category, pick) in categories {
            let n = archiveOrgFacetValues(items, pick).count
            guard n > 0 else { continue }
            guard !deletedCats.contains("c:" + facetName(category)) else {
                ArchiveUserLists.shared.backfillTarget(page: aoPageKey, key: "c:" + facetName(category),
                    target: .aoFacet(user: source.username, listID: sourceListID, category: facetName(category), value: nil))
                continue
            }
            // WHY: every step into the tree pushes its own nav level
            // (pushingCurrent: true), exactly like drilling into a
            // section - the back button needs each one to pop.
            categoryRows.append(("  · \(label)  (\(n))", true, nil, { [weak self] in
                self?.currentArchiveOrgFilterCategory = category
                self?.showArchiveOrgProfile(source: source, items: items, filter: filter, pushingCurrent: true)
            }))
            categoryAcc.append(accessories(for: rowMeta("c:" + facetName(category), label, page: aoPageKey,
                parent: displayTitle, index: categoryAcc.count,
                target: .aoFacet(user: source.username, listID: sourceListID, category: facetName(category), value: nil))))
        }
 
        let deletedFilms = ArchiveUserLists.shared.deletedKeys(page: aoPageKey)
        for item in items where deletedFilms.contains("o:" + item.identifier) {
            ArchiveUserLists.shared.backfillTarget(page: aoPageKey, key: "o:" + item.identifier,
                                                   target: .aoItem(item, user: source.username, listID: sourceListID))
        }
        let filteredItems = (filter.map { f in items.filter { f.matches($0) } } ?? items)
            .filter { !deletedFilms.contains("o:" + $0.identifier) }
        // WHY: "X of Y catalogued" while the backfill runs - a bare count
        // makes an in-progress list look identical to a finished one.
        let catalogueKey: String
        switch source {
        case .profile(let username): catalogueKey = username
        case .list(let username, let listID): catalogueKey = ArchiveOrgCatalogue.keyForList(username: username, listID: listID)
        }
        let catalogueProgress = ArchiveOrgCatalogue.shared.progress(for: catalogueKey)
        let countLabel: String
        if let total = catalogueProgress.total, catalogueProgress.have < total, filter == nil {
            countLabel = "\(filteredItems.count) of \(total) catalogued · still fetching"
        } else {
            countLabel = "\(filteredItems.count) film\(filteredItems.count == 1 ? "" : "s")"
        }
        let aoPage = aoPageKey
        let sortedItems = archiveOrgSorted(filteredItems)
        let listID = sourceListID
        let filmAcc: [[FileRowAccessory]] = [[]] + sortedItems.map { item in
            let key = "o:" + item.identifier
            return accessories(for: rowMeta(key, item.title, page: aoPage, parent: displayTitle, index: 0,
                                            target: .aoItem(item, user: source.username, listID: listID)))
        }
        let filmRows: [(String, Bool, String?, () -> Void)] =
            [("  · · \(countLabel)", false, nil, {})] +
            sortedItems.map { item in
                ("  \(item.title)", true, nil, { [weak self] in
                    self?.selectArchiveOrgItem(item)
                })
            }
 
        var acc: [[FileRowAccessory]] = []
        if let _ = filter {
            // "  × clear filter · \(filter.label)", topbar was already showing
            // the selected filter showing also in this row was unnnecessary.
            // deleting the filter.label caused value 'filter' was defined but never used warning.
            rows.append(("  × clear", true, nil, { [weak self] in
                self?.showArchiveOrgProfile(source: source, items: items, filter: nil, pushingCurrent: true)
            }))
            rows.append(contentsOf: filmRows)
            // blank separator row between the film-list tail and the
            // category options, same break the count row gives the top
            rows.append(("  · ·", false, nil, {}))
            rows.append(contentsOf: categoryRows)
            acc = [[]] + filmAcc + [[]] + categoryAcc
        } else {
            // No filter active: categories are the only navigation on offer,
            // so they stay on top exactly as before.
            rows.append(contentsOf: categoryRows)
            rows.append(contentsOf: filmRows)
            acc = categoryAcc + filmAcc
        }
 
        rebuildList(rows: rows, accessories: acc, page: aoPage, contentActions: sortedItems.map { item in
            { [weak self] in self?.selectArchiveOrgItem(item) }
        })
        screen = .files
    }

    // Same SortMode the rest of the browser uses, applied to the item
    // title since ArchiveOrgItem carries no separate date field to sort by.
    private func archiveOrgSorted(_ items: [ArchiveOrgItem]) -> [ArchiveOrgItem] {
        switch sortMode {
        case .newestFirst: return items.reversed()
        case .oldestFirst: return items
        case .az: return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .za: return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        }
    }

    // User tapped one film in the profile list — resolve its actual
    // video file(s) now (the profile screen only ever fetched facets, not
    // files) and hand off to the normal file-listing screen. A single-file
    // item skips straight to playback instead of showing a one-row list.
    private func selectArchiveOrgItem(_ item: ArchiveOrgItem) {
        selectionGeneration += 1  // a new async destination supersedes older fetches
        navStack.append(currentNavEntry())
        if let src = currentArchiveOrgProfile?.source {
            var lid: Int? = nil
            if case .list(_, let id) = src { lid = id }
            currentFilesParent = .aoItem(item, user: src.username, listID: lid)
        }
        // Captured before the profile state is cleared - keys the
        // catalogue's file cache; bail rather than risk writing under the
        // wrong catalogue. WHY: catalogueKey picks per source - a list's
        // films must never be cached under the list owner's uploads key
        // (see keyForList in TransferResolver.swift).
        guard let source = currentArchiveOrgProfile?.source else {
            rebuildList(rows: [
                ("  couldn't tell which profile this film belongs to", false, nil, {}),
                ("  ← back", true, nil, { [weak self] in self?.goBack() }),
            ])
            return
        }
        let catalogueKey: String
        switch source {
        case .profile(let username): catalogueKey = username
        case .list(let username, let listID): catalogueKey = ArchiveOrgCatalogue.keyForList(username: username, listID: listID)
        }
        currentTitle = item.title
        currentSectionTitles = nil
        currentArchiveOrgProfile = nil
        currentArchiveOrgListPicker = nil
        currentArchiveOrgFilter = nil
        currentArchiveOrgFilterCategory = nil
        screen = .fetching
        topBar.setTitle("\(item.title) · fetching...")
        topBar.backVisible = true
        // WHY: the cancel row bails out of a stalled /metadata request
        // immediately, and the generation check keeps a late response
        // from overwriting the screen the user moved to.
        let openingGeneration = selectionGeneration
        rebuildList(rows: [
            ("  opening \(item.title)...", false, nil, {}),
            ("  ✕ cancel", true, nil, { [weak self] in self?.goBack() }),
        ])

        // WHY: resolveFiles caches a film's file list forever once
        // opened - later visits need no network request.
        ArchiveOrgCatalogue.shared.resolveFiles(identifier: item.identifier, username: catalogueKey) { [weak self] files, errorMessage in
            DispatchQueue.main.async {
                guard let self, self.selectionGeneration == openingGeneration else { return }
                guard !files.isEmpty else {
                    // prefix the real reason (timeout, DNS, archive.org
                    // error) so a connection failure doesn't read as an
                    // empty item
                    let message = errorMessage.map { "archive.org error: \($0)" } ?? "no video files found for \(item.title)"
                    self.rebuildList(rows: [
                        ("  \(message)", false, nil, {}),
                        ("  ← back", true, nil, { [weak self] in self?.goBack() }),
                    ])
                    return
                }
                self.currentFiles = files
                self.screen = .files
                self.topBar.setTitle(item.title)
                if files.count == 1, let onlyFile = files.first, !onlyFile.isFolder {
                    self.selectionGeneration += 1
                    self.selectFile(onlyFile)
                } else {
                    // preserveOrder: true — keep ArchiveOrgResolver's own
                    // mkv-first/largest-first ordering on first display;
                    // the sort button (applySortToCurrentScreen) still
                    // re-sorts normally if tapped.
                    self.showFiles(files, preserveOrder: true)
                }
            }
        }
    }
    
    // preserveOrder: true keeps `files` in the order the caller already
    // sorted them in (used for an archive.org item's mkv/mp4 list, which
    // arrives already ordered mkv-first/largest-first — see
    // ArchiveOrgResolver.fetchItemFiles) instead of re-sorting by the
    // topBar's sortMode. The sort button still overrides this: tapping it
    // calls applySortToCurrentScreen(), which always re-renders through the
    // normal sortedFiles() path, so A-Z/Z-A/newest remain one tap away —
    // this only affects what's shown before the user asks for a different
    // order.
    private func showFiles(_ files: [ArchiveFile], preserveOrder: Bool = false) {
        let folderIcons = ["","","","","","","","","","",""]
        // Keep companions in currentFiles/navStack, but never play them as videos.
        let page = "files:" + currentTitle
        let deletedHere = ArchiveUserLists.shared.deletedKeys(page: page)
        func fileKey(_ file: ArchiveFile) -> String { "f:" + file.name + "|" + file.elementId }
        if let parent = currentFilesParent {
            for file in files where deletedHere.contains(fileKey(file)) {
                ArchiveUserLists.shared.backfillTarget(page: page, key: fileKey(file),
                    target: .file(parent: parent, name: file.name, elementId: file.elementId, isFolder: file.isFolder))
            }
        }
        let visibleFiles = files.filter { !$0.isGofileSubtitle && !deletedHere.contains(fileKey($0)) }
        let orderedFiles = preserveOrder ? visibleFiles : sortedFiles(visibleFiles)
        let rows: [(String, Bool, String?, () -> Void)] = orderedFiles.enumerated().map { (i, file) in
            if file.isFolder {
                let icon = folderIcons[i % folderIcons.count]
                return ("  \(icon) \(file.name)", true, nil, { [weak self] in
                    // WHY: transferURL arrives complete from
                    // resolveDriveFolder/gofile - rebuilding a Drive link
                    // from elementId would break gofile subfolders.
                    guard let self else { return }
                    self.nextFilesParent = self.currentFilesParent.map {
                        .file(parent: $0, name: file.name, elementId: file.elementId, isFolder: true)
                    }
                    self.selectTitle(file.name, links: [file.transferURL])
                })
            } else if file.transferURL.hasPrefix("gofile-unresolved::") {
                // WHY: gofile's folder field is unverified, so this child
                // may be a folder or an unsupported type - selectFile
                // would spin a "retrying..." loop with no clear error.
                // Show a fixed warning instead.
                return ("  \(file.name)", true, file.size, { [weak self] in
                    self?.topBar.setTitle("\(file.name) · unrecognized (might be a folder - gofile support doesn't cover it yet)")
                })
            } else {
                return ("  \(file.name)", true, file.size, { [weak self] in
                    self?.selectionGeneration += 1  // new selection — invalidate any previous file's retry chain
                    self?.selectFile(file)
                })
            }
        }
        let parentTarget = currentFilesParent
        let acc = orderedFiles.enumerated().map { (i, file) in
            accessories(for: rowMeta(fileKey(file), file.name, page: page, parent: currentTitle, index: i,
                                     target: parentTarget.map {
                                         .file(parent: $0, name: file.name, elementId: file.elementId, isFolder: file.isFolder)
                                     }))
        }
        rebuildList(rows: rows, accessories: acc, page: page, contentActions: rows.filter { $0.1 }.map { $0.3 })
        consumePendingFile(in: files)
    }

    // Extracts the folder/share key from either transferURL shape
    // fetchMegaNodes produces: a plain root share URL ("...#KEY"), or a
    // subfolder composite ("mega-folder::...#KEY::handle"). Both keep the
    // SAME folder-wide key after the LAST '#' — MEGA doesn't re-key
    // subfolders within one public folder share — so take everything
    // after the last '#' and, if present, drop a trailing "::handle".
    private static func megaFolderKeyFragment(from transferURL: String) -> String? {
        guard let hashRange = transferURL.range(of: "#", options: .backwards) else { return nil }
        var fragment = String(transferURL[hashRange.upperBound...])
        if let sepRange = fragment.range(of: "::") {
            fragment = String(fragment[..<sepRange.lowerBound])
        }
        return fragment.isEmpty ? nil : fragment
    }

    /// True while the interception placeholder row is the visible list. Mega
    /// relay status renders as a row under it instead of the mpv OSD layer,
    /// which overlaps this panel's topbar.
    private var interceptRowVisible = false

    private func selectFile(_ file: ArchiveFile, attemptsLeft: Int = 3) {
        pendingFilePath = []
        // Snapshot the current generation. If the user navigates away or taps
        // a different file before this capture (or a scheduled retry of it)
        // fires, selectionGeneration will have moved on and we bail out
        // instead of acting on a stale selection.
        let generation = selectionGeneration

        topBar.setTitle("\(file.name) · getting URL...")
        topBar.backVisible = true
        rebuildList(rows: [("  intercepting signed URL...", false, nil, {})])
        interceptRowVisible = true
        print("🔍 file.elementId: \(file.elementId)")
        print("🔍 file.transferURL: \(file.transferURL)")
        resolver.captureURL(transferURL: file.transferURL,
                            elementId: file.elementId) { [weak self] signedURL in
            DispatchQueue.main.async {
                guard let self else { return }

                guard self.selectionGeneration == generation else {
                    print("🔄 capture returned for a stale selection, discarding")
                    return
                }

                guard let url = signedURL else {
                    // CDPSession exhausted its own XHR retries - give the
                    // page a moment, then retry up to attemptsLeft times
                    // (bounded; the user may have left).
                    guard attemptsLeft > 1 else {
                        print("🔄 URL capture failed repeatedly, giving up")
                        self.topBar.setTitle("\(file.name) · couldn't get URL — try again")
                        self.resolver.cancel()
                        return
                    }
                    print("🔄 URL capture failed, retrying with fresh session… (\(attemptsLeft - 1) attempt(s) left)")
                    self.topBar.setTitle("\(file.name) · retrying…")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        guard let self, self.selectionGeneration == generation else { return }
                        self.selectFile(file, attemptsLeft: attemptsLeft - 1)
                    }
                    return
                }
                // Pass URL to mpv. Keep the session alive until mpv confirms it has
                // opened the file (currentFilePath non-empty), then close the browser.
                // We do NOT cancel the session here — it may still be needed for the
                // subfolder XHR on a subsequent file selection.
                self.resolveGofileSubtitles(for: file, generation: generation) { [weak self] subtitleURLs in
                    guard let self, self.selectionGeneration == generation else { return }
                    self.onPlay?(url, file.name, file.nodeKey,
                                 file.nodeKey != nil ? Self.megaFolderKeyFragment(from: file.transferURL) : nil,
                                 subtitleURLs)
                    if file.transferURL.contains("pixeldrain.com") {
                        self.resolver.cancel()
                        self.onClose?()
                    } else {
                        self.waitForStreamStart(file: file, attemptsLeft: 20, generation: generation)
                    }
                }
            }
        }
    }

    // Resolve sequentially: the DOM fallback owns one CDP session at a time.
    // Snapshot the complete containing folder before filtering/search changes its rows.
    private func resolveGofileSubtitles(for video: ArchiveFile, generation: Int,
                                        completion: @escaping ([String]) -> Void) {
        guard video.transferURL.hasPrefix("gofile-direct::") ||
                video.transferURL.hasPrefix("https://gofile.io/d/") else { completion([]); return }
        let companions = currentFiles.filter { $0.isGofileSubtitle && $0.gofileFolderID == video.gofileFolderID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        var urls: [String] = []
        func resolveNext(_ index: Int) {
            guard self.selectionGeneration == generation else { return }
            guard index < companions.count else {
                print("[gofile-subtitles 260930.1] resolved \(urls.count)/\(companions.count) folder companions")
                completion(urls); return
            }
            let subtitle = companions[index]
            self.resolver.captureURL(transferURL: subtitle.transferURL, elementId: subtitle.elementId) { [weak self] signedURL in
                DispatchQueue.main.async {
                    guard let self, self.selectionGeneration == generation else { return }
                    if let signedURL, !urls.contains(signedURL) {
                        urls.append(signedURL)
                    } else {
                        print("[gofile-subtitles 260930.1] companion URL unavailable: \(subtitle.name)")
                    }
                    resolveNext(index + 1)
                }
            }
        }
        resolveNext(0)
    }

    private func waitForStreamStart(file: ArchiveFile, attemptsLeft: Int, generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.selectionGeneration == generation else { return }
            let appDelegate = NSApp.delegate as? AppDelegate
            let streamStarted = appDelegate?.controller?.currentFilePath.isEmpty == false

            if streamStarted {
                self.resolver.cancel()
                self.onClose?()
            } else if attemptsLeft > 1 {
                self.waitForStreamStart(file: file, attemptsLeft: attemptsLeft - 1, generation: generation)
            } else {
                // mpv never opened the file — URL likely expired; get a fresh one
                print("🔄 Stream not started after 10 s, fetching fresh URL…")
                self.topBar.setTitle("\(file.name) · retrying…")
                self.selectFile(file)
            }
        }
    }
    
    // MARK: - Navigation
    
    // WHY: navStack holds exactly what to redraw for each level; pop and
    // redraw, never a hardcoded destination. Falls back to close() at the
    // top of the stack.
    private func goBack() {
        resolver.cancel()
        // WHY: cancel() only tears down a CDP session - archive.org's
        // URLSession requests keep running, so the generation bump is what
        // stops a late response from rewriting the screen.
        selectionGeneration += 1
        searchDebounceItem?.cancel()
        // WHY: a library-level search pushes nothing onto navStack, so
        // back here clears the query and redraws the plain library -
        // popping could leave the library or close the panel outright.
        if isFiltered, screen == .library {
            isFiltered = false
            searchQuery = ""
            showLibrary()
            return
        }
        pendingFilePath = []
        pendingFacet = nil
        isFiltered = false  // leaving this screen — an active search shouldn't silently carry over to whatever we pop back to
        guard let previous = navStack.popLast() else {
            close()
            return
        }
        switch previous {
        case .library:
            showLibrary(pushingCurrent: false)
        case .section(let name, let titles):
            showSection(name, titles: titles, pushingCurrent: false)
        case .files(let title, let files, let parent):
            currentFilesParent = parent
            currentTitle = title
            currentFiles = files
            currentSectionTitles = nil
            currentArchiveOrgProfile = nil
            currentArchiveOrgListPicker = nil
            currentArchiveOrgFilter = nil
            screen = .files
            topBar.setTitle(title)
            topBar.backVisible = true
            showFiles(files)
        case .archiveOrgProfile(let source, let items, let filter, let category):
            // restores the category value-list view too when that's what
            // was on screen (see NavEntry.archiveOrgProfile)
            currentArchiveOrgFilterCategory = category
            showArchiveOrgProfile(source: source, items: items, filter: filter, pushingCurrent: false)
        case .archiveOrgListPicker(let username, let lists):
            showArchiveOrgListPicker(username: username, lists: lists, pushingCurrent: false)
        case .favorites:
            showFavorites(pushingCurrent: false)
        case .deleted(let page, let label):
            showDeleted(page: page, label: label, pushingCurrent: false)
        }
    }
    
    private func filterContent(_ query: String) {
        // Search only covers the normal pages; favorites/deleted lists are short and fixed.
        guard listMode == .normal else { return }
        searchQuery = query
        searchDebounceItem?.cancel()

        guard !query.isEmpty else {
            isFiltered = false
            // Clearing the query (backspace to empty) should feel instant —
            // no debounce needed, there's nothing expensive to wait out.
            if screen == .library { showLibrary() }
            else if let profile = currentArchiveOrgProfile { showArchiveOrgProfile(source: profile.source, items: profile.items, filter: currentArchiveOrgFilter, pushingCurrent: false) }
            else if let sectionTitles = currentSectionTitles { showSection(currentTitle, titles: sectionTitles, pushingCurrent: false) }
            else { showFiles(currentFiles) }
            return
        }

        isFiltered = true
        // WHY: the library screen normally hides back, but an active
        // search is its own state needing a way out (goBack() special-
        // cases it). Toggled here once per search session, not per
        // keystroke in runFilter.
        if screen == .library {
            topBar.backVisible = true
        }
        let item = DispatchWorkItem { [weak self] in
            self?.runFilter(query)
        }
        searchDebounceItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    private func runFilter(_ query: String) {
        // Search rows follow the same rules as the pages they come from: rows deleted on their
        // own page stay hidden, and every row carries its own favorite/delete buttons.
        var delCache: [String: Set<String>] = [:]
        func hidden(_ page: String, _ key: String) -> Bool {
            if delCache[page] == nil { delCache[page] = ArchiveUserLists.shared.deletedKeys(page: page) }
            return delCache[page]?.contains(key) ?? false
        }
        var acc: [[FileRowAccessory]] = []
        // WHY: search the section's titles when currentSectionTitles is
        // set - currentFiles is stale/empty there. Otherwise the real
        // file list.
        if screen == .library {
            // Global ara
            let matches = ArchiveLibrary.shared.titles.filter {
                $0.title.localizedCaseInsensitiveContains(query) || $0.section.localizedCaseInsensitiveContains(query)
            }
            var rows: [(String, Bool, String?, () -> Void)] = []
            let folderIcons = ["","","","","","","","","","",""]
            for (i, title) in sortedTitles(matches).enumerated() {
                let tkey = "t:" + title.title + "|" + (title.links.first ?? "")
                guard !hidden("section:" + title.section, tkey) else { continue }
                let icon = folderIcons[i % folderIcons.count]
                rows.append(("  \(icon) \(title.title) [\(title.section)]", true, nil, {
                    self.selectTitle(title.title, links: title.links)
                }))
                acc.append(accessories(for: rowMeta(tkey, title.title, page: "section:" + title.section,
                    parent: title.section, index: acc.count, target: .title(title))))
            }
            // WHY: every profile/list opened at least once has its full
            // film list cached on disk (ArchiveOrgCatalogue), so global
            // search includes those cached titles without network. Matches
            // open via the normal select entry points; never-fetched rows
            // contribute nothing.
            for title in ArchiveLibrary.shared.titles {
                guard let link = title.links.first, let source = archiveOrgSource(fromLink: link) else { continue }
                let key: String
                switch source {
                case .profile(let username): key = username
                case .list(let username, let listID): key = ArchiveOrgCatalogue.keyForList(username: username, listID: listID)
                }
                let cachedItems = ArchiveOrgCatalogue.shared.currentItems(for: key)
                guard !cachedItems.isEmpty else { continue }
                let filmMatches = cachedItems.filter { $0.title.localizedCaseInsensitiveContains(query) }
                var itemListID: Int? = nil
                if case .list(_, let id) = source { itemListID = id }
                for item in archiveOrgSorted(filmMatches) {
                    guard !hidden("ao:" + key, "o:" + item.identifier) else { continue }
                    acc.append(accessories(for: rowMeta("o:" + item.identifier, item.title, page: "ao:" + key,
                        parent: sheetRowTitle(title), index: acc.count,
                        target: .aoItem(item, user: source.username, listID: itemListID))))
                    rows.append(("  \(item.title) [\(sheetRowTitle(title))]", true, nil, { [weak self] in
                        guard let self else { return }
                        self.pendingArchiveOrgIdentifier = item.identifier
                        switch source {
                        case .profile(let username):
                            self.selectArchiveOrgProfile(username: username, pushingCurrent: true)
                        case .list(let username, let listID):
                            self.selectArchiveOrgList(username: username, listID: listID, pushingCurrent: true)
                        }
                    }))
                }
            }
            if rows.isEmpty { rows.append(("  no results for \"\(query)\"", false, nil, {})) }
            rebuildList(rows: rows, accessories: acc, contentActions: rows.filter { $0.1 }.map { $0.3 })
        } else if let profile = currentArchiveOrgProfile {
            var profListID: Int? = nil
            if case .list(_, let id) = profile.source { profListID = id }
            let profPage: String
            switch profile.source {
            case .profile(let username): profPage = "ao:" + username
            case .list(let username, let listID): profPage = "ao:" + ArchiveOrgCatalogue.keyForList(username: username, listID: listID)
            }
            // WHY: on a category's value-list screen, search that
            // category's own values - searching film titles against a
            // screen that isn't showing films reads as broken.
            if let category = currentArchiveOrgFilterCategory {
                func pick(_ item: ArchiveOrgItem) -> String? {
                    switch category {
                    case .year: return item.year
                    case .creator: return item.creator
                    case .language: return item.language
                    case .subject: return item.subject
                    }
                }
                func makeFilter(_ value: String) -> ArchiveOrgFilter {
                    switch category {
                    case .year: return .year(value)
                    case .creator: return .creator(value)
                    case .language: return .language(value)
                    case .subject: return .subject(value)
                    }
                }
                let matches = archiveOrgFacetValues(profile.items, pick).filter { $0.value.localizedCaseInsensitiveContains(query) }
                var rows: [(String, Bool, String?, () -> Void)] = []
                for (value, count) in matches {
                    let vkey = "v:" + facetName(category) + ":" + value
                    guard !hidden(profPage, vkey) else { continue }
                    rows.append(("  · \(value)  (\(count))", true, nil, { [weak self] in
                        guard let self else { return }
                        self.currentArchiveOrgFilterCategory = nil
                        self.showArchiveOrgProfile(source: profile.source, items: profile.items, filter: makeFilter(value), pushingCurrent: true)
                    }))
                    acc.append(accessories(for: rowMeta(vkey, value, page: profPage, parent: currentTitle, index: acc.count,
                        target: .aoFacet(user: profile.source.username, listID: profListID, category: facetName(category), value: value))))
                }
                if rows.isEmpty { rows.append(("  no results for \"\(query)\"", false, nil, {})) }
                rebuildList(rows: rows, accessories: acc, contentActions: [])
                return
            }
            let matches = profile.items.filter { $0.title.localizedCaseInsensitiveContains(query) }
            var rows: [(String, Bool, String?, () -> Void)] = []
            for item in archiveOrgSorted(matches) {
                guard !hidden(profPage, "o:" + item.identifier) else { continue }
                rows.append(("  \(item.title)", true, nil, { [weak self] in
                    self?.selectArchiveOrgItem(item)
                }))
                acc.append(accessories(for: rowMeta("o:" + item.identifier, item.title, page: profPage, parent: currentTitle,
                    index: acc.count, target: .aoItem(item, user: profile.source.username, listID: profListID))))
            }
            if rows.isEmpty { rows.append(("  no results for \"\(query)\"", false, nil, {})) }
            rebuildList(rows: rows, accessories: acc, contentActions: rows.filter { $0.1 }.map { $0.3 })
        } else if let sectionTitles = currentSectionTitles {
            // search within the section's title list
            let matches = sectionTitles.filter { $0.title.localizedCaseInsensitiveContains(query) }
            var rows: [(String, Bool, String?, () -> Void)] = []
            let folderIcons = ["","","","","","","","","","",""]
            let secPage = "section:" + currentTitle
            for (i, title) in sortedTitles(matches).enumerated() {
                let tkey = "t:" + title.title + "|" + (title.links.first ?? "")
                guard !hidden(secPage, tkey) else { continue }
                let icon = folderIcons[i % folderIcons.count]
                rows.append(("  \(icon) \(sheetRowTitle(title))", true, nil, {
                    self.selectTitle(title.title, links: title.links)
                }))
                acc.append(accessories(for: rowMeta(tkey, sheetRowTitle(title), page: secPage, parent: currentTitle,
                    index: acc.count, target: .title(title))))
            }
            if rows.isEmpty { rows.append(("  no results for \"\(query)\"", false, nil, {})) }
            rebuildList(rows: rows, accessories: acc, contentActions: rows.filter { $0.1 }.map { $0.3 })
        } else {
            // search only currentFiles. isFiltered is already true by
            // the time this runs (set synchronously in filterContent before
            // the debounce fires), so this only snapshots once per search
            // session — not on every keystroke's delayed runFilter call.
            showFiles(currentFiles.filter { $0.name.localizedCaseInsensitiveContains(query) })
        }
    }

    
    private func close() {
        selectionGeneration += 1  // panel closing — invalidate stale retries
        interceptRowVisible = false
        resolver.cancel()
        searchDebounceItem?.cancel()  // pending debounced search — pointless once the panel is gone
        // clear onUpdated so a closed panel stops listening
        if ArchiveLibrary.shared.onUpdated != nil {
            ArchiveLibrary.shared.onUpdated = nil
        }
        onClose?()
    }
    
    // MARK: - List

    /// Mega relay status while intercepting: a row below the placeholder, per
    /// the no-overlap spec. Returns false once the placeholder is gone (panel
    /// closed, user navigated) so the caller falls back to the mpv OSD.
    func showMegaRelayStatus(_ message: String) -> Bool {
        guard interceptRowVisible else { return false }
        rebuildList(rows: [
            ("  intercepting signed URL...", false, nil, {}),
            ("  " + message, false, nil, {}),
        ])
        interceptRowVisible = true  // rebuildList cleared it; still intercepting
        return true
    }

    // `accessories` is aligned with `rows` (shorter is fine); `page` names the page these rows
    // belong to, which decides whether the deleted-items button is offered.
    private func rebuildList(rows: [(String, Bool, String?, () -> Void)],
                             accessories: [[FileRowAccessory]] = [],
                             page: String? = nil,
                             contentActions: [() -> Void] = []) {
        interceptRowVisible = false
        // Choose from the same actionable visible rows, never the hidden/deleted
        // source arrays or accessory buttons. Mixed folders/videos use one draw;
        // the chosen row's normal action decides browse vs play.
        randomActions = contentActions
        listMode = .normal
        currentPageKey = page
        updateChrome()
        listView?.removeFromSuperview()
        listScroll.documentView = nil
        
        let width = max(listScroll.bounds.width, bounds.width, 100)
        let listView = FileListView(width: width)
        
        for (index, (title, playable, sizeText, action)) in rows.enumerated() {
            listView.row(idx: index, title: title, isPlayable: playable, sizeText: sizeText,
                         accessories: index < accessories.count ? accessories[index] : [],
                         action: action)
        }
        
        listView.finish(scrollView: listScroll)
        self.listView = listView
    }

    // MARK: - Deleted items / favorites

    private func updateChrome() {
        topBar.favoritesVisible = !isTorrentMode && listMode != .favorites
        topBar.deletedVisible = !isTorrentMode && listMode == .normal && currentPageKey != nil
    }

    // Hover buttons for one row: favorite toggle and delete. Both work on every row that has an owner page.
    private func accessories(for meta: ArchiveRowMeta?) -> [FileRowAccessory] {
        guard let meta else { return [] }
        var out: [FileRowAccessory] = []
        if let target = meta.target {
            let fav = ArchiveFavorite(key: meta.key, label: meta.label, target: target)
            let isFav = ArchiveUserLists.shared.isFavorite(key: fav.key)
            out.append(FileRowAccessory(glyph: "♥", hover: isFav ? "unfavorite" : "favorite") { [weak self] in
                ArchiveUserLists.shared.toggleFavorite(fav)
                self?.rerenderPreservingScroll()
            })
        }
        if listMode == .favorites { return out }
        out.append(FileRowAccessory(glyph: "×", hover: "delete") { [weak self] in
            ArchiveUserLists.shared.delete(page: meta.page, key: meta.key, label: meta.label,
                                           parent: meta.parent, index: meta.index, target: meta.target)
            self?.libraryListView = nil  // cached library rows still show this one
            self?.rerenderPreservingScroll()
        })
        return out
    }

    // Row meta for the page being built; `index` is the row's position in `acc`.
    private func rowMeta(_ key: String, _ label: String, page: String, parent: String,
                         index: Int, target: ArchiveTarget?) -> ArchiveRowMeta {
        ArchiveRowMeta(key: key, label: label, page: page, parent: parent, index: index, target: target)
    }

    private func rerenderPreservingScroll() {
        let y = listScroll.contentView.bounds.origin.y
        if isFiltered, listMode == .normal, !searchQuery.isEmpty { runFilter(searchQuery) } else { applySortToCurrentScreen() }
        if let doc = listScroll.documentView {
            let maxY = max(0, doc.frame.height - listScroll.contentSize.height)
            listScroll.contentView.setBoundsOrigin(NSPoint(x: 0, y: min(y, maxY)))
        }
    }

    private func resetScreenState(title: String) {
        selectionGeneration += 1  // invalidate stale async results from the screen we leave
        isFiltered = false
        currentTitle = title
        currentFiles = []
        currentSectionTitles = nil
        currentArchiveOrgProfile = nil
        currentArchiveOrgListPicker = nil
        currentArchiveOrgFilter = nil
        currentArchiveOrgFilterCategory = nil
        screen = .files
        topBar.setTitle(title)
        topBar.backVisible = true
    }

    private func showFavorites(pushingCurrent: Bool) {
        if pushingCurrent { navStack.append(currentNavEntry()) }
        resetScreenState(title: "favorites")
        listMode = .favorites   // before building rows: favorites rows get no delete button
        let favs = ArchiveUserLists.shared.favorites
        var rows: [(String, Bool, String?, () -> Void)] = []
        var acc: [[FileRowAccessory]] = []
        var eligibleFavorites: [() -> Void] = []
        for fav in favs {
            if Self.isRandomContent(fav.target) { eligibleFavorites.append { [weak self] in self?.openFavorite(fav) } }
            rows.append(("  \(fav.label)", true, nil, { [weak self] in self?.openFavorite(fav) }))
            acc.append(accessories(for: ArchiveRowMeta(key: fav.key, label: fav.label, page: "", parent: "",
                                                       index: acc.count, target: fav.target)))
        }
        if rows.isEmpty { rows.append(("  no favorites yet", false, nil, {})) }
        rebuildList(rows: rows, accessories: acc, page: nil, contentActions: eligibleFavorites)
        listMode = .favorites
        updateChrome()
    }

    private func openFavorite(_ fav: ArchiveFavorite) { open(fav.target) }

    // Replays a path from a catalogue entry; pages and files are fetched fresh, so nothing
    // depends on a stored (signed/expiring) URL. File targets finish by picking the row by
    // name + id once its parent page has loaded (see consumePendingFile).
    private func open(_ target: ArchiveTarget) {
        pendingFilePath = []
        pendingFacet = nil
        switch target {
        case .section(let name):
            let titles = ArchiveLibrary.shared.titles.filter { $0.section == name }
            showSection(name, titles: titles, pushingCurrent: true)
        case .title(let t):
            selectTitle(t.title, links: t.links)
        case .aoList(let user, let id, _):
            selectArchiveOrgList(username: user, listID: id, pushingCurrent: true)
        case .aoItem(let item, let user, let listID):
            let source: ArchiveOrgSource
            if let id = listID { source = .list(username: user, listID: id) } else { source = .profile(username: user) }
            // selectArchiveOrgItem reads the owning profile/list from here; the nav entry stays .favorites.
            currentArchiveOrgProfile = (source, [])
            selectArchiveOrgItem(item)
        case .aoFacet(let user, let listID, let category, let value):
            pendingFacet = (user, listID, category, value)
            if let id = listID {
                selectArchiveOrgList(username: user, listID: id, pushingCurrent: true)
            } else {
                selectArchiveOrgProfile(username: user, pushingCurrent: true)
            }
        case .file:
            // Collect the chain root-first: [folder..., file], open the root, then walk down.
            var chain: [(String, String)] = []
            var node = target
            while case .file(let parent, let name, let elementId, _) = node {
                chain.insert((name, elementId), at: 0)
                node = parent
            }
            open(node)
            pendingFilePath = chain
        }
    }

    // Called when a files page is on screen: if a favorite is waiting for one of its rows, open it.
    private func consumePendingFile(in files: [ArchiveFile]) {
        guard let next = pendingFilePath.first else { return }
        guard let file = files.first(where: { $0.name == next.0 && $0.elementId == next.1 }) else {
            pendingFilePath = []   // row no longer exists at the source; leave the list as is
            return
        }
        pendingFilePath.removeFirst()
        if file.isFolder {
            nextFilesParent = currentFilesParent.map { .file(parent: $0, name: file.name, elementId: file.elementId, isFolder: true) }
            selectTitle(file.name, links: [file.transferURL])
        } else {
            pendingFilePath = []
            selectionGeneration += 1
            selectFile(file)
        }
    }

    // archive.org facet values are narrowed with the same filters the tree uses.
    private func facetFilter(category: String, value: String) -> ArchiveOrgFilter? {
        switch category {
        case "year": return .year(value)
        case "creator": return .creator(value)
        case "language": return .language(value)
        case "subject": return .subject(value)
        default: return nil
        }
    }
    private func facetCategory(_ name: String) -> ArchiveOrgFilterCategory? {
        switch name {
        case "year": return .year
        case "creator": return .creator
        case "language": return .language
        case "subject": return .subject
        default: return nil
        }
    }
    private func facetName(_ category: ArchiveOrgFilterCategory) -> String {
        switch category {
        case .year: return "year"
        case .creator: return "creator"
        case .language: return "language"
        case .subject: return "subject"
        }
    }

    // Entries saved before paths were stored: sections, titles and archive.org lists can be rebuilt from
    // the key and page alone. Every other kind is filled in the first time its page is shown (backfillTarget).
    private static func derivedTarget(page: String, entry: ArchiveDeletedEntry) -> ArchiveTarget? {
        let key = entry.key
        if key.hasPrefix("s:") { return .section(String(key.dropFirst(2))) }
        if key.hasPrefix("t:") {
            let rest = String(key.dropFirst(2))
            if let bar = rest.lastIndex(of: "|") {
                let title = String(rest[..<bar]), link = String(rest[rest.index(after: bar)...])
                if let t = ArchiveLibrary.shared.titles.first(where: { $0.title == title && ($0.links.first ?? "") == link }) {
                    return .title(t)
                }
            }
            return nil
        }
        if key.hasPrefix("l:"), page.hasPrefix("aolists:"), let id = Int(key.dropFirst(2)) {
            return .aoList(user: String(page.dropFirst("aolists:".count)), id: id, name: entry.label)
        }
        return nil
    }

    private static func isRandomContent(_ target: ArchiveTarget) -> Bool {
        if case .aoFacet = target { return false }
        return true
    }

    private func showDeleted(page: String, label: String, pushingCurrent: Bool) {
        if pushingCurrent { navStack.append(currentNavEntry()) }
        resetScreenState(title: "deleted · \(label)")
        var rows: [(String, Bool, String?, () -> Void)] = []
        var acc: [[FileRowAccessory]] = []
        var eligibleDeleted: [() -> Void] = []
        for entry in ArchiveUserLists.shared.deletedEntries(page: page).sorted(by: { $0.index < $1.index }) {
            if let target = entry.target ?? Self.derivedTarget(page: page, entry: entry), Self.isRandomContent(target) {
                eligibleDeleted.append { [weak self] in self?.open(target) }
            }
            // Clicking the title opens the row exactly as on its own page (browse inside it, play it)
            // without recovering it; only the + button puts it back. The size slot shows which page
            // the row came from.
            rows.append(("  \(entry.label)", true, entry.parent.isEmpty ? nil : entry.parent, { [weak self] in
                if let t = entry.target ?? Self.derivedTarget(page: page, entry: entry) { self?.open(t) }
            }))
            acc.append([FileRowAccessory(glyph: "+", hover: "recover", alwaysVisible: true) { [weak self] in
                ArchiveUserLists.shared.recover(page: page, key: entry.key)
                self?.libraryListView = nil
                self?.rerenderPreservingScroll()
            }])
        }
        if rows.isEmpty { rows.append(("  nothing deleted here", false, nil, {})) }
        rebuildList(rows: rows, accessories: acc, page: nil, contentActions: eligibleDeleted)
        listMode = .deleted(page: page, label: label)
        updateChrome()
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ================================================================
//  ArchiveTopBar - title bar + floating search panel
// ================================================================
// ─────────────────────────────────────────────────────────────────────────────

final class ArchiveTopBar: NSView, NSTextFieldDelegate {
    var onClose: (() -> Void)?
    var onBack: (() -> Void)?
    // WHY: the background load runs once per process and never re-fetches
    // on its own - refresh forces a reload so spreadsheet changes appear
    // without an app restart.
    var onRefresh: (() -> Void)?
    
    var backVisible: Bool = false {
        didSet {
            backBtn.isHidden = !backVisible
            needsLayout = true
        }
    }
    // Hidden in torrent mode (refreshVisible defaults to true, set false by
    // ArchiveBrowserPanel for torrent-file browsing where there's no
    // spreadsheet library to refresh).
    var refreshVisible: Bool = true {
        didSet {
            refreshBtn.isHidden = !refreshVisible
            needsLayout = true
        }
    }
    
    var onFavorites: (() -> Void)?
    var onDeleted: (() -> Void)?
    var favoritesVisible: Bool = false {
        didSet {
            guard favoritesVisible != oldValue else { return }
            favBtn.isHidden = !favoritesVisible
            needsLayout = true
        }
    }
    var deletedVisible: Bool = false {
        didSet {
            guard deletedVisible != oldValue else { return }
            delBtn.isHidden = !deletedVisible
            needsLayout = true
        }
    }
    
    var onSearch: ((String) -> Void)?
    // Cycles ArchiveBrowserPanel.sortMode on tap; icon reflects the mode
    // that's now active (set via setSortIcon right after toggling).
    var onSortToggle: (() -> Void)?
    var onRandom: (() -> Void)?
    var randomVisible = true { didSet { randomBtn.isHidden = !randomVisible; needsLayout = true } }
    // The search field's own floating NSPanel (see openSearchPanel), tracked
    // here so the app-wide ESC monitor (MenuActions.swift) can ask "is
    // search open?" before deciding to close the whole archive browser —
    // ESC should close search first, and only close the browser on a
    // second press once search is already gone. nil whenever no search
    // panel is currently on screen.
    private(set) weak var activeSearchPanel: NSPanel?
    // Same MusicBtn (typewriter hover title) the file browser top bar uses.
    private let searchBtn = MusicBtn("◌", hover: "search")
    private let refreshBtn = MusicBtn("•", hover: "refresh")
    private let randomBtn = MusicBtn("∞", hover: "random")
    private let sortBtn = MusicBtn("↓", hover: "sort")
    // Same hearts the IPTV bar uses for its faves; "∅" exists in every UI font and cannot be
    // mistaken for the close "×".
    private let favBtn = MusicBtn("♥", hover: "favorites")
    private let delBtn = MusicBtn("∅", hover: "deleted")
    
    private let closeBtn = MusicBtn("×", hover: "close")
    private let backBtn = MusicBtn("←", hover: "back")
    private let titleLbl: NSTextField = {
        let field = NSTextField()
        field.isEditable = false
        field.isBordered = false
        field.drawsBackground = false
        field.textColor = NSColor.white.withAlphaComponent(0.5)
        field.font = PhotonFont.chromeNs()
        return field
    }()
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        
        closeBtn.tap = { [weak self] in self?.tappedClose() }
        backBtn.expandsLeftToRight = true
        backBtn.tap = { [weak self] in self?.tappedBack() }
        backBtn.isHidden = true
        searchBtn.tap = { [weak self] in self?.openSearchPanel() }
        refreshBtn.tap = { [weak self] in self?.tappedRefresh() }
        randomBtn.tap = { [weak self] in self?.onRandom?() }
        sortBtn.tap = { [weak self] in self?.tappedSort() }
        favBtn.tap = { [weak self] in self?.onFavorites?() }
        delBtn.tap = { [weak self] in self?.onDeleted?() }
        favBtn.isHidden = true
        delBtn.isHidden = true
        addSubview(searchBtn)
        
        [backBtn, titleLbl, searchBtn, refreshBtn, sortBtn, randomBtn, favBtn, delBtn, closeBtn].forEach { addSubview($0) }
        
        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self, self.window != nil else { return }
            self.titleLbl.font = PhotonFont.chromeNsDriven(view: self, profile: .panel)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setTitle(_ title: String) {
        titleLbl.stringValue = title
    }

    func setSortIcon(_ icon: String) {
        sortBtn.setLabel(icon)
    }
    
    override func layout() {
        super.layout()
        let height = bounds.height
        let pad: CGFloat = 4
        // Back expands left to right from a pinned origin; the right group
        // keeps equal gaps between glyph ink edges (IconBarFit), live ink
        // widths, and the title yields to both.
        var leftX: CGFloat = pad
        if !backBtn.isHidden {
            backBtn.frame = CGRect(x: leftX, y: 0, width: backBtn.frame.width, height: height)
            leftX += backBtn.frame.width + pad
        }
        // Deleted-items button sits left of the whole button group, as the user asked.
        let rightBtns = ([closeBtn, refreshBtn, searchBtn, sortBtn, randomBtn, favBtn, delBtn] as [MusicBtn]).filter { !$0.isHidden }
        let frames = IconBarFit.trailingFrames(right: bounds.width - pad, height: height, gap: IconBarFit.standardGap,
            buttons: rightBtns.map { IconBarFit.Slot(width: $0.frame.width, ink: $0.inkWidth) })
        for (btn, f) in zip(rightBtns, frames) { btn.frame = f }
        let rx = frames.last?.minX ?? (bounds.width - pad)
        titleLbl.frame = CGRect(x: leftX, y: 0, width: max(0, rx - leftX), height: height)
    }
    
    @objc private func tappedClose() { onClose?() }
    @objc private func tappedBack() { onBack?() }
    @objc private func tappedRefresh() { onRefresh?() }
    @objc private func tappedSort() { onSortToggle?() }
    
    @objc func openSearchPanel() {
        // WHY: a second press refocuses the existing panel instead of
        // leaking a new floating NSPanel each time.
        if let existing = activeSearchPanel {
            existing.makeKeyAndOrderFront(nil)
            if let tf = (existing.stereoSession?.original ?? existing.contentView)?.subviews.first(where: { $0 is NSTextField }) as? NSTextField {
                existing.makeFirstResponder(tf)
            }
            return
        }
        guard let parentWin = window else { return }
        let appDelegate = NSApp.delegate as? AppDelegate
        
        let ph: CGFloat = 54
        let startFrame = SearchBarFit.initialFrame(host: parentWin, height: ph)
        let pw = startFrame.width
        let px = startFrame.minX
        let py = startFrame.minY
        
        let panel = GORInputPanel(contentRect: CGRect(x: px, y: py, width: pw, height: ph),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false; panel.level = .modalPanel
        panel.backgroundColor = NSColor.black; panel.isOpaque = true
        panel.titlebarAppearsTransparent = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        
        let bg = NSView(frame: CGRect(x: 0, y: 0, width: pw, height: ph))
        bg.wantsLayer = true; bg.layer?.backgroundColor = NSColor.black.cgColor
        
        let tf = NSTextField(frame: CGRect(x: 20, y: 14, width: pw - 40, height: 28))
        tf.font = PhotonFont.chromeNs(); tf.textColor = .white
        tf.backgroundColor = .clear; tf.drawsBackground = false
        tf.isBordered = false; tf.focusRingType = .none
        tf.isEditable = true; tf.isSelectable = true
        tf.placeholderString = "search..."
        // live filtering per keystroke via controlTextDidChange; Enter
        // only dismisses the panel
        tf.delegate = self
        tf.target = self; tf.action = #selector(commitSearch)
        
        bg.addSubview(tf); panel.contentView = bg
        SearchBarFit.install(panel: panel, field: tf, anchor: .center, host: parentWin)
        
        appDelegate?.isShowingInputPanel = true
        appDelegate?.setEventTapEnabled(false)
        parentWin.ignoresMouseEvents = true
        activeSearchPanel = panel
        
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self, weak parentWin] _ in
            appDelegate?.isShowingInputPanel = false
            appDelegate?.setEventTapEnabled(true)
            parentWin?.ignoresMouseEvents = false
            if self?.activeSearchPanel === panel { self?.activeSearchPanel = nil }
        }
        
        panel.installStereoIfNeeded(parent: parentWin)
        panel.makeKeyAndOrderFront(nil)
        panel.assertKeyAndFocus(tf)
    }

    // WHY: the app-wide ESC monitor can't see this panel's first
    // responder - it is called first, closes the search panel and reports
    // back, so the same ESC doesn't also close the browser.
    @discardableResult
    func closeActiveSearchPanel() -> Bool {
        guard let panel = activeSearchPanel else { return false }
        panel.close()
        activeSearchPanel = nil
        return true
    }

    // Source commentary elided for privacy; historical proof hashes are not rebound.
    func toggleSearchFromKey() {
        if closeActiveSearchPanel() { return }
        openSearchPanel()
    }

    // Fires on every keystroke in the search field (NSTextFieldDelegate),
    // not just on Enter — filters the list as the user types instead of
    // waiting for the full query.
    func controlTextDidChange(_ obj: Notification) {
        guard let tf = obj.object as? NSTextField else { return }
        onSearch?(tf.stringValue.trimmingCharacters(in: .whitespaces))
    }

    // Lets ESC inside the search field close just the search panel via the
    // normal responder chain (cancelOperation), instead of only being
    // reachable through the app-wide monitor in MenuActions.swift — belt
    // and suspenders, since first-responder key handling is more reliable
    // than a global monitor for a focused text field.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            closeActiveSearchPanel()
            return true
        }
        return false
    }

    @objc private func commitSearch() {
        guard let panel = activeSearchPanel,
              let tf = (panel.stereoSession?.original ?? panel.contentView)?.subviews.first(where: { $0 is NSTextField }) as? NSTextField else { return }
        let q = tf.stringValue.trimmingCharacters(in: .whitespaces)
        closeActiveSearchPanel()
        guard !q.isEmpty else { return }
        onSearch?(q)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// ================================================================
//  in_port_t - port helpers
// ================================================================
// ─────────────────────────────────────────────────────────────────────────────

// in_port_t bigEndian helper
extension in_port_t {
    var bigEndian: in_port_t {
        return (self << 8) | (self >> 8)
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/ArchiveBrowser.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='25472e0eb5da384cda6b5823dc851c8471e002c9223e1949937055b9e98608bb', 'pinned source changed: rebase and review, never bless silently'
for token in ['ArchiveConfig', 'Sheet', 'cacheFileName', 'ArchiveTitle', 'ArchiveOrgItem', 'archiveOrgDisplayName', 'ArchiveFile', 'ArchiveFavorite', 'ArchiveDeletedEntry', 'ArchiveUserLists', 'Stored', 'save']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='25472e0eb5da384cda6b5823dc851c8471e002c9223e1949937055b9e98608bb'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-02: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-02: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
