# Open intent classification, source-only

Base: gorav 13b160e001011c3bfb3cb4288d15d5a4e1234eb8.

The classifier keeps absolute paths and local file URLs separate from remote
OpenURLRouter inputs. It does not admit a source or perform any effect. Local
media is a candidate for the embedded session's open(path:) entry; remote
routing remains the existing open(url:) contract. Font/subtitle/image/torrent
classification does not assert a working gorav loader for those kinds.

Extension groups are referenced from the recovered historical gor handler in
instinct 94ee671d6f1f5f95eeef8a37d74d0f110c8dbf82,
archive/gor/Sources/gor/gor/DragDropHandler.swift, SHA256
44f6b8ee47cc2a5bbf404cadafdb654c9dc002c1ed03bc2d2ce4942fde37b332.
That is not current-gor parity evidence. No current handler equivalence claimed.

Not implemented: pasteboard/event monitoring, batch ordering, first-media
replace/append, duplicate-drop suppression, torrent stopping, host side effects,
AppDelegate/AppleEvent integration, recent-items storage, runtime admission.

File URLs decode the path once and accept only an absent/empty/localhost host,
without credentials or a port. Queries and fragments do not become path bytes.
Absolute paths are literal, including percent signs, question marks and hashes.
Other strings retain the router's typed result. No existence, permission, file
kind or symlink check is performed. The caller must validate those before use.

Run `Tests/OpenIntentClassification/run-portable.sh` with SWIFTC/CC if needed.
It builds the actual GorAVCore router module plus the new classifier and an
independent literal expected table. `python3 Tests/OpenIntentClassification/run-mutants.py`
requires each mutant to compile and fail a runtime classification assertion.

The classification commit did not edit Package.swift or the embedded session.
Correction: GorAVPlaybackCore uses directory discovery, not an explicit source
list, so the classifier is already included in that target. The follow-up
adoption registers a dispatcher executable test target and changes the existing
GorAVEmbeddedSession.open(url:) entry to use OpenIntentDispatch. It calls the
normal open(path:) for local media/images, refuses font/subtitle execution, and
keeps remote/torrent routes on the existing host path. No replacement/append or
stop policy is invented. Portable host tests prove dispatch and error forwarding,
not a full PlaybackCore build or macOS session runtime. Native execution is UNRUN.
