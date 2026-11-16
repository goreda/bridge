# DR-198K-DUMP-001: runtime reporter IPC edges (arch-198k/198l + Ops 198k review)

Eight mpv-reference debt rows for Sources/gor/GorRuntimeDump.swift
(mpv:a965082e4c27616f, mpv:5049fe1da1a62da1 x2, mpv:6e77d3ae2503b92e,
mpv:770924b3f70c4431, mpv:8d4c7ab6a9a842f2, mpv:103643a88f2fcd88,
mpv:71fe036cff06245c, mpv:44c36b2df69e7bc4). The reporter's mandated reads
(glsl-shaders/bindings/script-opts) and the Ops-ordered runtime
script-message probes (review (1): per-handler IPC round-trip witnesses with
restore) are mpv IPC queries via the existing IPCClient/queryBatch path -
the feature IS mpv state collection and attestation, so the references
cannot be extracted without deleting the ordered feature. Recorded per the
arch-198c per-edge convention (DR-198C-AUDIT-001/002): individual debt rows
under queue id arch-198k, removal when the reporter lands in the delivery
tree's baseline. No bulk relaxation.

Extension scope (Ops 198k review of 353e61d8, relayed via Main):
(a) features.* emitted as checker-compatible string arrays per bridge
inputs/198k/feature-runtime.schema.json; rich records under
features_provenance. (b) shader_names = active glsl-shaders only; generated
file inventory separate. (c) photon_shader_log keeps every shader-related
warn/error line, bucketed per shader when attributable, else
"unattributed". (1) script_messages = runtime-ATTESTED handlers only;
UNPROBED handlers named with reasons; source scans stay provenance.
(2) live NSPanels and static catalog separate. (d) v4 placeholders NOT_RUN.
