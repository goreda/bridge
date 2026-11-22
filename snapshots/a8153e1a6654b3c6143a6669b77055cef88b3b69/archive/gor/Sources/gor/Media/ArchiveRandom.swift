// Native port of middots/random.js (636a63f), archive selection route.
// Fresh local crypto on every draw; optional remote entropy never blocks UI.
// SHA-512/XOR pools enrich, not replace, local entropy. Rejection sampling
// removes modulo bias. Public beacon provenance is not proof of fairness.
import Foundation
import Security
import CryptoKit

final class ArchiveRandom {
    static let shared = ArchiveRandom()
    private let queue = DispatchQueue(label: "gor.archive.random.entropy")
    private let lock = NSLock()
    private var seed = Data(), reservoir = Data(), cursor = 0, counter: UInt64 = 0
    private var lastTiming: Double?, timing: [Double] = []
    private var anu: Data?, nist: Data?
    private var refreshing = false
    private init() { queue.async { self.reseed(); self.refresh() } }
    private func local(_ count: Int) -> Data? {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { ptr in SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!) }
        return status == errSecSuccess ? data : nil
    }
    private func hash(_ data: Data) -> Data { Data(SHA512.hash(data: data)) }
    private func expand(_ value: Data, domain: String, block: UInt64) -> Data {
        hash(value + Data("middots/random/v1:\(domain.count):\(domain):\(block)".utf8))
    }
    private func fillLocked() {
        reservoir = Data(reservoir.dropFirst(cursor)); cursor = 0
        for _ in 0..<8 { reservoir.append(expand(seed, domain: "shared", block: counter)); counter &+= 1 }
    }
    private func reseed() {
        lock.lock(); defer { lock.unlock() }
        let humanValue: Data? = timing.isEmpty ? local(8) : Data(hash(Data(timing.map { String($0) }.joined(separator: ":").utf8)).prefix(8))
        guard let fresh = local(8), let a = anu ?? local(8), let b = nist ?? local(8), let human = humanValue else { return }
        var merged = fresh
        for i in 0..<8 { merged[i] ^= a[i] ^ b[i] ^ human[i] }
        timing.removeAll(); seed = hash(merged + seed); counter = 0; reservoir = Data(); cursor = 0; fillLocked()
    }
    func addTiming(_ now: Double) {
        guard now.isFinite else { return }; lock.lock()
        if let last = lastTiming, now > last { timing.append(now-last); if timing.count > 32 { timing.removeFirst() } }
        lastTiming = now; lock.unlock(); queue.async { self.reseed() }
    }
    private func word() -> UInt32? {
        guard var bytes = local(4) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if cursor+4 <= reservoir.count { for i in 0..<4 { bytes[i] ^= reservoir[cursor]; cursor += 1 } }
        if reservoir.count-cursor < 64 && !seed.isEmpty { fillLocked() }
        return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    private var bags: [String: (order: [Int], cursor: Int)] = [:]
    func chooseIndex(count: Int) -> Int? {
        guard count > 0, UInt64(count) <= 4_294_967_296 else { return nil }
        let width = UInt64(count), limit = 4_294_967_296 / width * width
        while let value = word() { if UInt64(value) < limit { return Int(UInt64(value) % width) } }
        return nil // entropy failure never silently falls back to biased/non-crypto RNG
    }
    /// Session shuffle bag (owner order 2026-11-15): panel random buttons draw
    /// without replacement from a per-session bag, so a repeat can only happen
    /// after every choice appeared once. chooseIndex stays the single uniform
    /// source for the Fisher-Yates shuffle; a new bag's first draw never equals
    /// the previous bag's last draw when count > 1, so even the bag boundary
    /// cannot repeat. count changes (library edited) rebuild the bag.
    func drawIndex(count: Int, session: String) -> Int? {
        guard count > 0, UInt64(count) <= 4_294_967_296 else { return nil }
        lock.lock()
        let bag = bags[session] ?? (order: [Int](), cursor: 0)
        lock.unlock()
        if bag.order.count == count, bag.cursor < bag.order.count {
            let index = bag.order[bag.cursor]
            lock.lock(); bags[session] = (order: bag.order, cursor: bag.cursor + 1); lock.unlock()
            return index
        }
        var order = Array(0..<count)
        for i in stride(from: count - 1, through: 1, by: -1) {
            guard let j = chooseIndex(count: i + 1) else { return nil }
            order.swapAt(i, j)
        }
        if count > 1, let last = bag.order.last, order.first == last { order.swapAt(0, 1) }
        lock.lock(); bags[session] = (order: order, cursor: 1); lock.unlock()
        return order[0]
    }
    private func refresh() {
        guard !refreshing else { return }; refreshing = true
        let group = DispatchGroup()
        for (kind, raw) in [("anu", "https://qrng.anu.edu.au/API/jsonI.php?length=8&type=uint8&size=1"),
                            ("nist", "https://beacon.nist.gov/beacon/2.0/pulse/last")] {
            group.enter(); var request = URLRequest(url: URL(string: raw)!, timeoutInterval: 4)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            EntropyFetch.run(request) { data, response, _ in
                defer { group.leave() }
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let data, data.count < 100_000, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                var bytes: Data?
                if kind == "anu", json["success"] as? Bool == true, let values = json["data"] as? [Int], values.count == 8,
                   values.allSatisfy({ (0...255).contains($0) }) { bytes = Data(values.map(UInt8.init)) }
                if kind == "nist", let pulse = json["pulse"] as? [String: Any], pulse["statusCode"] as? Int == 0,
                   let output = pulse["outputValue"] as? String, output.count == 128,
                   output.allSatisfy({ $0.isHexDigit }), let timestamp = pulse["timeStamp"] as? String,
                   let date = Self.date(timestamp), Date().timeIntervalSince(date) <= 300, date.timeIntervalSinceNow <= 60,
                   pulse["chainIndex"] as? Int != nil, pulse["pulseIndex"] as? Int != nil {
                    let prefix = Array(output.prefix(16)); var result = Data()
                    for i in stride(from: 0, to: 16, by: 2) { if let byte = UInt8(String(prefix[i...i+1]), radix: 16) { result.append(byte) } }
                    if result.count == 8 { bytes = result }
                }
                self.lock.lock(); if kind == "anu" { self.anu = bytes } else { self.nist = bytes }; self.lock.unlock()
            }
        }
        group.notify(queue: queue) { self.refreshing = false; self.reseed() }
    }
    private final class EntropyFetch: NSObject, URLSessionDataDelegate {
        private var session: URLSession?, task: URLSessionDataTask?, deadline: DispatchWorkItem?
        private var bytes = Data(), response: URLResponse?
        private let callback: (Data?, URLResponse?, Error?) -> Void
        private let gate = NSLock(); private var finished = false
        private init(_ callback: @escaping (Data?, URLResponse?, Error?) -> Void) { self.callback = callback }
        static func run(_ request: URLRequest, callback: @escaping (Data?, URLResponse?, Error?) -> Void) {
            let fetch = EntropyFetch(callback); fetch.start(request)
        }
        private func start(_ request: URLRequest) {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 4; config.timeoutIntervalForResource = 4
            session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            task = session?.dataTask(with: request)
            let work = DispatchWorkItem { [weak self] in
                self?.finish(data: nil, error: NSError(domain: "ArchiveRandom", code: 1, userInfo: [NSLocalizedDescriptionKey: "entropy source deadline"]))
            }
            deadline = work; DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now()+4, execute: work); task?.resume()
        }
        private func finish(data: Data?, error: Error?) {
            gate.lock(); guard !finished else { gate.unlock(); return }; finished = true
            let response = self.response; let owned = session; session = nil; gate.unlock()
            deadline?.cancel(); task?.cancel(); callback(data, response, error); owned?.invalidateAndCancel()
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            gate.lock(); self.response = response; let done = finished; gate.unlock()
            guard !done, response.expectedContentLength <= 100_000 else { completionHandler(.cancel); return }
            completionHandler(.allow)
        }
        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            gate.lock(); let allowed = !finished && data.count <= 100_000-bytes.count
            if allowed { bytes.append(data) }; gate.unlock()
            if !allowed { finish(data: nil, error: NSError(domain: "ArchiveRandom", code: 2)) }
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            gate.lock(); let data = bytes; gate.unlock(); finish(data: error == nil ? data : nil, error: error)
        }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil) // endpoint identity is fixed, no third-party redirect enrichment
        }
    }
    private static func date(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}
