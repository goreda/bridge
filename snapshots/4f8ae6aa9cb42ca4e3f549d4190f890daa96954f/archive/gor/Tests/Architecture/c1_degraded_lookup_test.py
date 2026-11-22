#!/usr/bin/env python3
"""C1 audit source-assembly proof only. No Swift/runtime/native result is implied."""
from pathlib import Path
import contextlib
import importlib.util
import io
import runpy
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
SCRIPT='Tests/HeadPose/degraded_input_audit_test.py'


def capture(root):
    saved_run,saved_output=subprocess.run,subprocess.check_output
    saved_path,saved_argv=sys.path[:],sys.argv[:]
    saved_modules={name:sys.modules.pop(name,None) for name in ('camera_source','c1_projection_audit')}
    groups=[]
    def compiler(args,*unused,**kwargs):
        assert '-o' in args,args
        inputs=[Path(arg).read_text() for arg in args if str(arg).endswith('.swift')]
        assert inputs,args
        groups.append(inputs)
        return subprocess.CompletedProcess(args,0)
    def runtime(args,*unused,**kwargs):
        assert len(args)==1 and Path(args[0]).name=='test',args
        return 'SWIFT_RUNTIME_NOT_EXECUTED\n'
    try:
        subprocess.run=compiler;subprocess.check_output=runtime
        sys.path.insert(0,str(root/'Tests/HeadPose'));sys.argv=[str(root/SCRIPT)]
        with contextlib.redirect_stdout(io.StringIO()):runpy.run_path(str(root/SCRIPT))
    finally:
        subprocess.run=saved_run;subprocess.check_output=saved_output
        sys.path[:]=saved_path;sys.argv[:]=saved_argv
        for name,value in saved_modules.items():
            sys.modules.pop(name,None)
            if value is not None:sys.modules[name]=value
    assert len(groups)==4,len(groups)
    return groups

def boundary(root):
    spec=importlib.util.spec_from_file_location('c1_boundary_source_test',root/'Tests/HeadPose/c1_projection_audit.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module.native_boundary_sources(root)


expected_boundary=boundary(ROOT)
expected=capture(ROOT)
with tempfile.TemporaryDirectory(prefix='c1-audit-lookup-') as directory:
    root=Path(directory)
    shutil.copytree(ROOT/'Sources',root/'Sources')
    for folder in ('Tests/HeadPose','Tests/Architecture','Tests/Structure'):
        shutil.copytree(ROOT/folder,root/folder,ignore=shutil.ignore_patterns('__pycache__'))
    spec=importlib.util.spec_from_file_location('c1_move_sections',root/'Tests/Structure/section_source.py')
    sections=importlib.util.module_from_spec(spec);spec.loader.exec_module(sections)
    names=('PoseContinuity','PoseMeasurementValidity','PoseFrameQuality','PupilDistanceScale','BuildID','CameraHelperEngine')
    paths={sections.symbol_decl(root,name)[0] for name in names}
    handlers=[path for path in sections.swift_files(root) if 'private func handleHelperFrame(' in path.read_text()]
    assert len(handlers)==1,handlers
    paths.add(handlers[0])
    carrier=root/'Sources/gor/C1AuditStation/Inputs.swift';carrier.parent.mkdir()
    text=''
    for path in sorted(paths):
        source=path.read_text();assert source.endswith('\n'),path
        text+='// MARK: - '+path.name+'\n'+source
        path.unlink()
    carrier.write_text(text)
    assert len(paths)==7 and all(not path.exists() for path in paths)
    assert capture(root)==expected,'C1 audit Swift inputs changed after retiring six literal source hosts'
    assert boundary(root)==expected_boundary,'Real boundary declaration/function bytes changed after relocation'
    print('PASS C1 source assembly: seven retired source hosts including native producer, four unchanged compiler-input groups, source guards and five mutants')
    changes=(
        ('producer scalar','fileprivate static func faceRect(','face.yaw?.doubleValue','face.yaw?.floatValue'),
        ('producer point coordinates','private static func pointList(_ region: VNFaceLandmarkRegion2D?)','Double($0.x)','Double($0.y)'),
        ('producer quality','fileprivate static func measureQuality(','mean: q.mean','mean: q.contrast'),
        ('callback generation','private func handleHelperFrame(','self.lifecycleGeneration == lifecycle.generation','true'),
        ('consumer trace quality','private func applyObservation(','frameQuality:frameQuality','frameQuality:[]'),
        ('real slot delivery',None,'work?()','_ = work'))
    for label,signature,old,new in changes:
        original_block=sections.func_text(root,signature) if signature else sections.symbol_text(root,'LatestMainFrame')
        hosts=[path for path in sections.swift_files(root) if original_block in path.read_text()]
        assert len(hosts)==1 and old in original_block,label
        host=hosts[0];before=host.read_text()
        host.write_text(before.replace(original_block,original_block.replace(old,new,1),1))
        try:
            try:boundary(root)
            except (AssertionError,ValueError,StopIteration):pass
            else:raise AssertionError('native-boundary source mutant accepted: '+label)
        finally:host.write_text(before)
    assert boundary(root)==expected_boundary
    print('PASS six native-boundary source mutants RED: SDK scalar, point coordinates, producer quality, generation, consumer quality and real slot delivery. Native execution NOT_RUN.')
    fixture=root/'Tests/HeadPose/fixtures/Pose192d.3083622.swift.txt'
    before=fixture.read_bytes();fixture.write_bytes(before+b'\n')
    try:
        try:capture(root)
        except AssertionError as error:
            assert 'historical' in str(error),error
        else:raise AssertionError('changed historical formula fixture accepted')
    finally:fixture.write_bytes(before)
    print('PASS historical formula fixture tamper RED; original immutable-reference equality retained without Git-history dependency')
print('Swift compilation, runtime, native SDK/camera cases NOT_RUN by this witness')
