// AUTHORED_NEW source-only observation values, NOT_COMPILED / NOT_RUN.
import Foundation

public struct PlaneObservation: Equatable, Sendable {
    public let index: Int
    public let rowBytes: Int
    public let rows: Int
    public let stride: Int
    public let readableExtent: Int
    public let containingBufferExtent: UInt
    public let planeOffset: UInt
    public let coverageVerified: Bool
}
public struct FrameObservation: Equatable, Sendable {
    public let sessionEpoch: UInt64
    public let handle: UInt64
    public let selectedStreamIndex: Int32
    public let pixelFormat: String
    public let width: Int
    public let height: Int
    public let pts: Int64?
    public let duration: Int64
    public let planes: [PlaneObservation]
}
public enum ObservationRefusal: Error, Equatable, Sendable {
    case foreignOrStaleSession
    case releasedHandle
    case unavailableHandle
    case invalidLease
    case unavailableMetadata
    case unboundedPlane
    case traceUnavailable
}
/// Logical invocation evidence only. NOT proof of native free, refcount or leaks.
/// absent = no fully initialized custom IO owner at this cleanup site.
/// called = close invoked but return not yet observed; completed = close returned.
public enum CustomIOLogicalTeardown: String, Equatable, Sendable {
    case absent, called, completed
}
public enum SessionTraceKind: String, Sendable {
    case selectedStream, demuxReadEOF, nilFlushSendResult, receiveEOF
    case terminalEOF, terminalInterrupted, terminalFailed, closed
    case customIOAbsent, customIOCloseCalled, customIOCloseCompleted
}
public struct SessionTraceRecord: Equatable, Sendable {
    public let sequence: UInt64
    public let kind: SessionTraceKind
    public let providerResult: Int32?
    public let selectedStreamIndex: Int32
}
public struct SessionTraceSnapshot: Equatable, Sendable {
    public let sessionEpoch: UInt64
    public let capacity: Int
    public let overflowed: Bool
    public let customIOLogicalTeardown: CustomIOLogicalTeardown
    public let records: [SessionTraceRecord]
    // No success assertion. Any consumer must refuse success on overflow.
}
