#!/usr/bin/env python3
"""Execute actual extracted transient helper. Linux/macOS Foundation, not full film render."""
import pathlib,tempfile,subprocess,sys,json,shutil,os,signal
root=pathlib.Path(__file__).resolve().parents[2]
s=(root/'Sources/gor/Stereo/Render.swift').read_text();a=s.index('    private static func transientShotCopy(');b=s.index('\n    /// `depthSize`',a)
helper=s[a:b].replace('private static func','static func',1)
cases=[('ffmpeg-timeout','exec '+shutil.which('ffmpeg')+' -loglevel quiet -re -f lavfi -i testsrc=size=16x16:rate=24 -t 10 -f null -',.2,None,True),('ffmpeg-cancel','exec '+shutil.which('ffmpeg')+' -loglevel quiet -re -f lavfi -i testsrc=size=16x16:rate=24 -t 10 -f null -',10,.15,True),('ignore-term',"trap '' TERM; while :; do sleep 0.1; done",.2,None,True),('chatty','i=0; while [ $i -lt 8000 ]; do echo error123456789 >&2; i=$((i+1)); done; exit 1',5,None,True),('descendant-holds-stderr','sleep 4',.2,None,True)]
with tempfile.TemporaryDirectory(prefix='d2-transient-') as d:
 d=pathlib.Path(d); rows=[]
 for name,body,timeout,cancel,required in cases:
  sh=d/(name+'.sh');sh.write_text('#!/bin/sh\n'+body+'\n');sh.chmod(0o755)
  # Routing-only stub selects the executable; helper body and arguments remain actual production bytes.
  code='import Foundation\n#if canImport(Darwin)\nimport Darwin\n#else\nimport Glibc\n#endif\nenum GORResources {static func vendorPath(_ p:String)->String {'+json.dumps(str(sh))+'}}\nstruct Probe {\n'+helper+'}\n'
  code+='let out=URL(fileURLWithPath:'+json.dumps(str(d/(name+'.mp4')))+');try Data("partial".utf8).write(to:out);let start=Date()\n'
  code+='let ok=Probe.transientShotCopy(film:out,to:out,startPTS:0,endPTS:1,timeout:'+str(timeout)+',cancelled:{'+('return Date().timeIntervalSince(start)>'+str(cancel) if cancel else 'return false')+'})\n'
  code+='print("RESULT \\(ok) \\(Date().timeIntervalSince(start)) \\(!FileManager.default.fileExists(atPath:out.path))")\n'
  p=d/'main.swift';p.write_text(code);binary=d/'test'
  subprocess.run(['swiftc','-swift-version','5',str(p),'-o',str(binary)],check=True,timeout=90)
  proc=subprocess.Popen([str(binary)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True)
  try:text=proc.communicate(timeout=8)[0];rc=proc.returncode
  except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);text=proc.communicate()[0];rc=124
  print(name,text.strip(),flush=True)
  parsed=text.strip().split();valid=rc==0 and len(parsed)>=4 and parsed[-4]=='RESULT';elapsed=float(parsed[-2]) if valid else None
  bounded=bool(valid and parsed[-3]=='false' and parsed[-1]=='true' and elapsed<(3.5 if name=='ignore-term' else 2))
  rows.append(dict(case=name,result='PASS' if bounded else 'FAIL',required=required,exit=rc,elapsed=elapsed,scope='actual extracted helper with executable routing stub'))
  if required:assert bounded,rows[-1]
 out=pathlib.Path(os.environ.get('OUT',d))/'d2-transient-results.json';out.write_text(json.dumps(rows,indent=2));print(json.dumps(rows));print('PASS all5 helper cases including descendant-holds-stderr bounded return; descendant process reaping independently unverified')
