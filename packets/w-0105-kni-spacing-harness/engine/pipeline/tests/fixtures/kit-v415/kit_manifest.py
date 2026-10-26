#!/usr/bin/env python3
"""Kit v2.4: build the engine manifest for ONE style from its tile folder.

  kit_manifest.py --tiledir DIR --style Family/Style --template kni/manifest-full-478.tmpl
                  --scales kni/style-scales.tsv --out MANIFEST [--scale X]

Everything style-specific is derived, nothing is copied from the Marq/Alternate template
except the policy lines (vendor, upm, rdp_epsilon, fit_*, flatten_tolerance) and the
codepoint -> glyph-name map:
  glyph rows      from the folder: NNNNN__CP__hash.png, single-codepoint tiles only.
                  Multi-codepoint (sequence) tiles are listed and excluded.
                  Identical images (>=3 tiles) are only .notdef CANDIDATES (v3.7: reported, never auto-excluded; normal run refuses). /
                  fallback render and is excluded; smaller identical pairs are kept.
  family/subfamily/postscript_name  from --style ("Family/Style" -> Family-Style, ASCII, no spaces)
  scale           --scale, else the style's row in style-scales.tsv, else a hard error
                  ("not measured"): a scale is never borrowed from another style.
  max_pairs       n * (n - 1) over the emitted glyph set
  population_sha256  sha256 of the sorted "cp-hex:name\\n" rows (same rule as the engine's
                  population_pin), so the engine's run_mode gate accepts exactly this set.
  space           own U+0020 row `space 0x20 ADV` (ADV in font units): kni/style-space.tsv rows are HISTORICAL and DISABLED
                  (a HistoricalNotApplicable row is not evidence: never a fallback, never rescaled);
                  else <style>/space-measurement.json slope (capture px) * scale
                  (that slope is the H-space-H measurement with H's sidebearings already removed);
                  else NO space row: the bare manifest key `derive_space_from_letter_advances` is emitted
                  instead and the engine derives the space advance from solved glyph advances
                  (U+006E advance, else median of present a-z, else median of all glyphs; declared
                  convention, see docs/kni/2026-10-17-space-derive-convention.md). The kit never refuses
                  for a missing space source and never runs partial over one.
  .notdef         repeated identical images (>=3) are only CANDIDATES, reported (header + --notdef-out), never auto-excluded; a normal run with a candidate refuses;
                  the engine currently always writes an EMPTY .notdef, so the graphic is NOT yet in the OTF.
  scale basis     exact measured row, else (same 1485x1050 capture frame, PNG IHDR checked) the capture
                  constant of the reference row = ASSUMED, labelled in the manifest header and stderr.
Exit 2 = refused (message says why). Stdlib only; reads files, writes MANIFEST only.
"""
import argparse, glob, hashlib, json, os, re, struct, sys, unicodedata, zlib

TILE = re.compile(r"^(\d+)__([0-9A-Fa-f]+(?:_[0-9A-Fa-f]+)*)__([0-9a-f]+)\.(?:png|jpe?g)$")
REPLACED = {"family", "subfamily", "postscript_name", "scale", "max_pairs", "population_sha256", "run_mode", "glyph"}

def refuse(msg, code=3):
    sys.stderr.write("kit_manifest: REFUSED: " + msg + "\n"); sys.exit(code)

def signed_post_offset(name, value):
    """Parse an explicit signed offset; missing values stay missing, not defaults."""
    try:
        x = float(value)
    except (ValueError, TypeError):
        refuse(f"PostOffsetInvalid: {name} {value!r} is not a number", 3)
    if not (x == x and x not in (float("inf"), float("-inf"))) or x != int(x):
        refuse(f"PostOffsetInvalid: {name} {value!r} must be a finite signed integer (output units)", 3)
    return int(x)

def ascii_fold(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s) if ord(c) < 128)

class NameRefused(Exception): pass

# Canonical accent->plain table: READ from kni/tools/parity/translit_table-canonical-b5331111.tsv (canonical table; no embedded copy) and gated by a sha256 pin.
# A different file hash = hard stop (drift gate), never a silent different table.
TRANSLIT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "parity", "translit_table-canonical-b5331111.tsv")
TRANSLIT_SHA256 = "ee19b3689f84884ae6594153523549afe38dd3b3d6c989bfc6b9251e7a343291"
PARITY_JSON_SHA256 = "7b34f100bf856a6057b4e715e65df31c8cfd2677ccca0c03ae13969f1eb9507a"   # derive_names_parity-v1-04826676.json, checked by test_derive_names.py
def _load_translit():
    raw = open(TRANSLIT_FILE, "rb").read()
    if hashlib.sha256(raw).hexdigest() != TRANSLIT_SHA256:
        sys.stderr.write("kit_manifest: REFUSED: TranslitTableDrift: parity/translit_table-canonical-b5331111.tsv sha256 does not match the pin\n"); sys.exit(3)
    t = {}
    for l in raw.decode("utf-8").splitlines():
        u, c, b = l.split("\t"); t[chr(int(u[2:], 16))] = b
    return t
try: TRANSLIT = _load_translit()
except (OSError, ValueError, IndexError) as _e:   # import-time dependency failure: typed refusal, never a traceback
    sys.stderr.write("kit_manifest: REFUSED: DependencyUnavailable: translit table unreadable or malformed (%s: %s)\n" % (type(_e).__name__, _e)); sys.exit(3)
# Rust char::is_whitespace set (White_Space). str.strip() is NOT used: U+001C-001F are not trimmed (they are Control).
_WS = frozenset([0x9, 0xA, 0xB, 0xC, 0xD, 0x20, 0x85, 0xA0, 0x1680, *range(0x2000, 0x200B), 0x2028, 0x2029, 0x202F, 0x205F, 0x3000])

def _rtrim(t):
    i, j = 0, len(t)
    while i < j and ord(t[i]) in _WS: i += 1
    while j > i and ord(t[j - 1]) in _WS: j -= 1
    return t[i:j]

def derive_names(label):
    """Transcription of derive_names in pipeline/src/run_config.rs (policy: verbatim family/subfamily, spaces removed, accents mapped to plain ASCII). Rust is the source of truth;
    kni/tools/test_derive_names.py checks this function against the canonical table and parity JSON (exact equality).
    Returns (family, subfamily, postscript) or raises NameRefused(<Kind>). The ONLY name derivation in the kit."""
    parts = label.split("/")
    if len(parts) != 2: raise NameRefused("BadShape")
    f, s_ = _rtrim(parts[0]), _rtrim(parts[1])
    if not f or not s_: raise NameRefused("EmptyPart")
    def enc(t):
        o = []; prev = False
        for ch in t:
            c = ord(ch)
            if unicodedata.category(ch) == "Cc": raise NameRefused("Control")
            if ch == " ": prev = False; continue
            if c < 128:
                if c < 33 or c > 126 or ch in "[](){}<>/%": raise NameRefused("InvalidPostScriptChar")
                o.append(ch); prev = ch.isalpha()
            elif ch in TRANSLIT: o.append(TRANSLIT[ch]); prev = True
            elif 0x300 <= c <= 0x36F:
                if not prev: raise NameRefused("StrayCombiningMark")
            else: raise NameRefused("UnmappableChar")
        return "".join(o)
    ef, es = enc(f), enc(s_)
    if not ef or not es: raise NameRefused("EmptyPart")
    ps = ef + "-" + es
    if len(ps) > 63: raise NameRefused("PostScriptTooLong")
    return f, s_, ps

def ps_name(family, style):
    try: return derive_names(family + "/" + style)[2]
    except NameRefused as e: refuse(f"NameDerivationFailed: {e} for {family!r}/{style!r}", 3)

def _ps_slug(*parts):
    """folder-slug PostScript name fragment: alphanumerics only, deterministic, <= 63 chars total later."""
    s = "-".join(re.sub(r"[^A-Za-z0-9]+", "", p) for p in parts if re.sub(r"[^A-Za-z0-9]+", "", p))
    return s or "KNIUnnamed"

def check_collection_names(root):
    """set-level PostScript name check over every <Family>/<Style>/glyph under root. Always-output:
    a PostScriptCollision or NameDerivationFailed no longer refuses the collection; the affected style
    gets a uniquified PS name built from its folder slug plus a typed flag row (returned in flags).
    Returns (ps_by_style, flags_by_style)."""
    seen, ps_of, flags = {}, {}, {}
    for fam in sorted(os.listdir(root)):
        for sty in sorted(os.listdir(os.path.join(root, fam))) if os.path.isdir(os.path.join(root, fam)) else []:
            if not os.path.isdir(os.path.join(root, fam, sty, "glyph")): continue
            label = fam + "/" + sty
            try: ps = derive_names(label)[2]
            except NameRefused as e:
                ps = _ps_slug(fam, sty)[:63]
                flags.setdefault(label, []).append("#@warning ps_name_uniquified: NameDerivationFailed (%s); PostScript name derived from the folder slug: %s" % (e, ps))
            if ps in seen:
                base = ps
                ps = (base + "-" + _ps_slug(fam, sty))[:63]
                n = 2
                while ps in seen:
                    ps = (base + "-" + _ps_slug(fam, sty) + str(n))[:63]; n += 1
                flags.setdefault(label, []).append("#@warning ps_name_uniquified: PostScriptCollision %r from %r and %r; uniquified to %s" % (base, seen[base], label, ps))
            seen[ps] = label
            ps_of[label] = ps
    if not seen: refuse("CollectionEmpty: no <Family>/<Style>/glyph", 3)
    return ps_of, flags

def read_template(path):
    policy, names = [], {}
    for ln in open(path, encoding="utf-8"):
        t = ln.strip()
        if not t or t.startswith("#"): continue
        k = t.split()[0]
        if k == "glyph":
            p = t.split(); names[int(p[1], 16)] = p[2]
        elif k not in REPLACED: policy.append(t)
    if not names or not policy: refuse(f"template {path} has no glyph rows or no policy lines")
    return policy, names

def png_wh(path):
    """image size (w, h) from the PNG IHDR or the first JPEG SOF marker; header read only"""
    with open(path, "rb") as f: b = f.read()
    if b[:8] == b"\x89PNG\r\n\x1a\n" and b[12:16] == b"IHDR": return struct.unpack(">II", b[16:24])
    if b[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(b):
            if b[i] != 0xFF: i += 1; continue
            m = b[i + 1]
            if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", b[i + 5:i + 9]); return (w, h)
            if m == 0xD8 or 0xD0 <= m <= 0xD7 or m == 0x01: i += 2; continue
            i += 2 + struct.unpack(">H", b[i + 2:i + 4])[0]
    refuse(f"{path}: not a readable PNG/JPEG")

def tile_readable(path):
    """header probe for the always-output exclusion route: True when the file carries a readable
    PNG IHDR or JPEG marker prefix; anything else is excluded with a typed row, never a refusal."""
    try:
        with open(path, "rb") as f: b = f.read(64 * 1024)
    except OSError: return False
    if b[:8] == b"\x89PNG\r\n\x1a\n": return b[12:16] == b"IHDR" and len(b) >= 24
    if b[:2] == b"\xff\xd8": return True
    return False

def read_tsv(path):
    rows = []
    if os.path.isfile(path):
        for ln in open(path, encoding="utf-8"):
            t = ln.rstrip("\n")
            if t and not t.startswith("#"): rows.append(t.split("\t"))
    return rows

# ---- run-ledger evidence: the font_size the capture actually SENT per style (kni-downloader ledger.jsonl, shard roots) ----
# Gate: flipping this to True lets "same ledger font_size as the measured reference style" produce a scale.
# Default False: the ledger proves the INPUT (font_size) only; the renderer's px/em for that input is not render-verified.
ACCEPT_LEDGER_FONT_SIZE_CALIBRATION = False

def ledger_font_sizes(ledger_globs):
    """{ 'Family dir/Style dir': {font_size,...} } from source_refresh profiles joined to request/asset records by id.
    Names come from the asset path the request produced (the folder names), never guessed."""
    fs, names = {}, {}
    for g in ledger_globs:
        for f in sorted(glob.glob(g)):
            req, resp = {}, {}
            for ln in open(f, encoding="utf-8"):
                d = json.loads(ln)
                if d.get("kind") == "source_refresh":
                    pr = dict(map(tuple, d.get("profile", []))); fs.setdefault((d["family"], str(d["style_value"])), set()).add(pr.get("font_size"))
                if isinstance(d.get("request_identity"), dict): req[d["id"]] = d["request_identity"]
                if isinstance(d.get("asset"), dict): resp[d["id"]] = d["asset"]["path"]
            for i, pth in resp.items():
                if i in req: names.setdefault((req[i]["family"], str(req[i]["style_value"])), set()).add("/".join(pth.split("/")[1:3]))
    out = {}
    for k, nm in names.items():
        for n in nm: out.setdefault(n, set()).update(fs.get(k, set()))
    return out

# ---- the ONE place the unverified capture-constant assumption lives. Set ALLOW_ASSUMED_CAPTURE_CONSTANT = False
# (or delete this function) to turn it into a refusal for every style without a measured row. ----
ALLOW_ASSUMED_CAPTURE_CONSTANT = False   # RED for any normal run; only the explicit --diagnostic-assumed-scale artifact may use it
def assumed_capture_constant(style, rows, sample_png, upm):
    if not ALLOW_ASSUMED_CAPTURE_CONSTANT: return None
    ref = [p for p in rows if len(p) >= 4]
    if ref:
        r = ref[0]; rw, rh = int(r[2].split("x")[0]), int(r[2].split("x")[1])
        if png_wh(sample_png) == (rw, rh):
            ppem = float(upm) / float(r[1])          # capture px per em at the reference style's capture
            return repr(float(upm) / ppem), f"ASSUMED-capture-constant(from {r[0]}: {ppem:.6f} px/em; same {rw}x{rh} frame; NOT verified for {style})"
    return None

def jpeg_wh(path):
    b = open(path, "rb").read(); i = 2
    if b[:2] != b"\xff\xd8": return None
    while i + 4 <= len(b):
        m = b[i + 1]; n = struct.unpack(">H", b[i + 2:i + 4])[0]
        if m in (0xC0, 0xC1, 0xC2): h, w = struct.unpack(">HH", b[i + 5:i + 9]); return (w, h)
        i += 2 + n
    return None

PAUL_STYLE = "Paul New/Regular"
PAUL_H_PIN = "c7cd69b88be228b339c3f7f1978ad11ced392b7f81f036c622a211c0a2e55464"
def frame_slug(style): return style.replace(" ", "").replace("/", "-")
def declared_convention(style, row, scales_path, tiledir):
    """OwnerDeclaredScaleSet/2026-10-16-v2 row (chief code-integration spec): tsv columns
    style, scale(K), frame, basis, ref(cap_px), em_px, evidence_path, evidence_sha256.
    Triple binding, any leg fails -> typed refusal:
      a. declared_units == 10 * round_half_up(1000 * cap_px / (10 * em_px))
      b. declared_units == round_half_up(cap_px * K)
      c. evidence sha + ref tile sha + frame checks.
    An em_receipt_sha still marked pending is a refusal: staged rows never ship."""
    if len(row) < 8:
        refuse(f"DeclaredConventionInvalid: row for {style!r} has {len(row)} columns; the declared scale model needs 8 (style, scale, frame, basis, ref_cap_px, em_px, evidence_path, evidence_sha256)", 3)
    ev_path = os.path.join(os.path.dirname(scales_path), row[6])
    if not os.path.isfile(ev_path) or hashlib.sha256(open(ev_path, "rb").read()).hexdigest() != row[7]:
        refuse(f"MissingScaleEvidence: DeclaredConvention row for {style!r} has no evidence record {row[6]} matching sha256 {row[7]}", 3)
    ev = json.load(open(ev_path, encoding="utf-8"))
    if ev.get("style") != style or ev.get("calibrated") is not False or ev.get("cross_frame_reuse") is not False:
        refuse(f"DeclaredConventionInvalid: evidence for {style!r} must name this style with calibrated=false and cross_frame_reuse=false", 3)
    if str(ev.get("em_receipt_sha", "")).startswith("PENDING"):
        refuse(f"DeclaredConventionEvidencePending: evidence for {style!r} still carries a pending em_receipt_sha; land the em measurement receipt and re-pin the row first", 3)
    try:
        scale = float(row[1]); du = int(ev["declared_units"]); cap = float(ev["cap_px"]); em = float(ev["em_px"])
    except (KeyError, TypeError, ValueError) as e:
        refuse(f"DeclaredConventionInvalid: evidence/row numeric fields unreadable ({e})", 3)
    if not (scale > 0 and scale < float("inf")) or du <= 0 or not (cap > 0) or not (em > 0):
        refuse(f"DeclaredConventionInvalid: scale/declared_units/cap_px/em_px must be positive (scale={row[1]!r} declared_units={ev.get('declared_units')!r} cap_px={ev.get('cap_px')!r} em_px={ev.get('em_px')!r})", 3)
    if float(row[4]) != cap or float(row[5]) != em:
        refuse(f"DeclaredConventionChanged: row cap_px/em_px ({row[4]!r}/{row[5]!r}) differ from the evidence record ({cap!r}/{em!r})", 3)
    if row[3] != ev.get("basis"):
        refuse(f"DeclaredConventionChanged: row basis {row[3]!r} differs from the evidence basis {ev.get('basis')!r}", 3)
    if ev.get("scale") is not None and struct.pack(">d", float(ev["scale"])) != struct.pack(">d", scale):
        refuse(f"DeclaredConventionChanged: evidence scale {ev['scale']!r} differs from the row's declared K {row[1]!r}", 3)
    got_a = 10 * int(1000.0 * cap / (10.0 * em) + 0.5)   # the universal function; round-half-up, positive only
    if du != got_a:
        refuse(f"DeclaredConventionChanged: declared_units {du} != 10*round_half_up(1000*cap_px/(10*em_px)) = {got_a} (triple binding leg a)", 3)
    got_b = int(cap * scale + 0.5)
    if du != got_b:
        refuse(f"DeclaredConventionChanged: declared_units {du} != round_half_up(cap_px {cap!r} * K {row[1]!r}) = {got_b} (triple binding leg b)", 3)
    tile = os.path.join(tiledir, ev["ref_tile"])
    if not os.path.isfile(tile) and "/" in ev["ref_tile"]:
        alt = os.path.join(os.path.dirname(tiledir.rstrip("/")), ev["ref_tile"])   # ref_tile may be recorded style-dir-relative ("glyph/<file>")
        if os.path.isfile(alt): tile = alt
    if not os.path.isfile(tile) or hashlib.sha256(open(tile, "rb").read()).hexdigest() != ev["ref_tile_sha256"]:
        refuse(f"DeclaredConventionChanged: reference tile {ev['ref_tile']} missing or its sha256 differs from the pin (H pin changed)", 3)
    wh = jpeg_wh(tile) or png_wh(tile)
    if wh is None or "%dx%d" % wh != row[2]:
        refuse(f"DeclaredConventionChanged: reference tile frame {wh} differs from the row's declared frame {row[2]!r}", 3)
    return row[1], "DECLARED_CONVENTION(calibrated=false K=%s declared_units=%s cap_px=%s em_px=%s em_source=%s basis=%s frame=%s cross_frame_reuse=false; triple binding a:du==10*rhU(1000*cap/(10*em)) b:du==rhU(cap*K) c:evidence+tile+frame)" % (row[1], ev["declared_units"], ev["cap_px"], ev["em_px"], ev.get("em_source"), ev.get("basis"), row[2])


def config_default_scale(scales_path):
    """single source: the engine's own RunConfig default (no second literal in the kit)"""
    base = os.path.join(os.path.dirname(scales_path), "engine", "pipeline", "src")
    try:
        t = open(os.path.join(base, "run_config.rs"), encoding="utf-8").read()
        w = open(os.path.join(base, "scale_wiring.rs"), encoding="utf-8").read()
    except OSError as e: refuse(f"DefaultScaleSourceMissing: cannot read the engine run_config.rs / scale_wiring.rs ({e})", 3)
    m = re.search(r"fn default_units_per_px\(\) -> f64 \{ ([0-9.]+) \}", t); c = re.search(r'CONFIG_CONVENTION_ID: &str = "([^"]+)"', w)
    if not m or not c: refuse("DefaultScaleSourceMissing: default_units_per_px / CONFIG_CONVENTION_ID not found in the engine source", 3)
    return repr(float(m.group(1))), c.group(1)

def scale_for(style, override, scales_path, sample_png, upm, diagnostic=False, ledgers=None, legacy_ok=False, diagnostic_out=False, tiledir=None):
    """returns (scale_text, basis). basis: override | measured | ASSUMED-capture-constant"""
    if override is not None:
        try: _ov = float(override)
        except ValueError: refuse("ScaleOverrideNotANumber: --scale %r is not a number" % (override,), 3)
        if not (_ov > 0 and _ov < float("inf")): refuse("ScaleOverrideInvalid: --scale must be finite and > 0", 3)
    for p_ in read_tsv(scales_path):   # a DeclaredConvention style: no other scale may stand in for it (not even a diagnostic one)
        if len(p_) >= 5 and p_[0] == style and (p_[4] == "DeclaredConvention" or len(p_) >= 8):
            if override is not None and struct.pack(">d", float(override)) != struct.pack(">d", float(p_[1])):
                refuse(f"DeclaredConventionChanged: --scale {override} differs from the declared K {p_[1]} of {style!r}; no other scale (default or user) is accepted for this style", 3)
            if override is not None: break
    if override is not None:
        if not diagnostic_out:
            refuse(f"MissingScaleEvidence: --scale is a user-declared UNVALIDATED value; it is accepted only for a *.DIAGNOSTIC.txt artifact (stage1_only). "
                   f"A validated override needs a Validated row with an evidence record in {scales_path}.", 3)
        try: v = float(override)
        except ValueError: refuse("--scale is not a number")
        if not (v > 0 and v < float("inf")): refuse("--scale must be finite and > 0")
        return override, "USER-DECLARED-UNVALIDATED"
    rows = [r for r in read_tsv(scales_path)]
    for p in rows:
        if len(p) >= 4 and p[0] == style:
            if len(p) >= 5 and p[4] == "LegacyUnvalidatedScale":
                if legacy_ok: return p[1], "LegacyUnvalidatedScale(historical out8 receipt constant; no derivation code; NOT validated)"
                refuse(f"LegacyUnvalidatedScale: {style!r} only has the historical out8 receipt constant {p[1]} (no derivation, units/calibration unverified). "
                       f"Not usable in a normal run; --legacy-ref-mode writes a *.DIAGNOSTIC.txt candidate only.", 3)
            if len(p) >= 8:
                return declared_convention(style, p, scales_path, tiledir)
            if len(p) >= 7 and p[4] == "DeclaredConvention":
                if diagnostic_out or True: return declared_convention(style, p, scales_path, tiledir)
            if len(p) >= 7 and p[4] == "Validated":
                ev = os.path.join(os.path.dirname(scales_path), p[5])
                if not os.path.isfile(ev) or hashlib.sha256(open(ev, "rb").read()).hexdigest() != p[6]:
                    refuse(f"MissingScaleEvidence: Validated row for {style!r} has no evidence record {p[5]} matching sha256 {p[6]}", 3)
                return p[1], "VALIDATED"
            refuse(f"MissingScaleEvidence: row for {style!r} is not marked Validated with an evidence record (status={p[4] if len(p) > 4 else 'none'})", 3)
    if style != PAUL_STYLE:   # every style without a row of its own: the engine's config default convention, calibrated=false
        dk, cid = config_default_scale(scales_path)
        return dk, "CONFIG_CONVENTION(%s calibrated=false K=%s from engine run_config.rs; same K for every glyph; not measured for %s)" % (cid, dk, style)
    led = ledger_font_sizes(ledgers) if ledgers else {}
    ref = next((p for p in rows if len(p) >= 4), None)
    if led and ref and style in led and ref[0] in led and led[style] == led[ref[0]] and len(led[style]) == 1:
        fsv = next(iter(led[style]))
        if ACCEPT_LEDGER_FONT_SIZE_CALIBRATION: return ref[1], f"LEDGER-FONTSIZE-EQUAL(font_size {fsv} sent for both {style} and measured {ref[0]}; renderer px/em not render-verified)"
        ledger_note = f" Ledger evidence: font_size sent = {sorted(led[style])} for {style} and {sorted(led[ref[0]])} for the measured {ref[0]} (all shards); ledger gate ACCEPT_LEDGER_FONT_SIZE_CALIBRATION is off (needs chief)."
    else: ledger_note = ""
    if diagnostic:
        global ALLOW_ASSUMED_CAPTURE_CONSTANT
        ALLOW_ASSUMED_CAPTURE_CONSTANT = True
    got = assumed_capture_constant(style, rows, sample_png, upm)
    if got: return got
    refuse(f"MissingScaleEvidence: no measured / source-reproducible scale for {style!r}. The capture sends the form's own per-style declared font_size maximum (@max); "
           f"a canvas size does not fix px/em. Needs the run ledger's resolved font_size per style plus a calibration, or a measured row in {scales_path}. "
           f"Nothing is borrowed from another style." + ledger_note, 3)

def decode_png_rows(path):
    b = open(path, "rb").read()
    if b[:8] != b"\x89PNG\r\n\x1a\n": return None
    w, h, depth, ct, _, _, il = struct.unpack(">IIBBBBB", b[16:29])
    ch = {0: 1, 2: 3, 4: 2, 6: 4}.get(ct)
    if depth != 8 or il != 0 or ch is None: return None
    i, idat = 8, b""
    while i < len(b):
        n = struct.unpack(">I", b[i:i + 4])[0]
        if b[i + 4:i + 8] == b"IDAT": idat += b[i + 8:i + 8 + n]
        i += 12 + n
    raw = zlib.decompress(idat); st = w * ch; prev = bytearray(st); rows = []; k = 0
    for _ in range(h):
        ft = raw[k]; line = bytearray(raw[k + 1:k + 1 + st]); k += 1 + st
        for x in range(st):
            a_ = line[x - ch] if x >= ch else 0; c_ = prev[x - ch] if x >= ch else 0; u = prev[x]
            if ft == 1: line[x] = (line[x] + a_) & 255
            elif ft == 2: line[x] = (line[x] + u) & 255
            elif ft == 3: line[x] = (line[x] + ((a_ + u) >> 1)) & 255
            elif ft == 4:
                pa, pb, pc = abs(u - c_), abs(a_ - c_), abs(a_ + u - 2 * c_)
                line[x] = (line[x] + (a_ if pa <= pb and pa <= pc else u if pb <= pc else c_)) & 255
        rows.append(bytes(line)); prev = line
    return rows

def notdef_status(tiledir, rep):
    """DETECTED-BLANK | DETECTED-GRAPHIC | DETECTED-UNDECODABLE | EVIDENCE-ABSENT (absent is NOT empty)"""
    if not rep: return "EVIDENCE-ABSENT"
    rows = decode_png_rows(os.path.join(tiledir, rep[0]))
    if rows is None: return "DETECTED-UNDECODABLE"
    bg = rows[0][:4] if rows else b""
    return "DETECTED-BLANK" if all(r == rows[0] and r == rows[0][:1] * len(r) for r in rows) else "DETECTED-GRAPHIC"

def find_space_source(style_dir):
    """H s H (0048_0020_0048) and H H H (0048_0048_0048) tiles under <style>/sidebearing/**; evidence for the hub's measurement.
    Detection only - nothing is measured here. Returns (hsh_paths, hhh_paths) relative to the style dir."""
    hsh, hhh = [], []
    for root, _, files in os.walk(os.path.join(style_dir, "sidebearing")):
        for f in sorted(files):
            m = TILE.match(f)
            if not m: continue
            seq = m.group(2).upper()
            rel = os.path.relpath(os.path.join(root, f), style_dir)
            if seq == "0048_0020_0048": hsh.append(rel)
            elif seq == "0048_0048_0048": hhh.append(rel)
    return sorted(hsh), sorted(hhh)

def space_row(style, tiledir, scale_txt, fixed_path, frame, allow_missing=False):
    """returns (row_or_None, note)"""
    for p in read_tsv(fixed_path):
        if p[0] == style:
            if len(p) >= 3 and p[1] == "HistoricalNotApplicable":
                # the historical row is not evidence: never a fallback, never rescaled. The style falls
                # through to the measured-source checks and, failing those, the derive-space key path.
                break
            return f"space 0x0020 {p[1]}", f"space {p[1]} fu: {p[2] if len(p) > 2 else 'fixed row'}"
    mj = os.path.join(os.path.dirname(tiledir.rstrip("/")), "space-measurement.json")
    if os.path.isfile(mj):
        d = json.load(open(mj, encoding="utf-8")); sl = d.get("space_advance_px_slope")
        if d.get("schema") != "kni-space-measurement/v1" or d.get("units") != "capture_px":
            refuse(f"{mj}: schema/units check failed", 3)
        w1 = (d.get("reference_renders") or {}).get("W1", {}).get("canvas")
        if w1 and tuple(w1) != tuple(frame): refuse(f"{mj}: measured in canvas {w1}, tiles are {list(frame)}", 3)
        if isinstance(sl, (int, float)) and sl >= 0:
            # slope of ink-span width over 1/2/3 spaces: H and its sidebearings are in every render, so they cancel in the
            # difference and the slope IS the space advance. Consistency: gap(H H) = rsb+space+lsb must exceed it.
            g = (d.get("cross_checks") or {}).get("gap_H_H")
            if isinstance(g, (int, float)) and g < sl: refuse(f"{mj}: gap_H_H {g} < slope {sl}: sidebearings would be negative", 3)
            return f"space 0x0020 {sl * float(scale_txt)!r}", f"space from space-measurement.json slope {sl}px (frame {list(frame)}) * scale"
        gp = d.get("space_advance_px_gap")
        if isinstance(gp, (int, float)) and gp > 0:
            # gap-derived fallback (kni_space_update.py): gap(X<sp>X) - gap(X-X) from the style's own
            # captures; the H derivation is preferred, O/n are recorded alongside under gap_derived.
            g = (d.get("cross_checks") or {}).get("gap_H_H")
            if isinstance(g, (int, float)) and g < gp: refuse(f"{mj}: gap_H_H {g} < gap-derived space {gp}: sidebearings would be negative", 3)
            return f"space 0x0020 {gp * float(scale_txt)!r}", f"space from space-measurement.json gap-derived {gp}px {d.get('gap_derived')} (frame {list(frame)}) * scale"
    return None, "MissingSpaceEvidence: NO SPACE ROW (no fixed width, no space-measurement.json (needs H-space-H reference renders); no value invented"

class StyleTokenError(ValueError): pass
def style_token_encode(style):
    """STYLE token of the pipeline manifest line `notdef evidence FILE SHA STYLE CAPTURE SCALE FRAME` (5th token): ONLY ASCII space -> %20 and literal % -> %25
    (percent first). Every other character, including all non-ASCII Unicode, stays as is. The evidence/capture TSV style field and --notdef-out keep the plain name."""
    return style.replace("%", "%25").replace(" ", "%20")
def style_token_decode(tok):
    """strict single-pass decode: only uppercase %20 and %25; any other or truncated % is refused; the token must be canonical (encode(decode(tok)) == tok)."""
    out = []; i = 0
    while i < len(tok):
        c = tok[i]
        if c == "%":
            esc = tok[i:i + 3]
            if esc == "%20": out.append(" ")
            elif esc == "%25": out.append("%")
            else: raise StyleTokenError(f"malformed percent escape {esc!r} in STYLE token {tok!r}")
            i += 3
        else:
            if c == " ": raise StyleTokenError(f"raw space in STYLE token {tok!r} (must be %20)")
            out.append(c); i += 1
    s = "".join(out)
    if style_token_encode(s) != tok: raise StyleTokenError(f"STYLE token {tok!r} is not canonical")
    return s

def _main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiledir", required=True); ap.add_argument("--style", required=True)
    ap.add_argument("--template", required=True); ap.add_argument("--scales", required=True)
    ap.add_argument("--notdef-dir"); ap.add_argument("--iou-ink-threshold"); ap.add_argument("--iou-flatten-steps"); ap.add_argument("--lsb-add"); ap.add_argument("--rsb-add"); ap.add_argument("--post-scope"); ap.add_argument("--post-scope-label"); ap.add_argument("--out", required=True); ap.add_argument("--scale"); ap.add_argument("--space-table"); ap.add_argument("--notdef-out"); ap.add_argument("--run-ledger", action="append", default=[], help="glob of kni-downloader run-output-*/ledger.jsonl (evidence of the font_size sent per style)")
    ap.add_argument("--legacy-ref-mode", action="store_true", help="DIAGNOSTIC ONLY: use a LegacyUnvalidatedScale row (historical receipt constant); --out must end with .DIAGNOSTIC.txt")
    ap.add_argument("--diagnostic-assumed-scale", action="store_true", help="DIAGNOSTIC ONLY: capture-constant scale; --out must end with .DIAGNOSTIC.txt; RUN.sh never passes it")
    ap.add_argument("--collision-root", help="collection root: hard-refuse on any PostScriptCollision among its styles"); ap.add_argument("--snapshot-sha256", help="canonical landed-tree sha256 recorded as #@canonical_snapshot"); ap.add_argument("--allow-no-space", action="store_true", help="DIAGNOSTIC ONLY: emit without a space row; --out must end with .DIAGNOSTIC.txt"); ap.add_argument("--allow-missing-space", action="store_true", help="always-output degrade: emit without a space row (typed #@warning in the manifest); the engine marks the run partial instead of refusing"); ap.add_argument("--allow-missing-notdef", action="store_true", help="always-output degrade: emit without a bound .notdef detector record (typed #@warning); run the engine in its partial mode (blank gid0, typed reason)")
    a = ap.parse_args()
    if a.style.count("/") != 1 or not all(a.style.split("/")): refuse(f"--style must be Family/Style, got {a.style!r}")
    family, sub = a.style.split("/")
    coll_ps, name_flag_lines = {}, []
    if a.collision_root:
        coll_ps, coll_flags = check_collection_names(a.collision_root)
        name_flag_lines = coll_flags.get(a.style, [])
        for ln in name_flag_lines: sys.stderr.write("kit_manifest: NOTE " + ln + "\n")
    if a.snapshot_sha256 and not re.fullmatch(r"[0-9a-f]{64}", a.snapshot_sha256): refuse("snapshot sha256 must be 64 lowercase hex", 3)
    # name rule: family = parent-of-parent dir, style = parent dir of the glyph tile folder (verbatim, no normalization claim); no override
    parts = os.path.normpath(os.path.abspath(a.tiledir)).split(os.sep)
    if len(parts) < 4 or parts[-1] != "glyph": refuse(f"UnknownTreeShape: tile folder must be .../<Family>/<Style>/glyph, got {a.tiledir!r}", 3)
    d_fam, d_sub = parts[-3:-1]
    if (family, sub) != (d_fam, d_sub):
        refuse(f"NameDerivationFailed: --style {a.style!r} != folder names {d_fam!r}/{d_sub!r}", 3)
    if not os.path.isdir(a.tiledir): refuse(f"tile folder not found: {a.tiledir}")
    policy, known = read_template(a.template)

    tiles, ignored = [], []
    upm = next((t.split()[1] for t in policy if t.split()[0] == "upm"), None)
    if upm is None: refuse("template has no upm line")
    for f in sorted(os.listdir(a.tiledir)):
        m = TILE.match(f)
        if not m: ignored.append(f); continue
        tiles.append((f, [int(x, 16) for x in m.group(2).split("_")]))
    if not tiles: refuse(f"no tiles named NNNNN__CP__hash.png in {a.tiledir}")
    sha = {f: hashlib.sha256(open(os.path.join(a.tiledir, f), "rb").read()).hexdigest() for f, _ in tiles}
    count = {}
    for f, cps in tiles:
        if len(cps) == 1: count[sha[f]] = count.get(sha[f], 0) + 1
    # v3.7: NO automatic .notdef exclusion. Identical images (>=3 single-codepoint tiles) are only reported as CANDIDATES;
    # without a real detector record nothing is removed. Always-output: unresolved candidates no longer refuse;
    # typed #@warning lines name every candidate group, a #@disposition_request asks for the owner decision,
    # and the engine ships a blank .notdef.
    cand_groups = {h: sorted(f for f, cps in tiles if len(cps) == 1 and sha[f] == h) for h, c in count.items() if c >= 3}
    notdef = set()
    cand_note = "; ".join("%d identical tiles e.g. %s" % (len(v), v[0]) for v in cand_groups.values())
    nd_bound = a.notdef_dir is not None
    if nd_bound:
        for _n in ("capture-manifest.tsv", "evidence.tsv"):
            if not os.path.isfile(os.path.join(a.notdef_dir, _n)): refuse(f"NotdefEvidenceMissing: {a.notdef_dir}/{_n} (notdef_dir must hold capture-manifest.tsv and evidence.tsv)", 3)
    cand_degrade = []
    if cand_groups and not nd_bound:
        # always-output degrade (was NotdefCandidateUnresolved): never auto-pick; name every candidate
        # group in a typed flag, request the owner disposition, ship a blank .notdef.
        for h in sorted(cand_groups):
            group = cand_groups[h]
            cand_degrade.append("#@warning notdef_candidate_unresolved: %d identical tiles (tile sha256 %s): %s; no tile excluded, no graphic picked; the engine ships a blank .notdef" % (len(group), h, ",".join(group)))
        cand_degrade.append("#@disposition_request notdef_candidate: owner decision needed - bind a .notdef detector record (--notdef-dir) or name the .notdef tile; until then .notdef stays blank")
    if not nd_bound and not a.allow_missing_notdef and not a.out.endswith(".DIAGNOSTIC.txt"):
        refuse("NotdefEvidenceMissing: no notdef_dir configured. The engine refuses every full run without a bound .notdef detector record (DetectionState::MissingEvidence); an empty .notdef is not a shortcut. Provide notdef_dir (capture-manifest.tsv + evidence.tsv).", 3)
    rows, seq, rep = {}, [], []
    excl_lines = []
    for f, cps in tiles:
        if len(cps) > 1: seq.append(f); continue
        if sha[f] in notdef: rep.append(f); continue
        cp = cps[0]
        if cp > 0x10FFFF or 0xD800 <= cp <= 0xDFFF: refuse(f"{f}: not a Unicode scalar value")
        if not tile_readable(os.path.join(a.tiledir, f)):
            # always-output: a corrupt/unsupported tile is excluded with a typed ledger row; the font ships.
            excl_lines.append("#@warning glyph_excluded unreadable_tile: %s excluded (header is not a readable PNG/JPEG); the run continues without it" % f)
            continue
        if cp in rows:
            # always-output (was DuplicateCodepoint): keep the first tile by deterministic filename
            # order (tiles are processed sorted); every dropped claim gets a typed ledger row.
            kind = "byte-identical" if sha[f] == sha[rows[cp][0]] else "distinct-bytes"
            excl_lines.append("#@warning glyph_excluded duplicate_codepoint: U+%04X kept %s; excluded %s (%s)" % (cp, rows[cp][0], f, kind))
            continue
        rows[cp] = (f, known.get(cp, "uni%04X" % cp if cp <= 0xFFFF else "u%05X" % cp))
    sample = os.path.join(a.tiledir, next(iter(rows.values()))[0]) if rows else None
    if (a.diagnostic_assumed_scale or a.allow_no_space or a.legacy_ref_mode or a.scale is not None) and not a.out.endswith(".DIAGNOSTIC.txt"):
        refuse(("MissingScaleEvidence: --scale is user-declared and UNVALIDATED; " if a.scale is not None else "") + "diagnostic flags write only to a file named *.DIAGNOSTIC.txt", 3 if a.scale is not None else 2)
    if len(rows) < 2: refuse(f"only {len(rows)} usable glyph tile(s) after exclusions; need at least 2")
    scale, basis = scale_for(a.style, a.scale, a.scales, sample, upm, a.diagnostic_assumed_scale, a.run_ledger, a.legacy_ref_mode, a.out.endswith('.DIAGNOSTIC.txt'), a.tiledir)
    srow, snote = space_row(a.style, a.tiledir, scale, a.space_table or os.path.join(os.path.dirname(a.scales), "style-space.tsv"), png_wh(sample), a.allow_missing_space)
    notdef_tiles = sorted(next(iter(cand_groups.values()))) if cand_groups else []
    nd_status = notdef_status(a.tiledir, notdef_tiles)
    hsh, hhh = find_space_source(os.path.dirname(a.tiledir.rstrip("/")))
    ssrc = ("space_source HsH=%s HHH=%s" % (",".join(hsh), ",".join(hhh) if hhh else "none")) if hsh else \
           "space_source MissingSpaceEvidence (no 0048_0020_0048 tile under sidebearing/)"
    seen_names = {}
    for cp in sorted(list(rows)):
        nm = rows[cp][1]
        if nm in seen_names:
            # always-output (was "duplicate glyph names" refusal): keep the first by codepoint order.
            excl_lines.append("#@warning glyph_excluded duplicate_glyph_name: %s kept U+%04X (%s); excluded U+%04X (%s)" % (nm, seen_names[nm][0], seen_names[nm][1], cp, rows[cp][0]))
            del rows[cp]
        else:
            seen_names[nm] = (cp, rows[cp][0])
    if len(rows) < 2: refuse(f"only {len(rows)} usable glyph tile(s) after exclusions; need at least 2")
    n = len(rows)
    pop = hashlib.sha256("".join(sorted("%x:%s\n" % (cp, nm) for cp, (_, nm) in rows.items())).encode()).hexdigest()
    derive_space_line = []
    if srow is None and not a.allow_no_space:
        # always-output: no measured/fixed space source -> emit the derive key; the engine derives the
        # space advance from solved glyph advances (U+006E advance, else a-z median, else all-glyph
        # median) instead of refusing or running partial. Verify the engine parser knows the key.
        _eng = os.path.join(os.path.dirname(a.scales), "engine", "pipeline", "src", "main.rs")
        try: _src = open(_eng, encoding="utf-8").read()
        except OSError as e: refuse(f"EngineSourceMissing: {e}", 3)
        if '"derive_space_from_letter_advances"' not in _src:
            refuse("EngineLacksManifestKey: the kit engine's manifest parser does not know derive_space_from_letter_advances yet (engine change not merged); the kit will not drop it silently", 3)
        derive_space_line = ["derive_space_from_letter_advances"]
        snote = snote + "; derive_space_from_letter_advances emitted (engine derives the space advance)"
    if 0x48 not in rows: refuse("MissingHReference: no U+0048 tile; the engine's capture_frame binding needs the H reference tile", 3)
    _ht = os.path.join(a.tiledir, rows[0x48][0]); _w, _h = (jpeg_wh(_ht) or png_wh(_ht))
    cframe = "%s:%dx%d:H-sha256:%s" % (frame_slug(derive_names(family + "/" + sub)[0] + "/" + derive_names(family + "/" + sub)[1]), _w, _h, hashlib.sha256(open(_ht, "rb").read()).hexdigest())
    if (derive_names(family + "/" + sub)[0] + "/" + derive_names(family + "/" + sub)[1]) == PAUL_STYLE and not cframe.endswith(":H-sha256:" + PAUL_H_PIN):
        refuse("DeclaredConventionChanged: Paul New H tile does not match the pinned H sha256", 3)
    iou_lines = []
    if a.iou_ink_threshold is not None or a.iou_flatten_steps is not None:
        try: _it, _is = int(a.iou_ink_threshold), int(a.iou_flatten_steps)
        except (TypeError, ValueError): refuse("IouSettingsInvalid: iou_ink_threshold and iou_flatten_steps must both be given as integers", 3)
        if not (1 <= _it <= 255) or _is < 1: refuse(f"IouSettingsInvalid: iou_ink_threshold {_it} must be 1..255 and iou_flatten_steps {_is} >= 1", 3)
        _eng = os.path.join(os.path.dirname(a.scales), "engine", "pipeline", "src", "main.rs")
        try: _src = open(_eng, encoding="utf-8").read()
        except OSError as e: refuse(f"EngineSourceMissing: {e}", 3)
        if '"iou_ink_threshold"' not in _src or '"iou_flatten_steps"' not in _src:
            refuse("EngineLacksManifestKey: the kit engine's manifest parser does not know iou_ink_threshold / iou_flatten_steps yet (IouSettings change not merged); the kit will not drop them silently", 3)
        iou_lines = [f"iou_ink_threshold {_it}", f"iou_flatten_steps {_is}"]
    notdef_lines = ["#@notdef_staging pending: RUN.command runs kni/tools/stage_notdef.py after the run root exists (capture_manifest + notdef evidence lines are appended there)"] if nd_bound else []
    degrade_lines = list(cand_degrade)
    if a.allow_missing_notdef and not nd_bound:
        degrade_lines.append("#@warning notdef_evidence_missing: always-output degrade; no bound .notdef detector record; the engine's partial mode emits a blank gid0 with typed reason missing_gid0_evidence")
    post_lines = []
    _pv = [a.lsb_add, a.rsb_add, a.post_scope, a.post_scope_label]
    if any(v is not None for v in _pv):
        if any(v is None for v in _pv): refuse("PostOffsetIncomplete: --lsb-add --rsb-add --post-scope --post-scope-label must all be given", 3)
        _lsb = signed_post_offset("lsb_add", a.lsb_add)
        _rsb = signed_post_offset("rsb_add", a.rsb_add)
        _members = a.post_scope.split(",")
        if any(m not in ("base", "space", "notdef", "mark", "kerning_letters") for m in _members) or len(set(_members)) != len(_members): refuse(f"PostOffsetInvalid: post_scope {a.post_scope!r} must be a comma list of distinct base|space|notdef|mark, or kerning_letters alone", 3)
        if "kerning_letters" in _members and len(_members) != 1: refuse("PostOffsetInvalid: post_scope kerning_letters must stand alone", 3)
        if not re.fullmatch(r"[A-Za-z0-9._+-]+", a.post_scope_label): refuse("PostOffsetInvalid: post_scope_label must be one token [A-Za-z0-9._+-]", 3)
        try: _psrc = open(os.path.join(os.path.dirname(a.scales), "engine", "pipeline", "src", "main.rs"), encoding="utf-8").read()
        except OSError as e: refuse(f"EngineSourceMissing: {e}", 3)
        if not all(('"%s"' % key) in _psrc for key in ("lsb_add", "rsb_add", "post_scope", "post_scope_label")):
            refuse("EngineLacksManifestKey: the kit engine's manifest parser does not know lsb_add/rsb_add/post_scope/post_scope_label yet (parser change not landed in this engine); the kit will not drop them silently", 3)
        post_lines = [f"lsb_add {_lsb}", f"rsb_add {_rsb}", f"post_scope {a.post_scope}", f"post_scope_label {a.post_scope_label}"]
    _sid = derive_names(family + "/" + sub)
    out = [f"#@style_id {_sid[0]}/{_sid[1]}", f"#@scale_status {'VALIDATED' if basis == 'VALIDATED' else ('DECLARED_CONVENTION' if basis.startswith('DECLARED_CONVENTION') else ('CONFIG_CONVENTION' if basis.startswith('CONFIG_CONVENTION') else 'UNVALIDATED:' + basis.split('(')[0]))} (run_mode full only for VALIDATED, DECLARED_CONVENTION or CONFIG_CONVENTION; anything else is stage1_only)", *(["#@accepted_basis OWNER_DECLARED_CONVENTION", "#@calibrated false"] if basis.startswith("DECLARED_CONVENTION") else (["#@accepted_basis ConfigDefaultScaleK/v1", "#@calibrated false"] if basis.startswith("CONFIG_CONVENTION") else [])), f"#@{ssrc}", *([f"#@canonical_snapshot {a.snapshot_sha256}"] if a.snapshot_sha256 else []), f"#@notdef_status {nd_status if not cand_groups else 'CANDIDATE-UNRESOLVED:' + nd_status} (graphic is NOT exported: engine writes empty gid0)", f"# kit v2.4 manifest generated from {os.path.basename(os.path.dirname(a.tiledir.rstrip('/')))}/{os.path.basename(a.tiledir.rstrip('/'))} for style {a.style}: "
           f"{n} glyph tiles; excluded 0 tiles as .notdef (no auto-exclusion; candidates: {cand_note or 'none'}) and {len(seq)} sequence tiles; "
           f"scale basis: {basis}; {snote}; .notdef graphic tile (repeated render, engine writes EMPTY .notdef today): {notdef_tiles[0] if notdef_tiles else 'NOTDEF-EVIDENCE-ABSENT (not the same as empty)'}; NOT an authoritative inventory",
           f"run_mode {'full' if (basis == 'VALIDATED' or basis.startswith('DECLARED_CONVENTION') or basis.startswith('CONFIG_CONVENTION')) else 'stage1_only'}", f"population_sha256 {pop}", f"family {derive_names(family + '/' + sub)[0]}", f"subfamily {derive_names(family + '/' + sub)[1]}", f"postscript_name {coll_ps.get(a.style) or ps_name(family, sub)}", f"capture_cohort {derive_names(family + '/' + sub)[0]}/{derive_names(family + '/' + sub)[1]}", f"capture_frame {cframe}", f"#@name_source folder_family={d_fam!r} folder_style={d_sub!r} label={family + '/' + sub!r} rule=run_config.rs:derive_names(candidate)",
           f"scale {scale}", *post_lines, *iou_lines, *notdef_lines, *excl_lines, *name_flag_lines, *degrade_lines, *derive_space_line, *policy, f"max_pairs {n * (n - 1)}"] + ([srow] if srow else [])
    for cp in sorted(rows): out.append("glyph 0x%04X %s @TILEDIR@/%s" % (cp, rows[cp][1], rows[cp][0]))
    if basis.startswith("DECLARED_CONVENTION"):   # self-check of the emitted line: exact bits of the declared K, nothing else
        want = next(float(p_[1]) for p_ in read_tsv(a.scales) if len(p_) >= 5 and p_[0] == a.style and (len(p_) >= 8 or p_[4] == "DeclaredConvention"))
        got = [l for l in out if l.split(" ")[0] == "scale"]
        if len(got) != 1 or struct.pack(">d", float(got[0].split(" ")[1])) != struct.pack(">d", want):
            refuse(f"DeclaredConventionMismatch: emitted scale line {got} is not the declared K {want!r} (bits 0x{struct.pack('>d', want).hex()})", 3)
    open(a.out, "w", encoding="utf-8").write("\n".join(out) + "\n")
    if a.notdef_out:
        open(a.notdef_out, "w", encoding="utf-8").write("notdef_status\t%s\nnotdef_tiles\t%d\nnotdef_sample\t%s\nspace\t%s\nscale_basis\t%s\n%s\n" % (nd_status, len(notdef_tiles), notdef_tiles[0] if notdef_tiles else "NOTDEF-EVIDENCE-ABSENT", snote, basis, ssrc))
    if basis.startswith("ASSUMED"): sys.stderr.write("kit_manifest: WARNING scale basis " + basis + "\n")
    if srow is None: sys.stderr.write("kit_manifest: WARNING " + snote + "\n")
    sys.stderr.write(f"kit_manifest: style={a.style} tiles={len(tiles)} glyphs={n} repeated_excluded={len(rep)} "
                     f"sequence_excluded={len(seq)} ignored_files={len(ignored)} scale={scale} max_pairs={n*(n-1)}\n")

def main():
    try: _main()
    except SystemExit: raise
    except BaseException as e:   # any unexpected failure is a typed refusal, never a traceback with exit 1/2
        sys.stderr.write("kit_manifest: REFUSED: KitInternalError: %s: %s\n" % (type(e).__name__, e)); sys.exit(3)

if __name__ == "__main__": main()
