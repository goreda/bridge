// StereoLookNativeCommands.swift - v3 typed parser for vr180_look
// chrome commands on the NATIVE embedded host. Lane: stereo/photon.
// v3: vr180-look-set-ipd-mm is ACCEPTED as setIpdMM (strict finite) -
// the conversion owner now exists: the native input owner converts
// mm->NDC locally with full block182 distance-clamp custody (D1
// owner-local conversion, engineering judgment per main 7:46:08; Ops
// full-model boundary agreement 7:53:35). Lua route l.1070-1075.
// v2 applies Ops' actual-review corrections (main 6:19:13):
//  (3) vr180-look-calibration is PERMANENTLY refused: the shader
//      calibration feature is retired (ThreeD/Control.swift l.2259,
//      calibration_mark explicitly retired; the live calibration UI is
//      the AppKit crosshair ThreeDCornerTuneView, a separate thing).
//      No future bool path revives it.
//  (4) STRICT validation: a present-but-invalid or non-finite number
//      refuses the command; nil is only a documented missing/empty
//      optional slot (set-orientation); nudge slots follow Lua
//      l.1103-1108 only for missing/empty, never for garbage.
// Grounding: Ops native-feed custody 2c560c63 + 2cc5af52. Wire formats
// cited per case against vr180-look.lua. Pure value type, no state.

import Foundation

enum StereoLookNativeCommand: Equatable {
    /// vr180-look-set-enabled "true"|"false" (Lua register_route l.998;
    /// dispatched by VR180Controller l.478).
    case setEnabled(Bool)
    /// vr180-look-set-projection <kind> <aspect> (Lua l.895; wire has
    /// exactly kind+aspect, VR180Controller l.390).
    case setProjection(kind: String, aspect: Double)
    /// vr180-look-set-pack <pack> <gain> <conv> <zoom> <soft> (Lua
    /// l.886; dispatched VR180Controller l.324).
    case setPack(pack: Int, gain: Double, conv: Double, zoom: Double, soft: Double)
    /// vr180-look-set-orientation, 13 optional numeric slots + distance
    /// reason (Lua l.1036: nil slot = leave unchanged;
    /// resetOrientationJSON sends only the first 8).
    case setOrientation(yaw: Double?, pitch: Double?, fov: Double?, roll: Double?,
                        ipdNudge: Double?, headX: Double?, headY: Double?, headZ: Double?,
                        distanceMM: Double?, distanceReason: String?, mmPerPx: Double?,
                        fusionRoll: Double?, nativeRawRoll: Double?)
    /// vr180-look-viewing-cross: "1"/"true" = swap, else 0 (Lua l.1089;
    /// dispatched VR180Controller l.328).
    case viewingCross(Bool)
    /// vr180-look-tools-active: val == "true" (Lua l.962; dispatched by
    /// VR180Controller.refreshToolsActive via LookToolsRoute).
    case toolsActive(Bool)
    /// vr180-look-set-tune <name> <value> (Lua l.767). Only the two
    /// lanes the qualified native StereoLookTune carries are accepted;
    /// every other vr_tune key has no native input lane. NO current
    /// producer (grep-verified 6:15).
    case setTuneParallaxStrength(Double)
    case setTuneParallaxDisparity(Double)
    /// vr180-look-set-swap-eyes: "1"/"true" = 1.0 (Lua l.1096;
    /// dispatched VR180Controller l.512).
    case setSwapEyes(Bool)
    /// vr180-look-set-ipd-mm <mm>: the session-scale IPD offset dial in
    /// anatomical mm on the 63 mm default (block182 md.2; Lua route
    /// l.1070-1075). Dispatched by VR180Controller.publishBaseIPD
    /// (l.793-796) on entry and on every store change (l.329). The
    /// native input owner converts mm->NDC (Lua vr_apply_ipd_mm
    /// l.356-362) with the full combined clamp (l.376-405).
    case setIpdMM(Double)
    /// vr180-look-nudge <dyaw> <dpitch> <dfov> <droll> (Lua l.1103;
    /// dispatched VR180Controller l.466/469, always all four slots).
    case nudge(dyaw: Double, dpitch: Double, dfov: Double, droll: Double)
    /// vr180-look-full-fit / vr180-look-smooth-fit (Lua l.1146/1150):
    /// input semantic = accumulated manual offsets return to zero; the
    /// 0.3s smooth animation is presentation, not input state.
    case fullFit
    case smoothFit
}

enum StereoLookNativeCommandRefusal: Error, Equatable, CustomStringConvertible {
    case missingMessage
    case badArity(String)
    case badNumber(String)
    case unknownProjectionKind(String)
    case noNativeTuneLane(String)
    /// Feature retired in source: permanent refusal with the citation.
    case retired(String)
    /// Known-or-unknown wire message with no native acceptance yet:
    /// backlog, loud refusal (host fails like any unsupported command).
    case unsupported(String)

    var description: String {
        switch self {
        case .missingMessage: return "missing message name"
        case .badArity(let m): return "bad arity for \(m)"
        case .badNumber(let m): return "bad number in \(m)"
        case .unknownProjectionKind(let k): return "unknown projection kind \(k)"
        case .noNativeTuneLane(let n): return "no native tune lane for \(n)"
        case .retired(let why): return "retired: \(why)"
        case .unsupported(let m): return "unsupported vr180_look message \(m)"
        }
    }
}

enum StereoLookNativeCommands {
    /// Known projection kinds (mirror's Lua set-projection map l.899).
    static let projectionKinds: Set<String> =
        ["flat-2d3d", "flat-sbs", "flat-tb", "vr180", "vr180-tb", "vr360-mono", "vr360-tb"]

    /// Parse the vr180_look message tail: parts[0] is the message name,
    /// the rest its arguments (strings on the wire, NSNumber tolerated).
    static func parse(_ parts: [Any]) -> Result<StereoLookNativeCommand, StereoLookNativeCommandRefusal> {
        func string(_ i: Int) -> String? {
            guard parts.indices.contains(i) else { return nil }
            if let s = parts[i] as? String { return s }
            if let n = parts[i] as? NSNumber { return n.stringValue }
            return nil
        }
        /// STRICT finite Double for a REQUIRED slot.
        func finite(_ i: Int, _ message: String) -> Result<Double, StereoLookNativeCommandRefusal> {
            guard let s = string(i), !s.isEmpty else { return .failure(.badArity(message)) }
            guard let v = Double(s), v.isFinite else { return .failure(.badNumber(message)) }
            return .success(v)
        }
        /// set-orientation optional slot: MISSING or EMPTY = nil (leave
        /// unchanged, Lua l.1036). PRESENT-but-invalid or non-finite is
        /// a poisoning attempt and refuses the whole command.
        func optionalNum(_ i: Int, _ message: String) -> Result<Double?, StereoLookNativeCommandRefusal> {
            guard let s = string(i), !s.isEmpty else { return .success(nil) }
            guard let v = Double(s), v.isFinite else { return .failure(.badNumber(message)) }
            return .success(v)
        }
        /// nudge slot (Lua l.1103-1108): missing/empty = 0.0;
        /// present-but-invalid or non-finite refuses (Ops correction 4:
        /// invalid -> 0.0 was wrong).
        func deltaNum(_ i: Int, _ message: String) -> Result<Double, StereoLookNativeCommandRefusal> {
            guard let s = string(i), !s.isEmpty else { return .success(0.0) }
            guard let v = Double(s), v.isFinite else { return .failure(.badNumber(message)) }
            return .success(v)
        }
        func bool01(_ i: Int) -> Bool {
            let s = string(i) ?? ""
            return s == "1" || s == "true"
        }
        guard let name = string(0), !name.isEmpty else { return .failure(.missingMessage) }
        switch name {
        case "vr180-look-set-enabled":
            guard let s = string(1) else { return .failure(.badArity(name)) }
            guard s == "true" || s == "false" else { return .failure(.badNumber(name)) }
            return .success(.setEnabled(s == "true"))
        case "vr180-look-set-projection":
            guard let kind = string(1) else { return .failure(.badArity(name)) }
            guard projectionKinds.contains(kind) else { return .failure(.unknownProjectionKind(kind)) }
            switch finite(2, name) {
            case .failure(let r): return .failure(r)
            case .success(let aspect):
                guard aspect > 0 else { return .failure(.badNumber(name)) }
                return .success(.setProjection(kind: kind, aspect: aspect))
            }
        case "vr180-look-set-pack":
            guard let packS = string(1), let pack = Int(packS), (0...3).contains(pack) else {
                return .failure(.badNumber(name))
            }
            var values = [Double]()
            for i in 2...5 {
                switch finite(i, name) {
                case .failure(let r): return .failure(r)
                case .success(let v): values.append(v)
                }
            }
            return .success(.setPack(pack: pack, gain: values[0], conv: values[1], zoom: values[2], soft: values[3]))
        case "vr180-look-set-orientation":
            var slots = [Double?]()
            for i in [1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13] {
                switch optionalNum(i, name) {
                case .failure(let r): return .failure(r)
                case .success(let v): slots.append(v)
                }
            }
            return .success(.setOrientation(
                yaw: slots[0], pitch: slots[1], fov: slots[2], roll: slots[3],
                ipdNudge: slots[4], headX: slots[5], headY: slots[6], headZ: slots[7],
                distanceMM: slots[8], distanceReason: string(10), mmPerPx: slots[9],
                fusionRoll: slots[10], nativeRawRoll: slots[11]))
        case "vr180-look-viewing-cross":
            return .success(.viewingCross(bool01(1)))
        case "vr180-look-tools-active":
            return .success(.toolsActive(string(1) == "true"))
        case "vr180-look-calibration":
            // Ops correction 3: PERMANENT refusal. The shader
            // calibration mark is retired (ThreeD/Control.swift l.2259);
            // the live calibration UI is the AppKit crosshair
            // (ThreeDCornerTuneView), a separate surface that is never
            // bool-mapped onto this lane.
            return .failure(.retired("vr180-look-calibration: shader calibration retired at ThreeD/Control.swift l.2259"))
        case "vr180-look-set-tune":
            guard let tuneName = string(1) else { return .failure(.badArity(name)) }
            switch finite(2, name) {
            case .failure(let r): return .failure(r)
            case .success(let v):
                switch tuneName {
                case "vr_parallax_strength": return .success(.setTuneParallaxStrength(v))
                case "vr_parallax_disparity": return .success(.setTuneParallaxDisparity(v))
                default: return .failure(.noNativeTuneLane(tuneName))
                }
            }
        case "vr180-look-set-swap-eyes":
            return .success(.setSwapEyes(bool01(1)))
        case "vr180-look-set-ipd-mm":
            // v3: accepted, STRICT finite (Lua l.1071-1073 silently
            // tonumber-drops invalid; Ops correction 4 keeps invalid a
            // loud refusal). The owner re-validates on accept.
            switch finite(1, name) {
            case .failure(let r): return .failure(r)
            case .success(let mm): return .success(.setIpdMM(mm))
            }
        case "vr180-look-nudge":
            var deltas = [Double]()
            for i in 1...4 {
                switch deltaNum(i, name) {
                case .failure(let r): return .failure(r)
                case .success(let v): deltas.append(v)
                }
            }
            return .success(.nudge(dyaw: deltas[0], dpitch: deltas[1], dfov: deltas[2], droll: deltas[3]))
        case "vr180-look-full-fit":
            return .success(.fullFit)
        case "vr180-look-smooth-fit":
            return .success(.smoothFit)
        default:
            // plan-lock, set-output, surround-invert, set-lids,
            // set-blink-analog, menu-crop, bar-crop, source-eye-crop,
            // motion, set-ipd, store-revision, route-complete,
            // republish-film-frame, and anything unknown: backlog,
            // loud refusal (status quo on the native host today).
            return .failure(.unsupported(name))
        }
    }
}
