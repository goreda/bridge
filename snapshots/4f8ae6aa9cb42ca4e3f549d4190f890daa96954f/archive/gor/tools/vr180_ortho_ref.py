#!/usr/bin/env python3
"""Reference geometry for 190t block G (VR180 orthoscopic, no stretch). The Metal kernel must reproduce these numbers.
Frame: pinhole camera, width W px, height H px, horizontal FoV theta_h (rad), square pixels, f = (W/2)/tan(theta_h/2).
Equirect 180 eye image: u in [0,1] -> lon = (u-0.5)*pi, v in [0,1] -> lat = (0.5-v)*pi. Ray d = (cos lat sin lon, sin lat, cos lat cos lon).
Film is not levelled or stretched: it occupies exactly theta_h about yaw 0 pitch 0, black outside."""
import math

def focal(w, theta_h): return (w / 2.0) / math.tan(theta_h / 2.0)

def ray(u, v):
    lon, lat = (u - 0.5) * math.pi, (0.5 - v) * math.pi
    return (math.cos(lat) * math.sin(lon), math.sin(lat), math.cos(lat) * math.cos(lon))

def equirect_to_frame(u, v, w, h, theta_h):
    """Mono VR180: equirect pixel -> frame pixel (x, y) or None when outside the film (black)."""
    dx, dy, dz = ray(u, v)
    if dz <= 1e-9: return None
    f = focal(w, theta_h)
    x, y = f * dx / dz + w / 2.0, h / 2.0 - f * dy / dz
    return (x, y) if 0.0 <= x <= w and 0.0 <= y <= h else None

def frame_to_equirect(x, y, w, h, theta_h, depth=None, eye=0.0):
    """Stereo: unproject frame pixel with metric depth z (metres along the optical axis, None = infinity), view from an eye
    centre displaced by `eye` metres along +x (left eye -0.032, right +0.032 for 63 mm IPD). Returns (u, v)."""
    f = focal(w, theta_h)
    rx, ry = (x - w / 2.0) / f, (h / 2.0 - y) / f           # ray through the pixel at z = 1
    if depth is None: px, py, pz = rx, ry, 1.0              # at infinity the eye offset is zero
    else: px, py, pz = rx * depth - eye, ry * depth, depth
    n = math.sqrt(px * px + py * py + pz * pz)
    lon, lat = math.atan2(px, pz), math.asin(py / n)
    return (lon / math.pi + 0.5, 0.5 - lat / math.pi)

def disparity_px(x, y, w, h, theta_h, depth, out_w, ipd=0.063):
    """Horizontal disparity in output pixels between right and left eye for one source pixel."""
    ul, _ = frame_to_equirect(x, y, w, h, theta_h, depth, -ipd / 2)
    ur, _ = frame_to_equirect(x, y, w, h, theta_h, depth, +ipd / 2)
    return (ul - ur) * out_w  # positive = crossed (nearer than screen) convention: left-eye image sits right of right-eye image
