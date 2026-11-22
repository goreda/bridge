"""Scale-alignment tests: LSQ recovery under noise, EMA smoothing, cut reset."""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))

from align import ShotAligner, align_shot, fit_scale_shift

rng = np.random.default_rng(7)


def main():
    # exact recovery without noise
    ref = rng.uniform(1, 10, (40, 60))
    scale, shift = fit_scale_shift(ref * 0.5 + 3.0, ref)
    assert abs(scale - 2.0) < 1e-8 and abs(shift + 6.0) < 1e-8, (scale, shift)

    # noisy recovery
    tgt = ref * 0.25 + 1.0 + rng.normal(0, 0.01, ref.shape)
    scale, shift = fit_scale_shift(tgt, ref)
    assert abs(scale - 4.0) < 0.05 and abs(shift + 4.0) < 0.2, (scale, shift)
    print("PASS lsq exact + noisy recovery")

    # mask restricts the fit
    mask = np.zeros_like(ref, bool); mask[:20] = True
    s2, _ = fit_scale_shift(ref[:20] * 0.5 + 3.0, ref[:20])
    sm, _ = fit_scale_shift(np.pad(ref * 0.5 + 3.0, ((0, 0), (0, 0))) * 0 +  # garbage outside mask
                            np.where(mask, ref * 0.5 + 3.0, 1e6), ref, mask)
    assert abs(sm - s2) < 1e-8
    print("PASS mask")

    # EMA smoothing within a shot: jittery per-frame fits converge near truth
    vda = rng.uniform(0, 1, (12, 20, 30))
    moge = vda * 5.0 + 2.0 + rng.normal(0, 0.05, vda.shape)
    al = ShotAligner(ema=0.7)
    for v, m in zip(vda, moge):
        al.update(v, m)
    assert abs(al.scale - 5.0) < 0.1, al.scale  # vda->moge scale is 5
    print("PASS ema smoothing")

    # reset at cut: new shot with different affine must not inherit old state
    al.reset()
    assert al.scale is None and al.shift is None
    vda2 = rng.uniform(0, 1, (20, 30))
    moge2 = vda2 * 9.0 - 1.0
    out = al.update(vda2, moge2)
    np.testing.assert_allclose(out, moge2, atol=1e-6)
    print("PASS reset at cut")

    # regression (190v anim): MoGe-2 emits +inf at sky; unmasked it poisoned
    # the EMA and blacked out whole shots. Inf must be excluded from the fit.
    al = ShotAligner(ema=0.9)
    vda3 = rng.uniform(0.2, 1.0, (40, 50))
    moge3 = vda3 * -3.0 + 12.0
    moge3[:5, :] = np.inf          # sky row
    vda3[:5, :] = rng.uniform(0.2, 1.0, (5, 50))  # vda says something finite there
    out = al.update(vda3, moge3)
    assert np.isfinite(al.scale) and np.isfinite(al.shift)
    np.testing.assert_allclose(out[10:], moge3[10:], atol=1e-4)
    # all-inf metric frame: skipped, prior estimate kept, never NaN
    out2 = al.update(vda3, np.full_like(vda3, np.inf))
    assert np.isfinite(out2).all() and al.skipped >= 1
    print("PASS inf-sky regression: fit finite, estimate kept, skip counted")

    # align_shot end-to-end
    aligned = align_shot(vda, vda * 5.0 + 2.0)
    np.testing.assert_allclose(aligned, vda * 5.0 + 2.0, atol=1e-4)
    print("PASS align_shot end-to-end")
    print("ALL ALIGN TESTS PASS")


if __name__ == "__main__":
    main()
