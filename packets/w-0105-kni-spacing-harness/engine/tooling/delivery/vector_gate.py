#!/usr/bin/env python3
"""Validate a hash-bound vector-fidelity receipt for delivery."""
import argparse
import hashlib
import json
import math
from pathlib import Path

SCHEMA = "kni.vector-delivery-gate.v1"
METRICS = {
    "symmetric_difference_area": "unit^2",
    "hausdorff": "units",
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _codepoint(value):
    if isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 0x10FFFF:
        return value
    if isinstance(value, str):
        try:
            raw = value[2:] if value.startswith("U+") else value
            result = int(raw, 16)
            return result if 0 <= result <= 0x10FFFF else None
        except ValueError:
            return None
    return None


def validate(receipt_path, reference_font_sha256, expected_codepoints):
    receipt_path = Path(receipt_path)
    try:
        receipt = json.loads(receipt_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return {"status": "FAIL", "schema": SCHEMA, "receipt_sha256": sha(receipt_path) if receipt_path.is_file() else None, "source_font_sha256": reference_font_sha256, "glyph_count": 0, "table_row_count": 0, "criteria": {"symmetric_difference_area": "value <= area_floor", "hausdorff": "value <= distance_floor"}, "failures": [f"vector receipt unreadable: {exc}"]}
    failures = []
    if receipt.get("schema") != SCHEMA:
        failures.append("unsupported vector receipt schema")
    if receipt.get("source_font_sha256") != reference_font_sha256:
        failures.append("vector receipt source font hash mismatch")
    glyphs = receipt.get("glyphs")
    expected = set(expected_codepoints)
    if not isinstance(glyphs, list):
        glyphs = []
        failures.append("vector receipt glyph rows missing")
    by_code = {}
    for glyph in glyphs:
        if not isinstance(glyph, dict):
            failures.append("invalid vector glyph row")
            continue
        cp = _codepoint(glyph.get("codepoint"))
        if cp is None:
            failures.append("invalid vector glyph codepoint")
            continue
        if cp in by_code:
            failures.append(f"duplicate vector glyph row: {cp}")
        by_code[cp] = glyph
        if glyph.get("path_label") != "vector":
            failures.append(f"{cp}: vector path label missing or incorrect")
    if set(by_code) != expected:
        failures.append("vector receipt codepoints do not exactly cover the source cmap")
    rows = receipt.get("table_rows")
    if not isinstance(rows, list):
        rows = []
        failures.append("vector table rows missing")
    seen = set()
    for row in rows:
        if not isinstance(row, dict):
            failures.append("invalid vector table row")
            continue
        cp = _codepoint(row.get("codepoint"))
        if cp is None:
            failures.append("invalid vector table codepoint")
            continue
        metric = row.get("metric")
        key = (cp, metric)
        if key in seen:
            failures.append(f"duplicate vector metric row: {cp} {metric}")
        seen.add(key)
        if row.get("path_label") != "vector":
            failures.append(f"{cp} {metric}: table row path label missing or incorrect")
        if metric not in METRICS:
            failures.append(f"{cp}: unsupported vector metric")
            continue
        if row.get("unit") != METRICS[metric]:
            failures.append(f"{cp} {metric}: unit mismatch")
        value, limit = row.get("value"), row.get("limit")
        if not isinstance(value, (int, float)) or isinstance(value, bool) or not math.isfinite(value) or value < 0:
            failures.append(f"{cp} {metric}: value must be finite and nonnegative")
            continue
        if not isinstance(limit, (int, float)) or isinstance(limit, bool) or not math.isfinite(limit) or limit < 0:
            failures.append(f"{cp} {metric}: limit must be finite and nonnegative")
            continue
        passed = value <= limit
        if not passed:
            failures.append(f"{cp} {metric}: measured value exceeds its limit")
        if row.get("pass") is not passed:
            failures.append(f"{cp} {metric}: pass flag disagrees with the gate criterion")
        glyph = by_code.get(cp)
        if glyph is not None:
            expected_value = glyph.get(metric)
            expected_limit = glyph.get("area_floor" if metric == "symmetric_difference_area" else "distance_floor")
            if expected_value != value or expected_limit != limit:
                failures.append(f"{cp} {metric}: summary and table row disagree")
    required = {(cp, metric) for cp in expected for metric in METRICS}
    if seen != required:
        failures.append("vector table rows do not exactly cover every glyph and required metric")
    overall = all(row.get("pass") is True for row in rows if isinstance(row, dict)) and not any("measured value exceeds" in item for item in failures)
    if receipt.get("status") != "PASS":
        failures.append("vector receipt status is not PASS")
    if not overall:
        failures.append("vector receipt contains a non-passing metric row")
    return {
        "status": "PASS" if not failures else "FAIL",
        "schema": SCHEMA,
        "receipt_sha256": sha(receipt_path),
        "source_font_sha256": reference_font_sha256,
        "glyph_count": len(glyphs),
        "table_row_count": len(rows),
        "criteria": {
            "symmetric_difference_area": "value <= area_floor",
            "hausdorff": "value <= distance_floor",
        },
        "failures": failures,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--reference-font-sha256", required=True)
    parser.add_argument("--codepoints", required=True, help="comma-separated U+hex code points")
    parser.add_argument("--output")
    args = parser.parse_args()
    cps = {int(item[2:] if item.startswith("U+") else item, 16) for item in args.codepoints.split(",") if item}
    result = validate(args.receipt, args.reference_font_sha256, cps)
    rendered = json.dumps(result, sort_keys=True)
    if args.output:
        Path(args.output).write_text(rendered + "\n")
    print(rendered)
    raise SystemExit(0 if result["status"] == "PASS" else 1)
