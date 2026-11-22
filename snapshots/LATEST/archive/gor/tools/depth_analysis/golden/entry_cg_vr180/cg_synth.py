"""Synthetic VR180-lane CG sample: pinhole render, exact geometry (stall
class), camera dolly. Writes /tmp/benchcg/slice.mp4 (640x360, 48f, 24fps)."""
import numpy as np
import subprocess

H, W, T, FPS = 360, 640, 48, 24
HFOV = 60.0

# scene: floor y=-1.2, back wall z=9, three spheres
SPHERES = [((-1.6, -0.3, 4.0), 0.9, (235, 80, 70)),
           ((0.4, 0.1, 5.5), 1.1, (80, 200, 120)),
           ((1.8, -0.5, 3.2), 0.7, (90, 120, 235))]


def render(cam_z, seed_light):
    fy = 0.5 * H / np.tan(np.radians(HFOV) / 2) * (W / H) ** 0  # vertical f from hfov
    fx = 0.5 * W / np.tan(np.radians(HFOV) / 2)
    fy = fx  # square pixels
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float64)
    dx = (xx - W / 2) / fx
    dy = -(yy - H / 2) / fy
    dz = np.ones_like(dx)
    n = np.sqrt(dx * dx + dy * dy + 1.0)
    dx, dy, dz = dx / n, dy / n, dz / n
    ro = np.array([0.0, 0.0, cam_z])
    zbuf = np.full((H, W), np.inf)
    img = np.zeros((H, W, 3), np.uint8)
    img[:] = (18, 20, 26)
    L = np.array([0.4, 0.8, 0.45]); L = L / np.linalg.norm(L)
    # back wall z = 9 + cam_z? wall fixed at z=9 world
    tw = (9.0 - ro[2]) / dz
    hitw = (tw > 0)
    # wall texture: checker
    wx = ro[0] + dx * tw; wy = ro[1] + dy * tw
    check = ((np.floor(wx * 1.2) + np.floor(wy * 1.2)) % 2).astype(np.uint8)
    wall_col = np.where(check[..., None], np.array([200, 190, 170]), np.array([120, 130, 150])).astype(np.float64)
    lam = np.clip(0.35 + 0.65 * L[2], 0, 1)
    img[hitw] = (wall_col[hitw] * lam).astype(np.uint8)
    zbuf = np.where(hitw, tw, zbuf)
    # floor y = -1.2
    tf = (-1.2 - ro[1]) / np.where(dy < -1e-9, dy, -1e-9)
    hitf = (tf > 0) & (tf < zbuf)
    fx_ = ro[0] + dx * tf; fz_ = ro[2] + dz * tf
    fcheck = ((np.floor(fx_) + np.floor(fz_)) % 2).astype(np.uint8)
    fcol = np.where(fcheck[..., None], np.array([90, 85, 80]), np.array([60, 62, 68])).astype(np.float64)
    img[hitf] = (fcol[hitf] * 0.9).astype(np.uint8)
    zbuf = np.where(hitf, tf, zbuf)
    for (c, r, col) in SPHERES:
        oc = ro - np.array(c)
        b = 2 * (dx * oc[0] + dy * oc[1] + dz * oc[2])
        cc = (oc * oc).sum() - r * r
        disc = b * b - 4 * cc
        hit = disc > 0
        t = (-b - np.sqrt(np.maximum(disc, 0))) / 2
        hit &= (t > 0) & (t < zbuf)
        px = ro[0] + dx * t - c[0]; py = ro[1] + dy * t - c[1]; pz = ro[2] + dz * t - c[2]
        nl = (dx * px + dy * py + dz * pz)  # n dot (-L)? compute properly
        nn = np.stack([px, py, pz], -1) / r
        lam = np.clip((nn * L).sum(-1), 0, 1) * 0.85 + 0.15
        img[hit] = (np.array(col) * lam[hit][:, None]).astype(np.uint8)
        zbuf = np.where(hit, t, zbuf)
    # subtle deterministic texture noise so encoders/models see real signal
    rng = np.random.default_rng(seed_light)
    noise = rng.integers(-3, 4, img.shape)
    img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    # world z per pixel = zbuf * dz_component? ray param t IS euclidean distance;
    # camera-space z = t * dz
    z = np.where(np.isfinite(zbuf), zbuf * dz, 0.0)  # 0 = sky (none here, but keep semantics)
    return img, z.astype(np.float32)


def main():
    import os
    os.makedirs("/tmp/benchcg", exist_ok=True)
    proc = subprocess.Popen(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo",
                             "-s", f"{W}x{H}", "-pix_fmt", "rgb24",
                             "-framerate", str(FPS), "-i", "-",
                             "-c:v", "libx264", "-preset", "veryfast",
                             "-crf", "18", "-pix_fmt", "yuv420p",
                             "/tmp/benchcg/slice.mp4"], stdin=subprocess.PIPE)
    zs = []
    for i in range(T):
        img, z = render(i * 0.025, 1000 + i)  # 1.2 m dolly over 48 f
        proc.stdin.write(img.tobytes())
        zs.append(z)
    proc.stdin.close(); proc.wait()
    np.save("/tmp/benchcg/z_true.npy", np.stack(zs).astype(np.float16))
    print("wrote /tmp/benchcg/slice.mp4 + z_true.npy", zs[0].shape)


if __name__ == "__main__":
    main()
