import Foundation

/// App-side native-entry receipt view (lane: stereo/photon; architecture
/// facade r2). A pure value copy of the FULL synthesized-equality surface of
/// the package's NativeStereoEntryReceipt (GorAVEmbeddedShell), constructed
/// at the ONE existing package boundary (GorAVPlayerHost) so this seam's app
/// files no longer import gorav-internal modules. Nothing is recomputed,
/// defaulted or filtered: values arrive verbatim. r1's view dropped the
/// optional pixel-aspect pair; the original's synthesized Equatable compares
/// them (no custom == exists on receipt/evidence/identity - source-verified),
/// so unequal originals collapsed to equal views on the adapter's dedupe and
/// reseal path (Ops compiled witness, 3 collapse cases, debug+optimized).
/// r2 carries every original equality field; the adapter consumes none of
/// the pixel-aspect values, they exist for IDENTITY only.
struct StereoLookNativeEntryReceipt: Equatable {
    /// Source identity fence (package ActiveMediaInventoryIdentity surface).
    struct Identity: Equatable {
        let sourceID: String
        let session: UInt64
        let revision: UInt64
        let presentationEpoch: UInt64
    }
    /// Opened native-entry source facts only; never an applied-state snapshot.
    struct Evidence: Equatable {
        /// Mirrors the package PixelAspectOrigin cases (identity only).
        enum PixelAspectOrigin: String {
            case selectedStream
            case openedDecoder
        }
        let identity: Identity
        let selectedVideoIndex: Int
        let uncroppedWidth: Int
        let uncroppedHeight: Int
        let pixelAspect: Double?
        let pixelAspectOrigin: PixelAspectOrigin?
        let attachedPicture: Bool
    }
    let originalMediaID: String
    let playbackMediaID: String
    let prepared: Bool
    let evidence: Evidence
}
