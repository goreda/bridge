import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
s=(_pp_split().path(r,'PPController.swift')).read_text();a=s.index('    func selectVRProjection(');b=s.index('    func toggleHeadTracking()',a)
prefix='import Foundation\nenum Preset {case defaultAR}\nfinal class AppDelegate {var currentAspectPreset=Preset.defaultAR}\nlet NSApp=(delegate:AppDelegate(),unused:0)\nfinal class Mode { var kind="";func selectProjection(_ k:String){kind=k} }\nfinal class Detector {var stereoSBS=false;var stereoTopBottom=false;func cancel(){};func resetLastFile(){} }\nfinal class Harness {\nvar vr180Controller:Mode?=Mode();var cropDetector=Detector();var appliedVideoFrame=CGRect.zero;var appliedVideoFrameWindowSize=CGSize.zero;var bounds=CGRect.zero;var scans:[Bool]=[];var stereoProjectionBaseAspect:Double?;var stereoManualAspect:Double?;var stereoGeometryKey="";var stereoRestorePending=false\nfunc ipcCommand(_ s:String){}\nfunc refreshStereoMenuGeometry(force:Bool){};func refreshEffectiveGap(){};func applyVideoFrame(bounds:CGRect){}\nfunc startAutomaticCropDetection(needsRedetect:Bool){scans.append(cropDetector.stereoTopBottom)}\n'
suffix='}\nlet h=Harness()\nfor kind in ["flat-sbs","flat-tb","flat-sbs","flat-tb","vr180"] {h.selectVRProjection(kind);precondition(h.scans.last == (kind=="flat-tb"));precondition(h.cropDetector.stereoSBS)}\nprint("PASS actual production selectVRProjection manual SBS->TB->SBS->TB->VR180: scanner packing synchronized BEFORE scan dispatch")\n'
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(prefix+s[a:b]+suffix)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
