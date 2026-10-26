#!/usr/bin/env python3
"""fit_bench workload manifest generator (parallel-fitting program, piece 18).

Builds an engine-accepted full-run manifest for ONE style from its tile
folder. Policy lines (rdp/fit/flatten) are copied from the engine's own
manifest-full-478.tmpl, the scale row is the style's declared K from the
runkit's style-scales.tsv (the same h_ink_units/cap_px values the engine's
declared_convention records pin), the codepoint -> glyph-name map comes from the same template with a
mechanical uniXXXX fallback, and the population pin replicates the engine's
population_pin() rule exactly (sha256 over sorted "cp_hex:name\n" rows).
Nothing is invented: unknowns refuse, they never default silently.

Usage:
  gen_manifest.py --tiledir DIR --style Family/Style --template TMPL \\
                  --scales style-scales.tsv --out MANIFEST [--limit N] [--tile-prefix P]
Stdlib only.
"""
import argparse, hashlib, os, re, sys, unicodedata

TILE = re.compile(r"^(\d+)__([0-9A-Fa-f]+)__([0-9a-f]+)\.(?:png|jpe?g)$")
POLICY_KEYS = ("vendor", "upm", "rdp_epsilon", "fit_tolerance_policy",
               "fit_squared_error", "fit_max_refits", "flatten_tolerance")


def refuse(msg, code=3):
    sys.stderr.write("gen_manifest: REFUSED: " + msg + "\n")
    sys.exit(code)


def frame_slug(style):
    # engine rule (declared_convention::frame_slug): spaces removed, '/'->'-';
    # unicode kept. NOT the CLI --style-id fold.
    return style.replace(" ", "").replace("/", "-")


def ps_slug(style):
    # PostScript-safe fold for postscript_name only.
    return unicodedata.normalize("NFKD", style).encode("ascii", "ignore").decode().replace(" ", "").replace("/", "-")


def png_wh(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] == b"\x89PNG\r\n\x1a\n":
        return int.from_bytes(head[16:20], "big"), int.from_bytes(head[20:24], "big")
    return None, None


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--tiledir", required=True)
    p.add_argument("--style", required=True, help="Family/Style")
    p.add_argument("--template", required=True)
    p.add_argument("--scales", required=True, help="style-scales.tsv: the declared per-style K (h_ink_units/cap_px in the engine declared_convention records)")
    p.add_argument("--out", required=True)
    p.add_argument("--limit", type=int, default=None)
    p.add_argument("--tile-prefix", default=None,
                   help="emit glyph rows against this path instead of the tiledir abspath "
                        "(use a whitespace-free symlink: the manifest grammar splits on whitespace)")
    a = p.parse_args()

    family, sep, sub = a.style.partition("/")
    if not sep or not family or not sub:
        refuse("BadStyleLabel: --style must be exactly Family/Style")

    # scale: the style's declared K (engine: declared_convention h_ink_units /
    # cap_px; the runkit's style-scales.tsv carries the same declared values).
    scale = None
    for line in open(a.scales, encoding="utf-8"):
        parts = line.rstrip("\n").split("\t")
        if parts and parts[0] == a.style:
            scale = parts[1]
            break
    if scale is None:
        refuse("StyleScaleMissing: no row for %r in %s" % (a.style, a.scales))
    float(scale)  # malformed row refuses here, never reaches the manifest

    # policy lines + cp -> name map from the engine's own template
    policy, names = {}, {}
    for line in open(a.template, encoding="utf-8"):
        parts = line.split()
        if not parts or parts[0].startswith("#"):
            continue
        if parts[0] in POLICY_KEYS:
            policy[parts[0]] = " ".join(parts[1:])
        elif parts[0] == "glyph" and len(parts) >= 3:
            names[int(parts[1], 16)] = parts[2]
    missing = [k for k in POLICY_KEYS if k not in policy]
    if missing:
        refuse("TemplatePolicyMissing: " + ",".join(missing))

    rows, excluded = {}, 0
    for fn in sorted(os.listdir(a.tiledir)):
        t = TILE.match(fn)
        if not t:
            excluded += 1
            continue
        cp = int(t.group(2), 16)
        if cp in rows:
            refuse("DuplicateCodepoint: " + hex(cp))
        rows[cp] = fn
    if len(rows) < 2:
        refuse("too few usable single-codepoint tiles: %d" % len(rows))
    cps = sorted(rows)
    if a.limit:
        keep = set(cps[: a.limit])
        if 0x48 in rows:
            keep.add(0x48)  # H row: declared-convention binding refuses without it
        cps = [cp for cp in cps if cp in keep]
    if 0x48 in cps:
        frame_tile = rows[0x48]
    else:
        frame_tile = rows[cps[0]]
    w, h = png_wh(os.path.join(a.tiledir, frame_tile))
    if not w:
        refuse("FrameUnreadable: cannot read PNG size of " + frame_tile)
    with open(os.path.join(a.tiledir, frame_tile), "rb") as f:
        pin = hashlib.sha256(f.read()).hexdigest()
    frame = "%s:%dx%d:H-sha256:%s" % (frame_slug(a.style), w, h, pin)

    gnames = {cp: names.get(cp, "uni%04X" % cp) for cp in cps}
    pop = hashlib.sha256("".join(sorted("%x:%s\n" % (cp, gnames[cp]) for cp in cps)).encode()).hexdigest()
    n = len(cps)
    out = [
        "# fit_bench workload manifest: generated by tooling/fit_bench/gen_manifest.py",
        "#@style_id %s" % a.style,
        "#@glyphs %d (single-codepoint tiles of %s; %d non-tile/sequence entries excluded)" % (n, a.tiledir, excluded),
        "run_mode full",
        "population_sha256 %s" % pop,
        "family %s" % family,
        "subfamily %s" % sub,
        "postscript_name %s-%s" % (ps_slug(family), ps_slug(sub)),
        "capture_cohort %s" % a.style,
        "capture_frame %s" % frame,
        "scale %s" % scale,
    ]
    out += ["%s %s" % (k, policy[k]) for k in POLICY_KEYS]
    out.append("max_pairs %d" % (n * (n - 1)))
    tile_base = a.tile_prefix if a.tile_prefix is not None else os.path.abspath(a.tiledir)
    if any(c.isspace() for c in tile_base):
        refuse("WhitespaceInTilePath: glyph rows split on whitespace; pass --tile-prefix with a space-free path")
    out += ["glyph 0x%04X %s %s" % (cp, gnames[cp], os.path.join(tile_base, rows[cp])) for cp in cps]
    with open(a.out, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    sys.stderr.write("gen_manifest: style=%s glyphs=%d scale=%s pin=%s\n" % (a.style, n, scale, pop[:12]))


if __name__ == "__main__":
    main()
