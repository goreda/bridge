/// Measured playback quantities for one backend on one fixture.
/// A nil field means the backend could not measure that quantity; it is
/// emitted as `NA` and forces a non-pass parity status. Nil is never
/// silently replaced by zero.
public struct PlaybackProbe: Sendable {
    public let frames: Int?
    public let duration: Double?
    public let seekLanding: Double?
    public let avOffset: Double?

    public init(frames: Int? = nil, duration: Double? = nil, seekLanding: Double? = nil, avOffset: Double? = nil) {
        self.frames = frames
        self.duration = duration
        self.seekLanding = seekLanding
        self.avOffset = avOffset
    }
}
