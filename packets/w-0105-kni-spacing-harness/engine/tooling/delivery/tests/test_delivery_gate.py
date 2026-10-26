import copy, importlib.util, json, tempfile, unittest
from pathlib import Path
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw
import sys
base=Path(__file__).parents[1];sys.path.insert(0,str(base/'tools' if (base/'tools').is_dir() else base))
spec=importlib.util.spec_from_file_location('gate',(Path(__file__).parents[1]/'tools/delivery_gate.py' if (Path(__file__).parents[1]/'tools').is_dir() else Path(__file__).parents[1]/'delivery_gate.py'))
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)

class GateTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
  fb=FontBuilder(1000,isTTF=False);fb.setupGlyphOrder(['.notdef','A','space']);fb.setupCharacterMap({65:'A',32:'space'})
  chars={}
  for n in ['.notdef','A','space']:
   p=T2CharStringPen(600,None)
   if n!='space':p.moveTo((50,0));p.lineTo((550,0));p.lineTo((300,700));p.closePath()
   chars[n]=p.getCharString()
  fb.setupCFF('GateTest',{'FullName':'Gate Test','FamilyName':'Gate Test','Weight':'Regular'},chars,{})
  fb.setupHorizontalMetrics({n:(600,0) for n in chars});fb.setupHorizontalHeader(ascent=800,descent=-200)
  fb.setupNameTable({'familyName':'Gate Test','styleName':'Regular','uniqueFontIdentifier':'Gate Test','fullName':'Gate Test','psName':'GateTest'});fb.setupOS2();fb.setupPost()
  self.font=self.root/'test.otf';fb.save(self.font);f=TTFont(self.font)
  rows=[]
  for cp,n in f.getBestCmap().items():
   tile=self.root/f'{cp}.png';im=Image.new('L',(16,16),255)
   if n!='space':ImageDraw.Draw(im).rectangle((2,2,13,13),fill=0)
   im.save(tile);cs=f['CFF '].cff.topDictIndex[0].CharStrings[n];cs.compile()
   rows.append({'codepoint':cp,'capture':{'path':tile.name,'sha256':gate.sha(tile),'source_identity':{'family':'Gate Test','style':'Regular'},'synthetic':False,'role':'glyph','status':'intentional_blank' if n=='space' else 'ink','reason':'source blank' if n=='space' else None},'fit':{'engine_revision':'test','path':'capture_png>fit_captured>integer_charstring','parameters':{'rdp_eps':1},'frame':{'scale':1},'measurement':{'spans':3}},'charstring_sha256':gate.hashlib.sha256(cs.bytecode).hexdigest()})
  for r in rows:
   fit=r['fit'];cs=f['CFF '].cff.topDictIndex[0].CharStrings[f.getBestCmap()[r['codepoint']]];cs.compile()
   ap=self.root/f"{r['codepoint']}.audit.json";ap.write_text(json.dumps({'schema':'kni.capture-audit.v1'}|{k:fit[k] for k in ('path','parameters','frame','measurement')}|{'charstring_hex':cs.bytecode.hex(),'source_png_hex':(self.root/r['capture']['path']).read_bytes().hex()}))
   r['capture_audit']={'path':ap.name,'sha256':gate.sha(ap)}
  self.manifest={'source_identity':{'family':'Gate Test','style':'Regular'},'source_revision':'test','font_sha256':gate.sha(self.font),'glyphs':rows}
 def tearDown(self):self.tmp.cleanup()
 def vector_receipt(self, font, codepoints):
  path=self.root/'vector-receipt.json';glyphs=[];rows=[]
  for cp in codepoints:
   glyphs.append({'codepoint':cp,'path_label':'vector','symmetric_difference_area':0.0,'area_floor':1.0,'hausdorff':0.0,'distance_floor':1.0})
   rows.extend([{'codepoint':cp,'path_label':'vector','metric':'symmetric_difference_area','value':0.0,'limit':1.0,'unit':'unit^2','pass':True},{'codepoint':cp,'path_label':'vector','metric':'hausdorff','value':0.0,'limit':1.0,'unit':'units','pass':True}])
  glyphs=[{**g,'codepoint':int(g['codepoint'].removeprefix('U+'),16) if isinstance(g['codepoint'],str) else g['codepoint']} for g in glyphs]
  rows=[{**r,'codepoint':int(r['codepoint'].removeprefix('U+'),16) if isinstance(r['codepoint'],str) else r['codepoint']} for r in rows]
  path.write_text(json.dumps({'schema':'kni.vector-delivery-gate.v1','source_font_sha256':gate.sha(font),'status':'PASS','glyphs':glyphs,'table_rows':rows}))
  return path
 def run_gate(self,m=None):
  manifest=m or self.manifest;p=self.root/'manifest.json';p.write_text(json.dumps(manifest));v=self.vector_receipt(self.font,[row['codepoint'] for row in manifest['glyphs']]);return gate.evaluate(self.font,p,self.root/'evidence',128,128,v,gate.sha(self.font))
 def test_complete(self):self.assertEqual(self.run_gate()['status'],'PASS')
 def test_vector_gate_failure_blocks_delivery(self):
  p=self.root/'manifest.json';p.write_text(json.dumps(self.manifest));v=self.vector_receipt(self.font,[row['codepoint'] for row in self.manifest['glyphs']]);r=json.loads(v.read_text());r['table_rows'][0]['path_label']='image';v.write_text(json.dumps(r));result=gate.evaluate(self.font,p,self.root/'evidence',128,128,v,gate.sha(self.font));self.assertEqual(result['status'],'FAIL')
 def test_vector_receipt_is_in_evidence_pack(self):
  self.assertEqual(self.run_gate()['status'],'PASS');self.assertTrue((self.root/'evidence/vector-gate-receipt.json').is_file())
 def test_audit_path_is_recorded_per_glyph(self):
  self.run_gate();audit=json.loads((self.root/'evidence/audit.json').read_text());self.assertTrue(all(row['path_label']=='image' and row['audit_path']['source_tile_sha256'] and row['audit_path']['capture_audit'] for row in audit['glyphs']))
 def test_missing_required_codepoint(self):
  self.manifest['required_codepoints']=[0xE000];self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_language_specific_field_rejected(self):
  self.manifest['require_turkish']=True;self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_missing_capture(self):
  self.manifest['glyphs'][0]['capture']['sha256']='bad';self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_noncanonical(self):
  self.manifest['glyphs'][0]['fit']['path']='landed_trace';self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_missing_charstring(self):
  self.manifest['glyphs'][0]['charstring_sha256']='bad';self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_unexpected_blank(self):
  self.manifest['glyphs'][0]['capture']['status']='ink';self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_cmap_gap(self):
  self.manifest['glyphs'].pop();self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_audit_gap(self):
  self.manifest['glyphs'][0].pop('capture_audit');self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_wrong_style(self):
  self.manifest['glyphs'][0]['capture']['source_identity']={'family':'Another','style':'Regular'};self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_synthetic(self):
  self.manifest['glyphs'][0]['capture']['synthetic']=True;self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_fit_gap(self):
  self.manifest['glyphs'][0]['fit'].pop('frame');self.assertEqual(self.run_gate()['status'],'FAIL')
if __name__=='__main__':unittest.main()

class SealTests(GateTests):
 def seal_module(self):
  tool=Path(__file__).parents[1]/'tools' if (Path(__file__).parents[1]/'tools').is_dir() else Path(__file__).parents[1]
  path=tool/'seal_evidence.py'
  if not path.is_file():
   self.skipTest('seal_evidence.py is not included in the supplied base package')
  s=importlib.util.spec_from_file_location('seal',path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
 def review(self):
  self.run_gate();pack=self.root/'evidence';sums=json.loads((pack/'SHA256SUMS.json').read_text());p=self.root/'review.json'
  p.write_text(json.dumps({'reviewer':'test reviewer','status':'APPROVED','font_sha256':gate.sha(self.font),'gate_sha256':gate.sha(pack/'gate.json'),'images':{n:h for n,h in sums.items() if n.endswith('.png')}}));return p
 def test_seal_valid(self):self.assertEqual(self.seal_module().seal(self.root/'evidence',self.review())['status'],'DELIVERY_READY')
 def test_seal_stale(self):
  p=self.review();r=json.loads(p.read_text());r['gate_sha256']='bad';p.write_text(json.dumps(r))
  with self.assertRaises(ValueError):self.seal_module().seal(self.root/'evidence',p)
 def test_seal_incomplete_visual(self):
  p=self.review();r=json.loads(p.read_text());r['images'].pop('U000041.png');p.write_text(json.dumps(r))
  with self.assertRaises(ValueError):self.seal_module().seal(self.root/'evidence',p)
 def test_seal_tamper(self):
  p=self.review();(self.root/'evidence/U000041.png').write_bytes(b'tampered')
  with self.assertRaises(ValueError):self.seal_module().seal(self.root/'evidence',p)

class ManifestTests(GateTests):
 def builder(self):
  base=Path(__file__).parents[1];path=base/'tools/build_delivery_manifest.py' if (base/'tools').is_dir() else base/'build_delivery_manifest.py'
  s=importlib.util.spec_from_file_location('builder',path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
 def test_producer_and_gate(self):
  p=self.root/'intake.json';p.write_text(json.dumps(self.manifest));out=self.root/'built.json'
  m=self.builder().build(self.font,p,'test-engine',out);self.assertNotIn('require_turkish',m);v=self.vector_receipt(self.font,[r['codepoint'] for r in m['glyphs']]);self.assertEqual(gate.evaluate(self.font,out,self.root/'built-evidence',128,128,v,gate.sha(self.font))['status'],'PASS')
 def test_producer_rejects_wrong_final_bytes(self):
  r=self.manifest['glyphs'][0];ap=self.root/r['capture_audit']['path'];audit=json.loads(ap.read_text());audit['charstring_hex']='deadbeef';ap.write_text(json.dumps(audit));r['capture_audit']['sha256']=gate.sha(ap)
  p=self.root/'intake.json';p.write_text(json.dumps(self.manifest))
  with self.assertRaises(ValueError):self.builder().build(self.font,p,'test-engine',self.root/'built.json')

class EntryTests(GateTests):
 def entry(self):
  import sys
  base=Path(__file__).parents[1];tool=base/'tools' if (base/'tools').is_dir() else base;sys.path.insert(0,str(tool))
  sys.path.insert(0,str(tool))
  sys.modules.pop('delivery_gate',None)
  sys.modules.pop('build_delivery_manifest',None)
  sys.modules.pop('vector_gate',None)
  s=importlib.util.spec_from_file_location('entry',tool/'canonical_delivery.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
 def test_entry_mocked_capture(self):
  from unittest.mock import patch
  binary=self.root/'binary';binary.write_bytes(b'test-binary')
  plan=copy.deepcopy(self.manifest);plan.update({'base_font':{'path':str(self.font),'sha256':gate.sha(self.font)},'audit_binary_sha256':gate.sha(binary),'engine_revision':'test'})
  vector_path=self.vector_receipt(self.font,[r['codepoint'] for r in plan['glyphs']])
  plan['vector_receipt']={'path':vector_path.name,'sha256':gate.sha(vector_path)}
  for r in plan['glyphs']:r['fit']={'parameters':{'rdp_eps':1,'squared_error':1,'max_refits':0},'frame':{'scale':1,'translation':[0,0]}}
  p=self.root/'plan.json';p.write_text(json.dumps(plan))
  def fake_run(cmd,check):
   original=self.root/(Path(cmd[1]).stem+'.audit.json');Path(cmd[2]).write_bytes(original.read_bytes())
  entry=self.entry()
  with patch.object(entry.subprocess,'run',side_effect=fake_run):result=entry.run(p,binary,self.root/'production-test',128,128)
  self.assertEqual(result['status'],'NUMERIC_CANDIDATE_VISUAL_PENDING')
  self.assertNotIn('visual_seal',result)
 def test_entry_hash_mismatch(self):
  binary=self.root/'binary';binary.write_bytes(b'test-binary');plan=copy.deepcopy(self.manifest);plan.update({'base_font':{'path':str(self.font),'sha256':'bad'},'audit_binary_sha256':gate.sha(binary),'engine_revision':'test'});p=self.root/'plan.json';p.write_text(json.dumps(plan))
  with self.assertRaises(ValueError):self.entry().run(p,binary,self.root/'production-test',128,128)

class PreserveTests(GateTests):
 def preserved(self):
  r=self.manifest['glyphs'][0];r['provenance']='unchanged_baseline';r['preserved_baseline']={'path':str(self.font),'sha256':gate.sha(self.font),'source_identity':self.manifest['source_identity'],'source_available':False,'reason':'Source scan unavailable, preserve existing cmap mapping','status':'intentional_blank','charstring_sha256':r['charstring_sha256']};r.pop('capture');r.pop('fit');r.pop('capture_audit');return r
 def test_preserve_blank(self):self.preserved();self.assertEqual(self.run_gate()['status'],'PASS')
 def test_preserve_hash_tamper(self):r=self.preserved();r['preserved_baseline']['charstring_sha256']='bad';self.assertEqual(self.run_gate()['status'],'FAIL')
 def test_preserve_wrong_style(self):r=self.preserved();r['preserved_baseline']['source_identity']={};self.assertEqual(self.run_gate()['status'],'FAIL')
