"""C1 decoded-frame projection and source contracts for the degradation audit.

The portable projection compiles the unchanged production scalar/geometry span
against the real CameraHelperIPC wire types. Its explicit boundary is the
selected-box early return and the Snapshot result, not a fake Vision object or
an implementation of camera callbacks, lifecycle, gaze or capture.

The explicit --native mode builds the genuine gor target with the locked local
provider and macOS SDK. It never substitutes SDK types or the real consumer.
Source-only, portable runtime and native compiler results stay separate.
"""
from pathlib import Path
import importlib.util
import os
import subprocess
import tempfile


def sections(root):
    spec=importlib.util.spec_from_file_location('c1_audit_sections',Path(root)/'Tests/Structure/section_source.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def check_contracts(helper,apply):
    assert 'let lm = f.landmarks' in helper
    assert 'lm != nil && lm?.yaw != nil && lm?.pitch != nil && lm?.roll != nil' in helper
    assert 'guard let selectedBox = selectedIsLandmarks ? lm?.box : f.rect?.box else {' in helper
    for axis in ('Yaw','Pitch','Roll'):
        line=next(line for line in helper.splitlines() if 'let sel'+axis in line)
        assert 'selectedIsLandmarks ? lm?.'+axis.lower() in line and 'f.rect?.'+axis.lower() in line
    assert 'let measuredAngles:[Double]=[selYaw,selPitch,selRoll].compactMap{$0}' in helper
    assert 'PoseMeasurementValidity.rectangleReason(faceCount:poseFaceCount,angles:measuredAngles,box:box)' in helper
    assert 'PoseMeasurementValidity.reason(faceCount:poseFaceCount,landmarkFaceCount:landmarkFaceCount,angles:measuredAngles,box:box,pupils:measuredPupils,landmarkConfidence:landmarkConfidence)' in helper
    quality=next(line.strip() for line in helper.splitlines() if 'let frameQuality:' in line)
    assert quality=='let frameQuality:[Double]=[f.quality?.mean ?? -1,f.lumaRectFace?.room ?? -1,f.quality?.contrast ?? -1,f.quality?.clipped ?? -1,landmarkConfidence,frameAge,qualityFaceCount,f.exposureChanging]'
    for typed in ('landmarkConfidence:Double','frameAge:Double','landmarkFaceCount:Int','detectedFaceCount:Int','qualityFaceCount:Double','poseFaceCount:Int','measuredPupils:[Double]','pairedPupilCoordinates:[Double]','observedBox:[Double]','observedLandmarkBox:[Double]','signedPoseAngles:[Double]','poseConfidence:Double','frameTimestamp:Double'):
        assert 'let '+typed in helper,typed
    submit=helper.index('        deliverySlot.submit {')
    assert 'let deliverySlot=f.delivery == "blink" ? latestLandmarkFrame:latestPoseFrame' in helper[:submit]
    callback=helper[submit:]
    assert 'compactMap' not in callback and 'Double(' not in callback and '? pts:' not in callback
    for binding in ('poseAngles:signedPoseAngles','framePTS:frameTimestamp','frameQuality:frameQuality,structureReason:structureReason','pairedPupils:pairedPupilCoordinates','eyeWidths:measuredWidths'):
        assert binding in callback,binding
    for gate in ('if structureReason != 0 {','if let eyes=eyeApertures,!poseEyeGate.accept(eyes) {'):
        start=apply.index(gate);end=apply.index('        var distanceReady=',start)
        assert 'return' in apply[start:end] and 'poseFollow?.hold(at:t);poseNoise.interrupt()' in apply[start:end]
    assert apply.index('if structureReason != 0 {')<apply.index('let distance=pupilDistanceScale.sample')


def build_projection(root):
    ss=sections(root)
    helper=ss.func_text(root,'private func handleHelperFrame(')
    apply=ss.func_text(root,'private func applyObservation(')
    check_contracts(helper,apply)
    selection=helper[helper.index('        let lm = f.landmarks'):helper.index('        guard let selectedBox =')]
    body=helper[helper.index('        let selYaw'):helper.index('        let gaze =')]
    host=ss.host_text(root,'private static let yawSign:')
    signs='\n'.join(line for line in host.splitlines() if any('private static let '+axis+'Sign:' in line for axis in ('yaw','pitch','roll')))
    assert len(signs.splitlines())==3
    dependencies='\n\n'.join(ss.symbol_text(root,name) for name in ('CameraHelperIPC','EyeAperture','PoseMeasurementValidity'))
    boundary=r'''
struct C1ProjectionSnapshot {
 let widths:[Double],quality:[Double],angles:[Double],signed:[Double],paired:[Double],eyeGeometry:[Double],faceBox:[Double],landmarkBox:[Double]
 let reason:Int,framePTS:Double,landmarkKind:String
}
struct C1Projection {
'''+signs+r'''
 static func project(_ f:CameraHelperIPC.Frame)->C1ProjectionSnapshot? {
'''+selection+r'''
        guard let selectedBox = selectedIsLandmarks ? lm?.box : f.rect?.box else {return nil}
'''+body+r'''
        return C1ProjectionSnapshot(widths:measuredWidths,quality:frameQuality,angles:measuredAngles,signed:signedPoseAngles,paired:pairedPupilCoordinates,eyeGeometry:eyeGeometry,faceBox:observedBox,landmarkBox:observedLandmarkBox,reason:structureReason,framePTS:frameTimestamp,landmarkKind:landmarkKind)
 }
}
'''
    checks=r'''
func frame()->CameraHelperIPC.Frame {
 CameraHelperIPC.Frame(generation:1,window:2,now:3,pts:2.9,age:0.1,pixelWidth:640,pixelHeight:480,ambientOnly:false,settled:true,consecutiveSettled:3,seenFirstSettled:true,ambientSettled:true,processed:true,visionFailed:false,visionMS:1,exposureChanging:0)
}
func landmarks(_ points:[[Double]],yaw:Double?=0.3,pitch:Double?=0.2,roll:Double?=0.1)->CameraHelperIPC.FaceLandmarks {
 CameraHelperIPC.FaceLandmarks(box:[0.1,0.2,0.5,0.5],yaw:yaw,pitch:pitch,roll:roll,confidence:0.8,landmarksConfidence:0.9,faceCount:1,leftEye:points,rightEye:points,leftPupil:nil,rightPupil:nil)
}
func decoded(_ f:CameraHelperIPC.Frame)throws->CameraHelperIPC.Frame {
 try JSONDecoder().decode(CameraHelperIPC.Frame.self,from:JSONEncoder().encode(f))
}
var cases=0
for angle in [-30.0,0,30] {for scale in [0.8,1.0,1.2] {
 let radians=angle*Double.pi/180
 let points=[[0.0,0.0],[40*scale*cos(radians)/320,40*scale*sin(radians)/240]]
 var f=frame();f.delivery="blink";f.landmarks=landmarks(points)
 f.rect=CameraHelperIPC.FaceRect(box:[0.2,0.2,0.4,0.4],yaw:-0.4,pitch:-0.3,roll:-0.2,confidence:0.6,faceCount:1)
 f.quality=CameraHelperIPC.Quality(mean:10,contrast:30,clipped:0.2)
 f.lumaRectFace=CameraHelperIPC.Luma2(face:11,room:20,combined:15)
 let result=C1Projection.project(try decoded(f))!
 precondition(result.widths.count==2 && result.widths.allSatisfy{abs($0-40*scale)<1e-9})
 precondition(result.angles==[0.3,0.2,0.1] && result.signed==[0.3,-0.2,0.1])
 precondition(result.quality==[10,20,30,0.2,0.9,0.1,1,0] && result.framePTS==2.9)
 precondition(result.reason==0 && result.landmarkKind=="eye" && result.paired.isEmpty)
 cases+=1
}}
precondition(C1Projection.project(frame())==nil)
var f=frame();f.delivery="head"
f.rect=CameraHelperIPC.FaceRect(box:[0.2,0.2,0.4,0.4],yaw:0.4,pitch:0.3,roll:0.2,confidence:0.6,faceCount:1)
var result=C1Projection.project(try decoded(f))!
precondition(result.reason==0 && result.widths.isEmpty && result.quality==[-1,-1,-1,-1,0,0.1,0,0])
f.rect!.yaw=nil;result=C1Projection.project(try decoded(f))!
precondition(result.angles.count==2 && result.reason==2,"missing angle became measured zero")
f.rect!.yaw=0.4;f.rect!.faceCount=2
result=C1Projection.project(try decoded(f))!;precondition(result.reason==1)
f.rect!.faceCount=1;f.rect!.roll=Double.nan;f.pts=Double.nan
result=C1Projection.project(f)!
precondition(result.reason==3 && result.framePTS == -1)
f=frame();f.delivery="blink";f.landmarks=landmarks([[0,0],[0.1,0.1]],yaw:nil)
let absent=C1Projection.project(try decoded(f))
precondition(absent==nil,"incomplete landmark pose must fall back to rectangle or no result")
f.rect=CameraHelperIPC.FaceRect(box:[0.2,0.2,0.4,0.4],yaw:0.4,pitch:0.3,roll:0.2,confidence:0.6,faceCount:1)
result=C1Projection.project(try decoded(f))!
precondition(result.angles==[0.4,0.3,0.2] && result.reason==0)
f.landmarks!.leftEye=nil;f.landmarks!.rightEye=nil
result=C1Projection.project(try decoded(f))!;precondition(result.reason==2)
print("PASS C1 decoded production projection: \(cases) pixel-aspect/roll/0.8-1.2 scale cases, real IPC roundtrip, pose fallback/missing/nonfinite/multiple-face reasons, eight quality fields/sentinels and timestamp; native camera/SDK performance NOT_PROVEN")
'''
    return 'import Foundation\n'+dependencies+'\n'+boundary+checks,helper,apply


def run(root):
    native_boundary_sources(root)
    program,helper,apply=build_projection(root)
    mutants=[('measured zero',helper.replace('[selYaw,selPitch,selRoll].compactMap{$0}','[selYaw ?? 0,selPitch ?? 0,selRoll ?? 0]',1),apply),
             ('quality sentinel',helper.replace('f.quality?.mean ?? -1','f.quality?.mean ?? 0',1),apply),
             ('lost slot independence',helper.replace('let deliverySlot=f.delivery == "blink" ? latestLandmarkFrame:latestPoseFrame','let deliverySlot=latestPoseFrame',1),apply),
             ('inline callback conversion',helper.replace('poseAngles:signedPoseAngles','poseAngles:[rawYaw,rawPitch,rawRoll]',1),apply),
             ('structure gate removed',helper,apply.replace('if structureReason != 0 {','if false {',1))]
    for label,changed_helper,changed_apply in mutants:
        assert (changed_helper,changed_apply)!=(helper,apply),label
        try:check_contracts(changed_helper,changed_apply)
        except (AssertionError,ValueError,StopIteration):pass
        else:raise AssertionError('source contract mutant accepted: '+label)
    print('PASS C1 source contracts: absent angles, typed wire quality, independent delivery slot, precomputed callback payload and hold-before-mutation; five mutants RED')
    with tempfile.TemporaryDirectory() as directory:
        path=Path(directory);(path/'main.swift').write_text(program)
        subprocess.run([os.environ.get('SWIFTC','swiftc'),str(path/'main.swift'),'-o',str(path/'test')],check=True)
        print(subprocess.check_output([str(path/'test')],text=True),end='')


def native_boundary_sources(root):
    """Source links only. This does not typecheck or execute the native boundary."""
    import hashlib
    ss=sections(root)
    functions={name:ss.func_text(root,signature) for name,signature in (
        ('pointList','private static func pointList(_ region: VNFaceLandmarkRegion2D?)'),
        ('faceRect','fileprivate static func faceRect('),
        ('faceLandmarks','fileprivate static func faceLandmarks('),
        ('eyeCentre','private static func eyeCentre(_ points: [[Double]]?'),
        ('measureQuality','fileprivate static func measureQuality('),
        ('handleHelperFrame','private func handleHelperFrame('),
        ('applyObservation','private func applyObservation('))}
    check_contracts(functions['handleHelperFrame'],functions['applyObservation'])
    for name in ('faceRect','faceLandmarks'):
        for axis in ('yaw','pitch','roll'):
            assert axis+': face.'+axis+'?.doubleValue' in functions[name],(name,axis)
    assert 'region.normalizedPoints.map' in functions['pointList']
    assert all('Double($0.'+axis+')' in functions['pointList'] for axis in ('x','y'))
    quality=functions['measureQuality']
    assert 'PoseFrameQuality.measure(pixelBuffer, face: box, eyes: eyes)' in quality
    assert 'CameraHelperIPC.Quality(mean: q.mean, contrast: q.contrast, clipped: q.clipped)' in quality
    declarations={name:ss.symbol_text(root,name) for name in (
        'CameraHelperEngine','CameraHelperIPC','HeadTracker','LatestMainFrame',
        'FrameLossLatch','PoseFrameQuality','PoseTraceRing','BinocularGazeSample')}
    engine=declarations['CameraHelperEngine']
    for link in ('frame.rect =','Self.faceRect(','frame.landmarks = Self.faceLandmarks(',
                 'frame.quality = Self.measureQuality('):
        assert link in engine,link
    callback=functions['handleHelperFrame'].split('        deliverySlot.submit {',1)[1]
    for link in ('self.lifecycleGeneration == lifecycle.generation',
                 'self.frameLossLatch.consume()', 'self.applyObservation('):
        assert link in callback,link
    for link in ('pending=work','DispatchQueue.main.async','work?()'):
        assert link in declarations['LatestMainFrame'],link
    consumer=functions['applyObservation']
    assert 'frameQuality:[Double]=[]' in consumer
    traces=[line for line in consumer.splitlines() if 'PoseTraceRing.shared.append(' in line]
    assert len(traces)==4 and sum('frameQuality:frameQuality' in line for line in traces)==3
    assert sum('action:"baselineSeed"' in line and 'frameQuality:' not in line for line in traces)==1
    def record(text):
        data=text.encode();return {'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    return {'functions':{name:record(text) for name,text in functions.items()},
            'declarations':{name:record(text) for name,text in declarations.items()},
            'scope':'Real producer, complete callback and consumer source links; native compilation and asynchronous execution are separate results.'}


def native_input_pins(root):
    import hashlib
    root=Path(root)
    paths=set((root/'Sources/gor').rglob('*.swift'))
    paths.update((root/'Packages/gorav/Sources').rglob('*.swift'))
    paths.update(root/name for name in ('Package.swift','Packages/gorav/Package.swift',
                                        'tools/build-with-gorav-provider.py'))
    return {str(path.relative_to(root)):hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(paths) if path.is_file()}


def run_native(root,report):
    """Build the genuine gor target in fresh scratch space. Never install or run it."""
    import ast
    import json
    import platform
    import shutil
    import sys
    import time
    root=Path(root).resolve()
    report=Path(report).resolve();report.parent.mkdir(parents=True,exist_ok=True)
    result={'source_contract_status':'PASS','native_status':'NOT_RUN',
            'boundary':native_boundary_sources(root),'camera_runtime':'NOT_RUN',
            'async_runtime':'NOT_RUN','added_solver_limit':None,
            'performance_baseline':'NOT_ESTABLISHED'}
    def save(code):
        result['exit_code']=code
        report.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
        print('C1 native status: '+result['native_status']+'; report: '+str(report))
        return code
    if platform.system()!='Darwin':
        result['reason']='macOS and the real macOS SDK are required';return save(77)
    if shutil.which('xcrun') is None:
        result['reason']='xcrun is unavailable';return save(77)
    wrapper=root/'tools/build-with-gorav-provider.py'
    required=[root/'Package.swift',root/'Packages/gorav/Package.swift',wrapper]
    missing=[str(path.relative_to(root)) for path in required if not path.is_file()]
    if missing:
        result['missing_inputs']=missing;return save(77)
    # Read the wrapper's actual provider table, without importing or running it.
    assignments=ast.parse(wrapper.read_text()).body
    table=next(ast.literal_eval(node.value) for node in assignments if isinstance(node,ast.Assign)
               and any(isinstance(t,ast.Name) and t.id=='PROVIDERS' for t in node.targets))
    provider=os.environ.get('GORAV_PROVIDER','7.1-full-codec')
    if provider not in table:
        result['reason']='Unsupported provider selection';return save(77)
    provider_dir=root/'Packages/gorav-provider'
    missing=[str((provider_dir/name).relative_to(root)) for name in table[provider]
             if not (provider_dir/name).is_file()]
    if missing:
        result['missing_inputs']=missing;return save(77)
    def clean(text,scratch=None):
        import re
        if scratch:text=text.replace(str(scratch),'$SCRATCH')
        text=text.replace(str(root),'$ROOT').replace(str(Path.home()),'$HOME')
        return re.sub(r'(?:phonemsg|imsgmsg|peermsg|chat|agent)-[A-Za-z0-9]+','[message-reference]',text)
    try:
        sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
        swift=subprocess.check_output(['xcrun','--sdk','macosx','--find','swift'],text=True).strip()
        if not Path(sdk).is_dir() or not Path(swift).is_file():
            raise FileNotFoundError('SDK or compiler path does not exist')
    except (OSError,subprocess.CalledProcessError) as error:
        result['reason']='SDK preflight failed: '+clean(str(error));return save(77)
    env=os.environ.copy();env['PATH']=str(Path(swift).parent)+os.pathsep+env.get('PATH','')
    env['SDKROOT']=sdk;env['GORAV_PROVIDER']=provider
    result.update(sdk=clean(sdk),provider=provider,
                  compiler=clean(subprocess.check_output([swift,'--version'],text=True,env=env)))
    before=native_input_pins(root);result['input_pins']=before
    # SwiftPM, not a regex or reconstructed type, owns actual target membership.
    with tempfile.TemporaryDirectory(prefix='c1-native-description-') as description:
        describe=subprocess.run([swift,'package','--package-path',str(root),
                                 '--scratch-path',description,'describe','--type','json'],
                                text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
    if describe.returncode:
        result.update(native_status='FAILED',stage='package-description',returncode=describe.returncode)
        report.with_suffix('.log').write_text(clean(describe.stdout+describe.stderr));return save(1)
    package=json.loads(describe.stdout)
    target=next(item for item in package['targets'] if item['name']=='gor')
    declared={str((root/target['path']/name).resolve().relative_to(root)) for name in target['sources']}
    expected={str(path.relative_to(root)) for path in sections(root).swift_files(root)}
    if target['type']!='executable' or declared!=expected:
        result.update(native_status='FAILED',stage='target-membership',
                      missing=sorted(expected-declared),unexpected=sorted(declared-expected));return save(1)
    result['actual_gor_target_sources']=sorted(declared)
    with tempfile.TemporaryDirectory(prefix='c1-native-genuine-target-') as directory:
        scratch=Path(directory)/'build'
        command=[sys.executable,str(wrapper),'--package-path',str(root),
                 '--scratch-path',str(scratch),'-c','debug','--product','gor']
        result['command']=[clean(arg,scratch) for arg in command]
        result.update(native_status='INCOMPLETE',stage='native-build')
        report.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
        started=time.monotonic()
        build=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,env=env)
        result['elapsed_build_seconds']=round(time.monotonic()-started,3)
        result['returncode']=build.returncode
        report.with_suffix('.log').write_text(clean(build.stdout,scratch))
        result['source_inputs_unchanged']=before==native_input_pins(root)
        result['native_status']='PASS' if build.returncode==0 and result['source_inputs_unchanged'] else 'FAILED'
        result['scope']='Fresh real gor target build, including actual Vision/CoreVideo producer, IPC, complete HeadTracker callback and applyObservation. No camera, callback scheduling or lifecycle runtime claim.'
    return save(0 if result['native_status']=='PASS' else 1)


if __name__=='__main__':
    import argparse
    import json
    parser=argparse.ArgumentParser(description='C1 boundary source links or genuine macOS target compilation; never app execution.')
    parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[2])
    parser.add_argument('--native',action='store_true',help='Build the real target using the locked provider; requires --report. Exit 77 means NOT_RUN.')
    parser.add_argument('--report',type=Path,help='JSON evidence destination; native compiler diagnostics use the same stem with .log.')
    args=parser.parse_args()
    if not __debug__:parser.error('C1 contracts require Python assertions enabled')
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps({'native_status':'INCOMPLETE','source_contract_status':'NOT_CHECKED'})+'\n')
    if args.native:
        if not args.report:parser.error('--native requires --report')
        try:code=run_native(args.root,args.report)
        except Exception as error:
            args.report.write_text(json.dumps({'native_status':'FAILED','error_type':type(error).__name__})+'\n')
            raise
        raise SystemExit(code)
    result={'source_contract_status':'PASS','native_status':'NOT_RUN',
            'portable_runtime':'NOT_RUN','boundary':native_boundary_sources(args.root)}
    if args.report:
        args.report.parent.mkdir(parents=True,exist_ok=True)
        args.report.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print('PASS C1 native-boundary source links only; Swift compilation, portable/native runtime and camera NOT_RUN')
