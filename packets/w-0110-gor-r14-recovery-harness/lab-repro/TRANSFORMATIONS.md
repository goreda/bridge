# W-0110 transformation disclosure

Source pin: goreda/bridge @ 91da2e7f2433e712a8b9341b404ffa6ce1fd9964
- packets/w-0110-gor-r14-recovery-harness/AppDelegate.swift
  sha256 3ce05563098bc930d96315f657aa2a71676e6a73a66493278ced6dd9af380a55 (3329 lines)
- packets/w-0110-gor-r14-recovery-harness/test_update.py
  sha256 3b2667a7fe8053af8682d339ffe77a7ece43bc706adf8a3dd0d944a8482c7f3c

Extracted VERBATIM (byte-identical body text, comments included):
- recovery state fields (source lines 115-122)
- `static func isYoutubeURL` (lines 1230-1233)
- `static func isYoutubeOpenFailureDiagnostic` incl. the 403 regex (lines 1235-1242)
- `func invalidateYoutubeRecovery` body (lines 1245-1251)
- `func handleYoutubeOpenFailure` body (source lines 1253-1315)

Disclosed mechanical injections (each replaces exactly one dependency token;
control flow, guards, print log lines and the byte-compare expression are
unchanged production text):

1. `dispatchPrecondition(condition: .onQueue(.main))` - REMOVED (2 lines).
   Reason: swift-corelibs-libdispatch on Linux does not provide
   dispatchPrecondition; the harness drives all entry points from one thread,
   so the main-queue contract is upheld by construction. No semantic change to
   ordering: production async hops are reproduced via the gated executors.
2. `AppDelegate.stagedYtDlpPath()` -> `stagedYtDlpPathProvider()`.
   Production resolves Bundle.main vendor paths / Application Support staging;
   the harness injects temp fixture paths (legacy staged binary and a
   `/yt-dlp-standalone/` path). Both branches of the production dispatch on the
   path string are exercised.
3. `controller?.currentTime` -> `currentTimeProvider()`.
   PPController is AppKit-side product code outside the pinned source.
4. `mpvProcess` (Process?) -> `mpvProcessToken` (AnyObject?).
   Identity semantics preserved: the `mpvProcessToken === playbackProcess`
   guard is the production `===` check; tests swap the token to prove the drop.
5. `Process()` -> `updateProcessFactory()` returning the `UpdateProcess`
   protocol (class-constrained, so the production `let update` + property
   sets compile unchanged). LABELED FAKE process; the before/after byte
   comparison runs against REAL temp files the fake actually rewrites, so
   `before != nil && after != nil && before != after` executes as production.
   The factory and the main executor are captured as locals immediately before
   the background closure (`let updateProcessFactory = self.updateProcessFactory`,
   `let mainExecutor = self.mainExecutor`) because production news `Process`
   directly and first touches self only in the main continuation; the closure
   capture list `[weak self]` and the inner `guard let self` are production text.
6. `DispatchQueue.global(qos: .userInitiated).async` / `DispatchQueue.main.async`
   -> `backgroundExecutor.async` / `mainExecutor.async`.
   LABELED FAKE Dispatch executors (GatedExecutor): queued blocks run only on
   explicit harness ACK, so async ordering is proven by gates/ACK, never sleeps.
7. `playMedia(url:title:startPos:subtitleURLs:)` -> recording stub.
   LABELED: playMedia is product code defined outside the pinned source file;
   the stub records calls for assertion and performs no playback.

NOT done (packet prohibitions respected):
- no rewritten boolean model substituted for the actual source
- no canonical AppDelegate edit, no product push/merge/deploy
- no AppKit/UI/native/CDN-403-cure claim, no credentials, no network
