# Lane c open-url router tests receipt

Lane c executed open-url-tests on clean product a34e2cd96b6825932a196424a17cc62962e910a7 with lane-c FFmpeg 7.1 + GnuTLS on Linux (Swift 6.1.2). Test main 87e03266 unchanged across both runs.

Current: router 0f3fa423 GREEN, 31 PASS 0 FAIL (run-full.log). Covers MEGA/magnet/torrent/generic routing, explicit transfer preparer/refusal (never raw media), percent-encoded host and path, trailing dot, userinfo, port, query, fragment, valid trailing slash.

Preserved RED: router 835add3f RED, 30 PASS 1 FAIL (run-router-835add3f.log): https://%74ransfer.it/t/a (percent-encoded host) routed to needsTransferResolver because URLComponents.host returns the percent-decoded host on this toolchain. Router 0f3fa423 refuses '%' in the raw authority before host normalization and closes exactly this case; the 835add3f result is kept as a separate historical record, not superseded silently.

Scope: routing classification unit tests only; no service, download, decode, Darwin or product landing claim. Linux TEST evidence only.

secret scan: clean
