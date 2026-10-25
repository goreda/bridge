#!/usr/bin/env python3
"""W-0083 requester-supplied fixture: scene/container pair generator.
Container 392x204; insets are PER SIDE: effective extent = (392-2i) x (204-2i).
12-pair default matrix: insets {0,24,48} x area scales {0.5,0.8,1.1,1.6},
scene aspect preserved from the effective extent, dims rounded to 0.1.
Interface-test rows (PROPOSED requester-side correction - NOT a ratified
contract change; the published W-0083 request text is unchanged):
  test_fail: scene 405x150 at inset 48 vs effective cap 296x108 -> must FAIL
             (both dimensions over; ratio_w = 405/296 = 1.368).
  test_pass: scene 392x204 at inset 0 vs its own stated cap 392x204 -> must PASS
             (exact fit; the cap is INCLUSIVE).
The published draft's "405-unit vs 297-unit" and "392x204.1" figures are
mis-stated (underivable from the matrix geometry under either inset reading);
the rows above are the requester side's PROPOSED corrected fixture/test,
pending independent lab acceptance.
Schema: one JSON per line {"pair":k,"inset":i,"scale":s,"scene":{"w":..,"h":..},
"container":{"w":392,"h":204},"effective":{"w":..,"h":..},"expect":"pass|fail"}.
"""
import json, math, sys

def run(outdir):
    lines = []
    k = 0
    for inset in (0, 24, 48):
        ew, eh = 392 - 2 * inset, 204 - 2 * inset
        for scale in (0.5, 0.8, 1.1, 1.6):
            f = math.sqrt(scale)
            sw, sh = round(ew * f, 1), round(eh * f, 1)
            over = sw > ew or sh > eh
            lines.append(json.dumps({"pair": k, "inset": inset, "scale": scale,
                                     "scene": {"w": sw, "h": sh},
                                     "container": {"w": 392, "h": 204},
                                     "effective": {"w": ew, "h": eh},
                                     "expect": "fail" if over else "pass"}, separators=(",", ":")))
            k += 1
    lines.append(json.dumps({"pair": "test_fail", "inset": 48, "scale": None,
                             "scene": {"w": 405.0, "h": 150.0},
                             "container": {"w": 392, "h": 204},
                             "effective": {"w": 296, "h": 108}, "expect": "fail"}, separators=(",", ":")))
    lines.append(json.dumps({"pair": "test_pass", "inset": 0, "scale": None,
                             "scene": {"w": 392.0, "h": 204.0},
                             "container": {"w": 392, "h": 204},
                             "effective": {"w": 392, "h": 204}, "expect": "pass"}, separators=(",", ":")))
    with open(f"{outdir}/scenes.jsonl", "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"w0083 OK pairs=12+2 effective insets 0/24/48 -> 392x204 / 344x156 / 296x108")

if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else ".")
