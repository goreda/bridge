"""s40: first-Mac-run log checker (CONTRACT-190v s39 13-line checklist).

Takes a gor log from the owner's Mac and checks it line-family by
line-family against the s39 pass checklist. Per family prints
PASS / MISSING / FORMAT-BUG / FAIL plus the load-bearing numbers
(thermal peak, rtstage table vs the rt_budget model, fps, depth stats):

  PASS        family present, well-formed, within policy
  MISSING     family absent - the Mac build did not emit it (format bug
              on the Mac side OR a truncated log)
  FORMAT-BUG  family present but malformed - fix the format before any
              number is read (diff rule, s39)
  FAIL        well-formed but out of policy/budget (a real finding)

Exit 0 = every family PASS; 1 = any MISSING/FORMAT-BUG/FAIL;
2 = no gor3d-selftest v1 lines at all.

CLI: python3 mac_log_check.py LOG [--expected PATH] [--json]
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import degrade_fsm as fsm  # noqa: E402
import selftest_check as stc  # noqa: E402

FSM_RE = re.compile(r"3dfsm from=([A-Z_]+) ev=([a-z_0-9]+) to=([A-Z_]+) "
                    r"act=\S+( note=.*)?$")
KEY_V3_RE = re.compile(
    r"^v3\|(comfort\|ipd[\d.eE+-]+\|sf[\d.eE+-]+|fixed\|ipd[\d.eE+-]+)"
    r"\|[\w]+\|[^|]+\|\d+\|[\w-]+\|(True|False)\|[\d.eE+-]+"
    r"\|(True|False)\|[^|]+$")
KEY_V4_RE = re.compile(
    r"^v4\|(mlbw_l2_inpaint_video|mlbw_l2_inpaint|row_flow_v3|dibr_golden)"
    r"\|(comfort\|ipd[\d.eE+-]+\|sf[\d.eE+-]+|fixed\|ipd[\d.eE+-]+)"
    r"\|[\w]+\|[^|]+\|\d+\|[\w-]+\|(True|False)\|[\d.eE+-]+"
    r"\|(True|False)\|[^|]+$")  # 190w W3: v3 body + method field


class Family:
    def __init__(self, name):
        self.name, self.status, self.lines = name, "PASS", []

    def fail(self, status, line):
        order = {"PASS": 0, "FAIL": 1, "FORMAT-BUG": 2, "MISSING": 3}
        if order[status] > order[self.status]:
            self.status = status
        self.lines.append(f"    {status}: {line}")

    def note(self, line):
        self.lines.append(f"    {line}")

    def render(self):
        return [f"  [{self.status:9s}] {self.name}"] + self.lines


def f_lifecycle(run, _lines, _exp):
    f = Family("1 lifecycle (begin/end)")
    if run["ended"]:
        f.note(f"begin header '{run['header'].splitlines()[0]}...', "
               f"end errors={run['end_errors']}")
        if run["end_errors"] not in (None, len(run["errors"])):
            f.fail("FAIL", f"end errors={run['end_errors']} != "
                           f"{len(run['errors'])} error lines (log truncated)")
    else:
        f.fail("MISSING", "no `end errors=N` line (run interrupted?)")
    return f


def f_clip(run, _lines, _exp):
    f = Family("2 clip note + fps")
    decl = stc.clip_decl(run["notes"])
    if "clip" not in run["notes"]:
        f.fail("MISSING", "note key=clip absent")
    elif not decl:
        f.fail("FORMAT-BUG", f"clip note '{run['notes']['clip']}' does not "
                             "match '<W>x<H> <N>f @<fps> ...'")
    else:
        m = re.search(r"@([\d.]+)", run["notes"]["clip"])
        f.note(f"{decl[0]}x{decl[1]} {decl[2]}f @ {m.group(1) if m else '?'} fps")
    return f


def f_stages(run, _lines, exp):
    f = Family("3 stage budgets")
    for name, budget in exp["stage_budgets_ms"].items():
        st = run["stages"].get(name)
        if st is None:
            f.fail("MISSING", f"stage {name}: no line")
        elif not st["ms"] <= budget:
            f.fail("FAIL", f"stage {name}: {st['ms']:.0f} ms over budget "
                           f"{budget} ms")
        else:
            f.note(f"{name} {st['ms']:.0f} ms (budget {budget})")
    return f


def f_rtstages(run, _lines, _exp):
    f = Family("4+5 rtstage table + rt_config")
    if run["notes"].get("rt_config") is None and not run["rtstages"]:
        f.fail("MISSING", "no rtstage lines and no rt_config note")
        return f
    lines, fails = stc.check_rt(run)
    for l in lines:
        f.note(l.strip())
    for l in fails:
        f.fail("MISSING" if "MISSING" in l else "FAIL", l)
    if run["notes"].get("rt_config") is None:
        f.fail("MISSING", "note key=rt_config absent")
    return f


def f_thermal(run, _lines, exp):
    f = Family("6 thermal (heat)")
    if run["peak"] is None:
        f.fail("MISSING", "thermal_peak line absent")
    else:
        f.note(f"peak level {run['peak']} transitions {run['transitions']} "
               f"({len(run['thermal'])} readings)")
        if run["peak"] > exp["thermal"]["peak_level_max"]:
            f.fail("FAIL", f"peak level {run['peak']} exceeds s19 policy "
                           f"max {exp['thermal']['peak_level_max']}")
    return f


def f_precision(run, _lines, _exp):
    f = Family("7 moge_precision")
    prec = run["notes"].get("moge_precision")
    if prec is None:
        f.fail("MISSING", "note key=moge_precision absent")
        return f
    pm = dict(p.split("=") for p in prec.split() if "=" in p)
    try:
        u16, u32 = int(pm.get("fp16_used", 0)), int(pm.get("fp32_used", 0))
        rej = int(pm.get("fp16_rejected", 0))
    except ValueError:
        f.fail("FORMAT-BUG", f"unparseable: {prec}")
        return f
    f.note(f"fp16_used={u16} fp32_used={u32} fp16_rejected={rej}")
    if u16 + u32 == 0:
        f.fail("FAIL", "no fp16 and no fp32 weights ran")
    if rej:
        f.fail("FAIL", f"fp16 weights rejected {rej} time(s)")
    return f


def f_depth(run, _lines, exp):
    f = Family("8 depth stats")
    d = run["depth"]
    if d is None:
        f.fail("MISSING", "depth line absent")
        return f
    decl = stc.clip_decl(run["notes"])
    want = None
    if decl:
        bw, bh = stc.letterbox(decl[0], decl[1])
        want = decl[2] * bw * bh
    f.note(f"min={d['min']:g} max={d['max']:g} nan={d['nan']} inf={d['inf']} "
           f"count={d['count']}" + (f" (want {want})" if want else ""))
    for key in ("min", "max"):
        if d[key] != d[key]:  # nan
            f.fail("FORMAT-BUG", f"depth {key} unparseable")
    if d["nan"] != 0 or d["inf"] != 0:
        f.fail("FAIL", f"nan={d['nan']} inf={d['inf']}")
    if not (d["min"] > exp["depth"]["min_exclusive"]):
        f.fail("FAIL", f"min {d['min']} not positive")
    if not (d["max"] < exp["depth"]["max_exclusive"]):
        f.fail("FAIL", f"max {d['max']} out of range")
    if d["min"] >= d["max"]:
        f.fail("FAIL", f"min {d['min']} >= max {d['max']}")
    if want is not None and d["count"] != want:
        f.fail("FAIL", f"count {d['count']} != {want} (frames x letterbox "
                       "picture)")
    return f


def f_sha(run, _lines, _exp):
    f = Family("9 first_3d_frame_sha256")
    h = run["notes"].get("first_3d_frame_sha256")
    if h is None:
        f.fail("MISSING", "note absent")
    elif not re.fullmatch(r"[0-9a-f]{64}", h):
        f.fail("FORMAT-BUG", f"not 64 lowercase hex: {h[:24]}...")
    else:
        f.note(h[:16] + "... (presence+format; bit-exact never required)")
    return f


def f_jitter(run, _lines, _exp):
    f = Family("10 jitter_rel (s35)")
    v = run["notes"].get("jitter_rel")
    if v is None:
        f.fail("MISSING", "note key=jitter_rel absent (s35 selftest contract)")
        return f
    try:
        j = float(v.split()[0])
    except (ValueError, IndexError):
        f.fail("FORMAT-BUG", f"unparseable: {v[:32]}")
        return f
    health = "healthy <0.05" if j < 0.05 else "HIGH - see s35 dark/noisy finding"
    f.note(f"jitter_rel={j:.4f} ({health})")
    return f


def f_render_key(run, _lines, _exp):
    f = Family("11 render_key_v4 (190w W3)")
    v = run["notes"].get("render_key_v4")
    if v is None:
        f.fail("MISSING", "note key=render_key_v4 absent")
    elif not KEY_V4_RE.match(v):
        f.fail("FORMAT-BUG", f"not the 190w v4 shape: {v[:48]}...")
    else:
        f.note(v)
    return f


def f_fsm(run, lines, _exp):
    f = Family("12 3dfsm transitions (s38)")
    found, bad = 0, []
    for line in lines:
        if "3dfsm " not in line:
            continue
        m = FSM_RE.search(line)
        if not m:
            bad.append(line.strip()[:64])
            continue
        found += 1
        if m.group(1) not in fsm.STATES or m.group(3) not in fsm.STATES:
            bad.append(f"unknown state: {m.group(1)}->{m.group(3)}")
        elif m.group(2) not in fsm.EVENTS:
            bad.append(f"unknown event: {m.group(2)}")
    if bad:
        for b in bad[:3]:
            f.fail("FORMAT-BUG", b)
    if not found:
        f.fail("MISSING", "no 3dfsm transition lines")
    else:
        f.note(f"{found} transition lines, all well-formed"
               if not bad else f"{found} well-formed, {len(bad)} broken")
    return f


def f_errors(run, _lines, exp):
    f = Family("13 error bucketing")
    if not run["errors"]:
        f.note("no error lines")
        return f
    for name, errs in stc.bucket_errors(run["errors"],
                                       exp["error_buckets"]).items():
        for e in errs:
            f.fail("FAIL", f"error[{name}]: {e[:72]}")
    return f


FAMILIES = (f_lifecycle, f_clip, f_stages, f_rtstages, f_thermal,
            f_precision, f_depth, f_sha, f_jitter, f_render_key,
            f_fsm, f_errors)


def check_log(log_lines, exp):
    """-> (per-run [[Family, ...]], ) None when no selftest runs found."""
    runs = stc.parse_runs(log_lines)
    if not runs:
        return None
    return [[fn(run, log_lines, exp) for fn in FAMILIES] for run in runs]


def main():
    args = sys.argv[1:]
    log_path = args[0]
    exp_path = (args[args.index("--expected") + 1]
                if "--expected" in args else stc.EXPECTED)
    exp = json.load(open(exp_path))
    lines = open(log_path, errors="replace").read().splitlines()
    per_run = check_log(lines, exp)
    if per_run is None:
        print("no gor3d-selftest v1 lines in the log")
        sys.exit(2)
    worst = 0
    out = {"runs": []}
    for i, fams in enumerate(per_run):
        print(f"run {i}: s39 first-run checklist")
        for fam in fams:
            for l in fam.render():
                print(l)
            if fam.status != "PASS":
                worst = 1
        out["runs"].append({fam.name: fam.status for fam in fams})
    if "--json" in args:
        print(json.dumps(out))
    print("MAC-LOG PASS" if worst == 0 else "MAC-LOG FAIL")
    sys.exit(worst)


if __name__ == "__main__":
    main()
