# W0224 stage1b overlay reproduction

This archive is an incremental overlay at the same w0224/ root as approved15 baseline archive ab43080c43e2efef88375384ce4e294893712ad0ecb0bbd849ce1046dfc736b4. Do not replace baseline files or refit baseline calibration.

All24 added PNG sets are already included. No font bytes included. To re-render, download own immutable URLs from extension-stage1b.json into extension-cache/<slug>/<file> and verify font/OFL hashes, then run frozen baseline harness:

```
python3 harness.py render --out added24-dataset --manifest extension-stage1b.json --cache extension-cache --gate extension-gate.json
python3 run_added24.py
python3 export_tables.py added24-fixture/results.json
python3 extension_cluster_intervals.py
```

run_added24.py calls the actual pinned data.py preprocess on every added tight crop and uses a declared metadata oracle, never a recognizer. It retains baseline prediction rows, fixes the original calibration map, asserts baseline validation/map equal, reports original5/added24/combined29 separately. Dropped Saira Extra Condensed has no images; original25 manifest bytes stay unchanged and separate drop receipt binds exact hash. Combined derived manifest is not a newly approved proposal: it only joins already approved baseline15 and proposal25 for provenance checks, with dropped family explicitly missing.

The included combined-dataset.json references both baseline and added frame roots. With both archives extracted, the requester can run:

```
python3 harness.py score --dataset added24-fixture/combined-dataset.json --manifest added24-fixture/combined-manifest-derived.json --plugin my_plugin.py --out requester-production-run
```

This is a new requester production run, clearly separate from both oracle outputs. No real scorer runs are included here, and no production quality claims may be drawn from the metadata oracle. For a standalone extension-only scorer, use the combined baseline calibration inputs and the additional frames, then preserve original heldout rows and explicit missing-family declaration.

Visual evidence: contact sheet samples A/g/0 for every added family, top full frame and bottom aspect-preserved tight glyph view. Source PNGs are384x384 with fixed em256; thumbnails do not substitute for those sources. All frame geometry/margins passed automatic checks. 72 full frames and tight shapes visually inspected, no cropping or glyph loss found. This is sampled visual checking, not a claim to visually inspect all4968 frames.
