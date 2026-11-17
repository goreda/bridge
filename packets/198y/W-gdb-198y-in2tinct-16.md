# W-gdb-198y-in2tinct-16
state: OPEN / unclaimed
lab: in2tinct

Extend source-contract characterization for Sources/GorAVPlaybackCore/ArchiveItemSource.swift in shipping-path engine station GorAVPlaybackCore. Add at least two named assertions on the shown production declarations and one removed/renamed-declaration mutant. Do not implement a parallel engine or claim runtime playback.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-16.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean isolated source-only materialization of the exact Git blob plus complete inline test; not a full package checkout/build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-16",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/ArchiveItemSource.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads Sources/GorAVPlaybackCore/ArchiveItemSource.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: ArchiveItemSourceError, ArchiveItemSource, identifier, fileComponents, downloadURL, set, ArchiveMetadataFetch, start, cancel, urlSession, urlSession, urlSession",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-16.py",
    "callee": "Sources/GorAVPlaybackCore/ArchiveItemSource.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-16.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-16.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-16.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:13:38.913269+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/ArchiveItemSource.swift",
        "block": "source1",
        "sha256": "b3ceab524aed7067e6744c6885cf14f343cf52b09300bb87e6a676ae4c5781bd"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-16.py",
        "block": "fixtures1",
        "sha256": "2ca834efc19eb8ea24b3556ba15f93d559c462e14fcb540f1d2d1bdcb7825043"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "da00fd3e0e3ef03f5d2977a34f52cf06f883af64346355477ce2287e27b95281",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-16: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "379a9835c4895d5c30d70bdbfd9637ef73d165490c2b6fca1804c3cf8d4c4685"
  }
}
```

```swift id=source1
// Proposed original-engine P4 source adapter. No player/ffmpeg wrapper.
// Metadata contract: archive.org/developers/md-read.html and md-record.html.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ArchiveItemSourceError: Error, Equatable {
    case invalidIdentifier, invalidFilename, badMetadata, unavailable
    case missingFile, duplicateFile, privateFile, responseTooLarge, httpStatus(Int)
}

public enum ArchiveItemSource {
    public static let maxMetadataBytes = 8 * 1024 * 1024
    public static func identifier(_ id: String) throws -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard !id.isEmpty, id != ".", id != "..", id.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ArchiveItemSourceError.invalidIdentifier
        }
        return id
    }
    public static func fileComponents(_ filename: String) throws -> [String] {
        let parts = filename.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              !filename.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 92 }) else {
            throw ArchiveItemSourceError.invalidFilename
        }
        return parts
    }
    public static func downloadURL(metadata: Data, identifier id: String, filename: String,
                                   base: URL = URL(string: "https://archive.org")!) throws -> URL {
        _ = try identifier(id); let parts = try fileComponents(filename)
        guard metadata.count <= maxMetadataBytes else { throw ArchiveItemSourceError.responseTooLarge }
        guard let obj = (try? JSONSerialization.jsonObject(with: metadata)) as? [String: Any],
              let files = obj["files"] as? [[String: Any]] else { throw ArchiveItemSourceError.badMetadata }
        func set(_ v: Any?) -> Bool {
            if let b = v as? Bool { return b }
            if let s = v as? String { return s == "true" || s == "1" }
            return false
        }
        guard !set(obj["is_dark"]), !set(obj["nodownload"]) else { throw ArchiveItemSourceError.unavailable }
        let matches = files.filter { ($0["name"] as? String) == filename }
        guard !matches.isEmpty else { throw ArchiveItemSourceError.missingFile }
        guard matches.count == 1 else { throw ArchiveItemSourceError.duplicateFile }
        guard !set(matches[0]["private"]) else { throw ArchiveItemSourceError.privateFile }
        var url = base.appendingPathComponent("download").appendingPathComponent(id)
        for part in parts { url.appendPathComponent(part) }
        return url
    }
}

// Caller owns cancellation via the returned operation. Response collection is
// bounded before appending bytes, and completion fires once on a serial queue.
public final class ArchiveMetadataFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var data = Data()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let taskLock = NSLock()
    private var failure: Error?
    private let completion: (Result<Data, Error>) -> Void
    private let cap: Int
    private init(cap: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        self.cap = cap; self.completion = completion
    }
    @discardableResult
    public static func start(identifier: String, base: URL = URL(string: "https://archive.org")!,
                             timeout: TimeInterval = 25, cap: Int = ArchiveItemSource.maxMetadataBytes,
                             completion: @escaping (Result<Data, Error>) -> Void) throws -> ArchiveMetadataFetch {
        _ = try ArchiveItemSource.identifier(identifier)
        guard cap > 0, timeout.isFinite, timeout > 0 else { throw ArchiveItemSourceError.badMetadata }
        let op = ArchiveMetadataFetch(cap: cap, completion: completion)
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout; config.timeoutIntervalForResource = timeout
        config.httpCookieStorage = nil; config.urlCache = nil
        op.session = URLSession(configuration: config, delegate: op, delegateQueue: queue)
        var request = URLRequest(url: base.appendingPathComponent("metadata").appendingPathComponent(identifier))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let task = op.session!.dataTask(with: request)
        op.taskLock.lock(); op.task = task; op.taskLock.unlock()
        task.resume()
        return op
    }
    public func cancel() {
        taskLock.lock(); let current = task; taskLock.unlock()
        current?.cancel()
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            failure = ArchiveItemSourceError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            completionHandler(.cancel); return
        }
        if response.expectedContentLength > Int64(cap) {
            failure = ArchiveItemSourceError.responseTooLarge; completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard failure == nil else { return }
        guard chunk.count <= cap - data.count else {
            failure = ArchiveItemSourceError.responseTooLarge; dataTask.cancel(); return
        }
        data.append(chunk)
    }
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let e = failure ?? error { completion(.failure(e)) } else { completion(.success(data)) }
        data.removeAll()
        taskLock.lock(); self.task = nil; taskLock.unlock()
        self.session = nil
        session.finishTasksAndInvalidate()
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVPlaybackCore/ArchiveItemSource.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='b3ceab524aed7067e6744c6885cf14f343cf52b09300bb87e6a676ae4c5781bd', 'pinned source changed: rebase and review, never bless silently'
for token in ['ArchiveItemSourceError', 'ArchiveItemSource', 'identifier', 'fileComponents', 'downloadURL', 'set', 'ArchiveMetadataFetch', 'start', 'cancel', 'urlSession', 'urlSession', 'urlSession']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='b3ceab524aed7067e6744c6885cf14f343cf52b09300bb87e6a676ae4c5781bd'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-16: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-16: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
