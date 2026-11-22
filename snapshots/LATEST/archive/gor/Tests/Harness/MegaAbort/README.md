# MEGA relay abort and error actual-handler fixtures

Run `bash gor/Tests/Harness/MegaAbort/run.sh`. Node built-ins only, current mega_relay.mjs required. Isolates current HTTP handler in VM with controlled Readable fixtures and actual loopback client close/error/clean completion. No snapshot fallback, real provider/media, backend imports, Swift/mpv/UI or production action.

Three actual controls: downstream abort pauses/destroys upstream without ERROR, genuine source error emits ERROR and destroys, clean completion avoids ERROR. Mutation outcomes recorded explicitly; pipeline can supply cleanup independently, so surviving redundant mutations are not a false negative claim. No real MEGA transfer or account behavior clearance. External upstream semantics, repeated connections/pressure/error codes and Mac playback remain open. Complements MegaHTTP headers/range fixtures. No production patch included.
