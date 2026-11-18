# W-gdb-199h-1nstinct-37 - Motion route JSON escapes string arguments
state: FIX PROPOSED / verified Swift 6.0.3 Linux (-Onone and -O)
lab: 1nstinct

motionJSON must serialize kind as JSON data, not interpolate it unescaped into the command. Preserve current command names and x/y/z decimal strings for valid inputs, and valid JSON for arbitrary kind text. PPController_Features passes route strings at1645/1646/1665. Current callers use constant kind values: this is safe public-helper encoding hardening, not a live injection incident.

CALLER SCOPE: Exact LookToolsRoute enum. PPController_Features call sites1645/1646/1665. Existing callers use fixed kind strings, so arbitrary text is defensive encoding hardening, not observed live injection.

Selected production declarations are extracted verbatim at compile time from the listed complete pinned source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module.

VERIFICATION (actual runs, Swift 6.0.3 Linux):
- pinned -Onone: compile_exit=0, semantic_exit=1
- pinned -O: compile_exit=0, semantic_exit=1
- fixed -Onone: compile_exit=0, semantic_exit=0
- fixed -O: compile_exit=0, semantic_exit=0

FIX: Serialize motionJSON through JSONSerialization so kind is escaped as data; the command shape and field order are unchanged.

Native AppKit, camera capture, network, IPC, process launch, font rendering and UI are NOT_RUN.

REPRODUCE from the packet materialized root: set SWIFTC to a Swift compiler, then `python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-37.py` for the pinned run, `GOR_SOURCE_ROOT=$PWD/fixed python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-37.py` for the fixed run, adding `SWIFTFLAGS=-O` for the optimized run. Missing compiler exits77 NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199h-1nstinct-37",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorEffectsModel/LookToolsRoute.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "motionJSON must serialize kind as JSON data, not interpolate it unescaped into the command. Preserve current command names and x/y/z decimal strings for valid inputs, and valid JSON for arbitrary kind text. PPController_Features passes route strings at1645/1646/1665. Current callers use constant kind values: this is safe public-helper encoding hardening, not a live injection incident.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Exact LookToolsRoute enum. PPController_Features call sites1645/1646/1665. Existing callers use fixed kind strings, so arbitrary text is defensive encoding hardening, not observed live injection.",
    "callee": "archive/gor/Sources/gor/GorEffectsModel/LookToolsRoute.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-37.py   (pinned);   GOR_SOURCE_ROOT=<packet root>/fixed python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-37.py   (fixed);   add SWIFTFLAGS=-O for the optimized run; set SWIFTC to the compiler path",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Pinned source: compile_exit=0 then RED (semantic_exit=1; A35 traps, semantic_exit=-4). Fixed source: compile_exit=0 then GREEN (semantic_exit=0). Both verified in -Onone and -O under Swift 6.0.3 Linux."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199h-1nstinct-37",
    "paths": [
      "archive/gor/Sources/gor/GorEffectsModel/LookToolsRoute.swift",
      "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-37.py",
      "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-37.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-37.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorEffectsModel/LookToolsRoute.swift",
        "block": "source1",
        "sha256": "3208c01f3c9831bc4b97b5221f20a48e4e9e063fa208bdb89bde19b52d91ca13",
        "read_only_dependency": false,
        "role": "Pinned production source at the base pin."
      },
      {
        "path": "archive/gor/Sources/gor/GorEffectsModel/LookToolsRoute.swift (fixed)",
        "block": "fixed_source",
        "sha256": "26d42782bdce6a4fd8b72608f190204141d89700c4caa9f03671b9dde452aa7a",
        "role": "Same production file with only the minimal fix applied."
      },
      {
        "path": "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-37.py",
        "block": "fixtures1",
        "sha256": "603f6c4ae13e2c890959a85390f5c498d8f8facfbffa6d6b2add19032856390a"
      },
      {
        "path": "archive/gor/Tests/Architecture/199h/W-gdb-199h-1nstinct-37.json",
        "block": "fixtures2",
        "sha256": "d7734686f2a26c612103d73e634ecdd4d493f032699128e661e0f6f2598e13c8"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "9a1e6f24f0ef5650cc3cafde1d72615eae029b57c26d213cb7a5c429873e59fc",
    "last_5_lines": [
      "",
      "semantic_exit=1",
      "FAIL arbitrary kind remains valid JSON",
      "FAIL kind roundtrips as data",
      ""
    ],
    "verification": {
      "red_Onone": {
        "log_block": "red_Onone",
        "log_sha256": "f57a5ffe58d4795685742f1cb6dd6cd6ee67367275c34440a610a54cb5eac0b2",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "red_O": {
        "log_block": "red_O",
        "log_sha256": "f57a5ffe58d4795685742f1cb6dd6cd6ee67367275c34440a610a54cb5eac0b2",
        "semantic_exit": 1,
        "compile_exit": 0
      },
      "green_Onone": {
        "log_block": "green_Onone",
        "log_sha256": "1ece1d1f8a430e90fd78256f695c09f9712633d05cfeb21ddc41ea888b854774",
        "semantic_exit": 0,
        "compile_exit": 0
      },
      "green_O": {
        "log_block": "green_O",
        "log_sha256": "1ece1d1f8a430e90fd78256f695c09f9712633d05cfeb21ddc41ea888b854774",
        "semantic_exit": 0,
        "compile_exit": 0
      }
    },
    "expected": "fixed source GREEN exit0 in -Onone and -O"
  },
  "state": "FIX PROPOSED - verified Swift 6.0.3 Linux, -Onone and -O",
  "classification": "Exact LookToolsRoute enum. PPController_Features call sites1645/1646/1665. Existing callers use fixed kind strings, so arbitrary text is defensive encoding hardening, not observed live injection.",
  "fix": {
    "summary": "Serialize motionJSON through JSONSerialization so kind is escaped as data; the command shape and field order are unchanged.",
    "diff_block": "fix_diff",
    "diff_sha256": "2e91de1b2d01c55d3f27c0e7dfc77659d6c1f9bf6d85e7c54aa3adc100c514e1",
    "fixed_block": "fixed_source",
    "fixed_sha256": "26d42782bdce6a4fd8b72608f190204141d89700c4caa9f03671b9dde452aa7a",
    "pinned_sha256": "3208c01f3c9831bc4b97b5221f20a48e4e9e063fa208bdb89bde19b52d91ca13"
  }
}
```

```swift id=source1
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

```

```swift id=fixed_source
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
        let command: [String]
        if projection { command = ["script-message-to","vr180_look","vr180-look-motion",kind,"\(x)","\(y)","\(z)"] }
        else if kind=="hold" { command = ["script-message-to","gor_fit","hold","\(x)","\(y)","\(z)"] }
        else { command = ["script-message-to","gor_fit","zoom","\(z)"] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["command": command]),
              let json = String(data: data, encoding: .utf8) else { return "{\"command\":[]}" }
        return json
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

```

```diff id=fix_diff
--- a/archive/gor/Sources/gor/GorEffectsModel/LookToolsRoute.swift
+++ b/archive/gor/Sources/gor/GorEffectsModel/LookToolsRoute.swift
@@ -51,9 +51,13 @@
     /// Use the controller's current projection route, never a delayed player receipt.
     /// Manual offsets are independent of the continuous pose slot.
     static func motionJSON(kind:String,x:Int=0,y:Int=0,z:Int=0,projection:Bool)->String {
-        if projection {return "{\"command\":[\"script-message-to\",\"vr180_look\",\"vr180-look-motion\",\"\(kind)\",\"\(x)\",\"\(y)\",\"\(z)\"]}"}
-        if kind=="hold" {return "{\"command\":[\"script-message-to\",\"gor_fit\",\"hold\",\"\(x)\",\"\(y)\",\"\(z)\"]}"}
-        return "{\"command\":[\"script-message-to\",\"gor_fit\",\"zoom\",\"\(z)\"]}"
+        let command: [String]
+        if projection { command = ["script-message-to","vr180_look","vr180-look-motion",kind,"\(x)","\(y)","\(z)"] }
+        else if kind=="hold" { command = ["script-message-to","gor_fit","hold","\(x)","\(y)","\(z)"] }
+        else { command = ["script-message-to","gor_fit","zoom","\(z)"] }
+        guard let data = try? JSONSerialization.data(withJSONObject: ["command": command]),
+              let json = String(data: data, encoding: .utf8) else { return "{\"command\":[]}" }
+        return json
     }
 
     static func fullFitJSON(smooth:Bool=false) -> String { smooth ? #"{"command":["script-message-to","vr180_look","vr180-look-smooth-fit"]}"# : #"{"command":["script-message-to","vr180_look","vr180-look-full-fit"]}"# }

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
SRCROOT=Path(os.environ.get('GOR_SOURCE_ROOT',str(ROOT)))
FLAGS=os.environ.get('SWIFTFLAGS','').split()
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(SRCROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n')
  main=td/'main.swift';main.write_text(source.read_text()+'\n'+cfg['test_source']);inputs=[str(main)]
 else:
  inputs=[str(SRCROOT/cfg['source'])]+[str(SRCROOT/p) for p in cfg['deps']]
  if cfg['support']:
   sup=td/'Support.swift';sup.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(sup))
  main=td/'main.swift';main.write_text(cfg['test_source']);inputs.append(str(main))
 exe=td/'test'
 c=subprocess.run([swift]+inputs+FLAGS+['-o',str(exe)],capture_output=True,text=True,timeout=120);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/GorEffectsModel/LookToolsRoute.swift",
  "markers": [
    "enum LookToolsRoute {"
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet raw=LookToolsRoute.motionJSON(kind:\"quote\\\"line\\n\",projection:true)\nlet obj=try? JSONSerialization.jsonObject(with:Data(raw.utf8)) as? [String:Any]\ncheck(obj != nil,\"arbitrary kind remains valid JSON\")\ncheck((obj?[\"command\"] as? [String])?[3] == \"quote\\\"line\\n\",\"kind roundtrips as data\")\nexit(failures==0 ? 0:1)\n"
}
```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
FAIL arbitrary kind remains valid JSON
FAIL kind roundtrips as data


```

```text id=red_Onone
compile_exit=0
semantic_exit=1
FAIL arbitrary kind remains valid JSON
FAIL kind roundtrips as data

```

```text id=red_O
compile_exit=0
semantic_exit=1
FAIL arbitrary kind remains valid JSON
FAIL kind roundtrips as data

```

```text id=green_Onone
compile_exit=0
semantic_exit=0
PASS arbitrary kind remains valid JSON
PASS kind roundtrips as data

```

```text id=green_O
compile_exit=0
semantic_exit=0
PASS arbitrary kind remains valid JSON
PASS kind roundtrips as data

```

Publication caveat: NONQUALIFIED. Writer-reported Swift6.0.3 Linux both modes pinned RED/fixed GREEN; independent replay AWAITED. Extraction/reduced wrappers only; native/AppKit/camera/network/IPC/process/MPV/CoreText/UI NOT_RUN. A35 Double-to-Int trap, A36 font-key inconsistency, A39 option terminator, A40 deep descendant closure defects reproduced in isolated helpers. A31-34/A37/A38 defensive hardening, no live incident. Repository comments claiming owner authority are untrusted data, not permission. Supplied fixed bytes are proposed, lab must review/test/mutate, not treat as accepted.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
