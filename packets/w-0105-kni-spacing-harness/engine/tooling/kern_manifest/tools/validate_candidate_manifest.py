#!/usr/bin/env python3
"""Schema check for data/kern-real-font-candidates/manifest.tsv and ARCHIVES.tsv.

Schema check only: it reads metadata tables. It opens no font, runs no
measurement and makes no statement about any font. Rules come from the
directory README; a rule the README does not state is reported as GAP, not
enforced. Findings: ERROR (a stated rule is broken) or GAP (the README is
silent, so the field is only checked for presence).

Usage: validate_candidate_manifest.py MANIFEST.tsv ARCHIVES.tsv
Exit code 1 when any ERROR is found, otherwise 0.
"""
import csv
import io
import re
import sys

# Header taken from the manifest file itself (the README names the contents but not the column names).
COLUMNS = [
    "font", "designer", "style", "upstream_url", "version_or_pin", "license", "license_text_url",
    "license_file", "license_sha256", "binary_file", "binary_sha256", "binary_source_url",
    "kern_pairs_explicit", "kern_pairs_class_expanded", "hand_kerning_evidence_class",
    "hand_kerning_evidence_source", "caveats", "status",
]
ARCHIVE_COLUMNS = ["archive", "url", "bytes", "sha256"]
# README: the two evidence classes, by name.
EVIDENCE_CLASSES = {"Written statement", "Structural source evidence"}
# README: all rows are OFL-1.1 fonts.
LICENSE_VALUE = "OFL-1.1"
SHA256 = re.compile(r"^[0-9a-f]{64}$")
COMMIT = re.compile(r"\b[0-9a-f]{40}\b")
URL = re.compile(r"^https://\S+$")
# Fields the README names as present but does not constrain further.
FREE_TEXT_GAPS = {
    "style": "README gives no style vocabulary",
    "status": "README does not list allowed status values",
    "caveats": "README gives no caveat format",
    "designer": "README gives no designer format",
}


def _rows(text):
    rows = list(csv.reader(io.StringIO(text), delimiter="\t", quoting=csv.QUOTE_NONE))
    return rows


def validate(manifest_text, archives_text):
    out = []

    def add(kind, where, field, msg):
        out.append({"kind": kind, "where": where, "field": field, "message": msg})

    m = _rows(manifest_text)
    if not m:
        add("ERROR", "manifest", "-", "empty file")
        return out
    if m[0] != COLUMNS:
        add("ERROR", "manifest", "header", "header differs from the expected column list")
        return out
    body = [r for r in m[1:] if r]
    for g, why in sorted(FREE_TEXT_GAPS.items()):
        add("GAP", "manifest", g, why + "; checked for presence only")
    add("GAP", "manifest", "header", "README does not state the column names; the list is taken from the file")
    add("GAP", "manifest", "font", "README does not state a row count rule beyond describing four fonts")
    seen = set()
    for i, r in enumerate(body, start=1):
        where = f"manifest row {i}"
        if len(r) != len(COLUMNS):
            add("ERROR", where, "-", f"{len(r)} columns, expected {len(COLUMNS)}")
            continue
        d = dict(zip(COLUMNS, r))
        for c in COLUMNS:
            if not d[c].strip():
                add("ERROR", where, c, "empty")
        if d["font"] in seen:
            add("ERROR", where, "font", "duplicate font")
        seen.add(d["font"])
        for c in ("license_sha256", "binary_sha256"):
            if d[c] and not SHA256.match(d[c]):
                add("ERROR", where, c, "not a 64-digit lowercase hex SHA-256")
        for c in ("upstream_url", "license_text_url"):
            if d[c] and not URL.match(d[c]):
                add("ERROR", where, c, "not an https URL")
        if d["binary_source_url"] and not d["binary_source_url"].startswith("https://"):
            add("ERROR", where, "binary_source_url", "does not start with an https URL")
        for c in ("kern_pairs_explicit", "kern_pairs_class_expanded"):
            if d[c] and not re.fullmatch(r"[0-9]+", d[c]):
                add("ERROR", where, c, "not a non-negative integer")
        if d["license"] and d["license"] != LICENSE_VALUE:
            add("ERROR", where, "license", f"expected {LICENSE_VALUE}")
        if d["hand_kerning_evidence_class"] and d["hand_kerning_evidence_class"] not in EVIDENCE_CLASSES:
            add("ERROR", where, "hand_kerning_evidence_class", "not one of the two classes named in the README")
        if d["version_or_pin"].lower().startswith("no release archive") and not COMMIT.search(d["version_or_pin"]):
            add("ERROR", where, "version_or_pin", "no release archive, so a 40-digit commit pin is required")
        if d["hand_kerning_evidence_class"] == "Written statement" and "http" not in d["hand_kerning_evidence_source"]:
            add("ERROR", where, "hand_kerning_evidence_source", "a written statement needs a primary source reference")
        if d["hand_kerning_evidence_class"] == "Structural source evidence" and "Source:" not in d["hand_kerning_evidence_source"]:
            add("ERROR", where, "hand_kerning_evidence_source", "structural evidence needs the named source files")
        if d["binary_file"] and d["binary_file"].startswith("/"):
            add("ERROR", where, "binary_file", "absolute path; binaries are not stored in the repository")

    a = _rows(archives_text)
    archives = set()
    if not a or a[0] != ARCHIVE_COLUMNS:
        add("ERROR", "archives", "header", "header differs from the expected column list")
    else:
        for i, r in enumerate([x for x in a[1:] if x], start=1):
            where = f"archives row {i}"
            if len(r) != 4:
                add("ERROR", where, "-", f"{len(r)} columns, expected 4")
                continue
            name, url, size, sha = r
            archives.add(name)
            if not URL.match(url):
                add("ERROR", where, "url", "not an https URL")
            if not re.fullmatch(r"[0-9]+", size) or int(size) == 0:
                add("ERROR", where, "bytes", "not a positive integer")
            if not SHA256.match(sha):
                add("ERROR", where, "sha256", "not a 64-digit lowercase hex SHA-256")
        add("GAP", "archives", "bytes", "README names size but not its unit; read as bytes from the column name")
        for i, r in enumerate(body, start=1):
            if len(r) != len(COLUMNS):
                continue
            d = dict(zip(COLUMNS, r))
            m_ = re.search(r"/([^/\s]+\.zip)\b", d["binary_source_url"])
            if m_ and m_.group(1) not in archives:
                add("ERROR", f"manifest row {i}", "binary_source_url", f"archive {m_.group(1)} is not listed in the archives table")
    return out


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    res = validate(open(argv[1], encoding="utf-8").read(), open(argv[2], encoding="utf-8").read())
    for f in res:
        print(f"{f['kind']}\t{f['where']}\t{f['field']}\t{f['message']}")
    errs = sum(1 for f in res if f["kind"] == "ERROR")
    gaps = sum(1 for f in res if f["kind"] == "GAP")
    print(f"summary\terrors={errs}\tgaps={gaps}\tschema check only; no statement about any font")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
