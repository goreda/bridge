"""s32 self-diagnosing Mac run: rtstage verdict vs the rt_budget model.

Pins the s32 log-line contract (CONTRACT-190v s32) and the comparator
extension in selftest_check.py using the committed fixture pair
(golden/selftest_fixture/rt_pass.log, rt_fail.log):
- pass log: every stage within the ratio window -> exit 0, verdict
  table carries all 7 stages + the thermal readings;
- fail log: missing surround rtstage -> exit 1 naming the missing
  stage; moge ratio 12.2 -> REVISE line naming the MoGe assumption.

Run: python3 Tests/DepthAnalysis/test_selftest_rt.py
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, "..", "..", "tools", "depth_analysis",
                     "selftest_check.py")
FIX = os.path.join(HERE, "..", "..", "tools", "depth_analysis",
                   "golden", "selftest_fixture")

STAGES = ("vda", "moge", "upsample", "surround", "render",
          "vt_decode", "vt_encode")


def run(log):
    return subprocess.run([sys.executable, CHECK, os.path.join(FIX, log)],
                          capture_output=True, text=True)


def main():
    p = run("rt_pass.log")
    assert p.returncode == 0, p.stdout + p.stderr
    for s in STAGES:
        assert f"  {s:10s} model" in p.stdout, (s, p.stdout)
    assert "thermal: peak level 1 transitions 1" in p.stdout
    assert "REVISE" not in p.stdout
    assert "ratio   1.15  ok" in p.stdout  # vda row pinned
    print("PASS fixture: all 7 stages ok, thermal in table, exit 0")

    f = run("rt_fail.log")
    assert f.returncode == 1, f.stdout + f.stderr
    assert "rtstage surround: line MISSING" in f.stdout
    assert "ratio  12.22  REVISE" in f.stdout
    assert "revise assumption: MoGe GFLOP/keyframe or package shape" \
        in f.stdout
    print("FAIL fixture: missing surround fails loudly; moge REVISE "
          "names the MoGe assumption; exit 1")
    print("ALL SELFTEST RT TESTS PASS")


if __name__ == "__main__":
    main()
