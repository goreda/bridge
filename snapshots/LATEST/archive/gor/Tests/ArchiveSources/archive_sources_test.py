#!/usr/bin/env python3
"""Archive keeps ONLY spreadsheet 1-O2aje... (gid 576490957). Checks the owning file lists exactly that source, the removed id appears
nowhere in Sources, the cache file name is keyed by the source list (FNV-1a port equals Swift text), stale snapshots are deleted, and a
merged load from the old cache can not carry removed-source rows. Swift compiled only on gor-ci; this is a Python port + text pins."""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]
cfg = (root/'Sources/gor/Media/ArchiveBrowser.swift').read_text(); lib = (root/'Sources/gor/Media/ArchiveLibrary.swift').read_text()
fails = []
def check(n, ok):
    print(('PASS ' if ok else 'FAIL ') + n)
    if not ok: fails.append(n)
block = cfg[cfg.index('static let spreadsheetSources'):]; block = block[:block.index(']\n')]
ids = re.findall(r'\("([^"]+)", "([^"]*)", "([^"]*)"\)', block)
check('exactly one source', len(ids) == 1)
check('the kept source is 1-O2aje... gid 576490957', ids == [("1-O2ajewvMSrs6L8N3uMjDp53jcHz5klLvOSv9wndRaA", "576490957", "")])
removed = '1vne06BO86a0R_gb5KHap8p03xPArhIJihqXCGl_pNjE'
check('removed id absent from every Swift source', not any(removed in p.read_text(errors='ignore') for p in (root/'Sources').rglob('*.swift')))
def fnv(sources):
    h = 0xcbf29ce484222325
    for b in '|'.join('%s:%s' % (i, g) for i, g, _ in sources).encode(): h = ((h ^ b) * 0x100000001b3) & (2**64 - 1)
    return 'archive_cache-%x.json' % h
old_list = [(removed, '0', ''), ids[0]]
check('cache name differs between old and new source lists', fnv(old_list) != fnv(ids))
check('cache name is deterministic', fnv(ids) == fnv(list(ids)))
check('Swift cache-name text pinned', 'cacheFileName(for sources' in cfg and '0xcbf29ce484222325' in cfg and '0x100000001b3' in cfg and '"archive_cache-" + String(h, radix: 16) + ".json"' in cfg)
check('library uses the keyed name', 'ArchiveConfig.cacheFileName(for: ArchiveConfig.spreadsheetSources)' in lib)
check('library deletes other archive_cache*.json', 'f.hasPrefix("archive_cache") && f.hasSuffix(".json") && f != name' in lib and 'removeItem' in lib)
# model of the startup: delete every cache file but the current one, then read
files = {'archive_cache.json', fnv(old_list), 'other.json'}
cur = fnv(ids); kept = {f for f in files if not (f.startswith('archive_cache') and f.endswith('.json') and f != cur)}
check('model: old snapshots removed, unrelated files kept, current absent -> first-run fetch', kept == {'other.json'})
# model: a refresh replaces titles wholesale (no merge with cache)
check('refresh replaces titles with the network result (no union with cache)', 'self.titles = result' in lib and 'titles + result' not in lib)
# mutant: keeping the removed source must fail the single-source check
mut = re.findall(r'\("([^"]+)", "([^"]*)", "([^"]*)"\)', '("%s", "0", ""), ("1-O2ajewvMSrs6L8N3uMjDp53jcHz5klLvOSv9wndRaA", "576490957", "")' % removed)
check('mutant (old source kept) is caught', len(mut) != 1)
print('archive sources: %d failure(s)' % len(fails)); sys.exit(1 if fails else 0)
