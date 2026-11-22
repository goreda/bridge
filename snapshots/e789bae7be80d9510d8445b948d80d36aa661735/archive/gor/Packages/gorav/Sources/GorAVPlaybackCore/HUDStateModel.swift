import Foundation

// P29-HUD (DR-0020, lane c): photon-hud.lua v2.2.17's state/aggregation/display
// layer re-expressed as a pure Swift value-type model. Owner-pinned boundaries
// (gor structure writer, relayed 2026-11-17 00:48 +03): Foundation only; no
// mpv IPC, OSD, user-data reads, timers, menu publishing, or payload string
// decode (gor hands per-field raw wire strings in). The clock is gor's: fold
// animation steps once per explicit tick call. Warn-once is a data flag the
// model returns; real mp.msg.warn stays gor. The model is INERT until the gor
// lane's LuaJIT witness passes; photon-hud.lua stays authoritative.

/// hud_guard.num: domain-checked numeric field with hold-last-good state and
/// warn-once as a returned data flag. Empty/nil string means "no value yet"
/// and holds silently with the caller's fallback (never a corrupt warn).
public struct HUDFieldGuard: Equatable {
    public private(set) var lastGood: [String: Double] = [:]
    public private(set) var warnedFields: Set<String> = []
    /// Fields that gained a first-time corrupt value in the most recent
    /// sample application (warn-once as a data flag; emission stays gor).
    public internal(set) var lastRejected: [String] = []

    public init() {}

    public mutating func num(_ field: String, _ str: String?, _ lo: Double, _ hi: Double, fallback: Double?) -> Double? {
        lastRejected = []
        return numInner(field, str, lo, hi, fallback: fallback)
    }

    /// Batch-friendly variant that accumulates rejections across a sample.
    public mutating func numAccumulate(_ field: String, _ str: String?, _ lo: Double, _ hi: Double, fallback: Double?) -> Double? {
        let before = lastRejected.count
        let v = numInner(field, str, lo, hi, fallback: fallback)
        if lastRejected.count == before { /* no new rejection */ }
        return v
    }

    private mutating func numInner(_ field: String, _ str: String?, _ lo: Double, _ hi: Double, fallback: Double?) -> Double? {
        guard let str, !str.isEmpty else { return fallback }
        guard let v = Double(str), v == v, v != .infinity, v != -.infinity, v >= lo, v <= hi else {
            if !warnedFields.contains(field) {
                warnedFields.insert(field)
                lastRejected.append(field)
            }
            return lastGood[field] ?? fallback
        }
        lastGood[field] = v
        return v
    }
}

/// Raw per-section wire strings, as decoded by the gor side from the frozen
/// hud-state payloads. Missing keys decode as nil, exactly like an absent
/// payload field.
public struct HUDSubsystemSample: Equatable {
    public var fields: [String: String]
    public init(fields: [String: String]) { self.fields = fields }
    public subscript(_ key: String) -> String? { fields[key] }
}

/// The typed bright snapshot (boundary: the adaptive-brightness user-data
/// reads enter the model this way). A nil backlight/ambient level means the
/// engine has not published yet - that distinction is preserved, never
/// collapsed to a zero or an OFF decision.
public struct HUDBrightSnapshot: Equatable {
    public var active: Bool = false
    public var backlight: Double? = nil
    public var inertiaMode: String = "n/a"
    public var isCut: Bool = false
    public var ambientLevel: Double? = nil
    public var ambientWindowOpen: Bool = false
    public var ambientSource: String = "n/a"
    public var ambientLux: Double? = nil
    public var ambientFace: Double? = nil
    public var ambientRoom: Double? = nil
    public init() {}
}

/// One resolved draw: the exact gor-osd payload (newlines already escaped as
/// U+2016), plus per-section fold positions for observability.
public struct HUDRenderState: Equatable {
    public var osdPayload: String?
    public var foldPositions: [String: Int]
    public var sectionLines: [String: [String]]
}

public struct HUDStateModel: Equatable {
    static let indent = String(repeating: " ", count: 6)

    public private(set) var enabled = false
    public private(set) var guardState = HUDFieldGuard()
    public private(set) var bright = HUDBrightSnapshot()

    public struct Fold: Equatable {
        public var revealed: Double
        public var direction: Int
        public var timerRunning = false
        public var justFlipped = false
        public var lastEnabled: Bool? = nil
    }
    public private(set) var fold: [String: Fold] = [
        "photon": Fold(revealed: .infinity, direction: -1),
        "bright": Fold(revealed: .infinity, direction: -1),
        "sharp": Fold(revealed: .infinity, direction: -1),
        "grain": Fold(revealed: .infinity, direction: -1),
        "chrome": Fold(revealed: 0, direction: 1),
        "negativ": Fold(revealed: 0, direction: 1),
    ]

    public private(set) var photonState: [String: AnyValue]? = nil
    public private(set) var grainState: [String: AnyValue]? = nil
    public private(set) var chromeState: [String: AnyValue]? = nil
    public private(set) var negativState: [String: AnyValue]? = nil
    public private(set) var sharpState: [String: AnyValue] = ["enabled": .bool(false)]
    public private(set) var grainMeasureStatus: String? = nil
    public private(set) var grainMeasureAt: Double? = nil
    public private(set) var sizeEvidence: String? = nil
    /// Wall clock for the 12s measure-note expiry; gor drives it.
    public private(set) var now: Double = 0

    public init() {}

    /// Loose typed cell so section state mirrors the Lua tables field-for-field.
    public enum AnyValue: Equatable {
        case bool(Bool)
        case num(Double)
        case optNum(Double?)
        case str(String?)
    }

    // MARK: - ingress (gor decodes the wire payload, hands raw strings in)

    public mutating func setNow(_ t: Double) { now = t }

    public mutating func hudToggle() { enabled.toggle() }

    public mutating func fileLoaded() {
        grainMeasureStatus = nil
        grainMeasureAt = nil
    }

    public mutating func grainMeasure(_ value: String, at t: Double) {
        grainMeasureStatus = value
        grainMeasureAt = t
    }

    public mutating func setSizeEvidence(_ value: String?) { sizeEvidence = value }

    public mutating func applyBright(_ b: HUDBrightSnapshot) { bright = b }

    private mutating func num(_ f: String, _ s: String?, _ lo: Double, _ hi: Double, _ fb: Double?) -> Double? {
        guardState.numAccumulate(f, s, lo, hi, fallback: fb)
    }

    public mutating func applyPhoton(_ s: HUDSubsystemSample) {
        guardState.lastRejected = []
        photonState = [
            "enabled": .bool(s["enabled_str"] == "true"),
            "scene_smooth_peak": .num(num("photon.scene_smooth_peak", s["scene_smooth_peak_str"], 0, 1, 0)!),
            "scene_smooth_contrast": .num(num("photon.scene_smooth_contrast", s["scene_smooth_contrast_str"], 0, 1, 0)!),
            "scene_smooth_noise": .num(num("photon.scene_smooth_noise", s["scene_smooth_noise_str"], 0, 1, 0)!),
            "scene_motion": .num(num("photon.scene_motion", s["scene_motion_str"], 0, 1, 0)!),
            "scene_has_feed": .bool(s["scene_has_feed_str"] == "true"),
            "is_hdr": .bool(s["is_hdr_str"] == "true"),
            "is_live": .bool(s["is_live_str"] == "true"),
            "hdr_peak": .num(num("photon.hdr_peak", s["hdr_peak_str"], 0, 100000, 0)!),
            "hdr_vel": .num(num("photon.hdr_vel", s["hdr_vel_str"], -5000, 5000, 0)!),
            "hdr_avg": .num(num("photon.hdr_avg", s["hdr_avg_str"], 0, 1, 0)!),
            "hdr_drive": .num(num("photon.hdr_drive", s["hdr_drive_str"], 0, 1, 0)!),
            "hdr_contrast": .num(num("photon.hdr_contrast", s["hdr_contrast_str"], 0, 1, 0)!),
            "hdr_cut_thr": .num(num("photon.hdr_cut_thr", s["hdr_cut_thr_str"], 0, 1, 0)!),
            "hdr_pq": .num(num("photon.hdr_pq", s["hdr_pq_str"], 0, 1, 0)!),
            "hdr_dark_thresh": .num(num("photon.hdr_dark_thresh", s["hdr_dark_thresh_str"], 0, 1, 0)!),
            "hdr_bright_thresh": .num(num("photon.hdr_bright_thresh", s["hdr_bright_thresh_str"], 0, 1, 0)!),
            "sdr_pbs": .num(num("photon.sdr_pbs", s["sdr_pbs_str"], 0, 10000, 0)!),
            "sdr_vel": .num(num("photon.sdr_vel", s["sdr_vel_str"], -10000, 10000, 0)!),
            "sdr_gamma": .num(num("photon.sdr_gamma", s["sdr_gamma_str"], -7.5, 7.5, 0)!),
            "sdr_neutral": .num(num("photon.sdr_neutral", s["sdr_neutral_str"], 0, 10000, 0)!),
            "live_calib_ready": .bool(s["live_calib_ready_str"] == "true"),
            "live_calib_samples": .num(num("photon.live_calib_samples", s["live_calib_samples_str"], 0, 1000000, 0)!),
            "live_calib_frames": .num(num("photon.live_calib_frames", s["live_calib_frames_str"], 0, 1000000, 0)!),
            "radar_buffer_len": .num(num("photon.radar_buffer_len", s["radar_buffer_len_str"], 0, 10000000, 0)!),
            "radar_buffer_miss": .bool(s["radar_buffer_miss_str"] == "true"),
            "ring": .num(num("photon.ring", s["ring_str"], 0, 1000, 0)!),
            "rlevel": .num(num("photon.rlevel", s["rlevel_str"], 0, 1, 0)!),
        ]
    }

    public mutating func applyGrain(_ s: HUDSubsystemSample) {
        guardState.lastRejected = []
        grainState = [
            "enabled": .bool(s["enabled_str"] == "true"),
            "amount": .num(num("grain.amount", s["amount_str"], 0, 1000, 0)!),
            "fps": .num(num("grain.fps", s["fps_str"], 0, 1000, 0)!),
            "size_base": .num(num("grain.size_base", s["size_base_str"], 0, 100, 0)!),
            "hint_received": .bool(s["hint_received_str"] == "true"),
            "hint_suppressed": .bool(s["hint_suppressed_str"] == "true"),
            "hint_value": .optNum(num("grain.hint_value", s["hint_value_str"], 0, 100, nil)),
            "hue_has_data": .bool(s["hue_has_data_str"] == "true"),
            "hue": .num(num("grain.hue", s["hue_str"], 0, 360, 0)!),
            "source_h": .num(num("grain.source_h", s["source_h_str"], 0, 100000, 0)!),
            "output_h": .num(num("grain.output_h", s["output_h_str"], 0, 100000, 0)!),
            "coefficient": .num(num("grain.coefficient", s["coefficient_str"], 0, 2, 0)!),
            "strength_k": .optNum(num("grain.strength_k", s["strength_k_str"], 0, 2, nil)),
            "adaptive_mode": .bool(s["adaptive_mode_str"] == "true"),
            "strength_status": .str(s["strength_status_str"]),
            "render_density": .optNum(num("grain.render_density", s["render_density_str"], 0, 1, nil)),
            "strength_base": .num(num("grain.strength_base", s["strength_base_str"], 0, 1000, 0)!),
            "strength_src": .str(s["strength_src_str"]),
            "size_trim": .num(num("grain.size_trim", s["size_trim_str"], 0, 100, 1)!),
            "strength_hint_received": .bool(s["strength_hint_received_str"] == "true"),
            "strength_hint_suppressed": .bool(s["strength_hint_suppressed_str"] == "true"),
            "strength_hint_value": .optNum(num("grain.strength_hint_value", s["strength_hint_value_str"], 0, 1000, nil)),
        ]
    }

    public mutating func applyChrome(_ s: HUDSubsystemSample) {
        guardState.lastRejected = []
        chromeState = [
            "enabled": .bool(s["enabled_str"] == "true"),
            "filter_idx": .num(num("chrome.filter_idx", s["filter_idx_str"], 0, 100, 0)!),
            "filter_strength": .num(num("chrome.filter_strength", s["filter_strength_str"], 0, 100, 0)!),
            "contrast_amount": .num(num("chrome.contrast", s["contrast_str"], -100, 100, 0)!),
            "has_feed": .bool(s["has_feed_str"] == "true"),
            "hue_driven": .bool(s["hue_driven_str"] == "true"),
            "hue": .optNum(num("chrome.hue", s["hue_str"], 0, 360, nil)),
            "shadow_lift": .num(num("chrome.shadow_lift", s["shadow_lift_str"], -100, 100, 0)!),
            "highlight_rolloff": .num(num("chrome.highlight_rolloff", s["highlight_rolloff_str"], 0, 1000, 0)!),
            "mono_grain": .bool(s["mono_grain_str"] == "true"),
            "arc_clamped": .bool(s["arc_clamped_str"] == "true"),
        ]
    }

    public mutating func applyNegativ(_ s: HUDSubsystemSample) {
        guardState.lastRejected = []
        let mode = s["mode_str"]
        negativState = [
            "enabled": .bool(s["enabled_str"] == "true"),
            "stock_idx": .num(num("negativ.stock_idx", s["stock_idx_str"], 1, 100, 1)!),
            "mask_gain": .num(num("negativ.mask_gain", s["mask_gain_str"], 0, 1000, 0)!),
            "gamma": .num(num("negativ.gamma", s["gamma_str"], 0, 100, 0)!),
            "has_feed": .bool(s["has_feed_str"] == "true"),
            "hue_driven": .bool(s["hue_driven_str"] == "true"),
            "hue": .optNum(num("negativ.hue", s["hue_str"], 0, 360, nil)),
            "arc_clamped": .bool(s["arc_clamped_str"] == "true"),
            "mode": .str((mode?.isEmpty == false) ? mode : "mask"),
        ]
    }

    public mutating func applySharp(_ s: HUDSubsystemSample) {
        guardState.lastRejected = []
        sharpState = [
            "enabled": .bool(s["enabled_str"] == "true"),
            "shader_ready": .bool(s["shader_ready_str"] == "true"),
            "current_algo": .num(num("sharp.current_algo", s["current_algo_str"], 0, 100, 0)!),
            "user_strength": .num(num("sharp.user_strength", s["user_strength_str"], 0, 1000, 0)!),
            "smooth_coarse": .num(num("sharp.smooth_coarse", s["smooth_coarse_str"], 0, 1000, 0)!),
            "global_factor": .num(num("sharp.global_factor", s["global_factor_str"], 0, 100, 0)!),
            "halo_guard": .num(num("sharp.halo_guard", s["halo_guard_str"], 0, 100, 0)!),
            "texture_bias": .num(num("sharp.texture_bias", s["texture_bias_str"], 0, 100, 0)!),
            "fine_strength": .num(num("sharp.fine_strength", s["fine_strength_str"], 0, 1000, 0)!),
            "medium_strength": .num(num("sharp.medium_strength", s["medium_strength_str"], 0, 1000, 0)!),
            "coarse_strength": .num(num("sharp.coarse_strength", s["coarse_strength_str"], 0, 1000, 0)!),
            "content_adapt": .num(num("sharp.content_adapt", s["content_adapt_str"], 0, 100, 0)!),
            "temporal_mode": .num(num("sharp.temporal_mode", s["temporal_mode_str"], 0, 100, 0)!),
            "ring_damp": .num(num("sharp.ring_damp", s["ring_damp_str"], 0, 100, 0)!),
            "source_h": .num(num("sharp.source_h", s["source_h_str"], 0, 100000, 0)!),
            "output_h": .num(num("sharp.output_h", s["output_h_str"], 0, 100000, 0)!),
            "multiplier": .num(num("sharp.multiplier", s["multiplier_str"], 0.5, 1.0, 1.0)!),
            "adaptive_mode": .bool(s["adaptive_mode_str"] == "true"),
        ]
    }

    // MARK: - fold machine

    static func splitLines(_ body: String) -> [String] {
        if body.isEmpty { return [] }
        var rest = String(body.dropFirst()) + "\n"
        var out: [String] = []
        while let nl = rest.firstIndex(of: "\n") {
            out.append(String(rest[..<nl]))
            rest = String(rest[rest.index(after: nl)...])
        }
        return out
    }

    private mutating func applyFold(_ info: String, section: String, knownTotal: Int?) -> String {
        let nl = info.firstIndex(of: "\n")
        let title = nl.map { String(info[..<$0]) } ?? info
        let body = nl.map { String(info[$0...]) } ?? ""
        let prefix = section + "\t"
        guard var state = fold[section] else { return prefix + title + body }
        let lines = HUDStateModel.splitLines(body)
        let total = knownTotal ?? lines.count
        state.justFlipped = false
        if state.revealed == Double(total), state.direction > 0 {
            state.direction = -1
            state.justFlipped = true
        } else if state.revealed == 0, state.direction < 0 {
            state.direction = 1
            state.justFlipped = true
        }
        if state.revealed > Double(total) { state.revealed = Double(total) }
        if state.revealed < 0 { state.revealed = 0 }
        fold[section] = state
        let revealed = Int(state.revealed)
        if revealed <= 0 { return prefix + title }
        if revealed >= total {
            return prefix + title + "\n" + lines.prefix(total).map { prefix + $0 }.joined(separator: "\n")
        }
        return prefix + title + "\n" + lines.prefix(revealed).map { prefix + $0 }.joined(separator: "\n")
    }

    /// Click on a section title/line. Starts (or reverses) the fold animation;
    /// the 0.04s cadence is gor's clock, stepped via foldTick.
    public mutating func toggleFold(_ section: String) {
        guard var state = fold[section] else { return }
        if state.timerRunning {
            state.direction = -state.direction
            fold[section] = state
            return
        }
        startFoldAnimation(&state, fromWithinDraw: false)
        fold[section] = state
    }

    private mutating func startFoldAnimation(_ state: inout Fold, fromWithinDraw: Bool) {
        state.revealed += Double(state.direction)
        state.justFlipped = false
        if !fromWithinDraw {
            _ = drawHUD()
            if state.justFlipped { return }
        }
        state.timerRunning = true
    }

    /// One 0.04s animation tick for a section. The draw it produces is
    /// returned through renderState()/drawHUD by the caller as usual.
    public mutating func foldTick(_ section: String) {
        guard var state = fold[section], state.timerRunning else { return }
        if state.justFlipped {
            state.timerRunning = false
            fold[section] = state
            return
        }
        state.revealed += Double(state.direction)
        fold[section] = state
        _ = drawHUD()
        state = fold[section]!
        if state.justFlipped {
            state.timerRunning = false
            fold[section] = state
        }
    }

    private mutating func syncFold(_ section: String, _ isEnabled: Bool) {
        guard var state = fold[section] else { return }
        if state.lastEnabled == nil {
            state.lastEnabled = isEnabled
            fold[section] = state
            return
        }
        if state.lastEnabled == isEnabled { return }
        state.lastEnabled = isEnabled
        if state.timerRunning { fold[section] = state; return }
        let needsOpen = isEnabled && state.revealed == 0
        let needsClose = !isEnabled && state.revealed > 0
        guard needsOpen || needsClose else { fold[section] = state; return }
        state.direction = isEnabled ? 1 : -1
        fold[section] = state
        startFoldAnimation(&state, fromWithinDraw: true)
        fold[section] = state
    }

    // MARK: - value accessors

    private func b(_ state: [String: AnyValue]?, _ key: String, _ def: Bool = false) -> Bool {
        guard case .bool(let v)? = state?[key] else { return def }
        return v
    }
    private func n(_ state: [String: AnyValue]?, _ key: String, _ def: Double = 0) -> Double {
        guard case .num(let v)? = state?[key] else { return def }
        return v
    }
    private func on(_ state: [String: AnyValue]?, _ key: String) -> Double? {
        guard case .optNum(let v)? = state?[key] else { return nil }
        return v
    }
    private func s(_ state: [String: AnyValue]?, _ key: String) -> String? {
        guard case .str(let v)? = state?[key] else { return nil }
        return v
    }

    static func measureReason(_ why: String) -> String {
        func starts(_ p: String) -> Bool { why.hasPrefix(p) }
        if starts("shot-fail") || starts("shot-fields") || starts("data-not-string") || starts("short-row") {
            return "not measured: capture failed"
        }
        if starts("crop<96") { return "not measured: frame too small" }
        if starts("capture-no-luma") || starts("no-frame-height") { return "not measured: frame unreadable" }
        if starts("blocks<6") { return "not measured: too few blocks" }
        if starts("zero-hp") { return "not measured: frame too flat" }
        if starts("stale-mirror") { return "not measured: stale grain mirror" }
        if starts("soft<") { return "not measured: softness outside table" }
        if starts("no-eff") { return "not measured: effective size outside table" }
        if starts("over-corrected-source-power") || starts("garbage-curve") || starts("source-share-below-floor") {
            return "not measured: no valid size signal"
        }
        return "not measured: see log for reason"
    }

    // MARK: - draw

    /// The exact gor-osd payload for the current state, or nil when disabled.
    /// C printf semantics via String(format:) match Lua's string.format.
    @discardableResult
    public mutating func drawHUD() -> String? {
        renderState().osdPayload
    }

    public mutating func renderState() -> HUDRenderState {
        guard enabled else {
            return HUDRenderState(osdPayload: nil, foldPositions: foldPositions(), sectionLines: [:])
        }
        let I = HUDStateModel.indent
        let pst = photonState
        let photonStatus = pst.map { b($0, "enabled") ? "on" : "off" } ?? "?"
        let PHOTON_TOTAL = 4
        if let pst { syncFold("photon", b(pst, "enabled")) }
        var photonSkipFold = false
        var photonKnown: Int? = nil
        let photonInfo: String
        if pst == nil {
            photonInfo = "phot? photon\n" + I + "waiting for photon.lua…"
            photonSkipFold = true
        } else if fold["photon"]!.revealed <= 0 {
            photonInfo = String(format: "phot%@ %@", photonStatus, b(pst, "is_hdr") ? "hdr" : "sdr")
            photonKnown = PHOTON_TOTAL
        } else if b(pst, "is_hdr") {
            let pq = n(pst, "hdr_pq")
            let zone = pq < n(pst, "hdr_dark_thresh") ? "dark" : (pq > n(pst, "hdr_bright_thresh") ? "bright" : "mid")
            photonInfo = String(format:
                "phot%@ hdr%@\n" + I + "peak: %d nit   vel: %+.1f nit/s\n"
                + I + "avg-pq: %.4f   hybrid: %.4f\n"
                + I + "contrast ∂: %.4f   cut@: %.4f\n"
                + I + "scene: %@   ring: %.1f (lvl %.2f)",
                photonStatus, b(pst, "is_live") ? "  live" : "",
                Int(floor(n(pst, "hdr_peak"))), n(pst, "hdr_vel"),
                n(pst, "hdr_avg"), n(pst, "hdr_drive"), n(pst, "hdr_contrast"), n(pst, "hdr_cut_thr"),
                zone, n(pst, "ring"), n(pst, "rlevel"))
            photonKnown = PHOTON_TOTAL
        } else {
            let mode: String
            if b(pst, "is_live") {
                mode = String(format: "live  vf-metadata  calib: %@",
                              b(pst, "live_calib_ready")
                                ? String(format: "%.0f", n(pst, "sdr_neutral"))
                                : String(format: "%d/%d", Int(n(pst, "live_calib_samples")), Int(n(pst, "live_calib_frames"))))
            } else if n(pst, "radar_buffer_len") > 0 && !b(pst, "radar_buffer_miss") {
                mode = String(format: "radar  %d frames", Int(n(pst, "radar_buffer_len")))
            } else if b(pst, "radar_buffer_miss") {
                mode = "seek → probe"
            } else {
                mode = "probe (warming up)"
            }
            let pbs = n(pst, "sdr_pbs"), neutral = n(pst, "sdr_neutral")
            let zone = pbs < neutral * 0.6 ? "dark" : (pbs > neutral * 1.4 ? "bright" : "mid")
            photonInfo = String(format:
                "phot%@ sdr\n" + I + "%@\n"
                + I + "pbs: %.1f   vel: %+.1f/s\n"
                + I + "gamma: %.2f   neutral: %.0f\n"
                + I + "scene: %@   ring: %.1f (lvl %.2f)",
                photonStatus, mode, pbs, n(pst, "sdr_vel"), n(pst, "sdr_gamma"), neutral,
                zone, n(pst, "ring"), n(pst, "rlevel"))
            photonKnown = PHOTON_TOTAL
        }

        let ss = sharpState
        let shaderStatus = !b(ss, "enabled") ? "off" : (b(ss, "shader_ready") ? "on" : "off")
        syncFold("sharp", b(ss, "enabled"))
        let SHARP_TOTAL = 8
        var sharpKnown: Int? = nil
        let sharpInfo: String
        if fold["sharp"]!.revealed <= 0 {
            sharpInfo = String(format: "phot%@ sharp", shaderStatus)
            sharpKnown = SHARP_TOTAL
        } else {
            let algoNames = ["Hybrid", "Perceptual", "Structural", "Conservative", "Aggressive"]
            let ai = Int(n(ss, "current_algo"))
            let algoName = ai >= 0 && ai < algoNames.count ? algoNames[ai] : "?"
            let temporalName = Int(n(ss, "temporal_mode")) == 1 ? "Phase2(buf)" : "Phase1(EMA)"
            let contentName = Int(n(ss, "content_adapt")) == 1 ? "on" : "off"
            let ringDamp = n(ss, "ring_damp")
            var info = String(format:
                "phot%@ sharp\n" + I + "global: %.2f   halo: %.2f   texture: %.2f\n"
                + I + "peak: %.2f   contrast: %.2f   noise: %.2f\n"
                + I + "motion: %.2f   amount: %.2f   fine-mix: %.2f%@\n"
                + I + "algo: %@  bands  F: %.2f  M: %.2f  C: %.2f\n"
                + I + "content-adapt: %@   temporal: %@",
                shaderStatus,
                n(ss, "global_factor"), n(ss, "halo_guard"), n(ss, "texture_bias"),
                n(photonState, "scene_smooth_peak"), n(photonState, "scene_smooth_contrast"), n(photonState, "scene_smooth_noise"),
                n(photonState, "scene_motion"), n(ss, "user_strength"), n(ss, "smooth_coarse"),
                ringDamp > 0.01 ? String(format: "   ring: -%.0f%%", ringDamp * 55) : "",
                algoName, n(ss, "fine_strength"), n(ss, "medium_strength"), n(ss, "coarse_strength"),
                contentName, temporalName)
            // The adaptive block renders only once a real sharp sample has
            // arrived (source: `if ss.adaptive_mode ~= nil`); the boot-time
            // { enabled = false } table has no adaptive_mode.
            if ss["adaptive_mode"] != nil {
            info += "\n" + I + String(format:
                "adaptive: %@   src/out: %.0f/%.0f   m: %.2f\n"
                + I + "(open-loop, source-height only, attenuation only,\n"
                + I + "synthetic basis, not noise-adaptive)",
                b(ss, "adaptive_mode") ? "on" : "off", n(ss, "source_h"), n(ss, "output_h"), n(ss, "multiplier", 1))
            }
            sharpInfo = info
        }

        let gs = grainState
        let grEnabled = gs.map { b($0, "enabled") } ?? false
        let grStatus = grEnabled ? "on" : "off"
        syncFold("grain", grEnabled)
        let GRAIN_TOTAL = 7
        var grainKnown: Int? = nil
        var grainInfo: String
        if fold["grain"]!.revealed <= 0 {
            grainInfo = String(format: "phot%@ grain", grStatus)
            grainKnown = GRAIN_TOTAL
        } else {
            let grFeed = b(photonState, "scene_has_feed") ? "live" : "no feed"
            let sizeBase = n(gs, "size_base")
            var sizeLine: String
            if let gs, b(gs, "hint_suppressed") {
                sizeLine = String(format: "base size: manual (%.2f)", sizeBase)
            } else if sizeEvidence == "instrument-derived", let hv = on(gs, "hint_value") {
                sizeLine = String(format: "base size: %.2f (measured x%.3f)", sizeBase, hv)
            } else {
                sizeLine = "base size: not measured yet (neutral 1.0)"
            }
            if let gs, b(gs, "hint_suppressed") {
                if !b(gs, "adaptive_mode") { sizeLine += " | adaptive off" }
            } else if let gs, !b(gs, "adaptive_mode") {
                sizeLine = "fixed (adaptive off)"
            } else if let why = grainMeasureStatus, let at = grainMeasureAt, now - at <= 12 {
                if why == "measured" {
                    if sizeEvidence == "instrument-derived" {
                        sizeLine += "  measured (may be unchanged)"
                    } else {
                        sizeLine = "size: measured, awaiting samples for decision"
                    }
                } else if why == "strength-only" {
                    sizeLine = "size not measured; strength estimate available"
                } else {
                    sizeLine = HUDStateModel.measureReason(why)
                }
            }
            if let gs, !b(gs, "hint_suppressed"), abs(n(gs, "size_trim", 1) - 1.0) > 0.005 {
                sizeLine += String(format: "  trim x%.2f", n(gs, "size_trim", 1))
            }
            let hueLine = (gs != nil && b(gs, "hue_has_data"))
                ? String(format: "hue: %.0f°", n(gs, "hue"))
                : "hue: off (no data)"
            let strengthBase = n(gs, "strength_base")
            let sv = on(gs, "strength_hint_value")
            let src = s(gs, "strength_src")
            let strengthLine: String
            if let gs, b(gs, "strength_hint_suppressed") {
                strengthLine = String(format: "strength: manual (%.2f)", strengthBase)
            } else if src == "auto-measured", let sv {
                strengthLine = String(format: "strength: %.2f  auto, source noise measured (x%.3f)", strengthBase, sv)
            } else if src == "auto-clean", let sv {
                strengthLine = String(format: "strength: %.2f  auto, no noise reading, full look (x%.3f)", strengthBase, sv)
            } else if src == "mult", let sv {
                strengthLine = String(format: "strength: %.2f  residual(mult x%.3f)", strengthBase, sv)
            } else if src == "seed", let sv {
                strengthLine = String(format: "strength: %.2f  seed (x%.3f)", strengthBase, sv)
            } else {
                strengthLine = String(format: "strength: %.2f  default (not measured)", strengthBase)
            }
            grainInfo = String(format:
                "phot%@ grain\n" + I + "amount: %.2f   fps: %.2f  feed: %@\n"
                + I + "%@   %@\n" + I + "%@\n"
                + I + "scene → peak: %.2f   contrast: %.2f\n"
                + I + "noise: %.2f   motion: %.2f",
                grStatus, n(gs, "amount"), n(gs, "fps"), grFeed, sizeLine, hueLine, strengthLine,
                n(photonState, "scene_smooth_peak"), n(photonState, "scene_smooth_contrast"),
                n(photonState, "scene_smooth_noise"), n(photonState, "scene_motion"))
            if let gs {
                grainInfo += "\n" + I + String(format: "resolution scale: %@",
                    !b(gs, "adaptive_mode") ? "off"
                        : (n(gs, "coefficient") > 0 ? String(format: "auto %.2fx", n(gs, "coefficient"))
                           : "on, video size not known yet"))
                if let density = on(gs, "render_density") {
                    let measured = src == "auto-measured" || src == "auto-clean"
                    grainInfo += "\n" + I + String(format:
                        measured ? "density: %.2f neutral, strength from sampled frames"
                                 : "density: %.2f neutral, strength not measured yet", density)
                } else {
                    grainInfo += "\n" + I + "strength: fixed (adaptive off)"
                }
            }
        }

        let cs = chromeState
        let chEnabled = cs.map { b($0, "enabled") } ?? false
        let chStatus = chEnabled ? "on" : "off"
        syncFold("chrome", chEnabled)
        let CHROME_TOTAL = 3
        var chromeKnown: Int? = nil
        let chromeInfo: String
        if fold["chrome"]!.revealed <= 0 {
            chromeInfo = String(format: "phot%@ chrome", chStatus)
            chromeKnown = CHROME_TOTAL
        } else {
            let names = ["red", "orange", "yellow", "green"]
            let fi = cs.map { Int(n($0, "filter_idx")) } ?? 0
            let filterName = (cs != nil && fi >= 0 && fi < names.count) ? names[fi] : "orange"
            let chFeed = cs.map { b($0, "has_feed") ? "live" : (chEnabled ? "waiting" : "no feed") } ?? "no feed"
            let chHue = on(cs, "hue").map { String(format: "%.3f", $0) } ?? "n/a"
            chromeInfo = String(format:
                "phot%@ chrome\n" + I + "filter: %@   strength: %.2f  feed: %@\n"
                + I + "contrast: %.2f   shadow: %.2f   highlight: %.2f\n"
                + I + "hue-driven: %@   hue: %@   mono-grain: %@",
                chStatus, filterName, n(cs, "filter_strength"), chFeed,
                n(cs, "contrast_amount"), n(cs, "shadow_lift"), n(cs, "highlight_rolloff"),
                (cs != nil && b(cs, "hue_driven")) ? "on" : "off", chHue,
                (cs != nil && b(cs, "mono_grain")) ? "on" : "off")
        }

        let ns = negativState
        let ngEnabled = ns.map { b($0, "enabled") } ?? false
        let ngStatus = ngEnabled ? "on" : "off"
        let ngModeName = s(ns, "mode") ?? "mask"
        syncFold("negativ", ngEnabled)
        let NEGATIV_TOTAL = 2
        var negativKnown: Int? = nil
        let negativInfo: String
        if fold["negativ"]!.revealed <= 0 {
            negativInfo = String(format: "phot%@ negativ%@", ngStatus, ngEnabled ? " — " + ngModeName : "")
            negativKnown = NEGATIV_TOTAL
        } else {
            let stockNames = ["ECN-2", "C-41", "vintage-warm"]
            let si = ns.map { Int(n($0, "stock_idx", 1)) } ?? 1
            let stockName = (ns != nil && si >= 0 && si < stockNames.count) ? stockNames[si] : "C-41"
            let ngFeed = ns.map { b($0, "has_feed") ? "live" : (ngEnabled ? "waiting" : "no feed") } ?? "no feed"
            let ngHueDriven = ns.map { b($0, "hue_driven") } ?? false
            let ngHue = on(ns, "hue").map { String(format: "%.3f", $0) } ?? "n/a"
            let ngArc = (ngHueDriven && on(ns, "hue") != nil) ? (b(ns, "arc_clamped") ? "yes" : "no") : "n/a"
            negativInfo = String(format:
                "phot%@ negativ%@\n" + I + "stock: %@   mask: %.2f   gamma: %.2f  feed: %@\n"
                + I + "hue-driven: %@   hue: %@   arc-clamped: %@",
                ngStatus, ngEnabled ? " — " + ngModeName : "",
                stockName, n(ns, "mask_gain"), n(ns, "gamma"), ngFeed,
                ngHueDriven ? "on" : "off", ngHue, ngArc)
        }

        let bd = bright
        let abStatus = bd.active ? "on" : "off"
        syncFold("bright", bd.active)
        let BRIGHT_TOTAL = 2
        var brightKnown: Int? = nil
        let brightInfo: String
        if fold["bright"]!.revealed <= 0 {
            brightInfo = String(format: "phot%@ bright", abStatus)
            brightKnown = BRIGHT_TOTAL
        } else {
            let abBacklight = bd.backlight.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"
            let abAmbient: String
            if let level = bd.ambientLevel {
                abAmbient = String(format: "%.0f%%", level * 100)
            } else if bd.ambientWindowOpen {
                abAmbient = "reading..."
            } else {
                abAmbient = "n/a"
            }
            var extra = ""
            if bd.ambientSource == "als", let lux = bd.ambientLux {
                extra = String(format: " als: %.0f lux", lux)
            } else if bd.ambientSource == "camera-room_face" {
                let face = bd.ambientFace.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"
                let room = bd.ambientRoom.map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"
                extra = String(format: " face: %@ room: %@", face, room)
            }
            let abFeed = bd.backlight != nil ? "live" : (bd.active ? "waiting" : "no feed")
            brightInfo = String(format:
                "phot%@ bright\n" + I + "backlight: %@   inertia: %@   cut: %@   feed: %@\n"
                + I + "ambient: %@%@",
                abStatus, abBacklight, bd.inertiaMode, bd.isCut ? "yes" : "no", abFeed, abAmbient, extra)
        }

        let divider = " "
        let photonSection = photonSkipFold ? "photon\t" + photonInfo : applyFold(photonInfo, section: "photon", knownTotal: photonKnown)
        let full = photonSection
            + divider + "\n" + applyFold(brightInfo, section: "bright", knownTotal: brightKnown)
            + divider + "\n" + applyFold(sharpInfo, section: "sharp", knownTotal: sharpKnown)
            + divider + "\n" + applyFold(grainInfo, section: "grain", knownTotal: grainKnown)
            + divider + "\n" + applyFold(chromeInfo, section: "chrome", knownTotal: chromeKnown)
            + divider + "\n" + applyFold(negativInfo, section: "negativ", knownTotal: negativKnown)
        let payload = full.replacingOccurrences(of: "\n", with: "‖")
        return HUDRenderState(osdPayload: payload, foldPositions: foldPositions(),
                              sectionLines: ["photon": [photonInfo], "bright": [brightInfo], "sharp": [sharpInfo],
                                             "grain": [grainInfo], "chrome": [chromeInfo], "negativ": [negativInfo]])
    }

    private func foldPositions() -> [String: Int] {
        fold.mapValues { $0.revealed == .infinity ? Int.max : Int($0.revealed) }
    }
}
