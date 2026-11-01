    /// - lines: cue.lines (explicit breaks; \h already materialized by the parser).
    /// - style: the cue's ASSOCIATED style fields, exactly as parsed (R2).
    /// - colorimetry: must be .sdrBT709 - anything extended-range is typed-refused.
    /// - layoutWidth: drawable pixel width the text must fit (PlayRes->drawable scaling
    ///   is renderer-side per R3; the caller passes the resolved width).
    /// - planRevision: the producer's current revision, echoed into the plane so the
    ///   commit gate's registered authority can refuse stale planes typed.
    public static func rasterize(lines: [String],
                                 style: RasterStyleInput,
                                 colorimetry: OverlayColorimetry,
                                 layoutWidth: Int,
                                 layoutHeight: Int,
                                 playResY: Int?,
                                 planRevision: UInt64,
                                 planContentID: String,
                                 planSessionID: String,
                                 coordinateSpace: OverlayCoordinateSpace = .drawablePixels)
                                 -> (outcome: RasterizeOutcome, layout: LayoutDecision?) {
        guard !colorimetry.requiresExtendedRange else {
            return .refused(.hdrOverlayOnSDRContract)
        }
        guard layoutWidth > 0, layoutHeight > 0, !lines.isEmpty else {
            return (.refused(.incompletePeerPlan), nil)
        }

        let text = lines.joined(separator: "\n") // R1: explicit line structure preserved
        let (scaledSize, usedDefaultRes) = SubtitleLayout.scaleFontSize(style.fontSize,
                                                                        playResY: playResY,
                                                                        drawableHeight: layoutHeight)
        let font = CTFontCreateWithName(style.fontName as CFString, scaledSize, nil) // R3 scaled
        // ASS alpha is INVERTED (0x00 opaque) - normalize before premultiplying.
        let a = CGFloat(255 - ((style.primaryColourARGB >> 24) & 0xFF)) / 255.0
        let r = CGFloat((style.primaryColourARGB >> 16) & 0xFF) / 255.0
        let g = CGFloat((style.primaryColourARGB >> 8) & 0xFF) / 255.0
        let b = CGFloat(style.primaryColourARGB & 0xFF) / 255.0
        let color = CGColor(srgbRed: r, green: g, blue: b, alpha: a)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let setter = CTFramesetterCreateWithAttributedString(attrString)
        let maxSize = CGSize(width: CGFloat(layoutWidth), height: .greatestFiniteMagnitude)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, maxSize, nil)
        let w = Int(ceil(fit.width)), h = Int(ceil(fit.height))
        guard w > 0, h > 0 else { return (.refused(.incompletePeerPlan), nil) }

        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue |
                         CGImageAlphaInfo.premultipliedLast.rawValue // memory order R,G,B,A premultiplied
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return (.refused(.incompletePeerPlan), nil)
        }
        // CoreText draws in a flipped (bottom-left) context; flip so row 0 is the top line.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: w, height: h), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), path, nil)
        CTFrameDraw(frame, ctx)

        // Declared-default placement (ASS alignment/margins NOT parsed, R2); the decision
        // travels with the plane so the receipt can state what was defaulted.
        var layout = SubtitleLayout.declaredDefaultRect(textW: Double(w), textH: Double(h),
                                                        drawableW: Double(layoutWidth),
                                                        drawableH: Double(layoutHeight),
                                                        space: coordinateSpace)
        layout = LayoutDecision(scaledFontSize: scaledSize,
                                usedDefaultPlayRes: usedDefaultRes,
                                destinationRect: layout.destinationRect,
