"""Read bounded numeric playback-cost evidence. Never emit paths/process args."""
from pathlib import Path
import re
import datetime
import sys

PATTERN = re.compile(r'playback-cost gor=([0-9.]+) mpv=([0-9.]+) ffmpeg=([0-9.]+) ffmpegWorkers=([0-9]+) sampleEvery_s=10 metric=ps_cpu_percent')
THERMAL = re.compile(r'\[thermal-diag\].*?hwdec-current=([A-Za-z0-9_.+-]+).*?drop=([0-9.]+|unavailable).*?delayed=([0-9.]+|unavailable).*?mistimed=([0-9.]+|unavailable)')

def extract(text):
    lines = []
    for line in text.splitlines():
        match = PATTERN.search(line)
        if match:
            lines.append('playback-cost gor=%s mpv=%s ffmpeg=%s ffmpegWorkers=%s sampleEvery_s=10 metric=ps_cpu_percent' % match.groups())
        thermal = THERMAL.search(line)
        if thermal:
            lines.append('playback-decode hwdec-current=%s drop=%s delayed=%s mistimed=%s' % thermal.groups())
        stamp = re.match(r'(\d{2}:\d{2}:\d{2}) ', line)
        if (match or thermal) and stamp:
            lines[-1] = stamp[1] + ' ' + lines[-1]
        thread = re.search(r'thread-cpu: win=([0-9.]+)s threads=([0-9]+) total=([0-9.]+)%', line)
        busy = re.search(r'main-thread: win=([0-9.]+)s busy=([0-9.]+)% loops=([0-9]+)', line)
        if thread: lines.append((stamp[1]+' ' if stamp else '')+'thread-cost win_s=%s threads=%s total_pct=%s' % thread.groups())
        if busy: lines.append((stamp[1]+' ' if stamp else '')+'main-cost win_s=%s busy_pct=%s loops=%s' % busy.groups())
        if 'gor-sample[' in line:
            categories = [name for name in ['StretchGlyph', 'CoreText', 'AppKit', 'cacheDisplay'] if name in line]
            if categories: lines.append((stamp[1]+' ' if stamp else '')+'glyph-sample categories=' + ','.join(categories))
    return lines[-24:]


CACHE = re.compile(r'\[playback-cache\] utc_ms=(\d+) position_s=([-0-9.]+) cache_s=([0-9.]+) paused_for_cache=(-?\d+)')
def correlate(text):
    caches = [tuple(float(v) for v in m.groups()) for m in CACHE.finditer(text)]
    rows = []
    for line in text.splitlines():
        if 'Audio device underrun detected.' not in line: continue
        stamp = re.search(r'ts=(\d{4}-\d\d-\d\dT[0-9:.]+Z)', line)
        if not stamp: continue
        at = datetime.datetime.fromisoformat(stamp[1].replace('Z','+00:00')).timestamp()*1000
        prior = [c for c in caches if 0 <= at-c[0] <= 3000]
        if prior:
            c = max(prior, key=lambda c:c[0])
            rows.append('underrun utc=%s cache_s=%.3f cache_age_ms=%.0f paused_for_cache=%d position_s=%.3f' % (stamp[1], c[2], at-c[0], c[3], c[1]))
        else: rows.append('underrun utc=%s cache=unavailable-within-prior3s' % stamp[1])
    return rows[-12:]

if __name__ == '__main__':
    root = Path(sys.argv[1])
    output = []; evidence = []
    sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'tools'))
    from session_log_paths import resolve
    for path in [resolve('/tmp/gor_diag.log'),resolve('/tmp/gor_direct.log')]:
        try:
            with path.open('rb') as stream:
                stream.seek(max(0, path.stat().st_size - 131072))
                text=stream.read(131072).decode('utf-8', 'replace'); evidence.append(text)
                output.extend(extract(text))
        except OSError:
            pass
    print('BEGIN numeric playback cost (bounded; OS CPU percent, not GPU frame time)')
    print('\n'.join(output[-24:]) if output else 'NOT_RUN no playback cost samples available')
    print('END numeric playback cost')

    print('BEGIN numeric cache/underrun correlation (prior cache sample within3s, not a cause verdict)')
    print('\n'.join(correlate('\n'.join(evidence))) or 'NOT_RUN no timestamped underrun available')
    print('END numeric cache/underrun correlation')
