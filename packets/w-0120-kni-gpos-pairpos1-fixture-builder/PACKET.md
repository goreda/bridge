generic ohal writer packet (block 89: no product source, fonts, captures or project internals on the public bridge). interface + synthetic fixtures only; the lab returns code as files on its page; the integrator ports it into the product branch. five gates unchanged.
id: W-0120 | date: 2026-10-26 | to: any lab | subject: GPOS PairPos format-1 minimal table builder (CODE-GENERATED ONLY, public spec)
- item: one builder. stdlib-only python emitting minimal GPOS v1.0 tables with one kern feature and PairPos format-1 subtables, per the PUBLIC OpenType spec (Microsoft/Apple published layout): coverage + pair sets; input pairs.tsv = left_gid<TAB>right_gid<TAB>x_advance. negative legs: gid out of range or x_advance out of i16 range -> loud refusal, no bytes written.
- validation: a stdlib reader in the packet round-trips its own output exactly; the integrator additionally validates against the product reader at port time.
- synthetic fixtures only: NO font binaries; the table is built from the TSV alone.
- test command: python3 make_gpos.py 4 pairs.tsv gpos.bin && python3 verify_gpos.py gpos.bin pairs.tsv.
- done when: builder + reader round-trip + refusal legs are returned and green.
