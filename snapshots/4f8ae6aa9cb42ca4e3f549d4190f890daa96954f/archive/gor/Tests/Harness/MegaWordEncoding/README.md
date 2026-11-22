# Synthetic MEGA node-word encoding contract

Run `bash gor/Tests/Harness/MegaWordEncoding/run.sh`. Python 3 only, current CDPSession.swift required. Invented fixture words only, never account credentials or real provider keys. Signed boundaries, string/integer equivalence, invalid shape and 1000 seeded roundtrips. Three source mutations fail. No snapshot fallback, provider/decryption/network/Swift execution or production edit.

Python packing port covers integer fixtures, not Foundation NSNumber Bool/float/overflow coercions. Arbitrary nonempty word counts and empty handles remain helper admission characterizations; actual provider key format/caller requirements were not established and no cryptographic failure is claimed. PASS is source/serialization-port evidence, not key/decryption/native correctness. No real secrets or source snapshots included in package.
