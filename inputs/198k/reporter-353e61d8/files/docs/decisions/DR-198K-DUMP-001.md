# DR-198K-DUMP-001: runtime reporter IPC edges (arch-198k/198l)

Two mpv-reference debt rows for Sources/gor/GorRuntimeDump.swift
(mpv:a965082e4c27616f, mpv:5049fe1da1a62da1). The reporter's mandated reads
(script messages/bindings/glsl-shaders/script-opts) are mpv IPC queries via
the existing IPCClient/queryBatch path - the feature IS mpv state collection,
so the references cannot be extracted without deleting the ordered feature.
Recorded per the arch-198c per-edge convention (DR-198C-AUDIT-001/002): two
individual debt rows under queue id arch-198k, removal when the reporter
lands in the delivery tree's baseline. No bulk relaxation.
