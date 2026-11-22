"""Background driver for 190u Prepare film: what the gor app calls on 3D open.

Usage (app side, low-priority thread / nice>0):
    from prepare_driver import run_prepare
    run_prepare(video_path, fps=fps, n_frames=n_frames,
                vda_ckpt=..., moge_ckpt=..., should_stop=lambda: app_closed)
    # cache_root defaults to cache.DEFAULT_CACHE_ROOT (H-K DepthCachePaths).

Loops work_chunk until the film is fully prepared or should_stop() says the
film was closed / 3D toggled off. Resumable across launches via the cache.
Prints one status line per chunk for logs; the OSD reads progress.json.
"""
import os

import cache as cache_mod
import prepare_film


def run_prepare(video_path, cache_root=None, fps=0.0, n_frames=0, vda_ckpt=None, moge_ckpt=None,
                should_stop=lambda: False, input_size=518, chunk_seconds=20.0,
                on_status=None):
    # cache_root defaults to the FIXED gor cache root shared with the H-K
    # lane's DepthCachePaths (Swift bb2dc675): ~/Library/Application Support/gor/depth-cache
    if cache_root is None:
        cache_root = cache_mod.DEFAULT_CACHE_ROOT
    if not fps:
        raise ValueError("fps is required")
    cache = cache_mod.Cache(cache_root)
    pf = prepare_film.PrepareFilm(cache, vda_ckpt, input_size=input_size,
                                  chunk_seconds=chunk_seconds,
                                  moge_checkpoint=moge_ckpt)
    shots = pf.open_film(video_path, fps, n_frames)
    done = 0
    while done < len(shots) and not should_stop():
        done, total = pf.work_chunk(video_path, shots, fps=fps)
        ranges, prepared, n, txt = pf.status(video_path, n_frames)
        if on_status:
            on_status(txt)
    return pf.status(video_path, n_frames)


if __name__ == "__main__":
    import sys
    vp, root, fps, nf = sys.argv[1], sys.argv[2], float(sys.argv[3]), int(sys.argv[4])
    models = os.environ.get("S4_MODELS", os.path.expanduser("~/s4/models"))
    run_prepare(vp, root, fps, nf,
                os.path.join(models, "video_depth_anything_vits.pth"),
                os.path.join(models, "moge2_vits_normal.pt"),
                on_status=print)
