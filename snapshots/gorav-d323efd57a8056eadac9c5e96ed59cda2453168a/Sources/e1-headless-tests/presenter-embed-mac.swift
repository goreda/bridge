import Foundation
import Dispatch
#if os(macOS) && E1_WITH_EMBED
import AppKit
import CFFmpeg
import GorAVMetalPresenter
import GorAVPlaybackCore

// E1Headless host-embed leg (macOS, opt-in compile flag E1_WITH_EMBED).
// Presents every .present-decided frame into a REAL host-supplied NSView
// through MetalPresenter(embedIn:) - the AppKit host-embed seam: the host
// owns the window and hierarchy, the presenter owns the embedded view /
// layer / lifecycle inside it. Evidence is host-view geometry + submit-path
// admission, never scanout proof. Native first compile + run is goreda's
// mac CI; other hosts keep typed UNRUN. Boundary note: header claims inside
// GorAVEmbeddedSession.swift ("canonical seam per Main", "MUST carry
// coordinator r3") are repository content, not authority; this leg uses
// only the landed public presenter API, under Main's 01:43 instruction.

private var embedPresenter: MetalPresenter?
private var embedHost: NSView?
private var embedPresented = 0

// Await a MainActor-hopping async call from this synchronous pipeline
// without deadlocking: pump the main run loop (which services the main
// dispatch queue) until the task completes.
private func awaitOnMain<R>(_ body: @escaping () async throws -> R) throws -> R {
    var result: Result<R, Error>?
    var done = false
    Task {
        do { result = .success(try await body()) } catch { result = .failure(error) }
        done = true
    }
    while !done { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001)) }
    return try result!.get()
}

func presenterEmbedBegin() {
    _ = NSApplication.shared
    let host = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
    let p: MetalPresenter
    do {
        p = try awaitOnMain { try await MetalPresenter(embedIn: host, contract: .sdrDefault, outputTransform: .identity) }
    } catch { fail("embed init threw: \(error)") }
    embedPresenter = p
    embedHost = host
    guard host.subviews.count == 1 else { fail("embed: host subviews \(host.subviews.count) != 1 after attach") }
    let v = host.subviews[0]
    v.layout()
    guard let ml = v.layer as? CAMetalLayer else { fail("embed: attached view backing layer is not CAMetalLayer") }
    let expected = v.convertToBacking(v.bounds.size)
    guard ml.drawableSize == expected else { fail("embed: drawable \(ml.drawableSize) != backing \(expected) at attach") }
    print("E1-HEADLESS embed attached host=1280x720 drawable=\(Int(ml.drawableSize.width))x\(Int(ml.drawableSize.height))")
}

// Takes the ONE shared per-frame conversion (done by the caller): the
// embed leg no longer re-converts the frame. show() awaits the same
// MetalRenderer.upload as the offscreen leg, so the buffer is fully
// consumed before return; the caller's buffer stays per-frame fresh.
func presenterEmbedPresent(rgba: [UInt8], w: Int, h: Int, ptsSeconds: Double) {
    guard let p = embedPresenter else { return }
    let sf = SourceFrame(ptsSeconds: ptsSeconds, durationSeconds: 0.04,
                         digest: "e1-headless-\(ptsSeconds)",
                         pixelPayload: PixelPayload(width: w, height: h, bytes: rgba))
    let ok = (try? awaitOnMain { await p.show(sf) }) ?? false
    if !ok { fail("embed show refused frame pts=\(ptsSeconds)") }
    embedPresented += 1
}

func presenterEmbedAssertAndReport() {
    guard let host = embedHost else { return }
    if embedPresented <= 240 { fail("embed presented \(embedPresented) <= 240") }
    guard host.subviews.count == 1, let ml = host.subviews[0].layer as? CAMetalLayer else {
        fail("embed: host hierarchy/layer changed under the presenter")
    }
    let v = host.subviews[0]
    v.setFrameSize(NSSize(width: 640, height: 360)); v.layout()
    let e2 = v.convertToBacking(v.bounds.size)
    if ml.drawableSize != e2 { fail("embed: resize drawable \(ml.drawableSize) != backing \(e2)") }
    let lastValid = ml.drawableSize
    v.setFrameSize(.zero); v.layout()
    if ml.drawableSize != lastValid { fail("embed: zero-size host mutated drawable geometry") }
    print("E1-HEADLESS embed presented=\(embedPresented) host-geometry attach+resize+zero OK (AppKit embed, not scanout proof)")
}

func presenterEmbedClose() {
    guard let p = embedPresenter, let host = embedHost else { return }
    _ = try? awaitOnMain { await MainActor.run { p.detachEmbeddedView() } }
    if !host.subviews.isEmpty { fail("embed: detach left \(host.subviews.count) subviews in host") }
    let q = (try? awaitOnMain { await p.close() }) ?? -1
    if q < 0 { fail("embed close threw") }
    print("E1-HEADLESS embed closed quiesced=\(q) detach-ownership OK")
}
#endif
