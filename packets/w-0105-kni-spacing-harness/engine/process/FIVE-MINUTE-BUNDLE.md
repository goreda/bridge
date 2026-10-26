# Five-minute process bundle

Owner direction source: phonemsg-01M4K81Y56KMS212H3RYQ9PJ63 and phonemsg-01M4K825DC9J1YGGAKJEYARWYX, October 10, 2026, 18:49:08/18:49:15 +03, supplied verbatim through the parent. KNI code and process state are to remain current with five-minute repository updates.

bundle-state.sh is a resumable commit/push entry point, not a running background process. A task schedule must invoke it every five minutes, reporting material failure promptly. It stages only authored code/contracts/process paths, checks whitespace, commits changes if any, and emits local HEAD. Before any push it requires an authenticated authorized remote, a verified upstream base marker and actual base ancestry; no force push. Push is checked against actual remote branch HEAD. Exit2 means blocked transport/base, not completed push; exit3 means remote result unverifiable. No credential values or retrieval logic is embedded.

The current repository remains UNVERIFIED-UPSTREAM-PLACEHOLDER; kni.verifiedUpstreamBase is NOT set. Only the integration owner may set it after exact upstream HEAD/tree validation and reconciliation. Marker existence alone is not proof. Existing source paths must be revalidated when integrating; actual upstream content is never replaced from this placeholder. Process docs, code, input custody and OPEN ledger are covered; safely scoped additional paths may be added explicitly later. No engine build/test execution is included.

No ongoing schedule or shell daemon is started by authoring this file. Loop lifecycle belongs to the coordinating parent; transport blockers remain real. No push claimed until PUSH_VERIFIED is observed with the exact current remote SHA.

## Authenticated browser relay preparation

export-flat-snapshot.sh is an authored packaging-only producer, NOT_RUN. It exports actual local HEAD with an ordered local SHA manifest; no.git, no engine build/test/run or push. Explicit destination required. Browser writer lands snapshot under its own upstream commit; local SHAs remain provenance, not upstream ancestry. Keep earlier bundler push route inactive. Repeated logged-in browser mutation cadence waits owner explicit rate-risk acceptance; no schedule started here. Parent controls relay and wakes.

Count defect root cause: initial manual snapshot file count belonged to an earlier snapshot and was not regenerated/reported from each later artifact. Added packaging self-check: derive regular-file member count, ordered SHA row count and source HEAD directly from the produced archive/manifest before delivery. Prior report counts are not repaired retroactively. Upstream relay must use artifact-derived values. File packaging is not engine execution. Producer script remains authored NOT_RUN; ad hoc archive inspection can verify current delivered artifacts independently.
