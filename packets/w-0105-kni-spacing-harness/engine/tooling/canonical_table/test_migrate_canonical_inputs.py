import csv,io,json,tempfile,unittest
from pathlib import Path
from canonical_table_build import SCHEMA_VERSION,BuildError,ErrorCode,digest
from migrate_canonical_inputs import PLAN_VERSION,migrate
class SyntheticMigration(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name)
        self.raw=b'family\tstyle\tengine\tcp\tiou\nSynthetic\tPlain\tengine_a\t0041\t0.5000\n'
        (self.root/'old.tsv').write_bytes(self.raw)
        self.plan={'schema_version':PLAN_VERSION,'sources':{'table':{'path':'old.tsv','sha256':digest(self.raw),'rows':1,'header':['family','style','engine','cp','iou']}}}
        self.target={'schema_version':SCHEMA_VERSION,'files':{'table':{'path':'table.tsv','kind':'tsv','sha256':digest(self.raw),'header':['schema_version','family','style','engine','cp','iou']}},'metadata_checks':[]}
        self.p=self.root/'plan.json';self.t=self.root/'target.json'
    def run_migration(self,name='output'):
        self.p.write_text(json.dumps(self.plan));self.t.write_text(json.dumps(self.target));return migrate(self.p,self.t,self.root,self.root/name)
    def test_preserves_values_and_records_new_hash(self):
        self.run_migration();raw=(self.root/'output/table.tsv').read_bytes();rows=list(csv.DictReader(io.StringIO(raw.decode()),delimiter='\t'))
        self.assertEqual(rows[0]['iou'],'0.5000');self.assertEqual(rows[0]['schema_version'],SCHEMA_VERSION)
        m=json.loads((self.root/'output/manifest.json').read_text());self.assertEqual(m['files']['table']['sha256'],digest(raw))
        self.run_migration('other');self.assertEqual(raw,(self.root/'other/table.tsv').read_bytes())
    def test_checksum_and_existing_destination(self):
        self.plan['sources']['table']['sha256']='0'*64
        with self.assertRaises(BuildError) as c:self.run_migration()
        self.assertEqual(c.exception.code,ErrorCode.CHECKSUM);self.assertFalse((self.root/'output').exists())
        self.plan['sources']['table']['sha256']=digest(self.raw);self.run_migration()
        with self.assertRaises(BuildError):self.run_migration()
    def test_header_changes_and_embedded_bindings_fail_closed(self):
        self.target['files']['table']['header'].append('invented')
        with self.assertRaises(BuildError):self.run_migration()
        self.target['files']['table']['header'].pop();self.target['metadata_checks']=[{'example':'binding'}]
        with self.assertRaises(BuildError):self.run_migration()
    def test_missing_and_versioned_inputs_rejected(self):
        self.plan['schema_version']='unknown'
        with self.assertRaises(BuildError):self.run_migration()
    def test_metadata_scalar_preservation(self):
        raw=b'{"render_scale":"1.7000","description":"synthetic"}'
        (self.root/'old.json').write_bytes(raw)
        self.plan['sources']={'meta':{'path':'old.json','sha256':digest(raw)}}
        self.target['files']={'meta':{'path':'meta.json','kind':'json','sha256':digest(raw)}}
        self.run_migration();obj=json.loads((self.root/'output/meta.json').read_text());self.assertEqual(obj['render_scale'],'1.7000')
if __name__=='__main__':unittest.main()

class ExplicitHashMigration(SyntheticMigration):
    def test_embedded_hash_binding_is_explicit_and_verified(self):
        raw=json.dumps({'slice_sha':digest(self.raw),'note':'synthetic'}).encode()
        (self.root/'old.json').write_bytes(raw)
        self.plan['sources']['meta']={'path':'old.json','sha256':digest(raw)}
        self.target['files']['meta']={'path':'meta.json','kind':'json','sha256':digest(raw)}
        self.plan['metadata_sha_rewrites']=[{'file':'meta','path':['slice_sha'],'source_sha':'table'}]
        self.target['metadata_checks']=[{'file':'meta','path':['slice_sha'],'equals_source_sha':'table'}]
        self.run_migration();obj=json.loads((self.root/'output/meta.json').read_text());manifest=json.loads((self.root/'output/manifest.json').read_text())
        self.assertEqual(obj['slice_sha'],manifest['files']['table']['sha256']);self.assertEqual(obj['note'],'synthetic')
class V2Guards(SyntheticMigration):
    def test_raw_tsv_bytes_quotes_bom_crlf_empty_fields(self):
        self.raw=b'\xef\xbb\xbffamily\tstyle\tengine\tcp\tiou\r\n"Synthetic"\t\tengine_a\t0041\t0.5000\r\n'
        (self.root/'old.tsv').write_bytes(self.raw);self.plan['sources']['table']['sha256']=digest(self.raw);self.target['files']['table']['sha256']=digest(self.raw)
        self.run_migration();self.assertEqual((self.root/'output/table.tsv').read_bytes(),b'\xef\xbb\xbfschema_version\tfamily\tstyle\tengine\tcp\tiou\r\n'+SCHEMA_VERSION.encode()+b'\t"Synthetic"\t\tengine_a\t0041\t0.5000\r\n')
    def test_blank_and_row_count_rejected(self):
        self.plan['sources']['table']['rows']=2
        with self.assertRaises(BuildError):self.run_migration()
        self.raw+=b'\n';(self.root/'old.tsv').write_bytes(self.raw);self.plan['sources']['table'].update(sha256=digest(self.raw),rows=2);self.target['files']['table']['sha256']=digest(self.raw)
        with self.assertRaises(BuildError):self.run_migration()
    def test_current_target_hash_rejected(self):
        self.target['files']['table']['sha256']='0'*64
        with self.assertRaises(BuildError):self.run_migration()
    def json_input(self,raw):
        (self.root/'old.json').write_bytes(raw);self.plan['sources']={'meta':{'path':'old.json','sha256':digest(raw)}};self.target['files']={'meta':{'path':'meta.json','kind':'json','sha256':digest(raw)}}
    def test_numeric_tokens_preserved(self):
        self.json_input(b'{"a":1.7000,"b":1e+09,"c":-0,"d":12345678901234567890}')
        self.run_migration();raw=(self.root/'output/meta.json').read_bytes()
        for token in [b'1.7000',b'1e+09',b'-0',b'12345678901234567890']:self.assertIn(token,raw)
    def test_nonfinite_and_duplicate_rejected(self):
        for raw in [b'{"a":NaN}',b'{"a":Infinity}',b'{"a":-Infinity}',b'{"a":1,"a":2}']:
            self.json_input(raw)
            with self.assertRaises(BuildError):self.run_migration()
    def test_unlisted_stale_nested_hash_rejected(self):
        raw=json.dumps({'nested':[{'sha':digest(self.raw)}]}).encode();(self.root/'old.json').write_bytes(raw);self.plan['sources']['meta']={'path':'old.json','sha256':digest(raw)};self.target['files']['meta']={'path':'meta.json','kind':'json','sha256':digest(raw)}
        with self.assertRaises(BuildError):self.run_migration()
