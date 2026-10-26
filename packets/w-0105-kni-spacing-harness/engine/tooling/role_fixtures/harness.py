"""Recovery / false-rate harness. derive = pluggable: derive(outline, noise=None) -> same dict shape as ref_roles.derive.
usage: python3 harness.py [module_with_derive] ; default ref_roles"""
import importlib, json, math, sys, csv, hashlib, glob, os
import numpy as np
import gen
mod = importlib.import_module(sys.argv[1] if len(sys.argv) > 1 else "ref_roles")
REPS = int(os.environ.get("REPS", 60))
SIGMAS = [0.0, 0.5, 1.0, 2.0, 4.0]
F = gen.add_flat_truth(gen.fixtures())
rows = []   # (group, sigma, rounding, noise_mode, metric, num, den)
def add(group, s, rd, mode, metric, num, den): rows.append((group, s, rd, mode, metric, num, den))
def noise_for(mode, true_sigma, outline):
    if mode == "measured": return mod.measure_noise(outline)
    f = {"declared_true": 1.0, "declared_half": 0.5, "declared_double": 2.0}[mode]
    return {"sigma": true_sigma*f, "origin": "declared", "derivation": f"{mode}: {f} x true sigma"}
modes = ["measured", "declared_true", "declared_half", "declared_double"]
for sg in SIGMAS:
  for rd in (False, True):
    for mode in modes:
        if sg == 0.0 and mode in ("declared_half", "declared_double"): continue
        agg = {}
        def acc(k, num, den):
            a = agg.setdefault(k, [0, 0]); a[0] += num; a[1] += den
        for rep in range(REPS):
            for name, fx in F.items():
                rng = np.random.default_rng(abs(hash((name, sg, rd, rep))) % (2**32)) if False else np.random.default_rng(int(hashlib.md5(f"{name}|{sg}|{rd}|{rep}".encode()).hexdigest()[:8], 16))
                ob = gen.perturb(fx, sg, rng, rd)
                nz = noise_for(mode, sg, ob)
                d = mod.derive(ob, nz)
                if mode == "measured":
                    acc("noise_est_abs_err", abs(nz["sigma"]-sg), 1) if nz["origin"] == "measured" else None
                    acc("noise_measurable", 1 if nz["origin"] == "measured" else 0, 1)
                grp = "wedge" if name.startswith("wedge") else "main"
                for ci, c in enumerate(fx["contours"]):
                    dc = d["contours"][ci]
                    for r in c["geometric_classes"]:
                        got = dc["nodes"][r["node"]]["geometric_class"]
                        acc(f"{grp}:node_geometric_class[{r['geometric_class']}]_correct", int(got == r["geometric_class"]), 1)
                        if name.startswith("wedge"): acc(f"wedge_corner_detect[{int(r['turn_deg'])}deg]", int(got == "corner"), 1)
                    # interior extrema
                    te = {(e["seg"], e["axis"]) for e in c.get("interior_extrema", [])}
                    de = {(e["seg"], e["axis"]) for e in dc["interior_extrema"]}
                    acc("interior_extremum_tp", len(te & de), len(te)); acc("interior_extremum_fp", len(de-te), 1)
                    # inflections
                    ti = c.get("inflections", []); di = dc["inflections"]
                    tp = sum(any(i["seg"] == j["seg"] and abs(i["t"]-j["t"]) < 0.05 for j in di) for i in ti)
                    acc("inflection_tp", tp, len(ti)); acc("inflection_fp", max(0, len(di)-tp), 1)
                    # flat edges (horizontal)
                    tf = {f["seg"]: f for f in c.get("flat", [])}
                    dfl = {f["seg"]: f for f in dc["flat"] if f["axis"] == "h"}
                    acc("flat_edge_tp", len(set(tf) & set(dfl)), len(tf)); acc("flat_edge_fp", len(set(dfl)-set(tf)), 1)
                    for sgm in set(tf) & set(dfl):
                        acc("flat_edge_abs_offset_sum", abs(dfl[sgm]["pos"]-tf[sgm]["y"]), 1)
                    # closure: truth gap 0 and gap 5/2 units (no noise-free coordinate drift beyond sigma)
                    if name == "rect":
                        for gap in (0.0, 1.0, 2.0, 5.0, 10.0):
                            ang = rng.uniform(0, 2*math.pi)
                            e = np.array(ob["contours"][0]["nodes"][0]) + gap*np.array([math.cos(ang), math.sin(ang)]) + (rng.normal(0, sg, 2) if sg else 0)
                            g = float(np.linalg.norm(e-np.array(ob["contours"][0]["nodes"][0])))
                            acc(f"closure_declared_closed[gap={gap}]", int(mod.closure_ok(g, nz)), 1)
        for k, (a, b) in agg.items():
            add("", sg, rd, mode, k, a, b)
with open("results.tsv", "w") as f:
    f.write("sigma_true\trounded\tnoise_mode\tmetric\tnum\tden\trate_or_mean\n")
    for _, sg, rd, mode, m, a, b in rows:
        if m.endswith("_sum") or m == "noise_est_abs_err": val = a/b if b else float("nan")
        else: val = a/b if b else float("nan")
        f.write(f"{sg}\t{int(rd)}\t{mode}\t{m}\t{a:.6g}\t{b}\t{val:.4f}\n")
print("rows", len(rows))
