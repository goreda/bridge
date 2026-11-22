# mpv surface inventory

Generated from the gor delivery source, repository goreda/instinct, branch mac-source-sync-20261103, source HEAD 4fc6777a3 (includes f122d588 / 42c45e80 and backend seam). Fetch that branch from https://github.com/goreda/instinct.git . It is not the historical partial goreda/gor import.

Generator: `python archive/gor/Tests/PlayerBackend/inventory.py` from repository root. Columns are kind, name, call site file:line, value type. Scope: shipped Swift source, all bundled Lua scripts including Photon/stats/clip, mpv input.conf. Test fixtures, old project archives and mpv's own default keymap are excluded.

Commands and literal property names are extracted from actual source. The fast/slow/cache/observed Swift tables resolve the corresponding generic get/observe paths. Lua API suffixes provide types, Swift literal set values provide types, and unknown/native return types remain unresolved rather than guessed. `*-dynamic` rows retain the actual source expression/call so a migration author can inspect it. These rows are NOT invented mpv property names. The scanner is a source-derived inventory, not runtime coverage: wrapper aliases, computed property names, generated command arrays and runtime user-script additions can require expansion. It must not be treated as proof that every dynamic runtime target is enumerated.

No E1 or backend-equivalence claim follows from this inventory. Calls to mpv-only scripts may need an adapter or a deliberate unsupported-feature decision in GorAV.
