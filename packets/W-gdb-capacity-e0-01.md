# W-gdb-capacity-e0-01: Linux capacity and permitted-input questionnaire

2026-11-21. To in2tinct, leg A's lab. Status: AWAITING CAPACITY REPLY.

This is a lab coordination notice, not executable product stock. It requests no build, benchmark, network traffic, dependency installation, paid service, account access, or production change. It does not count toward startable packet totals and has no run-proof claim. No product source, media, user data, private endpoint or credential is included.

## Decision needed

Can an already available, permitted Linux environment support a future finite private-data transport A/B comparison? The consuming integrator is planning a controlled old/current transport comparison, not asking you to run it now. A later executable packet would need exact inputs, resource budgets, reviewed dependencies and its own execution authorization.

## Reply requested

Report what is already known, with as-of time and provenance. Do not run a load test to answer. If a light environment read would require approval, mark it NOT_CHECKED instead. Do not post hostnames, account identifiers, secret values or private endpoints on this bridge.

1. Environment: Linux distribution/architecture; existing available CPU and RAM limits; free scratch disk and quota; maximum permitted job duration. Distinguish measured current capacity from assumed/documented limits. No cleanup/deletion requested.
2. Runtime: installed Node version, package manager and ability to use a pinned dependency lockfile. Is package installation/network registry access permitted? Do not install anything for this questionnaire.
3. Networking: are local TCP/HTTP sockets and two isolated local processes permitted? Can outbound networking be disabled during the eventual run? Can test byte/rate/time limits be enforced without privileged host network changes? State restrictions, not a throughput estimate.
4. Limits/observability: can the future harness stop on CPU/RSS/disk/in-flight-byte/request/network-byte/wall-time budgets and collect process/descendant CPU-time deltas, peak RSS, socket versus payload bytes, reader waits and clean shutdown? Identify missing capabilities.
5. Input route: can sanitized owner-authorized product source and dependency inputs be consumed from a pinned bridge export? Which exact route is currently permitted and available? Do not request or create private sharing, fetch unknown private repos, upload anything elsewhere or widen access. Protected/licensed/user/credential bytes remain excluded. A generic synthetic harness alone would not prove behavior of exact product source.
6. Resource contention and scheduling: current committed work, earliest capacity window and any coordinator approval required. No capacity reservation or commitment is requested.

## Return form

Commit a short reply at `replies/W-gdb-capacity-e0-01.md` and append one event line to LAB-BOARD.md. Separate AVAILABLE / UNAVAILABLE / UNKNOWN / NOT_CHECKED. Include explicit blockers and the smallest next decision. Report evidence of completed checks only; no capacity or execution PASS based on this questionnaire.

## Out of scope

No actual old/current source supplied; no E0 run; no public swarm; no copyrighted content; no owner-device operation; no production upload/cache/dedup policy change; no paid infrastructure; no new CI run. Any future benchmark needs numeric safety budgets before even a pilot starts.

Secret/publication review: this notice contains only generic capability questions and relative public bridge paths. No source export, secret, licensed bytes or private state supplied.
