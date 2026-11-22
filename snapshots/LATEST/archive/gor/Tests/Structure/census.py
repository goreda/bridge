"""Token census of Sources/gor against a baseline ref. Baseline selection, first match wins:
--baseline <ref>, else CENSUS_BASELINE, else a positional ref, else the historical faa9d2ab.
The default run SEPARATES historical replay from the live guard: the replay compares the whole
token multiset against the baseline (layout-agnostic: the split preserved tokens, so a pre-split
baseline still lines up), and the live guard pins the current tree's 199az rule conjunction and
the ledger-pinned post-split edits independently of the baseline.

199az (owner 2026-11-21, blink in normal playback): the CaptureConsumerRules.blinkShouldRun
conjunction dropped `vrEnabled`, losing exactly one 'vrEnabled' and two '&' tokens ('&&'
tokenizes as two '&'; comments are not tokens). The gate binds EXACTLY that loss for the rule
edit itself, fixture-vs-live or baseline-vs-live, never a blanket exemption.

Baseline eras: with a split-era baseline (--baseline <lane base>, e.g. 644...) the only allowed
difference is the rule edit. With the pre-split default faa9d2ab there is no
Camera/CaptureConsumerRules.swift on the baseline side, so the allowed difference is the composite
of the recorded post-split edits, computed from the fixture ledger (pp-split-manifest.json
historical_fixture parts, live bytes pinned by current_sha256) - the rule edit among them. Any
other loss or addition, anywhere, turns the run RED. Retire the gate only with a deliberate
re-baseline."""
from pathlib import Path
import hashlib,json,os,re,collections,subprocess,sys
# Ignore comments/import boundary only. Retain all literal/code tokens, then
# compare multisets: declarations and every other token must be unchanged.
pattern=r'//[^\n]*|/\*[\s\S]*?\*/|#?"(?:\\.|[^"\\])*"|\b[A-Za-z_][A-Za-z_0-9]*\b|[^\s]'
def tokens(t):
 t=re.sub(r'^import .*\n|^#(?:if|else|endif).*\n','',t,flags=re.M)
 return [m.group(0) for m in re.finditer(pattern,t) if not m.group(0).startswith(('//','/*'))]

DEFAULT_BASELINE='faa9d2ab369fbc179e1298639d0005a3101a852e'
def baseline_ref(argv):
 """--baseline <ref> > CENSUS_BASELINE > positional ref > DEFAULT_BASELINE."""
 if '--baseline' in argv:
  i=argv.index('--baseline');assert i+1<len(argv),'--baseline needs a ref';return argv[i+1]
 env=os.environ.get('CENSUS_BASELINE')
 if env:return env
 pos=[a for a in argv[1:] if not a.startswith('--')]
 return pos[0] if pos else DEFAULT_BASELINE

GATE_FILE='Camera/CaptureConsumerRules.swift'
GATE_PART='CaptureConsumerRules.swift'
GATE_OLD='blinkOn && vrEnabled && loadedVideoActive && cameraAllowed'
GATE_NEW='blinkOn && loadedVideoActive && cameraAllowed'
GATE_ALLOWED_LOSS={'vrEnabled':1,'&':2}
MANIFEST='Tests/Structure/pp-split-manifest.json'
RETIREMENTS='Tests/Structure/retirements.json'

def _delta(old_text,new_text):
 o=collections.Counter(tokens(old_text));n=collections.Counter(tokens(new_text))
 # Counter subtraction drops non-positive counts, so compute both directions by hand.
 return {t:o[t]-n.get(t,0) for t in o if o[t]-n.get(t,0)>0},{t:n[t]-o.get(t,0) for t in n if n[t]-o.get(t,0)>0}

def _pinned_parts(root):
 """Fixture-backed split parts as (file, historical text, live text); both sides sha-pinned by
 the manifest ledger, so a silent drift of either turns the gate RED instead of being absorbed."""
 man=json.loads((root/MANIFEST).read_text())['files']
 out=[]
 for name in sorted(man):
  for p in man[name]['parts']:
   if 'historical_fixture' not in p:continue
   hist=(root/p['historical_fixture']).read_bytes()
   assert hashlib.sha256(hist).hexdigest()==p['historical_sha256'],'199az gate: fixture drift '+p['file']
   hits=[q for q in (root/'Sources/gor').rglob(p['file']) if q.is_file()]  # 199bv: station-moved parts resolve by name, not by pinned station dir
   assert len(hits)==1,'199az gate: live part not exactly once in tree: '+p['file']
   live=hits[0].read_bytes()
   assert hashlib.sha256(live).hexdigest()==p['current_sha256'],'199az gate: live bytes drift from pinned current_sha256 for '+p['file']
   out.append((p['file'],hist.decode(),live.decode()))
 return out

def gate(before,after,root=None):
 """Historical replay + live guard. Returns (bt, at, mode, allowed_loss, allowed_gain)."""
 assert GATE_FILE in after,'199az gate: '+GATE_FILE+' missing from the tree'
 assert GATE_NEW in after[GATE_FILE],'199az gate: tree lacks the 199az conjunction'
 if GATE_FILE in before:
  mode='split-era baseline'
  assert before[GATE_FILE]!=after[GATE_FILE],'199az gate: '+GATE_FILE+' carries no edit; re-baseline or retire this gate'
  assert GATE_OLD in before[GATE_FILE],'199az gate: baseline lost the pre-edit conjunction'
  prior=before[GATE_FILE]
  allowed_loss,allowed_gain=dict(GATE_ALLOWED_LOSS),{}
  expected={t:-n for t,n in GATE_ALLOWED_LOSS.items()}
 else:
  mode='pre-split baseline (fixture ledger)'
  assert root is not None,'199az gate: pre-split baseline needs the tree root for the fixture ledger'
  assert GATE_OLD in '\n'.join(before.values()),('199az gate: baseline predates the split AND lacks the pre-edit conjunction - wrong baseline; pass --baseline <split-era commit>')
  parts=_pinned_parts(root)
  assert any(f==GATE_PART for f,_,_ in parts),'199az gate: fixture ledger lost the '+GATE_PART+' entry'
  prior=next(h for f,h,_ in parts if f==GATE_PART)
  # The multiset is global, so the allowance is the NET signed delta of the recorded edits:
  # a token one edit adds and another removes nets out, exactly as Counter subtraction nets it.
  signed=collections.Counter()
  for _,h,l in parts:
   signed.update(collections.Counter(tokens(l)));signed.subtract(collections.Counter(tokens(h)))
  allowed_loss={t:-n for t,n in signed.items() if n<0};allowed_gain={t:n for t,n in signed.items() if n>0}
  expected=dict(signed)
 # The rule edit itself is bound exactly, whichever side supplied the pre-edit bytes.
 loss,gain=_delta(prior,after[GATE_FILE])
 assert loss==GATE_ALLOWED_LOSS and not gain,('199az gate: the rule edit must be exactly '+json.dumps(GATE_ALLOWED_LOSS)+' lost, nothing gained',loss,gain)
 bt=[t for s in before.values() for t in tokens(s)];at=[t for s in after.values() for t in tokens(s)]
 lost=collections.Counter(bt)-collections.Counter(at);gained=collections.Counter(at)-collections.Counter(bt)
 assert dict(lost)==allowed_loss,('199az gate: token loss differs from the recorded post-split edits',dict(lost),'allowed',allowed_loss)
 assert dict(gained)==allowed_gain,('199az gate: unexpected token additions',dict(gained),'allowed',allowed_gain)
 return bt,at,mode,allowed_loss,allowed_gain,expected

def compare(before,after,root,retired):
 """Full census comparison: gate + keyword census + hub coverage + per-name byte equality."""
 bt,at,mode,allowed_loss,allowed_gain,expected=gate(before,after,root)
 keys=['class','struct','enum','protocol','typealias','func','var','let','case','objc']
 a={k:bt.count(k) for k in keys};b={k:at.count(k) for k in keys}
 for k in keys:assert b[k]-a[k]==expected.get(k,0),('keyword census differs from the recorded post-split edits',k,a[k],b[k],expected.get(k,0))
 hubs=[]
 for name in ['PPController.swift','AppDelegate.swift','SubtitleView.swift']:
  if name in after:assert before[name]==after[name];hubs.append(name+'=bytes')
  else:
   assert name in retired,('hub file neither in the tree nor in the retirement ledger: '+name)
   hubs.append(name+'=retirement-ledger')
 for name in before:
  if name in after and name not in ('Diag.swift',GATE_FILE):assert before[name]==after[name],name
 return bt,at,a,b,mode,allowed_loss,allowed_gain,hubs,expected

def main():
 r=Path(__file__).resolve().parents[2];src=r/'Sources/gor';ref=baseline_ref(sys.argv)
 repo=Path(subprocess.check_output(['git','-C',str(r),'rev-parse','--show-toplevel'],text=True).strip())
 source_prefix=src.relative_to(repo).as_posix()+'/'
 paths=subprocess.check_output(['git','-C',str(repo),'ls-tree','-r','--name-only',ref,'--',source_prefix],text=True).splitlines()
 before={p.removeprefix(source_prefix):subprocess.check_output(['git','-C',str(repo),'show',ref+':'+p],text=True) for p in paths if p.endswith('.swift')}
 assert before, 'baseline source tree is empty: '+source_prefix
 after={str(p.relative_to(src)):p.read_text() for p in src.rglob('*.swift')}
 retired={e['path'].removeprefix('Sources/gor/') for e in json.loads((r/RETIREMENTS).read_text())['entries']}
 bt,at,a,b,mode,allowed_loss,allowed_gain,hubs,expected=compare(before,after,r,retired)
 report={'baseline':ref,'gate_mode':mode,'199az_allowed_loss':allowed_loss,'199az_allowed_gain':allowed_gain,'hub_coverage':hubs,'before_files':len(before),'after_files':len(after),'before':a,'after':b,'token_count':len(bt),'code_token_multiset':'strict; allowed delta = '+json.dumps({'loss':allowed_loss,'gain':allowed_gain}),'top5':[]}
 for name,text in sorted(before.items(),key=lambda n:len(n[1].splitlines()),reverse=True)[:5]:
  if name in after:report['top5'].append({'path':name,'before':len(text.splitlines()),'after':len(after[name].splitlines()),'delta':len(after[name].splitlines())-len(text.splitlines())})
 print(json.dumps(report,indent=2))

if __name__=='__main__':main()
