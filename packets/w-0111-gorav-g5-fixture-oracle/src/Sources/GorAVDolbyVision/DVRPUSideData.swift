// DVRPUSideData.swift - gorav block 78 L6: RPU via FFmpeg side data (primary path).
// Base: gorav trunk main c5f06bd (v1.4 exact base, FFmpeg n8.0.1 @ 894da5ca).
// STATUS r4.1: TYPECHECKED + LIVE-RUN on Linux Swift 6.0.3 against the real
// GorAVDVRPU C core and a fake borrow (dovi-selftest/swift, clearly marked).
// NOT YET RUN against the real L3 decoder: L3 v4 is UNCOMPILED upstream
// (R2Y compile + safety review pending; runtime hold stays). Mac build via
// swift build on the trunk is STILL UNRUN.
//
// r4 (architect review part 1/2 findings 1-2):
// - Typed producer fetch: a nil/absent conflation can no longer classify a
//   producer error or an oversize refusal as "non-DV content". .absent is
//   emitted ONLY when the producer proves absence; L3 v3.1's sideDataCopy
//   cannot prove it, so the v3.1 bridge maps nil -> .unavailable.
// - No precondition traps: a nonconforming producer returning more than the
//   bound gets a typed refusal, never a crash.
// - Kind binding: the RPU side-data kind is a pinned constant of this
//   module, not a caller-supplied Int32, so no caller can relabel non-RPU
//   bytes as an RPU receipt. The integration bridge checks the constant
//   against the real AVFrameSideDataType at startup.
// - Semantic receipt: the observation carries the C core's header-parse
//   outcome (not just bytes), so .ok is a parsed-RPU receipt, and parse
//   failure degrades the receipt instead of hiding it.
// Consumer scope (unchanged): never sees an AVFrame pointer, never wraps
// pointer+UInt64, hashes the OWNED copy after it leaves the lease, stores
// nothing borrowed. The borrow protocol does NOT prove producer
// enforcement - budget/scope/token/stream/PTS identity enforcement remains
// L3 v4 producer work.

import Foundation
import GorAVDVRPU

/// AV_FRAME_DATA_DOVI_RPU_BUFFER in the pinned FFmpeg n8.0.1 @ 894da5ca
/// (libavutil/frame.h enum position 23), VERIFIED by a compiled assert
/// against the pinned headers (dovi-selftest/swift/kindcheck.c output in
/// TESTLOG). The integration bridge MUST check this against the real
/// CFFmpeg constant at startup (see DVRPUL3Bridge.swift).
public let dvRPUBufferSideDataKind: Int32 = 23

/// Hard bound on one RPU side-data buffer. RPUs are typically 150-400 B
/// (dolby_vision crate comment); 1 MiB is deliberately generous and turns
/// anything larger into a typed refusal instead of an unbounded copy.
/// This is the LANE's consumer bound, independent of producer copy caps
/// (L3 v4.3: 32 MiB per copy, 128 MiB aggregate per borrow) - the tighter
/// bound wins on this path by design.
public let dvRPUMaxBytes: Int = 1_048_576

/// Standard FNV-1a 64. Receipt hash only, NOT a cryptographic integrity
/// claim. Matches DVRPUAnnexB.c exactly (pinned by standard vectors).
@inline(__always)
public func dvFnv1a64(_ bytes: [UInt8]) -> UInt64 {
    var h: UInt64 = 14695981039346656037
    for b in bytes { h ^= UInt64(b); h &*= 1099511628211 }
    return h
}

/// Typed producer fetch result. `.absent` requires the producer to PROVE
/// absence; anything else that failed is `.unavailable`, never `.absent`.
public enum DVRPUSideDataFetch: Sendable, Equatable {
    case absent                                     // producer's typed absence CLAIM; v4.2 closes the present-but-NULL hole at the type level (new .malformedNilData refusal), but v4.2 is UNCOMPILED + review-pending - still not verified proof of non-DV content
    case ok([UInt8])                                // owned bounded copy
    case refusedOversize(size: Int, limit: Int)     // producer policy refusal
    case malformed(reason: String)                  // producer-detected inconsistency (e.g. zero-length)
    case unavailable(reason: String)                // lease invalidated/stale/budget/error, or absence unproven
}

/// The slice of the producer borrow the consumer is allowed to use:
/// producer-reported frame identity + ONE typed bounded fetch. The
/// integration call site conforms the real borrow (L3 v4+) to this
/// protocol; lane tests use a fake. The consumer passes the pinned
/// dvRPUBufferSideDataKind, never a caller value.
/// Identity shape matches the L3 v4 borrow: PTS is REQUIRED (a frame
/// without PTS has no identity - v4 typed-refuses .missingFramePTS), and
/// the presentation generation pins against seek/fallback.
public protocol DVRPUFrameBorrow {
    var sessionEpoch: UInt64 { get }
    var presentationEpoch: UInt64 { get }
    var streamIndex: Int { get }
    var handle: UInt64 { get }
    var pts: Int64 { get }
    func dvFetchSideData(_ kind: Int32, maxBytes: Int) -> DVRPUSideDataFetch
}

/// Semantic status of the received bytes, from the lane C core's
/// reference-verified header parse. A receipt is never "just bytes".
public enum DVRPUHeaderStatus: Sendable, Equatable {
    case parsed(profileGuess: UInt32) // header parse OK; framing-level guess, NOT a config-record claim
    case malformed
    case crcMismatch
    case semanticRejected             // framed + CRC-valid, reference validate() rejects
    case parseUnavailable(reason: String) // parse failed on RESOURCES (alloc), not content
}

/// Immutable per-frame RPU receipt. Value type, Sendable. Invariants:
/// bytes.count <= dvRPUMaxBytes (enforced by the typed constructor);
/// fnv1a64 is over the OWNED bytes after copy.
public struct DVRPUObservation: Sendable, Equatable {
    public let bytes: [UInt8]
    public let byteCount: Int
    public let fnv1a64: UInt64
    public let context: DVRPUContext
    public let headerStatus: DVRPUHeaderStatus
    /// Typed construction: oversize input yields nil, never a trap.
    /// INTERNAL on purpose (r4.2 part 3): the header status is COMPUTED by
    /// the lane's own parse over these exact bytes; there is no public way
    /// to attach a "parsed" claim to arbitrary bytes. Consumers READ
    /// headerStatus - an .ok observation with a non-.parsed status is a
    /// degraded receipt and MUST be treated as such. A parsed RPU header is
    /// NOT reshaping/DM/config-record capability validation.
    init?(bytes: [UInt8], context: DVRPUContext) {
        guard bytes.count <= dvRPUMaxBytes else { return nil }
        self.bytes = bytes
        self.byteCount = bytes.count
        self.fnv1a64 = dvFnv1a64(bytes)
        self.context = context
        self.headerStatus = DVRPUSideData.parseStatus(of: bytes)
    }
    /// True iff the lane's reference-verified parse fully validated the
    /// fixed HEADER SUBSET of THESE bytes (framing + CRC + the reference's
    /// header validate arms). SCOPE LIMIT (architect r4.3): this is NOT
    /// full DV validity - rpu_data_mapping, NLQ and DM metadata are
    /// NOT_PARSED, reshaping is not validated, FEL is out of scope, and a
    /// parsed header is not a playback/config-record claim. False on any
    /// degraded receipt (malformed/crcMismatch/semanticRejected/
    /// parseUnavailable) - such an observation proves byte delivery, never
    /// DV content validity.
    public var isHeaderParsed: Bool {
        if case .parsed = headerStatus { return true }
        return false
    }
}

/// Producer-reported identity of the frame the RPU came from. doviProfile
/// stays `.unknown` until the shim exposes the DV configuration record
/// (dovi_meta.h, trunk-owner patch); the header-parse profile guess lives
/// separately in headerStatus and is NOT a config-record claim.
public struct DVRPUContext: Sendable, Equatable {
    public enum Profile: Sendable, Equatable { case unknown; case value(UInt32) }
    public let sessionEpoch: UInt64
    public let presentationEpoch: UInt64
    public let streamIndex: Int
    public let handle: UInt64
    public let pts: Int64 // producer-reported; v4 requires PTS identity
    public let doviProfile: Profile
}

/// Typed result of reading RPU side data from one decoded frame.
public enum DVRPUReadResult: Sendable, Equatable {
    /// Producer's typed absence claim. CAVEAT (architect, L3 v4.2): the
    /// v4.2 SOURCE closes the present-but-NULL->absent hole at the type
    /// level (nil payload is now the typed refusal .malformedNilData, a
    /// malformed frame), but v4.2 is UNCOMPILED and Main's peer review is
    /// pending. Until that verifies, treat .absent as "no RPU bytes
    /// delivered", not proof of non-DV content.
    case absent
    /// Side data present but empty or inconsistent.
    case corrupt(reason: String)
    /// RPU buffer exceeds dvRPUMaxBytes; typed refusal, never a truncation.
    case rejectedOversize(size: Int, limit: Int)
    /// Producer errored, or could not prove absence (L3 v3.1 nil). Distinct
    /// from .absent: never tells the caller "this is non-DV content".
    case unavailable(reason: String)
    /// Full, bounded, owned copy with identity + semantic parse status.
    /// `.ok` means "bytes were delivered and copied within bound" - it is
    /// NOT a DV-verified-content claim. An .ok observation whose
    /// headerStatus is not .parsed (malformed/CRC/semantic/resource) is a
    /// DEGRADED receipt; consumers MUST check headerStatus (or
    /// observation.isHeaderParsed) before treating the bytes as a valid RPU.
    case ok(DVRPUObservation)
}

public enum DVRPUSideData {
    /// The ONLY work done inside the producer's protected turn: the
    /// producer's own bounded typed copy plus a capture of the
    /// producer-reported identity. No hashing, no parsing - the producer's
    /// serial owner queue is not the place for consumer CPU (bounded but
    /// non-RT latency consideration, r4.2 part 3).
    public static func syncFetch<B: DVRPUFrameBorrow>(_ borrow: B) -> (DVRPUSideDataFetch, DVRPUContext) {
        let ctx = DVRPUContext(sessionEpoch: borrow.sessionEpoch,
                               presentationEpoch: borrow.presentationEpoch,
                               streamIndex: borrow.streamIndex,
                               handle: borrow.handle,
                               pts: borrow.pts,
                               doviProfile: .unknown)
        return (borrow.dvFetchSideData(dvRPUBufferSideDataKind, maxBytes: dvRPUMaxBytes), ctx)
    }

    /// Assemble the typed result from an owned fetch + captured identity.
    /// Runs OUTSIDE the producer turn (bridge) or inline (tests).
    /// INTERNAL (r4.3, architect): assembly from raw parts is not a public
    /// capability - a public assemble(fetch, context) would let any caller
    /// pair arbitrary bytes with a fabricated identity and present the
    /// result with the same shape as a producer-delivered receipt. The
    /// trusted boundary is the real bridge: only this module assembles, and
    /// the only public entry is syncRead(borrow), where provenance is
    /// exactly the borrow passed. A caller-conformed fake borrow is the
    /// CALLER'S OWN claim - the observation honestly reports hash + parse
    /// over the delivered bytes, it cannot and does not prove producer
    /// provenance. Only borrows vended by DVRPUL3Bridge.read from a real
    /// FFmpegSoftwareDecoder carry that.
    static func assemble(_ fetch: DVRPUSideDataFetch, context: DVRPUContext) -> DVRPUReadResult {
        switch fetch {
        case .absent:
            return .absent
        case .refusedOversize(let size, let limit):
            return .rejectedOversize(size: size, limit: limit)
        case .malformed(let reason):
            return .corrupt(reason: reason)
        case .unavailable(let reason):
            return .unavailable(reason: reason)
        case .ok(let copy):
            guard !copy.isEmpty else { return .corrupt(reason: "zero-length side-data buffer") }
            guard let obs = DVRPUObservation(bytes: copy, context: context) else {
                return .rejectedOversize(size: copy.count, limit: dvRPUMaxBytes)
            }
            return .ok(obs)
        }
    }

    /// Convenience: fetch + assemble in one call - the ONLY public read
    /// entry. Provenance equals the borrow passed (see assemble): tests use
    /// a fake borrow, production uses borrows vended by DVRPUL3Bridge.read.
    /// Lease integrations (the bridge, same module) use the internal split
    /// form so the parse/hash stay off the producer's turn.
    public static func syncRead<B: DVRPUFrameBorrow>(_ borrow: B) -> DVRPUReadResult {
        let (fetch, ctx) = syncFetch(borrow)
        return assemble(fetch, context: ctx)
    }

    /// The lane's own reference-verified header parse - the ONLY source of
    /// a .parsed status. -5 (allocation failure) is a resource class, never
    /// reported as content malformation.
    static func parseStatus(of bytes: [UInt8]) -> DVRPUHeaderStatus {
        bytes.withUnsafeBufferPointer { buf in
            var h = GorAVDVRPUHeader()
            guard let base = buf.baseAddress else { return .malformed }
            switch gorav_dv_parse_rpu_header(base, buf.count, &h) {
            case 0:  return .parsed(profileGuess: UInt32(gorav_dv_guess_profile(&h)))
            case -2: return .crcMismatch
            case -4: return .semanticRejected
            case -5: return .parseUnavailable(reason: "parser allocation failure")
            case -6: return .parseUnavailable(reason: "lane caller bug: invalid parse arguments") // unreachable via public API (bytes are non-null); kept for exhaustiveness
            default: return .malformed
            }
        }
    }
}
