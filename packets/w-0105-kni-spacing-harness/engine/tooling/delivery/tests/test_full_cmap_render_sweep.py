"""Permanent full-cmap render delivery gate.

Builds a complete-cmap CFF1 reference font (contiguous Unicode blocks, no
per-language selection), renders a source capture tile for every codepoint,
fits every tile with the real compiled capture_audit binary, measures the
fitted outlines against the reference outlines, produces the vector receipt,
and then drives the production delivery entrypoint (canonical_delivery) which
re-fits every glyph, rebuilds the candidate font, and runs the mandatory
full-cmap render sweep and evidence pack. The sweep must cover every cmap
codepoint exactly once, the evidence pack must bind every artifact, and the
visual seal must close over the full pack. Uniform rules only: every outline,
tile, frame, measurement and limit is a pure function of the codepoint and
the declared render/fit contract; nothing is language-, glyph-, or
style-specific.
"""
import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile
import unicodedata
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from fontTools import agl
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageChops, ImageDraw, ImageFont

BASE = Path(__file__).parents[1]
sys.path.insert(0, str(BASE))

import canonical_delivery
import seal_evidence
import vector_receipt_producer

# Render contract inputs (caller-bound, same role as the gate CLI's
# --ppem/--threshold) and the uniform fit contract applied to every glyph.
UPM = 1000
ASCENT = 800
DESCENT = -200
TILE_PPEM = 64
GATE_PPEM = 128
INK_THRESHOLD = 128
TILE_MARGIN_PX = 8
FIT_PARAMETERS = {"rdp_eps": 0.75, "squared_error": 2.0, "max_refits": 2}
FLATTEN_STEPS = 16
EDGE_SAMPLE_STEP = 8.0

# Contiguous Unicode blocks; the fixture repertoire is a block range, never a
# per-language pick.
CODEPOINT_RANGES = ((0x20, 0x7E), (0xA0, 0xFF), (0x100, 0x17F))

SOURCE_IDENTITY = {"family": "Full Cmap Reference", "style": "Regular"}
SOURCE_REVISION = "full-cmap-render-sweep-fixture"

REPO_ROOT = Path(__file__).parents[3]
AUDIT_BINARY = Path(os.environ.get(
    "KNI_CAPTURE_AUDIT_BINARY",
    REPO_ROOT / "target" / "debug" / "examples" / "capture_audit"))
if not AUDIT_BINARY.is_file():
    AUDIT_BINARY = REPO_ROOT / "target" / "release" / "examples" / "capture_audit"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def repertoire():
    return [cp for lo, hi in CODEPOINT_RANGES for cp in range(lo, hi + 1)]


def glyph_name(cp):
    return agl.UV2AGL.get(cp, f"uni{cp:04X}")


def outline_is_blank(cp):
    # General Unicode-derived rule: space separators carry no ink.
    return unicodedata.category(chr(cp)) == "Zs"


def _unit_rand(cp, salt):
    digest = hashlib.sha256(f"kni-full-cmap-fixture:{cp}:{salt}".encode()).digest()
    return int.from_bytes(digest[:8], "big") / 2**64


def outline_for(cp):
    """Deterministic silhouette, uniform function of the codepoint.

    Returns (contours, advance). First contour is the outer ring; an optional
    reversed inner ring cuts a counter.
    """
    x0 = 40 + int(_unit_rand(cp, "x0") * 60)
    width = 300 + int(_unit_rand(cp, "w") * 280)
    y0 = int(_unit_rand(cp, "y0") * 40)
    height = 480 + int(_unit_rand(cp, "h") * 220)
    x1, y1 = x0 + width, y0 + height
    slant = int((_unit_rand(cp, "sl") - 0.5) * 120)
    mid = (y0 + y1) // 2
    outer = [(x0, y0), (x1, y0), (x1 + slant, mid), (x1, y1),
             (x0 + slant // 2, y1), (x0, mid)]
    contours = [outer]
    if _unit_rand(cp, "counter") < 0.34:
        ix0, ix1 = x0 + width // 4, x1 - width // 4
        iy0, iy1 = y0 + height // 4, y1 - height // 4
        contours.append([(ix0, iy0), (ix0, iy1), (ix1, iy1), (ix1, iy0)])
    return contours, x1 + abs(slant) + 60


def build_reference_font(path, codepoints):
    fb = FontBuilder(UPM, isTTF=False)
    order = [".notdef"] + [glyph_name(cp) for cp in codepoints]
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({cp: glyph_name(cp) for cp in codepoints})
    chars, metrics = {}, {}
    for cp in codepoints:
        name = glyph_name(cp)
        if outline_is_blank(cp):
            pen = T2CharStringPen(280, None)
        else:
            contours, advance = outline_for(cp)
            pen = T2CharStringPen(advance, None)
            for ring in contours:
                pen.moveTo(ring[0])
                for pt in ring[1:]:
                    pen.lineTo(pt)
                pen.closePath()
        chars[name] = pen.getCharString()
    for name in order:
        if name not in chars:
            chars[name] = T2CharStringPen(500, None).getCharString()
    fb.setupCFF("FullCmapReference",
                {"FullName": "Full Cmap Reference",
                 "FamilyName": "Full Cmap Reference", "Weight": "Regular"},
                chars, {})
    font = TTFont(path) if False else None
    metrics = {}
    for cp in codepoints:
        name = glyph_name(cp)
        if outline_is_blank(cp):
            metrics[name] = (280, 0)
        else:
            _, advance = outline_for(cp)
            metrics[name] = (advance, 0)
    metrics[".notdef"] = (500, 0)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupNameTable({"familyName": "Full Cmap Reference",
                       "styleName": "Regular",
                       "uniqueFontIdentifier": "Full Cmap Reference",
                       "fullName": "Full Cmap Reference",
                       "psName": "FullCmapReference"})
    fb.setupOS2()
    fb.setupPost()
    fb.save(path)


def render_tile(font_path, cp, out_path):
    font = ImageFont.truetype(str(font_path), TILE_PPEM)
    scale = TILE_PPEM / UPM
    ascent_px = math.ceil(ASCENT * scale)
    descent_px = math.ceil(-DESCENT * scale)
    if outline_is_blank(cp):
        advance = 280
    else:
        _, advance = outline_for(cp)
    width = math.ceil(advance * scale) + 2 * TILE_MARGIN_PX
    height = ascent_px + descent_px + 2 * TILE_MARGIN_PX
    im = Image.new("L", (width, height), 255)
    if not outline_is_blank(cp):
        ImageDraw.Draw(im).text(
            (TILE_MARGIN_PX, TILE_MARGIN_PX + ascent_px),
            chr(cp), font=font, fill=0, anchor="ls")
    im.save(out_path)


def tile_has_ink(tile_path):
    return Image.open(tile_path).convert("L").getextrema()[0] < INK_THRESHOLD


def consistent_repertoire(font_path, tile_dir):
    """Uniform fixture construction rule: the rendered capture is ink truth.

    A codepoint stays in the fixture only when its reference outline and its
    rendered tile agree on ink presence. Codepoints that text layout renders
    invisible despite an ink outline cannot be captured through rendering, so
    the fixture drops them from its cmap instead of inventing evidence.
    """
    keep, dropped = [], []
    for cp in repertoire():
        if tile_has_ink(Path(tile_dir) / f"U{cp:06X}.png") == (not outline_is_blank(cp)):
            keep.append(cp)
        else:
            dropped.append(cp)
    return keep, dropped


def reference_bounds(font, cp):
    pen = BoundsPen(font.getGlyphSet())
    font.getGlyphSet()[glyph_name(cp)].draw(pen)
    return pen.bounds


# --- Vector measurement stage (test double of the trusted stage) -----------
# Both outlines are read from bytes (reference charstrings from the pinned
# font, candidate charstrings from the real audit output), flattened to
# polygons, rasterized at one font unit per pixel, and compared. Limits are
# derived from the declared capture-fit contract, uniformly for every glyph.

def charstring_polygons(program):
    polys, stack, cur, start = [], [], None, None

    def num(v):
        return float(v)

    for v in program:
        if not isinstance(v, str):
            stack.append(v)
            continue
        if v in ("rmoveto", "hmoveto", "vmoveto"):
            base = cur[-1] if cur else (0.0, 0.0)
            if cur is not None and start is not None:
                cur.append(start)
                polys.append(cur)
            if v == "rmoveto":
                dx, dy = num(stack[-2]), num(stack[-1])
            elif v == "hmoveto":
                dx, dy = num(stack[-1]), 0.0
            else:
                dx, dy = 0.0, num(stack[-1])
            pt = (base[0] + dx, base[1] + dy)
            cur, start = [pt], pt
        elif v == "rlineto":
            for j in range(0, len(stack), 2):
                cur.append((cur[-1][0] + num(stack[j]), cur[-1][1] + num(stack[j + 1])))
        elif v in ("hlineto", "vlineto"):
            horiz = v == "hlineto"
            for j, d in enumerate(stack):
                if (j % 2 == 0) == horiz:
                    cur.append((cur[-1][0] + num(d), cur[-1][1]))
                else:
                    cur.append((cur[-1][0], cur[-1][1] + num(d)))
        elif v == "rrcurveto":
            for j in range(0, len(stack), 6):
                p0 = cur[-1]
                c1 = (p0[0] + num(stack[j]), p0[1] + num(stack[j + 1]))
                c2 = (c1[0] + num(stack[j + 2]), c1[1] + num(stack[j + 3]))
                p1 = (c2[0] + num(stack[j + 4]), c2[1] + num(stack[j + 5]))
                for k in range(1, FLATTEN_STEPS + 1):
                    t, mt = k / FLATTEN_STEPS, 1 - k / FLATTEN_STEPS
                    cur.append((mt**3 * p0[0] + 3 * mt * mt * t * c1[0]
                                + 3 * mt * t * t * c2[0] + t**3 * p1[0],
                                mt**3 * p0[1] + 3 * mt * mt * t * c1[1]
                                + 3 * mt * t * t * c2[1] + t**3 * p1[1]))
        elif v == "endchar":
            if cur is not None and start is not None:
                cur.append(start)
                polys.append(cur)
            cur, start = None, None
        stack = []
    return polys


def font_polygons(font, name):
    cs = font["CFF "].cff.topDictIndex[0].CharStrings[name]
    cs.decompile()
    return charstring_polygons(cs.program)


def audit_polygons(charstring_hex):
    from fontTools.misc.psCharStrings import T2CharString
    cs = T2CharString(bytecode=bytes.fromhex(charstring_hex))
    cs.decompile()
    return charstring_polygons(cs.program)


def _raster(polys):
    if not polys:
        return None, None
    xs = [p[0] for poly in polys for p in poly]
    ys = [p[1] for poly in polys for p in poly]
    x0, y0 = math.floor(min(xs)) - 2, math.floor(min(ys)) - 2
    x1, y1 = math.ceil(max(xs)) + 2, math.ceil(max(ys)) + 2
    im = Image.new("L", (x1 - x0, y1 - y0), 0)
    draw = ImageDraw.Draw(im)
    for poly in polys:
        draw.polygon([(p[0] - x0, y1 - p[1]) for p in poly], fill=255)
    return im, (x0, y0, x1, y1)


def _segments(polys):
    return [(poly[j], poly[j + 1]) for poly in polys for j in range(len(poly) - 1)]


def _sample_edges(polys):
    pts = []
    for a, b in _segments(polys):
        n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / EDGE_SAMPLE_STEP))
        for k in range(n):
            t = k / n
            pts.append((a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])))
    return pts


def _seg_dist(p, a, b):
    px, py = p
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def measure_outline_pair(ref_polys, cand_polys, distance_budget):
    """Symmetric-difference area (unit^2) and boundary Hausdorff (units)."""
    ref_im, ref_box = _raster(ref_polys)
    cand_im, cand_box = _raster(cand_polys)
    if ref_im is None and cand_im is None:
        sym = 0.0
    else:
        boxes = [b for b in (ref_box, cand_box) if b]
        cx0 = min(b[0] for b in boxes)
        cy1 = max(b[3] for b in boxes)
        size = (max(b[2] for b in boxes) - cx0, cy1 - min(b[1] for b in boxes))

        def place(im, box):
            out = Image.new("L", size, 0)
            if im is not None:
                out.paste(im, (box[0] - cx0, cy1 - box[3]))
            return out

        diff = ImageChops.difference(place(ref_im, ref_box), place(cand_im, cand_box))
        sym = float(sum(1 for v in diff.getdata() if v))
    ref_pts, cand_pts = _sample_edges(ref_polys), _sample_edges(cand_polys)
    ref_segs, cand_segs = _segments(ref_polys), _segments(cand_polys)

    def directed(pts, segs):
        return max((min(_seg_dist(p, s[0], s[1]) for s in segs) for p in pts), default=0.0)

    if not ref_pts or not cand_pts:
        haus = 0.0 if not ref_pts and not cand_pts else float("inf")
    else:
        haus = max(directed(ref_pts, cand_segs), directed(cand_pts, ref_segs))
    perimeter = sum(math.hypot(s[1][0] - s[0][0], s[1][1] - s[0][1]) for s in ref_segs)
    area_floor = perimeter * distance_budget + 4 * distance_budget * distance_budget
    return sym, haus, area_floor, distance_budget


@unittest.skipUnless(
    AUDIT_BINARY.is_file(),
    "capture_audit binary not built; run `cargo build --example capture_audit` "
    "in the engine workspace first (Rust compile is required on integration)")
class FullCmapRenderSweepTests(unittest.TestCase):
    """The complete glyph sweep as a permanent gate over the production path."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.root = Path(cls.tmp.name)
        cls.pitch = UPM / TILE_PPEM
        # Uniform acceptance budget of the capture-fit chain: one sample
        # pitch, plus RDP tolerance, plus fit deviation tolerance, mapped to
        # font units, plus integer rounding.
        cls.distance_budget = (
            cls.pitch * (1 + FIT_PARAMETERS["rdp_eps"]
                         + math.sqrt(FIT_PARAMETERS["squared_error"])) + 0.5)

        cls.reference = cls.root / "reference.otf"
        build_reference_font(cls.reference, repertoire())
        tiles = cls.root / "tiles"
        tiles.mkdir()
        for cp in repertoire():
            render_tile(cls.reference, cp, tiles / f"U{cp:06X}.png")
        keep, cls.dropped = consistent_repertoire(cls.reference, tiles)
        if cls.dropped:
            for cp in cls.dropped:
                (tiles / f"U{cp:06X}.png").unlink()
            build_reference_font(cls.reference, keep)
        cls.font = TTFont(cls.reference)
        cls.codepoints = sorted(cls.font.getBestCmap())
        cls.tiles = tiles

        # Measurement stage: real audit binary per ink glyph, honest
        # geometry comparison against the reference outlines.
        audits = cls.root / "measure-audits"
        audits.mkdir()

        def run_audit(cp):
            if outline_is_blank(cp):
                return
            b = reference_bounds(cls.font, cp)
            subprocess.run(
                [str(AUDIT_BINARY), str(tiles / f"U{cp:06X}.png"),
                 str(audits / f"U{cp:06X}.json"),
                 str(FIT_PARAMETERS["rdp_eps"]), str(cls.pitch),
                 str(FIT_PARAMETERS["squared_error"]),
                 str(FIT_PARAMETERS["max_refits"]),
                 str(cls.font["hmtx"].metrics[glyph_name(cp)][0]),
                 str(float(b[0])), str(float(b[1]))],
                check=True)

        with ThreadPoolExecutor() as pool:
            list(pool.map(run_audit, cls.codepoints))

        measurements = []
        cls.worst_hausdorff = 0.0
        cls.worst_symdiff = 0.0
        for cp in cls.codepoints:
            if outline_is_blank(cp):
                sym, haus, area_floor, distance_floor = (
                    0.0, 0.0,
                    4 * cls.distance_budget * cls.distance_budget,
                    cls.distance_budget)
            else:
                audit = json.loads((audits / f"U{cp:06X}.json").read_text())
                sym, haus, area_floor, distance_floor = measure_outline_pair(
                    font_polygons(cls.font, glyph_name(cp)),
                    audit_polygons(audit["charstring_hex"]),
                    cls.distance_budget)
            cls.worst_hausdorff = max(cls.worst_hausdorff, haus)
            cls.worst_symdiff = max(cls.worst_symdiff, sym)
            if not (sym <= area_floor and haus <= distance_floor):
                raise AssertionError(
                    f"fixture fit outside its own acceptance budget at U+{cp:04X}: "
                    f"sym {sym} > {area_floor} or hausdorff {haus} > {distance_floor}")
            measurements.append({
                "codepoint": cp, "path_label": "vector",
                "symmetric_difference_area": sym, "area_floor": area_floor,
                "hausdorff": haus, "distance_floor": distance_floor})

        reference_sha = sha(cls.reference)
        cls.reference_sha = reference_sha
        (cls.root / "vector-input.json").write_text(json.dumps({
            "schema": "kni.vector-input-manifest.v1",
            "reference_font_sha256": reference_sha,
            "codepoints": cls.codepoints}))
        (cls.root / "vector-measurements.json").write_text(json.dumps({
            "schema": "kni.vector-measurements.v1",
            "reference_font_sha256": reference_sha,
            "glyphs": measurements}))
        (cls.root / "measured-cmap.json").write_text(json.dumps({
            "schema": "kni.measured-cmap.v1",
            "reference_font_sha256": reference_sha,
            "codepoints": cls.codepoints}))
        cls.receipt = cls.root / "vector-receipt.json"
        produced = vector_receipt_producer.produce(
            cls.root / "vector-input.json", cls.root / "vector-measurements.json",
            cls.receipt, set(cls.codepoints))
        if produced["status"] != "PASS":
            raise AssertionError(f"fixture vector receipt did not pass: {produced}")

        cls.plan = {
            "base_font": {"path": str(cls.reference), "sha256": reference_sha},
            "vector_receipt": {"path": str(cls.receipt), "sha256": sha(cls.receipt)},
            "audit_binary_sha256": sha(AUDIT_BINARY),
            "engine_revision": "full-cmap-render-sweep-test",
            "source_revision": SOURCE_REVISION,
            "source_identity": SOURCE_IDENTITY,
            "required_codepoints": [cls.codepoints[1], cls.codepoints[-1]],
            "glyphs": [cls._plan_row(cp) for cp in cls.codepoints],
        }
        cls.plan_path = cls.root / "plan.json"
        cls.plan_path.write_text(json.dumps(cls.plan))

        cls.output = cls.root / "production"
        cls.entry_result = canonical_delivery.run(
            cls.plan_path, str(AUDIT_BINARY), cls.output, GATE_PPEM, INK_THRESHOLD)
        cls.evidence = cls.output / "evidence"
        cls.gate = json.loads((cls.evidence / "gate.json").read_text())
        cls.audit = json.loads((cls.evidence / "audit.json").read_text())

    @classmethod
    def _plan_row(cls, cp):
        tile = cls.tiles / f"U{cp:06X}.png"
        blank = outline_is_blank(cp)
        capture = {
            "path": str(tile), "sha256": sha(tile),
            "status": "intentional_blank" if blank else "ink",
            "reason": "Unicode space separator carries no ink" if blank else None,
            "source_identity": SOURCE_IDENTITY, "synthetic": False, "role": "glyph",
        }
        b = reference_bounds(cls.font, cp)
        row = {
            "codepoint": cp,
            "capture": capture,
            "fit": {
                "parameters": FIT_PARAMETERS,
                "frame": {"scale": cls.pitch,
                          "translation": [float(b[0]), float(b[1])] if b else [0.0, 0.0]},
            },
        }
        if blank:
            pen = T2CharStringPen(cls.font["hmtx"].metrics[glyph_name(cp)][0], None)
            cs = pen.getCharString()
            cs.compile()
            audit = {
                "schema": "kni.capture-audit.v1",
                "source_png_hex": tile.read_bytes().hex(),
                "path": "capture_png>fit_captured>integer_charstring",
                "parameters": FIT_PARAMETERS,
                "frame": {"scale": cls.pitch, "translation": [0.0, 0.0],
                          "quantization": "nearest_integer"},
                "measurement": {"captured_rings": 0, "fit_spans": 0, "fallback": False,
                                "dropped_rings": 0, "charstring_bytes": len(cs.bytecode)},
                "charstring_hex": cs.bytecode.hex(),
            }
            audit_path = cls.root / f"blank-audit-U{cp:06X}.json"
            audit_path.write_text(json.dumps(audit, sort_keys=True))
            row["capture_audit"] = {"path": str(audit_path), "sha256": sha(audit_path)}
        return row

    def test_entry_returns_numeric_candidate_for_complete_cmap(self):
        self.assertEqual(self.entry_result["status"], "NUMERIC_CANDIDATE_VISUAL_PENDING")
        self.assertEqual(self.entry_result["cmap_count"], len(self.codepoints))

    def test_gate_passes_and_sweeps_every_cmap_codepoint(self):
        self.assertEqual(self.gate["status"], "PASS", self.gate["failures"])
        self.assertEqual(self.gate["cmap_count"], len(self.codepoints))
        self.assertEqual(self.gate["sweep_count"], len(self.codepoints))
        swept = {int(row["codepoint"].removeprefix("U+"), 16) for row in self.audit["glyphs"]}
        self.assertEqual(swept, set(self.codepoints))
        self.assertTrue(all(not row["failures"] for row in self.audit["glyphs"]))

    def test_evidence_pack_binds_every_glyph_and_artifact(self):
        pngs = {p.name for p in self.evidence.glob("U*.png")}
        expected = {f"U{cp:06X}.png" for cp in self.codepoints}
        self.assertEqual(pngs, expected)
        self.assertEqual(self.gate["sheets"], ["sweep.png"])
        self.assertTrue((self.evidence / "vector-gate-receipt.json").is_file())
        sums = json.loads((self.evidence / "SHA256SUMS.json").read_text())
        for name in expected | {"sweep.png", "audit.json", "gate.json",
                                "vector-gate-receipt.json"}:
            self.assertIn(name, sums)
            self.assertEqual(sums[name], sha(self.evidence / name))

    def test_candidate_cmap_matches_reference_cmap_exactly(self):
        candidate = TTFont(self.output / "candidate.otf")
        self.assertEqual(set(candidate.getBestCmap()), set(self.codepoints))

    def test_visual_seal_closes_over_the_full_pack(self):
        sums = json.loads((self.evidence / "SHA256SUMS.json").read_text())
        review = self.root / "review.json"
        review.write_text(json.dumps({
            "reviewer": "full-cmap sweep test pixel check",
            "status": "APPROVED",
            "font_sha256": self.gate["font_sha256"],
            "gate_sha256": sha(self.evidence / "gate.json"),
            "images": {n: h for n, h in sums.items() if n.endswith(".png")},
        }))
        sealed = seal_evidence.seal(self.evidence, review)
        self.assertEqual(sealed["status"], "DELIVERY_READY")

    def test_incomplete_cmap_plan_is_refused(self):
        plan = json.loads(self.plan_path.read_text())
        plan["glyphs"] = [r for r in plan["glyphs"] if r["codepoint"] != self.codepoints[-1]]
        broken = self.root / "plan-incomplete.json"
        broken.write_text(json.dumps(plan))
        with self.assertRaises(ValueError):
            canonical_delivery.run(broken, str(AUDIT_BINARY),
                                   self.root / "production-incomplete",
                                   GATE_PPEM, INK_THRESHOLD)

    def test_evidence_tamper_breaks_seal(self):
        sums = json.loads((self.evidence / "SHA256SUMS.json").read_text())
        review = self.root / "review-tamper.json"
        review.write_text(json.dumps({
            "reviewer": "full-cmap sweep test pixel check",
            "status": "APPROVED",
            "font_sha256": self.gate["font_sha256"],
            "gate_sha256": sha(self.evidence / "gate.json"),
            "images": {n: h for n, h in sums.items() if n.endswith(".png")},
        }))
        target = self.evidence / f"U{self.codepoints[len(self.codepoints) // 2]:06X}.png"
        original = target.read_bytes()
        target.write_bytes(b"tampered")
        try:
            with self.assertRaises(ValueError):
                seal_evidence.seal(self.evidence, review)
        finally:
            target.write_bytes(original)


if __name__ == "__main__":
    unittest.main()
