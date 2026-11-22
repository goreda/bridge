from pathlib import Path
import importlib.util,tempfile,io,contextlib,subprocess
p=Path(__file__).with_name('capture.py');spec=importlib.util.spec_from_file_location('capture',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as td:
 r=Path(td);log=r/'app.log';raw='unrelated\n[LiveCaption] Model not installed: small\n[SCE] RMS=0.02\n';log.write_text(raw)
 model=r/'Resources/vendor/whisper/models';model.mkdir(parents=True);(model/'ggml-small.bin').write_bytes(b'model')
 binary=model.parent/'whisper-live';binary.write_bytes(b'binary')
 calls=[]
 def run(args,**kw):
  calls.append(args)
  return subprocess.CompletedProcess(args,1,'','unknown flag: --version') if args[-1]=='--version' else subprocess.CompletedProcess(args,0,'ls fixture','')
 out=io.StringIO()
 with contextlib.redirect_stdout(out):m.capture(r,logs=[log],run=run)
 text=out.getvalue();assert 'Model not installed' in text and 'RMS=0.02' in text and 'unrelated' not in text
 assert 'ggml-small.bin bytes=5' in text and 'BINARY sha256:' in text and 'VERSION unavailable or unsupported' in text
 assert log.read_text()==raw and binary.read_bytes()==b'binary'
 assert len(calls)==3
print('PASS actual read-only capture helper: scoped app-tail, asset stats/model list/hash, honest unsupported version, no log or asset mutation')
