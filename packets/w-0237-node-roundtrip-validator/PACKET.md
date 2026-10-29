# W-0237 - master/outline typed node roundtrip validator (cyclic rotation only) (generic production-code unit)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0237) through every fix/review round.

##12 / lab1: master/outline typed node roundtrip validator

node_roundtrip.py: compare(expected,readback,rotation_allowed=True)->{ok,violations}. expected/readback list of closed contours with stable contour_id and typed nodes {x,y,type,smooth}. Allow cyclic rotation only, never reversal, control reassociation or contour-population loss. Exact coordinates default; optional explicit quantization contract via keyword quantum, documented round mode (no tolerance-by-proximity). Detect duplicate zero-length closing edge introduced, node-kind change, smooth loss and missing controls. Repeated coincident nodes remain distinct, match full cyclic tuple not greedy nearest coordinate. Tests real invented curved seam, coincident controls, altered winding, normalized rotation, legitimate repeated endpoints not silently removed.


##  All units delivery
Version/start commit, real implementation+tests+API, exact run command/raw output, archive byte count/SHA256/per-file pins; immutable source changes invalidate output receipts. Reviewer blind cases first then actual execution; exploratory diagnostics not invented acceptance. Return no font/model/private data. Requester-only writer after exact-byte/path/public-safe review; branch transport and lab review not production acceptance. Keep unconsumed-return queue rule checked by writer; no duplicate existing two or five units.
secret scan: clean


secret scan: clean
