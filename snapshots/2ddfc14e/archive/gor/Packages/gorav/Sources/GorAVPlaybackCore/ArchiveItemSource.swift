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
