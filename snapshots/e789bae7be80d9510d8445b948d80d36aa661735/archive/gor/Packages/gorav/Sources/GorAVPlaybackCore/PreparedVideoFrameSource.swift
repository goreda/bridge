import Foundation

/// A staged first frame plus subsequent decoded frames in the existing film
/// clock domain. Payloads/PTS spacing are preserved; this never invents frames.
public actor PreparedVideoFrameSource: FrameSource {
    private let source: FrameSource
    private var first: SourceFrame?
    private let offset: Double
    public init(source: FrameSource, first: SourceFrame, sourceStart: Double, filmStart: Double) {
        self.source = source; self.first = first; self.offset = filmStart - sourceStart
    }
    public func nextEvent() async -> SourceEvent {
        let event: SourceEvent
        if let frame = first { first = nil; event = .frame(frame) }
        else { event = await source.nextEvent() }
        guard case .frame(let frame) = event else { return event }
        let mapped = frame.ptsSeconds + offset
        guard mapped.isFinite, frame.durationSeconds.isFinite, frame.durationSeconds > 0 else {
            return .failed(-94)
        }
        return .frame(SourceFrame(ptsSeconds: mapped, durationSeconds: frame.durationSeconds,
            digest: frame.digest, pixelPayload: frame.pixelPayload))
    }
}
