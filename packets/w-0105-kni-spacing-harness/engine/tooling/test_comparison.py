"""Authored NOT_RUN. No engine execution or parser dependency used by fixture."""
import copy
import unittest
from compare_decoded_outline import compare

class ComparisonFixtures(unittest.TestCase):
    def source(self):
        return {"glyph_order": [".notdef", "A"], "cmap": {"65": "A"}, "glyphs": {".notdef": {"outline": [], "metrics": [500, 0]}, "A": {"outline": [["moveTo", [[0, 0]]], ["lineTo", [[100, 0]]], ["curveTo", [[100, 100], [0, 100], [0, 0]]], ["closePath", []]], "metrics": [500, 0]}}}
    def test_identity(self):
        source = self.source()
        self.assertEqual(compare(source, copy.deepcopy(source))["glyph_count"], 2)
    def test_lost_sibling(self):
        source = self.source()
        decoded = copy.deepcopy(source)
        del decoded["glyphs"]["A"]
        with self.assertRaises(ValueError): compare(source, decoded)
    def test_changed_control(self):
        source = self.source()
        decoded = copy.deepcopy(source)
        decoded["glyphs"]["A"]["outline"][2][1][0][0] = 99
        with self.assertRaises(ValueError): compare(source, decoded)
    def test_changed_order(self):
        source = self.source()
        decoded = copy.deepcopy(source)
        decoded["glyph_order"].reverse()
        with self.assertRaises(ValueError): compare(source, decoded)
    def test_missing_closure(self):
        source = self.source()
        decoded = copy.deepcopy(source)
        decoded["glyphs"]["A"]["outline"].pop()
        with self.assertRaises(ValueError): compare(source, decoded)
    def test_bad_metric_or_cmap(self):
        for key in ["metric", "cmap"]:
            source = self.source()
            decoded = copy.deepcopy(source)
            if key == "metric": decoded["glyphs"]["A"]["metrics"][0] = 499
            else: decoded["cmap"]["65"] = ".notdef"
            with self.assertRaises(ValueError): compare(source, decoded)

if __name__ == "__main__": unittest.main()
