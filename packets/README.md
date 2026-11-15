# Direct bridge writes and packet index - 2026-11-15, arch-196o r2

Owner10:51: "lab'lerin boşta kalması durumu da asla kabul edilemez ... buna dair bir investigation başlat. ve bu açığı da kapat."
Owner10:54: "ben böyle bir kural koymadım. köprüye kimin yazması gerekiyorsa onun yazmasının gerekliliği yönünde bir kısıt kaldırımı gerekli. köprü aktif bir şekilde tüm ajanlar tarafından kullanılmalı ki lablerden maksimum verim alınsın."

Every contributor from gdb/zuellue, goreda, their integrators and the labs may write packets, replies, rulings and ingest results directly. No mandatory publisher, relay or review-before-publish. The five gates are unchanged. Never post credentials, keys, user data, licensed bytes or private endpoints. Scan every new packet before publication.

New packets: packets/W-<writer>-<seq>.md, writer=gdb,goreda or a stable integrator short id. One writer owns each packet file. Rebase and retry push conflicts; never overwrite another contributor's file. GROUP-INBOX.md is now an append-only index, one line per packet: id | line | target branch | status. Existing claim priority remains; the lab writes its claim in the packet.

Mandatory startable form: actual source/excerpts at a pinned SHA, exact interface, test that must pass, target branch, return as patch or full files. Label failed/not-run separately. Proposed/interface-less stock is retired. Open startable packets must cover all running workers and at least20 per lab while product lines are open. Any contributor consumes a return by applying/testing/merging or answering with the exact failure within2h; overdue returns are blockers.

The legacy W-0288..W-0327 batch is NOT STARTABLE, withdrawn from the runnable queue pending a rewrite in the pinned-source form. Its text remains below unchanged for history. This notice does not claim the older W-0276..W-0287 stock is startable; row owners must rewrite or withdraw it. Do not start from a legacy proposed/interface-less entry.

secret scan: clean

## Required fields

- Packet ID and writer
- Product problem and behavior that must not change
- Target branch and source SHA
- Actual source files or excerpts, hashes and necessary dependency context
- Exact input/output interface
- Reproducer and mandatory acceptance test command
- Return as patch or full files; measured, assumed, failed and not-run separated
- Lab claim, result, ingest status and exact failure or merged SHA
- secret scan: clean
