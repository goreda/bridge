#!/usr/bin/env python3
"""Deterministic generated pixels for 191c roll measurements, not rendered evidence.

Standard-library only. See README.md for the coordinate and manifest contract.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import zlib

SCHEMA = 'roll-markers/v1'
MODES = ('sbs', 'half_sbs', 'top_bottom', 'mono', 'native_vr180')
DISPARITIES = (-0.02, 0.0, 0.02)
PALETTE = ((255, 96, 96), (96, 255, 96), (96, 144, 255),
           (255, 240, 96), (255, 96, 255), (96, 255, 255),
           (255, 176, 96), (176, 96, 255), (176, 255, 176))
SOURCE = {
    'repository': 'zuellue/gorav-native-ci',
    'commit': '2ca10de8ab767d8a24d8c3f4b481e5d6984701e0',
    'path': 'payload/gor/Resources/vendor/mpv/scripts/vr180-look.lua',
    'verification': 'not performed by generator; capture runner must bind actual bytes',
}


def canonical(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n').encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def png_rgb(width, height, pixels):
    """PNG with explicitly specified stored DEFLATE blocks, stable across zlib versions."""
    if len(pixels) != width * height * 3:
        raise ValueError('RGB pixel length mismatch')
    raw = b''.join(b'\0' + pixels[y * width * 3:(y + 1) * width * 3]
                   for y in range(height))
    compressed = bytearray(b'\x78\x01')
    for start in range(0, len(raw), 65535):
        block = raw[start:start + 65535]
        compressed.append(int(start + len(block) == len(raw)))
        compressed.extend(struct.pack('<HH', len(block), 65535 - len(block)))
        compressed.extend(block)
    compressed.extend(struct.pack('>I', zlib.adler32(raw) & 0xffffffff))

    def chunk(kind, data):
        return (struct.pack('>I', len(data)) + kind + data +
                struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff))
    return (b'\x89PNG\r\n\x1a\n' +
            chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', bytes(compressed)) + chunk(b'IEND', b''))


def geometry(mode, eye_width, eye_height):
    if mode not in MODES:
        raise ValueError('unknown mode')
    if mode == 'half_sbs':
        if eye_width % 2:
            raise ValueError('half-SBS needs an even logical eye width')
        w, h = eye_width // 2, eye_height
    else:
        w, h = eye_width, eye_height
    if mode == 'top_bottom':
        return w, 2 * h, {'left': [0, 0, w, h], 'right': [0, h, w, h]}
    if mode == 'mono':
        return w, h, {'mono': [0, 0, w, h]}
    return 2 * w, h, {'left': [0, 0, w, h], 'right': [w, 0, w, h]}


def eye_to_pixel(rect, uv):
    """Image coordinates are pixel-centre indices: top-left centre = (0,0)."""
    x, y, w, h = rect
    return [x + uv[0] * w - 0.5, y + uv[1] * h - 0.5]


def rectangle_coverage(px, py, cx, cy, rx, ry):
    return (max(0.0, min(px + 0.5, cx + rx) - max(px - 0.5, cx - rx)) *
            max(0.0, min(py + 0.5, cy + ry) - max(py - 0.5, cy - ry)))


def cross_coverage(px, py, cx, cy, rx, ry, tx, ty):
    return (rectangle_coverage(px, py, cx, cy, tx, ry) +
            rectangle_coverage(px, py, cx, cy, rx, ty) -
            rectangle_coverage(px, py, cx, cy, tx, ty))


def marker_patch(cx, cy, rx, ry, color):
    # Box-filtered analytic rectangles preserve fractional marker centres.
    x0, y0 = math.floor(cx - rx - 1), math.floor(cy - ry - 1)
    x1, y1 = math.ceil(cx + rx + 1), math.ceil(cy + ry + 1)
    width, height = x1 - x0 + 1, y1 - y0 + 1
    out = bytearray(width * height * 3)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            outer = cross_coverage(x, y, cx, cy, rx, ry, rx * 0.28, ry * 0.28)
            inner = cross_coverage(x, y, cx, cy, rx * 0.72, ry * 0.72,
                                   rx * 0.12, ry * 0.12)
            for c in range(3):
                value = 12 + (color[c] - 12) * outer + (255 - color[c]) * inner
                out[((y-y0) * width + x-x0) * 3+c] = min(255, max(0, int(value + 0.5)))
    return [x0, y0, width, height], bytes(out)


def validate(eye_width, eye_height, marker_radius):
    if (isinstance(eye_width, bool) or isinstance(eye_height, bool) or
            not isinstance(eye_width, int) or not isinstance(eye_height, int)):
        raise ValueError('eye dimensions must be integers')
    if eye_width < 200 or eye_height < 120 or eye_width > 8192 or eye_height > 8192:
        raise ValueError('eye size outside supported range 200x120 through 8192x8192')
    if not math.isfinite(marker_radius) or marker_radius < 8:
        raise ValueError('marker radius must be finite and at least 8 logical pixels')
    if eye_width % 2:
        raise ValueError('eye width must be even for half-SBS')
    if eye_width * eye_height > 18000000:
        raise ValueError('eye area exceeds allocation limit')


def generate(output, eye_width=1280, eye_height=720, marker_radius=12.0, modes=MODES):
    validate(eye_width, eye_height, marker_radius)
    if not modes or len(set(modes)) != len(modes) or any(m not in MODES for m in modes):
        raise ValueError('modes must be a nonempty unique subset of supported modes')
    # Validate all geometry before creating files.
    for mode in modes:
        width, height, rects = geometry(mode, eye_width, eye_height)
        rw, rh = next(iter(rects.values()))[2:]
        rx, ry = marker_radius * rw / eye_width, marker_radius
        if rx < 4 or ry < 4:
            raise ValueError('unresolvable marker after packing')
        if 2 * (rx + 2) >= 0.3 * rw or 2 * (ry + 2) >= 0.3 * rh:
            raise ValueError('marker patches overlap')
        if rx + 2 >= 0.18 * rw or ry + 2 >= 0.2 * rh:
            raise ValueError('marker patch crosses an eye boundary')
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    manifest = {
        'schema': SCHEMA, 'generator': 'generate_roll_markers.py/v1',
        'evidence': 'synthetic generated source pixels, not mpv captures',
        'source_under_test': SOURCE,
        'coordinate_convention': {
            'eye_uv': 'u increases right, v increases down, range [0,1]',
            'source_pixel_xy': 'pixel-centre indices, origin top-left; x=u*w-0.5+offset_x, y=v*h-0.5+offset_y',
            'disparity': 'right.u-left.u, in fractions of logical eye width; left unshifted',
            'screen_xy': 'not provided; source pixels are not rendered screen positions',
            'native_vr180': 'SBS equirectangular hemispheres; longitude_deg=180*(u-0.5), latitude_deg=180*(0.5-v); source mapping only, not a production geometry verdict',
            'mono': 'one source image, no baked stereo disparity; right eye is synthesized by production d3, not asserted here',
        },
        'logical_eye_dimensions': [eye_width, eye_height],
        'background_rgb': [12, 12, 12],
        'fixtures': [],
    }
    for mode in modes:
        width, height, rects = geometry(mode, eye_width, eye_height)
        disparities = (0.0,) if mode == 'mono' else DISPARITIES
        for disparity in disparities:
            suffix = {-0.02: 'neg02', 0.0: 'zero', 0.02: 'pos02'}[disparity]
            fixture_id = mode + '_' + suffix
            pixels = bytearray(bytes((12, 12, 12)) * width * height)
            markers = []
            for row, v in enumerate((0.2, 0.5, 0.8)):
                for col, u in enumerate((0.2, 0.5, 0.8)):
                    marker_id = 'r%dc%d' % (row, col)
                    color = PALETTE[row * 3 + col]
                    positions = {}
                    for eye, rect in rects.items():
                        uv = [round(u + (disparity if eye == 'right' else 0.0), 12), v]
                        xy = eye_to_pixel(rect, uv)
                        rx = marker_radius * rect[2] / eye_width
                        bbox, patch = marker_patch(*xy, rx, marker_radius, color)
                        x0, y0, pw, ph = bbox
                        for py in range(ph):
                            start = ((y0 + py) * width + x0) * 3
                            pixels[start:start + pw * 3] = patch[py * pw * 3:(py + 1) * pw * 3]
                        template_path = 'templates/%s_%s_%s.png' % (fixture_id, marker_id, eye)
                        data = png_rgb(pw, ph, patch)
                        (output / 'templates').mkdir(exist_ok=True)
                        (output / template_path).write_bytes(data)
                        positions[eye] = {
                            'eye_uv': uv, 'source_pixel_xy': xy,
                            'bbox_xywh': bbox, 'template_path': template_path,
                            'template_sha256': digest(data),
                        }
                        if mode == 'native_vr180':
                            positions[eye]['longitude_latitude_deg'] = [180*(uv[0]-.5), 180*(.5-uv[1])]
                    markers.append({'id': marker_id, 'pair_id': fixture_id + ':' + marker_id,
                                    'grid_rc': [row, col], 'base_eye_uv': [u, v],
                                    'disparity_fraction': disparity, 'identity_rgb': list(color),
                                    'positions': positions})
            data = png_rgb(width, height, pixels)
            image_path = fixture_id + '.png'
            (output / image_path).write_bytes(data)
            manifest['fixtures'].append({
                'id': fixture_id, 'mode': mode, 'path': image_path,
                'width': width, 'height': height, 'sha256': digest(data),
                'pixel_rgb_sha256': digest(pixels), 'eyes': rects,
                'sample_aspect_ratio': [2, 1] if mode == 'half_sbs' else [1, 1],
                'logical_eye_dimensions': [eye_width, eye_height],
                'signed_disparity_fraction': disparity,
                'baked_stereo': mode != 'mono', 'markers': markers,
            })
    (output / 'manifest.json').write_bytes(canonical(manifest))
    return manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--eye-width', type=int, default=1280)
    parser.add_argument('--eye-height', type=int, default=720)
    parser.add_argument('--marker-radius', type=float, default=12)
    parser.add_argument('--modes', nargs='+', choices=MODES, default=list(MODES))
    args = parser.parse_args(argv)
    try:
        result = generate(args.output, args.eye_width, args.eye_height,
                          args.marker_radius, args.modes)
    except (ValueError, OSError) as exc:
        print('generator_error: ' + str(exc), file=sys.stderr)
        return 2
    print(json.dumps({'manifest': str(args.output / 'manifest.json'),
                      'fixtures': len(result['fixtures']),
                      'manifest_sha256': digest(canonical(result))}, sort_keys=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
