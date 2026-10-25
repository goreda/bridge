#!/usr/bin/env python3
"""W-0085 requester-supplied fixture: toy training loop with injected CPU competitor.
500 steps, pure-Python numeric kernel (fixed-size dot product, identical work
every step in both phases), seed 5 for the data.
Phase A: steps 0-99, no competitor. Phase B: steps 100-499, competitor process
toggled ON for steps 100-199 and 300-349 via a flag file (same host).
Log schema (one JSON per step): {"step":k,"phase":"A|B","t_compute_s":float,
"t_wall_s":float,"t_wait_s":float} where t_compute = inside the step kernel,
t_wait = input-pipeline wait, t_wall = whole step. The attribution tool must
find the competitor windows from the compute/wall gap alone.
Usage: python3 w0085_toy_loop.py OUTDIR [flagfile]
"""
import json, os, random, subprocess, sys, time

STEPS = 500
ON_WINDOWS = [(100, 199), (300, 349)]

def kernel(rng_data):
    acc = 0.0
    for v in rng_data:
        acc += v * v
    return acc

def run(outdir):
    rng = random.Random(5)
    data = [rng.random() for _ in range(20000)]
    flag = os.path.join(outdir, "competitor.flag")
    comp = subprocess.Popen([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                          "w0085_competitor.py"), flag, "--max-s", "900"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if os.path.exists(flag):
        os.remove(flag)
    lines = []
    try:
        for k in range(STEPS):
            tw0 = time.monotonic()
            want_on = any(a <= k <= b for a, b in ON_WINDOWS)
            exists = os.path.exists(flag)
            if want_on and not exists:
                open(flag, "w").write("on")
            elif exists and not want_on:
                os.remove(flag)
            tw1 = time.monotonic()
            tc0 = time.monotonic()
            kernel(data)
            tc1 = time.monotonic()
            lines.append(json.dumps({"step": k, "phase": "A" if k < 100 else "B",
                                     "t_compute_s": round(tc1 - tc0, 6),
                                     "t_wall_s": round(tc1 - tw0, 6),
                                     "t_wait_s": round(tw1 - tw0, 6)}, separators=(",", ":")))
    finally:
        if os.path.exists(flag):
            os.remove(flag)
        comp.terminate()
        try:
            comp.wait(timeout=30)
        except subprocess.TimeoutExpired:
            comp.kill()
            comp.wait()
    with open(f"{outdir}/run_log.jsonl", "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(f"{outdir}/planted_truth.json", "w") as f:
        json.dump({"steps": STEPS, "seed": 5, "kernel": "20000-element dot product, identical every step",
                   "competitor_on_steps": [[100, 199], [300, 349]], "phase_A_steps": [0, 99],
                   "phase_B_steps": [100, 499]}, f, indent=2)
    print("w0085 OK steps=500 windows=100-199,300-349")

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else ".")
