# W-gdb-199e-1nstinct-21 - Parse CRLF archive CSV records
state: OPEN / unclaimed
lab: 1nstinct

Fix parseCSV record splitting for CRLF, which Swift represents as one Character. Preserve CR-only/LF-only records, quoted embedded newlines, escaped quotes and existing return shape. Do not change archive network/cache behavior.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199e-1nstinct-21",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorSources/ArchiveLibrary.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Fix parseCSV record splitting for CRLF, which Swift represents as one Character. Preserve CR-only/LF-only records, quoted embedded newlines, escaped quotes and existing return shape. Do not change archive network/cache behavior.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Existing shipping helper callers; no new feature/parity claim.",
    "callee": "archive/gor/Sources/gor/GorSources/ArchiveLibrary.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-21.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199e-1nstinct-21",
    "paths": [
      "archive/gor/Sources/gor/GorSources/ArchiveLibrary.swift",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-21.py",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-21.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-21.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorSources/ArchiveLibrary.swift",
        "block": "source1",
        "sha256": "772942f9057fe2486eac455c145f544e7101238dc52e1693e0aee32cf5a6f1a3",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-21.py",
        "block": "fixtures1",
        "sha256": "730c373aa4798b02ab0eb98bf6629f9a0d5bcf336784e31bc3fb39c669adc5f6"
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-21.json",
        "block": "fixtures2",
        "sha256": "896ca67b75f772c697d5f1f6ded5c0f519b9998f90f1b24eea748b8ee5d300be"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "93fb72deff7e693e83dfd35328d20f4b27919ece9381793640046cfe468dee0e",
    "last_5_lines": [
      "semantic_exit=1",
      "FAIL CRLF records separated",
      "PASS LF retained",
      "PASS CR retained",
      ""
    ],
    "receipt_sha256": "27d0f991ea06983649e5d77e06184bd70bb1406b97935b66d760e3fdb1d9f717"
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
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(ROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n');inputs=[str(source)]
 else:
  inputs=[str(ROOT/cfg['source'])]+[str(ROOT/p) for p in cfg['deps']]
  if cfg['support']:
   source=td/'Support.swift';source.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(source))
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith('ArchiveLibrary.swift') else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith('ArchiveLibrary.swift'):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/GorSources/ArchiveLibrary.swift",
  "markers": [
    "private func parseCSV("
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\ncheck(parseCSV(\"title,url\\r\\nmovie,https://example.invalid/a\\r\\n\") == [[\"title\",\"url\"],[\"movie\",\"https://example.invalid/a\"]],\"CRLF records separated\")\ncheck(parseCSV(\"a,b\\nc,d\\n\") == [[\"a\",\"b\"],[\"c\",\"d\"]],\"LF retained\")\ncheck(parseCSV(\"a,b\\rc,d\\r\") == [[\"a\",\"b\"],[\"c\",\"d\"]],\"CR retained\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL CRLF records separated
PASS LF retained
PASS CR retained


```

Publication caveat: NONQUALIFIED: exact-source declaration extraction, not native/full module acceptance. HeatTelemetry in A27 is an explicit test support value, not production telemetry evidence. Own compiler rerun NOT_RUN.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
