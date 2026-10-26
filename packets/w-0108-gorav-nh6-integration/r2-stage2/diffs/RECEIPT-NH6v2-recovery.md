NH6 v2 isolated-validation: consolidated receipt qualification (bounded existing-state recovery;
NO rerun, NO new build, NO new matrix). Supplements run log da7f7132 (41/0, exit 0, zero
gate-timeout lines, explicit selector NH6 a-f, timeout -k 5 180).

== RECOVERED FROM EXISTING STATE ==
1. Fixture binding (actual run path): S5_SEEK_FIXTURE=/tmp/s5build/fixture.mov per the recorded run
   command (build-commands.txt). sha256 397930c3283da04fed563ecfdf0d49a0a89ffac9b5fe00704b78ff8f16094f8e
   recorded PRE-RUN at 04:25:28 (layout step) and re-verified POST-RUN at 04:28:56 against current
   bytes (unchanged; 2,962,036 bytes, mtime 03:39, file(1): ISO Media / Apple QuickTime .MOV).
2. CAtomics origin (compile command was omitted from build-commands.txt - writer omission, corrected
   here from the writer transcript record 04:25:35):
   cc -fPIC -shared -O2 gorav_atomics.c -o /tmp/s5iso/obj/libGorAVCAtomics.so
   cc = Ubuntu gcc 11.4.0-1ubuntu1~22.04.3. Source pin 403f68e0 (gorav_atomics.c) + header
   0619d60e + modulemap 6e620ba9 (source-manifest.sha256); object c067ab79 (object-hashes.txt).
   Printed status was "atomics-ok" via shell && chain (genuine shell record).
3. Modulemap bytes: pinned in source-manifest.sha256 (CFFmpeg 7fd87c43, GorAVCAtomics 6e620ba9).
4. FFmpeg: static .a hashes recorded pre-build (4d6bca1b / 28f20b25 / 30d1381e). Independent FFmpeg
   BUILD receipt NOT available (built in a prior session from branch tar 894da5ca, kit-minimal
   configure, gcc - per NH packet README v4); link receipt is de facto: adapter/exe link success is
   evidenced by object existence + hashes + the running binary, not by a captured link status.

== RECEIPT CAVEATS (honest qualification, not new failures) ==
5. Per-command "exit=0" echoes in my build transcript captured the pipeline TAIL's status, not
   swiftc's; they are not compiler exit records. Build success is evidenced by object
   existence/hashes and the executed binary; the one real build failure (core attempt 1, missing
   atomics modulemap) emitted error text and was retried with the fix - retry history is in
   build-commands.txt.
6. The RUN's true-exit=0 IS a genuine shell record ($? of timeout(1) captured immediately).
7. Freshness (rm -rf /tmp/s5iso + fresh mkdir) remains a WRITER CLAIM; no clean-objdir trace was
   captured. Manifests are runtime path pins, not independent source->object proof.

== SCOPE PHRASING (peer 1/2 correction folded) ==
8. The six HELD transactions (NH6a-f) are PRE-ENTRY: reachedStage .preSeek, av_seek_frame never
   entered for them. NH6b.providerUnpoisoned starts a SECOND, fresh recovery seek expecting
   nativeReady; that seek runs the normal path (avseek + flush + open/prime decodes) and is NOT
   held-native / post-entry-cancel evidence. The run must not be described as "no avseek" overall.
9. Standing limits unchanged: NH6c.postPoisonRefused is an untyped catch-all; only NH6f is typed
   SeekRefusal.closed. resumePolicy is a PUBLIC SeekReceipt field (coreGated disposition) that the
   tests do NOT assert - not proved at runtime, surface not absent. cancelledNoMutation carries no
   facts. Atomic gap-absence is a SOURCE property, not a timing witness. Evidence class: ONE
   writer-run Linux diagnostic, partially bound; NOT independent reproduction, production adoption,
   live-branch change, Mac/RT, whole-S5, NH1-5, merge, or kit.

== STILL OPEN (not recovered, not retro-created) ==
Glob-expansion trace, compiler warning stream, loader trace, standalone prod 1d019d42 compile,
current integration state.
