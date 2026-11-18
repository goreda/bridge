import AppKit

// Menu-driven mpv queries that used to sit in PPController (kept out so PPController stays at its line ceiling).
extension PPController {
    func queryMenuPayload(_ payload:String) -> [String:Any] {
        let lines=ipcClient.queryBatch(payload,timeout:0.3)
        let reply=IPCClient.parseFirst(lines)
        return reply
    }
    func surfaceDrawableReceipt() -> (Double,Double)? {
        // Accepted persistent-feed dimensions only. Never block the main thread on a socket read.
        surfaceDrawableSnapshot
    }
    /// Absolute sub-pos preset (subtitles > position, the shift+1..9 rows).
    /// Same set-then-read plumbing and OSD as adjustSubtitleProperty.
    @discardableResult
    func setSubtitlePositionPreset(_ pos:Int) -> Bool {
        let payload=MPVCommand.make(["set_property","sub-pos",pos])+"\n"+MPVCommand.make(["get_property","sub-pos"])
        let reply=queryMenuPayload(payload)
        guard let value=reply["data"] as? Double,value.isFinite else{
            spineUI.showMPVOSD("subtitle control unavailable",duration:1.5,force:true);return false
        }
        pendingSubtitleModePosition=nil;subtitleView.setSubtitlePosition(value,force:true)
        spineUI.showMPVOSD("subtitle position: "+String(format:"%.0f%%",value),duration:1.5,force:true)
        return true
    }
    /// Output devices mpv itself reports (audio-device-list), with the current
    /// pick. Same one-shot queryBatch pattern as nativeTrackSnapshot.
    func nativeAudioDeviceSnapshot() -> (current:String,devices:[(name:String,label:String)]) {
        let current=IPCClient.parseFirst(ipcClient.queryBatch(#"{"command":["get_property","audio-device"]}"#,timeout:0.15))["data"] as? String ?? "auto"
        let raw=IPCClient.parseFirst(ipcClient.queryBatch(#"{"command":["get_property","audio-device-list"]}"#,timeout:0.15))["data"] as? [[String:Any]] ?? []
        let devices=raw.compactMap { entry -> (name:String,label:String)? in
            guard let name=entry["name"] as? String else{return nil}
            return (name,entry["description"] as? String ?? name)
        }
        return (current,devices)
    }
}

/// Applied-crop invariant (owner): an applied crop may ONLY be changed by the reset menu, an explicit
/// Detect, a manual crop menu choice, or opening a new file. Every automatic path (dims change, aspect or
/// format cycle, pip / fullscreen / resize / screen move, rendition hop, auto re-detect, abandon) keeps it.
enum CropInvariant {
    static func mayChange(manual: Bool) -> Bool { manual }
    static func keptLine(_ cause: String) -> String { "[crop-guard] kept applied crop: \(cause)" }
    static func transitionLine(_ event: String, crop: CGRect?, display: (w: Double, h: Double)) -> String {
        let c = crop.map { String(format: "%.4f,%.4f %.4fx%.4f", $0.minX, $0.minY, $0.width, $0.height) } ?? "none"
        return "[crop-guard] \(event) crop=\(c) disp=\(Int(display.w))x\(Int(display.h))"
    }
    /// Rendition hop: a stored rect that falls outside the new source dims is kept as state but not applied
    /// (never silently dropped); only Detect, reset, a manual choice or a new file resolves it.
    static func fits(x: Int, y: Int, w: Int, h: Int, srcW: Int, srcH: Int) -> Bool {
        let ok = x >= 0 && y >= 0 && x + w <= srcW + 1 && y + h <= srcH + 1
        if !ok { print(keptLine("stored rect \(w)x\(h)+\(x)+\(y) outside new source \(srcW)x\(srcH), not applied; waiting for Detect")) }
        return ok
    }
}

extension PPController {
    /// Aspect of the crop that mpv is showing through `video-crop` (our applied crop). The player window,
    /// pip shaping and every window-size proposal must follow it: pip used to shape the window from the
    /// FULL frame (videoDisplayW/H stay uncropped while video-crop is active), so the cropped picture sat
    /// in a window of the wrong aspect and the crop looked broken the moment pip shrank the window.
    var appliedSourceCropAspect: Double? {
        guard cropRect != nil, sourceCropPropertyActive, let c = SBSGeometry.parseCrop(lastSourceCropValue), c.1 > 0 else { return nil }
        return c.0 / c.1
    }
    /// [pip-crop] line: our applied rect, mpv's own video-crop and dwidth/dheight read back, window frame.
    func logPipCrop(_ event: String, frame: NSRect) {
        let q = ipcClient.queryBatch(MPVCommand.make(["get_property", "video-crop"]) + "\n" + MPVCommand.make(["get_property", "dwidth"]) + "\n" + MPVCommand.make(["get_property", "dheight"]), timeout: 0.3)
        let r = q.compactMap { IPCClient.parseFirst([$0])["data"] }.map { "\($0)" }
        let applied = cropRect.map { String(format: "%.4f,%.4f %.4fx%.4f", $0.minX, $0.minY, $0.width, $0.height) } ?? "none"
        print("[pip-crop] \(event) applied=\(applied) video-crop=\(r.first ?? "?") dwidth/dheight=\(r.dropFirst().joined(separator: "x")) cropAspect=\(appliedSourceCropAspect.map { String(format: "%.4f", $0) } ?? "none") disp=\(Int(videoDisplayW))x\(Int(videoDisplayH)) window=\(frame)")
    }
}
