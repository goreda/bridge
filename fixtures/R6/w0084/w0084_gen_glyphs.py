#!/usr/bin/env python3
"""W-0084 requester-supplied fixture: glyph-manifest dataset generator, seed 3.
40 invented font families x 62 classes (0-9 a-z A-Z) x 20 variants.
Families carry procedural render metadata (stroke_w, slant, serif, xo, yo);
the lab renders from this metadata - exact pixel equality of two rows holds
iff (family_params, class, variant_params) are identical. variant_params are
family-independent augmentation draws (seeded per class+variant), so a
render_param_override that swaps only family params yields exact-pixel
duplicates of the source family rows.
Outputs: families.json (40), manifest.jsonl (49,600 rows), and three split
manifests: split_clean.json (train fams 0..31 / test fams 32..39),
split_leak2.json (test includes train families 30 and 31),
split_leakvar.json (test fams 32..39, but family 39 test rows for classes 0..9
and variants 0..4 carry family 31's RENDER PARAMS under the family-39 label:
planted near-duplicate variants across the boundary, labels disjoint).
Planted truth: clean {shared_families 0, shared_pairs 0, dup_variants 0};
leak2 {shared_families 2, shared_pairs 124, dup_variants 0};
leakvar {shared_families 0, shared_pairs 0, dup_variants 50}.
"""
import json, random, string, sys

CLASSES = list(string.digits + string.ascii_lowercase + string.ascii_uppercase)

def family_params(fid):
    rng = random.Random(3 * 1000 + fid)
    return {"family_id": fid, "name": f"fam-{fid:02d}",
            "stroke_w": round(rng.uniform(1.0, 4.0), 3),
            "slant": round(rng.uniform(-0.3, 0.3), 3),
            "serif": bool(rng.getrandbits(1)),
            "xo": rng.randint(0, 3), "yo": rng.randint(0, 3)}

def variant_params(fid, ci, v):
    rng = random.Random(3 * 1000000 + ci * 100 + v)
    return {"scale": round(rng.uniform(0.9, 1.1), 3), "rot": round(rng.uniform(-5, 5), 3)}

def run(outdir):
    fams = [family_params(f) for f in range(40)]
    with open(f"{outdir}/families.json", "w") as f:
        json.dump(fams, f, indent=1)
    rows = []
    for fid in range(40):
        for ci, c in enumerate(CLASSES):
            for v in range(20):
                rows.append({"glyph_id": f"f{fid:02d}_{c}_{v:02d}", "family": fid,
                             "class": c, "variant": v,
                             "render": {**family_params(fid), **variant_params(fid, ci, v)}})
    with open(f"{outdir}/manifest.jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(r, separators=(",", ":")) + "\n")
    splits = {
        "split_clean.json": {"train": list(range(0, 32)), "test": list(range(32, 40))},
        "split_leak2.json": {"train": list(range(0, 32)), "test": list(range(30, 40))},
        "split_leakvar.json": {"train": list(range(0, 32)), "test": list(range(32, 40)),
                               "render_param_override": [
                                   {"label_family": 39, "use_family_params": 31,
                                    "classes": CLASSES[0:10], "variants": [0, 1, 2, 3, 4]}]},
    }
    for name, sp in splits.items():
        with open(f"{outdir}/{name}", "w") as f:
            json.dump(sp, f, indent=1)
    with open(f"{outdir}/planted_truth.json", "w") as f:
        json.dump({"split_clean.json": {"shared_families": 0, "shared_pairs": 0, "dup_variants": 0},
                   "split_leak2.json": {"shared_families": 2, "shared_pairs": 124, "dup_variants": 0},
                   "split_leakvar.json": {"shared_families": 0, "shared_pairs": 0, "dup_variants": 50},
                   "seed": 3, "families": 40, "classes": 62, "variants": 20}, f, indent=2)
    print("w0084 OK rows=49600 splits=3 planted dups 0/0/50 shared 0/2/0")

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else ".")
