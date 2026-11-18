# D5-10 validator inputs

Current carrier layout: repo root contains ci/, payload/gor/, out/. Product repo layout: archive/gor/. macOS is required for automatic native graph emission; do not fake graph success on Linux.

Before CI: materialize candidate product source into payload/gor, preserving executable bits; run `python3 ci/native49-emit.py` from carrier root. It runs graph/inventory emission through payload/gor/tools/architecture.py, writes architecture/manifest.tsv and delivery.tsv, creates a local carrier-only commit, runs the production read-only integrity branch and manifest_tree_test, then writes out/native49-native-manifest.json and two native49-*.tsv copies. No remote promotion is performed by emitter.

At promotion: native48-finalizer.py currently has explicit native48 source-pin and local path constants. It is supplied as an exact example, not a generic native49 validator. Command: `python3 native48-finalizer.py --artifacts RECEIPTS_DIR --build-id BUILD_ID --build-url OBSERVED_BUILD_URL --live-carrier FULL_CARRIER_SHA`. It writes class-e-receipt.json and promotion-proof.json and a local manifest-only candidate ref. It does not push delivery refs.

Materialize the exact resulting candidate in a clean worktree, then run `python3 production-integrity-gate.py --root WORKTREE/archive/gor` and `python3 WORKTREE/archive/gor/Tests/Architecture/manifest_tree_test.py`. The production gate extracts only build.sh's read-only integrity branch, before install. Require both exits zero and native receipt candidate/input maps equal. Repeat on the exact candidate at atomic promotion; expected old refs must also match current remote state.

Output: delivery.tsv columns path, sha256, mode; manifest.tsv columns are architecture.py HEADER (source classification/target inventory, not artifact access grants). Native emitter receipt has result, source_pin, platform, manifest_tree_test, graph_errors_advisory, targets, files{architecture/name:SHA256}, scope. Finalizer output includes candidate, exact compile/static/native/emitted-manifest/updater evidence and owner-install runtime deferral. Never treat a carrier/source map alone as updater integrity PASS.

No credentials, deploy key names, key paths, or authentication helpers are included.
