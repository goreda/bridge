#!/usr/bin/env python3
"""190v (E-G 15:02): regenerate nunif_consumption_fixtures.npz with torch +
the real upstream weights (iw3 @ b1548e8, lock shas in models.lock.tsv).
Runs on a torch box only; the gate test (Tests/NunifMath) is torch-free.

Fixtures:
  rf_*  T3 row_flow_v3 consumption: apply_divergence_nn_LR / _nn_delta
        semantics (flip for the right eye, steps loop, final ordered warp)
        with the REAL RowFlowV3 delta (fp32, no AMP).
  rs_*  1080p -> model-input sizing: BaseInpaint._resize (SCALE, bilinear,
        antialias=True, align_corners=False, even rounding) -> 756x1344,
        then the video inpaint model's replication pad to 768x1408.
  lw_*  layer_weight resize: F.interpolate(bilinear, align_corners=True,
        antialias=True) cases (up/down) + one antialias=False contrast.
Every torch result is cross-checked against nunif_pipeline_reference.py
(numpy) at generation time; the gate re-checks the numpy side only.
"""
import pathlib
import sys

import numpy as np

KIT = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(KIT))
sys.path.insert(0, "/home/sandbox/s4/190t/nunif")  # pinned upstream clone

import nunif_pipeline_reference as ref

import torch
import torch.nn.functional as F
from iw3.hub_dir import HUB_MODEL_DIR
from nunif.utils.ui import TorchHubDir
from nunif.models import load_model
import iw3.models  # noqa: F401  (registers sbs.row_flow_v3 etc.)
from iw3.backward_warp import apply_divergence_nn, make_input_tensor

OUT = KIT / "nunif_consumption_fixtures.npz"
ATOL = 2e-5

fx = {}


# ---------------------------------------------------------------- A. T3 row_flow
def fixture_row_flow():
    with TorchHubDir(HUB_MODEL_DIR):
        model = load_model(
            "https://github.com/nagadomi/nunif/releases/download/0.0.0/iw3_row_flow_v3_20250627.pth",
            weights_only=True, device_ids=[-1])[0].eval()
    model.symmetric = False
    model.delta_output = True

    rng = np.random.default_rng(5)
    h, w = 48, 64
    depth = (0.15 + 0.8 * np.linspace(0, 1, w)[None, :].repeat(h, 0)
             + 0.05 * rng.random((h, w))).astype(np.float32)
    depth[12:36, 20:44] = 0.08                       # near block
    c = rng.random((3, h, w)).astype(np.float32)
    div, conv, steps = 2.5, 0.5, 1

    ct = torch.from_numpy(c)[None]
    dt = torch.from_numpy(depth)[None, None]
    eyes = {}
    for shift, name in ((1, "right"), (-1, "left")):
        with torch.inference_mode():
            z = apply_divergence_nn(model, ct, dt, div, conv, steps,
                                    shift=shift, enable_amp=False)
        eyes[name] = z[0].numpy()

    # intermediates (delta-path internals, iw3/backward_warp.py:315-366)
    inter = {}
    for shift, name in ((1, "right"), (-1, "left")):
        d = torch.flip(dt, (3,)) if shift > 0 else dt
        with torch.inference_mode():
            x = torch.stack([make_input_tensor(None, d[i], div, conv,
                                               image_width=max(h, w))
                             for i in range(d.shape[0])])
            delta = model(x)
        inter[name] = (x[0].numpy(), delta[0].numpy())

    # numpy orchestration must reproduce both eyes from the STORED deltas
    def delta_fn(name):
        return lambda x: inter[name][1][None]
    for shift, name in ((1, "right"), (-1, "left")):
        z = ref.apply_divergence_nn_delta(c[None], depth[None, None],
                                          delta_fn(name), div, conv, steps,
                                          shift)[0]
        err = np.abs(z - eyes[name]).max()
        assert err < 1e-5, (name, err)
        print(f"row_flow {name}: numpy orchestration vs torch max dev {err:.2e}")

    fx.update(rf_depth=depth, rf_c=c, rf_divergence=np.float32(div),
              rf_convergence=np.float32(conv), rf_steps=np.int64(steps),
              rf_x_right=inter["right"][0], rf_delta_right=inter["right"][1],
              rf_right_eye=eyes["right"],
              rf_x_left=inter["left"][0], rf_delta_left=inter["left"][1],
              rf_left_eye=eyes["left"])
    print(f"row_flow fixture: delta right [{inter['right'][1].min():.4f}, "
          f"{inter['right'][1].max():.4f}] half-px units")


# ---------------------------------------------------------------- B. 1080p sizing
def fixture_resize():
    frame = ref.make_frame_1080p()
    x = torch.from_numpy(frame)[None]
    with torch.inference_mode():
        rs = F.interpolate(x, size=(756, 1344), mode="bilinear",
                           antialias=True, align_corners=False)[0].numpy()
    mine = ref.resize_for_inpaint(frame[None], 1344)[0]
    err = np.abs(mine - rs).max()
    assert err < ATOL, err
    print(f"1080p resize: numpy vs torch max dev {err:.2e} (756x1344)")
    assert ref.inpaint_1080p_shape() == (768, 1408)
    fx.update(rs_rows=np.stack([rs[:, 0], rs[:, 377], rs[:, 755]], 1),   # [3,3,1344]
              rs_cols=np.stack([rs[:, :, 0], rs[:, :, 672], rs[:, :, 1343]], 2),
              rs_block=rs[:, 348:412, 640:704],
              rs_out_shape=np.array(rs.shape, np.int64),
              rs_pad=np.array([0, 768 - 756, 0, 1408 - 1344], np.int64))  # t,b,l,r


# ---------------------------------------------------------------- C. layer_weight resize
def fixture_layer_weight():
    rng = np.random.default_rng(9)
    lw = rng.random((1, 2, 27, 45)).astype(np.float32)
    cases = [("up4x", (108, 180), True, True), ("upodd", (100, 100), True, True),
             ("down", (13, 22), True, True), ("up2x_noaa", (54, 90), True, False)]
    for name, size, ac, aa in cases:
        with torch.inference_mode():
            t = F.interpolate(torch.from_numpy(lw), size=size, mode="bilinear",
                              align_corners=ac, antialias=aa)[0].numpy()
        mine = ref.resize_bilinear_torch(lw, size, align_corners=ac,
                                         antialias=aa)[0]
        err = np.abs(mine - t).max()
        assert err < ATOL, (name, err)
        print(f"layer_weight {name} {size} ac={ac} aa={aa}: max dev {err:.2e}")
        fx[f"lw_{name}"] = t
    fx["lw_input"] = lw[0]


fixture_row_flow()
fixture_resize()
fixture_layer_weight()
np.savez_compressed(OUT, **fx)
print("wrote", OUT, OUT.stat().st_size, "bytes")
