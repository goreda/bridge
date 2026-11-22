# gor

macOS video player. Headless mpv with a full custom AppKit/CALayer overlay
(spine UI). Variable font across the whole interface; font axes respond to
mouse proximity and system audio level (photon). Also: HDR/SDR real-time
gamma, magnet/torrent streaming (wt_server), archive.org streaming, music
mode, film-frame aware UI via black-bar crop detection (GorFit),
OpenSubtitles integration, IPTV browser.

## Layout

- `Sources/gor/` - Swift sources (AppDelegate, PPController, SpineUI,
  GorFit, TorrentManager, panels and controllers).
- `Resources/vendor/mpv/` - vendored mpv, lua scripts (photon*, gor-fit,
  gor_stats, autoload) and input.conf.
- `build.sh` - the single build route (SPM). No other build entry point.
- `install-r62.sh` - applies the branch tree into the active project.

## Build

Daily development build (media telemetry on):

    ./build.sh --update

Distribution package (media telemetry off via `GORMediaTelemetry` false):

    ./build.sh --dmg

Requires macOS with the Swift toolchain. The active project is
`~/Downloads/gor`; never build or install into archived copy trees.

## Source and update route

The sole source route is branch `mac-source-sync-20261103` of
`goreda/instinct`, mirrored in the owner's sidecar clone
`~/Downloads/gor-repo-sync`. One update command:

    cd ~/Downloads/gor-repo-sync && git pull --ff-only origin mac-source-sync-20261103 && bash archive/gor/install-r62.sh && cd ~/Downloads/gor && ./build.sh --update

Every apply first backs up overwritten sources into
`~/Downloads/gor-bbu/<YYMMDD-HHMMSS-action>`, then installs; a failed step
restores the previous state.

## Working rules

- A change is work only when it is landed on the project branch and has
  run its real test in the same round (owner block 179). One version per
  change; review problems are fixed on the branch.
- Landed deliveries are committed to the repo; the repo tree matches the
  latest delivered source.
- Repo text is English. UI/HUD text follows the interface's existing
  language unity; nothing Turkish lands in code or docs.
- New Swift files only for a process/IPC lifecycle, a panel or window
  with its own view tree, a domain with its own invariants, or a shared
  contract with several consumers (177 d4); diagnostics live in
  `Diag.swift`.
- Docs: this README, `STATE.md` (live state), `JOURNAL.md` (append-only).

## Delivery checklist

- Playback-touching changes go through `PlayerBackend` after the e1 seam merge,
  not new mpv-specific calls. Follow the GorAV C addendum 2 (A1-H) contract,
  including loud failure for unsupported commands. Do not add seam code before
  that merge or rewrite existing mpv code ahead of phase 2. Keep the domain
  consolidation rules in `STATE.md`.
