# W-gdb-198y-1nstinct-23
state: OPEN / unclaimed
lab: 1nstinct

Build a new independent scope-aware source/move characterization test for this exact file. Parse lexical nominal ownership including nesting, ignore comments/strings, and compare fully qualified declaration owners across the entire pinned Sources tree. Do not confuse nested names in unrelated owners with duplicates. Preserve pinned bytes. Check old and mapped station, renamed copies, valid overload/nested-name controls, and real duplicate mutants. Use explicit failure paths that remain active under python3 -O. Run normal and optimized positive plus on-disk external negative/restore controls. The existing 01..20 returns are evidence only and may not be copied unchanged.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-23.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-23",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/ArchiveLibrary.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-23.py checks archive/gor/Sources/gor/ArchiveLibrary.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: parseCSV, extractLinks, archiveOrgProfileTitle, ArchiveLibrary, loadCacheFromDisk, writeCacheToDisk, fetchCSV, fetchConcurrently, fetchAllFromNetwork, load, refreshInBackground, reload",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-23.py",
    "callee": "archive/gor/Sources/gor/ArchiveLibrary.swift owning station GorSources"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-23.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-23.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-23.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:15.827028+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/ArchiveLibrary.swift",
        "block": "source1",
        "sha256": "772942f9057fe2486eac455c145f544e7101238dc52e1693e0aee32cf5a6f1a3"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-23.py",
        "block": "fixtures1",
        "sha256": "27be27f8f0ed9b1c867562122670df5276755246cb57da9df5d1a7e44f18dd3d"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "408968e94d4a3b1c1517c3b6a5b0969af1c5346233f5f6359db5aa1c72d09580",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-23: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "6dfb6ccccaa261fd19d16b805310d5612385349c8d4ad613394c9fbe55d1af31"
  }
}
```

```swift id=source1
// ================================================================
//  ArchiveLibrary.swift - Google Sheets archive library (singleton)
//  Owns: titles, disk cache, sheet fetch/parse, link extraction
//  Contract: load() serves disk cache instantly then refreshes silently;
//  onLoaded fires once titles are usable, onUpdated only on real change
// ================================================================
import AppKit
import Foundation

private func parseCSV(_ raw: String) -> [[String]] {
    var rows: [[String]] = []
    var currentRow: [String] = []
    var currentField = ""
    var inQuotes = false
    var i = raw.startIndex

    while i < raw.endIndex {
        let char = raw[i]

        if inQuotes {
            // inside quotes: everything goes into the field
            if char == "\"" {
                let next = raw.index(after: i)
                if next < raw.endIndex && raw[next] == "\"" {
                    currentField.append("\"")
                    i = raw.index(after: next)
                    continue
                }
                inQuotes = false
            } else {
                currentField.append(char)
            }
        } else {
            switch char {
            case "\"":
                inQuotes = true
            case ",":
                currentRow.append(currentField)
                currentField = ""
            case "\r":
                // CR ends the row (outside quotes); skip a following LF
                currentRow.append(currentField)
                currentField = ""
                rows.append(currentRow)
                currentRow = []
                let next = raw.index(after: i)
                if next < raw.endIndex && raw[next] == "\n" {
                    i = next
                }
            case "\n":
                currentRow.append(currentField)
                currentField = ""
                rows.append(currentRow)
                currentRow = []
            default:
                currentField.append(char)
            }
        }
        i = raw.index(after: i)
    }

    if !currentField.isEmpty || !currentRow.isEmpty {
        currentRow.append(currentField)
        rows.append(currentRow)
    }

    if let last = rows.last, last.count == 1, last[0].isEmpty {
        rows.removeLast()
    }

    return rows
}

private func extractLinks(_ s: String) -> [String] {
    // archive.org: only /details/@user (profile) and /download/<id> (item
    // directory) are meaningful sources — the bare domain isn't, so it's
    // matched with its path prefix baked in rather than as an alternative
    // host on its own.
    guard let regex = try? NSRegularExpression(pattern: #"https://(transfer\.it|mega\.nz|gofile\.io|drive\.google\.com|pixeldrain\.com)/[^\s,;"'<>]+|https://archive\.org/(details/@|download/)[^\s,;"'<>]+"#) else {
        return []
    }
    let ns = s as NSString
    return regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        .map { ns.substring(with: $0.range) }
}

// A single-column sheet row has no separate title cell — an archive.org
// profile link carries a readable handle in its own URL, so pull it out
// instead of falling back to the generic "Unnamed" placeholder.
// WHY: profile / list / lists links all contain "archive.org/details/@";
// the suffix (" · profile", " · list", " · lists") keeps the three kinds
// distinct on screen. WHY: lowercase matches archive.org's fetched display
// names. Contract: placeholder only — ArchiveBrowserPanel.sheetRowTitle
// prefers ArchiveOrgCatalogue's fetched real name once known (see
// sheetRowTitle()); this runs before any archive.org network call.
private func archiveOrgProfileTitle(from link: String) -> String? {
    guard let range = link.range(of: "archive.org/details/@") else { return nil }
    let afterAt = link[range.upperBound...]
    let segments = afterAt.components(separatedBy: "/")
    guard let rawUsername = segments.first, !rawUsername.isEmpty else { return nil }
    let username = rawUsername
        .components(separatedBy: "?").first ?? rawUsername
    let readableUsername = username.replacingOccurrences(of: "_", with: " ").lowercased()
    guard !readableUsername.isEmpty else { return nil }

    // segments[1] == "lists": a specific list (numeric segments[2]) or the
    // id-less "all lists" form. Anything else is the plain profile link.
    guard segments.count >= 2, segments[1] == "lists" else {
        return "\(readableUsername) · profile"
    }
    let hasNumericID = segments.count >= 3 && Int(segments[2]) != nil
    if hasNumericID {
        return "\(readableUsername) · list"
    } else {
        return "\(readableUsername) · lists"
    }
}

// ================================================================
//  ArchiveLibrary
// ================================================================

final class ArchiveLibrary {
    static let shared = ArchiveLibrary()
    private init() {}

    private(set) var titles: [ArchiveTitle] = []
    private(set) var isLoaded = false
    /// Fired the first time `titles` is usable on screen (disk cache or
    /// first network fetch). ArchiveBrowserPanel's initial showLibrary() hangs off this.
    var onLoaded: (() -> Void)?
    /// Fired when a background refresh finds the library actually changed;
    /// payload is the already-updated `titles`. Never fires on a no-change refresh.
    var onUpdated: (() -> Void)?

    // GUARD-RAIL: a second load() during an in-flight fetch must queue its
    // callback, not start a duplicate network pass.
    private var isFetching = false
    private var pendingCallbacks: [() -> Void] = []
    // sheets in flight - each fetch is an I/O-bound curl Process, safe past
    // core count (12 tuned for ~25 sheets across 2 sources)
    private let maxConcurrentFetches = 12

    // MARK: - Disk cache

    // First completed network fetch writes a disk snapshot. Every later
    // load() reads disk first: cache present -> titles + onLoaded
    // immediately, then a silent background refresh. Changed data updates
    // titles, writes a new snapshot and fires onUpdated; unchanged fires nothing.
    private static var cacheURL: URL? = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appDir = dir.appendingPathComponent("gor", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        // Snapshots written before the source list changed (archive_cache.json and other hashes) are removed: no stale rows.
        let name = ArchiveConfig.cacheFileName(for: ArchiveConfig.spreadsheetSources)
        if let old = try? FileManager.default.contentsOfDirectory(atPath: appDir.path) {
            for f in old where f.hasPrefix("archive_cache") && f.hasSuffix(".json") && f != name {
                try? FileManager.default.removeItem(at: appDir.appendingPathComponent(f))
            }
        }
        return appDir.appendingPathComponent(name)
    }()

    private func loadCacheFromDisk() -> [ArchiveTitle]? {
        guard let url = Self.cacheURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ArchiveTitle].self, from: data) else {
            return nil
        }
        return decoded
    }

    private static let cacheWriteQueue = DispatchQueue(label: "archive.library.cache-write", qos: .utility)

    /// Callers dispatch off the main thread around this.
    private func writeCacheToDisk(_ titles: [ArchiveTitle]) {
        guard let url = Self.cacheURL,
              let data = try? JSONEncoder().encode(titles) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fetchCSV(_ url: String) throws -> [[String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-fsSL", "--max-time", "20", url]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        // WHY: read stdout to EOF before waitUntilExit; waiting first deadlocks the pipe.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let csv = String(data: data, encoding: .utf8) else {
            throw ArchiveError.csvFetchFailed(url)
        }

        return parseCSV(csv)
    }

    /// Fetches `items` with up to `maxConcurrentFetches` in flight.
    /// Blocks the calling thread until every item completes; call off the main thread.
    private func fetchConcurrently<T>(
        _ items: [T],
        resultQueue: DispatchQueue,
        fetch: @escaping (T) -> Void
    ) {
        let semaphore = DispatchSemaphore(value: maxConcurrentFetches)
        let group = DispatchGroup()
        for item in items {
            semaphore.wait()
            group.enter()
            resultQueue.async {
                fetch(item)
                semaphore.signal()
                group.leave()
            }
        }
        group.wait()
    }

    /// Every sheet from every source, fetched concurrently, merged into one
    /// array. Pure network function: touches no `titles`/`isLoaded`/disk
    /// state, so both the first-load and silent-refresh paths reuse it.
    private func fetchAllFromNetwork() -> [ArchiveTitle]? {
        var result: [ArchiveTitle] = []
        var fetchFailed = false
        let sources = ArchiveConfig.spreadsheetSources
        let fetchQueue = DispatchQueue(label: "archive.library.fetch", attributes: .concurrent)
        let mergeQueue = DispatchQueue(label: "archive.library.merge")

        // WHY: sheet lists resolve concurrently too; no assumption sources stay few.
        var sheetJobs: [(source: (id: String, gid: String, label: String), name: String)] = []
        let indexGroup = DispatchGroup()
        let indexQueue = DispatchQueue(label: "archive.library.index")
        for source in sources {
            indexGroup.enter()
            fetchQueue.async {
                defer { indexGroup.leave() }
                let indexURL = "https://docs.google.com/spreadsheets/d/\(source.id)/export?format=csv&gid=\(source.gid)"
                guard let indexRows = try? self.fetchCSV(indexURL) else {
                    indexQueue.sync { fetchFailed = true }
                    print("❌ \(source.label): could not read sheet list")
                    return
                }
                // The index column can arrive in two shapes: one sheet name
                // per row, OR a single quoted cell holding the whole
                // newline-joined list (Google's CSV export quotes any cell
                // containing newlines, so a multi-line cell survives parseCSV
                // as one field with embedded \r\n). Splitting on newlines
                // covers both; .whitespaces alone never stripped \r anyway.
                let sheetNames = indexRows.compactMap { $0.first }
                    .flatMap { $0.components(separatedBy: .newlines) }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if sheetNames.isEmpty { indexQueue.sync { fetchFailed = true } }
                print("[archive] \(source.label) sheet list: \(sheetNames)")
                indexQueue.sync {
                    sheetJobs.append(contentsOf: sheetNames.map { (source, $0) })
                }
            }
        }
        indexGroup.wait()

        fetchConcurrently(sheetJobs, resultQueue: fetchQueue) { job in
            let (source, name) = job
            var sheetQuery = CharacterSet.urlQueryAllowed
            sheetQuery.remove(charactersIn: "&+=")
            let encodedName = name.addingPercentEncoding(withAllowedCharacters: sheetQuery) ?? name
            let sheetURL = "https://docs.google.com/spreadsheets/d/\(source.id)/gviz/tq?tqx=out:csv&sheet=\(encodedName)"
            guard let rows = try? self.fetchCSV(sheetURL) else {
                indexQueue.sync { fetchFailed = true }
                print("❌ \(source.label)/\(name) could not be read")
                return
            }
            // Empty label (no prefix wanted for this source) shouldn't leave
            // a stray leading space in the section name.
            let displayName = source.label.isEmpty ? name : "\(source.label) \(name)"
            print("[archive] '\(displayName)': \(rows.count) rows")

            var sheetTitles: [ArchiveTitle] = []
            var seen = Set<String>()
            for row in rows {
                if row.count == 1, let link = row.first, !link.isEmpty {
                    let links = extractLinks(link)
                    if !links.isEmpty {
                        // A single-column row has no title cell, so this is
                        // normally "Unnamed" — except an archive.org profile
                        // link carries its own @username in the URL.
                        let rowTitle = archiveOrgProfileTitle(from: links.first ?? "") ?? "Unnamed"
                        let key = "\(rowTitle)|\(displayName)|\(links.first ?? "")"
                        if seen.insert(key).inserted {
                            sheetTitles.append(ArchiveTitle(title: rowTitle, section: displayName, links: links))
                        }
                    }
                    continue
                }
                guard row.count > 2 else { continue }

                let year  = row[0].trimmingCharacters(in: .whitespaces)
                let title = row[1].trimmingCharacters(in: .whitespaces)
                let cell  = row[2].trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty, !cell.isEmpty else { continue }

                let links = extractLinks(cell)
                guard !links.isEmpty else { print("⚠️ no links from cell: \(cell)"); continue }

                let fullTitle = year.isEmpty ? title : "\(title) (\(year))"
                // dedupe key: title + section + first link
                let key = "\(fullTitle)|\(displayName)|\(links.first ?? "")"
                guard seen.insert(key).inserted else { continue }

                sheetTitles.append(ArchiveTitle(title: fullTitle, section: displayName, links: links))
            }

            mergeQueue.sync {
                result.append(contentsOf: sheetTitles)
            }
        }

        for manual in ArchiveConfig.manualLinks {
            result.append(ArchiveTitle(title: manual.title, section: "manual", links: manual.links))
        }
        return fetchFailed ? nil : result
    }

    /// Entry point. Titles already in memory -> fire onLoaded. A fetch in
    /// flight -> queue the callback. Otherwise: disk cache shows instantly
    /// and a silent refresh follows; no cache (first run) blocks on the
    /// network fetch before onLoaded.
    func load() {
        if isLoaded {
            onLoaded?()
            return
        }
        if isFetching {
            if let onLoaded { pendingCallbacks.append(onLoaded) }
            return
        }

        if let cached = loadCacheFromDisk(), !cached.isEmpty {
            titles = cached
            isLoaded = true
            print("[archive] loaded instantly from cache: \(cached.count) titles")
            onLoaded?()
            // Cache already on screen — refresh in the background without
            // blocking or touching onLoaded again; onUpdated covers it if
            // anything actually changed.
            refreshInBackground()
            return
        }

        // No cache yet — first run: onLoaded fires only once real data exists.
        isFetching = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.fetchAllFromNetwork()
            if let result, !result.isEmpty { self.writeCacheToDisk(result) }
            DispatchQueue.main.async {
                if let result, !result.isEmpty { self.titles = result; self.isLoaded = true }
                self.isFetching = false
                print("[archive] Total: \(self.titles.count) titles")
                guard self.isLoaded else {
                    print("[archive] initial fetch failed; retry available on next load")
                    return
                }
                let callbacks = [self.onLoaded].compactMap { $0 } + self.pendingCallbacks
                self.pendingCallbacks = []
                callbacks.forEach { $0() }
            }
        }
    }

    /// Silent background refresh: re-fetches without touching what's on
    /// screen and without a loading state. Used automatically after a cached
    /// load() and by the refresh button (ArchiveBrowserPanel.refreshLibrary()).
    func refreshInBackground() {
        guard !isFetching else { return }  // a fetch (initial or silent) is already running
        isFetching = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let result = self.fetchAllFromNetwork()
            DispatchQueue.main.async {
                self.isFetching = false
                guard let result, !result.isEmpty else {
                    print("[archive] refresh failed; keeping current cache")
                    let callbacks = self.pendingCallbacks
                    self.pendingCallbacks = []
                    callbacks.forEach { $0() }
                    return
                }
                // WHY: sheet completion order varies run to run, so merge
                // order isn't stable — compare as sets or a pure reordering
                // triggers a pointless redraw and cache write every refresh.
                let changed = Set(result) != Set(self.titles)
                if changed {
                    self.titles = result
                    print("[archive] background refresh: \(result.count) titles (changed)")
                    self.onUpdated?()
                    // titles/onUpdated already reflect the new data; the
                    // disk write can happen off the main thread.
                    // Serial queue: two quick refreshes must land on disk in enqueue order.
                    Self.cacheWriteQueue.async {
                        self.writeCacheToDisk(result)
                    }
                } else {
                    print("[archive] background refresh: no changes")
                }
                let callbacks = self.pendingCallbacks
                self.pendingCallbacks = []
                callbacks.forEach { $0() }
            }
        }
    }

    /// Alias for refreshInBackground(): same never-blank, never-blocking
    /// contract, wired to the refresh button.
    func reload() {
        refreshInBackground()
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/ArchiveLibrary.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='772942f9057fe2486eac455c145f544e7101238dc52e1693e0aee32cf5a6f1a3', 'pinned source changed: rebase and review, never bless silently'
for token in ['parseCSV', 'extractLinks', 'archiveOrgProfileTitle', 'ArchiveLibrary', 'loadCacheFromDisk', 'writeCacheToDisk', 'fetchCSV', 'fetchConcurrently', 'fetchAllFromNetwork', 'load', 'refreshInBackground', 'reload']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='772942f9057fe2486eac455c145f544e7101238dc52e1693e0aee32cf5a6f1a3'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-23: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-23: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
