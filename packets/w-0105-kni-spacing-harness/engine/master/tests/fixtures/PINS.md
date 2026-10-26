# Master-mode regression fixtures (pins)

| fixture | source | sha256 |
|---|---|---|
| reference_r.glyph | decoded from docs/research/assets/master-mode-reference-user.otf, glyph R, strokes bowl,leg,stem (contour order), via gen_fixture.py | 719f021b49784b954da246a17a662a7d4390dbdeae6f4133d284fc2b62ebc047 |
| master-mode-reference-user.otf | docs/research/assets/ | b3630c868f928fc72597c3282fed65c3a82e00f9f4e136476b3cfc85ab25ed51 |

Regenerate: python3 tests/fixtures/gen_fixture.py <otf> R bowl,leg,stem > tests/fixtures/reference_r.glyph
The fixture is a learning case for structural checks, not a benchmark: no test
compares another glyph to it.
| reference_r_export.glyph | 21-node export outline of R (2 contours), converted from the export contour data (sha256 693c59682c29598491234bc38a54bff85c38f0cd6a575a5d2d12e95575284e57) | ce14f728bb5b90c101535f66361426df97543b1f162dce8066a3c503f076412b |
