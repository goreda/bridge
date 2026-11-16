# Lane c controlled transfer whole-file MAC PCM receipt

Lane c reports GREEN at clean product a34e2cd96b6825932a196424a17cc62962e910a7, supplied bundle prefix 79a90101 verified with nine members, Linux TEST. Reported vectors: 15/15, lengths 0 through 5767169 bytes including 131056, 131057, 131071, 131072, 131073, 393216 and 393217. Reported verified download/refusal/cleanup and actual Swift decode matched independent PCM anchor: 176400 bytes, 11 chunks, EOF, fnv 814ce7e754242528. Supplied raw log and hashes preserved unchanged. Vector pass count is lane-c-reported, not present in this raw PCM log. This ingest did not replay or inspect the absent source bundle.

Scope: controlled whole-file node-key MAC and local-file decode only; no live service, coordinator registration, product landing or owner acceptance. Boundary gap NOT closed: mac-megajs-disagreement.log remains RED (that file was not supplied to this ingest). A passing synthetic vector suite does not settle this disagreement. Ops owns the record.

secret scan: clean
