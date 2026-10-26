# GlyphData provenance

- Source: schriftgestalt/GlyphsInfo, GlyphData.xml, repository blob sha
  980bbc2d6b2631a1c833b1b51b7daafb04d5d7f7 (GitHub contents API, 2026-10-18).
- License: MIT (GLYPHDATA-LICENSE.txt, vendored from the same repository).
- XML source URL: https://raw.githubusercontent.com/schriftgestalt/GlyphsInfo/master/GlyphData.xml
- License URL: https://raw.githubusercontent.com/schriftgestalt/GlyphsInfo/master/LICENSE
- XML SHA256: cf14510f8f7f7da3b8259831cbe22524c0e6d2c6d5cdb5ba98a549c0d29e032c
- Compaction: name/category/subCategory/script/rowIndex only. 30,377 rows.
- Ordering policy: `.notdef` first; known category rank then literal category
  name, script, literal subcategory, upstream row index. Lexical script and
  subcategory order is a generator policy, not a canonical Glyphs order claim.
  Unknown names have no classification inferred and sort last by byte name.
  No classification override support is claimed. Upstream name coverage does
  not prove a given installed Glyphs version uses identical classifications.
