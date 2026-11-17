# W-gdb-198y-1nstinct-14
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/MusicController.swift -> GorSources. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-14.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-14",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/MusicController.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/MusicController.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: MusicItem, TrackItem, PlaylistEntry, Playlist, QueueItem, MusicController, start, stop, detachForQuit, search, play, playTrack",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-14.py",
    "callee": "archive/gor/Sources/gor/MusicController.swift owning station GorSources"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-14.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-14.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-14.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:15.522697+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/MusicController.swift",
        "block": "source1",
        "sha256": "e8e322d64449214ce03b030b156efe8b28305f8580c5038cd9bfbae43b1a1e1e"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-14.py",
        "block": "fixtures1",
        "sha256": "58ed18caac4d1903798095fcd37623d4f8240711ddc0d6ffa8c3821bcd459833"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "1745ed8a085a28f0086a534931ecedbf80ab2542eceebbf079fe18394db0e8b3",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-14: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "f6a2703c7d4f4f37a02fe15041dec7c41d1ee4859432bc5ff807b7eac95d196d"
  }
}
```

```swift id=source1
// ================================================================
//  MusicController.swift - mus2 process bridge for music mode
//  Owns: mus2 process lifecycle, newline-delimited JSON protocol,
//  current track/queue context
//  Answers: TRAP-11
//  Contract: every callback fires on the main thread
// ================================================================
import AppKit
import Foundation

// ================================================================
//  Data models
// ================================================================

struct MusicItem {
    let title: String
    let source: String   // "archive" | "bandcamp"
    let index: Int
    let cacheIdx: Int
    let cover: String?
}

struct TrackItem {
    let n: Int
    let title: String
    let duration: String
    let streamUrl: String?  // bandcamp only; nil for archive
}

struct PlaylistEntry {
    let cacheIdx: Int
    let title: String
    let source: String
    let cover: String?
}

struct Playlist {
    let id: String
    var name: String
    var items: [PlaylistEntry]
}

struct QueueItem {
    let title: String
    let url: String
    let coverUrl: String?
    let source: String
    let cacheIdx: Int
    let trackN: Int?
}

// ================================================================
//  MusicController - mus2.py communication
// ================================================================

final class MusicController {

    var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private let ipcPath: String

    private var currentTracks: [TrackItem] = []
    private var currentTrackN: Int = 0
    private var currentAlbumIdx: Int = 0
    private var currentSource: String = ""

    var currentDataMode: String = ""

    var isRunning: Bool {
        return process?.isRunning ?? false
    }

    // Callbacks - all fire on the main thread
    var onStatus:    ((String, String, String, Bool, String) -> Void)?
    var onResults:   (([MusicItem]) -> Void)?
    var onTracks: ((Int, String, String?, [TrackItem], String) -> Void)?   // albumIdx, title, cover, tracks
    var onInfo:      ((Int, String, String) -> Void)?                 // albumIdx, title, text
    var onMenu:      (([Playlist], Int, String) -> Void)?             // playlists, libCount, libTitle
    var onPlaylists: (([Playlist]) -> Void)?
    var onQueue:     (([QueueItem], Int) -> Void)?                    // items, currentIdx
    var onNowPlaying: ((String, String, Int) -> Void)?  // title, source, trackN

    var onLocalLibraries: (([[String: Any]]) -> Void)?
    var onLocalItems: ((String, String, [[String: Any]]) -> Void)?  // path, name, items

    private let stdoutLock = NSLock()
    private var stdoutBuffer = Data()
    private var chunkBuffer: [Int: String] = [:]
    private var chunkTotal: Int = 0
    /// Bumped on every start() and stop(). Responses decoded for an older generation are dropped,
    /// so a queued reply from a stopped/restarted mus2 never reaches the UI callbacks.
    private var generation = 0
    private var quitDetached = false // main-thread-only terminal callback latch

    init(ipcPath: String) {
        self.ipcPath = ipcPath
    }

    // MARK: - Lifecycle

    func start() {
        if process != nil { stop() }
        guard let mus2Path = GORResources.vendor()?.appendingPathComponent("mus2/mus2").path else { return }
        stdoutLock.lock(); generation += 1; let gen = generation; stdoutLock.unlock()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: mus2Path)
        task.arguments = [ipcPath]
        stdinPipe  = Pipe()
        stdoutPipe = Pipe()
        task.standardInput  = stdinPipe
        task.standardOutput = stdoutPipe

        stdoutPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.stdoutLock.lock(); let current = self.generation == gen; self.stdoutLock.unlock()
            guard current else { return }
            // TRAP-11: buffer raw Data to the newline, then decode complete
            // lines; a pipe read can split a UTF-8 character.
            self.stdoutLock.lock()
            self.stdoutBuffer.append(data)
            if self.stdoutBuffer.count > 4 * 1_048_576 {
                self.stdoutBuffer.removeAll()
                self.stdoutLock.unlock()
                NSLog("[mus2] Discarded oversized unterminated stdout line")
                return
            }
            var lines: [String] = []
            while let nl = self.stdoutBuffer.firstIndex(of: 0x0A) {
                let line = String(data: self.stdoutBuffer[self.stdoutBuffer.startIndex..<nl], encoding: .utf8)
                self.stdoutBuffer.removeSubrange(self.stdoutBuffer.startIndex...nl)
                if let line { lines.append(line) }
            }
            self.stdoutLock.unlock()
            for line in lines { self.handleJSON(line, gen: gen) }
        }
        do { try task.run() } catch {
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            stdinPipe = nil
            stdoutPipe = nil
            NSLog("[mus2] Failed to start: %@", String(describing: error))
            return
        }
        process = task
        QuitChildKiller.shared.register(task)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.localList()
            self?.requestMenu()
        }
    }

    func stop() {
        send("quit")
        stdoutLock.lock(); generation += 1; stdoutLock.unlock()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        if let p = process { QuitChildKiller.shared.unregisterIfStopped(p) }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stdoutLock.lock()
        stdoutBuffer.removeAll()
        stdoutLock.unlock()
        chunkBuffer.removeAll()
        chunkTotal = 0
    }

    /// Quit-only detach. Never writes the input pipe or takes stdoutLock on
    /// main. The caller owns bounded termination of the returned known child.
    func detachForQuit() -> Process? {
        precondition(Thread.isMainThread)
        guard !quitDetached else { return nil }
        quitDetached = true
        let child = process
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        if let child = child { QuitChildKiller.shared.unregisterIfStopped(child) } // live child stays registered; drain owns it
        stdinPipe = nil
        stdoutPipe = nil
        chunkBuffer.removeAll()
        chunkTotal = 0
        // An already-running reader may finish. Every UI callback is rejected
        // by the terminal latch; background buffer cleanup must not block main.
        DispatchQueue.global(qos: .utility).async { [self] in
            let deadline = ProcessInfo.processInfo.systemUptime + 0.1
            while !stdoutLock.try() {
                if ProcessInfo.processInfo.systemUptime >= deadline { return }
                Thread.sleep(forTimeInterval: 0.005)
            }
            generation += 1
            stdoutBuffer.removeAll()
            stdoutLock.unlock()
        }
        return child
    }

    // MARK: - Commands

    func search(_ query: String)           { send("search \(query)") }

    func play(cacheIdx: Int) {
        currentTracks = []  // clear the playlist; let mpv manage it
        currentTrackN = 0
        currentSource = "archive"  // play carries no source; bandcamp also lands here
        send("play \(cacheIdx)")
    }

    func playTrack(cacheIdx: Int, n: Int)  { send("play_track \(cacheIdx) \(n)") }
    func browse(cacheIdx: Int)             { send("browse \(cacheIdx)") }
    func info(cacheIdx: Int)               { send("info \(cacheIdx)") }
    func pause()                           { send("pause") }

    func setDataMode(_ mode: String) {
        send("set_mode \(mode)")
    }

    func playTrackWithContext(cacheIdx: Int, n: Int, tracks: [TrackItem], source: String) {
        guard let index = tracks.firstIndex(where: { $0.n == n }) else { return }
        currentTracks = tracks
        currentTrackN = index
        currentAlbumIdx = cacheIdx
        currentSource = source
        send("play_track \(cacheIdx) \(n)")
        onNowPlaying?(tracks[index].title, source, n)
    }

    func prev() {
        guard !currentTracks.isEmpty else { send("prev"); return }
        let prevN = currentTrackN - 1
        guard prevN >= 0 else { return }
        currentTrackN = prevN
        let track = currentTracks[prevN]
        if currentSource == "local", let url = track.streamUrl {
            send("play_local \(url)")
        } else {
            send("play_track \(currentAlbumIdx) \(track.n)")
        }
        onNowPlaying?(track.title, currentSource, currentTrackN)
    }

    func next() {
        guard !currentTracks.isEmpty else { send("next"); return }
        let nextN = currentTrackN + 1
        guard nextN < currentTracks.count else { return }
        currentTrackN = nextN
        let track = currentTracks[nextN]
        if currentSource == "local", let url = track.streamUrl {
            send("play_local \(url)")
        } else {
            send("play_track \(currentAlbumIdx) \(track.n)")
        }
        onNowPlaying?(track.title, currentSource, currentTrackN)
    }

    func volume(_ delta: Int)              { send("vol \(delta)") }
    func requestStatus()                   { send("status") }
    func requestMenu()                     { send("menu") }
    func refresh()                         { send("refresh") }

    // ── Playlist ─────────────────────────────────────────────────
    func newPlaylist(name: String)                     { send("pl_new \(name)") }
    func addToPlaylist(id: String, cacheIdx: Int)      { send("pl_add \(id) \(cacheIdx)") }
    func removeFromPlaylist(id: String, itemIdx: Int)  { send("pl_remove \(id) \(itemIdx)") }
    func playPlaylist(id: String)                      { send("pl_play \(id)") }
    func listPlaylists()                               { send("pl_list") }
    func deletePlaylist(id: String) { send("pl_delete \(id)") }

    // ── Queue ────────────────────────────────────────────────────
    func queueAlbum(cacheIdx: Int)              { send("q_add \(cacheIdx)") }
    func queueTrack(cacheIdx: Int, trackN: Int) { send("q_add_track \(cacheIdx) \(trackN)") }
    func clearQueue()                           { send("q_clear") }
    func queueList()                            { send("q_list") }
    func queueNext()                            { send("q_next") }

    func localList()                          { send("local_list") }
    func localAdd(path: String)               { send("local_add \(path)") }
    func localRemove(path: String)            { send("local_remove \(path)") }
    func localBrowse(path: String)            { send("local_browse \(path)") }

    func playLocal(path: String) {
        send("play_local \(path)")
    }

    func playLocalWithContext(path: String, tracks: [[String: Any]], trackN: Int) {
        guard tracks.indices.contains(trackN) else { return }
        currentTracks = tracks.enumerated().map { (i, t) in
            TrackItem(n: i, title: t["title"] as? String ?? "", duration: "", streamUrl: t["local_path"] as? String)
        }
        currentTrackN = trackN
        currentAlbumIdx = -1
        currentSource = "local"
        send("play_local \(path)")
        // The backend consumes stdin commands in order. Append once, from one
        // owner, after play_local rather than racing an arbitrary timer.
        for track in tracks.dropFirst(trackN + 1) {
            if let nextPath = track["local_path"] as? String { send("queue_local \(nextPath)") }
        }
        onNowPlaying?(tracks[trackN]["title"] as? String ?? "", "local", trackN)
    }

    func queueLocal(path: String) { send("q_add_local \(path)") }

    // MARK: - Private

    func send(_ command: String) {
        guard isRunning, let data = (command + "\n").data(using: .utf8) else { return }
        stdinPipe?.fileHandleForWriting.write(data)
    }

    func sendRaw(_ cmd: String) { send(cmd) }

    private func handleJSON(_ line: String, gen: Int) {
        guard let data = line.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd  = obj["cmd"] as? String else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.quitDetached, self.generation == gen else { return }
            switch cmd {

            case "results":
                guard let raw = obj["items"] as? [[String: Any]] else { return }
                let items = raw.enumerated().compactMap { (i, d) -> MusicItem? in
                    guard let title  = d["title"]  as? String,
                          let source = d["source"] as? String else { return nil }
                    return MusicItem(title: title, source: source, index: i,
                                     cacheIdx: d["cache_idx"] as? Int ?? i,
                                     cover: d["cover"] as? String)
                }
                self.onResults?(items)

            case "tracks":
                guard let albumIdx = obj["album_idx"] as? Int,
                      let title    = obj["title"]     as? String,
                      let raw      = obj["items"]     as? [[String: Any]] else { return }
                let cover = obj["cover"] as? String
                let source = obj["source"] as? String ?? "archive"
                let tracks = raw.map { d in
                    TrackItem(n:          d["n"]          as? Int    ?? 0,
                              title:      d["title"]      as? String ?? "",
                              duration:   d["duration"]   as? String ?? "",
                              streamUrl:  d["stream_url"] as? String)
                }
                self.onTracks?(albumIdx, title, cover, tracks, source)

            case "chunk":
                guard let total = obj["total"] as? Int,
                      let index = obj["index"] as? Int,
                      let data  = obj["data"]  as? String else { return }
                guard total > 0, total <= 4096, index >= 0, index < total,
                      data.utf8.count <= 1_048_576 else {
                    chunkBuffer.removeAll(); chunkTotal = 0; return
                }
                if chunkTotal != total { chunkBuffer.removeAll(); chunkTotal = total }
                chunkBuffer[index] = data
                if chunkBuffer.values.reduce(0, { $0 + $1.utf8.count }) > 4 * 1_048_576 {
                    chunkBuffer.removeAll(); chunkTotal = 0; return
                }
                if chunkBuffer.count == total {
                    let full = (0..<total).compactMap { self.chunkBuffer[$0] }.joined()
                    chunkBuffer.removeAll()
                    chunkTotal = 0
                    self.handleJSON(full, gen: gen)
                }

            case "info":
                guard let albumIdx = obj["album_idx"] as? Int,
                      let title    = obj["title"]     as? String,
                      let text     = obj["text"]      as? String else { return }
                self.onInfo?(albumIdx, title, text)

            case "menu":
                let rawPls = obj["playlists"] as? [[String: Any]] ?? []
                let pls = rawPls.compactMap { Self.parsePlaylist($0) }
                let count = obj["library_count"] as? Int ?? 0
                let libTitle = obj["library_title"] as? String ?? "library"
                if let mode = obj["data_mode"] as? String { self.currentDataMode = mode }
                self.onMenu?(pls, count, libTitle)

            case "playlists":
                let rawPls = obj["playlists"] as? [[String: Any]] ?? []
                let pls = rawPls.compactMap { Self.parsePlaylist($0) }
                self.onPlaylists?(pls)

            case "queue":
                let rawQ = obj["items"] as? [[String: Any]] ?? []
                let items = rawQ.map { d in
                    QueueItem(title:    d["title"]     as? String ?? "",
                              url:      d["url"]       as? String ?? "",
                              coverUrl: d["cover_url"] as? String,
                              source:   d["source"]    as? String ?? "",
                              cacheIdx: d["cache_idx"] as? Int ?? -1,
                              trackN:   d["track_n"]   as? Int)
                }
                let current = obj["current"] as? Int ?? -1
                self.onQueue?(items, current)

            case "np":
                let title  = obj["title"]  as? String ?? ""
                let source = obj["source"] as? String ?? ""
                let trackN = obj["track_n"] as? Int ?? 0
                if currentTracks.isEmpty {
                    currentTrackN = trackN
                    currentSource = source
                }
                // WHY: no onNowPlaying here - context is owned by next/prev/playTrackWithContext
                onStatus?(title, "0", "0", false, "80")

            case "status":
                let title  = obj["title"]  as? String ?? ""
                let pos    = obj["pos"]    as? String ?? "0"
                let dur    = obj["dur"]    as? String ?? "0"
                let paused = obj["paused"] as? Bool   ?? false
                let vol    = obj["vol"]    as? String ?? "80"
                self.onStatus?(title, pos, dur, paused, vol)

            case "local_libraries":
                let libs = obj["libraries"] as? [[String: Any]] ?? []
                self.onLocalLibraries?(libs)

            case "local_items":
                let path  = obj["path"]  as? String ?? ""
                let name  = obj["name"]  as? String ?? ""
                let items = obj["items"] as? [[String: Any]] ?? []
                self.onLocalItems?(path, name, items)

            case "log":
                let _ = obj["msg"]
                let _ = obj["level"]

            default: break
            }
        }
    }

    private static func parsePlaylist(_ d: [String: Any]) -> Playlist? {
        guard let id   = d["id"]   as? String,
              let name = d["name"] as? String else { return nil }
        let rawItems = d["items"] as? [[String: Any]] ?? []
        let items = rawItems.map { e in
            PlaylistEntry(cacheIdx: e["cache_idx"] as? Int    ?? -1,
                          title:    e["title"]     as? String ?? "",
                          source:   e["source"]    as? String ?? "",
                          cover:    e["cover"]     as? String)
        }
        return Playlist(id: id, name: name, items: items)
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/MusicController.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='e8e322d64449214ce03b030b156efe8b28305f8580c5038cd9bfbae43b1a1e1e', 'pinned source changed: rebase and review, never bless silently'
for token in ['MusicItem', 'TrackItem', 'PlaylistEntry', 'Playlist', 'QueueItem', 'MusicController', 'start', 'stop', 'detachForQuit', 'search', 'play', 'playTrack']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='e8e322d64449214ce03b030b156efe8b28305f8580c5038cd9bfbae43b1a1e1e'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-14: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-14: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
