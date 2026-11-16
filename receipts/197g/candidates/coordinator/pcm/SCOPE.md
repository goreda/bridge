# Lane c coordinator PCM receipt (real controlled API join)

Lane c executed this packet on clean product a34e2cd96b6825932a196424a17cc62962e910a7 with lane-c FFmpeg 7.1 + GnuTLS on Linux (Swift 6.1.2, node v22.23.4). Result GREEN: M2_COORDINATOR_PCM_RESULT product_decode_exit=0; prepared local cache bytes=176444 integrity=node-key-mac; actual engine decode matched the independent PCM anchor bytes=176400 chunks=11 eof=true fnv=814ce7e754242528; cache removed only after explicit release. Transfer oracle lineage: WAV 7ef9ec96 / PCM e1c969f1 (distinct from the archive-02 oracle used by the MEGA receipt; do not merge lineage). All executed bytes published: v1 main dd8dec16, optional harness v2 main 76331ccb (typed-error wrapper), runner, fixture and dispatch Node scripts, embedded-preparation patch, close-order patch, MAC vectors, and both product-file overrides.

Harness v2 results: positive run GREEN identical to v1; dead-fixture-gateway run exits 1 with typed "FAIL source preparation typed refusal: source_refused", no SIGILL, no core, cache left empty. v1 under the same dead-gateway condition traps via top-level fatal-on-throw (rc=132) - a harness-invocation artifact, not a product result.

Clean-base resolution: same as the sibling process/ receipt - runner verifies clean a34e2cd, archives to scratch, applies patch-tls-close-order.py b89e3b16 and the listed overrides before build; hash list is the applied-input set. transfer-api-fixture.mjs reads MAC vectors from transfer-candidate/mac-vectors.json relative to its own directory; that layout is mirrored here.

Scope: controlled API fixture, node-key MAC, local-file decode; no live service, Darwin or product landing claim. Linux TEST evidence only.

secret scan: clean
