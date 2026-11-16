# Transfer plaintext MAC candidate, 2026-11-16 15:21 Europe/Istanbul

Choice: for the transfer.it plaintext download contract, use documented per-chunk CBC MAC and final meta MAC, with no synthetic EOF chunk. Do not silently substitute MEGAJS encryption's differing exact-boundary behavior. This is a controlled candidate, not current-service validation.

Source-grounded contract:
- https://github.com/feelmypain/transferit-cli/blob/main/API.md
- https://github.com/feelmypain/transferit-cli/blob/main/script.go
Fetched15:18-15:20. Unofficial reverse-engineered sources. Go verifyDownloadedReader/computeFileKeyFromReader/chunkMACs calculate plaintext chunk MACs using nodekey, 128KiB increasing chunks to1MiB, CBC nonce IV and zero-IV condensation. Empty has no chunks. Node key must be32B for full-file verification. Transfer plaintext bytes are not decrypted a second time.

Implementation: TransferPlainMAC.mjs streaming block verifier (Node builtin crypto, no dependencies). TransferItVerifiedSource.mjs retains key inside a verifier factory closure rather than logging/serializing it. TransferItVerifiedDownload.mjs must verify exact byte count and MAC before reporting success; mismatch removes cache. Old unverified candidates/receipts remain untouched.

Independent synthetic oracle: generate-mac-vectors.py uses Python cryptography batch CBC rather than streaming Node. Its fixed bytes00..17 upload key is public synthetic test data, never a service credential. mac-vectors.json contains15input lengths, fixed data hashes and expected filekeys. Node runs each with17/4093/65536B update fragmentation, tampered plaintext and altered expected metaMAC. Sizes0/1/15/16/17/131056/131057/131071/131072/131073/176444/393216/393217/1048577/5767169 allPASS locally. Generating vectors requires Python cryptography; Linux replay can use supplied hash-bound vectors without package installation. Test source and generator both supplied.

Real disagreement preserved: diagnose-megajs-boundary.mjs (requires separately supplied pinned MEGAJS1.3.10 under ../mega-candidate/node_modules) exits1. Sizes0/131057/131071/131072/393216 differ from documented batch oracle, other10match. MEGAJS condense includes reset state after an exact padded chunk boundary. No actual transfer.it server vector settles this. mac-megajs-disagreement.log staysRED and must travel with receipt. No claim either algorithm is confirmed compatible with all live files. The176444B media fixture does not hit a disagreement.

Local verified download measurement: 176444B independent WAV SHA2567ef9ec96e9434e9175c06c6f7c7858ff394383286d9790aaa353f4c1f172dab7, plaintext MAC matches independently generated synthetic nodekey. Same-size corruption -> exact integrity_mismatch+cache cleanup. Existing file/caps/HTML/downgrade/loop/short/timeout/inflightcancel checks retainPASS. Current service, cross-originHTTPS stripped-header test, ranges and default coordinator remain open.

Pending Linux measurement: extract this bundle under transfer-candidate/ beside parent patch-tls-close-order.py; run bash transfer-candidate/run-transfer-verified-pcm.sh CLEAN_A34_CHECKOUT FF_PREFIX. It runs all15protocol vectors and controlled verified-download faults, saves successful downloadedWAV+separate rawPCM anchor, then actual product decoder must reachEOF/44100stereo/exact176400BData equality. Existing lane-c unverified-download recipe measured11chunks/FNV814ce7e754242528; new MAC recipe not yet run by lane c. No run_proof is fabricated. Product branch landing requires parent/lane ownership.
