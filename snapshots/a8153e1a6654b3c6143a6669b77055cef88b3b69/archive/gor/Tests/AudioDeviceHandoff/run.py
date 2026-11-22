from pathlib import Path
import subprocess,json,os,hashlib
here=Path(__file__).resolve().parent;root=here.parents[1];logs=here/'results';logs.mkdir(exist_ok=True)
subprocess.run(['python3',str(here/'extract-adapter.py')],check=True)
source=root/'Packages/gorav/Sources/GorAVPlaybackCore/AudioOutputDeviceTransaction.swift'
good=source.read_text();rows=[]
variants=[('green',good),('red-ignore-inventory',good.replace('inventory.devices.contains(where:{$0.uid==expected && $0.isAlive})','true')),('red-skip-final-validation',good.replace('return validateCurrent(provider:provider)','return .accepted(currentUID:uid)')),('red-forget-selected-uid',good.replace('if let selectedUID {uid=selectedUID}', 'if let _=selectedUID {uid=try provider.currentUID(currentToken)}')), ('red-no-readback',good.replace('try verify(new,expected:uid,provider:provider)','') .replace('return validateCurrent(provider:provider)','return .accepted(currentUID:uid)')),('red-no-quiesce',good.replace('do {try provider.quiesce(old)}','do { }')),('red-no-terminal',good.replace('guard !terminal else{return .refused(AudioDeviceFailure(.stopped))}','guard true else{return .refused(AudioDeviceFailure(.stopped))}')),('red-premature-commit',good.replace('currentToken=new','currentToken=old'))]
manifest={str(source.relative_to(root)):hashlib.sha256(source.read_bytes()).hexdigest()}
for variant,text in variants:
    for suite in ['transaction','adapter']:
        if variant!='green' and suite=='adapter':continue
        # Green compiles the actual production file in place, not a copy.
        mutant=logs/'MutantTransaction.swift';mutant.write_text(text)
        src=source if variant=='green' else mutant
        files=[src,here/('TransactionTests.swift' if suite=='transaction' else 'AdapterTests.swift')]
        if suite=='adapter':files.insert(1,logs/'ActualAdapter.swift')
        for language in ['5','6']:
            for optimization in ['Onone','O']:
                name=f'{suite}-{variant}-{language}-{optimization}'
                executable=logs/'witness'
                cmd=[os.environ.get('SWIFTC','swiftc'),'-swift-version',language,'-strict-concurrency=complete','-'+optimization,*map(str,files),'-o',str(executable)]
                q=subprocess.run(cmd,capture_output=True,text=True);(logs/(name+'-compile.log')).write_text(q.stdout+q.stderr)
                assert q.returncode==0,q.stderr
                q=subprocess.run([str(executable)],capture_output=True,text=True);(logs/(name+'-run.log')).write_text(q.stdout+q.stderr)
                assert (q.returncode==0)==(variant=='green'),q.stdout+q.stderr
                rows.append(dict(suite=suite,variant=variant,language=language,optimization=optimization,exit=q.returncode,command=cmd))
                print(name,q.stdout.strip().splitlines()[:1],flush=True)
adapter=logs/'ActualAdapter.swift';actual=adapter.read_text()
for variant,text in [
    ('red-selection-unbound',actual.replace('selectedUID:explicitDeviceTransaction?.selectedUID','selectedUID:nil')),
    ('red-review-unbound',actual.replace('guard !deviceTerminal,var transaction=explicitDeviceTransaction,case .active = lifecycle.current,','guard !deviceTerminal,explicitDeviceTransaction != nil,case .active = lifecycle.current,').replace('let result=transaction.validateCurrent(provider:provider)','var transaction=AudioOutputDeviceTransaction(currentToken:1)\n        let result=transaction.validateCurrent(provider:provider)')),
    ('red-shared-context',actual.replace('contexts[2]=fresh;tokens[2]=registration','contexts[2]=context;tokens[2]=registration')),
    ('red-no-retirement',actual.replace('local.admission.retire()','// omitted retirement')),
    ('red-no-rollback-start',actual.replace('let status=AudioOutputUnitStart(unit)','let status:Int32=0')),
]:
    mutant=logs/'MutantAdapter.swift';mutant.write_text(text)
    for language in ['5','6']:
        for optimization in ['Onone','O']:
            name=f'adapter-{variant}-{language}-{optimization}';executable=logs/'witness'
            cmd=[os.environ.get('SWIFTC','swiftc'),'-swift-version',language,'-strict-concurrency=complete','-'+optimization,str(source),str(mutant),str(here/'AdapterTests.swift'),'-o',str(executable)]
            q=subprocess.run(cmd,capture_output=True,text=True);(logs/(name+'-compile.log')).write_text(q.stdout+q.stderr);assert q.returncode==0,q.stderr
            q=subprocess.run([str(executable)],capture_output=True,text=True);(logs/(name+'-run.log')).write_text(q.stdout+q.stderr);assert q.returncode!=0,variant
            rows.append(dict(suite='adapter',variant=variant,language=language,optimization=optimization,exit=q.returncode,command=cmd))
            print(name,'KILLED',flush=True)
(logs/'MutantAdapter.swift').unlink(missing_ok=True)
(logs/'RESULTS.json').write_text(json.dumps(rows,indent=2)+'\n')
(logs/'SOURCE-SHA256.json').write_text(json.dumps(manifest,indent=2)+'\n')
(logs/'witness').unlink(missing_ok=True)
(logs/'MutantTransaction.swift').unlink(missing_ok=True)
