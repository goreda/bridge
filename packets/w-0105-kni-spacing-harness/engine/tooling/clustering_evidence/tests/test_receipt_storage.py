import copy
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from clustering_evidence.receipt_storage import StorageError,canonical,parse,schema_bound,decode,frame,append,Anchor,ZERO_HASH

def string(n):return {'type':'string','minLength':0,'maxLength':n}
def integer(a,b):return {'type':'integer','minimum':a,'maximum':b}
def obj(props):return {'type':'object','additionalProperties':False,'required':list(props),'properties':props}
def schema():
    # All counts/bounds here are SYNTHETIC fixture conventions, not production policy.
    receipt=obj({'schema_version':integer(1,1),'tree_sha256':string(64),'gate_id':string(20),
        'gate_config_sha256':string(64),'input_sha256s':{'type':'array','minItems':0,'maxItems':4,'items':string(64)},
        'c2_source':string(40),'res_c2_col':obj({'tag':string(7),'value':string(16)}),
        'status':string(20),'co_gate_status':string(20),'logical_hash_status':string(20)})
    return obj({'previous_frame_sha256':string(64),'receipt':receipt})
def receipt():
    return {'schema_version':1,'tree_sha256':'a'*64,'gate_id':'fixture','gate_config_sha256':'b'*64,
        'input_sha256s':['c'*64],'c2_source':'synthetic','res_c2_col':{'tag':'present','value':'c2'},
        'status':'NOT_EVALUATED','co_gate_status':'NOT_EVALUATED','logical_hash_status':'NOT_EVALUATED'}
def encoded(r=None,seq=1,previous=ZERO_HASH):return frame(seq,canonical({'previous_frame_sha256':previous,'receipt':r or receipt()}))

class StorageTests(unittest.TestCase):
    def test_canonical(self):self.assertEqual(canonical({'z':1,'a':'ü'}),b'{"a":"\xc3\xbc","z":1}')
    def test_forbidden_types(self):
        for v in (True,None,1.0,2**63,{'ü':1},'\ud800'):
            with self.subTest(v=repr(v)),self.assertRaises(StorageError):canonical(v)
    def test_duplicate_keys(self):
        with self.assertRaises(StorageError):parse(b'{"a":1,"a":1}')
    def test_noncanonical(self):
        with self.assertRaises(StorageError):parse(b'{ "a":1}')
    def test_schema_bound(self):self.assertGreaterEqual(schema_bound(schema()),len(canonical({'previous_frame_sha256':ZERO_HASH,'receipt':receipt()})))
    def test_unbounded_schema(self):
        with self.assertRaises(StorageError):schema_bound({'type':'string'})
    def test_chain_anchor(self):
        first=encoded();r=receipt();r['gate_id']='second';second=encoded(r,2,hashlib.sha256(first).hexdigest())
        log=decode(first+second,schema());self.assertEqual(log.tail_completeness,'UNVERIFIED')
        self.assertEqual(decode(first+second,schema(),log.anchor).tail_completeness,'VERIFIED')
    def test_tail_loss_anchor(self):
        first=encoded();r=receipt();r['gate_id']='second';whole=first+encoded(r,2,hashlib.sha256(first).hexdigest())
        with self.assertRaises(StorageError):decode(first,schema(),decode(whole,schema()).anchor)
    def test_corruption_and_torn_tail(self):
        original=encoded()
        for raw in (original[:-1],original[:3],original[:-1]+bytes([original[-1]^1])):
            with self.subTest(size=len(raw)),self.assertRaises(StorageError):decode(raw,schema())
    def test_previous_hash_authenticated(self):
        with self.assertRaises(StorageError):decode(encoded(previous='d'*64),schema())
    def test_unverifiable_never_pass(self):
        r=receipt();r['status']='PASS'
        with self.assertRaises(StorageError):decode(encoded(r),schema())
    def test_append_idempotence_conflict(self):
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as directory, patch('clustering_evidence.receipt_storage.filesystem',return_value='synthetic-test-only'):
            path=Path(directory)/'receipts';r=receipt()
            first=append(path,r,schema(),timeout_ms=0,poll_ms=1)
            raw=path.read_bytes();second=append(path,r,schema(),timeout_ms=0,poll_ms=1,anchor=first.anchor)
            self.assertEqual(raw,path.read_bytes());self.assertEqual(first.anchor,second.anchor)
            r['status']='FAIL'
            with self.assertRaises(StorageError) as caught:append(path,r,schema(),timeout_ms=0,poll_ms=1)
            self.assertEqual(caught.exception.code,'idempotency_conflict')
    def test_schema_overflow(self):
        with self.assertRaises(StorageError):decode(b'',{'type':'string','minLength':0,'maxLength':2**32})

class FaultTests(unittest.TestCase):
    def test_partial_write_requires_manual_recovery(self):
        from unittest.mock import patch
        import os
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'receipts';real_write=os.write;calls=[]
            def broken(fd,data):
                if not calls:
                    calls.append(1);return real_write(fd,data[:7])
                raise OSError('injected write failure')
            with patch('clustering_evidence.receipt_storage.filesystem',return_value='synthetic-test-only'),patch('clustering_evidence.receipt_storage.os.write',side_effect=broken):
                with self.assertRaises(StorageError):append(path,receipt(),schema(),timeout_ms=0,poll_ms=1)
            self.assertEqual(path.stat().st_size,7)
            with patch('clustering_evidence.receipt_storage.filesystem',return_value='synthetic-test-only'):
                with self.assertRaises(StorageError) as caught:append(path,receipt(),schema(),timeout_ms=0,poll_ms=1)
            self.assertEqual(caught.exception.code,'incomplete_or_corrupt_tail')
            self.assertEqual(path.stat().st_size,7)
    def test_package_import(self):
        import clustering_evidence.input_attestation
        import clustering_evidence.receipt_storage
        self.assertTrue(callable(clustering_evidence.input_attestation.verify))

class SyncFaultTests(unittest.TestCase):
    def test_fsync_failure_closes_and_reconciles(self):
        from unittest.mock import patch
        import os
        closed=[];real_close=os.close
        def close(fd):closed.append(fd);return real_close(fd)
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'receipts'
            with patch('clustering_evidence.receipt_storage.filesystem',return_value='synthetic-test-only'),patch('clustering_evidence.receipt_storage.os.fsync',side_effect=OSError('injected sync failure')),patch('clustering_evidence.receipt_storage.os.close',side_effect=close):
                with self.assertRaises(StorageError) as caught:append(path,receipt(),schema(),timeout_ms=0,poll_ms=1)
            self.assertEqual(caught.exception.code,'storage_io');self.assertTrue(closed)
            # Bytes may be present despite sync failure: no success or rollback claim.
            self.assertEqual(len(decode(path.read_bytes(),schema()).records),1)
            with patch('clustering_evidence.receipt_storage.filesystem',return_value='synthetic-test-only'):
                self.assertEqual(len(append(path,receipt(),schema(),timeout_ms=0,poll_ms=1).records),1)
