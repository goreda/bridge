"""191a C1/C5: end-to-end pose sign-convention reference, written during the
2026-11-09 audit triggered by the owner's report (phonemsg-01M70RPX610GYR2Y53DTTAC6TT:
"saga bakinca sola, sola bakinca saga kaydiriyor" - looking right shifted the
picture LEFT, "everything reversed").

INTENDED SEMANTIC (window / content-follows-head, from the owner's words):
the picture content moves WITH the head's motion. Look right -> content shifts
right; look down -> content down; move head right -> content right (window
parallax reveals the left side); move up -> content up; tilt head left ->
picture top tips left (world-fixed horizon, owner-approved 2026-11-05);
lean in -> content grows (approaching); closer -> more convergence nudge.

CHAIN MIRRORED HERE (signs read LIVE from the Swift source, not restated):
  physical action
    -> Vision raw (Apple header conventions, upright UNMIRRORED buffer:
       yaw/roll positive = counterclockwise, pitch positive = nodding DOWN;
       the mirrored preview never reaches Vision, no mirror compensation)
    -> HeadTracker sign constants (ScreenCaptureEngine.swift yawSign/pitchSign/
       rollSign/xOffsetSign/yOffsetSign)
    -> applyHeadPose gains (PPController_Features.swift)
    -> vr180-look-set-orientation uniforms (vr180-look.lua)
    -> shader math (sphere path: roll->pitch->yaw ray rotation, head_offset
       parallax; flat path: uv += flat_roll_offset(...))
    -> screen-space content direction.

AUDIT RESULT: yaw, pitch and x were INVERTED (sign constants were unverified
guesses, "flip if it looks wrong" comment; never run against the camera until
the owner's report). roll (+1) and y (+1) were already correct; z direction
(lean in -> fov decreases -> content grows; convergence nudge increases) is
consistent with approach and uncomplained - unchanged.

FLAT PACK ALIGNMENT: the flat projection paths pre-812702cb disagreed with
the sphere path on pitch and head_x (reported to Main as a region-patch
proposal; E-G landed the fix in 812702cb): the flat uv offset now reads
vec2(vr_yaw,vr_pitch)/1.5707963 + vec2(-vr_head_x,vr_head_y)*0.5, and all
modes agree per channel (asserted by the test; manual pitch keeps its own
- sign convention, gesture-side, unchanged).
"""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
import math
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SWIFT = _s3read(ROOT / "Sources/gor/GorCaptureModel/ScreenCaptureEngine.swift")


def _swift_const(name, src):
    m = re.search(r"static let %s:\s*Double = ([-\d.]+)" % name, src)
    if not m:
        raise AssertionError("constant %s not found in ScreenCaptureEngine.swift" % name)
    return float(m.group(1))


YAW_SIGN = _swift_const("yawSign", SWIFT)
PITCH_SIGN = _swift_const("pitchSign", SWIFT)
ROLL_SIGN = _swift_const("rollSign", SWIFT)
X_SIGN = _swift_const("xOffsetSign", SWIFT)
Y_SIGN = _swift_const("yOffsetSign", SWIFT)

# PPController_Features.swift applyHeadPose gains (pinned by text in the test)
HEAD_ROTATION_GAIN = 1.0
HEAD_TRANSLATE_M_PER_UNIT = 0.20
HEAD_Z_TRANSLATE_SIGN = -1.0
REST_FOV_DEG = 135.0
LEAN_FOV_DEG_PER_UNIT = -150.0
IPD_NUDGE_PER_UNIT = 0.12
DEAD_ZONE_RAD = 0.004


def soft_dead_zone(x):
    m = max(0.0, abs(x) - DEAD_ZONE_RAD)
    return -m if x < 0 else m


def vision_raw(action, amount=0.35):
    """Apple-convention raw Vision values for a canonical physical action
    (upright, unmirrored buffer). yaw/roll: +CCW; pitch: + nod down.
    Box offsets: normalized, origin bottom-left (y up)."""
    a = amount
    table = {
        "look right": (-a, 0.0, 0.0, 0.0, 0.0, 0.0),   # nose sweeps CW from above
        "look left": (a, 0.0, 0.0, 0.0, 0.0, 0.0),
        "look down": (0.0, a, 0.0, 0.0, 0.0, 0.0),     # pitch + = nod down
        "look up": (0.0, -a, 0.0, 0.0, 0.0, 0.0),
        "tilt left": (0.0, 0.0, -a, 0.0, 0.0, 0.0),    # user's left = CW in image
        "move right": (0.0, 0.0, 0.0, -0.5, 0.0, 0.0),  # face toward image left
        "move up": (0.0, 0.0, 0.0, 0.0, 0.5, 0.0),     # y up from bottom-left
        "lean in": (0.0, 0.0, 0.0, 0.0, 0.0, 0.5),     # box grows
    }
    return table[action]


def chain(action, signs=None):
    """Full Swift->Lua chain; returns the shader uniforms for an action.
    signs overrides the (yaw, pitch, roll, x, y) sign constants (mutant tests)."""
    ys, ps_, rs, xs, yos = signs or (YAW_SIGN, PITCH_SIGN, ROLL_SIGN, X_SIGN, Y_SIGN)
    yaw, pitch, roll, x, y, z = vision_raw(action)
    p_yaw = soft_dead_zone(HEAD_ROTATION_GAIN * ys * yaw)
    p_pitch = soft_dead_zone(HEAD_ROTATION_GAIN * ps_ * pitch)
    p_roll = soft_dead_zone(HEAD_ROTATION_GAIN * rs * roll)
    fov = REST_FOV_DEG + LEAN_FOV_DEG_PER_UNIT * z
    head_x = HEAD_TRANSLATE_M_PER_UNIT * xs * x
    head_y = HEAD_TRANSLATE_M_PER_UNIT * yos * y
    head_z = HEAD_Z_TRANSLATE_SIGN * HEAD_TRANSLATE_M_PER_UNIT * z
    ipd = IPD_NUDGE_PER_UNIT * z
    return dict(vr_yaw=p_yaw, vr_pitch=p_pitch, vr_roll=p_roll, vr_fov=fov,
                vr_head_x=head_x, vr_head_y=head_y, vr_head_z=head_z, ipd_nudge=ipd)


def sphere_screen_effect(u):
    """Content motion on screen for the sphere path (vr180-look.lua):
    content_dx > 0 = content moved RIGHT; content_dy > 0 = content moved DOWN
    (screen coords, y down); picture_roll > 0 = top tips RIGHT (CW);
    magnification > 1 = content grew."""
    cy, sy = math.cos(u["vr_yaw"]), math.sin(u["vr_yaw"])
    cp, sp = math.cos(u["vr_pitch"]), math.sin(u["vr_pitch"])
    # center ray (0,0,1) through roll (no-op), pitch, yaw:
    ray = (sy, -sp * cy, cp * cy)
    hx, hy = u["vr_head_x"], u["vr_head_y"]
    R = 2.0  # SPHERE_RADIUS_METERS value is irrelevant for direction
    hit = (ray[0] * R - hx, ray[1] * R - hy, ray[2] * R - u["vr_head_z"])
    n = math.sqrt(sum(c * c for c in hit))
    ray = (hit[0] / n, hit[1] / n, hit[2] / n)
    theta = math.atan2(ray[0], ray[2])          # sampled longitude
    phi = math.asin(max(-1.0, min(1.0, ray[1])))  # sampled latitude
    # sampling +theta means right-side content comes to center -> content moved LEFT
    content_dx = -theta
    # v = 0.5 - phi/pi; sampling v>0.5 (below) pulls content UP (dy negative)
    content_dy = phi
    picture_roll = u["vr_roll"]   # +vr_roll -> picture CW (top tips right)
    mag = math.tan(math.radians(REST_FOV_DEG / 2)) / math.tan(math.radians(u["vr_fov"] / 2))
    return dict(content_dx=content_dx, content_dy=content_dy,
                picture_roll=picture_roll, magnification=mag, ipd_nudge=u["ipd_nudge"])


def flat_screen_effect(u):
    """Content motion for the FLAT projection path (uv offset, post-812702cb
    form). Same sign conventions as sphere_screen_effect."""
    dx = -(u["vr_yaw"] / (math.pi / 2) - 0.5 * u["vr_head_x"])
    dy = -(u["vr_pitch"] / (math.pi / 2) + 0.5 * u["vr_head_y"])
    # flat_roll_offset rotates the offset by -roll (numeric CCW = visually CW with v down)
    return dict(content_dx=dx, content_dy=dy, picture_roll=u["vr_roll"],
                magnification=1.0, ipd_nudge=u["ipd_nudge"])


def trace_rows():
    """Deterministic per-channel trace: action -> raw -> uniforms -> effect."""
    import json
    rows = []
    for action in ("look right", "look left", "look down", "look up",
                   "tilt left", "move right", "move up", "lean in"):
        raw = vision_raw(action)
        uni = chain(action)
        eff = sphere_screen_effect(uni)
        rows.append(json.dumps({
            "action": action, "vision_raw": [round(v, 5) for v in raw],
            "uniforms": {k: round(v, 6) for k, v in uni.items()},
            "sphere": {k: round(v, 6) if isinstance(v, float) else v for k, v in eff.items()},
        }, sort_keys=True))
    return rows
