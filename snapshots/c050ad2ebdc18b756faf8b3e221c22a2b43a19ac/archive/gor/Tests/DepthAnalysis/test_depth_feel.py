#!/usr/bin/env python3
"""Depth-feel measurement pins (owner 17:07, 190v): the F3 span policy
visibly increases depth feel over the current baseline on the committed
CG golden, inside the same comfort budgets. Numbers are pinned to
tools/depth_analysis/golden/DEPTH-FEEL-1707.md.

Run: python3 Tests/DepthAnalysis/test_depth_feel.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "depth_analysis"))

import comfort
import depth_feel_report as rep


def main():
    rows = rep.main()                      # also prints the table
    cg = rows[0]
    assert cg["shot"].startswith("CG golden"), cg
    # pinned CG numbers (DEPTH-FEEL-1707.md)
    assert abs(cg["base_scale"] - 0.31) < 0.01, cg
    assert abs(cg["span_gain"] - 0.93) < 0.01, cg
    assert abs(cg["base_span_deg"] - 0.84) < 0.02, cg
    assert abs(cg["span_span_deg"] - 2.46) < 0.02, cg
    # the owner-facing property: depth feel roughly triples
    assert cg["span_span_deg"] >= 2.5 * cg["base_span_deg"], cg
    # budgets hold by construction; near clamp cost stays small
    assert cg["span_crossed_max"] <= comfort.NEAR_BUDGET + 1e-9, cg
    assert cg["span_uncrossed_min"] >= -comfort.FAR_BUDGET - 1e-9, cg
    assert cg["span_clamped_frac"] <= 0.06, cg
    # the mirror carries the render clamp the wiring needs
    sp = comfort.shot_comfort_span_values(0.8, 12.0, 2.5)
    assert abs(sp["near_clamp_m"]
               - comfort.near_clamp(2.5, comfort.IPD * sp["gain"])) < 1e-12
    print("ALL DEPTH-FEEL TESTS PASS")


if __name__ == "__main__":
    main()
