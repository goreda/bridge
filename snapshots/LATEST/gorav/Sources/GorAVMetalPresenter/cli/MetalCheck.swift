// L2 presenter (block 78d), revision 5 (architect r6 findings 1-6 + L8 r7 seam):
// gorav-metal-check witness matrix. Every section states what it PROVES;
// offscreen readback is offscreen evidence, never scanout proof; the
// owner's visual/audio verdict stays the display evidence (78c).
// A per-frame readback identity, both sinks (GPU witness EVERY frame)
// B orientation probe              C REAL window resize + drawable geometry
// D fullscreen round-trip receipts E seal fence / QUEUED race / stale /
//   recreate / in-flight stress    G invalid-input + byte-budget rejections
// H decode-error cleanup witness   F real-fixture ordered parity vs v1.4
// I HDR contract validation        J 16F upload + float readback path
// K overlay identity/geometry/space witnesses   R renegotiate epoch witness
// AUTHORED NEW 2026-10-25, L2 lane.
#if canImport(AppKit) && canImport(CoreAudio) && canImport(Metal)
import AppKit
import CryptoKit
import GorAVPlaybackCore
import GorAVMacShell
import GorAVMetalPresenter

private func sha(_ bytes: [UInt8]) -> String {
    SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
}
private func pass(_ name: String) { print("{\"section\":\"\(name)\",\"verdict\":\"PASS\"}") }
private func fail(_ name: String, _ why: String) -> Never {
    print("{\"section\":\"\(name)\",\"verdict\":\"FAIL\",\"why\":\"\(why)\"}")
    Foundation.exit(1)
}

/// Unique, asymmetric, non-opaque frame: index embedded, x/y distinguishable
/// (order/swap detectable), alpha varies per index (not all-opaque).
private func uniqueFrame(_ k: Int, w: Int, h: Int) -> SourceFrame {
    var b = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let o = (y * w + x) * 4
        b[o] = UInt8((x & 0xFF) ^ (k & 0xFF))         // r: x-dominant + index
        b[o + 1] = UInt8((y & 0xFF))                   // g: y-dominant
        b[o + 2] = UInt8((x / 2 + y / 2 + k) & 0xFF)   // b: diagonal + index
        b[o + 3] = UInt8(192 + (k % 64))               // a: varies, non-opaque
    } }
    return SourceFrame(ptsSeconds: Double(k) * 0.04, durationSeconds: 0.04,
                       digest: "script-\(k)",
                       pixelPayload: PixelPayload(width: w, height: h, bytes: b))
}

final class CheckAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct MetalCheckMain {
    static let delegate = CheckAppDelegate()
    static func main() {
        setbuf(stdout, nil)
        let args = CommandLine.arguments
        // Flags/positions validated BEFORE use; no traps on
        // negative/NaN/inf/missing values.
        guard args.count >= 3, ["play", "matrix"].contains(args[1]), !args[2].isEmpty else {
            FileHandle.standardError.write(Data("usage: gorav-metal-check play|matrix <avPath> [holdSeconds]\n".utf8))
            Foundation.exit(2)
        }
        let mode = args[1], clip = args[2]
        var hold = 4.0
        if args.count >= 4 {
            guard let h = Double(args[3]), h.isFinite, h >= 0, h <= 3600 else {
                FileHandle.standardError.write(Data("holdSeconds must be finite in [0,3600]\n".utf8))
                Foundation.exit(2)
            }
            hold = h
        }
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        Task { @MainActor in
            do {
                switch mode {
                case "play":
                    let receipt = try await GorAVMetalShellApp.runMuxed(path: clip)
                    print("gorav play-metal: windowOnScreen=\(MetalPresenterTelemetry.visibleUploads > 0 ? 1 : 0)")
                    let eh = MetalPresenterTelemetry.closedByUser ? 0.0 : hold
                    if eh > 0 {
                        print("gorav play-metal: playback finished, holding window \(Int(eh))s")
                        try? await Task.sleep(nanoseconds: UInt64(eh * 1_000_000_000))
                    }
                    _ = receipt
                default:
                    try await runMatrix(clip: clip)
                }
            } catch {
                FileHandle.standardError.write(Data("GORAV_METAL_CHECK_ERROR: \(error)\n".utf8))
                Foundation.exit(1)
            }
            Foundation.exit(0)
        }
        app.run()
    }

    @MainActor static func expectThrow<T>(_ section: String, _ want: SurfaceContract.NegotiationError,
                                        _ body: () throws -> T) {
        do {
            _ = try body()
            fail(section, "expected \(want), got success")
        } catch let e as SurfaceContract.NegotiationError {
            guard e == want else { fail(section, "expected \(want), got \(e)") }
        } catch {
            fail(section, "expected \(want), got \(error)")
        }
    }

    @MainActor static func runMatrix(clip: String) async throws {
        let W = 640, H = 360, N = 12

        // I: HDR contract validation (pure Swift, no GPU; r2 finding 4).
        let sig = GorAVMetalPresenter.SourceSignal(transfer: .pq, primaries: .bt2020,
                               masteringMinNits: 0.005, masteringMaxNits: 1000,
                               maxCLL: 1000, maxFALL: 400)
        func mk(fmt: SurfaceContract.PixelFormat, tr: SurfaceContract.Transfer,
                pr: SurfaceContract.Primaries, s: GorAVMetalPresenter.SourceSignal?, edr: Bool,
                rw: Double = 100, mif: Int = 3,
                intent: SurfaceContract.OutputIntent = .nativeSDR) -> SurfaceContract {
            SurfaceContract(pixelFormat: fmt, transfer: tr, primaries: pr,
                            alphaSpace: .premultiplied, origin: .topLeftRowFirst,
                            referenceWhiteNits: rw, sourceSignal: s, outputIntent: intent,
                            wantsEDR: edr, framebufferOnly: !edr, drawableWidth: 0,
                            drawableHeight: 0, maxInFlight: mif)
        }
        expectThrow("I", .edrRequiresFloatFormat) { try mk(fmt: .sdrRGBA8, tr: .sRGB, pr: .bt709, s: nil, edr: true).validated() }
        expectThrow("I", .hdrWithoutSourceSignal) { try mk(fmt: .edrRGBA16F, tr: .linear, pr: .bt2020, s: nil, edr: true, intent: .nativeHDR).validated() }
        expectThrow("I", .edrSurfaceWithoutEDR) { try mk(fmt: .edrRGBA16F, tr: .linear, pr: .bt2020, s: sig, edr: false, intent: .nativeHDR).validated() }
        expectThrow("I", .invalidOutputIntent) { try mk(fmt: .sdrRGBA8, tr: .sRGB, pr: .bt709, s: sig, edr: false).validated() }
        expectThrow("I", .invalidOutputIntent) { try mk(fmt: .edrRGBA16F, tr: .linear, pr: .bt2020, s: sig, edr: true, intent: .tonemappedHDRtoSDR).validated() }
        expectThrow("I", .hdrWithoutSourceSignal) { try mk(fmt: .sdrRGBA8, tr: .sRGB, pr: .bt709, s: nil, edr: false, intent: .tonemappedHDRtoSDR).validated() }
        expectThrow("I", .invalidReferenceWhite) { try mk(fmt: .sdrRGBA8, tr: .sRGB, pr: .bt709, s: nil, edr: false, rw: 0).validated() }
        expectThrow("I", .invalidReferenceWhite) { try mk(fmt: .sdrRGBA8, tr: .sRGB, pr: .bt709, s: nil, edr: false, rw: .nan).validated() }
        expectThrow("I", .invalidSourceSignal) {
            try mk(fmt: .edrRGBA16F, tr: .pq, pr: .bt2020,
                   s: GorAVMetalPresenter.SourceSignal(transfer: .pq, primaries: .bt2020, masteringMinNits: 1000, masteringMaxNits: 5),
                   edr: true, intent: .nativeHDR).validated()
        }
        expectThrow("I", .invalidSourceSignal) {
            try mk(fmt: .edrRGBA16F, tr: .pq, pr: .bt2020,
                   s: GorAVMetalPresenter.SourceSignal(transfer: .pq, primaries: .bt2020, maxCLL: .nan), edr: true, intent: .nativeHDR).validated()
        }
        expectThrow("I", .unsupportedColorSpaceMapping) { try mk(fmt: .edrRGBA16F, tr: .pq, pr: .bt709, s: sig, edr: true, intent: .nativeHDR).validated() }
        expectThrow("I", .inFlightOutOfRange) { try mk(fmt: .sdrRGBA8, tr: .sRGB, pr: .bt709, s: nil, edr: false, mif: 0).validated() }
        // Valid contracts: native HDR PQ, native HDR linear EDR, and
        // tone-mapped HDR-source -> SDR output (L5 r5 (c)) all validate.
        _ = try mk(fmt: .edrRGBA16F, tr: .pq, pr: .bt2020, s: sig, edr: true, intent: .nativeHDR).validated()
        _ = try mk(fmt: .edrRGBA16F, tr: .linear, pr: .bt2020, s: sig, edr: true, intent: .nativeHDR).validated()
        let tm = try mk(fmt: .sdrRGBA8, tr: .sRGB, pr: .bt709, s: sig, edr: false, intent: .tonemappedHDRtoSDR).validated()
        guard tm.sourceSignal != nil, !tm.wantsEDR else { fail("I", "tonemapped intent lost provenance") }
        pass("I")

        // J: 16F upload + REAL float readback (r2 findings 4/5). Renderer
        // only - no window needed; offscreen target matches the contract.
        do {
            let c16 = try mk(fmt: .edrRGBA16F, tr: .linear, pr: .bt2020, s: sig, edr: true, intent: .nativeHDR).validated()
            let r16 = try MetalRenderer(contract: c16, outputTransform: .identity)
            r16.beginSession(sessionID: "matrix-J", generation: 900)
            let id16 = FrameIdentity(sessionID: "matrix-J", sessionGeneration: 900,
                                     sequence: 1, surfaceRevision: 0, ptsSeconds: 0)
            // RGBA8 upload on the 16F surface: typed rejection, never reinterpret.
            if case .rejectedUnsupportedVariant = r16.upload(rgba: [UInt8](repeating: 0, count: 8 * 4 * 4),
                                                             width: 8, height: 4, identity: id16) {} else {
                fail("J", "rgba8 upload on 16F surface not typed-rejected")
            }
            // 16F upload: half-float words for 0.0/0.5/1.0/2.0 patterns.
            let halves: [UInt16] = [0x0000, 0x3800, 0x3C00, 0x4000]
            var payload = [UInt16](repeating: 0, count: 8 * 4 * 4)
            for i in 0..<(8 * 4) { for ch in 0..<4 { payload[i * 4 + ch] = halves[(i + ch) % 4] } }
            guard case .ok(let upSha) = r16.upload16F(halfWords: payload, width: 8, height: 4, identity: id16) else {
                fail("J", "16F upload rejected")
            }
            // NaN/Inf half words are a typed rejection (r3 finding 6).
            var nanPayload = payload
            nanPayload[0] = 0x7C00 // +Inf
            let id16b = FrameIdentity(sessionID: "matrix-J", sessionGeneration: 900,
                                      sequence: 2, surfaceRevision: 0, ptsSeconds: 0.04)
            if case .rejectedNonFinitePayload = r16.upload16F(halfWords: nanPayload, width: 8, height: 4, identity: id16b) {} else {
                fail("J", "NaN/Inf 16F payload not typed-rejected")
            }
            // Sequence regress is a typed rejection (r3 finding 2).
            if case .rejectedSequenceRegress = r16.upload16F(halfWords: payload, width: 8, height: 4, identity: id16) {} else {
                fail("J", "sequence regress not typed-rejected")
            }
            // 8-bit readback on a 16F contract is a typed failure.
            if r16.readbackNative(identity: id16) != nil {
                fail("J", "8-bit readback on 16F contract should fail typed")
            }
            guard let rb = r16.readbackNative16F(identity: id16) else {
                fail("J", "16F readback unavailable")
            }
            guard rb.sha256 == upSha, rb.pixelFormat == .edrRGBA16F,
                  rb.identity.leaseKey == id16.leaseKey else {
                fail("J", "float readback digest != upload digest (16F path broken)")
            }
            print("{\"section\":\"J\",\"floatReadbackSha256\":\"\(rb.sha256)\",\"proves\":\"16F upload + offscreen float readback identity, offscreen evidence\"}")
        }
        pass("J")

        // H: decode-error cleanup witness. A bogus path must throw, and the
        // structured cleanup must leave the process able to run the real
        // fixture afterwards (proved by F passing after this).
        do {
            _ = try await GorAVMetalShellApp.runMuxed(path: "/nonexistent/gorav-no-such-clip.mov")
            fail("H", "bogus path did not throw")
        } catch {
            print("{\"section\":\"H\",\"threw\":\"\(error)\",\"verdict\":\"cleanup-witness-ok\"}")
        }
        pass("H")

        // A: unique frames through both sinks; counter parity + PER-FRAME
        // GPU-path byte identity (readback after EVERY frame, r2 finding 8).
        // STRICT ticketed display (independent review F2/F3/F4): the global
        // KitDisplayTelemetry was REMOVED from trunk (DisplaySink counters are
        // per-instance), DisplaySink's init requires a CancelCommit, and an
        // unticketed show is ALWAYS a typed refusal on both sinks. Each sink
        // mints its own harness authority (sessionEpoch 0) and every show
        // carries a real admission ticket bound to the frame's pts+digest.
        MetalPresenterTelemetry.reset()
        let cgCommit = CancelCommit(sessionEpoch: 0)
        let metalCommit = CancelCommit(sessionEpoch: 0)
        let cgSink = DisplaySink(screenCheck: (), commit: cgCommit)
        let metal = try MetalPresenter(screenCheck: (), commit: metalCommit)
        for k in 0..<N {
            let f = uniqueFrame(k, w: W, h: H)
            let want = sha(f.pixelPayload!.bytes)
            guard let cgTicket = cgCommit.tryAdmit(revision: 0, framePTS: f.ptsSeconds, frameDigest: f.digest) else {
                fail("A", "frame \(k): cg admission refused")
            }
            let cgShown = await cgSink.show(f, admission: cgTicket)
            guard cgShown else { fail("A", "frame \(k): cg typed admission false") }
            guard let metalTicket = metalCommit.tryAdmit(revision: 0, framePTS: f.ptsSeconds, frameDigest: f.digest) else {
                fail("A", "frame \(k): metal admission refused")
            }
            let admitted = await metal.show(f, admission: metalTicket)
            guard admitted else { fail("A", "frame \(k): typed admission false") }
            guard cgSink.uploads == k + 1,
                  MetalPresenterTelemetry.uploads == k + 1 else {
                fail("A", "frame \(k): uploads cg=\(cgSink.uploads) metal=\(MetalPresenterTelemetry.uploads)")
            }
            guard let id = metal.lastIdentity else { fail("A", "frame \(k): no identity") }
            guard let rb = metal.readback(identity: id) else { fail("A", "frame \(k): readback unavailable") }
            guard rb.sha256 == want else {
                fail("A", "frame \(k): offscreen readback sha != input sha (reorder/dup/stale)")
            }
            guard rb.identity.leaseKey == id.leaseKey else {
                fail("A", "frame \(k): readback not bound to its frame identity")
            }
        }
        guard cgSink.noPixels == 0, MetalPresenterTelemetry.noPixels == 0 else {
            fail("A", "noPixels cg=\(cgSink.noPixels) metal=\(MetalPresenterTelemetry.noPixels)")
        }
        let ctrA = metal.rendererCounters()
        guard ctrA.readbacksOK == N, ctrA.readbackErrors == 0 else {
            fail("A", "readback counters \(ctrA.readbacksOK)/\(ctrA.readbackErrors), want \(N)/0")
        }
        print("{\"section\":\"A\",\"frames\":\(N),\"perFrameReadback\":\(N),\"proves\":\"identical sink counters + per-frame GPU-path byte identity at 1:1 (offscreen)\"}")
        pass("A")

        // B: orientation probe, red top / blue bottom, readback witness.
        var ob = [UInt8](repeating: 0, count: 8 * 4 * 4)
        for y in 0..<4 { for x in 0..<8 {
            let o = (y * 8 + x) * 4
            if y < 2 { ob[o] = 255; ob[o + 3] = 255 } else { ob[o + 2] = 255; ob[o + 3] = 255 }
        } }
        _ = await metal.show(SourceFrame(ptsSeconds: 100.0, durationSeconds: 0.04, digest: "orient",
                                     pixelPayload: PixelPayload(width: 8, height: 4, bytes: ob)))
        guard let orientId = metal.lastIdentity,
              let obr = metal.readback(identity: orientId) else { fail("B", "orientation readback unavailable") }
        guard let obb = obr.bytes else { fail("B", "8-bit readback bytes missing") }
        let topIsRed = obb[0] == 255 && obb[2] == 0
        let botIdx = (3 * 8) * 4
        let botIsBlue = obb[botIdx + 2] == 255 && obb[botIdx] == 0
        guard topIsRed, botIsBlue else {
            fail("B", "orientation flipped in readback (swap v coords in MetalRenderer.quad)")
        }
        pass("B")

        // K: overlay witnesses (r2 finding 5): stale identity typed-dropped;
        // out-of-frame geometry typed-dropped; a valid overlay composites
        // and the READBACK carries the same composited output as the present.
        _ = await metal.show(uniqueFrame(7, w: W, h: H))
        guard let kId = metal.lastIdentity else { fail("K", "no identity") }
        let white4 = OverlayRepresentation.sdrRGBA8Premultiplied(
            rgba: [UInt8](repeating: 255, count: 4 * 4 * 4), width: 4, height: 4)
        let staleId = FrameIdentity(sessionID: kId.sessionID, sessionGeneration: kId.sessionGeneration,
                                    sequence: kId.sequence + 999, surfaceRevision: kId.surfaceRevision,
                                    ptsSeconds: kId.ptsSeconds)
        let oStale = metal.showOverlay(PresenterOverlay(identity: staleId, representation: white4,
                                                        frameX: 0, frameY: 0, frameW: 4, frameH: 4))
        let oInvalid = metal.showOverlay(PresenterOverlay(identity: kId, representation: white4,
                                                          frameX: W - 1, frameY: 0, frameW: 4, frameH: 4))
        let oValid = metal.showOverlay(PresenterOverlay(identity: kId, representation: white4,
                                                        frameX: 0, frameY: 0, frameW: 4, frameH: 4,
                                                        subtitlePlanRevision: 1))
        guard oStale == .overlayRefused, oInvalid == .overlayRefused, oValid == .submitted else {
            fail("K", "overlay outcomes stale=\(oStale) invalid=\(oInvalid) valid=\(oValid) (want refused/refused/submitted)")
        }
        let ctrK = metal.rendererCounters()
        guard ctrK.overlayStaleDrops == 1, ctrK.overlayInvalidDrops == 1 else {
            fail("K", "overlay typed drops stale=\(ctrK.overlayStaleDrops) invalid=\(ctrK.overlayInvalidDrops)")
        }
        guard let krb = metal.readback(identity: kId), let kbytes = krb.bytes else {
            fail("K", "overlay readback unavailable")
        }
        // L8 authority receipts (r6 finding 3): the readback receipt and
        // the composite receipt name the composited plan revision.
        guard krb.compositedOverlayPlanRevision == 1 else {
            fail("K", "readback receipt missing composited plan revision (got \(String(describing: krb.compositedOverlayPlanRevision)))")
        }
        guard let krcpt = metal.overlayReceipt(for: kId), krcpt.compositedPlanRevision == 1 else {
            fail("K", "no overlay composite receipt naming plan 1 for the frame")
        }
        // (0,0) sits inside the 4x4 opaque white overlay: composited white.
        guard kbytes[0] == 255, kbytes[1] == 255, kbytes[2] == 255 else {
            fail("K", "overlay not composited in readback at (0,0)")
        }
        // Per-frame store (r6 finding 3): a BARE present of ANOTHER frame
        // must not clobber this frame's stored plan (r6's single global
        // lease did exactly that).
        _ = await metal.show(uniqueFrame(8, w: W, h: H))
        guard let krb2 = metal.readback(identity: kId), let kb2 = krb2.bytes,
              kb2[0] == 255, kb2[1] == 255, kb2[2] == 255,
              krb2.compositedOverlayPlanRevision == 1 else {
            fail("K", "bare present of another frame clobbered the per-frame overlay lease")
        }
        // A pixel outside the overlay keeps its base value.
        let outside = ((H / 2) * W + (W / 2)) * 4
        guard !(kbytes[outside] == 255 && kbytes[outside + 1] == 255 && kbytes[outside + 2] == 255
                && uniqueFrame(7, w: W, h: H).pixelPayload!.bytes[outside] != 255) else {
            fail("K", "outside-overlay pixel unexpectedly white")
        }
        pass("K")

        // C: REAL window resize: drawable follows contentSize*backingScale,
        // re-render callback confirms, letterbox geometry at the new size.
        _ = await metal.show(uniqueFrame(0, w: W, h: H))
        guard let cId = metal.lastIdentity else { fail("C", "no identity") }
        let resizeSizes = [(800, 600), (320, 240), (1024, 768), (640, 480)]
        for (cw, ch) in resizeSizes {
            let resizeBefore = MetalPresenterTelemetry.resizeEvents
            let callbacksBefore = metal.rendererCounters().presentCallbacksOK
            metal.setWindowSize(width: cw, height: ch)
            try? await Task.sleep(nanoseconds: 300_000_000)
            let content = metal.windowContentPixelSize
            let drawable = metal.drawablePixelSize
            guard drawable == content else {
                fail("C", "drawable \(drawable) != content backing size \(content) at \(cw)x\(ch)")
            }
            guard MetalPresenterTelemetry.resizeEvents > resizeBefore else {
                fail("C", "no resize event at \(cw)x\(ch)")
            }
            guard metal.rendererCounters().presentCallbacksOK > callbacksBefore else {
                fail("C", "no completed-callback re-render after resize to \(cw)x\(ch)")
            }
            // Rebind witness (r6 finding 2): after the resize the frame
            // is owned by a CANONICAL identity at the NEW revision; the
            // pre-resize identity is stale typed.
            guard let curId = metal.lastIdentity else {
                fail("C", "no canonical identity after resize to \(cw)x\(ch)")
            }
            guard curId.sequence == cId.sequence, curId.surfaceRevision > cId.surfaceRevision else {
                fail("C", "canonical identity not rebound (seq \(curId.sequence) rev \(curId.surfaceRevision), want seq \(cId.sequence) rev > \(cId.surfaceRevision))")
            }
            if metal.probePixel(identity: cId, px: 0, py: 0,
                                drawableW: drawable.w, drawableH: drawable.h) != nil {
                fail("C", "pre-resize identity still resolves after rebind (should be stale)")
            }
            let fit = AspectFit.fit(drawableW: drawable.w, drawableH: drawable.h, frameW: W, frameH: H)
            let center = (drawable.w / 2, drawable.h / 2)
            guard let c = metal.probePixel(identity: curId, px: center.0, py: center.1,
                                           drawableW: drawable.w, drawableH: drawable.h),
                  !(c.r == 0 && c.g == 0 && c.b == 0) else {
                fail("C", "center black/unavailable at \(cw)x\(ch)")
            }
            for (cx, cy) in [(2, 2), (drawable.w - 3, 2), (2, drawable.h - 3), (drawable.w - 3, drawable.h - 3)]
            where AspectFit.isLetterbox(px: cx, py: cy, fit: fit) {
                guard let p = metal.probePixel(identity: curId, px: cx, py: cy,
                                               drawableW: drawable.w, drawableH: drawable.h),
                      p.r == 0, p.g == 0, p.b == 0 else {
                    fail("C", "letterbox not black at \(cw)x\(ch) corner \(cx),\(cy)")
                }
            }
            print("{\"section\":\"C\",\"content\":\"\(cw)x\(ch)\",\"drawable\":\"\(drawable)\",\"fitRect\":\"\(fit.pixelRect)\",\"verdict\":\"ok\"}")
        }
        pass("C")

        // D: fullscreen round trip: delegate receipts + window alive +
        // completed-callback re-render. Receipt states observations only.
        let fsE = MetalPresenterTelemetry.fullscreenEntries
        let fsX = MetalPresenterTelemetry.fullscreenExits
        let cbD = metal.rendererCounters().presentCallbacksOK
        metal.toggleFullScreenNow()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard MetalPresenterTelemetry.fullscreenEntries == fsE + 1 else {
            fail("D", "no fullscreen entry receipt (entries=\(MetalPresenterTelemetry.fullscreenEntries))")
        }
        metal.toggleFullScreenNow()
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        guard MetalPresenterTelemetry.fullscreenExits == fsX + 1 else {
            fail("D", "no fullscreen exit receipt")
        }
        guard metal.windowIsVisible else { fail("D", "window not visible after round trip") }
        guard metal.rendererCounters().presentCallbacksOK > cbD else {
            fail("D", "no completed-callback re-render across fullscreen transitions")
        }
        print("{\"section\":\"D\",\"entries\":\(MetalPresenterTelemetry.fullscreenEntries),\"exits\":\(MetalPresenterTelemetry.fullscreenExits),\"proves\":\"delegate receipts + window lifetime + callback-confirmed re-render, not pixels\"}")
        pass("D")

        // E: close-intent FENCE witnesses (r2 findings 1/8): queued work
        // launched BEFORE performUserClose but executing after it must be
        // typed-dropped. The tasks queue on the MainActor; performUserClose
        // runs synchronously in THIS MainActor turn, so windowShouldClose
        // seals before the queued shows run - deterministic.
        for k in 0..<8 { _ = await metal.show(uniqueFrame(k, w: W, h: H)) } // in-flight burst
        let upBeforeFence = MetalPresenterTelemetry.uploads
        for k in 20..<24 { Task { _ = await metal.show(uniqueFrame(k, w: W, h: H)) } }
        metal.performUserClose()
        guard MetalPresenterTelemetry.closedByUser else {
            fail("E", "performClose did not set closedByUser via windowShouldClose")
        }
        let residual = await metal.close()
        guard residual == 0 else { fail("E", "close quiescence residual=\(residual)") }
        // The 4 queued shows landed after the fence: all typed-dropped.
        guard MetalPresenterTelemetry.uploads == upBeforeFence,
              MetalPresenterTelemetry.staleWorkAfterClose >= 4 else {
            fail("E", "queued shows after the close-intent fence were not typed-dropped (uploads \(upBeforeFence)->\(MetalPresenterTelemetry.uploads), stale=\(MetalPresenterTelemetry.staleWorkAfterClose))")
        }
        // Direct post-close show: typed drop, admission false.
        let staleAdmitted = await metal.show(uniqueFrame(9, w: W, h: H))
        guard !staleAdmitted, MetalPresenterTelemetry.uploads == upBeforeFence else {
            fail("E", "direct stale show after close was not typed-dropped")
        }
        // Duplicate-PTS attribution (r2 finding 3): two frames with the SAME
        // pts get distinct records by sequence. On a fresh presenter:
        let metal2 = try MetalPresenter(screenCheck: ())
        let dupA = await metal2.show(SourceFrame(ptsSeconds: 5.0, durationSeconds: 0.04, digest: "dupA",
                                                 pixelPayload: PixelPayload(width: 8, height: 4, bytes: ob)))
        let dupB = await metal2.show(SourceFrame(ptsSeconds: 5.0, durationSeconds: 0.04, digest: "dupB",
                                                 pixelPayload: PixelPayload(width: 8, height: 4, bytes: ob)))
        guard dupA, dupB else { fail("E", "fresh-session admissions not true") }
        let recs = metal2.rendererRecords()
        let dupRecs = recs.filter { $0.identity.ptsSeconds == 5.0 }
        guard dupRecs.count == 2, dupRecs[0].identity.sequence != dupRecs[1].identity.sequence else {
            fail("E", "duplicate-PTS frames misattributed (records=\(dupRecs.count))")
        }
        guard MetalPresenterTelemetry.uploads == 2 else {
            fail("E", "recreate session counters contaminated (=\(MetalPresenterTelemetry.uploads), want 2)")
        }
        pass("E")

        // R: renegotiate epoch/lease witness (r2 finding 2): old-epoch
        // completions can never corrupt the new ring; drain residual 0;
        // work resumes on the new surface revision.
        do {
            for k in 30..<34 { _ = await metal2.show(uniqueFrame(k, w: W, h: H)) }
            try await metal2.renegotiateSurface(.sdrDefault, ot: .identity)
            let ctrR = metal2.rendererCounters()
            guard ctrR.renegotiations == 1 else { fail("R", "renegotiation not counted") }
            let afterR = await metal2.show(uniqueFrame(35, w: W, h: H))
            guard afterR else { fail("R", "admission false after renegotiate") }
            guard metal2.lastIdentity != nil else { fail("R", "no upload after renegotiate") }
            let residualR = await metal2.close()
            guard residualR == 0 else { fail("R", "post-renegotiate quiescence residual=\(residualR)") }
            print("{\"section\":\"R\",\"renegotiations\":1,\"proves\":\"epoch-checked leases, bounded drain before ring replacement, resume on new revision\"}")
        }
        pass("R")

        // G: invalid inputs + byte budget rejected typed, no success
        // counters move. The budget rejection needs NO payload (size-stage).
        let metal3 = try MetalPresenter(screenCheck: ())
        let ctr0 = metal3.rendererCounters()
        let upG = MetalPresenterTelemetry.uploads
        _ = await metal3.show(SourceFrame(ptsSeconds: 0, durationSeconds: 0.04, digest: "bad0",
                                      pixelPayload: PixelPayload(width: 0, height: 10, bytes: [])))
        _ = await metal3.show(SourceFrame(ptsSeconds: 0, durationSeconds: 0.04, digest: "badBig",
                                      pixelPayload: PixelPayload(width: 16385, height: 10,
                                                                 bytes: [UInt8](repeating: 0, count: 16385 * 10 * 4))))
        _ = await metal3.show(SourceFrame(ptsSeconds: 0, durationSeconds: 0.04, digest: "badShort",
                                      pixelPayload: PixelPayload(width: 4, height: 4, bytes: [UInt8](repeating: 0, count: 63))))
        // 6000x6000 RGBA8 = 144 MB > 128 MiB frame budget: rejected at the
        // size stage with a tiny payload present.
        _ = await metal3.show(SourceFrame(ptsSeconds: 0, durationSeconds: 0.04, digest: "badBudget",
                                      pixelPayload: PixelPayload(width: 6000, height: 6000,
                                                                 bytes: [UInt8](repeating: 0, count: 64))))
        let ctr1 = metal3.rendererCounters()
        guard ctr1.uploadsOK == ctr0.uploadsOK,
              ctr1.validationRejections >= ctr0.validationRejections + 3,
              ctr1.byteBudgetRejections >= ctr0.byteBudgetRejections + 1,
              MetalPresenterTelemetry.uploads == upG else {
            fail("G", "invalid inputs not typed-rejected cleanly")
        }
        pass("G")

        // T: cancellation-quiescence witness (r3 finding 8): a cancelled
        // run stops at the next frame, runs FULL cleanup + quiescence, then
        // throws typed .cancelled; F passing afterwards proves the cleanup.
        do {
            let runTask = Task { @MainActor in
                try await GorAVMetalShellApp.runMuxed(path: clip)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            runTask.cancel()
            do {
                _ = try await runTask.value
                fail("T", "cancelled run completed without typed .cancelled")
            } catch let e as MetalRunError {
                guard e == .cancelled else { fail("T", "typed error \(e), want .cancelled") }
                print("{\"section\":\"T\",\"threw\":\"cancelled\",\"proves\":\"cancel stops pumps, full cleanup + quiescence ran, typed receipt\"}")
            }
        }
        pass("T")

        // F: real-fixture ordered parity vs v1.4 (measured 11:48 owner run):
        // shown=250 dropped=0 waits=248 audioPushed=1764000 residual=0.
        MetalPresenterTelemetry.reset()
        let receipt = try await GorAVMetalShellApp.runMuxed(path: clip)
        let uniqueDigests = Set(receipt.digestsShown).count
        print("{\"section\":\"F\",\"shown\":\(receipt.shown),\"dropped\":\(receipt.dropped),\"waits\":\(receipt.waits),\"outOfOrder\":\(receipt.outOfOrderDrops),\"nonFinite\":\(receipt.nonFiniteDrops),\"digestsShown\":\(receipt.digestsShown.count),\"uniqueDigests\":\(uniqueDigests),\"audioPushed\":\(receipt.audioPushed),\"audioTerminal\":\"\(receipt.audioTerminal)\",\"audioResidual\":\(receipt.audioResidualAtStop),\"quiescenceResidual\":\(receipt.quiescenceResidual),\"v14\":{\"shown\":250,\"dropped\":0,\"audioPushed\":1764000,\"residual\":0}}")
        // Digest uniqueness is REPORTED, not gated: repeated static frames
        // legitimately share a digest. Residuals are CHECKED here.
        guard receipt.shown == 250, receipt.dropped == 0, receipt.outOfOrderDrops == 0,
              receipt.nonFiniteDrops == 0, receipt.digestsShown.count == 250,
              receipt.audioPushed == 1764000,
              receipt.audioResidualAtStop == 0, receipt.quiescenceResidual == 0 else {
            fail("F", "parity vs v1.4 not met (see receipt)")
        }
        pass("F")
        print("{\"matrix\":\"COMPLETE\",\"verdict\":\"ALL_PASS\"}")
    }
}
#else
import Foundation
@main
struct MetalCheckUnsupported {
    static func main() {
        setbuf(stdout, nil)
        print("gorav-metal-check: Metal presenter requires macOS (AppKit/Metal); unsupported on this host")
        Foundation.exit(3)
    }
}
#endif
