"""190t A + 190u: per-file analysis cache with prepare-mode resume and eviction.

Layout under <root>/<key>/:
  .gor-cache-entry        marker: we created this dir (only such dirs are ever evicted)
  meta.json               model sha256s, tier, analysis params, created/updated times
  progress.json           {"prepared": [[first, last], ...]}  frame ranges with Tier-1 depth cached
  cuts.json               cut frame list
  depth_shot_NNNNN.mp4    per-shot 10-bit HEVC lossless depth, Main 10 4:2:0 (depth on luma,
                          neutral chroma; VT/AVFoundation-decodable), PTS film time
  depth_shot_NNNNN.json   per-shot sidecar: start/end, input_size, depth_width/height, align_scale/shift
  fov_track.json          per-shot FoV degrees + confidence
  scale_track.json        per-shot scale/shift fit vs MoGe-2 metric

190u: Prepare-film writes progress.json incrementally so a relaunch resumes where it
stopped. Playback asks prepared_ranges()/is_prepared(frame): inside prepared range is
always Tier 1; auto-tier applies only outside it.
"""
import hashlib, json, os, time
# Fixed cache root, shared with the H-K lane's DepthCachePaths (Swift,
# bb2dc675). PrepareFilm gets it injected; this is the default.
DEFAULT_CACHE_ROOT = os.path.expanduser("~/Library/Application Support/gor/depth-cache")


MARKER = ".gor-cache-entry"

def cache_key(path):
    """sha256 over size+mtime+first/last 1MB. No full-file read on open."""
    st = os.stat(path)
    h = hashlib.sha256()
    h.update(f"{st.st_size}:{st.st_mtime_ns}".encode())
    with open(path, "rb") as f:
        h.update(f.read(1024 * 1024))
        if st.st_size > 2 * 1024 * 1024:
            f.seek(st.st_size - 1024 * 1024)
            h.update(f.read(1024 * 1024))
    return h.hexdigest()

class CacheEntry:
    def __init__(self, root, key, create=False):
        self.dir = os.path.join(root, key)
        if create:
            os.makedirs(self.dir, exist_ok=True)
            open(os.path.join(self.dir, MARKER), "a").close()
    def path(self, name):
        return os.path.join(self.dir, name)
    def _read(self, name, default):
        p = self.path(name)
        if not os.path.exists(p):
            return default
        with open(p) as f:
            return json.load(f)
    def _write(self, name, obj):
        tmp = self.path(name + ".tmp")
        with open(tmp, "w") as f:
            json.dump(obj, f)
        os.replace(tmp, self.path(name))  # atomic: a killed prepare never corrupts state
    def touch_meta(self, **fields):
        m = self._read("meta.json", {})
        m.update(fields); m["updated"] = time.time()
        m.setdefault("created", m["updated"])
        self._write("meta.json", m)
    def prepared_ranges(self):
        return self._read("progress.json", {"prepared": []})["prepared"]
    def is_prepared(self, frame):
        return any(a <= frame <= b for a, b in self.prepared_ranges())
    def mark_prepared(self, first, last):
        """Merge [first,last] into prepared ranges (idempotent, resume-safe)."""
        rs = sorted(self.prepared_ranges() + [[first, last]])
        merged = []
        for a, b in rs:
            if merged and a <= merged[-1][1] + 1:
                merged[-1][1] = max(merged[-1][1], b)
            else:
                merged.append([a, b])
        self._write("progress.json", {"prepared": merged})
        return merged

class Cache:
    def __init__(self, root, cap_bytes=2 * 1024**3):
        self.root = root; self.cap = cap_bytes
        os.makedirs(root, exist_ok=True)
    def entry(self, video_path, create=False):
        return CacheEntry(self.root, cache_key(video_path), create)
    def _entries(self):
        for k in os.listdir(self.root):
            d = os.path.join(self.root, k)
            if os.path.isdir(d) and os.path.exists(os.path.join(d, MARKER)):
                yield d
    def _size(self, d):
        t = 0
        for base, _, files in os.walk(d):
            for f in files:
                t += os.path.getsize(os.path.join(base, f))
        return t
    def evict_to_fit(self):
        """Evict oldest-touched entries until under cap. Only marker dirs are touched."""
        entries = [(self._size(d), os.path.getmtime(d), d) for d in self._entries()]
        total = sum(s for s, _, _ in entries)
        evicted = []
        for s, _, d in sorted(entries, key=lambda e: e[1]):
            if total <= self.cap:
                break
            for base, dirs, files in os.walk(d, topdown=False):
                for f in files:
                    os.remove(os.path.join(base, f))
                for sub in dirs:
                    os.rmdir(os.path.join(base, sub))
            os.rmdir(d)
            total -= s; evicted.append(d)
        return evicted
