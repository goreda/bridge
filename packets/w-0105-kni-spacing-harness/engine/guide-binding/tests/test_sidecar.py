import importlib.util, unittest, subprocess, json
from pathlib import Path
spec=importlib.util.spec_from_file_location('sidecar',Path(__file__).parents[1]/'tools/capture_audit_sidecar.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Compatibility(unittest.TestCase):
    def setUp(self):
        self.audit={'schema':'kni.capture-audit.v1','frame':{'scale':2.0,'translation':[3.0,-1.0],'capture_origin':[10.0,-20.0],'tile_size':[30,40],'quantization':'nearest_integer'},'float_rings':[{'start':[0.0,100.5],'spans':[{'L':[10.0,100.5]},{'C':[[10.0,90.0],[0.0,90.0],[0.0,-0.5]]}]}],'charstring_hex':'deadbeef'}
        self.binding={'scope':{'font':'fixture','master':'m','style':'s','frame':'y-up'},'audit_frame':self.audit['frame'].copy(),'source_pin':'a'*64,'glyph':'H','classes':['cap'],'edges':[{'edge_id':'a','glyph':'H','class':'cap','membership_evidence':'independent-source-class','source_y':[100.0,100.0]},{'edge_id':'b','glyph':'E','class':'cap','membership_evidence':'independent-source-class','source_y':[100.0,100.0]}],'node_memberships':{'0:0':'a','0:1':'a'}}
    def test_rounding_translation_and_read_only(self):
        before=json.dumps(self.audit,sort_keys=True);stream=m.prepare(self.audit,self.binding)
        self.assertIn('N\t0:0\tH\t100.0\ta',stream);self.assertIn('N\t0:2\tH\t-2.0\t',stream)
        self.assertEqual(before,json.dumps(self.audit,sort_keys=True));self.assertEqual(self.audit['charstring_hex'],'deadbeef')
        exe=Path(__file__).parents[1]/'target/debug/examples/capture_audit_guides'
        result=subprocess.run([exe],input=stream,text=True,capture_output=True,check=True).stdout
        self.assertIn('missing source edge membership',result);self.assertEqual(result.count('no snap, measurement/annotation only'),3)
    def test_frame_mismatch_rejected(self):
        self.binding['audit_frame']['scale']=1.0
        with self.assertRaisesRegex(ValueError,'frame mismatch'):m.prepare(self.audit,self.binding)
    def test_unknown_membership_rejected(self):
        self.binding['node_memberships']['9:9']='a'
        with self.assertRaisesRegex(ValueError,'unknown audit node'):m.prepare(self.audit,self.binding)
    def test_nonfinite_rejected(self):
        self.audit['float_rings'][0]['start'][1]=float('inf')
        with self.assertRaisesRegex(ValueError,'nonfinite'):m.prepare(self.audit,self.binding)
if __name__=='__main__':unittest.main()
