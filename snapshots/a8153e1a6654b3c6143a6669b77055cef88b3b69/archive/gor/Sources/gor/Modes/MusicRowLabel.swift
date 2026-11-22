import AppKit
import CoreImage
import Foundation
import IOKit
import IOKit.ps
import CoreGraphics
import Darwin
import QuartzCore
// ================================================================
//  MusicRowLabel - music row text
// ================================================================
final class MusicRowLabel: NSTextField {

    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        isEditable       = false
        isBordered       = false
        drawsBackground  = false
        backgroundColor  = .clear
        textColor        = .white
        lineBreakMode    = .byTruncatingTail

        self.shadow = PPController.globalShadow

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self, userInfo: nil
        ))

        VariationBroadcaster.shared.addListener { [weak self] in
            guard let self = self else { return }
            self.updateVariation()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateVariation() {
        let engine = ScreenCaptureEngine.shared
        let color  = engine.currentColor(for: "subtitle") ?? .white
        let alpha: CGFloat = isHovered ? 1.0 : 0.7

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            self.animator().textColor = color.withAlphaComponent(alpha)
            self.animator().font      = PhotonFont.chromeNsDriven(view: self, profile: .button)
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true;  updateVariation() }
    override func mouseExited(with event: NSEvent)  { isHovered = false; updateVariation() }

    override func mouseMoved(with event: NSEvent) {
        if let winPt = window?.contentView?.convert(event.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }
}

