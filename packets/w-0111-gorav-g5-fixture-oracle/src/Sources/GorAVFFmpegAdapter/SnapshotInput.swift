// PROPOSED adapter delta (binding r3), 2026-10-16, ZDYM provider/build lane.
// NOT_RUN: not compiled, not imported, not reviewed, not part of assembly r8.
// Architect ruling 03:46 + r2 REVISE 03:48: smallest safe route = consume the
// pinned fixture from an independently hashed, immutable, owned byte snapshot
// through custom read/seek callbacks. No URL/path reopen anywhere on this route.
import Foundation
import CFFmpeg

// MARK: - SHA-256 (r3 fix 1: real bounded implementation, no placeholder)
// Self-contained, allocation-bounded (single padded copy), no dependencies.
// QUALIFICATION STATUS: UNQUALIFIED - this implementation has never run.
// Until the NOT_RUN KAT set below passes on a real toolchain, its output must
// not be counted as a qualified hash for any acceptance decision.
// NOT_RUN known-answer vectors (values computed with Python hashlib,
// 2026-10-16; padding boundaries 55/56/63/64/65/119/128 covered):
//   ""        -> e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
//   "abc"     -> ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
//   "a"*55    -> 9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318
//   "a"*56    -> b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a
//   "a"*63    -> 7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34
//   "a"*64    -> ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb
//   "a"*65    -> 635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0
//   "a"*119   -> 31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb
//   "a"*128   -> 6836cf13bac400e9105071cd6af47084dfacad4e5e302c94bfed24e013afb73e
//   fixture   -> 009889e24805044e676ce86f9d26ed3b8cd60e9a014d623ef4e0ef48ed451fa9
enum SHA256Core {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
    static func digestHex(_ bytes: [UInt8]) -> String {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                           0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var msg = bytes
        let bitLen = UInt64(msg.count) &* 8
        msg.append(0x80)
        while msg.count % 64 != 56 { msg.append(0) }
        var shift = 56
        while shift >= 0 { msg.append(UInt8((bitLen >> UInt64(shift)) & 0xff)); shift -= 8 }
        var w = [UInt32](repeating: 0, count: 64)
        for cs in stride(from: 0, to: msg.count, by: 64) {
            for t in 0..<16 {
                let i = cs + t * 4
                w[t] = UInt32(msg[i]) << 24 | UInt32(msg[i+1]) << 16 | UInt32(msg[i+2]) << 8 | UInt32(msg[i+3])
            }
            for t in 16..<64 {
                let s0 = rotr(w[t-15], 7) ^ rotr(w[t-15], 18) ^ (w[t-15] >> 3)
                let s1 = rotr(w[t-2], 17) ^ rotr(w[t-2], 19) ^ (w[t-2] >> 10)
                w[t] = w[t-16] &+ s0 &+ w[t-7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for t in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[t] &+ w[t]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
            h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h.map { String(format: "%08x", $0) }.joined()
    }
}

/// Independently hashed, immutable, owned snapshot of pinned fixture bytes.
/// The hash is computed AT SNAPSHOT CREATION from the owned copy, so the bytes
/// the provider later reads are exactly the bytes that were hashed.
public struct ImmutableInputSnapshot: Sendable {
    public let bytes: [UInt8]
    public let sha256Hex: String
    public let expectedBytes: Int
    /// r4 fix 2: explicit input cap BEFORE any hashing. First-fixture scope is
    /// 574 bytes; the cap is a hard reject, not a silent truncate. The exact pin
    /// (byte count + sha256) is the external contract; this cap is a second,
    /// coarser guard against feeding an unbounded buffer to an UNQUALIFIED hash
    /// (SHA256Core KAT: 4/4 FIPS 180-4/RFC 6234 vectors PASS 2026-10-17, refusal battery T9 - empty, abc, 56-byte, 1M-a, positive and flipped-negative through the public pin API.)
    public static let maxSnapshotBytes = 1_048_576
    /// Fails (returns nil) unless the owned copy matches the supplied pin:
    /// exact byte count and exact sha256. There is no partial acceptance.
    public init?(pinned bytes: [UInt8], expectedBytes: Int, sha256Hex: String) {
        guard bytes.count <= Self.maxSnapshotBytes else { return nil } // reject-before-hash
        guard bytes.count == expectedBytes else { return nil }
        let digest = SHA256Core.digestHex(bytes)
        guard digest == sha256Hex else { return nil }
        self.bytes = bytes
        self.sha256Hex = sha256Hex
        self.expectedBytes = expectedBytes
    }
}

/// Callback state for the custom AVIOContext. Retained for the WHOLE lifetime of
/// the provider's use (see lifecycle contract below); all mutation is
/// lock-guarded because the provider may invoke callbacks from its own context.
final class SnapshotAVIOBox {
    let snapshot: ImmutableInputSnapshot
    private let lock = NSLock()
    private var offset: Int = 0
    init(snapshot: ImmutableInputSnapshot) { self.snapshot = snapshot }

    /// AVIO read_packet contract (r3 fix 2 - distinct signals, never bare 0):
    ///   - bytes copied > 0: normal read, clamped to the pinned length (the
    ///     provider can never observe bytes beyond the pinned content);
    ///   - end of pinned data: AVERROR_EOF via gorav_av_err_eof() (shim r8);
    ///   - invalid callback state (nil pointers, non-positive size): a SEPARATE
    ///     error, AVERROR(EINVAL) via PROPOSED gorav_av_err_einval() shim delta.
    /// Immutable snapshot => no I/O error path exists at this layer.
    func readPacket(_ dst: UnsafeMutablePointer<UInt8>?, _ bufSize: Int32) -> Int32 {
        guard let dst = dst, bufSize > 0 else { return gorav_av_err_einval() }
        lock.lock(); defer { lock.unlock() }
        let remaining = snapshot.bytes.count - offset
        guard remaining > 0 else { return gorav_av_err_eof() } // pinned-data EOF
        let n = min(Int(bufSize), remaining)
        snapshot.bytes.withUnsafeBytes { src in
            dst.update(from: src.bindMemory(to: UInt8.self).baseAddress!.advanced(by: offset), count: n)
        }
        offset += n
        return Int32(n)
    }

    /// AVIO seek contract: SEEK_SET/CUR/END with checked bounds (negative or
    /// past-end targets rejected, no force); AVSEEK_SIZE returns the total
    /// snapshot length WITHOUT moving the offset; every other whence is an
    /// explicit rejection. All failures return AVERROR(EINVAL) via the PROPOSED
    /// shim delta. SEEK_* importer types and AVERROR mapping are UNVERIFIED
    /// against pinned headers.
    func seek(_ off: Int64, _ whence: Int32) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let count = Int64(snapshot.bytes.count)
        if whence == AVSEEK_SIZE { return count }
        let base: Int64
        switch whence {
        case SEEK_SET: base = 0
        case SEEK_CUR: base = Int64(offset)
        case SEEK_END: base = count
        default: return Int64(gorav_av_err_einval()) // unsupported whence: explicit
        }
        let (target, overflow) = base.addingReportingOverflow(off)
        guard !overflow, target >= 0, target <= count else { return Int64(gorav_av_err_einval()) }
        offset = Int(target)
        return target
    }
}

/// C-interop trampoline surface (PROPOSED). Opaque is a RETAINED SnapshotAVIOBox.
/// r3 fix 2: nil opaque is invalid state -> EINVAL, never conflated with EOF.
enum SnapshotAVIOBridge {
    static let read: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32) -> Int32 = { opaque, buf, size in
        guard let opaque = opaque else { return gorav_av_err_einval() }
        return Unmanaged<SnapshotAVIOBox>.fromOpaque(opaque).takeUnretainedValue().readPacket(buf, size)
    }
    static let seek: @convention(c) (UnsafeMutableRawPointer?, Int64, Int32) -> Int64 = { opaque, off, whence in
        guard let opaque = opaque else { return Int64(gorav_av_err_einval()) }
        return Unmanaged<SnapshotAVIOBox>.fromOpaque(opaque).takeUnretainedValue().seek(off, whence)
    }
}

/// PROPOSED partial-open lifecycle for the snapshot route (r3 fix 3+4).
/// Every step's failure cleanup is explicit; order is load-bearing.
///
/// Buffer ownership per PUBLIC FFmpeg 8.0 source (COMPARISON ONLY, not ABI
/// proof; the exact installed 8.0.1 implementation needs its own pin):
/// aviobuf.c (L126-129) avio_context_free only av_freep(ps) - it frees the
/// context struct, NOT the buffer; avio.c (L630) the CURRENT s->buffer is freed
/// separately (av_freep), (L641) the context is freed. The r3 claim that
/// "avio_context_free frees the current buffer" was WRONG and is withdrawn.
/// Custom-IO cleanup is therefore explicit and ordered:
///   av_freep(&avio->buffer)   - frees whatever buffer is CURRENT at teardown
///   avio_context_free(&avio)  - frees the context struct only
/// The original handed-off buffer pointer must never be re-freed, stored for
/// later, or compared by us after handoff: if the provider replaced the buffer
/// internally (seekback/dynamic paths), the original pointer is stale. Whether
/// the installed 8.0.1 build matches this public-source behavior is an OPEN
/// pinned-source confirmation item.
///
/// Steps:
///   1. box = SnapshotAVIOBox(snapshot); opaque = Unmanaged.passRetained(box)
///   2. avioBuffer = av_malloc(avioBufferSize)
///      nil  => box.release(); fail (nothing else exists)
///   3. avio = avio_alloc_context(avioBuffer, size, write_flag=0, opaque,
///                                read=Bridge.read, write=nil, seek=Bridge.seek)
///      nil  => av_free(avioBuffer) [context never took ownership];
///             box.release(); fail
///   4. fmt = avformat_alloc_context()
///      nil  => av_freep(&avio->buffer) [CURRENT buffer, explicit];
///             avio_context_free(&avio) [context struct only];
///             box.release(); fail
///      else: fmt.pb = avio; fmt.flags |= AVFMT_FLAG_CUSTOM_IO
///            (provider must neither free nor reopen pb)
///   5. avformat_open_input(&fmt, NULL, NULL, NULL) - filename is NULL: no URL,
///      no path, no protocol layer, no reopen is possible on this route
///   6a. success: ownership transfers to the session; close order is:
///        avformat_close_input(&fmt)   (CUSTOM_IO: does NOT free avio)
///        av_freep(&avio->buffer)      (CURRENT buffer, explicit - see above)
///        avio_context_free(&avio)     (context struct only)
///        box.release()                (callback storage dead only AFTER this)
///   6b. open failure: on this route avformat_open_input does NOT free avio =>
///        av_freep(&avio->buffer); avio_context_free(&avio); if fmt non-nil
///        then avformat_free_context(fmt); box.release(). No other order valid.
///   7. cancel/interrupt: same GorAVInterruptSlot storage contract as the path
///      route (stable allocated storage; freed last, after close).
///
/// STATUS: CONDITIONAL DESIGN NOTES, not an integration. Nothing here is
/// wired into any accepted assembly, and no statement in this file claims the
/// snapshot route closes any gate. NOT_RUN: no step has executed. Every
/// constant (AVSEEK_SIZE, SEEK_*, AVFMT_FLAG_CUSTOM_IO), every signature, and
/// the buffer-ownership semantics above need the pinned 8.0.1 header/source
/// set + importer; all UNVERIFIED.
public enum SnapshotOpenLifecycleProposal {}
