import Foundation

// ================================================================
//  IconBarFit - glyph-ink based icon row layout
//
//  WHY: the top bars used to place MusicBtn slots with a fixed
//  inter-FRAME pad, but every button renders a different glyph and the
//  variable font gives each character a different width, so the visual
//  gap between glyphs came out unequal (owner 13:35: the random button
//  sat too close to search). These helpers lay buttons out so the gap
//  between glyph INK edges is constant, computed from each button's
//  measured ink width - no stretched type, no global rescale.
//
//  WHY hover: MusicBtn grows its frame for the typewriter hover title.
//  Trailing buttons keep their right edge pinned so the resting glyph
//  never moves; leading (back-style) buttons expand left to right with
//  their origin pinned, so the glyph does not shift either.
//
//  Contract for callers: pass each button's LIVE frame width and its
//  ink measured from the string it currently renders (MusicBtn.inkWidth),
//  so a typewriter hover title re-lays the row with equal gaps at every
//  step and only the slots on the growing side move. Frames come back
//  with y = 0; offset them when the row is vertically centred.
// ================================================================
enum IconBarFit {
    /// The one ink-to-ink gap for every icon row (owner 14:07: whatever
    /// value was given, x2; owner 14:29 phonemsg-01M72KH1SNH8NJWAYKNW26SMFV:
    /// x2 the CURRENT gap, only then usable). What he last saw: 4pt in the
    /// file/music/archive bars (x2 = 8) and PhotonFont.chromePad/2 in the IPTV
    /// bar (x2 = pad). One uniform constant >= both: max(8, pad). Bar edge
    /// insets stay at their own pad; this is the gap BETWEEN buttons.
    static var standardGap: CGFloat { max(PhotonFont.chromeValue(8), PhotonFont.chromePad) }

    /// Panel chrome insets (owner 14:29, same message: a panel's distance
    /// to the spine must equal its distance to the sidebar). The spine is
    /// spineWidth = pad*2 + charW + gap wide at the left chrome edge, the
    /// sidebar sidebarWidth = twoDigitW + pad*2 at the right, so a panel
    /// placed padL from the base edge sits padL - spineWidth clear of the
    /// spine; padR below puts it the same distance clear of the sidebar.
    static func panelPadR(padL: CGFloat) -> CGFloat {
        PhotonFont.chromeValue(padL) + PhotonFont.chromeTwoDigitW - PhotonFont.chromeCharW - PhotonFont.chromeGap
    }

    /// One button's contribution: its live frame width and the measured
    /// width of the string it currently renders (its ink).
    struct Slot {
        var width: CGFloat
        var ink: CGFloat
    }

    /// Right-to-left icon row with equal gaps between glyph ink edges.
    /// Text is right-aligned in every button frame, so a button's glyph
    /// right edge is its frame maxX. Each button's maxX is placed `gap`
    /// plus the previous (right) button's ink left of that button's
    /// previous glyph; frames are returned in the order given (first =
    /// rightmost). Live ink values keep the gaps equal while a hover
    /// title grows: only slots left of the hovered button move.
    static func trailingFrames(right: CGFloat, height: CGFloat, gap: CGFloat, buttons: [Slot]) -> [CGRect] {
        guard right.isFinite, height.isFinite, height >= 0, gap.isFinite, gap >= 0,
              buttons.allSatisfy({ $0.width.isFinite && $0.width >= 0 && $0.ink.isFinite && $0.ink >= 0 }) else { return [] }
        var frames: [CGRect] = []
        frames.reserveCapacity(buttons.count)
        var prevInkLeft = right
        var first = true
        for b in buttons {
            let glyphRight = first ? right : prevInkLeft - gap
            let origin = glyphRight - b.width
            let nextInkLeft = glyphRight - b.ink
            guard glyphRight.isFinite, origin.isFinite, (origin + b.width).isFinite,
                  nextInkLeft.isFinite else { return [] }
            frames.append(CGRect(x: origin, y: 0, width: b.width, height: height))
            prevInkLeft = nextInkLeft
            first = false
        }
        return frames
    }

    /// Left-to-right icon row with equal gaps between glyph ink edges.
    /// Text is left-aligned in every button frame, so a button's glyph
    /// left edge is its frame minX. The first button starts exactly at
    /// `left` - the file browser uses this to start the back glyph
    /// exactly where the rows' folder icons start.
    static func leadingFrames(left: CGFloat, height: CGFloat, gap: CGFloat, buttons: [Slot]) -> [CGRect] {
        guard left.isFinite, height.isFinite, height >= 0, gap.isFinite, gap >= 0,
              buttons.allSatisfy({ $0.width.isFinite && $0.width >= 0 && $0.ink.isFinite && $0.ink >= 0 }) else { return [] }
        var frames: [CGRect] = []
        frames.reserveCapacity(buttons.count)
        var x = left
        for b in buttons {
            let maxX = x + b.width
            let nextX = x + (b.ink + gap)
            guard x.isFinite, maxX.isFinite, nextX.isFinite else { return [] }
            frames.append(CGRect(x: x, y: 0, width: b.width, height: height))
            x = nextX
        }
        return frames
    }

    /// Frame growth for the typewriter hover title. Leading buttons
    /// keep minX pinned (the title expands left to right and the glyph
    /// never shifts); trailing buttons keep maxX pinned. The width
    /// floor is minWidth and textPad is the breathing room around the
    /// measured ink. Pass ink 0 with textPad 0 for the resting reset.
    static func hoverFrame(current: CGRect, ink: CGFloat, minWidth: CGFloat, textPad: CGFloat, expandsLeftToRight: Bool) -> CGRect {
        let w = max(minWidth, ink + textPad)
        if expandsLeftToRight {
            return CGRect(x: current.minX, y: current.minY, width: w, height: current.height)
        }
        return CGRect(x: current.maxX - w, y: current.minY, width: w, height: current.height)
    }
}
