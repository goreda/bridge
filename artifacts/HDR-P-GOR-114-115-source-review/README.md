# HDR-P-GOR 114/115 source review export

Source-review only. No native compile, runtime, EDR display or subtitle SDR-white pixel acceptance is claimed. No source is applied to a product branch, and no delivery ref moves.

The manifest resolves every requested pin in goreda/instinct. Four complete Swift files are exported at each of the shell-handoff, gor-candidate, subtitle-availability-guard and computed-state-fix commits. Each snapshot has its original product path, full commit, Git blob id, SHA256 and byte count. The spec pin is resolved but its private body is not included. Snapshots are distinct historical trees, not an assertion that the four commits compose or that any one is the current delivery.

Review interface: HDRSurfaceHandoff owns weak presenter state-source/metrics-sink references and routes revisioned HDRSurfaceState. HDRScreenMetrics uses screen points plus a separate backing-scale ratio. Presenter owns negotiation and drawable pixels; shell reads screen/window metrics. GorAVHostWindow/GorAVPlayerHost are callers of the handoff; SubtitleView.setupLayer is the subtitle presentation seam. Follow the exact exported signatures and call sites, not this short orientation.

The computed-state fix removes private(set) from a read-only computed property. The availability guard wraps three wantsExtendedDynamicRangeContent=false assignments in macOS14 availability. Those source facts do not prove successful native behavior or SDR-white pixels.

Run python3 artifacts/HDR-P-GOR-114-115-source-review/verify.py from the bridge root. Expected: PASS 16 source snapshots match manifest. This checks export integrity only. Review result should cite full pin, file/line, finding and any suggested Swift-only patch; no runtime acceptance can be returned from this packet. Target is the existing HDR-P-GOR candidate/review queue, not a delivery branch. No new lab implementation request is created by this evidence export.

No-secrets scan: credential formats, contact identifiers and private endpoints checked across the exported source/patch bytes before publication. Only Swift source and Swift text patches are carried. No credentials, user data, licensed fonts, media, captures or binary assets. Product repositories stay private.
