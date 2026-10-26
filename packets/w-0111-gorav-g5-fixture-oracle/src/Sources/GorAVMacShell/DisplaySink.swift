#if canImport(AppKit) && canImport(CoreAudio)
import AppKit
import CoreImage
import GorAVPlaybackCore

/// NSWindow + layer-backed NSView display sink. mpv 0.41.0 renders through
/// CAMetalLayer (video/out/mac/metal_layer.swift, libplacebo shaders); this
/// probe shell takes the honest minimal path: yuv420p -> RGBA conversion on
/// CPU (BT.601 limited range), CGImage upload to the view's layer. The
/// Metal/libplacebo path is the documented follow-up (see README).
///
/// L1 REWORK v2 (architect PART1 finding 4 + PART2 finding 8):
///  - Telemetry is PER-INSTANCE. v1.4's global KitDisplayTelemetry let a new
///    window/run inherit the previous run's closedByUser and counters
///    (finding 8). A fresh DisplaySink starts closedByUser == false.
///  - show() returns typed acceptance and logs RECEIPTS: displayAttempt
///    BEFORE the upload decision, displayAccepted AFTER the layer contents
///    assignment, closeFenceSkip when fenced. frameShown in the pump is
///    logged only for accepted shows - never "shown" into a closed window.
public final class DisplaySink: NSObject, FrameSink, NSWindowDelegate, @unchecked Sendable {
    /// Verdict S5 rev5: the shared cancel/commit authority is an
    /// IMMUTABLE INIT-TIME input - there is NO adopt/re-adopt mutation
    /// surface at all; a sink is bound to ONE authority for its life.
    /// The on-actor upload fence consults it inside the commit section.
    private let cancelCommit: CancelCommit

    /// L1 wiring (off-RT: show() and the delegate are MainActor/main thread).
    public var ledger: TimingLedger?
    public var ledgerSession: UInt64 = 0
    public var ledgerGeneration: UInt64 = 0

    // Per-instance telemetry (MainActor-owned in practice: written from
    // windowShouldClose and the MainActor upload block).
    public private(set) var uploads = 0
    public private(set) var noPixels = 0
    public private(set) var visibleUploads = 0
    /// Set when the user closes the window mid-playback (windowShouldClose).
    /// Close intent is HONORED - the pump stops at the next frame and the run
    /// ends cleanly - never overridden by an invisible pump.
    public private(set) var closedByUser = false
    /// Uploads fenced ON the MainActor after a close intent (in-flight
    /// frames that passed the pump-side stop check).
    public private(set) var fenceSkips = 0
    public private(set) var closeIntentCount = 0

    /// User closed the window: record the intent and ALLOW the close. The
    /// video pump observes closedByUser and stops at the next frame; the run
    /// then tears down in order (closes, drain, stop) instead of pumping
    /// into an invisible window.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            self.closedByUser = true
            self.closeIntentCount += 1
        }
        // Close intent is recorded as its own event; the completed teardown
        // is a SEPARATE fence (architect cond. 3).
        ledger?.append(session: ledgerSession, generation: ledgerGeneration, segment: .pump,
                       subsystem: .video, kind: .closeIntent)
        return true
    }
    private let window: NSWindow
    private let view: NSView

    @MainActor public init(screenCheck: Void, commit: CancelCommit) {
        let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 640, height: 480),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "gorav probe"
        // v1.1: the v1 crash was a message to a zeroed-isa object from
        // CoreFoundation inside NSApplication.run (.ips disassembly). This
        // does NOT stop the window closing or its close machinery - it only
        // keeps window ownership single (sink) instead of shared with
        // AppKit's release-on-close. Close intent itself is handled in
        // windowShouldClose below.
        // v1.2: Swift name is isReleasedWhenClosed; v1.1 used the pre-Swift-3
        // name releasedWhenClosed, a hard error under Swift 6.1.2 (owner Mac run
        // 2026-10-25 10:52, result zip 261025-105308-gorav-play-v1-1-54146cf463fb).
        w.isReleasedWhenClosed = false
        let v = NSView(frame: w.contentView!.bounds)
        v.wantsLayer = true
        v.autoresizingMask = [.width, .height]
        w.contentView = v
        self.window = w
        self.view = v
        self.cancelCommit = commit
        super.init()
        // v1.3: the delegate assignment must follow super.init - v1.1 set it
        // before, a 'self used before super.init call' hard error under
        // Swift 6.1.2 (owner Mac run 2026-10-25 11:00, result zip
        // 261025-110025-gorav-play-v1-2-c4da222d0be4.zip).
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
    }

    /// The conversion lives in GorAVPlaybackCore.YUV420Converter (pure Swift,
    /// Linux-tested against an independent C oracle); the sink only uploads.

    @discardableResult
    public func show(_ frame: SourceFrame) async -> Bool {
        // Verdict S5 rev3 STRICT SINK: an unticketed show is ALWAYS a
        // typed refusal on this display - there is no bypass path and
        // NO default-accept when the authority is missing.
        await MainActor.run {
            self.fenceSkips += 1
            self.ledger?.append(session: self.ledgerSession, generation: self.ledgerGeneration,
                                segment: .pump, subsystem: .video, kind: .closeFenceSkip,
                                pts: frame.ptsSeconds, note: "unticketedShowRefused")
        }
        return false
    }
    /// r3-rev2 S5 (architect-ruling shape): the pump's immutable
    /// per-frame admission ticket travels with the frame and is
    /// validated ON the MainActor immediately before the contents
    /// assignment. After a cancel/seek ACK, NO further commit lands
    /// (mayFinish refuses) - an old-revision frame can never become
    /// visible after a seek. The check and the assignment serialize on
    /// this actor, so no ACK can interleave between them.
    @discardableResult
    public func show(_ frame: SourceFrame, admission: CancelCommit.AdmissionTicket) async -> Bool {
        await showImpl(frame, ticket: admission)
    }
    private func showImpl(_ frame: SourceFrame, ticket: CancelCommit.AdmissionTicket) async -> Bool {
        // The shell's SourceFrame must carry pixels: see ShellFrameSource,
        // which wraps the decoder and attaches plane copies + strides.
        guard let px = frame.pixelPayload else { await MainActor.run { self.noPixels += 1 }; return false }
        let cg = px.bytes.withUnsafeBytes { raw -> CGImage? in
            guard let base = raw.baseAddress else { return nil }
            guard let data = CFDataCreate(nil, base.assumingMemoryBound(to: UInt8.self), raw.count),
                  let provider = CGDataProvider(data: data) else { return nil }
            return CGImage(width: px.width, height: px.height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: px.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        return await MainActor.run {
            // Finding 4: typed ATTEMPT receipt before the upload decision.
            self.ledger?.append(session: self.ledgerSession, generation: self.ledgerGeneration,
                                segment: .pump, subsystem: .video, kind: .displayAttempt,
                                pts: frame.ptsSeconds)
            // Verdict S5 rev5: the authority is an immutable init-time
            // input - a foreign ticket is refused typed by the issuer
            // binding inside commitFrame, never default-accepted.
            let commit = self.cancelCommit
            // Verdict S5 CONTRACT (rev3): ACK = NO FURTHER COMMIT, and
            // the check/consume/assignment are ONE critical section on
            // the commit authority (CancelCommit.commitFrame): an
            // external cancel/seek ACK BLOCKS until the contents
            // assignment completes - no ACK can interleave between the
            // check and layer.contents. The close-intent fence is
            // evaluated INSIDE the same section as `permit`. The ticket
            // is consumed only when the assignment runs, so a fenced
            // frame never burns its ticket.
            guard let image = cg, let layer = self.view.layer else { self.noPixels += 1; return false }
            let committed = commit.commitFrame(ticket,
                framePTS: frame.ptsSeconds, frameDigest: frame.digest,
                permit: { UploadFence.mayUpload(closeIntent: self.closedByUser) },
                assign: {
                    layer.contents = image
                    self.uploads += 1
                    if self.window.isVisible && self.window.windowNumber > 0 {
                        self.visibleUploads += 1
                    }
                })
            guard committed else {
                self.fenceSkips += 1
                self.ledger?.append(session: self.ledgerSession, generation: self.ledgerGeneration,
                                    segment: .pump, subsystem: .video, kind: .closeFenceSkip,
                                    pts: frame.ptsSeconds)
                return false
            }
            // Finding 4: typed ACCEPTED receipt after the assignment.
            // NOTE: this is an upload acceptance, NOT a confirmed on-screen
            // present - the CPU/CGImage path has no present callback.
            self.ledger?.append(session: self.ledgerSession, generation: self.ledgerGeneration,
                                segment: .pump, subsystem: .video, kind: .displayAccepted,
                                pts: frame.ptsSeconds)
            return true
        }
    }
}
#endif
