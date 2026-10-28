"""Shared per-crop scoring: frozen epoch-3 recognizer + 426 reject head.

Single implementation of the 426 pinned 133-feature path (128 backbone
+ conf62 top softmax + 4 geometry stats) so api.py, the input identity
flow and the output readback all score crops identically. Asset pins are
verified on load; a mismatch refuses, never scores.
"""
import hashlib
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np
import torch

from .api import (EXPECTED_EPOCH3_SHA256, EXPECTED_REJECT_HEAD_SHA256,
                  _load_reject_head)


@dataclass
class CropScore:
    char: str                  # advisory top-1 class label; "" when pack_refused
    confidence: float          # top softmax prob; ADVISORY only, not calibrated
    reject_score: Optional[float]  # 426 head output; None when pack_refused
    rejected: bool             # fragment / not-a-character signal (NOT identity doubt)
    pack_refused: bool         # tile outside pack contract (e.g. no ink)


class Scorer:
    """Pinned recognizer + reject head, loaded once, read-only."""

    def __init__(self, seg402_root, assets_root):
        assets_root = Path(assets_root)
        for name, want in (("epoch-3.pt", EXPECTED_EPOCH3_SHA256),
                           ("reject_head.pt", EXPECTED_REJECT_HEAD_SHA256)):
            got = hashlib.sha256((assets_root / name).read_bytes()).hexdigest()
            if got != want:
                raise RuntimeError(f"asset pin mismatch {name}: {got} != {want}")
        sys.path.insert(0, str(Path(seg402_root).resolve()))
        from seg402.recognizer import Recognizer
        self.rec = Recognizer(assets_root)
        self.head, self.threshold = _load_reject_head(assets_root)
        self.checkpoint_sha256 = EXPECTED_EPOCH3_SHA256
        self.reject_head_sha256 = EXPECTED_REJECT_HEAD_SHA256

    def score(self, img) -> CropScore:
        from data import PackRefusal  # w6trainer-src, on sys.path via Recognizer
        rec = self.rec
        try:
            x = rec._preprocess(img, rec.decl).unsqueeze(0)
        except PackRefusal:
            return CropScore("", 0.0, None, True, True)
        a = np.asarray(img.convert("L"), dtype=np.float32)
        stats = torch.tensor([[float(np.log1p(img.width)),
                               float(np.log1p(img.height)),
                               float(img.width) / max(1.0, float(img.height)),
                               float((a < 128).mean())]])
        model = rec.model
        with torch.no_grad():
            h = torch.relu(model.head_fc(model.features(x).mean(dim=(2, 3))))
            prob = model.head_out(h).softmax(1)
            p, i = prob.max(1)
            rscore = float(self.head(torch.cat([h, p.unsqueeze(1), stats], dim=1))[0, 0])
        return CropScore(rec.classes[int(i)], float(p), rscore,
                         rscore > self.threshold, False)
