#!/usr/bin/env python3
"""190v (E-G 15:02): nunif consumption fixtures vs the numpy reference
(tools/depth_analysis/kit/nunif_pipeline_reference.py). Torch-free gate:
the npz was generated AND cross-checked against torch + the real
RowFlowV3 weights by gen_consumption_fixtures.py (iw3 @ b1548e8)."""
import pathlib
import sys

import numpy as np

root = pathlib.Path(__file__).resolve().parents[2]
kit = root / 'tools/depth_analysis/kit'
sys.path.insert(0, str(kit))
import nunif_pipeline_reference as ref

fx = np.load(kit / 'nunif_consumption_fixtures.npz')
fails = []


def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok:
        fails.append(n)


ATOL = 2e-5

# --- A. T3 row_flow_v3 consumption (apply_divergence_nn_LR / _nn_delta)
depth, c = fx['rf_depth'], fx['rf_c']
div, conv, steps = float(fx['rf_divergence']), float(fx['rf_convergence']), int(fx['rf_steps'])
for shift, name in ((1, 'right'), (-1, 'left')):
    x_stored = fx[f'rf_x_{name}']
    delta = fx[f'rf_delta_{name}']
    d = depth[..., ::-1] if shift > 0 else depth
    x_ref = ref.make_input_tensor(d, div, conv)
    check(f'row_flow {name}: make_input_tensor matches the torch input',
          np.abs(x_ref - x_stored).max() < 1e-6)
    z = ref.apply_divergence_nn_delta(c[None], depth[None, None],
                                      lambda x: delta[None], div, conv,
                                      steps, shift)[0]
    check(f'row_flow {name}: numpy orchestration reproduces the torch eye',
          np.abs(z - fx[f'rf_{name}_eye']).max() < 1e-5)
check('row_flow: delta is a horizontal shift field (y channel zero)',
      (fx['rf_delta_right'][1] == 0).all() and (fx['rf_delta_left'][1] == 0).all())
check('row_flow: auto warp steps (v3: >5 -> ceil(div/4); v2: >2.5 -> ceil(div/2))',
      ref.auto_warp_steps('row_flow_v3', 2.5, 'both') == 1
      and ref.auto_warp_steps('row_flow', 6.0, 'both') == 2
      and ref.auto_warp_steps('row_flow', 2.5, 'right') == 1   # 2*2.5 = 5.0, not > 5
      and ref.auto_warp_steps('row_flow', 3.0, 'right') == 2   # single eye doubles
      and ref.auto_warp_steps('row_flow_v2', 3.0, 'both') == 2
      and ref.auto_warp_steps('row_flow_v2', 2.5, 'both') == 1)

# --- B. 1080p sizing: SCALE to 756x1344 (never pad/crop), then pad to 768x1408
frame = ref.make_frame_1080p()
rs = ref.resize_for_inpaint(frame[None], 1344)[0]
check('1080p: resized shape is 756x1344 (scale, aspect-kept, even)',
      tuple(rs.shape) == tuple(fx['rs_out_shape']))
check('1080p: resized rows match torch slices',
      np.abs(np.stack([rs[:, 0], rs[:, 377], rs[:, 755]], 1) - fx['rs_rows']).max() < ATOL)
check('1080p: resized cols match torch slices',
      np.abs(np.stack([rs[:, :, 0], rs[:, :, 672], rs[:, :, 1343]], 2) - fx['rs_cols']).max() < ATOL)
check('1080p: center block matches torch',
      np.abs(rs[:, 348:412, 640:704] - fx['rs_block']).max() < ATOL)
padded, (ph, pw) = ref.inpaint_model_pad(rs[None], 64)
t, b, l, r = (int(v) for v in fx['rs_pad'])
want = np.pad(rs, [(0, 0), (0, 12), (0, 64)], mode="edge")
check('1080p: model pad is replication, bottom 12 + right 64 -> 768x1408',
      (ph, pw) == (b, r) and (t, l) == (0, 0) and padded.shape == (1, 3, 768, 1408)
      and (padded[0] == want).all())
check('1080p: documented shape fact 768x1408 (1344-wide feed pads the width too)',
      ref.inpaint_1080p_shape() == (768, 1408))

# --- C. layer_weight resize (align_corners=True, antialias=True)
lw = fx['lw_input'][None]
for name, size in (('up4x', (108, 180)), ('upodd', (100, 100)), ('down', (13, 22))):
    mine = ref.resize_bilinear_torch(lw, size, align_corners=True, antialias=True)[0]
    check(f'layer_weight {name}: numpy ac=T aa=T matches torch',
          np.abs(mine - fx[f'lw_{name}']).max() < ATOL)
mine = ref.resize_bilinear_torch(lw, (54, 90), align_corners=True, antialias=False)[0]
check('layer_weight up2x_noaa: numpy ac=T aa=F matches torch',
      np.abs(mine - fx['lw_up2x_noaa']).max() < ATOL)
check('layer_weight: antialias is not a no-op under align_corners (torch quirk pinned)',
      np.abs(mine - fx['lw_up4x'][:, ::2, ::2]).max() > 1e-3)

print('nunif consumption: %d failure(s)' % len(fails))
sys.exit(1 if fails else 0)
