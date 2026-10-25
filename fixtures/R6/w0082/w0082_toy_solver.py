#!/usr/bin/env python3
"""W-0082 requester-supplied fixture: toy 3-pass solver with planted defect + control.
32 entities x 200 steps, box 100x100, seed 11.
Passes: 1 integrate (pos += vel), 2 pairwise push-out (min dist 2.0),
3 boundary clamp. DEFECT variant: pass 3 clamps to the shrunken region [46,54]^2,
undoing pass-2 separations. CONTROL: pass 3 clamps to the true [0,100]^2 boundary.
Log schema (one line per entity per step):
{"step":k,"entity":i,"after_pass":[[x1,y1],[x2,y2],[x3,y3]]}
The attribution tool derives writer ids and undo counts from after_pass positions.
Planted truth: defect undo>0 for every step after step 1; control undo==0 always.
"""
import json, math, random, sys

N, STEPS, BOX = 32, 200, 100.0
MIND = 2.0

def init_entities():
    rng = random.Random(11)
    ent = []
    for i in range(N):
        ent.append([rng.gauss(50, 5), rng.gauss(50, 5),
                    rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6)])
    return ent

def step_solver(ent, defect):
    log = []
    for i in range(N):
        x, y, vx, vy = ent[i]
        nx, ny = x + vx, y + vy
        # pass 1 bounce keeps dynamics inside [10,90]^2 so a true boundary
        # clamp in pass 3 (control) never fires.
        if nx < 10 or nx > 90: vx = -vx; nx = max(10, min(90, nx))
        if ny < 10 or ny > 90: vy = -vy; ny = max(10, min(90, ny))
        ent[i][2], ent[i][3] = vx, vy
        p1 = [nx, ny]
        p2 = list(p1)
        log.append({"entity": i, "after_pass": [list(p1), p2, None]})
    # pass 2: pairwise push-out
    for a in range(N):
        for b in range(a + 1, N):
            xa, ya = log[a]["after_pass"][1]
            xb, yb = log[b]["after_pass"][1]
            dx, dy = xb - xa, yb - ya
            d = math.hypot(dx, dy)
            if d < MIND and d > 1e-9:
                push = (MIND - d) / 2
                ux, uy = dx / d, dy / d
                log[a]["after_pass"][1] = [xa - ux * push, ya - uy * push]
                log[b]["after_pass"][1] = [xb + ux * push, yb + uy * push]
    # pass 3: clamp
    lo, hi = (46.0, 54.0) if defect else (0.0, BOX)
    for i in range(N):
        x2, y2 = log[i]["after_pass"][1]
        log[i]["after_pass"][2] = [max(lo, min(hi, x2)), max(lo, min(hi, y2))]
    return log

def undo_counts(logs):
    """Per step: entities whose pass-3 position moved back toward pass 1
    (pass-2 displacement magnitude reduced by pass 3)."""
    out = []
    for log in logs:
        c = 0
        for row in log:
            p1, p2, p3 = row["after_pass"]
            d21 = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
            d31 = math.hypot(p3[0] - p1[0], p3[1] - p1[1])
            if d31 < d21 - 1e-9:
                c += 1
        out.append(c)
    return out

def run(outdir):
    results = {}
    for variant, defect in (("defect", True), ("control", False)):
        ent = init_entities()
        lines = []
        logs = []
        for k in range(STEPS):
            log = step_solver(ent, defect)
            logs.append(log)
            for row in log:
                lines.append(json.dumps({"step": k, "entity": row["entity"],
                                         "after_pass": [[round(v, 6) for v in p] for p in row["after_pass"]]},
                                        separators=(",", ":")))
            for i in range(N):
                ent[i][0], ent[i][1] = log[i]["after_pass"][2]
        with open(f"{outdir}/solver_log_{variant}.jsonl", "w") as f:
            f.write("\n".join(lines) + "\n")
        uc = undo_counts(logs)
        results[variant] = uc
    d, c = results["defect"], results["control"]
    assert all(u > 0 for u in d[1:]), "defect undo must be >0 for every step after step 1"
    assert all(u == 0 for u in c), "control undo must be 0"
    with open(f"{outdir}/planted_truth.json", "w") as f:
        json.dump({"entities": N, "steps": STEPS, "seed": 11,
                   "defect_undo_per_step_first5": d[:5], "defect_undo_min_after_step1": min(d[1:]),
                   "control_undo_total": sum(c),
                   "defect_rule": "pass3 clamps to [46,54]^2", "control_rule": "pass3 clamps to [0,100]^2"}, f, indent=2)
    print(f"w0082 OK defect_min_undo_after_step1={min(d[1:])} control_total={sum(c)}")

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else ".")
