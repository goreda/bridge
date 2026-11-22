# File navigation/autoload current-tree harness

Run `bash gor/Tests/Harness/FileNavigationAutoload/run.sh`. Requires Python 3 and Lupa; install requirements.txt into your own isolated Python environment first. The runner does not install packages or contact sites. It reads current FileBrowser.swift, ArchiveBrowser.swift, AppDelegate.swift, vendored autoload.lua and autoload.conf directly.

Navigation: epoch state model plus five async entry-point source guards and torrent visibility anchors. Resource: eight source anchors for accepted dev root, temporary copy/link staging and preserved generated directories. Autoload: actual vendored Lua runs under Lupa with mocked mpv API/filesystem; current autoload.conf options are loaded. Eight Lua controls cover natural ordering/filtering, abort/manual playlist, missing/non-local paths, duplicate start, hidden current file and recursive hidden directory. Three independent live-source mutations are rejected.

Not a Swift/AppKit navigation, macOS FileManager, installed mpv, subtitle-sidecar or UI test. Resource source anchors do not prove atomic staging or permissions. Lua mock tests do not prove real mpv command effects. Current-source changes require semantic model review. Native validation stays open. No production changes.
