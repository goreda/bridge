// App/ExportAsSeenAction.swift
// Photon menu entries and the plan-only Export As Seen panel; nothing here starts an encode.
// Uses: AppKit, Foundation, AppDelegate, PPController, ScriptMessageHub, PhotonLookCapture, ExportAsSeenPreflight, ExportPanelModel, ExportPanelGate, ExportSettings, ExportE0NativeProbe, ExportRenderObservationBridge
// Engine: none
import AppKit
import Foundation
import GorAVCore

/// Read-only adapter from the running player to the Picture preflight. Inputs that the app cannot supply yet
/// (measured stream sizes, the Photon look snapshot, calibration) answer "not available": the panel then shows a typed refusal.
struct ExportAsSeenAction: ExportSnapshotAdapter {
    let controller: PPController?
    /// The renderer-owner's source of a real same-job readback receipt (composition injection). nil = no render owner wired: no receipt, the preflight keeps refusing.
    /// Nothing in the app sets it yet; an unset source is never a pass.
    var renderReceiptSource: ((ExportLookCapture) -> ExportRenderObservation?)? = nil
    /// The composition root's source of the playing player's opened-file identity: the native host session's own
    /// open receipt (the descriptor the decoder reads through), converted field for field. Called on the main thread.
    /// nil = unwired: the playing identity stays unknown and the start fence refuses - never a fresh open of the path.
    var playingSourceIdentitySource: (() -> ExportFileIdentity?)? = nil
    static let gate = ExportPanelGate()
    static let settingsBacking = DefaultsBacking()

    /// Photon menu entries from the ExportMenu model through its pure surface sync: exactly one action (tag 7403) and one settings row (tag 7414) however often this runs,
    /// duplicates of those tags removed, every other item untouched and in order. Ownership is the verified tag, never a title.
    /// The action item opens only the plan-only panel (nothing starts an encode, Start stays disabled there); the model's encode-route reason is its tooltip.
    static func installMenu(in photonMenu: NSMenu, target: AppDelegate) {
        // Owner spec (2026-11-26 22:05-22:15, re-stated 2026-11-28 00:35): the "encode" top-level menu is ONE page, no submenu inside it:
        // export, separator, dimmed settings, x264 x265, separator, resolutions, separator, gor crf 12..22. Rows come from the ExportMenu model
        // (settingsRows minus its leading "encode" parent row); they are placed directly in this menu. Every row this binding adds carries a tag, so a
        // second run removes exactly its own rows (idempotent), including the nested "encode" item (tag 7414) an earlier build installed.
        let model = ExportMenu(profile: ExportSettings.profile(from: settingsBacking), sourceHDR: nil, encodeRoute: .unavailable(reason: "no accepted encode route"))
        let flatOption = 7416
        let owned: Set<Int> = [ExportMenuTags.action, ExportMenuTags.settingsSubmenu, ExportMenuTags.separatorCodec, ExportMenuTags.separatorResolution,
                               ExportMenuTags.separatorQuality, ExportMenuTags.settingsHeading, flatOption]
        for old in photonMenu.items where owned.contains(old.tag) { photonMenu.removeItem(old) }
        let keys = ["codec": ExportSettings.codecKey, "resolution": ExportSettings.resolutionKey, "quality": ExportSettings.qualityKey]
        for row in model.settingsRows.dropFirst() {
            let entry: NSMenuItem
            switch row.kind {
            case .separator:
                entry = NSMenuItem.separator()
            case .action:
                // Always clickable: it opens the panel, which states the typed reason Start cannot run (never a dead menu item).
                // The row model's disabledReason assumes an absent encode route; the route IS composed at the composition root
                // (installExportComposition) and the panel gates Start on the live capability state, so the tooltip says what the
                // click does - never "export is not available" while an export can in fact start from that click.
                entry = NSMenuItem(title: row.title, action: #selector(AppDelegate.menuExportAsSeen), keyEquivalent: "")
                entry.target = target; entry.toolTip = "Opens the export panel; Start is gated by the capability state shown there."
            case .heading:
                entry = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                entry.isEnabled = false
            case .option, .settingsSubmenu:
                guard let rep = row.representedValue, let dot = rep.firstIndex(of: "."), let key = keys[String(rep[..<dot])] else { continue }
                entry = NSMenuItem(title: row.title, action: #selector(SettingsMenuHandler.choose(_:)), keyEquivalent: "")
                entry.target = SettingsMenuHandler.shared; entry.representedObject = [key, String(rep[rep.index(after: dot)...])]
                entry.state = row.isChecked ? .on : .off; entry.isEnabled = row.isEnabled; entry.toolTip = row.disabledReason
            }
            entry.tag = row.tag == 0 ? flatOption : row.tag
            photonMenu.addItem(entry)
        }
    }

    /// Lane E skeleton: the composition root installs the real Start provider through here. The provider runs
    /// outside every controller lock (ExportStartCoordinator); until the cached capability snapshot is
    /// start-capable (all four legs present, Lane A amendment) AND the root supplies the real builder (the
    /// lanes' parts), it answers nil and Start keeps its typed .noProvider: fail-closed, never a static ready.
    static func installStartProvider(on controller: PPController, capability: ExportCapabilitySource,
                                     build: ((ExportPreflightResult) -> ExportStartInputs?)? = nil) {
        // The same source the provider gates on is shared with the controller: the panel's capability read
        // (PPController.exportCapabilitySnapshot) then sees the bound legs, never a parallel unbound answer.
        controller.exportCapabilitySource = capability
        controller.exportStartProvider = { result in
            guard capability.cachedSnapshot.startCapable, let build = build else { return nil }
            return build(result)
        }
    }

    /// encode > export: the preflight runs off the main thread with a timeout; a ready plan starts the export directly, otherwise the panel shows the plan or the typed refusal.
    static func present(controller: PPController?, framesBakedVerifier: ExportFramesBakedChainVerifier? = nil) {
        guard gate.begin() else { note("busy", "export click ignored: a previous export panel or preflight is still open", controller: controller); return }
        note("open", "export requested from the encode menu; preflight running", controller: controller)
        // Re-read the lanes' bound evidence off-main while the preflight runs; the panel reads the cached
        // snapshot when the preflight answers (E's refresh step, adapted: the root owns the source; refresh is
        // on the protocol - an UnboundExportCapability delivers its no-I/O snapshot inline).
        controller?.exportCapabilitySource?.refresh { _ in }
        let profile = ExportSettings.profile(from: settingsBacking)
        var adapter = ExportAsSeenAction(controller: controller)
        // The E0 render-receipt source (chain 8d060ab6 wiring): per capture, this adapter's own evidence plus the
        // ffprobe transfer tag from its own measured inventory (one video tag; none or split = nil, the contract
        // refuses typed), the providers built at the S2-allowed root (AppDelegate.goravE0Providers; the host reads
        // hop to main, the bridge itself runs on this preflight worker thread). Every typed refusal is nil.
        adapter.renderReceiptSource = { capture in
            let reader = ExportAsSeenAction(controller: controller)
            let entry = Date()
            guard var evidence = reader.colourEvidence(for: capture.mediaPath) else { return nil }
            let streams = try? reader.streamInventory(for: capture.mediaPath)
            let tags = Set((streams ?? []).filter { $0.kind == .video }.compactMap { $0.colorTransferTag })
            var signal = evidence.decodedSignal
            signal?.sourceTag = tags.count == 1 ? tags.first : nil
            evidence.decodedSignal = signal
            guard let providers = ExportE0NativeProbe.onMain({ (NSApp.delegate as? AppDelegate)?.goravE0Providers(capture: capture, evidence: evidence, controller: controller, entry: entry) }) else { return nil }
            if case .success(let observation) = ExportRenderObservationBridge.make(capture: capture, providers: providers) { return observation }
            return nil
        }
        // The start fence's playing-source identity: the native host's open receipt for the current session,
        // converted field for field; nil (no native engine, no session, unwired) keeps the fence refusing. Read on main.
        adapter.playingSourceIdentitySource = {
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.goravHostForAppGate?.activeSourceOpenReceipt() }.map { ExportFileIdentity(openReceipt: $0) }
        }
        // W-gdb-199eb-20: record the preflight's colour probe and measured inventory for the Start build's
        // contract (the build runs on main, where no probe/IO is allowed); forwarding is otherwise verbatim.
        let recordingAdapter = ExportStartRecordingAdapter(base: adapter)
        ExportAsSeenPreflight.runAsync(adapter: recordingAdapter, profile: profile, timeoutSeconds: 8, onColourEvidence: { framesBakedVerifier?.record($0) }) { result in
            // The preflight has recorded its colour evidence: refresh the capability (the frames-baked leg reads it) and decide in the refresh callback, so Start works on the first click.
            let decide: (ExportCapability) -> Void = { _ in
            defer { gate.end() }
            // The capability state comes from the player's typed seam read, taken after the refresh above (ruling 2026-11-26: never a "ready" impression).
            let capability = controller?.exportCapabilitySnapshot() ?? UnboundExportCapability(providerAssigned: false).cachedSnapshot
            // The capability state comes from the player's typed seam read (ruling 2026-11-26: the real state,
            // never a "ready" impression). No player = the unbound default with nothing assigned.
            let model = ExportPanelModel(result: result, capability: capability)
            // The export item is the Start: a ready plan (plan present and the capability start-capable) starts at once, with no second click. Anything else shows the panel with its
            // typed reasons and a disabled Start button (never a dead menu item).
            var choice = NSApplication.ModalResponse.alertSecondButtonReturn
            if !model.startEnabled {
                note("panel", model.lines.joined(separator: " | "), controller: controller)
                let alert = NSAlert()
                alert.messageText = model.title
                alert.informativeText = model.lines.joined(separator: "\n")
                alert.addButton(withTitle: "Close")
                let start = alert.addButton(withTitle: model.startTitle)
                start.isEnabled = false
                choice = alert.runModal()
            }
            // Start (the second button): the intent goes through the controller's typed seam only - the App never
            // sees the owner queue, wire lines, backend factory, source or runner. Both answers are typed: the
            // decision at call time, and the terminal outcome, which arrives on the controller's background queue
            // and is delivered back on main here.
            guard choice == .alertSecondButtonReturn else { note("dismissed", "export panel closed without Start", controller: controller); return }
            let decision = controller?.exportStartFromPanel(result: result, onTerminal: { terminal in
                DispatchQueue.main.async { ExportAsSeenAction.presentTerminal(terminal, controller: controller) }
            }) ?? .noProvider
            if decision == .started {
                note("started", "export run started", controller: controller, hud: "export started")
            } else {
                ExportAsSeenAction.presentStartDecision(decision, controller: controller)
            }
            }
            if let source = controller?.exportCapabilitySource { source.refresh(deliverOnMain: decide) } else { decide(UnboundExportCapability(providerAssigned: false).cachedSnapshot) }
        }
    }

    /// One structured row in this player's gor_diag.log (kind=export-lifecycle) and an optional HUD line for an
    /// export lifecycle point. The diag row rides the existing DiagSessionSink (admitted per-player sink, tagged,
    /// dropped - never fatal - when the sink is unavailable); the HUD line rides the existing spineUI channels:
    /// transient showPhotonHUD for started/terminal, the separate-lifetime engine-refusal line for refusals.
    private struct ExportLifecycleRow: Encodable { let kind: String; let stage: String; let detail: String }
    private static func note(_ stage: String, _ detail: String, controller: PPController?, hud: String? = nil, stickyHUD: Bool = false) {
        if let data = try? JSONEncoder().encode(ExportLifecycleRow(kind: "export-lifecycle", stage: stage, detail: detail)) {
            _ = DiagSessionSink.append(data + Data("\n".utf8))
        }
        guard let hud = hud else { return }
        DispatchQueue.main.async {
            if stickyHUD { controller?.spineUI.setEngineRefusalHUD(hud) } else { controller?.spineUI.showPhotonHUD(hud) }
        }
    }

    /// A Start decision that did not start a run, surfaced typed (never silent).
    private static func presentStartDecision(_ decision: ExportStartOperation.Decision, controller: PPController?) {
        let text: String
        switch decision {
        case .started: return
        case .alreadyRunning: text = "An export is already running."
        case .tearingDown: text = "The previous export is still being torn down; try again when it has finished."
        case .noPlan: text = "There is no plan to run."
        case .noProvider: text = "The export pipeline is not connected yet (no provider)."
        }
        note("refused", text, controller: controller, hud: "export refused: " + text, stickyHUD: true)
        let alert = NSAlert()
        alert.messageText = "Export not started"
        alert.informativeText = text
        alert.addButton(withTitle: "Close")
        _ = alert.runModal()
    }

    /// The run's typed terminal outcome; the controller's callback arrives on its background queue and the caller
    /// of exportStartFromPanel delivers it here on main.
    private static func presentTerminal(_ terminal: ExportStartOperation.Terminal, controller: PPController?) {
        var text: String
        switch terminal {
        case .refused(let r): text = "Export refused: \(String(describing: r))"
        case .cancelledBeforeRun: text = "Export was cancelled before it ran; nothing was published."
        case .finished(.published(let path, let bytes)): text = "Export published: \(path) (\(bytes) B)"
        case .finished(.stopped(let reason, let partial, let bytes)):
            text = "Export stopped (\(String(describing: reason))), \(bytes) B written; nothing published."
            if let partial = partial { text += " Partial file kept at: \(partial)" }
        case .finished(.failed(let failure, let partial, let bytes)):
            text = "Export failed: \(String(describing: failure)) (\(bytes) B written)."
            if let partial = partial { text += " Partial file kept at: \(partial)" }
        }
        note("terminal", text, controller: controller, hud: text)
        if case .finished(.published) = terminal { controller?.spineUI.setEngineRefusalHUD(nil) }
        let alert = NSAlert()
        alert.messageText = "Export"
        alert.informativeText = text
        alert.addButton(withTitle: "Close")
        _ = alert.runModal()
    }

    func mediaFacts() -> ExportMediaFacts? {
        onMain {
            guard let c = controller, let p = c.currentPath else { return nil }
            return ExportMediaFacts(path: p, durationSeconds: c.duration, displayWidth: c.videoDisplayW, displayHeight: c.videoDisplayH)
        }
    }

    func isLocalFile(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let url = URL(fileURLWithPath: path)
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    func fileIdentity(_ path: String) -> ExportFileIdentity? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { return nil }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let (secNs, o1) = Int64(st.st_mtimespec.tv_sec).multipliedReportingOverflow(by: 1_000_000_000)
        let (mtimeNs, o2) = secNs.addingReportingOverflow(Int64(st.st_mtimespec.tv_nsec))
        guard !o1, !o2, mtimeNs > 0 else { return nil }
        return ExportFileIdentity(device: UInt64(st.st_dev), inode: UInt64(st.st_ino), bytes: Int64(st.st_size), mtimeNs: mtimeNs, resolvedPath: resolved)
    }

    /// The playing player's opened-file identity, read from the composition-injected source: the native host's own
    /// open receipt for the current session, converted field for field. A fresh open of the path is never a substitute:
    /// a replaced or re-linked file must fail the start fence. nil = no source wired or no receipt: the fence keeps refusing.
    func playingSourceIdentity() -> ExportFileIdentity? {
        guard let source = playingSourceIdentitySource else { return nil }
        return onMain { source() }
    }

    /// Measured stream sizes through the Picture owner's typed measureForExport (mimar ruling, 2026-11-26): App
    /// passes its OWN independent stat observation as the expected identity (never the inventory's self-report),
    /// primaryVideoIndex stays nil (primary unknown: no typed selected-video source exists for the planned file
    /// today - never the 0 constant), and the seconds budget (6) is the measurement/probe budget only, owned here.
    /// Typed refusals (.sourceChanged/.probeUnavailable/.deadlineExceeded/.cancelled) are RETHROWN, never
    /// flattened to nil: the preflight maps each to its own refusal. nil answers only "App has no independent
    /// observation" (typed unknown). This measurement does not fill playingSourceIdentity. A result landing after
    /// the preflight's 8 s timeout is dropped as late by runAsync (never mistaken for done or cancelled).
    func streamInventory(for path: String) throws -> [ExportSourceStream]? {
        guard let observed = fileIdentity(path), observed.bytes >= 0 else { return nil }
        let expected = SourceIdentity(device: observed.device, inode: observed.inode, size: UInt64(observed.bytes), mtimeNanos: observed.mtimeNs)
        return try StreamInventoryProbe.measureForExport(path: path, expected: expected, primaryVideoIndex: nil, seconds: 6, cancel: InventoryCancel())
    }

    /// Captures the look from the running scripts: one token request over IPC, reply via client-message, 8 s cap. The request carries the host's
    /// accepted source identity (PPController.sourceSnapshot: session, opening, path); the reply must echo it, and the same snapshot must still
    /// hold after the reply. A pending or uncertain source is refused. A false send means the request was never written (released
    /// transport); a written line still cannot report socket failure (requested, awaiting reply).
    func lookSnapshot(for path: String, deadlineSeconds: Double, expectedEncodeRaster: PhotonEncodeRaster?) throws -> ExportLookCapture {
        guard let c = controller else { throw ExportRefusal.incompleteLook("no player to capture the look from") }
        let lookDispatch = PhotonLookCaptureDispatch(transport: c)
        let capture = PhotonLookCapture(send: { line in onMain { MainActor.assumeIsolated { lookDispatch.send(line) } } },
                                        source: { let s = c.sourceSnapshot(); return HostSourceSnapshot(pending: s.pending, session: s.session, opening: s.opening, path: s.path) })
        // Consumer latch (v12m): the accepted identity + producer receipt pair, bound through the host request
        // epoch (the receipt is the tagged accept-time query reply, never the observed property; the binding says
        // nothing about the producer load having settled at query time - floor hint only). The capture's caller fence re-checks
        // that the identity is still current at latch; a receipt observed under an older identity (late
        // observer) is a typed refusal, not a silent downgrade. No v12m peer or no epoch reply yet:
        // no latch — the capture runs explicit-unknown and admission must not upgrade (producerRunVerified=false).
        var acceptedIdentity: ExportAcceptedIdentity?
        if let pair = c.acceptedLoadAndReceipt(), let r = pair.receipt,
           let s = pair.identity.session, let o = pair.identity.opening, let p = pair.identity.path {
            let receipt = PhotonLoadReceipt(runId: r.runId, loadGen: r.loadGenKnown.map(PhotonLoadReceipt.LoadGen.known) ?? .unknown, loadPath: r.loadPath)
            try capture.latchProducerReceipt(receipt, forAcceptedIdentity: HostSourceSnapshot(pending: false, session: s, opening: o, path: p))
            acceptedIdentity = ExportAcceptedIdentity(session: s, opening: o, path: p)
        }
        let ownerAtRequest = c.exportOwnerSnapshot()   // label captured when the request is made, never re-read later
        ScriptMessageHub.setListener { capture.deliver(args: $0) }
        defer { ScriptMessageHub.setListener(nil) }
        // The declaration path comes from the same resolver the encoder leg reads (release set, then sibling Resources), never the mpv config dir.
        let declarationPath = GORResources.renderStackDeclarationSearchPath()
        // A control or render property that moves while the look is read refuses that capture ("... changed during capture"); the player settles
        // within a moment, so retry that one refusal up to 3 times inside the caller's deadline. Every other refusal stays immediate.
        let startedAt = Date()
        var attempt = 0
        var result: PhotonLookCaptureResult
        while true {
            attempt += 1
            let remaining = deadlineSeconds - Date().timeIntervalSince(startedAt)
            do {
                result = try capture.capture(deadlineSeconds: remaining, expectedPath: path, expectedRaster: expectedEncodeRaster, providerDeclarationPath: declarationPath)
                break
            } catch ExportRefusal.incompleteLook(let reason) where reason.contains("changed during capture") && attempt < 3 && Date().timeIntervalSince(startedAt) < deadlineSeconds - 1.5 {
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        let env = result.envelope
        // Capture-time dev/inode is not recorded yet (PLAYBACK owes an opened-file identity at capture): explicit nil,
        // and the capture fence refuses the run until it is recorded - never a stat-after-the-fact guess.
        let lookCapture = ExportLookCapture(mediaPath: path, look: env.look, raster: env.raster, loadReceipt: env.loadReceipt,
                                            producerRunVerified: env.producerRunVerified, acceptedIdentity: acceptedIdentity, sourceIdentity: nil,
                                            exportEpoch: env.epoch.map(Int64.init))
        // Pin source for the run lease: only a verified capture (run receipt + accepted identity) whose owner state did not move between request and reply
        // (same session, opening, path and connection epoch) and whose run id is the owner's receipt run id. Anything else publishes no pin: fail closed.
        if let ctx = ExportProducerRunContext(capture: lookCapture), let a = ownerAtRequest, let b = c.exportOwnerSnapshot(),
           a.session == b.session, a.opening == b.opening, a.path == b.path, a.connectionEpoch == b.connectionEpoch, b.receiptRunId == ctx.runId,
           ctx.identity == ExportAcceptedIdentity(session: b.session, opening: b.opening, path: b.path) {
            c.exportNotePin(ctx.lookPinSha256, runId: ctx.runId, capturedAt: a)   // the label captured at request time, unchanged (b only proved the owner did not move)
        }
        return lookCapture
    }

    /// The load serial of the run lease's observation snapshot (written on the connection queue, read as one whole value under the lease lock): no read of
    /// fileLoadedGeneration on main. nil when no load is observed. It is an observation, not a commit-owning lease.
    func playerGeneration() -> Int? { controller?.exportLease.current()?.generation }

    private func onMain<T>(_ f: () -> T) -> T { Thread.isMainThread ? f() : DispatchQueue.main.sync(execute: f) }

    /// No render/probe evidence source exists in the app yet: the renderer-to-look binding that would prove frames-baked-as-seen,
    /// the render path class and the decoded signal read is not connected. nil is the typed "not available" answer: the preflight
    /// lists it missing and plans nothing. There is no default evidence and no route toggle.
    /// Decoded source colour probe from the running player. The Engine station (PlayerColourProbeOperations) owns the query,
    /// the parsing and the owner-snapshot fence; the result is typed evidence bound to one accepted load, or nil (typed unknown).
    /// It is a host identity fence, never producer-settlement or opened-file proof; the existing gates keep refusing Start.
    /// Render-side evidence has no real producer in the app: render path, frames-baked, look-pixel and gamut
    /// statements stay nil and validation stays false - never derived from a route name, an IPC ACK or a
    /// static boolean. The preflight keeps listing them missing, plans nothing colour-bound, Start stays disabled.
    func colourEvidence(for path: String) -> ExportColourEvidence? {
        guard let c = controller else { return nil }
        // The Engine station owns property names, payload, request ids, the batch round trip, reply parsing and the owner-snapshot
        // fence (PlayerColourProbeOperations); this caller receives the typed evidence only and holds no property key or payload.
        return c.exportColourProbe.probe(requestedPath: path)
    }

    func renderObservation(for capture: ExportLookCapture) -> ExportRenderObservation? { renderReceiptSource?(capture) }

    func calibratedCRF() -> Int? { nil }

    func freeBytes(near path: String) -> Int64? {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        guard let v = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let free = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return free
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
}

/// UserDefaults behind the settings protocol.
final class DefaultsBacking: ExportSettingsBacking {
    func string(forKey key: String) -> String? { UserDefaults.standard.string(forKey: key) }
    func set(_ value: String?, forKey key: String) { UserDefaults.standard.set(value, forKey: key) }
}

/// Target of the export settings menu items: saves the choice and moves the checkmark within its group.
final class SettingsMenuHandler: NSObject {
    static let shared = SettingsMenuHandler()
    @objc func choose(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        ExportAsSeenAction.settingsBacking.set(pair[1], forKey: pair[0])
        // The encode page is flat: move the checkmark only within this option's own group (same settings key).
        sender.menu?.items.forEach { if let rep = $0.representedObject as? [String], rep.first == pair[0] { $0.state = $0 === sender ? .on : .off } }
    }
}

extension AppDelegate {
    /// encode > export: preflight, then a ready plan starts directly; otherwise the panel shows the typed refusal.
    @objc func menuExportAsSeen(_ sender: NSMenuItem) { ExportAsSeenAction.present(controller: controller, framesBakedVerifier: (NSApp.delegate as? AppDelegate)?.exportFramesBakedVerifier) }
}
