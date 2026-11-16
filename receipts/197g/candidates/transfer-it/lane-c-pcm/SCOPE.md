# Lane c transfer PCM receipt

Lane c reports GREEN on clean product a34e2cd96b6825932a196424a17cc62962e910a7 with lane-c FFmpeg 7.1 + GnuTLS on Linux. Supplied run-full.log and hashes are preserved unchanged. Actual Swift decode reportedly matched independent PCM anchor: 176400 bytes, 11 chunks, EOF, fnv 814ce7e754242528. Node refusal/cancel leg reportedly passed. This ingest did not replay the packet or independently verify the omitted runner/Swift source.

Scope: local API fixture, bounded Node download, local-file decode; no live service, whole-file MAC, coordinator registration, owner verification or product landing claim. Linux TEST evidence only. The supplied sha256.txt includes a hash-only reference to an external close-order patch; its contents were not retrieved, executed or published by this ingest. Ops owns the record.

secret scan: clean
