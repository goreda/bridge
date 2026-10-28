"""Recipe v12 sec. 2-3 pack intake: W4.4 tiles.tsv + pack manifest with the
four REQUIRED producer declarations + split/fold policy artifact. A pack
without all four declarations is REJECTED at intake (typed refusal).
Group rule (sec. 2c): every draw of the same (font, glyph) group lands in
EXACTLY ONE split; enforced here against the pack's split artifact."""
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import torch
from PIL import Image
from torch.utils.data import Dataset

TILES_FIELDS = ["tile_path", "tile_sha256", "family", "style", "codepoint",
                "draw_index", "augmentation_seed", "degradation_draw_kind",
                "source_path", "binary_sha256", "recipe_version", "recipe_sha256"]
REQUIRED_DECLARATIONS = ["polarity", "padding_fill", "crop_threshold", "inversion"]
SPLITS = ("train_inner", "val_inner", "test_outer")


class PackRefusal(Exception):
    """Typed intake refusal; the run never starts on one."""


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


@dataclass(frozen=True)
class PackManifest:
    sha256: str
    polarity: str
    padding_fill: float
    crop_threshold: float
    inversion: bool
    families: tuple


def load_manifest(pack_dir: Path) -> PackManifest:
    p = pack_dir / "pack_manifest.json"
    if not p.exists():
        raise PackRefusal("PackManifestMissing: pack_manifest.json absent")
    raw = p.read_bytes()
    doc = json.loads(raw.decode("utf-8"))
    decl = doc.get("producer_declarations")
    if not isinstance(decl, dict):
        raise PackRefusal("PackDeclarationMissing: producer_declarations block absent")
    missing = [k for k in REQUIRED_DECLARATIONS if k not in decl]
    if missing:
        raise PackRefusal(f"PackDeclarationMissing: {','.join(missing)}")
    if decl["polarity"] not in ("dark_ink_on_light", "light_ink_on_dark"):
        raise PackRefusal("PackDeclarationInvalid: polarity")
    return PackManifest(
        sha256=hashlib.sha256(raw).hexdigest(),
        polarity=decl["polarity"],
        padding_fill=float(decl["padding_fill"]),
        crop_threshold=float(decl["crop_threshold"]),
        inversion=bool(decl["inversion"]),
        families=tuple(sorted(doc.get("families", []))),
    )


def load_rows(pack_dir: Path) -> list:
    p = pack_dir / "tiles.tsv"
    if not p.exists():
        raise PackRefusal("TilesTsvMissing")
    rows = []
    lines = p.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].split("\t") != TILES_FIELDS:
        raise PackRefusal("TilesHeaderMismatch")
    for ln, line in enumerate(lines[1:], start=2):
        fields = line.split("\t")
        if len(fields) != len(TILES_FIELDS):
            raise PackRefusal(f"TilesRowMalformed: line {ln}")
        rows.append(dict(zip(TILES_FIELDS, fields)))
    if not rows:
        raise PackRefusal("TilesEmpty")
    return rows


def group_key(row: dict) -> str:
    """Pack-leakage design v1 canonical key shape: source font-byte sha +
    glyph identity. Face is not a tiles.tsv field; source_path carries it."""
    return f"{row['binary_sha256']}|{row['source_path']}|{row['codepoint']}"


def load_split_map(pack_dir: Path, rows: list) -> dict:
    """The pack's split/fold policy artifact decides the outer scheme
    (recipe sec. 9 reconciliation). Enforce the group rule here."""
    p = pack_dir / "split_map.json"
    if not p.exists():
        raise PackRefusal("SplitArtifactMissing")
    m = json.loads(p.read_text(encoding="utf-8"))
    out = {}
    for row in rows:
        g = group_key(row)
        s = m.get(g)
        if s not in SPLITS:
            raise PackRefusal(f"SplitAssignmentMissing: {g}")
        prev = out.get(g)
        if prev is not None and prev != s:
            raise PackRefusal(f"GroupSplitOverlap: {g}")
        out[g] = s
    return out


def preprocess(img: Image.Image, decl: PackManifest) -> torch.Tensor:
    """Recipe sec. 3: gray -> polarity-normalized (0.0 = ink black,
    1.0 = paper white; declared inversion applied, never assumed) ->
    ink-bbox tight crop at the declared threshold -> height-normalize to
    105 px, aspect preserved, centered on a 105x105 canvas filled with the
    declared padding value; over-wide ink downscaled to fit."""
    g = img.convert("L")
    if decl.inversion:
        g = Image.eval(g, lambda v: 255 - v)
    px = list(g.getdata())
    w0, h0 = g.size
    thresh = int(round(decl.crop_threshold * 255))
    xs = [i % w0 for i, v in enumerate(px) if v < thresh]
    ys = [i // w0 for i, v in enumerate(px) if v < thresh]
    if not xs:
        raise PackRefusal("TileNoInk")
    crop = g.crop((min(xs), min(ys), max(xs) + 1, max(ys) + 1))
    cw, ch = crop.size
    scale = 105.0 / ch
    nw, nh = max(1, round(cw * scale)), 105
    if nw > 105:
        nw, nh = 105, max(1, round(ch * (105.0 / cw)))
    crop = crop.resize((nw, nh), Image.BILINEAR)
    canvas = Image.new("L", (105, 105), int(round(decl.padding_fill * 255)))
    canvas.paste(crop, ((105 - nw) // 2, (105 - nh) // 2))
    buf = canvas.tobytes()
    data = torch.frombuffer(bytearray(buf), dtype=torch.uint8).float().div(255.0)
    return data.view(1, 105, 105)


class PackDataset(Dataset):
    def __init__(self, pack_dir: Path, rows: list, split_map: dict,
                 split: str, decl: PackManifest, class_index: dict):
        self.pack_dir = pack_dir
        self.decl = decl
        self.items = [(r, class_index[r["codepoint"]])
                      for r in rows if split_map[group_key(r)] == split]

    def __len__(self):
        return len(self.items)

    def __getitem__(self, i):
        row, cls = self.items[i]
        tile = self.pack_dir / row["tile_path"]
        if sha256_file(tile) != row["tile_sha256"]:
            raise PackRefusal(f"TileHashMismatch: {row['tile_path']}")
        with Image.open(tile) as img:
            x = preprocess(img, self.decl)
        return x, cls
