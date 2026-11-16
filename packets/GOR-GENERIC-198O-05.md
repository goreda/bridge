# GOR-GENERIC-198O-05: failure-first bundle gate review

Status: startable review-only task, synthetic fixtures, no native or product acceptance. No private repository access or Mac required.

## Pinned input

Use only the existing shared input `inputs/198k/bundle-feature-gate.py` at blob `8d9feb24800d8c3cc78595cfdf31f5151b50ef4b`, SHA256 `7041691a9109d71400531ad018dbddf0aa01c1a9fb6c5999aa2b918fccdff99f`, 11067 bytes. Independently fetched at both bridge refs `609445a365560407c7894f4741451022040412b6` and `14c53ca`; bytes and git blob agree. `14c53ca` is the reviewed newer head, not a promise that main remains there.

No external schema/test fixtures supplied: inspect checker contract and generate your own fixtures, report gaps honestly. The adjacent `inputs/198k/test-bundle-feature-gate.py` exists, but is not a required input or supplied fixture for this review. The checker itself is the input contract. Every fixture below is newly made stdlib synthetic data. Do not turn fabricated hash/runtime fields into actual runtime evidence.

## Interface and exact invocation

From bridge root:

```sh
python3 inputs/198k/bundle-feature-gate.py --help
python3 inputs/198k/bundle-feature-gate.py \
  --baseline /tmp/gate-review/baseline.json \
  --bundle /tmp/gate-review/app \
  --resources /tmp/gate-review/resources \
  --runtime /tmp/gate-review/runtime.json \
  --removals /tmp/gate-review/removals.md \
  --out /tmp/gate-review/result.json
```

The embedded runner creates isolated directories and invokes those actual flags. Save it as `/tmp/generic-198o-05-fixtures.py`, then run:

```sh
python3 /tmp/generic-198o-05-fixtures.py inputs/198k/bundle-feature-gate.py
```

## Failure cases before positive control

| Case | Expected actual contract result |
|---|---|
| No `--runtime` | exit1, FAIL, missing runtime receipt |
| Wrong runtime executable digest | exit1, FAIL, executable binding error |
| Omit baseline-named resource file | exit1, FAIL, removed resource |
| Omit baseline-named runtime menu | exit1, FAIL, removed runtime menu |
| Source-only baseline status | exit1, FAIL, baseline not attested |
| Missing app executable | exit1, FAIL, built executable missing |
| Malformed runtime JSON | nonzero process error; structured result is NOT promised |
| Positive synthetic closure | exit0, PASS; fake file is text, not executable/native proof |

Author ran these eight CLI cases against the pinned input:8/8 expected outcomes. These are synthetic schema/CLI checks only. The positive deliberately contains no Lua shader resource, so it does not exercise the checker shader-specific witness branch. Review that branch separately with your own synthetic fixtures; do not call the small positive a complete gate proof.

## Review work

Inspect and extend tests for stale candidate/source binding, changed resource bytes versus resource presence, duplicated/omitted feature IDs, nonfinite numeric proof, malformed types, path traversal, and unearned runtime claims. For each, first establish whether the pinned checker actually declares/enforces the condition. A negative control that is unexpectedly accepted is a finding, not permission to invent a contract or weaken a requirement. Report false positives and process-error gaps with minimal reproducer and path/line. Do not patch the input in place or weaken a gate.

Target branch: `lab/generic-198o-05`. Return: review finding table, minimal patch if appropriate, generated fixtures, exact commands, raw stdout/stderr, expected/actual exit table and input digest. Clearly separate observed checker behavior from proposed policy. No production build, removal permission or device acceptance follows.

## Embedded stdlib-only fixture runner

```python
#!/usr/bin/env python3
"""Synthetic stdlib-only CLI review fixtures; never native runtime proof."""
import copy, hashlib, json, subprocess, sys, tempfile
from pathlib import Path

checker = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    exe = p / 'app/Contents/MacOS/gor'
    exe.parent.mkdir(parents=True)
    exe.write_bytes(b'synthetic-not-executable\n')
    resources = p / 'resources'
    resources.mkdir()
    (resources / 'fixture.txt').write_text('synthetic resource\n')
    baseline = dict(status='BUILT_AND_RUNTIME_ATTESTED',
                    built_bundle_files=['Contents/MacOS/gor'],
                    resource_files={'Resources/fixture.txt':'synthetic'},
                    input_bindings={}, script_messages={},
                    photon_injected_shader_names={}, runtime_features={'menus':['fixture-menu']})
    runtime = dict(executable_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(),
                   features={'menus':['fixture-menu']})
    (p/'removals.md').write_text('')
    cases = [
        ('missing-runtime','FAIL'), ('wrong-executable-hash','FAIL'),
        ('missing-required-resource','FAIL'), ('missing-menu','FAIL'),
        ('source-only-baseline','FAIL'), ('missing-executable','FAIL'),
        ('malformed-runtime-json','PROCESS_ERROR'), ('positive-synthetic','PASS')]
    for name, expected in cases:
        b,r=copy.deepcopy(baseline),copy.deepcopy(runtime)
        resource=resources/'fixture.txt'
        resource.write_text('synthetic resource\n')
        exe.write_bytes(b'synthetic-not-executable\n')
        if name=='wrong-executable-hash':r['executable_sha256']='wrong'
        if name=='missing-required-resource':resource.unlink()
        if name=='missing-menu':r['features']['menus']=[]
        if name=='source-only-baseline':b['status']='SOURCE_ONLY'
        if name=='missing-executable':exe.unlink()
        (p/'baseline.json').write_text(json.dumps(b))
        (p/'runtime.json').write_text('{' if name=='malformed-runtime-json' else json.dumps(r))
        out=p/'result.json'
        out.unlink(missing_ok=True)
        command=[sys.executable,str(checker),'--baseline',str(p/'baseline.json'),
                 '--bundle',str(p/'app'),'--resources',str(resources),
                 '--removals',str(p/'removals.md'),'--out',str(out)]
        if name!='missing-runtime':command+=['--runtime',str(p/'runtime.json')]
        result=subprocess.run(command,text=True,capture_output=True)
        body=json.loads(out.read_text()) if out.exists() else None
        actual=body['result'] if body else 'PROCESS_ERROR'
        assert actual==expected,(name,expected,actual,result.stderr)
        assert (result.returncode==0)==(expected=='PASS'),name
        print(json.dumps(dict(case=name,expected=expected,actual=actual,
                              exit=result.returncode,errors=body['errors'] if body else [],
                              removed=body['removed'] if body else {},
                              stderr=result.stderr.strip()),sort_keys=True))
    print('8/8 synthetic CLI cases passed; no product/native/runtime attestation')
```
