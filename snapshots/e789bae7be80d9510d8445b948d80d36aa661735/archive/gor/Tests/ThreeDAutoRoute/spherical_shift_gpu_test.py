#!/usr/bin/env python3
"""Native camera-ray oracle;194h rotating optical centres have their own GPU gate.
193b ray-only full-pair oracle is superseded by owner November12 00:41 report.
Camera ray must remain identical when interocular axis is neutral.
"""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
f = root / 'Tests/ThreeDAutoRoute/engine193b_gpu_test.py'
# The native section includes generated-hook identity and 28 exact pixel comparisons.
# Do not execute the separate flat/applier tests a second time here.
exec(compile(f.read_text().split('# Flat engines retain', 1)[0], str(f), 'exec'))

# Negative control: restore the withdrawn flat-pair transform only inside the
# native hook. The frame oracle must detect the resulting native geometry loss.
mutant = current.replace('    eye_uv=surface_uv(eye_uv,actual_size);',
    '    eye_uv=surface_uv(eye_uv,actual_size);\n'
    '    eye_uv=stereo_pair_uv(eye_uv,is_right_eye,out_size.x*left_end/out_size.y,vec2(1.0));', 1)
assert mutant != current
for extended in (False, True):
    good = program(generated(current, extended))
    bad = program(generated(mutant, extended))
    values = dict(vr_roll=math.radians(30), vr_head_roll=math.radians(30),
        vr_yaw=.13, vr_pitch=-.08, vr_fov=math.radians(119), vr_flat_sbs=0,
        vr_flat_mono=0, vr_pack=0, vr_source_layout=3, vr_native_tb=0)
    changed = int(np.any(draw(good, values) != draw(bad, values), axis=2).sum())
    assert changed > 0, ('native flat-pair mutant escaped frame oracle', extended)
    print('PASS native flat-pair negative control', 'extended' if extended else 'legacy', 'changed pixels', changed)
