"""nunif pre/post-model pipeline - numpy reference (190w W3, for E-G's Swift runner).

Numbers/code, not prose. Every function mirrors upstream nunif release 0.0.0
(iw3 @ 190t clone) and the fixture nunif_pipeline_fixture.npz was generated
by THIS file and checked against the upstream torch ops on Linux.

Run:  python3 nunif_pipeline_reference.py   # writes nunif_pipeline_fixture.npz
Check on Mac: recompute each section and compare to the npz (all float32,
max abs diff should be < 1e-6 for pure-numpy reimplementation).

Upstream sources (file:lines in the 190t clone):
  1. make_divergence_feature_value   iw3/backward_warp.py:10-16
  2. make_input_tensor (c=None)      iw3/backward_warp.py:19-73
  3. apply_divergence_nn_delta_weight delta convention
                                     iw3/backward_warp.py:394-489
  4. backward_warp / make_grid       iw3/backward_warp.py:95-131
  5. pad_delta_y                     iw3/backward_warp.py:369-373
  6. postprocess_hole_mask           iw3/backward_warp.py:529-539
     closing/dilate_inner/dilate_outer  iw3/dilation.py:63-102
  7. inpaint preprocess (mask blur)  iw3/models/light_inpaint_v1.py:91-105
     SeparableGaussianFilter2d       nunif/modules/gaussian_filter.py:9-97
  8. video windowing                 iw3/base_inpaint.py:407-743

DEPTH INPUT RANGE: the depth channel is fed AS-IS (iw3 default --mapper is
"none" for the DepthAnything/VDA family, iw3/mapper.py:69). gor feeds the
VDA inverse-depth output, normalised 0..1 (per-stream min-max, higher =
closer). No rescale, no offset before make_input_tensor.
"""
import numpy as np

# ---------------------------------------------------------------- 1. feature values
def make_divergence_feature_value(divergence, convergence, image_width):
    # iw3/backward_warp.py:10-16 (image_width = max(H, W))
    divergence_pix = divergence * 0.5 * 0.01 * image_width
    return divergence_pix / 32.0, (-divergence_pix * convergence) / 32.0


def make_input_tensor(depth_hw, divergence, convergence):
    # iw3/backward_warp.py:19-73 with c=None, mapper=None, preserve_screen_border=False
    # -> [3,H,W] = (depth, divergence_feature, convergence_feature)
    image_width = max(depth_hw.shape)
    dv, cv = make_divergence_feature_value(divergence, convergence, image_width)
    return np.stack([
        depth_hw,
        np.full_like(depth_hw, dv),
        np.full_like(depth_hw, cv),
    ]).astype(np.float32)


# ---------------------------------------------------------------- 2/3/4. warp convention
def make_grid(b, h, w):
    # iw3/backward_warp.py:95-103: base grid, normalized coords, x then y
    my, mx = np.meshgrid(np.linspace(-1, 1, h), np.linspace(-1, 1, w), indexing="ij")
    grid = np.stack([mx, my])[None]  # [1,2,H,W]
    return np.repeat(grid, b, axis=0).astype(np.float32)


def pad_delta_y(delta_x):
    # iw3/backward_warp.py:369-373: interleave delta_x with 0 as the y component
    b, c, h, w = delta_x.shape
    out = np.stack([delta_x, np.zeros_like(delta_x)], axis=2)  # [B,C,2,H,W]
    return out.reshape(b, c * 2, h, w)


def backward_warp(c, grid, delta, delta_scale):
    # iw3/backward_warp.py:75-92: grid += delta*delta_scale, then grid_sample
    # (bilinear, padding border, align_corners=True). delta units: half-width
    # pixels (delta_scale = 1/(W//2 - 1)); positive delta_x warps right.
    return grid_sample_bilinear(c, grid + delta * delta_scale, padding="border")


def delta_scale_for(width):
    # iw3/backward_warp.py:446 (apply_divergence_nn_delta_weight) and
    # iw3/models/mlbw.py:135: 1/(W//2 - 1) with W = frame width
    return 1.0 / (width // 2 - 1)


def apply_mlbw_delta_weight(c, delta_x, layer_weight, num_layers):
    # iw3/backward_warp.py:447-460: per-layer backward warp, weighted sum, clamp
    b, _, h, w = c.shape
    delta = pad_delta_y(delta_x)
    grid = make_grid(b, h, w)
    ds = np.float32(delta_scale_for(w))
    z = np.zeros_like(c)
    for i in range(num_layers):
        d = delta[:, i * 2 : i * 2 + 2]
        wgt = layer_weight[:, i : i + 1]
        z = z + backward_warp(c, grid, d, ds) * wgt
    return np.clip(z, 0.0, 1.0)


def grid_sample_bilinear(c, grid, padding="border"):
    # torch F.grid_sample(mode=bilinear, padding_mode=border, align_corners=True)
    b, ch, h, w = c.shape
    gx = (grid[:, 0] + 1.0) * (w - 1) / 2.0
    gy = (grid[:, 1] + 1.0) * (h - 1) / 2.0
    if padding == "border":
        gx = np.clip(gx, 0, w - 1)
        gy = np.clip(gy, 0, h - 1)
    x0 = np.floor(gx).astype(np.int64); y0 = np.floor(gy).astype(np.int64)
    x1 = np.clip(x0 + 1, 0, w - 1); y1 = np.clip(y0 + 1, 0, h - 1)
    x0 = np.clip(x0, 0, w - 1); y0 = np.clip(y0, 0, h - 1)
    wx = (gx - np.floor(gx))[:, None]; wy = (gy - np.floor(gy))[:, None]
    out = np.zeros((b, ch, h, w), dtype=np.float32)
    for bi in range(b):
        cb = c[bi].transpose(1, 2, 0)  # HWC so advanced indexing keeps order
        Ia = cb[y0[bi], x0[bi]].transpose(2, 0, 1); Ib = cb[y1[bi], x0[bi]].transpose(2, 0, 1)
        Ic = cb[y0[bi], x1[bi]].transpose(2, 0, 1); Id = cb[y1[bi], x1[bi]].transpose(2, 0, 1)
        out[bi] = (Ia * (1 - wx[bi]) * (1 - wy[bi]) + Ic * wx[bi] * (1 - wy[bi])
                   + Ib * (1 - wx[bi]) * wy[bi] + Id * wx[bi] * wy[bi])
    return out


# ---------------------------------------------------------------- 5. hole mask
def mask_closing(mask, kernel_size=3, n_iter=1):
    # iw3/dilation.py:63-70 (postprocess_hole_mask uses n_iter=1, kernel 3,
    # grayscale max/min filter over the kernel window)
    m = mask.astype(np.float32)
    for _ in range(n_iter):
        m = _gray_dilate(m, kernel_size)
    for _ in range(n_iter):
        m = _gray_erode(m, kernel_size)
    return m


def _gray_dilate(m, k):
    r = k // 2
    p = np.pad(m, ((0, 0), (0, 0), (r, r), (r, r)), mode="edge")
    out = np.zeros_like(m)
    for dy in range(k):
        for dx in range(k):
            out = np.maximum(out, p[:, :, dy:dy + m.shape[2], dx:dx + m.shape[3]])
    return out


def _gray_erode(m, k):
    return -_gray_dilate(-m, k)


def postprocess_hole_mask(mask_logits, target_size, threshold=0.15,
                          inner_dilation=0, outer_dilation=0):
    # iw3/backward_warp.py:529-539: closing(1) -> bilinear resize (align_corners
    # True, antialias False) -> sigmoid -> > threshold -> inner/outer dilation.
    base_width = mask_logits.shape[-1]
    m = mask_closing(mask_logits, n_iter=1)
    if tuple(target_size) != m.shape[-2:]:
        m = bilinear_resize_align_corners(m, target_size)
    m = 1.0 / (1.0 + np.exp(-m))
    m = m > threshold
    m = dilate_inner(m, inner_dilation, base_width)
    m = dilate_outer(m, outer_dilation, base_width)
    return m


def dilate_outer(mask, n_iter, base_width=None):
    # iw3/dilation.py:73-87: OR with left-shifted copy, n_iter scaled by width ratio
    if n_iter <= 0:
        return mask
    if base_width is not None:
        n_iter = max(round(mask.shape[-1] / base_width * n_iter), 1)
    m = mask.astype(bool)
    for _ in range(n_iter):
        m = m | np.pad(m, ((0, 0), (0, 0), (0, 0), (1, 0)))[:, :, :, :-1]
    return m


def dilate_inner(mask, n_iter, base_width=None):
    # iw3/dilation.py:90-102: OR with right-shifted copy
    if n_iter <= 0:
        return mask
    if base_width is not None:
        n_iter = max(round(mask.shape[-1] / base_width * n_iter), 1)
    m = mask.astype(bool)
    for _ in range(n_iter):
        m = m | np.pad(m, ((0, 0), (0, 0), (0, 0), (0, 1)))[:, :, :, 1:]
    return m


def bilinear_resize_align_corners(x, size):
    # torch F.interpolate(mode=bilinear, align_corners=True, antialias=False)
    th, tw = size
    b, c, h, w = x.shape
    if h == th and w == tw:
        return x.astype(np.float32)
    ys = np.linspace(0, h - 1, th); xs = np.linspace(0, w - 1, tw)
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    y1 = np.minimum(y0 + 1, h - 1); x1 = np.minimum(x0 + 1, w - 1)
    wy = (ys - y0)[None, :, None]; wx = (xs - x0)[None, None, :]
    out = np.zeros((b, c, th, tw), dtype=np.float32)
    for bi in range(b):
        for ci in range(c):
            f = x[bi, ci]
            Ia = f[np.ix_(y0, x0)]; Ib = f[np.ix_(y1, x0)]
            Ic = f[np.ix_(y0, x1)]; Id = f[np.ix_(y1, x1)]
            out[bi, ci] = (Ia * (1 - wy) * (1 - wx) + Ic * (1 - wy) * wx
                           + Ib * wy * (1 - wx) + Id * wy * wx)
    return out


# ---------------------------------------------------------------- 6. inpaint preprocess
def gaussian_kernel1d(kernel_size, sigma=None):
    # nunif/modules/gaussian_filter.py:9-20 (torchvision formula)
    if sigma is None:
        sigma = kernel_size * 0.15 + 0.35  # k=15 -> sigma = 2.6
    half = (kernel_size - 1) * 0.5
    x = np.linspace(-half, half, kernel_size)
    k = np.exp(-0.5 * (x / sigma) ** 2)
    return (k / k.sum()).astype(np.float32)


def gaussian_blur_k15(mask, kernel_size=15):
    # SeparableGaussianFilter2d(1, kernel_size=15, padding=7): replication pad,
    # separable conv, sigma = 15*0.15+0.35 = 2.6 (default)
    k = gaussian_kernel1d(kernel_size)
    r = kernel_size // 2
    m = np.pad(mask, ((0, 0), (0, 0), (r, r), (r, r)), mode="edge")
    for axis, k2 in ((3, k), (2, k)):
        m = np.apply_along_axis(lambda v: np.convolve(v, k2, mode="same"), axis, m)
    return m[:, :, r:-r, r:-r].astype(np.float32)


def inpaint_preprocess(x, mask, inner_dilation=0, outer_dilation=0, base_width=None):
    # iw3/models/light_inpaint_v1.py:91-105 (closing=False path used at runtime
    # when inner/outer dilation are 0 the mask still gets the blur):
    #   x = x * (1 - mask);  mask = clamp(blur_k15(mask) + mask, 0, 1)
    m = mask.astype(np.float32)
    m = dilate_inner(m > 0, inner_dilation, base_width).astype(np.float32) \
        if inner_dilation > 0 else m
    m = dilate_outer(m > 0, outer_dilation, base_width).astype(np.float32) \
        if outer_dilation > 0 else m
    x_masked = x * (1.0 - m)
    m = np.clip(gaussian_blur_k15(m) + m, 0.0, 1.0)
    return x_masked.astype(np.float32), m


# ---------------------------------------------------------------- 7. video windowing
# Upstream BaseVideoInpaint (iw3/base_inpaint.py:407-743), defaults:
SEQ_LEN = 12
PRE_PAD = 3
POST_PAD = 3
STEP = SEQ_LEN - (PRE_PAD + POST_PAD)  # = 6
# - queue capacity 12; when the queue is EMPTY the first frame is enqueued
#   PRE_PAD+1 = 4 times (head edge-clamp: first window = f0 x4 + f1..f8)
# - each full window emits frames [PRE_PAD : SEQ_LEN - POST_PAD] (6 frames)
#   then drops STEP = 6 from the queue
# - flush(): tail is filled by REPLICATING THE LAST WARPED FRAME
#   (FrameQueue.fill) and emits the rest ([PRE_PAD:] of the filled window)
# E-G's stated semantics (12, 3+3 pad, step 6, edge-clamped tail) CONFIRMED
# against upstream on 2026-11-09; note the head is edge-clamped too (f0 x3 extra).


def video_windows(n_frames):
    """Reference window plan: list of (window_frame_indices, emit_slice)."""
    plan = []
    q = []
    i = 0
    # head clamp
    q = [0] * (PRE_PAD + 1)
    i = 1
    while i < n_frames:
        q.append(i)
        i += 1
        if len(q) == SEQ_LEN:
            plan.append((list(q), (PRE_PAD, SEQ_LEN - POST_PAD)))
            q = q[STEP:]
    if q:
        pad = SEQ_LEN - len(q)
        while len(q) < SEQ_LEN:
            q.append(q[-1])  # tail edge-clamp
        # upstream flush emits [PRE_PAD:] then drops the `pad` replicated
        # tail frames (iw3/base_inpaint.py:711-743)
        plan.append((list(q), (PRE_PAD, SEQ_LEN - pad)))
    return plan


# ---------------------------------------------------------------- fixture

# ---------------------------------------------------------------- 7. T3 row_flow consumption (E-G 15:02)
def auto_warp_steps(method, divergence, synthetic_view):
    # iw3/utils.py:2837-2845 + 61-64: extra warp steps above the model's max
    # divergence (row_flow_v2: >2.5 -> ceil(div/2); row_flow/v3: >5.0 -> ceil(div/4));
    # single-eye view doubles the divergence first. None -> steps=1 upstream.
    import math
    div = divergence if synthetic_view == "both" else divergence * 2
    if method == "row_flow_v2" and div > 2.5:
        return math.ceil(div / 2.0)
    if method in {"row_flow", "row_flow_v3"} and div > 5.0:
        return math.ceil(div / 4.0)
    return 1


def apply_divergence_nn_delta(c, depth, delta_fn, divergence, convergence,
                              steps, shift, preserve_screen_border=False):
    # iw3/backward_warp.py:315-366 (non-symmetric delta models: row_flow_v2/v3
    # with model.delta_output=True). shift=+1 is the right eye: c and depth
    # are H-flipped first, the result flipped back. divergence_step =
    # divergence/steps; each step re-runs the model on the warped depth; the
    # image is warped ONCE PER STEP at the end, in order. convergence arrives
    # per-batch (scalar broadcast upstream, iw3/utils.py:416/523).
    assert shift in (-1, 1)
    if shift > 0:
        c = c[..., ::-1].copy(); depth = depth[..., ::-1].copy()
    b, _, h, w = depth.shape
    base_size = max(h, w)
    grid = make_grid(b, h, w)
    ds = np.float32(delta_scale_for(w))
    depth_warp = depth
    deltas = []
    for _ in range(steps):
        x = np.stack([make_input_tensor(depth_warp[i], divergence / steps,
                                        convergence)
                      for i in range(b)])                      # [B,3,H,W]
        deltas.append(delta_fn(x).astype(np.float32))          # [B,2,H,W]
        if len(deltas) < steps:
            depth_warp = backward_warp(depth_warp, grid, deltas[-1], ds)
    z = c
    for d in deltas:
        z = backward_warp(z, grid, d, ds)
    z = np.clip(z, 0.0, 1.0)
    if shift > 0:
        z = z[..., ::-1].copy()
    return z


# ---------------------------------------------------- 8. torch-exact resize (E-G 15:02)
def _linear_weights(in_size, out_size, align_corners, antialias, dtype=np.float64):
    # torch aten UpSample.h, HelperInterpLinear (separable aa path):
    # scale = align_corners ? (in-1)/(out-1) : in/out;  center =
    # align_corners ? scale*i : scale*(i+0.5)-0.5;  filter_scale =
    # max(1, scale) when antialias else 1;  support = filter_scale;
    # w_j = max(1 - |center-j|/filter_scale, 0) over j in [center-support,
    # center+support] clipped to [0, in-1], renormalised to sum 1.
    if align_corners:
        scale = (in_size - 1) / (out_size - 1) if out_size > 1 else 0.0
    else:
        scale = in_size / out_size
    filter_scale = max(1.0, scale) if antialias else 1.0
    support = filter_scale
    idxs = np.zeros((out_size, int(np.ceil(2 * support)) + 2), np.int64)
    wgts = np.zeros_like(idxs, dtype)
    for i in range(out_size):
        # torch quirk (generic_aa path): with antialias=True the CENTER is
        # always half-pixel; align_corners then bends only the scale.
        center = (scale * (i + 0.5) - 0.5) if (antialias or not align_corners) \
                 else scale * i
        lo = int(np.ceil(center - support)); hi = int(np.floor(center + support))
        js = np.arange(max(lo, 0), min(hi, in_size - 1) + 1)
        w = np.maximum(1.0 - np.abs(center - js) / filter_scale, 0.0)
        w = w / w.sum()
        idxs[i, :len(js)] = js; wgts[i, :len(js)] = w
    return idxs, wgts


def resize_bilinear_torch(x, size, align_corners, antialias):
    # torch F.interpolate(mode="bilinear", align_corners=..., antialias=...),
    # float64 accumulate -> float32 out. x: [B,C,H,W].
    th, tw = size
    b, c, h, w = x.shape
    if (h, w) == (th, tw):
        return x.astype(np.float32)
    y_idx, y_w = _linear_weights(h, th, align_corners, antialias)
    x_idx, x_w = _linear_weights(w, tw, align_corners, antialias)
    xf = x.astype(np.float64)
    # horizontal pass
    tmp = np.zeros((b, c, h, tw), np.float64)
    for j in range(x_idx.shape[1]):
        wj = x_w[:, j]
        valid = wj > 0
        if not valid.any():
            continue
        tmp[:, :, :, valid] += xf[:, :, :, x_idx[valid, j]] * wj[valid]
    out = np.zeros((b, c, th, tw), np.float64)
    for j in range(y_idx.shape[1]):
        wj = y_w[:, j]
        valid = wj > 0
        if not valid.any():
            continue
        out[:, :, valid, :] += tmp[:, :, y_idx[valid, j], :] * wj[valid][None, :, None]
    return out.astype(np.float32)


def make_frame_1080p(seed=7):
    """Deterministic synthetic 1080p frame (gradient + noise), [3,1080,1920]
    fp32 in [0,1]; shared by the fixture generator and the gate test."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:1080, 0:1920].astype(np.float32)
    frame = np.stack([xx / 1919.0, yy / 1079.0,
                      (xx + yy) / 2998.0]) + 0.25 * rng.random((3, 1080, 1920),
                                                                dtype=np.float32)
    return np.clip(frame, 0, 1).astype(np.float32)


def resize_for_inpaint(x, max_width):
    # iw3/base_inpaint.py:200-209 BaseInpaint._resize: SCALE ONLY, never
    # pad/crop: width -> max_width (bumped to even), height follows the
    # source aspect ratio (int(), bumped to even); bilinear, antialias=True,
    # align_corners=False. A no-op when the frame already fits.
    if max_width is None or x.shape[-1] <= max_width:
        return x
    if max_width % 2 != 0:
        max_width += 1
    new_w = max_width
    new_h = int((max_width / x.shape[-1]) * x.shape[-2])
    if new_h % 2 != 0:
        new_h += 1
    return resize_bilinear_torch(x, (new_h, new_w), align_corners=False,
                                 antialias=True)


def inpaint_model_pad(x, mod_by):
    # iw3/models/light_video_inpaint_v1.py:200-207: replication pad of the
    # RIGHT and BOTTOM edges by mod*downscaling_factor - dim % (mod*factor)
    # (note: a full mod block is appended when already divisible; for the
    # video inpaint mod*factor = 16*4 = 64), cropped back after the network.
    b, c, h, w = x.shape
    pad_w = mod_by - w % mod_by
    pad_h = mod_by - h % mod_by
    return np.pad(x, [(0, 0), (0, 0), (0, pad_h), (0, pad_w)], mode="edge"), (pad_h, pad_w)


def inpaint_1080p_shape(src_w=1920, src_h=1080, max_width=1344, mod_by=64):
    # The 768x1344 question (E-G 15:02): iw3 SCALES 1920x1080 to 756x1344
    # (resize_for_inpaint), the model then REPLICATION-PADS to 768x1408
    # (inpaint_model_pad: 756 -> +12 rows, 1344 -> +64 cols) and crops back.
    # 768x1344 is the padded HEIGHT x the SCALED width - a fixed-shape
    # runner at 768x1344 must either pad the width itself (iw3 semantics,
    # 64 extra replicated columns) or accept a border difference in the
    # rightmost 64 source columns.
    new_w = max_width + (max_width % 2)
    new_h = int((new_w / src_w) * src_h)
    new_h += new_h % 2
    return (new_h + (mod_by - new_h % mod_by),
            new_w + (mod_by - new_w % mod_by))

def main():
    rng = np.random.default_rng(190)
    h, w = 24, 48  # tiny, multiples of nothing that matters here
    depth = rng.random((h, w), dtype=np.float32)
    frame = rng.random((1, 3, h, w), dtype=np.float32)
    logits = rng.standard_normal((1, 1, h, w)).astype(np.float32) * 2.0
    mask = (rng.random((1, 1, h, w), dtype=np.float32) > 0.7).astype(np.float32)

    out = {}
    # 1. feature values + input tensor
    x3 = make_input_tensor(depth, divergence=2.0, convergence=1.0)
    out["feature_x3"] = x3
    dv, cv = make_divergence_feature_value(2.0, 1.0, 48)
    out["feature_values"] = np.array([dv, cv], dtype=np.float32)
    # 2. delta convention + warp
    delta_x = rng.standard_normal((1, 2, h, w)).astype(np.float32) * 0.5
    lw = rng.random((1, 2, h, w), dtype=np.float32)
    out["warp_delta_padded"] = pad_delta_y(delta_x)
    out["warp_delta_scale"] = np.array([delta_scale_for(w)], dtype=np.float32)
    out["warp_grid"] = make_grid(1, h, w)
    out["warp_out"] = apply_mlbw_delta_weight(frame, delta_x, lw, num_layers=2)
    # 3. hole mask
    out["mask_post"] = postprocess_hole_mask(logits, (h, w), 0.15, 1, 1).astype(np.uint8)
    # 4. gaussian k15
    out["gauss_k15"] = gaussian_kernel1d(15)
    out["mask_blur"] = gaussian_blur_k15(mask)
    xm, mb = inpaint_preprocess(frame, mask)
    out["inpaint_x_masked"] = xm
    out["inpaint_mask_blurred"] = mb
    # 5. window plan for 26 frames
    plan = video_windows(26)
    out["windows_26f"] = np.array([p[0] for p in plan], dtype=np.int64)
    out["windows_26f_emit"] = np.array([p[1] for p in plan], dtype=np.int64)

    np.savez_compressed("nunif_pipeline_fixture.npz", **out)
    print("wrote nunif_pipeline_fixture.npz:", sorted(out))
    print("feature_values (div=2, conv=1, width 48):", out["feature_values"])
    print("delta_scale(48):", out["warp_delta_scale"])
    print("windows for 26f:", plan)


if __name__ == "__main__":
    main()
