# Lane C review of lab returns G0927-G0930 / H0660 (arch-199h D5 + writer stock)

Posted 2026-11-18 13:2x +03 by Team B relay. This note is information for the bridge, not orders. Reviewed against the current composition (native49 source b570c15ac). Do not adopt the reviewed D5-01..09 returns over the current composition.

## Findings per return

- D5-01 (film-frame map): loop defect - k=0 with `while k<=e-s` but k never incremented; witness produced [72,72,72] where corrected pairing gives [72,73,74].
- D5-02 (MKV stream-copy segment): standalone ShotSegment, not wired into the render path; uses a direct ffmpeg cache URL with no quota sink.
- D5-03 (drop prepare step 2b): overlaps D2a v3; needs a source-aware rebase.
- D5-04 (source_shot migration): migration deletes source proxies under SH pin; retirement must be exclusive to owned entries.
- D5-05 (render retention window): lacks reentry and unknown-playhead protection.
- D5-06 / D5-07 (D3 session / coordinator+PreparedShotPlayback): overlap D3 session r2 and lack the r3 cachePin capture.
- D5-08 / D5-09 (D4 seek repro / fix): helper tests do not prove a defect in the real seek API; 09 calls nonexistent currentBinding()/descriptor(for:) - the real API is seekDescriptor(session:) with referenceOrigin/audioTimebase.
- D5-10 (emitter automation): parameterize the native48 finalizer (repo/ledger/carrier paths, source pin, receipt prefixes, candidate ref, baselines) into an explicit-input adapter; keep the result/source-map/executable/baseline binding checks; fail closed; enforce before CI and at atomic promotion with expected old refs revalidated at mutation.
- WR03 (installed BuildID read): applies in principle; needs a current-candidate BuildID check; rollback caller and launch logging not wired.

## Disposition

Returns not adopted. Next packet round is re-pinned to the current composition (native49 source b570c15ac) with these findings carried as acceptance notes.

secret scan: clean
