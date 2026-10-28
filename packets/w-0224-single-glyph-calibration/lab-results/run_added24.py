"""Approved stage1b image-backed fixture, frozen baseline calibration map.
Extension-only score schedule; baseline rows and calibration are never rescored.
"""
import pathlib,json,hashlib,collections
from PIL import Image
import harness as h
R=pathlib.Path(__file__).parent;out=R/'added24-fixture';out.mkdir(exist_ok=True)
doc=json.loads((R/'added24-dataset/dataset.json').read_text());ext=json.loads((R/'extension-stage1b.json').read_text());base=json.loads((R/'font-manifest.json').read_text());baseline_rows=json.loads((R/'approved15-fixture/predictions.json').read_text());baseline_results=json.loads((R/'approved15-fixture/results.json').read_text());families=sorted({r['family'] for r in doc['rows']});mod,decl=h.load_preprocess();rows=[]
for meta in doc['rows']:
 path=R/'added24-dataset'/meta['path'];assert h.sha(path)==meta['image_sha256'];im=Image.open(path);crop,box=h.intake(im)
 if crop is None:value=h.Abstain('TileNoInk','intake blank; production intake refuses before scorer');draw=None
 else:
  t=mod.preprocess(crop,decl);draw=(7*families.index(meta['family'])+11*[256,384,512].index(meta['frame_size'])+13*ord(meta['source_char']))%100
  value=h.FixtureScorer(meta['truth'],draw,meta['kind']).score(crop);meta={**meta,'recognition_bbox':box,'preprocessed_sha256':hashlib.sha256(t.numpy().tobytes()).hexdigest()}
 meta={**meta,'id':'stage1b/'+meta['id'],'fixture_draw':draw,'fixture_scope':'metadata oracle, not recognizer accuracy'};rows.append(h.record(meta,value))
combined_manifest={**base,'fonts':base['fonts']+ext['fonts']};missing=[f['family'] for f in ext['fonts'] if f['slug']=='sairaextracondensed'];combined_rows=baseline_rows+rows
results=h.evaluate(combined_rows,combined_manifest,missing_families=missing);assert results['calibrator']==baseline_results['calibrator'];assert results['cohorts']['validation']==baseline_results['cohorts']['validation']
cal=baseline_results['calibrator'];edges=cal['edges'];separate={'schema':'w0224-stage1b-comparison-v1','scope':'IMAGE-PIPELINE FIXTURE METADATA ORACLE ONLY','missing_families':missing,'calibration':'frozen original baseline5; no new fitting/tuning','baseline_test5':baseline_results['cohorts']['test'],'added_test24':h.summary(rows,edges,cal),'combined_test29':results['cohorts']['test']}
separate['added_test24']['per_font']={f:h.summary([r for r in rows if r['family']==f],edges,cal) for f in families};separate['added_test24']['per_render_size']={str(size):h.summary([r for r in rows if r['frame_size']==size],edges,cal) for size in [256,384,512]}
h.write_json(out/'predictions.json',rows);h.write_json(out/'combined-predictions.json',combined_rows);h.write_json(out/'combined-manifest-derived.json',combined_manifest);h.write_json(out/'results.json',results);h.write_json(out/'separate-baseline-added-combined.json',separate)
# Independent arithmetic check of each score, not just an aggregation replay.
for r in rows:
 d=r['fixture_draw']
 if r['kind']=='blank':assert r['status']=='abstain' and r['abstain_code']=='TileNoInk';continue
 if r['kind']!='glyph':
  assert r['status']==['prediction','prediction','abstain','missing'][d%4]
  if d%4<2:assert r['predicted']=='A' and r['rejected']==(d%4==1)
 else:
  assert r['status']==('prediction' if d<90 else 'abstain' if d<95 else 'missing')
  if d<90:assert r['predicted']==(r['truth'] if d<70 or d>=80 else h.LABELS[(h.LABELS.index(r['truth'])+1)%62]) and r['rejected']==(d>=80)
h.write_json(out/'verification.json',{'passed':True,'added_rows':len(rows),'combined_rows':len(combined_rows),'added_fonts':len(families),'combined_test_fonts':results['cohorts']['test']['font_count'],'dropped_not_rendered':missing,'baseline_calibrator_byte_value_equal':True,'baseline_validation_value_equal':True,'all_added_image_hashes_preprocess_and_known_row_outcomes_checked':True})
print(json.dumps({'added_rows':len(rows),'combined_rows':len(combined_rows),'combined_test_fonts':results['cohorts']['test']['font_count'],'outcomes':dict(collections.Counter(r['status'] for r in rows))}))
