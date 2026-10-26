import sys, unittest
from pathlib import Path
from fontTools.misc.psCharStrings import T2CharString
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from charstring_equiv import same_program


def wide(v):
    return bytes([28, (v >> 8) & 255, v & 255])


class CharstringEquivTest(unittest.TestCase):
    def setUp(self):
        prog = [10, 0, 'rmoveto', 290, 0, 'rlineto', -290, 'hlineto', 'endchar']
        self.compact = T2CharString(program=prog)
        self.compact.compile()
        self.compact_bytes = self.compact.bytecode
        # same program, every operand written as a 16-bit integer
        body = b''
        ops = {'rmoveto': 21, 'rlineto': 5, 'hlineto': 6, 'endchar': 14}
        for t in prog:
            body += bytes([ops[t]]) if isinstance(t, str) else wide(t & 0xFFFF if t < 0 else t)
        self.wide_bytes = body

    def test_bytes_differ_programs_equal(self):
        self.assertNotEqual(self.compact_bytes, self.wide_bytes)
        self.assertTrue(same_program(self.wide_bytes.hex(), self.compact_bytes))

    def test_changed_operand_fails(self):
        other = T2CharString(program=[10, 0, 'rmoveto', 291, 0, 'rlineto', -290, 'hlineto', 'endchar'])
        other.compile()
        self.assertFalse(same_program(self.wide_bytes.hex(), other.bytecode))

    def test_garbage_fails(self):
        self.assertFalse(same_program('zz', self.compact_bytes))
        self.assertFalse(same_program('', self.compact_bytes))


if __name__ == '__main__':
    unittest.main()
