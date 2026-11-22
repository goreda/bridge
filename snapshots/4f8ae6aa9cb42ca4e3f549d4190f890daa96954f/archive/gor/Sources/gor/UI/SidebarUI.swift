// ================================================================
//  SidebarUI.swift - right-edge sidebar: seek bar, timecodes,
//  list-scroll mode; shared label/button/dot views
//  Owns: SidebarUI, SeekBar, TimecodeLabel, PLabel, PBtn, TrafficDot
//  Answers: I29 I39 - TRAP-02
//  Contract: SeekBar.hitTest returns self only inside its frame (I29);
//  render-only layers use PhotonFont.ctFace() (I39)
// ================================================================
import AppKit
import QuartzCore

// ================================================================
//  SidebarUI - right edge: SeekBar + HH/MM/SS/ms timecodes
// ================================================================

final class SidebarUI: NSView {


    /// Collapsed width, font-derived; PPController reads this to set the
    /// frame width, and layout() self-syncs its own frame to it.
    var sidebarWidth: CGFloat { PhotonFont.chromeTwoDigitW + PhotonFont.chromePad * 2 }

    weak var playerView: (AnyObject & PlayerProtocol)?

    let seekBar   = SeekBar()
    private let timeNow   = TimecodeLabel()
    private let timeTot   = TimecodeLabel()
    private let timeHover = TimecodeLabel()

    private var duration: Double = 0
    private var lastProgress: Double = 0
    private var savedProgress: Double?
    
    private var currentTime: Double = 0
    private var isRemainingToggled = true
    private var isTimeTotHovered = false
    
    // ── Live stream modu ─────────────────────────────────────────
    /// Set by PPController: true for IPTV streams, false for VOD/files.
    var isLiveStream: Bool = false {
        didSet { seekBar.isLiveStream = isLiveStream }
    }

    // ── List / Scroll modu ───────────────────────────────────────
    var isListMode: Bool = false {
        didSet {
            seekBar.isListMode = isListMode
            timeNow.isHidden   = isListMode
            timeTot.isHidden   = isListMode
            timeHover.isHidden = true
            // in list mode, route seekBar's onSeek/onHover to scrolling
            if isListMode {
                seekBar.onSeek  = { [weak self] p in
                    self?.scrollListTo(p)
                }
                seekBar.onHover = { [weak self] p, _, visible in
                    guard visible else { return }
                    self?.scrollListTo(p)
                }
                seekBar.onScrollUp = { [weak self] in
                    guard let sv = self?.scrollTarget else { return }
                    let current = sv.contentView.bounds.origin.y
                    sv.contentView.scroll(to: NSPoint(x: 0, y: max(0, current - 40)))
                    sv.reflectScrolledClipView(sv.contentView)
                    self?.syncSeekBarFromScroll()
                }
                seekBar.onScrollDown = { [weak self] in
                    guard let sv = self?.scrollTarget,
                          let doc = sv.documentView else { return }
                    let maxY    = doc.frame.height - sv.contentSize.height
                    let current = sv.contentView.bounds.origin.y
                    sv.contentView.scroll(to: NSPoint(x: 0, y: min(maxY, current + 40)))
                    sv.reflectScrolledClipView(sv.contentView)
                    self?.syncSeekBarFromScroll()
                }
            } else {
                seekBar.onScrollUp   = nil
                seekBar.onScrollDown = nil
                seekBar.onSeek = { [weak self] p in
                    guard let self else { return }
                    self.savedProgress = nil
                    self.lastProgress  = p
                    self.playerView?.seek(to: p)
                }
                seekBar.onHover = { [weak self] (p, mouseY, visible) in
                    guard let self else { return }
                    if visible {
                        if self.savedProgress == nil { self.savedProgress = self.lastProgress }
                        self.timeHover.setTime(p * self.duration)
                        self.timeHover.isHidden = false
                        let bf  = self.seekBar.frame
                        let absY = bf.minY + mouseY
                        let lh: CGFloat = PhotonFont.chromeSize * 4.0
                        self.timeHover.frame = CGRect(
                            x: +3,
                            y: max(bf.minY, min(bf.maxY - lh, absY - lh / 2)) - (PhotonFont.chromeSize / 3),
                            width: self.bounds.width,
                            height: lh
                        )
                        self.playerView?.seek(to: p)
                    } else {
                        self.timeHover.isHidden = true
                        if let restore = self.savedProgress {
                            self.playerView?.seek(to: restore)
                            self.savedProgress = nil
                        }
                    }
                }
            }
        }
    }

    weak var scrollTarget: NSScrollView?   // MusicPanel's listScroll

    func setScrollProgress(_ p: Double) {
        guard isListMode else { return }
        // p: 0.0 = top of list, 1.0 = bottom; SeekBar runs inverted
        seekBar.setProgress(1.0 - p)
    }

    private func scrollListTo(_ p: Double) {
        guard let sv = scrollTarget,
              let docView = sv.documentView else { return }
        let contentH   = docView.frame.height
        let visibleH   = sv.contentSize.height
        let scrollable = max(0, contentH - visibleH)
        guard scrollable > 0 else { return }
        let targetOffset = scrollable * (1.0 - p)
        sv.contentView.scroll(to: NSPoint(x: 0, y: targetOffset))
        sv.reflectScrolledClipView(sv.contentView)
        seekBar.forceProgress(p)
    }
    
    private func syncSeekBarFromScroll() {
        guard let sv = scrollTarget,
              let doc = sv.documentView else { return }
        let scrollable = max(1, doc.frame.height - sv.contentSize.height)
        let offsetY    = sv.contentView.bounds.origin.y
        let progress   = Double(offsetY / scrollable)   // 0=top, 1=bottom
        seekBar.forceProgress(1.0 - progress)           // inverted
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            self?.needsLayout = true
        }
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return superview?.performDragOperation(sender) ?? false
    }

    private func build() {
        wantsLayer = true

        seekBar.onSeek = { [weak self] p in
            guard let self = self else { return }
            // click: clear savedProgress so the hover restore doesn't run
            self.savedProgress = nil
            self.lastProgress  = p
            self.playerView?.seek(to: p)
        }
        
        seekBar.onHover = { [weak self] (p: Double, mouseY: CGFloat, visible: Bool) in
            guard let self = self else { return }
            if visible {
                if self.savedProgress == nil {
                    self.savedProgress = self.lastProgress
                }
                
                self.timeHover.setTime(p * self.duration)
                self.timeHover.isHidden = false
                
                let bf  = self.seekBar.frame
                let absY = bf.minY + mouseY
                let lh: CGFloat = PhotonFont.chromeSize * 4.0
                
                self.timeHover.frame = CGRect(
                    x: +3,
                    y: max(bf.minY, min(bf.maxY - lh, absY - lh / 2)) - (PhotonFont.chromeSize / 3),
                    width: self.bounds.width,
                    height: lh
                )
                
                self.playerView?.seek(to: p)
            } else {
                self.timeHover.isHidden = true
                // restore only for hover scrubs; clicks clear savedProgress
                if let restore = self.savedProgress {
                    self.playerView?.seek(to: restore)
                    self.savedProgress = nil
                }
            }
        }

        timeTot.onHoverChange = { [weak self] isHovered in
            self?.isTimeTotHovered = isHovered
            self?.refreshTimeTotDisplay()
        }
        
        timeTot.onClick = { [weak self] in
            self?.isRemainingToggled.toggle()
            self?.refreshTimeTotDisplay()
        }
        
        timeHover.isHidden   = true
        timeHover.alphaValue = 1.0
        [timeNow, timeTot, seekBar, timeHover].forEach { addSubview($0) }
        seekBar.removeFromSuperview()
        addSubview(seekBar)
    }

    private var _updatingWidth = false

    override func layout() {
        super.layout()

        // Self-sync: layout() can fire before PPController.applyVideoFrame
        // after a font change; the _updatingWidth guard prevents recursion.
        if !_updatingWidth {
            let sw = sidebarWidth
            if abs(frame.size.width - sw) > 0.5 {
                _updatingWidth = true
                frame.size.width = sw
                _updatingWidth = false
            }
        }

        let w = bounds.width
        let h = bounds.height

        let tcH: CGFloat = PhotonFont.chromeLineH * 4
        let pad: CGFloat = PhotonFont.chromePad
        let x3 = PhotonFont.chromeValue(3)
        let up5 = PhotonFont.chromeValue(5)
        let down6 = PhotonFont.chromeValue(6)
        let gap10 = PhotonFont.chromeValue(10)
        let inset2 = PhotonFont.chromeValue(2)

        timeTot.frame = CGRect(x: x3, y: pad - up5,           width: w, height: tcH)
        timeNow.frame = CGRect(x: x3, y: h - pad - tcH + down6, width: w, height: tcH)

        let barBot = pad + tcH + PhotonFont.chromeGap + gap10
        let barTop = h - pad - tcH - PhotonFont.chromeGap
        seekBar.frame = CGRect(x: 0, y: barBot - inset2, width: w, height: (max(0, barTop - barBot)) + gap10)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let v = super.hitTest(point)
        return v === self ? nil : v
    }

    private func refreshTimeTotDisplay() {
        let showRemaining = isRemainingToggled || isTimeTotHovered
        if showRemaining {
            let remaining = max(0, duration - currentTime)
            timeTot.setTime(remaining, isRemaining: true)
        } else {
            timeTot.setTime(duration, isRemaining: false)
        }
    }

    func update(currentTime: Double, duration: Double, progress: Double, volume: Float) {
        self.currentTime = currentTime
        self.duration    = duration
        self.lastProgress = progress
        timeNow.setTime(currentTime)
        refreshTimeTotDisplay()
        
        if savedProgress == nil && !isListMode {
            seekBar.setProgress(progress)
        }
    }
}

// ================================================================
//  SeekBar - glyph-rendered seek bar ("·" dotted / "|" solid),
//  CATextLayer pools, thumb-centered proximity audio response
// ================================================================

final class SeekBar: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }


    enum Style { case solid, dotted }
    static var style: Style = .dotted

    // ── Font-derived metrics ─────────────────────────────────────
    private var glyphSize: CGFloat { PhotonFont.chromeSize }
    private var dotBase:   CGFloat { glyphSize * 0.55 }
    private var dotStep:   CGFloat { dotBase * 0.8 }
    private var fSizeBase: CGFloat { dotBase * 1.8 }
    private var solidStep: CGFloat { glyphSize * 0.8 }

    // ── State ────────────────────────────────────────────────────
    private var mouseY:       CGFloat = -9999
    private var isHovering:   Bool    = false
    private var audioScale:   CGFloat = 0
    private var vbToken:      UUID?
    private var progress:     Double  = 0
    private var isTracking:   Bool    = false

    var bufferProgress: Double = 0 {
        didSet {
            let clamped = bufferProgress.isFinite ? max(0, min(1, bufferProgress)) : 0
            if bufferProgress != clamped { bufferProgress = clamped }
            guard bufferProgress != oldValue else { return }
            redraw()
        }
    }

    // ── Layer pools ──────────────────────────────────────────────
    private var trackDots:  [CATextLayer] = []
    private var fillDots:   [CATextLayer] = []
    private var bufferDots: [CATextLayer] = []
    private var trackBars:  [CATextLayer] = []
    private var fillBars:   [CATextLayer] = []
    private var bufferBars: [CATextLayer] = []

    // ── Thumb ────────────────────────────────────────────────────
    private let thumbM = CATextLayer()
    private let thumbL = CATextLayer()
    private let thumbR = CATextLayer()

    // ── Endpoints + hover ────────────────────────────────────────
    private var startDot: CATextLayer?
    private var endDot:   CATextLayer?
    private var hoverDot: CATextLayer?

    // ── Callbacks ────────────────────────────────────────────────
    var onSeek:       ((Double) -> Void)?
    var onHover:      ((Double, CGFloat, Bool) -> Void)?
    var onScrollUp:   (() -> Void)?
    var onScrollDown: (() -> Void)?
    var isListMode:   Bool = false

    var adaptiveColor: NSColor = .white {
        didSet { applyAdaptiveColor(adaptiveColor) }
    }

    /// Live stream mode: thumb goes crimson; other layers unaffected.
    var isLiveStream: Bool = false {
        didSet { guard isLiveStream != oldValue else { return }; redrawThumb() }
    }

    private var thumbColor: CGColor {
        isLiveStream
            ? NSColor(red: 0.863, green: 0.078, blue: 0.235, alpha: 1).cgColor  // crimson
            : adaptiveColor.cgColor
    }

    /// Pool-layout key - the pools rebuild only when one of these changes.
    private struct DotLayoutKey: Equatable {
        let fontName:  String
        let pointSize: CGFloat
        let count:     Int
    }
    private var _lastLayoutKey: DotLayoutKey?
    /// Last tick's proximity band as Int bounds. Unioned with this tick's
    /// band so dots that just left the radius get reset to base size once.
    private var _lastProxLo: Int?
    private var _lastProxHi: Int?
    /// Last applied fill/buffer counts for boundary-only opacity diffing.
    /// -1 = full pass required (layout change / pool rebuild).
    private var _appliedFill:   Int = -1
    private var _appliedBuffer: Int = -1
    private var scrollRepeatTimer: Timer?
    private enum ScrollDir { case up, down }

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false

        for tl in [thumbL, thumbM, thumbR] {
            tl.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            tl.isWrapped     = false
            tl.alignmentMode = .center
        }
        thumbM.string = "•"
        thumbL.string = "·"
        thumbR.string = "·"

        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))

        vbToken = VariationBroadcaster.shared.addListener { [weak self] in
            guard let self, self.isEffectivelyVisible else { return }
            let s = CGFloat(VariationBroadcaster.shared.smoothAudio)
            guard abs(s - self.audioScale) > 0.005 else { return }
            self.audioScale = s
            self.redraw()
        }

        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self._lastLayoutKey = nil
            self.redraw()
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let t = vbToken { VariationBroadcaster.shared.removeListener(t) } }

    // MARK: - Progress

    func setProgress(_ v: Double) {
        guard !isTracking else { return }
        let next = v.clamped(to: 0...1)
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        let samePixel = (CGFloat(progress) * bounds.height * scale).rounded()
            == (CGFloat(next) * bounds.height * scale).rounded()
        progress = next
        guard !samePixel else { return }
        redraw()
    }
    func forceProgress(_ v: Double) {
        progress = v.clamped(to: 0...1)
        redraw()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
        redraw()
    }

    // MARK: - Color

    func applyAdaptiveColor(_ color: NSColor) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let cg = color.cgColor
        trackDots.forEach  { $0.foregroundColor = cg }
        fillDots.forEach   { $0.foregroundColor = cg }
        bufferDots.forEach { $0.foregroundColor = cg }
        trackBars.forEach  { $0.foregroundColor = cg }
        fillBars.forEach   { $0.foregroundColor = cg }
        bufferBars.forEach { $0.foregroundColor = cg }
        let tc = thumbColor
        thumbM.foregroundColor = tc; thumbL.foregroundColor = tc; thumbR.foregroundColor = tc
        startDot?.foregroundColor = cg; endDot?.foregroundColor = cg
        hoverDot?.foregroundColor = cg
        CATransaction.commit()
    }

    // MARK: - Redraw dispatcher

    private func redraw() {
        switch SeekBar.style {
        case .dotted: redrawDotted()
        case .solid:  redrawSolid()
        }
        redrawThumb()
        redrawEndpoints()
    }

    // MARK: - Proximity (thumb-centered audio response)

    /// Returns [0,1] — 1 = dot is exactly at thumb position, 0 = outside radius.
    /// Only dots/bars near the thumb scale up; the rest stay at base size.
    private func proximityToThumb(dotCenterY: CGFloat, thumbY: CGFloat) -> CGFloat {
        let radius = dotStep * 10
        let dist   = abs(thumbY - dotCenterY)
        guard dist < radius else { return 0 }
        let sigma  = radius / 3.5
        return exp(-dist * dist / (2 * sigma * sigma))
    }

    // MARK: - .dotted mode

    private func redrawDotted() {
        let x      = barX()
        let h      = bounds.height
        let gs         = PhotonFont.chromeSize
        let dotBase    = gs * 0.55
        let step       = dotBase * 0.8
        let fSizeBase  = dotBase * 1.8
        let proxRadius = step * 10
        guard step > 1 else { return }

        let count       = max(1, Int(h / step))
        let fillCount   = max(0, min(count, Int((CGFloat(progress) * CGFloat(count)).rounded())))
        let bufferCount = max(0, min(count, Int((CGFloat(bufferProgress) * CGFloat(count)).rounded())))

        let key = DotLayoutKey(fontName: PhotonFont.fontName, pointSize: gs, count: count)
        let layoutChanged = key != _lastLayoutKey || trackDots.count != count
        if layoutChanged {
            _lastLayoutKey = key
            clearSolidLayers()
            trackDots.forEach  { $0.removeFromSuperlayer() }
            fillDots.forEach   { $0.removeFromSuperlayer() }
            bufferDots.forEach { $0.removeFromSuperlayer() }
            trackDots = []; fillDots = []; bufferDots = []
            for _ in 0..<count {
                trackDots.append(makeDotLayer())
                fillDots.append(makeDotLayer())
                bufferDots.append(makeDotLayer())
            }
            [thumbL, thumbM, thumbR].forEach { $0.removeFromSuperlayer(); layer?.addSublayer($0) }
            _lastProxLo = nil; _lastProxHi = nil // fresh layers, nothing to diff
            _appliedFill = -1; _appliedBuffer = -1
            // WHY: makeDotLayer() never sets .font, and the band pass
            // below only touches dots near the thumb - stamp the shared
            // face font on every dot at (re)build so none stay on the
            // system default. Per-dot size via the layer's own fontSize;
            // render-only, so ctFace(), no per-size CTFonts (I39).
            let face = PhotonFont.ctFace()
            for i in 0..<count {
                PhotonFont.setIfChanged(face, on: trackDots[i])
                trackDots[i].fontSize = fSizeBase
                PhotonFont.setIfChanged(face, on: fillDots[i])
                fillDots[i].fontSize = fSizeBase
                PhotonFont.setIfChanged(face, on: bufferDots[i])
                bufferDots[i].fontSize = fSizeBase
            }
        }

        let thumbY = CGFloat(progress) * h

        // Only dots within proxRadius of the thumb ever get a non-base
        // fSize. The band is the union of this and last tick's Int bounds,
        // so dots that just left the radius are revisited once and reset
        // to base. Every write below is compare-then-write.
        let firstIdx = max(0, Int(((thumbY - proxRadius) / step).rounded(.down)))
        let lastIdx  = min(count - 1, Int(((thumbY + proxRadius) / step).rounded(.up)))
        let valid = firstIdx <= lastIdx
        let lo = valid ? min(firstIdx, _lastProxLo ?? firstIdx) : (_lastProxLo ?? firstIdx)
        let hi = valid ? max(lastIdx,  _lastProxHi ?? lastIdx)  : (_lastProxHi ?? lastIdx)
        _lastProxLo = valid ? firstIdx : nil
        _lastProxHi = valid ? lastIdx  : nil

        CATransaction.begin(); CATransaction.setDisableActions(true)

        if layoutChanged {
            // Full pass: base geometry + visibility rule from scratch.
            let baseSize = CGSize(width: fSizeBase, height: fSizeBase)
            for i in 0..<count {
                let cy  = CGFloat(i) * step + step * 0.5
                let pos = CGPoint(x: x, y: cy)
                trackDots[i].bounds  = CGRect(origin: .zero, size: baseSize)
                trackDots[i].position  = pos
                fillDots[i].bounds   = CGRect(origin: .zero, size: baseSize)
                fillDots[i].position   = pos
                bufferDots[i].bounds = CGRect(origin: .zero, size: baseSize)
                bufferDots[i].position = pos
                trackDots[i].opacity  = 1
                fillDots[i].opacity   = i < fillCount ? 1 : 0
                bufferDots[i].opacity = (i < bufferCount && i >= fillCount) ? 1 : 0
            }
            _appliedFill = fillCount
            _appliedBuffer = bufferCount
        }

        // Band pass: compare-then-write; the font itself never changes
        // (stamped once at layoutChanged).
        if lo <= hi {
            for i in lo...hi {
                let cy    = CGFloat(i) * step + step * 0.5
                let prox  = proximityToThumb(dotCenterY: cy, thumbY: thumbY)
                let fSize = fSizeBase * (1.0 + (audioScale * 0.6 + prox * 0.6) * prox)
                let size  = CGSize(width: fSize, height: fSize)
                let pos   = CGPoint(x: x, y: cy)
                for l in [trackDots[i], fillDots[i], bufferDots[i]] {
                    if l.fontSize != fSize       { l.fontSize = fSize }
                    if l.bounds.size != size     { l.bounds = CGRect(origin: .zero, size: size) }
                    if l.position != pos         { l.position = pos }
                }
            }
        }

        applyFillBufferDiff(fillCount: fillCount, bufferCount: bufferCount)
        CATransaction.commit()
    }

    /// Fill/buffer opacity diffing. Progress moves one dot at a time, so only
    /// the indices between the old and new count can flip; recompute the
    /// visibility rule for just those and write only where it differs.
    /// Buffer visibility depends on fillCount too (the i >= fillCount term),
    /// so a fill move also re-evaluates the buffer dots inside its band.
    /// Full passes (layoutChanged) set _appliedFill/_appliedBuffer directly.
    private func applyFillBufferDiff(fillCount: Int, bufferCount: Int) {
        let count = trackDots.count
        guard count > 0 else { return }
        if fillCount != _appliedFill {
            let lo = max(0, min(fillCount, _appliedFill))
            let hi = min(count, max(fillCount, _appliedFill))
            for i in lo..<hi {
                let f: Float = i < fillCount ? 1 : 0
                if fillDots[i].opacity != f { fillDots[i].opacity = f }
                let b: Float = (i < bufferCount && i >= fillCount) ? 1 : 0
                if bufferDots[i].opacity != b { bufferDots[i].opacity = b }
            }
            _appliedFill = fillCount
        }
        if bufferCount != _appliedBuffer {
            let lo = max(0, min(bufferCount, _appliedBuffer))
            let hi = min(count, max(bufferCount, _appliedBuffer))
            for i in lo..<hi {
                let b: Float = (i < bufferCount && i >= fillCount) ? 1 : 0
                if bufferDots[i].opacity != b { bufferDots[i].opacity = b }
            }
            _appliedBuffer = bufferCount
        }
        // No per-tick color writes: stamped at creation, applyAdaptiveColor
        // covers changes.
    }

    // MARK: - .solid mode

    private func redrawSolid() {
        let x     = barX()
        let h     = bounds.height
        let step  = solidStep
        guard step > 1 else { return }

        // bars touch edge-to-edge; "|" glyphs run shorter than the font
        // size, so oversize slightly to close gaps
        let spacing = step
        let fSize   = step * 1.15

        let endDotR    = fSizeBase / 2
        let effectiveH = h - endDotR * 3
        var count      = 1
        while CGFloat(count - 1) * spacing < effectiveH {
            count += 1
        }

        let fillCount   = max(0, min(count, Int((CGFloat(progress) * CGFloat(count)).rounded())))
        let bufferCount = max(0, min(count, Int((CGFloat(bufferProgress) * CGFloat(count)).rounded())))

        let key = DotLayoutKey(fontName: PhotonFont.fontName, pointSize: PhotonFont.chromeSize, count: count)
        if key != _lastLayoutKey || trackBars.count != count {
            _lastLayoutKey = key
            clearDottedLayers()
            trackBars.forEach  { $0.removeFromSuperlayer() }
            fillBars.forEach   { $0.removeFromSuperlayer() }
            bufferBars.forEach { $0.removeFromSuperlayer() }
            trackBars = []; fillBars = []; bufferBars = []
            for _ in 0..<count {
                trackBars.append(makeBarLayer())
                fillBars.append(makeBarLayer())
                bufferBars.append(makeBarLayer())
            }
            [thumbL, thumbM, thumbR].forEach { $0.removeFromSuperlayer(); layer?.addSublayer($0) }
        }

        let thumbY = CGFloat(progress) * h
        let cg     = adaptiveColor.cgColor

        CATransaction.begin(); CATransaction.setDisableActions(true)
        for i in 0..<count {
            let yPos  = CGFloat(i) * spacing
            let frame = CGRect(x: x - step / 2, y: yPos, width: step, height: step)
            let cy    = yPos + step * 0.5
            let prox  = proximityToThumb(dotCenterY: cy, thumbY: thumbY)
            let wTot  = Double(audioScale * 0.7 + prox * 0.5).clamped(0, 1)
            let ctFont = PhotonFont.chromeCt(size: fSize,
                                       wght: PhotonFont.scaledValue(tag: 0x77676874, tFull: wTot))

            trackBars[i].frame           = frame
            PhotonFont.setIfChanged(ctFont, on: trackBars[i])
            trackBars[i].fontSize        = fSize
            trackBars[i].foregroundColor  = cg
            trackBars[i].opacity         = 1

            fillBars[i].frame            = frame
            PhotonFont.setIfChanged(ctFont, on: fillBars[i])
            fillBars[i].fontSize         = fSize
            fillBars[i].foregroundColor   = cg
            fillBars[i].opacity          = i < fillCount ? 1 : 0

            bufferBars[i].frame          = frame
            PhotonFont.setIfChanged(ctFont, on: bufferBars[i])
            bufferBars[i].fontSize       = fSize
            bufferBars[i].foregroundColor = cg
            bufferBars[i].opacity        = (i < bufferCount && i >= fillCount) ? 1 : 0
        }
        CATransaction.commit()
    }
    
    // MARK: - Thumb

    private func redrawThumb() {
        let x      = barX()
        let h      = bounds.height
        let thumbY = CGFloat(progress) * h
        let tSize  = glyphSize * (1.0 + audioScale * 0.5)
        let ctFont = PhotonFont.chromeCtDriven(p: 0.5, t_audio: Double(audioScale), size: tSize)
        let sSize:  CGFloat = tSize
        let spread: CGFloat = tSize * 0.5
        let tc = thumbColor

        let face = PhotonFont.ctFace()

        CATransaction.begin(); CATransaction.setDisableActions(true)
        PhotonFont.setIfChanged(ctFont, on: thumbM); if thumbM.fontSize != tSize { thumbM.fontSize = tSize }
        thumbM.frame = CGRect(x: x - tSize/2, y: thumbY - tSize/2, width: tSize, height: tSize)
        thumbM.foregroundColor = tc
        PhotonFont.setIfChanged(face, on: thumbL); if thumbL.fontSize != sSize { thumbL.fontSize = sSize }
        thumbL.frame = CGRect(x: x - spread - sSize/2, y: thumbY - sSize/2, width: sSize, height: sSize)
        thumbL.foregroundColor = tc
        PhotonFont.setIfChanged(face, on: thumbR); if thumbR.fontSize != sSize { thumbR.fontSize = sSize }
        thumbR.frame = CGRect(x: x + spread - sSize/2, y: thumbY - sSize/2, width: sSize, height: sSize)
        thumbR.foregroundColor = tc
        if isLiveStream {
            thumbM.opacity = 0.4 + 0.6 * Float(audioScale)
        } else if thumbM.opacity != 1 {
            thumbM.opacity = 1
        }
        CATransaction.commit()
    }

    // MARK: - Endpoints

    private func redrawEndpoints() {
        let x = barX(); let h = bounds.height
        let s = fSizeBase; let half = s / 2
        let face = PhotonFont.ctFace()

        CATransaction.begin(); CATransaction.setDisableActions(true)
        if startDot == nil { startDot = makeEndpointLayer(); layer?.insertSublayer(startDot!, at: 0) }
        if let startDot {
            PhotonFont.setIfChanged(face, on: startDot)
            if startDot.fontSize != s { startDot.fontSize = s }
            startDot.frame = CGRect(x: x - half, y: -half, width: s, height: s)
        }

        if endDot == nil { endDot = makeEndpointLayer(); layer?.insertSublayer(endDot!, at: 0) }
        if let endDot {
            PhotonFont.setIfChanged(face, on: endDot)
            if endDot.fontSize != s { endDot.fontSize = s }
            endDot.frame = CGRect(x: x - half, y: h - half, width: s, height: s)
        }
        CATransaction.commit()
    }

    // MARK: - Layer factories

    private func makeDotLayer() -> CATextLayer {
        let l = CATextLayer()
        l.string = "·"
        l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        l.isWrapped = false
        l.alignmentMode = .center
        l.foregroundColor = adaptiveColor.cgColor
        l.masksToBounds = false
        layer?.addSublayer(l)
        return l
    }

    private func makeBarLayer() -> CATextLayer {
        let l = CATextLayer()
        l.string = "|"
        l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        l.isWrapped = false
        l.alignmentMode = .center
        l.foregroundColor = adaptiveColor.cgColor
        l.masksToBounds = false
        layer?.addSublayer(l)
        return l
    }

    private func makeEndpointLayer() -> CATextLayer {
        let l = CATextLayer()
        l.string = "."
        l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        l.isWrapped = false
        l.alignmentMode = .center
        l.foregroundColor = adaptiveColor.cgColor
        l.masksToBounds = false
        return l
    }

    // MARK: - Cleanup

    private func clearDottedLayers() {
        trackDots.forEach  { $0.removeFromSuperlayer() }; trackDots  = []
        fillDots.forEach   { $0.removeFromSuperlayer() }; fillDots   = []
        bufferDots.forEach { $0.removeFromSuperlayer() }; bufferDots = []
    }
    private func clearSolidLayers() {
        trackBars.forEach  { $0.removeFromSuperlayer() }; trackBars  = []
        fillBars.forEach   { $0.removeFromSuperlayer() }; fillBars   = []
        bufferBars.forEach { $0.removeFromSuperlayer() }; bufferBars = []
    }

    // MARK: - Helpers

    private func barX() -> CGFloat {
        bounds.width - (PhotonFont.chromeTwoDigitW / 2 - 2 + PhotonFont.chromePad)
    }
    private func prog(y: CGFloat) -> Double {
        Double(y / max(1, bounds.height)).clamped(to: 0...1)
    }

    // MARK: - Scroll repeat

    private func startScrollRepeat(dir: ScrollDir) {
        scrollRepeatTimer?.invalidate()
        scrollRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            switch dir { case .up: self?.onScrollUp?(); case .down: self?.onScrollDown?() }
        }
    }
    private func stopScrollRepeat() { scrollRepeatTimer?.invalidate(); scrollRepeatTimer = nil }

    // MARK: - Mouse

    // I29 / TRAP-02: frame.contains check, never a bare `return self` -
    // an unconditional self swallows the timecode clicks behind the bar.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func mouseDown(with e: NSEvent) {
        let loc = convert(e.locationInWindow, from: nil)
        if e.modifierFlags.contains(.command) {
            SeekBar.style = SeekBar.style == .dotted ? .solid : .dotted
            _lastLayoutKey = nil; clearDottedLayers(); clearSolidLayers(); redraw(); return
        }
        let x = barX()
        if isListMode {
            let hitR: CGFloat = max(8, fSizeBase / 2)
            if CGRect(x: x-hitR, y: -hitR, width: hitR*2, height: hitR*2).contains(loc) {
                onScrollUp?(); startScrollRepeat(dir: .up); return
            }
            if CGRect(x: x-hitR, y: bounds.height-hitR, width: hitR*2, height: hitR*2).contains(loc) {
                onScrollDown?(); startScrollRepeat(dir: .down); return
            }
            isTracking = true; let p = prog(y: loc.y); forceProgress(p); onSeek?(p); return
        }
        isTracking = true; let p = prog(y: loc.y); progress = p; redraw(); onSeek?(p)
    }

    override func mouseDragged(with e: NSEvent) {
        guard !isListMode, isTracking else { return }
        let loc = convert(e.locationInWindow, from: nil)
        let p = prog(y: loc.y); progress = p; redraw(); onSeek?(p); onHover?(p, loc.y, true)
    }

    override func mouseUp(with e: NSEvent) {
        stopScrollRepeat()
        isTracking = false
    }

    override func mouseMoved(with e: NSEvent) {
        guard !isListMode else { return }
        let loc = convert(e.locationInWindow, from: nil)
        let p   = prog(y: loc.y)

        if let winPt = window.map({ convert(loc, to: $0.contentView) }) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }

        let x = barX()
        guard loc.x >= x - 12 && loc.x <= bounds.width else {
            isHovering = false; mouseY = -9999
            CATransaction.begin(); CATransaction.setDisableActions(true)
            hoverDot?.opacity = 0
            CATransaction.commit()
            redraw()
            return
        }

        isHovering = true
        mouseY     = loc.y

        if hoverDot == nil { hoverDot = makeEndpointLayer(); layer?.addSublayer(hoverDot!) }
        let hSize = fSizeBase * 1.3; let half = hSize / 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        // WHY: hSize never changes (derived from fSizeBase) - guard the
        // font write on this per-pixel callback.
        if let hoverDot { PhotonFont.setIfChanged(PhotonFont.ctFace(), on: hoverDot) }
        if hoverDot?.fontSize != hSize { hoverDot?.fontSize = hSize }
        hoverDot?.frame = CGRect(x: x - half, y: loc.y - half, width: hSize, height: hSize)
        hoverDot?.opacity = 1
        CATransaction.commit()

        redraw()
        onHover?(p, loc.y, true)
    }

    override func mouseExited(with e: NSEvent) {
        guard !isListMode else { return }
        isHovering = false; mouseY = -9999
        CATransaction.begin(); CATransaction.setDisableActions(true)
        hoverDot?.opacity = 0
        CATransaction.commit()
        redraw()
        onHover?(0, 0, false)
    }
}

// ================================================================
//  TimecodeLabel - HH / MM / SS / ms stacked, right-aligned
// ================================================================
final class TimecodeLabel: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    private let lH  = CATextLayer()
    private let lM  = CATextLayer()
    private let lS  = CATextLayer()
    private let lMS = CATextLayer()
    private var layers: [CATextLayer] { [lH, lM, lS, lMS] }
    
    var onHoverChange: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        
        for l in layers {
            l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            l.isWrapped = false
            l.foregroundColor = NSColor.white.cgColor
            l.alignmentMode = .right
            l.font = PhotonFont.chromeCt()
            if l.fontSize != PhotonFont.chromeSize { l.fontSize = PhotonFont.chromeSize }
            l.shadowColor = NSColor.black.cgColor
            l.shadowRadius = PPController.shadowRadius
            l.shadowOpacity = PPController.shadowOpacity
            l.shadowOffset = .zero
            self.layer?.addSublayer(l)
        }
        
        setTime(80542.222)
        
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))

        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            for layer in self.layers {
                layer.font = PhotonFont.chromeCt()
                if layer.fontSize != PhotonFont.chromeSize { layer.fontSize = PhotonFont.chromeSize }
            }
            self.needsLayout = true
        }

        for (i, layer) in layers.enumerated() {
            VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self, weak layer] in
                guard let self = self, let layer = layer, self.isEffectivelyVisible else { return }
                let newFont = PhotonFont.chromeCtDriven(view: self, profile: .layered(i))
                PhotonFont.setIfChanged(newFont, on: layer)
                if layer.fontSize != PhotonFont.chromeSize { layer.fontSize = PhotonFont.chromeSize }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    
    override func mouseEntered(with e: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with e: NSEvent)  { onHoverChange?(false) }
    override func mouseDown(with e: NSEvent)    { onClick?() }

    override func layout() {
        super.layout()
        for layer in layers { if layer.fontSize != PhotonFont.chromeSize { layer.fontSize = PhotonFont.chromeSize } }
        let rH = PhotonFont.chromeLineH
        let w = bounds.width
        lH.frame  = CGRect(x: -PhotonFont.chromePad, y: rH * 3, width: w, height: rH)
        lM.frame  = CGRect(x: -PhotonFont.chromePad, y: rH * 2, width: w, height: rH)
        lS.frame  = CGRect(x: -PhotonFont.chromePad, y: rH * 1, width: w, height: rH)
        lMS.frame = CGRect(x: -PhotonFont.chromePad, y: 0,      width: w, height: rH)
    }

    func setTime(_ t: Double, isRemaining: Bool = false) {
        let sec = Int(max(0, t))
        let ms  = Int((max(0, t) - Double(sec)) * 100)
        let hStr = String(format: "%02d", sec / 3600)
        
        let values: [(CATextLayer, String)] = [
            (lH, isRemaining ? "-\(hStr)" : hStr),
            (lM, String(format: "%02d", (sec % 3600) / 60)),
            (lS, String(format: "%02d", sec % 60)),
            (lMS, String(format: "%02d", ms))
        ]
        let changed = values.filter { ($0.0.string as? String) != $0.1 }
        guard !changed.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, value) in changed { layer.string = value }
        CATransaction.commit()
    }
}

// ================================================================
//  PLabel - single-line PhotonFont label
// ================================================================
final class PLabel: NSView {
    private let textLayer = CATextLayer()
    var stringValue: String = "" {
        didSet {
            textLayer.string = stringValue
        }
    }
    var alignment: NSTextAlignment = .center {
        didSet {
            switch alignment {
            case .left:   textLayer.alignmentMode = .left
            case .right:  textLayer.alignmentMode = .right
            default:      textLayer.alignmentMode = .center
            }
        }
    }
    var textColor: NSColor = .white {
        didSet {
            textLayer.foregroundColor = textColor.cgColor
        }
    }
    var font: NSFont? {
        didSet {
            guard let font = font else { return }
            // compare against the layer's actual font, not the previous
            // property value
            PhotonFont.setIfChanged(font, on: textLayer)
            if textLayer.fontSize != font.pointSize { textLayer.fontSize = font.pointSize }
        }
    }
    
    init(_ s: String = "") {
        super.init(frame: .zero)
        wantsLayer = true
        stringValue = s
        
        textLayer.string = s
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        textLayer.isWrapped = false
        textLayer.truncationMode = .none
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.font = PhotonFont.chromeCt()
        if textLayer.fontSize != PhotonFont.chromeSize { textLayer.fontSize = PhotonFont.chromeSize }
        textLayer.alignmentMode = .center
        
        textLayer.shadowColor = NSColor.black.cgColor
        textLayer.shadowRadius = PPController.shadowRadius
        textLayer.shadowOpacity = PPController.shadowOpacity
        textLayer.shadowOffset = .zero
        
        layer?.addSublayer(textLayer)

        // Unmanaged PLabels (no VariationBroadcaster listener — VolumePopup,
        // PBtn, transient rows) never re-read PhotonFont after init, so a
        // drag-dropped font never reached them. Re-apply the plain face on
        // every font change; driven owners' listeners immediately re-assert
        // their driven font on the poke that follows a font load.
        LayoutEngine.shared.addObserver(weakLifetime: self) { [weak self] in
            guard let self else { return }
            self.font = PhotonFont.chromeNs()
            self.needsLayout = true
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        textLayer.frame = bounds
    }
    
    func applyVariation(wght: Double, SIZE: Double, ROTA: Double) {
        let size = self.font?.pointSize ?? PhotonFont.chromeSize
        textLayer.font = PhotonFont.chromeCt(size: size, wght: wght, SIZE: SIZE, ROTA: ROTA)
    }
}

// ================================================================
//  PBtn - label button with delayed hover tooltip
// ================================================================
final class PBtn: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    var action: (() -> Void)?
    var tip:    String = ""
    private let label: PLabel
    private var tipLayer: CATextLayer?
    private var tipTimer: Timer?

    init(_ text: String) {
        label = PLabel(text); super.init(frame: .zero); wantsLayer = true
        addSubview(label)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); label.frame = bounds }
    override func mouseDown(with e: NSEvent) {
        layer?.opacity = 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.layer?.opacity = 1 }
        action?()
    }
    override func mouseEntered(with e: NSEvent) {
        tipTimer?.invalidate(); let ev = e
        tipTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in self?.showTip(ev) }
    }
    override func mouseExited(with e: NSEvent) { tipTimer?.invalidate(); hideTip() }
    private func showTip(_ e: NSEvent) {
        guard !tip.isEmpty, let rl = window?.contentView?.layer else { return }
        hideTip(); let l = CATextLayer()
        l.string = tip; if l.fontSize != PhotonFont.chromeSize { l.fontSize = PhotonFont.chromeSize }; l.font = PhotonFont.chromeCt()
        l.foregroundColor = NSColor.white.cgColor
        l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2; l.isWrapped = false
        let w = CGFloat(tip.count) * PhotonFont.chromeCharWidth + 10
        let loc = e.locationInWindow
        let xPos: CGFloat = loc.x > (window?.frame.width ?? 800) / 2 ? loc.x - w - 8 : loc.x + 12
        l.frame = CGRect(x: xPos, y: loc.y + 10, width: w, height: 15)
        rl.addSublayer(l); tipLayer = l
        tipTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.hideTip() }
    }
    private func hideTip() { tipLayer?.removeFromSuperlayer(); tipLayer = nil }
}

// ================================================================
//  TrafficDot - colored circle button
// ================================================================
final class TrafficDot: NSView {
    override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    var action: (() -> Void)?
    private let circle = CALayer()
    private let color:  NSColor
    init(color: NSColor, tip: String) {
        self.color = color; super.init(frame: .zero); wantsLayer = true
        circle.cornerRadius    = 5.5
        circle.backgroundColor = color.cgColor
        layer?.addSublayer(circle)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); circle.frame = bounds }
    override func mouseEntered(with e: NSEvent) { circle.backgroundColor = color.cgColor }
    override func mouseExited(with e: NSEvent)  { circle.backgroundColor = color.cgColor }
    override func mouseDown(with e: NSEvent)    { action?() }
}
