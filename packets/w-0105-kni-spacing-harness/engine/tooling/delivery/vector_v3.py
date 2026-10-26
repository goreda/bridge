#!/usr/bin/env python3
"""Separate v2 outline gate. V1 interfaces and schemas are never widened."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import jsonschema

METHOD='merged-flattened-area-sampled-hausdorff-v2'
MEASUREMENT='kni.vector-measurements.v3'
MANIFEST='kni.vector-input-manifest.v3'
RECEIPT='kni.vector-delivery-gate.v3'
BINDINGS=('reference_font_sha256','candidate_font_sha256','upm','params','method','scope')
METRICS={'symmetric_difference_area':('area_floor','unit^2'),'hausdorff':('distance_floor','units')}
class InputError(ValueError): pass

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path):
    def pairs(items):
        obj={}
        for k,v in items:
            if k in obj:raise InputError('duplicate JSON key')
            obj[k]=v
        return obj
    def constant(v):raise InputError('nonfinite JSON constant')
    try:return json.loads(Path(path).read_bytes(),object_pairs_hook=pairs,parse_constant=constant)
    except (OSError,ValueError) as e:raise InputError(str(e)) from e

def finite_tree(v):
    if isinstance(v,float) and not math.isfinite(v):raise InputError('nonfinite numeric value')
    if isinstance(v,dict):
        for x in v.values():finite_tree(x)
    if isinstance(v,list):
        for x in v:finite_tree(x)

def schema_check(obj,name):
    finite_tree(obj)
    try:jsonschema.Draft202012Validator(read(Path(__file__).parent/'schema'/name)).validate(obj)
    except jsonschema.ValidationError as e:raise InputError('schema: '+e.message) from e

def validate_inputs(manifest,measurements,measured_cmap):
    schema_check(manifest,'vector-input-manifest-v3.schema.json')
    schema_check(measurements,'vector-measurements-v3.schema.json')
    for key in BINDINGS:
        if manifest[key]!=measurements[key]:raise InputError('binding mismatch: '+key)
    if manifest['reference_font_sha256']==manifest['candidate_font_sha256']:raise InputError('identical font hashes forbidden')
    expected=manifest['codepoints']
    if len(set(expected))!=len(expected):raise InputError('duplicate manifest codepoint')
    actual=list(measured_cmap)
    if len(set(actual))!=len(actual) or set(actual)!=set(expected):raise InputError('independent reference cmap mismatch')
    cps=[r['codepoint'] for r in measurements['glyphs']]
    if len(set(cps))!=len(cps):raise InputError('duplicate measurement codepoint')
    if set(cps)!=set(expected):raise InputError('measurement keyset mismatch')
    count=sum(r.get('status')=='n/a' for r in measurements['glyphs'])
    if count!=measurements['n_a_count']:raise InputError('n_a_count mismatch')
    counts={c:0 for c in ('reference_unmeasurable','candidate_missing_or_empty','measurement_error')}
    for row in measurements['glyphs']:
        if row.get('status')=='n/a':
            c=row['reason_class'];f=row['font'];counts[c]+=1
            if c=='reference_unmeasurable' and f!='reference' or c=='candidate_missing_or_empty' and f!='candidate':raise InputError('reason class/font mismatch')
    if counts!=measurements['n_a_by_class']:raise InputError('n_a_by_class mismatch')

def build_receipt(manifest,measurements,measured_cmap,measurement_sha256):
    validate_inputs(manifest,measurements,measured_cmap)
    if len(measurement_sha256)!=64 or any(c not in '0123456789abcdef' for c in measurement_sha256):raise InputError('invalid measurement SHA')
    rows=[];failures=[]
    for glyph in sorted(measurements['glyphs'],key=lambda r:r['codepoint']):
        cp=glyph['codepoint']
        if glyph.get('status')=='n/a':
            failures.append({k:glyph[k] for k in ('codepoint','reason','reason_class','font')})
            continue
        for metric,(limit,unit) in METRICS.items():
            rows.append({'codepoint':cp,'metric':metric,'value':glyph[metric],'limit':glyph[limit],'unit':unit,'pass':glyph[metric]<=glyph[limit]})
    # A single n/a forbids PASS. Failed measured rows still remain numeric.
    status='FAIL' if any(not r['pass'] for r in rows) else ('N/A' if failures else 'PASS')
    result={'schema':RECEIPT,**{k:measurements[k] for k in BINDINGS},'measurement_sha256':measurement_sha256,'status':status,'n_a_count':len(failures),'n_a_by_class':measurements['n_a_by_class'],'glyphs':sorted(measurements['glyphs'],key=lambda r:r['codepoint']),'table_rows':rows,'unmeasurable':failures}
    schema_check(result,'vector-gate-receipt-v3.schema.json')
    return result

def verified_inputs(manifest_path,measurement_path,cmap_path,reference_path,candidate_path):
    manifest=read(manifest_path);measurements=read(measurement_path);cmap=read(cmap_path)
    if not isinstance(cmap,dict) or set(cmap)!={'schema','reference_font_sha256','codepoints'} or cmap['schema']!='kni.measured-cmap.v3':raise InputError('independent cmap schema mismatch')
    if not isinstance(cmap['codepoints'],list) or any(type(c) is not int or not 0<=c<=0x10ffff for c in cmap['codepoints']):raise InputError('invalid independent cmap codepoints')
    schema_check(manifest,'vector-input-manifest-v3.schema.json')
    if sha(reference_path)!=manifest['reference_font_sha256'] or sha(candidate_path)!=manifest['candidate_font_sha256']:raise InputError('font byte hash mismatch')
    if cmap['reference_font_sha256']!=manifest['reference_font_sha256']:raise InputError('independent cmap hash mismatch')
    return build_receipt(manifest,measurements,cmap['codepoints'],sha(measurement_path))

def produce(manifest_path,measurement_path,cmap_path,reference_path,candidate_path,output_path):
    receipt=verified_inputs(manifest_path,measurement_path,cmap_path,reference_path,candidate_path)
    Path(output_path).write_text(json.dumps(receipt,sort_keys=True,indent=2,allow_nan=False)+'\n')
    return receipt

def gate(receipt_path,manifest_path,measurement_path,cmap_path,reference_path,candidate_path):
    try:
        expected=verified_inputs(manifest_path,measurement_path,cmap_path,reference_path,candidate_path)
        received=read(receipt_path);schema_check(received,'vector-gate-receipt-v3.schema.json')
        if received!=expected:raise InputError('receipt differs from recomputed hash-bound measurements')
        return {'schema':RECEIPT,'status':expected['status'],'receipt_sha256':sha(receipt_path),'n_a_count':expected['n_a_count'],'n_a_by_class':expected['n_a_by_class'],'candidate_missing_or_empty_flag':expected['n_a_by_class']['candidate_missing_or_empty']>0,'candidate_attributed_n_a_flag':any(r['font'] in ('candidate','both') for r in expected['unmeasurable']),'failures':[] if expected['status']=='PASS' else ['outline measurements are not all passing']}
    except InputError as e:return {'schema':RECEIPT,'status':'FAIL','failures':[str(e)]}

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['produce','gate'])
    for n in ['manifest','measurements','cmap','reference','candidate','receipt']:p.add_argument('--'+n,required=True)
    a=p.parse_args();args=(a.manifest,a.measurements,a.cmap,a.reference,a.candidate)
    try:r=produce(*args,a.receipt) if a.action=='produce' else gate(a.receipt,*args)
    except InputError as e:p.exit(2,'input error: '+str(e)+'\n')
    print(json.dumps(r,sort_keys=True));return 0 if r['status']=='PASS' else 1
if __name__=='__main__':raise SystemExit(main())
