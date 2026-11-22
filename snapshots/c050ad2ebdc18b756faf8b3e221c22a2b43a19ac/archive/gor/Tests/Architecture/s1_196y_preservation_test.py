#!/usr/bin/env python3
"""S1 deferred-satellite absorption (arch-196y item 5): strict byte evidence.

Integration mode (default, uses git): the section between the station-move
sentinels in the receiving file must equal the satellite's bytes at the pinned
base, its sha256 must match the map pin, the satellite path must be absent, and
the host file outside the sentinels must be byte-identical to the host at base
(full reconstruction: host == base host + '\\n' + BEGIN + body + END).
`--fixture` mode: portable negative controls on embedded sanitized excerpts.
No newline normalization, trimming or semantic compare anywhere."""
from pathlib import Path
import json, subprocess, hashlib, sys

BEGIN = '// BEGIN station-move %s\n'
END = '// END station-move %s\n'

def section(host, name):
    return host.split(BEGIN % name, 1)[1].split(END % name, 1)[0]

def check_host(host, old, name, sha256, where, old_host=None):
    assert host.count(BEGIN % name) == 1 and host.count(END % name) == 1, where + ': sentinel count'
    body = section(host, name)
    assert body == old, where + ': moved bytes'
    assert hashlib.sha256(body.encode()).hexdigest() == sha256, where + ': body hash'
    if old_host is not None:
        assert host == old_host + '\n' + BEGIN % name + old + END % name, where + ': host residual drift outside sentinels'
    return body

def integration():
    r = Path(__file__).resolve().parents[2]
    spec = json.loads((r / 'Tests/Architecture/s1-196y-map.json').read_text())
    s = r / 'Sources/gor'
    for m in spec['moves']:
        old = subprocess.check_output(['git', '-C', str(r), 'show', spec['base'] + ':archive/gor/Sources/gor/' + m.get('base_old', m['old'])], text=True)
        old_host = subprocess.check_output(['git', '-C', str(r), 'show', spec['base'] + ':archive/gor/Sources/gor/' + m.get('base_host', m['new'])], text=True)
        check_host((s / m['new']).read_text(), old, m['old'], m['sha256'], m['new'], old_host)
        assert not (s / m['old']).exists(), m['old'] + ': satellite path still present'
    print('PASS S1-196y exact source bytes preserved under station-move sentinels; satellite paths absent; hosts byte-identical outside sentinels')

NAME = 'WidgetCache.swift'
BODY = 'import Foundation\n\nstruct WidgetCache {\n    static let ttl: TimeInterval = 0.25\n}\n'
BODY_SHA = hashlib.sha256(BODY.encode()).hexdigest()
HOST_BASE = 'import AppKit\nfinal class Host {}\n'
HOST = HOST_BASE + '\n' + BEGIN % NAME + BODY + END % NAME

def verify(host):
    check_host(host, BODY, NAME, BODY_SHA, 'fixture', HOST_BASE)

def fixture():
    verify(HOST)
    for name, h in [
        ('body mutation', HOST.replace('0.25', '0.5', 1)),
        ('lost newline', HOST.replace(BODY + END % NAME, BODY.rstrip('\n') + END % NAME, 1)),
        ('duplicate sentinel', HOST + BEGIN % NAME),
        ('missing sentinel', HOST.replace(BEGIN % NAME, '', 1)),
        ('host mutation outside sentinels', HOST.replace('final class Host {}', 'final class Host { /*<*/', 1)),
    ]:
        try:
            verify(h)
        except (AssertionError, IndexError):
            print('CAUGHT', name)
        else:
            raise RuntimeError('uncaught mutant: ' + name)
    print('PASS portable byte-preservation fixture and 5 negative controls')

if __name__ == '__main__':
    fixture() if '--fixture' in sys.argv[1:] else integration()
