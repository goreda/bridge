"""Receiving comparator for the Mac 3D self-test (contract s23).

Reads the owner's gor log, picks out the `gor3d-selftest v1` lines
(E-G's PrepareTelemetry format; substring match anywhere in the line,
same as the Swift parse), reconstructs each run, and checks it against
selftest_expected.json: stage-time budgets, thermal peak vs the s19
policy, fp16-vs-fallback precision, depth min/max/nan/inf sanity, the
first_3d_frame_sha256 rule (presence/format; bit-exact only against a
recorded same-machine reference, mismatch = warning, never a fail -
see the expected file), and every error verbatim, bucketed
gh/kit/coreml_load/compute_plan/other.

Output: a short English finding list the architect inbox can take.

CLI: python3 selftest_check.py LOG [--expected PATH] [--json]
exit 0 = PASS, 1 = FAIL, 2 = no self-test lines in the log.
"""
import json
import os
import re
import sys

PREFIX = "gor3d-selftest v1 "
HERE = os.path.dirname(os.path.abspath(__file__))
EXPECTED = os.path.join(HERE, "selftest_expected.json")


def unescape(s):
    """PrepareTelemetry.unescape: \\n, \\r, and \\<c> -> <c>."""
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append("\n" if n == "n" else "\r" if n == "r" else n)
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def _num(s):
    v = {"nan": float("nan"), "inf": float("inf"),
         "-inf": float("-inf")}.get(s)
    if v is not None:
        return v
    try:
        return float(s)
    except (TypeError, ValueError):
        return float("nan")


def parse_runs(log_lines):
    """Port of PrepareTelemetry.parse, split into runs at each begin."""
    runs, cur = [], None
    for line in log_lines:
        i = line.find(PREFIX)
        if i < 0:
            continue
        rest = line[i + len(PREFIX):].rstrip("\n")
        if rest.startswith("begin "):
            cur = {"header": unescape(rest[6:]), "stages": {},
                   "rtstages": {},
                   "thermal": [], "peak": None, "transitions": None,
                   "depth": None, "notes": {}, "errors": [],
                   "ended": False, "end_errors": None}
            runs.append(cur)
        elif cur is None:
            continue
        elif rest.startswith("stage "):
            d = _kv(rest[6:])
            cur["stages"][d.get("name", "?")] = {
                "ms": _num(d.get("ms", "nan")),
                "n": int(d.get("n", "0")),
                "max_ms": _num(d.get("max_ms", "nan"))}
        elif rest.startswith("rtstage "):
            # s32: per-stage real-time ms, compared against the
            # rt_budget model (not the flat v1 budgets)
            d = _kv(rest[8:])
            cur["rtstages"][d.get("name", "?")] = {
                "ms": _num(d.get("ms", "nan")),
                "n": int(d.get("n", "0")),
                "max_ms": _num(d.get("max_ms", "nan"))}
        elif rest.startswith("thermal_peak "):
            d = _kv(rest[13:])
            cur["peak"] = int(d.get("level", "-2"))
            cur["transitions"] = int(d.get("transitions", "-1"))
        elif rest.startswith("thermal "):
            d = _kv(rest[8:])
            cur["thermal"].append((int(d.get("level", "-1")),
                                   _num(d.get("t_ms", "nan"))))
        elif rest.startswith("depth "):
            d = _kv(rest[6:])
            cur["depth"] = {"min": _num(d.get("min", "nan")),
                            "max": _num(d.get("max", "nan")),
                            "nan": int(d.get("nan", "0")),
                            "inf": int(d.get("inf", "0")),
                            "count": int(d.get("count", "0"))}
        elif rest.startswith("note key="):
            t = rest[9:]
            j = t.find(" value=")
            if j >= 0:
                cur["notes"][t[:j]] = unescape(t[j + 7:])
        elif rest.startswith("error i="):
            j = rest.find(" msg=")
            if j >= 0:
                cur["errors"].append(unescape(rest[j + 5:]))
        elif rest.startswith("end "):
            d = _kv(rest[4:])
            cur["ended"] = True
            cur["end_errors"] = int(d.get("errors", "0"))
    return runs


def _kv(s):
    d = {}
    for part in s.split(" "):
        if "=" in part:
            k, v = part.split("=", 1)
            d[k] = v
    return d


def letterbox(src_w, src_h, w=266, h=154):
    """Port of VDAStream.letterbox / preprocess_aspect: uniform scale,
    half-to-even rounding. Depth is cropped to this box (s22/ce1ab092),
    so per-frame depth count = nw*nh, not 266*154."""
    scale = min(w / src_w, h / src_h)
    return max(1, round(src_w * scale)), max(1, round(src_h * scale))


def clip_decl(notes):
    """(w, h, frames) from the clip note '640x360 36f @24.0 synthetic'."""
    m = re.search(r"(\d+)x(\d+)\s+(\d+)f", notes.get("clip", ""))
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def bucket_errors(errors, buckets):
    out = {}
    for e in errors:
        for name, pat in buckets.items():
            if re.search(pat, e):
                out.setdefault(name, []).append(e)
                break
    return out


# s32 ratio window: the model is coarse (stated M1 util estimates);
# inside it the stage agrees with the model, outside it the named
# assumption needs revising. Missing lines always fail loudly.
RT_RATIO_LO, RT_RATIO_HI = 0.25, 4.0


def rt_config(run):
    """(fps, vr180, depth_rate, surround_opt) from the rt_config note,
    'fps=24.0 vr180=true depth_rate=12.0 surround_opt=false'; defaults
    per the shipping config."""
    raw = run["notes"].get("rt_config")
    if raw is None:
        return None
    d = dict(p.split("=", 1) for p in raw.split() if "=" in p)
    return {"fps": _num(d.get("fps", "24")),
            "vr180": d.get("vr180", "false") == "true",
            "depth_rate": (_num(d["depth_rate"])
                           if "depth_rate" in d else None),
            "surround_opt": d.get("surround_opt", "false") == "true"}


def check_rt(run):
    """s32 verdict table vs the rt_budget model. -> (lines, fails).

    Active when the run declares rt_config or emitted any rtstage
    line; then EVERY model stage must have a line (missing = fail).
    """
    cfg = rt_config(run)
    if cfg is None and not run["rtstages"]:
        return [], []
    import rt_budget as rtb
    if cfg is None:
        cfg = {"fps": 24.0, "vr180": False, "depth_rate": None,
               "surround_opt": False}
    model = rtb.expected_stage_ms(cfg["fps"], cfg["vr180"],
                                  cfg["depth_rate"], cfg["surround_opt"])
    lines = [f"s32 real-time stages vs rt_budget model (fps={cfg['fps']:g} "
             f"vr180={cfg['vr180']} depth_rate={cfg['depth_rate']} "
             f"surround_opt={cfg['surround_opt']}):"]
    fails = []
    for name in rtb.RT_STAGES:
        st = run["rtstages"].get(name)
        if st is None:
            fails.append(f"rtstage {name}: line MISSING (the s32 log "
                         f"contract requires every stage)")
            continue
        exp_ms = model[name]
        ratio = st["ms"] / exp_ms if exp_ms > 0 else float("nan")
        tag = "ok" if RT_RATIO_LO <= ratio <= RT_RATIO_HI else "REVISE"
        lines.append(f"  {name:10s} model {exp_ms:7.2f} ms  measured "
                     f"{st['ms']:8.2f} ms  ratio {ratio:6.2f}  {tag}")
        if tag == "REVISE":
            lines.append(f"      -> revise assumption: "
                         f"{rtb.RT_ASSUMPTION[name]}")
    # thermal readings alongside the stage table
    if run["peak"] is not None:
        series = "; ".join(f"l{l}@{t:.0f}ms" for l, t in run["thermal"][:6])
        lines.append(f"  thermal: peak level {run['peak']} "
                     f"transitions {run['transitions']}"
                     + (f"  series [{series}]" if series else ""))
    else:
        fails.append("thermal_peak line missing (s32 verdict needs the "
                     "thermal readings)")
    return lines, fails


def check_run(run, exp):
    """-> (findings, fails): findings are short English lines."""
    f, bad = [], []
    n = run["notes"]
    if not run["ended"]:
        bad.append("run did not emit an end line (interrupted?)")
    if run["end_errors"] not in (None, len(run["errors"])):
        bad.append(f"end errors={run['end_errors']} != {len(run['errors'])} "
                   "error lines (log truncated)")
    for name, budget in exp["stage_budgets_ms"].items():
        st = run["stages"].get(name)
        if st is None:
            bad.append(f"stage {name}: missing")
        elif not (st["ms"] <= budget):
            bad.append(f"stage {name}: {st['ms']:.0f} ms over budget "
                       f"{budget} ms")
    peak = run["peak"]
    if peak is None:
        bad.append("thermal_peak line missing")
    elif peak > exp["thermal"]["peak_level_max"]:
        bad.append(f"thermal peak level {peak} exceeds policy max "
                   f"{exp['thermal']['peak_level_max']} (s19)")
    prec = n.get("moge_precision", "")
    pm = dict(p.split("=") for p in prec.split() if "=" in p)
    used16, used32 = int(pm.get("fp16_used", 0)), int(pm.get("fp32_used", 0))
    rej = int(pm.get("fp16_rejected", 0))
    if used16 + used32 == 0:
        bad.append("moge_precision: no fp16 and no fp32 weights ran")
    if rej:
        f.append(f"fp16 weights rejected {rej} time(s); "
                 f"fp32 fallback used={used32}")
    d = run["depth"]
    if d is None:
        bad.append("depth stats line missing")
    else:
        decl = clip_decl(n)
        if decl:
            cw, ch, cf = decl
            bw, bh = letterbox(cw, ch)
            want, why = cf * bw * bh, (f"{cf}f x {bw}x{bh} letterbox "
                                       f"picture of {cw}x{ch}")
        else:
            want = (exp["clip"]["frames"] * exp["clip"]["depth_w"]
                    * exp["clip"]["depth_h"])
            why = (f"{exp['clip']['frames']}f x full "
                   f"{exp['clip']['depth_w']}x{exp['clip']['depth_h']} "
                   "canvas (no clip note; pre-letterbox build?)")
            f.append("no clip note: depth count checked against the "
                     "full 266x154 canvas - a ce1ab092+ build crops to "
                     "the letterbox picture")
        if d["nan"] != exp["depth"]["nan"] or d["inf"] != exp["depth"]["inf"]:
            bad.append(f"depth sanity: nan={d['nan']} inf={d['inf']}")
        if not (d["min"] > exp["depth"]["min_exclusive"]):
            bad.append(f"depth min {d['min']} not positive")
        if not (d["max"] < exp["depth"]["max_exclusive"]):
            bad.append(f"depth max {d['max']} out of range")
        if d["min"] >= d["max"]:
            bad.append(f"depth min {d['min']} >= max {d['max']}")
        if d["count"] != want:
            bad.append(f"depth count {d['count']} != expected {want} ({why})")
    h = n.get("first_3d_frame_sha256")
    rule = exp["first_3d_frame_sha256"]
    if h is None:
        bad.append("first_3d_frame_sha256 note missing")
    elif not re.fullmatch(r"[0-9a-f]{64}", h):
        bad.append(f"first_3d_frame_sha256 malformed: {h[:24]}...")
    elif rule.get("expect"):
        if h == rule["expect"]:
            f.append("first_3d_frame_sha256 matches the recorded reference")
        else:
            f.append("first_3d_frame_sha256 DIFFERS from the recorded "
                     "reference (bit-exact only pins same-machine "
                     "same-build reruns; investigate only with other "
                     "symptoms)")
    for name, errs in bucket_errors(run["errors"],
                                    exp["error_buckets"]).items():
        for e in errs:
            bad.append(f"error[{name}]: {e}")
    rt_lines, rt_fails = check_rt(run)
    f.extend(rt_lines)
    bad.extend(rt_fails)
    return f, bad


def evaluate(log_lines, exp):
    runs = parse_runs(log_lines)
    if not runs:
        return None
    out = []
    for i, run in enumerate(runs):
        findings, fails = check_run(run, exp)
        out.append({"run": i, "header": run["header"],
                    "findings": findings, "fails": fails,
                    "verdict": "FAIL" if fails else "PASS"})
    return out


def main():
    args = sys.argv[1:]
    log_path = args[0]
    exp_path = (args[args.index("--expected") + 1]
                if "--expected" in args else EXPECTED)
    exp = json.load(open(exp_path))
    lines = open(log_path, errors="replace").read().splitlines()
    results = evaluate(lines, exp)
    if results is None:
        print("no gor3d-selftest v1 lines in the log")
        sys.exit(2)
    worst = 0
    for r in results:
        print(f"run {r['run']} ({r['header']}): {r['verdict']}")
        for line in r["findings"]:
            print(f"  note: {line}")
        for line in r["fails"]:
            print(f"  FAIL: {line}")
        worst = max(worst, 1 if r["verdict"] == "FAIL" else 0)
    sys.exit(worst)


if __name__ == "__main__":
    main()
