"""Thermal budget pins (contract s19 + 93C audit).

Run: python3 Tests/DepthAnalysis/test_thermal_budget.py
"""
import os
import sys

sys.path.insert(0, os.path.join(HERE := os.path.dirname(
    os.path.abspath(__file__)), "..", "..", "tools", "depth_analysis"))

import thermal_budget as tb


def main():
    # s19 op-count pins (the contract numbers, executable)
    assert tb.VDA_S_GFLOP_FRAME == 79.0
    assert tb.MOGE_GFLOP_KF_169 == 74.0 and tb.MOGE_GFLOP_KF_VR180 == 148.0
    tf = tb.sustained_tflops(vr180=True)
    assert abs(tf - tb.S19_WORST_TFLOPS) < 0.05, tf  # 1.90 + 0.59 ~ 2.5

    # 93C audit: the compliant config stays well under the serious
    # onset; reaching 93C needs >= 2x the s19 worst case
    rows = tb.audit_93c()
    compliant = rows[0]
    assert compliant["vs_serious_onset"] == "below", compliant
    assert compliant["package_w_est"] <= 0.6 * tb.SERIOUS_ONSET_W, compliant
    violations = [r for r in rows if r["case"].startswith("VIOLATION")]
    assert any(r["x_s19_worst"] >= 2.0 and
               r["vs_serious_onset"] == "AT/ABOVE" for r in violations), \
        violations

    # config guard
    assert tb.validate_config() == []
    assert tb.validate_config(moge_stride=1) != []
    assert tb.validate_config(vda_fps=48) != []
    print("test_thermal_budget: PASS (s19 pins, 93C needs >=2x worst "
          "case, config guard)")


if __name__ == "__main__":
    main()
