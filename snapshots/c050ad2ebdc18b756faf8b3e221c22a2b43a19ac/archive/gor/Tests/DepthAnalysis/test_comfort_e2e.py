"""End-to-end comfort pipeline regression pins (contract s27).

Full reference chain - depth -> shot comfort -> soft surround r3 ->
render SBS - under default (conv=0, full IPD, no clamp) vs comfort
(shot_comfort: median z_c, adaptive baseline, z_near clamp) params.

CG golden tier (ungated, 6 frames):
  disocclusion fill area: default 0.0118 -> comfort 0.0024 of footprint
  footprint black px: 0 both modes
  halo (s20 r3 ring metric): 5.95 -> 5.47 LSB, pin < 10 both
  flicker (s21 disparity jitter): 0.0180 -> 0.0057 px median

Subtitle/overlay tier (ungated): overlays composite POST-render at
identical canvas coords in both eyes: measured L/R shift exactly 0 px
(screen depth by construction), stamp bytes identical at the same
coords in both eyes, and independent of the depth map / clamp.

Live tier (gated on GOR_LIVE_ENTRY, 6 frames):
  fill 3.6e-4 -> 6.4e-6, jitter 0.056 -> 0.042 px, halo unchanged
  (top-side ~23 LSB both modes: bright top boundary vs r3
  global-average surround trend - content, not a comfort regression).

Run: python3 Tests/DepthAnalysis/test_comfort_e2e.py
"""
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DA = os.path.join(HERE, "..", "..", "tools", "depth_analysis")
GOLD = os.path.join(DA, "golden", "entry_cg_vr180")
sys.path.insert(0, DA)

import comfort_e2e


def check_pair(md, mc, label, cg):
    assert md["footprint_black"] == 0 and mc["footprint_black"] == 0
    assert mc["fill_frac"] < md["fill_frac"], (label, md, mc)
    assert mc["halo_lsb"] <= md["halo_lsb"] + 0.5, (label, md, mc)
    assert (mc["disp_jitter"]["median"]
            < md["disp_jitter"]["median"]), (label, md, mc)
    if cg:
        assert md["fill_frac"] <= 0.02 and mc["fill_frac"] <= 0.005, (md, mc)
        assert md["halo_lsb"] < 10.0 and mc["halo_lsb"] < 10.0, (md, mc)
        assert md["disp_jitter"]["median"] <= 0.03, md
        assert mc["disp_jitter"]["median"] <= 0.012, mc
    print(f"PASS {label}: fill {md['fill_frac']:.4f}->{mc['fill_frac']:.4f}, "
          f"halo {md['halo_lsb']:.2f}->{mc['halo_lsb']:.2f} LSB, "
          f"jitter {md['disp_jitter']['median']:.4f}"
          f"->{mc['disp_jitter']['median']:.4f} px, black 0")


def main():
    # --- CG golden tier ---------------------------------------------------
    _, _, md = comfort_e2e.run_case(GOLD, 0, "default", max_frames=6)
    sbs_c, info, mc = comfort_e2e.run_case(GOLD, 0, "comfort", max_frames=6)
    check_pair(md, mc, "CG e2e default->comfort", cg=True)

    # --- subtitle/overlay audit -------------------------------------------
    stamped, box = comfort_e2e.overlay_stamp(sbs_c[0])
    shift = comfort_e2e.overlay_disparity(stamped, box)
    assert shift == 0.0, shift  # zero angular disparity = screen depth
    r0, r1, c0, c1 = box
    ow = stamped.shape[1] // 2
    np.testing.assert_array_equal(stamped[r0:r1, c0:c1],
                                  stamped[r0:r1, ow + c0:ow + c1])
    # the stamp is post-render: identical regardless of depth map or clamp
    sbs_d, _, _ = comfort_e2e.run_case(GOLD, 0, "default", max_frames=1)
    stamped_d, _ = comfort_e2e.overlay_stamp(sbs_d[0])
    np.testing.assert_array_equal(stamped_d[r0:r1, c0:c1],
                                  stamped[r0:r1, c0:c1])
    print("PASS overlay: L/R shift 0.00 px (screen depth), eyes identical, "
          "post-render (depth map never touches it)")

    # --- live tier ----------------------------------------------------------
    entry = os.environ.get("GOR_LIVE_ENTRY", "/tmp/bench190v/entry")
    if not os.path.isdir(entry):
        print("live tier SKIPPED (no bench entry; set GOR_LIVE_ENTRY)")
        print("ALL COMFORT-E2E TESTS PASS")
        return
    _, _, mdl = comfort_e2e.run_case(entry, 0, "default", max_frames=int(os.environ.get("GOR_E2E_LIVE_FRAMES", "6")))
    _, _, mcl = comfort_e2e.run_case(entry, 0, "comfort", max_frames=int(os.environ.get("GOR_E2E_LIVE_FRAMES", "6")))
    check_pair(mdl, mcl, "live e2e default->comfort", cg=False)
    # comfort must not regress the surround halo on live content
    assert mcl["halo_lsb"] <= mdl["halo_lsb"] + 0.5, (mdl, mcl)
    print("ALL COMFORT-E2E TESTS PASS")


if __name__ == "__main__":
    main()
