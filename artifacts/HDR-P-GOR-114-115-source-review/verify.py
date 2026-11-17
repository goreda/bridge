import pathlib,json,hashlib
r=pathlib.Path(__file__).resolve().parent;m=json.loads((r/'manifest.json').read_text())
for f in m['files']:
 b=(r/f['path']).read_bytes();assert len(b)==f['bytes']and hashlib.sha256(b).hexdigest()==f['sha256'],f['path']
print('PASS 16 source snapshots match manifest; source integrity only, no native/runtime/pixel acceptance')
