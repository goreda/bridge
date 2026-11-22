# HLS quality resolution and selection ownership

Run `bash gor/Tests/Harness/HLSResolution/run.sh`. Python 3 only. Current PPController_Features.swift required; no snapshot fallback. No network fetch, HLS stream, Swift/Foundation/mpv playback or UI execution. Separate from IPTVIngestion M3U channel parsing.

Five controls preserve highest-bandwidth policy, absolute/simple-relative URLs, media-playlist fallback, non-HLS pass-through and current invalid-bandwidth/comment behavior. Three source mutations fail. Counterexamples cover root-relative/network-path/dot-parent URI references with source string concatenation, blank URI line, leading tag whitespace and out-of-order A/B completion that queues old loadfile/quality list. Python URI comparison is not Foundation URL execution; malformed/whitespace cases are characterizations, not externally certified HLS compliance failures.

Priority handoff: scope completion to the active selection and resolve URI references against the master URL without changing highest-bandwidth selection policy. Preserve direct non-HLS and media-playlist fallback. Review query/fragment/redirect/audio/codec semantics with native tests before a production patch. Native URL parity, network order, HTTP failures, equal bandwidth ties, quoted attributes and quality UI remain open. PASS retains expected counterexamples; it is not correctness clearance.
