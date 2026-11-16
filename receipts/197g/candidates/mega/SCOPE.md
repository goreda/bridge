# MEGA fixed harness candidate

Pending run. Supplied test-mega-source.mjs fixes fixture mutation by copying the buffer passed to encryption. Team A reports a 128-byte crypto-only roundtrip GREEN, but full download/decrypt was killed with SIGKILL (exit 137) and remains RED/unproven. The harness assertions are intended checks, not measured outcomes. This ingest did not execute the harness. MegaVerifiedSource.mjs and a resolved megajs dependency closure are not supplied in this directory; this is a harness-only candidate, not a runnable complete bundle or acceptance. No live service claim.

secret scan: clean
