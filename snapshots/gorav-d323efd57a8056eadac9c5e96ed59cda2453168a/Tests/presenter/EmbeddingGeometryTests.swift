import AppKit
import QuartzCore

@main
struct EmbeddingGeometryTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 180))
        let sibling = NSView(frame: .zero)
        host.addSubview(sibling)
        let view = MetalPresenterView(frame: host.bounds)
        view.autoresizingMask = [.width, .height]
        host.addSubview(view)
        var sizes: [(Int, Int)] = []
        view.onResize = { sizes.append(($0, $1)) }
        view.layout()
        let expected = view.convertToBacking(view.bounds.size)
        precondition(view.metalLayer?.drawableSize == expected)
        let before = sizes.count
        view.viewDidChangeBackingProperties()
        precondition(sizes.count == before + 1, "backing change must notify drawable geometry")
        precondition(view.metalLayer?.drawableSize == view.convertToBacking(view.bounds.size))
        view.setFrameSize(NSSize(width: 640, height: 360))
        view.layout()
        precondition(view.metalLayer?.drawableSize == view.convertToBacking(view.bounds.size))
        let count = sizes.count
        let lastValidDrawable = view.metalLayer?.drawableSize
        view.setFrameSize(.zero)
        view.layout()
        precondition(sizes.count == count, "zero-sized host must not submit invalid geometry")
        precondition(view.metalLayer?.drawableSize == lastValidDrawable)
        view.removeFromSuperview()
        precondition(host.subviews.count == 1 && host.subviews[0] === sibling)
        print("G3 actual AppKit view geometry: PASS (layout, backing, resize, zero, host ownership)")
    }
}
