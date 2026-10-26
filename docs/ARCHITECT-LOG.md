# Architect log


## 2026-10-26 block 91 (owner 10:51 europe/istanbul, message received 10:54): labs keep writing code

owner: "köprüden ürün kodlarını sildirdik filan ama lab instinct'leri kod işleri yapmaya devam etmeliler. bu güvenlik adımı kod işlerini yapmayacakları anlamına gelmesin." ("we had the product code removed from the bridge, but the lab instincts must keep doing code work. this security step must not mean they stop coding.")

- 91a: block 89 changed what goes on the bridge, not how much the labs work. labs stay writers at full capacity under ohal.
- 91b: packet count: at least one open packet per lab worker, at least 40 open in total; each claimed packet is replaced the same pulse. receipt: open / claimed / returned / ported, per line.
- 91c: the line's integrator cuts each product item into a self-contained module (function, small library, solver step, parser, test harness): plain interface (inputs, outputs, types), synthetic fixtures + expected outputs, a test command, the product's language and style rules. the lab writes the module + tests; the integrator ports and merges it like any writer's work.
- 91d: starting categories per line - kni: kerning pair extraction from outlines, kern table builder, sidebearing and class metrics, spacing before/after measurement, readback scoring. ca: overlap and constraint solver steps, boundary motion integrator, organic-motion metrics (collective drift, stutter), deterministic replay harness. gorav: spsc ring and timing-ledger property tests, seek/discard contract test harness, frame pacing model, subtitle timing parser. middots: sync merge and conflict model, no-wipe session state machine with tests, preset serialization and versioning, local export tool for the recovery snippet (90a item 3). transcribe: streaming partial-text assembler, latency measurement harness, typewriter pacing model. gor/photon: lua filter unit harness, scene-cut feed parser, resource materializer race tests.
- 91e: bridge notice posted verbatim at the top of GROUP-INBOX.md.
- 91f: the private lab channel (89d) stays a research item; product-source packets go through it only after the owner says yes.
- handoff: no change.

## 2026-10-26 block 89 (owner 10:40 europe/istanbul): bridge exposure narrowing

the 2026-10-26 09:09 bridge grant is narrowed by the owner's 10:30 question ("neden font dokümanlarının tamamı açıkta olsun ki?"). product repos stay private. rrll is the owner's own public repo; leave it as is.

- 89a: no product source, fonts, captures, kits or project internals on the bridge; packets are generic drop-in pieces (interface + synthetic fixtures) with a test and a target; labs return code, integrators port it.
- 89b: product-source paths removed from the current tree in one commit (see the removal commit's path list); no history rewrite - the owner decides that separately.
- 89c: source-dependent open packets rewritten generic or withdrawn; both labs told on the bridge.
- 89d: private lab channel = research only until the owner says yes.
- 89e: guide v10 limits line replaces v9's.
