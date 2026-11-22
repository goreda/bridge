# PollEngine property store and cadence harness

Run `bash gor/Tests/Harness/PollEngine/run.sh`. Python 3 only, current PPController.swift required. No snapshot fallback, Swift/timer/Dispatch/mpv/socket/UI execution. Distinct from IPCTransport wire framing and gorav rendering.

Nine controls cover source-derived property ID tables, playing/paused tiers, kicks, disabled/disconnected/idle suppression, terminal reply flush IDs, null/error removal, state changes and file-scoped purge. Three source mutations fail. Subscription reinstall and absence of time-pos observation are current source guards. Cadence is modeled, not measured elapsed time.

Characterizations preserve adversarial ordering: copied main-queue snapshots survive live-store purge; a prior-file reply arriving after purge can refill a fixed-ID property; fast-tier snapshots contain older slow/event values by design. These are not observed mpv/UI incidents. Main queue FIFO and actual start-file/reply ordering can constrain the scenarios; native evidence is needed before calling them visible defects. PASS means controls/characterizations reproduced, not queue or player correctness clearance.

Future validation should capture real ordered event/reply traces and test file-generation suppression without breaking paused/kick/tier behavior. No production fix included. Timer accuracy, start/stop/reconnect ordering, response source identity, player-side consumption and native UI remain open.
