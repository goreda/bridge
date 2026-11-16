#!/usr/bin/env python3
# Isolated source proposal. Refuse drift, never overwrite another lane's tree.
from pathlib import Path
import sys,hashlib
root=Path(sys.argv[1]);target=root/'Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift'
s=target.read_text()

def replace(old,new):
    global s
    assert s.count(old)==1,('anchor drift',old[:80])
    s=s.replace(old,new)
replace('    private let runID: String','''    private let runID: String
    /// Host explicitly registers the preparation implementation. No implicit
    /// browser/player fallback. Linux process backend is not Darwin support.
    public typealias SourcePreparer = @Sendable (String, String?, SourcePreparationCancellation) async throws -> PreparedLocalMedia
    private let sourcePreparer: SourcePreparer?
    private var sourcePreparationCancellation: SourcePreparationCancellation?
    private var preparingSource = false
    private var preparedMedia: PreparedLocalMedia?''')
replace('    public init(hostView: NSView, runID: String) {\n        self.hostView = hostView\n        self.runID = runID\n    }','''    public init(hostView: NSView, runID: String, sourcePreparer: SourcePreparer? = nil) {
        self.hostView = hostView
        self.runID = runID
        self.sourcePreparer = sourcePreparer
    }''')
replace('    public func open(path: String) async throws {','''    public func open(path: String) async throws {
        guard !preparingSource else { throw EmbeddedRefusal.alreadyOpen }''')
replace('    public func open(url: String) async throws {\n        switch OpenURLRouter.route(url) {','''    public func open(url: String, selectedFilename: String? = nil) async throws {
        guard !preparingSource else { throw EmbeddedRefusal.alreadyOpen }
        switch OpenURLRouter.route(url) {''')
replace('''        case .needsMegaResolver:
            throw EmbeddedRefusal.unsupportedSource("mega link: the external mega resolve/decrypt step must produce an admitted http(s) URL first (R3)")''','''        case .needsTransferResolver, .needsMegaResolver:
            try await openPreparedSource(url: url, selectedFilename: selectedFilename)''')
anchor='    /// Remote twin of open(path:): same proven sequence, remote differences'
replace(anchor,'''    /// Preparation is fenced before any local decoder opens. The cache lease
    /// survives until cleanupLegs has closed every decoder and audio handle.
    private func openPreparedSource(url: String, selectedFilename: String?) async throws {
        guard !tornDown, !fenced else { throw EmbeddedRefusal.illegalState("tornDownOrFenced") }
        guard plane.state == .idle, session == nil, !preparingSource else { throw EmbeddedRefusal.alreadyOpen }
        guard let sourcePreparer else { throw EmbeddedRefusal.unsupportedSource("sourcePreparerNotRegistered") }
        let cancellation = SourcePreparationCancellation()
        sourcePreparationCancellation = cancellation
        preparingSource = true
        defer { preparingSource = false; sourcePreparationCancellation = nil }
        let media: PreparedLocalMedia
        do {
            media = try await withTaskCancellationHandler(operation: {
                try await sourcePreparer(url, selectedFilename, cancellation)
            }, onCancel: { cancellation.cancel() })
        } catch {
            // Never forward an external exception or URL/key to the UI.
            throw EmbeddedRefusal.unsupportedSource("sourcePreparationRefused")
        }
        guard !tornDown, !fenced, !Task.isCancelled, plane.state == .idle, session == nil else {
            do { try media.release() } catch { onEvent?(.failed("sourceCacheCleanupFailed")) }
            throw EmbeddedRefusal.illegalState("preparedSourceStale")
        }
        preparedMedia = media
        preparingSource = false
        do { try await open(path: media.path) }
        catch {
            // open(path:) owns partial decoder cleanup before throwing.
            do { try media.release(); preparedMedia = nil } catch { onEvent?(.failed("sourceCacheCleanupFailed")) }
            throw error
        }
    }

'''+anchor)
replace('''    private func tearDownInternal(reason: String) async {
        guard !tornDown else { return }
        tornDown = true
        closeSubtitleDelivery()''','''    private func tearDownInternal(reason: String) async {
        guard !tornDown else { return }
        tornDown = true
        sourcePreparationCancellation?.cancel()
        closeSubtitleDelivery()''')
replace('''        audioTask = nil; pumpTask = nil; audioBinding = nil; audioCorrelation = nil
    }''','''        audioTask = nil; pumpTask = nil; audioBinding = nil; audioCorrelation = nil
        if let media = preparedMedia {
            do { try media.release(); preparedMedia = nil }
            catch { onEvent?(.failed("sourceCacheCleanupFailed")) }
        }
    }''')
target.write_text(s)
print('SHELL_SOURCE_CANDIDATE_SHA256',hashlib.sha256(s.encode()).hexdigest())
