// DVRPUL3Bridge.swift - L6 <-> L3 integration bridge.
// REBIND CHECK v4.3 (pack 2026-10-25, 4664af14, sha256 79d97547...0152):
// the ENTIRE bound surface (L3BorrowError 8 cases, L3CopyRefusal 7 incl.
// malformedNilData, L3CopyResult, L3FrameBorrow public fields,
// sideDataCopy body, withFrameLease signature) is BYTE-IDENTICAL to v4.2 -
// diff-verified. v4.3's changes are elsewhere: ptsTimeBaseNum/Den land on
// FrameObservation (metadata API), NOT on the borrow; copy caps are now
// 32 MiB per copy / 128 MiB aggregate (the lane's own 1 MiB bound stays
// tighter by design); HDR-gate/plane-copy and joint-seek work is not on
// this consumer path. No rebind change needed beyond this note.
// STATUS: AUTHORED-UNCOMPILED. L3 v4.3 is itself UNCOMPILED upstream -
// R2Y compile + safety review pending, runtime hold STAYS. This file exists so the ACTUAL call-site shape is reviewed
// before integration. Do not ship in swift build until L3 compiles and
// clears review. (No mock-FFmpeg typecheck is claimed anywhere in the lane:
// the swiftbinding harness compiles DVRPUSideData.swift only, never this
// file.)
//
// r4.3 rebind to v4.2 (actual source read, not interface assumption);
// v4.3 rebind check above:
// - withFrameLease signature IDENTICAL (handle/session/expectedPTS:
//   Int64/expectedPresentationEpoch: UInt64?/body) - verified by diff.
// - L3FrameBorrow public fields IDENTICAL (sessionEpoch, presentationEpoch,
//   streamIndex, handle, pts: Int64, ...); only isLive internals changed
//   (v4.1 critical-section fix, no consumer impact).
// - L3BorrowError: same 8 cases - exhaustive switch below unchanged.
// - L3CopyRefusal gains .malformedNilData: a side-data ENTRY with a nil
//   payload pointer is a malformed frame, typed-refused - it no longer
//   collapses to .absent (the architect's v4 present-but-NULL finding,
//   fixed producer-side in v4.2 source; UNVERIFIED until compile+review).
// - framePlaneCopySDR removal / framePlaneCopyDerived and the audio-seek /
//   L3AVCoordinator work are NOT on this consumer path (side data only;
//   per Main: derived previews are not for HDR/RPU consumption).
// - v4.2 note (Main): presentationEpoch wraps (&+=) - a generation pin,
//   not an alias proof; the optional pin below is a consistency check,
//   never an identity guarantee.
//
// r4.2 (R2Y actual-compile facts + architect nested-type finding):
// - Types are FULLY QUALIFIED against the actual v4 source: L3FrameBorrow,
//   L3BorrowError, L3CopyResult and L3CopyRefusal are NESTED inside
//   FFmpegSoftwareDecoder (FFmpegSoftwareDecoder.swift:1215-1345).
// - SessionID comes from GorAVCore (trunk Sources/GorAVCore/Boundary.swift)
//   - explicit import, no re-export assumption.
// - sideDataCopy returns NON-OPTIONAL L3CopyResult - no guard let.
// - expectedPTS is a REQUIRED Int64; the caller must refuse nil PTS before
//   calling (v4 typed-refuses missing/ mismatched PTS itself).
// - The kind conversion happens IN THE BODY: the Int32 constant is
//   converted to AVFrameSideDataType with a round-trip check AND compared
//   to the real AV_FRAME_DATA_DOVI_RPU_BUFFER on every call, not only at
//   startup.
// - All eight v4 L3BorrowError cases are switched exhaustively with their
//   actual associated values.

import Foundation
import CFFmpeg
import GorAVCore
import GorAVFFmpegAdapter

public enum DVRPUBridgeError: Error, Equatable {
    case kindConstantMismatch(lane: Int32, ffmpeg: UInt32) // fail closed at startup
    case leaseCancelled
    case foreignOrStaleSession
    case unavailableHandle
    case invalidLease
    case ptsMismatch(expected: Int64, actual: Int64)
    case missingFramePTS
    case presentationEpochMismatch(expected: UInt64, actual: UInt64)
    case reentrancy
}

extension FFmpegSoftwareDecoder.L3FrameBorrow: DVRPUFrameBorrow {
    public func dvFetchSideData(_ kind: Int32, maxBytes: Int) -> DVRPUSideDataFetch {
        // In-body conversion + binding (R2Y compile fact 4): the lane kind
        // must convert cleanly AND be exactly the RPU buffer kind, or the
        // fetch is refused typed - a caller can never relabel other bytes.
        let converted = AVFrameSideDataType(rawValue: UInt32(bitPattern: kind))
        guard converted.rawValue == UInt32(bitPattern: kind),
              converted == AV_FRAME_DATA_DOVI_RPU_BUFFER else {
            return .unavailable(reason: "non-RPU or unconvertible side-data kind requested")
        }
        // NON-OPTIONAL typed result (v4) - no guard let on the copy call.
        switch sideDataCopy(converted, maxBytes: maxBytes) {
        case .bytes(let copy):
            return .ok(copy)
        case .absent:
            // v4.2 typed absent is the PRODUCER'S claim. The v4 hole
            // (present-but-NULL also mapped here) is closed in the v4.2
            // SOURCE: nil payload now typed-refuses .malformedNilData.
            // v4.2 is UNCOMPILED + review-pending, so downstream still
            // must not treat .absent as verified proof of non-DV content -
            // only as "no RPU bytes delivered".
            return .absent
        case .refused(let why):
            switch why {
            case .oversize(let requested, let limit):
                return .refusedOversize(size: requested, limit: limit)
            case .malformedZeroLength:
                return .malformed(reason: "producer: zero-length side-data buffer")
            case .malformedNilData:
                // v4.2: side-data ENTRY exists, payload pointer nil - a
                // malformed frame, NEVER an absence claim.
                return .malformed(reason: "producer: side-data entry present but payload nil (v4.2 malformedNilData)")
            case .invalidated:
                return .unavailable(reason: "producer: borrow invalidated (post-turn access)")
            case .staleSession:
                return .unavailable(reason: "producer: stale session")
            case .badIndex(let requested, let available):
                return .unavailable(reason: "producer: bad index \(requested)/\(available)")
            case .aggregateBudgetExceeded(let used, let limit):
                return .unavailable(reason: "producer: aggregate budget \(used)>\(limit)")
            }
        }
    }
}

public enum DVRPUL3Bridge {
    /// Startup consistency check; call once at integration bring-up.
    public static func verifyKindConstant() throws {
        let real = AV_FRAME_DATA_DOVI_RPU_BUFFER.rawValue
        guard real == UInt32(bitPattern: dvRPUBufferSideDataKind) else {
            throw DVRPUBridgeError.kindConstantMismatch(lane: dvRPUBufferSideDataKind, ffmpeg: real)
        }
    }

    /// The actual v4 call-site shape: PTS identity REQUIRED (refuse a nil
    /// PTS BEFORE calling), optional presentation-epoch pin; outer await on
    /// the producer lease, all consumer reads synchronously inside the
    /// protected body.
    public static func read(decoder: FFmpegSoftwareDecoder, handle: UInt64,
                            session: SessionID, expectedPTS: Int64,
                            expectedPresentationEpoch: UInt64? = nil) async throws -> DVRPUReadResult {
        try verifyKindConstant()
        do {
            // Split form (r4.2 part 3): inside the producer turn ONLY the
            // typed bounded copy + identity capture run; hash + reference
            // parse run on the OWNED copy after the turn ends, keeping
            // consumer CPU off the producer's serial owner queue.
            let (fetch, ctx) = try await decoder.withFrameLease(handle: handle, session: session,
                                                    expectedPTS: expectedPTS,
                                                    expectedPresentationEpoch: expectedPresentationEpoch) { borrow in
                DVRPUSideData.syncFetch(borrow)
            }
            return DVRPUSideData.assemble(fetch, context: ctx)
        } catch let e as FFmpegSoftwareDecoder.L3BorrowError {
            switch e {
            case .cancelled: throw DVRPUBridgeError.leaseCancelled
            case .foreignOrStaleSession: throw DVRPUBridgeError.foreignOrStaleSession
            case .unavailableHandle: throw DVRPUBridgeError.unavailableHandle
            case .invalidLease: throw DVRPUBridgeError.invalidLease
            case .ptsMismatch(let expected, let actual):
                throw DVRPUBridgeError.ptsMismatch(expected: expected, actual: actual)
            case .missingFramePTS: throw DVRPUBridgeError.missingFramePTS
            case .presentationEpochMismatch(let expected, let actual):
                throw DVRPUBridgeError.presentationEpochMismatch(expected: expected, actual: actual)
            case .reentrancy: throw DVRPUBridgeError.reentrancy
            }
        }
    }
}
