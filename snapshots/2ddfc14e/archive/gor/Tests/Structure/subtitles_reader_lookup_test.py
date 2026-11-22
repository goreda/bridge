#!/usr/bin/env python3
"""Run unchanged source-anchored models after arbitrary Subtitles host relocation.

This exercises the real lifecycle and paused/thermal model readers. It does not
execute Swift timers, screen capture or the live-caption audio/process lifecycle.
"""
from pathlib import Path
import shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
READERS=('Tests/Harness/LiveCaption/test_lifecycle_model.py','Tests/SubtitleSamplePaused/subtitle_sample_paused_test.py')
def run(root,reader):return subprocess.run([sys.executable,str(root/reader)],cwd=root,capture_output=True,text=True,timeout=40)
expected={}
for reader in READERS:
 result=run(ROOT,reader);assert result.returncode==0,(reader,result.stdout,result.stderr);expected[reader]=result.stdout
with tempfile.TemporaryDirectory(prefix='subtitles-readers-') as td:
 root=Path(td);shutil.copytree(ROOT/'Sources',root/'Sources');shutil.copytree(ROOT/'Tests',root/'Tests')
 carriers=[]
 for i,name in enumerate(('SubtitleView.swift','LiveCaption.swift')):
  host=root/'Sources/gor/Subtitles'/name;carrier=root/'Sources/gor/ReaderGhost'/('Carrier'+str(i)+'.swift');carrier.parent.mkdir(exist_ok=True);host.rename(carrier);carriers.append(carrier);assert not host.exists()
 for reader in READERS:
  result=run(root,reader);assert result.returncode==0,(reader,result.stdout,result.stderr);assert result.stdout==expected[reader]
 print('PASS both actual readers: old unit paths and both planned host paths absent, arbitrary MARK carriers GREEN, output byte-identical')
 carrier=carriers[1];before=carrier.read_text()
 for reader,old,new in ((READERS[0],'captionGeneration &+= 1','captionGeneration &+= 0'),(READERS[1],'thermalPlayingInterval: Double = 0.4','thermalPlayingInterval: Double = 0.8')):
  assert old in before;carrier.write_text(before.replace(old,new,1));result=run(root,reader);assert result.returncode!=0,('source mutant accepted',reader);carrier.write_text(before)
 print('PASS actual readers refuse caption-generation and thermal-spacing source mutants')
 for reader in READERS:
  result=run(root,reader);assert result.returncode==0 and result.stdout==expected[reader]
print('SUBTITLES_READER_LOOKUP PASS; no native lifecycle/capture claim')
