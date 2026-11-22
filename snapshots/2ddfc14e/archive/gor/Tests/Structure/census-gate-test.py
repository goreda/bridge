#!/usr/bin/env python3
"""199az census gate mutants, both branches of the historical-replay/live-guard split:
split-era baseline (gated file on both sides) and pre-split baseline (fixture-ledger composite).
Accepts EXACTLY the blinkShouldRun rule-edit token loss (one 'vrEnabled', two '&') and turns RED
on a revert, any extra or remote loss, any unrecorded addition, live/fixture byte drift, a
missing ledger entry, a wrong baseline, and broken hub coverage. Synthetic trees only - no git,
no repo history, so it runs anywhere; census.py main() on the real baseline stays with gdb."""
import importlib.util as _iu, pathlib as _pl, json as _j, hashlib as _hl, os as _os, tempfile as _tf
_d=_pl.Path(__file__).resolve().parent
_s=_iu.spec_from_file_location('census',_d/'census.py');census=_iu.module_from_spec(_s);_s.loader.exec_module(census)
G=census.GATE_FILE
OLD='enum R {\n static func f() -> Bool { blinkOn && vrEnabled && loadedVideoActive && cameraAllowed }\n}\n'
NEW='enum R {\n static func f() -> Bool { blinkOn && loadedVideoActive && cameraAllowed }\n}\n'
BASE={G:OLD,'Other.swift':'let x = 1\n'}
GOOD={G:NEW,'Other.swift':'let x = 1\n'}
def red(name,fn,*a):
    try:fn(*a)
    except AssertionError:print('PASS mutant RED:',name);return
    raise AssertionError('mutant accepted: '+name)
def sha(t):return _hl.sha256(t.encode()).hexdigest()
def make_root(tmp,live):
    root=_pl.Path(tmp)
    (root/'Tests/Structure/pp-split-historical').mkdir(parents=True)
    (root/'Sources/gor/Camera').mkdir(parents=True)
    (root/'Tests/Structure/pp-split-historical/CaptureConsumerRules.swift.6888f672.txt').write_text(OLD)
    (root/'Sources/gor/Camera/CaptureConsumerRules.swift').write_text(live)
    part={'file':'CaptureConsumerRules.swift','header_lines':8,'body_lines':14,'historical_fixture':'Tests/Structure/pp-split-historical/CaptureConsumerRules.swift.6888f672.txt','historical_sha256':sha(OLD),'current_sha256':sha(live)}
    (root/'Tests/Structure/pp-split-manifest.json').write_text(_j.dumps({'files':{'PPController_Features.swift':{'sha256':'0'*64,'bytes':0,'lines':0,'preamble':[],'parts':[part]}}}))
    (root/'Tests/Structure/retirements.json').write_text(_j.dumps({'entries':[{'path':'Sources/gor/PPController.swift','sha256':'0'*64,'replacements':{}},{'path':'Sources/gor/SubtitleView.swift','sha256':'0'*64,'replacements':{}}]}))
    return root

# --- Branch 1: split-era baseline (gated file on both sides) ---
census.gate(BASE,GOOD);print('PASS split-era: exact 199az rule edit accepted')
red('split-era revert: gated file carries no edit',census.gate,BASE,dict(BASE))
red('split-era extra loss in another file',census.gate,BASE,{G:NEW,'Other.swift':'let x = \n'})
red('split-era remote lookalike loss without the edit',census.gate,{G:OLD,'Other.swift':'let vrEnabled = a && b\n'},{G:OLD,'Other.swift':'let = a b\n'})
red('split-era token addition',census.gate,BASE,{G:NEW,'Other.swift':'let x = 1 + 2\n'})
red('split-era further edit inside the gated file',census.gate,BASE,{G:NEW.replace(' -> Bool',''),'Other.swift':'let x = 1\n'})
red('split-era baseline conjunction already gone',census.gate,{G:NEW,'Other.swift':'let x = 1\n'},GOOD)

# --- Branch 2: pre-split baseline (file absent; fixture ledger supplies the composite) ---
MONO='// monolith\nlet mono = 1\n'+OLD
PRE_BASE={'PPController_Features.swift':MONO,'AppDelegate.swift':'let app = 2\n'}
PRE_GOOD={G:NEW,'Other.swift':'let mono = 1\n','AppDelegate.swift':'let app = 2\n'}
with _tf.TemporaryDirectory() as tmp:
    root=make_root(tmp,NEW)
    bt,at,mode,al,ag,_exp=census.gate(PRE_BASE,PRE_GOOD,root)
    assert mode.startswith('pre-split') and al=={'vrEnabled':1,'&':2} and ag=={}
    print('PASS pre-split: exact rule edit accepted via the fixture ledger')
    red('pre-split loss elsewhere',census.gate,PRE_BASE,{**PRE_GOOD,'Other.swift':'let mono = \n'},root)
    red('pre-split unrecorded addition',census.gate,PRE_BASE,{**PRE_GOOD,'Other.swift':'let mono = 1 + 2\n'},root)
    red('pre-split tree lacks the conjunction',census.gate,PRE_BASE,{**PRE_GOOD,G:OLD},root)
    red('pre-split gated file deleted from tree',census.gate,PRE_BASE,{k:v for k,v in PRE_GOOD.items() if k!=G},root)
    red('pre-split baseline lacks the pre-edit conjunction',census.gate,{'PPController_Features.swift':'let mono = 1\n','AppDelegate.swift':'let app = 2\n'},PRE_GOOD,root)
    red('pre-split rule edit gains tokens',census.gate,PRE_BASE,PRE_GOOD,make_root(_tf.mkdtemp(),NEW+'let q = 9\n'))
    d2=_tf.mkdtemp();r2=make_root(d2,NEW)
    (r2/'Sources/gor/Camera/CaptureConsumerRules.swift').write_text(NEW+'// comment only\n')
    red('pre-split live byte drift (comment only, tokens unchanged)',census.gate,PRE_BASE,PRE_GOOD,r2)
    d3=_tf.mkdtemp();r3=make_root(d3,NEW)
    (r3/'Tests/Structure/pp-split-historical/CaptureConsumerRules.swift.6888f672.txt').write_text(OLD+'\n')
    red('pre-split fixture byte drift',census.gate,PRE_BASE,PRE_GOOD,r3)
    d4=_tf.mkdtemp();r4=make_root(d4,NEW)
    man=_j.loads((r4/'Tests/Structure/pp-split-manifest.json').read_text());man['files']['PPController_Features.swift']['parts']=[]
    (r4/'Tests/Structure/pp-split-manifest.json').write_text(_j.dumps(man))
    red('pre-split ledger lost the gated part entry',census.gate,PRE_BASE,PRE_GOOD,r4)
    # compare() hub coverage on the same pair
    retired={'PPController.swift','SubtitleView.swift'}
    census.compare(PRE_BASE,PRE_GOOD,root,retired);print('PASS compare: absent hubs covered by the retirement ledger')
    red('compare: absent hub not retired',census.compare,PRE_BASE,PRE_GOOD,root,set())
    red('compare: flat file drift',census.compare,PRE_BASE,{**PRE_GOOD,'AppDelegate.swift':'let app = 3\n'},root,retired)
    red('compare: moved-part token drift',census.compare,PRE_BASE,{**PRE_GOOD,G:NEW.replace('cameraAllowed','cameraAllowed ) && true (')},root,retired)

# --- Baseline selection ---
assert census.baseline_ref(['census.py','--baseline','644abc'])=='644abc'
_os.environ['CENSUS_BASELINE']='env123';assert census.baseline_ref(['census.py'])=='env123'
assert census.baseline_ref(['census.py','--baseline','flag456'])=='flag456'
del _os.environ['CENSUS_BASELINE']
assert census.baseline_ref(['census.py','deadbee'])=='deadbee'
assert census.baseline_ref(['census.py'])==census.DEFAULT_BASELINE
print('PASS baseline selection: --baseline > CENSUS_BASELINE > positional > default')
print('PASS census 199az gate: split-era 6 mutants, pre-split 9 mutants + 3 compare mutants, baseline selection')
