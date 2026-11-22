"""191a C1: pose from Vision landmarks. Reference implementation + spec.

MOTIVATION: the blink-shared VNFaceLandmarks request's face observation lacks
pitch on this macOS (Tests/HeadTrackVisionOnce), so the shared handler cannot
supply pose angles - pose today depends on the separate face-rectangle
request's yaw/pitch/roll being non-nil. This module derives all six channels
from the landmarks the blink path ALREADY receives (no extra Vision request),
as (a) a fallback when the rectangle angles are nil and (b) a cross-check
channel for the rectangle angles.

CONVENTIONS (load-bearing): the output channels use the EXACT same semantics
as the Vision raw values in the audited chain (tools/head_pose/pose_signs.py),
so the SAME Swift sign constants (yawSign/pitchSign/rollSign/xOffsetSign/
yOffsetSign) apply unchanged and the pose filter (pose_filter.py) is agnostic
to the source:
  yaw   + = counterclockwise seen from above (user turns LEFT)   [Apple]
  pitch + = nodding DOWN                                          [Apple]
  roll  + = counterclockwise in the upright unmirrored image      [Apple]
  x, y  = face-center minus neutral, normalized, origin bottom-left (y up)
  z     = (iod - iod_ref)/iod_ref, iod = inter-ocular distance (box-width
          offset semantics: fraction larger than neutral)

MATH (image space: x right, y up, upright unmirrored buffer; anatomical left
eye appears at image RIGHT - the Swift side pins "Named leftEye/rightEye stay
anatomical"):
  cL, cR   centroids of the 6-point leftEye/rightEye contours
  d        = cL - cR (upright: d.x > 0); iod = |d|
  roll     = atan2(d.y, d.x)                      (exact under pure roll)
  mid      = (cL + cR)/2; x = mid.x - ref.x, y = mid.y - ref.y
  u        = d/iod (anatomical right->left unit); v = (-u.y, u.x) (toward crown)
  lat      = dot(nose - mid, u)                   (lateral nose shift)
  nose_dn  = dot(mid - nose, v)                   (down-along-face nose extent)
  yaw      = atan2(lat, NOSE_DEPTH_RATIO * iod)   (look right -> negative)
  pitch    = atan2(nose_dn - nose_dn_ref, NOSE_DEPTH_RATIO * iod)  (nod down -> +)
Neutral calibration (iod_ref, nose_dn_ref, ref center) rides the existing
recenter mechanism, exactly like neutralAngles/refCenter for the box path.

NOSE_DEPTH_RATIO is a face-proportions PRIOR (nose protrusion ~ 0.45 x iod,
typical adult range 0.40-0.55): it scales angle magnitudes, never their signs.
Validated on a synthetic 3D head in Tests/HeadPose/test_landmark_pose.py
(signs exact, magnitudes within 3 deg at +-20 deg yaw / +-15 deg pitch / +-45
roll; roll exact for pure roll). Orthographic projection is assumed (webcam
distances); non-square pixels would need an aspect correction the current
box-based x/y also lacks - documented, not handled.
"""
import math

NOSE_DEPTH_RATIO = 0.45


def estimate(left_eye, right_eye, nose_pts, iod_ref, nose_dn_ref, ref_center):
    """left_eye/right_eye: 6 (x,y) contour points (anatomical naming).
    nose_pts: nose contour points or None (yaw/pitch unavailable then).
    Returns dict(roll, x, y, z, yaw|None, pitch|None) in Vision conventions,
    or None when the eye line is degenerate."""
    if len(left_eye) < 2 or len(right_eye) < 2:
        return None
    cL = _centroid(left_eye)
    cR = _centroid(right_eye)
    d = (cL[0] - cR[0], cL[1] - cR[1])
    iod = math.hypot(*d)
    if iod < 1e-6:
        return None
    roll = math.atan2(d[1], d[0])
    mid = ((cL[0] + cR[0]) / 2, (cL[1] + cR[1]) / 2)
    x = mid[0] - ref_center[0]
    y = mid[1] - ref_center[1]
    z = (iod - iod_ref) / iod_ref
    yaw = pitch = None
    if nose_pts:
        n = _centroid(nose_pts)
        u = (d[0] / iod, d[1] / iod)
        v = (-u[1], u[0])
        nm = (n[0] - mid[0], n[1] - mid[1])
        lat = nm[0] * u[0] + nm[1] * u[1]
        nose_dn = -(nm[0] * v[0] + nm[1] * v[1])
        yaw = math.atan2(lat, NOSE_DEPTH_RATIO * iod)
        pitch = math.atan2(nose_dn - nose_dn_ref, NOSE_DEPTH_RATIO * iod)
    return dict(roll=roll, x=x, y=y, z=z, yaw=yaw, pitch=pitch)


def _centroid(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def calibrate(left_eye, right_eye, nose_pts, ref_center):
    """Neutral-frame capture (the recenter moment): returns
    (iod_ref, nose_dn_ref)."""
    cL = _centroid(left_eye)
    cR = _centroid(right_eye)
    d = (cL[0] - cR[0], cL[1] - cR[1])
    iod = math.hypot(*d)
    mid = ((cL[0] + cR[0]) / 2, (cL[1] + cR[1]) / 2)
    n = _centroid(nose_pts)
    u = (d[0] / iod, d[1] / iod)
    v = (-u[1], u[0])
    nm = (n[0] - mid[0], n[1] - mid[1])
    return iod, -(nm[0] * v[0] + nm[1] * v[1])
