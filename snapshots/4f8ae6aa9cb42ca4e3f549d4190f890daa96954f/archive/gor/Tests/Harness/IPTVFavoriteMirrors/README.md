# IPTV favorite mirror persistence

Run `bash gor/Tests/Harness/IPTVFavoriteMirrors/run.sh` (Python 3, current `Sources/gor/IPTV.swift`).
Reads the persisted key set from `saveFavorites()` in source and models save->load->failover.
Mode `loss` (current main): proves a favorite saved with main + two mirrors reloads with main/identity intact and zero mirrors, so `tryNextAlternateURL` goes straight to "all URLs failed".
Mode `fixed` (after the `alts` patch): proves mirror order, failover candidates, dedupe and old-record loading.
Out of scope: real UserDefaults, restart, playback, Swift/UI execution. Supersedes the "alternateURLs not in saved schema" guard in `IPTVFavorites/test_favorites.py` once the fix lands (that cell must be updated then).
