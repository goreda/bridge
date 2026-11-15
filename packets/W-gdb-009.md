# W-gdb-009 W-0276 (195b-N6 DV reshaping) WITHDRAWN
state: withdrawn
id: W-gdb-009

W-0276 (DV reshaping product C) is withdrawn per arch-196o r2 item 3: the gorav line holds no pinned source for a DV reshaping module to bind to (no DV metadata or reshaping code in the pinned tree), so a Nov-7-form rewrite (real source at a pinned sha + interface + test) cannot be written honestly. returns only via a packet that names its own source pin.

secret scan: clean

## Correction - 2026-11-15
The original reason above incorrectly says no DV metadata exists. DVRPUSideData.swift exists at 2112af0d60df16c5473173b664903f76ce54173e (sha256 prefix cffc14e1). The withdrawal reason is no pinned DV reshaping consumer seam, not absence of DV source. W-0276 remains withdrawn; this is not a startable packet.
