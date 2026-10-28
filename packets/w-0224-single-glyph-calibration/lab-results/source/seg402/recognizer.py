"""013 recognizer adapter (card 402): per-input scoring built from the trainer's
read-only handoff. The trainer exposes aggregate eval only (card 345 finding);
this adapter wraps the pinned R2Net + preprocess exactly as the handoff's
inference_api.py documents. No training, no weight mutation, read-only load."""
import json
import sys
from pathlib import Path

import torch
from PIL import Image
from .abstention import RecognitionAbstain

CLASSES_PATH = Path(__file__).resolve().parent.parent / "w6trainer-src" / ".." / "labels-62.json"


class Recognizer:
    """Per-crop scorer. Input contract: a single tight-cropped glyph tile image;
    preprocess() does the crop/pad/resize to 105x105 under the pack manifest
    polarity declarations. Multi-char crops are out of contract and used only
    by the confidence probe, never as accepted output."""

    def __init__(self, root: Path):
        root = Path(root)
        sys.path.insert(0, str(root / "w6trainer-src"))
        from data import load_manifest, preprocess, PackRefusal  # handoff sources @ 3a1f3274
        from model import R2Net
        self._preprocess = preprocess
        self._pack_refusal = PackRefusal
        self.classes = json.loads((root / "labels-62.json").read_text())["classes"]
        ck = torch.load(root / "epoch-3.pt", map_location="cpu", weights_only=False)
        self.model = R2Net(num_classes=len(self.classes))
        self.model.load_state_dict(ck["model"])
        self.model.eval()
        self.decl = load_manifest(root / "pack")
        self.checkpoint_sha256 = "d5068a873d93af7226b0078ffc3dfa5cec9355b668fa54846781c74bd9cbf4f9"

    def _prepare(self, img):
        try:
            return self._preprocess(img, self.decl)
        except self._pack_refusal as exc:
            if str(exc) != "TileNoInk":
                raise
            # Preprocess already determined that no pixel meets its unchanged
            # declared ink predicate. Preserve the reason, not a made-up score.
            gray = img.convert("L")
            if self.decl.inversion:
                gray = Image.eval(gray, lambda v: 255 - v)
            low, high = gray.getextrema()
            reason = "blank_paper" if low == high == 255 else "threshold_rejected"
            return RecognitionAbstain("TileNoInk", reason, low, high,
                                      int(round(self.decl.crop_threshold * 255)))

    def score(self, img: Image.Image):
        """Return the original score tuple or an explicit per-crop abstain."""
        x = self._prepare(img)
        if isinstance(x, RecognitionAbstain):
            return x
        with torch.no_grad():
            logits = self.model(x.unsqueeze(0))[0]
        probs = logits.softmax(0)
        p, i = probs.max(0)
        return self.classes[int(i)], float(p), float(logits[int(i)] - logits.logsumexp(0))

    def score_batch(self, imgs: list) -> list:
        """Preserve order and length, including abstains among valid images."""
        prepared = [self._prepare(img) for img in imgs]
        indices = [i for i, x in enumerate(prepared)
                   if not isinstance(x, RecognitionAbstain)]
        out = list(prepared)
        if not indices:
            return out
        with torch.no_grad():
            logits = self.model(torch.stack([prepared[i] for i in indices]))
        probs = logits.softmax(1)
        for index, row, logit in zip(indices, probs, logits):
            p, i = row.max(0)
            out[index] = (self.classes[int(i)], float(p),
                          float(logit[int(i)] - logit.logsumexp(0)))
        return out
