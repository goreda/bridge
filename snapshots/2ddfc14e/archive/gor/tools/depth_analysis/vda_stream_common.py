"""Shared preprocessing + sliding-window cache logic for VDA-S streaming drivers.

Mirrors video_depth_anything/video_depth_stream.py (upstream commit 4f5ae23)
exactly, but with explicit preprocessing at the export resolution so the
PyTorch reference and the ONNX export are fed identical inputs.

Model: Video-Depth-Anything-Small, checkpoint video_depth_anything_vits.pth
(Apache-2.0, depth-anything/Video-Depth-Anything-Small, repo sha 25687536).
"""
import cv2
import numpy as np

EXPORT_H, EXPORT_W = 154, 266  # vda-stream export resolution (manifest)
INFER_LEN = 32
GAP = 41

_MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
_STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)


def preprocess(frame_bgr_or_rgb, h=EXPORT_H, w=EXPORT_W, already_rgb=True):
    """frame HxWx3 uint8 -> [1,3,h,w] float32, ImageNet-normalized."""
    img = frame_bgr_or_rgb if already_rgb else frame_bgr_or_rgb[..., ::-1]
    img = cv2.resize(img, (w, h), interpolation=cv2.INTER_CUBIC).astype(np.float32) / 255.0
    img = (img - _MEAN) / _STD
    return img.transpose(2, 0, 1)[None].copy()  # [1,3,h,w]


def preprocess_aspect(frame_bgr_or_rgb, h=EXPORT_H, w=EXPORT_W,
                      already_rgb=True):
    """Aspect-correct variant (contract s22, kit manifest vda_aspect_rule).

    Letterboxes the source into the stream canvas preserving aspect
    (black bars, uniform scale) instead of stretching. The plain
    stretch biases square (1:1) sources -14% median inverse depth with
    ~10% spatial non-uniformity (center -22%, corners ~0%) - a
    depth-curvature distortion per-shot alignment cannot absorb.
    `preprocess` stays the byte-exact baseline for parity fixtures
    against the upstream export; runners feeding real sources use this.
    """
    img = frame_bgr_or_rgb if already_rgb else frame_bgr_or_rgb[..., ::-1]
    sh, sw = img.shape[:2]
    scale = min(w / sw, h / sh)
    nw, nh = max(1, int(round(sw * scale))), max(1, int(round(sh * scale)))
    r = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_CUBIC)
    canvas = np.zeros((h, w, 3), np.float32)
    y0, x0 = (h - nh) // 2, (w - nw) // 2
    canvas[y0:y0 + nh, x0:x0 + nw] = r.astype(np.float32)
    canvas = canvas / 255.0
    canvas = (canvas - _MEAN) / _STD
    return canvas.transpose(2, 0, 1)[None].copy()  # [1,3,h,w]


class WindowState:
    """Replicates frame_cache_list sliding-window logic (anchor + rolling).

    Works on generic per-frame cache bundles: a bundle is a list of arrays
    with the frame axis at dim 1 (shape [tokens, 1|31, dim]).
    """

    def __init__(self, concat_fn):
        self.id = -1
        self.frame_cache_list = []
        self._cat = concat_fn

    def is_first(self):
        return self.id < 0

    def start(self, first_bundle):
        self.id = 0
        self.frame_cache_list = [first_bundle] * INFER_LEN
        frame_id_list_len = INFER_LEN - 1
        self._fid_len = frame_id_list_len

    def build_cur_cache(self):
        cur_list = self.frame_cache_list[0:2] + self.frame_cache_list[-INFER_LEN + 3:]
        assert len(cur_list) == INFER_LEN - 1
        return [self._cat([h[i] for h in cur_list], axis=1) for i in range(len(cur_list[0]))]

    def advance(self, new_bundle):
        self.id += 1
        self.frame_cache_list.append(new_bundle)
        self._fid_len += 1
        if self.id + INFER_LEN > GAP + 1:
            self._fid_len -= 1
            del self.frame_cache_list[1]
