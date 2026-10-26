from pathlib import Path
import tempfile,subprocess,shutil,hashlib
root=Path(__file__).parent/'onedir'
# Exercise ACTUAL shell unsigned selection predicate from candidate, using real Mach-O resources.
s=(Path(__file__).parent/'build.sh').read_text();start=s.index('    while IFS= read -r -d',s.index('# Copy all source binaries on --no-sign'));end=s.index('\nfi\nfor rel',start)
loop=s[start:end].replace('/usr/bin/file','file').replace('/usr/bin/grep','grep')
for existing in [False,True]:
 with tempfile.TemporaryDirectory() as td:
  p=Path(td);(p/'src/Resources/vendor').mkdir(parents=True);shutil.copytree(root,p/'src/Resources/vendor/yt-dlp-standalone');dest=p/'dst';dest.mkdir()
  if existing:
   shutil.copytree(root,dest/'yt-dlp-standalone');(dest/'yt-dlp-standalone/yt-dlp_macos').write_bytes(b'STALE')
  script='project_root='+str(p/'src')+'\nchanged_signed=()\n'+loop+'\nprintf "%s\\n" "${changed_signed[@]}"'
  selected=subprocess.check_output(['bash','-c',script],text=True).splitlines()
  assert len(selected)==107 and 'yt-dlp-standalone/_internal/Python' in selected
  for rel in selected:
   out=dest/rel;out.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p/'src/Resources/vendor'/rel,out)
  assert hashlib.sha256((dest/'yt-dlp-standalone/yt-dlp_macos').read_bytes()).digest()==hashlib.sha256((root/'yt-dlp_macos').read_bytes()).digest()
print('PASS actual unsignedselection107MachO fresh+existingstaleexe replacement. Model copy, not macOS build.')
