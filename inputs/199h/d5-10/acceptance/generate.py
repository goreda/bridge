from pathlib import Path
import json,hashlib,copy
r=Path(__file__).resolve().parent
body=b'#!/bin/sh\nexit 0\n'
base={'schema':'synthetic-adapter-fixture-v1','candidate':'1'*40,'carrier':'2'*40,'source_pin':'3'*40,'expected_old_refs':{'delivery':'4'*40,'candidate':'5'*40},'observed_old_refs':{'delivery':'4'*40,'candidate':'5'*40},'phase':'pre-ci','receipt':{'result':'PASS','candidate':'1'*40,'carrier':'2'*40,'source_pin':'3'*40,'native_compile_exit':0,'manifest_tree_test':'PASS'},'inventory':[{'path':'tools/fixture.sh','sha256':hashlib.sha256(body).hexdigest(),'mode':'0o755'}],'actual_files':[{'path':'tools/fixture.sh','sha256':hashlib.sha256(body).hexdigest(),'mode':'0o755'}],'synthetic':True}
cases={}
for phase in ['pre-ci','atomic-promotion']:
 good=copy.deepcopy(base);good['phase']=phase;cases[phase+'-positive']=(good,0)
 bad=copy.deepcopy(good);bad['receipt']['candidate']='6'*40;cases[phase+'-wrong-candidate']=(bad,1)
 bad=copy.deepcopy(good);bad['receipt']=None;cases[phase+'-missing-receipt']=(bad,1)
 bad=copy.deepcopy(good);bad['actual_files'][0]['mode']='0o644';cases[phase+'-mode-mismatch']=(bad,1)
 bad=copy.deepcopy(good);bad['actual_files'][0]['sha256']='0'*64;cases[phase+'-hash-mismatch']=(bad,1)
 bad=copy.deepcopy(good);bad['receipt']['source_pin']='7'*40;cases[phase+'-wrong-source']=(bad,1)
bad=copy.deepcopy(base);bad['phase']='atomic-promotion';bad['observed_old_refs']['delivery']='8'*40;cases['atomic-promotion-stale-ref']=(bad,1)
bad=copy.deepcopy(base);bad['phase']='atomic-promotion';bad['ref_read_sequence']=[copy.deepcopy(bad['observed_old_refs']),{'delivery':'8'*40,'candidate':'5'*40}];cases['atomic-promotion-ref-changes-after-precheck']=(bad,1)
rows=[]
for name,(data,status) in cases.items():
 p=r/'cases'/name/'fixture.json';p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(data,indent=2)+'\n');tree=p.parent/'product/tools';tree.mkdir(parents=True,exist_ok=True);f=tree/'fixture.sh';f.write_bytes(body);f.chmod(0o644 if 'mode-mismatch' in name else 0o755)
 rows.append({'name':name,'case':'cases/'+name+'/fixture.json','expect_zero':status==0})
(r/'cases.json').write_text(json.dumps(rows,indent=2)+'\n')
print('Generated',len(rows),'synthetic cases. No validator result asserted.')
