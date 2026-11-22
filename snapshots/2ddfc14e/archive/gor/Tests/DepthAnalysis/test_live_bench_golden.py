"""Live bench golden pin (contract s11/s20).

tools/depth_analysis/golden/render_bench_live.json holds the Python
reference SBS for 8 frames of the real live-bench prepared shot
(1280x720, eye_n 720, surround soft). The bench entry is too large to
commit, so this test is two-tier:

- ungated: the committed manifest is internally consistent (fields,
  hash shapes, Mac-default parity params);
- full tier (GOR_FULL_GOLDEN=1) gated on the bench entry (env
  GOR_LIVE_ENTRY, default /tmp/bench190v/entry): lean re-render of the
  8 frames through the same render_shot_sbs path, sequence hash must
  match exactly.

Run: python3 Tests/DepthAnalysis/test_live_bench_golden.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAN = os.path.join(HERE, "..", "..", "tools", "depth_analysis", "golden",
                   "render_bench_live.json")
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))

HEX64 = lambda s: isinstance(s, str) and len(s) == 64 and all(
    c in "0123456789abcdef" for c in s)


def main():
    man = json.load(open(MAN))
    # internal consistency (ungated)
    assert man["frames"] == 8 and len(man["frame_sha256"]) == 8
    assert HEX64(man["sequence_sha256"])
    assert all(HEX64(h) for h in man["frame_sha256"])
    assert man["screen_deg"] == 75.0 and man["theta_h_deg"] == 75.0
    assert man["swap_eyes"] is True and man["surround"] == "soft"
    assert man["out_w"] == man["out_h"] == 720  # eye_n_for(720)
    assert man["ipd"] == 0.063 and man["depth_scale"] == 1.0
    assert man["convergence_m"] == 2.0
    pp = man["parity_params"]
    assert pp["eye_n"] == 720 and pp["swap_eyes"] is True
    assert pp["screen_deg"] == 75.0 and pp["convergence_m"] == 2.0
    print("manifest consistency: PASS (8 frames, 720^2 eyes, seq "
          + man["sequence_sha256"][:16] + ")")

    if os.environ.get("GOR_FULL_GOLDEN") != "1":
        print("hash re-render SKIPPED (fast tier; GOR_FULL_GOLDEN=1 to run)")
        return
    entry = os.environ.get("GOR_LIVE_ENTRY", "/tmp/bench190v/entry")
    if not os.path.isdir(entry):
        print("bench entry not present (" + entry + "); hash re-render "
              "SKIPPED (set GOR_LIVE_ENTRY)")
        return
    from reference_render import golden_manifest, render_shot_sbs
    sbs, info = render_shot_sbs(entry, 0, ipd=0.063, convergence_m=2.0,
                                swap_eyes=True, max_frames=8)
    man2 = golden_manifest(sbs, info)
    assert man2["sequence_sha256"] == man["sequence_sha256"], \
        (man2["sequence_sha256"], man["sequence_sha256"])
    assert man2["frame_sha256"] == man["frame_sha256"]
    print("hash-locked re-render: PASS (seq "
          + man2["sequence_sha256"][:16] + ")")


if __name__ == "__main__":
    main()
