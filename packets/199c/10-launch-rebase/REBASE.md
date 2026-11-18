# A10 launch-identity-aware rebase

Status: HOLD pending reviewed rebase and actual test execution. This is the existing A10 source lease, not extra pump stock.

Base: e83b0d2101a811f0a52529ee28e56699322253cc. Supplied hashes bind committed bytes. Change only parseCommit in archive/gor/Sources/gor/GorCore/BuildID.swift and own Architecture/199c/10 tests. Scan every commit entry; reject malformed/conflicting entries, keep identical duplicates and legacy opaque grammar. Preserve parseTree, tree, launchTimestamp, launchLine and every current launch call site byte-for-byte. There is no current logLine API: migrate old acceptance assertion to current launchLine without reintroducing logLine or weakening identity checks.

Run actual Swift debug and optimized semantic tests, and python3 archive/gor/Tests/LaunchIdentity/launch_identity_test.py with the supplied real archive/gor/tools/gor-periodic-capture.py. Verify known build/tree/date launch line, unknown/whitespace fallbacks and real capture extract route. Preserve SOURCE-HASHES baseline and return production diff, updated own test source, exact commands/compiler/raw exit codes. Full host/native remains NOT_RUN unless separately executed. Textually clean application is not semantic acceptance.

The supplied old A10 runner/config are input for adaptation, not current acceptance or PASS evidence. Lane b baseline PASS did not include current launch semantics. No product or delivery refs may move from this packet.
