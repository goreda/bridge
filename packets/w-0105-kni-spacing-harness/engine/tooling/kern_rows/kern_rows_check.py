#!/usr/bin/env python3
"""Reference validator for the verified-row table; mirrors the Rust guard.

Usage: kern_rows_check.py ROWS.tsv MANIFEST.tsv
Exit 0 when every row is valid, 1 otherwise (message on stderr).

All comparisons are exact (fractions of parsed decimal text; no floats).
Values and aligned intermediates are limited to the signed 128-bit range, as in
the Rust guard; leaving it is an "overflow" refusal, never a rounding."""
import re
import sys
from fractions import Fraction

COLUMNS = ["font_sha256", "left", "right", "outline_source", "outline_sha256", "upm", "gap_after",
           "gap_target", "y_lo", "y_hi", "error_bound_method", "error_bound_value", "tol", "tolerance_label",
           "status", "reason"]
MEASURE_COLUMNS = ["upm", "gap_after", "gap_target", "y_lo", "y_hi", "error_bound_method", "error_bound_value",
                   "tol", "tolerance_label"]
MANIFEST_COLUMNS = ["name", "label", "class", "unit", "method", "value", "derivation"]
ERROR_METHODS = ["analytic_root_solve", "flatten"]
OUTLINE_SOURCES = ["extract_quadratic", "extract_cff"]
NA_REASONS = ["no_vertical_overlap", "missing_wall_evidence", "missing_outline_evidence",
              "tolerance_missing", "numerical_unresolved"]
UNIT = "font_units"
NA = "n/a"

# FORMAT constants.
SHA_HEX_LEN = 64            # sha256 digest: 32 bytes as 64 hex characters
RADIX = 10                  # radix of the decimal text
I128_VALUE_BITS = 127       # magnitude bits of a signed 128-bit integer
U32_BITS = 32               # width of the upm integer type
I128_MAX = (1 << I128_VALUE_BITS) - 1
U32_MAX = (1 << U32_BITS) - 1
HEADER_LINES = 1            # header line count in both tables
FIRST_DATA_LINE = HEADER_LINES + 1   # 1-based line number of the first data line
ARG_ROWS, ARG_MANIFEST = 1, 2   # command-line positions
OVERFLOW = "overflow: exact decimal arithmetic left the i128 range"

DECIMAL = re.compile(r"-?[0-9]+(\.[0-9]+)?")   # one plain decimal grammar, ASCII digits only
UINT = re.compile(r"[0-9]+")


class RowError(Exception):
    pass


def is_sha(s):
    return len(s) == SHA_HEX_LEN and all(c in "0123456789abcdef" for c in s)


def parse_dec(s):
    """Returns (mantissa, scale) for -?[0-9]+(\\.[0-9]+)?, else raises RowError."""
    if not DECIMAL.fullmatch(s):
        raise RowError(f"not a plain decimal: {s!r}")
    body = s[1:] if s.startswith("-") else s
    int_part, _, frac = body.partition(".")
    mant = int(int_part + frac)
    if mant > I128_MAX:
        raise RowError(OVERFLOW)
    return (-mant if s.startswith("-") else mant), len(frac)


def align(*decs):
    """Mirrors the Rust common-scale step; raises on i128 overflow. Returns exact integers."""
    common = max(scale for _, scale in decs)
    out = []
    for mant, scale in decs:
        factor = 1
        for _ in range(common - scale):
            factor *= RADIX
            if factor > I128_MAX:
                raise RowError(OVERFLOW)
        if abs(mant * factor) > I128_MAX:
            raise RowError(OVERFLOW)
        out.append(mant * factor)
    return out


def frac(d):
    return Fraction(d[0], RADIX ** d[1])


def leq(a, b):
    align(a, b)
    return frac(a) <= frac(b)


def within(a, b, tol):
    x, y, _ = align(a, b, tol)
    if abs(x - y) > I128_MAX:
        raise RowError(OVERFLOW)
    return abs(frac(a) - frac(b)) <= frac(tol)


def positive(d):
    return d[0] > 0


def parse_manifest(text):
    """Entries named 'tolerance' (error bound: method analytic_root_solve or flatten, value > 0)
    and 'flatten' (the flatten parameter). Each is class CONVENTION with a written derivation.
    Returns {(name, label): (method, decimal)}."""
    lines = [l for l in text.split("\n") if l.strip()]
    if not lines or lines[0].split("\t") != MANIFEST_COLUMNS:
        raise RowError("manifest: bad header")
    out = {}
    for n, l in enumerate(lines[HEADER_LINES:], FIRST_DATA_LINE):
        f = l.split("\t")
        if len(f) != len(MANIFEST_COLUMNS) or not all(x.strip() for x in f):
            raise RowError(f"manifest line {n}: every field required")
        name, label, cls, unit, method, value, _ = f
        if name not in ("tolerance", "flatten"):
            raise RowError(f"manifest line {n}: unknown name")
        if cls != "CONVENTION":
            raise RowError(f"manifest line {n}: class must be CONVENTION")
        if name == "tolerance" and (unit != UNIT or method not in ERROR_METHODS):
            raise RowError(f"manifest line {n}: tolerance needs unit {UNIT} and a known error-bound method")
        if name == "flatten" and method != "flatten":
            raise RowError(f"manifest line {n}: flatten entry method must be flatten")
        v = parse_dec(value)
        if not positive(v):
            raise RowError(f"manifest line {n}: value must be a positive decimal")
        if (name, label) in out:
            raise RowError(f"manifest line {n}: duplicate entry")
        out[(name, label)] = (method, v)
    return out


def parse_upm(s, n):
    if not UINT.fullmatch(s) or not 0 < int(s) <= U32_MAX:
        raise RowError(f"line {n}: upm must be a positive integer")
    return int(s)


def check_rows(text, manifest):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    if not lines or lines[0].split("\t") != COLUMNS:
        raise RowError("rows: header must be exactly the declared columns")
    previous = None
    upm_of_font = {}
    counts = {"VERIFIED": 0, "FAIL": 0, NA: 0}
    for n, l in enumerate(lines[HEADER_LINES:], FIRST_DATA_LINE):
        f = l.split("\t")
        if len(f) != len(COLUMNS):
            raise RowError(f"line {n}: expected {len(COLUMNS)} fields, got {len(f)}")
        r = dict(zip(COLUMNS, f))
        if not is_sha(r["font_sha256"]):
            raise RowError(f"line {n}: font_sha256 must be 64 lowercase hex")
        if not r["left"] or not r["right"]:
            raise RowError(f"line {n}: empty glyph name")
        key = tuple(r[c].encode("utf-8") for c in ("font_sha256", "left", "right"))
        if previous is not None:
            if key == previous:
                raise RowError(f"line {n}: duplicate row for font and pair")
            if key < previous:
                raise RowError(f"line {n}: rows must be in strictly increasing byte order of font_sha256, left, right")
        previous = key
        st = r["status"]
        if st in ("VERIFIED", "FAIL"):
            if r["outline_source"] not in OUTLINE_SOURCES or not is_sha(r["outline_sha256"]):
                raise RowError(f"line {n}: {st} row needs outline_source and outline_sha256")
            upm = parse_upm(r["upm"], n)
            if upm_of_font.setdefault(r["font_sha256"], upm) != upm:
                raise RowError(f"line {n}: the same font_sha256 carries two different upm values")
            try:
                after, target, lo, hi, eb, tol = (parse_dec(r[c]) for c in
                                                  ("gap_after", "gap_target", "y_lo", "y_hi",
                                                   "error_bound_value", "tol"))
                if not leq(lo, hi):
                    raise RowError("y_lo must not exceed y_hi")
                if not positive(eb):
                    raise RowError("error_bound must be positive; zero is never assumed")
                entry = manifest.get(("tolerance", r["tolerance_label"]))
                if entry is None:
                    raise RowError("tolerance_label not in the manifest")
                if r["error_bound_method"] != entry[0]:
                    raise RowError("error_bound_method differs from the manifest method")
                if not leq(eb, entry[1]):
                    raise RowError("error_bound exceeds the manifest bound")
                if not leq(eb, tol):
                    raise RowError("tol must cover the error bound")
                if entry[0] == "flatten" and not any(k[0] == "flatten" for k in manifest):
                    raise RowError("flatten method needs a flatten entry in the manifest")
                if r["reason"]:
                    raise RowError(f"{st} row carries no reason")
                want = "VERIFIED" if within(after, target, tol) else "FAIL"
                if st != want:
                    raise RowError(f"status {st} contradicts the measurement ({want})")
            except RowError as e:
                raise RowError(f"line {n}: {e}") from None
        elif st == NA:
            for c in MEASURE_COLUMNS:
                if r[c] != NA:
                    raise RowError(f"line {n}: n/a row must hold exactly n/a in {c}")
            have = (r["outline_source"] in OUTLINE_SOURCES) and is_sha(r["outline_sha256"])
            none = r["outline_source"] == NA and r["outline_sha256"] == NA
            if not (have or none):
                raise RowError(f"line {n}: n/a row outline columns must both be real or both n/a")
            if r["reason"] not in NA_REASONS:
                raise RowError(f"line {n}: n/a row needs a typed reason")
            if r["reason"] == "missing_outline_evidence" and have:
                raise RowError(f"line {n}: missing_outline_evidence contradicts the outline columns")
            if r["reason"] == "no_vertical_overlap" and not have:
                raise RowError(f"line {n}: no_vertical_overlap needs an outline")
        else:
            raise RowError(f"line {n}: status must be VERIFIED, FAIL or n/a")
        counts[st] += 1
    return counts["VERIFIED"], counts["FAIL"], counts[NA]


if __name__ == "__main__":
    try:
        m = parse_manifest(open(sys.argv[ARG_MANIFEST]).read())
        v, f, n = check_rows(open(sys.argv[ARG_ROWS]).read(), m)
        print(f"ok verified={v} fail={f} n/a={n}")
    except RowError as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
