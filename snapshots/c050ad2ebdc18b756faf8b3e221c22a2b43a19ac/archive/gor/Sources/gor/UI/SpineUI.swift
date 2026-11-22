// ================================================================
//  SpineUI.swift - vertical playback controls and overlays
//  Owns: button state, dropdowns, OSD, title layout
//  Answers: I24 I25 I28 · TRAP-01 TRAP-03 TRAP-08
//  Contract: SpineUI owns its layout; callers supply playback state
// ================================================================
import AppKit
import QuartzCore

// ================================================================
//  TrafficTextBtn - hover-expanding text control
// ================================================================
final class TrafficTextBtn: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    var action: (() -> Void)?
    private let label = CATextLayer()
    private let hoverColor: NSColor
    private let shortText: String
    private var fullText: String
    private var typeTimer: Timer?
    private var fadeTimer: Timer?
    private let fixedX: CGFloat
    private var isHovering = false
    private var isExpanded = false
    
    private var originalFullText: String = ""
    private var altFullText: String = ""
    var cmdAction: (() -> Void)?
    var altAction: (() -> Void)?
    var shiftAction: (() -> Void)?
    private var isCmdHeld = false
    private var altTextTimer: Timer?
    private var flagsMonitor: Any?

    init(short: String, full: String, color: NSColor, tip: String, fixedX: CGFloat = 10) {
        self.shortText = short; self.fullText = full
        self.hoverColor = color; self.fixedX = fixedX
        super.init(frame: .zero)
        wantsLayer = true
        
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        label.alignmentMode = .left
        label.isWrapped = false
        label.truncationMode = .none
        label.string = short
        label.foregroundColor = NSColor.white.cgColor
        if label.fontSize != PhotonFont.chromeSize { label.fontSize = PhotonFont.chromeSize }
        label.font = PhotonFont.chromeCt()
        
        label.shadowColor = NSColor.black.cgColor
        label.shadowOpacity = Float(PPController.shadowOpacity)
        label.shadowRadius = PPController.shadowRadius
        label.shadowOffset = .zero
        
        layer?.addSublayer(label)
        
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))

        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self = self else { return }
            guard self.isEffectivelyVisible else { return }
            let currentSize = PhotonFont.chromeSize
            let newFont = PhotonFont.chromeNsDriven(view: self, profile: .button, size: currentSize)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            PhotonFont.setIfChanged(newFont, on: self.label)
            if self.label.fontSize != PhotonFont.chromeSize { self.label.fontSize = PhotonFont.chromeSize }
            CATransaction.commit()
        }
        
        // Font selection is state, not animation: update even while hidden or
        // while the variation clock is stalled. Visibility still gates ticks.
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.label.font = PhotonFont.chromeCt()
            if self.label.fontSize != PhotonFont.chromeSize { self.label.fontSize = PhotonFont.chromeSize }
            self.needsLayout = true
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self,
                  self.isHovering,
                  self.altAction != nil,
                  let ppc = (NSApp.delegate as? AppDelegate)?.controller else { return event }
            
            let cmdNow = event.modifierFlags.contains(.command)
            guard cmdNow != self.isCmdHeld else { return event }
            self.isCmdHeld = cmdNow
            
            if cmdNow {
                let targetText = ppc.isMusicMode ? "Video" : "Music"
                self.typeTimer?.invalidate()
                self.morphBetween(targetText)
            } else {
                self.altTextTimer?.invalidate()
                self.typeTimer?.invalidate()
                self.label.string = self.fullText
            }
            return event
        }
    }
    
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let monitor = flagsMonitor { NSEvent.removeMonitor(monitor) } }
    
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.frame = bounds
        CATransaction.commit()
    }

    override func mouseEntered(with e: NSEvent) {
        if e.modifierFlags.contains(.command), altAction != nil,
           let ppc = (NSApp.delegate as? AppDelegate)?.controller {
            let targetText = ppc.isMusicMode ? "Video" : "Music"
            morphBetween(targetText)
            return
        }
        
        isHovering = true
        fadeTimer?.invalidate()
        
        self.frame.size.width = PhotonFont.chromeExpandedBtnW(for: fullText)
        label.foregroundColor = hoverColor.cgColor
        
        typeTimer?.invalidate()
        var idx = 1
        let chars = Array(fullText)
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            idx += 1
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.label.string = String(chars.prefix(idx))
            CATransaction.commit()
            
            if idx >= chars.count {
                t.invalidate()
                self.isExpanded = true
            }
        }
    }

    override func mouseExited(with e: NSEvent) {
        if altAction != nil {
            typeTimer?.invalidate()
            label.string = shortText
            fullText = originalFullText
            label.foregroundColor = NSColor.white.cgColor
            self.frame.size.width = PhotonFont.chromeCollapsedBtnW
            self.isExpanded = false
            isHovering = false
            return
        }
        
        isHovering = false
        typeTimer?.invalidate()
        
        let chars = Array((label.string as? String) ?? "")
        guard !chars.isEmpty else { return }
        
        var idx = chars.count
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            idx -= 1
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if idx <= 0 {
                self.label.string = self.shortText
                self.label.foregroundColor = NSColor.white.cgColor
                self.frame.size.width = PhotonFont.chromeCollapsedBtnW
                self.isExpanded = false
                t.invalidate()
            } else {
                self.label.string = String(chars.prefix(idx))
            }
            CATransaction.commit()
        }
    }
    
    override func mouseDown(with e: NSEvent) {
        if e.modifierFlags.contains(.shift), !e.modifierFlags.contains(.command),
           let shiftAction = shiftAction {
            shiftAction()
        } else if e.modifierFlags.contains(.command), let cmdAction = cmdAction {
            cmdAction()
        } else if e.modifierFlags.contains(.command), let altAction = altAction {
            altAction()
        } else if e.modifierFlags.contains(.command) {
            super.mouseDown(with: e)
        } else {
            action?()
        }
    }
    
    func updateFullText(_ newFull: String) {
        self.fullText = newFull
        
        if isExpanded {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            label.string = newFull
            
            let newWidth = CGFloat(newFull.count) * PhotonFont.chromeCharW + 10
            label.frame.size.width = newWidth
            CATransaction.commit()
        }
    }

    private func morphToAlt() {
        isHovering = true
        fadeTimer?.invalidate()
        typeTimer?.invalidate()
        
        self.frame.size.width = PhotonFont.chromeExpandedBtnW(for: altFullText)
        label.foregroundColor = hoverColor.cgColor
        
        let fromText = shortText
        let toText = altFullText
        let fromChars = Array(fromText)
        let toChars = Array(toText)
        let maxLen = max(fromChars.count, toChars.count)
        
        var step = 0
        typeTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            step += 1
            
            var result = ""
            for i in 0..<maxLen {
                if i < step && i < toChars.count {
                    if Bool.random() && i < fromChars.count {
                        result.append(fromChars[i])
                    } else {
                        result.append(toChars[i])
                    }
                } else if i < fromChars.count {
                    result.append(fromChars[i])
                } else {
                    result.append(" ")
                }
            }
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.label.string = result
            CATransaction.commit()
            
            if step >= maxLen + 3 {
                self.label.string = String(toChars)
                t.invalidate()
                self.isExpanded = true
            }
        }
    }
    
    func setAlt(full: String, action: @escaping () -> Void) {
        self.originalFullText = self.fullText
        self.altFullText = full
        self.altAction = action
    }
    
    private func morphBetween(_ target: String) {
        altTextTimer?.invalidate()
        typeTimer?.invalidate()
        
        let currentText = label.string as? String ?? fullText
        let reservedW = max(PhotonFont.chromeExpandedBtnW(for: currentText),
                            PhotonFont.chromeExpandedBtnW(for: target))
        self.frame.size.width = reservedW
        let fromChars = Array(currentText)
        let toChars = Array(target)
        let maxLen = max(fromChars.count, toChars.count)
        
        var step = 0
        let totalSteps = maxLen + 4
        
        altTextTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            step += 1
            
            var result = ""
            for i in 0..<maxLen {
                if step >= totalSteps {
                    result = target
                    break
                }
                
                let progress = Double(step) / Double(totalSteps)
                let charProgress = Double(i) / Double(maxLen)
                
                if charProgress < progress {
                    if i < toChars.count {
                        if Double.random(in: 0...1) < 0.3 {
                            let randomChar = Character(UnicodeScalar(Int.random(in: 33...126))!)
                            result.append(randomChar)
                        } else {
                            result.append(toChars[i])
                        }
                    }
                } else {
                    if i < fromChars.count {
                        result.append(fromChars[i])
                    }
                }
            }
            
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.label.string = result
            CATransaction.commit()
            
            if step >= totalSteps {
                self.label.string = target
                t.invalidate()
            }
        }
    }
}

// ================================================================
//  VolumeSliderBtn - volume button and slider
// ================================================================
final class VolumeSliderBtn: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    var action: (() -> Void)?
    var onChanged: ((Double) -> Void)?
    var value: Double = Double(PPController.defaultVolume) {
        didSet { if isHovering { updateLabel() } }
    }
    var isBlocked = false

    private let label        = CATextLayer()
    var isTracking   = false
    private var fadeTimer:   Timer?
    private var idleTimer:   Timer?
    private var keyboardHideTimer: Timer?
    private var mouseMonitor: Any?

    var isHovering   = false
    private var entryWinX:   CGFloat = 0
    private var entryValue:  Double  = 0

    private let fullWord = "Volume"
    private let chars: [String]
    var lastSetValue: Double = Double(PPController.defaultVolume)

    private var collapsedW: CGFloat { PhotonFont.chromeCollapsedBtnW }
    private var maxSliderWidth: CGFloat { PhotonFont.chromeExpandedBtnW(for: "Volume 100") }

    override init(frame: NSRect) {
        var temp: [String] = []
        for i in 1...fullWord.count { temp.append(String(fullWord.prefix(i))) }
        self.chars = temp

        super.init(frame: frame)
        wantsLayer = true

        label.contentsScale  = NSScreen.main?.backingScaleFactor ?? 2
        label.alignmentMode  = .left
        label.isWrapped      = false
        label.foregroundColor = NSColor.white.cgColor
        label.font           = PhotonFont.chromeCt()
        label.fontSize       = PhotonFont.chromeSize
        label.string         = "V"
        label.shadowColor    = NSColor.black.cgColor
        label.shadowRadius   = PPController.shadowRadius
        label.shadowOpacity  = PPController.shadowOpacity
        label.shadowOffset   = .zero
        layer?.addSublayer(label)

        var lastVariationReport: Double = -.infinity
        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let report = now - lastVariationReport >= 10
            if report { lastVariationReport = now }
            let visible = self.isEffectivelyVisible
            if report {
                let proximity = VariationBroadcaster.shared.proximity(to: self, profile: .button)
                print("[VB][volume] visible=\(visible) window=\(self.window != nil) windowAlpha=\(self.window?.alphaValue ?? -1) hidden=\(self.isHidden) alpha=\(self.alphaValue) proximity=\(proximity)")
            }
            guard visible else { return }
            let sz = PhotonFont.chromeSize
            let newFont = PhotonFont.chromeCtDriven(view: self, profile: .button, size: sz)
            PhotonFont.setIfChanged(newFont, on: self.label)
            if self.label.fontSize != PhotonFont.chromeSize { self.label.fontSize = PhotonFont.chromeSize }
            if report {
                let desired = CTFontCopyVariation(newFont)
                let actual = self.label.font.map { CTFontCopyVariation($0 as! CTFont) }
                print("[VB][volume] desired=\(String(describing: desired)) layer=\(String(describing: actual))")
            }
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self = self, !self.isBlocked, let win = self.window else { return event }

            let btnOriginX = self.convert(NSPoint.zero, to: win.contentView).x
            let winX       = event.locationInWindow.x

            if !self.isHovering {
                let btnFrame = self.convert(self.bounds, to: win.contentView)
                let inBtn = winX >= btnFrame.minX - 2 && winX <= btnFrame.maxX + 2 &&
                            event.locationInWindow.y >= btnFrame.minY - 2 &&
                            event.locationInWindow.y <= btnFrame.maxY + 2
                guard inBtn else { return event }
                self.isHovering   = true
                self.fadeTimer?.invalidate()
                self.idleTimer?.invalidate()
                self.fadeTimer    = nil
                self.value        = self.lastSetValue
                self.frame.size.width = self.maxSliderWidth
                self.entryWinX    = winX
                self.entryValue   = self.lastSetValue
                self.updateLabel()
                return event
            }

            let btnFrameExpanded = self.convert(self.bounds, to: win.contentView)
            let inExpanded = winX >= btnFrameExpanded.minX - 4 &&
                             winX <= btnFrameExpanded.maxX + 4 &&
                             event.locationInWindow.y >= btnFrameExpanded.minY - 4 &&
                             event.locationInWindow.y <= btnFrameExpanded.maxY + 4
            if !inExpanded {
                self.isHovering    = false
                self.lastSetValue  = self.value
                self.startIdleTimer()
                return event
            }

            let absX   = winX - btnOriginX
            let newVal = max(0, min(1, Double(absX / self.maxSliderWidth)))
            if abs(newVal - self.value) > 0.005 {
                self.value        = newVal
                self.lastSetValue = newVal
                self.onChanged?(newVal)
                self.updateLabel()
            }
            return event
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let m = mouseMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Label & display

    private func updateLabel() {
        let vol   = Int(round(value * 100))
        let step  = 1.0 / Double(chars.count)
        let index = min(Int(floor(value / step)), chars.count - 1)
        label.string = value < 0.05 ? "\(vol)" : "\(chars[index]) \(vol)"
    }

    private func resetToShort() {
        label.string       = "V"
        frame.size.width   = collapsedW
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self, !self.isHovering else { return }
            self.fadeOut()
        }
    }

    private func fadeOut() {
        let currentText = label.string as? String ?? "V"
        let chars = Array(currentText)
        guard !chars.isEmpty else { resetToShort(); return }
        var idx = chars.count
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            idx -= 1
            if idx <= 0 {
                self.label.string    = "V"
                self.frame.size.width = PhotonFont.chromeCollapsedBtnW
                t.invalidate()
                self.fadeTimer = nil
            } else {
                self.label.string = String(chars.prefix(idx))
            }
        }
    }

    // MARK: - Keyboard simulation

    func simulateHoverForKeyboard() {
        guard !isHovering else { return }
        isHovering = true
        fadeTimer?.invalidate()
        idleTimer?.invalidate()
        let targetValue = lastSetValue
        var step = 0
        let totalSteps = chars.count
        keyboardHideTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            step += 1
            let progress = min(1.0, Double(step) / Double(totalSteps))
            self.value = targetValue * progress
            self.updateLabel()
            if step >= totalSteps {
                timer.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.isHovering = false
                    self?.resetToShort()
                }
            }
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        label.frame = bounds
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) { }
    override func mouseExited(with event: NSEvent)  { }

    // MARK: - Mouse down / drag / up

    private var _mouseDownX: CGFloat = 0

    override func mouseDown(with event: NSEvent) {
        guard !isBlocked else { return }
        idleTimer?.invalidate()
        window?.isMovable = false
        _mouseDownX = convert(event.locationInWindow, from: nil).x
        isTracking  = true
        if !isHovering {
            isHovering = true
            fadeTimer?.invalidate()
            fadeTimer  = nil
            frame.size.width = maxSliderWidth
            entryWinX  = event.locationInWindow.x
            entryValue = lastSetValue
        }
        entryWinX  = event.locationInWindow.x
        entryValue = value
        updateLabel()
        onChanged?(value)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isBlocked else { return }
        if !isHovering {
            isHovering = true
            frame.size.width = maxSliderWidth
            entryWinX  = event.locationInWindow.x
            entryValue = value
        }
        let delta  = event.locationInWindow.x - entryWinX
        let scaled = Double(delta / maxSliderWidth)
        value      = max(0, min(1, entryValue + scaled))
        lastSetValue = value
        updateLabel()
        onChanged?(value)
    }

    override func mouseUp(with event: NSEvent) {
        window?.isMovable = true
        let localX = convert(event.locationInWindow, from: nil).x
        if abs(localX - _mouseDownX) < 4 { action?() }
        isTracking = false
        if !isHovering { startIdleTimer() }
    }
}

// ================================================================
//  VolumePopup - volume overlay
// ================================================================
final class VolumePopup: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    var onChanged: ((Double) -> Void)?
    var onDismiss: (() -> Void)?
    private var value: Double = Double(PPController.defaultVolume)
    private var isTracking = false
    private let label = PLabel()
    private let barLength: Int = 10
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        
        label.alignment = .left
        label.font = PhotonFont.chromeNs()
        addSubview(label)
        
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func setValue(_ v: Double) {
        guard !isTracking else { return }
        value = max(0, min(1, v))
        updateLabel()
    }
    
    /// Re-apply the current face; called by SpineUI's LayoutEngine observer
    /// because this label has no VariationBroadcaster listener of its own.
    func refreshFont() {
        label.font = PhotonFont.chromeNs()
    }

    private func updateLabel() {
        let vol = Int(round(value * 100))
        let stepPerChar = 100 / barLength
        let filled = Int(round(Double(vol) / Double(stepPerChar)))
        let bar = String(repeating: "—", count: filled) + String(repeating: " ", count: barLength - filled)
        label.stringValue = "\(bar) \(vol)"
    }
    
    override func layout() {
        super.layout()
        label.frame = bounds
        updateLabel()
    }
    
    private func xToCharIndex(_ x: CGFloat) -> Int {
        let charWidth = PhotonFont.chromeCharWidth
        let index = Int(floor(x / charWidth))
        return max(0, min(barLength - 1, index))
    }
    
    override func mouseEntered(with event: NSEvent) {
    }
    
    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let charIndex = xToCharIndex(location.x)
        let stepPerChar = 100 / barLength
        let newVol = charIndex * stepPerChar + stepPerChar/2
        let newVal = Double(newVol) / 100.0
        
        if abs(newVal - value) > 0.01 {
            value = newVal
            updateLabel()
            onChanged?(value)
        }
    }
    
    override func mouseExited(with event: NSEvent) {
    }
    
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 || event.clickCount == 2 {
            onDismiss?()
            return
        }
        
        isTracking = true
        let location = convert(event.locationInWindow, from: nil)
        let charIndex = xToCharIndex(location.x)
        let stepPerChar = 100 / barLength
        let newVol = charIndex * stepPerChar + stepPerChar/2
        value = Double(newVol) / 100.0
        updateLabel()
        onChanged?(value)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let charIndex = xToCharIndex(location.x)
        let stepPerChar = 100 / barLength
        let newVol = charIndex * stepPerChar + stepPerChar/2
        value = Double(newVol) / 100.0
        updateLabel()
        onChanged?(value)
    }
    
    override func mouseUp(with event: NSEvent) {
        isTracking = false
    }
}

// ================================================================
//  DropdownList - track and language selection
// ================================================================
final class DropdownList: NSView {
    var onSelect:        ((Int) -> Void)?
    var onToggleVisible: ((Bool) -> Void)?
    var onDismissed:     (() -> Void)?
    var onLiveCaptionRowHoverEnter: ((NSRect) -> Void)?
    var onLiveCaptionRowHoverExit: (() -> Void)?
    var subVisible = true

    private var trackIds:  [Int]   = []
    private var ROW: CGFloat { PhotonFont.chromeLineH }
    private var totalRows          = 0
    private var topIndex           = 0
    private var scrollAccum: CGFloat = 0
    private var allRows:   [DropRow] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    func populate(_ tracks: [(id: Int, title: String)], type: String = "", maxH: CGFloat = 400,
                  liveCaptionOn: Bool = false, selectedId: Int? = nil,
                  disabledTrackIds: Set<Int> = [],
                  showLiveCaptionLabel: Bool = false, liveCaptionModel: String = "auto",
                  liveCaptionLanguage: String? = nil) {
        allRows.forEach { $0.removeFromSuperview() }
        allRows = []
        trackIds = tracks.map { $0.id }
        topIndex = 0
        scrollAccum = 0

        struct RowDef { let text: String; let kind: Kind; let trackIdx: Int
            enum Kind { case toggle, spacer, track }
        }
        var rows: [RowDef] = []
        if type == "sub" {
            rows.append(.init(text: "", kind: .spacer, trackIdx: -1))
            rows.append(.init(text: subVisible ? "off" : "on", kind: .toggle, trackIdx: -1))
            rows.append(.init(text: "", kind: .spacer, trackIdx: -1))
        }
        for (i, t) in tracks.enumerated() {
            rows.append(.init(text: t.title.isEmpty ? "track \(t.id)" : t.title,
                              kind: .track, trackIdx: i))
        }

        totalRows = rows.count
        let visRows = max(1, Int(floor(maxH / ROW)))
        frame.size.height = CGFloat(min(visRows, totalRows)) * ROW

        let longestTitle = rows.map { $0.text }.max(by: { $0.count < $1.count }) ?? ""
        let textW = (longestTitle as NSString).size(withAttributes: [.font: PhotonFont.chromeNs()]).width
        frame.size.width = max(textW + PhotonFont.chromePad * 4, PhotonFont.chromeCharW * 10)

        for (i, row) in rows.enumerated() {
            let isLiveCaptionRow = row.kind == .track && row.trackIdx >= 0
                && trackIds[row.trackIdx] == -998
            let dr = isLiveCaptionRow
                ? DropRow.makeLiveCaptionRow(showBullet: liveCaptionOn, idx: i, height: ROW,
                                              showLabel: showLiveCaptionLabel, model: liveCaptionModel,
                                              language: liveCaptionLanguage)
                : DropRow(text: row.text, idx: i, height: ROW)
            dr.autoresizingMask = [.width]
            if isLiveCaptionRow {
                dr.onHoverEnter = { [weak self, weak dr] in
                    guard let self = self, let dr = dr else { return }
                    self.onLiveCaptionRowHoverEnter?(dr.frame)
                }
                dr.onHoverExit = { [weak self] in
                    self?.onLiveCaptionRowHoverExit?()
                }
            }
            switch row.kind {
            case .toggle:
                dr.setToggleStyle()
                dr.onTap = { [weak self] _ in
                    guard let self = self else { return }
                    self.subVisible.toggle()
                    self.onToggleVisible?(self.subVisible)
                    self.dismiss()
                }
            case .spacer:
                dr.alphaValue = 0
            case .track:
                let ti = row.trackIdx
                if disabledTrackIds.contains(trackIds[ti]) { dr.setEnabled(false) }
                if let selectedId = selectedId, self.trackIds[ti] == selectedId {
                    dr.setSelected(true)
                }
                dr.onTap = { [weak self] _ in
                    guard let self = self else { return }
                    let finalId = self.trackIds[ti]
                    print("✅ [DROPDOWN OK] Row selected. Sent ID: \(finalId)")
                    self.onSelect?(finalId)
                    self.dismiss()
                }
            }
            allRows.append(dr)
            addSubview(dr)
        }
        layoutRows()
    }

    private func layoutRows() {
        let maxVisible = Int(frame.height / ROW)
        let maxIdx = max(0, totalRows - maxVisible)
        topIndex = max(0, min(maxIdx, topIndex))
        
        let visH = frame.height
        for (i, dr) in allRows.enumerated() {
            let rowIdx = i - topIndex
            let y = visH - CGFloat(rowIdx + 1) * ROW
            
            dr.frame = CGRect(x: 0, y: y, width: frame.width, height: ROW)
            
            dr.isHidden = (rowIdx < 0 || rowIdx >= maxVisible)
        }
    }

    override func scrollWheel(with e: NSEvent) {
        guard e.scrollingDeltaY != 0 else { return }
        // Traditional wheels report lines, precise trackpads report pixels.
        scrollAccum += e.hasPreciseScrollingDeltas ? e.scrollingDeltaY:e.scrollingDeltaY*ROW
        let step = ROW * 0.4
        
        var changed = false
        while scrollAccum >  step { topIndex -= 1; scrollAccum -= step; changed = true }
        while scrollAccum < -step { topIndex += 1; scrollAccum += step; changed = true }
        
        if changed {
            let maxVisible = Int(frame.height / ROW)
            topIndex = max(0, min(max(0, totalRows - maxVisible), topIndex))
            layoutRows()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view != nil {
        } else {
        }
        return view
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }) { [weak self] in
            self?.onDismissed?()
            self?.removeFromSuperview()
        }
    }

    func dimItem(at rowIndex: Int) {
        guard rowIndex >= 0 && rowIndex < allRows.count else { return }
        allRows[rowIndex].setDimmed(true)
    }

    func unDimItem(at rowIndex: Int) {
        guard rowIndex >= 0 && rowIndex < allRows.count else { return }
        allRows[rowIndex].setDimmed(false)
    }

    func pulseLiveRow(to opacity: CGFloat) {
        guard let liveIdx = trackIds.firstIndex(of: -998), liveIdx < allRows.count else { return }
        let row = allRows[liveIdx]
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            row.setBulletOpacity(opacity)
        }, completionHandler: {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.30
                row.setBulletOpacity(0.55)
            }
        })
    }

    func syncLiveRowBullet(to isOn: Bool) {
        guard let liveIdx = trackIds.firstIndex(of: -998), liveIdx < allRows.count else { return }
        let row = allRows[liveIdx]
        if isOn {
            row.addBullet(height: ROW)
            row.setBulletOpacity(0.55)
        } else {
            row.removeBullet()
        }
    }

    func syncLiveRowLabel(model: String, language: String?, showLabel: Bool) {
        guard let liveIdx = trackIds.firstIndex(of: -998), liveIdx < allRows.count else { return }
        allRows[liveIdx].setLiveCaptionLabel(model: model, language: language, showLabel: showLabel)
    }
}

// ================================================================
//  DropRow - dropdown row
// ================================================================
final class DropRow: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    var onTap: ((Int) -> Void)?
    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    private let idx: Int
    private var lbl: PLabel

    private var bulletLbl: PLabel?

    private var isSelected = false
    private var isEnabled = true

    init(text: String, idx: Int, height: CGFloat) {
        self.idx = idx
        lbl = PLabel(text)
        super.init(frame: .zero); wantsLayer = true
        lbl.alignment = .left
        lbl.frame = CGRect(x: PhotonFont.chromeGap, y: 0, width: max(PhotonFont.chromeCharW * 60, 400), height: height)
        addSubview(lbl)
        alphaValue = 1.0
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))

        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self = self else { return }
            if self.isSelected {
                self.lbl.font = PhotonFont.chromeCt(wght: 900)
            } else {
                self.lbl.font = PhotonFont.chromeNsDriven(view: self, profile: .row)
            }
            self.bulletLbl?.font = PhotonFont.chromeNsDriven(view: self, profile: .row)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        lbl.font = selected ? PhotonFont.chromeCt(wght: 900) : PhotonFont.chromeCt()
    }

    static func makeLiveCaptionRow(showBullet: Bool, idx: Int, height: CGFloat,
                                    showLabel: Bool = false, model: String = "auto",
                                    language: String? = nil) -> DropRow {
        let row = DropRow(text: Self.liveCaptionRowText(showLabel: showLabel, model: model, language: language),
                           idx: idx, height: height)
        if showBullet { row.addBullet(height: height) }
        return row
    }

    static func liveCaptionRowText(showLabel: Bool, model: String, language: String?) -> String {
        guard showLabel else { return "live" }
        var parts: [String] = []
        if model != "auto" { parts.append(model) }
        if let language = language { parts.append(language) }
        guard !parts.isEmpty else { return "live" }
        return "live (\(parts.joined(separator: ", ")))"
    }

    func setLiveCaptionLabel(model: String, language: String?, showLabel: Bool) {
        let newText = Self.liveCaptionRowText(showLabel: showLabel, model: model, language: language)
        let old = lbl
        let new = PLabel(newText)
        new.alignment = old.alignment
        new.frame = old.frame
        new.font = isSelected ? PhotonFont.chromeCt(wght: 900) : PhotonFont.chromeCt()
        new.shadow = old.shadow
        new.textColor = old.textColor
        addSubview(new, positioned: .above, relativeTo: old)
        old.removeFromSuperview()
        lbl = new
    }

    func addBullet(height: CGFloat) {
        guard bulletLbl == nil else { return }
        let bullet = PLabel("•")
        bullet.alignment = .left
        bullet.textColor = NSColor(red: 0.86, green: 0.08, blue: 0.24, alpha: 1.0)
        let bulletW = PhotonFont.chromeCharW * 1.6
        bullet.frame = CGRect(x: PhotonFont.chromeGap, y: 0, width: bulletW, height: height)
        addSubview(bullet)
        bulletLbl = bullet
        lbl.frame.origin.x += bulletW
    }

    func removeBullet() {
        guard let bullet = bulletLbl else { return }
        let bulletW = bullet.frame.width
        bullet.removeFromSuperview()
        bulletLbl = nil
        lbl.frame.origin.x -= bulletW
    }

    func setBulletOpacity(_ opacity: CGFloat) {
        bulletLbl?.animator().alphaValue = opacity
    }

    override func mouseEntered(with e: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = 1.0
        }
        lbl.shadow = PPController.globalShadow
        onHoverEnter?()
    }

    override func mouseExited(with e: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = 0.85
        }
        lbl.shadow = PPController.globalShadow
        onHoverExit?()
    }

    override func mouseDown(with e: NSEvent) { if isEnabled { onTap?(idx) } }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        alphaValue = enabled ? 1.0 : 0.35
    }

    func setToggleStyle() {
        lbl.textColor = NSColor(white: 0.55, alpha: 1)
    }

    func setDimmed(_ dimmed: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().alphaValue = dimmed ? 0.35 : 0.85
        }
    }
}

// ================================================================
//  SpineUI - vertical playback controls
// ================================================================
final class SpineUI: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    weak var playerView: (AnyObject & PlayerProtocol)?
    var onIPC: ((String) -> Void)?
    var onSubVisibilityChanged: ((Bool) -> Void)?
    var getTrackList: ((String, @escaping ([(id:Int, title:String)]) -> Void) -> Void)?
    
    var isPGSCodec: Bool = false
    
    var onSearchOpenSubtitles: ((String) -> Void)?
    var onExportSrcSubtitle: (() -> Void)?
    var canExportSrcSubtitle: (() -> Bool)?
    var currentSubtitleSearchStatus: (() -> String?)?

    var onFoldToggle: ((String) -> Void)?

    private var foldableHUDLayers: [(layer: CATextLayer, section: String)] = []

    private var foldClickMonitor: Any?

    var onToggleLiveCaption: ((String?) -> Bool)?

    var onSelectLiveCaptionModel: ((String) -> Void)?

    var currentLiveCaptionModel: String = "medium"

    private(set) var currentLiveCaptionLanguage: String? = nil

    var showLiveCaptionModelLanguageLabel: Bool = true

    private(set) var liveCaptionOn: Bool = false

    func forceLiveCaptionOff() {
        liveCaptionOn = false
    }

    func pulseLiveCaptionBullet() {
        guard let drop = activeDropdown as? DropdownList else { return }
        let level = CGFloat(ScreenCaptureEngine.shared.currentAudioLevel)
        let target = 0.35 + 0.65 * level
        drop.pulseLiveRow(to: target)
    }
    
    private var PAD:   CGFloat { PhotonFont.chromePad }
    private var BTN_H: CGFloat { PhotonFont.chromeLineH }
    private var BTN_W: CGFloat { PhotonFont.chromeCharW + PhotonFont.chromeGap }

    var spineWidth: CGFloat { PhotonFont.chromePad * 2 + PhotonFont.chromeCharW + PhotonFont.chromeGap }
    
    private let titleContainerLayer = CALayer()
    private let titleLayer   = CATextLayer()
    private var titleText    = ""
    private var isHovering   = false
    
    private var osdVisible   = false
    private var osdLayers:   [CATextLayer] = []
    private var osdStrings:  [String]      = []
    
    private weak var volumePopup:    VolumePopup?
    weak var activeDropdown: NSView?
    private var settingsOpen = false
    private var subVisible   = true
    
    let btnQ  = TrafficTextBtn(short:"Q", full:"Quit",
                               color:NSColor(red:0.98,green:0.37,blue:0.34,alpha:1), tip:"close")
    let btnM  = TrafficTextBtn(short:"M", full:"Minimize",
                               color:NSColor(red:0.98,green:0.73,blue:0.12,alpha:1), tip:"minimize")
    let btnFS = TrafficTextBtn(short:"F", full:"Fullscreen",
                               color:NSColor(red:0.20,green:0.78,blue:0.35,alpha:1), tip:"tam ekran")
    
    let btnP   = TrafficTextBtn(short:"P", full:"Pause", color:.white, tip:"Duraklat")
    let btnB   = TrafficTextBtn(short:"B", full:"Back",       color:.white, tip:"geri -10s")
    let btnFwd = TrafficTextBtn(short:"F", full:"Forward",    color:.white, tip:"ileri +10s")
    let btnV = VolumeSliderBtn()
    let btnS   = TrafficTextBtn(short:"S", full:"Settings",   color:.white, tip:"ayarlar")
    
    let btnT   = TrafficTextBtn(short:"C", full:"Caption",   color:NSColor(white:0.7,alpha:1), tip:"subtitles")
    let btnA   = TrafficTextBtn(short:"A", full:"Audio",      color:NSColor(white:0.7,alpha:1), tip:"audio track")
    let btnO   = TrafficTextBtn(short:"O", full:"Osd",        color:NSColor(white:0.7,alpha:1), tip:"osd");let btnVid = TrafficTextBtn(short:"V", full:"Video", color:NSColor(white:0.7,alpha:1), tip:"video")
    
    private var streamControlsVisible = false
    private var streamControlLayers: [(layer: CATextLayer, action: () -> Void, frame: CGRect, baseText: String, hoverLabel: String, cmd: String?)] = []
    private var hoveredGlyphIndex: Int? = nil
    private var glyphHoverTimer: Timer?
    private var glyphFeedbackTimers: [Int: Timer] = [:]

    var torrentStalling: Bool = false {
        didSet {
            guard torrentStalling != oldValue else { return }
            applyStallColoring()
        }
    }
    var torrentStalledPiece: Int? = nil
    var torrentWindowActive: Bool = false

    func reportTorrentCommandFeedback(forCmd cmd: String, text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.showCommandFeedback(forCmd: cmd, text: text)
        }
    }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.needsLayout = true
            // Non-tick surfaces: the volume popup label has no broadcaster
            // listener, and the OSD/HUD layer pools re-apply fonts only on
            // content events; refresh both deterministically on a face change.
            self.titleLayer.font = PhotonFont.chromeCt()
            if self.titleLayer.fontSize != PhotonFont.chromeSize { self.titleLayer.fontSize = PhotonFont.chromeSize }
            self.volumePopup?.refreshFont()
            self.applyVariationToOSDLayers()
        }
        registerForDraggedTypes([.fileURL])

        foldClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, event.clickCount == 1,
                  !self.foldableHUDLayers.isEmpty,
                  event.window === self.window else { return event }
            guard let parent = self.superview else { return event }
            let pt = parent.convert(event.locationInWindow, from: nil)
            for item in self.foldableHUDLayers {
                // Layers are torn down and rebuilt on every HUD redraw;
                // an entry whose layer already left the hierarchy is stale
                // and must not fire.
                guard item.layer.superlayer != nil else { continue }
                let realW  = item.layer.preferredFrameSize().width
                let origin = item.layer.frame.origin
                let hitFrame = CGRect(x: origin.x, y: origin.y,
                                       width: realW, height: item.layer.frame.height)
                if hitFrame.contains(pt) {
                    self.onFoldToggle?(item.section)
                    return nil
                }
            }
            return event
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let m = foldClickMonitor { NSEvent.removeMonitor(m) }
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return superview?.performDragOperation(sender) ?? false
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        let v = super.hitTest(point)
        if v != nil { return v }
        
        if streamControlsVisible {
            for item in streamControlLayers {
                if item.frame.contains(point) {
                    item.action()
                    return self
                }
            }
        }

        
        let (botY, topY) = titleArea()
        if point.y >= botY && point.y <= topY && point.x >= 0 && point.x <= bounds.width {
            return self
        }
        return nil
    }
    
    private func build() {
        wantsLayer = true
        // I24: the spine extends outside its bounds; never clip the view or layer.
        clipsToBounds = false
        layer?.masksToBounds = false
        
        titleLayer.fontSize        = PhotonFont.chromeSize
        titleLayer.foregroundColor = NSColor.white.cgColor
        titleLayer.contentsScale   = NSScreen.main?.backingScaleFactor ?? 2
        titleLayer.isWrapped       = false
        titleLayer.truncationMode  = .end
        titleLayer.font            = PhotonFont.chromeCt()
        titleLayer.alignmentMode   = .left
        titleLayer.transform       = CATransform3DMakeRotation(.pi / 2, 0, 0, 1)
        
        titleLayer.shadowColor   = NSColor.black.cgColor
        titleLayer.shadowRadius  = PPController.shadowRadius
        titleLayer.shadowOpacity = PPController.shadowOpacity
        titleLayer.shadowOffset  = .zero
        
        titleContainerLayer.masksToBounds = true
        vrChromeContainer.anchorPoint = .zero // Match the subtitle origin-based sublayer transform.
        vrChromeReplicator.instanceCount = 1
        vrChromeReplicator.addSublayer(vrChromeContainer)
        layer?.addSublayer(vrChromeReplicator)
        vrChromeContainer.addSublayer(titleContainerLayer)
        titleContainerLayer.addSublayer(titleLayer)

        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self = self, self.isEffectivelyVisible, !self.osdVisible else { return }
            let newFont = PhotonFont.chromeCtDriven(view: self, profile: .title)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            PhotonFont.setIfChanged(newFont, on: self.titleLayer)
            CATransaction.commit()
        }

        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self, userInfo: nil))
        
        btnQ.action = { [weak self] in self?.playerView?.closeWindow() }
        btnQ.shiftAction = {
            (NSApp.delegate as? AppDelegate)?.menuRestartQuit()
        }
        btnM.action  = { [weak self] in
            self?.playerView?.miniaturizeWindow()
            self?.window?.alphaValue = 0
        }
        btnM.setAlt(full: "Music", action: { [weak self] in
            (self?.playerView as? PlayerViewStub)?.controller?.toggleMusicMode()
        })
        btnFS.action = { [weak self] in self?.playerView?.toggleFullScreen() }
        
        btnB.action   = { [weak self] in self?.playerView?.seekRelative(-10) }
        btnP.action   = { [weak self] in self?.playerView?.togglePlay() }
        btnFwd.action = { [weak self] in self?.playerView?.seekRelative(10) }
        
        btnV.action = nil
        btnV.onChanged = { [weak self] v in
            self?.playerView?.volume = Float(v)
            self?.onIPC?("{\"command\":[\"set_property\",\"volume\",\(Int(v*100))]}")
        }
        
        btnS.action = { [weak self] in self?.toggleSettings() }
        
        btnT.action = { [weak self] in
            guard let self = self else { return }
            self.showTrackDropdown(type: "sub", near: self.btnT)
        }
        btnA.action = { [weak self] in
            guard let self = self else { return }
            self.showTrackDropdown(type: "audio", near: self.btnA)
        }
        
        btnO.action = { [weak self] in
            guard let self = self else { return }
            self.closeSettings()
            self.toggleOSD()
        };btnVid.action = { [weak self] in self?.showVideoDropdown() }
        
        [btnT, btnA, btnVid, btnO].forEach { $0.isHidden = true; $0.alphaValue = 0.85 }
        [btnQ, btnM, btnFS, btnB, btnP, btnFwd, btnV, btnS, btnT, btnA, btnVid, btnO].forEach { addSubview($0) }
    }
    
    // MARK: - Layout
    
    private var _updatingWidth = false

    // The vertical title's available length depends on the spine height; make sure a height change
    // (window <-> fullscreen) always re-runs layout so the title is re-fitted.
    private var lastLaidOutHeight: CGFloat = -1
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !_updatingWidth, abs(newSize.height - lastLaidOutHeight) > 0.5 {
            lastLaidOutHeight = newSize.height
            needsLayout = true
        }
    }

    // 180d stereo chrome: spine HUD title + OSD text rows live in this
    // container inside a replicator; instanceCount 2 mirrors them into the
    // right eye in VR (visual only - replicator replicas are never
    // hit-testable, so hit-testing stays on instance 0). Outside VR a single
    // instance: no behavior change.
    // AppKit controls are sibling NSViews, not children of titleContainerLayer. The parent mirrors
    // their rendered bitmap, keeping the real controls and hit testing on the original left eye.
    var vrControlViews: [NSView] { [btnQ, btnM, btnFS, btnB, btnP, btnFwd, btnV, btnS, btnT, btnA, btnVid, btnO] }
    private let vrChromeReplicator = CAReplicatorLayer()
    private let vrChromeContainer = CALayer()
    private var trackedUITilt=0.0; private var trackedUITiltCenter=NSPoint.zero; private var trackedUIOffset:CGFloat=0
    private var trackedUIFitScale:CGFloat=1,trackedUIClip=true
    private var trackedUITranslation=NSPoint.zero,trackedUIReplica:NSPoint?
    func setTrackedUITilt(_ angle:Double,center:NSPoint,translation:NSPoint = .zero,replica:NSPoint? = nil,fitScale:CGFloat = 1,clipToBounds:Bool = true) {
        trackedUIFitScale=fitScale;trackedUIClip=clipToBounds;trackedUITranslation=translation;trackedUIReplica=replica
        trackedUITilt=angle;trackedUITiltCenter=center; let c=CGFloat(cos(angle)),s=CGFloat(sin(angle)),x=center.x,y=center.y
        let scale=fitScale.isFinite && fitScale>0 ? fitScale:1
        var t=CATransform3DMakeRotation(CGFloat(angle),0,0,1); t.m11*=scale;t.m12*=scale;t.m21*=scale;t.m22*=scale
        t.m41=x-scale*(c*x-s*y)+trackedUIOffset+translation.x;t.m42=y-scale*(s*x+c*y)+translation.y
        CATransaction.begin();CATransaction.setDisableActions(true);vrChromeContainer.sublayerTransform=t
        if let replica {vrChromeReplicator.instanceTransform=CATransform3DMakeTranslation(replica.x,replica.y,0)}
        vrChromeContainer.masksToBounds=clipToBounds && vrChromeReplicator.instanceCount>1
        CATransaction.commit()
    }
    private let trackedOutputBandMask=CAShapeLayer()
    func setTrackedUIOutputClip(_ rect:CGRect?) {
        guard let rect else {if vrChromeContainer.mask === trackedOutputBandMask {vrChromeContainer.mask=nil};return}
        let path=CGMutablePath();path.addRect(rect)
        trackedOutputBandMask.path=path;trackedOutputBandMask.fillColor=NSColor.black.cgColor
        trackedOutputBandMask.frame=vrChromeContainer.bounds;vrChromeContainer.mask=trackedOutputBandMask
    }
    /// PPController-level stereo container for chrome in superview
    /// coordinates (photon HUD rows, mpv OSD lines, HUD scroll indicator).
    weak var vrParentChromeContainer: CALayer?

    /// Block 180 3d: stereo replication. shiftX = left-to-right eye band
    /// translation in points. In VR the container clips to the view bounds
    /// (this view sits inside the left eye's band); outside VR clipping is
    /// off - identical to the pre-180d direct parenting.
    func setVRChrome(on: Bool, shiftX: CGFloat, leftOffset: CGFloat = 0, rightOffset: CGFloat = 0) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setVRChrome(on: on, shiftX: shiftX,leftOffset:leftOffset,rightOffset:rightOffset) }
            return
        }
        vrChromeReplicator.instanceCount = on ? 2 : 1
        trackedUIOffset=on ? leftOffset:0
        if abs(trackedUITilt)<1e-10 || !on {
            setTrackedUITilt(on ? trackedUITilt:0,center:trackedUITiltCenter,translation:trackedUITranslation,replica:trackedUIReplica,fitScale:trackedUIFitScale,clipToBounds:trackedUIClip)
            if trackedUIClip {
                vrChromeReplicator.instanceTransform=CATransform3DMakeTranslation(shiftX+(on ? rightOffset-leftOffset:0),0,0)
                vrChromeContainer.masksToBounds=on
            }
        } // While tilted, retain the last complete common map until the parent republishes it.
    }

    /// 180d/v2 trace surface: the ACTUAL committed child-content union
    /// INTERSECTED with the actual clip rect (view-local coordinates), the
    /// clip rect itself (nil when not clipping), child count, and the
    /// replicator's committed instance x-translation.
    func vrChromeTraceState() -> (content: CGRect?, children: Int, clip: CGRect?, tx: CGFloat) {
        var u: CGRect? = nil
        let kids = vrChromeContainer.sublayers ?? []
        for k in kids { u = u.map { $0.union(k.frame) } ?? k.frame }
        let clip: CGRect? = vrChromeContainer.masksToBounds ? vrChromeContainer.bounds : nil
        if let c = clip, let r = u { let i = r.intersection(c); u = i.isNull ? nil : i }
        return (u, kids.count, clip, vrChromeReplicator.instanceTransform.m41)
    }

    override func layout() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        super.layout()
        if let hostLayer = layer {
            vrChromeReplicator.frame = hostLayer.bounds
            vrChromeContainer.frame  = hostLayer.bounds
        }
        if !_updatingWidth {
            let sw = spineWidth
            if abs(frame.size.width - sw) > 0.5 {
                _updatingWidth = true
                var f = frame; f.size.width = sw; frame = f
                _updatingWidth = false
            }
        }
        // I25: titleArea() reads button frames; keep button layout first.
        layoutButtons()
        layoutTitle()
        if osdVisible { layoutOSD() }
        layoutLiveStatusHUD()
        layoutPhotonHUD()
    }
    
    private func layoutButtons() {
        let h = bounds.height
        let pad = PAD
        let row = BTN_H
        let width = BTN_W
        let gap5 = PhotonFont.chromeValue(5)
        let inset2 = PhotonFont.chromeValue(2)
        let gap10 = PhotonFont.chromeValue(10)
        
        btnQ.frame  = NSRect(x:pad, y:h-pad+gap5-row,       width:width, height:row)
        btnM.frame  = NSRect(x:pad, y:h-pad+gap5-row*2,     width:width, height:row)
        btnFS.frame = NSRect(x:pad, y:h-pad+gap5-row*3,     width:width, height:row)
        
        let vW = (btnV.isHovering || btnV.isTracking) ? btnV.frame.size.width : width
        btnV.frame  = NSRect(x:pad-inset2, y:h-pad+gap5-row*4, width:vW, height:row)
        
        var y = pad
        btnP.frame   = NSRect(x:pad, y:y-gap5, width:width, height:row); y += row
        btnFwd.frame = NSRect(x:pad, y:y-gap5, width:width, height:row); y += row
        btnB.frame   = NSRect(x:pad, y:y-gap5, width:width, height:row); y += row
        btnS.frame   = NSRect(x:pad, y:y-gap5, width:width, height:row); y += row
        
        
        btnT.frame = NSRect(x:pad, y:y-gap5, width:width, height:row); y += row
        btnA.frame = NSRect(x:pad, y:y-gap5, width:width, height:row); y += row; btnVid.frame = NSRect(x:pad, y:y-gap5, width:width, height:row); y += row
        btnO.frame = NSRect(x:pad, y:y-gap10, width:width, height:row+gap5)
    }
    
    func updatePlayPauseState(isPlaying: Bool) {
        let full = isPlaying ? "Pause" : "Play"
        btnP.updateFullText(full)
    }
    
    // MARK: - Settings toggle
    
    private func toggleSettings() {
        settingsOpen.toggle()
        let hidden = !settingsOpen
        [btnT, btnA, btnVid, btnO].forEach { $0.isHidden = hidden }
        needsLayout = true
        if !settingsOpen {
            activeDropdown?.removeFromSuperview(); activeDropdown = nil
            hideLiveCaptionMenus()
        }
    }
    
    func closeSettings() {
        guard settingsOpen else { return }
        settingsOpen = false
        [btnT, btnA, btnVid, btnO].forEach { $0.isHidden = true }
        needsLayout = true
        hideLiveCaptionMenus()
    }
    
    // MARK: - Volume Popup
    
    private func toggleVolumePopup() {
        if let existing = volumePopup {
            existing.removeFromSuperview()
            volumePopup = nil
            return
        }
        
        guard let parent = superview else { return }
        
        let popup = VolumePopup(frame: .zero)
        
        let vInParent = convert(btnV.frame, to: parent)
        
        let barLength: CGFloat = 10
        let spaceForNumbers: CGFloat = 3
        let totalChars = barLength + 1 + spaceForNumbers
        popup.frame = CGRect(
            x: vInParent.maxX - 62,
            y: vInParent.minY,
            width: totalChars * PhotonFont.chromeCharWidth,
            height: BTN_H
        )
        
        popup.setValue(Double(playerView?.volume ?? PPController.defaultVolume))
        popup.onChanged = { [weak self] v in
            self?.playerView?.volume = Float(v)
            self?.onIPC?("{\"command\":[\"set_property\",\"volume\",\(Int(v*100))]}")
        }
        
        popup.onDismiss = { [weak self, weak popup] in
            popup?.removeFromSuperview()
            self?.volumePopup = nil
        }
        
        parent.addSubview(popup)
        volumePopup = popup
    }
    
    func updateVolume(_ v: Float) {
        volumePopup?.setValue(Double(v))
        btnV.value = Double(v)
        btnV.lastSetValue = Double(v)
    }
    
    // MARK: - Track Dropdown
    
    private func showLanguageSelector(near anchor: NSRect) {
        let languages: [(code: String, label: String)] = [
            ("en", "English"),
            ("tr", "Turkish"),
            ("de", "Deutsch"),
            ("fr", "Français"),
            ("es", "Español"),
            ("it", "Italiano"),
            ("pt", "Português"),
            ("ru", "Русский"),
            ("ja", "日本語"),
            ("ko", "한국어"),
            ("zh", "中文"),
            ("ar", "العربية"),
        ]
        
        guard let window = self.window, let rootView = window.contentView else { return }
        
        let anchorInRoot = self.convert(
            CGPoint(x: self.PAD + self.BTN_W + 6, y: anchor.maxY),
            to: rootView
        )
        
        let drop = DropdownList(frame: .zero)
        drop.wantsLayer = true
        drop.layer?.zPosition = 5001
        
        let indexedItems = languages.enumerated().map { (id: $0.offset + 1, title: $0.element.label) }
        drop.populate(indexedItems, type: "", maxH: anchorInRoot.y)
        
        let availableW = rootView.bounds.width - anchorInRoot.x - 4
        drop.frame.size.width = min(drop.frame.width, max(availableW, 80))
        drop.frame.origin = CGPoint(
            x: anchorInRoot.x,
            y: anchorInRoot.y - drop.frame.height
        )
        
        self.btnV.isBlocked = true
        drop.onDismissed = { [weak self] in self?.btnV.isBlocked = false }
        
        drop.onSelect = { [weak self] idx in
            guard let self = self else { return }
            let langCode = idx >= 1 && idx <= languages.count
            ? languages[idx - 1].code : "en"
            print("[SpineUI] Language selected: \(langCode)")
            // Keep caption controls open so search/load status stays visible.
            self.activeDropdown?.removeFromSuperview()
            self.activeDropdown = nil
            self.onSearchOpenSubtitles?(langCode)
            // DropdownList dismisses itself after onSelect. Publish status
            // on the next turn, after its own animation/cleanup is scheduled.
            DispatchQueue.main.async { [weak self] in
                guard let self, let status = self.currentSubtitleSearchStatus?() else { return }
                self.showSubtitleSearchStatus(status)
            }
        }
        
        drop.alphaValue = 0.0
        rootView.addSubview(drop, positioned: .above, relativeTo: nil)
        self.activeDropdown = drop
        
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            drop.animator().alphaValue = 0.9
        }
    }
    
    private func showLiveCaptionLanguageSelector(near anchor: NSRect) {
        if liveCaptionPicker != nil { return }

        let languages: [(code: String?, label: String)] = [
            (nil,  "Auto"),
            ("en", "English"),
            ("tr", "Turkish"),
            ("de", "Deutsch"),
            ("fr", "Français"),
            ("es", "Español"),
            ("it", "Italiano"),
            ("pt", "Português"),
            ("ru", "Русский"),
            ("ja", "日本語"),
            ("ko", "한국어"),
            ("zh", "中文"),
            ("ar", "العربية"),
        ]

        guard let window = self.window, let rootView = window.contentView else { return }

        let anchorInRoot = self.convert(
            CGPoint(x: anchor.maxX + 6, y: anchor.maxY),
            to: rootView
        )

        let drop = DropdownList(frame: .zero)
        drop.wantsLayer = true
        drop.layer?.zPosition = 5001

        let indexedItems = languages.enumerated().map { (id: $0.offset + 1, title: $0.element.label) }
        let selectedLangId = languages.firstIndex { $0.code == self.currentLiveCaptionLanguage }.map { $0 + 1 }
        drop.populate(indexedItems, type: "", maxH: anchorInRoot.y, selectedId: selectedLangId)

        let availableW = rootView.bounds.width - anchorInRoot.x - 4
        drop.frame.size.width = min(drop.frame.width, max(availableW, 80))
        drop.frame.origin = CGPoint(
            x: anchorInRoot.x,
            y: anchorInRoot.y - drop.frame.height
        )

        self.btnV.isBlocked = true
        drop.onDismissed = { [weak self] in
            self?.btnV.isBlocked = false
            self?.liveCaptionPicker = nil
        }

        drop.onSelect = { [weak self] idx in
            guard let self = self else { return }
            let langCode: String? = (idx >= 1 && idx <= languages.count) ? languages[idx - 1].code : nil
            print("[SpineUI] Live caption language selected: \(langCode ?? "auto")")
            self.currentLiveCaptionLanguage = langCode
            let wasOn = self.liveCaptionOn
            self.liveCaptionOn = self.onToggleLiveCaption?(langCode) ?? self.liveCaptionOn
            if wasOn != self.liveCaptionOn {
                (self.activeDropdown as? DropdownList)?.syncLiveRowBullet(to: self.liveCaptionOn)
            }
            (self.activeDropdown as? DropdownList)?.syncLiveRowLabel(
                model: self.currentLiveCaptionModel, language: self.currentLiveCaptionLanguage,
                showLabel: self.showLiveCaptionModelLanguageLabel)
            self.hideLiveCaptionMenus()
        }

        drop.alphaValue = 0.0
        rootView.addSubview(drop, positioned: .above, relativeTo: nil)
        self.liveCaptionPicker = drop

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            drop.animator().alphaValue = 0.9
        }
    }

    private var liveCaptionSubmenu: DropdownList?
    private weak var liveCaptionPicker: DropdownList?

    private func hideLiveCaptionMenus() {
        liveCaptionPicker?.removeFromSuperview()
        liveCaptionPicker = nil
        liveCaptionSubmenu?.removeFromSuperview()
        liveCaptionSubmenu = nil
    }

    private func showLiveCaptionSubmenu(near anchor: NSRect) {
        guard let window = self.window, let rootView = window.contentView else { return }
        if liveCaptionSubmenu != nil { return }

        let items = [(id: 1, title: "Model"), (id: 2, title: "Language")]

        let anchorInRoot = self.convert(
            CGPoint(x: anchor.maxX + 6, y: anchor.maxY),
            to: rootView
        )

        let drop = DropdownList(frame: .zero)
        drop.wantsLayer = true
        drop.layer?.zPosition = 5001
        drop.populate(items, type: "", maxH: anchorInRoot.y)
        drop.frame.origin = CGPoint(x: anchorInRoot.x, y: anchorInRoot.y - drop.frame.height)

        for case let row as DropRow in drop.subviews {
            row.onHoverEnter = { [weak self, weak row] in
                guard let self = self, let row = row else { return }
                let rowFrameInSelf = self.convert(row.frame, from: drop)
                self.liveCaptionPicker?.removeFromSuperview()
                self.liveCaptionPicker = nil
                if row === drop.subviews.compactMap({ $0 as? DropRow }).first {
                    self.showLiveCaptionModelSelector(
                        near: rowFrameInSelf, installedModels: LiveCaptionController.shared.installedModels())
                } else {
                    self.showLiveCaptionLanguageSelector(near: rowFrameInSelf)
                }
            }
        }

        drop.onDismissed = { [weak self] in self?.liveCaptionSubmenu = nil }
        drop.alphaValue = 0.0
        rootView.addSubview(drop, positioned: .above, relativeTo: nil)
        liveCaptionSubmenu = drop

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            drop.animator().alphaValue = 0.9
        }
    }

    func showLiveCaptionModelSelector(near anchor: NSRect, installedModels: [String]) {
        if liveCaptionPicker != nil { return }

        let displayNames: [String: String] = [
            "large-v3": "Large v3", "large-v2": "Large v2", "large": "Large",
            "medium": "Medium", "small": "Small", "base": "Base", "tiny": "Tiny",
        ]
        let models: [(name: String, label: String)] =
            [("auto", "Auto")] + installedModels.map { ($0, displayNames[$0] ?? $0) }

        guard let window = self.window, let rootView = window.contentView else { return }

        let anchorInRoot = self.convert(
            CGPoint(x: anchor.maxX + 6, y: anchor.maxY),
            to: rootView
        )

        let drop = DropdownList(frame: .zero)
        drop.wantsLayer = true
        drop.layer?.zPosition = 5001

        let indexedItems = models.enumerated().map { (id: $0.offset + 1, title: $0.element.label) }
        let selectedModelId = models.firstIndex { $0.name == self.currentLiveCaptionModel }.map { $0 + 1 }
        drop.populate(indexedItems, type: "", maxH: anchorInRoot.y, selectedId: selectedModelId)

        let availableW = rootView.bounds.width - anchorInRoot.x - 4
        drop.frame.size.width = min(drop.frame.width, max(availableW, 80))
        drop.frame.origin = CGPoint(
            x: anchorInRoot.x,
            y: anchorInRoot.y - drop.frame.height
        )

        self.btnV.isBlocked = true
        drop.onDismissed = { [weak self] in
            self?.btnV.isBlocked = false
            self?.liveCaptionPicker = nil
        }

        drop.onSelect = { [weak self] idx in
            guard let self = self else { return }
            guard idx >= 1 && idx <= models.count else { return }
            let chosen = models[idx - 1].name
            print("[SpineUI] Live caption model selected: \(chosen)")
            self.currentLiveCaptionModel = chosen
            self.onSelectLiveCaptionModel?(chosen)
            (self.activeDropdown as? DropdownList)?.syncLiveRowLabel(
                model: self.currentLiveCaptionModel, language: self.currentLiveCaptionLanguage,
                showLabel: self.showLiveCaptionModelLanguageLabel)
            self.hideLiveCaptionMenus()
        }

        drop.alphaValue = 0.0
        rootView.addSubview(drop, positioned: .above, relativeTo: nil)
        self.liveCaptionPicker = drop

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            drop.animator().alphaValue = 0.9
        }
    }

    // Source search now selects the best release itself. Keep the user
    // informed without a second selection menu.
    func showSubtitleSearchStatus(_ status: String) {
        guard settingsOpen, let rootView = window?.contentView else { return }
        activeDropdown?.removeFromSuperview()
        let anchor = convert(CGPoint(x: PAD + BTN_W + 6, y: btnT.frame.maxY), to: rootView)
        let drop = DropdownList(frame: .zero)
        drop.wantsLayer = true
        drop.layer?.zPosition = 5001
        drop.populate([(id: 0, title: status)], type: "", maxH: anchor.y)
        drop.onSelect = { [weak drop] _ in drop?.removeFromSuperview() }
        drop.frame.origin = CGPoint(x: anchor.x, y: anchor.y - drop.frame.height)
        drop.frame.size.width = min(drop.frame.width, max(rootView.bounds.width - anchor.x - 4, 80))
        rootView.addSubview(drop, positioned: .above, relativeTo: nil)
        activeDropdown = drop
    }

    // I28 / TRAP-01: cap dropdown width in root coordinates; anchor uses PAD + BTN_W here.
    private func showTrackDropdown(type: String, near anchorBtn: NSView) {
        activeDropdown?.removeFromSuperview(); activeDropdown = nil
        hideLiveCaptionMenus()
        
        getTrackList?(type) { [weak self] rawTracks in
            guard let self = self else { return }
            guard let window = self.window, let rootView = window.contentView else { return }
            
            var tracks = rawTracks
            if type == "sub" {
                tracks.insert((id: -999, title: "src"), at: 0)
                tracks.insert((id: -997, title: "sve"), at: 1)
                tracks.insert((id: -998, title: "live"), at: 2)
            }
            
            guard !tracks.isEmpty else { return }
            
            let anchorInRoot = self.convert(
                CGPoint(x: self.PAD + self.BTN_W + 6, y: anchorBtn.frame.maxY),
                to: rootView
            )
            
            let drop = DropdownList(frame: .zero)
            drop.subVisible = self.subVisible
            drop.wantsLayer = true
            drop.layer?.zPosition = 5000
            
            let disabled: Set<Int> = type == "sub" && self.canExportSrcSubtitle?() != true ? [-997] : []
            drop.populate(tracks, type: type, maxH: anchorInRoot.y, liveCaptionOn: self.liveCaptionOn,
                          disabledTrackIds: disabled,
                          showLiveCaptionLabel: self.showLiveCaptionModelLanguageLabel,
                          liveCaptionModel: self.currentLiveCaptionModel,
                          liveCaptionLanguage: self.currentLiveCaptionLanguage)

            drop.onLiveCaptionRowHoverEnter = { [weak self, weak drop] rowFrame in
                guard let self = self, let drop = drop else { return }
                let rowFrameInSelf = self.convert(rowFrame, from: drop)
                self.showLiveCaptionSubmenu(near: rowFrameInSelf)
            }

            drop.onToggleVisible = { [weak self] visible in
                guard let self = self else { return }
                self.subVisible = visible
                self.onSubVisibilityChanged?(visible)
            }
            
            let availableW = rootView.bounds.width - anchorInRoot.x - 4
            drop.frame.size.width = min(drop.frame.width, max(availableW, 80))
            drop.frame.origin = CGPoint(
                x: anchorInRoot.x,
                y: anchorInRoot.y - drop.frame.height
            )
            
            self.btnV.isBlocked = true
            drop.onDismissed = { [weak self] in self?.btnV.isBlocked = false }
            
            drop.onSelect = { [weak self] trackId in
                guard let self = self else { return }
                
                if trackId == -999 {
                    self.activeDropdown?.removeFromSuperview()
                    self.activeDropdown = nil
                    self.showLanguageSelector(near: anchorBtn.frame)
                    return
                }

                if trackId == -997 {
                    self.activeDropdown?.removeFromSuperview()
                    self.activeDropdown = nil
                    self.onExportSrcSubtitle?()
                    return
                }

                if trackId == -998 {
                    self.activeDropdown?.removeFromSuperview()
                    self.activeDropdown = nil
                    self.hideLiveCaptionMenus()
                    if self.liveCaptionOn {
                        self.liveCaptionOn = self.onToggleLiveCaption?(nil) ?? self.liveCaptionOn
                    } else {
                        self.onSelectLiveCaptionModel?(self.currentLiveCaptionModel)
                        self.liveCaptionOn = self.onToggleLiveCaption?(self.currentLiveCaptionLanguage) ?? self.liveCaptionOn
                    }
                    return
                }
                
                let isAudio = type.lowercased().hasPrefix("aud")
                let prop = isAudio ? "aid" : "sid"
                
                print("🎯 [DEBUG CLICK] Tip: \(type) -> Prop: \(prop), ID: \(trackId)")
                
                let cmd = "{\"command\":[\"set_property\",\"\(prop)\",\(trackId)]}"
                self.onIPC?(cmd)
                if !isAudio {
                    self.subVisible=true;self.onSubVisibilityChanged?(true)
                    self.onIPC?(#"{"command":["set_property","sub-visibility",false]}"#)
                    self.onIPC?(#"{"command":["set_property","secondary-sub-visibility",false]}"#)
                }
                
                self.closeSettings()
                self.activeDropdown?.removeFromSuperview()
                self.activeDropdown = nil
            }
            
            drop.alphaValue = 0.0
            rootView.addSubview(drop, positioned: .above, relativeTo: nil)
            self.activeDropdown = drop
            
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                drop.animator().alphaValue = 0.9
            }
        }
    }
    
    /// Root/VR event routes must not consume a wheel over the caption list.
    func scrollTrackDropdownIfNeeded(with event:NSEvent)->Bool {
        guard let drop=activeDropdown,drop.superview != nil,
              drop.bounds.contains(drop.convert(event.locationInWindow,from:nil)) else {return false}
        drop.scrollWheel(with:event);return true
    }

    // MARK: - Title & Marquee
    
    private var titleDragStart:    CGFloat = 0
    private var titleScrollOffset: CGFloat = 0
    private var titleTextWidth:    CGFloat = 0
    private var isDraggingTitle    = false
    
    private func titleArea() -> (botY: CGFloat, topY: CGFloat) {
        let topBtn:  NSView = btnV
        let botBtn:  NSView = settingsOpen ? btnO : btnS
        let topY = topBtn.frame.minY - PhotonFont.chromeGap
        let botY = PhotonFont.chromeValue(5) + botBtn.frame.maxY + PhotonFont.chromeGap
        return (botY, topY)
    }
    
    private func layoutTitle() {
        guard !osdVisible else { titleContainerLayer.isHidden = true; return }
        titleContainerLayer.isHidden = false
        if titleLayer.fontSize != PhotonFont.chromeSize { titleLayer.fontSize = PhotonFont.chromeSize }
        titleLayer.removeAllAnimations()
        
        let (botY, topY) = titleArea()
        let avail = topY - botY
        GeomTrace.log("spine.title", "bounds=\(Int(bounds.width))x\(Int(bounds.height)) avail=\(Int(avail)) chars=\(titleText.count)")
        guard avail > 20 else { titleContainerLayer.isHidden = true; return }
        
        titleContainerLayer.frame = CGRect(x: 0, y: botY, width: bounds.width, height: avail)
        
        let lineH: CGFloat = titleLayer.fontSize + PhotonFont.chromeValue(10)
        let cx: CGFloat    = PAD + PhotonFont.chromeValue(14)
        
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: PhotonFont.chromeNs(),
            .kern: PhotonFont.chromeTrackingPx,
        ]
        let fullWidth = (titleText as NSString).size(withAttributes: textAttrs).width
        titleTextWidth = fullWidth
        
        if fullWidth > avail {
            let charStep = PhotonFont.chromeCharW
            
            if isDraggingTitle || isHovering {
                let maxScroll = max(0, fullWidth - avail)
                let charCount = Int(maxScroll / charStep) + 1
                let charIndex = Int(round(-titleScrollOffset / charStep))
                let clampedCharIndex = max(0, min(charCount, charIndex))
                
                
                let startChar = clampedCharIndex
                var endChar = titleText.count
                var displayText = ""
                
                for i in startChar..<titleText.count {
                    let test = String(titleText.dropFirst(startChar).prefix(i - startChar + 1))
                    let testW = (test as NSString).size(withAttributes: textAttrs).width
                    if testW > avail { break }
                    endChar = i + 1
                }
                
                if startChar > 0 {
                    displayText = "" + String(titleText.dropFirst(startChar).prefix(endChar - startChar))
                } else {
                    displayText = String(titleText.prefix(endChar))
                }
                
                if endChar < titleText.count {
                    displayText += "…"
                }
                
                titleLayer.string = displayText
                titleLayer.anchorPoint = CGPoint(x: 0.0, y: 0.5)
                titleLayer.position    = CGPoint(x: cx, y: 0)
                titleLayer.bounds = CGRect(x: 0, y: 0, width: avail + 4, height: lineH)
            } else {
                titleScrollOffset = 0
                var fitCount = titleText.count
                while fitCount > 1 {
                    let sub = String(titleText.prefix(fitCount)) + "…"
                    let subW = (sub as NSString).size(withAttributes: textAttrs).width
                    if subW <= avail { break }
                    fitCount -= 1
                }
                titleLayer.string = String(titleText.prefix(fitCount)) + "…"
                titleLayer.anchorPoint = CGPoint(x: 0.0, y: 0.5)
                titleLayer.position    = CGPoint(x: cx, y: 0)
                titleLayer.bounds = CGRect(x: 0, y: 0, width: avail + 4, height: lineH)
            }
        } else {
            titleScrollOffset = 0
            titleLayer.string = titleText
            titleLayer.anchorPoint = CGPoint(x: 0.0, y: 0.5)
            titleLayer.position    = CGPoint(x: cx, y: 0)
            titleLayer.bounds = CGRect(x: 0, y: 0, width: avail + 4, height: lineH)
        }
    }
    
    private var lastVariationEventTimestamp: TimeInterval = -1   // one NSEvent can arrive twice (PPController forward + own mouseMoved)
    func handleExternalMouseMoved(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        if let winPt = window.map({ convert(pt, to: $0.contentView) }) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
        guard e.timestamp != lastVariationEventTimestamp else { return }
        lastVariationEventTimestamp = e.timestamp
        applyVariationToOSDLayers()
        updateGlyphHover(selfPt: pt)
    }

    func handleExternalMouseExited() {
        clearGlyphHover()
    }

    override func mouseMoved(with e: NSEvent) {
        handleExternalMouseMoved(with: e)
        let pt = convert(e.locationInWindow, from: nil)
        let (botY, topY) = titleArea()
        let inTitle = pt.x >= 0 && pt.x <= bounds.width && pt.y >= botY && pt.y <= topY
        if inTitle != isHovering {
            isHovering = inTitle
            if !osdVisible { layoutTitle() }
        }
        
        if inTitle && !osdVisible {
            let avail = topY - botY
            if titleTextWidth > avail {
                NSCursor.resizeUpDown.set()
            } else {
                NSCursor.arrow.set()
            }
        } else {
            NSCursor.arrow.set()
        }
    }
    
    override func mouseExited(with e: NSEvent) {
        let wasHovering = isHovering
        isHovering = false
        NSCursor.arrow.set()
        clearGlyphHover()
        if wasHovering && !osdVisible { layoutTitle() }
    }
    
    private var titleDragStartOffset: CGFloat = 0

    override func mouseDown(with e: NSEvent) {
        let pt = convert(e.locationInWindow, from: nil)
        
        if e.modifierFlags.contains(.command) && btnP.frame.contains(pt) {
            guard let ppc = superview as? PPController else { return }
            ppc.toggleMusicMode()
            return
        }
        
        let (botY, topY) = titleArea()
        let inTitle = pt.x >= 0 && pt.x <= bounds.width && pt.y >= botY && pt.y <= topY
        if inTitle && titleTextWidth > (topY - botY) {
            isDraggingTitle = true
            titleDragStart = pt.y
            titleDragStartOffset = titleScrollOffset
        } else {
            isDraggingTitle = false
            super.mouseDown(with: e)
        }
    }

    override func mouseDragged(with e: NSEvent) {
        guard isDraggingTitle else { return }
        let pt = convert(e.locationInWindow, from: nil)
        let delta = pt.y - titleDragStart
        titleScrollOffset = titleDragStartOffset + delta
        layoutTitle()
    }

    override func scrollWheel(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let (botY, topY) = titleArea()
        let inTitle = pt.x >= 0 && pt.x <= bounds.width && pt.y >= botY && pt.y <= topY
        guard inTitle else { return }
        titleScrollOffset += event.scrollingDeltaY
        layoutTitle()
    }
    
    override func mouseUp(with e: NSEvent) {
        let wasDragging = isDraggingTitle
        isDraggingTitle = false
        if wasDragging && !osdVisible { layoutTitle() }
    }
    
    // TRAP-08: poll repeats the same title every tick; change-guard preserves scrolling.
    func setTitle(_ s: String) {
        guard s != titleText else { return }
        titleText = s
        titleScrollOffset = 0
        titleLayer.string = s
        if !osdVisible { layoutTitle() }
    }
    
    // MARK: - OSD
    
    func toggleOSD() {
        // The HUD state and layer tree share the main-queue owner.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.toggleOSD() }
            return
        }
        osdVisible.toggle()
        if osdVisible {
            titleContainerLayer.isHidden = true
            if let pv = playerView { refreshOSD(string: pv.osdString()) }
        } else {
            clearOSDLayers()
            layoutTitle()
        }
    }
    
    func clearMPVOSD(animated: Bool = false) {
        // The HUD state and layer tree share the main-queue owner.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.clearMPVOSD(animated: animated) }
            return
        }
        mpvOSDGeneration &+= 1
        let generation = mpvOSDGeneration
        photonHUDGeneration &+= 1
        let pgeneration = photonHUDGeneration
        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.5)
            mpvOSDLayers.forEach { $0.opacity = 0 }
            photonHUDLayers.forEach { $0.opacity = 0 }
            CATransaction.commit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Independent owners, independent fences: a newer magnet
                // redraw must not strand zeroed photon layers, and a newer
                // photon frame must not strand mpv layers.
                if self.mpvOSDGeneration == generation {
                    self.mpvOSDLayers.forEach { $0.removeFromSuperlayer() }
                    self.mpvOSDLayers = []
                }
                if self.photonHUDGeneration == pgeneration {
                    self.teardownPhotonHUD()
                }
            }
        } else {
            mpvOSDLayers.forEach { $0.removeFromSuperlayer() }
            mpvOSDLayers = []
            teardownPhotonHUD()
        }
        mpvOSDTimer?.invalidate()
        mpvOSDTimer = nil
        magnetGridRowCount = 0
        hudUpperRowCount = 0
    }
    
    func refreshOSD(string: String) {
        // The HUD state and layer tree share the main-queue owner.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refreshOSD(string: string) }
            return
        }
        guard osdVisible else { return }
        let parts = splitOSD(string)
        let oldStrings = osdStrings
        if parts.count != osdLayers.count {
            clearOSDLayers()
            parts.forEach { s in
                let l = makeOSDLayer(s)
                vrChromeContainer.addSublayer(l)
                osdLayers.append(l)
            }
        } else {
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for (i, text) in parts.enumerated() where oldStrings[safe: i] != text {
                osdLayers[i].string = text
            }
            CATransaction.commit()
        }
        // Count changes clear the old cache; publish new strings after that reset.
        osdStrings = parts
        layoutOSD()
    }
    
    // TRAP-03: OSD layers use self coordinates; screen placement uses superview coordinates.
    private func layoutOSD() {
        guard osdVisible, !osdLayers.isEmpty else { return }
        let lineH: CGFloat = PhotonFont.chromeSize + 6
        let x: CGFloat = PhotonFont.chromeCharW + PhotonFont.chromePad * 2
        let startY = btnQ.frame.maxY
        
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, l) in osdLayers.enumerated() {
            let text = osdStrings[safe: i] ?? ""
            let tw   = min(CGFloat(text.count) * PhotonFont.chromeCharWidth + 8, 250)
            let y    = startY - CGFloat(i + 1) * lineH
            let anchor = CGPoint(x: 0, y: 0)
            let position = CGPoint(x: x, y: y)
            let bounds = CGRect(x: 0, y: 0, width: tw, height: lineH)
            if l.anchorPoint != anchor { l.anchorPoint = anchor }
            if l.position != position { l.position = position }
            if l.bounds != bounds { l.bounds = bounds }
        }
        CATransaction.commit()
    }
    
    private func clearOSDLayers() { osdLayers.forEach { $0.removeFromSuperlayer() }; osdLayers = []; osdStrings = [] }
    
    private func makeOSDLayer(_ t: String) -> CATextLayer {
        let l = CATextLayer()
        l.string         = t
        l.fontSize       = PhotonFont.chromeSize
        l.foregroundColor = NSColor.white.cgColor
        l.contentsScale  = NSScreen.main?.backingScaleFactor ?? 2
        l.isWrapped      = false
        l.font           = PhotonFont.chromeCt()
        l.alignmentMode  = .left
        l.transform      = CATransform3DIdentity
        l.shadowColor   = NSColor.black.cgColor
        l.shadowRadius  = PPController.shadowRadius
        l.shadowOpacity = PPController.shadowOpacity
        l.shadowOffset  = .zero
        return l
    }
    
    private func hudProximity(_ layer: CALayer, in parent: NSView?) -> Double {
        let p = VariationBroadcaster.shared.proximity(to: layer, in: parent, radius: 100)
        return 0.5 + (1.0 - p) * 0.75
    }

    private func hudAudioBlend(_ p: Double, audioLevel: Double) -> Double {
        max(0.0, min(1.0, (p + audioLevel) / 2.0))
    }

    private func applyVariationToOSDLayers() {
        guard !osdLayers.isEmpty || !mpvOSDLayers.isEmpty || !streamControlLayers.isEmpty || !photonHUDLayers.isEmpty else { return }

        let audioLevel = Double(ScreenCaptureEngine.shared.currentAudioLevel)
        let parent = self.superview

        for l in osdLayers {
            let p = hudProximity(l, in: parent)
            PhotonFont.setIfChanged(PhotonFont.chromeCtDriven(p: p, t_audio: hudAudioBlend(p, audioLevel: audioLevel), size: nil), on: l)
        }
        for l in mpvOSDLayers {
            let p = hudProximity(l, in: parent)
            PhotonFont.setIfChanged(PhotonFont.chromeCtDriven(p: p, t_audio: hudAudioBlend(p, audioLevel: audioLevel), size: nil), on: l)
        }
        for l in photonHUDLayers {
            let p = hudProximity(l, in: parent)
            PhotonFont.setIfChanged(PhotonFont.chromeCtDriven(p: p, t_audio: hudAudioBlend(p, audioLevel: audioLevel), size: nil), on: l)
        }
        for (i, item) in streamControlLayers.enumerated() {
            guard i != hoveredGlyphIndex else { continue }
            let p = hudProximity(item.layer, in: parent)
            PhotonFont.setIfChanged(PhotonFont.chromeCtDriven(p: p, t_audio: hudAudioBlend(p, audioLevel: audioLevel), size: nil), on: item.layer)
        }
    }

    private func applyStallColoring() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, item) in streamControlLayers.enumerated() {
            if i < 3 {
                let color: NSColor
                switch i {
                case 0:
                    color = NSColor(red:0.98, green:0.37, blue:0.34, alpha:1)
                case 1:
                    color = NSColor(red:0.98, green:0.73, blue:0.12, alpha:1)
                case 2:
                    color = NSColor(red:0.20, green:0.78, blue:0.35, alpha:1)
                default:
                    color = NSColor.white.withAlphaComponent(0.9)
                }
                item.layer.foregroundColor = torrentStalling && i < 3
                    ? color.cgColor
                    : color.withAlphaComponent(1.00).cgColor
            } else {
                item.layer.foregroundColor = NSColor(white: 0.5, alpha: 1).cgColor
            }
        }
        CATransaction.commit()
    }
    
    private func colorForGlyph(at index: Int, active: Bool = true) -> CGColor {
        let colors: [NSColor] = [
            NSColor(red:0.98, green:0.37, blue:0.34, alpha:1),
            NSColor(red:0.98, green:0.73, blue:0.12, alpha:1),
            NSColor(red:0.20, green:0.78, blue:0.35, alpha:1),
        ]
        guard index < 3 else { return NSColor(white: 0.5, alpha: 1).cgColor }
        return active ? colors[index].cgColor : colors[index].withAlphaComponent(0.45).cgColor
    }

    private func showCommandFeedback(forCmd cmd: String, text: String) {
        guard let idx = streamControlLayers.firstIndex(where: { $0.cmd?.lowercased() == cmd.lowercased() || (cmd == "stop" && $0.cmd == nil) }) else { return }
        let item = streamControlLayers[idx]

        glyphFeedbackTimers[idx]?.invalidate()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        item.layer.string = item.baseText + "  " + text
        item.layer.foregroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        CATransaction.commit()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            guard let self = self, self.streamControlLayers.indices.contains(idx) else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.streamControlLayers[idx].layer.string = self.streamControlLayers[idx].baseText
            if self.torrentStalling && idx < 3 {
                self.streamControlLayers[idx].layer.foregroundColor = colorForGlyph(at: idx, active: torrentStalling)
            } else {
                self.streamControlLayers[idx].layer.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            }
            CATransaction.commit()
            self.glyphFeedbackTimers.removeValue(forKey: idx)
        }
        glyphFeedbackTimers[idx] = timer
    }

    private func updateGlyphHover(selfPt pt: NSPoint) {
        guard streamControlsVisible, !streamControlLayers.isEmpty else {
            clearGlyphHover()
            return
        }

        let ox = self.frame.origin.x
        let oy = self.frame.origin.y

        var found: Int? = nil
        for (i, item) in streamControlLayers.enumerated() {
            let selfFrame = item.frame.offsetBy(dx: -ox, dy: -oy)
            if selfFrame.contains(pt) {
                found = i
                break
            }
        }

        if found == hoveredGlyphIndex { return }

        if let prev = hoveredGlyphIndex {
            glyphHoverTimer?.invalidate()
            glyphHoverTimer = nil
            if streamControlLayers.indices.contains(prev) {
                let prevItem = streamControlLayers[prev]
                if glyphFeedbackTimers[prev] == nil {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    prevItem.layer.string = prevItem.baseText
                    prevItem.layer.foregroundColor = colorForGlyph(at: prev, active: torrentStalling)
                    let p = hudProximity(prevItem.layer, in: self.superview)
                    let audioLevel = Double(ScreenCaptureEngine.shared.currentAudioLevel)
                    PhotonFont.setIfChanged(PhotonFont.chromeCtDriven(p: p, t_audio: hudAudioBlend(p, audioLevel: audioLevel), size: nil), on: prevItem.layer)
                    CATransaction.commit()
                }
            }
        }

        hoveredGlyphIndex = found

        guard let idx = found else { return }
        let item = streamControlLayers[idx]
        let hoverLabel = item.hoverLabel
        let baseText   = item.baseText

        guard glyphFeedbackTimers[idx] == nil else { return }

        let fullText = baseText + "  " + hoverLabel
        let chars = Array(fullText)
        let startIdx = baseText.count

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        item.layer.string = String(chars.prefix(startIdx + 1))
        item.layer.foregroundColor = NSColor.white.withAlphaComponent(0.95).cgColor
        PhotonFont.setIfChanged(PhotonFont.chromeCtDriven(p: 0.0, t_audio: 0, size: nil), on: item.layer)
        CATransaction.commit()

        var currentIdx = startIdx + 1
        glyphHoverTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] t in
            guard let self = self, self.hoveredGlyphIndex == idx,
                  self.streamControlLayers.indices.contains(idx) else { t.invalidate(); return }
            currentIdx += 1
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.streamControlLayers[idx].layer.string = String(chars.prefix(currentIdx))
            CATransaction.commit()
            if currentIdx >= chars.count { t.invalidate() }
        }
    }

    private func clearGlyphHover() {
        guard let prev = hoveredGlyphIndex else { return }
        hoveredGlyphIndex = nil
        glyphHoverTimer?.invalidate()
        glyphHoverTimer = nil
        guard streamControlLayers.indices.contains(prev) else { return }
        guard glyphFeedbackTimers[prev] == nil else { return }
        let prevItem = streamControlLayers[prev]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        prevItem.layer.string = prevItem.baseText
        prevItem.layer.foregroundColor = colorForGlyph(at: prev, active: torrentStalling)
        let p = hudProximity(prevItem.layer, in: self.superview)
        let audioLevel = Double(ScreenCaptureEngine.shared.currentAudioLevel)
        PhotonFont.setIfChanged(PhotonFont.chromeCtDriven(p: p, t_audio: hudAudioBlend(p, audioLevel: audioLevel), size: nil), on: prevItem.layer)
        CATransaction.commit()
    }

    private func splitOSD(_ s: String) -> [String] {
        let lines = s.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? [s.trimmingCharacters(in: .whitespaces)] : lines
    }
    
    func isOSDVisible() -> Bool { osdVisible }
    
    private var mpvOSDLayers: [CATextLayer] = []
    // Photon HUD lives in its own layer set. The torrent/magnet HUD, transient
    // mpv OSD messages and the photon HUD used to share mpvOSDLayers, so every
    // redraw wiped the other: the two HUDs alternated and the magnet HUD
    // flashed on each refresh. Both must stay visible at the same time.
    private var photonHUDLayers: [CATextLayer] = []
    private var photonHUDStrings: [String] = []
    /// Display metadata only. A route refresh never opens an empty/hidden HUD.
    var photonHUDRoute:(()->(engine:String,sourceIdentity:String,fallbackReason:String?)?)?
    func refreshPhotonHUDRoute() {
        guard !photonHUDStrings.isEmpty,alphaValue > 0.1 else {return}
        layoutPhotonHUD()
    }
    private var photonHUDFirstRow: Int = 0          // scroll offset in whole rows
    private var photonHUDMaxScrollRows: Int = 0
    private var photonHUDScrollAccum: CGFloat = 0
    // Rows currently occupying the HUD top region above the photon HUD:
    // the magnet/torrent stats grid, or a transient mpv/torrent message while
    // it lives. On transient expiry the anchor falls back to the grid baseline.
    private var magnetGridRowCount: Int = 0
    private var hudUpperRowCount: Int = 0
    // Fences delayed fade/teardown against newer photon HUD frames.
    private var photonHUDGeneration: UInt64 = 0
    // Cropped video target in superview coords, kept in sync by
    // PPController.applyVideoFrame. .zero until the first layout: the HUD
    // then falls back to the window bounds, like before.
    var hudCropBounds: CGRect = .zero
    private var mpvOSDTimer: Timer?
    // Main-owned identity fences delayed fade/removal across newer HUD updates.
    private var mpvOSDGeneration: UInt64 = 0
    
    /// Existing WT/MB/transient rows must follow mode/crop changes even without new text.
    private func layoutLiveStatusHUD() {
        guard !mpvOSDLayers.isEmpty else{return}
        let lineH=PhotonFont.chromeSize+6
        let region=StatusHUDPlacement.region(anchorX:frame.minX+PhotonFont.chromeCharW+PhotonFont.chromePad*2,
            anchorY:frame.minY+btnQ.frame.maxY,
            visible:hudCropBounds == .zero ? (superview?.bounds ?? .zero) : hudCropBounds,pad:PAD)
        CATransaction.begin();CATransaction.setDisableActions(true)
        for (i,layer) in mpvOSDLayers.enumerated() {
            layer.frame=CGRect(x:region.minX,y:region.maxY-CGFloat(i+1)*lineH,width:region.width,height:lineH)
            if let j=streamControlLayers.firstIndex(where:{$0.layer === layer}) {
                streamControlLayers[j].frame=CGRect(x:layer.frame.minX,y:layer.frame.minY,
                    width:min(streamControlLayers[j].frame.width,region.width),height:lineH)
            }
        }
        CATransaction.commit()
    }

    func showMPVOSD(_ message: String, animated: Bool = true,duration:TimeInterval=3.0,force:Bool=false) {
        // The HUD state and layer tree share the main-queue owner.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showMPVOSD(message,animated:animated,duration:duration,force:force) }
            return
        }
        guard !message.isEmpty else { return }
        
        guard force || alphaValue > 0.1 else { return }
        
        let lines = message.components(separatedBy: "‖").flatMap { $0.components(separatedBy: "\n") }.filter { !$0.isEmpty }
        let lineH: CGFloat = PhotonFont.chromeSize + 6
        let osdX = self.frame.origin.x + PhotonFont.chromeCharW + PhotonFont.chromePad * 2
        let statusRegion=StatusHUDPlacement.region(anchorX:osdX,anchorY:self.frame.origin.y+self.btnQ.frame.maxY,
            visible:hudCropBounds == .zero ? (superview?.bounds ?? CGRect(x:0,y:0,width:osdX+400,height:1000)) : hudCropBounds,pad:PAD)
        let maxW=statusRegion.width
        let startY=statusRegion.maxY

        let torrentRowMeta: [(hoverLabel: String, cmd: String?)] = [
            ("refresh peers", "REFRESH"),
            ("rewindow",      "REWINDOW"),
            ("skip piece",    "SKIP"),
            ("stop stream",   nil),
        ]

        mpvOSDGeneration &+= 1
        let generation = mpvOSDGeneration

        var preservedText: [Int: String] = [:]
        if !animated && !streamControlLayers.isEmpty {
            for (i, item) in streamControlLayers.enumerated() {
                if i == hoveredGlyphIndex || glyphFeedbackTimers[i] != nil {
                    preservedText[i] = item.layer.string as? String
                }
            }
        }

        mpvOSDLayers.forEach { $0.removeFromSuperlayer() }
        mpvOSDLayers = []
        mpvOSDTimer?.invalidate()
        // foldableHUDLayers is owned by the photon HUD path (layoutPhotonHUD);
        // magnet/transient redraws must not wipe the photon fold targets.

        if animated {
        } else {
            streamControlLayers = []
        }

        for (i, line) in lines.enumerated() {
            var displayLine = line
            var foldSection: String? = nil
            if let tabIdx = line.firstIndex(of: "\t") {
                foldSection = String(line[line.startIndex..<tabIdx])
                displayLine = String(line[line.index(after: tabIdx)...])
            }

            let l = CATextLayer()
            l.string = preservedText[i] ?? displayLine
            if l.fontSize != PhotonFont.chromeSize { l.fontSize = PhotonFont.chromeSize }
            l.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            l.isWrapped = false
            l.font = PhotonFont.chromeCt()
            l.alignmentMode = .left
            l.shadowColor = NSColor.black.cgColor
            l.shadowRadius = PPController.shadowRadius
            l.shadowOpacity = PPController.shadowOpacity
            l.shadowOffset = .zero

            let rowY = startY - CGFloat(i + 1) * lineH
            l.frame = CGRect(x: statusRegion.minX, y: rowY, width: maxW, height: lineH)
            l.opacity = 0
            (vrParentChromeContainer ?? superview?.layer)?.addSublayer(l)
            mpvOSDLayers.append(l)

            // Fold targets are section headers only: headers arrive flush-left,
            // body lines indented. Registering every line made the whole HUD
            // block a fold click target (phantom photon-toggle storms).
            if let section = foldSection, displayLine.first?.isWhitespace == false {
                foldableHUDLayers.append((layer: l, section: section))
            }

            if !animated && i < torrentRowMeta.count {
                let meta = torrentRowMeta[i]
                let cmd = meta.cmd
                let action: () -> Void
                if let cmd = cmd {
                    let ownedMedia = (NSApp.delegate as? AppDelegate)?.currentTorrentURL ?? ""
                    action = { [weak self] in
                        PlayerTorrentEndpoint.withControlURL(for: ownedMedia, path: "/cmd") { url in
                            var req = URLRequest(url: url)
                            req.httpMethod = "POST"
                            req.httpBody = "\(cmd)\n".data(using: .utf8)
                            URLSession.shared.dataTask(with: req).resume()
                        }
                        print("[Torrent] HTTP POST: \(cmd)")
                        self?.showCommandFeedback(forCmd: cmd, text: "sent")
                    }
                } else {
                    action = { [weak self] in
                        self?.playerView?.stopStream()
                    }
                }
                let glyphHitChars: CGFloat = 3
                let hitW = min(glyphHitChars * PhotonFont.chromeCharWidth,
                                CGFloat(displayLine.count) * PhotonFont.chromeCharWidth)
                let hitFrame = CGRect(x: statusRegion.minX, y: rowY, width: hitW, height: lineH)
                streamControlLayers.append((layer: l, action: action, frame: hitFrame,
                                             baseText: displayLine, hoverLabel: meta.hoverLabel, cmd: cmd))
            }

            if animated {
                let fadeIn = CABasicAnimation(keyPath: "opacity")
                fadeIn.fromValue = 0
                fadeIn.toValue = 0.9
                fadeIn.duration = 0.3
                l.add(fadeIn, forKey: "fadeIn")
            }
            l.opacity = 0.9
        }
        
        // Upper-region bookkeeping for the photon HUD anchor. Persistent
        // (non-animated) content is the magnet/torrent HUD family; it stays
        // until replaced or the stream ends. Animated transients borrow the
        // region for their 3s lifetime, then the anchor falls back to the
        // grid baseline (see the fade completion below).
        if animated {
            hudUpperRowCount = lines.count
        } else {
            magnetGridRowCount = lines.count
            hudUpperRowCount = lines.count
        }
        layoutPhotonHUD()

        applyVariationToOSDLayers()
        if !animated { applyStallColoring() }

        if animated {
            mpvOSDTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                guard let self, self.mpvOSDGeneration == generation else { return }
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.4)
                self.mpvOSDLayers.forEach { $0.opacity = 0 }
                CATransaction.commit()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, self.mpvOSDGeneration == generation else { return }
                    self.mpvOSDLayers.forEach { $0.removeFromSuperlayer() }
                    self.mpvOSDLayers = []
                    // Transient expired: the photon HUD anchor returns to the
                    // magnet grid baseline (the grid repaints on the next STATS).
                    let baseline = self.streamControlsVisible ? self.magnetGridRowCount : 0
                    if self.hudUpperRowCount != baseline {
                        self.hudUpperRowCount = baseline
                        self.layoutPhotonHUD()
                    }
                }
            }
        }
    }
    
    
    // MARK: - Photon HUD (dedicated layer set, crop-bounded, scrollable)

    /// Vertical region the photon HUD is allowed to occupy, in superview
    /// coordinates. The spine frame is already aligned to the cropped video
    /// area (PPController.applyVideoFrame), so anchoring the region to the
    /// spine frame keeps the HUD inside the crop in every crop state.
    /// Top: under the spine buttons, shifted one row below the magnet/torrent
    /// HUD while that HUD is open. Bottom: crop bottom.
    private func photonHUDRegion() -> (top: CGFloat, bottom: CGFloat, x: CGFloat, width: CGFloat, lineH: CGFloat) {
        let lineH: CGFloat = PhotonFont.chromeSize + 6
        let osdX = self.frame.origin.x + PhotonFont.chromeCharW + PhotonFont.chromePad * 2
        // The right edge follows the cropped video target, not the whole
        // window: PPController.applyVideoFrame keeps hudCropBounds in sync.
        let rightEdge = hudCropBounds != .zero
            ? hudCropBounds.maxX
            : (superview?.bounds.width ?? osdX + 400)
        let upperOffset = hudUpperRowCount > 0 ? CGFloat(hudUpperRowCount + (streamControlsVisible && magnetGridRowCount > 0 ? 0 : 1)) * lineH : 0
        var top = self.frame.origin.y + self.btnQ.frame.maxY - upperOffset
        var bottom = self.frame.origin.y + 4
        var regionX = osdX
        // P4 (card 713) v8: bound the region on ALL four edges, not just the
        // right edge. With the spine aligned to the crop (landed layout) the
        // bottom/x clamps are inert; the top clamp bites only when the old
        // region would extend above the crop top by (5 - PhotonFont.chromePad)
        // points with no magnet rows open - a pre-existing pixel-class
        // overflow the clamp corrects. Under the v8 mapped branch (zoom/pan
        // divergence) the four-edge clamp keeps the HUD inside the mapped
        // rect; a collapsed region hides the HUD (existing capacity guard).
        if hudCropBounds != .zero {
            top = min(top, hudCropBounds.maxY)
            bottom = max(bottom, hudCropBounds.minY)
            regionX = max(regionX, hudCropBounds.minX)
        }
        let maxW: CGFloat = max(0, rightEdge - regionX - PAD)
        return (top, bottom, regionX, maxW, lineH)
    }

    /// Y (superview coords) exactly one text row below the rows currently
    /// occupying the HUD top region (magnet/torrent grid or a transient
    /// message); the plain spine-top anchor when no upper rows are open.
    /// Shared anchor so an overlay panel can sit directly under the HUD
    /// instead of opening underneath it. Owner 11-16 17:10: the multi-file
    /// magnet selection panel must open one row below the magnet HUD, inside
    /// the player area. Deliberately NOT photonHUDRegion().top: that anchor
    /// drops the gap row while stream controls ride the grid, but the panel
    /// must keep the one-row gap in every HUD state.
    var hudUpperAnchorY: CGFloat {
        let lineH: CGFloat = PhotonFont.chromeSize + 6
        let upperOffset = hudUpperRowCount > 0 ? CGFloat(hudUpperRowCount + 1) * lineH : 0
        return self.frame.origin.y + self.btnQ.frame.maxY - upperOffset
    }

    /// Photon HUD frames arrive via gor-osd with a "section	" prefix on every
    /// line (photon-hud.lua). When the rows do not fit the region the HUD
    /// keeps a whole-row scroll window instead of overflowing the crop: the
    /// window only ever moves in whole rows (pixel-level glyph/shadow
    /// clipping is verified in the Mac receipt).
    /// Separate lifetime, same existing HUD renderer/region. Routine OSD and photon updates cannot erase it.
    private var engineRefusalHUDLine:String?
    func setEngineRefusalHUD(_ line:String?) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setEngineRefusalHUD(line) };return
        }
        engineRefusalHUDLine=line
        layoutPhotonHUD()
    }
    func showPhotonHUD(_ message: String) {
        // The HUD state and layer tree share the main-queue owner.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showPhotonHUD(message) }
            return
        }
        guard !message.isEmpty else { clearPhotonHUD(); return }
        guard alphaValue > 0.1 else { return }

        let lines = message.components(separatedBy: "‖").flatMap { $0.components(separatedBy: "\n") }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { clearPhotonHUD(); return }
        photonHUDGeneration &+= 1
        photonHUDStrings = lines
        layoutPhotonHUD()
    }

    func clearPhotonHUD() {
        // The HUD state and layer tree share the main-queue owner.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.clearPhotonHUD() }
            return
        }
        teardownPhotonHUD()
    }

    /// Main-queue only. Bumps the generation so a delayed animated teardown
    /// (clearMPVOSD(animated: true)) can never wipe fresher HUD content.
    private func teardownPhotonHUD() {
        photonHUDGeneration &+= 1
        photonHUDLayers.forEach { $0.removeFromSuperlayer() }
        photonHUDLayers = []
        photonHUDStrings = []
        if engineRefusalHUDLine != nil {layoutPhotonHUD()}
        photonHUDFirstRow = 0
        photonHUDMaxScrollRows = 0
        photonHUDScrollAccum = 0
        foldableHUDLayers = []
    }

    private func layoutPhotonHUD() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.layoutPhotonHUD() }
            return
        }
        let lines = (engineRefusalHUDLine.map{[$0]} ?? []) + photonHUDStrings
        guard !lines.isEmpty else {
            photonHUDLayers.forEach{$0.removeFromSuperlayer()};photonHUDLayers=[]
            return
        }
        guard (alphaValue > 0.1 || engineRefusalHUDLine != nil), let parentLayer = vrParentChromeContainer ?? superview?.layer else { return }

        let region = photonHUDRegion()
        let regionH = max(0, region.top - region.bottom)
        let capacity = Int(regionH / region.lineH)

        // Region too small for even one whole row, or horizontally empty
        // (extreme crop, the magnet HUD eating the full height, or a tiny
        // window): hide the HUD completely rather than spilling outside the
        // crop. Strings and scroll state survive; the layout recovers when
        // the region returns.
        guard capacity >= 1, region.width > 0 else {
            photonHUDLayers.forEach { $0.removeFromSuperlayer() }
            photonHUDLayers = []
            foldableHUDLayers = []
            photonHUDMaxScrollRows = 0
            return
        }

        let contentCapacity=max(0,capacity-(engineRefusalHUDLine == nil ? 0:1))
        photonHUDMaxScrollRows = max(0, photonHUDStrings.count - contentCapacity)
        photonHUDFirstRow = min(max(photonHUDFirstRow, 0), photonHUDMaxScrollRows)
        let first = photonHUDFirstRow
        let last = min(photonHUDStrings.count, first + contentCapacity)
        let displayedLines=(engineRefusalHUDLine.map{[$0]} ?? []) + Array(photonHUDStrings[first..<last])

        // Rebuild layers only when the visible window size changes; otherwise
        // update strings in place so the 4 Hz refresh never flashes.
        let rebuild = photonHUDLayers.count != displayedLines.count
        if rebuild {
            photonHUDLayers.forEach { $0.removeFromSuperlayer() }
            photonHUDLayers = []
        }
        foldableHUDLayers = []

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for j in 0..<displayedLines.count {
            let line = displayedLines[j]
            var displayLine = line
            var foldSection: String? = nil
            if let tabIdx = line.firstIndex(of: "\t") {
                foldSection = String(line[line.startIndex..<tabIdx])
                displayLine = String(line[line.index(after: tabIdx)...])
            }
            let l: CATextLayer
            if rebuild {
                l = CATextLayer()
                if l.fontSize != PhotonFont.chromeSize { l.fontSize = PhotonFont.chromeSize }
                l.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
                l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
                l.isWrapped = false
                // isWrapped=false alone lets a long line draw past the layer
                // (and past the crop); truncate inside the bounded width.
                l.truncationMode = .end
                l.font = PhotonFont.chromeCt()
                l.alignmentMode = .left
                l.shadowColor = NSColor.black.cgColor
                l.shadowRadius = PPController.shadowRadius
                l.shadowOpacity = PPController.shadowOpacity
                l.shadowOffset = .zero
                l.opacity = 0.9
                parentLayer.addSublayer(l)
                photonHUDLayers.append(l)
            } else {
                l = photonHUDLayers[j]
                // A clearMPVOSD fade that started before this frame zeroed
                // the opacity; the layer survives, so restore it.
                l.opacity = 0.9
            }
            l.string = displayLine
            l.frame = CGRect(x: region.x, y: region.top - CGFloat(j + 1) * region.lineH,
                             width: region.width, height: region.lineH)
            // Fold targets are section headers only: headers arrive flush-left,
            // body lines indented (same rule as showMPVOSD).
            if let section = foldSection, displayLine.first?.isWhitespace == false {
                foldableHUDLayers.append((layer: l, section: section))
            }
        }
        CATransaction.commit()

        GeomTrace.logChanged("hudLayout", String(format: #"{"k":"hudLayout","top":%.0f,"bottom":%.0f,"x":%.0f,"w":%.0f,"cap":%ld,"first":%ld,"max":%ld,"lines":%ld}"#,
            region.top, region.bottom, region.x, region.width,
            capacity, photonHUDFirstRow, photonHUDMaxScrollRows, photonHUDStrings.count))
        applyVariationToOSDLayers()
    }

    /// Scrolls the photon HUD only while the pointer hovers the drawn rows
    /// and the content overflows; outside the rows the event falls through to
    /// the subtitle-position scroll. Returns true when the event was consumed.
    func scrollPhotonHUDIfNeeded(with event: NSEvent, in hostView: NSView) -> Bool {
        guard Thread.isMainThread else { return false }
        guard !photonHUDStrings.isEmpty, photonHUDMaxScrollRows > 0 else { return false }
        let region = photonHUDRegion()
        // Rows are anchored at region.top growing downward; the hover band is
        // exactly the drawn rows, not the empty remainder of the region.
        let bandH = CGFloat(photonHUDLayers.count) * region.lineH
        let rect = CGRect(x: region.x, y: region.top - bandH,
                          width: region.width, height: bandH)
        let pt = hostView.convert(event.locationInWindow, from: nil)
        guard rect.contains(pt) else { return false }

        // Analog feel: trackpads stream precise fractional deltas that
        // accumulate into whole rows; mouse wheels report line units, so the
        // scaling steps one scrollingDeltaY unit per row (the physical notch
        // feel per device is verified in the Mac receipt).
        let dy = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : event.scrollingDeltaY * region.lineH
        // A direction change drops the leftover sub-row so reversal responds
        // immediately instead of paying back the wound-up remainder first.
        if dy != 0, (dy > 0) != (photonHUDScrollAccum > 0) {
            photonHUDScrollAccum = 0
        }
        photonHUDScrollAccum += dy
        // Strict drain: the accumulator never winds up against an end, so
        // reversing at the edge never pays back a residue. Drain both an
        // outward sub-row delta (below) and any arrival at an end (further
        // below), whether the window moved or not.
        let outward = (photonHUDFirstRow == 0 && photonHUDScrollAccum < 0)
            || (photonHUDFirstRow == photonHUDMaxScrollRows && photonHUDScrollAccum > 0)
        if outward { photonHUDScrollAccum = 0 }
        let rows = Int(photonHUDScrollAccum / region.lineH)
        guard rows != 0 else { return true }
        photonHUDScrollAccum -= CGFloat(rows) * region.lineH
        let clamped = min(max(photonHUDFirstRow + rows, 0), photonHUDMaxScrollRows)
        if clamped != photonHUDFirstRow {
            GeomTrace.log("hudScroll", String(format: #"{"k":"hudScroll","v":%ld,"from":%ld,"to":%ld,"max":%ld}"#,
                rows, photonHUDFirstRow, clamped, photonHUDMaxScrollRows))
        }
        photonHUDFirstRow = clamped
        if clamped == 0 || clamped == photonHUDMaxScrollRows { photonHUDScrollAccum = 0 }
        layoutPhotonHUD()
        return true
    }

    /// Test-only HUD scroll drive (active under GOR_TRACE_GEOM=1 via
    /// PPController's harness): applies a whole-row delta through the same
    /// guard, clamp, trace and layout path as the wheel handler. The sub-row
    /// accumulator feel is wheel-only and not exercised here.
    func drivePhotonHUDScrollForTest(rows: Int) {
        guard GeomTrace.on else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.drivePhotonHUDScrollForTest(rows: rows) }
            return
        }
        guard rows != 0, !photonHUDStrings.isEmpty, photonHUDMaxScrollRows > 0 else {
            GeomTrace.log("hudScrollReject", "{\"k\":\"hudScrollReject\",\"v\":\(rows),\"lines\":\(photonHUDStrings.count),\"max\":\(photonHUDMaxScrollRows)}")
            return
        }
        let clamped = min(max(photonHUDFirstRow + rows, 0), photonHUDMaxScrollRows)
        if clamped != photonHUDFirstRow {
            GeomTrace.log("hudScroll", String(format: #"{"k":"hudScroll","v":%ld,"from":%ld,"to":%ld,"max":%ld}"#,
                rows, photonHUDFirstRow, clamped, photonHUDMaxScrollRows))
        }
        photonHUDFirstRow = clamped
        if clamped == 0 || clamped == photonHUDMaxScrollRows { photonHUDScrollAccum = 0 }
        layoutPhotonHUD()
    }

    // MARK: - Stream Controls

    func showStreamControls() {
        // The HUD state and layer tree share the main-queue owner.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.showStreamControls() }
            return
        }
        streamControlsVisible = true
    }

    func hideStreamControls() {
        // The HUD state and layer tree share the main-queue owner.
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.hideStreamControls() }
            return
        }
        streamControlsVisible = false
        streamControlLayers = []
        if magnetGridRowCount != 0 || hudUpperRowCount != 0 {
            magnetGridRowCount = 0
            hudUpperRowCount = 0
            layoutPhotonHUD()
        }
    }

    // MARK: - Axis Mapping

    func showAxisMapping(axes: [(tag: Int, name: String)],
                         autoMapping: [Int: Set<Int>],
                         reversedAxes: Set<Int>,
                         onComplete: @escaping ([Int: Set<Int>], Set<Int>) -> Void,
                         onDismiss: @escaping () -> Void) {
        guard let window = self.window, let rootView = window.contentView else { return }
        activeDropdown?.removeFromSuperview()
        activeDropdown = nil

        let panel = AxisMappingPanel(axes: axes, autoMapping: autoMapping, reversedAxes: reversedAxes)
        panel.wantsLayer = true
        panel.layer?.zPosition = 5000

        let padR: CGFloat = PhotonFont.chromeCharW + PhotonFont.chromePad * 1.5
        let padT: CGFloat = PhotonFont.chromePad / 1.4
        panel.frame.origin = CGPoint(x: padR,
                                     y: bounds.height - padT - panel.frame.height)

        self.btnV.isBlocked = true

        panel.onDismiss = { [weak self] in
            self?.btnV.isBlocked = false
            self?.activeDropdown = nil
            onDismiss()
        }
        panel.onConfirm = { [weak self] mapping, reversed in
            self?.btnV.isBlocked = false
            self?.activeDropdown = nil
            onComplete(mapping, reversed)
        }

        self.activeDropdown = panel
        panel.alphaValue = 0
        rootView.addSubview(panel, positioned: .above, relativeTo: nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0.9
        }
        window.makeFirstResponder(panel)
    }

}

// ================================================================
//  AxisMappingPanel - axis mapping editor
// ================================================================
final class AxisMappingPanel: NSView {
    var onConfirm: (([Int: Set<Int>], Set<Int>) -> Void)?
    var onDismiss: (() -> Void)?

    private let axes: [(tag: Int, name: String)]
    private var signalAssignment: [Int: Int?] = [:]
    private var reversedAssignment: [Int: Bool] = [:]
    private var rows: [AxisMappingRow] = []
    private var confirmRow: AxisMappingRow!

    static let signalLabels: [String] = [
        "0  audio+prox",
        "1  soft-prox",
        "2  inv-prox",
        "3  hard-prox",
        "4  audio",
    ]
    static let noneLabel = "—  (none)"
    static let signalCycleCount = signalLabels.count + 1

    private var ROW: CGFloat { PhotonFont.chromeLineH }

    init(axes: [(tag: Int, name: String)], autoMapping: [Int: Set<Int>], reversedAxes: Set<Int>) {
        self.axes = axes
        var assignment: [Int: Int?] = [:]
        for axis in axes { assignment[axis.tag] = nil }
        for (signalIndex, tags) in autoMapping {
            for tag in tags {
                if assignment.keys.contains(tag) {
                    assignment[tag] = signalIndex
                }
            }
        }
        self.signalAssignment = assignment

        var reversed: [Int: Bool] = [:]
        for axis in axes { reversed[axis.tag] = reversedAxes.contains(axis.tag) }
        self.reversedAssignment = reversed

        let totalRows = axes.count + 1
        let h = CGFloat(totalRows) * PhotonFont.chromeLineH
        let w = max(120, PhotonFont.chromeCharW * 14)
        super.init(frame: CGRect(x: 0, y: 0, width: w, height: h))
        buildRows()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildRows() {
        for (i, axis) in axes.enumerated() {
            let rowY = frame.height - ROW * CGFloat(i + 1)
            let signalIdx: Int? = signalAssignment[axis.tag] ?? nil
            let isReversed = reversedAssignment[axis.tag] ?? false
            let row = AxisMappingRow(
                axisName: axis.name,
                signalIndex: signalIdx,
                reversed: isReversed,
                frame: CGRect(x: 0, y: rowY, width: frame.width, height: ROW)
            )
            row.autoresizingMask = [.width]
            row.onTap = { [weak self] in self?.cycleSignal(at: i) }
            row.onToggleReverse = { [weak self] in self?.toggleReverse(at: i) }
            addSubview(row)
            rows.append(row)
        }

        let confirmY: CGFloat = 0
        confirmRow = AxisMappingRow(
            text: "apply",
            frame: CGRect(x: 0, y: confirmY, width: frame.width, height: ROW),
            isConfirm: true
        )
        confirmRow.autoresizingMask = [.width]
        confirmRow.setActive(hasAnyAssignment())
        confirmRow.onTap = { [weak self] in self?.commit() }
        addSubview(confirmRow)
    }

    private func cycleSignal(at index: Int) {
        let tag = axes[index].tag
        let current: Int? = signalAssignment[tag] ?? nil
        let next: Int?
        if let c = current {
            let n = c + 1
            next = n < AxisMappingPanel.signalLabels.count ? n : nil
        } else {
            next = 0
        }
        signalAssignment[tag] = next
        rows[index].setSignal(next)
        confirmRow.setActive(hasAnyAssignment())
    }

    private func hasAnyAssignment() -> Bool {
        signalAssignment.values.contains { $0 != nil }
    }

    private func toggleReverse(at index: Int) {
        let tag = axes[index].tag
        let next = !(reversedAssignment[tag] ?? false)
        reversedAssignment[tag] = next
        rows[index].setReversed(next)
    }

    private func commit() {
        guard hasAnyAssignment() else { return }
        var mapping: [Int: Set<Int>] = [:]
        for (tag, signalIdx) in signalAssignment {
            guard let si = signalIdx else { continue }
            mapping[si, default: []].insert(tag)
        }
        let reversed = Set(reversedAssignment.compactMap { tag, isRev in isRev ? tag : nil })
        dismiss(then: { [weak self] in self?.onConfirm?(mapping, reversed) })
    }

    private func dismiss(then completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 0
        }) { [weak self] in
            self?.onDismiss?()
            self?.removeFromSuperview()
            completion?()
        }
    }

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss() }
        else { super.keyDown(with: event) }
    }
}

// ================================================================
//  AxisMappingRow - axis mapping row
// ================================================================
final class AxisMappingRow: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    var onTap: (() -> Void)?
    var onToggleReverse: (() -> Void)?

    private let nameLabel  = CATextLayer()
    private let signalLabel = CATextLayer()
    private let hoverLabel = CATextLayer()
    private var reversedGlyph: ReversedGlyph?
    private let isConfirm:  Bool
    private var isActive = true
    private var isReversedState = false

    static let reverseHoverText = "reverse axis"

    convenience init(text: String, frame: NSRect, isConfirm: Bool) {
        self.init(axisName: text, signalIndex: nil, reversed: false, frame: frame, isConfirmRow: isConfirm)
    }

    init(axisName: String, signalIndex: Int?, reversed: Bool, frame: NSRect, isConfirmRow: Bool = false) {
        self.isConfirm = isConfirmRow
        super.init(frame: frame)
        wantsLayer = true

        func configLayer(_ lbl: CATextLayer, text: String) {
            lbl.contentsScale  = NSScreen.main?.backingScaleFactor ?? 2
            lbl.alignmentMode  = .left
            lbl.isWrapped      = false
            lbl.truncationMode = .end
            lbl.string         = text
            lbl.foregroundColor = NSColor.white.cgColor
            lbl.fontSize       = PhotonFont.chromeSize
            lbl.font           = PhotonFont.chromeCt()
            lbl.shadowColor    = NSColor.black.cgColor
            lbl.shadowOpacity  = Float(PPController.shadowOpacity)
            lbl.shadowRadius   = PPController.shadowRadius
            lbl.shadowOffset   = .zero
            layer?.addSublayer(lbl)
        }

        if isConfirmRow {
            configLayer(nameLabel, text: axisName)
        } else {
            configLayer(nameLabel, text: axisName)
            let sigText = signalText(for: signalIndex)
            configLayer(signalLabel, text: sigText)
            if signalIndex != nil {
                signalLabel.font = PhotonFont.chromeCt(wght: 900)
            }

            configLayer(hoverLabel, text: AxisMappingRow.reverseHoverText)
            hoverLabel.opacity = 0
            hoverLabel.zPosition = 1

            let glyph = ReversedGlyph(reversed: reversed)
            self.isReversedState = reversed
            glyph.onTap = { [weak self] in self?.onToggleReverse?() }
            glyph.onHoverStart = { [weak self] in self?.setHovering(true) }
            glyph.onHoverEnd   = { [weak self] in self?.setHovering(false) }
            glyph.onReversedChanged = { [weak self] reversed in
                self?.isReversedState = reversed
                self?.updateHoverLabelVisibility()
            }
            addSubview(glyph)
            reversedGlyph = glyph
        }

        alphaValue = isConfirmRow ? 0.35 : 0.85

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))

        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self = self else { return }
            self.refreshFont()
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private var reverseZoneW: CGFloat {
        guard !isConfirm else { return 0 }
        return PhotonFont.chromeCharW + PhotonFont.chromeGap
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let gap = PhotonFont.chromeGap
        let zoneW = reverseZoneW
        let remaining = bounds.width - zoneW
        let halfW = remaining * 0.5
        nameLabel.frame   = CGRect(x: gap, y: 0, width: halfW - gap, height: bounds.height)
        signalLabel.frame = CGRect(x: halfW, y: 0, width: halfW - gap, height: bounds.height)
        if let glyph = reversedGlyph {
            glyph.frame = CGRect(x: remaining, y: 0, width: zoneW, height: bounds.height)
            let labelText = isReversedState ? "axis reversed" : AxisMappingRow.reverseHoverText
            let labelW = (labelText as NSString)
                .size(withAttributes: [.font: PhotonFont.chromeNs()]).width
            hoverLabel.frame = CGRect(x: remaining + zoneW + gap, y: 0, width: labelW, height: bounds.height)
        }
        CATransaction.commit()
    }

    func setReversed(_ reversed: Bool) {
        reversedGlyph?.setReversed(reversed)
    }

    private var isHoveringGlyph = false
    private func setHovering(_ hovering: Bool) {
        isHoveringGlyph = hovering
        updateHoverLabelVisibility()
    }

    private func updateHoverLabelVisibility() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        let labelText = isReversedState ? "axis reversed" : AxisMappingRow.reverseHoverText
        hoverLabel.string = labelText
        let labelW = (labelText as NSString).size(withAttributes: [.font: PhotonFont.chromeNs()]).width
        hoverLabel.frame.size.width = labelW
        hoverLabel.opacity = (isReversedState || isHoveringGlyph) ? 1 : 0
        CATransaction.commit()
    }

    func setSignal(_ signalIndex: Int?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        signalLabel.string = signalText(for: signalIndex)
        signalLabel.font   = signalIndex != nil ? PhotonFont.chromeCt(wght: 900) : PhotonFont.chromeCt()
        CATransaction.commit()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = signalIndex != nil ? 1.0 : 0.85
        }
    }

    func setActive(_ active: Bool) {
        guard isConfirm else { return }
        isActive = active
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            self.animator().alphaValue = active ? 0.85 : 0.35
        }
    }

    private func signalText(for index: Int?) -> String {
        guard let i = index else { return AxisMappingPanel.noneLabel }
        return AxisMappingPanel.signalLabels[safe: i] ?? "\(i)  curve"
    }

    private func refreshFont() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        PhotonFont.setIfChanged(PhotonFont.chromeCt(), on: nameLabel)
        CATransaction.commit()
    }

    override func mouseEntered(with e: NSEvent) {
        if isConfirm {
            guard isActive else { return }
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            self.animator().alphaValue = 1.0
        }
        nameLabel.shadowOpacity = min(1.0, Float(PPController.shadowOpacity) * 1.5)
    }

    override func mouseExited(with e: NSEvent) {
        NSCursor.arrow.set()
        let target: CGFloat = isConfirm ? (isActive ? 0.85 : 0.35) : 0.85
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = target
        }
        nameLabel.shadowOpacity = Float(PPController.shadowOpacity)
    }

    override func mouseDown(with e: NSEvent) {
        if isConfirm && !isActive { return }
        onTap?()
    }
}

// ================================================================
//  ReversedGlyph - reverse-state glyph
// ================================================================
final class ReversedGlyph: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    var onTap: (() -> Void)?
    var onHoverStart: (() -> Void)?
    var onHoverEnd: (() -> Void)?
    var onReversedChanged: ((Bool) -> Void)?

    private let glyphLayer = CATextLayer()
    private var isReversed: Bool
    private var isHovering = false

    static let forwardGlyph  = "·"
    static let reversedGlyph = "•"

    init(reversed: Bool) {
        self.isReversed = reversed
        super.init(frame: .zero)
        wantsLayer = true

        glyphLayer.contentsScale  = NSScreen.main?.backingScaleFactor ?? 2
        glyphLayer.alignmentMode  = .center
        glyphLayer.isWrapped      = false
        glyphLayer.foregroundColor = NSColor.white.cgColor
        glyphLayer.fontSize       = PhotonFont.chromeSize
        glyphLayer.font           = PhotonFont.chromeCt()
        glyphLayer.shadowColor    = NSColor.black.cgColor
        glyphLayer.shadowOpacity  = Float(PPController.shadowOpacity)
        glyphLayer.shadowRadius   = PPController.shadowRadius
        glyphLayer.shadowOffset   = .zero
        layer?.addSublayer(glyphLayer)
        applyGlyphState()

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.frame = bounds
        CATransaction.commit()
    }

    func setReversed(_ reversed: Bool) {
        isReversed = reversed
        applyGlyphState()
        onReversedChanged?(reversed)
    }

    private func applyGlyphState() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphLayer.string = (isHovering || isReversed) ? ReversedGlyph.reversedGlyph : ReversedGlyph.forwardGlyph
        CATransaction.commit()
    }

    override func mouseEntered(with e: NSEvent) {
        NSCursor.pointingHand.set()
        isHovering = true
        applyGlyphState()
        onHoverStart?()
    }

    override func mouseExited(with e: NSEvent) {
        NSCursor.arrow.set()
        isHovering = false
        applyGlyphState()
        onHoverEnd?()
    }

    override func mouseDown(with e: NSEvent) {
        onTap?()
    }
}

// MARK: - Array safe subscript
// ================================================================
//  Array - Array
// ================================================================
extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

enum StatusHUDPlacement {
    static func region(anchorX:CGFloat,anchorY:CGFloat,visible:CGRect,pad:CGFloat)->CGRect {
        let x=max(anchorX,visible.minX)
        let top=min(anchorY,visible.maxY)
        return CGRect(x:x,y:visible.minY,width:max(0,visible.maxX-x-pad),height:max(0,top-visible.minY))
    }
}
