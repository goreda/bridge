#!/usr/bin/env python3
"""Read-only bounded evidence for the existing update capture. Never starts capture/inference."""
from pathlib import Path
import hashlib,os,re,subprocess,sys
PATTERN=re.compile(r'LiveCaption|whisper-live stderr|whisper-diag|live-caption session|\[SCE\]|Process Tap|RMS',re.I)
def tail(path,limit=262144):
 with path.open('rb') as f:
  f.seek(max(0,path.stat().st_size-limit));return f.read(limit).decode('utf8','replace')
def capture(project,logs=None,run=subprocess.run):
 print('BEGIN live-caption read-only evidence')
 for path in logs or [Path('/tmp/gor_direct.log'),Path('/tmp/gor_diag.log')]:
  print('LOG '+str(path).replace(str(Path.home()),'~'))
  try:
   selected=[line for line in tail(path).splitlines() if PATTERN.search(line)][-100:]
   for line in selected:
    line=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',line)
    print(''.join(c for c in line[:1200] if c=='\t' or ord(c)>=32).replace(str(Path.home()),'~'))
   if not selected:print('NO matching runtime lines in last 256KiB (not proof toggle succeeded)')
  except OSError as e:print('UNAVAILABLE '+type(e).__name__)
 # Same runtime layouts as GORResources: bundle assets first, sibling next.
 bundle=project/'gor.app/Contents/Resources/vendor'
 vendor=bundle if bundle.is_dir() and not bundle.is_symlink() else project/'Resources/vendor'
 binary=vendor/'whisper/whisper-live';models=vendor/'whisper/models'
 for path in [binary,models]:
  print('ASSET '+str(path).replace(str(Path.home()),'~'))
  try:
   result=run(['/bin/ls','-ld',str(path)],capture_output=True,text=True,timeout=5)
   print((result.stdout or result.stderr).strip().replace(str(Path.home()),'~'))
  except Exception as e:print('UNAVAILABLE '+type(e).__name__)
 if models.is_dir():
  for model in sorted(models.glob('ggml-*.bin'))[:64]:
   try:
    st=model.stat();print('MODEL '+model.name+' bytes='+str(st.st_size)+' mtime='+str(st.st_mtime))
   except OSError as e:print('MODEL '+model.name+' '+type(e).__name__)
 if binary.is_file():
  # Hash identity is reliable even for older binaries without a --version flag.
  h=hashlib.sha256()
  with binary.open('rb') as f:
   for chunk in iter(lambda:f.read(1048576),b''):h.update(chunk)
  print('BINARY sha256:'+h.hexdigest())
  try:
   result=run([str(binary),'--version'],stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=5)
   output=(result.stdout+'\n'+result.stderr).strip()
   print('VERSION probe rc='+str(result.returncode)+' '+output[:2048].replace(str(Path.home()),'~'))
   if result.returncode:print('VERSION unavailable or unsupported; hash above identifies installed bytes')
  except Exception as e:print('VERSION unavailable '+type(e).__name__)
 print('END live-caption read-only evidence')
if __name__=='__main__':
 capture(Path(sys.argv[1]))
 import runpy
 try:runpy.run_path(str(Path(__file__).parents[1]/'PlaybackCost/capture.py'),run_name='__main__')
 except OSError:print('playback-cost capture unavailable')
