# Magnet access/tracker current-tree harness

Run `node --test gor/Tests/Harness/MagnetAccess/test_access.mjs`. Uses Node built-ins only. Imports the current vendored magnet_search.mjs directly. Does not run cli.mjs, bridge_uindex.mjs, a browser or external site; all UDP fixtures bind 127.0.0.1 with an ephemeral port. No torrent bytes or downloads.

Nine checks: valid BEP15 counts, silent/error/wrong-scrape transaction handling, row budget/populated counts, non-UDP magnet, wrong-connect transaction rejection regression, challenge HTML rejection, CLI final-parse network-trigger source anchors. This cell complements existing MagnetJSON rather than duplicating provider metadata tests.

Connect-transaction regression is fixed in the current source (promotion 6085a725; custody 40d90d73). The wrong-connect-tx test now requires unknown seed counts and zero scrape requests. Valid connect response remains a positive control. The prior baseline SHA 1ad027e2e54061e562e3e9c8b30fa73b5c046ee62964c666675a55edfba7ef99 accepted a wrong connect transaction; that is historical evidence, not current bug status.

Still open: external BEP15 sender address/port binding, packet length/action/state validation, real provider/tracker behavior and native browser/app proof. The connect-ID fix does not establish these gates.

Source comments claiming local-only/automatic clearance are not results. Tracker scrape communicates over UDP to configured tracker hosts in production; only this test uses loopback. CLI final parse can invoke a browser bridge and enrichSeeds; do not use it as an offline test. No headless/browser challenge clearance, signed-app UI, real provider access or network reliability proof. No production changes. Timeout milliseconds here are test bounds, not performance benchmarks.
