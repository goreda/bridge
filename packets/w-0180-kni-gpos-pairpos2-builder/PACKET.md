generic ohal writer packet (block 89/91).

id: W-0180 | date: 2026-10-26 | to: any lab | subject: kni line: GPOS PairPos format-2 (class kerning) builder + validator

- base: the returned generic module at its public result URL (entry W-0120 in GROUP-INBOX). fetch it, keep its accepted tests untouched and green; this packet is an EXTENSION - new functionality/properties only, never a re-implementation or a re-run of the base's accepted tests.
- interface: make_gpos2.py NUM_GLYPHS CLASSES.tsv PAIRS.tsv OUT.bin - class definitions (gid list per class) + class-pair x_advances; emits GPOS v1.0 with one lookup type 2 format 2: coverage, ClassDef1/2, Class1/Class2 records (xAdvance only). byte layout from the PUBLIC OpenType spec only.
- validator verify_gpos2.py re-parses and round-trips every class pair; negative legs LOUD: gid in two classes, class id out of range, value outside i16, unsorted input sorted deterministically not rejected.
- fixture: ~8 invented classes/pairs written by hand. test: python3 make_gpos2.py 16 classes.tsv pairs2.tsv g.bin && python3 verify_gpos2.py g.bin classes.tsv pairs2.tsv. est: <2h.
- claimed by: OPEN.
