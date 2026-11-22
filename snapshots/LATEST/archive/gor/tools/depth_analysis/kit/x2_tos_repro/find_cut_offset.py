import subprocess, numpy as np, sys
W,H = 320,180
# T2 png: SBS 640x180, left half = left eye (warped input)
raw = subprocess.run(["ffmpeg","-v","error","-i","/tmp/photon-check/archive/gor/tools/depth_analysis/kit/x2_tos_reference/tos_t2_mlbw_l2_inpaint_image.png","-f","rawvideo","-pix_fmt","gray","-"],capture_output=True,check=True).stdout
t2 = np.frombuffer(raw,np.uint8).reshape(180,640)[:, :320].astype(np.float32)
t2 = (t2 - t2.mean()) / (t2.std() + 1e-9)
# interior crop to reduce warp-edge influence
c0,c1 = 40,280
t2c = t2[:, c0:c1]
tf = np.fft.rfft2(t2c)
p = subprocess.Popen(["ffmpeg","-v","error","-i","tos_720p.mov","-vf","scale=320:180","-f","rawvideo","-pix_fmt","gray","-"],stdout=subprocess.PIPE)
fsz = W*H
best = (-2, -1, 0)
n = 0
while True:
    buf = p.stdout.read(fsz)
    if len(buf) < fsz: break
    f = np.frombuffer(buf,np.uint8).reshape(H,W).astype(np.float32)
    f = (f - f.mean())/(f.std()+1e-9)
    fc = f[:, c0:c1]
    # normalized cross-correlation via FFT over vertical shift too (small)
    corr = np.fft.irfft2(np.fft.rfft2(fc) * np.conj(tf), s=fc.shape)
    v = corr.max() / fc.size
    if v > best[0]: best = (v, n, int(np.unravel_index(corr.argmax(), corr.shape)[1]))
    n += 1
    if n % 2000 == 0: print(f"{n} frames, best so far {best}", flush=True)
p.stdout.close(); p.wait()
print("TOTAL", n, "BEST", best)
