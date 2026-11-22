#!/usr/bin/env python3
"""P29-LIVE-CONTROL golden vectors: MODEL-ONLY Python replay of
photon-live-control.lua (M.VERSION=1) semantics, emitted as JSON. This file is
NOT the authoritative reference: it is a Python reading of the Lua source and
serves as a secondary cross-check only. The authoritative reference is the
real LuaJIT execution of the exact pinned script, produced by
lua-reference/run-live-control.lua (see lua-reference/README.md) into
lua-reference/live-control-lua-reference.json. Never present this Python
replay as independent verification. Source pin: instinct main
photon-live-control.lua, 84 lines,
SHA256 4b8ec6a5b8e2f23be36900fc95e9c34a87705673bf2bef4fec69789401da6b76.

The source is a live-only gamma actuator with no mpv API usage. Timestamps
are integer microseconds (nowUs), same convention as DR-0019/DR-0020."""
import json, math, sys

INF = math.inf

def finite(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and v == v and abs(v) < INF

class Actuator:
    """Exact replica of photon-live-control.lua's M.new(config) instance."""

    @staticmethod
    def base_config():
        return {
            "initial_gamma": 1.0,
            "qualified": True,
            "rate": 0.5,                # gamma units per second
            "stale_age": 0.5,
            "callback_gap": 0.5,
            "reference_interval": 1.0 / 24.0,
            "retention": 0.5,
            "max_settlement_samples": 3,
            "classify_cut": lambda old, new: (
                "confirmed" if abs(new["pbs"] - old["pbs"]) > 30
                else "candidate" if abs(new["pbs"] - old["pbs"]) > 15
                else None),
            "settled": lambda profiles: (len(profiles) >= 2
                and max(p["pbs"] for p in profiles) - min(p["pbs"] for p in profiles) < 5),
            "target": lambda profile, velocity: max(0.5, min(2.0, 1.0 + (profile["pbs"] - 100.0) / 100.0)),
            "velocity": lambda old, new, prev: (new["pbs"] - old["pbs"]) / (new["t"] - old["t"]),
            "feed": None,  # set per-sim to count calls
        }

    def __init__(self, config):
        self.config = dict(config)
        self.gamma = config["initial_gamma"]
        assert finite(self.gamma)
        self.state = "UNKNOWN"
        self.velocity = 0.0
        self.target = None
        self.previous = None
        self.reason = None
        self.doc = None
        self.last_id = None
        self.last_pts = None
        self.last_t = None
        self.last_tick = None
        self.cut_pending = False
        self.cut_profiles = None
        self.feed_calls = 0
        self._feed_cb = config.get("feed")

    def qualified(self):
        c = self.config
        return (c.get("qualified") is True and finite(c.get("rate")) and c["rate"] > 0
                and finite(c.get("stale_age")) and c["stale_age"] > 0
                and finite(c.get("callback_gap")) and c["callback_gap"] > 0
                and finite(c.get("reference_interval")) and c["reference_interval"] > 0
                and finite(c.get("retention")) and 0 < c["retention"] < 1
                and callable(c.get("classify_cut")) and callable(c.get("settled"))
                and callable(c.get("target")) and callable(c.get("velocity"))
                and finite(c.get("max_settlement_samples")) and c["max_settlement_samples"] >= 1
                and c["max_settlement_samples"] % 1 == 0)

    def hold(self, reason):
        self.state = "CUT_HOLD_UNKNOWN" if self.cut_pending else "UNKNOWN"
        self.target = None
        self.velocity = 0.0
        self.previous = None
        self.reason = reason
        if self.cut_pending:
            self.cut_profiles = {}

    def diagnostics(self):
        return {
            "state": self.state, "reason": self.reason,
            "cut_pending": self.cut_pending is True,
            "settlement_samples": len(self.cut_profiles) if self.cut_profiles is not None else 0,
            "held_gamma": self.gamma,
        }

    def observe(self, profile):
        c = self.config
        if (not isinstance(profile, dict) or profile.get("doc") is None or profile.get("id") is None
                or not finite(profile.get("t")) or not finite(profile.get("pts"))
                or not finite(profile.get("pbs"))):
            self.hold("invalid-profile")
            return False
        if self.doc != profile["doc"]:
            self.hold("document")
            self.doc = profile["doc"]
            self.last_id = self.last_pts = self.last_t = None
            self.cut_profiles = None
            self.cut_pending = False
            self.state = "UNKNOWN"
        if (self.last_id is not None
                and (profile["id"] <= self.last_id or profile["pts"] <= self.last_pts
                     or profile["t"] <= self.last_t)):
            self.hold("repeated-profile")
            return False
        old = self.previous
        self.last_id, self.last_pts, self.last_t = profile["id"], profile["pts"], profile["t"]
        # Feed fresh observations even while gamma is held.
        self.feed_calls += 1
        if self._feed_cb:
            self._feed_cb(profile)
        if not self.qualified():
            self.hold("unqualified")
            return False
        if old is not None and profile["t"] - old["t"] > c["stale_age"]:
            self.hold("observation-gap")
            old = None
        cut = c["classify_cut"](old, profile) if old is not None else None
        if cut in ("candidate", "confirmed"):
            self.state = "CUT_HOLD"
            self.cut_pending = True
            self.velocity = 0.0
            self.target = None
            self.cut_profiles = [profile]
        elif self.cut_pending:
            if self.cut_profiles is None:
                self.cut_profiles = {}
            self.cut_profiles = list(self.cut_profiles)
            if len(self.cut_profiles) >= c["max_settlement_samples"]:
                self.cut_profiles.pop(0)
            self.cut_profiles.append(profile)
            if c["settled"](self.cut_profiles) is True:
                self.state = "READY"
                self.reason = None
                self.cut_profiles = None
                self.cut_pending = False
            else:
                self.state = "CUT_HOLD"
                self.reason = "settlement-unresolved"
        else:
            self.state = "READY"
            self.reason = None
        if self.state == "READY":
            if old is not None:
                self.velocity = c["velocity"](old, profile, self.velocity)
            else:
                self.velocity = 0.0
            target = c["target"](profile, self.velocity)
            if not finite(target):
                self.hold("invalid-target")
                return False
            self.target = target
        self.previous = profile
        return self.state == "READY"

    def tick(self, now):
        c = self.config
        if not finite(now):
            self.hold("invalid-clock")
            return None
        last = self.last_tick
        self.last_tick = now
        if not self.qualified():
            self.hold("unqualified")
            return None
        if last is None:
            return None
        dt = now - last
        if dt <= 0 or dt > c["callback_gap"]:
            self.hold("callback-gap")
            return None
        if self.last_t is None or now < self.last_t or now - self.last_t > c["stale_age"]:
            self.hold("stale")
            return None
        if self.state != "READY" or not finite(self.target if self.target is not None else INF):
            return None
        distance = self.target - self.gamma
        proposal = distance * (1 - c["retention"] ** (dt / c["reference_interval"]))
        step = max(-c["rate"] * dt, min(c["rate"] * dt, proposal))
        if abs(step) > abs(distance):
            step = distance
        candidate = self.gamma + step
        if not finite(candidate):
            self.hold("invalid-actuator")
            return None
        self.gamma = candidate
        return candidate


# ---------------------------------------------------------------- vectors --
def us(t):
    return int(round(t * 1e6))

def qt(t):
    # every time that enters the sim is quantized first (DR-0019 convention)
    return us(t) / 1e6

def P(doc, i, t, pts, pbs):
    return {"doc": doc, "id": i, "t": qt(t), "pts": pts, "pbs": pbs}

vectors = []

def expect(sim, returned=None):
    e = sim.diagnostics()
    e["velocity"] = sim.velocity
    e["target"] = sim.target
    e["feed_calls"] = sim.feed_calls
    if returned != "__no_check__":
        e["returned"] = returned
    return e

# LC1 happy path: three profiles -> READY with targets, then ticks approach
# target with rate clamp and the exponential retention proposal.
sim = Actuator(Actuator.base_config())
steps = []
p1 = P("a", 1, 0.000, 0.000, 100.0)
r = sim.observe(p1); steps.append({"op": "observe", "profile": p1, "nowUs": 0, "expect": expect(sim, r)})
p2 = P("a", 2, 0.100, 0.100, 103.0)
r = sim.observe(p2); steps.append({"op": "observe", "profile": p2, "nowUs": us(0.1), "expect": expect(sim, r)})
p3 = P("a", 3, 0.200, 0.200, 106.0)
r = sim.observe(p3); steps.append({"op": "observe", "profile": p3, "nowUs": us(0.2), "expect": expect(sim, r)})
r = sim.tick(qt(0.200)); steps.append({"op": "tick", "nowUs": us(0.2), "expect": expect(sim, r)})
for i in range(1, 6):
    t = qt(0.2 + i / 24.0)
    r = sim.tick(t)
    steps.append({"op": "tick", "nowUs": us(t), "expect": expect(sim, r)})
vectors.append({"name": "LC1-happy-path", "steps": steps})

# LC2 hold ladder: one trigger per hold reason. Order matters: every hold
# clears previous, so observation-gap must be triggered straight off a READY
# with no intervening hold; stale needs last_t older than stale_age at tick
# time with a valid callback dt.
sim = Actuator(Actuator.base_config())
steps = []
r = sim.observe({"doc": None, "id": 1, "t": 0.0, "pts": 0.0, "pbs": 100.0})
steps.append({"op": "observeRaw", "profile": {"doc": None, "id": 1, "t": 0.0, "pts": 0.0, "pbs": 100.0}, "nowUs": 0, "expect": expect(sim, r)})
r = sim.observe(p1); steps.append({"op": "observe", "profile": p1, "nowUs": 0, "expect": expect(sim, r)})  # document hold then READY
r = sim.observe(p2); steps.append({"op": "observe", "profile": p2, "nowUs": us(0.1), "expect": expect(sim, r)})
r = sim.observe(P("a", 2, 0.100, 0.100, 103.0))  # repeated id/pts/t
steps.append({"op": "observe", "profile": P("a", 2, 0.100, 0.100, 103.0), "nowUs": us(0.1), "expect": expect(sim, r)})
r = sim.observe(p3); steps.append({"op": "observe", "profile": p3, "nowUs": us(0.2), "expect": expect(sim, r)})
r = sim.observe(P("a", 4, 0.9, 0.9, 110.0))  # t jump 0.7 > stale_age straight off READY -> observation-gap (transient reason, velocity resets)
steps.append({"op": "observe", "profile": P("a", 4, 0.9, 0.9, 110.0), "nowUs": us(0.9), "expect": expect(sim, r)})
r = sim.tick(qt(0.9)); steps.append({"op": "tick", "nowUs": us(0.9), "expect": expect(sim, r)})
r = sim.tick(float("nan"))
steps.append({"op": "tickRaw", "now": "NaN", "nowUs": 0, "expect": expect(sim, r)})
r = sim.tick(qt(1.0))  # last valid tick 0.9 -> dt 0.1 ok; last_t 0.9 -> fresh; but previous was cleared by invalid-clock hold: READY only after next observe
steps.append({"op": "tick", "nowUs": us(1.0), "expect": expect(sim, r)})
r = sim.observe(P("a", 5, 1.0, 1.0, 111.0))
steps.append({"op": "observe", "profile": P("a", 5, 1.0, 1.0, 111.0), "nowUs": us(1.0), "expect": expect(sim, r)})
r = sim.tick(qt(1.05)); steps.append({"op": "tick", "nowUs": us(1.05), "expect": expect(sim, r)})
r = sim.tick(qt(1.7))  # dt 0.65 > callback_gap 0.5
steps.append({"op": "tick", "nowUs": us(1.7), "expect": expect(sim, r)})
r = sim.tick(qt(1.8))  # dt 0.1 ok, but now - last_t = 0.8 > stale_age -> stale
steps.append({"op": "tick", "nowUs": us(1.8), "expect": expect(sim, r)})
vectors.append({"name": "LC2-hold-ladder", "steps": steps})

# LC3 cut lifecycle: candidate cut -> CUT_HOLD, sliding settlement window at
# max 3 (alternating pbs keeps spread >= 10 so the window evicts and never
# settles), then a steady pair settles -> READY; a second cut while pending
# re-arms; invalid-clock while pending -> CUT_HOLD_UNKNOWN.
sim = Actuator(Actuator.base_config())
steps = []
base = [P("d", 1, 0.0, 0.0, 100.0), P("d", 2, 0.1, 0.1, 102.0), P("d", 3, 0.2, 0.2, 104.0)]
for p in base:
    r = sim.observe(p); steps.append({"op": "observe", "profile": p, "nowUs": us(p["t"]), "expect": expect(sim, r)})
cut = P("d", 4, 0.3, 0.3, 140.0)  # +36 > 30 -> confirmed cut
r = sim.observe(cut); steps.append({"op": "observe", "profile": cut, "nowUs": us(0.3), "expect": expect(sim, r)})
for p in [P("d", 5, 0.4, 0.4, 150.0), P("d", 6, 0.5, 0.5, 140.0), P("d", 7, 0.6, 0.6, 150.0)]:
    r = sim.observe(p); steps.append({"op": "observe", "profile": p, "nowUs": us(p["t"]), "expect": expect(sim, r)})
r = sim.tick(float("nan"))  # invalid-clock while pending -> CUT_HOLD_UNKNOWN
steps.append({"op": "tickRaw", "now": "NaN", "nowUs": 0, "expect": expect(sim, r)})
for p in [P("d", 8, 0.7, 0.7, 142.0), P("d", 9, 0.8, 0.8, 141.0)]:  # spread 1 < 5 -> settles
    r = sim.observe(p); steps.append({"op": "observe", "profile": p, "nowUs": us(p["t"]), "expect": expect(sim, r)})
vectors.append({"name": "LC3-cut-lifecycle", "steps": steps})

# LC4 step math: rate clamp binds when the proposal exceeds rate*dt, and the
# overshoot clamp lands exactly on target at the end.
cfg = Actuator.base_config()
cfg["rate"] = 0.02  # slow: rate clamp binds
sim = Actuator(cfg)
steps = []
p = P("e", 1, 0.0, 0.0, 180.0)  # target = 1.8
r = sim.observe(p); steps.append({"op": "observe", "profile": p, "nowUs": 0, "expect": expect(sim, r)})
r = sim.tick(qt(0.0)); steps.append({"op": "tick", "nowUs": 0, "expect": expect(sim, r)})
for i in range(1, 8):
    t = qt(i / 24.0)
    r = sim.tick(t)
    steps.append({"op": "tick", "nowUs": us(t), "expect": expect(sim, r)})
vectors.append({"name": "LC4-step-math", "config": {"rate": 0.02}, "steps": steps})

# LC5 invalid-target + unqualified + document-change mid-stream.
sim = Actuator(Actuator.base_config())
steps = []
r = sim.observe(P("f", 1, 0.0, 0.0, 100.0)); steps.append({"op": "observe", "profile": P("f", 1, 0.0, 0.0, 100.0), "nowUs": 0, "expect": expect(sim, r)})
sim.config["target"] = lambda profile, velocity: float("nan")
steps.append({"op": "setTargetNaN", "nowUs": us(0.05)})
r = sim.observe(P("f", 2, 0.1, 0.1, 105.0)); steps.append({"op": "observe", "profile": P("f", 2, 0.1, 0.1, 105.0), "nowUs": us(0.1), "expect": expect(sim, r), "note": "config target swapped to NaN externally; non-cut step reaches READY -> invalid-target"})
sim2 = Actuator(dict(Actuator.base_config(), qualified=False))
r = sim2.observe(P("f", 1, 0.0, 0.0, 100.0))
steps.append({"op": "freshUnqualified", "profile": P("f", 1, 0.0, 0.0, 100.0), "nowUs": 0, "expect": expect(sim2, r)})
r = sim.observe(P("g", 1, 0.2, 0.2, 100.0))  # document change: hold then same-observe recovery
steps.append({"op": "observe", "profile": P("g", 1, 0.2, 0.2, 100.0), "nowUs": us(0.2), "expect": expect(sim, r), "note": "config still NaN-target -> invalid-target after document recovery reaches READY"})
vectors.append({"name": "LC5-invalid-target-unqualified-document", "steps": steps})

# LC6 negative controls: invalid fields, per-field monotonic fences, first-tick
# grace, zero-dt callback gap, document-reset fence restore, unqualified tick,
# and the no-observe stale fence.
sim = Actuator(Actuator.base_config())
steps = []
for field in ("t", "pts", "pbs"):
    bad = {"doc": "n", "id": 1, "t": 0.0, "pts": 0.0, "pbs": 100.0, "__nan__": field}
    r = sim.observe({k: (float("nan") if k == field else v) for k, v in bad.items() if k != "__nan__"})
    steps.append({"op": "observeNaN", "nanField": field,
                  "profile": {"doc": "n", "id": 1, "t": 0.0, "pts": 0.0, "pbs": 100.0},
                  "nowUs": 0, "expect": expect(sim, r)})
r = sim.observe(P("n", 1, 0.0, 0.0, 100.0)); steps.append({"op": "observe", "profile": P("n", 1, 0.0, 0.0, 100.0), "nowUs": 0, "expect": expect(sim, r)})
r = sim.observe(P("n", 0, 0.1, 0.1, 101.0)); steps.append({"op": "observe", "profile": P("n", 0, 0.1, 0.1, 101.0), "nowUs": us(0.1), "expect": expect(sim, r), "note": "id regresses -> repeated-profile"})
r = sim.observe(P("n", 2, 0.1, 0.05, 101.0)); steps.append({"op": "observe", "profile": P("n", 2, 0.1, 0.05, 101.0), "nowUs": us(0.1), "expect": expect(sim, r), "note": "pts regresses -> repeated-profile"})
r = sim.observe(P("n", 2, 0.05, 0.2, 101.0)); steps.append({"op": "observe", "profile": P("n", 2, 0.05, 0.2, 101.0), "nowUs": us(0.05), "expect": expect(sim, r), "note": "t regresses -> repeated-profile"})
r = sim.observe(P("n", 2, 0.2, 0.2, 101.0)); steps.append({"op": "observe", "profile": P("n", 2, 0.2, 0.2, 101.0), "nowUs": us(0.2), "expect": expect(sim, r)})
r = sim.tick(qt(0.2)); steps.append({"op": "tick", "nowUs": us(0.2), "expect": expect(sim, r), "note": "first tick: last_tick primed, nil return, no hold"})
r = sim.tick(qt(0.2)); steps.append({"op": "tick", "nowUs": us(0.2), "expect": expect(sim, r), "note": "dt == 0 -> callback-gap"})
r = sim.tick(qt(0.4)); steps.append({"op": "tick", "nowUs": us(0.4), "expect": expect(sim, r), "note": "dt ok, fresh last_t, but state UNKNOWN -> nil, no hold"})
r = sim.observe(P("m", 1, 0.5, 0.5, 100.0)); steps.append({"op": "observe", "profile": P("m", 1, 0.5, 0.5, 100.0), "nowUs": us(0.5), "expect": expect(sim, r), "note": "document reset: id 1 accepted again on the new doc (fence restored)"})
r = sim.observe(P("m", 1, 0.6, 0.6, 100.0)); steps.append({"op": "observe", "profile": P("m", 1, 0.6, 0.6, 100.0), "nowUs": us(0.6), "expect": expect(sim, r), "note": "fence rebuilt after restore -> repeated-profile"})
sim2 = Actuator(Actuator.base_config())
sim2.tick(qt(0.4))
r = sim2.tick(qt(0.5))
steps.append({"op": "freshStaleTick", "nowUs": us(0.5), "expect": expect(sim2, r), "note": "no observe yet: second tick -> stale (last_t nil)"})
sim3 = Actuator(dict(Actuator.base_config(), qualified=False))
sim3.observe(P("u", 1, 0.0, 0.0, 100.0))
r = sim3.tick(qt(0.1))
steps.append({"op": "freshUnqualifiedTick", "profile": P("u", 1, 0.0, 0.0, 100.0), "nowUs": us(0.1), "expect": expect(sim3, r), "note": "unqualified: observe holds, tick holds unqualified again"})
vectors.append({"name": "LC6-negative-controls", "steps": steps})

out = sys.argv[1] if len(sys.argv) > 1 else "live-control-vectors.json"
with open(out, "w") as f:
    json.dump({"source": "photon-live-control.lua M.VERSION=1 SHA256 4b8ec6a5b8e2f23be36900fc95e9c34a87705673bf2bef4fec69789401da6b76",
               "derivation": "python-model-replay (MODEL-ONLY cross-check; NOT authoritative - authoritative reference is lua-reference/live-control-lua-reference.json)",
               "status": "landed-inert (model; Lua authoritative; no behaviour swap authorized)",
               "vectors": vectors}, f, indent=1)
print(f"wrote {out}: {len(vectors)} vectors, {sum(len(v['steps']) for v in vectors)} steps")
