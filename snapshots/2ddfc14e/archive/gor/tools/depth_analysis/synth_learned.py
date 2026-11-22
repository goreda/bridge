"""Learned Tier-1 stereo synthesis wrapper (iw3 mlbw) - LOCAL-ONLY until the
architect rules on the nunif weight licence route (CONTRACT-190v section 5).

HARD GATE: importing the model requires GOR_NUNIF_LOCAL=1 in the environment
AND a local weights directory (S4_MODELS/nunif or --weights). Nothing in
prepare_film / drive / any build path imports this module; the weights are
not referenced by models.lock.tsv or any owner-facing artefact. If the
ruling accepts the MIT release-asset route, the weights enter the build via
models.lock.tsv with sha256 pins and this gate is revisited.

API:
  synth_sbs_mlbw(rgb, inv_depth, divergence=2.5, convergence=0.5)
      rgb: uint8 [H,W,3]; inv_depth: float [h,w], larger = nearer
        (v = D_SCALE / Z contract semantics); normalized internally to
        iw3's [0,1] 1=near convention.
      returns SBS uint8 [H, 2W, 3] (left | right).
"""
import os

import numpy as np

_MODEL = None


def _gate(weights_dir):
    if os.environ.get("GOR_NUNIF_LOCAL") != "1":
        raise RuntimeError(
            "learned synthesis is local-only pending the architect's nunif "
            "licence ruling (CONTRACT-190v section 5); set GOR_NUNIF_LOCAL=1 "
            "for local development runs only")
    w = weights_dir or os.path.join(
        os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models")),
        "nunif")
    for f in ("iw3_mlbw_l2_d1_20250627.pth",):
        if not os.path.exists(os.path.join(w, f)):
            raise RuntimeError("nunif weights not found at " + w)
    return w


def _load(weights_dir=None):
    global _MODEL
    if _MODEL is None:
        w = _gate(weights_dir)
        import typing
        if not hasattr(typing, "Self"):  # py3.10 shim for nunif imports
            typing.Self = typing.TypeVar("Self")
        import sys
        repo = os.environ.get("NUNIF_REPO",
                              os.path.expanduser("~/s4/190t/nunif"))
        if repo not in sys.path:
            sys.path.insert(0, repo)
        import torch  # noqa: F401
        import iw3.models  # noqa: F401  (registers sbs.mlbw et al.)
        from nunif.models import load_model
        m, _ = load_model(os.path.join(w, "iw3_mlbw_l2_d1_20250627.pth"),
                          device_ids=[-1])
        m.eval()
        m.delta_output = True
        _MODEL = m
    return _MODEL


def synth_sbs_mlbw(rgb, inv_depth, divergence=2.5, convergence=0.5,
                   weights_dir=None):
    """One frame -> learned SBS (left | right), uint8 [H, 2W, 3]."""
    import torch
    model = _load(weights_dir)  # _load puts the nunif repo on sys.path
    from iw3.mlbw_inpaint import apply_divergence_mlbw
    h, w = rgb.shape[:2]
    d = inv_depth.astype(np.float32)
    lo, hi = float(d.min()), float(d.max())
    d = (d - lo) / max(1e-6, hi - lo)  # [0,1], 1 = near (iw3 convention)
    import cv2
    d = cv2.resize(d, (w, h), interpolation=cv2.INTER_LINEAR)
    x = torch.from_numpy(rgb.astype(np.float32) / 255.0) \
        .permute(2, 0, 1).unsqueeze(0)
    dt = torch.from_numpy(d).unsqueeze(0).unsqueeze(0)
    with torch.no_grad():
        left, right = apply_divergence_mlbw(
            model, x, dt, divergence=divergence, convergence=convergence,
            synthetic_view="both", enable_amp=False, return_mask=False)[:2]
    a = torch.cat([left[0], right[0]], dim=2).permute(1, 2, 0).cpu().numpy()
    return np.clip(a * 255.0, 0, 255).astype(np.uint8)
