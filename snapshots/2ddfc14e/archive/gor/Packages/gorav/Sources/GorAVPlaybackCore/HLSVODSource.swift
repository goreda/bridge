// Original-engine HLS fetch preparation, finite unencrypted VOD subset.
// Parser/variant policy comes from the actual product LabHLSPlaylist.
// Live timeline, ABR switches, byte ranges and encrypted HLS stay typed gaps.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum HLSVODSourceError: Error, Equatable {
    case badURL, invalidText, unsupportedFeature, emptyPlaylist
    case responseTooLarge, totalTooLarge, httpStatus(Int), unsafeRedirect
}
public struct HLSPreparedSegment {
    public let sequence: Int
    public let duration: Double
    public let discontinuity: Bool
    public let fileURL: URL
}
public enum HLSVODSource {
    public static func admitted(_ url: URL, relativeTo parent: URL? = nil) throws -> URL {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil, url.user == nil, url.password == nil,
              !(parent?.scheme?.lowercased() == "https" && scheme == "http") else {
            throw HLSVODSourceError.badURL
        }
        return url
    }
    static func reference(_ text: String, base: URL) throws -> URL {
        guard let value = URL(string: text, relativeTo: base)?.absoluteURL else { throw HLSVODSourceError.badURL }
        return try admitted(value, relativeTo: base)
    }
    /// Fetch chosen variant and media bytes into caller-owned private cache.
    /// Caller removes returned files after all decoder handles close.
    /// No cookie/header forwarding is implemented by this public-source seam.
    public static func prepare(url: URL, bandwidthBps: Double, directory: URL,
                               maxHeight: Int? = nil, probedHeights: [String: Int]? = nil,
                               maxTotalBytes: Int = 64 * 1024 * 1024) async throws -> [HLSPreparedSegment] {
        guard bandwidthBps.isFinite, bandwidthBps > 0, directory.isFileURL, maxTotalBytes > 0 else {
            throw HLSVODSourceError.badURL
        }
        func text(_ data: Data) throws -> String {
            guard let result = String(data: data, encoding: .utf8) else { throw HLSVODSourceError.invalidText }
            return result
        }
        let first = try await HLSResourceFetch.load(url: admitted(url), cap: 1024 * 1024)
        var body = try text(first.0), mediaURL = first.1
        let variants = try LabHLSPlaylist.parseMaster(body)
        if !variants.isEmpty {
            // When a height cap is requested, declared resolution alone is not
            // evidence. Require real probe results for every chosen candidate.
            if maxHeight != nil && probedHeights == nil { throw HLSVODSourceError.unsupportedFeature }
            let candidateVariants = variants.filter { maxHeight == nil || (probedHeights?[$0.uri] ?? 0) > 0 }
            let choice = try LabHLSPlaylist.chooseVariant(candidateVariants, bandwidthBps: bandwidthBps,
                    maxHeight: maxHeight, probedHeights: probedHeights)
            let response = try await HLSResourceFetch.load(url: reference(choice.uri, base: mediaURL), cap: 1024 * 1024)
            body = try text(response.0); mediaURL = response.1
        }
        let media = try LabHLSPlaylist.parseMedia(body)
        guard media.ended else { throw HLSVODSourceError.unsupportedFeature }
        guard !media.segments.isEmpty, media.mediaSeq >= 0 else { throw HLSVODSourceError.emptyPlaylist }
        var initReference: String?
        for raw in body.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXT-X-KEY:") {
                guard LabHLSPlaylist.parseAttrs(String(line.dropFirst(11)))["METHOD"] == "NONE" else { throw HLSVODSourceError.unsupportedFeature }
            }
            if line.hasPrefix("#EXT-X-BYTERANGE:") { throw HLSVODSourceError.unsupportedFeature }
            if line.hasPrefix("#EXT-X-MAP:") {
                let attrs = LabHLSPlaylist.parseAttrs(String(line.dropFirst(11)))
                guard initReference == nil, let uri = attrs["URI"], attrs["BYTERANGE"] == nil else { throw HLSVODSourceError.unsupportedFeature }
                initReference = uri
            }
        }
        var initial = Data(), total = 0, created: [URL] = [], complete = false
        defer { if !complete { for file in created { try? FileManager.default.removeItem(at: file) } } }
        if let name = initReference { initial = try await HLSResourceFetch.load(url: reference(name, base: mediaURL), cap: min(maxTotalBytes, 4 * 1024 * 1024)).0 }
        var result: [HLSPreparedSegment] = []
        for segment in media.segments {
            try Task.checkCancellation()
            let bytes = try await HLSResourceFetch.load(url: reference(segment.uri, base: mediaURL), cap: min(maxTotalBytes, 16 * 1024 * 1024)).0
            guard initial.count <= maxTotalBytes - total, bytes.count <= maxTotalBytes - total - initial.count else { throw HLSVODSourceError.totalTooLarge }
            var joined = initial; joined.append(bytes); total += joined.count
            let destination = directory.appendingPathComponent("hls-" + UUID().uuidString + ".mp4")
            try joined.write(to: destination, options: .atomic); created.append(destination)
            result.append(HLSPreparedSegment(sequence: segment.seq, duration: segment.duration, discontinuity: segment.discontinuity, fileURL: destination))
        }
        try Task.checkCancellation(); complete = true; return result
    }
}

private final class HLSResourceFetch: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let cap: Int
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var data = Data(), failure: Error?, finalURL: URL?, redirects = 0
    private let completion: (Result<(Data, URL), Error>) -> Void
    private init(cap: Int, completion: @escaping (Result<(Data, URL), Error>) -> Void) { self.cap = cap; self.completion = completion }
    private func cancel() { lock.lock(); let value = task; lock.unlock(); value?.cancel() }
    static func load(url: URL, cap: Int) async throws -> (Data, URL) {
        let holder = HLSFetchCancellation()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let op = HLSResourceFetch(cap: cap) { continuation.resume(with: $0) }
                let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 10; config.timeoutIntervalForResource = 20
                config.httpCookieStorage = nil; config.urlCache = nil
                let session = URLSession(configuration: config, delegate: op, delegateQueue: queue)
                op.session = session
                let task = session.dataTask(with: url)
                op.lock.lock(); op.task = task; op.lock.unlock()
                holder.install { op.cancel() }; task.resume()
            }
        }, onCancel: { holder.cancel() })
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= 8, let target = request.url, (try? HLSVODSource.admitted(target, relativeTo: response.url)) != nil else {
            failure = HLSVODSourceError.unsafeRedirect; completionHandler(nil); return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            failure = failure ?? HLSVODSourceError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? 0); completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= Int64(cap), let url = response.url else {
            failure = HLSVODSourceError.responseTooLarge; completionHandler(.cancel); return
        }
        finalURL = url; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard failure == nil else { return }
        guard chunk.count <= cap - data.count else { failure = HLSVODSourceError.responseTooLarge; dataTask.cancel(); return }
        data.append(chunk)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = failure ?? error { completion(.failure(error)) }
        else if let url = finalURL { completion(.success((data, url))) }
        else { completion(.failure(HLSVODSourceError.badURL)) }
        lock.lock(); self.task = nil; lock.unlock()
        self.session = nil; data.removeAll(); session.finishTasksAndInvalidate()
    }
}
private final class HLSFetchCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var action: (() -> Void)?
    func install(_ action: @escaping () -> Void) { lock.lock(); self.action = action; let value = cancelled; lock.unlock(); if value { action() } }
    func cancel() { lock.lock(); cancelled = true; let value = action; lock.unlock(); value?() }
}
