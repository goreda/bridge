// L1 rework v4 (architect PART1 + v2-review + full-review):
// true single-producer/single-consumer rings on C11 atomics.
//  v4-1: atomic CELLS are C-owned AND C-typed: gorav_acell_create()
//        (malloc + atomic_init + compile-time lock-free assertion +
//        runtime atomic_is_lock_free proof, NULL = typed refusal). No
//        Swift allocator, no Swift-typed storage under an atomic access.
//  v4-2: BOTH rings use raw allocated storage (no Array, no CoW, no
//        subscript, no lock, no alloc on either hot path).
//  v4-3: a STICKY drop latch (droppedAnything) is set by ANY drop -
//        frame drop, partial-tail refusal, or event-ring overflow. A
//        per-generation reset clears it; "==1" exact-count reads are gone.
//  v4-4: event payloads are UNIT-TYPED (frames vs bytes); no frames value
//        is ever stored in a bytes field.
//  v4-5: render takes UInt32 frames (the AudioUnit unit); all byte
//        arithmetic is range-checked before conversion.
import Foundation
import GorAVCAtomics

/// Atomic UInt64 on a C-owned, C-typed cell (v4-1). The cell is created
/// by C (malloc + atomic_init + lock-free proof) and destroyed by C.
/// Failable: a NULL cell is a typed refusal, never a silent fallback.
public final class AtomicU64: @unchecked Sendable {
    /// Opaque C-owned cell (an _Atomic uint64_t on the C heap). Never nil
    /// after a successful init - the failable init is the typed refusal.
    private let cell: UnsafeMutableRawPointer
    public init?(_ initial: UInt64 = 0) {
        guard let c = gorav_acell_create(initial) else { return nil }
        cell = c
    }
    deinit { gorav_acell_destroy(cell) }
    @inline(__always) public func load() -> UInt64 { gorav_aload(cell) }
    @inline(__always) public func store(_ v: UInt64) { gorav_astore(cell, v) }
    @discardableResult @inline(__always) public func fetchAdd(_ v: UInt64) -> UInt64 { gorav_afetch_add(cell, v) }
    /// Single-word CAS: true iff the cell held `expected` and now holds
    /// `desired`. The reservation primitive (S1d atomic reserve).
    @discardableResult @inline(__always) public func compareExchange(expected: UInt64, desired: UInt64) -> Bool {
        var e = expected
        return gorav_acas(cell, &e, desired) != 0
    }
    /// Saturating read for telemetry: never traps on conversion.
    public var intValue: Int { let v = load(); return v > UInt64(Int.max) ? Int.max : Int(v) }
}

/// LANE-0 / architect 80b constraint A: callback admission. One packed
/// C-owned cell (bit 63 RETIRED + reader count). A reader (RT callback)
/// enters ONLY while not retired; after retire it touches NO payload and
/// outputs silence. The owner retires FIRST, then drains admitted readers
/// to zero BEFORE any reset/reuse/dispose. This is a LOCAL payload
/// lifetime fence - NO provider-quiescence claim.
public final class AdmissionCell: @unchecked Sendable {
    private let cell: UnsafeMutableRawPointer
    public init?() {
        guard let c = gorav_acell_create(0) else { return nil }
        cell = c
    }
    deinit { gorav_acell_destroy(cell) }
    /// RT-safe, lock-free. true = admitted (MUST exit); false = retired.
    @inline(__always) public func enter() -> Bool { gorav_admit_enter(cell) != 0 }
    @inline(__always) public func exit() { gorav_admit_exit(cell) }
    /// Retire (idempotent); returns readers still inside at retire time.
    @discardableResult public func retire() -> UInt64 { gorav_admit_retire(cell) }
    public var readers: UInt64 { gorav_admit_readers(cell) }
    public var isRetired: Bool { gorav_admit_is_retired(cell) != 0 }
}

public struct RTEvent: Sendable, Equatable {
    public enum Kind: UInt8, Sendable { case underrunStart = 1, underrunEnd = 2, staleFenced = 3 }
    /// Unit-typed payload (v4-4): underrun events carry FRAMES;
    /// staleFenced carries BYTES. The units are part of the type.
    public enum Payload: Sendable, Equatable { case frames(UInt64), bytes(UInt64) }
    public let kind: Kind
    public let generation: UInt64   // session generation AT POST TIME (per-registration context)
    public let tEvent: Double       // event-time stamp from the injected clock
    public let payload: Payload
    public init(kind: Kind, generation: UInt64, tEvent: Double, payload: Payload) {
        self.kind = kind; self.generation = generation; self.tEvent = tEvent; self.payload = payload
    }
}

/// SPSC event ring. Writer: the RT render callback. Reader: off-RT drain.
/// v4-2: slots live in a raw allocated buffer; the write index publishes
/// with a release store after the slot is fully written; the reader
/// acquire-loads. No Array, no CoW, no lock, no allocation on the hot path.
public final class SPSCEventRing: @unchecked Sendable {
    private let buf: UnsafeMutablePointer<RTEvent>
    public let capacity: Int
    private let w: AtomicU64
    private let r: AtomicU64
    /// Monotonic per-generation overflow counter (diagnostic).
    public let overflowed: AtomicU64
    /// STICKY latch (v4-3): 1 once ANY event was dropped this generation.
    public let droppedAnything: AtomicU64
    private let clock: @Sendable () -> Double
    public init?(capacity requested: Int = 256, clock: @Sendable @escaping () -> Double) {
        // v5-1: C cells FIRST - a cell refusal leaves no raw buffer behind
        // (previously the buffer was allocated before the guard: a leak).
        guard let w = AtomicU64(), let r = AtomicU64(),
              let ov = AtomicU64(), let da = AtomicU64() else { return nil }
        self.w = w; self.r = r; self.overflowed = ov; self.droppedAnything = da
        let cap = Swift.max(1, Swift.min(requested, 1 << 16)) // clamp, never trap
        self.capacity = cap
        buf = UnsafeMutablePointer<RTEvent>.allocate(capacity: cap)
        buf.initialize(repeating: RTEvent(kind: .underrunEnd, generation: 0, tEvent: 0, payload: .frames(0)), count: cap)
        self.clock = clock
    }
    deinit { buf.deinitialize(count: capacity); buf.deallocate() }
    /// RT-safe. Single writer. `generation` comes from the caller's
    /// PER-REGISTRATION context, never from shared mutable sink state.
    public func post(_ kind: RTEvent.Kind, generation: UInt64, payload: RTEvent.Payload) {
        let wi = w.load()          // own index: exact
        let ri = r.load()          // reader's index: stale-low only
        // v5-2: counter-space exhaustion is a TYPED refusal BEFORE wrap -
        // no wrapping-arithmetic claim is made anywhere in this type.
        if wi >= UInt64.max - 1 { overflowed.fetchAdd(1); droppedAnything.store(1); return }
        if wi &- ri >= UInt64(capacity) { overflowed.fetchAdd(1); droppedAnything.store(1); return }
        let t = clock()            // event time at post
        buf[Int(wi % UInt64(capacity))] = RTEvent(kind: kind, generation: generation, tEvent: t, payload: payload)
        w.store(wi &+ 1)           // release: publishes the slot above
    }
    /// OFF-RT. Single reader.
    public func drain() -> [RTEvent] {
        let ri = r.load()
        let wi = w.load()
        let n = (wi >= ri) ? (wi - ri) : 0 // defined order + saturating
        guard n > 0 else { return [] }
        var out: [RTEvent] = []
        out.reserveCapacity(Int(Swift.min(n, UInt64(capacity))))
        for i in 0..<n { out.append(buf[Int((ri &+ i) % UInt64(capacity))]) }
        r.store(wi)
        return out
    }
    /// Generation reset: owner side only, while the RT poster is proven
    /// quiescent. Clears indices, the overflow counter AND the sticky latch.
    public func resetForNewGeneration() {
        r.store(0); w.store(0); overflowed.store(0); droppedAnything.store(0)
    }
}

/// Immutable admission evidence for one STOPPED session: captured BEFORE
/// resetForNewGeneration() so the retired session's records survive the
/// reset. Live queue state and retired-session evidence are SEPARATE.
public struct PCMRingReceipt: Sendable, Equatable {
    public let generation: UInt64
    public let requestedBytes: UInt64
    public let admittedBytes: UInt64
    public let droppedBytes: UInt64       // frame-drops AND refused partial tails, byte-exact
    public let partialTailDrops: UInt64   // count of refused 1-3 byte tails (NOT frames)
    public let pushedFrames: UInt64
    public let droppedFrames: UInt64
    public let consumedFrames: UInt64
    public let underrunFrames: UInt64
    public let pushCount: UInt64
    public let maxPushFrames: UInt64
    public let maxAvailAfterPushFrames: UInt64
    public let droppedAnything: Bool      // sticky latch at snapshot time
}

/// SPSC PCM ring, frame-quantized (4-byte s16le stereo frames).
/// Writer: the decoder-side producer (off-RT). Reader: the RT render
/// callback. Raw allocated storage: no Array subscript, no CoW, no lock,
/// no allocation on either hot path.
public final class SPSCPCMRing: @unchecked Sendable {
    public static let bytesPerFrame = 4
    /// Hard capacity bound: validated at init, clamped - never a trap.
    public static let maxCapacityFrames = 1 << 22
    private let buf: UnsafeMutablePointer<UInt8>
    public let capacityFrames: UInt64
    private let w: AtomicU64 // frames written (monotonic) - PRODUCER-owned
    private let r: AtomicU64 // frames read (monotonic) - CONSUMER-owned
    public let requestedBytes: AtomicU64
    public let admittedBytes: AtomicU64
    public let droppedBytes: AtomicU64
    public let partialTailDrops: AtomicU64
    public let pushedFrames: AtomicU64
    public let droppedFrames: AtomicU64
    public let consumedFrames: AtomicU64
    public let underrunFrames: AtomicU64
    public let pushCount: AtomicU64
    public let maxPushFrames: AtomicU64
    public let maxAvailAfterPushFrames: AtomicU64
    /// STICKY latch (v4-3): 1 once ANY byte or frame was refused.
    public let droppedAnything: AtomicU64
    public init?(capacityFrames requested: Int = 1 << 18) {
        // v5-1: C cells FIRST - a cell refusal leaves no raw buffer behind.
        guard let w = AtomicU64(), let r = AtomicU64(),
              let req = AtomicU64(), let adm = AtomicU64(), let drb = AtomicU64(),
              let ptd = AtomicU64(), let pf = AtomicU64(), let df = AtomicU64(),
              let cf = AtomicU64(), let uf = AtomicU64(), let pc = AtomicU64(),
              let mp = AtomicU64(), let ma = AtomicU64(), let da = AtomicU64() else { return nil }
        self.w = w; self.r = r
        self.requestedBytes = req; self.admittedBytes = adm; self.droppedBytes = drb
        self.partialTailDrops = ptd; self.pushedFrames = pf; self.droppedFrames = df
        self.consumedFrames = cf; self.underrunFrames = uf; self.pushCount = pc
        self.maxPushFrames = mp; self.maxAvailAfterPushFrames = ma
        self.droppedAnything = da
        let cap = Swift.max(1, Swift.min(requested, SPSCPCMRing.maxCapacityFrames))
        buf = UnsafeMutablePointer<UInt8>.allocate(capacity: cap * SPSCPCMRing.bytesPerFrame)
        buf.initialize(repeating: 0, count: cap * SPSCPCMRing.bytesPerFrame)
        self.capacityFrames = UInt64(cap)
    }
    deinit { buf.deinitialize(count: Int(capacityFrames) * SPSCPCMRing.bytesPerFrame); buf.deallocate() }
    /// Approximate LIVE occupancy for observers (hb/telemetry): loads r
    /// BEFORE w with a saturating subtract - can never underflow; may
    /// overestimate by the frames consumed between the two loads.
    public var availableFrames: UInt64 {
        let ri = r.load(); let wi = w.load()
        return wi >= ri ? wi - ri : 0
    }
    /// Producer side (OFF-RT). Whole frames only; a trailing partial frame
    /// is REFUSED and counted byte-exactly (partialTailDrops/droppedBytes),
    /// never as a 4-byte frame drop. Drop policy when full: drop-newest at
    /// frame granularity. ANY refusal sets the sticky latch.
    @discardableResult
    public func push(_ pcm: UnsafeBufferPointer<UInt8>) -> (admittedFrames: UInt64, droppedFrames: UInt64, droppedTailBytes: UInt64) {
        let reqBytes = UInt64(pcm.count)
        requestedBytes.fetchAdd(reqBytes)
        let frames = reqBytes / UInt64(SPSCPCMRing.bytesPerFrame)
        let tail = reqBytes % UInt64(SPSCPCMRing.bytesPerFrame)
        if tail > 0 {
            partialTailDrops.fetchAdd(1)
            droppedBytes.fetchAdd(tail)
            droppedAnything.store(1)
        }
        guard frames > 0 else { return (0, 0, tail) }
        // v5-3: the chunk witness records EVERY attempted push, including
        // fully rejected ones (a refused large push is still evidence of
        // what the producer asked for).
        if frames > maxPushFrames.load() { maxPushFrames.store(frames) }
        let wi = w.load()                    // own: exact
        // v5-2: refuse BEFORE the monotonic counters can wrap - typed drop,
        // sticky latch; no wrapping-arithmetic claim is made.
        if wi > UInt64.max - UInt64(capacityFrames) - 1 {
            droppedFrames.fetchAdd(frames)
            droppedBytes.fetchAdd(frames &* UInt64(SPSCPCMRing.bytesPerFrame))
            droppedAnything.store(1)
            return (0, frames, tail)
        }
        let ri = r.load()                    // consumer's: stale-low only -> free-space UNDERestimate, safe
        let used = wi >= ri ? wi - ri : 0
        let free = used < capacityFrames ? capacityFrames - used : 0
        let admit = Swift.min(frames, free)
        let drop = frames - admit
        if admit > 0 {
            var idx = Int(wi % capacityFrames) &* SPSCPCMRing.bytesPerFrame
            var src = 0
            let n = Int(admit) &* SPSCPCMRing.bytesPerFrame
            let base = pcm.baseAddress!
            while src < n {
                buf[idx] = base[src]
                idx = (idx &+ 1) == bufCount ? 0 : idx &+ 1
                src &+= 1
            }
            // Admission witness BEFORE publication: the peak occupancy
            // attributable to this push, computed with a fresh consumer
            // read - never an after-publish underestimate.
            let witness = (wi &+ admit) &- r.load()
            if witness > maxAvailAfterPushFrames.load() { maxAvailAfterPushFrames.store(witness) }
            w.store(wi &+ admit)             // release: publishes the bytes above
            pushedFrames.fetchAdd(admit)
            pushCount.fetchAdd(1)
            admittedBytes.fetchAdd(admit &* UInt64(SPSCPCMRing.bytesPerFrame))
        }
        if drop > 0 {
            droppedFrames.fetchAdd(drop)
            droppedBytes.fetchAdd(drop &* UInt64(SPSCPCMRing.bytesPerFrame))
            droppedAnything.store(1)
        }
        return (admit, drop, tail)
    }
    private var bufCount: Int { Int(capacityFrames) &* SPSCPCMRing.bytesPerFrame }
    /// Consumer side (RT). Renders `frames` frames DIRECTLY into `dst`:
    /// real frames copied, shortfall zero-filled and counted as underrun.
    /// No allocation, no lock, no Array subscript. Returns underrun frames.
    /// v4-5: frames is UInt32 (the AudioUnit unit); byte arithmetic is
    /// range-checked, no UInt64->Int narrowing.
    @discardableResult
    public func render(into dst: UnsafeMutablePointer<UInt8>, frames: UInt32) -> UInt32 {
        let want = UInt64(frames)
        let ri = r.load()                    // own: exact
        let wi = w.load()                    // producer's: acquire; may equal/exceed ri
        let avail = wi >= ri ? wi - ri : 0   // saturating: never underflows
        let real = Swift.min(avail, want)
        if real > 0 {
            var idx = Int(ri % capacityFrames) &* SPSCPCMRing.bytesPerFrame
            var i = 0
            let n = Int(real) &* SPSCPCMRing.bytesPerFrame // real <= UInt32.max frames
            while i < n {
                dst[i] = buf[idx]
                idx = (idx &+ 1) == bufCount ? 0 : idx &+ 1
                i &+= 1
            }
            r.store(ri &+ real)              // release the consumed region
            consumedFrames.fetchAdd(real)
        }
        let total = Int(frames) &* SPSCPCMRing.bytesPerFrame
        var i = Int(real) &* SPSCPCMRing.bytesPerFrame
        while i < total { dst[i] = 0; i &+= 1 }
        let under = want - real
        if under > 0 { underrunFrames.fetchAdd(under) }
        return UInt32(under)
    }
    /// Capture this session's admission evidence. Preconditions (enforced
    /// by the sink's lifecycle, not by this type): producer AND consumer
    /// BOTH quiescent (stop completed, pump joined) - then every counter is
    /// stable and the snapshot is internally consistent.
    public func snapshotReceipt(generation: UInt64) -> PCMRingReceipt {
        PCMRingReceipt(generation: generation,
                       requestedBytes: requestedBytes.load(),
                       admittedBytes: admittedBytes.load(),
                       droppedBytes: droppedBytes.load(),
                       partialTailDrops: partialTailDrops.load(),
                       pushedFrames: pushedFrames.load(),
                       droppedFrames: droppedFrames.load(),
                       consumedFrames: consumedFrames.load(),
                       underrunFrames: underrunFrames.load(),
                       pushCount: pushCount.load(),
                       maxPushFrames: maxPushFrames.load(),
                       maxAvailAfterPushFrames: maxAvailAfterPushFrames.load(),
                       droppedAnything: droppedAnything.load() != 0)
    }
    /// Generation reset: called by the sink ONLY with BOTH writer and
    /// reader proven quiescent (producer task joined AND AudioUnit
    /// stop+uninit succeeded). The receipt MUST be snapshotted first.
    public func resetForNewGeneration() {
        r.store(0); w.store(0)
        requestedBytes.store(0); admittedBytes.store(0); droppedBytes.store(0)
        partialTailDrops.store(0)
        pushedFrames.store(0); droppedFrames.store(0)
        consumedFrames.store(0); underrunFrames.store(0)
        pushCount.store(0); maxPushFrames.store(0); maxAvailAfterPushFrames.store(0)
        droppedAnything.store(0)
    }
}
