# MEGA bounded harness candidate

## Latest supplied result: 128-byte full pipeline GREEN

Team A reports v2 full prepareMegaFile pipeline on 128 bytes of owned data under a 64 MiB heap cap and 5-second wall limit: exit 0, all assertions pass. Supplied bounded-128-test-v2.log preserved unchanged. Checks cover ciphertext download/decrypt/MAC byte identity; tamper, wrong-key and unknown-file refusal; size cap; timeout/cancel; output cleanup. This ingest did not replay the harness.

## Earlier RED results retained

The first 128-byte full-pipeline diagnostic was RED, exit 1, because the fixture disconnected on cancellation. The v2 harness handles that expected aborted-client ECONNRESET. Earlier crypto-only 128-byte roundtrip GREEN was narrower evidence. The earlier 176 kB full download/decrypt SIGKILL (exit 137) remains unexplained and RED/unproven; the new 128-byte result does not settle that failure or establish size-general behavior.

MegaVerifiedSource.mjs and a resolved megajs dependency closure remain absent from this directory. This is a supplied harness plus reported-result candidate, not a complete runnable bundle. No live service, product integration, acceptance or size-general claim. Ephemeral fixture keys are generated at run time, not included as saved values.

secret scan: clean

## Later lane c controlled full-size GREEN

See lane-c-pcm/ for subsequently supplied Linux TEST evidence on a 176444-byte fixture: lane c reports full ciphertext download/decrypt/MAC and actual Swift local-file decode equal to the independent PCM anchor, with no SIGKILL in that run. This supersedes the earlier unproven full-size status only for that specific later controlled run; earlier failure cause remains unexplained. No size-general, ranges, live-service or coordinator claim. This ingest did not replay the run. Bundle sources/dependency closure are still absent from this directory.
