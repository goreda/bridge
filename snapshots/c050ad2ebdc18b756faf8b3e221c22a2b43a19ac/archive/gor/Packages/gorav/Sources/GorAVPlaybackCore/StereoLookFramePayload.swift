import Foundation

/// Source-only handoff for one frame of one installed stereo stage.
/// The caller supplies its complete immutable frame identity as FrameKey.
/// Presenter composition must use FrameIdentity itself, not a projected tuple
/// or a string/debug key. No metadata or title source is inferred here.
public struct StereoLookFramePayload<FrameKey: Equatable> {
    public let frame: FrameKey
    public let stageGeneration: UInt64
    public let revision: ParameterBlockRevision
    public let packet: Data
    public enum Refusal: Error { case unrepresentableLane(String) }
    private init(frame: FrameKey, stageGeneration: UInt64,
                 revision: ParameterBlockRevision, packet: Data) {
        self.frame = frame; self.stageGeneration = stageGeneration
        self.revision = revision; self.packet = packet
    }

    /// Host controls and geometry are explicit inputs. No default caller state
    /// and no metadata-to-layout conversion is added at this boundary.
    /// A closed publication gate returns nil and leaves the block unchanged.
    public static func produce(block: inout LookParameterBlock,
                               frame: FrameKey, stageGeneration: UInt64,
                               session: StereoLookSession,
                               controls: StereoLookControls,
                               geometry: StereoLookGeometry,
                               tune: StereoLookTune) throws -> Self? {
        var working = block
        guard try StereoLookProducer.apply(to: &working, session: session,
                                           controls: controls, geometry: geometry,
                                           tune: tune) else { return nil }
        // The public block accepts finite Double values outside the wire
        // domain. Preflight EVERY lane locally before the ABI's narrowing
        // conversions; a foreign-stage lane must not trap or emit infinity.
        for parameter in LookParameterTable.all {
            let value = working.values[parameter.offset]
            let representable: Bool
            switch parameter.kind {
            case .floatUniform: representable = value.isFinite && Float(value).isFinite
            case .intUniform, .compileTimeDefine: representable = Int32(exactly: value) != nil
            }
            guard representable else { throw Refusal.unrepresentableLane(parameter.name) }
        }
        let payload = Self(frame: frame, stageGeneration: stageGeneration,
                           revision: working.revision,
                           packet: LookParameterABI.serialize(working))
        block = working
        return payload
    }

    /// Consumer must supply the actual admitted frame and installed stage.
    /// Only the ABI's validated shader words may be bound, never packet memory.
    public func consume(frame expected: FrameKey, stageGeneration installed: UInt64,
                        revision expectedRevision: ParameterBlockRevision) -> LookParameterABI.Block? {
        guard frame == expected, stageGeneration == installed,
              revision == expectedRevision else { return nil }
        guard case let .success(block) = LookParameterABI.consume(packet, revision: revision) else { return nil }
        return block
    }
}
