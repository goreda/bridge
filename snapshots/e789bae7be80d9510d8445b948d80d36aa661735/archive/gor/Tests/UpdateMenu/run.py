"""Update button gate (owner, 2026-11-08: "rename check chromium update to update; when automatic repo updates arrive,
check chromium updates at the same time. Include yt-dlp updates too.
That button is now responsible for updates").

The chromium-only item becomes the general update button: one press checks
chromium and yt-dlp today, reports the pinned vendor components (they ride
the app update by design), and runs the app/repo check the moment the
auto-update engine is activated. The engine stays OFF: the new file reads
its config, never writes it.

Proofs:
1. Menu wiring: app > update with the same ⌃⌥⌘4 chord, the old item gone.
2. Coverage: menuUpdate runs the chromium leg (the existing handler, its own
   log tag), a yt-dlp leg on the same staged binary and "-U" flag the
   recovery path uses, and the app/repo leg; pinned components are logged.
3. Engine safety: the config is read-only (no write/replace anywhere in the
   owning file), the engine script and fetch-release sit strictly behind the
   enabled guard, and the off path logs instead of acting.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
app = (ROOT / 'Sources/gor/App/AppDelegate.swift').read_text()
owning = (lambda s:s.split('// BEGIN station-move UpdateChecks.swift\n',1)[1].split('// END station-move UpdateChecks.swift\n',1)[0])((ROOT / 'Sources/gor/UI/MenuActions.swift').read_text())

# ── 1. menu wiring ─────────────────────────────────────────────────────────
assert 'item("update", action: #selector(menuUpdate), key: "4", mods: [.command, .control, .option])' in app
assert '"check chromium update"' not in app, 'old chromium-only item must be gone'

# ── 2. coverage ────────────────────────────────────────────────────────────
menu = owning[owning.index('@objc func menuUpdate()'):]
menu = menu[:menu.index('private func checkYtDlpOnDemand')]
assert 'menuCheckChromiumUpdate()' in menu, 'chromium leg'
assert 'checkYtDlpOnDemand()' in menu, 'yt-dlp leg'
assert 'UpdateChecks.repoManaged' in menu, 'pinned components are reported, not forgotten'
assert 'checkAppUpdateOnDemand()' in menu, 'app/repo leg'
# Chromium leg reuses the existing handler (single source for its guards).
assert '@objc func menuCheckChromiumUpdate()' in app
assert 'AppDelegate.checkChromiumOnUse(binary: binary, force: true)' in app
# yt-dlp leg: same staged binary and update flag as the recovery path.
ytdlp = owning[owning.index('private func checkYtDlpOnDemand'):]
ytdlp = ytdlp[:ytdlp.index('private func checkAppUpdateOnDemand')]
assert 'AppDelegate.stagedYtDlpPath()' in ytdlp
assert 'task.arguments = ["-U"]' in ytdlp
assert 'ytdlpUpdateInProgress = true' in ytdlp and 'ytdlpUpdateInProgress = false' in ytdlp

# ── 3. engine stays OFF: read-only config, guarded execution ───────────────
for forbidden in ['.write(', 'write(to:', 'atomic', 'setObject', '"enabled": true', '"enabled":true']:
    assert forbidden not in owning, 'UpdateChecks must never write the engine config: ' + forbidden
assert 'let enabled = object["enabled"] as? Bool else { return false }' in owning
appleg = owning[owning.index('private func checkAppUpdateOnDemand'):]
order = [appleg.index('guard UpdateChecks.appUpdateEnabled(project: project)'),
         appleg.index('guard let script = UpdateChecks.engineScript'),
         appleg.index('"fetch-release"')]
assert order == sorted(order), 'engine script and fetch-release must sit behind the enabled guard'
assert 'auto-update engine off' in appleg, 'off path logs instead of acting'
# The sidecar is the milat repo-sync checkout, never created or mutated here.
assert 'Downloads/gor-repo-sync' in appleg
assert 'fileExists(atPath: sidecar)' in appleg

print('PASS update button: one item owns chromium + yt-dlp + pinned-component reporting,')
print('  app/repo check wired behind the engine config (read-only, OFF until the owner activates)')
