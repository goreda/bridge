# MEGA relay HTTP handler loopback harness

Run `bash gor/Tests/Harness/MegaHTTP/run.sh`. Node built-ins only. Reads current mega_relay.mjs and isolates HTTP server block in a VM with synthetic 16-byte source. Seven actual loopback controls cover GET/HEAD/body lengths/ranges/method/bounds. Socket uses 127.0.0.1 ephemeral port and closes on completion. No snapshot fallback, backend imports, real MEGA source/provider/download/Swift/mpv/media/UI or production action.

Three behavioral mutations rejected. Two surviving mutations are documented, not counted as rejected: redundant start-bound check, and second HEAD writeHead after prior headers. Suffix ranges, oversized ends and multiranges return 416; actual results, not certified HTTP compliance failures or requested policy change. Upstream errors/abort/empty source/mpv seeking remain open. PASS is isolated handler coverage, not streaming reliability.
