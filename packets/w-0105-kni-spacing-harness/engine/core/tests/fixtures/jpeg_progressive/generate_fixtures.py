# Regenerates the small progressive test fixtures (needs Pillow + numpy).
# For each case a baseline and a progressive JPEG are written from the SAME pixels,
# quality and subsampling, so both carry identical quantized coefficients.
import io, numpy as np
from PIL import Image
rng = np.random.default_rng(20261016)
def img_gray(w, h):
    y, x = np.mgrid[0:h, 0:w]
    a = (x * 255 // max(w - 1, 1) + y * 7) % 256
    a = a + rng.integers(-40, 40, (h, w))
    return Image.fromarray(np.clip(a, 0, 255).astype('uint8'), 'L')
def img_rgb(w, h):
    g = np.array(img_gray(w, h)).astype(int)
    rgb = np.stack([g, (255 - g) // 2 + rng.integers(0, 30, g.shape), (g * 3) % 256], -1)
    return Image.fromarray(np.clip(rgb, 0, 255).astype('uint8'), 'RGB')
cases = [
    ("gray_17x13", img_gray(17, 13), dict(quality=75)),
    ("gray_64x48_q95", img_gray(64, 48), dict(quality=95)),
    ("gray_1x1", img_gray(1, 1), dict(quality=90)),
    ("ycbcr_444_23x19", img_rgb(23, 19), dict(quality=80, subsampling=0)),
    ("ycbcr_420_35x27", img_rgb(35, 27), dict(quality=85, subsampling=2)),
    ("ycbcr_422_40x16", img_rgb(40, 16), dict(quality=70, subsampling=1)),
]
for name, im, kw in cases:
    for prog in (False, True):
        b = io.BytesIO(); im.save(b, 'JPEG', progressive=prog, **kw)
        open(f"{name}.{'prog' if prog else 'base'}.jpg", 'wb').write(b.getvalue())
# gray_grad_40x40 (smooth image, long EOB runs) comes from ImageMagick, not Pillow:
#   convert -size 40x40 gradient:white-black -interlace None -quality 80 gray_grad_40x40.base.jpg
#   convert -size 40x40 gradient:white-black -interlace JPEG -quality 80 gray_grad_40x40.prog.jpg
