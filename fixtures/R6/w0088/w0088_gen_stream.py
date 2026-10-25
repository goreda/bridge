#!/usr/bin/env python3
"""W-0088 requester-supplied fixture: token-stream generator, seed 17.
Two planted schedules, 60 s each, schema {"t_ms":int,"tokens":int} per line:
  schedule_worst_burst.jsonl: background bursts 0-30 tokens every 700+/-300 ms,
    PLUS one 400-token burst at t=1000 ms.
  schedule_idle.jsonl: zero tokens for the full 60 s (meta only).
pace.json (REQUESTER-STATED cap): {"target_tokens_per_s":13,"window_ms":100,
"catchup_cap_tokens_per_window":40} - the cap unit is tokens per 100 ms window,
including immediately after the 400-token burst.
"""
import json, random, sys

def run(outdir):
    rng = random.Random(17)
    events = []
    t = 0
    while t < 60000:
        n = rng.randint(0, 30)
        if n:
            events.append({"t_ms": t, "tokens": n})
        t += 700 + rng.randint(-300, 300)
    events.append({"t_ms": 1000, "tokens": 400})
    events.sort(key=lambda e: e["t_ms"])
    with open(f"{outdir}/schedule_worst_burst.jsonl", "w") as f:
        for e in events:
            f.write(json.dumps(e, separators=(",", ":")) + "\n")
    with open(f"{outdir}/schedule_idle.jsonl", "w") as f:
        f.write(json.dumps({"meta": "idle schedule: zero tokens for 60000 ms", "t_ms": 0, "tokens": 0}) + "\n")
    with open(f"{outdir}/pace.json", "w") as f:
        json.dump({"target_tokens_per_s": 13, "window_ms": 100,
                   "catchup_cap_tokens_per_window": 40}, f, indent=1)
    with open(f"{outdir}/planted_truth.json", "w") as f:
        json.dump({"seed": 17, "worst_burst": {"burst_at_ms": 1000, "burst_tokens": 400,
                   "background": "0-30 tokens every 700+/-300 ms", "events": len(events)},
                   "idle": {"tokens": 0}, "cap": "40 tokens per 100 ms window"}, f, indent=2)
    print(f"w0088 OK events={len(events)} burst=400@1000ms cap=40/100ms")

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else ".")
