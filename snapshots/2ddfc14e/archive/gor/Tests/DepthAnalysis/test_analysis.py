import os, subprocess, sys, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "tools", "depth_analysis"))
import cache, cuts

def test_cache_key_stable_and_sensitive(tmp_path=None):
    d = tempfile.mkdtemp()
    p = os.path.join(d, "f.bin")
    open(p, "wb").write(b"x" * (3 * 1024 * 1024))
    k1 = cache.cache_key(p)
    assert k1 == cache.cache_key(p), "key not stable"
    with open(p, "r+b") as f:
        f.seek(2 * 1024 * 1024); f.write(b"DIFFERENT")
    assert k1 != cache.cache_key(p), "key did not change with content"
    print("PASS key stable + content-sensitive")

def test_prepare_resume_merge():
    d = tempfile.mkdtemp()
    p = os.path.join(d, "f.bin"); open(p, "wb").write(b"y" * 100)
    c = cache.Cache(os.path.join(d, "cache"))
    e = c.entry(p, create=True)
    e.mark_prepared(0, 99); e.mark_prepared(100, 199)  # adjacent -> merge
    e.mark_prepared(500, 599)
    e.mark_prepared(150, 170)                          # subset -> idempotent
    assert e.prepared_ranges() == [[0, 199], [500, 599]], e.prepared_ranges()
    assert e.is_prepared(150) and not e.is_prepared(300)
    # resume across relaunch: new Cache object over same root sees the state
    e2 = cache.Cache(os.path.join(d, "cache")).entry(p)
    assert e2.prepared_ranges() == [[0, 199], [500, 599]], "resume lost state"
    print("PASS prepare/resume/merge")

def test_eviction_only_marker_dirs():
    d = tempfile.mkdtemp()
    root = os.path.join(d, "cache")
    c = cache.Cache(root, cap_bytes=2000)
    # foreign dir without marker must survive
    foreign = os.path.join(root, "foreign"); os.makedirs(foreign)
    open(os.path.join(foreign, "keep.txt"), "w").write("do not delete")
    for i in range(3):
        p = os.path.join(d, f"f{i}.bin"); open(p, "wb").write(bytes([i]) * 100)
        e = c.entry(p, create=True)
        e.mark_prepared(0, 10)
        open(e.path("depth.hevc"), "wb").write(b"d" * 1500)
        os.utime(e.dir, (i, i))  # oldest first: f0, f1, f2
    evicted = c.evict_to_fit()
    assert os.path.exists(os.path.join(foreign, "keep.txt")), "foreign dir deleted!"
    assert len(evicted) >= 1, "no eviction happened"
    assert any("f0" not in e or True for e in evicted)
    assert not os.path.exists(os.path.join(root, cache.cache_key(os.path.join(d, 'f0.bin')))), "oldest not evicted first"
    print("PASS eviction (marker-only, oldest first)")

def test_cuts_on_synthetic_video():
    d = tempfile.mkdtemp()
    v = os.path.join(d, "t.mp4")
    # 2s red, 2s noise, 2s green at 10 fps: cuts at frames 20 and 40
    subprocess.run(["ffmpeg", "-y", "-v", "error",
                    "-f", "lavfi", "-i", "color=c=red:s=320x240:r=10:d=2",
                    "-f", "lavfi", "-i", "nullsrc=s=320x240:r=10:d=2,noise=alls=80:allf=t",
                    "-f", "lavfi", "-i", "color=c=green:s=320x240:r=10:d=2",
                    "-filter_complex", "[0:v][1:v][2:v]concat=n=3:v=1",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", v], check=True)
    got = cuts.detect_cuts(v, fps=10)
    assert got == [20, 40], f"cuts {got} != [20, 40]"
    shots = cuts.shots_from_cuts(60, got)
    assert shots == [(0, 19), (20, 39), (40, 59)], shots
    print("PASS cut detection + shot ranges")

if __name__ == "__main__":
    test_cache_key_stable_and_sensitive()
    test_prepare_resume_merge()
    test_eviction_only_marker_dirs()
    test_cuts_on_synthetic_video()
    print("ALL ANALYSIS TESTS PASS")
