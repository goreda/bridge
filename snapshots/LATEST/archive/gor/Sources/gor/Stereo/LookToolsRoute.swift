import Foundation

// Backend routes for the vr180-look script that the controller used to spell out inline. Pure text and decisions, no player socket here:
// the caller hands the returned string to VR180Controller.sendRaw, the one existing line that owns the socket call, so a new look message
// never adds an edge to the player-connection baseline. Mirrors Tests/LookToolsRoute/look_tools_route_test.py (Linux model plus text pins).
// UNCOMPILED on a Mac.

/// Per-file source interpretation. Path key stays stable while a magnet file grows.
/// Compatibility reads while existing renderer code moves to typed state. No defaults writer remains here.
enum SourceFormatChoice {
    static func filmID(_ path:String)->FilmID {MainActor.assumeIsolated {ThreeDStore.shared.id(for:path) ?? ThreeDRecognitionBridge.filmID(path:path)}}
    static func get(_ path:String,_ d:UserDefaults = .standard)->String {
        MainActor.assumeIsolated { let store=ThreeDStore.shared;let film=store.snapshot.films[filmID(path).rawValue] ?? FilmThreeD();return raw(film.source.format == .auto && filmID(path)==store.snapshot.currentFilm ? store.snapshot.detectedSource:film.source) }
    }
    static func output(_ path:String,_ d:UserDefaults = .standard)->String {
        MainActor.assumeIsolated {ThreeDStore.shared.output(for:filmID(path)).rawValue}
    }
    static func off(_ path:String)->Bool {output(path)=="off"}
    static func lastOutput(_ path:String,_ d:UserDefaults = .standard)->String {
        MainActor.assumeIsolated {ThreeDStore.shared.snapshot.films[filmID(path).rawValue]?.lastOutput.rawValue ?? "full_sbs"}
    }
    static func raw(_ source:ThreeDSource)->String {
        let value:[ThreeDSource.Format:String]=[.auto:"auto",.flat2D:"flat",.sbsFull:"sbs",.sbsHalf:"half_sbs",.tbFull:"ou",.tbHalf:"half_ou",.vr180SBS:"vr180",.vr180TB:"vr180_tb",.vr360Mono:"vr360_mono",.vr360TB:"vr360_tb"]
        return (value[source.format] ?? "flat")+(source.swap ? ":swap":"")
    }
    static func source(_ value:String)->ThreeDSource {
        let base=value.split(separator:":").first.map(String.init) ?? value
        let values:[String:ThreeDSource.Format]=["auto":.auto,"flat":.flat2D,"sbs":.sbsFull,"half_sbs":.sbsHalf,"ou":.tbFull,"half_ou":.tbHalf,"vr180":.vr180SBS,"vr180_tb":.vr180TB,"vr360_mono":.vr360Mono,"vr360_tb":.vr360TB]
        return ThreeDSource(values[base] ?? .flat2D,swap:value.hasSuffix(":swap"))
    }
    static func kind(_ value:String)->String? {
        let s=source(value)
        if s.format == .auto {return nil}
        return s.format == .flat2D ? "mono":s.projection
    }
}

/// Messages for the look script's tools overlay and the orientation reset.
enum LookToolsRoute {
    /// The look script shows its tools overlay only while the head-tracking or blink log tools are in use with a film loaded. It must run with VR and 3D
    /// off: this message touches no aspect, no keepaspect and no stereo setting.
    static func toolsActive(headTracking: Bool, blinkLog: Bool, loadedVideo: Bool) -> Bool {
        (headTracking || blinkLog) && loadedVideo
    }

    /// {"command":["script-message-to","vr180_look","vr180-look-tools-active","true"|"false"]}
    static func toolsActiveJSON(_ active: Bool) -> String {
        "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-tools-active\",\"\(active ? "true" : "false")\"]}"
    }

    /// Use the controller's current projection route, never a delayed player receipt.
    /// Manual offsets are independent of the continuous pose slot.
    static func motionJSON(kind:String,x:Int=0,y:Int=0,z:Int=0,projection:Bool)->String {
        if projection {return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-motion\",\"\(kind)\",\"\(x)\",\"\(y)\",\"\(z)\"]}"}
        if kind=="hold" {return "{\"command\":[\"script-message-to\",\"gor_fit\",\"hold\",\"\(x)\",\"\(y)\",\"\(z)\"]}"}
        return "{\"command\":[\"script-message-to\",\"gor_fit\",\"zoom\",\"\(z)\"]}"
    }

    static func fullFitJSON(smooth:Bool=false) -> String { smooth ? #"{"command":["script-message-to","vr180_look","vr180-look-smooth-fit"]}"# : #"{"command":["script-message-to","vr180_look","vr180-look-full-fit"]}"# }
    /// Orientation args: yaw, pitch, fov, roll, ipd nudge, head x, y, z. Neutral pose at the default 135 degree field of view.
    static let neutralOrientationArgs = ["0", "0", "135", "0", "0", "0", "0", "0"]

    /// Sent when head tracking is switched off, so the picture returns to the neutral pose at once.
    static func resetOrientationJSON() -> String {
        let args = neutralOrientationArgs.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-set-orientation\",\(args)],\"request_id\":194}"
    }
}

/// The single 3D switch: which internal output the switch picks for the film that is open, from the native detection
/// (VRRecognition.choose kind: "vr180", "flat-sbs", "flat-tb", "flat-2d3d", "mono"/nil).
/// A native stereo file plays as it is, never through the 2D to 3D depth conversion; a plain 2D film is converted.
enum SingleSwitchRoute {
    enum Plan: Equatable {
        case nativeVR180       // 180 degree equirect pair: vr180 projection, no conversion
        case nativeSBS         // flat side by side (half or full): flat-sbs projection, no conversion
        case nativeTB          // flat top and bottom: flat-tb projection, no conversion
        case convert2D         // ordinary 2D film: flat-2d3d with the depth prepare
    }

    static func plan(detected kind: String?) -> Plan {
        switch kind {
        case "vr180": return .nativeVR180
        case "flat-sbs": return .nativeSBS
        case "flat-tb": return .nativeTB
        default: return .convert2D          // nil, "mono", "flat-2d3d" and anything unknown: the film is not known to be stereo
        }
    }

    /// The projection kind VR180Controller.selectProjection takes for this plan.
    static func projection(for plan: Plan) -> String {
        switch plan {
        case .nativeVR180: return "vr180"
        case .nativeSBS: return "flat-sbs"
        case .nativeTB: return "flat-tb"
        case .convert2D: return "flat-2d3d"
        }
    }

    /// true only when the film needs the depth prepare.
    static func convertsDepth(_ plan: Plan) -> Bool { plan == .convert2D }

    /// One line the OSD or the log can show for the choice.
    static func note(_ plan: Plan) -> String {
        switch plan {
        case .nativeVR180: return "3D: VR180 video, playing it as is"
        case .nativeSBS: return "3D: side by side video, playing it as is"
        case .nativeTB: return "3D: top and bottom video, playing it as is"
        case .convert2D: return "3D: 2D film, converting to 3D"
        }
    }
}

/// Controller entry points for the routes above. They live here, outside PPController_Features, and reach the player only through VR180Controller.sendRaw.
extension VR180Controller {
    func resetTestVRProperty() {sendRaw(#"{"command":["set_property","user-data/gor-test-vr-mode",0]}"#)}
    /// Tools overlay on or off for the current state. Call after head tracking, the blink log, or the loaded film changes. Works with VR and 3D off.
    func refreshToolsActive() {
        sendRaw(LookToolsRoute.toolsActiveJSON(LookToolsRoute.toolsActive(headTracking: headTrackingEnabled, blinkLog: blinkLogEnabled, loadedVideo: loadedVideoActive)))
    }

    /// Head tracking was switched off: neutral orientation at once.
    func releaseProjectionLock() {sendRaw(#"{"command":["script-message-to","vr180_look","vr180-look-plan-lock","off"]}"#)}
    func resetFilmView(smooth:Bool=false) { onSubtitleTilt?(0,0);onUITilt?(0);sendRaw(LookToolsRoute.fullFitJSON(smooth:smooth)) }
    func resetOrientation() { onSubtitleTilt?(0,0);onUITilt?(0);sendRaw(LookToolsRoute.resetOrientationJSON()) }

    /// Single 3D switch: what the open film is (native detection) and so which internal output to pick for it.
    func singleSwitchPlan() -> SingleSwitchRoute.Plan { SingleSwitchRoute.plan(detected: SourceFormatChoice.kind(SourceFormatChoice.get(recognitionPath)) ?? detectedStereoKind) }

    /// Legacy entry points route to the reducer. They never guess output or persist a projection.
    @discardableResult func applySingleSwitch() -> (plan: SingleSwitchRoute.Plan, final: Bool) {
        MainActor.assumeIsolated {ThreeDStore.shared.dispatch(.toggle3D)}
        return (singleSwitchPlan(),true)
    }

}
