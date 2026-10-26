"""python -m gposcheck --original A.ttf --output B.ttf --declared pairs.json [--allow-diff-tag TAG] [--receipt R.txt]
  [--enumeration-limit N] [--allow-legacy-kern REASON] [--compare-original] [--original-drop-is-finding] [--sequences s.json]

pairs.json: a list of {"left","right","requested","written"(int|null),"status","reason"}.
Exit code 0: verdict PASS. Exit code 1: verdict FAIL (at least one finding). Exit code 2: an input or file error
(unreadable file, JSON that does not parse, a top level that is not a list, bad arguments); a receipt with the
typed finding is printed and written when it can be.
"""
import argparse
import json
import sys
from pathlib import Path
from .core import check, ENUM_LIMIT_DEFAULT, RECEIPT_VERSION


def _input_error(code, detail, receipt):
    text = "%s\nfinding code=%s detail=%s\nverdict=INPUT_ERROR findings=1\n" % (RECEIPT_VERSION, code, detail)
    if receipt:
        try:
            Path(receipt).write_text(text)
        except OSError as e:
            text += "receipt_not_written %r\n" % (str(e),)
    sys.stdout.write(text)
    return 2


def _load_list(path, code):
    try:
        data = json.loads(Path(path).read_text())
    except (OSError, ValueError) as e:
        return None, (code, "%s: %s" % (path, e))
    if not isinstance(data, list):
        return None, (code, "%s: top level must be a list, got %s" % (path, type(data).__name__))
    return data, None


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--original", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--declared", required=True)
    ap.add_argument("--allow-diff-tag", action="append", default=[])
    ap.add_argument("--receipt")
    ap.add_argument("--enumeration-limit", type=int, default=ENUM_LIMIT_DEFAULT,
                    help="all-pairs glyph limit (CONVENTION default %d); above it the run fails with not_enumerated" % ENUM_LIMIT_DEFAULT)
    ap.add_argument("--allow-legacy-kern", metavar="REASON", help="explicit exception, reason is printed in the receipt")
    ap.add_argument("--compare-original", action="store_true")
    ap.add_argument("--original-drop-is-finding", action="store_true")
    ap.add_argument("--sequences", help="JSON list of strings or {text, expected_kern}")
    a = ap.parse_args(argv)
    blobs = {}
    for name in ("original", "output"):
        try:
            blobs[name] = Path(getattr(a, name)).read_bytes()
        except OSError as e:
            return _input_error("input_file_unreadable", "%s: %s" % (getattr(a, name), e), a.receipt)
    declared, err = _load_list(a.declared, "declared_file_unusable")
    if err:
        return _input_error(err[0], err[1], a.receipt)
    seqs = []
    if a.sequences:
        seqs, err = _load_list(a.sequences, "sequences_file_unusable")
        if err:
            return _input_error(err[0], err[1], a.receipt)
    text, findings, _ = check(blobs["original"], blobs["output"], declared, tuple(a.allow_diff_tag),
                              enumeration_limit=a.enumeration_limit, allow_legacy_kern=a.allow_legacy_kern,
                              compare_original=a.compare_original, original_drop_is_finding=a.original_drop_is_finding,
                              sequences=seqs)
    if a.receipt:
        try:
            Path(a.receipt).write_text(text)
        except OSError as e:
            return _input_error("receipt_not_writable", "%s: %s" % (a.receipt, e), None)
    sys.stdout.write(text)
    return 0 if not findings else 1


if __name__ == "__main__":
    sys.exit(main())
