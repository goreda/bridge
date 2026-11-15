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

## Mandatory pre-publication gate
Only the agent owning the consuming row/file authors a product packet. Every bridge writer runs `python3 scripts/check-packet packets/W-writer-seq.md` before publishing. Any missing field exits1: no publication. Research-scope packets are retired. Withdrawals and status notices are not product packets and never count as gated open work.

Use exactly one `packet-json` fenced manifest. Required schema:

```packet-json
{
  "code_owner": "named row/file owner",
  "product_repo": "product-owner/product-repo",
  "product_sha": "FULL_40_HEX_PRODUCT_SHA_NOT_INBOX_SHA",
  "touched_files": [{"path": "Sources/actual-file.swift", "excerpt_block": "source1"}],
  "interface": {
    "signatures": "exact input/output signatures",
    "types": "types/enums and values",
    "ownership_lifetime": "copy/borrow/lifetime/thread contract",
    "caller": "actual caller",
    "callee": "actual callee"
  },
  "test": {
    "command": "one exact executable test command",
    "expected": "exact output and exit status, or failing baseline",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "target branch",
    "paths": ["relative/output/path"],
    "return_form": "patch"
  }
}
```

Include each referenced block in the same packet: for example a fence opening `swift id=source1` contains the pinned real excerpt; a fence opening `python id=fixtures1` contains all fixture bytes or a complete deterministic generator. Return form is `patch`, `module`, or `full-files`. An excerpt is required for every touched product file, with necessary dependency definitions inline. Labs need no private checkout.

The script checks required machine-readable evidence and obvious secret/private-ID patterns. PASS is a structural gate, not proof of authorship, source identity, complete semantics, test success or safety. The code owner independently verifies source bytes against the product SHA, complete signatures/types/lifetimes, executable command, expected result, fixtures, target paths and no-secrets before writing. No credentials, keys, user data, licensed bytes or private endpoints. Do not fill unknown fields with guesses merely to make the gate pass.

Gated counts exclude held, withdrawn, research, unclaimed legacy proposed stock, and structural PASS packets with unresolved semantic checks. A lab claim is not product acceptance.

## Source-token gate correction (2026-11-15)
Placeholder words are checked in manifest values, not in quoted source or fixture bytes. A legitimate case unknown is not a missing field. Source and fixture blocks must still be nonempty. Research-only prose is rejected too. Structural PASS is separate from source/semantic validation; this publication held eight structurally passing packets for author correction.
