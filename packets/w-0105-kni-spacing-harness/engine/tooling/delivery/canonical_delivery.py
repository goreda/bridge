#!/usr/bin/env python3
"""Canonical production entrypoint: capture batch -> CFF font -> bound manifest -> sweep.
A numeric candidate is not deliverable until a separate visual seal approves it.
"""
import argparse,hashlib,json,subprocess
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.misc.psCharStrings import T2CharString
from build_delivery_manifest import build
from delivery_gate import evaluate
from baseline_provenance import validate as baseline_validate

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def run(plan_path,audit_binary,output,ppem,threshold,review=None):
 plan_path=Path(plan_path).resolve();root=plan_path.parent;plan=json.loads(plan_path.read_text());out=Path(output).resolve()
 if out.exists() and any(out.iterdir()):raise ValueError('fresh output directory required; refusing stale receipts/evidence')
 if ppem<=0 or not 0<threshold<256:raise ValueError('invalid render contract')
 out.mkdir(parents=True,exist_ok=True);(out/'audits').mkdir(exist_ok=True)
 base=(root/plan['base_font']['path']).resolve()
 if sha(base)!=plan['base_font']['sha256']:raise ValueError('base font hash mismatch')
 vector_ref=plan.get('vector_receipt',{})
 vector_path=(root/vector_ref.get('path','__missing__')).resolve()
 if not vector_path.is_file() or vector_ref.get('sha256')!=sha(vector_path):raise ValueError('vector receipt missing/hash mismatch')
 try:
  vector_receipt=json.loads(vector_path.read_text())
 except (OSError,json.JSONDecodeError) as e:raise ValueError('vector receipt unreadable') from e
 if vector_receipt.get('source_font_sha256')!=plan['base_font']['sha256']:raise ValueError('vector receipt must bind the pinned reference font')
 if vector_receipt.get('status')!='PASS':raise ValueError('vector receipt status is not PASS')
 if sha(audit_binary)!=plan['audit_binary_sha256']:raise ValueError('audit binary hash mismatch')
 if not plan.get('engine_revision'):raise ValueError('engine revision required')
 if 'require_turkish' in plan:raise ValueError('language-specific requirement field require_turkish is not supported; declare the coverage in required_codepoints')
 font=TTFont(base);cmap=font.getBestCmap() or {}
 if 'CFF ' not in font:raise ValueError('CFF1 required')

 rows=plan['glyphs'];codes=[int(r['codepoint'].removeprefix('U+'),16) if isinstance(r['codepoint'],str) else r['codepoint'] for r in rows]
 if len(set(codes))!=len(codes) or set(codes)!=set(cmap):raise ValueError('plan must cover full final cmap exactly')
 top=font['CFF '].cff.topDictIndex[0];intake=[]
 for cp,r in zip(codes,rows):
  if r.get('provenance')=='unchanged_baseline':
   baseline_validate(r,root,cp,font,plan['source_identity']);preserved=dict(r['preserved_baseline']);preserved['path']=str((root/preserved['path']).resolve())
   intake.append({'codepoint':f'U+{cp:04X}','provenance':'unchanged_baseline','preserved_baseline':preserved});continue
  capture=dict(r['capture']);tile=(root/capture['path']).resolve()
  if sha(tile)!=capture['sha256']:raise ValueError(f'U+{cp:04X}: source tile hash mismatch')
  if capture.get('source_identity')!=plan['source_identity'] or capture.get('synthetic') is not False or capture.get('role')!='glyph':raise ValueError('unbound/wrong/synthetic source')
  ap=out/'audits'/f'U{cp:06X}.json'
  if capture['status']=='intentional_blank':
   # Blank source has no captured ring. Requires its independently produced audit,
   # never invokes a tracing fallback or invents a blank based on Unicode category.
   original=(root/r['capture_audit']['path']).resolve()
   if sha(original)!=r['capture_audit']['sha256']:raise ValueError('blank audit hash mismatch')
   ap.write_bytes(original.read_bytes())
  else:
   fit=r['fit'];p=fit['parameters'];frame=fit['frame'];tx,ty=frame['translation']
   advance=font['hmtx'].metrics[cmap[cp]][0]
   subprocess.run([str(Path(audit_binary).resolve()),str(tile),str(ap),str(p['rdp_eps']),str(frame['scale']),str(p['squared_error']),str(p['max_refits']),str(advance),str(tx),str(ty)],check=True)
  audit=json.loads(ap.read_text())
  if audit['source_png_hex']!=tile.read_bytes().hex():raise ValueError('audit tile bytes mismatch')
  prior=top.CharStrings[cmap[cp]]
  top.CharStrings[cmap[cp]]=T2CharString(bytecode=bytes.fromhex(audit['charstring_hex']),private=prior.private,globalSubrs=prior.globalSubrs)
  capture['path']=str(tile)
  intake.append({'codepoint':f'U+{cp:04X}','capture':capture,'capture_audit':{'path':str(ap),'sha256':sha(ap)}})
 font_path=out/'candidate.otf';font.save(font_path)
 ip=out/'intake.json';ip.write_text(json.dumps({'source_revision':plan['source_revision'],'source_identity':plan['source_identity'],'required_codepoints':plan.get('required_codepoints',[]),'glyphs':intake},indent=2)+'\n')
 mp=out/'manifest.json';build(font_path,ip,plan['engine_revision'],mp)
 gate=evaluate(font_path,mp,out/'evidence',ppem,threshold,vector_path,sha(base))
 if gate['status']!='PASS':raise ValueError('delivery gate failed; inspect evidence/gate.json')
 receipt={'status':'NUMERIC_CANDIDATE_VISUAL_PENDING','base_font_sha256':sha(base),'audit_binary_sha256':sha(audit_binary),'engine_revision':plan['engine_revision'],'plan_sha256':sha(plan_path),'font_sha256':sha(font_path),'cmap_count':len(cmap)}
 if review:
  from seal_evidence import seal
  receipt['visual_seal']=seal(out/'evidence',review);receipt['status']='DELIVERY_READY'
 (out/'run-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');return receipt
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--plan',required=True);p.add_argument('--audit-binary',required=True);p.add_argument('--output',required=True);p.add_argument('--ppem',required=True,type=int);p.add_argument('--threshold',required=True,type=int);p.add_argument('--review');a=p.parse_args()
 try:print(json.dumps(run(a.plan,a.audit_binary,a.output,a.ppem,a.threshold,a.review)))
 except (ValueError,KeyError,OSError,subprocess.CalledProcessError) as e:p.exit(1,str(e)+'\n')
