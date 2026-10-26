"""Synthetic ground-truth outlines for source-outline geometric-class derivation.
Units: font units (UPM 1000). Contour = list of nodes; seg i joins node i -> node i+1 (closed).
seg = ('L',) or ('C', c1, c2).  Truth is stored with the fixture, never read by the derivation code.
Guides (declared test values, not engine constants): baseline 0, xheight 500, cap 700, overshoot +10/-10.
"""
import json, math, sys
import numpy as np
GUIDES = {"baseline": 0.0, "xheight": 500.0, "cap": 700.0, "xheight_over": 510.0, "baseline_over": -10.0}
KAPPA = 0.5522847498307936

def bez(p0, c1, c2, p1, t):
    t = np.asarray(t, float)[..., None]
    return (1-t)**3*p0 + 3*(1-t)**2*t*c1 + 3*(1-t)*t**2*c2 + t**3*p1

def split(p0, c1, c2, p1, t=0.5):
    a = p0+(c1-p0)*t; b = c1+(c2-c1)*t; c = c2+(p1-c2)*t
    d = a+(b-a)*t; e = b+(c-b)*t; f = d+(e-d)*t
    return (p0, a, d, f), (f, e, c, p1)

def contour(nodes, segs, classes=None):
    return {"nodes": [list(map(float, n)) for n in nodes],
            "segs": [[s[0]] + [list(map(float, x)) for x in s[1:]] for s in segs],
            "geometric_classes": classes or []}

def ellipse(cx, cy, rx, ry, rot_nodes=False):
    # nodes at extrema (right, top, left, bottom), counter-clockwise
    P = [(cx+rx, cy), (cx, cy+ry), (cx-rx, cy), (cx, cy-ry)]
    segs = []
    for i in range(4):
        p0 = np.array(P[i]); p1 = np.array(P[(i+1) % 4])
        d0 = np.array([0, 1]) if i % 2 == 0 else np.array([-1, 0])
        d0 = {0: (0, ry), 1: (-rx, 0), 2: (0, -ry), 3: (rx, 0)}[i]
        d1 = {0: (rx, 0), 1: (0, ry), 2: (-rx, 0), 3: (0, -ry)}[i]
        c1 = p0 + KAPPA*np.array(d0); c2 = p1 + KAPPA*np.array(d1)
        segs.append(("C", c1, c2))
    classes = [{"node": i, "geometric_class": "extremum", "turn_deg": 0.0} for i in range(4)]
    return P, segs, classes

def fixtures():
    F = {}
    # F1 rectangle, flat edges on baseline and cap, four 90 degree corners
    n = [(100, 0), (500, 0), (500, 700), (100, 700)]
    c = contour(n, [("L",)]*4, [{"node": i, "geometric_class": "corner", "turn_deg": 90.0} for i in range(4)])
    c["flat"] = [{"seg": 0, "class": "baseline", "y": 0.0}, {"seg": 2, "class": "cap", "y": 700.0}]
    F["rect"] = {"contours": [c]}
    # F2 ellipse with nodes at extrema; top at x-height overshoot, bottom at baseline overshoot
    P, segs, classes = ellipse(300, 250, 260, 260)  # top = 510, bottom = -10
    c = contour(P, segs, classes); c["flat"] = []
    F["ellipse_ext"] = {"contours": [c]}
    # F3 ellipse whose nodes sit at 45-degree points: extrema are interior to segments (missing extrema)
    th = [math.pi/4 + k*math.pi/2 for k in range(4)]
    cx, cy, rx, ry = 300, 250, 260, 260
    pts = [np.array([cx+rx*math.cos(a), cy+ry*math.sin(a)]) for a in th]
    segs = []
    for i in range(4):
        a0, a1 = th[i], th[i]+math.pi/2
        k = 4/3*math.tan((a1-a0)/4)
        t0 = np.array([-rx*math.sin(a0), ry*math.cos(a0)]); t1 = np.array([-rx*math.sin(a1), ry*math.cos(a1)])
        segs.append(("C", pts[i]+k*t0, pts[(i+1) % 4]-k*t1))
    c = contour(pts, segs, [{"node": i, "geometric_class": "seam", "turn_deg": 0.0} for i in range(4)])
    c["interior_extrema"] = [{"seg": i, "axis": ("y" if i % 2 == 0 else "x"), "t": 0.5} for i in range(4)]
    c["flat"] = []
    F["ellipse_noext"] = {"contours": [c]}
    # F4 collinear and G1 seam nodes: a line split in two, a cubic split at t=0.5
    p = [np.array(v, float) for v in [(0, 0), (300, 0), (300, 400), (0, 400)]]
    nodes = [p[0], (150, 0), p[1], p[2], p[3]]
    segs = [("L",), ("L",), ("L",), ("L",), ("L",)]
    classes = [{"node": 0, "geometric_class": "corner", "turn_deg": 90.0}, {"node": 1, "geometric_class": "seam", "turn_deg": 0.0},
             {"node": 2, "geometric_class": "corner", "turn_deg": 90.0}, {"node": 3, "geometric_class": "corner", "turn_deg": 90.0},
             {"node": 4, "geometric_class": "corner", "turn_deg": 90.0}]
    c = contour(nodes, segs, classes); c["flat"] = [{"seg": 0, "class": "baseline", "y": 0.0}, {"seg": 1, "class": "baseline", "y": 0.0}]
    F["line_seam"] = {"contours": [c]}
    # F5 cubic arch split at t=0.5 (G1 seam, not an extremum node) with a flat base
    a0, a1, a2, a3 = np.array([0, 0.]), np.array([0, 500.]), np.array([400, 500.]), np.array([400, 0.])
    (l0, l1, l2, l3), (r0, r1, r2, r3) = split(a0, a1, a2, a3, 0.5)
    nodes = [l0, l3, r3]
    segs = [("C", l1, l2), ("C", r1, r2), ("L",)]
    classes = [{"node": 0, "geometric_class": "corner", "turn_deg": 90.0}, {"node": 1, "geometric_class": "extremum", "turn_deg": 0.0},
             {"node": 2, "geometric_class": "corner", "turn_deg": 90.0}]
    c = contour(nodes, segs, classes); c["flat"] = [{"seg": 2, "class": "baseline", "y": 0.0}]
    F["arch_split"] = {"contours": [c]}
    # F6 S-curve: one cubic with an inflection (t where cross(B',B'')=0), closed by a straight return
    s0, s1, s2, s3 = np.array([0, 0.]), np.array([300, 0.]), np.array([60, 380.]), np.array([300, 420.])
    nodes = [s0, s3, (300, 460), (0, 460)]
    segs = [("C", s1, s2), ("L",), ("L",), ("L",)]
    ts = np.linspace(0, 1, 100001)
    d1 = 3*((1-ts)[:, None]**2*(s1-s0) + 2*((1-ts)*ts)[:, None]*(s2-s1) + (ts**2)[:, None]*(s3-s2))
    d2 = 6*((1-ts)[:, None]*(s2-2*s1+s0) + ts[:, None]*(s3-2*s2+s1))
    cr = d1[:, 0]*d2[:, 1]-d1[:, 1]*d2[:, 0]
    idx = np.where(cr[:-1]*cr[1:] <= 0)[0]
    ti = ts[idx[(ts[idx] > 1e-6) & (ts[idx] < 1-1e-6)]]
    ti = ti[np.concatenate([[True], np.diff(ti) > 1e-4])]
    assert len(ti) >= 1
    c = contour(nodes, segs, [])
    c["inflections"] = [{"seg": 0, "t": float(t)} for t in ti]
    c["flat"] = []; c["geometric_classes"] = []
    F["s_curve"] = {"contours": [c]}
    # F7 rounded rectangle: flat edges at baseline and cap joined by smooth corner arcs
    r = 80.0; w = 400.0; h = 700.0
    nodes = [(r, 0), (w-r, 0), (w, r), (w, h-r), (w-r, h), (r, h), (0, h-r), (0, r)]
    segs = [("L",), ("C", (w-r+KAPPA*r, 0), (w, r-KAPPA*r)), ("L",), ("C", (w, h-r+KAPPA*r), (w-r+KAPPA*r, h)), ("L",),
            ("C", (r-KAPPA*r, h), (0, h-r+KAPPA*r)), ("L",), ("C", (0, r-KAPPA*r), (r-KAPPA*r, 0))]
    segs[1] = ("C", (w-r+KAPPA*r, 0), (w, r-KAPPA*r)); segs[3] = ("C", (w, h-r+KAPPA*r), (w-r+KAPPA*r, h))
    segs[5] = ("C", (r-KAPPA*r, h), (0, h-r+KAPPA*r)); segs[7] = ("C", (0, r-KAPPA*r), (r-KAPPA*r, 0))
    classes = [{"node": i, "geometric_class": "extremum", "turn_deg": 0.0} for i in range(8)]
    c = contour(nodes, segs, classes)
    c["flat"] = [{"seg": 0, "class": "baseline", "y": 0.0}, {"seg": 4, "class": "cap", "y": 700.0}]
    c["interior_extrema"] = []
    F["round_rect"] = {"contours": [c]}
    # F8 corner-angle ladder: isosceles wedges, one corner of known turn angle each (apex), others 90+ degree
    for turn in [1, 2, 3, 5, 8, 12, 20, 30, 45, 90, 135, 170]:
        a = math.radians(turn)   # exterior turn at the apex = turn
        L = 300.0
        apex = np.array([0.0, 0.0])
        # build a polyline in -> apex -> out with exterior turn 'turn' at apex, long legs
        pin = np.array([-L, 0.0]); pout = L*np.array([math.cos(a), math.sin(a)])
        far = np.array([0.0, -400.0])
        nodes = [pin, apex, pout, far]
        c = contour(nodes, [("L",)]*4, [{"node": 1, "geometric_class": "corner" if turn > 0 else "smooth", "turn_deg": float(turn)}])
        c["flat"] = []; F[f"wedge_{turn:03d}"] = {"contours": [c]}
    return F

def add_flat_truth(F):
    for name, fx in F.items():
        for c in fx["contours"]:
            n = len(c["nodes"]); fl = []
            for i, s in enumerate(c["segs"]):
                if s[0] != "L": continue
                p0 = np.array(c["nodes"][i]); p1 = np.array(c["nodes"][(i+1) % n])
                if abs(p0[1]-p1[1]) < 1e-9 and abs(p1[0]-p0[0]) >= 50:
                    cl = next((k for k, v in GUIDES.items() if abs(v-p0[1]) < 1e-9), "none")
                    fl.append({"seg": i, "class": cl, "y": float(p0[1])})
            c["flat"] = fl
    return F

def perturb(fx, sigma, rng, rounding):
    out = json.loads(json.dumps(fx))
    for c in out["contours"]:
        c["nodes"] = [[v + (rng.normal(0, sigma) if sigma else 0) for v in n] for n in c["nodes"]]
        for s in c["segs"]:
            for j in range(1, len(s)):
                s[j] = [v + (rng.normal(0, sigma) if sigma else 0) for v in s[j]]
        if rounding:
            c["nodes"] = [[round(v) for v in n] for n in c["nodes"]]
            for s in c["segs"]:
                for j in range(1, len(s)):
                    s[j] = [round(v) for v in s[j]]
    return out

if __name__ == "__main__":
    import os
    os.makedirs("fixtures", exist_ok=True)
    F = add_flat_truth(fixtures())
    with open("truth.tsv", "w") as t:
        t.write("fixture\tcontour\tkind\tindex\tvalue\tdetail\n")
        for name, fx in F.items():
            json.dump(fx, open(f"fixtures/{name}.json", "w"))
            for ci, c in enumerate(fx["contours"]):
                for r in c["geometric_classes"]:
                    t.write(f"{name}\t{ci}\tnode_geometric_class\t{r['node']}\t{r['geometric_class']}\tturn_deg={r['turn_deg']}\n")
                for e in c.get("interior_extrema", []):
                    t.write(f"{name}\t{ci}\tinterior_extremum\t{e['seg']}\t{e['t']}\taxis={e['axis']}\n")
                for e in c.get("inflections", []):
                    t.write(f"{name}\t{ci}\tinflection\t{e['seg']}\t{e['t']:.6f}\t\n")
                for e in c.get("flat", []):
                    t.write(f"{name}\t{ci}\tflat_edge\t{e['seg']}\t{e['y']}\tclass={e['class']}\n")
    print(len(F), "fixtures")
