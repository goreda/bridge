import hashlib
import os
from pathlib import Path
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from clustering_evidence.input_attestation import (AttestationError, Contract, InputAttestation, SourceRecord, Status, verify)

class AttestationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/'input'
        self.source = SourceRecord('synthetic', 'fixture', 'a'*64)
        self.contract = Contract(('measurements',), ('synthetic',), 4096, 100, 64, 2, 0, 1)
    def expected(self, data, lines):
        self.path.write_bytes(data)
        return InputAttestation('measurements', hashlib.sha256(data).hexdigest(), lines, self.source)
    def run_verify(self, expected, sink=None, **kwargs):
        return verify(self.path, expected, role='measurements', source=self.source, contract=self.contract,
                      consume_chunk=sink or (lambda _:None), **kwargs)
    def test_physical_lines(self):
        for data, lines in [(b'',0),(b'\n',1),(b'a',1),(b'a\r\n\r\nb',3),(b'\xef\xbb\xbfhead\n\nx',3)]:
            with self.subTest(data=data):
                chunks=[]
                from unittest.mock import patch
                with patch('clustering_evidence.receipt_storage.filesystem',return_value='synthetic-test-only'):
                    result=self.run_verify(self.expected(data,lines),chunks.append,cooperative_lock=True)
                self.assertEqual(result.status,Status.VERIFIED)
                self.assertEqual(b''.join(chunks),data)
                self.assertEqual(result.logical_hash_status,Status.NOT_EVALUATED)
    def test_no_snapshot_protocol(self):
        result=self.run_verify(self.expected(b'x',1))
        self.assertEqual(result.status,Status.UNVERIFIABLE)
    def test_missing_attestation(self):
        self.assertEqual(self.run_verify(None).status,Status.NOT_EVALUATED)
    def test_missing_file(self):
        expected=self.expected(b'x',1);self.path.unlink()
        self.assertEqual(self.run_verify(expected).status,Status.NOT_EVALUATED)
    def test_hash_mismatch(self):
        expected=self.expected(b'x\n',1);self.path.write_bytes(b'y\n')
        with self.assertRaises(AttestationError) as caught:self.run_verify(expected)
        self.assertEqual(caught.exception.code,'sha_mismatch')
    def test_count_mismatch(self):
        expected=self.expected(b'x',2)
        with self.assertRaises(AttestationError) as caught:self.run_verify(expected)
        self.assertEqual(caught.exception.code,'line_count_mismatch')
    def test_source_mismatch(self):
        expected=self.expected(b'x',1)
        expected=InputAttestation(expected.role,expected.sha256,1,SourceRecord('synthetic','other','a'*64))
        with self.assertRaises(AttestationError) as caught:self.run_verify(expected)
        self.assertEqual(caught.exception.code,'source_mismatch')
    def test_role_mismatch(self):
        expected=self.expected(b'x',1)
        expected=InputAttestation('other',expected.sha256,1,self.source)
        with self.assertRaises(AttestationError) as caught:self.run_verify(expected)
        self.assertEqual(caught.exception.code,'role_mismatch')
    def test_bool_count_refused(self):
        expected=self.expected(b'x',True)
        with self.assertRaises(AttestationError):self.run_verify(expected)
    def test_symlink_refused(self):
        expected=self.expected(b'x',1); target=self.path.with_name('other');self.path.rename(target);self.path.symlink_to(target)
        with self.assertRaises(AttestationError) as caught:self.run_verify(expected)
        self.assertEqual(caught.exception.code,'input_open')
    def test_mutation_detected(self):
        expected=self.expected(b'abcdefgh',1)
        changed=[]
        def consume(_):
            if not changed:
                changed.append(True)
                with self.path.open('ab') as out:out.write(b'z')
        with self.assertRaises(AttestationError) as caught:self.run_verify(expected,consume)
        self.assertEqual(caught.exception.code,'input_mutated')
    def test_path_replacement_same_fd(self):
        data=b'abcdefgh';expected=self.expected(data,1);chunks=[]
        def consume(chunk):
            chunks.append(chunk)
            if len(chunks)==1:
                self.path.rename(self.path.with_name('old'))
                self.path.write_bytes(b'replaced')
        # Rename may alter ctime: either refuse mutation or verify original FD,
        # never hash replacement bytes or call them the attested input.
        try:
            result=self.run_verify(expected,consume)
            self.assertEqual(result.byte_sha256,expected.sha256)
        except AttestationError as error:self.assertEqual(error.code,'input_mutated')
        self.assertEqual(b''.join(chunks),data)

if __name__=='__main__':unittest.main()
