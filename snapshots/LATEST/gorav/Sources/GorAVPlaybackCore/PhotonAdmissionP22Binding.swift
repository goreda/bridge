import Foundation

// P29-LIVE-CONTROL (DR-0021, lane c): the wiring the queue assigns to this
// item - PhotonAdmission (DR-0018) bound to the typed P22 parameter writer
// (LookParameterBlock, DR-0015). A control write flows: Command ->
// admission fences -> apply -> typed lane set (exact value, no clamping,
// true only after the typed block accepted). Refused commands never reach
// the block. This is gorav-side model work only: no gor shell file and no
// photon-hud surface is involved (198o/OHAL-QUEUE reconciliation).

/// Applies admitted strength values to one named lane of a typed P22 block.
/// The typed writer is the sole writer of that lane: it refuses unknown
/// names, non-finite values and compile-time defines loudly, which the
/// admission layer surfaces as apply-failed.
public final class PhotonAdmissionP22Writer {
    public let lane: String
    public private(set) var block: LookParameterBlock

    public init(lane: String, block: LookParameterBlock = LookParameterBlock()) {
        self.lane = lane
        self.block = block
    }

    /// The admission apply contract: apply the exact value without clamping,
    /// return true only after host acceptance.
    public func apply(_ value: Double) -> Bool {
        if case .success = block.set(lane, value) { return true }
        return false
    }

    public func value() -> Double? { block.value(lane) }
}
