"""Native graph emitter before compile. Keep unchanged repository archive metadata."""
from pathlib import Path
import importlib.util,csv,json,hashlib,subprocess,platform
R=Path(__file__).resolve().parents[1];G=R/'payload/gor';O=R/'out';O.mkdir(exist_ok=True)
assert platform.system()=='Darwin','Darwin emitter only'
spec=importlib.util.spec_from_file_location('native_arch',G/'tools/architecture.py');a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
old={r['path']:r for r in csv.DictReader((G/a.MANIFEST).open(),delimiter='\t')}
targets,errors=a.graph(G)
assert targets and not any('graph unavailable' in e or 'swift unavailable' in e for e in errors),errors
rows=a.inventory(G,targets);present={r[0] for r in rows}
# Materialized inputs include EVERY current production/deployed file. Missing
# rows are repository-only archives; keep their existing metadata, never infer
# absent archive bytes or drop them as though product code had been removed.
manifest={p:list(r.values()) for p,r in old.items() if p not in present}
for r in rows:manifest[r[0]]=[r[0],r[1],r[2],r[5]]
a.write_tsv(G/a.MANIFEST,a.HEADER,[manifest[k] for k in sorted(manifest)])
# Use the product emitter's exact deployment and generated-file filters.
delivery=[]
for path,k,*_ in rows:
 if not a.deployed(path) or path==a.DELIVERY or k=='generated' and not path.startswith(('architecture/','docs/adr/')) and path not in {'ARCHITECTURE.md','.swift-format','VENDOR.md','ffmpeg-provider.lock','Package.swift','Packages/.keep','Tests/Architecture/prior-installer.sh','models/models.lock.tsv'}:continue
 p=G/path;delivery.append([path,hashlib.sha256(p.read_bytes()).hexdigest(),oct(p.stat().st_mode&0o777)])
a.write_tsv(G/a.DELIVERY,['path','sha256','mode'],delivery)
# The source-bound receipt will use the final production commit assembled from
# these two emitted files. CI's live carrier identity remains separately recorded.
subprocess.run(['git','config','user.name','Native CI'],cwd=R,check=True);subprocess.run(['git','config','user.email','native-ci@localhost'],cwd=R,check=True)
subprocess.run(['git','add','--','payload/gor/architecture/manifest.tsv','payload/gor/architecture/delivery.tsv'],cwd=R,check=True)
subprocess.run(['git','commit','--allow-empty','-m','CI local native manifest emission, no remote ref update'],cwd=R,check=True)
subprocess.run(['python3',R/'ci/198t/production-integrity-gate.py','--root',G],check=True)
for p in ('manifest.tsv','delivery.tsv'):(O/('native49-'+p)).write_bytes((G/'architecture'/p).read_bytes())
r=dict(result='PASS',source_pin=json.loads((R/'UPDATER-INTEGRITY.json').read_text())['source_pin'],platform=platform.platform(),manifest_tree_test='PASS',graph_errors_advisory=errors,targets=targets,files={('architecture/'+p):hashlib.sha256((G/'architecture'/p).read_bytes()).hexdigest() for p in ('manifest.tsv','delivery.tsv')},scope='native graph and production/deployed inventory; unchanged repository-only archive metadata preserved')
(O/'native49-native-manifest.json').write_text(json.dumps(r,indent=2)+'\n');print('NATIVE49_NATIVE_MANIFEST '+json.dumps(r),flush=True)
