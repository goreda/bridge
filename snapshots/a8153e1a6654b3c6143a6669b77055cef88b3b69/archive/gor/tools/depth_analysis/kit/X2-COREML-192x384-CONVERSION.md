# X2 goreda lane: ToS-parity-shape (192x384) CoreML conversion record (2026-11-09 ~21:26 +03)

What: re-converted all four nunif iw3 synthesis models to CoreML fp16 .mlpackage at the ToS-parity
shape 192x384 (320x180 replication-padded to multiples of 96) plus seeded torch-fp32 fixtures, using
the in-repo converter tools/depth_analysis/nunif_convert.py unchanged (--shape 192x384, one tag per
process). Box: Linux 2 cores 1 GB RAM, torch 2.14.1+cpu, coremltools 9.0. All four traces fit memory
at this shape (row_flow, mlbw, inpaint, video incl. the 12-frame video model).

Why: the handoff's Mac parity run needs packages at the ToS shape; the 768x1344 kit and the 288x480
bring-up video package do not match the committed 320x180 reference renders. This retires open item
2 ("light_video re-convert needed on Mac, Linux OOM") for the parity shape: at 192x384 the video
model converts on Linux without OOM. Production-shape (768x1344) video conversion still needs the
bigger box/Mac per the original note.

Artifacts (local, NOT committed - converted weights, owner-private Mac scope):
/tmp/x2-verify/gor-kit-nunif-coreml-192x384.tar = 4 packages + 4 fixtures,
sha256 10a40c8a217075163c6dd3544d4f6911f1619586072fed3b292b0f1dff3a88da, 51,957,760 B.
Per-package hashes + fixture shas: nunif-coreml-192x384-manifest.json (committed next to this file).
Reproduce: NUNIF_SRC=<nunif b1548e8> GOR_NUNIF_WEIGHTS=<dir with the 7 verified .pth> \
  python3 nunif_convert.py --only row_flow|mlbw|inpaint|video --shape 192x384 --out <dir>

Distribution blocker: the tar needs the gorav gor-kit-2026-11-09 release route (owner gh login);
this lane has no gorav write access. After upload, add the models.lock row (same shape as
iw3-nunif-coreml, revision gor-kit-2026-11-09, file/sha/bytes above).

CoreML-vs-PyTorch diff remains Mac-side execution (no CoreML runtime on Linux); the committed
fixtures are the torch-fp32 reference outputs for exactly that diff, and the parity-shape packages
let it run against the committed ToS renders directly.

## Update 21:28: converter boundary finding + fix (this lane)

Inspection of my converted specs found the image-inpaint package outputting [1,3,160,352], 32 px
smaller per dim. Cause: nunif_convert.py wrapped ONLY the video model with skip_i2i_offset=True;
the image model traced with the default skip_i2i_offset=False, baking the 16 px/side i2i-offset
crop + composite into the graph. nunif_convert.py has exactly one commit (f4833cd84, 14:18), so
the SHIPPED 768x1344 kit image-inpaint package has the same baked-in crop: its real out is
[1,3,736,1312], and both nunif-coreml-kit-manifest.json and NUNIF-COREML-RUNNER-CONTRACT.md
misdocument it as [1,3,768,1344]. Fix landed here: image inpaint now uses the same
skip_i2i_offset=True wrapper as video; re-converted at 192x384, spec + fixture out now
[1,3,192,384] full-size (hashes updated in the manifest; tar re-built, new sha above).
The 768x1344 production package must be re-converted from the fixed script on the Mac.
Verified by reading the compiled spec protobufs (coremltools.proto.Model_pb2, Linux) + fixture
npz shapes: row_flow delta [1,2,192,384]; mlbw delta/layer_weight/hole_mask_logits
[1,2/-]/[1,2/-]/[1,1,192,384]; video out [12,3,192,384]; all FLOAT16 mlProgram, op mixes sane.
