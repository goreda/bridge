"""Typed per-crop inference abstains; never a fabricated class or probability."""
from dataclasses import dataclass


@dataclass(frozen=True)
class RecognitionAbstain:
    code: str
    reason: str
    gray_min: int
    gray_max: int
    threshold: int
