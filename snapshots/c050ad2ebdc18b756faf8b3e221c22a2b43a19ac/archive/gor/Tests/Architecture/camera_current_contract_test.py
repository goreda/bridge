#!/usr/bin/env python3
"""Run the actual current-source guards from three HeadPose harnesses.

This does not run their Swift programs. Two source mutants per guard group
must fail, so adapting renamed locals cannot silently drop their protection.
"""
from pathlib import Path
import ast
import importlib.util

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('current_camera_source', ROOT / 'Tests/Architecture/camera_source.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = module.read_source(ROOT / 'Sources/gor/GorCaptureModel/ScreenCaptureEngine.swift')


def guards(relative, text):
    tree = ast.parse((ROOT / relative).read_text())
    allowed = {'s', 'gate_start', 'gate_end', 'eye_gate'}
    statements = []
    for node in tree.body:
        names = {n.id for n in ast.walk(node) if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load)}
        if isinstance(node, ast.Assert) and names and names <= allowed:
            statements.append(node)
        elif isinstance(node, ast.Assign):
            targets = {n.id for target in node.targets for n in ast.walk(target) if isinstance(n, ast.Name)}
            if targets and targets <= allowed - {'s'} and names <= allowed:
                statements.append(node)
    assert len([n for n in statements if isinstance(n, ast.Assert)]) >= 4, relative
    code = compile(ast.fix_missing_locations(ast.Module(body=statements, type_ignores=[])), relative, 'exec')
    exec(code, {'s': text})


cases = (
    ('Tests/HeadPose/calibration_boundary_test.py', (
        ('if continuity.reacquire || !distanceReady', 'if false'),
        ('distanceReady=distanceConsistent && poseDistanceConsistency.ready(for:landmarkKind)', 'distanceReady=distanceConsistent'),
    )),
    ('Tests/HeadPose/distance_consistency_test.py', (
        ('distanceUsedPupils=distance.usedPupils', 'distanceUsedPupils=false'),
        ('distanceMode:distanceConsistent ?', 'distanceMode:true ?'),
    )),
    ('Tests/HeadPose/distance_orientation_test.py', (
        ('if let eyes=eyeApertures,!poseEyeGate.accept(eyes)', 'if let eyes=eyeApertures,poseEyeGate.accept(eyes)'),
        ('eyeHold:true', 'eyeHold:false'),
    )),
)
for relative, mutations in cases:
    guards(relative, source)
    for before, after in mutations:
        assert before in source, before
        bad = source.replace(before, after)
        try:
            guards(relative, bad)
        except (AssertionError, ValueError):
            pass
        else:
            raise AssertionError('source mutant survived: ' + relative)
    print('PASS actual source guards:', relative, 'current GREEN, 2 mutants RED')
print('PASS 3 current C1/ingestion source-guard groups; Swift/native runtime NOT_RUN')
