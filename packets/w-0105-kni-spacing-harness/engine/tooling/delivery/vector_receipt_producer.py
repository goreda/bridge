#!/usr/bin/env python3
"""Build a full-cmap vector receipt from a pinned manifest and measurements."""
import argparse
import json
import math
from pathlib import Path

SCHEMA = "kni.vector-input-manifest.v1"
RECEIPT_SCHEMA = "kni.vector-delivery-gate.v1"
METRICS = {
    "symmetric_difference_area": ("area_floor", "unit^2"),
    "hausdorff": ("distance_floor", "units"),
}


class ReceiptInputError(ValueError):
    """Raised when a pinned manifest or measurement set is incomplete or invalid."""


def codepoint(value):
    if isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 0x10FFFF:
        return value
    if isinstance(value, str):
        raw = value[2:] if value.startswith("U+") else value
        try:
            result = int(raw, 16)
        except ValueError as exc:
            raise ReceiptInputError(f"invalid codepoint: {value}") from exc
        if 0 <= result <= 0x10FFFF:
            return result
    raise ReceiptInputError(f"invalid codepoint: {value!r}")


def _read_json(path, description):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ReceiptInputError(f"{description} is unreadable: {exc}") from exc


def _finite_nonnegative(value, where):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ReceiptInputError(f"{where} must be numeric")
    if not math.isfinite(value) or value < 0:
        raise ReceiptInputError(f"{where} must be finite and nonnegative")
    return value


def build_receipt(manifest, measurements, measured_cmap=None):
    if not isinstance(manifest, dict) or set(manifest) != {"schema", "reference_font_sha256", "codepoints"}:
        raise ReceiptInputError("manifest fields do not match the input manifest schema")
    if manifest["schema"] != SCHEMA:
        raise ReceiptInputError("unsupported input manifest schema")
    reference_hash = manifest["reference_font_sha256"]
    if not isinstance(reference_hash, str) or len(reference_hash) != 64 or any(c not in "0123456789abcdef" for c in reference_hash):
        raise ReceiptInputError("reference_font_sha256 must be 64 lowercase hexadecimal characters")
    if not isinstance(manifest["codepoints"], list) or not manifest["codepoints"]:
        raise ReceiptInputError("manifest codepoints must be a non-empty list")
    expected = [codepoint(value) for value in manifest["codepoints"]]
    if len(set(expected)) != len(expected):
        raise ReceiptInputError("manifest contains duplicate codepoints")
    expected_set = set(expected)
    if measured_cmap is not None and expected_set != set(measured_cmap):
        raise ReceiptInputError("manifest codepoints do not exactly match the measured source cmap")
    if not isinstance(measurements, dict) or set(measurements) != {"schema", "reference_font_sha256", "glyphs"}:
        raise ReceiptInputError("measurement fields must be schema, reference_font_sha256, and glyphs")
    if measurements["schema"] != "kni.vector-measurements.v1":
        raise ReceiptInputError("unsupported vector measurements schema")
    if measurements["reference_font_sha256"] != reference_hash:
        raise ReceiptInputError("measurement reference font hash does not match the manifest")
    if not isinstance(measurements["glyphs"], list):
        raise ReceiptInputError("measurement glyphs must be a list")

    by_cp = {}
    for glyph in measurements["glyphs"]:
        if not isinstance(glyph, dict) or set(glyph) != {"codepoint", "path_label", "symmetric_difference_area", "area_floor", "hausdorff", "distance_floor"}:
            raise ReceiptInputError("each measurement glyph needs codepoint, path_label, both metrics, and both floors")
        cp = codepoint(glyph["codepoint"])
        if cp in by_cp:
            raise ReceiptInputError(f"duplicate measurement codepoint U+{cp:04X}")
        if glyph["path_label"] != "vector":
            raise ReceiptInputError(f"U+{cp:04X} measurement path_label must be vector")
        for field in METRICS:
            _finite_nonnegative(glyph[field], f"U+{cp:04X} {field}")
        for limit_field, _ in METRICS.values():
            _finite_nonnegative(glyph[limit_field], f"U+{cp:04X} {limit_field}")
        by_cp[cp] = glyph
    if set(by_cp) != expected_set:
        missing = sorted(expected_set - set(by_cp))
        extra = sorted(set(by_cp) - expected_set)
        raise ReceiptInputError(f"measurement codepoints must exactly match manifest; missing={missing}, extra={extra}")

    glyph_rows = []
    table_rows = []
    all_pass = True
    for cp in sorted(expected_set):
        source = by_cp[cp]
        row = {"codepoint": cp, "path_label": "vector"}
        for metric, (limit_field, unit) in METRICS.items():
            value = source[metric]
            limit = source[limit_field]
            passed = value <= limit
            all_pass = all_pass and passed
            row[metric] = value
            row[limit_field] = limit
            table_rows.append({
                "codepoint": cp,
                "path_label": "vector",
                "metric": metric,
                "value": value,
                "limit": limit,
                "unit": unit,
                "pass": passed,
            })
        glyph_rows.append(row)
    return {
        "schema": RECEIPT_SCHEMA,
        "source_font_sha256": reference_hash,
        "status": "PASS" if all_pass else "FAIL",
        "glyphs": glyph_rows,
        "table_rows": table_rows,
    }


def produce(manifest_path, measurements_path, output_path, measured_cmap=None):
    receipt = build_receipt(_read_json(manifest_path, "input manifest"), _read_json(measurements_path, "measurements"), measured_cmap)
    Path(output_path).write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--measurements", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--measured-cmap", help="JSON file with an independent codepoint list from the pinned source font")
    args = parser.parse_args()
    try:
        measured_cmap = None
        if args.measured_cmap:
            measured = _read_json(args.measured_cmap, "measured cmap")
            if not isinstance(measured, dict) or measured.get("schema") != "kni.measured-cmap.v1" or not isinstance(measured.get("codepoints"), list):
                raise ReceiptInputError("measured cmap must use kni.measured-cmap.v1 and a codepoints list")
            measured_cmap = {codepoint(value) for value in measured["codepoints"]}
        result = produce(args.manifest, args.measurements, args.output, measured_cmap)
    except ReceiptInputError as exc:
        parser.exit(2, f"receipt input error: {exc}\n")
    print(json.dumps({"status": result["status"], "glyph_count": len(result["glyphs"]), "table_row_count": len(result["table_rows"])}))
    raise SystemExit(0 if result["status"] == "PASS" else 1)
