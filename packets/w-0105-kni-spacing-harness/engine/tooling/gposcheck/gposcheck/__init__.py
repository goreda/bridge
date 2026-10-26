"""Independent acceptance checker for kerning (GPOS) output of a font writer.

The checker never calls the writer. It reads the original font bytes, the writer's
output font bytes and the writer's declared pair list, and reports what the output
font actually contains, using fontTools (table parsing) and HarfBuzz (shaping).
"""
from .core import check, Declared, RECEIPT_VERSION  # noqa: F401
