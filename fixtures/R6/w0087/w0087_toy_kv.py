#!/usr/bin/env python3
"""W-0087 requester-supplied fixture: in-memory toy KV + job poller, seed 19
(requester-pinned; the published request named the mix but no seed).
Store fixture: 40 open jobs = 12 active, 20 returned, 8 expired.
REQUESTER RULINGS (answering the lab's (a)-(d)):
(a) design_json schema: {"design":"baseline"|"index","index_key":"jobs:index"}.
(b) a RETURNED job counts as closed by the candidate; stale/expired closure
    criteria: state == "returned", or state == "active" with expires_at < now
    (= "expired"); the candidate names every job it closes in closed_jobs.
(c) the baseline's open-job ID registry is known in-band (no discovery call):
    baseline performs exactly one list per open job per cycle (40 at N=40);
    the candidate performs exactly ONE list call (its index listing), which IS
    its discovery.
(d) zero-open-jobs: candidate 1 list call vs baseline 0 is the intended
    reading; both are valid measurements, reported as measured.
Note (endorsed): list-call count alone is not latency or quota evidence.
run_cycle(store, design_json) -> {"list_calls":int,"closed_jobs":[ids]}.
"""
import json, random, sys

def make_store():
    rng = random.Random(19)
    jobs = {}
    ids = [f"job-{i:02d}" for i in range(40)]
    states = ["active"] * 12 + ["returned"] * 20 + ["expired"] * 8
    rng.shuffle(states)
    now = 1_700_000_000
    for jid, st in zip(ids, states):
        jobs[jid] = {"state": "active" if st == "expired" else st,
                     "created": now - rng.randint(100, 9000),
                     "expires_at": (now - 1) if st == "expired" else (now + 3600)}
    return {"now": now, "jobs": jobs}

def run_cycle(store, design):
    now = store["now"]
    jobs = store["jobs"]
    list_calls = 0
    closed = []
    kind = design["design"]
    if kind == "baseline":
        for jid in list(jobs):  # registry known in-band: one list call per open job
            list_calls += 1  # LIST job:<id>:*
            j = jobs[jid]
            if j["state"] == "returned" or (j["state"] == "active" and j["expires_at"] < now):
                closed.append(jid)
    elif kind == "index":
        index_key = design["index_key"]  # required by the design_json schema
        list_calls += 1  # LIST <index_key> (single index listing)
        for jid, j in jobs.items():
            if j["state"] == "returned" or (j["state"] == "active" and j["expires_at"] < now):
                closed.append(jid)
    else:
        raise ValueError(f"unknown design {kind!r}: expected 'baseline' or 'index'")
    return {"list_calls": list_calls, "closed_jobs": sorted(closed)}

def run(outdir):
    store = make_store()
    with open(f"{outdir}/store_fixture.json", "w") as f:
        json.dump(store, f, indent=1, sort_keys=True)
    res = {"baseline": run_cycle(json.loads(json.dumps(store)), {"design": "baseline"}),
           "index": run_cycle(json.loads(json.dumps(store)), {"design": "index", "index_key": "jobs:index"})}
    assert res["baseline"]["list_calls"] == 40 and res["index"]["list_calls"] == 1
    assert res["baseline"]["closed_jobs"] == res["index"]["closed_jobs"]
    with open(f"{outdir}/planted_truth.json", "w") as f:
        json.dump({"seed": 19, "jobs": 40, "mix": {"active": 12, "returned": 20, "expired": 8},
                   "baseline_list_calls": 40, "index_list_calls": 1,
                   "closed_count": len(res["index"]["closed_jobs"]),
                   "closed_jobs": res["index"]["closed_jobs"]}, f, indent=2)
    print(f"w0087 OK baseline=40 index=1 closed={len(res['index']['closed_jobs'])}")

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else ".")
