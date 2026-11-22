#!/usr/bin/env python3
"""P29-HUD golden vectors: formula-derived expected behaviour for
photon-hud.lua v2.2.17's state/aggregation/display layer, emitted as JSON for
the Linux witness (hud-state-tests) and the gor-lane harness. Formula-derived
(no Lua interpreter on this host); the gor lane re-derives truth from the
authoritative Lua before the Swift model leaves inert. Source pin: instinct
main photon-hud.lua 820 lines SHA256 0902f3b07901dbffb95ffeb056011e1a68e2144e14e380f65e1f23dd111c696d.

The compared output per draw is the exact gor-osd payload string (newlines
escaped as U+2016), matching print("gor-osd:" .. escaped). Timestamps are
integer microseconds (nowUs) like DR-0019."""
import json, math, sys

HUD_INDENT = " " * 6
INF = math.inf

def lua_fmt(fmt, *args):
    """C printf semantics - Python's %-formatting matches Lua string.format."""
    return fmt % args

class Guard:
    """hud_guard: domain-checked numeric fields, hold-last-good, warn-once."""
    def __init__(self):
        self.logged = {}
        self.last = {}
        self.warnings = []  # observed, not part of parity output
    def num(self, field, s, lo, hi, fallback):
        if s is None or s == "":
            return fallback
        try:
            v = float(s)
        except (TypeError, ValueError):
            v = None
        if v is None or v != v or v == INF or v == -INF or v < lo or v > hi:
            if field not in self.logged:
                self.logged[field] = True
                self.warnings.append(field)
            return self.last.get(field, fallback)
        self.last[field] = v
        return v

class FoldState:
    def __init__(self, revealed, direction):
        self.revealed = revealed
        self.direction = direction
        self.timer = False  # animation running
        self.just_flipped = False
        self.last_enabled = None

def split_lines(body):
    if body == "":
        return []
    return body[1:].split("\n")[:-1] if body.endswith("\n") else (body[1:] + "\n")[:-1].split("\n")

class Sim:
    """Exact replica of photon-hud.lua's draw_hud state machine."""
    def __init__(self):
        self.enabled = False
        self.guard = Guard()
        self.photon_state = None
        self.grain_state = None
        self.chrome_state = None
        self.negativ_state = None
        self.sharp_state = {"enabled": False}
        self.grain_measure_status = None
        self.grain_measure_at = None
        self.size_evidence = None
        # user-data/adaptive-brightness-* (Swift-written properties in the
        # source; here plain inputs).
        self.bright = {
            "active": False, "backlight": None, "inertia_mode": "n/a",
            "is_cut": False, "ambient_level": None, "ambient_window_open": False,
            "ambient_source": "n/a", "ambient_lux": None,
            "ambient_face": None, "ambient_room": None,
        }
        self.fold = {
            "photon":  FoldState(INF, -1),
            "bright":  FoldState(INF, -1),
            "sharp":   FoldState(INF, -1),
            "grain":   FoldState(INF, -1),
            "chrome":  FoldState(0, 1),
            "negativ": FoldState(0, 1),
        }
        self.now = 0.0

    # ---- message handlers (state ingress) ----
    def grain_hud_state(self, **f):
        g = self.guard.num
        self.grain_state = {
            "enabled": f["enabled_str"] == "true",
            "amount": g("grain.amount", f["amount_str"], 0.0, 1000.0, 0.0),
            "fps": g("grain.fps", f["fps_str"], 0.0, 1000.0, 0.0),
            "size_base": g("grain.size_base", f["size_base_str"], 0.0, 100.0, 0.0),
            "hint_received": f["hint_received_str"] == "true",
            "hint_suppressed": f["hint_suppressed_str"] == "true",
            "hint_value": g("grain.hint_value", f["hint_value_str"], 0.0, 100.0, None),
            "hue_has_data": f["hue_has_data_str"] == "true",
            "hue": g("grain.hue", f["hue_str"], 0.0, 360.0, 0.0),
            "source_h": g("grain.source_h", f["source_h_str"], 0.0, 100000.0, 0.0),
            "output_h": g("grain.output_h", f["output_h_str"], 0.0, 100000.0, 0.0),
            "coefficient": g("grain.coefficient", f["coefficient_str"], 0.0, 2.0, 0.0),
            "strength_k": g("grain.strength_k", f["strength_k_str"], 0.0, 2.0, None),
            "adaptive_mode": f["adaptive_mode_str"] == "true",
            "strength_status": f["strength_status_str"],
            "render_density": g("grain.render_density", f["render_density_str"], 0.0, 1.0, None),
            "strength_base": g("grain.strength_base", f["strength_base_str"], 0.0, 1000.0, 0.0),
            "strength_src": f["strength_src_str"],
            "size_trim": g("grain.size_trim", f["size_trim_str"], 0.0, 100.0, 1.0),
            "strength_hint_received": f["strength_hint_received_str"] == "true",
            "strength_hint_suppressed": f["strength_hint_suppressed_str"] == "true",
            "strength_hint_value": g("grain.strength_hint_value", f["strength_hint_value_str"], 0.0, 1000.0, None),
        }

    def chrome_hud_state(self, **f):
        g = self.guard.num
        self.chrome_state = {
            "enabled": f["enabled_str"] == "true",
            "filter_idx": g("chrome.filter_idx", f["filter_idx_str"], 0.0, 100.0, 0),
            "filter_strength": g("chrome.filter_strength", f["filter_strength_str"], 0.0, 100.0, 0.0),
            "contrast_amount": g("chrome.contrast", f["contrast_str"], -100.0, 100.0, 0.0),
            "has_feed": f["has_feed_str"] == "true",
            "hue_driven": f["hue_driven_str"] == "true",
            "hue": g("chrome.hue", f["hue_str"], 0.0, 360.0, None),
            "shadow_lift": g("chrome.shadow_lift", f["shadow_lift_str"], -100.0, 100.0, 0.0),
            "highlight_rolloff": g("chrome.highlight_rolloff", f["highlight_rolloff_str"], 0.0, 1000.0, 0.0),
            "mono_grain": f["mono_grain_str"] == "true",
            "arc_clamped": f["arc_clamped_str"] == "true",
        }

    def negativ_hud_state(self, **f):
        g = self.guard.num
        self.negativ_state = {
            "enabled": f["enabled_str"] == "true",
            "stock_idx": g("negativ.stock_idx", f["stock_idx_str"], 1.0, 100.0, 1),
            "mask_gain": g("negativ.mask_gain", f["mask_gain_str"], 0.0, 1000.0, 0.0),
            "gamma": g("negativ.gamma", f["gamma_str"], 0.0, 100.0, 0.0),
            "has_feed": f["has_feed_str"] == "true",
            "hue_driven": f["hue_driven_str"] == "true",
            "hue": g("negativ.hue", f["hue_str"], 0.0, 360.0, None),
            "arc_clamped": f["arc_clamped_str"] == "true",
            "mode": f.get("mode_str") or "mask",
        }

    def sharp_hud_state(self, **f):
        g = self.guard.num
        self.sharp_state = {
            "enabled": f["enabled_str"] == "true",
            "shader_ready": f["shader_ready_str"] == "true",
            "current_algo": g("sharp.current_algo", f["current_algo_str"], 0.0, 100.0, 0),
            "user_strength": g("sharp.user_strength", f["user_strength_str"], 0.0, 1000.0, 0.0),
            "smooth_coarse": g("sharp.smooth_coarse", f["smooth_coarse_str"], 0.0, 1000.0, 0.0),
            "global_factor": g("sharp.global_factor", f["global_factor_str"], 0.0, 100.0, 0.0),
            "halo_guard": g("sharp.halo_guard", f["halo_guard_str"], 0.0, 100.0, 0.0),
            "texture_bias": g("sharp.texture_bias", f["texture_bias_str"], 0.0, 100.0, 0.0),
            "fine_strength": g("sharp.fine_strength", f["fine_strength_str"], 0.0, 1000.0, 0.0),
            "medium_strength": g("sharp.medium_strength", f["medium_strength_str"], 0.0, 1000.0, 0.0),
            "coarse_strength": g("sharp.coarse_strength", f["coarse_strength_str"], 0.0, 1000.0, 0.0),
            "content_adapt": g("sharp.content_adapt", f["content_adapt_str"], 0.0, 100.0, 0),
            "temporal_mode": g("sharp.temporal_mode", f["temporal_mode_str"], 0.0, 100.0, 0),
            "ring_damp": g("sharp.ring_damp", f["ring_damp_str"], 0.0, 100.0, 0.0),
            "source_h": g("sharp.source_h", f["source_h_str"], 0.0, 100000.0, 0.0),
            "output_h": g("sharp.output_h", f["output_h_str"], 0.0, 100000.0, 0.0),
            "multiplier": g("sharp.multiplier", f["multiplier_str"], 0.5, 1.0, 1.0),
            "adaptive_mode": f["adaptive_mode_str"] == "true",
        }

    def photon_hud_state(self, **f):
        g = self.guard.num
        self.photon_state = {
            "enabled": f["enabled_str"] == "true",
            "scene_smooth_peak": g("photon.scene_smooth_peak", f["scene_smooth_peak_str"], 0.0, 1.0, 0.0),
            "scene_smooth_contrast": g("photon.scene_smooth_contrast", f["scene_smooth_contrast_str"], 0.0, 1.0, 0.0),
            "scene_smooth_noise": g("photon.scene_smooth_noise", f["scene_smooth_noise_str"], 0.0, 1.0, 0.0),
            "scene_motion": g("photon.scene_motion", f["scene_motion_str"], 0.0, 1.0, 0.0),
            "scene_has_feed": f["scene_has_feed_str"] == "true",
            "is_hdr": f["is_hdr_str"] == "true",
            "is_live": f["is_live_str"] == "true",
            "hdr_peak": g("photon.hdr_peak", f["hdr_peak_str"], 0.0, 100000.0, 0.0),
            "hdr_vel": g("photon.hdr_vel", f["hdr_vel_str"], -5000.0, 5000.0, 0.0),
            "hdr_avg": g("photon.hdr_avg", f["hdr_avg_str"], 0.0, 1.0, 0.0),
            "hdr_drive": g("photon.hdr_drive", f["hdr_drive_str"], 0.0, 1.0, 0.0),
            "hdr_contrast": g("photon.hdr_contrast", f["hdr_contrast_str"], 0.0, 1.0, 0.0),
            "hdr_cut_thr": g("photon.hdr_cut_thr", f["hdr_cut_thr_str"], 0.0, 1.0, 0.0),
            "hdr_pq": g("photon.hdr_pq", f["hdr_pq_str"], 0.0, 1.0, 0.0),
            "hdr_dark_thresh": g("photon.hdr_dark_thresh", f["hdr_dark_thresh_str"], 0.0, 1.0, 0.0),
            "hdr_bright_thresh": g("photon.hdr_bright_thresh", f["hdr_bright_thresh_str"], 0.0, 1.0, 0.0),
            "sdr_pbs": g("photon.sdr_pbs", f["sdr_pbs_str"], 0.0, 10000.0, 0.0),
            "sdr_vel": g("photon.sdr_vel", f["sdr_vel_str"], -10000.0, 10000.0, 0.0),
            "sdr_gamma": g("photon.sdr_gamma", f["sdr_gamma_str"], -7.5, 7.5, 0.0),
            "sdr_neutral": g("photon.sdr_neutral", f["sdr_neutral_str"], 0.0, 10000.0, 0.0),
            "live_calib_ready": f["live_calib_ready_str"] == "true",
            "live_calib_samples": g("photon.live_calib_samples", f["live_calib_samples_str"], 0.0, 1000000.0, 0),
            "live_calib_frames": g("photon.live_calib_frames", f["live_calib_frames_str"], 0.0, 1000000.0, 0),
            "radar_buffer_len": g("photon.radar_buffer_len", f["radar_buffer_len_str"], 0.0, 10000000.0, 0),
            "radar_buffer_miss": f["radar_buffer_miss_str"] == "true",
            "ring": g("photon.ring", f["ring_str"], 0.0, 1000.0, 0.0),
            "rlevel": g("photon.rlevel", f["rlevel_str"], 0.0, 1.0, 0.0),
        }

    def set_grain_measure_status(self, value, now):
        self.grain_measure_status = value
        self.grain_measure_at = now

    def file_loaded(self):
        self.grain_measure_status = None
        self.grain_measure_at = None

    # ---- fold machine ----
    def apply_fold(self, info_text, section, known_total_lines=None):
        nl = info_text.find("\n")
        title = info_text[:nl] if nl >= 0 else info_text
        body = info_text[nl:] if nl >= 0 else ""
        prefix = section + "\t"
        state = self.fold.get(section)
        if state is None:
            return prefix + title + body
        lines = split_lines(body)
        total = known_total_lines if known_total_lines is not None else len(lines)
        state.just_flipped = False
        if state.revealed == total and state.direction > 0:
            state.direction = -1
            state.just_flipped = True
        elif state.revealed == 0 and state.direction < 0:
            state.direction = 1
            state.just_flipped = True
        if state.revealed > total:
            state.revealed = total
        if state.revealed < 0:
            state.revealed = 0
        if state.revealed <= 0:
            return prefix + title
        if state.revealed >= total:
            return prefix + title + "\n" + "\n".join(prefix + l for l in lines[:total])
        return prefix + title + "\n" + "\n".join(prefix + l for l in lines[:state.revealed])

    def start_fold_animation(self, state, from_within_draw_hud=False):
        state.revealed += state.direction
        state.just_flipped = False
        if not from_within_draw_hud:
            self.draw_hud()
            if state.just_flipped:
                return
        state.timer = True

    def toggle_fold(self, section):
        state = self.fold.get(section)
        if state is None:
            return
        if state.timer:
            state.direction = -state.direction
            return
        self.start_fold_animation(state)

    def fold_tick(self, section):
        """One 0.04s timer tick for a section with a running animation."""
        state = self.fold[section]
        if not state.timer:
            return
        if state.just_flipped:
            state.timer = False
            return
        state.revealed += state.direction
        self.draw_hud()
        if state.just_flipped:
            state.timer = False

    def sync_fold(self, section, is_enabled):
        state = self.fold.get(section)
        if state is None:
            return
        if state.last_enabled is None:
            state.last_enabled = is_enabled
            return
        if state.last_enabled == is_enabled:
            return
        state.last_enabled = is_enabled
        if state.timer:
            return
        needs_open = is_enabled and state.revealed == 0
        needs_close = (not is_enabled) and state.revealed > 0
        if not (needs_open or needs_close):
            return
        state.direction = 1 if is_enabled else -1
        self.start_fold_animation(state, from_within_draw_hud=True)

    # ---- draw ----
    def draw_hud(self):
        if not self.enabled:
            return None
        pst = self.photon_state
        photon_status = ("on" if pst["enabled"] else "off") if pst else "?"
        PHOTON_TOTAL = 4
        if pst:
            self.sync_fold("photon", pst["enabled"])
        photon_skip_fold = False
        photon_known = None
        if not pst:
            photon_info = "phot? photon\n" + HUD_INDENT + "waiting for photon.lua…"
            photon_skip_fold = True
        elif self.fold["photon"].revealed <= 0:
            photon_info = lua_fmt("phot%s %s", photon_status, "hdr" if pst["is_hdr"] else "sdr")
            photon_known = PHOTON_TOTAL
        elif pst["is_hdr"]:
            zone = ("dark" if pst["hdr_pq"] < pst["hdr_dark_thresh"]
                    else "bright" if pst["hdr_pq"] > pst["hdr_bright_thresh"] else "mid")
            photon_info = lua_fmt(
                "phot%s hdr%s\n"
                + HUD_INDENT + "peak: %d nit   vel: %+.1f nit/s\n"
                + HUD_INDENT + "avg-pq: %.4f   hybrid: %.4f\n"
                + HUD_INDENT + "contrast ∂: %.4f   cut@: %.4f\n"
                + HUD_INDENT + "scene: %s   ring: %.1f (lvl %.2f)",
                photon_status, "  live" if pst["is_live"] else "",
                math.floor(pst["hdr_peak"]), pst["hdr_vel"],
                pst["hdr_avg"], pst["hdr_drive"], pst["hdr_contrast"], pst["hdr_cut_thr"],
                zone, pst["ring"], pst["rlevel"])
            photon_known = PHOTON_TOTAL
        else:
            if pst["is_live"]:
                mode = lua_fmt("live  vf-metadata  calib: %s",
                               lua_fmt("%.0f", pst["sdr_neutral"]) if pst["live_calib_ready"]
                               else lua_fmt("%d/%d", pst["live_calib_samples"], pst["live_calib_frames"]))
            elif pst["radar_buffer_len"] > 0 and not pst["radar_buffer_miss"]:
                mode = lua_fmt("radar  %d frames", pst["radar_buffer_len"])
            elif pst["radar_buffer_miss"]:
                mode = "seek → probe"
            else:
                mode = "probe (warming up)"
            zone = ("dark" if pst["sdr_pbs"] < pst["sdr_neutral"] * 0.6
                    else "bright" if pst["sdr_pbs"] > pst["sdr_neutral"] * 1.4 else "mid")
            photon_info = lua_fmt(
                "phot%s sdr\n"
                + HUD_INDENT + "%s\n"
                + HUD_INDENT + "pbs: %.1f   vel: %+.1f/s\n"
                + HUD_INDENT + "gamma: %.2f   neutral: %.0f\n"
                + HUD_INDENT + "scene: %s   ring: %.1f (lvl %.2f)",
                photon_status, mode, pst["sdr_pbs"], pst["sdr_vel"], pst["sdr_gamma"],
                pst["sdr_neutral"], zone, pst["ring"], pst["rlevel"])
            photon_known = PHOTON_TOTAL

        ss = self.sharp_state
        shader_status = "off" if not ss["enabled"] else ("on" if ss.get("shader_ready") else "off")
        self.sync_fold("sharp", ss["enabled"])
        SHARP_TOTAL = 8
        sharp_known = None
        if self.fold["sharp"].revealed <= 0:
            sharp_info = lua_fmt("phot%s sharp", shader_status)
            sharp_known = SHARP_TOTAL
        else:
            algo_names = ["Hybrid", "Perceptual", "Structural", "Conservative", "Aggressive"]
            idx = int(ss.get("current_algo") or 0)
            algo_name = algo_names[idx] if 0 <= idx < len(algo_names) else "?"
            temporal_name = "Phase2(buf)" if ss.get("temporal_mode") == 1 else "Phase1(EMA)"
            content_name = "on" if ss.get("content_adapt") == 1 else "off"
            p = self.photon_state or {}
            sharp_info = lua_fmt(
                "phot%s sharp\n"
                + HUD_INDENT + "global: %.2f   halo: %.2f   texture: %.2f\n"
                + HUD_INDENT + "peak: %.2f   contrast: %.2f   noise: %.2f\n"
                + HUD_INDENT + "motion: %.2f   amount: %.2f   fine-mix: %.2f%s\n"
                + HUD_INDENT + "algo: %s  bands  F: %.2f  M: %.2f  C: %.2f\n"
                + HUD_INDENT + "content-adapt: %s   temporal: %s",
                shader_status,
                ss.get("global_factor") or 0.0, ss.get("halo_guard") or 0.0, ss.get("texture_bias") or 0.0,
                p.get("scene_smooth_peak") or 0.0, p.get("scene_smooth_contrast") or 0.0, p.get("scene_smooth_noise") or 0.0,
                p.get("scene_motion") or 0.0, ss.get("user_strength") or 0.0, ss.get("smooth_coarse") or 0.0,
                (lua_fmt("   ring: -%.0f%%", (ss.get("ring_damp") or 0.0) * 55)
                 if (ss.get("ring_damp") or 0.0) > 0.01 else ""),
                algo_name, ss.get("fine_strength") or 0.0, ss.get("medium_strength") or 0.0,
                ss.get("coarse_strength") or 0.0, content_name, temporal_name)
            if ss.get("adaptive_mode") is not None:
                sharp_info += "\n" + HUD_INDENT + lua_fmt(
                    "adaptive: %s   src/out: %.0f/%.0f   m: %.2f\n"
                    + HUD_INDENT + "(open-loop, source-height only, attenuation only,\n"
                    + HUD_INDENT + "synthetic basis, not noise-adaptive)",
                    "on" if ss["adaptive_mode"] else "off",
                    ss.get("source_h") or 0, ss.get("output_h") or 0, ss.get("multiplier") or 1)

        gs = self.grain_state
        gr_enabled = gs["enabled"] if gs else False
        gr_status = "on" if gr_enabled else "off"
        self.sync_fold("grain", gr_enabled)
        GRAIN_TOTAL = 7
        grain_known = None
        if self.fold["grain"].revealed <= 0:
            grain_info = lua_fmt("phot%s grain", gr_status)
            grain_known = GRAIN_TOTAL
        else:
            p = self.photon_state or {}
            gr_amount = gs["amount"] if gs else 0.0
            gr_fps = gs["fps"] if gs else 0.0
            gr_feed = "live" if p.get("scene_has_feed") else "no feed"
            size_base = gs["size_base"] if gs else 0.0
            if gs and gs["hint_suppressed"]:
                size_line = lua_fmt("base size: manual (%.2f)", size_base)
            else:
                if self.size_evidence == "instrument-derived" and gs and gs["hint_value"]:
                    size_line = lua_fmt("base size: %.2f (measured x%.3f)", size_base, gs["hint_value"])
                else:
                    size_line = "base size: not measured yet (neutral 1.0)"
            if gs and gs["hint_suppressed"]:
                if not gs["adaptive_mode"]:
                    size_line += " | adaptive off"
            elif gs and not gs["adaptive_mode"]:
                size_line = "fixed (adaptive off)"
            elif (self.grain_measure_status and self.grain_measure_at is not None
                  and self.now - self.grain_measure_at <= 12):
                why = self.grain_measure_status
                if why == "measured":
                    if self.size_evidence == "instrument-derived":
                        size_line += "  measured (may be unchanged)"
                    else:
                        size_line = "size: measured, awaiting samples for decision"
                elif why == "strength-only":
                    size_line = "size not measured; strength estimate available"
                else:
                    size_line = measure_reason(why)
            if gs and not gs["hint_suppressed"] and gs["size_trim"] and abs(gs["size_trim"] - 1.0) > 0.005:
                size_line += lua_fmt("  trim x%.2f", gs["size_trim"])
            hue_line = (lua_fmt("hue: %.0f°", gs["hue"]) if gs and gs["hue_has_data"]
                        else "hue: off (no data)")
            strength_base = gs["strength_base"] if gs else 0.0
            sv = gs["strength_hint_value"] if gs else None
            if gs and gs["strength_hint_suppressed"]:
                strength_line = lua_fmt("strength: manual (%.2f)", strength_base)
            elif gs and gs["strength_src"] == "auto-measured" and sv:
                strength_line = lua_fmt("strength: %.2f  auto, source noise measured (x%.3f)", strength_base, sv)
            elif gs and gs["strength_src"] == "auto-clean" and sv:
                strength_line = lua_fmt("strength: %.2f  auto, no noise reading, full look (x%.3f)", strength_base, sv)
            elif gs and gs["strength_src"] == "mult" and sv:
                strength_line = lua_fmt("strength: %.2f  residual(mult x%.3f)", strength_base, sv)
            elif gs and gs["strength_src"] == "seed" and sv:
                strength_line = lua_fmt("strength: %.2f  seed (x%.3f)", strength_base, sv)
            else:
                strength_line = lua_fmt("strength: %.2f  default (not measured)", strength_base)
            grain_info = lua_fmt(
                "phot%s grain\n"
                + HUD_INDENT + "amount: %.2f   fps: %.2f  feed: %s\n"
                + HUD_INDENT + "%s   %s\n"
                + HUD_INDENT + "%s\n"
                + HUD_INDENT + "scene → peak: %.2f   contrast: %.2f\n"
                + HUD_INDENT + "noise: %.2f   motion: %.2f",
                gr_status, gr_amount, gr_fps, gr_feed, size_line, hue_line, strength_line,
                p.get("scene_smooth_peak") or 0.0, p.get("scene_smooth_contrast") or 0.0,
                p.get("scene_smooth_noise") or 0.0, p.get("scene_motion") or 0.0)
            if gs:
                grain_info += "\n" + HUD_INDENT + lua_fmt(
                    "resolution scale: %s",
                    "off" if not gs["adaptive_mode"]
                    else (lua_fmt("auto %.2fx", gs["coefficient"]) if (gs["coefficient"] or 0) > 0
                          else "on, video size not known yet"))
                grain_info += "\n" + HUD_INDENT + (
                    lua_fmt("density: %.2f neutral, strength from sampled frames", gs["render_density"])
                    if gs["render_density"] and gs["strength_src"] in ("auto-measured", "auto-clean")
                    else lua_fmt("density: %.2f neutral, strength not measured yet", gs["render_density"])
                    if gs["render_density"] else "strength: fixed (adaptive off)")

        cs = self.chrome_state
        ch_enabled = cs["enabled"] if cs else False
        ch_status = "on" if ch_enabled else "off"
        self.sync_fold("chrome", ch_enabled)
        CHROME_TOTAL = 3
        chrome_known = None
        if self.fold["chrome"].revealed <= 0:
            chrome_info = lua_fmt("phot%s chrome", ch_status)
            chrome_known = CHROME_TOTAL
        else:
            names = ["red", "orange", "yellow", "green"]
            fi = int(cs["filter_idx"]) if cs else 0
            ch_filter_name = names[fi] if cs and 0 <= fi < 4 else "orange"
            ch_feed = ("live" if cs["has_feed"] else ("waiting" if ch_enabled else "no feed")) if cs else "no feed"
            ch_hue = lua_fmt("%.3f", cs["hue"]) if cs and cs["hue"] is not None else "n/a"
            chrome_info = lua_fmt(
                "phot%s chrome\n"
                + HUD_INDENT + "filter: %s   strength: %.2f  feed: %s\n"
                + HUD_INDENT + "contrast: %.2f   shadow: %.2f   highlight: %.2f\n"
                + HUD_INDENT + "hue-driven: %s   hue: %s   mono-grain: %s",
                ch_status, ch_filter_name, cs["filter_strength"] if cs else 0.0, ch_feed,
                cs["contrast_amount"] if cs else 0.0, cs["shadow_lift"] if cs else 0.0,
                cs["highlight_rolloff"] if cs else 0.0,
                "on" if (cs and cs["hue_driven"]) else "off", ch_hue,
                "on" if (cs and cs["mono_grain"]) else "off")

        ns = self.negativ_state
        ng_enabled = ns["enabled"] if ns else False
        ng_status = "on" if ng_enabled else "off"
        ng_mode_name = ns["mode"] if ns else "mask"
        self.sync_fold("negativ", ng_enabled)
        NEGATIV_TOTAL = 2
        negativ_known = None
        if self.fold["negativ"].revealed <= 0:
            negativ_info = lua_fmt("phot%s negativ%s", ng_status,
                                   " — " + ng_mode_name if ng_enabled else "")
            negativ_known = NEGATIV_TOTAL
        else:
            stock_names = ["ECN-2", "C-41", "vintage-warm"]
            si = int(ns["stock_idx"]) if ns else 1
            ng_stock = stock_names[si] if ns and 0 <= si < 3 else "C-41"
            ng_feed = ("live" if ns["has_feed"] else ("waiting" if ng_enabled else "no feed")) if ns else "no feed"
            ng_hue_driven = ns["hue_driven"] if ns else False
            ng_hue = lua_fmt("%.3f", ns["hue"]) if ns and ns["hue"] is not None else "n/a"
            ng_arc = (("yes" if ns["arc_clamped"] else "no") if (ng_hue_driven and ns and ns["hue"] is not None)
                      else "n/a")
            negativ_info = lua_fmt(
                "phot%s negativ%s\n"
                + HUD_INDENT + "stock: %s   mask: %.2f   gamma: %.2f  feed: %s\n"
                + HUD_INDENT + "hue-driven: %s   hue: %s   arc-clamped: %s",
                ng_status, " — " + ng_mode_name if ng_enabled else "",
                ng_stock, ns["mask_gain"] if ns else 0.0, ns["gamma"] if ns else 0.0, ng_feed,
                "on" if ng_hue_driven else "off", ng_hue, ng_arc)

        b = self.bright
        ab_status = "on" if b["active"] else "off"
        self.sync_fold("bright", b["active"])
        BRIGHT_TOTAL = 2
        bright_known = None
        if self.fold["bright"].revealed <= 0:
            bright_info = lua_fmt("phot%s bright", ab_status)
            bright_known = BRIGHT_TOTAL
        else:
            ab_backlight = lua_fmt("%.0f%%", b["backlight"] * 100) if b["backlight"] is not None else "n/a"
            if b["ambient_level"] is not None:
                ab_ambient = lua_fmt("%.0f%%", b["ambient_level"] * 100)
            elif b["ambient_window_open"]:
                ab_ambient = "reading..."
            else:
                ab_ambient = "n/a"
            extra = ""
            if b["ambient_source"] == "als" and b["ambient_lux"] is not None:
                extra = lua_fmt(" als: %.0f lux", b["ambient_lux"])
            elif b["ambient_source"] == "camera-room_face":
                face = lua_fmt("%.0f%%", b["ambient_face"] * 100) if b["ambient_face"] is not None else "n/a"
                room = lua_fmt("%.0f%%", b["ambient_room"] * 100) if b["ambient_room"] is not None else "n/a"
                extra = lua_fmt(" face: %s room: %s", face, room)
            ab_feed = "live" if b["backlight"] is not None else ("waiting" if b["active"] else "no feed")
            bright_info = lua_fmt(
                "phot%s bright\n"
                + HUD_INDENT + "backlight: %s   inertia: %s   cut: %s   feed: %s\n"
                + HUD_INDENT + "ambient: %s%s",
                ab_status, ab_backlight, b["inertia_mode"],
                "yes" if b["is_cut"] else "no", ab_feed, ab_ambient, extra)

        divider = " "
        full = (("photon\t" + photon_info) if photon_skip_fold
                else self.apply_fold(photon_info, "photon", photon_known)) \
            + divider + "\n" \
            + self.apply_fold(bright_info, "bright", bright_known) \
            + divider + "\n" \
            + self.apply_fold(sharp_info, "sharp", sharp_known) \
            + divider + "\n" \
            + self.apply_fold(grain_info, "grain", grain_known) \
            + divider + "\n" \
            + self.apply_fold(chrome_info, "chrome", chrome_known) \
            + divider + "\n" \
            + self.apply_fold(negativ_info, "negativ", negativ_known)
        return full.replace("\n", "‖")


def measure_reason(why):
    def starts(p):
        return why[:len(p)] == p
    if starts("shot-fail") or starts("shot-fields") or starts("data-not-string") or starts("short-row"):
        return "not measured: capture failed"
    if starts("crop<96"):
        return "not measured: frame too small"
    if starts("capture-no-luma") or starts("no-frame-height"):
        return "not measured: frame unreadable"
    if starts("blocks<6"):
        return "not measured: too few blocks"
    if starts("zero-hp"):
        return "not measured: frame too flat"
    if starts("stale-mirror"):
        return "not measured: stale grain mirror"
    if starts("soft<"):
        return "not measured: softness outside table"
    if starts("no-eff"):
        return "not measured: effective size outside table"
    if starts("over-corrected-source-power") or starts("garbage-curve") or starts("source-share-below-floor"):
        return "not measured: no valid size signal"
    return "not measured: see log for reason"


# ---------------------------------------------------------------- vectors --
def us(t):
    return int(round(t * 1e6))

vectors = []

GRAIN_FULL = dict(enabled_str="true", amount_str="0.55", fps_str="24.0",
    size_base_str="1.25", hint_received_str="true", hint_suppressed_str="false",
    hint_value_str="1.023", hue_has_data_str="true", hue_str="42.0",
    strength_base_str="0.62", strength_hint_received_str="true",
    strength_hint_suppressed_str="false", strength_hint_value_str="0.58",
    size_rendered_str="1.2", development_rendered_str="0.9", softness_rendered_str="0.3",
    amount_rendered_str="0.55", user_offset_str="0.0", weight_shift_str="0.0",
    res_adapt_str="true", target_enabled_str="true", source_h_str="1080",
    output_h_str="2160", coefficient_str="1.12", strength_k_str="0.9",
    adaptive_mode_str="true", strength_status_str="ok", render_density_str="0.5",
    effective_h_str="1080", strength_src_str="auto-measured", size_trim_str="1.04")

CHROME_FULL = dict(enabled_str="true", filter_idx_str="1", filter_strength_str="0.68",
    contrast_str="0.12", has_feed_str="true", hue_driven_str="true", hue_str="0.083",
    shadow_lift_str="0.05", highlight_rolloff_str="0.9", mono_grain_str="false",
    arc_clamped_str="false", manual_filter_str="false")

NEGATIV_FULL = dict(enabled_str="true", stock_idx_str="1", mask_gain_str="0.85",
    gamma_str="1.05", has_feed_str="true", hue_driven_str="true", hue_str="0.5",
    arc_clamped_str="true", mode_str="mask")

SHARP_FULL = dict(enabled_str="true", shader_ready_str="true", current_algo_str="0",
    user_strength_str="0.45", smooth_coarse_str="0.30", global_factor_str="0.80",
    halo_guard_str="0.65", texture_bias_str="0.20", fine_strength_str="0.50",
    medium_strength_str="0.35", coarse_strength_str="0.25", content_adapt_str="1",
    temporal_mode_str="1", ring_damp_str="0.10", target_enabled_str="true",
    source_h_str="1080", output_h_str="2160", multiplier_str="0.85",
    adaptive_mode_str="true")

PHOTON_HDR = dict(enabled_str="true", scene_smooth_peak_str="0.72",
    scene_smooth_contrast_str="0.31", scene_smooth_noise_str="0.12",
    scene_motion_str="0.05", scene_has_feed_str="true", is_hdr_str="true",
    is_live_str="false", hdr_peak_str="812.4", hdr_vel_str="-12.5",
    hdr_avg_str="0.4123", hdr_drive_str="0.505", hdr_contrast_str="0.0771",
    hdr_cut_thr_str="0.42", hdr_pq_str="0.55", hdr_dark_thresh_str="0.30",
    hdr_bright_thresh_str="0.75", sdr_pbs_str="120.0", sdr_vel_str="2.0",
    sdr_gamma_str="-1.875", sdr_neutral_str="110.0", live_calib_ready_str="false",
    live_calib_samples_str="2", live_calib_frames_str="50",
    radar_buffer_len_str="300", radar_buffer_miss_str="false",
    ring_str="12.3", rlevel_str="0.44")

PHOTON_SDR = dict(PHOTON_HDR, is_hdr_str="false")

# V1 all-sections steady state: every subsystem enabled and feeding, one draw.
sim = Sim()
steps = []
sim.photon_hud_state(**PHOTON_HDR); steps.append({"op": "photonHudState", "fields": PHOTON_HDR, "nowUs": 0})
sim.grain_hud_state(**GRAIN_FULL); steps.append({"op": "grainHudState", "fields": GRAIN_FULL, "nowUs": 0})
sim.chrome_hud_state(**CHROME_FULL); steps.append({"op": "chromeHudState", "fields": CHROME_FULL, "nowUs": 0})
sim.negativ_hud_state(**NEGATIV_FULL); steps.append({"op": "negativHudState", "fields": NEGATIV_FULL, "nowUs": 0})
sim.sharp_hud_state(**SHARP_FULL); steps.append({"op": "sharpHudState", "fields": SHARP_FULL, "nowUs": 0})
BRIGHT1 = dict(active=True, backlight=0.62, inertia_mode="ease", is_cut=False,
               ambient_level=0.35, ambient_source="als", ambient_lux=180.0)
sim.bright.update(BRIGHT1); steps.append({"op": "brightState", "fields": BRIGHT1, "nowUs": 0})
sim.enabled = True
steps.append({"op": "hudToggle", "nowUs": 0})
steps.append({"op": "draw", "nowUs": 0, "expect": {"osd": sim.draw_hud()}})
vectors.append({"name": "V1-all-sections-hdr", "steps": steps})

# V2 guard paths: NaN / inf / out-of-domain / empty-string hold + last-good.
sim = Sim()
steps = []
sim.photon_hud_state(**PHOTON_HDR); steps.append({"op": "photonHudState", "fields": PHOTON_HDR, "nowUs": 0})
sim.enabled = True
steps.append({"op": "hudToggle", "nowUs": 0})
steps.append({"op": "draw", "nowUs": 0, "expect": {"osd": sim.draw_hud()}})
bad = dict(PHOTON_HDR, hdr_peak_str="nan", hdr_vel_str="inf",
           sdr_gamma_str="99.0", scene_smooth_peak_str="")
sim.photon_hud_state(**bad)
steps.append({"op": "photonHudState", "fields": bad, "nowUs": us(0.25)})
steps.append({"op": "draw", "nowUs": us(0.25), "expect": {"osd": sim.draw_hud()}})
steps.append({"op": "expectWarnings", "fields": ["photon.hdr_peak", "photon.hdr_vel", "photon.sdr_gamma"]})
vectors.append({"name": "V2-guard-corrupt-hold", "steps": steps})

# V3 fold toggle trajectory: chrome starts folded (revealed 0); click opens it
# one line per tick, flips direction at full, click again closes to 0.
sim2 = Sim()
steps = []
sim2.photon_hud_state(**PHOTON_SDR); steps.append({"op": "photonHudState", "fields": PHOTON_SDR, "nowUs": 0})
sim2.chrome_hud_state(**CHROME_FULL); steps.append({"op": "chromeHudState", "fields": CHROME_FULL, "nowUs": 0})
sim2.enabled = True
steps.append({"op": "hudToggle", "nowUs": 0})
steps.append({"op": "draw", "nowUs": 0, "expect": {"osd": sim2.draw_hud()}})
sim2.toggle_fold("chrome")
steps.append({"op": "toggleFold", "section": "chrome", "nowUs": us(1.0)})
for i in range(5):  # 3 lines to reveal + flip + settle
    sim2.fold_tick("chrome")
    steps.append({"op": "foldTick", "section": "chrome", "nowUs": us(1.0 + (i + 1) * 0.04),
                  "expect": {"osd": sim2.draw_hud()}})
sim2.toggle_fold("chrome")
steps.append({"op": "toggleFold", "section": "chrome", "nowUs": us(2.0)})
for i in range(5):
    sim2.fold_tick("chrome")
    steps.append({"op": "foldTick", "section": "chrome", "nowUs": us(2.0 + (i + 1) * 0.04),
                  "expect": {"osd": sim2.draw_hud()}})
vectors.append({"name": "V3-fold-toggle-trajectory", "steps": steps})

# V4 sync-to-enabled: chrome was manually open; disabling closes it (animated),
# re-enabling opens it again.
sim = Sim()
steps = []
sim.photon_hud_state(**PHOTON_SDR); steps.append({"op": "photonHudState", "fields": PHOTON_SDR, "nowUs": 0})
sim.chrome_hud_state(**CHROME_FULL); steps.append({"op": "chromeHudState", "fields": CHROME_FULL, "nowUs": 0})
sim.enabled = True
steps.append({"op": "hudToggle", "nowUs": 0})
steps.append({"op": "draw", "nowUs": 0, "expect": {"osd": sim.draw_hud()}})
off = dict(CHROME_FULL, enabled_str="false")
sim.chrome_hud_state(**off)
steps.append({"op": "chromeHudState", "fields": off, "nowUs": us(1.0)})
steps.append({"op": "draw", "nowUs": us(1.0), "expect": {"osd": sim.draw_hud()}})
for i in range(5):
    sim.fold_tick("chrome")
    steps.append({"op": "foldTick", "section": "chrome", "nowUs": us(1.0 + (i + 1) * 0.04),
                  "expect": {"osd": sim.draw_hud()}})
sim.chrome_hud_state(**CHROME_FULL)
steps.append({"op": "chromeHudState", "fields": CHROME_FULL, "nowUs": us(2.0)})
steps.append({"op": "draw", "nowUs": us(2.0), "expect": {"osd": sim.draw_hud()}})
vectors.append({"name": "V4-sync-fold-to-enabled", "steps": steps})

# V5 grain measure status expiry: measured note shows within 12s, expires after.
sim = Sim()
steps = []
sim.photon_hud_state(**PHOTON_SDR); steps.append({"op": "photonHudState", "fields": PHOTON_SDR, "nowUs": 0})
sim.grain_hud_state(**GRAIN_FULL); steps.append({"op": "grainHudState", "fields": GRAIN_FULL, "nowUs": 0})
sim.enabled = True
steps.append({"op": "hudToggle", "nowUs": 0})
steps.append({"op": "draw", "nowUs": 0, "expect": {"osd": sim.draw_hud()}})
sim.set_grain_measure_status("blocks<6", 5.0)
steps.append({"op": "grainMeasureStatus", "value": "blocks<6", "nowUs": us(5.0)})
steps.append({"op": "draw", "nowUs": us(5.0), "expect": {"osd": sim.draw_hud()}})
sim.now = 17.5
steps.append({"op": "setNow", "nowUs": us(17.5)})
steps.append({"op": "draw", "nowUs": us(17.5), "expect": {"osd": sim.draw_hud()}})
sim.file_loaded()
steps.append({"op": "fileLoaded", "nowUs": us(18.0)})
sim.now = 18.0
steps.append({"op": "draw", "nowUs": us(18.0), "expect": {"osd": sim.draw_hud()}})
vectors.append({"name": "V5-grain-measure-expiry", "steps": steps})

# V6 photon SDR mode variants: radar / seek-miss / warming / live-calib.
sim = Sim()
steps = []
sim.enabled = True
steps.append({"op": "hudToggle", "nowUs": 0})
for i, variant in enumerate([
        dict(PHOTON_SDR),
        dict(PHOTON_SDR, radar_buffer_len_str="0"),
        dict(PHOTON_SDR, radar_buffer_len_str="0", radar_buffer_miss_str="true"),
        dict(PHOTON_SDR, is_live_str="true", live_calib_ready_str="true"),
        dict(PHOTON_SDR, is_live_str="true", live_calib_ready_str="false")]):
    sim.photon_hud_state(**variant)
    steps.append({"op": "photonHudState", "fields": variant, "nowUs": us(i * 0.25)})
    steps.append({"op": "draw", "nowUs": us(i * 0.25), "expect": {"osd": sim.draw_hud()}})
vectors.append({"name": "V6-photon-sdr-modes", "steps": steps})

# V7 bright section variants: als / camera-room_face / reading... / no feed.
sim = Sim()
steps = []
sim.photon_hud_state(**PHOTON_SDR); steps.append({"op": "photonHudState", "fields": PHOTON_SDR, "nowUs": 0})
sim.enabled = True
steps.append({"op": "hudToggle", "nowUs": 0})
variants = [
    dict(active=True, backlight=0.5, inertia_mode="ease", is_cut=True,
         ambient_level=None, ambient_window_open=True, ambient_source="als", ambient_lux=None),
    dict(active=True, backlight=None, inertia_mode="hold", is_cut=False,
         ambient_level=None, ambient_window_open=False, ambient_source="camera-room_face",
         ambient_face=0.4, ambient_room=0.7),
    dict(active=False, backlight=None, inertia_mode="n/a", is_cut=False,
         ambient_level=None, ambient_window_open=False, ambient_source="n/a"),
]
for i, v in enumerate(variants):
    sim.bright.update(v)
    steps.append({"op": "brightState", "fields": v, "nowUs": us(i * 0.25)})
    steps.append({"op": "draw", "nowUs": us(i * 0.25), "expect": {"osd": sim.draw_hud()}})
vectors.append({"name": "V7-bright-variants", "steps": steps})

# V8 no-state waiting draw + hud disabled nil draw.
sim = Sim()
steps = [{"op": "draw", "nowUs": 0, "expect": {"osd": sim.draw_hud()}}]  # None: disabled
sim.enabled = True
steps.append({"op": "hudToggle", "nowUs": 0})
steps.append({"op": "draw", "nowUs": 0, "expect": {"osd": sim.draw_hud()}})
vectors.append({"name": "V8-waiting-and-disabled", "steps": steps})

out = sys.argv[1] if len(sys.argv) > 1 else "hud-vectors.json"
with open(out, "w") as f:
    json.dump({"source": "photon-hud.lua v2.2.17 SHA256 0902f3b07901dbffb95ffeb056011e1a68e2144e14e380f65e1f23dd111c696d",
               "derivation": "formula-derived (no Lua interpreter on the Linux host); gor lane re-derives from authoritative Lua",
               "vectors": vectors}, f, indent=1, ensure_ascii=False)
print(f"wrote {out}: {len(vectors)} vectors, {sum(len(v['steps']) for v in vectors)} steps")
