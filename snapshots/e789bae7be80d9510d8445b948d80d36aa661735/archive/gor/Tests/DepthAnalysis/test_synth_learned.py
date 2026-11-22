"""Licence-gate test for the learned synthesis wrapper (CONTRACT-190v s5).
The gate must refuse without GOR_NUNIF_LOCAL=1; with the flag and weights it
synthesizes (skipped when torch/nunif/weights are unavailable, e.g. CI)."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..",
                                "tools", "depth_analysis"))
import synth_learned  # noqa: E402


def test_gate_refuses_without_flag():
    os.environ.pop("GOR_NUNIF_LOCAL", None)
    synth_learned._MODEL = None
    rgb = np.zeros((8, 8, 3), np.uint8)
    try:
        synth_learned.synth_sbs_mlbw(rgb, np.ones((8, 8), np.float32))
        raise SystemExit("gate must refuse without GOR_NUNIF_LOCAL=1")
    except RuntimeError as ex:
        assert "section 5" in str(ex) and "local-only" in str(ex)
    print("PASS licence gate refuses without GOR_NUNIF_LOCAL=1")


def test_gate_refuses_missing_weights(tmp_path=None):
    os.environ["GOR_NUNIF_LOCAL"] = "1"
    synth_learned._MODEL = None
    try:
        synth_learned.synth_sbs_mlbw(np.zeros((8, 8, 3), np.uint8),
                                     np.ones((8, 8), np.float32),
                                     weights_dir="/nonexistent-nunif")
        raise SystemExit("gate must refuse when weights are absent")
    except RuntimeError as ex:
        assert "not found" in str(ex)
    print("PASS licence gate refuses when weights absent")


def test_synthesis_runs_when_gated_in():
    os.environ["GOR_NUNIF_LOCAL"] = "1"
    try:
        import torch  # noqa: F401
        w = os.path.join(os.environ.get("S4_MODELS",
                                        os.path.expanduser("~/s4/models")),
                         "nunif")
        if not os.path.exists(os.path.join(w, "iw3_mlbw_l2_d1_20250627.pth")):
            raise ImportError("weights absent")
    except Exception as ex:
        print(f"SKIP synthesis run: {ex}")
        return
    rng = np.random.default_rng(7)
    rgb = rng.integers(0, 256, (64, 96, 3), dtype=np.uint8)
    inv = np.linspace(0.1, 1.0, 64 * 96,
                      dtype=np.float32).reshape(64, 96)
    sbs = synth_learned.synth_sbs_mlbw(rgb, inv)
    assert sbs.shape == (64, 192, 3) and sbs.dtype == np.uint8
    assert sbs.sum() > 0
    print("PASS synthesis runs gated-in:", sbs.shape)


if __name__ == "__main__":
    test_gate_refuses_without_flag()
    test_gate_refuses_missing_weights()
    test_synthesis_runs_when_gated_in()
