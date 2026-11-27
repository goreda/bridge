// Engine/CropProbeTransport.swift
// Typed crop-probe queries; owns NO mpv socket, client or command shape.
// Uses: Foundation
// Engine: mpv

import Foundation

// CropDetector keeps sampling intent, pacing and measurement. The socket
// path, the client and every mpv command shape live with the backend owner
// (MPVCommand.swift), which mints the typed CropProbeCapability this
// transport holds; the Picture layer receives its probes through the
// injected CropProbeFactory and never names the backend command owner. The
// surface and semantics are unchanged from the direct-IPC extraction this
// type began as; only the ownership moved. Semantics-preserving, not wire-byte-preserving:
// decoded commands equal the inlined calls they
// replaced, but JSONSerialization escapes "/" as "\/", so the three
// hand-interpolated screenshot-to-file sends differ on the wire only by
// slash escaping. Timeouts, call order and refusal results (nil exactly
// where an empty first reply object yielded nil) are unchanged. A true
// screenshot result means the command was built and handed to the socket;
// it is not write-success proof. mpv can finish writing the screenshot
// after the IPC reply, so the uniquely named screenshot file on disk is
// the evidence of capture, never this result.

/// How the composition root hands crop detection its probes: a typed factory
/// value the backend owner provides and the Picture layer only calls.
typealias CropProbeFactory = (_ path: String) -> CropProbeTransport

final class CropProbeTransport {
    private let capability: CropProbeCapability
    init(capability: CropProbeCapability) { self.capability = capability }
    /// Loaded-file duration in seconds; nil until the file reports one.
    func fileDuration(timeout: TimeInterval = 0.8) -> Double? { capability.fileDuration(timeout) }
    /// Seek-in-progress flag; nil while the reply carries no bool.
    func isSeeking(timeout: TimeInterval = 0.15) -> Bool? { capability.isSeeking(timeout) }
    /// Pause flag; nil while the reply carries no bool.
    func isPaused() -> Bool? { capability.isPaused() }
    /// Currently loaded path; nil while the reply carries no string.
    func currentPath() -> String? { capability.currentPath() }
    /// Playhead position in seconds; nil while the reply carries no number.
    func timePosition() -> Double? { capability.timePosition() }
    /// Screenshot format mpv is configured to write; "png" when unread.
    func screenshotFormat() -> String { capability.screenshotFormat() }
    /// Absolute seek; the caller's poll loop confirms completion.
    func seekAbsolute(seconds: Int) { capability.seekAbsolute(seconds) }
    /// Prepares the screenshot command without sending it; nil only when the
    /// backend refuses to build it. The prepared token is opaque here: this
    /// type can hold it and hand it back, never read or shape it. Callers
    /// that log before sending hold this, log, then sendPrepared.
    func screenshotCommand(to path: String) -> CropProbePreparedCommand? { capability.prepareScreenshot(path) }
    /// Hands a prepared command back to the backend and discards the reply:
    /// the screenshot file is the evidence of capture, not the socket result.
    func sendPrepared(_ command: CropProbePreparedCommand) { capability.sendPrepared(command) }
    /// Build + send in the old fire-and-forget order; the result is the
    /// build-and-hand-off signal the header describes, nothing more.
    @discardableResult
    func screenshotVideo(to path: String) -> Bool { capability.screenshotVideo(path) }
}
