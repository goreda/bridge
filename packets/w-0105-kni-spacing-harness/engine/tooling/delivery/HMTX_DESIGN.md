# Horizontal metric comparison proposal

Design only. Outline area and Hausdorff do not measure hmtx fidelity. Add an independent metric scope, not extra meaning to existing outline PASS.

For each reference cmap codepoint, compare reference and candidate raw hmtx advanceWidth and leftSideBearing in equal unitsPerEm font-unit frames, with no scaling, normalization, hinting or phantom-point borrowing. For glyph IDs below numberOfHMetrics, take both fields from the corresponding longHorMetric. For later glyph IDs, reuse the final long advanceWidth and read signed leftSideBearing from the trailing array. Verify numberOfHMetrics in [1,numGlyphs] and complete table extents before reading. UPM mismatch is frame n/a, never silently rescaled.

Report reference and candidate values and signed candidate-minus-reference differences, plus absolute differences for threshold evaluation. These are integers in font units, so exact-zero equality is a useful default diagnostic. Any nonzero acceptance threshold must be an explicit pinned contract, not borrowed from outline flattening floors or Params.grid. Keep advance and LSB separate: cancellation is not fidelity.

Missing codepoint, glyph index, truncated hmtx or unsupported source produces codepoint + metric-specific n/a reason, no zero. Preserve the complete reference cmap keyset. A failed outline measurement need not cancel a valid raw hmtx diagnostic and vice versa. Empty outlines can still carry useful advances and bearings; empty-empty is not metric n/a when both hmtx entries exist.

Raw-table comparison is not rasterizer-effective metrics: USE_MY_METRICS, TrueType instructions, phantom points, variations and device-size hinting can change effective bearings/advances. Label scope raw-hmtx-v1. For an eventual effective-metrics mode, require a pinned interpreter, variation coordinates, size/load flags and separate method version; otherwise mark that scope n/a. Neither mode establishes kerning, shaping, vertical metrics or full font fidelity.

Source for raw bearing placement, phantom points and USE_MY_METRICS distinction:
https://learn.microsoft.com/en-us/typography/opentype/spec/glyf
