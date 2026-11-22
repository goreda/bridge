#if canImport(AppKit) && canImport(CoreVideo)
import Foundation
import CoreVideo
import GorAVNativeProbeKit

// P27 (arch-195b) / arch-195g G3: REAL decoded-frame tap. This type
// supersedes the metadata-only DecodedFrameTap (GorAVPlaybackCore) in the
// product path: every accepted frame is an identity-tagged, RETAINED
// CVPixelBuffer with pts, not a bookkeeping record. The presented-frame
// readback role is served by MetalRenderer.readbackNative /
// MetalPresenter.readbackLast; together they cover the two P27 consumers
// (decoded-frame tap for crop detection / live depth / brightness reads /
// depth preparation, presented-frame readback for screenshot-to-file). The
// unwired BGRA CVPixelBufferReadback utility (GorAVMetalPresenter) is
// retired by this landing: the tap retains decoded buffers directly, so no
// GPU blit is needed to read decoded pixels.
//
// Identity: every frame carries (session, seekGeneration, pts, handle).
// The producer stamps the generation AT ADMISSION from the frame's own
// admitted origin (ShellSeekBridge fence revision), never from bridge
// state read after awaited work - an old frame can never be relabeled
// under a newer seek. Frames from a foreign session or a fenced (pre-seek)
// generation are REFUSED, typed and counted.
//
// Ownership: the tap retains each accepted buffer until the frame is
// consumed, evicted (bounded FIFO or byte budget), fenced out or the tap
// is closed. Byte accounting covers BOTH retain slots exactly: the queue
// (queuedBytes) and the newest/readback slot (newestBytes); a frame held
// in both is counted in both, so a consumed or evicted frame still held
// for readback is never unaccounted. Retained byte sizes are the ACTUAL
// CoreVideo plane strides x plane heights recorded at production, not a
// 1.5x-luma estimate.
//
// Threading: offers run on the producer's decode/source worker (never the
// render thread); the rate limiter defaults to ~2 Hz and non-finite or
// negative clocks are REFUSED, so production cost stays bounded. State is
// NSLock-guarded so consumers (crop, depth, brightness, screenshot) can
// read from any thread. No render-thread type (Metal/AppKit) is touched
// here.
//
// Ownership contract (review item 6): exactly one tap per playback
// session, created by the composing SESSION OWNER through
// FrameTap.makeForSession, assigned to ShellFrameSource.frameTap for the
// session's lifetime, and closed at session teardown (ShellFrameSource's
// deinit also closes it). After close() the tap refuses every later offer.

/// One retained decoded frame with its full identity.
public struct TappedFrame: @unchecked Sendable {
    /// Owning playback session (SessionID.epoch of the producing source).
    public let session: UInt64
    /// Seek generation the frame was ADMITTED under (the frame origin's
    /// provider revision captured at admission; 0 on the legacy unfenced
    /// path). Stamped from the admitted origin, never re-read after awaits.
    public let seekGeneration: UInt64
    /// Provider-minted source identity the frame was decoded from (nil on
    /// the legacy unfenced path). Session+generation alone collides across
    /// a prepared source replacement; the token is what makes the identity
    /// exact against the bridge's current fence binding.
    public let source: SourceToken?
    /// Decoder frame handle (identity only; the decoder lease is NOT held).
    public let handle: UInt64
    /// Presentation time in the producer's decoder time base.
    public let pts: Int64
    /// Presentation time in seconds (producer time base applied).
    public let ptsSeconds: Double
    public let width: Int
    public let height: Int
    public let pixelFormatName: String
    /// ACTUAL retained bytes: sum of CoreVideo plane bytesPerRow x plane
    /// height recorded at production (stride- and odd-chroma-exact).
    public let retainedBytes: Int
    /// Retained pixel buffer. Owned by this TappedFrame; valid until the
    /// frame is consumed or released by the tap. Never a decoder-lease
    /// pointer: planes were copied into tap-owned storage at accept time.
    public let pixelBuffer: CVPixelBuffer
    public init(session: UInt64, seekGeneration: UInt64, source: SourceToken?,
                handle: UInt64,
                pts: Int64, ptsSeconds: Double, width: Int, height: Int,
                pixelFormatName: String, retainedBytes: Int, pixelBuffer: CVPixelBuffer) {
        self.session = session; self.seekGeneration = seekGeneration
        self.source = source
        self.handle = handle; self.pts = pts; self.ptsSeconds = ptsSeconds
        self.width = width; self.height = height
        self.pixelFormatName = pixelFormatName
        self.retainedBytes = retainedBytes; self.pixelBuffer = pixelBuffer
    }
}

public enum FrameTapVerdict: Equatable, Sendable {
    case accepted
    /// Within the rate budget: frame refused before any copy/retain.
    case droppedRateLimit
    /// Queue full: the OLDEST retained frame was released to keep the tap live.
    case acceptedEvictingOldest
    /// Frame carries a session this tap no longer serves.
    case refusedStaleSession
    /// Frame carries a generation older than the current seek fence.
    case refusedStaleGeneration
    /// Clock sample was non-finite or negative: refused, never rate-bypassed.
    case refusedInvalidClock
    /// Retaining this frame would exceed the byte budget after eviction.
    case refusedByteBudget
    /// The tap is closed; every later offer refuses typed.
    case refusedClosed
    /// Arithmetic overflow while accounting a hostile frame; nothing was
    /// retained or mutated.
    case refusedOverflow
}

public struct FrameTapCounters: Equatable, Sendable {
    public var accepted = 0
    public var droppedRateLimit = 0
    public var evictedOldest = 0
    public var evictedByteBudget = 0
    public var refusedStaleSession = 0
    public var refusedStaleGeneration = 0
    public var refusedInvalidClock = 0
    public var refusedByteBudget = 0
    public var refusedClosed = 0
    public var refusedOverflow = 0
    public var fencedReleases = 0
    public var consumed = 0
    public var readbacks = 0
    public var closedReleases = 0
    public init() {}
}

public final class FrameTap: @unchecked Sendable {
    /// The session this tap serves; frames from any other session are refused.
    public let session: UInt64
    private let capacity: Int
    private let minInterval: Double
    private let byteBudget: Int
    private let lock = NSLock()
    private var queue: [TappedFrame] = []
    /// Retained bytes of frames in the queue slot.
    private var queuedBytes = 0
    /// Newest accepted frame, held for the readback path. ALWAYS accounted
    /// in newestBytes, including while the same frame is also queued (two
    /// retain slots, two accounts) and after it leaves the queue - a
    /// consumed frame held for readback is never unaccounted.
    private var newest: TappedFrame?
    private var newestBytes = 0
    private var lastAcceptClock: Double?
    /// Current seek fence: frames older than this generation refuse typed.
    private var generation: UInt64 = 0
    private var closed = false
    public private(set) var counters = FrameTapCounters()

    /// capacity >= 1; maxPerSecond <= 0 means no rate limit (default 2 Hz);
    /// byteBudget bounds total retained bytes across BOTH slots.
    public init(session: UInt64, capacity: Int = 8, maxPerSecond: Double = 2.0,
                byteBudget: Int = 64 << 20) {
        self.session = session
        self.capacity = max(1, capacity)
        self.minInterval = maxPerSecond > 0 ? 1.0 / maxPerSecond : 0
        self.byteBudget = max(1, byteBudget)
    }

    /// P27 session-owner creation contract: the composing session owner
    /// (Delivery wires it) creates exactly one tap per playback session
    /// here, assigns it to ShellFrameSource.frameTap, and closes it at
    /// session teardown. No other production site assigns frameTap.
    public static func makeForSession(session: UInt64, capacity: Int = 8,
                                      maxPerSecond: Double = 2.0,
                                      byteBudget: Int = 64 << 20) -> FrameTap {
        FrameTap(session: session, capacity: capacity,
                 maxPerSecond: maxPerSecond, byteBudget: byteBudget)
    }

    public var depth: Int { lock.lock(); defer { lock.unlock() }; return queue.count }
    /// Total retained bytes across both retain slots.
    public var retainedBytes: Int { lock.lock(); defer { lock.unlock() }; return queuedBytes + newestBytes }
    public var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }

    /// Cheap pre-check for the producer: TRUE only when an offer right now
    /// would not be closed/session/generation/clock/rate refused. Lets the
    /// decode worker skip the CVPixelBuffer production copy for dropped
    /// frames. The authoritative verdict remains offer()'s (state may
    /// change between the two calls under concurrency).
    public func admits(session: UInt64, generation: UInt64, clockNow: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed, session == self.session, generation >= self.generation else { return false }
        guard clockNow.isFinite, clockNow >= 0 else { return false }
        if minInterval > 0, let last = lastAcceptClock, clockNow - last < minInterval { return false }
        return true
    }

    /// Offer one decoded frame observed at `clockNow`. The clock must be
    /// finite and >= 0; non-finite or negative samples are REFUSED (never
    /// a rate-limiter bypass). On any refusal the caller's buffer is NOT
    /// retained; ownership stays with the caller.
    @discardableResult
    public func offer(_ frame: TappedFrame, clockNow: Double) -> FrameTapVerdict {
        lock.lock(); defer { lock.unlock() }
        guard !closed else {
            counters.refusedClosed += 1
            return .refusedClosed
        }
        guard frame.session == session else {
            counters.refusedStaleSession += 1
            return .refusedStaleSession
        }
        guard frame.seekGeneration >= generation else {
            counters.refusedStaleGeneration += 1
            return .refusedStaleGeneration
        }
        guard clockNow.isFinite, clockNow >= 0 else {
            counters.refusedInvalidClock += 1
            return .refusedInvalidClock
        }
        if minInterval > 0, let last = lastAcceptClock, clockNow - last < minInterval {
            counters.droppedRateLimit += 1
            return .droppedRateLimit
        }
        let frameBytes = max(0, frame.retainedBytes)
        // Overflow-safe accounting (hostile retainedBytes refuses typed
        // BEFORE any queue/counter mutation beyond the refusal count).
        let (doubleBytes, ov) = frameBytes.multipliedReportingOverflow(by: 2)
        guard !ov else {
            counters.refusedOverflow += 1
            return .refusedOverflow
        }
        var verdict: FrameTapVerdict = .accepted
        // Budget against the REAL final state: after accept the new frame
        // sits in BOTH the FIFO (queuedBytes) and the readback slot
        // (newestBytes replaces the old newest's account), so the worst-case
        // final total is queuedBytes + doubleBytes. Evict oldest queued
        // frames until that final state fits; a frame that cannot fit even
        // into an empty tap refuses typed (never retained).
        while !queue.isEmpty {
            let (total, sumOv) = queuedBytes.addingReportingOverflow(doubleBytes)
            if !sumOv, total <= byteBudget { break }
            let evicted = queue.removeFirst()
            queuedBytes -= max(0, evicted.retainedBytes)
            counters.evictedByteBudget += 1
        }
        let (finalTotal, finalOv) = queuedBytes.addingReportingOverflow(doubleBytes)
        guard !finalOv else {
            counters.refusedOverflow += 1
            return .refusedOverflow
        }
        guard finalTotal <= byteBudget else {
            counters.refusedByteBudget += 1
            return .refusedByteBudget
        }
        if queue.count >= capacity {
            let evicted = queue.removeFirst()
            queuedBytes -= max(0, evicted.retainedBytes)
            counters.evictedOldest += 1
            verdict = .acceptedEvictingOldest
        }
        queue.append(frame)
        queuedBytes += frameBytes
        newest = frame
        newestBytes = frameBytes
        lastAcceptClock = clockNow
        counters.accepted += 1
        return verdict
    }

    /// Fence the tap at a new seek generation: retained frames from older
    /// generations are released now (both slots), and later offers of older
    /// generations refuse typed. Monotonic: an older fence value is a no-op.
    public func fence(newGeneration: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard newGeneration > generation else { return }
        generation = newGeneration
        var kept: [TappedFrame] = []
        kept.reserveCapacity(queue.count)
        for frame in queue {
            if frame.seekGeneration >= newGeneration {
                kept.append(frame)
            } else {
                queuedBytes -= max(0, frame.retainedBytes)
                counters.fencedReleases += 1
            }
        }
        queue = kept
        if let n = newest, n.seekGeneration < newGeneration {
            newest = nil
            newestBytes = 0
            counters.fencedReleases += 1
        }
    }

    /// Oldest retained frame (FIFO). Ownership of the queue slot moves to
    /// the caller; the newest slot keeps its own accounted retain when the
    /// consumed frame is also the newest.
    public func next() -> TappedFrame? {
        lock.lock(); defer { lock.unlock() }
        guard !queue.isEmpty else { return nil }
        let frame = queue.removeFirst()
        queuedBytes -= max(0, frame.retainedBytes)
        counters.consumed += 1
        return frame
    }

    /// Newest accepted frame for the screenshot/readback path, retained and
    /// accounted even after the frame leaves the queue. Consumers must
    /// check seekGeneration against the current fence before trusting
    /// pixels.
    public func latestForReadback() -> TappedFrame? {
        lock.lock(); defer { lock.unlock() }
        if newest != nil { counters.readbacks += 1 }
        return newest
    }

    /// Release every retained frame and close the tap (teardown / source
    /// close). Every later offer refuses .refusedClosed.
    public func close() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        counters.closedReleases += queue.count + (newest != nil ? 1 : 0)
        queue.removeAll()
        queuedBytes = 0
        newest = nil
        newestBytes = 0
    }
}

/// Real producer of tap-owned CVPixelBuffers from decoded yuv420p planes.
/// Planes are COPIED into CoreVideo-allocated storage, so the result
/// outlives the decoder lease it was produced from; ownership moves to the
/// caller (and from there into the tap on accept).
public enum YUV420PixelBufferProducer {
    /// Copy 3-plane yuv420p (Y full res, U/V half res with CEIL sizes for
    /// odd dimensions, per the shell's narrow SDR contract) into a new
    /// kCVPixelFormatType_420YpCbCr8Planar buffer. Returns the buffer AND
    /// its actual retained bytes (per-plane bytesPerRow x plane height -
    /// stride-exact, not an estimate). Nil on any size/overflow/budget
    /// violation - never a partial buffer.
    public static func makePlanar(planes: [[UInt8]], width: Int, height: Int,
                                  maxBytes: Int = 128 << 20) -> (buffer: CVPixelBuffer, retainedBytes: Int)? {
        guard planes.count == 3, width > 0, height > 0, maxBytes > 0 else { return nil }
        // Checked ceil-half dimensions: hostile Int.max inputs return nil,
        // never trap.
        let (wPlus1, ow) = width.addingReportingOverflow(1)
        let (hPlus1, oh) = height.addingReportingOverflow(1)
        guard !ow, !oh else { return nil }
        let chromaWidth = wPlus1 >> 1, chromaHeight = hPlus1 >> 1
        let (yNeed, o1) = width.multipliedReportingOverflow(by: height)
        let (cNeed, o2) = chromaWidth.multipliedReportingOverflow(by: chromaHeight)
        guard !o1, !o2, planes[0].count >= yNeed,
              planes[1].count >= cNeed, planes[2].count >= cNeed else { return nil }
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true,
                                      kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
        guard CVPixelBufferCreate(nil, width, height,
                                  kCVPixelFormatType_420YpCbCr8Planar,
                                  attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let buffer = pb else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0)) == kCVReturnSuccess
        else { return nil }
        var copiedBytes = 0
        var retainedBytes = 0
        var ok = true
        for plane in 0..<3 {
            guard let dst = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { ok = false; break }
            let dstStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
            let dstRows = CVPixelBufferGetHeightOfPlane(buffer, plane)
            let srcRows = plane == 0 ? height : chromaHeight
            let srcRowBytes = plane == 0 ? width : chromaWidth
            guard dstStride >= srcRowBytes, dstRows >= srcRows else { ok = false; break }
            let (planeCopy, ov1) = srcRowBytes.multipliedReportingOverflow(by: srcRows)
            let (planeRetained, ov2) = dstStride.multipliedReportingOverflow(by: dstRows)
            let (runningCopy, ov3) = copiedBytes.addingReportingOverflow(planeCopy)
            let (runningRetained, ov4) = retainedBytes.addingReportingOverflow(planeRetained)
            guard !ov1, !ov2, !ov3, !ov4, runningCopy <= maxBytes,
                  runningRetained <= maxBytes else { ok = false; break }
            planes[plane].withUnsafeBytes { src in
                guard let base = src.baseAddress else { ok = false; return }
                for row in 0..<srcRows {
                    memcpy(dst + row * dstStride, base + row * srcRowBytes, srcRowBytes)
                }
            }
            guard ok else { break }
            copiedBytes = runningCopy
            retainedBytes = runningRetained
        }
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        return ok ? (buffer, retainedBytes) : nil
    }
}
#endif
