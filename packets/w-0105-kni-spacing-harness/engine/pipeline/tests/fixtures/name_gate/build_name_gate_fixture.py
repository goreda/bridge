#!/usr/bin/env python3
"""Deterministic builder for the name-gate repo fixture.

The readback gate under test (pipeline/src/main.rs name_table_readback) parses
only the sfnt offset table and the 'name' table, so the fixture is a minimal
well-formed sfnt carrying exactly the name records of the defective delivery
this gate guards against (PostScript name "MarqAlternateKNI-Regular", family
"Marq Alternate KNI", subfamily "Regular"). The full shipped binary never
entered the repo (it lived in a machine-local scratch path), so this builder
reconstructs the name-table payload from the documented values; the table
checksum and directory are computed per the OpenType spec, keeping the file a
valid sfnt for any future parser stricter than today's readback.

Usage: build_name_gate_fixture.py <output.otf>
Prints the sha256 of the bytes written; the test module pins that digest.
"""
import hashlib
import struct
import sys

# nameID -> value. IDs 1, 2, 4, 6 are the contract fields the gate verifies;
# 3 and 5 keep the table shaped like a real delivery.
RECORDS = [
    (1, "Marq Alternate KNI"),
    (2, "Regular"),
    (3, "MarqAlternateKNI-Regular:1"),
    (4, "Marq Alternate KNI Regular"),
    (5, "Version 1.0"),
    (6, "MarqAlternateKNI-Regular"),
]


def name_table() -> bytes:
    strings = b""
    entries = b""
    for name_id, value in RECORDS:
        encoded = value.encode("utf-16-be")
        entries += struct.pack(">6H", 3, 1, 0x0409, name_id, len(encoded), len(strings))
        strings += encoded
    return struct.pack(">3H", 0, len(RECORDS), 6 + 12 * len(RECORDS)) + entries + strings


def checksum(data: bytes) -> int:
    padded = data + b"\0" * (-len(data) % 4)
    total = 0
    for i in range(0, len(padded), 4):
        total = (total + struct.unpack(">I", padded[i:i + 4])[0]) & 0xFFFFFFFF
    return total


def sfnt() -> bytes:
    table = name_table()
    offset = 12 + 16
    header = struct.pack(">I4H", 0x00010000, 1, 16, 0, 0)
    record = b"name" + struct.pack(">3I", checksum(table), offset, len(table))
    return header + record + table + b"\0" * (-len(table) % 4)


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    data = sfnt()
    with open(sys.argv[1], "wb") as fh:
        fh.write(data)
    print(hashlib.sha256(data).hexdigest())


if __name__ == "__main__":
    main()
