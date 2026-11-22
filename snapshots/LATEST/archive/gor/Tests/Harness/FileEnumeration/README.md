# File browser enumeration/admission harness

Run `bash gor/Tests/Harness/FileEnumeration/run.sh`. Python 3 only, current FileBrowser.swift required. Extension sets read directly from both folder/search sources and compared. Six controls preserve extension case handling, hidden/nonplayable filtering, directory-first sort, query and 500 admitted result cap. Three source mutations fail.

Characterizations: ignored fileExists return can admit a name removed after listing; cap-before-sort means returned subset depends on native enumeration order; failed contentsOfDirectory can produce empty rows without error handling here. These are source/state models, not actual filesystem incidents or permission/UI proof. Globally sorted complete search is not promised by the bounded current design; do not silently change its policy.

No snapshot fallback, real filesystem scan, Swift/AppKit execution, title truncation/image/preview pixels or production edit. Complements existing navigation epoch harness without duplicating its coverage. Native FileManager symlinks/races/permissions/Unicode/timing and visible errors remain open. PASS is admission-port evidence, not complete file browser correctness.
