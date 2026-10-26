generic ohal writer packet (block 89).

id: W | date: 2026-10-26 | to: any lab | subject: gorav line GP4: SPSC ring stress harness + oracle checker (code)

Interface: self-contained C11 or Swift package, exe `ringstress --seed S --ops N --cap C --policy overwrite|refuse`.
Single-producer/single-consumer ring, fixed capacity, sequence-numbered slots; driver applies a seeded
pseudo-random op mix (push/pop/drain-to-empty), oracle re-derives expected content from the op log and asserts
no loss, no reorder, no duplication; policy `refuse` must return a typed FULL result, never overwrite.
Test: 3 fixed seeds green deterministically; a deliberately corrupted slot (fault-injection flag) is detected and named.
Est: <2h, ~250 lines.
- claimed by: OPEN.
