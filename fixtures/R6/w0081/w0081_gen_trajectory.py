#!/usr/bin/env python3
"""W-0081 requester-supplied fixture: N=64 soft-disc trajectory generator.
Plate 800x450, vertical separators at x=300 and x=500, PRNG seed 7, 600 steps.
Planted truth: discs 0 and 1 in contact for steps 10..590 INCLUSIVE (581 steps);
all other pairs brief (construction asserts no other run exceeds 20 steps).
Schema: line 1 meta {"type":"meta","plate":[800,450],"separators":[300,500],
"epsilon":1.0,"radii":[...]}; then one line per step:
{"step":k,"entities":[{"id":i,"x":float,"y":float}]}. Radii in meta by id.
Contact rule (for the consuming tool): center distance < r_i + r_j + epsilon
AND both discs in the same separator-delimited segment (separators block contact).
Dynamics: constant-velocity drift, elastic bounce off plate walls and separators.
"""
import json, math, random, sys

def seg(x, seps=(300, 500)):
    return 0 if x < seps[0] else (1 if x < seps[1] else 2)

def run(outdir):
    rng = random.Random(7)
    N, W, H, STEPS = 64, 800, 450, 600
    SEPS = (300, 500)
    EPS = 1.0
    radii = [6 + (i * 7) % 9 for i in range(N)]
    lanes = [(0, SEPS[0]), (SEPS[0], SEPS[1]), (SEPS[1], W)]
    r0, r1 = radii[0], radii[1]
    offset = r0 + r1  # planted distance: contact since offset < r0+r1+EPS
    ent = []
    for i in range(N):
        lane = lanes[0] if i == 1 else lanes[i % 3]
        lo, hi = lane[0] + radii[i], lane[1] - radii[i]
        if i == 0:
            lo = r0 + offset + 1.0
            hi = SEPS[0] - r1 - offset - 1.0
        x = rng.uniform(lo, hi)
        y = rng.uniform(r1 + 1.0 if i == 0 else radii[i], H - (r1 + 1.0 if i == 0 else radii[i]))
        vx = rng.uniform(-1.2, 1.2) or 0.7
        vy = rng.uniform(-1.2, 1.2) or -0.5
        ent.append([x, y, vx, vy, lane])
    lines = []
    runs_live = {}
    for k in range(STEPS):
        rows = []
        for i in range(N):
            x, y, vx, vy, lane = ent[i]
            if i == 0:
                lo, hi = r0 + offset + 1.0, SEPS[0] - r1 - 4 * offset - 1.0
                ylo, yhi = r1 + 1.0, H - r1 - 1.0
            else:
                lo, hi = lane[0] + radii[i], lane[1] - radii[i]
                ylo, yhi = radii[i], H - radii[i]
            if i == 1:
                # scripted planted fixture: parallel parking at 4x offset outside the
                # window, snap to `offset` (contact) for steps 10..590 inclusive.
                x = ent[0][0] + (offset if 10 <= k <= 590 else 4 * offset)
                y = ent[0][1]
            else:
                x += vx; y += vy
                if x < lo or x > hi: vx = -vx; x = max(lo, min(hi, x))
                if y < ylo or y > yhi: vy = -vy; y = max(ylo, min(yhi, y))
            ent[i] = [x, y, vx, vy, lane]
            rows.append({"id": i, "x": round(x, 6), "y": round(y, 6)})
        lines.append(json.dumps({"step": k, "entities": rows}, separators=(",", ":")))
        # deterministic run-breaking (scripted nudge, documented in README):
        # any non-planted pair reaching a 20-step contact run moves the
        # non-planted member (or b) to the far end of its lane at the next step.
        for a in range(N):
            for b in range(a + 1, N):
                if (a, b) == (0, 1):
                    continue
                xa, ya = ent[a][0], ent[a][1]
                xb, yb = ent[b][0], ent[b][1]
                contact = seg(xa, SEPS) == seg(xb, SEPS) and math.hypot(xa - xb, ya - yb) < radii[a] + radii[b] + EPS
                if contact:
                    runs_live[(a, b)] = runs_live.get((a, b), 0) + 1
                    if runs_live[(a, b)] == 20:
                        d = b if b not in (0, 1) else a
                        lane = ent[d][4]
                        mid = (lane[0] + lane[1]) / 2
                        ent[d][0] = (lane[1] - radii[d] - 1) if ent[d][0] < mid else (lane[0] + radii[d] + 1)
                        ent[d][2] = -ent[d][2]
                        rows[d]["x"] = round(ent[d][0], 6)
                        lines[-1] = json.dumps({"step": k, "entities": rows}, separators=(",", ":"))
                else:
                    runs_live[(a, b)] = 0
    longest_other = 0
    runs = {}
    planted = 0
    planted_first = planted_last = None
    for k in range(STEPS):
        es = json.loads(lines[k])["entities"]
        seen = set()
        for a in range(N):
            for b in range(a + 1, N):
                xa, ya, xb, yb = es[a]["x"], es[a]["y"], es[b]["x"], es[b]["y"]
                contact = seg(xa, SEPS) == seg(xb, SEPS) and math.hypot(xa - xb, ya - yb) < radii[a] + radii[b] + EPS
                key = (a, b)
                if contact:
                    runs[key] = runs.get(key, 0) + 1
                    if key == (0, 1):
                        planted = max(planted, runs[key])
                        if planted_first is None: planted_first = k
                        planted_last = k
                else:
                    if key != (0, 1): longest_other = max(longest_other, runs.get(key, 0))
                    runs[key] = 0
                seen.add(key)
        for key in list(runs):
            if key not in seen: runs[key] = 0
    assert planted == 581, f"planted run {planted} != 581"
    assert planted_first == 10 and planted_last == 590, f"planted window {planted_first}..{planted_last}"
    assert longest_other <= 20, f"non-planted run {longest_other} > 20"
    meta = json.dumps({"type": "meta", "plate": [W, H], "separators": list(SEPS),
                       "epsilon": EPS, "radii": radii}, separators=(",", ":"))
    with open(f"{outdir}/trajectory.jsonl", "w") as f:
        f.write(meta + "\n" + "\n".join(lines) + "\n")
    with open(f"{outdir}/planted_truth.json", "w") as f:
        json.dump({"pair": [0, 1], "start_step": 10, "end_step": 590,
                   "length_steps_inclusive": 581,
                   "max_other_pair_run_steps": longest_other,
                   "epsilon": EPS, "seed": 7}, f, indent=2)
    print(f"w0081 OK planted=581 window=10..590 longest_other={longest_other}")

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else ".")
