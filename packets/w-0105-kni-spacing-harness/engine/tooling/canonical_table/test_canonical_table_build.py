import csv
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import canonical_table_build as b

class SyntheticBuilder(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.m = {'schema_version':b.SCHEMA_VERSION,'numeric_comparison':{'label':'CONVENTION','relative_tolerance':'0','absolute_tolerance':'0'},'files':{},'metadata_checks':[],
                  'style_pools':[{'family':'Synthetic','style':'Plain','pool':'synthetic_pool'}],'expected_output_rows':4,'blocks':[]}
        header = ['schema_version','family','style','engine','cp','iou','nodes','pool']
        comps = []
        for e in ('engine_a','engine_b'):
            for cp, iou, nodes in [('0041','0.5','2'),('0042','1.0','4')]:
                comps.append(dict(schema_version=b.SCHEMA_VERSION,family='Synthetic',style='Plain',engine=e,cp=cp,iou=iou,nodes=nodes,pool='synthetic_pool'))
        self.write('components',header,comps)
        self.write('perstyle',['schema_version','family','style','engine','n','mean_iou','median_iou','mean_nodes','median_nodes'],[dict(schema_version=b.SCHEMA_VERSION,family='Synthetic',style='Plain',engine=e,n='2',mean_iou='0.75',median_iou='0.75',mean_nodes='3.0',median_nodes='3.0') for e in ('engine_a','engine_b')])
        self.write('frames',['schema_version','style','tiles','translation'],[dict(schema_version=b.SCHEMA_VERSION,style='Synthetic|Plain',tiles='2',translation='explicit')])
        self.m['blocks'] = [dict(kind='frames',file='frames',style_column='style',expected_styles=[['Synthetic','Plain']],source_files=['frames'],fields={'block':'01_FRAME','n':{'context':'tiles'},'translation':{'context':'translation'}}),
              dict(kind='perstyle',join='family_style_engine',components='components',perstyle='perstyle',metadata_file='',engines=['engine_a','engine_b'],expected_styles=[['Synthetic','Plain']],rows_per_group=2,columns={'family':'family','style':'style','engine':'engine','codepoint':'cp','iou':'iou','nodes':'nodes'},required_values={},compare_metrics=['n','mean_iou','median_iou','mean_nodes','median_nodes'],fields={'block':'02_SUMMARY','frame':'synthetic_frame','sample_base':'synthetic_sample'},engine_fields={'engine_a':{},'engine_b':{}},source_files=['components','perstyle'],crosschecks=[]),
              dict(kind='exclusions',expected_styles=[['Synthetic','Plain']],source_files=['frames'],fields={'block':'03_EXCLUSIONS','grounding':'UNGROUNDED'})]
        self.save()
    def write(self,name,header,rows):
        path = self.root/(name+'.tsv')
        with path.open('w',encoding='utf-8',newline='') as f:
            w=csv.DictWriter(f,header,delimiter='\t',lineterminator='\n');w.writeheader();w.writerows(rows)
        self.m['files'][name]={'path':path.name,'sha256':b.digest(path.read_bytes()),'kind':'tsv','header':header}
    def save(self):
        self.manifest = self.root/'manifest.json';self.manifest.write_text(json.dumps(self.m))
    def run_build(self):
        self.save();return b.build(self.manifest,self.root)
    def expect(self,code):
        with self.assertRaises(b.BuildError) as ctx:self.run_build()
        self.assertEqual(ctx.exception.code,code)
    def test_deterministic_header_format_and_derived_count(self):
        rows=self.run_build();payload=b.render(rows)
        self.assertEqual(payload,b.render(self.run_build()))
        self.assertEqual(payload.splitlines()[0].decode().split('\t'),b.FIELDS)
        self.assertEqual(len(rows),1+2+1)
        self.assertEqual(rows[1]['mean_iou'],'0.75')
        self.assertEqual(rows[1]['mean_nodes'],'3.0')
        self.assertEqual(rows[1]['C2_missing_extrema'] if 'C2_missing_extrema' in rows[1] else '', '')
        parsed=list(csv.DictReader(__import__('io').StringIO(payload.decode()),delimiter='\t'))
        self.assertEqual(len(parsed),4)
        self.assertFalse(any(None in row for row in parsed))
        self.assertEqual(json.loads(parsed[1]['perstyle_source_json'])['n'],'2')
    def test_checksum(self):
        with (self.root/'components.tsv').open('a') as f:f.write('\n')
        self.expect(b.ErrorCode.CHECKSUM)
    def test_schema_and_missing_configuration(self):
        self.m['schema_version']='unknown';self.expect(b.ErrorCode.SCHEMA)
        self.m['schema_version']=b.SCHEMA_VERSION;del self.m['numeric_comparison'];self.expect(b.ErrorCode.SCHEMA)
    def test_row_count_and_engine_set(self):
        self.m['blocks'][1]['rows_per_group']=3;self.expect(b.ErrorCode.COVERAGE)
        self.m['blocks'][1]['rows_per_group']=2;self.m['blocks'][1]['engines'].append('engine_c');self.expect(b.ErrorCode.COVERAGE)
    def test_external_pool_guard(self):
        self.m['style_pools'][0]['pool']='different';self.expect(b.ErrorCode.MISMATCH)
    def test_perstyle_mismatch(self):
        spec=self.m['files']['perstyle'];rows=b.read_tsv((self.root/spec['path']).read_bytes(),spec);rows[0]['mean_iou']='0.1';self.write('perstyle',spec['header'],rows);self.expect(b.ErrorCode.MISMATCH)
    def test_duplicate_codepoint(self):
        spec=self.m['files']['components'];rows=b.read_tsv((self.root/spec['path']).read_bytes(),spec);rows[1]['cp']=rows[0]['cp'];self.write('components',spec['header'],rows);self.expect(b.ErrorCode.KEY)
    def test_nonfinite_and_negative(self):
        spec=self.m['files']['components'];rows=b.read_tsv((self.root/spec['path']).read_bytes(),spec);rows[0]['iou']='nan';self.write('components',spec['header'],rows);self.expect(b.ErrorCode.NUMERIC)
    def test_input_permutation_changes_provenance_only(self):
        first=self.run_build();spec=self.m['files']['components'];rows=b.read_tsv((self.root/spec['path']).read_bytes(),spec);self.write('components',spec['header'],list(reversed(rows)));second=self.run_build()
        for a,z in zip(first,second):
            self.assertEqual({k:v for k,v in a.items() if k!='source_sha256'},{k:v for k,v in z.items() if k!='source_sha256'})
    def test_engine_metadata_join_and_crosscheck(self):
        block=self.m['blocks'][1];block['join']='engine_metadata';block['identity']={'family':'Synthetic','style':'Plain'}
        meta={'schema_version':b.SCHEMA_VERSION,'engines':{'engine_a':{'label':'native_a'},'engine_b':{'label':'native_b'}}}
        path=self.root/'metadata.json';path.write_text(json.dumps(meta));self.m['files']['metadata']={'path':path.name,'kind':'json','sha256':b.digest(path.read_bytes())};block['metadata_file']='metadata'
        block['engine_fields']={e:{'construction_label':{'metadata':['engines',{'context':'engine'},'label']}} for e in block['engines']}
        self.write('check',['schema_version','engine','codepoint','iou'],[dict(schema_version=b.SCHEMA_VERSION,engine='engine_a',codepoint=cp,iou=iou) for cp,iou in [('0041','0.5'),('0042','1')]])
        block['crosschecks']=[dict(file='check',key=['Synthetic','Plain','engine_a'],engine_column='engine',codepoint_column='codepoint',iou_column='iou')]
        rows=self.run_build();self.assertEqual(rows[1]['construction_label'],'native_a')
        block['crosschecks'][0]['key'][2]='engine_missing';self.expect(b.ErrorCode.COVERAGE)
    def test_override_refused(self):
        self.m['blocks'][1]['fields']['n']='999';self.expect(b.ErrorCode.MISMATCH)
    def test_unknown_join_and_bad_tolerance(self):
        self.m['blocks'][1]['join']='unknown';self.expect(b.ErrorCode.SCHEMA)
        self.m['blocks'][1]['join']='family_style_engine';self.m['numeric_comparison']['relative_tolerance']='-1';self.expect(b.ErrorCode.NUMERIC)
if __name__=='__main__':unittest.main()
