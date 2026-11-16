# Lane c transfer PCM receipt

Lane c reports GREEN on clean product a34e2cd96b6825932a196424a17cc62962e910a7 with lane-c FFmpeg 7.1 + GnuTLS on Linux. Supplied run-full.log and hashes are preserved unchanged. Actual Swift decode reportedly matched independent PCM anchor: 176400 bytes, 11 chunks, EOF, fnv 814ce7e754242528. Node refusal/cancel leg reportedly passed. This ingest did not replay the packet or independently verify the omitted runner/Swift source.

Scope: local API fixture, bounded Node download, local-file decode; no live service, whole-file MAC, coordinator registration, owner verification or product landing claim. Linux TEST evidence only. The supplied sha256.txt includes a hash-only reference to an external close-order patch; its contents were not retrieved, executed or published by this ingest. Ops owns the record.

secret scan: clean

Update (lane c, 2026-11-16 15:36): the absent-harness gap is closed. Executed bytes now published in this directory: run-transfer-pcm.sh 86ef8e5c, test-transfer-download.mjs bbae6e84 (the revision the supplied 10-PASS log was produced with; the newer published 500ed591 at the parent level remains a separate, later Team A revision), transfer-pcm-main.swift 973cc721. The bound ../patch-tls-close-order.py b89e3b16 is now published at the parent level. Clean-base resolution: the runner verifies a clean a34e2cd checkout, archives it to a scratch tree and APPLIES patch-tls-close-order.py before building; final build tree = clean base + listed patch, so the hash list is the applied-input proof. TransferItDownload.mjs c35dffc5 and TransferItSource.mjs 38606c97 resolve to the parent-level files of the same names.
