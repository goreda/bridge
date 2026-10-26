#!/usr/bin/env python3
"""Bind canonical build outputs to source intake; never reconstruct missing audits."""
import argparse,hashlib,json
from pathlib import Path
from fontTools.ttLib import TTFont
from baseline_provenance import validate as baseline_validate
from charstring_equiv import same_program

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def build(font_path,intake_path,engine_revision,output):
 font_path=Path(font_path).resolve(); intake_path=Path(intake_path).resolve(); output=Path(output).resolve()
 intake=json.loads(intake_path.read_text());root=intake_path.parent
 font=TTFont(font_path);cmap=font.getBestCmap() or {};rows=[]
 if 'CFF ' not in font:raise ValueError('CFF1 required')
 for r in intake['glyphs']:
  cp=int(r['codepoint'].removeprefix('U+'),16) if isinstance(r['codepoint'],str) else r['codepoint']
  if cp not in cmap:raise ValueError(f'expected mapping U+{cp:04X} absent')
  if r.get('provenance')=='unchanged_baseline':
   digest=baseline_validate(r,root,cp,font,intake['source_identity']);p=dict(r['preserved_baseline']);p['path']=str((root/p['path']).resolve())
   rows.append({'codepoint':f'U+{cp:04X}','provenance':'unchanged_baseline','preserved_baseline':p,'charstring_sha256':digest});continue
  capture=dict(r['capture']);tile=(root/capture['path']).resolve();cap_hash=sha(tile)
  if capture.get('sha256')!=cap_hash:raise ValueError('source intake hash mismatch')
  ap=(root/r['capture_audit']['path']).resolve();audit=json.loads(ap.read_text())
  if r['capture_audit'].get('sha256')!=sha(ap):raise ValueError('audit intake hash mismatch')
  if audit.get('source_png_hex')!=tile.read_bytes().hex():raise ValueError('audit source mismatch')
  cs=font['CFF '].cff.topDictIndex[0].CharStrings[cmap[cp]];cs.compile()
  if not same_program(audit.get('charstring_hex') or '',cs.bytecode):raise ValueError('audit does not match final CFF')
  capture['path']=str(tile)
  rows.append({'codepoint':f'U+{cp:04X}','capture':capture,'capture_audit':{'path':str(ap),'sha256':sha(ap)},'fit':{'engine_revision':engine_revision,**{k:audit[k] for k in ('path','parameters','frame','measurement')}},'charstring_sha256':hashlib.sha256(cs.bytecode).hexdigest()})
 if {int(r['codepoint'][2:],16) for r in rows}!=set(cmap) or len(rows)!=len(cmap):raise ValueError('exact cmap coverage required')
 manifest={'source_revision':intake['source_revision'],'source_identity':intake['source_identity'],'font_sha256':sha(font_path),'required_codepoints':intake.get('required_codepoints',[]),'glyphs':rows}
 output.write_text(json.dumps(manifest,indent=2)+'\n');return manifest
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--font',required=True);p.add_argument('--intake',required=True);p.add_argument('--engine-revision',required=True);p.add_argument('--output',required=True);a=p.parse_args()
 try:build(a.font,a.intake,a.engine_revision,a.output)
 except (ValueError,KeyError,OSError) as e:p.exit(1,str(e)+'\n')
