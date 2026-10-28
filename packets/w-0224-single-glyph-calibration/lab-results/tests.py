import harness as h,math,json,pathlib,random
R=pathlib.Path(__file__).parent
# Split seed implementation uses original inputs, not already shuffled inputs.
m=json.loads((R/'font-manifest.json').read_text());rng=random.Random(m['seed'])
for style,names in m['style_inputs'].items():
 names=list(names);rng.shuffle(names)
 for co,name in zip(['calibration','validation','test'],names):assert any(f['slug']==name and f['cohort']==co and f['style']==style for f in m['fonts'])
assert len({f['family'] for f in m['fonts']})==len(m['fonts'])
assert h.normalize(('A',.7,-.356)).reject_available is False
assert h.normalize(None) is None
assert isinstance(h.normalize(h.Abstain('x','y')),h.Abstain)
for bad in [('A',float('nan')),('?',.7),('A',1.1),h.Prediction('A',.8,None,True,False)]:
 try:h.normalize(bad);raise AssertionError('bad accepted')
 except ValueError:pass
assert h.rate(0,0)['value'] is None
assert h.bucket(0,[0,.5,1])==0 and h.bucket(.5,[0,.5,1])==1 and h.bucket(1,[0,.5,1])==1
rows=h.fixture_rows()
try:h.fit_calibration(rows,[0,.5,1]);raise AssertionError('leakage accepted')
except ValueError:pass
# Missing/abstain never increase all-input numerator or coverage, nor vanish.
rs=[h.record(dict(cohort='test',family='x',truth='A',frame_size=384),v) for v in [h.Prediction('A',.9),None,h.Abstain('x','y')]]
s=h.summary(rs,[0,.5,1],{'edges':[0,.5,1],'values':[None,.9]});assert s['all_input_recall']['value']==1/3 and s['coverage']['value']==1/3
assert s['reject_head_false_accept'] is None
# No gate means no output renders.
try:h.render(R/'font-manifest.json',R/'font-cache',R/'must-not-exist',R/'missing-gate.json');raise AssertionError('missing gate accepted')
except FileNotFoundError:pass
print('PASS: fixture, label-order, seeded family split, denominator, abstain, missing, bucket boundaries, malformed predictions, calibration leakage, reject ambiguity, gate refusal')
import copy
# Negative regressions: reject invalid provenance BEFORE any calibration/report.
for name,mutate in [
 ('family overlap',lambda rr:[r.update(family='THE-SAME-FONT') for r in rr]),
 ('binary overlap',lambda rr:[r.update(font_sha256='same-font-bytes') for r in rr]),
 ('unknown cohort',lambda rr:rr[0].update(cohort='tesst')),
 ('absent calibration',lambda rr:rr.__setitem__(slice(None),[r for r in rr if r['cohort']!='calibration'])),
 ('no calibration predictions',lambda rr:[r.update(status='missing') for r in rr if r['cohort']=='calibration']),
 ('duplicate row',lambda rr:rr.append(rr[0].copy())),
 ('fixture provenance',lambda rr:rr[0].pop('fixture_provenance'))]:
 rr=copy.deepcopy(rows);mutate(rr)
 try:h.evaluate(rr,fixture=True);raise AssertionError(name+' accepted')
 except ValueError:pass
try:h.evaluate(rows);raise AssertionError('no manifest accepted')
except ValueError:pass
fake_manifest={'fonts':[{'family':'synthetic-'+co,'sha256':h.hashlib.sha256(('synthetic-'+co).encode()).hexdigest(),'cohort':co} for co in ['calibration','validation','test']]}
h.validate_rows(rows,fake_manifest)
for key,val in [('family','unlisted'),('font_sha256','wrong'),('cohort','validation')]:
 rr=copy.deepcopy(rows);rr[0][key]=val
 try:h.evaluate(rr,fake_manifest);raise AssertionError('manifest mismatch accepted')
 except ValueError:pass
print('PASS: negative family/SHA overlap, unknown cohort, absent/empty calibration, duplicate ID, missing fixture provenance, missing manifest, manifest membership/hash/assignment')
# Explicit partial reports, not silent cohort loss.
for omitted in ['validation','test']:
 rr=[r for r in rows if r['cohort']!=omitted];missing=['synthetic-'+omitted]
 out=h.evaluate(rr,fake_manifest,missing_families=missing)
 assert out['status']=='partial' and out['cohorts'][omitted]['status']=='not_measured' and out['cohorts'][omitted]['metrics'] is None
 assert out['input_reconciliation']['input_rows']==len(rr)
rr=[r for r in rows if r['cohort']!='calibration']
out=h.evaluate(rr,fake_manifest,missing_families=['synthetic-calibration'])
assert out['status']=='partial_refusal' and out['calibrator'] is None
for missing,rr in [(['typo'],rows),(['synthetic-test'],rows),([], [r for r in rows if r['cohort']!='test'])]:
 try:h.evaluate(rr,fake_manifest,missing_families=missing);raise AssertionError('bad partial accepted')
 except ValueError:pass
rr=[r for r in rows if r['cohort']!='test'];rr=copy.deepcopy(rr);rr[0]['cohort']='tesst'
try:h.evaluate(rr,fake_manifest,missing_families=['synthetic-test']);raise AssertionError('partial typo accepted')
except ValueError:pass
print('PASS: explicit missing validation/test partial null metrics, missing calibration typed partial refusal, unknown/contradictory/undeclared missing families and typo refusal')

rr=copy.deepcopy([r for r in rows if r["cohort"]!="test"])
for r in rr:
 if r["cohort"]=="calibration":r["status"]="missing"
out=h.evaluate(rr,fake_manifest,missing_families=["synthetic-test"])
assert out["status"]=="partial_refusal" and out["calibrator"] is None
