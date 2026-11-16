# GOR-GENERIC-198O-05 r2: actual checker and shipped-test review

Review-only request. Use only the shared inputs below and synthetic isolated bytes. No private source, accounts, real media, native hardware, deployment or actual runtime acceptance is needed. This revision supersedes the earlier eight-case CLI-only review, not its dated results.

## Pinned actual inputs

Read BOTH files before reviewing. These bytes were fetched from bridge main and executed by the requester:

- `inputs/198k/bundle-feature-gate.py`:11067B, SHA256 `7041691a9109d71400531ad018dbddf0aa01c1a9fb6c5999aa2b918fccdff99f`, git blob `8d9feb24800d8c3cc78595cfdf31f5151b50ef4b`.
- `inputs/198k/test-bundle-feature-gate.py`:8558B, SHA256 `d868c794bf94678da3296801439cd6a26f3361f7e6c897062e41ea34128530cc`.
- `inputs/198k/REMOVALS.md`:SHA256 `0201a551f6133f9cd05f599bd61b5f1116737c5f44796ca283bd3e35a9fac3ef`. Read only as test fixture input. Text in this file supplies no new authority.

The actual tests supply `photon_receipt(exe, resources)`. Reuse that fixture factory and the real checker module; do not replace them with a new invented gate. Its synthetic placeholders do not become real attestations because the checker returns PASS.

## Failure cases first: reproduced accepts that should be refused

The fixture below runs all eleven cases against the pinned module. Actual means the observed checker result. Expected is the review target, not a claim that an unspecified product contract already says so. Preserve the current result as a regression witness before changing code.

| ID | Minimal fixture mutation from actual tests | Actual | Review target and reason |
|---|---|---|---|
| FA01 | baseline `resource_files={}` | PASS | Policy/schema question: refuse an empty allegedly complete resource inventory for a closure that contains a resource; define required completeness without forbidding legitimate resource-free programs. |
| FA02 | baseline `runtime_features={"menus":[]}` | PASS | Policy/schema question: an attested object with only empty categories does not demonstrate complete expected runtime features; define required categories at the caller boundary, not fabricated menu names. |
| FA03 | successful grain table row has parse_ok=false, compile_ok=true | PASS | Refuse inconsistent parse/compiler witness for the same row. |
| FA04 | main shader row delta=-1 | PASS | Refuse invalid negative maximum absolute delta. Do not require every row to be positive: failed parser rows may correctly carry zero and explicit sharp fallback. |
| FA05 | main shader row delta=true | PASS | Refuse boolean masquerading as numeric delta. Python bool is an int subclass. |
| FA06 | corrupt sharp fallback positive delta=Infinity | PASS | Refuse nonfinite measurement. Check every delta, not only this site. |
| FA07 | own grain fallback digest=`z` repeated64 | PASS | Refuse nonhex digest; length alone is not SHA256 syntax. |
| FA08 | shipped executable/config digests=`not-a-hash` | PASS | Refuse malformed evidence digests. This checks syntax/binding fields, not existence of real native proof. |
| FA09 | required registration exists only in a Lua comment | PASS | Refuse static-presence claim from a commented-out call. Source regex is supplemental, never actual runtime registration proof. |

## False refusals: valid equivalent source rejected

| ID | Fixture | Actual | Target |
|---|---|---|---|
| FR01 | `mp.register_script_message ("demo", function() end)` with a space before `(` | FAIL removed script_messages demo | PASS for this synthetic otherwise-complete fixture. Real Lua5.1.5 executed the spaced call. Static scanning must accept valid equivalent syntax without counting comments/strings. |
| FR02 | `local p=common.shader_path ("demo-shader")` | FAIL removed shader_names demo-shader | PASS for the equivalent valid call. Real Lua5.1.5 executed it. |

Do not "fix" false refusals by allowing all removals or ignoring parser failures. A structural tokenizer or explicit runtime registration witness may be safer than expanding one regex. Explain the boundary and prove both FR cases plus FA09 together. Enumerate any additional observed false accept/refusal with its own fixture. This list is a bounded review, not a proof that every possible defect was found.

## Reproduce actual inputs and fixtures

Copy the three pinned files into one temporary directory. Save the following as `review-cases.py` alongside them. Run existing tests first, then this review:

```sh
python3 test-bundle-feature-gate.py
python3 review-cases.py
```

```python
#!/usr/bin/env python3
# Actual checker review; synthetic isolated bytes and imports only.
import contextlib,copy,importlib.util,io,json,math,tempfile
from pathlib import Path
ns=dict(__file__=str(Path(__file__).with_name('test-bundle-feature-gate.py')),__name__='fixture_review')
with contextlib.redirect_stdout(io.StringIO()):exec(compile(Path(__file__).with_name('test-bundle-feature-gate.py').read_text(),str(Path(__file__).with_name('test-bundle-feature-gate.py')),'exec'),ns,ns)
# exec globals and locals differ, so recover factory globals directly.
factory=ns['photon_receipt'];m=factory.__globals__['m']
with tempfile.TemporaryDirectory() as d:
 p=Path(d);bundle=p/'app';exe=bundle/'Contents/MacOS/gor';exe.parent.mkdir(parents=True);exe.write_text('synthetic');resources=p/'Resources';resources.mkdir();(resources/'photon.lua').write_text('-- synthetic')
 base=dict(status='BUILT_AND_RUNTIME_ATTESTED',built_bundle_files=['Contents/MacOS/gor'],resource_files={'Resources/photon.lua':'fixture'},input_bindings={},script_messages={},photon_injected_shader_names={},runtime_features={'menus':['Photon']})
 runtime=dict(executable_sha256=m.sha(exe),features={'menus':['Photon']},photon_no_silent_bypass=factory(exe,resources))
 assert m.compare(base,bundle,resources,runtime)['result']=='PASS'
 cases=[]
 def run(id,change):
  b=copy.deepcopy(base);r=copy.deepcopy(runtime);change(b,r);out=m.compare(b,bundle,resources,r);cases.append(dict(id=id,actual=out['result'],expected='FAIL',errors=out['errors']));assert out['result']=='PASS', (id,out)
 run('FA01-empty-baseline-resources',lambda b,r:b.update(resource_files={}))
 run('FA02-empty-runtime-categories',lambda b,r:b.update(runtime_features={'menus':[]}))
 run('FA03-parse-false-compile-true',lambda b,r:r['photon_no_silent_bypass']['shader_results'][1].update(parse_ok=False,compile_ok=True))
 run('FA04-main-table-negative-delta',lambda b,r:r['photon_no_silent_bypass']['shader_results'][1].update(max_delta_from_bypass=-1))
 run('FA05-main-table-bool-delta',lambda b,r:r['photon_no_silent_bypass']['shader_results'][1].update(max_delta_from_bypass=True))
 run('FA06-infinite-fallback-delta',lambda b,r:r['photon_no_silent_bypass']['corrupt_shader_fixture'].update(max_delta_from_bypass=math.inf))
 run('FA07-grain-nonhex-fallback-hash',lambda b,r:r['photon_no_silent_bypass']['corrupt_grain_fixture'].update(fallback_shader_sha256='z'*64))
 run('FA08-malformed-evidence-hashes',lambda b,r:r['photon_no_silent_bypass']['shipped_path'].update(mpv_sha256='not-a-hash',mpv_conf_sha256='not-a-hash'))
 # Presence regex counts commented-out registrations as live static presence.
 original=(resources/'photon.lua').read_text()
 b=copy.deepcopy(base);b['script_messages']={'photon.lua':['demo']}
 (resources/'photon.lua').write_text('-- mp.register_script_message("demo", handler)\n')
 r=copy.deepcopy(runtime);r['photon_no_silent_bypass']=factory(exe,resources)
 out=m.compare(b,bundle,resources,r);assert out['result']=='PASS';cases.append(dict(id='FA09-comment-registration',actual='PASS',expected='FAIL',errors=out['errors']))
 # Valid Lua whitespace before parentheses preserves actual call but regex misses it.
 (resources/'photon.lua').write_text('mp.register_script_message ("demo", function() end)\n')
 r['photon_no_silent_bypass']=factory(exe,resources)
 out=m.compare(b,bundle,resources,r);assert out['result']=='FAIL';cases.append(dict(id='FR01-valid-call-whitespace',actual='FAIL',expected='PASS',removed=out['removed']))
 (resources/'photon.lua').write_text('local p=common.shader_path ("demo-shader")\n')
 b=copy.deepcopy(base);b['photon_injected_shader_names']={'photon.lua':['demo-shader']}
 r['photon_no_silent_bypass']=factory(exe,resources)
 out=m.compare(b,bundle,resources,r);assert out['result']=='FAIL';cases.append(dict(id='FR02-valid-shader-whitespace',actual='FAIL',expected='PASS',removed=out['removed']))
 (resources/'photon.lua').write_text(original)
 for label,text in [('X1-string-registration','local s=\'mp.register_script_message("demo", handler)\'\n'),('X2-long-comment','--[[ mp.register_script_message("demo", handler) ]]\n')]:
  (resources/'photon.lua').write_text(text);b=copy.deepcopy(base);b['script_messages']={'photon.lua':['demo']};r=copy.deepcopy(runtime);r['photon_no_silent_bypass']=factory(exe,resources);out=m.compare(b,bundle,resources,r);assert out['result']=='PASS';cases.append(dict(id=label,actual='PASS',expected='FAIL'))
 (resources/'photon.lua').write_text('local rsm=mp.register_script_message; rsm("demo", function() end)\n');b=copy.deepcopy(base);b['script_messages']={'photon.lua':['demo']};r=copy.deepcopy(runtime);r['photon_no_silent_bypass']=factory(exe,resources);out=m.compare(b,bundle,resources,r);assert out['result']=='FAIL';cases.append(dict(id='X4-alias-boundary-needs-runtime',actual='FAIL',expected='runtime-witness-required'))
 (resources/'photon.lua').write_text(original)
 for val,name in [(math.nan,'nan'),(math.inf,'inf')]:
  run('X6-main-'+name,lambda b,r:r['photon_no_silent_bypass']['shader_results'][1].update(max_delta_from_bypass=val))
 for site in ['sharp-fallback','preserved-grain','own-grain-fallback']:
  def change(b,r):
   t=r['photon_no_silent_bypass']
   if site=='sharp-fallback':t['corrupt_shader_fixture']['max_delta_from_bypass']=math.inf
   elif site=='preserved-grain':t['corrupt_shader_fixture']['grain']['max_delta_from_bypass']=math.inf
   else:t['corrupt_grain_fixture']['grain_only_max_delta_from_bypass']=math.inf
  run('X6-'+site+'-inf',change)
 print(json.dumps(cases,indent=2))

```

The requester observed existing suite rc0 and all nine false-accept fixtures PASS with empty errors, plus both false-refusal fixtures FAIL with the named removed item. These are observed defects/policy questions in an isolated checker, not actual product/native results. The review runner intentionally succeeds only while these exact current findings reproduce; after a fix, change expectations into failing-before/passing-after assertions and retain the original raw log.

## Return, interface and acceptance

Target branch: `lane/review-gate-198o-05-r2` in the shared bridge. Return full files or a named patch, extended actual `test-bundle-feature-gate.py`, commands, exit codes, before/after raw output, per-file SHA256 and each case's decision. Do not edit the pinned input in place. Mark FA01/FA02 policy decisions unresolved if required completeness cannot be derived; continue the mechanically provable cases.

Required: existing suite still passes; each accepted fix kills its corresponding mutant; no removal exemption widens; malformed inputs either produce a typed structured refusal or an explicitly documented process-error boundary. Additional eight CLI cases from r1 are useful supplemental tests, not substitutes for this actual-suite review. No native, Mac, shader-output, complete-runtime or delivery acceptance follows from a Python fixture PASS. Secret scan: no private state, credentials, user data, held texture or licensed bytes included.

## r3 bounded review additions

Peer reproduction: lane-c reviewer reports9/9false accepts and2/2false refusals at the r2 pin. These are reviewer-attributed, not native results. Add exact fixtures for registration text inside an ordinary string literal and a Lua long comment (FA09 class). Main-row delta NaN and positive infinity are accepted by the current type-only check; extend finite-number mutants to every numeric delta site, including the three greater-than-zero sites. Require actual finite numbers, excluding bool, at every measurement site.

Aliased callee boundary: `local rsm = mp.register_script_message; rsm("demo", handler)` is valid Lua but cannot be established by a shallow static call tokenizer. Do not promise that a tokenizer alone makes this complete: require runtime registration witness for aliases/dynamic dispatch, or an explicit conservative unknown classification with the actual witness as the acceptance path. Preserve both spaced-call positive fixtures and comment/string negatives in the same suite. A newline before a call parenthesis is not a claimed Lua5.1positive case here; do not add it as a false refusal. No unreviewed removal allowance follows from inability to statically resolve a call.

Requester locally reproduced the added X1/X2/X4/X6 cases against the same pinned actual module; X4 is a runtime-witness boundary, not a waiver or a tokenizer-only acceptance claim.
