#!/usr/bin/env python3
"""Assemble a synthetic-only evidence pack through KNI delivery tools.

This smoke runner generates a disposable CFF1 font and test captures, invokes
actual vector receipt, manifest, delivery-gate, and seal CLIs, then writes all
results under a caller-selected fresh output directory. Never use this pack as
font certification: every input is synthetic and the review is test-only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(cmd, cwd):
    print("$", " ".join(map(str, cmd)), flush=True)
    subprocess.run(list(map(str, cmd)), cwd=cwd, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tools", type=Path, default=Path(__file__).parent)
    parser.add_argument("--output", type=Path, required=True, help="fresh output directory; it must not exist")
    args = parser.parse_args()
    tools = args.tools.resolve()
    root = args.output.resolve()
    if root.exists():
        raise SystemExit(f"refusing to overwrite existing output: {root}")
    if not tools.is_dir():
        raise SystemExit(f"delivery tools directory not found: {tools}")
    root.mkdir(parents=True)
    (root / "SYNTHETIC_ONLY.txt").write_text(
        "SYNTHETIC SMOKE TEST ONLY. Generated font, captures, measurements, and review are not real source evidence.\n",
        encoding="utf-8",
    )
    work = root / "inputs"
    work.mkdir()
    evidence = root / "evidence"

    # Generate a tiny test-only CFF font, including A and an intentional blank space.
    fb = FontBuilder(1000, isTTF=False)
    order = [".notdef", "A", "space"]
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({65: "A", 32: "space"})
    chars = {}
    for name in order:
        pen = T2CharStringPen(600, None)
        if name != "space":
            pen.moveTo((50, 0)); pen.lineTo((550, 0)); pen.lineTo((300, 700)); pen.closePath()
        chars[name] = pen.getCharString()
    fb.setupCFF("SyntheticSmoke", {"FullName": "Synthetic Smoke", "FamilyName": "Synthetic Smoke", "Weight": "Regular"}, chars, {})
    fb.setupHorizontalMetrics({name: (600, 0) for name in order})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
    fb.setupNameTable({"familyName": "Synthetic Smoke", "styleName": "Regular", "uniqueFontIdentifier": "Synthetic Smoke", "fullName": "Synthetic Smoke", "psName": "SyntheticSmoke"})
    fb.setupOS2(); fb.setupPost()
    font_path = work / "synthetic.otf"
    fb.save(font_path)
    font = TTFont(font_path)
    font_sha = sha(font_path)
    identity = {"family": "Synthetic Smoke", "style": "Regular"}

    glyphs = []
    for cp, name in sorted(font.getBestCmap().items()):
        tile = work / f"U{cp:06X}.png"
        image = Image.new("L", (16, 16), 255)
        if name != "space":
            ImageDraw.Draw(image).rectangle((2, 2, 13, 13), fill=0)
        image.save(tile)
        cs = font["CFF "].cff.topDictIndex[0].CharStrings[name]
        cs.compile()
        audit = work / f"U{cp:06X}.audit.json"
        fit = {
            "path": "capture_png>fit_captured>integer_charstring",
            "parameters": {"rdp_eps": 1, "squared_error": 1, "max_refits": 0},
            "frame": {"scale": 1, "translation": [0, 0]},
            "measurement": {"spans": 3},
        }
        audit_obj = {"schema": "kni.capture-audit.v1", **fit,
                     "charstring_hex": cs.bytecode.hex(), "source_png_hex": tile.read_bytes().hex()}
        audit.write_text(json.dumps(audit_obj, sort_keys=True), encoding="utf-8")
        capture = {"path": tile.name, "sha256": sha(tile), "status": "intentional_blank" if name == "space" else "ink",
                   "reason": "synthetic empty glyph" if name == "space" else None,
                   "source_identity": identity, "synthetic": False, "role": "glyph"}
        glyphs.append({"codepoint": cp, "capture": capture,
                       "capture_audit": {"path": audit.name, "sha256": sha(audit)},
                       "fit": {"parameters": fit["parameters"], "frame": fit["frame"]}})

    intake = work / "intake.json"
    intake.write_text(json.dumps({"source_revision": "synthetic-smoke-only", "source_identity": identity,
                                  "required_codepoints": [], "glyphs": glyphs}, indent=2), encoding="utf-8")
    manifest_path = work / "manifest.json"
    run([sys.executable, tools / "build_delivery_manifest.py", "--font", font_path,
         "--intake", intake, "--engine-revision", "synthetic-smoke-only", "--output", manifest_path], tools)

    cps = sorted(font.getBestCmap())
    vector_manifest = work / "vector-input.json"
    vector_measurements = work / "vector-measurements.json"
    measured_cmap = work / "measured-cmap.json"
    vector_receipt = work / "vector-receipt.json"
    vector_manifest.write_text(json.dumps({"schema": "kni.vector-input-manifest.v1", "reference_font_sha256": font_sha, "codepoints": cps}, indent=2), encoding="utf-8")
    vector_measurements.write_text(json.dumps({"schema": "kni.vector-measurements.v1", "reference_font_sha256": font_sha,
        "glyphs": [{"codepoint": cp, "path_label": "vector", "symmetric_difference_area": 0.0, "area_floor": 1.0,
                    "hausdorff": 0.0, "distance_floor": 1.0} for cp in cps]}, indent=2), encoding="utf-8")
    measured_cmap.write_text(json.dumps({"schema": "kni.measured-cmap.v1", "reference_font_sha256": font_sha, "codepoints": cps}, indent=2), encoding="utf-8")
    run([sys.executable, tools / "vector_receipt_producer.py", "--manifest", vector_manifest,
         "--measurements", vector_measurements, "--measured-cmap", measured_cmap, "--output", vector_receipt], tools)
    run([sys.executable, tools / "delivery_gate.py", "--font", font_path, "--manifest", manifest_path,
         "--output", evidence, "--ppem", "128", "--threshold", "128", "--vector-receipt", vector_receipt,
         "--reference-font-sha256", font_sha], tools)

    gate = json.loads((evidence / "gate.json").read_text(encoding="utf-8"))
    if gate.get("status") != "PASS":
        raise SystemExit(f"synthetic delivery gate did not pass: {gate.get('failures')}")
    sums = json.loads((evidence / "SHA256SUMS.json").read_text(encoding="utf-8"))
    review = work / "synthetic-test-review.json"
    review.write_text(json.dumps({"reviewer": "synthetic smoke runner pixel check", "status": "APPROVED",
        "font_sha256": font_sha, "gate_sha256": sha(evidence / "gate.json"),
        "images": {name: digest for name, digest in sums.items() if name.endswith(".png")}}, indent=2), encoding="utf-8")
    seal_out = root / "synthetic-seal-result.json"
    run([sys.executable, tools / "seal_evidence.py", "--pack", evidence, "--review", review, "--output", seal_out], tools)
    sealed = json.loads(seal_out.read_text(encoding="utf-8"))
    if sealed.get("status") != "DELIVERY_READY":
        raise SystemExit(f"synthetic test sealing failed: {sealed}")
    # Explicitly test-only wrapper status, separate from the native seal's assertion.
    report = {"result": "synthetic-smoke-passed-not-production-evidence", "synthetic_only": True,
              "font_sha256": font_sha, "cmap_codepoints": [f"U+{cp:04X}" for cp in cps],
              "evidence_sha256s": sums, "native_seal_status": sealed["status"],
              "warning": "Do not interpret the native test seal as real delivery authorization or source-font evidence."}
    (root / "RUN-REPORT.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
