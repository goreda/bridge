# W-0232 - source/frame-bound integer bearing offsets (ADD not SET, i16) (generic production-code unit 5)

Solver: 1nstinct. in2tinct writes adversarial failure cases BEFORE reading the implementation, then reviews. One id (W-0232) through every fix/review round.

## 5. Source/frame-bound integer bearing offsets

Module bearing_offsets.py, build(source_sha256,frame,lsb_add,rsb_add,declaration_pin)->receipt; bind_manifest(text,receipt,expected_source,expected_frame)->text. Both offsets required finite strict integers in[-32768,32767], bool refused; ADD not SET. Four keys exactly lsb_add,rsb_add,post_scope='base',post_scope_label='explicit_add'. Source/frame/evidence pins verified; caller must supply expected source/frame independently. Existing identical four manifest lines idempotent; duplicate/conflicting/partial prior keys refuse, preserve unrelated lines/order. No omitted-to-zero, no hidden CLI flags. verify_geometry(before,after,receipt) checks before xmin/xmax shifted by lsb_add and advance by lsb_add+rsb_add; each glyph retains geometry width. Exact supplied numeric output units only, no typography inference. Tests: negative offsets, i16 limits, fractional refusal, stale source/frame, double-application guard and unchanged unrelated manifest. No filesystem/device effects.

## Delivery and review for every unit
Return real implementation plus tests (not report-only), module schema/API.md, version/start commit, patch against supplied contract stub, exact run command/output, archive byte count/SHA256/per-file pins. Reviewer writes failure cases before seeing solver code then independently executes it. Requirements versus diagnostic probes distinguished. No training/font/render assets needed. A code change invalidates earlier run receipts. Requester integrates/tests on real engine; lab tests/review/branch landing are NOT product acceptance. No new message/user permission or production deployment grant is encoded here. One ID per unit for all fixes. Existing queue >2h unconsumed-return rule checked by writer.

secret scan: clean

secret scan: clean
