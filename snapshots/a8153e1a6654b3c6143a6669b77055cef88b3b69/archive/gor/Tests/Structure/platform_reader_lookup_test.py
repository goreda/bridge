#!/usr/bin/env python3
"""Real Platform source readers after carrier relocation; no native UI claim."""
from pathlib import Path
import json,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
READERS=('Tests/Spaces/overlay_space_model_test.py','Tests/Spaces/overlay_space_wiring_test.py','Tests/Spaces/spaces_log_read_test.py','Tests/PanelFocus/check.py','Tests/Architecture/198y/W-gdb-198y-1nstinct-16.py','Tests/Architecture/198y/W-gdb-198y-1nstinct-19.py')
def run(root,reader):return subprocess.run([sys.executable,str(root/reader)],cwd=root,capture_output=True,text=True,timeout=45)
expected={}
for reader in READERS:
 result=run(ROOT,reader);assert result.returncode==0,(reader,result.stdout,result.stderr);expected[reader]=result.stdout
with tempfile.TemporaryDirectory(prefix='platform-readers-') as td:
 root=Path(td)/'archive/gor';root.mkdir(parents=True)
 for folder in ('Sources','Tests','architecture'):shutil.copytree(ROOT/folder,root/folder,ignore=shutil.ignore_patterns('__pycache__'))
 carriers=[]
 for name,dest in (('QuitChildKiller.swift','QuitChildKiller.swift'),('Windowing.swift','ArbitraryCarrier.swift')):
  host=root/'Sources/gor/Platform'/name;carrier=root/'Sources/gor/ReaderGhost'/dest;carrier.parent.mkdir(exist_ok=True);host.rename(carrier);carriers.append(carrier);assert not host.exists()
 for reader in READERS:
  result=run(root,reader);assert result.returncode==0,(reader,result.stdout,result.stderr)
  if '/198y/' not in reader:assert result.stdout==expected[reader],reader
 print('PASS six actual readers after both planned host paths disappear; standalone logical basename and arbitrary composed MARK carrier; four model/runtime outputs unchanged')
 carrier=carriers[1];before=carrier.read_text();old='moveInterval: TimeInterval = 0.5';assert old in before
 carrier.write_text(before.replace(old,'moveInterval: TimeInterval = 0.8',1))
 for reader in READERS[:3]+READERS[-2:]:
  result=run(root,reader);assert result.returncode!=0,('Space source mutant accepted',reader)
 carrier.write_text(before)
 old='override var canBecomeMain:Bool {false}';assert old in before
 carrier.write_text(before.replace(old,'override var canBecomeMain:Bool {true}',1))
 result=run(root,READERS[3]);assert result.returncode!=0,('focus source mutant accepted',result.stdout,result.stderr)
 carrier.write_text(before)
 # Hidden declarations outside the logical unit must not escape the lexical
 # guard merely because several units now share one physical file.
 carrier.write_text('struct OverlaySpaceGate {}\n'+before)
 for reader in READERS[-2:]:
  result=run(root,reader);assert result.returncode!=0,('extra carrier declaration accepted',reader)
 carrier.write_text(before)
 for reader in READERS:
  result=run(root,reader);assert result.returncode==0,(reader,result.stdout,result.stderr)
 print('PASS Space and focus source mutants rejected by their actual readers; extra carrier declaration rejected by both lexical ownership guards; clean rerun GREEN')
print('PLATFORM_READER_LOOKUP PASS; AppKit focus, desktop/Space behavior and native acceptance NOT_RUN')
