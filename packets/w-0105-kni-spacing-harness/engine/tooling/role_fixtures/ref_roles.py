"""Reference geometric-class derivation for a source outline (written for this fixture set; ideas only, no engine code).
derive(outline, noise) -> dict. Thresholds are derived from `noise` (sigma in font units):
  noise = {"sigma": float, "origin": "measured"|"declared", "derivation": str}
Constants marked CONVENTION are conventions, not measurements.
"""
import math
import numpy as np
K_SIGMA = 3.0            # CONVENTION: 3-sigma decision multiplier
Q_SIGMA = 1/math.sqrt(12)  # declared floor: integer-coordinate quantisation (CFF integer charstrings)
EPS_T = 1e-3             # numerical, not a tolerance on geometry

def _pt(a): return np.array(a, float)

def seg_pts(c, i):
    n = len(c["nodes"]); p0 = _pt(c["nodes"][i]); p1 = _pt(c["nodes"][(i+1) % n]); s = c["segs"][i]
    if s[0] == "L": return p0, None, None, p1
    return p0, _pt(s[1]), _pt(s[2]), p1

def tangent_out(c, i):
    p0, c1, c2, p1 = seg_pts(c, i)
    if c1 is None: return p1-p0, np.linalg.norm(p1-p0)
    for q in (c1, c2, p1):
        d = q-p0
        if np.linalg.norm(d) > 1e-9: return d, np.linalg.norm(d)
    return p1-p0, np.linalg.norm(p1-p0)

def tangent_in(c, i):   # incoming at node i (end of segment i-1)
    n = len(c["nodes"]); p0, c1, c2, p1 = seg_pts(c, (i-1) % n)
    if c1 is None: return p1-p0, np.linalg.norm(p1-p0)
    for q in (c2, c1, p0):
        d = p1-q
        if np.linalg.norm(d) > 1e-9: return d, np.linalg.norm(d)
    return p1-p0, np.linalg.norm(p1-p0)

def turn_deg(din, dout):
    a = math.atan2(din[0]*dout[1]-din[1]*dout[0], din @ dout)
    return abs(math.degrees(a))

def measure_noise(outline):
    """Measured noise: robust spread of axis-aligned straight segments about the segment-wise median
    (needs >= 1 axis-aligned straight segment); otherwise declared floor only."""
    res = []
    for c in outline["contours"]:
        for i, s in enumerate(c["segs"]):
            if s[0] != "L": continue
            p0, _, _, p1 = seg_pts(c, i); d = p1-p0
            L = np.linalg.norm(d)
            if L < 50: continue
            for ax in (0, 1):
                if abs(d[1-ax]) < 0.02*L:        # CONVENTION: within ~1 degree of an axis counts as axis-aligned
                    res += [p0[1-ax]-p1[1-ax]]   # endpoint mismatch across an ideal axis-aligned line
    if len(res) >= 1:
        sig = float(np.sqrt(np.mean(np.square(res))/2))
        return {"sigma": max(sig, 0.0), "origin": "measured", "derivation": f"RMS endpoint mismatch of {len(res)} axis-aligned lines / sqrt2"}
    return {"sigma": 0.0, "origin": "declared", "derivation": "no axis-aligned lines to measure"}

def effective_sigma(noise):
    return math.sqrt(noise["sigma"]**2 + Q_SIGMA**2)

def derivative_roots(p0, c1, c2, p1, axis):
    a = 3*(c1[axis]-p0[axis]); b = 3*(c2[axis]-c1[axis]); c = 3*(p1[axis]-c2[axis])
    A = a-2*b+c; B = 2*(b-a); C = a
    if abs(A) < 1e-12:
        r = [] if abs(B) < 1e-12 else [-C/B]
    else:
        D = B*B-4*A*C
        r = [] if D < 0 else [(-B-math.sqrt(D))/(2*A), (-B+math.sqrt(D))/(2*A)]
    return [t for t in r if EPS_T < t < 1-EPS_T]

def inflection_roots(p0, c1, c2, p1):
    ts = np.linspace(0, 1, 2001)[:, None]
    d = 3*((1-ts)**2*(c1-p0)+2*(1-ts)*ts*(c2-c1)+ts**2*(p1-c2))
    dd = 6*((1-ts)*(c2-2*c1+p0)+ts*(p1-2*c2+c1))
    cr = d[:, 0]*dd[:, 1]-d[:, 1]*dd[:, 0]
    out = []
    for k in np.where(cr[:-1]*cr[1:] <= 0)[0]:
        if cr[k] == 0 and cr[k+1] == 0: continue
        den = cr[k]-cr[k+1]
        out.append(float(ts[k, 0]) if den == 0 else float(ts[k, 0]+(ts[k+1, 0]-ts[k, 0])*cr[k]/den))
    out = [t for t in out if EPS_T < t < 1-EPS_T]
    ded = []
    for t in sorted(out):
        if not ded or t-ded[-1] > 1e-3: ded.append(t)
    return ded

def chord_dev(p0, c1, c2, p1):
    ch = p1-p0; L = np.linalg.norm(ch)
    if L < 1e-9: return 0.0
    n = np.array([-ch[1], ch[0]])/L
    return max(abs((c1-p0) @ n), abs((c2-p0) @ n))

def derive(outline, noise=None):
    noise = noise or measure_noise(outline)
    sig = effective_sigma(noise)
    res = {"noise": noise, "contours": []}
    for c in outline["contours"]:
        n = len(c["nodes"]); nodes = []; interior = []; infl = []; flat = []
        # closure: end of last segment is node 0 by construction; gap test uses explicit 'closure_gap' if present
        for i in range(n):
            din, lin = tangent_in(c, i); dout, lout = tangent_out(c, i)
            L = max(min(lin, lout), 1e-9)
            # turn-angle noise: both tangents carry sigma/L error: sigma_turn = sqrt(2)*sigma*sqrt(1/lin^2 + 1/lout^2)
            s_turn = math.sqrt(2)*sig*math.sqrt(1/max(lin, 1e-9)**2 + 1/max(lout, 1e-9)**2)
            tau = K_SIGMA*math.degrees(math.atan(s_turn))
            t = turn_deg(din, dout)
            gclass = "corner" if t > tau else "seam"
            curved_adjacent = c["segs"][i][0] == "C" or c["segs"][(i-1) % n][0] == "C"
            if gclass == "seam" and curved_adjacent:
                p0 = _pt(c["nodes"][i])
                for ax in (0, 1):
                    other = 1-ax
                    # tangent (smooth, averaged) parallel to the axis => derivative of the other coordinate ~ 0
                    d = din/np.linalg.norm(din)+dout/np.linalg.norm(dout)
                    if abs(d[ax]) < math.sin(math.radians(tau))*np.linalg.norm(d) and abs(d[other]) > 0:
                        gclass = "extremum"; break
            nodes.append({"node": i, "geometric_class": gclass, "status": "proposed", "source": "measured", "turn_deg": t, "tau_deg": tau})
        for i, s in enumerate(c["segs"]):
            p0, c1, c2, p1 = seg_pts(c, i)
            if c1 is None:
                d = p1-p0; L = np.linalg.norm(d)
                for ax in (0, 1):
                    if L > 0 and abs(d[1-ax])/L < math.sin(math.radians(K_SIGMA*math.degrees(math.atan2(math.sqrt(2)*sig, L)))):
                        flat.append({"seg": i, "axis": "h" if ax == 0 else "v", "pos": float((p0[1-ax]+p1[1-ax])/2)})
                continue
            dev = chord_dev(p0, c1, c2, p1)
            if dev < K_SIGMA*sig:
                d = p1-p0; L = np.linalg.norm(d)
                for ax in (0, 1):
                    if L > 0 and abs(d[1-ax])/L < math.sin(math.radians(K_SIGMA*math.degrees(math.atan2(math.sqrt(2)*sig, L)))):
                        flat.append({"seg": i, "axis": "h" if ax == 0 else "v", "pos": float((p0[1-ax]+p1[1-ax])/2)})
                continue   # straight within noise: no extrema/inflection
            for ax, name in ((0, "x"), (1, "y")):
                for t in derivative_roots(p0, c1, c2, p1, ax):
                    pt = bez(p0, c1, c2, p1, t)
                    # the extremum position moves by about sqrt(2*R*sigma) along the curve for a perpendicular error sigma
                    # (R = radius of curvature there), so the node-at-extremum distance threshold is derived from R and sigma
                    d1 = 3*((1-t)**2*(c1-p0)+2*(1-t)*t*(c2-c1)+t*t*(p1-c2)); d2 = 6*((1-t)*(c2-2*c1+p0)+t*(p1-2*c2+c1))
                    kap = abs(d1[0]*d2[1]-d1[1]*d2[0])/max(np.linalg.norm(d1), 1e-9)**3
                    Rr = 1.0/max(kap, 1e-4)
                    thr = K_SIGMA*(sig+math.sqrt(2*Rr*sig))
                    if np.linalg.norm(pt-p0) > thr and np.linalg.norm(pt-p1) > thr:
                        interior.append({"seg": i, "axis": name, "t": t})
            for t in inflection_roots(p0, c1, c2, p1):
                infl.append({"seg": i, "t": t})
        res["contours"].append({"nodes": nodes, "interior_extrema": interior, "inflections": infl, "flat": flat})
    return res

def bez(p0, c1, c2, p1, t):
    return (1-t)**3*p0+3*(1-t)**2*t*c1+3*(1-t)*t**2*c2+t**3*p1

def closure_ok(gap, noise):
    """Closed if the end-to-start gap is within K_SIGMA * sqrt(2) * sigma_eff (two noisy endpoints)."""
    return gap <= K_SIGMA*math.sqrt(2)*effective_sigma(noise)
