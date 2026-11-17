// ================================================================
//  SubtitleView.swift - cinematic subtitle overlay (CATextLayer +
//  audio-reactive variable font), OpenSubtitles/SubDL, external SRT
//  Owns: textLayer, SV wght pipeline, fade engine, subtitle cues and
//  cache, random-position grid
//  Answers: I1 I2 I12 I17 I26 I38 I45
//  Contract: own AudioNormalizer + buildSVVars, never ctDriven (I2);
//  applySVFont is the single font write point (I38)
// ================================================================
import AppKit
import QuartzCore
import CoreText
import Compression
import CoreAudio
import Accelerate

// Baselines belong to the selected font. Canvas bounds belong to actual glyph ink,
// including CoreText fallback runs; these are deliberately different authorities.
enum SubtitleTypography {
    struct Line { let text: CTLine; let origin: CGPoint }
    /// `inkRect` is the real visible glyph ink (canvas-local, y-up), never the metric
    /// guard or padding; its midY is the cue's ink center.
    struct Layout { let lines: [Line]; let size: CGSize; let inkRect: CGRect
        /// Actual CTLine break ranges (UTF-16, whole-text offsets): the wrap topology signature.
        let breaks: [NSRange]
        var inkCenterY: CGFloat { inkRect.midY } }

    /// Frame origin Y for a canvas of `height` at vertical position ratio (top / blend / bottom).
    static func anchoredFrameY(ratioY: CGFloat, height: CGFloat, boundsHeight: CGFloat,
                               mTop: CGFloat, mBottom: CGFloat) -> CGFloat {
        let topAnchor = boundsHeight - mTop - height
        if ratioY < 0.1 { return topAnchor }
        if ratioY > 0.9 { return mBottom }
        return topAnchor + (mBottom - topAnchor) * ratioY
    }

    /// One uniform block shift so the translated ink stays inside [mBottom, boundsHeight - mTop].
    /// Symmetry about the reference center is intentionally given up at the limit.
    static func clampBlock(frameY: CGFloat, inkRect: CGRect, boundsHeight: CGFloat,
                           mTop: CGFloat, mBottom: CGFloat) -> CGFloat {
        let lower = mBottom, upper = boundsHeight - mTop
        var y = frameY
        if y + inkRect.maxY > upper { y = upper - inkRect.maxY }
        if y + inkRect.minY < lower { y = lower - inkRect.minY }   // bottom wins if both
        return y
    }

    /// Frame origin Y that puts the layout's ink center at `refWorldCenterY`, then block-clamped.
    /// `layout` must already contain the uniform dy; its canvas origin shift is absorbed here,
    /// so dy is applied exactly once.
    static func pinnedFrameY(refWorldCenterY: CGFloat, layout: Layout, boundsHeight: CGFloat,
                             mTop: CGFloat, mBottom: CGFloat) -> CGFloat {
        clampBlock(frameY: refWorldCenterY - layout.inkCenterY, inkRect: layout.inkRect,
                   boundsHeight: boundsHeight, mTop: mTop, mBottom: mBottom)
    }

    static func attributed(_ text: String, font: NSFont, tracking: CGFloat,
                           alignment: NSTextAlignment, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: font, .kern: tracking,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ])
    }

    /// Visible ink of one CTLine, measured per run so a mixed Latin + bitmap-emoji/fallback line
    /// keeps every run. Color/bitmap fonts report no reliable outlines: use the run's typographic
    /// box. Outline fonts use real glyph rects; a run whose glyphs report nothing falls back to
    /// its typographic box. Coordinates are line-local (relative to the line origin).
    static func visibleInk(of line: CTLine, fallback: CGRect) -> CGRect {
        var ink = CGRect.null
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTRunGetTypographicBounds(run, CFRange(location: 0, length: 0),
                                                          &ascent, &descent, nil))
            let typo = CGRect(x: positions[0].x, y: positions[0].y - descent,
                              width: width, height: ascent + descent)
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let runFont = attrs[kCTFontAttributeName as String].map { $0 as! CTFont }
            let bitmap = runFont.map { CTFontGetSymbolicTraits($0).contains(.traitColorGlyphs) } ?? false
            if bitmap || runFont == nil { ink = ink.union(typo); continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            var rects = [CGRect](repeating: .zero, count: count)
            CTFontGetBoundingRectsForGlyphs(runFont!, .default, glyphs, &rects, count)
            var runInk = CGRect.null
            for i in 0..<count where rects[i].width > 0 && rects[i].height > 0 {
                runInk = runInk.union(rects[i].offsetBy(dx: positions[i].x, dy: positions[i].y))
            }
            ink = ink.union(runInk.isNull ? typo : runInk)
        }
        return ink.isNull ? fallback : ink
    }

    static func layout(_ text: NSAttributedString, font: NSFont,
                       width: CGFloat, flush: CGFloat, dy: CGFloat = 0,
                       forcedBreaks: [NSRange]? = nil) -> Layout {
        let width = max(1, width)
        let step = ceil(max(font.pointSize, font.ascender - font.descender + font.leading))
        var raw: [Line] = []
        var ink = CGRect.null
        var glyphInk = CGRect.null   // real visible ink only
        var row = 0
        var breaks: [NSRange] = []
        var forcedIndex = 0
        let paragraphs = text.string.components(separatedBy: "\n")
        var offset = 0
        for paragraph in paragraphs {
            let length = (paragraph as NSString).length
            if length == 0 {
                row += 1
            } else {
                let attributed = text.attributedSubstring(from: NSRange(location: offset, length: length))
                let blankParagraph = paragraph.trimmingCharacters(in: .whitespaces).isEmpty
                let typesetter = CTTypesetterCreateWithAttributedString(attributed)
                var start = 0
                while start < length {
                    var count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
                    // Reference layouts reuse the current wrap topology so row structure matches;
                    // a forced range is honored only when it lines up with this paragraph position.
                    if let forced = forcedBreaks, forcedIndex < forced.count,
                       forced[forcedIndex].location == offset + start,
                       forced[forcedIndex].length > 0, forced[forcedIndex].length <= length - start {
                        count = forced[forcedIndex].length
                    }
                    forcedIndex += 1
                    breaks.append(NSRange(location: offset + start, length: min(count, length - start)))
                    let line = CTTypesetterCreateLine(typesetter,
                        CFRange(location: start, length: min(count, length - start)))
                    let origin = CGPoint(x: CGFloat(CTLineGetPenOffsetForFlush(line, flush, Double(width))),
                                         y: -CGFloat(row) * step + dy)
                    raw.append(Line(text: line, origin: origin))
                    var bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
                    // Keep blank-space rows and bitmap fallback metrics represented too.
                    var ascent: CGFloat = 0, descent: CGFloat = 0
                    let advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
                    let metric = CGRect(x: 0, y: -descent, width: advance, height: ascent + descent)
                    // Visible ink: glyph path bounds; bitmap/fallback runs (emoji, note signs)
                    // that report no path bounds fall back to their typographic box.
                    if !blankParagraph {
                        let visible = visibleInk(of: line, fallback: metric)
                        glyphInk = glyphInk.union(visible.offsetBy(dx: origin.x, dy: origin.y))
                    }
                    bounds = bounds.union(metric)
                    ink = ink.union(bounds.offsetBy(dx: origin.x, dy: origin.y))
                    start += min(count, length - start)
                    row += 1
                }
            }
            offset += length + 1
        }
        // Preserve empty rows and the requested alignment canvas. Glyph overhangs
        // expand the canvas rather than being clipped or changing baseline distance.
        // dy translates the whole block (baselines, guard, ink) uniformly before the canvas is
        // computed, so the canvas always covers the translated ink.
        let lastBaseline = -CGFloat(max(0, row - 1)) * step + dy
        ink = ink.union(CGRect(x: 0, y: lastBaseline + font.descender,
                              width: width, height: font.ascender - font.descender - (lastBaseline - dy)))
        if glyphInk.isNull { glyphInk = ink }
        let padding: CGFloat = 2
        let extent = ink.insetBy(dx: -padding, dy: -padding).integral
        let lines = raw.map { Line(text: $0.text, origin: CGPoint(x: $0.origin.x - extent.minX,
                                                                 y: $0.origin.y - extent.minY)) }
        let inkLocal = glyphInk.offsetBy(dx: -extent.minX, dy: -extent.minY)
        return Layout(lines: lines, size: extent.size, inkRect: inkLocal, breaks: breaks)
    }
}

final class SubtitleInkLayer: CATextLayer {
    var inkLayout: SubtitleTypography.Layout?
    var inkColor: CGColor = NSColor.white.cgColor

    override func draw(in context: CGContext) {
        guard let inkLayout else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.setFillColor(inkColor)
        // Layer backing contexts may be flipped; normalize to CoreText's Y-up space.
        if isGeometryFlipped {
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        for line in inkLayout.lines {
            context.textPosition = line.origin
            CTLineDraw(line.text, context)
        }
        context.restoreGState()
    }
}

final class SubtitleView: NSView {

    // MARK: - Configuration

    struct Config {
        // ── Layout ───────────────────────────────────────────────────
        static let initialScale: CGFloat = 1.0
        static let minScale: CGFloat     = 2.0
        static let maxScale: CGFloat     = 2.5
        static let stepAmount: CGFloat   = 0.2

        static let mLeft:   CGFloat = PhotonFont.charW + PhotonFont.pad * 1.6
        static let mRight:  CGFloat = PhotonFont.charW + PhotonFont.pad * 2.6
        static let mTop:    CGFloat = PhotonFont.pad
        static let mBottom: CGFloat = PhotonFont.pad / 2

        static let alignLeftEnd:      CGFloat = 0.30
        static let alignRightStart:   CGFloat = 0.70
        static let baseWDivisor:      CGFloat = 2.0
        static var pipBlockGap:CGFloat {PhotonFont.pad * 2}
        static let defaultStartPosition: Int  = 2
        static var subPosRandom:      Bool    = false

        // ── Fade timing (proportional to subtitle on-screen duration) ─
        static let fadeInRatio:  Double = 0.10  // share of subtitle duration
        static let fadeOutRatio: Double = 0.16  // share of subtitle duration
        static let fadeInMax:    Double = 0.50  // upper cap in seconds
        static let fadeOutMax:   Double = 0.60  // upper cap in seconds
        static let fadeMinimum:  Double = 0.06  // lower floor in seconds

        // ── wght smoother time constants ─────────────────────────────
        // Reference only, not read at runtime - AudioNormalizer owns the
        // live values (I10); these taus shape motion feel, not range.
        static let wghtAttackTau:  Double = AudioNormalizer.attackTau
        static let wghtReleaseTau: Double = AudioNormalizer.releaseTau

        // ── Per-axis enable flags ─────────────────────────────────────
        // Set false to disable an axis entirely (holds at its neutral value).
        // Disable axisWghtEnabled + fadeEnabled + fontVariationWithFade
        // together to observe raw audio level changes in isolation.
        static var axisWghtEnabled: Bool = true   // audio level  → wght
        static var axisSizeEnabled: Bool = false   // mouse distance → SIZE axis
        static var axisRotaEnabled: Bool = false  // mouse angle    → ROTA axis

        // ── Fade debug flags ──────────────────────────────────────────
        /// Master switch for opacity fade in/out on subtitle transitions.
        /// When false, subtitles appear and disappear instantly.
        static var fadeEnabled: Bool = false

        /// When true, wght is interpolated alongside fade progress (300→target
        /// on fade-in, target→300 on fade-out).  When false, the display-link
        /// loop drives wght independently, unaffected by opacity transitions.
        /// Disable this to verify that wght variation reaches the text layer
        /// without being overwritten by the fade engine.
        static var fontVariationWithFade: Bool = true
        
        static var faceAvoidance: Bool = true
        
        static var wghtDebugLog: Bool = false

        // ── Live caption mode ───────────────────────────────────────
        /// True while LiveCaptionController feeds whisper-live output
        /// through show(). Does NOT suppress subPosRandom (Shift+0) or
        /// touch axisWghtEnabled/fadeEnabled - live captions behave like
        /// any other subtitle.
        static var liveCaptionActive: Bool = false

    }

    // MARK: - Properties
    private var currentText      = ""
    private var lastChangeTime: Double = 0
    private let textLayer        = SubtitleInkLayer()
    private var renderedText = ""
    private var adaptiveTextColor = NSColor.white
    private var adaptiveTargetColor = NSColor.white
    private var adaptiveColorTimer: Timer?
    private var adaptiveColorGeneration: UInt64 = 0
    // Natural (dy = 0) content height of the shown cue; the cross-fade decision compares this,
    // never the translated canvas height, so wght-driven dy cannot trigger cross-fades.
    private var naturalContentHeight: CGFloat = 0
    // Reference ink center: world-space, taken at a fixed nominal wght and NOT re-taken while
    // audio wght or color ticks. Reset only through its key (see ReferenceKey).
    private struct ReferenceKey: Equatable {
        let text: String; let width: CGFloat; let flush: CGFloat; let userScale: CGFloat
        let ratio: CGPoint; let boundsHeight: CGFloat; let family: String; let pointSize: CGFloat
        /// Wrap topology of the CURRENT layout (CTLine break ranges): a reflow retakes the reference.
        let breaks: [NSRange]
        /// Every variation value except the audio-driven (signal 0) tags. size/rota/custom mapped
        /// axes are part of the reference; audio wght ticks are not.
        let nonAudioVars: [Int: Double]
    }
    // size / rota signals exactly as last written to the font (listener or fade path).
    private var appliedSize: Double = 0
    private var appliedRota: Double = 0
    private var referenceKey: ReferenceKey?
    private var referenceWorldCenterY: CGFloat = 0

    private var userScale: CGFloat    = Config.initialScale
    private var subtitleFontScale=1.0
    private var committedGlyphCompensation=1.0
    private var subtitleDelay=0.0
    private var lastSubtitlePosition:Double?
    private var pictureInPictureTypography=false

    func setSubtitleFontScale(_ value:Double) {
        guard value.isFinite,value>0,abs(value-subtitleFontScale)>0.000001 else{return}
        subtitleFontScale=value
        unfreezeOutgoingGeometry()
        let vars=PhotonFont.buildSVVars(signal0T:targetWght,signal1T:appliedSize,signal2T:targetRota)
        applySVFont(PhotonFont.ct(vars:vars,size:CGFloat(targetFontSize)),fontSize:CGFloat(targetFontSize))
        needsLayout=true
    }
    func resetSubtitleFontSize() {
        if !pictureInPictureTypography {userScale=Config.initialScale}
        subtitleFontScale=1
        let picture=window?.convertToScreen(convert(bounds,to:nil)) ?? bounds
        let distance=hypot(NSEvent.mouseLocation.x-picture.midX,NSEvent.mouseLocation.y-picture.midY)
        targetFontSize=SubtitlePresentation.fontSize(userScale:Double(userScale),proximity:SubtitlePresentation.proximity(distance:distance),pictureInPicture:pictureInPictureTypography,windowHeight:Double(bounds.height))
        unfreezeOutgoingGeometry()
        let vars=PhotonFont.buildSVVars(signal0T:targetWght,signal1T:appliedSize,signal2T:targetRota)
        applySVFont(PhotonFont.ct(vars:vars,size:CGFloat(targetFontSize)),fontSize:CGFloat(targetFontSize))
        needsLayout=true
    }
    func setSubtitleDelay(_ value:Double) {
        guard value.isFinite,abs(value-subtitleDelay)>0.000001 else{return}
        subtitleDelay=value
        // Invalidate the old display window immediately. The next authoritative
        // mpv text/cue-store lookup will select the cue at the new delay.
        show(text:"",duration:0,at:lastCueProbeTime ?? 0)
    }
    func setSubtitlePosition(_ value:Double,force:Bool=false) {
        guard value.isFinite,force || lastSubtitlePosition != value else{return}
        defer {lastSubtitlePosition=value}
        // Initial property discovery must not undo the existing default/random
        // position; only an actual property change moves the custom cue.
        guard force || lastSubtitlePosition != nil else{return}
        let y=CGFloat(min(100,max(0,value))/100)
        guard abs(userPosRatio.y-y)>0.000001 else{return}
        userPosRatio.y=y;unfreezeOutgoingGeometry();needsLayout=true
    }

    var subtitlePositionProperty:Double {lastSubtitlePosition ?? 100}
    var typographyProbe:[String:Any] {
        ["pictureInPictureTypography":pictureInPictureTypography,"subtitleUserScale":Double(userScale),
         "subtitleFontScale":subtitleFontScale,"subtitleTargetPointSize":targetFontSize,
         "subtitleRenderedPointSize":Double(textLayer.fontSize),"subtitleResolvedPointSize":Double(resolvedFont().pointSize),
         "subtitleCanvasWidth":Double(bounds.width),"subtitleCanvasHeight":Double(bounds.height),
         "subtitleWrapWidth":Double(wrappingWidth(font:resolvedFont()))]
    }

    private var normalSubtitlePosition:(ratio:CGPoint,property:Double?)?
    private var pipSubtitlePosition:(ratio:CGPoint,property:Double?)?
    private var normalTypographyBeforePiP:(fontSize:Double,size:Double)?

    /// PiP is a viewing mode, not a pointer-proximity target. Apply immediately,
    /// including a paused cue or an outgoing fade that has no listener ticks.
    func setPictureInPictureTypography(_ active:Bool) {
        guard pictureInPictureTypography != active else{return}
        if active {
            normalTypographyBeforePiP=(targetFontSize,targetSize)
            normalSubtitlePosition=(userPosRatio,lastSubtitlePosition)
            if let saved=pipSubtitlePosition {userPosRatio=saved.ratio;lastSubtitlePosition=saved.property}
        } else {
            pipSubtitlePosition=(userPosRatio,lastSubtitlePosition)
            if let saved=normalSubtitlePosition {userPosRatio=saved.ratio;lastSubtitlePosition=saved.property}
        }
        pictureInPictureTypography=active
        if !active,let previous=normalTypographyBeforePiP {
            targetFontSize=previous.fontSize;targetSize=previous.size
            normalTypographyBeforePiP=nil
        }
        appliedSize=active ? 0 : targetSize
        unfreezeOutgoingGeometry()
        let vars=PhotonFont.buildSVVars(signal0T:targetWght,signal1T:appliedSize,signal2T:targetRota)
        applySVFont(PhotonFont.ct(vars:vars,size:CGFloat(targetFontSize)),fontSize:targetFontSize)
        needsLayout=true
    }

    private var userPosRatio: CGPoint = .zero
    private var hasInitialPos         = false

    // Axis targets - written by the VB listener, read by the fade engine
    // and layout. targetWght is tFull [0,1] from smoothForAxis(), for
    // buildSVVars(signal0T:); smoother state lives in AudioNormalizer.
    private var targetWght: Double = 0.0
    private var targetSize: Double = 0
    private var targetRota: Double = 0
    private var targetFontSize: Double = PhotonFont.size

    private var lastListenerTime: Double = 0   // CACurrentMediaTime() at previous tick

    private var wghtLastLogTime:  Double = 0   // throttle for wght debug log
    
    // I2: SV's own AudioNormalizer - never shared with VB, never ctDriven.
    // I17: smoothing runs in axis-space via smoothForAxis(), never t-space.
    private var normalizer = AudioNormalizer()

    // MARK: - Transition geometry freeze
    //
    // During an enabled fade, hold outgoing ink/frame until the text swap.
    // This alone is insufficient when fades are disabled (the default): that
    // path swaps immediately, so commitTextLayer also publishes ink + frame +
    // backing pixels together, without a deferred NSView-layout seam.
    private var frozenOutgoingText: String?
    private var frozenFrame: CGRect?
    private var frozenInkLayout: SubtitleTypography.Layout?

    /// Snapshot the outgoing cue's last committed geometry at transition start.
    private func freezeOutgoingGeometry() {
        guard !renderedText.isEmpty, textLayer.opacity > 0 else { return }
        // Rapid A->B->C: the first freeze is still the committed geometry; keep it.
        if frozenOutgoingText == renderedText, frozenFrame != nil { return }
        frozenOutgoingText = renderedText
        frozenFrame        = textLayer.frame
        frozenInkLayout    = textLayer.inkLayout
    }

    private func unfreezeOutgoingGeometry() {
        frozenOutgoingText = nil
        frozenFrame        = nil
        frozenInkLayout    = nil
    }

    // Fade state.
    private var fadeTimer: Timer?
    private var fadeProgress: Double = 0.0     // 0 = fully hidden, 1 = fully visible
    private var pendingFadeTarget: (text: String, duration: Double)?

    // MARK: - Pause freeze
    //
    // While paused nothing on screen may change, but two subsystems kept
    // mutating the subtitle with playback time frozen:
    //   1. The VB listener ran every tick while a subtitle was visible,
    //      smoothing the (decaying) captured audio level into wght - the
    //      font visibly thinned, or thickened on ambient noise.
    //   2. scheduleAutoHide ran on the WALL clock, so a cue shown for
    //      `duration` faded out mid-pause; the cue was still active at
    //      the frozen playback time, so checkExternalCue re-showed it and
    //      it faded back in - the paused fade-out/fade-in loop.
    // playbackPaused freezes both: the listener bails, auto-hide is
    // disarmed (re-armed with its remaining time on resume), and an
    // in-flight fade is suspended and resumed.
    //
    // The controller may set this from mpv's pause event; when it does
    // not, checkExternalCue auto-derives it from frozen timestamps.
    var playbackPaused: Bool = false {
        didSet {
            guard playbackPaused != oldValue else { return }
            if playbackPaused { freezeForPause() } else { resumeFromPause() }
        }
    }

    // Fade parameters mirrored out of startFade's closure so an in-flight
    // fade can be suspended at pause and resumed with its remaining time.
    private var fadeTargetOpacity: Float = 0
    private var fadeDuration:      Double = 0
    private var fadeStartTime:     Double = 0
    private var fadeStartOpacity:  Float = 0
    private var fadeStartProgress: Double = 0
    private var fadeCompletion:    (() -> Void)?

    private struct SuspendedFade {
        let targetOpacity: Float
        let duration: Double
        let elapsed: Double
        let startOpacity: Float
        let startProgress: Double
        let completion: (() -> Void)?
    }
    private var suspendedFade: SuspendedFade?

    // Wall-clock auto-hide bookkeeping. The token disarms a pending
    // asyncAfter fire; shownAt/duration let pause capture the remaining
    // display time so resume re-arms only what is left.
    private var autoHideToken:    Int = 0
    private var autoHideShownAt:  Double = 0
    private var autoHideDuration: Double = 0
    private var autoHideOutDur:   Double = 0
    private var pausedAutoHideRemaining: Double?
    // Cue media-time ownership survives seeks, speed changes and pause.
    private var activeCueStart: Double?
    private var activeCueEnd: Double?

    // Pause auto-detection: repeated identical playback times handed to
    // checkExternalCue mean the clock is frozen (mpv paused).
    private var lastCueProbeTime:   Double?
    private var cueTimeRepeatCount: Int = 0

    // OpenSubtitles state
    var isPGSCodec: Bool = false
    var currentFilePath: String = ""
    private var subtitleLookupGeneration = 0
    func invalidateSubtitleLookup() { subtitleLookupGeneration += 1 }
    private var subtitleLookupKey: String?
    private var lastSubtitleSearchStatus: String?
    private var loadedSrcSubtitle: (moviePath: String, srtData: Data)?
    private func isCurrentSubtitleLookup(_ generation: Int, path: String) -> Bool {
        subtitleLookupGeneration == generation && currentFilePath == path
    }
    var onSubtitleSearchStatus: ((String) -> Void)?
    private func publishSubtitleSearchStatus(_ status: String) {
        lastSubtitleSearchStatus = status
        onSubtitleSearchStatus?(status)
    }
    var subtitleSearchStatus: String? { lastSubtitleSearchStatus }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        setupLayer()
        setDefaultPosition()
        setupListener()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupLayer() {
        wantsLayer = true
        // HDR-P-GOR (DR-198A-5C): cues stay pinned to SDR white when an EDR
        // surface is active underneath. SubtitleView remains the subtitle
        // presentation owner; this pin keeps every cue layer out of the
        // extended dynamic range. Presenter-side cue labels carry the same
        // invariant on the gorav lane.
        // wantsExtendedDynamicRangeContent is macOS 14+; on macOS 13 the
        // property does not exist, so the SDR pin holds trivially there.
        if #available(macOS 14.0, *) {
            layer?.wantsExtendedDynamicRangeContent = false
            vrSubtitleContainer.wantsExtendedDynamicRangeContent = false
            textLayer.wantsExtendedDynamicRangeContent = false
        }
        
        textLayer.alignmentMode   = .left
        textLayer.isWrapped       = true
        textLayer.truncationMode  = .none
        applySVFont(PhotonFont.ct(size: PhotonFont.size), fontSize: PhotonFont.size)
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.contentsScale   = NSScreen.main?.backingScaleFactor ?? 2
        // WHY: font writes are change-guarded (applySVFont), so
        // geometry-only updates must be able to trigger a re-render.
        textLayer.needsDisplayOnBoundsChange = true
        textLayer.opacity         = 0
        
        textLayer.shadowColor   = NSColor.black.cgColor
        textLayer.shadowRadius  = PPController.shadowRadius
        textLayer.shadowOpacity = PPController.shadowOpacity
        textLayer.shadowOffset  = .zero
        
        // Opacity is already animated by our timer; Core Animation must not add
        // its own trailing opacity/geometry/contents animations to cue commits.
        textLayer.actions = Dictionary(uniqueKeysWithValues:
            ["opacity", "position", "bounds", "contents", "string", "font", "fontSize",
             "foregroundColor", "alignmentMode"].map { ($0, NSNull() as CAAction) })
        // Custom text remains in one compositor, replicated for stereo.
        vrSubtitleContainer.anchorPoint = .zero // sublayer transform is in the view-local origin
        vrSubtitleReplicator.instanceCount = 1
        vrSubtitleReplicator.addSublayer(vrSubtitleContainer)
        layer?.addSublayer(vrSubtitleReplicator)
        vrSubtitleContainer.addSublayer(textLayer)
        layer?.masksToBounds = false
        clipsToBounds = false
    }

    private func setupListener() {
        VariationBroadcaster.shared.addListener(weakLifetime: self) { [weak self] in
            guard let self = self else { return }
            // WHY: most of a movie has no subtitle on screen - the
            // per-tick math, smoothing, font rebuild and re-rasterize have
            // no visible effect then, so bail. Also bail when the view
            // itself is faded out at the window level.
            guard self.textLayer.opacity > 0, self.isEffectivelyVisible else { return }
            // Paused: freeze the rendered state. No audio- or mouse-driven
            // font variation while playback time is not advancing.
            guard !playbackPaused else { return }

            // real elapsed time, so the smoother ignores refresh-rate variation
            let now = CACurrentMediaTime()
            let dt  = lastListenerTime > 0 ? min(now - lastListenerTime, 0.1) : (1.0 / 60.0)
            lastListenerTime = now

            let subtitleCenter = CGPoint(x: textLayer.frame.midX, y: textLayer.frame.midY)
            let screenOrigin   = window?.convertToScreen(
                convert(NSRect(origin: subtitleCenter, size: .zero),to:nil)
            ).origin ?? .zero
            let dx = NSEvent.mouseLocation.x - screenOrigin.x
            let dy = NSEvent.mouseLocation.y - screenOrigin.y
            var rota = atan2(dy, dx) * 180 / .pi
            if rota < 0 { rota += 360 }
            let finalRota = Config.axisRotaEnabled ? rota : 0.0

            let screenFrame = window?.screen?.frame ?? NSScreen.main?.frame ?? .zero
            let pictureFrame=window?.convertToScreen(convert(bounds,to:nil)) ?? bounds
            let maxDistance = hypot(screenFrame.width/2,screenFrame.height/2)
            let mouseDistance = hypot(NSEvent.mouseLocation.x-pictureFrame.midX,
                                      NSEvent.mouseLocation.y-pictureFrame.midY)
            let rawSize  = min(1.0, mouseDistance / maxDistance) * 100
            let finalSize = SubtitlePresentation.sizeAxis(pointerValue:rawSize,enabled:Config.axisSizeEnabled,pictureInPicture:pictureInPictureTypography)

            // smoothForAxis() bundles tick() + axis-space smooth and
            // returns tFull [0,1] for buildSVVars(signal0T:) (I17).
            let rawLevel = Double(ScreenCaptureEngine.shared.currentAudioLevel)
            let tFull   = normalizer.smoothForAxis(level: rawLevel, dt: dt)
            let finalT  = Config.axisWghtEnabled ? tFull : AudioNormalizer.svAxisLow

            // throttled to ~4 Hz
            if Config.wghtDebugLog, now - wghtLastLogTime > 0.25 {
                wghtLastLogTime = now
                let filled = Int((rawLevel * 20).rounded())
                let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: 20 - filled)
                NSLog(String(format: "[SV-WGHT]  level: %.3f |%@| tFull: %.3f  finalT: %.3f  opacity: %.2f",
                                             rawLevel, bar, tFull, finalT, textLayer.opacity))
            }

            // Both modes use the same physical screen center and radius. An eye
            // canvas changes wrapping/clipping, not glyph size or mouse range.
            let p = SubtitlePresentation.proximity(distance:Double(mouseDistance))
            let finalFontSize = SubtitlePresentation.fontSize(userScale:Double(userScale), proximity:p,pictureInPicture:pictureInPictureTypography,windowHeight:Double(bounds.height))

            targetWght     = finalT
            targetSize     = finalSize
            targetRota     = finalRota
            targetFontSize = finalFontSize

            // WHY: the listener always owns the variation write, fade or
            // no fade - applyVariationDuringFade interpolates opacity only.
            // buildSVVars reads axisMapping[0/1/2]: signal 0 = tFull
            // (full-range), signals 1/2 = default-anchored. Never ctDriven (I2).
            appliedSize = finalSize
            appliedRota = finalRota
            let svVars = PhotonFont.buildSVVars(
                signal0T: finalT,
                signal1T: finalSize,
                signal2T: finalRota
            )
            applySVFont(PhotonFont.ct(vars: svVars, size: CGFloat(targetFontSize)),
                        fontSize: finalFontSize)
        }
    }

    /// I38: single write point for textLayer's font + fontSize; the guard
    /// compares against the layer's own model values, never a shadow copy.
    /// WHY: a font assignment refreshes the ink layout. PhotonFont.ct(vars:size:) returns the same
    /// cached instance for the same quantized input, so identity catches
    /// "nothing changed".
    // 196w: quantized-skip state for the applySVFont write guard below.
    private var lastAppliedRequestedFont: CTFont?
    private var lastAppliedQuantizedSize: CGFloat = -1
    @discardableResult
    private func applySVFont(_ requestedFont: CTFont, fontSize requestedSize: CGFloat) -> Bool {
        // The final write is the safety boundary for initialization, fades,
        // zoom and paused mode changes as well as the animation listener.
        let baseSize=pictureInPictureTypography ? CGFloat(SubtitlePresentation.pipFontSize(userScale:Double(userScale),windowHeight:Double(bounds.height))) : requestedSize
        let fontSize=baseSize*CGFloat(subtitleFontScale*committedGlyphCompensation)
        // 196w: the film-frame compensation is continuous in the published film
        // scale (1/scale), so under head-driven zoom it wobbles every frame and
        // the exact-equality guard below never held: each tick re-set the font,
        // re-set the string and forced a full CATextLayer re-typeset. Skip the
        // write unless the final size crosses PhotonFont's cache quantum
        // (0.25pt, sub-pixel at any backing scale) or the requested font itself
        // changes. PiP typography keeps the exact guard.
        let quantizedSize=(fontSize*4).rounded()/4
        if !pictureInPictureTypography,let last=lastAppliedRequestedFont,(last as AnyObject)===(requestedFont as AnyObject),quantizedSize==lastAppliedQuantizedSize { return false }
        let font:CTFont
        if pictureInPictureTypography {
            let vars=PhotonFont.buildSVVars(signal0T:targetWght,signal1T:0,signal2T:targetRota)
            font=PhotonFont.ct(vars:vars,size:fontSize)
            appliedSize=0
        } else {font=subtitleFontScale*committedGlyphCompensation == 1 ? requestedFont : CTFontCreateCopyWithAttributes(requestedFont,fontSize,nil,nil)}
        let sameFont = (textLayer.font as AnyObject?) === (font as AnyObject)
        let sameSize = textLayer.fontSize == fontSize
        if sameFont && sameSize { return false }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.font = font
        textLayer.fontSize = fontSize
        refreshTextLayerString()
        // I1: setNeedsDisplay() after every .font mutation, inside
        // CATransaction - without it the axis write is silently deferred
        // (needsLayout alone is not sufficient).
        textLayer.setNeedsDisplay()
        CATransaction.commit()
        // A PiP write replaces the layer's font outside the skip key, so it
        // invalidates the non-PiP skip state (the next non-PiP call must not
        // skip against a font the PiP path installed).
        if pictureInPictureTypography { lastAppliedRequestedFont=nil; lastAppliedQuantizedSize = -1 } else { lastAppliedRequestedFont=requestedFont; lastAppliedQuantizedSize=quantizedSize }
        return true
    }

    // MARK: - Font variation during fade
    //
    //  Called by the fade timer on each opacity tick. wght is owned by the
    //  VB listener; this only keeps SIZE interpolated against fadeProgress
    //  and fontSize in sync. Fully bypassed when fontVariationWithFade is off.
    //
    private func applyVariationDuringFade() {
        guard Config.fontVariationWithFade else { return }
        guard fadeProgress >= 0, fadeProgress <= 1 else { return }

        // wght is owned by the VB listener - don't overwrite it here.
        let currentSize = targetSize * fadeProgress

        // targetWght arrives from SV's own AudioNormalizer - never ctDriven (I2).
        appliedSize = currentSize
        appliedRota = targetRota
        let svVars = PhotonFont.buildSVVars(
            signal0T: max(0.0, min(1.0, targetWght)),
            signal1T: currentSize,
            signal2T: targetRota
        )
        applySVFont(PhotonFont.ct(vars: svVars, size: CGFloat(targetFontSize)),
                    fontSize: targetFontSize)
    }

    // MARK: - Fade duration computation

    private func fadeInDuration(for subtitleDuration: Double) -> Double {
        guard Config.fadeEnabled else { return 0 }
        let raw = subtitleDuration * Config.fadeInRatio
        return max(Config.fadeMinimum, min(raw, Config.fadeInMax))
    }

    private func fadeOutDuration(for subtitleDuration: Double) -> Double {
        guard Config.fadeEnabled else { return 0 }
        let raw = subtitleDuration * Config.fadeOutRatio
        return max(Config.fadeMinimum, min(raw, Config.fadeOutMax))
    }

    // MARK: - Fade engine
    //
    //  Animates textLayer.opacity along a cubic ease-in-out via a 60 Hz
    //  Timer. fadeEnabled = false applies the change instantly, no timer.
    //
    private func startFade(to targetOpacity: Float,
                           duration: Double,
                           completion: (() -> Void)? = nil) {
        startFade(to: targetOpacity, duration: duration, elapsed: 0,
                  startOpacity: textLayer.opacity, startProgress: fadeProgress,
                  completion: completion)
    }

    /// Workhorse behind startFade; the extra parameters let resumeFromPause
    /// re-arm a suspended fade with only its remaining time.
    private func startFade(to targetOpacity: Float,
                           duration: Double,
                           elapsed initialElapsed: Double,
                           startOpacity: Float,
                           startProgress: Double,
                           completion: (() -> Void)?) {
        fadeTimer?.invalidate()

        let endProgress   = Double(targetOpacity)
        let startTime     = CACurrentMediaTime() - initialElapsed
        let remaining     = duration - initialElapsed

        // Mirror the parameters so freezeForPause can suspend this fade.
        fadeTargetOpacity = targetOpacity
        fadeDuration      = duration
        fadeStartTime     = startTime
        fadeStartOpacity  = startOpacity
        fadeStartProgress = startProgress
        fadeCompletion    = completion

        // Apply instantly when the remaining duration is negligible or
        // fade is disabled.
        guard remaining > 0.016 else {
            textLayer.opacity = targetOpacity
            fadeProgress = endProgress
            fadeCompletion = nil
            applyVariationDuringFade()
            completion?()
            return
        }

        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let elapsed = CACurrentMediaTime() - startTime
            var t       = elapsed / duration

            if t >= 1.0 {
                self.textLayer.opacity = targetOpacity
                self.fadeProgress = endProgress
                self.fadeTimer?.invalidate()
                self.fadeTimer = nil
                self.fadeCompletion = nil
                self.applyVariationDuringFade()
                completion?()
            } else {
                // Cubic ease-in-out approximation.
                t = t < 0.5
                    ? 2 * t * t
                    : 1 - pow(-2 * t + 2, 2) / 2

                self.textLayer.opacity = startOpacity + (targetOpacity - startOpacity) * Float(t)
                self.fadeProgress = startProgress + (endProgress - startProgress) * t
                self.applyVariationDuringFade()
            }
        }
        RunLoop.main.add(fadeTimer!, forMode: .common)
    }

    // MARK: - Pause freeze / resume

    /// Freeze the rendered subtitle state. The VB listener already bails
    /// on playbackPaused; here we suspend an in-flight fade in place and
    /// disarm the wall-clock auto-hide, capturing its remaining time.
    private func freezeForPause() {
        if fadeTimer != nil {
            fadeTimer?.invalidate()
            fadeTimer = nil
            suspendedFade = SuspendedFade(
                targetOpacity: fadeTargetOpacity,
                duration: fadeDuration,
                elapsed: CACurrentMediaTime() - fadeStartTime,
                startOpacity: fadeStartOpacity,
                startProgress: fadeStartProgress,
                completion: fadeCompletion)
            fadeCompletion = nil
        }
        autoHideToken += 1   // disarm any pending wall-clock auto-hide fire
        if textLayer.opacity > 0, !currentText.isEmpty, autoHideDuration > 0 {
            let elapsed = CACurrentMediaTime() - autoHideShownAt
            pausedAutoHideRemaining = autoHideDuration - elapsed
        } else {
            pausedAutoHideRemaining = nil
        }
    }

    /// Resume exactly what pause froze: the auto-hide gets only its
    /// remaining display time, a suspended fade continues from where it
    /// stopped. If the display window fully elapsed during the pause, the
    /// subtitle hides right away instead of lingering.
    private func resumeFromPause() {
        if let remaining = pausedAutoHideRemaining {
            pausedAutoHideRemaining = nil
            if remaining <= 0 {
                autoHideDuration = 0
                unfreezeOutgoingGeometry()
                startFade(to: 0, duration: autoHideOutDur)
                currentText = ""
            } else {
                scheduleAutoHide(text: currentText, duration: remaining,
                                 outDur: autoHideOutDur, floorToMinimum: false)
            }
        }
        if let fade = suspendedFade {
            suspendedFade = nil
            startFade(to: fade.targetOpacity, duration: fade.duration,
                      elapsed: fade.elapsed, startOpacity: fade.startOpacity,
                      startProgress: fade.startProgress, completion: fade.completion)
        }
    }

    // MARK: - Mouse events
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if let winPt = window?.contentView?.convert(event.locationInWindow, from: nil) {
            VariationBroadcaster.shared.update(windowPt: winPt)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let isInteracting = event.phase != [] || event.momentumPhase != []
        guard isInteracting else { return }
        if event.modifierFlags.contains(.command) {
            applyStepZoom(up: event.scrollingDeltaY > 0)
        } else {
            applyPan(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        if textLayer.frame.insetBy(dx: -20, dy: -20).contains(localPoint) {
            return self
        }
        return nil
    }

    // MARK: - Manipulation
    func applyStepZoom(up: Bool) {
        let delta = up ? Config.stepAmount : -Config.stepAmount
        userScale = max(Config.minScale, min(userScale + delta, Config.maxScale))
        if textLayer.opacity > 0 { applyVariationDuringFade() }
        needsLayout = true
        if let winPt = window?.mouseLocationOutsideOfEventStream {
            VariationBroadcaster.shared.update(windowPt: convert(winPt, from: nil))
        }
    }

    func applyPan(dx: CGFloat, dy: CGFloat) {
        let screenW = bounds.width  > 0 ? bounds.width  : 1
        let screenH = bounds.height > 0 ? bounds.height : 1
        userPosRatio.x = max(0, min(1, userPosRatio.x + dx / screenW))
        userPosRatio.y = max(0, min(1, userPosRatio.y - dy / screenH))
        needsLayout = true
    }

    // 180d: replicator + container hosting textLayer for stereo mirroring.
    /// Hide custom ink until native subtitle OFF is acknowledged.
    func setNativeSubtitleRendererActive(_ active: Bool) {
        guard vrSubtitleReplicator.isHidden != active else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        vrSubtitleReplicator.isHidden = active
        CATransaction.commit()
    }

    private let vrSubtitleReplicator = CAReplicatorLayer()
    private let vrSubtitleContainer = CALayer()
    private let vrSubtitleSafeMask = CALayer()
    private var vrSubtitleOffset: CGFloat = 0
    private var vrSubtitleOn = false
    private var subtitleTilt=(roll:0.0,pair:0.0)
    private var subtitleTiltCanvas=CGRect.zero
    private var subtitleUIPlacementCanvas=CGRect.zero
    private var subtitleTiltReplica=(shift:CGFloat(0),left:CGFloat(0),offset:CGFloat(0))
    private var overlayControlBounds:CGRect?
    // PPController owns the shared control rail rect. Keep it in SubtitleView-local
    // coordinates so the tilt publisher can anchor controls there without changing
    // the subtitle ink placement or replica depth.
    func setTrackedOverlayBounds(_ rect:CGRect?,in host:NSView) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setTrackedOverlayBounds(rect,in:host) }
            return
        }
        guard let rect,rect.width>0,rect.height>0 else { overlayControlBounds=nil;return }
        let local=convert(rect,from:host)
        overlayControlBounds=local.width>0 && local.height>0 ? local:nil
    }
    func setTrackedTilt(roll:Double,pairRoll:Double) {
        subtitleTilt=(roll,pairRoll);applyTrackedSubtitleTilt()
    }
    // The subtitle compositor owns the rigid per-eye overlay geometry. Controls
    // consume this exact placement, including its translation-only ink safety.
    private func legacyOverlayInkFrame()->CGRect {
        guard abs(committedGlyphCompensation-1)>0.000001 else{return textLayer.frame}
        // The compatibility UI uses194p's unscaled text metrics. Counter-fit raster
        // sizing belongs to subtitles only and must never change the old UI pivot.
        let scaled=resolvedFont()
        let font=NSFont(descriptor:scaled.fontDescriptor,size:scaled.pointSize/CGFloat(committedGlyphCompensation)) ?? scaled
        let width=wrappingWidth(font:font)
        let x:CGFloat
        if userPosRatio.x<0.1 {x=horizontalMargin(font:font,left:true)}
        else if userPosRatio.x>0.9 {x=bounds.width-width-horizontalMargin(font:font,left:false)}
        else {x=horizontalMargin(font:font,left:true)+max(0,bounds.width-width-horizontalMargin(font:font,left:true)-horizontalMargin(font:font,left:false))*userPosRatio.x}
        let placed=placement(text:renderedText,font:font,width:width,flush:flush(forRatioX:userPosRatio.x),ratio:userPosRatio,useCache:false)
        return CGRect(x:x,y:placed.frameY,width:placed.layout.size.width,height:placed.layout.size.height)
    }
    func trackedOverlayPlacement(in host:NSView)->(center:NSPoint,placement:SubtitleTiltGeometry.Placement)? {
        guard vrSubtitleOn,abs(subtitleTilt.roll)>=1e-10 else{return nil}
        let ink=legacyOverlayInkFrame()
        let p=SubtitleTiltGeometry.place(ink:ink,screen:subtitleUIPlacementCanvas,
            shift:Double(subtitleTiltReplica.shift),left:Double(subtitleTiltReplica.left),offset:Double(subtitleTiltReplica.offset),roll:subtitleTilt.roll,pairRoll:subtitleTilt.pair)
        let anchor=overlayControlBounds.map{NSPoint(x:$0.midX,y:$0.midY)} ?? NSPoint(x:ink.midX,y:ink.midY)
        return (convert(anchor,to:host),p)
    }
    private var committedSubtitleFrame:[String:Double]?
    private var committedSubtitleOrigin=CGPoint.zero
    private var committedSubtitleOutput=CGSize.zero
    func setCommittedFilmFrame(_ value:[String:Double]?,origin:CGPoint,output:CGSize) {
        committedSubtitleFrame=value;committedSubtitleOrigin=origin;committedSubtitleOutput=output
        let compensation=SubtitlePresentation.fitFontCompensation(scale:value?["scale"])
        if abs(compensation-committedGlyphCompensation)>0.000001 {
            committedGlyphCompensation=compensation
            let vars=PhotonFont.buildSVVars(signal0T:targetWght,signal1T:appliedSize,signal2T:targetRota)
            // 196w: needsLayout only when applySVFont actually wrote (its
            // 0.25pt quantized skip absorbs per-frame sub-pixel wobble).
            if applySVFont(PhotonFont.ct(vars:vars,size:CGFloat(targetFontSize)),fontSize:CGFloat(targetFontSize)) { needsLayout=true }
        }
        if value == nil {
            vrSubtitleContainer.sublayerTransform=CATransform3DMakeTranslation(vrSubtitleOn ? subtitleTiltReplica.left:0,0,0)
            vrSubtitleReplicator.instanceCount=vrSubtitleOn ? 2:1
            vrSubtitleContainer.mask=nil;vrSubtitleContainer.masksToBounds=false
        }
        applyTrackedSubtitleTilt()
    }
    private func applyCommittedSubtitleFrame()->Bool {
        guard let f=committedSubtitleFrame,let scale=f["scale"],let angle=f["angle"],
              let lx=f["leftX"],let ly=f["leftY"],let rx=f["replicaX"],let ry=f["replicaY"],
              let fw=f["frameW"],let fh=f["frameH"],scale>0 else{return false}
        let w=Double(committedSubtitleOutput.width),h=Double(committedSubtitleOutput.height)
        let film=CGRect(x:0,y:0,width:fw*w,height:fh*h),ink=textLayer.frame
        // Place ink in ONE film-local rect, then apply the SAME fit as film/UI.
        // Stereo replication happens after the common map, never inside one eye's safety rect.
        let c=cos(angle),sn=sin(angle),cx=Double(film.midX),cy=Double(film.midY)
        let stereo=(f["instances"] ?? 1)>1,baseline=hypot(rx*w,ry*h)
        let ux=baseline>0 ? rx*w/baseline:1,uy=baseline>0 ? -ry*h/baseline:0
        let left=stereo ? Double(subtitleTiltReplica.left):0,offset=stereo ? Double(subtitleTiltReplica.offset):0
        func localDepth(_ value:Double)->CGPoint {CGPoint(x:(c*ux+sn*uy)*value/scale,y:(-sn*ux+c*uy)*value/scale)}
        let ld=localDepth(left),rd=localDepth(left+offset)
        let union=ink.offsetBy(dx:ld.x,dy:ld.y).union(ink.offsetBy(dx:rd.x,dy:rd.y))
        let fixX=max(film.minX-union.minX,min(0,film.maxX-union.maxX))
        let fixY=max(film.minY-union.minY,min(0,film.maxY-union.maxY))
        let safe=CGPoint(x:fixX+ld.x,y:fixY+ld.y)
        var t=CATransform3DMakeRotation(CGFloat(angle),0,0,1)
        t.m11*=CGFloat(scale);t.m12*=CGFloat(scale);t.m21*=CGFloat(scale);t.m22*=CGFloat(scale)
        t.m41=CGFloat(lx*w-Double(committedSubtitleOrigin.x)-scale*(c*cx-sn*cy)+scale*(c*safe.x-sn*safe.y))
        t.m42=CGFloat((1-ly)*h-Double(committedSubtitleOrigin.y)-scale*(sn*cx+c*cy)+scale*(sn*safe.x+c*safe.y))
        CATransaction.begin();CATransaction.setDisableActions(true)
        vrSubtitleContainer.sublayerTransform=t
        // Sublayer transforms do not transform the container's own mask. Ink is already
        // inside the film polygon by construction. Only TB needs its fixed output-band clip.
        vrSubtitleContainer.mask=nil;vrSubtitleContainer.masksToBounds=false
        if f["layout"] == 1 {
            vrSubtitleSafeMask.frame=CGRect(x:(f["clipX"] ?? 0)*w-Double(committedSubtitleOrigin.x),
                y:(1-(f["clipY"] ?? 0)-(f["clipH"] ?? 0))*h-Double(committedSubtitleOrigin.y),
                width:(f["clipW"] ?? 0)*w,height:(f["clipH"] ?? 0)*h)
            vrSubtitleSafeMask.backgroundColor=NSColor.black.cgColor;vrSubtitleContainer.mask=vrSubtitleSafeMask
        }
        vrSubtitleReplicator.instanceCount=Int(f["instances"] ?? 1)
        vrSubtitleReplicator.instanceTransform=CATransform3DMakeTranslation(CGFloat(rx*w+ux*offset),CGFloat(-ry*h+uy*offset),0)
        CATransaction.commit();return true
    }
    private func applyTrackedSubtitleTilt() {
        if applyCommittedSubtitleFrame() {return}
        guard vrSubtitleOn else{return}
        if abs(subtitleTilt.roll)<1e-10 {
            CATransaction.begin();CATransaction.setDisableActions(true)
            vrSubtitleContainer.sublayerTransform=CATransform3DMakeTranslation(subtitleTiltReplica.left,0,0)
            vrSubtitleReplicator.instanceTransform=CATransform3DMakeTranslation(subtitleTiltReplica.shift+subtitleTiltReplica.offset,0,0)
            vrSubtitleContainer.masksToBounds=true;updateVRSubtitleMask();CATransaction.commit();return
        }
        let ink=textLayer.frame,p=SubtitleTiltGeometry.place(ink:ink,screen:subtitleTiltCanvas,
            shift:Double(subtitleTiltReplica.shift),left:Double(subtitleTiltReplica.left),offset:Double(subtitleTiltReplica.offset),roll:subtitleTilt.roll,pairRoll:subtitleTilt.pair)
        let x=Double(ink.midX),y=Double(ink.midY),c=cos(p.angle),s=sin(p.angle)
        var t=CATransform3DMakeRotation(CGFloat(p.angle),0,0,1)
        t.m41=CGFloat(x-c*x+s*y+p.leftX);t.m42=CGFloat(y-s*x-c*y+p.leftY)
        CATransaction.begin();CATransaction.setDisableActions(true)
        vrSubtitleContainer.sublayerTransform=t;vrSubtitleContainer.mask=nil;vrSubtitleContainer.masksToBounds=false
        vrSubtitleReplicator.instanceTransform=CATransform3DMakeTranslation(CGFloat(p.replicaX),CGFloat(p.replicaY),0)
        CATransaction.commit()
    }

    private func updateVRSubtitleMask() {
        if pictureInPictureTypography && !vrSubtitleOn {
            let area=pipSubtitleArea(font:resolvedFont())
            vrSubtitleSafeMask.backgroundColor=NSColor.black.cgColor
            vrSubtitleSafeMask.frame=CGRect(x:area.minX,y:0,width:area.width,height:bounds.height)
            vrSubtitleContainer.mask=vrSubtitleSafeMask
            return
        }
        guard vrSubtitleOn,abs(subtitleTilt.roll)<1e-10 else { vrSubtitleContainer.mask = nil; return }
        let b = vrSubtitleContainer.bounds
        let x = max(0, -vrSubtitleOffset)
        vrSubtitleSafeMask.backgroundColor = NSColor.black.cgColor
        vrSubtitleSafeMask.frame = CGRect(x: b.minX + x, y: b.minY,
                                          width: max(0, b.width - abs(vrSubtitleOffset)), height: b.height)
        vrSubtitleContainer.mask = vrSubtitleSafeMask
    }

    /// Stereo replica translated on the window backing-pixel grid.
    func setVRReplica(on: Bool, shiftX: CGFloat, offsetX: CGFloat, leftOffset: CGFloat = 0, screen:CGRect = .zero, overlayScreen:CGRect? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setVRReplica(on: on, shiftX: shiftX, offsetX: offsetX, leftOffset:leftOffset,screen:screen,overlayScreen:overlayScreen) }
            return
        }
        subtitleTiltCanvas=screen;subtitleUIPlacementCanvas=overlayScreen ?? screen;subtitleTiltReplica=(shiftX,leftOffset,offsetX)
        let scale=window?.backingScaleFactor ?? textLayer.contentsScale
        let left=on ? (leftOffset*scale).rounded()/scale : 0
        let shift=((shiftX+(on ? offsetX:0))*scale).rounded()/scale
        vrSubtitleContainer.sublayerTransform=CATransform3DMakeTranslation(left,0,0)
        vrSubtitleReplicator.instanceCount = on ? 2 : 1
        vrSubtitleReplicator.instanceTransform = CATransform3DMakeTranslation(shift, 0, 0)
        vrSubtitleContainer.masksToBounds = on
        vrSubtitleOn = on
        vrSubtitleOffset = offsetX
        updateVRSubtitleMask();applyTrackedSubtitleTilt()
    }

    /// Committed local text/mask state for diagnostics.
    func vrReplicaTraceState() -> (content: CGRect?, raw: CGRect?, children: Int, clip: CGRect?, tx: CGFloat) {
        let kids = vrSubtitleContainer.sublayers ?? []
        var u: CGRect? = nil
        for k in kids { let r=k.frame.applying(CATransform3DGetAffineTransform(vrSubtitleContainer.sublayerTransform));u=u.map{$0.union(r)} ?? r }
        let raw = u
        let clip: CGRect? = vrSubtitleContainer.mask != nil ? vrSubtitleSafeMask.frame : nil
        if let c = clip, let r = u { let i = r.intersection(c); u = i.isNull ? nil : i }
        return (u, raw, kids.count, clip, vrSubtitleReplicator.instanceTransform.m41)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow();if let scale=window?.backingScaleFactor {textLayer.contentsScale=scale;textLayer.setNeedsDisplay()}
    }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties();if let scale=window?.backingScaleFactor {textLayer.contentsScale=scale;textLayer.setNeedsDisplay()}
    }
    override func layout() {
        super.layout()
        if pictureInPictureTypography {
            let vars=PhotonFont.buildSVVars(signal0T:targetWght,signal1T:0,signal2T:targetRota)
            applySVFont(PhotonFont.ct(vars:vars,size:CGFloat(targetFontSize)),fontSize:CGFloat(targetFontSize))
        }
        if let hostLayer = layer {
            vrSubtitleReplicator.frame = hostLayer.bounds
            vrSubtitleContainer.frame  = hostLayer.bounds
            updateVRSubtitleMask()
        }
        commitTextLayer()
        clipsToBounds        = false
        layer?.masksToBounds = false
    }

    /// Atomic cue/font/canvas commit, including outgoing fade and tracked tilt.
    private func commitTextLayer() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        updateVRSubtitleMask()
        // Keep the already-painted outgoing cue unchanged until its fade completes.
        if renderedText == frozenOutgoingText, let frozen = frozenFrame {
            // Defense in depth (as r13): restore the committed outgoing ink/frame if any other path replaced it.
            if let ink = frozenInkLayout,
               textLayer.inkLayout?.size != ink.size || textLayer.inkLayout?.inkRect != ink.inkRect {
                textLayer.inkLayout = ink
                textLayer.setNeedsDisplay()
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            textLayer.frame = frozen
            applyTrackedSubtitleTilt()
            CATransaction.commit()
            return
        }

        let font = resolvedFont()
        let targetW = wrappingWidth(font:font)
        let alignment: CATextLayerAlignmentMode
        let anchorX: CGFloat
        if userPosRatio.x < 0.1 {
            anchorX = horizontalMargin(font:font,left:true)
            alignment = .left
        } else if userPosRatio.x > 0.9 {
            anchorX = bounds.width - targetW - horizontalMargin(font:font,left:false)
            alignment = .right
        } else {
            let avail = bounds.width - targetW - horizontalMargin(font:font,left:true) - horizontalMargin(font:font,left:false)
            anchorX = horizontalMargin(font:font,left:true) + max(0, avail) * userPosRatio.x
            alignment = .center
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.alignmentMode = alignment
        let styled = styledText(renderedText, font: font)
        let placed = placement(text: renderedText, font: font, width: targetW,
                               flush: flush(forRatioX: userPosRatio.x),
                               ratio: userPosRatio, useCache: true)
        naturalContentHeight = measureContentHeight(renderedText, font: font, maxWidth: targetW)
        textLayer.inkLayout = placed.layout
        textLayer.string = styled
        textLayer.truncationMode = .none
        textLayer.isWrapped = true
        textLayer.frame = CGRect(x: anchorX, y: placed.frameY,
                                 width: placed.layout.size.width, height: placed.layout.size.height)
        // setNeedsDisplay alone defers the bitmap to another display pass. Complete
        // rasterization AFTER the final bounds, before this transaction can commit.
        textLayer.setNeedsDisplay()
        textLayer.displayIfNeeded()
        applyTrackedSubtitleTilt()
        CATransaction.commit()
    }

    private func nominalVars() -> [Int: Double] {
        PhotonFont.buildSVVars(signal0T: AudioNormalizer.svAxisLow,
                               signal1T: appliedSize, signal2T: appliedRota)
    }

    private func nominalFont(like font: NSFont, vars: [Int: Double]) -> NSFont {
        guard textLayer.font != nil else { return font }
        let ct = PhotonFont.ct(vars: vars, size: font.pointSize)
        return (ct as AnyObject as? NSFont) ?? font
    }

    private func referenceWorldCenter(text: String, font: NSFont, width: CGFloat, flush: CGFloat,
                                      ratio: CGPoint, breaks: [NSRange], useCache: Bool) -> CGFloat {
        let vars = nominalVars()
        let key = ReferenceKey(text: text, width: width, flush: flush, userScale: userScale,
                               ratio: ratio, boundsHeight: bounds.height,
                               family: CTFontCopyFamilyName(font as CTFont) as String,
                               pointSize: font.pointSize, breaks: breaks, nonAudioVars: vars)
        if useCache, referenceKey == key { return referenceWorldCenterY }
        let refFont = nominalFont(like: font, vars: vars)
        // Nominal glyphs, CURRENT wrap topology: same rows as what is on screen.
        let ref = SubtitleTypography.layout(styledText(text, font: refFont), font: refFont,
                                            width: width, flush: flush, forcedBreaks: breaks)
        let y = SubtitleTypography.anchoredFrameY(ratioY: ratio.y, height: ref.size.height,
                                                  boundsHeight: bounds.height,
                                                  mTop: Config.mTop, mBottom: Config.mBottom)
        let world = y + ref.inkCenterY
        if useCache { referenceKey = key; referenceWorldCenterY = world }
        return world
    }

    private func placement(text: String, font: NSFont, width: CGFloat, flush: CGFloat,
                           ratio: CGPoint, useCache: Bool) -> (layout: SubtitleTypography.Layout, frameY: CGFloat) {
        let styled = styledText(text, font: font)
        let natural = SubtitleTypography.layout(styled, font: font, width: width, flush: flush)
        let y0 = SubtitleTypography.anchoredFrameY(ratioY: ratio.y, height: natural.size.height,
                                                   boundsHeight: bounds.height,
                                                   mTop: Config.mTop, mBottom: Config.mBottom)
        guard !text.isEmpty else { return (natural, y0) }
        let refWorld = referenceWorldCenter(text: text, font: font, width: width, flush: flush,
                                            ratio: ratio, breaks: natural.breaks, useCache: useCache)
        let dy = refWorld - (y0 + natural.inkCenterY)
        if abs(dy) < 0.01 { return (natural, y0) }
        let shifted = SubtitleTypography.layout(styled, font: font, width: width, flush: flush, dy: dy,
                                                forcedBreaks: natural.breaks)
        let y1 = SubtitleTypography.pinnedFrameY(refWorldCenterY: refWorld, layout: shifted,
                                                 boundsHeight: bounds.height,
                                                 mTop: Config.mTop, mBottom: Config.mBottom)
        return (shifted, y1)
    }

    private func flush(forRatioX x: CGFloat) -> CGFloat { x < 0.1 ? 0 : (x > 0.9 ? 1 : 0.5) }

    // MARK: - Measurement
    private func resolvedFont() -> NSFont {
        let sz = textLayer.fontSize > 0 ? textLayer.fontSize : PhotonFont.size
        // I26: CTFont as AnyObject as? NSFont - the toll-free bridge
        // preserves variation axes, so measurement stays correct on width
        // axis fonts. Never unsafeBitCast.
        if let ctf = textLayer.font {
            let nsf = ctf as AnyObject as? NSFont
            if let f = nsf { return f }
        }
        // Fallback: measure without variation, at the right pointSize
        let name = (textLayer.font as? String) ?? PhotonFont.fontName
        return NSFont(name: name, size: sz)
            ?? NSFont.monospacedSystemFont(ofSize: sz, weight: .regular)
    }

    private func measureContentHeight(_ text: String, font: NSFont, maxWidth: CGFloat) -> CGFloat {
        guard !text.isEmpty, maxWidth > 0 else { return font.pointSize * 1.4 }
        return SubtitleTypography.layout(styledText(text, font: font), font: font,
                                         width: maxWidth, flush: textFlush).size.height
    }

    private var textFlush: CGFloat {
        switch textLayer.alignmentMode {
        case .right: return 1
        case .center: return 0.5
        default: return 0
        }
    }

    private func pipSubtitleArea(font:NSFont)->CGRect {
        let peers=superview?.subviews ?? []
        let left=peers.first(where:{$0 is SpineUI}).map{convert($0.bounds,from:$0)}
        let right=peers.first(where:{$0 is SidebarUI}).map{convert($0.bounds,from:$0)}
        return SubtitleWrapping.usableArea(windowWidth:Double(bounds.width),fontSize:Double(font.pointSize),left:left,right:right,gap:Double(Config.pipBlockGap))
    }
    private func wrappingWidth(font:NSFont)->CGFloat {
        if pictureInPictureTypography {return pipSubtitleArea(font:font).width}
        return CGFloat(SubtitleWrapping.width(windowWidth:Double(bounds.width),fontSize:Double(font.pointSize),
            pictureInPicture:pictureInPictureTypography,normalWidth:Double(bounds.width/Config.baseWDivisor*userScale)))
    }
    private func horizontalMargin(font:NSFont,left:Bool)->CGFloat {
        pictureInPictureTypography ? (left ? pipSubtitleArea(font:font).minX:bounds.width-pipSubtitleArea(font:font).maxX) : (left ? Config.mLeft:Config.mRight)
    }
    private func styledText(_ text: String, font: NSFont) -> NSAttributedString {
        let alignment: NSTextAlignment
        switch textLayer.alignmentMode {
        case .right: alignment = .right
        case .center: alignment = .center
        default: alignment = .left
        }
        return SubtitleTypography.attributed(SubtitleWrapping.text(text,pictureInPicture:pictureInPictureTypography), font: font, tracking: PhotonFont.trackingPx,
                                             alignment: alignment, color: adaptiveTextColor)
    }

    private func setRenderedText(_ text: String) {
        renderedText = text
        // ANY commit of rendered text ends the outgoing-cue freeze - including
        // re-committing the SAME text after a cancelled transition: the frozen
        // snapshot may be stale (bounds/pan/zoom changed since it was taken),
        // so the recommitted cue's geometry must be computed fresh below.
        unfreezeOutgoingGeometry()
        refreshTextLayerString()
    }

    private func refreshTextLayerString() {
        // Do not leave a cue's ink in a previous cue's frame until the next
        // NSView layout pass. The same atomic path handles font-driven reflows.
        commitTextLayer()
    }

    // Normal retargets keep the existing smoothstep from the painted color.
    // A clear-cut decision must settle even an already-running identical target.
    func applyAdaptiveColor(_ color: NSColor,
                            mode: ScreenCaptureEngine.SubtitleColorTransition = .normal) {
        guard adaptiveTargetColor != color || (mode == .clearCut && adaptiveColorTimer != nil) else { return }
        adaptiveTargetColor = color
        adaptiveColorGeneration &+= 1
        let generation = adaptiveColorGeneration
        adaptiveColorTimer?.invalidate()
        adaptiveColorTimer = nil
        if mode == .clearCut {
            paintAdaptiveColor(color)
            return
        }
        guard let from = adaptiveTextColor.usingColorSpace(.deviceRGB),
              let to = color.usingColorSpace(.deviceRGB) else {
            paintAdaptiveColor(color)
            return
        }
        let started = CACurrentMediaTime()
        let duration: TimeInterval = 0.55
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            // A queued old callback must neither paint nor clear a newer timer.
            guard self.adaptiveColorGeneration == generation else { timer.invalidate(); return }
            let t = min(1.0, max(0.0, (CACurrentMediaTime() - started) / duration))
            // Smooth velocity at both ends; samples still arrive every 100ms.
            let p = CGFloat(t * t * (3.0 - 2.0 * t))
            let next = NSColor(deviceRed: from.redComponent + (to.redComponent - from.redComponent) * p,
                               green: from.greenComponent + (to.greenComponent - from.greenComponent) * p,
                               blue: from.blueComponent + (to.blueComponent - from.blueComponent) * p,
                               alpha: from.alphaComponent + (to.alphaComponent - from.alphaComponent) * p)
            self.paintAdaptiveColor(t >= 1 ? color : next)
            if t >= 1 {
                timer.invalidate()
                self.adaptiveColorTimer = nil
            }
        }
        adaptiveColorTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        timer.fire()
    }

    private func paintAdaptiveColor(_ color: NSColor) {
        adaptiveTextColor = color
        textLayer.removeAnimation(forKey: "foregroundColor")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textLayer.foregroundColor = color.cgColor
        textLayer.inkColor = color.cgColor
        // Color ticks repaint existing CTLines, never reshape or resize text.
        textLayer.setNeedsDisplay()
        CATransaction.commit()
    }

    // MARK: - Adaptive color

    /// Returns the subtitle text layer's screen-space rect, used by
    /// ScreenCaptureEngine to sample the background colour underneath.
    private var depthEventEpoch: UInt64 = 0
    private var depthEventCueStart: Double?
    var depthEvent: String? { textLayer.opacity > 0.1 && !currentText.isEmpty ? "\(depthEventEpoch):\(currentText)" : nil }
    var currentTextFrame: CGRect? {
        guard textLayer.opacity > 0.1, !currentText.isEmpty else { return nil }
        guard let win = window else { return nil }
        let winRect = convert(textLayer.frame, to: win.contentView)
        return win.convertToScreen(winRect)
    }

    // MARK: - Public API

    /// Display or hide the subtitle text. Line-count changes cross-fade
    /// without flicker: if the measured content height differs by more
    /// than 2 pt while visible, fade out quickly, swap, fade in.
    ///
    func show(text: String, duration: Double = 2.0, at time: Double,
              cueStart: Double? = nil, cueEnd: Double? = nil) {
        if text != currentText || textLayer.opacity <= 0.1 || (cueStart != nil && cueStart != depthEventCueStart) { depthEventEpoch &+= 1 }; depthEventCueStart=cueStart
        if text == currentText, textLayer.opacity > 0 {
            // Same text still visible: a back-to-back cue with identical text must still take
            // over the hide window, or the old cue end would hide it early.
            if let cueEnd, cueEnd > time {
                activeCueStart = cueStart ?? time
                activeCueEnd = cueEnd
            }
            return
        }
        let inDur  = fadeInDuration(for: duration)
        let outDur = fadeOutDuration(for: duration)

        if text.isEmpty {
            activeCueStart = nil; activeCueEnd = nil
            // The cue is ending: a pending transition freeze has no swap left.
            unfreezeOutgoingGeometry()
            guard !currentText.isEmpty else { return }
            currentText = ""
            lastChangeTime = time
            startFade(to: 0, duration: outDur)
            return
        }

        lastChangeTime = time

        let font = resolvedFont()
        let targetW = wrappingWidth(font:font)
        let newH    = measureContentHeight(text, font: font, maxWidth: targetW)
        let oldH    = naturalContentHeight
        let heightChanged = abs(oldH - newH) > 2 && textLayer.opacity > 0.15

        if heightChanged {
            freezeOutgoingGeometry()
            let crossFade = min(inDur * 0.4, 0.08)
            startFade(to: 0, duration: crossFade) { [weak self] in
                guard let self = self else { return }
                self.currentText = text
                self.setRenderedText(text)
                if Config.subPosRandom { self.randomizePosition() }
                self.needsLayout = true
                self.startFade(to: 1, duration: inDur)
            }
        } else {
            currentText = text
            setRenderedText(text)
            if Config.subPosRandom { randomizePosition() }
            needsLayout = true
            startFade(to: 1, duration: inDur)
        }

        if let cueEnd, cueEnd > time {
            // Cue-owned hide (playback time). Disarm any earlier wall-clock hide so a stale
            // timer or a stale pause-remaining cannot hide or re-arm this cue.
            activeCueStart = cueStart ?? time
            activeCueEnd = cueEnd
            autoHideToken += 1
            autoHideDuration = 0
            pausedAutoHideRemaining = nil
        } else {
            activeCueStart = nil; activeCueEnd = nil
            scheduleAutoHide(text: text, duration: duration, outDur: outDur)
        }
    }

    private func scheduleAutoHide(text: String, duration: Double, outDur: Double,
                                  floorToMinimum: Bool = true) {
        // Wall-clock fallback for non-cue callers (live captions, ad-hoc
        // show()). Cue-driven display is owned by checkExternalCue, which
        // hides at cue end against playback time - this timer must never
        // outlive a pause, so it is token-gated and re-armed on resume
        // with only its remaining time.
        let displayDuration = floorToMinimum ? max(duration, 1.0) : duration
        autoHideShownAt  = CACurrentMediaTime()
        autoHideDuration = displayDuration
        autoHideOutDur   = outDur
        autoHideToken   += 1
        let token = autoHideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + displayDuration) { [weak self] in
            guard let self = self,
                  self.autoHideToken == token,
                  !self.playbackPaused,
                  self.currentText == text else { return }
            self.unfreezeOutgoingGeometry()
            self.startFade(to: 0, duration: outDur)
            self.currentText = ""
        }
    }

    func clearAll() {
        currentText = ""
        unfreezeOutgoingGeometry()
        lastChangeTime = 0
        startFade(to: 0, duration: 0.2)
        SubtitleCueStore.shared.cues = []
    }

    func toggleRandomMode() {
        Config.subPosRandom.toggle()
        let status = Config.subPosRandom ? "ON" : "OFF"
        print("[SubtitleView] Random position mode: \(status)")
        showTemporaryMessage("Random Mode: \(status)")
    }

    func moveToDefaultPosition(_ position: Int) {
        userPosRatio = getDefaultPositionRatio(for: position)
        needsLayout = true
        print("[SubtitleView] Moved to position \(position): \(userPosRatio)")
    }

    // MARK: - Helpers

    // I12: bounds-local coords; lastRandomGridIndex prevents the same
    // cell twice in a row.
    private var lastRandomGridIndex: Int = -1

    private func randomizePosition() {
        let font = resolvedFont()
        let subW = wrappingWidth(font:font)
        let faceText = currentText.isEmpty ? "M" : currentText

        // 5x5 grid of ratio candidates, bounds-local to match layout()
        // (I12); jitter ±0.10 stays under half a step so cells don't overlap.
        let steps = 4
        struct Candidate { let index: Int; let ratio: CGPoint; let overlap: CGFloat }
        var candidates: [Candidate] = []

        let engine = ScreenCaptureEngine.shared
        let faces = engine.freshSubtitleFaces.compactMap { screenRect -> CGRect? in
            guard let win = window else { return nil }
            return convert(win.convertFromScreen(screenRect), from: nil)
        }
        let checkFaces = Config.faceAvoidance && !faces.isEmpty

        for row in 0...steps {
            for col in 0...steps {
                // Score the final jittered position, never move it after checking faces.
                let ratio = CGPoint(x: (CGFloat(col) / CGFloat(steps) + CGFloat.random(in: -0.10...0.10)).clamped(to: 0...1),
                                    y: (CGFloat(row) / CGFloat(steps) + CGFloat.random(in: -0.10...0.10)).clamped(to: 0...1))
                let overlap: CGFloat
                if checkFaces {
                    // subtitleFrame uses bounds — same coordinate space as layout().
                    let frame = subtitleFrame(for: ratio, subW: subW, text: faceText, font: font)
                    overlap = faces.reduce(CGFloat(0)) { $0 + $1.intersection(frame).area }
                } else {
                    overlap = 0
                }
                let index = row * (steps + 1) + col
                candidates.append(Candidate(index: index, ratio: ratio, overlap: overlap))
            }
        }

        let minOverlap = candidates.min(by: { $0.overlap < $1.overlap })!.overlap
        let tolerance: CGFloat = 1.0
        var best = candidates.filter { $0.overlap <= minOverlap + tolerance }

        if best.count > 1 {
            best = best.filter { $0.index != lastRandomGridIndex }
        }

        let chosen = best.randomElement()!
        lastRandomGridIndex = chosen.index

        userPosRatio = chosen.ratio
    }

    // Subtitle frame in bounds-local coordinates, matching layout().
    // Face rectangles are converted from screen space before overlap scoring.
    private func subtitleFrame(for ratio: CGPoint, subW: CGFloat, text: String, font: NSFont) -> CGRect {
        let anchorX: CGFloat
        if ratio.x < 0.1 {
            anchorX = horizontalMargin(font:font,left:true)
        } else if ratio.x > 0.9 {
            anchorX = bounds.width - subW - horizontalMargin(font:font,left:false)
        } else {
            let avail = bounds.width - subW - horizontalMargin(font:font,left:true) - horizontalMargin(font:font,left:false)
            anchorX = horizontalMargin(font:font,left:true) + max(0, avail) * ratio.x
        }
        // Same translated canvas as layout(), so candidate scoring matches what is drawn.
        let placed = placement(text: text, font: font, width: subW, flush: flush(forRatioX: ratio.x),
                               ratio: ratio, useCache: false)
        return CGRect(x: anchorX, y: placed.frameY, width: placed.layout.size.width,
                      height: placed.layout.size.height)
    }

    private func setDefaultPosition() {
        userPosRatio = getDefaultPositionRatio(for: Config.defaultStartPosition)
        hasInitialPos = true
    }

    private func getDefaultPositionRatio(for position: Int) -> CGPoint {
        switch position {
        case 1: return CGPoint(x: 0.0, y: 1.0)
        case 2: return CGPoint(x: 0.5, y: 1.0)
        case 3: return CGPoint(x: 1.0, y: 1.0)
        case 4: return CGPoint(x: 0.0, y: 0.5)
        case 5: return CGPoint(x: 0.5, y: 0.5)
        case 6: return CGPoint(x: 1.0, y: 0.5)
        case 7: return CGPoint(x: 0.0, y: 0.0)
        case 8: return CGPoint(x: 0.5, y: 0.0)
        case 9: return CGPoint(x: 1.0, y: 0.0)
        default: return CGPoint(x: 0.0, y: 1.0)
        }
    }

    private func showTemporaryMessage(_ message: String) {
        let savedText    = currentText
        let savedOpacity = textLayer.opacity
        startFade(to: 0, duration: 0.15) { [weak self] in
            guard let self = self else { return }
            self.currentText = message
            self.setRenderedText(message)
            self.needsLayout = true
            self.startFade(to: 1, duration: 0.15) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.startFade(to: 0, duration: 0.3) {
                        self.currentText = savedText
                        self.setRenderedText(savedText)
                        self.needsLayout = true
                        self.startFade(to: savedOpacity, duration: 0.15)
                    }
                }
            }
        }
    }
}

// ================================================================
//  SubtitleView - external SRT cue support
// ================================================================
extension SubtitleView {
    struct Cue { let start: Double; let end: Double; let text: String }

    func loadCues(_ cues: [(start: Double, end: Double, text: String)]) {
        SubtitleCueStore.shared.cues = cues.map { Cue(start: $0.start, end: $0.end, text: $0.text) }
            .sorted { $0.start < $1.start }
    }

    func checkExternalCue(at playbackTime: Double) {
        // mpv already shifts sub-text availability. Only the independent external
        // cue store needs a shifted lookup clock; never delay mpv's text twice.
        let time=SubtitleMenuTiming.lookupTime(playbackTime:playbackTime,delay:subtitleDelay,external:!SubtitleCueStore.shared.cues.isEmpty)
        // Pause auto-detection: while paused the caller keeps polling with
        // the same frozen playback time. Require two consecutive repeats
        // so a single quantized sample during playback is not misread.
        // (If the controller sets playbackPaused from mpv's pause event,
        // this converges to the same state.)
        if let last = lastCueProbeTime, abs(time - last) < 0.0005 {
            cueTimeRepeatCount += 1
            if cueTimeRepeatCount >= 2, !playbackPaused { playbackPaused = true }
        } else {
            cueTimeRepeatCount = 0
            lastCueProbeTime = time
            if playbackPaused { playbackPaused = false }
        }
        guard !SubtitleCueStore.shared.cues.isEmpty else {
            // Cue-owned hide for callers outside the cue store (mpv sub-start/sub-end): hide when
            // playback time leaves the cue window, including a backward seek. With a cue store the
            // lookup below owns hide and replace, so this check must not run first (it would hide
            // a same-text successor cue for one poll).
            if let end = activeCueEnd, !currentText.isEmpty,
               time > end || time < (activeCueStart ?? end) - 0.25 {
                show(text: "", duration: 0.3, at: time)
            }
            return
        }
        let cues = SubtitleCueStore.shared.cues
        var lo = 0, hi = cues.count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if cues[mid].start <= time { lo = mid + 1 } else { hi = mid }
        }
        // Overlapping cues: the latest-start cue may already be over while an earlier,
        // longer one is still on screen. Scan back (bounded) for the latest-start active cue.
        var active: Cue? = nil
        var back = 1
        while back <= min(lo, 16) {
            if time <= cues[lo - back].end { active = cues[lo - back]; break }
            back += 1
        }
        if let active {
            if active.text != currentText {
                let cueDuration = active.end - active.start
                show(text: active.text, duration: cueDuration, at: time,
                     cueStart: active.start, cueEnd: active.end)
            } else {
                // Same text, new window (back-to-back identical cues): keep the window current.
                activeCueStart = active.start
                activeCueEnd = active.end
            }
        } else if !currentText.isEmpty {
            show(text: "", duration: 0.3, at: time)
        }
    }
}

// ================================================================
//  SubtitleCueStore - shared external cue list
// ================================================================
final class SubtitleCueStore {
    static let shared = SubtitleCueStore()
    var cues: [SubtitleView.Cue] = []
}

// ================================================================
//  SubtitleView - OpenSubtitles / SubDL integration
// ================================================================
extension SubtitleView {

    func setFilePath(_ path: String) {
        guard path != currentFilePath else { return }
        currentFilePath = path
        subtitleLookupGeneration += 1
        subtitleLookupKey = nil
        lastSubtitleSearchStatus = nil
        loadedSrcSubtitle = nil
        isPGSCodec = false
        SubtitleCueStore.shared.cues = []
    }

    func setPGSCodec(_ isPGS: Bool, mediaTitle: String? = nil) {
        guard isPGS, !isPGSCodec, !currentFilePath.isEmpty else { return }
        isPGSCodec = true
        loadSubtitleFromOpenSubtitles(filePath: currentFilePath, language: "en",
                                       silent: true, mediaTitle: mediaTitle)
    }

    static func parseMediaTitle(mediaTitle: String?, filePath: String) -> (title: String, year: Int?) {
        let raw = mediaTitle?.isEmpty == false
            ? mediaTitle!
            : URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent
        let normalized = raw
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let yearPattern = #"(19|20)\d{2}"#
        var year: Int? = nil
        var titleEnd = normalized.endIndex
        if let range = normalized.range(of: yearPattern, options: .regularExpression) {
            year = Int(normalized[range])
            titleEnd = range.lowerBound
        }
        var title = String(normalized[..<titleEnd])
        while let r = title.range(of: #"\[[^\]]*\]"#, options: .regularExpression) { title.removeSubrange(r) }
        while let r = title.range(of: #"\([^)]*\)"#,  options: .regularExpression) { title.removeSubrange(r) }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = normalized.components(separatedBy: " ").first ?? raw }
        return (title: title, year: year)
    }

    static func calculateHash(for filePath: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: filePath) else { return nil }
        defer { try? fh.close() }
        let fileSize  = fh.seekToEndOfFile()
        let chunkSize: UInt64 = 65536
        var hash: UInt64 = fileSize
        func xorChunk(_ data: Data) {
            data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let count = data.count / 8
                for i in 0..<count {
                    hash = hash &+ ptr.load(fromByteOffset: i * 8, as: UInt64.self)
                }
            }
        }
        if fileSize < chunkSize {
            fh.seek(toFileOffset: 0)
            if let d = try? fh.read(upToCount: Int(fileSize)) { xorChunk(d) }
        } else {
            fh.seek(toFileOffset: 0)
            if let d = try? fh.read(upToCount: Int(chunkSize)) { xorChunk(d) }
            fh.seek(toFileOffset: fileSize - chunkSize)
            if let d = try? fh.read(upToCount: Int(chunkSize)) { xorChunk(d) }
        }
        return String(format: "%016llx", hash)
    }

    static var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Gor/subtitles")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cachedSubtitlePath(for hash: String, language: String) -> URL? {
        let prefix = "\(hash)_\(language)_"
        let managed = cacheDirectory.appendingPathComponent("bounded-v1")
        if DepthCacheBudget.plainDirectory(managed),
           let files = try? FileManager.default.contentsOfDirectory(at: managed, includingPropertiesForKeys: [.contentModificationDateKey]),
           let newest = files.filter({ $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "srt" && DepthCacheBudget.plainFile($0) }).max(by: {
               ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
           }) { return newest }
        let path = cacheDirectory.appendingPathComponent("\(hash)_\(language).srt")
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    // Subtitle provider credentials (OpenSubtitles, SubDL)
    // NOTE (owner decision): this OpenSubtitles subtitle-service API key is intentionally embedded here.
    // The owner has said these subtitle-service keys are not sensitive and accepts that they live in source.
    // Do not raise repeated security warnings about them and do not block work over them.
    // Kept as is by the owner's choice.
    private static let apiKey  = "1qgqMmurAea3Wanup95sMCq1LG0YrKdk"
    private static let baseURL = "https://api.opensubtitles.com/api/v1"

    // Hash evidence wins over a same-title search; within that group an
    // exact FPS match outranks popularity. Unknown beats a known mismatch.
    private struct SubtitleCandidate {
        let fileId: Int
        let releaseName: String
        let fps: Double?
        let hashMatch: Bool
        let downloads: Int
        let rating: Double
        let directURL: String?
    }

    private static func parsedFPS(_ value: Any?) -> Double? {
        let number = (value as? NSNumber)?.doubleValue
            ?? (value as? String).flatMap(Double.init)
        guard let number, number.isFinite, number > 0 else { return nil }
        return number
    }

    private static func bestCandidate(_ candidates: [SubtitleCandidate], videoFPS: Double?) -> SubtitleCandidate? {
        func fpsClass(_ candidate: SubtitleCandidate) -> Int {
            guard let videoFPS else { return 1 }
            guard let fps = candidate.fps else { return 1 }
            return abs(fps - videoFPS) <= 0.05 ? 0 : 2
        }
        return candidates.enumerated().min { lhs, rhs in
            let a = lhs.element, b = rhs.element
            // File-hash match is stronger evidence of the right release
            // than FPS alone; two unrelated releases can share a frame rate.
            if a.hashMatch != b.hashMatch { return a.hashMatch }
            let ac = fpsClass(a), bc = fpsClass(b)
            if ac != bc { return ac < bc }
            if ac == 1 && a.fps != nil && b.fps == nil { return true }
            if ac == 1 && a.fps == nil && b.fps != nil { return false }
            if ac == 2, let videoFPS, let afps = a.fps, let bfps = b.fps {
                let ad = abs(afps - videoFPS), bd = abs(bfps - videoFPS)
                if ad != bd { return ad < bd }
            }
            if a.downloads != b.downloads { return a.downloads > b.downloads }
            if a.rating != b.rating { return a.rating > b.rating }
            return lhs.offset < rhs.offset
        }?.element
    }

    private enum SubtitleSearchOutcome {
        case match(SubtitleCandidate)
        case searchedOKNoMatch
        case unreachable
    }

    private static func searchSubtitles(hash: String, language: String, videoFPS: Double?,
                                        query: String? = nil, year: Int? = nil,
                                        completion: @escaping (SubtitleSearchOutcome) -> Void) {
        var comps = URLComponents(string: "\(baseURL)/subtitles")!
        if let q = query {
            var items = [
                URLQueryItem(name: "query",     value: q),
                URLQueryItem(name: "languages", value: language),
                URLQueryItem(name: "order_by",  value: "download_count"),
            ]
            if let y = year { items.append(URLQueryItem(name: "year", value: String(y))) }
            comps.queryItems = items
        } else {
            comps.queryItems = [
                URLQueryItem(name: "moviehash",  value: hash),
                URLQueryItem(name: "languages",  value: language),
                URLQueryItem(name: "order_by",   value: "download_count"),
            ]
        }
        var req = URLRequest(url: comps.url!)
        req.setValue(apiKey,    forHTTPHeaderField: "Api-Key")
        req.setValue("Gor/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        BoundedSubtitleDownload.fetch(req, limit: 1024 * 1024) { data in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArr = json["data"] as? [[String: Any]] else { completion(.unreachable); return }
            let candidates: [SubtitleCandidate] = dataArr.compactMap { item in
                guard let attrs = item["attributes"] as? [String: Any],
                      let files = attrs["files"] as? [[String: Any]],
                      let fileId = files.first?["file_id"] as? Int else { return nil }
                return SubtitleCandidate(fileId: fileId, releaseName: attrs["release"] as? String ?? "",
                    fps: parsedFPS(attrs["fps"]), hashMatch: attrs["moviehash_match"] as? Bool ?? false,
                    downloads: attrs["download_count"] as? Int ?? 0,
                    rating: parsedFPS(attrs["ratings"]) ?? 0, directURL: nil)
            }
            if let candidate = bestCandidate(candidates, videoFPS: videoFPS) {
                completion(.match(candidate))
            } else {
                completion(.searchedOKNoMatch)
            }
        }
    }

    // NOTE (owner decision): this SubDL subtitle-service API key is intentionally embedded here.
    // The owner has said these subtitle-service keys are not sensitive and accepts that they live in source.
    // Do not raise repeated security warnings about them and do not block work over them.
    // Kept as is by the owner's choice.
    private static let subdlApiKey = "subdl_rTH3N4Tl1ZbSVLaA4n4ewCnHVHN1q1I2Px9R5d-32z4"
    private static func subdlLanguageCode(_ iso: String) -> String {
        let map = ["en":"EN","tr":"TR","de":"DE","fr":"FR","es":"ES","it":"IT","pt":"PT",
                   "ru":"RU","ja":"JA","ko":"KO","zh":"ZH","ar":"AR","nl":"NL","pl":"PL",
                   "sv":"SV","da":"DA","fi":"FI","nb":"NO","cs":"CS","hu":"HU"]
        return map[iso] ?? iso.uppercased()
    }

    private static func searchSubtitlesSubDL(title: String, year: Int?, language: String,
                                              videoFPS: Double?,
                                              completion: @escaping (SubtitleSearchOutcome) -> Void) {
        var comps = URLComponents(string: "https://api.subdl.com/api/v1/subtitles")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "api_key",       value: subdlApiKey),
            URLQueryItem(name: "film_name",     value: title),
            URLQueryItem(name: "languages",     value: subdlLanguageCode(language)),
            URLQueryItem(name: "subs_per_page", value: "30"),
            URLQueryItem(name: "releases",      value: "1"),
            URLQueryItem(name: "unpack",        value: "1"),
            URLQueryItem(name: "type",          value: "movie"),
        ]
        if let y = year { items.append(URLQueryItem(name: "year", value: String(y))) }
        comps.queryItems = items
        guard let url = comps.url else { completion(.unreachable); return }
        var req = URLRequest(url: url)
        req.setValue("Gor/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        BoundedSubtitleDownload.fetch(req, limit: 1024 * 1024) { data in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let subsArr = json["subtitles"] as? [[String: Any]] else {
                completion(.unreachable); return
            }
            let entries: [SubtitleCandidate] = subsArr.enumerated().compactMap { index, item in
                // A ZIP is not an SRT. Only accept a raw, unpacked subtitle
                // file whose bytes the existing SRT parser can consume.
                let files = item["unpack_files"] as? [[String: Any]] ?? []
                guard let raw = files.first(where: { ($0["format"] as? String)?.lowercased() == "srt" }),
                      let rel = raw["url"] as? String,
                      rel.hasPrefix("/subtitle/") else { return nil }
                let candidate = SubtitleCandidate(fileId: index + 1,
                    releaseName: raw["release_name"] as? String ?? item["release_name"] as? String ?? "",
                    fps: parsedFPS(item["fps"]), hashMatch: false, downloads: 0, rating: 0,
                    directURL: "https://dl.subdl.com\(rel)")
                return candidate
            }
            if let candidate = bestCandidate(entries, videoFPS: videoFPS) {
                completion(.match(candidate))
            } else {
                completion(.searchedOKNoMatch)
            }
        }
    }

    static func downloadSubtitle(fileId: Int, completion: @escaping (Data?) -> Void) {
        var req = URLRequest(url: URL(string: "\(baseURL)/download")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,    forHTTPHeaderField: "Api-Key")
        req.setValue("Gor/1.0", forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["file_id": fileId])
        BoundedSubtitleDownload.fetch(req, limit: 1024 * 1024) { data in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let link = json["link"] as? String,
                  let url = URL(string: link) else { completion(nil); return }
            BoundedSubtitleDownload.fetch(URLRequest(url: url), completion: completion)
        }
    }

    func loadSubtitleFromOpenSubtitles(filePath: String, language: String,
                                       silent: Bool = false, mediaTitle: String? = nil,
                                       videoFPS: Double? = nil) {
        guard currentFilePath == filePath else { return }
        // Each explicit click supersedes previous results, even for the same movie.
        subtitleLookupGeneration += 1
        loadedSrcSubtitle = nil
        let generation = subtitleLookupGeneration
        let (title, year) = SubtitleView.parseMediaTitle(mediaTitle: mediaTitle, filePath: filePath)
        let queryHash = "query_\(StableCacheKey.sha1(title))"
        if !silent { publishSubtitleSearchStatus("searching subtitles…") }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let hash = SubtitleView.calculateHash(for: filePath)
            if silent, let hash,
               let cached = SubtitleView.cachedSubtitlePath(for: hash, language: language),
               let cues = SubtitleView.parseSRT(at: cached) {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isCurrentSubtitleLookup(generation, path: filePath) else { return }
                    self.loadCues(cues)
                }
                return
            }
            let key = hash ?? queryHash
            // Search OpenSubtitles by both hash and title when a file hash exists:
            // a title result can succeed when that exact upload has no hash match.
            // Group all candidates before ranking; network return order cannot win.
            let group = DispatchGroup()
            let lock = NSLock()
            var openOutcome: SubtitleView.SubtitleSearchOutcome?
            var openTitleOutcome: SubtitleView.SubtitleSearchOutcome?
            var subdlOutcome: SubtitleView.SubtitleSearchOutcome?
            group.enter()
            SubtitleView.searchSubtitles(hash: key, language: language, videoFPS: videoFPS,
                                         query: hash == nil ? title : nil, year: year) { outcome in
                lock.lock(); openOutcome = outcome; lock.unlock()
                group.leave()
            }
            if hash != nil {
                group.enter()
                SubtitleView.searchSubtitles(hash: key, language: language, videoFPS: videoFPS,
                                             query: title, year: year) { outcome in
                    lock.lock(); openTitleOutcome = outcome; lock.unlock()
                    group.leave()
                }
            }
            group.enter()
            SubtitleView.searchSubtitlesSubDL(title: title, year: year, language: language,
                                               videoFPS: videoFPS) { outcome in
                lock.lock(); subdlOutcome = outcome; lock.unlock()
                group.leave()
            }
            group.notify(queue: .main) { [weak self] in
                guard let self, self.isCurrentSubtitleLookup(generation, path: filePath) else { return }
                let openOutcomes = [openOutcome, openTitleOutcome].compactMap { $0 }
                let outcomes = openOutcomes + [subdlOutcome].compactMap { $0 }
                let candidates = outcomes.compactMap { outcome -> SubtitleCandidate? in
                    if case .match(let candidate) = outcome { return candidate }
                    return nil
                }
                guard let best = SubtitleView.bestCandidate(candidates, videoFPS: videoFPS) else {
                    // OpenSubtitles is one provider even when two queries ran.
                    // It is reachable if either query completed successfully.
                    let openUnreachable = openOutcomes.allSatisfy {
                        if case .unreachable = $0 { return true }
                        return false
                    }
                    let subdlUnreachable: Bool
                    if case .some(.unreachable) = subdlOutcome { subdlUnreachable = true }
                    else { subdlUnreachable = false }
                    let unreachableCount = (openUnreachable ? 1 : 0) + (subdlUnreachable ? 1 : 0)
                    let status: String
                    if unreachableCount == 2 {
                        status = "subtitle providers unavailable"
                    } else if unreachableCount == 1 {
                        status = "no subtitles found (one provider unreachable)"
                    } else {
                        status = "no subtitles found"
                    }
                    if !silent { self.publishSubtitleSearchStatus(status) }
                    return
                }
                self.subtitleLookupKey = "\(key)_\(language)"
                if !silent { self.publishSubtitleSearchStatus("loading best match…") }
                self.downloadAndLoad(fileId: best.fileId, hash: key, language: language,
                                     directURL: best.directURL, releaseName: best.releaseName,
                                     generation: generation, path: filePath)
            }
        }
    }

    private func downloadAndLoad(fileId: Int, hash: String, language: String,
                                 directURL: String?, releaseName: String,
                                 generation: Int, path: String) {
        guard isCurrentSubtitleLookup(generation, path: path),
              subtitleLookupKey == "\(hash)_\(language)" else { return }
        // Downloads stay in bounded memory, never a URLSession disk staging file.
        // A stale search cannot publish bytes or replace the current subtitle.
        let completed: (Data?) -> Void = { [weak self] bytes in
            let cues = bytes.flatMap { SubtitleView.parseSRT(data: $0) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrentSubtitleLookup(generation, path: path),
                      self.subtitleLookupKey == "\(hash)_\(language)" else { return }
                guard let bytes, let cues, !cues.isEmpty else {
                    self.publishSubtitleSearchStatus("subtitle download or format failed (32MiB safety limit)")
                    return
                }
                self.loadCues(cues)
                self.loadedSrcSubtitle = (moviePath: path, srtData: bytes)
                // Persistence is optional: full cache must never prevent loading
                // or source-adjacent export. Old/legacy files remain untouched.
                _ = BoundedDiskWriter.save(bytes, name: "\(hash)_\(language)_\(UUID().uuidString).srt",
                    under: SubtitleView.cacheDirectory, cap: 64 * 1024 * 1024, entries: 256)
                let label = releaseName.isEmpty ? "subtitle" : String(releaseName.prefix(56))
                self.publishSubtitleSearchStatus("loaded: \(label)")
            }
        }
        if let directURL {
            downloadSubDLDirect(from: directURL, completion: completed)
        } else {
            SubtitleView.downloadSubtitle(fileId: fileId, completion: completed)
        }
    }

    var canExportSrcSubtitle: Bool {
        guard let loaded = loadedSrcSubtitle, loaded.moviePath == currentFilePath,
              !loaded.srtData.isEmpty else { return false }
        return localMovieURL != nil
    }

    private var localMovieURL: URL? {
        let path = currentFilePath
        guard path.hasPrefix("/"), !path.contains("://") else { return nil }
        let movie = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: movie.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue ? movie : nil
    }

    /// Export only an SRT that src successfully downloaded and installed for
    /// this exact local movie. Never overwrite an existing sidecar.
    func exportSrcSubtitle() {
        guard let loaded = loadedSrcSubtitle, loaded.moviePath == currentFilePath,
              !loaded.srtData.isEmpty else {
            publishSubtitleSearchStatus("no src subtitle loaded to save")
            return
        }
        guard let movie = localMovieURL else {
            publishSubtitleSearchStatus("save requires a local movie file")
            return
        }
        let sidecar = movie.deletingPathExtension().appendingPathExtension("srt")
        // Exclusive creation prevents overwrite, even if a sidecar appeared
        // between showing sve and tapping it.
        let fd = sidecar.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, 0o644) }
        guard fd >= 0 else {
            publishSubtitleSearchStatus(FileManager.default.fileExists(atPath: sidecar.path)
                ? "SRT already exists; not replaced" : "could not create sidecar SRT")
            return
        }
        var wrote = 0
        let succeeded = loaded.srtData.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            while wrote < loaded.srtData.count {
                let n = Darwin.write(fd, base.advanced(by: wrote), loaded.srtData.count - wrote)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { return false }
                wrote += n
            }
            return true
        }
        let closed = Darwin.close(fd) == 0
        guard succeeded, closed else {
            try? FileManager.default.removeItem(at: sidecar)
            publishSubtitleSearchStatus("could not save sidecar SRT")
            return
        }
        publishSubtitleSearchStatus("saved: \(sidecar.lastPathComponent)")
    }

    private func downloadSubDLDirect(from urlString: String,
                                      completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: urlString) else { completion(nil); return }
        BoundedSubtitleDownload.fetch(URLRequest(url: url), completion: completion)
    }
}

// ================================================================
//  SubtitleView - SRT parser
// ================================================================
extension SubtitleView {
    static func parseSRT(at url: URL) -> [(start: Double, end: Double, text: String)]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return parseSRT(data: data)
    }

    static func parseSRT(data: Data) -> [(start: Double, end: Double, text: String)]? {
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var cues: [(start: Double, end: Double, text: String)] = []
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.components(separatedBy: "\n")
                             .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard lines.count >= 2 else { continue }
            var tsLine: String?
            var textStartIdx = 0
            for (i, line) in lines.enumerated() {
                if line.contains("-->") { tsLine = line; textStartIdx = i + 1; break }
            }
            guard let ts = tsLine else { continue }
            let tsParts = ts.components(separatedBy: "-->")
            guard tsParts.count == 2,
                  let start = parseTimestamp(tsParts[0].trimmingCharacters(in: .whitespaces)),
                  let end   = parseTimestamp(tsParts[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            guard start.isFinite, end.isFinite, end > start, textStartIdx < lines.count else { continue }
            let rawText = lines[textStartIdx...].joined(separator: "\n")
            let text = stripTags(rawText)
            guard !text.isEmpty else { continue }
            cues.append((start: start, end: end, text: text))
        }
        return cues.isEmpty ? nil : cues
    }

    static func parseSRT(path: String) -> [(start: Double, end: Double, text: String)]? {
        parseSRT(at: URL(fileURLWithPath: path))
    }

    private static func parseTimestamp(_ ts: String) -> Double? {
        let s = ts.replacingOccurrences(of: ",", with: ".")
        let parts = s.components(separatedBy: ":")
        guard parts.count == 3,
              let h  = Double(parts[0]),
              let m  = Double(parts[1]),
              let sm = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sm
    }

    private static let assTagPattern = try! NSRegularExpression(pattern: #"\{[^}]*\}"#)
    private static let htmlTagPattern = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    private static func stripTags(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        let withoutASS = assTagPattern.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        let htmlRange = NSRange(withoutASS.startIndex..., in: withoutASS)
        return htmlTagPattern.stringByReplacingMatches(in: withoutASS, range: htmlRange, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

private extension CGRect {
    var area: CGFloat { width * height }
}

/// Shared mono/stereo typography. Replica transforms translate; they do not scale ink.
enum SubtitlePresentation {
    /// Keep physical glyph size while the common film transform scales its layout.
    /// User scale remains untouched; the compositor cancels only its own fit scale.
    static func fitFontCompensation(scale:Double?)->Double {
        guard let scale,scale.isFinite,scale>0 else{return 1}
        return 1/scale
    }
    static func proximity(distance:Double) -> Double {
        min(1,max(0,1-distance/1000))
    }
    /// The PiP canvas drives only PiP typography. Explicit sub-scale is
    /// applied after this base, so every user adjustment remains proportional.
    static func pipFontSize(userScale:Double,windowHeight:Double=270)->Double {
        max(12,windowHeight*0.08)*max(1,userScale)
    }
    static func sizeAxis(pointerValue:Double,enabled:Bool,pictureInPicture:Bool)->Double {
        pictureInPicture ? 0 : (enabled ? pointerValue : 0)
    }
    static func fontSize(userScale:Double, proximity:Double,pictureInPicture:Bool=false,windowHeight:Double=270) -> Double {
        if pictureInPicture {return pipFontSize(userScale:userScale,windowHeight:windowHeight)}
        let p = min(1,max(0,proximity))
        return max(1,25*userScale + 12*(1-pow(p,2.2)*userScale))
    }
}

/// mpv shifts text availability but reports original cue timestamps.
/// Independent cue lists instead need one delayed lookup clock.
enum SubtitleMenuTiming {
    static func lookupTime(playbackTime:Double,delay:Double,external:Bool)->Double {
        external ? playbackTime-delay : playbackTime
    }
    static func displayWindow(start:Double,end:Double,delay:Double)->(start:Double,end:Double) {
        (start+delay,end+delay)
    }
}

/// PiP has a small physical canvas, not the normal half-screen subtitle column.
/// Reflow authored soft rows through the real font; retain paragraph/dialogue breaks.
enum SubtitleWrapping {
    static func usableArea(windowWidth:Double,fontSize:Double,left:CGRect?,right:CGRect?,gap:Double)->CGRect {
        let start=max(gap,Double(left?.maxX ?? 0)+gap)
        let end=min(windowWidth-gap,Double(right?.minX ?? CGFloat(windowWidth))-gap)
        return CGRect(x:start,y:0,width:max(0,end-start),height:1)
    }
    static func inset(fontSize:Double)->Double {max(8,fontSize*0.75)}
    static func width(windowWidth:Double,fontSize:Double,pictureInPicture:Bool,normalWidth:Double)->Double {
        pictureInPicture ? max(1,windowWidth-2*inset(fontSize:fontSize)) : normalWidth
    }
    static func text(_ text:String,pictureInPicture:Bool)->String {
        guard pictureInPicture else{return text}
        let rows=text.replacingOccurrences(of:"\r\n",with:"\n").components(separatedBy:"\n")
        var result=""
        for (i,row) in rows.enumerated() {
            if i>0 {
                let previous=rows[i-1].trimmingCharacters(in:.whitespaces)
                let current=row.trimmingCharacters(in:.whitespaces)
                let dialogue=previous.hasPrefix("-") || current.hasPrefix("-") || previous.hasPrefix("–") || current.hasPrefix("–")
                result += previous.isEmpty || current.isEmpty || dialogue ? "\n":" "
            }
            result += row
        }
        return result
    }
}
