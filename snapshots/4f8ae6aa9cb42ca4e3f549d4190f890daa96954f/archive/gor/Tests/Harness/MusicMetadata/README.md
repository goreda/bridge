# Music metadata actual pure-function harness

Run `bash gor/Tests/Harness/MusicMetadata/run.sh`. Python 3 only, current mus2.py required. AST-isolates AUDIO_TAGS and three metadata helpers, no backend import/start. Five controls cover tag admission, mixed-source precedence, duration boundaries/errors, title escaping and extension cache identity. Three behavioral mutations fail. No snapshot fallback, real cache/provider/network/Swift/UI action.

Characterizations: substring audio tags can match unrelated words; negative duration formats -1:59; collection/ext inputs are not quoted while title is. Normal collection producer validity/metadata intent and installed compiled-helper parity are unverified, so no exploit/provider or confirmed UI failure claim. Preserve current collection selection policy absent evidence. PASS is actual pure-helper fixture coverage, not metadata completeness/native correctness. No production patch included.
