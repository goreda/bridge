#!/usr/bin/env python3
"""Builds FILE.payloads.json from `ffprobe -v error -show_packets -show_data
-of json FILE` output on stdin: one SHA-256 per packet payload, in emitted
order. Used only at fixture-generation time; tests consume the saved JSON.
Usage: ffprobe -v error -show_packets -show_data -of json FILE | python3 tools/make_payload_oracle.py FILE > FILE.payloads.json"""
import json, hashlib, sys, re
name = sys.argv[1] if len(sys.argv) > 1 else "?"
d = json.load(sys.stdin)
out = []
for p in d["packets"]:
    raw = bytearray()
    for line in p["data"].strip().split("\n"):
        rest = line.split(":", 1)[1]
        hexpart = re.split(r"\s{2,}", rest.strip())[0]
        raw += bytes.fromhex(re.sub(r"[^0-9a-fA-F]", "", hexpart))
    assert len(raw) == int(p["size"]), (len(raw), p["size"])
    out.append({"size": len(raw), "sha256": hashlib.sha256(bytes(raw)).hexdigest()})
json.dump({"file": name, "packets": out}, sys.stdout, indent=1)
print()
