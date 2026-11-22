// ================================================================
//  AdaptiveColor.swift - adaptive color application for the overlay panels
//  Owns: smooth 1.2s color fades onto SpineUI, SidebarUI,
//  MusicPanel; ScreenCaptureEngine element registration (PPController ext)
// ================================================================
import AppKit
import QuartzCore

// MARK: - Smooth color application helpers

private func applySmooth(to layer: CALayer?, color: NSColor, duration: TimeInterval = 1.2) {
    guard let layer = layer as? CATextLayer else { return }
    let newColor = color.cgColor
    if let current = layer.foregroundColor,
       current == newColor { return }
    let anim = CABasicAnimation(keyPath: "foregroundColor")
    // Start from what is on screen: the model value is already the previous target, so
    // retargeting a running fade would jump to it first.
    anim.fromValue = layer.presentation()?.foregroundColor ?? layer.foregroundColor
    anim.toValue   = color.cgColor
    anim.duration  = duration
    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    anim.fillMode  = .forwards
    anim.isRemovedOnCompletion = false
    layer.add(anim, forKey: "foregroundColor")
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.foregroundColor = color.cgColor
    CATransaction.commit()
}

private func applySmoothToSublayers(of layer: CALayer?, color: NSColor) {
    guard let layer = layer else { return }
    applySmooth(to: layer, color: color)
    layer.sublayers?.forEach { applySmoothToSublayers(of: $0, color: color) }
}

private func applySmoothToSubviews(of view: NSView, color: NSColor) {
    for sub in view.subviews {
        if let label = sub as? NSTextField {
            let alpha = label.textColor?.alphaComponent ?? 1
            if label.textColor != color.withAlphaComponent(alpha) {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 1.2
                    ctx.allowsImplicitAnimation = true
                    label.animator().textColor = color.withAlphaComponent(alpha)
                }
            }
        }
        applySmoothToSubviews(of: sub, color: color)
    }
}

// MARK: - SpineUI extension

extension SpineUI {
    func applyAdaptiveColor(_ color: NSColor) {
        applySmoothToSublayers(of: layer, color: color)
        applySmoothToSubviews(of: self, color: color)
    }
}

// MARK: - SidebarUI extension

extension SidebarUI {
    func applyAdaptiveColor(_ color: NSColor) {
        // WHY: no applySmoothToSublayers here - SeekBar owns its layers (thumb
        // included) via applyAdaptiveColor; recursive painting clobbers thumbColor.
        applySmoothToSubviews(of: self, color: color)
        seekBar.applyAdaptiveColor(color)
    }
}

// MARK: - PPController extension

extension PPController {
    func setupAdaptiveColor() {
        let engine = ScreenCaptureEngine.shared

        engine.registerElement(id: "spine") { [weak self] in
            guard let self = self, let win = self.window else { return nil }
            return win.convertToScreen(self.spineUI.frame)
        } callback: { [weak self] color in
            self?.spineUI.applyAdaptiveColor(color)
            if let panel = self?.musicPanel, !panel.isHidden {
                panel.applyAdaptiveColor(color)
            }
        }

        engine.registerElement(id: "sidebar") { [weak self] in
            guard let self = self, let win = self.window else { return nil }
            return win.convertToScreen(self.sidebarUI.frame)
        } callback: { [weak self] color in
            self?.sidebarUI.applyAdaptiveColor(color)
        }

        engine.registerSubtitle(id: "subtitle") { [weak self] in
            self?.subtitleView.currentTextFrame
        } callback: { [weak self] color, mode in
            self?.subtitleView.applyAdaptiveColor(color, mode: mode)
        }

    }
}

// MARK: - MusicPanel extension
extension MusicPanel {
    func applyAdaptiveColor(_ color: NSColor) {
        applyColorRecursive(self, color: color)
    }

    private func applyColorRecursive(_ view: NSView, color: NSColor) {
        for sub in view.subviews {
            if let tf = sub as? NSTextField {
                let alpha = tf.textColor?.alphaComponent ?? 1.0
                if tf.textColor != color.withAlphaComponent(alpha) {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 1.2
                        ctx.allowsImplicitAnimation = true
                        tf.animator().textColor = color.withAlphaComponent(alpha)
                    }
                }
            }
            applyColorRecursive(sub, color: color)
        }
        applySmoothToSublayers(of: view.layer, color: color)
    }
}
