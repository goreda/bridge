# Lane c coordinator process receipt

Lane c executed this packet on clean product a34e2cd96b6825932a196424a17cc62962e910a7 with lane-c FFmpeg 7.1 + GnuTLS on Linux (Swift 6.1.2, node v22.23.4). Result GREEN: M2_COORDINATOR_PROCESS_RESULT product_decode_exit=0, 33/33 PASS including explicit share prepare, seven invalid-transfer-shape refusals (never raw media), lease/cache lifecycle, typed refusal redaction, cancellation and orphan-cache checks. All executed bytes published in this directory: Swift main, runner, fake/fixture Node scripts, and the two product-file overrides (NodeSourcePreparation.swift d8292cd6, OpenURLRouter.swift 0f3fa423) applied to the tree before build.

Clean-base resolution: the runner verifies a clean a34e2cd checkout (rev-parse + empty status), archives it to a scratch tree, then applies the listed overrides/patches before building. Final build tree = clean base + listed inputs; the hash list is the applied-input set, not colocated references.

Scope: controlled fake-child process fixture only; no live service, real API join, MAC, Darwin or product landing claim. Fault coverage here uses the fake child; the real-API join is the sibling pcm/ receipt. Linux TEST evidence only.

secret scan: clean
