"""Every derived node carries a geometric class plus status and source; no semantic role field exists."""
import unittest, gen, ref_roles

class DeriveFields(unittest.TestCase):
    def test_node_fields(self):
        F = gen.fixtures()
        for name, fx in F.items():
            d = ref_roles.derive(fx, {"sigma": 0.0, "origin": "declared", "derivation": "test"})
            for c in d["contours"]:
                for n in c["nodes"]:
                    self.assertNotIn("role", n, name)
                    self.assertIn(n["geometric_class"], ("corner", "extremum", "seam"), name)
                    self.assertEqual(n["status"], "proposed", name)
                    self.assertEqual(n["source"], "measured", name)

    def test_no_angle_cap(self):
        # a very large declared noise must not be silently capped at a fixed angle
        fx = gen.fixtures()["rect"]
        d = ref_roles.derive(fx, {"sigma": 1e6, "origin": "declared", "derivation": "test"})
        for n in d["contours"][0]["nodes"]:
            self.assertGreater(n["tau_deg"], 60.0)

if __name__ == "__main__":
    unittest.main()
