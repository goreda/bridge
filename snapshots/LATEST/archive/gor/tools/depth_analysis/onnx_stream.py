"""ONNX streaming driver for the vda-stream fp16 export (encoder/bootstrap/stream).

Export: huggingface.co/EmreGneri/video-depth-anything-small-stream (Apache-2.0),
exported from upstream commit 4f5ae23 of DepthAnything/Video-Depth-Anything,
checkpoint sha256 13379300...3609 (matches video_depth_anything_vits.pth).
ONNX runtime only; no PyTorch needed here.
"""
import numpy as np
import onnxruntime as ort

from vda_stream_common import WindowState, preprocess

NCACHE = 8


class OnnxVdaStream:
    def __init__(self, model_dir, providers=None):
        p = providers or ["CPUExecutionProvider"]
        self.enc = ort.InferenceSession(f"{model_dir}/vda-stream-encoder_fp16.onnx", providers=p)
        self.boot = ort.InferenceSession(f"{model_dir}/vda-stream-bootstrap_fp16.onnx", providers=p)
        self.stream = ort.InferenceSession(f"{model_dir}/vda-stream-stream_fp16.onnx", providers=p)
        self.state = WindowState(lambda xs, axis: np.concatenate(xs, axis=axis))

    def _feats(self, pixels):
        names = [i.name for i in self.enc.get_inputs()]
        out = self.enc.run(None, {names[0]: pixels})
        return {f"feat{i+1}": out[i] for i in range(4)}

    def process_frame(self, frame_rgb, aspect=False):
        """Returns depth [H,W] float32 at the export resolution.

        aspect=True uses the s22 aspect-correct letterbox (runners feeding
        real sources) instead of the byte-exact stretch baseline; the
        caller crops the canvas to the letterbox picture (letterbox_box).
        """
        if aspect:
            from vda_stream_common import preprocess_aspect
            pixels = preprocess_aspect(frame_rgb)
        else:
            pixels = preprocess(frame_rgb)
        feats = self._feats(pixels)
        if self.state.is_first():
            names = [o.name for o in self.boot.get_outputs()]
            out = self.boot.run(None, feats)
            depth = out[0][0, 0]  # [h,w]
            bundle = [out[i] for i in range(1, 1 + NCACHE)]
            self.state.start(bundle)
            return depth
        cur_cache = self.state.build_cur_cache()
        feed = dict(feats)
        for i in range(NCACHE):
            feed[f"cache{i}"] = cur_cache[i]
        out = self.stream.run(None, feed)
        depth = out[0][0, 0]
        bundle = [out[i] for i in range(1, 1 + NCACHE)]
        self.state.advance(bundle)
        return depth
