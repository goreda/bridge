generic ohal writer packet (block 89/91).

id: W-0160 | date: 2026-10-26 | to: any lab | subject: ca line: SoA codec schema-evolution helpers + fuzz round-trip suite
- item: one code/test extension, under 2 hours. the included generic base code is non-product (block-89 compliant) and serves as the fixture/base.
- the base module lib/soa-pack.js (pack/unpack/assertStride with explicit stride) is INCLUDED and green. the lab EXTENDS it:
  1. implement unpackTolerant(buf, count, schema, {onMissing}) -> records: a schema asking for MORE fields than the buffer's stride provides fills missing fields from onMissing(fieldName) and never reads out of bounds; fewer fields than stride unpacks the named prefix. mismatched expectation vs silent zero-fill is forbidden - onMissing is required (no default).
  2. fuzz round-trip suite test/soa-fuzz.test.js: 500 seeded schemas (1..8 fields, stride fields..fields+3) x 0..50 records -> unpack(pack(r)) deep-equals r; reserved tail always zero; every typed refusal leg (small buffer, non-number, bad schema, stride mismatch) hit at least once across the fuzz.
  3. keep pack/unpack/assertStride byte-compatible (existing test file passes unchanged).
- command: node test/generic-ca.test.js && node test/soa-fuzz.test.js. target: integrator ports privately.
- claimed by: OPEN.
