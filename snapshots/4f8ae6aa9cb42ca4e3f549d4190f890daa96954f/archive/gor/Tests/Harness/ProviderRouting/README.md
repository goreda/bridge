# Provider URL routing harness

Run `bash gor/Tests/Harness/ProviderRouting/run.sh`. Python 3 only, current CDPSession.swift required. Eleven valid/unknown provider routing controls and three negative-source mutations. No snapshot fallback, browser/provider/network/Swift execution or production edit. This classifier is separate from TransferResolver's fixed parsed archive-download capture gate.

Admission characterizations: provider text inside unrelated URL query/path still matches substring classifier; uppercase host can miss; incomplete internal pseudo-link can route with empty fields. External exploit, navigated destination or installed user failure is not demonstrated. Internal pseudo-link provenance and caller validation remain open. PASS is classifier/source port consistency, not URL security/provider correctness.

Priority handoff: parsed scheme/host/path routing while preserving internal pseudo-link protocol, provider precedence and valid IDs. Verify caller inputs and Foundation URL semantics before a production patch. No guessed provider availability or authorization claim.
