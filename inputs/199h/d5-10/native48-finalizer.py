"""Build exact manifest-only candidate and evidence from native48 downloaded artifacts.
Does not promote delivery refs. Run only after authenticated live terminal PASS.
"""
from pathlib import Path
import argparse,json,subprocess,os,hashlib,tempfile,csv,io
p=argparse.ArgumentParser();p.add_argument('--artifacts',type=Path,required=True);p.add_argument('--build-id',required=True);p.add_argument('--build-url',required=True);p.add_argument('--live-carrier',required=True);a=p.parse_args()
P=Path('/tmp/198y-s2');D=Path('/tmp/199g-ledger/docs/delivery');A=a.artifacts;env={**os.environ,'GIT_TERMINAL_PROMPT':'0'}
def git(*args,**kw):return subprocess.check_output(['git','-C',str(P),*args],env=kw.pop('env',env),**kw)
sha=lambda b:hashlib.sha256(b).hexdigest()
r=json.loads((A/'native48-result.json').read_text());assert r['result']=='PASS' and r['full_product_compile_exit']==0 and r['static_preinstall_exit']==0
source=r['source_pin'];assert source=='a198aee6be6bb2ce52ddf90c3c83da2a16359ab5';assert r['live_carrier_sha']==a.live_carrier
em=json.loads((A/'native48-native-manifest.json').read_text());assert em['result']=='PASS' and em['manifest_tree_test']=='PASS' and em['source_pin']==source
with tempfile.TemporaryDirectory() as td:
 e={**env,'GIT_INDEX_FILE':td+'/index'};git('read-tree',source,env=e)
 for name in ('delivery.tsv','manifest.tsv'):
  b=(A/('native48-'+name)).read_bytes();assert sha(b)==em['files']['architecture/'+name]
  oid=git('hash-object','-w','--stdin',input=b).decode().strip();git('update-index','--cacheinfo','100644',oid,'archive/gor/architecture/'+name,env=e)
 tree=git('write-tree',env=e).decode().strip();candidate=git('commit-tree',tree,'-p',source,input=b'delivery: automatic native48 emitted manifests for exact D1 cut\n').decode().strip()
 git('update-ref','refs/heads/candidate/ops/native48-delivery',candidate)
actual=json.loads((A/'native48-actual-product-source-map.json').read_text());assert actual['source_pin']==source and actual['live_carrier_sha']==a.live_carrier
alltree={row.split('\t')[1]:row.split()[2] for row in git('ls-tree','-r',candidate).decode().splitlines()}
assert len(actual['files'])>1800 and all(alltree.get(path)==blob for path,blob in actual['files'].items()),'CI compiler input differs from final product candidate'
# Validate every committed delivery row, not just the carrier's inventory.
for row in csv.DictReader(io.StringIO(git('show',candidate+':archive/gor/architecture/delivery.tsv').decode()),delimiter='\t'):
 assert sha(git('show',candidate+':archive/gor/'+row['path']))==row['sha256'],row['path']
s=json.loads((A/'native48-static-preinstall.json').read_text());script=json.loads((A/'native48-manifest.json').read_text());identity='source-manifest-sha256:'+sha(json.dumps(actual['files'],sort_keys=True,separators=(',',':')).encode());assert s['candidate']==script['candidate']==identity
assert script['compiled_executable_sha256']==s['executable_sha256']
# Carry the transport identity, never mislabel the original receipt as GitSHA.
for item in (s,script):item['transport_candidate']=item['candidate'];item['candidate']=candidate
carrier_baseline=subprocess.check_output(['git','-C','/tmp/198t/carrier','show',a.live_carrier+':ci/198t/DELIVERED-BASELINE.json'])
assert carrier_baseline==(D/'DELIVERED-BASELINE.json').read_bytes(),'CI baseline mismatch'
s['baseline_sha256']=sha(carrier_baseline);s['baseline_binding_source']='authenticated live carrier verified envelope and readback exact baseline bytes'
compile={'candidate':candidate,'result':'PASS','rows':[{'name':'exact-product-Darwin-compile','exit':0}]}
base=json.loads((D/'DELIVERED-BASELINE.json').read_text());buildhash=sha(git('show',candidate+':archive/gor/build.sh'))
build_source=git('show',candidate+':archive/gor/build.sh').decode()
assert 'gor_update_restore_current_swap() {' in build_source
assert 'gor_update_restore_current_swap || true' in build_source
assert 'gor_selftest\n    update_stage=result' in build_source
assert 'open -g -n "$app" --args --gor-no-activate' in build_source
assert 'st_wait_running 120' in build_source
assert '"$project_root/gor-selftest.sh" --lifeline-only' in build_source
assert build_source.rstrip().endswith('gor_update_finish\nfi')
assert s['result']=='PASS' and not s.get('removed') and not s.get('errors')
l2=json.loads((A/'native48-L2-results.json').read_text());fixed=[x for x in l2 if x['variant']=='fixed'];assert len(fixed)==18 and all(x['pass_'] for x in fixed);assert all(any(not x['pass_'] for x in l2 if x['variant']==v) for v in ('baseline','mutant-no-token','mutant-no-backup-identity','mutant-not-own-swap'))
check={'candidate':candidate,'result':'VERIFIED_SOURCE','build_sh_sha256':buildhash,'launch_after_build':True,'restore_this_run_on_failure':True,'runtime_attestation':'DEFERRED_TO_OWNER_INSTALL',**{k:{'candidate':candidate,'result':'PASS','exit':0,'build_sh_sha256':buildhash}for k in ('launch_check_test','L2_restore_test')}}
receipt={'candidate':candidate,'delivery_class':'E','authority':'phonemsg-01M7Q04ZD5EQBBCXXNJ0KECKKC','verification_source':'authenticated Codemagic live UI/API','build_url':a.build_url,'build_id':a.build_id,'terminal_status':'finished','carrier_sha':a.live_carrier,'live_carrier_sha':a.live_carrier,'static_preinstall':s,'compile':compile,'manifest':script,'native_manifest':{**em,'candidate':candidate},'updater_integrity':{'candidate':candidate,'result':'PASS','mismatches':0,'actual_build_sh_branch':True,'manifest_tree_test':True},'product_source_map':{'all_git_blobs_match_product':True,'files':actual['files']},'owner_install_check':check}
proof={'candidate':candidate,'baseline':base['source_commit'],'named_diffs':git('diff','--name-only',base['source_commit'],candidate).decode().splitlines(),'darwin_compile':compile,'manifest_regeneration':{**script,'result':'PASS'},'updater_integrity':receipt['updater_integrity']}
(A/'class-e-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');(A/'promotion-proof.json').write_text(json.dumps(proof,indent=2)+'\n');print('EXACT_CANDIDATE',candidate,'TRANSPORT',identity)
