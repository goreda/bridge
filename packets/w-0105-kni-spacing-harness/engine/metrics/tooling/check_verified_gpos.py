#!/usr/bin/env python3
"""Independent strict parse of verification-only DFLT/kern PairPos1 bytes."""
import csv
import struct
import sys
from pathlib import Path


def parse(path):
    b = path.read_bytes()
    def u(off):
        assert 0 <= off and off + 2 <= len(b), 'offset outside table'
        return struct.unpack_from('>H', b, off)[0]
    assert b[:4] == bytes([0, 1, 0, 0])
    sl, fl, ll = u(4), u(6), u(8)
    assert u(sl) == 1 and b[sl + 2:sl + 6] == b'DFLT'
    script = sl + u(sl + 6)
    lang = script + u(script)
    assert u(script + 2) == 0 and u(lang) == 0 and u(lang + 2) == 65535
    assert u(lang + 4) == 1 and u(lang + 6) == 0
    assert u(fl) == 1 and b[fl + 2:fl + 6] == b'kern'
    feat = fl + u(fl + 6)
    assert [u(feat), u(feat + 2), u(feat + 4)] == [0, 1, 0]
    assert u(ll) == 1
    lookup = ll + u(ll + 2)
    assert [u(lookup), u(lookup + 2), u(lookup + 4)] == [2, 0, 1]
    sub = lookup + u(lookup + 6)
    assert [u(sub), u(sub + 4), u(sub + 6)] == [1, 4, 0], 'VF2 must be zero'
    n = u(sub + 8)
    cov = sub + u(sub + 2)
    assert u(cov) == 1 and u(cov + 2) == n
    lefts = [u(cov + 4 + 2*i) for i in range(n)]
    assert lefts == sorted(set(lefts))
    assert cov + 4 + 2*n == len(b), 'unexpected trailing bytes'
    pairs = {}
    for i, left in enumerate(lefts):
        ps = sub + u(sub + 10 + 2*i)
        count = u(ps)
        end = ps + 2 + 4*count
        assert end <= cov
        rights = []
        for j in range(count):
            off = ps + 2 + 4*j
            right = u(off)
            value = struct.unpack_from('>h', b, off+2)[0]
            rights.append(right)
            assert (left, right) not in pairs
            pairs[left, right] = value
        assert rights == sorted(set(rights))
    return pairs


def check(out):
    with (out / 'verified-pairs.tsv').open() as f:
        rows = list(csv.DictReader(f, delimiter='\t'))
    expected = {(int(r['left_gid']), int(r['right_gid'])): int(r['kern_u']) for r in rows}
    assert len(expected) == len(rows)
    actual = parse(out / 'verification.gpos')
    for key in actual.keys() | expected.keys():
        assert actual.get(key) == expected.get(key), (key, actual.get(key), expected.get(key))
    print(f'independent-GPOS-readback PASS exact_pairs={len(actual)}; table-only, no shaping/font insertion')


if __name__ == '__main__':
    check(Path(sys.argv[1]))
