#!/usr/bin/env python3
"""World-fixed flat-film horizon invariant from actual generated shader angles.

This is an interior affine orientation test, not a GLSL interpreter or render.
It reads partition and picture rotation signs from the generated extended/pack
flat branch, then composes their Jacobians with eye normalization and aspect
fit. Uniform zoom, pair fit, centre/convergence translations do not affect the
horizon tangent. The R4 interocular bound remains a separate, unchanged test.
"""
from pathlib import Path
import hashlib
import math
import re
import sys
import numpy as np
from test_generated_sources import generated_sources
from test_roll_r4 import CANDIDATE_SHA

PRE_FIX_SHA = '51151e58609f45f9d0b2a94bb73b68e902a767221862415b725cbc276f01bb45'


def block(text, marker):
    start = text.index(marker) + len(marker)
    depth = 1
    for i in range(start, len(text)):
        depth += (text[i] == '{') - (text[i] == '}')
        if depth == 0:
            return text[start:i]
    raise AssertionError('unbalanced shader fixture')


def angle_sign(expression, cross):
    # Deliberately closed vocabulary, not eval or permissive source guessing.
    if expression == '-vr_roll':
        return -1.0
    if expression == 'vr_roll*(vr_cross_eye>0.5?1.0:-1.0)':
        return 1.0 if cross else -1.0
    if expression == '-vr_roll*(vr_cross_eye>0.5?1.0:-1.0)':
        return -1.0 if cross else 1.0
    raise AssertionError('unrecognized production angle: ' + expression)


def source_angles(shader, cross):
    code = re.sub(r'/\*.*?\*/|//[^\n]*', '', shader, flags=re.S)
    code = re.sub(r'\s+', '', code)
    partition = block(code, 'vec2stereo_partition(vec2pos,floataspect){')
    partition_expression = re.search(r'floatangle=([^;]+);', partition).group(1)
    assert 'q=mat2(cos(angle),sin(angle),-sin(angle),cos(angle))*q;' in partition
    flat = block(code, 'if(vr_flat_sbs>0.5){')
    # Bind the transform ordering and the frame used by sampling and centres.
    stages = [
        'split_pos=stereo_partition(',
        '(split_pos.x-rs)/(1.0-rs):split_pos.x/le,split_pos.y)',
        'stereo_pair_uv(uv,right,viewport_aspect,content,0.0)',
        'uv=(uv-vec2(0.5))/(content*zoom);',
        'floatcr=cos(',
        'uv.x*=source_aspect;uv=mat2(cr,sr,-sr,cr)*uv;uv.x/=source_aspect;',
    ]
    locations = [flat.index(stage) for stage in stages]
    assert locations == sorted(locations), 'flat transform ordering changed'
    picture_expression, sine_expression = re.search(r'floatcr=cos\(([^()]*)\),sr=sin\(([^()]*)\);', flat).groups()
    assert picture_expression == sine_expression
    if picture_expression == 'eye_roll':
        picture_expression = re.search(r'floateye_roll=([^;]+);', flat).group(1)
    return angle_sign(partition_expression, cross), angle_sign(picture_expression, cross)


def rotation(theta):
    c, s = math.cos(theta), math.sin(theta)
    return np.array([[c, -s], [s, c]])


def check(source):
    sha = hashlib.sha256(source.read_bytes()).hexdigest()
    assert sha in {PRE_FIX_SHA, CANDIDATE_SHA}, ('source binding', sha)
    failures = []
    count = 0
    worst = 0.0
    # These are explicit positive vr_eye_aspect fixture uniforms. Half-SBS
    # restores its horizontal squeeze. TB is per-eye 1280/720, not the SBS-only
    # fallback applied to a 1280x1440 packed raster.
    modes = [('sbs', 1280 / 720), ('half', 1280 / 720),
             ('tb', 1280 / 720), ('mono', 1280 / 720)]
    for variant, shader in generated_sources(source).items():
        if variant == 'legacy':
            continue  # No flat-film branch in the legacy source.
        for cross in (False, True):
            partition_sign, picture_sign = source_angles(shader, cross)
            for width, height in ((2560, 1600), (1920, 1080), (1600, 2560)):
                le, rs = 0.5 - 0.0125 / 4, 0.5 + 0.0125 / 4
                for mode, aspect in modes:
                    for eye_width in (width * le, width * (1 - rs)):
                        viewport_aspect = eye_width / height
                        content = np.ones(2)
                        if aspect > viewport_aspect:
                            content[1] = viewport_aspect / aspect
                        else:
                            content[0] = aspect / viewport_aspect
                        for degrees in (-30, -15, -5, 0, 5, 15, 30):
                            theta = math.radians(degrees)
                            source_metric = np.diag([aspect, 1.0])
                            # d(source uv)/d(physical output pixel).
                            jacobian = (np.linalg.inv(source_metric)
                                        @ rotation(picture_sign * theta)
                                        @ source_metric @ np.diag(1 / content)
                                        @ np.diag([1 / eye_width, 1 / height])
                                        @ rotation(partition_sign * theta))
                            tangent = np.linalg.solve(jacobian, np.array([1.0, 0.0]))
                            error = abs(math.degrees(math.atan2(tangent[1], tangent[0])))
                            count += 1
                            worst = max(worst, error)
                            if error > 1e-9:
                                failures.append((variant, mode, degrees, cross, error))
    print('source', sha, 'orientation cases', count,
          'worst world-horizon error deg', format(worst, '.12g'))
    assert count == 672, count
    if failures:
        print('first failing case', failures[0], 'failing cases', len(failures))
        raise AssertionError('world-fixed horizon violated')
    print('PASS world-fixed flat-branch horizon, parallel/crossed +/-5/15/30 deg; pack_eye/GPU/pixels/mpv NOT_RUN')


if __name__ == '__main__':
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / 'Resources/vendor/mpv/scripts/vr180-look.lua'
    check(path)
