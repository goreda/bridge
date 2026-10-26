"""python -m sweepaudit --root DIR --expected keys.txt --key-regex RE (--result RE | --refusal RE)... [--refusal-type RE]
[--exclude RE] [--expected-count N] [--max-read BYTES] [--receipt FILE] [--config cfg.json] [--strict]

Patterns are "content:RE" (default) or "path:RE". Exit code is 0 unless --strict is given and complete=false; 2 for an input or file error (missing root, unreadable or non-UTF-8 expected list, bad config).
"""
import argparse
import re
import sys
from pathlib import Path
from .core import audit, config_from_dict, load_json_strict, _esc


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--expected", required=True)
    ap.add_argument("--config")
    ap.add_argument("--key-regex")
    ap.add_argument("--key-from-expected", action="store_true")
    ap.add_argument("--result", action="append", default=[])
    ap.add_argument("--refusal", action="append", default=[])
    ap.add_argument("--refusal-type")
    ap.add_argument("--exclude")
    ap.add_argument("--expected-count", type=int)
    ap.add_argument("--max-read", type=int)
    ap.add_argument("--receipt")
    ap.add_argument("--strict", action="store_true")
    a = ap.parse_args(argv)
    try:
        c = load_json_strict(Path(a.config).read_bytes()) if a.config else {}
        if not isinstance(c, dict):
            raise ValueError("config must be a JSON object")
        expected_text = Path(a.expected).read_bytes().decode("utf-8")
        override = {}
        if a.key_regex:
            override["key_regex"] = a.key_regex
        if a.key_from_expected:
            override["key_from_expected"] = True
        if a.result:
            override["result_patterns"] = a.result
        if a.refusal:
            override["refusal_patterns"] = a.refusal
        for opt, name in ((a.refusal_type, "refusal_type_regex"), (a.exclude, "exclude_regex"),
                          (a.expected_count, "expected_count"), (a.max_read, "max_read")):
            if opt is not None:
                override[name] = opt
        cfg = config_from_dict(c, **override)
        if not cfg.key_regex and not cfg.key_from_expected:
            ap.error("key regex or --key-from-expected required")
        text, summary = audit(a.root, expected_text, cfg)
        if a.receipt:
            Path(a.receipt).write_text(text, encoding="utf-8")
    except (OSError, ValueError, KeyError, TypeError, re.error) as e:
        sys.stderr.write("INPUT_ERROR: %s\n" % _esc(str(e)))
        return 2
    sys.stdout.write(text)
    return 1 if (a.strict and not summary["complete"]) else 0


if __name__ == "__main__":
    sys.exit(main())
