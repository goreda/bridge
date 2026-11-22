"""PyTorch streaming reference driver (same checkpoint as the ONNX export).

Loads Video-Depth-Anything-Small (video_depth_stream.VideoDepthAnything, vits)
from the upstream repo at commit 4f5ae23 and drives it frame-by-frame with the
same sliding-window logic as video_depth_stream.infer_video_depth_one, but at
the ONNX export resolution and always fp32 on CPU. This is the parity reference
for onnx_stream.OnnxVdaStream.

Requires the upstream repo cloned at VDA_REPO (default ~/s4/190t/vda).
"""
import os
import sys
import types

import numpy as np
import torch

# The upstream module imports torchvision.transforms.Compose for its built-in
# transform, which these drivers never use; stub it to avoid a hard torchvision
# dependency (system torchvision here is binary-incompatible with this torch).
if "torchvision" not in sys.modules:
    _tv = types.ModuleType("torchvision")
    _tvt = types.ModuleType("torchvision.transforms")

    class _Compose:
        def __init__(self, transforms):
            self.transforms = transforms

        def __call__(self, x):
            for t in self.transforms:
                x = t(x)
            return x

    _tvt.Compose = _Compose
    _tv.transforms = _tvt
    sys.modules["torchvision"] = _tv
    sys.modules["torchvision.transforms"] = _tvt

from vda_stream_common import EXPORT_H, EXPORT_W, WindowState, preprocess

VDA_REPO = os.environ.get("VDA_REPO", os.path.expanduser("~/s4/190t/vda"))


class TorchVdaStream:
    def __init__(self, checkpoint, repo=VDA_REPO):
        sys.path.insert(0, repo)
        from video_depth_anything.video_depth_stream import VideoDepthAnything

        self.model = VideoDepthAnything(encoder="vits", features=64,
                                        out_channels=[48, 96, 192, 384])
        self.model.load_state_dict(torch.load(checkpoint, map_location="cpu"), strict=True)
        self.model.eval()
        self.state = WindowState(lambda xs, axis: torch.cat(xs, dim=axis))

    @torch.no_grad()
    def process_frame(self, frame_rgb):
        pixels = preprocess(frame_rgb)  # [1,3,h,w]
        x = torch.from_numpy(pixels).unsqueeze(0)  # [1,1,3,h,w]
        feats = self.model.forward_features(x)
        if self.state.is_first():
            depth, caches = self.model.forward_depth(feats, x.shape)
            self.state.start(caches)
        else:
            cur_cache = self.state.build_cur_cache()
            depth, caches = self.model.forward_depth(feats, x.shape,
                                                     cached_hidden_state_list=cur_cache)
            self.state.advance(caches)
        d = torch.relu(depth)[0, 0].float().cpu().numpy()
        assert d.shape == (EXPORT_H, EXPORT_W)
        return d
