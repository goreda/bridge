"""Distortion audit for the reference render (contract s20).

Two measurements, both pinned by Tests/DepthAnalysis/test_cg_vr180_golden.py:

1. Footprint stretch: the (x,y) -> (lon,lat) map (gnomonic source plane
   to equirect canvas) is angle-true only at the centre. We compute the
   Jacobian singular-value ratio (anisotropy) and area magnification at
   the footprint centre, horizontal edge, vertical edge and corner for
   the Mac-default screen (75 deg) on the CG entry geometry (16:9,
   theta_h 75 deg). ipd/depth do not change the MAP shape (eye offset
   translates lon only), so the audit runs at ipd=0.

2. Soft-surround seam: render a CG frame with surround off vs soft.
   Surround pixels are the diff mask. The seam ring = surround pixels
   4-connected to the film footprint. Each seam pixel is compared with
   its nearest footprint pixel along its row: soft fill is a 5x5 mean of
   edge-clamped taps, so seam delta should be small. Pole smear (columns
   of near-constant colour above/below the footprint) must exist ONLY
   outside the footprint - it is the documented surround behaviour, not
   a defect; we assert the footprint interior has no such columns.
"""
import json
import math
import os

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
GOLD = os.path.join(HERE, "golden", "entry_cg_vr180")


def map_metrics(w, h, theta_h):
    """Jacobian anisotropy + area ratio of the (x,y)->(lon,lat) map."""
    f = (w / 2.0) / math.tan(theta_h / 2.0)

    def lonlat(x, y):
        rx, ry = (x + 0.5 - w / 2.0) / f, (h / 2.0 - (y + 0.5)) / f
        z = 1.0
        n = math.sqrt(rx * rx * z * z + ry * ry * z * z + z * z)
        return math.atan2(rx * z, z), math.asin(ry * z / n)

    def j_at(x, y):
        e = 0.25
        l0, b0 = lonlat(x - e, y), lonlat(x, y - e)
        l1, b1 = lonlat(x + e, y), lonlat(x, y + e)
        j = np.array([[(l1[0] - l0[0]) / (2 * e), (b1[0] - b0[0]) / (2 * e)],
                      [(l1[1] - l0[1]) / (2 * e), (b1[1] - b0[1]) / (2 * e)]])
        sv = np.linalg.svd(j, compute_uv=False)
        return float(sv[0] / sv[1]), float(abs(np.linalg.det(j)))

    pts = {"centre": (w / 2, h / 2),
           "h_edge": (w - 1.0, h / 2),
           "v_edge": (w / 2, h - 1.0),
           "corner": (w - 1.0, h - 1.0)}
    out = {}
    for name, (x, y) in pts.items():
        aniso, area = j_at(x, y)
        out[name] = {"anisotropy": round(aniso, 4),
                     "area_ratio": round(area, 6)}
    c = out["centre"]["area_ratio"]
    for name in out:
        out[name]["area_vs_centre"] = round(out[name]["area_ratio"] / c, 4)
    return out


def seam_metrics(entry_dir):
    import sys
    sys.path.insert(0, HERE)
    from reference_render import render_shot_sbs
    sbs_soft, info = render_shot_sbs(entry_dir, 0, max_frames=1,
                                     surround="soft")
    sbs_off, _ = render_shot_sbs(entry_dir, 0, max_frames=1,
                                 surround="off")
    soft, off = sbs_soft[0], sbs_off[0]
    ow = info["out_w"]
    soft_l, off_l = soft[:, :ow], off[:, :ow]  # left eye audit half
    sur = np.any(soft_l != off_l, axis=-1)
    footprint = ~sur
    # seam ring: surround pixels 4-adjacent to footprint
    fp = footprint
    ring = sur & (np.roll(fp, 1, 0) | np.roll(fp, -1, 0) |
                  np.roll(fp, 1, 1) | np.roll(fp, -1, 1))
    deltas = []
    for y, x in np.argwhere(ring):
        row_fp = np.flatnonzero(fp[y])
        if len(row_fp) == 0:
            continue
        near = row_fp[np.argmin(np.abs(row_fp - x))]
        deltas.append(int(np.abs(soft_l[y, x].astype(int)
                                 - soft_l[y, near].astype(int)).max()))
    deltas = np.array(deltas) if deltas else np.array([0])
    # pole smear: columns whose vertical std < 1 LSB over their full height
    def smear_cols(img, mask):
        cols = 0
        for x in range(img.shape[1]):
            m = mask[:, x]
            if m.sum() > 8 and float(img[m, x].std()) < 1.0:
                cols += 1
        return cols
    return {
        "surround_px": int(sur.sum()),
        "footprint_px": int(footprint.sum()),
        "seam_px": int(ring.sum()),
        "seam_delta_mean": round(float(deltas.mean()), 3),
        "seam_delta_p95": round(float(np.percentile(deltas, 95)), 3),
        "seam_delta_max": int(deltas.max()),
        "smear_cols_in_footprint": smear_cols(soft_l, footprint),
        "smear_cols_in_surround": smear_cols(soft_l, sur),
    }


def main():
    meta = json.load(open(os.path.join(GOLD, "depth_shot_00000.json")))
    ft = json.load(open(os.path.join(GOLD, "fov_track.json")))
    import sys
    sys.path.insert(0, HERE)
    from reference_render import theta_h_for
    aspect = meta["source_width"] / meta["source_height"]
    th = theta_h_for(75.0, math.radians(ft["shots"][0]["hfov_deg"]), aspect)
    audit = {
        "screen_deg": 75.0, "theta_h_deg": round(math.degrees(th), 4),
        "aspect": aspect,
        "map": map_metrics(meta["source_width"], meta["source_height"], th),
        "seam": seam_metrics(GOLD),
    }
    out = os.path.join(GOLD, "distort_audit.json")
    json.dump(audit, open(out, "w"), indent=1)
    print(json.dumps(audit, indent=1))


if __name__ == "__main__":
    main()
