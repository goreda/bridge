#!/usr/bin/env python3
"""Run the actual three Display harnesses after a ghost MARK-carrier relocation.

Only source acquisition changes; their assertions and model implementations are
unchanged. This does not execute display hardware, native timers or app code.
"""
from pathlib import Path
import os,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
READERS=('Tests/Harness/BrightnessFade/test_fade.py','Tests/Harness/ContentDimming/test_dimming.py','Tests/HeatBrightnessIPC/brightness_ipc_test.py')
def run(root,reader):return subprocess.run([sys.executable,str(root/reader)],cwd=root,capture_output=True,text=True,timeout=40)
expected={}
for reader in READERS:
 result=run(ROOT,reader);assert result.returncode==0,(reader,result.stdout,result.stderr);expected[reader]=result.stdout
with tempfile.TemporaryDirectory(prefix='display-reader-relocation-') as td:
 root=Path(td);shutil.copytree(ROOT/'Sources',root/'Sources')
 files=READERS+('Tests/Structure/section_source.py','Tests/Structure/pp_split.py','Tests/Structure/pp-split-manifest.json','Tests/Structure/core_source.py','Tests/Structure/199u-core-map.json','Tests/Architecture/camera_source.py','Tests/Architecture/camera-s3-map.json','Tests/Structure/platform_source.py','Tests/Structure/199u-platform-map.json')
 for rel in files:
  p=root/rel;p.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/rel,p)
 shutil.copytree(ROOT/'Tests/Structure/pp-split-historical',root/'Tests/Structure/pp-split-historical')
 host=root/'Sources/gor/Picture/Brightness.swift';carrier=root/'Sources/gor/ReaderGhost/Carrier.swift';carrier.parent.mkdir();host.rename(carrier)
 assert not host.exists()
 for name in ('BrightnessController.swift','BrightnessReadCache.swift','ContentAdaptiveDimming.swift'):
  assert not (root/'Sources/gor/gor'/name).exists(),name
 for reader in READERS:
  result=run(root,reader);assert result.returncode==0,(reader,result.stdout,result.stderr)
  assert result.stdout==expected[reader],('reader result changed after relocation',reader)
 print('PASS three actual Display readers: old paths and planned host absent, arbitrary carrier GREEN, output byte-identical')
 before=carrier.read_text()
 mutants=(
  (READERS[0],'fadeStepDelay: TimeInterval = 0.05','fadeStepDelay: TimeInterval = 0.5'),
  (READERS[1],'lumaSmoothing: Float = 0.12','lumaSmoothing: Float = 0.99'),
  (READERS[2],'ttl: TimeInterval = 0.25','ttl: TimeInterval = 0.5'))
 for reader,old,new in mutants:
  assert before.count(old)==1,(reader,old)
  carrier.write_text(before.replace(old,new,1));result=run(root,reader)
  assert result.returncode!=0,('source semantic mutant accepted',reader)
  carrier.write_text(before)
 print('PASS fade-delay, dimming-smoothing and cache-TTL source mutants RED in the actual readers')
 for reader in READERS:
  result=run(root,reader);assert result.returncode==0 and result.stdout==expected[reader]
print('DISPLAY_READER_LOOKUP PASS; no native/hardware behavior claim')
